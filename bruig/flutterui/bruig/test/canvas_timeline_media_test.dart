import 'dart:io';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/export/export_media.dart';
import 'package:bruig/plugin_system/canvas/export/video_export.dart';
import 'package:bruig/plugin_system/canvas/media/ffmpeg_video.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/render/video_painter.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_channels.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_view.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';
import 'canvas_video_element_test.dart' show FakeFrames;

// canvas_timeline_media_test.dart is media on the timeline: where a clip is
// at a frame, the editor following the playhead, the Channels strip, and an
// export that carries the pictures and the sound.

const film = "cccccccccccccccc.mp4";
const filmSound = "dddddddddddddddd.flac";
const song = "aaaaaaaaaaaaaaaa.mp3";

MediaSource file(String id,
        {double start = 0,
        double end = 0,
        double length = 10,
        String sound = ""}) =>
    MediaSource(
        assetId: id,
        name: id,
        start: start,
        end: end,
        length: length,
        soundId: sound,
        width: 320,
        height: 180,
        fps: 25);

VideoElement timedVideo(String id, {int at = 0, MediaClip? clip}) =>
    VideoElement(ElementBase(id: id, name: "Talk", width: 320, height: 180),
        clip: (clip ?? MediaClip(playlist: [file(film, sound: filmSound)]))
            .copyWith(timed: true, at: at));

void main() {
  group("where a clip is", () {
    var clip = MediaClip(
        playlist: [file("a", start: 2, end: 6), file("b", length: 3)],
        fadeIn: 1,
        fadeOut: 1);

    test("nothing before it starts or after it ends", () {
      expect(clip.runLength, 7);
      expect(clip.momentAt(-0.1), isNull);
      expect(clip.momentAt(7), isNull);
    });

    test("in the first file's range, then the second's from its start", () {
      var m = clip.momentAt(1.5)!;
      expect([m.index, m.time], [0, 3.5]);
      m = clip.momentAt(4.5)!;
      expect([m.index, m.time], [1, 0.5]);
    });

    test("fading in and out at the ends of each file", () {
      expect(clip.momentAt(0.5)!.gain, closeTo(0.5, 1e-9));
      expect(clip.momentAt(2)!.gain, 1);
      expect(clip.momentAt(3.75)!.gain, closeTo(0.25, 1e-9));
    });

    test("a repeat goes round the list", () {
      var round = clip.copyWith(loop: MediaLoop.all);
      var m = round.momentAt(7.5)!;
      expect([m.index, m.time], [0, 2.5]);
    });

    test("a file of unknown length takes no time", () {
      expect(const MediaClip(playlist: [MediaSource(assetId: "x")]).momentAt(0),
          isNull);
    });

    test("and it reads back where it was put", () {
      var back =
          MediaClip.fromJson(const MediaClip(timed: true, at: 42).toJson());
      expect(back.timed, isTrue);
      expect(back.at, 42);
    });
  });

  group("the mix", () {
    test("each stretch trimmed, faded, set and placed; summed, not halved", () {
      var (inputs, graph) = mixArgs(const [
        ExportSound(
            path: "/a.flac",
            at: 2,
            from: 1.5,
            length: 4,
            fadeIn: 1,
            fadeOut: 0.5,
            volume: 0.8),
        ExportSound(path: "/b.flac", at: 0, from: 0, length: 3),
      ]);
      expect(inputs, [
        "-ss", "1.500", "-t", "4.000", "-i", "/a.flac", //
        "-ss", "0.000", "-t", "3.000", "-i", "/b.flac",
      ]);
      expect(graph, contains("[1:a]"));
      expect(graph, contains("afade=t=in:st=0:d=1.000"));
      expect(graph, contains("afade=t=out:st=3.500:d=0.500"));
      expect(graph, contains("volume=0.800"));
      expect(graph, contains("adelay=2000:all=1"));
      expect(graph, contains("amix=inputs=2:normalize=0"));
      expect(graph, endsWith("[mix]"));
    });
  });

  group("in the editor", () {
    late Directory root;
    late FakeEngine engine;
    late FakeFrames frames;

    setUp(() async {
      root = await Directory.systemTemp.createTemp("canvas_timed_test");
      CanvasStorage.rootOverride = root.path;
      engine = FakeEngine({filmSound: 10, song: 10});
      frames = FakeFrames(10);
      for (var (kind, id) in [
        (MediaKind.video, film),
        (MediaKind.audio, filmSound),
        (MediaKind.audio, song),
      ]) {
        var dir = Directory(path.join(root.path, "Canvas", kind.folder));
        await dir.create(recursive: true);
        await File(path.join(dir.path, id)).writeAsBytes([0]);
      }
    });

    tearDown(() async {
      CanvasStorage.rootOverride = null;
      if (await root.exists()) await root.delete(recursive: true);
    });

    CanvasController with_(CanvasDocument doc) {
      var c = CanvasController(doc, audioEngine: engine, frameSource: frames);
      addTearDown(c.dispose);
      return c;
    }

    Future<void> settle() => pumpEventQueue(times: 50);

    // Scrubbing is the whole point of putting it on the timeline: the frame
    // under the playhead is the frame shown.
    test("the playhead shows it, scrubs it and hides it", () async {
      var doc = CanvasDocument(
          frames: 200, frameRate: 25, elements: [timedVideo("v", at: 50)]);
      var c = with_(doc);
      var v = doc.elements.single as VideoElement;

      c.frame = 10;
      await settle();
      expect(c.videoShow(v).hidden, isTrue,
          reason: "not there before it starts");
      expect(frames.openedAt, isEmpty);

      c.frame = 75; // a second in
      await settle();
      expect(c.videoShow(v).hidden, isFalse);
      expect(frames.openedAt.last, closeTo(1, 1e-9));
      expect(c.video.isPlaying("v"), isFalse, reason: "held with the playhead");

      c.frame = 100; // two seconds in
      await settle();
      expect(frames.openedAt.last, closeTo(2, 1e-9),
          reason: "moved to the frame under the playhead");
    });

    test("it plays with the playhead and stops with it", () async {
      var doc = CanvasDocument(
          frames: 200, frameRate: 25, elements: [timedVideo("v")]);
      var c = with_(doc);
      c.play();
      await settle();
      expect(c.video.isPlaying("v"), isTrue);
      expect(c.audio.isPlaying("video:v"), isTrue);
      c.pause();
      await settle();
      expect(c.video.isPlaying("v"), isFalse);
      expect(engine.last.paused, isTrue);
    });

    test("nothing on it is pressed, and it does not start by itself", () async {
      var doc = CanvasDocument(frames: 200, frameRate: 25, elements: [
        timedVideo("v", at: 100).copyWith(
            clip: timedVideo("v", at: 100).clip.copyWith(autoplay: true)),
      ]);
      var c = with_(doc);
      c.play();
      await settle();
      expect(c.video.isPlaying("v"), isFalse,
          reason: "before its frame, playing the canvas does not start it");
      expect(
          c.pressVideo(doc.elements.single as VideoElement, VideoPart.picture),
          isNull);
      expect(c.video.isPlaying("v"), isFalse);
      c.pause();
    });

    // The master plays under every scene, so its timeline is the run's.
    test("a master's timed music follows the run, not the scene", () async {
      var bed = AudioElement(const ElementBase(id: "bed"),
          controls: const [],
          clip: MediaClip(
              playlist: [file(song)], timed: true, at: 30, volume: 1));
      var doc = CanvasDocument(
        frameRate: 25,
        scenes: const [
          CanvasScene(id: "one", frames: 50),
          CanvasScene(id: "two", frames: 50),
        ],
        master: CanvasScene(id: "m", background: CanvasBackground(sound: bed)),
        masterOn: true,
      );
      var c = with_(doc);
      c.goToScene(1);
      c.frame = 0; // the run's frame 50, twenty frames into the music
      c.play();
      await settle();
      expect(c.audio.isPlaying("bed"), isTrue);
      expect(engine.last.at, closeTo(20 / 25, 1e-9));
      c.pause();
    });

    test("the strip lists it, and moving it is one undo step", () async {
      var c = with_(CanvasDocument(
          frames: 200, frameRate: 25, elements: [timedVideo("v", at: 10)]));
      var lanes = c.timedLanes;
      expect(lanes.single.element.id, "v");
      expect(lanes.single.editable, isTrue);
      c.beginInteraction();
      c.setTimedClip(lanes.single.element, lanes.single.clip.copyWith(at: 40),
          transient: true);
      c.endInteraction();
      expect((c.document.elements.single as VideoElement).clip.at, 40);
      c.undo();
      expect((c.document.elements.single as VideoElement).clip.at, 10);
    });

    Future<void> showStrip(WidgetTester tester, CanvasController c) async {
      tester.view.physicalSize = const Size(1000, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                        height: 120,
                        child: CanvasChannels(
                            controller: c,
                            view: TimelineView.whole(c.document.frames)))))),
      ));
      await tester.pumpAndSettle();
    }

    // The strip is 1000 wide less its insets, over 200 frames: 4.9 pixels a
    // frame. A drag of 98 pixels is twenty frames.
    testWidgets("dragging the bar moves it; dragging its end trims it",
        (tester) async {
      var c = CanvasController(
          CanvasDocument(frames: 200, frameRate: 25, elements: [
            timedVideo("v",
                at: 50, clip: MediaClip(playlist: [file(film, length: 4)])),
          ]),
          audioEngine: engine,
          frameSource: frames);
      await showStrip(tester, c);
      var lane = find.byKey(const ValueKey("lane-v"));
      expect(lane, findsOneWidget);
      var box = tester.getRect(lane);
      double xOf(num frame) => box.left + frame / 200 * box.width;

      // The middle of the bar: frames 50 to 150.
      await tester.dragFrom(
          Offset(xOf(100), box.center.dy), Offset(20 / 200 * box.width, 0));
      await tester.pumpAndSettle();
      var clip = (c.document.elements.single as VideoElement).clip;
      expect(clip.at, closeTo(70, 1));

      // The front edge, in by a second's worth: the first second is cut off
      // and what is left stays put.
      await tester.dragFrom(
          Offset(xOf(clip.at), box.center.dy), Offset(25 / 200 * box.width, 0));
      await tester.pumpAndSettle();
      clip = (c.document.elements.single as VideoElement).clip;
      expect(clip.playlist.single.start, closeTo(1, 0.05));
      expect(clip.at, closeTo(95, 1));

      c.stopAudio();
      c.dispose();
    });
  });

  group("an export", () {
    late Directory root;
    String? ffmpeg;

    setUpAll(() async {
      ffmpeg = await ffmpegPath();
    });

    setUp(() async {
      root = await Directory.systemTemp.createTemp("canvas_timed_export");
      CanvasStorage.rootOverride = root.path;
    });

    tearDown(() async {
      CanvasStorage.rootOverride = null;
      if (await root.exists()) await root.delete(recursive: true);
    });

    test("places each stretch of sound where the clip is", () async {
      var doc = CanvasDocument(
        frameRate: 25,
        scenes: [
          CanvasScene(id: "one", frames: 100, elements: [
            timedVideo("v",
                at: 25,
                clip: MediaClip(playlist: [
                  file(film, start: 2, end: 3, sound: filmSound),
                ], loop: MediaLoop.all, fadeIn: 0.2, fadeOut: 0.2)),
          ]),
          const CanvasScene(id: "two", frames: 50),
        ],
      );
      var media = ExportMedia.of(doc,
          frames: FakeFrames(10), locate: (kind, id) async => "/$id")!;
      var sounds = await media.sounds();
      // One second from 1s, repeated until the scene ends at 4s.
      expect([for (var s in sounds) s.at], [1, 2, 3]);
      expect(sounds.every((s) => s.from == 2 && s.length == 1), isTrue);
      expect(sounds.first.path, "/$filmSound");
      media.dispose();
    });

    test("cut short by the end of its scene, it stops rather than fades",
        () async {
      var doc = CanvasDocument(frameRate: 25, frames: 50, elements: [
        timedVideo("v",
            clip: MediaClip(
                playlist: [file(film, sound: filmSound, length: 10)],
                fadeOut: 1)),
      ]);
      var media = ExportMedia.of(doc,
          frames: FakeFrames(10), locate: (kind, id) async => "/$id")!;
      var sound = (await media.sounds()).single;
      expect(sound.length, 2);
      expect(sound.fadeOut, 0);
      media.dispose();
    });

    testWidgets("frames arrive for the frames the clip is on", (tester) async {
      await tester.runAsync(() async {
        var doc = CanvasDocument(
            frameRate: 25, frames: 100, elements: [timedVideo("v", at: 10)]);
        var fake = FakeFrames(10);
        var media = ExportMedia.of(doc,
            frames: fake, locate: (kind, id) async => "/$id")!;
        var v = doc.elements.single as VideoElement;
        expect((await media.at(0))(v).hidden, isTrue);
        var show = (await media.at(10))(v);
        expect(show.frame, isNotNull);
        await media.at(11);
        await media.at(12);
        expect(fake.openedAt, [0], reason: "read forward, not reopened");
        media.dispose();
      });
    });

    // The real thing: a canvas with a video on its timeline, exported, and
    // the file asked what is in it.
    testWidgets("an MP4 of a timed video carries its picture and its sound",
        (tester) async {
      if (ffmpeg == null) return markTestSkipped("ffmpeg is not installed");
      await tester.runAsync(() async {
        var clipPath = path.join(root.path, "talk.mp4");
        await Process.run(ffmpeg!, [
          "-hide_banner", "-loglevel", "error", "-y", //
          "-f", "lavfi", "-i", "testsrc=size=160x120:rate=25",
          "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100",
          "-t", "2", "-shortest", "-c:v", "libx264", "-pix_fmt", "yuv420p",
          "-c:a", "aac", clipPath,
        ]);
        var videoId = (await CanvasMedia.saveFile(MediaKind.video, clipPath))!;
        var flac = path.join(root.path, "talk.flac");
        expect(await extractSound(ffmpeg!, clipPath, flac), isTrue);
        var soundId = (await CanvasMedia.saveFile(MediaKind.audio, flac))!;

        var doc = CanvasDocument(
          size: const CanvasSize(ratio: CanvasRatio.wide, width: 320),
          frameRate: 25,
          frames: 50,
          elements: [
            VideoElement(const ElementBase(id: "v", width: 160, height: 90),
                clip: MediaClip(playlist: [
                  MediaSource(
                      assetId: videoId,
                      soundId: soundId,
                      length: 2,
                      width: 160,
                      height: 120,
                      fps: 25),
                ], timed: true, at: 12)),
          ],
        );
        var export = await renderVideo(doc);
        expect(export, isNotNull, reason: "the export was written");
        var out = path.join(root.path, "out.mp4");
        await File(out).writeAsBytes(export!.data);
        var report = (await Process.run(ffmpeg!, ["-hide_banner", "-i", out]))
            .stderr
            .toString();
        expect(report, contains("Video: h264"));
        expect(report, contains("Audio: aac"),
            reason: "the clip's sound is in the file");
        var probe = parseProbe(report)!;
        expect(probe.duration, closeTo(2, 0.15),
            reason: "as long as the picture: fifty frames at twenty-five");
      });
    });
  });
}
