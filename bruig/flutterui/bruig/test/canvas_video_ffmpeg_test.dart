import 'dart:io';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/video_export.dart'
    show ffmpegPath;
import 'package:bruig/plugin_system/canvas/media/audio_runtime.dart';
import 'package:bruig/plugin_system/canvas/media/ffmpeg_video.dart';
import 'package:bruig/plugin_system/canvas/media/video_runtime.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'canvas_audio_fake.dart';

// canvas_video_ffmpeg_test.dart is the canvas asking a real ffmpeg about a
// real video: what it is, a still from it, its sound, and its frames.
//
// Skipped where there is no ffmpeg, which is the same terms the feature is
// offered on. The clips are made here by ffmpeg itself rather than checked in:
// a video file in the repository is a binary nobody can review.

void main() {
  String? ffmpeg;
  late Directory dir;
  late String pattern;

  setUpAll(() async {
    ffmpeg = await ffmpegPath();
    if (ffmpeg == null) return;
    dir = await Directory.systemTemp.createTemp("canvas_video_test");
    pattern = path.join(dir.path, "pattern.mp4");
    // Three seconds of the test card at 25 frames a second, with a tone.
    var made = await Process.run(ffmpeg!, [
      "-hide_banner", "-loglevel", "error", "-y", //
      "-f", "lavfi", "-i", "testsrc=size=320x240:rate=25",
      "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100",
      "-t", "3", "-shortest", "-c:v", "libx264", "-pix_fmt", "yuv420p",
      "-c:a", "aac", pattern,
    ]);
    if (made.exitCode != 0) ffmpeg = null;
  });

  tearDownAll(() async {
    if (ffmpeg != null && await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  test("a report is read for size, rate, length and sound", () {
    var probe = parseProbe('''
Input #0, mov,mp4,m4a,3gp,3g2,mj2, from 'pattern.mp4':
  Duration: 00:01:03.52, start: 0.000000, bitrate: 121 kb/s
  Stream #0:0[0x1](und): Video: h264 (High) (avc1 / 0x31637661), yuv420p(progressive), 1920x1080 [SAR 1:1 DAR 16:9], 41 kb/s, 29.97 fps, 29.97 tbr, 12800 tbn (default)
  Stream #0:1[0x2](und): Audio: aac (LC) (mp4a / 0x6134706D), 44100 Hz, mono, fltp, 69 kb/s (default)
''')!;
    expect(probe.width, 1920);
    expect(probe.height, 1080);
    expect(probe.fps, closeTo(29.97, 0.001));
    expect(probe.duration, closeTo(63.52, 0.001));
    expect(probe.hasAudio, isTrue);
    expect(parseProbe("Stream #0:0: Audio: mp3, 44100 Hz"), isNull,
        reason: "a sound on its own is not a video");
  });

  test("decoded no larger than it is drawn, nor than it is", () {
    expect(decodeSize(const ui.Size(1920, 1080), const ui.Size(640, 400)),
        (640, 360));
    expect(decodeSize(const ui.Size(320, 240), const ui.Size(4000, 3000)),
        (320, 240),
        reason: "never enlarged");
    expect(decodeSize(const ui.Size(3840, 2160), const ui.Size(4000, 3000)),
        (1280, 720),
        reason: "never wider than the cap");
  });

  test("the real thing: probed, a poster, its sound", () async {
    if (ffmpeg == null) return markTestSkipped("ffmpeg is not installed");
    var probe = (await probeVideo(ffmpeg!, pattern))!;
    expect(probe.width, 320);
    expect(probe.duration, closeTo(3, 0.1));
    expect(probe.hasAudio, isTrue);

    var poster = (await posterOf(ffmpeg!, pattern, at: 1))!;
    expect(poster.sublist(1, 4), "PNG".codeUnits);

    var sound = path.join(dir.path, "sound.flac");
    expect(await extractSound(ffmpeg!, pattern, sound), isTrue);
    expect(await File(sound).length(), greaterThan(1000));
  });

  testWidgets("frames arrive in order, timed from where they were asked for",
      (tester) async {
    if (ffmpeg == null) return markTestSkipped("ffmpeg is not installed");
    await tester.runAsync(() async {
      var reader = (await FfmpegFrames(() async => ffmpeg)
          .open(pattern, from: 1, width: 160, height: 120, fps: 25))!;
      var times = <double>[];
      for (var i = 0; i < 5; i++) {
        var frame = (await reader.next())!;
        expect(frame.image.width, 160);
        times.add(frame.time);
        frame.image.dispose();
      }
      reader.close();
      expect(times.first, closeTo(1, 1e-9));
      expect(times.last, closeTo(1 + 4 / 25, 1e-9));
    });
  });

  // The runtime with a real decoder behind it, and the fake sound card's
  // clock: moved to a second and a half in, the frame up is the one due then.
  testWidgets("the runtime shows the real frame due at the sound's time",
      (tester) async {
    if (ffmpeg == null) return markTestSkipped("ffmpeg is not installed");
    await tester.runAsync(() async {
      var engine = FakeEngine({"sound.flac": 3});
      var audio = AudioRuntime(engine: engine, locate: (id) async => id);
      var runtime = VideoRuntime(
          frames: FfmpegFrames(() async => ffmpeg),
          audio: audio,
          locate: (id) async => pattern);
      var e = VideoElement(const ElementBase(id: "v", width: 160, height: 120),
          clip: const MediaClip(playlist: [
            MediaSource(
                assetId: "pattern",
                soundId: "sound.flac",
                length: 3,
                width: 320,
                height: 240,
                fps: 25),
          ]));
      await runtime.play(e);
      for (var i = 0; i < 40 && runtime.view(e).frame == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(runtime.view(e).frame, isNotNull,
          reason: "a first frame, at once");
      expect(runtime.view(e).frame!.width, 160,
          reason: "decoded at the size it is drawn, not the file's");

      engine.last.at = 1.5;
      for (var i = 0; i < 200; i++) {
        runtime.tick();
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(runtime.view(e).position, 1.5);
      expect(runtime.isPlaying("v"), isTrue);
      runtime.dispose();
      audio.dispose();
    });
  });

  testWidgets("and stop at the end of the file", (tester) async {
    if (ffmpeg == null) return markTestSkipped("ffmpeg is not installed");
    await tester.runAsync(() async {
      var reader = (await FfmpegFrames(() async => ffmpeg)
          .open(pattern, from: 2.8, width: 64, height: 48, fps: 25))!;
      var count = 0;
      for (var f = await reader.next(); f != null; f = await reader.next()) {
        f.image.dispose();
        count++;
        if (count > 50) break;
      }
      reader.close();
      expect(count, inInclusiveRange(3, 7));
    });
  });
}
