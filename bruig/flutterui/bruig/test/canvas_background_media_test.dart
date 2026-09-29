import 'dart:io';
import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/video_key.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/element_settings_pane.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';
import 'canvas_video_element_test.dart' show FakeFrames, solid;

// canvas_background_media_test.dart is a background carrying a picture, a
// video and a sound: what it saves, the order they are drawn in, what plays
// when, and the panel that sets them up.

const song = "aaaaaaaaaaaaaaaa.mp3";
const film = "cccccccccccccccc.mp4";
const filmSound = "dddddddddddddddd.flac";

MediaClip playing(String id, {bool across = true, String sound = ""}) =>
    MediaClip(playlist: [
      MediaSource(
          assetId: id,
          soundId: sound,
          length: 10,
          width: 32,
          height: 18,
          fps: 25),
    ], autoplay: true, loop: MediaLoop.all, acrossPages: across);

CanvasBackground withSound(String id, {bool across = true}) => CanvasBackground(
    sound: AudioElement(ElementBase(id: id, name: "Background sound"),
        controls: const [], clip: playing(song, across: across)));

CanvasBackground withVideo(String id) => CanvasBackground(
    video: VideoElement(ElementBase(id: id, name: "Background video"),
        controls: const [], clip: playing(film, sound: filmSound)));

void main() {
  late Directory root;
  late FakeEngine engine;

  setUp(() async {
    root = await Directory.systemTemp.createTemp("canvas_bg_media_test");
    CanvasStorage.rootOverride = root.path;
    engine = FakeEngine({song: 10, filmSound: 10});
    for (var (kind, id) in [
      (MediaKind.audio, song),
      (MediaKind.audio, filmSound),
      (MediaKind.video, film),
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

  group("what it saves", () {
    // A background could hold a bare picture before it could hold one with
    // settings, and a canvas saved then has to open with it.
    test("an old background picture still reads, and gives way to a new one",
        () {
      var old = CanvasBackground.fromJson({
        "spec": const ProceduralSpec().toJson(),
        "image": "old.png",
        "fit": ImageFit.contain.name,
      });
      expect(old.shownPicture!.assetId, "old.png");
      expect(old.shownPicture!.fit, ImageFit.contain);

      var edited = old.copyWith(
          picture: const ImageElement(ElementBase(id: "p"),
              assetId: "new.png", saturation: 0.5));
      expect(edited.shownPicture!.assetId, "new.png");
      expect(edited.imageAssetId, isEmpty,
          reason: "the old one is gone for good");
      var back = CanvasBackground.fromJson(edited.toJson());
      expect(back.shownPicture!.saturation, 0.5);
    });

    test("a video and a sound read back as the elements they are", () {
      var bg = withVideo("v").copyWith(sound: withSound("s").sound);
      var back = CanvasBackground.fromJson(bg.toJson());
      expect(back.video!.clip.loop, MediaLoop.all);
      expect(back.video!.controls, isEmpty);
      expect(back.sound!.clip.playlist.single.assetId, song);
      expect(back.media.map((e) => e.id), ["v", "s"]);
    });

    // A sweep deletes whatever no saved canvas names. A background's files
    // are named by the background, on every scene and the master.
    test("every background's files are counted, not only the one showing", () {
      var doc = CanvasDocument(
        background: withSound("d"),
        scenes: [
          CanvasScene(id: "one", background: withVideo("v")),
          const CanvasScene(id: "two"),
        ],
        sceneAt: 1,
        master: CanvasScene(
            id: "m",
            background: const CanvasBackground(
                picture:
                    ImageElement(ElementBase(id: "p"), assetId: "pic.png"))),
      );
      expect(doc.mediaIds, {song, film, filmSound});
      expect(doc.assetIds, contains("pic.png"));
    });
  });

  group("drawn", () {
    Future<Color> pixel(CanvasDocument doc, Offset at,
        {Map<String, ui.Image> pictures = const {}}) async {
      var size = doc.size.size;
      var recorder = ui.PictureRecorder();
      paintCanvasDocument(ui.Canvas(recorder), doc,
          images: _Pictures(pictures));
      var image = await recorder
          .endRecording()
          .toImage(size.width.round(), size.height.round());
      var bytes = (await image.toByteData())!;
      var o = (at.dy.round() * image.width + at.dx.round()) * 4;
      return Color.fromARGB(bytes.getUint8(o + 3), bytes.getUint8(o),
          bytes.getUint8(o + 1), bytes.getUint8(o + 2));
    }

    const red = ProceduralSpec(
        style: ProceduralStyle.plain, background: Color(0xFFFF0000));
    const size = CanvasSize(ratio: CanvasRatio.wide, width: 160);

    // The pattern is what shows round a picture that does not cover the
    // page, and through a video with its screen taken out.
    testWidgets("pattern, then picture, then video", (tester) async {
      await tester.runAsync(() async {
        await VideoKey.load();
        var blue = solid(const Color(0xFF0000FF), 10, 10);
        var contained = CanvasDocument(
            size: size,
            background: const CanvasBackground(
                spec: red,
                picture: ImageElement(ElementBase(id: "p"),
                    assetId: "blue", fit: ImageFit.contain)));
        var mid = Offset(size.size.width / 2, size.size.height / 2);
        // Which colour it is rather than exactly how much: the plain pattern
        // darkens a little towards its edges.
        bool isRed(Color c) => c.r > 0.6 && c.g < 0.2 && c.b < 0.2;
        bool isBlue(Color c) => c.b > 0.6 && c.r < 0.2 && c.g < 0.2;
        expect(isBlue(await pixel(contained, mid, pictures: {"blue": blue})),
            isTrue,
            reason: "the picture in the middle");
        expect(
            isRed(await pixel(contained, const Offset(2, 45),
                pictures: {"blue": blue})),
            isTrue,
            reason: "the pattern either side of it");

        var green = solid(const Color(0xFF00B140), 32, 18);
        var keyed = CanvasDocument(
            size: size,
            background: CanvasBackground(
                spec: red,
                video: withVideo("v").video!.copyWith(
                    key: const ChromaKey(on: true),
                    clip: MediaClip(playlist: [
                      const MediaSource(
                          assetId: film, posterId: "poster", length: 10),
                    ]))));
        var seen = await pixel(keyed, mid, pictures: {"poster": green});
        expect(isRed(seen), isTrue,
            reason: "the screen is gone and the pattern shows through");
        VideoKey.forgetForTest();
      });
    });
  });

  group("what plays", () {
    CanvasController with_(CanvasDocument doc) {
      var c = CanvasController(doc,
          audioEngine: engine, frameSource: FakeFrames(10));
      addTearDown(c.dispose);
      return c;
    }

    test("the backdrop starts with the canvas", () async {
      var c = with_(CanvasDocument(
          frames: 1,
          background: withVideo("v").copyWith(sound: withSound("s").sound)));
      c.play();
      await pumpEventQueue(times: 50);
      expect(c.video.isPlaying("v"), isTrue);
      expect(c.audio.isPlaying("s"), isTrue);
      expect(c.audio.isPlaying("video:v"), isTrue,
          reason: "and the video's own sound with it");
    });

    test("the master's music carries on; a page's own stops at the turn",
        () async {
      var doc = CanvasDocument(
        frames: 1,
        scenes: [
          CanvasScene(id: "one", background: withSound("page")),
          const CanvasScene(id: "two"),
        ],
        master: CanvasScene(id: "m"),
        masterOn: true,
      );
      var c = with_(doc);
      c.play();
      await pumpEventQueue(times: 50);
      expect(c.audio.isPlaying("page"), isTrue);
      c.pause();
      c.goToScene(1);
      expect(c.audio.isPlaying("page"), isFalse);

      // Now with the music on the master's background instead.
      var shared = with_(CanvasDocument(
        frames: 1,
        scenes: const [CanvasScene(id: "one"), CanvasScene(id: "two")],
        master: CanvasScene(id: "m", background: withSound("bed")),
        masterOn: true,
      ));
      shared.play();
      await pumpEventQueue(times: 50);
      shared.pause();
      shared.goToScene(1);
      expect(shared.audio.isPlaying("bed"), isTrue,
          reason: "the master's backdrop is on every page");
    });

    test("unless it is told to stop at the join", () async {
      var c = with_(CanvasDocument(
        frames: 1,
        scenes: const [CanvasScene(id: "one"), CanvasScene(id: "two")],
        master:
            CanvasScene(id: "m", background: withSound("bed", across: false)),
        masterOn: true,
      ));
      c.play();
      await pumpEventQueue(times: 50);
      c.pause();
      c.goToScene(1);
      expect(c.audio.isPlaying("bed"), isFalse);
    });

    test("a button pauses the background music", () async {
      var c = with_(CanvasDocument(frames: 1, background: withSound("s")));
      c.play();
      await pumpEventQueue(times: 50);
      c.runButtonAction(const ButtonAction(
          kind: ButtonActionKind.pauseSound, elementId: "s"));
      expect(c.audio.isPlaying("s"), isFalse);
    });

    test("taking the video off the background stops it", () async {
      var c = with_(CanvasDocument(frames: 1, background: withVideo("v")));
      c.play();
      await pumpEventQueue(times: 50);
      c.setBackground(c.document.editedBackground.copyWith(clearVideo: true));
      expect(c.video.isPlaying("v"), isFalse);
      expect(c.audio.isPlaying("video:v"), isFalse);
    });
  });

  group("the panel", () {
    Future<void> show(WidgetTester tester, CanvasController c) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(
              create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
          child: SizedBox(
            width: 280,
            child: CanvasControlScope(
              maxWidth: 240,
              child: ListenableBuilder(
                  listenable: c,
                  builder: (context, _) => elementSettingsBody(context, c)),
            ),
          ),
        ))),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> open(WidgetTester tester, String label) async {
      var heading = find.text(label.toUpperCase());
      if (heading.evaluate().isEmpty) heading = find.text(label);
      await tester.ensureVisible(heading.first);
      await tester.tap(heading.first);
      await tester.pumpAndSettle();
    }

    // Sound goes on the timeline's channels. A background offers a picture
    // and a video; a sound only where it already has one, to change or take
    // off.
    testWidgets("offers a picture and a video, and no new sound",
        (tester) async {
      var c = CanvasController(const CanvasDocument(),
          audioEngine: engine, frameSource: FakeFrames(10));
      addTearDown(c.dispose);
      await show(tester, c);
      for (var key in ["backgroundPicture", "backgroundVideo"]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget);
      }
      expect(find.byKey(const ValueKey("backgroundSound")), findsNothing);
    });

    testWidgets("a background video has no link and nothing to press",
        (tester) async {
      var c = CanvasController(CanvasDocument(background: withVideo("v")),
          audioEngine: engine, frameSource: FakeFrames(10));
      addTearDown(c.dispose);
      await show(tester, c);
      await open(tester, "Video");
      expect(find.byKey(const ValueKey("videoKey")), findsOneWidget,
          reason: "it can be keyed like any video");
      expect(find.byKey(const ValueKey("videoLink")), findsNothing);
      expect(
          find.byKey(const ValueKey("videoControlplayButton")), findsNothing);

      await tester.ensureVisible(find.byKey(const ValueKey("videoKey")));
      await tester.tap(find.byKey(const ValueKey("videoKey")));
      await tester.pumpAndSettle();
      expect(c.document.editedBackground.video!.key.on, isTrue);

      c.undo();
      expect(c.document.editedBackground.video!.key.on, isFalse,
          reason: "an edit to the backdrop is one undo step");

      await tester.tap(find.byTooltip("Take the video off the background"));
      await tester.pumpAndSettle();
      expect(c.document.editedBackground.video, isNull);
    });

    testWidgets("on the master's backdrop, the sound can carry across",
        (tester) async {
      var c = CanvasController(
          CanvasDocument(
              scenes: const [CanvasScene(id: "one")],
              master: CanvasScene(id: "m", background: withSound("bed")),
              masterOn: true),
          audioEngine: engine,
          frameSource: FakeFrames(10));
      addTearDown(c.dispose);
      await show(tester, c);
      await open(tester, "Sound");
      expect(find.byKey(const ValueKey("audioAcross")), findsOneWidget);
      expect(find.byKey(const ValueKey("audioGlyph")), findsNothing,
          reason: "a backdrop's sound is never drawn");
    });
  });
}

class _Pictures extends CanvasImageSource {
  final Map<String, ui.Image> held;
  _Pictures(this.held);

  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) => held[assetId];
}
