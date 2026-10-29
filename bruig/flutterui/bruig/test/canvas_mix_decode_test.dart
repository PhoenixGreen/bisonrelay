import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/dart_audio_engine.dart';
import 'package:bruig/plugin_system/canvas/media/mix/decode.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

// canvas_mix_decode_test.dart decodes real files with the miniaudio inside a
// built copy of the SoLoud plugin -- the check that the structures handed to
// it are laid out as it expects. Skipped where there is no built app or no
// ffmpeg to make the files.

const _built = "build/macos/Build/Products/Debug/Bison Relay.app/Contents/"
    "Frameworks/flutter-soloud.framework/Versions/A/flutter-soloud";

void main() {
  late Directory dir;
  var ready = false;

  setUpAll(() async {
    if (!File(_built).existsSync()) return;
    var which = await Process.run("which", ["ffmpeg"]);
    if (which.exitCode != 0) return;
    miniaudioLibrary = File(_built).absolute.path;
    dir = await Directory.systemTemp.createTemp("canvas-decode");
    for (var ext in ["wav", "mp3", "flac", "ogg", "opus"]) {
      await Process.run("ffmpeg", [
        "-y", "-f", "lavfi", //
        "-i", "sine=frequency=1000:sample_rate=44100:duration=2",
        if (ext == "opus") ...["-c:a", "libopus"],
        // ffmpeg's own Vorbis encoder: not every build has libvorbis.
        if (ext == "ogg") ...["-c:a", "vorbis", "-strict", "-2", "-ac", "2"],
        path.join(dir.path, "tone.$ext"),
      ]);
    }
    ready = canDecode;
  });

  tearDownAll(() async {
    if (ready) await dir.delete(recursive: true);
  });

  for (var ext in ["wav", "mp3", "flac", "ogg"]) {
    test("a $ext file decodes as 48kHz stereo, at its length and level",
        () async {
      if (!ready) {
        markTestSkipped("no built app or no ffmpeg");
        return;
      }
      var file = path.join(dir.path, "tone.$ext");
      if (!File(file).existsSync()) {
        markTestSkipped("this ffmpeg could not write $ext");
        return;
      }
      var t = FileTrack.open(file);
      expect(t, isNotNull);
      // Two seconds, resampled from 44.1kHz -- give or take a codec's
      // padding.
      expect(t!.frames, closeTo(2 * mixRate, mixRate * 0.06));
      var l = Float32List(mixRate), r = Float32List(mixRate);
      var got = t.read(l, r, mixRate);
      expect(got, mixRate);
      double rms(Float32List x) {
        var sum = 0.0;
        for (var i = 10000; i < 40000; i++) {
          sum += x[i] * x[i];
        }
        return math.sqrt(sum / 30000);
      }

      // As loud as ffmpeg hears the same file -- whatever its encoder did
      // to it on the way in.
      var theirs = (await ffmpegTrack("ffmpeg", file))!;
      expect(rms(l), closeTo(rms(theirs.l), 0.003));
      expect(rms(l), greaterThan(0.05));
      expect(r[20000], closeTo(l[20000], 1e-6), reason: "mono to both sides");
      t.seek(mixRate ~/ 2);
      expect(t.read(l, r, 10), 10);
      t.close();
    });
  }

  test("Opus is not miniaudio's to read, and ffmpeg reads it instead",
      () async {
    if (!ready) {
      markTestSkipped("no built app or no ffmpeg");
      return;
    }
    var file = path.join(dir.path, "tone.opus");
    expect(FileTrack.open(file), isNull,
        reason: "SoLoud's backend is Vorbis only");
    var held = await ffmpegTrack("ffmpeg", file);
    expect(held, isNotNull);
    expect(held!.frames, closeTo(2 * mixRate, mixRate * 0.06));
  });

  test("a file that is not sound does not open", () async {
    if (!ready) {
      markTestSkipped("no built app or no ffmpeg");
      return;
    }
    var junk = path.join(dir.path, "junk.mp3");
    await File(junk).writeAsString("not a sound at all");
    expect(FileTrack.open(junk), isNull);
    expect(FileTrack.open(path.join(dir.path, "missing.wav")), isNull);
  });

  test("its peaks are its shape", () async {
    if (!ready) {
      markTestSkipped("no built app or no ffmpeg");
      return;
    }
    var p = filePeaks(path.join(dir.path, "tone.wav"), 20)!;
    expect(p.length, 20);
    expect(p.every((v) => (v - 0.125).abs() < 0.01), isTrue);
  });
}
