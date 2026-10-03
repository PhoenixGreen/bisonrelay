import 'dart:io';
import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/media/audio_runtime.dart';
import 'package:bruig/plugin_system/canvas/media/ffmpeg_video.dart';
import 'package:bruig/plugin_system/canvas/media/video_runtime.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/video_key.dart';
import 'package:bruig/plugin_system/canvas/render/video_painter.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_video_element_test.dart is the Video element: what it saves, how the runtime
// keeps its picture in step with its sound, the green screen, and the stage
// and settings that drive it. What ffmpeg itself does is in
// canvas_video_ffmpeg_test.dart.

const film = "cccccccccccccccc.mp4";
const filmSound = "dddddddddddddddd.flac";
const other = "eeeeeeeeeeeeeeee.mp4";

/// solid is a picture of one colour, made without waiting on the engine.
ui.Image solid(Color color, [int w = 8, int h = 6]) {
  var recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = color);
  return recorder.endRecording().toImageSync(w, h);
}

/// FakeFrames hands out frames of a file that is [length] seconds long, at
/// the rate asked for, and remembers where each reader was opened from.
class FakeFrames implements FrameSource {
  final double length;
  final List<double> openedAt = [];
  FakeFrames(this.length);

  @override
  Future<FrameReader?> open(String path,
      {required double from,
      required int width,
      required int height,
      required double fps}) async {
    openedAt.add(from);
    return _FakeReader(from, fps, length);
  }
}

class _FakeReader implements FrameReader {
  final double from, fps, length;
  int i = 0;
  bool closed = false;
  _FakeReader(this.from, this.fps, this.length);

  @override
  Future<VideoFrame?> next() async {
    var t = from + i / fps;
    if (closed || t >= length) return null;
    i++;
    return VideoFrame(t, solid(const Color(0xFF3060A0)));
  }

  @override
  void close() => closed = true;
}

MediaSource clipFile(String id,
        {double start = 0, double end = 0, bool sound = true}) =>
    MediaSource(
        assetId: id,
        name: id,
        start: start,
        end: end,
        length: 10,
        soundId: sound ? filmSound : "",
        width: 320,
        height: 180,
        fps: 25);

VideoElement video(String id,
        {List<MediaSource>? files,
        MediaClip? clip,
        List<VideoControl> controls = const [
          VideoControl.clickToggle,
          VideoControl.playButton,
          VideoControl.playbar,
        ],
        Rect at = const Rect.fromLTWH(100, 100, 640, 360)}) =>
    VideoElement(
        ElementBase(
            id: id, x: at.left, y: at.top, width: at.width, height: at.height),
        clip: clip ?? MediaClip(playlist: files ?? [clipFile(film)], volume: 1),
        controls: controls);

void main() {
  late Directory root;
  late FakeEngine engine;
  late FakeFrames frames;

  setUp(() async {
    root = await Directory.systemTemp.createTemp("canvas_video_test");
    CanvasStorage.rootOverride = root.path;
    engine = FakeEngine({filmSound: 10});
    frames = FakeFrames(10);
    for (var (kind, id) in [
      (MediaKind.video, film),
      (MediaKind.video, other),
      (MediaKind.audio, filmSound),
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

  group("the element", () {
    test("reads back everything it wrote, look and all", () {
      var e = VideoElement(
        const ElementBase(id: "v", width: 300, height: 200),
        clip: MediaClip(playlist: [clipFile(film, start: 2, end: 8)]),
        key: const ChromaKey(on: true, tolerance: 0.4, spill: 0.7),
        look: ImageElement(const ElementBase(id: ""),
            filter: ImageFilterPreset.values.last,
            saturation: 1.4,
            crop: const ImageCrop(left: 0.1)),
        controls: const [VideoControl.time, VideoControl.volume],
        accent: const Color(0xFF123456),
      );
      var back = elementFromJson(e.toJson()) as VideoElement;
      var source = back.clip.playlist.single;
      expect([source.start, source.end, source.width, source.fps],
          [2, 8, 320, 25]);
      expect(source.soundId, filmSound);
      expect(back.key.on, isTrue);
      expect(back.key.tolerance, 0.4);
      expect(back.look.filter, ImageFilterPreset.values.last);
      expect(back.look.saturation, 1.4);
      expect(back.look.crop.left, 0.1);
      expect(back.controls, [VideoControl.time, VideoControl.volume]);
      expect(back.accent, const Color(0xFF123456));
    });

    // Every move goes through rebase; a field it forgot is a setting that
    // switches itself off the first time the video is dragged.
    test("and keeps all of it through a move", () {
      var e = video("v").copyWith(
          key: const ChromaKey(on: true),
          link: "",
          look: const ImageElement(ElementBase(id: ""), saturation: 2));
      var moved = e.withBase(x: 5) as VideoElement;
      expect(moved.key.on, isTrue);
      expect(moved.look.saturation, 2);
      expect(moved.clip.playlist.single.assetId, film);
    });

    test("its look is edited where the video stands, and moves it", () {
      var e = video("v");
      expect(e.picture.bounds, e.bounds);
      var cropped = e.picture.croppedTo(const ImageCrop(left: 0.5));
      var back = e.withPicture(cropped);
      expect(back.id, "v");
      expect(back.look.crop.left, 0.5);
      expect(back.x, greaterThan(e.x), reason: "a crop moves the box");
    });

    test("a file's video and sound are media, its poster a picture", () {
      var e = video("v", files: [
        clipFile(film).copyWith(posterId: "poster"),
      ]);
      expect(e.mediaIds, {film, filmSound});
      expect(e.assetIds, {"poster"});
      var linked = e.copyWith(link: "https://vimeo.com/1");
      expect(linked.mediaIds, isEmpty,
          reason: "a link's files are not the canvas's to keep");
    });

    test("a link opens where it was told to", () {
      expect(VideoHost.of("https://youtu.be/abc"), VideoHost.youtube);
      expect(VideoHost.of("https://vimeo.com/123"), VideoHost.vimeo);
      expect(linkAt("https://www.youtube.com/watch?v=abc", 75),
          "https://www.youtube.com/watch?v=abc&t=75s");
      expect(
          linkAt("https://vimeo.com/123", 30), "https://vimeo.com/123#t=30s");
      expect(
          linkAt("https://example.com/a.mp4", 30), "https://example.com/a.mp4");
    });
  });

  group("the runtime", () {
    late AudioRuntime audio;
    late VideoRuntime runtime;

    setUp(() {
      audio = AudioRuntime(
          engine: engine,
          locate: (id) => CanvasMedia.existingPath(MediaKind.audio, id));
      runtime = VideoRuntime(
          frames: frames,
          audio: audio,
          locate: (id) => CanvasMedia.existingPath(MediaKind.video, id));
    });
    tearDown(() {
      runtime.dispose();
      audio.dispose();
    });

    Future<void> settle() => pumpEventQueue(times: 50);

    test("the first frame shows at once, and its sound plays with it",
        () async {
      var e = video("v", files: [clipFile(film, start: 3)]);
      await runtime.play(e);
      await settle();
      expect(frames.openedAt, [3]);
      expect(runtime.view(e).frame, isNotNull);
      expect(audio.isPlaying("video:v"), isTrue);
      expect(engine.last.at, 3,
          reason: "the sound starts where the range does");
    });

    // Two clocks drift. The picture is whichever frame is due at the point
    // the sound has reached.
    test("the picture follows the sound's clock", () async {
      var e = video("v");
      await runtime.play(e);
      await settle();
      engine.last.at = 0.5;
      for (var i = 0; i < 20; i++) {
        runtime.tick();
        await settle();
      }
      expect(runtime.view(e).position, closeTo(0.5, 1e-9));
      var shown = runtime.view(e).frame;
      expect(shown, isNotNull);
      // Nothing later than the sound is ever up.
      engine.last.at = 0.52;
      runtime.tick();
      await settle();
      expect(runtime.view(e).position, lessThan(0.6));
    });

    test("at the end of the range the next file plays, then it stops",
        () async {
      var e = video("v", files: [
        clipFile(film, end: 2),
        clipFile(other, start: 1, end: 3, sound: false),
      ]);
      await runtime.play(e);
      await settle();
      engine.last.at = 2;
      runtime.tick();
      await settle();
      expect(frames.openedAt, [0, 1]);
      expect(runtime.view(e).start, 1);

      // The second has no sound, so it keeps time by the stopwatch; the
      // reader running out is its end.
      for (var i = 0; i < 200 && runtime.isPlaying("v"); i++) {
        runtime.tick();
        await settle();
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
      expect(runtime.isPlaying("v"), isFalse);
      expect(runtime.view(e).frame, isNotNull,
          reason: "the last frame stays up rather than snapping to the poster");
    });

    test("pause holds the frame, and play carries on from it", () async {
      var e = video("v");
      await runtime.play(e);
      await settle();
      engine.last.at = 1.2;
      runtime.tick();
      runtime.pause("v");
      expect(runtime.isPlaying("v"), isFalse);
      expect(engine.last.paused, isTrue);
      expect(runtime.view(e).position, closeTo(1.2, 1e-9));
      await runtime.play(e);
      expect(frames.openedAt, [0], reason: "not reopened, only resumed");
      expect(engine.last.paused, isFalse);
    });

    test("the bar moves both the picture and the sound", () async {
      var e = video("v", files: [clipFile(film, start: 2, end: 6)]);
      await runtime.play(e);
      await settle();
      await runtime.seekTo(e, 0.5);
      await settle();
      expect(frames.openedAt.last, 4);
      expect(engine.last.at, 4);
    });

    test("fades the picture in from nothing", () async {
      var e = video("v",
          clip: MediaClip(
              playlist: [clipFile(film)], fadeIn: 2, fadeOut: 2, volume: 1));
      await runtime.play(e);
      await settle();
      engine.last.at = 0;
      expect(runtime.view(e).opacity, closeTo(0, 1e-9));
      engine.last.at = 1;
      expect(runtime.view(e).opacity, closeTo(0.5, 1e-9));
      engine.last.at = 9.5;
      expect(runtime.view(e).opacity, closeTo(0.25, 1e-9));
    });

    test("mute and volume reach its sound", () async {
      var e = video("v");
      await runtime.play(e);
      await settle();
      runtime.setVolume(e, 0.4);
      expect(engine.last.volume, 0.4);
      runtime.toggleMute(e);
      expect(engine.last.volume, 0);
      expect(runtime.view(e).muted, isTrue);
    });

    // On the timeline the clip's volume line is the volume, as it is for a
    // sound -- and, as there, it can be turned up past full.
    test("on the timeline it is as loud as its clip's volume line", () async {
      var e = video("v");
      e = e.copyWith(clip: e.clip.copyWith(timed: true));
      runtime.cue(e, e.clip.momentAt(0.5), playing: true);
      await settle();
      expect(audio.isPlaying("video:v"), isTrue);

      var louder = e.copyWith(clip: e.clip.copyWith(volume: 1.5));
      runtime.cue(louder, louder.clip.momentAt(0.6), playing: true);
      expect(engine.last.volume, closeTo(1.5, 0.001));
      var muted = louder.copyWith(clip: louder.clip.copyWith(muted: true));
      runtime.cue(muted, muted.clip.momentAt(0.7), playing: true);
      expect(engine.last.volume, 0);
    });
  });

  group("the controller", () {
    CanvasController with_(CanvasDocument doc) {
      var c = CanvasController(doc, audioEngine: engine, frameSource: frames);
      addTearDown(c.dispose);
      return c;
    }

    test("turning the page stops a page's video and its sound", () async {
      var doc = CanvasDocument(
        scenes: [
          CanvasScene(id: "one", elements: [video("page")]),
          const CanvasScene(id: "two"),
        ],
        master: CanvasScene(id: "m", elements: [video("backdrop")]),
        masterOn: true,
      );
      var c = with_(doc);
      await c.video.play(doc.scenes.first.elements.single as VideoElement);
      await c.video.play(doc.master!.elements.single as VideoElement);
      await pumpEventQueue(times: 50);
      expect(c.audio.isPlaying("video:page"), isTrue);

      c.goToScene(1);
      expect(c.video.isPlaying("page"), isFalse);
      expect(c.audio.isPlaying("video:page"), isFalse,
          reason: "a video's sound goes where the video goes");
      expect(c.video.isPlaying("backdrop"), isTrue);
      expect(c.audio.isPlaying("video:backdrop"), isTrue);
    });

    test("a button plays, pauses and mutes a video", () async {
      var c = with_(CanvasDocument(elements: [video("v")]));
      c.runButtonAction(
          const ButtonAction(kind: ButtonActionKind.playSound, elementId: "v"));
      await pumpEventQueue(times: 50);
      expect(c.video.isPlaying("v"), isTrue);
      c.runButtonAction(
          const ButtonAction(kind: ButtonActionKind.muteSound, elementId: "v"));
      expect(c.videoShow(c.document.elements.single as VideoElement).muted,
          isTrue);
      c.runButtonAction(const ButtonAction(
          kind: ButtonActionKind.toggleSound, elementId: "v"));
      expect(c.video.isPlaying("v"), isFalse);
    });

    test("a link is opened, never played", () {
      var c = with_(CanvasDocument(elements: [
        video("v").copyWith(link: "https://youtu.be/x", linkStart: 10),
      ]));
      var url = c.pressVideo(
          c.document.elements.single as VideoElement, VideoPart.bigPlay);
      expect(url, "https://youtu.be/x?t=10s");
      expect(c.video.isPlaying("v"), isFalse);
    });
  });

  group("drawn", () {
    test("the play bar takes the bottom, controls in order", () {
      var e = video("v", controls: VideoControl.values);
      var parts = videoParts(e, e.bounds);
      expect(parts.bar!.bottom, closeTo(parts.picture.bottom, 1e-9));
      expect(parts.playPause!.right, lessThan(parts.time!.left));
      expect(parts.time!.right, lessThan(parts.track!.left));
      expect(parts.track!.right, lessThan(parts.mute!.left));
      expect(parts.mute!.right, lessThan(parts.volume!.left));
      expect(
          videoPartAt(parts, parts.picture.topLeft + const Offset(4, 4),
              clickable: true),
          VideoPart.picture);
      expect(
          videoPartAt(parts, parts.picture.topLeft + const Offset(4, 4),
              clickable: false),
          isNull);
      expect(
          videoPartAt(parts, Offset(parts.bar!.center.dx, parts.bar!.center.dy),
              clickable: true),
          isNot(VideoPart.picture),
          reason: "a miss on the bar is not a press on the picture");
    });

    test("time reads the way a player writes it", () {
      expect(clockText(65), "1:05");
      expect(clockText(3725), "1:02:05");
    });

    Future<Color> pixelAt(ui.Image image, int x, int y) async {
      var bytes = (await image.toByteData())!;
      var o = (y * image.width + x) * 4;
      return Color.fromARGB(bytes.getUint8(o + 3), bytes.getUint8(o),
          bytes.getUint8(o + 1), bytes.getUint8(o + 2));
    }

    // The screen goes whether it is lit or in shadow; what stands in front
    // of it stays, even a yellow that is close to green.
    testWidgets("the green screen goes, from dark to bright, and nothing else",
        (tester) async {
      await tester.runAsync(() async {
        await VideoKey.load();
        expect(VideoKey.ready.value, isTrue);
        var colours = [
          const Color(0xFF00300F), // the screen in shadow
          const Color(0xFF00B140), // the screen
          const Color(0xFF60FF90), // the screen, over-lit
          const Color(0xFFE0AC8C), // skin
          const Color(0xFFF0D020), // yellow
          const Color(0xFF808080), // grey
        ];
        var recorder = ui.PictureRecorder();
        var canvas = ui.Canvas(recorder);
        for (var (i, c) in colours.indexed) {
          canvas.drawRect(
              Rect.fromLTWH(i * 10.0, 0, 10, 10), Paint()..color = c);
        }
        var frame = recorder.endRecording().toImageSync(60, 10);
        var keyed = VideoKey.keyed(frame, const ChromaKey(on: true));
        for (var i = 0; i < 3; i++) {
          expect((await pixelAt(keyed, i * 10 + 5, 5)).a, lessThan(0.05),
              reason: "screen patch $i");
        }
        for (var i = 3; i < 6; i++) {
          expect((await pixelAt(keyed, i * 10 + 5, 5)).a, greaterThan(0.95),
              reason: "subject patch $i");
        }
        expect(VideoKey.keyed(frame, const ChromaKey(on: true)), same(keyed),
            reason: "the same frame is not keyed twice");
        VideoKey.forgetForTest();
      });
    });

    // The poster is what an export and a stopped video show, so it is keyed
    // and graded exactly as a frame is.
    testWidgets("a stopped video draws its poster, keyed", (tester) async {
      await tester.runAsync(() async {
        await VideoKey.load();
        var green = solid(const Color(0xFF00B140), 64, 36);
        var e = video("v",
            files: [clipFile(film).copyWith(posterId: "poster")],
            at: const Rect.fromLTWH(0, 0, 64, 36),
            controls: const []).copyWith(key: const ChromaKey(on: true));
        var recorder = ui.PictureRecorder();
        paintCanvasDocument(
            ui.Canvas(recorder),
            CanvasDocument(
                size: const CanvasSize(ratio: CanvasRatio.wide, width: 64),
                background: const CanvasBackground(),
                elements: [e]),
            images: _Pictures({"poster": green}));
        var image = await recorder.endRecording().toImage(64, 36);
        var keyedAway = await pixelAt(image, 32, 18);
        var unkeyed = e.copyWith(key: const ChromaKey());
        var recorder2 = ui.PictureRecorder();
        paintCanvasDocument(
            ui.Canvas(recorder2),
            CanvasDocument(
                size: const CanvasSize(ratio: CanvasRatio.wide, width: 64),
                elements: [unkeyed]),
            images: _Pictures({"poster": green}));
        var shown = await pixelAt(
            await recorder2.endRecording().toImage(64, 36), 32, 18);
        expect(shown.g, greaterThan(0.6), reason: "unkeyed, the poster shows");
        expect(keyedAway.g, lessThan(shown.g),
            reason: "keyed, the green is gone from it");
        VideoKey.forgetForTest();
      });
    });
  });

  group("in the editor", () {
    const viewport = Size(1200, 800);

    Future<void> idle(WidgetTester tester) async {
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 4)));
        await tester.pump();
      }
    }

    Widget wrap(Widget child) => MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
                create: (c) => ThemeNotifier(doLoad: false)),
            ChangeNotifierProvider<SnackBarModel>(
                create: (c) => SnackBarModel()),
            ChangeNotifierProvider<CanvasPreferences>(
                create: (c) => CanvasPreferences()),
          ],
          child: MaterialApp(home: Scaffold(body: child)),
        );

    Widget settingsOf(CanvasController c) => ListenableBuilder(
          listenable: c,
          builder: (context, _) => SingleChildScrollView(
            child: SizedBox(
              width: 280,
              child: CanvasControlScope(
                maxWidth: 240,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: elementSettings(context, c, c.selected!),
                ),
              ),
            ),
          ),
        );

    Future<void> show(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(wrap(child));
      await tester.pumpAndSettle();
    }

    testWidgets("a selected video plays when its picture is pressed",
        (tester) async {
      var e = video("v", at: const Rect.fromLTWH(200, 100, 640, 360));
      var c = CanvasController(
          CanvasDocument(
              size: const CanvasSize(ratio: CanvasRatio.wide, width: 1280),
              frames: 10,
              elements: [e]),
          audioEngine: engine,
          frameSource: frames);
      c.selectOnly("v");
      var key = GlobalKey<CanvasStageState>();
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      String? opened;
      await tester.pumpWidget(wrap(SizedBox(
          width: viewport.width,
          height: viewport.height,
          child: CanvasStage(
              key: key, controller: c, onButtonLink: (u) => opened = u))));
      await tester.pumpAndSettle();
      var page = key.currentState!.pageRect;
      var scale = page.width / 1280;
      Offset at(Offset doc) => page.topLeft + doc * scale;

      await tester.tapAt(at(const Offset(300, 150)));
      await idle(tester);
      expect(c.video.isPlaying("v"), isTrue);

      // A link on the same spot asks to open instead.
      c.stopAudio();
      c.replaceElement(e.copyWith(link: "https://vimeo.com/5"));
      await tester.pump();
      await tester.tapAt(at(const Offset(300, 150)));
      await tester.pump();
      expect(opened, "https://vimeo.com/5");

      c.stopAudio();
      c.dispose();
    });

    testWidgets("the pointer is a hand over what a click would press",
        (tester) async {
      var c = CanvasController(
          CanvasDocument(
              size: const CanvasSize(ratio: CanvasRatio.wide, width: 1280),
              frames: 10,
              elements: [
                ButtonElement(const ElementBase(
                    id: "b", x: 100, y: 100, width: 200, height: 80)),
              ]),
          audioEngine: engine,
          frameSource: frames);
      addTearDown(c.dispose);
      var key = GlobalKey<CanvasStageState>();
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(wrap(SizedBox(
          width: viewport.width,
          height: viewport.height,
          child: CanvasStage(key: key, controller: c))));
      await tester.pumpAndSettle();
      var page = key.currentState!.pageRect;
      var scale = page.width / 1280;
      Offset at(Offset doc) => page.topLeft + doc * scale;
      MouseCursor cursor() => tester
          .widgetList<MouseRegion>(find.descendant(
              of: find.byType(CanvasStage), matching: find.byType(MouseRegion)))
          .first
          .cursor;

      var mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: at(const Offset(20, 20)));
      await mouse.moveTo(at(const Offset(200, 140)));
      await tester.pump();
      expect(cursor(), isNot(SystemMouseCursors.click),
          reason: "unselected, a click selects it rather than pressing it");

      c.selectOnly("b");
      await mouse.moveTo(at(const Offset(201, 141)));
      await tester.pump();
      expect(cursor(), SystemMouseCursors.click);

      await mouse.moveTo(at(const Offset(600, 400)));
      await tester.pump();
      expect(cursor(), isNot(SystemMouseCursors.click));
    });

    testWidgets("a link hides what only a file can do", (tester) async {
      var c = CanvasController(
          CanvasDocument(elements: [
            video("v").copyWith(link: "https://youtu.be/x"),
          ]),
          audioEngine: engine,
          frameSource: frames);
      addTearDown(c.dispose);
      c.selectOnly("v");
      await show(tester, settingsOf(c));
      expect(find.byKey(const ValueKey("videoLink")), findsOneWidget);
      expect(find.byKey(const ValueKey("videoKey")), findsNothing);
      expect(find.byKey(const ValueKey("videoLoop")), findsNothing);
      expect(
          find.byWidgetPredicate((w) =>
              w is Tooltip && (w.message ?? "").contains("YouTube link")),
          findsOneWidget,
          reason: "the hint says why a link cannot be keyed or trimmed");
    });

    testWidgets("the green screen and the look write the video",
        (tester) async {
      var c = CanvasController(CanvasDocument(elements: [video("v")]),
          audioEngine: engine, frameSource: frames);
      addTearDown(c.dispose);
      c.selectOnly("v");
      await show(tester, settingsOf(c));

      await tester.tap(find.byKey(const ValueKey("videoKey")));
      await tester.pumpAndSettle();
      expect((c.document.elements.single as VideoElement).key.on, isTrue);
      expect(find.byKey(const ValueKey("videoKeyColour")), findsOneWidget);

      // The picture's own groups, reached through the look: the filter set
      // there lands on the video's look, and the video stays where it was.
      var filter = tester.widget<CanvasDropdown<ImageFilterPreset>>(
          find.byType(CanvasDropdown<ImageFilterPreset>));
      filter.onChanged(ImageFilterPreset.values.last);
      await tester.pumpAndSettle();
      var after = c.document.elements.single as VideoElement;
      expect(after.look.filter, ImageFilterPreset.values.last);
      expect(after.id, "v");
      expect(after.bounds, video("v").bounds);
      expect(find.text("CROP"), findsWidgets);
      expect(find.text("OUTLINE"), findsWidgets);
    });

    testWidgets("on the master it can be told to keep playing", (tester) async {
      var c = CanvasController(
          CanvasDocument(
              scenes: const [CanvasScene(id: "one")],
              master: CanvasScene(id: "m", elements: [video("v")]),
              masterOn: true,
              onMaster: true),
          audioEngine: engine,
          frameSource: frames);
      addTearDown(c.dispose);
      c.selectOnly("v");
      await show(tester, settingsOf(c));
      await tester.tap(find.byKey(const ValueKey("videoAcross")));
      await tester.pumpAndSettle();
      expect((c.document.elements.single as VideoElement).clip.acrossPages,
          isFalse);
    });
  });
}

/// _Pictures is a picture store holding the pictures a test hands it.
class _Pictures extends CanvasImageSource {
  final Map<String, ui.Image> held;
  _Pictures(this.held);

  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) => held[assetId];
}
