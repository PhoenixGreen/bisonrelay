import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/dart_audio_engine.dart';
import 'package:bruig/plugin_system/canvas/media/mix/decode.dart';
import 'package:bruig/plugin_system/canvas/media/synth/part_render.dart'
    show wav16;
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

const _built = "build/macos/Build/Products/Debug/Bison Relay.app/Contents/"
    "Frameworks/flutter-soloud.framework/Versions/A/flutter-soloud";

class Offline extends DartAudioEngine {
  @override
  Future<bool> start() async => true;
}

// canvas_clip_sound_test.dart is an audio clip's sound changed for real --
// read by the app's own decoder, reversed, warped, played by the mix
// engine -- and heard: what Ken found flaky, reversed before warping. Skipped
// where there is no built app (for its decoder) or no ffmpeg.

void main() {
  test("reversed, then warped, it is heard each time", () async {
    if (!File(_built).existsSync() ||
        (await Process.run("which", ["ffmpeg"])).exitCode != 0) {
      markTestSkipped("no built app or no ffmpeg");
      return;
    }
    miniaudioLibrary = File(_built).absolute.path;
    var root = await Directory.systemTemp.createTemp("rev");
    CanvasStorage.rootOverride = root.path;
    var n = 48000 * 4;
    var l = Float32List(n);
    // A rising tone: loud at the end, quiet at the start -- reversed, the
    // other way round.
    for (var i = 0; i < n; i++) {
      l[i] = (i / n) * 0.8 * math.sin(i * 0.05);
    }
    var f = File(path.join(root.path, "in.wav"));
    await f.writeAsBytes(wav16(l, l));
    var m = File(path.join(root.path, "in.mp3"));
    await Process.run("ffmpeg", ["-y", "-i", f.path, m.path]);
    var id = (await CanvasMedia.saveFile(MediaKind.audio, m.path))!;
    var engine = Offline();
    var micros = 0;
    var c = CanvasController(
        CanvasDocument(
            frames: 4000,
            frameRate: 25,
            audio: const AudioSettings(tempo: 120),
            elements: [
              AudioElement(const ElementBase(id: "a", name: "a"),
                  clip: MediaClip(
                      playlist: [MediaSource(assetId: id, length: 4)],
                      timed: true)),
            ]),
        audioEngine: engine);
    c.clockForTest = () => micros;
    c.setSessionClip(
        "a",
        0,
        SessionClip(
            id: "s",
            sound: MediaSource(assetId: id, name: "x", length: 4),
            bars: 2));
    var bl = Float32List(4800), br = Float32List(4800);
    // A tenth of a second: what it sounds like, as its loudest.
    Future<double> hear() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      engine.core.render(bl, br, 4800);
      micros += 100000;
      c.tickClockForTest();
      return bl.map((v) => v.abs()).reduce(math.max);
    }

    c.pressClip("a", 0);
    var heard = <double>[];
    for (var i = 0; i < 5; i++) {
      heard.add(await hear());
    }
    expect(heard.first, lessThan(0.1), reason: "forwards: quiet first");
    // Reversed while it plays: heard reversed at once -- loud first.
    c.openClipEditor("a", 0);
    expect(await c.reverseClip(), isNull);
    heard.clear();
    for (var i = 0; i < 5; i++) {
      heard.add(await hear());
    }
    expect(heard.first, greaterThan(0.5), reason: "reversed: loud first");
    // Then warped: its tempo heard, rendered, and still heard.
    expect(await c.setWarp(true), isNull);
    heard.clear();
    for (var i = 0; i < 30; i++) {
      heard.add(await hear());
    }
    expect(c.session.at("a", 0)!.warped, isNotNull);
    expect(heard.where((v) => v > 0.1), isNotEmpty, reason: "warped, heard");
    c.pause();
    c.dispose();
    await root.delete(recursive: true);
    CanvasStorage.rootOverride = null;
  }, timeout: const Timeout(Duration(minutes: 2)));
}
