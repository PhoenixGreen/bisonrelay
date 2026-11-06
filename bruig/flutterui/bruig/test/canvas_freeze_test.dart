import 'dart:io';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/media/mix/decode.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'canvas_audio_fake.dart';

// canvas_freeze_test.dart freezes a real sound through a chain: rendered
// with the miniaudio inside a built copy of the SoLoud plugin, as
// canvas_mix_decode_test.dart decodes. Skipped where there is no built app
// or no ffmpeg to make the file.

const _built = "build/macos/Build/Products/Debug/Bison Relay.app/Contents/"
    "Frameworks/flutter-soloud.framework/Versions/A/flutter-soloud";

double _peak(String file) {
  var (l, r) = readWhole(file)!;
  var most = 0.0;
  for (var i = 0; i < l.length; i++) {
    most = math.max(most, math.max(l[i].abs(), r[i].abs()));
  }
  return most;
}

void main() {
  late Directory root;
  var ready = false;
  String? tone;

  setUpAll(() async {
    if (!File(_built).existsSync()) return;
    var which = await Process.run("which", ["ffmpeg"]);
    if (which.exitCode != 0) return;
    miniaudioLibrary = File(_built).absolute.path;
    root = await Directory.systemTemp.createTemp("canvas-freeze");
    CanvasStorage.rootOverride = root.path;
    var wav = path.join(root.path, "tone.wav");
    await Process.run("ffmpeg", [
      "-y", "-f", "lavfi", //
      "-i", "sine=frequency=440:sample_rate=48000:duration=1",
      "-ac", "2", wav,
    ]);
    tone = await CanvasMedia.saveFile(MediaKind.audio, wav);
    ready = canDecode && tone != null;
  });

  tearDownAll(() async {
    CanvasStorage.rootOverride = null;
    if (ready) await root.delete(recursive: true);
  });

  test("frozen, a sound plays a copy rendered through the chain's start",
      () async {
    if (!ready) {
      markTestSkipped("no built app or no ffmpeg");
      return;
    }
    var c = CanvasController(
        CanvasDocument(frames: 100, elements: [
          AudioElement(const ElementBase(id: "m", name: "Music"),
              clip: MediaClip(
                  playlist: [MediaSource(assetId: tone!, length: 1)],
                  timed: true,
                  mix: const ChannelMix(devices: [
                    // Halved, then doubled: frozen up to the first, it is
                    // the half that is heard in the copy.
                    MixDevice(DeviceKind.utility,
                        id: "d0", values: {"gain": -6.0206}),
                    MixDevice(DeviceKind.utility,
                        id: "d1", values: {"gain": 6.0206}),
                  ]))),
        ]),
        audioEngine: FakeEngine({tone!: 1}));
    addTearDown(c.dispose);
    var before =
        _peak((await CanvasMedia.existingPath(MediaKind.audio, tone!))!);
    expect(await c.freezeChain("m", "d0"), isNull);
    var clip = (c.document.elements.single as AudioElement).clip;
    var copy = clip.playlist.single.assetId;
    expect(copy, isNot(tone));
    var after = _peak((await CanvasMedia.existingPath(MediaKind.audio, copy))!);
    expect(after / before, closeTo(0.5, 0.02));
    expect(clip.mix.devices.first.on, isFalse, reason: "not run twice");
    expect(clip.mix.devices[1].on, isTrue, reason: "after it, still live");
    expect(c.frozenSteps("m"), {"d0"});
    c.unfreezeChain("m");
    clip = (c.document.elements.single as AudioElement).clip;
    expect(clip.playlist.single.assetId, tone);
    expect(clip.mix.devices.first.on, isTrue);
  });
}
