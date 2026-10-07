import 'dart:io';
import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_bundle.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/media/audio_runtime.dart';
import 'package:bruig/plugin_system/canvas/render/audio_painter.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/button_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/elements_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_audio_element_test.dart is the Audio element in the editor: what it
// saves, how it is stored and sent, how it is drawn, what the controller does
// with it, and the controls that set it up. The rules about what plays are in
// canvas_audio_runtime_test.dart.

const song = "aaaaaaaaaaaaaaaa.mp3";
const bell = "bbbbbbbbbbbbbbbb.ogg";

MediaClip clipOf(String id, {bool autoplay = false, bool across = true}) =>
    MediaClip(
        playlist: [MediaSource(assetId: id, name: id)],
        autoplay: autoplay,
        acrossPages: across);

AudioElement speaker(String id,
        {MediaClip clip = const MediaClip(),
        List<AudioControl> controls = const [AudioControl.playPause],
        Rect at = const Rect.fromLTWH(100, 100, 80, 80)}) =>
    AudioElement(
        ElementBase(
            id: id, x: at.left, y: at.top, width: at.width, height: at.height),
        clip: clip,
        controls: controls,
        box: const BoxSpec(fill: Color(0xFF223046), borderRadius: 999));

void main() {
  late Directory root;
  late FakeEngine engine;

  setUp(() async {
    root = await Directory.systemTemp.createTemp("canvas_audio_test");
    CanvasStorage.rootOverride = root.path;
    engine = FakeEngine({song: 30, bell: 2});
    // The player is handed a path, so the files have to be where the store
    // says they are. What is in them is the fake engine's business.
    var dir = Directory(path.join(root.path, "Canvas", canvasAudioFolder));
    await dir.create(recursive: true);
    for (var id in [song, bell]) {
      await File(path.join(dir.path, id)).writeAsBytes([1, 2, 3]);
    }
  });

  tearDown(() async {
    CanvasStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  group("the element", () {
    test("reads back everything it wrote", () {
      var e = AudioElement(
        const ElementBase(id: "a", x: 1, y: 2, width: 3, height: 4),
        clip: clipOf(song, autoplay: true),
        glyph: AudioGlyph.headphones,
        picture: "p1",
        pausedPicture: "p2",
        mutedPicture: "p3",
        iconColor: const Color(0xFF112233),
        accent: const Color(0xFF445566),
        controls: const [AudioControl.volume, AudioControl.mute],
      );
      var back = elementFromJson(e.toJson()) as AudioElement; // the one decoder
      expect(back.clip.playlist.single.assetId, song);
      expect(back.clip.autoplay, isTrue);
      expect(back.glyph, AudioGlyph.headphones);
      expect([back.picture, back.pausedPicture, back.mutedPicture],
          ["p1", "p2", "p3"]);
      expect(back.iconColor, const Color(0xFF112233));
      expect(back.accent, const Color(0xFF445566));
      expect(back.controls, [AudioControl.volume, AudioControl.mute]);
    });

    // Every move goes through rebase, so a field it forgot is a setting that
    // switches itself off the first time the element is dragged.
    test("and keeps all of it through a move", () {
      var e = AudioElement(const ElementBase(id: "a"),
          clip: clipOf(song),
          glyph: AudioGlyph.mic,
          picture: "p1",
          controls: const [AudioControl.mute]);
      var moved = e.withBase(x: 50) as AudioElement;
      expect(moved.x, 50);
      expect(moved.clip.playlist.single.assetId, song);
      expect(moved.glyph, AudioGlyph.mic);
      expect(moved.picture, "p1");
      expect(moved.controls, [AudioControl.mute]);
    });

    test("its sound is media and its pictures are pictures", () {
      var e = AudioElement(const ElementBase(id: "a"),
          clip: clipOf(song), picture: "pic");
      expect(e.mediaIds, {song});
      expect(e.assetIds, {"pic"});
    });

    // Every scene and the master, not the one open -- the same trap
    // assetIds fell into, where a sweep deleted what another scene used.
    test("a document names every sound on every scene and the master", () {
      var doc = CanvasDocument(
        scenes: [
          CanvasScene(id: "one", elements: [speaker("x", clip: clipOf(song))]),
          const CanvasScene(id: "two"),
        ],
        master:
            CanvasScene(id: "m", elements: [speaker("y", clip: clipOf(bell))]),
        sceneAt: 1,
      );
      expect(doc.mediaIds, {song, bell});
    });
  });

  group("stored and sent", () {
    test("a file is known by what it is, not what it is called", () {
      List<int> b(String text, [int at = 0]) =>
          [...List.filled(at, 0), ...text.codeUnits, ...List.filled(40, 0)];
      var wav = b("RIFF")..setRange(8, 12, "WAVE".codeUnits);
      expect(CanvasMedia.extensionOf(wav), ".wav");
      expect(CanvasMedia.extensionOf(b("fLaC")), ".flac");
      expect(CanvasMedia.extensionOf(b("OggS")), ".ogg");
      var opus = b("OggS")..setRange(28, 36, "OpusHead".codeUnits);
      expect(CanvasMedia.extensionOf(opus), ".opus");
      expect(CanvasMedia.extensionOf(b("ID3")), ".mp3");
      expect(CanvasMedia.extensionOf([0xFF, 0xFB, 0x90, 0x00]), ".mp3");
      var m4a = List<int>.filled(16, 0)
        ..setRange(4, 8, "ftyp".codeUnits)
        ..setRange(8, 12, "M4A ".codeUnits);
      expect(CanvasMedia.extensionOf(m4a), ".m4a");
      expect(CanvasMedia.extensionOf([0x1A, 0x45, 0xDF, 0xA3]), ".webm");
      expect(CanvasMedia.extensionOf(b("hello")), "");
    });

    test("stored once, by a hash of its bytes", () async {
      var source = File(path.join(root.path, "take one.mp3"));
      await source.writeAsBytes([...("ID3".codeUnits), ...List.filled(99, 7)]);
      var first = await CanvasMedia.saveFile(MediaKind.audio, source.path);
      var second = await CanvasMedia.saveFile(MediaKind.audio, source.path);
      expect(first, isNotNull);
      expect(first, second);
      expect(first, endsWith(".mp3"));
      expect(
          await CanvasMedia.existingPath(MediaKind.audio, first!), isNotNull);
    });

    test("an id is never a way out of the folder", () async {
      expect(
          await CanvasMedia.pathFor(MediaKind.audio, "../../etc.mp3"), isNull);
      expect(CanvasMedia.isId("0123456789abcdef.mp3"), isTrue);
    });

    // A sound added to a canvas nobody has saved yet is named by no saved
    // canvas. Swept on another canvas's save, it vanished from this one.
    test("a sweep keeps what the open canvas uses", () async {
      var removed =
          await CanvasMedia.sweep(MediaKind.audio, {song}); // bell is unused
      expect(removed, 1);
      expect(await CanvasMedia.existingPath(MediaKind.audio, song), isNotNull);
      await CanvasMedia.sweepUnused(open: {song});
      expect(await CanvasMedia.existingPath(MediaKind.audio, song), isNotNull,
          reason: "no saved canvas names it, and the open one does");
    });

    test("a bundle carries the sound and puts it back", () async {
      var doc = CanvasDocument(elements: [speaker("x", clip: clipOf(song))]);
      var packed = await packCanvas(doc,
          media: (id) async => id == song ? [9, 8, 7] : null);
      var back = (await unpackCanvas(packed))!;
      expect(back.media.keys, [song]);
      expect(back.pictures, isEmpty, reason: "a sound is not a picture");

      await File(path.join(root.path, "Canvas", canvasAudioFolder, song))
          .delete();
      await storeBundlePictures(back);
      var stored = await CanvasMedia.load(MediaKind.audio, song);
      expect(stored, [9, 8, 7]);
    });
  });

  group("drawn", () {
    test("alone, the icon sits in the middle of its box", () {
      var e = speaker("x");
      var parts = audioParts(e, e.bounds);
      expect(parts.icon.center.dx, closeTo(e.bounds.center.dx, 0.01));
      expect(parts.mute, isNull);
      expect(parts.volume, isNull);
    });

    test("with its controls, the icon leads and the bar takes the rest", () {
      var e = speaker("x",
          controls: const [AudioControl.mute, AudioControl.volume],
          at: const Rect.fromLTWH(0, 0, 400, 80));
      var parts = audioParts(e, e.bounds);
      var inner = e.box.inner(e.bounds);
      expect(parts.icon.left, closeTo(inner.left, 0.01));
      expect(parts.mute!.left, greaterThan(parts.icon.right));
      expect(parts.volume!.left, greaterThan(parts.mute!.right));
      expect(parts.volume!.right, closeTo(inner.right, 0.01));
      expect(volumeAt(parts.volume!, parts.volume!.left), 0);
      expect(volumeAt(parts.volume!, parts.volume!.right), 1);
    });

    Future<int> accentPixels(AudioElement e, AudioState state) async {
      var recorder = ui.PictureRecorder();
      paintAudio(ui.Canvas(recorder), e.bounds, e, state);
      var image = await recorder.endRecording().toImage(300, 300);
      var bytes = (await image.toByteData())!;
      var count = 0;
      for (var i = 0; i < bytes.lengthInBytes; i += 4) {
        var r = bytes.getUint8(i), g = bytes.getUint8(i + 1);
        if (r > 200 && g < 60) count++; // the accent below is red
      }
      return count;
    }

    // The waves are what say whether any sound is coming out of it.
    testWidgets("playing lights the waves; muted takes them away",
        (tester) async {
      await tester.runAsync(() async {
        var e = speaker("x").copyWith(accent: const Color(0xFFFF0000));
        expect(await accentPixels(e, const AudioState(volume: 1)), 0);
        expect(
            await accentPixels(e, const AudioState(playing: true, volume: 1)),
            greaterThan(20));
        expect(
            await accentPixels(
                e, const AudioState(playing: true, muted: true, volume: 1)),
            0);
      });
    });
  });

  group("the controller", () {
    CanvasController with_(CanvasDocument doc) {
      var c = CanvasController(doc, audioEngine: engine);
      addTearDown(c.dispose);
      return c;
    }

    test("a canvas with no sound never opens the sound device", () async {
      var c = with_(const CanvasDocument(frames: 10));
      c.play();
      c.pause();
      expect(engine.starts, 0);
    });

    test("a button plays, pauses, mutes and stops a sound", () async {
      var c =
          with_(CanvasDocument(elements: [speaker("s", clip: clipOf(song))]));
      ButtonAction does(ButtonActionKind k) =>
          ButtonAction(kind: k, elementId: "s");

      c.runButtonAction(does(ButtonActionKind.playSound));
      await pumpEventQueue();
      expect(c.audio.isPlaying("s"), isTrue);

      c.runButtonAction(does(ButtonActionKind.toggleSound));
      expect(c.audio.isPlaying("s"), isFalse);

      c.runButtonAction(does(ButtonActionKind.muteSound));
      expect(c.audioState(c.document.elements.single as AudioElement).muted,
          isTrue);

      c.runButtonAction(does(ButtonActionKind.stopSound));
      expect(c.audio.isPlaying("s"), isFalse);
    });

    test("a button's sound action is written down and read back", () {
      var action = const ButtonAction(
          kind: ButtonActionKind.toggleSound, elementId: "s");
      var back = ButtonAction.fromJson(action.toJson());
      expect(back.kind, ButtonActionKind.toggleSound);
      expect(back.elementId, "s");
    });

    test("turning the page stops its sound; the master's carries on", () async {
      var doc = CanvasDocument(
        scenes: [
          CanvasScene(
              id: "one", elements: [speaker("page", clip: clipOf(song))]),
          const CanvasScene(id: "two"),
        ],
        master: CanvasScene(id: "m", elements: [
          speaker("music", clip: clipOf(song)),
          speaker("chime", clip: clipOf(bell, across: false)),
        ]),
        masterOn: true,
      );
      var c = with_(doc);
      var master = doc.master!.elements.cast<AudioElement>();
      await c.audio.play(doc.scenes.first.elements.single as AudioElement);
      await c.audio.play(master.first);
      await c.audio.play(master.last);

      c.goToScene(1);
      expect(c.audio.isPlaying("page"), isFalse);
      expect(c.audio.isPlaying("music"), isTrue,
          reason: "set to keep playing across pages");
      expect(c.audio.isPlaying("chime"), isFalse,
          reason: "set to stop at the join");
    });

    // A clip on the master's timeline runs on the run's clock under every
    // scene. Stopped at each turn, the timeline started it again at once --
    // heard as a restart, or as itself twice over.
    test("a sound on the master's timeline plays on through every scene",
        () async {
      var music = AudioElement(const ElementBase(id: "music", visible: false),
          clip: const MediaClip(
              timed: true,
              acrossPages: false,
              playlist: [MediaSource(assetId: song, name: song, length: 30)]));
      var doc = CanvasDocument(
        frameRate: 10,
        scenes: const [
          CanvasScene(id: "one", frames: 10),
          CanvasScene(id: "two", frames: 10),
        ],
        master: CanvasScene(id: "m", elements: [music]),
        masterOn: true,
      );
      var c = with_(doc);
      c.playAll = true;
      c.play();
      for (var i = 0; i < 15; i++) {
        c.tickForTest();
        await pumpEventQueue();
      }
      expect(c.sceneAt, 1, reason: "past the turn");
      var heard = [
        for (var v in engine.voices)
          if (path.basename(v.track.path) == song) v
      ];
      expect(heard, hasLength(1),
          reason: "started once, not again at the turn");
      expect(heard.single.alive, isTrue);
      c.pause();
    });

    // A sound cut in two is played as the one sound it was: no stop and
    // start at the cut, which the playhead -- a frame at a time -- never
    // made on the sample, and which was heard as a skip.
    test("a cut sound plays on through the cut as one", () async {
      var music = AudioElement(const ElementBase(id: "music", visible: false),
          clip: const MediaClip(
              timed: true,
              channel: "ch1",
              channelName: "Channel 1",
              playlist: [MediaSource(assetId: song, name: song, length: 30)]));
      var c =
          with_(CanvasDocument(frames: 200, frameRate: 10, elements: [music]));
      expect(c.splitClip(c.timedLanes.single, 20), isTrue);
      c.frame = 15;
      c.play();
      for (var i = 0; i < 12; i++) {
        c.tickForTest();
        await pumpEventQueue();
      }
      expect(c.frame, 27, reason: "past the cut");
      expect(engine.voices, hasLength(1),
          reason: "one sound, not stopped and started again at the cut");
      expect(engine.voices.single.alive, isTrue);
      expect(c.audio.isPlaying(c.document.elements.last.id), isFalse,
          reason: "the second half is played by the first");
      c.pause();
    });

    // Stopped, a sound on the timeline is brought down and stopped rather
    // than paused -- a pause cuts it off mid-swing, a click -- and played
    // again it starts where the playhead now is, from nothing, so nothing of
    // the old place or the old level is heard: the spike at a fade's start.
    test("stopped and played again, a sound fades out and back in", () async {
      var music = AudioElement(const ElementBase(id: "music", visible: false),
          clip: const MediaClip(
              timed: true,
              fadeIn: 2,
              playlist: [MediaSource(assetId: song, name: song, length: 30)]));
      var c =
          with_(CanvasDocument(frames: 200, frameRate: 10, elements: [music]));
      c.frame = 50;
      c.play();
      await pumpEventQueue();
      c.tickForTest();
      await pumpEventQueue();
      c.pause();
      await pumpEventQueue();
      var first = engine.voices.single;
      expect(
          engine.softStops.map((s) => (s.$1, s.$2)), [(first, declickSeconds)],
          reason: "brought down, not cut off");

      c.frame = 5; // half a second into the two-second rise
      c.play();
      await pumpEventQueue();
      var again = engine.last;
      expect(again, isNot(same(first)));
      expect(again.at, closeTo(0.5, 0.01), reason: "where the playhead is");
      expect(again.volume, lessThan(0.5),
          reason: "at the fade's level, not the old one");
      c.pause();
    });

    // The sound plays by the sound card's clock, which does not run at quite
    // the computer's speed. Over a long track the two drifted apart until
    // the sound was moved back to the playhead: a skip part way through.
    // The playhead keeps with the sound instead, and the sound is never
    // moved for drift.
    test("a long track is never moved for drift; the playhead keeps with it",
        () async {
      var music = AudioElement(const ElementBase(id: "music", visible: false),
          clip: const MediaClip(
              timed: true,
              playlist: [MediaSource(assetId: song, name: song, length: 30)]));
      var c =
          with_(CanvasDocument(frames: 3600, frameRate: 10, elements: [music]));
      var now = 0;
      c.clockForTest = () => now;
      c.play();
      await pumpEventQueue();
      var voice = engine.voices.single;
      var moved = 0;
      // Twenty-five seconds of a thirty-second file, the sound card running
      // two percent slow: half a second apart by the end, unfollowed.
      for (var i = 1; i <= 250; i++) {
        now = i * 100000;
        var heard = i * 0.1 * 0.98;
        voice.at = heard;
        c.tickClockForTest();
        if ((voice.at - heard).abs() > 1e-9) moved++;
      }
      expect(moved, 0, reason: "the sound is never pulled back to the picture");
      expect(c.frame / 10, closeTo(voice.at, 0.2),
          reason: "the picture is with the sound");
      c.pause();
    });

    // A scene's clip running on past the scene stops at the turn -- brought
    // down, not cut off, which was a click.
    test("a scene's sound is faded out at the turn, not cut off", () async {
      var talk = AudioElement(const ElementBase(id: "talk", visible: false),
          clip: const MediaClip(
              timed: true,
              playlist: [MediaSource(assetId: song, name: song, length: 30)]));
      var c = with_(CanvasDocument(frameRate: 10, scenes: [
        CanvasScene(id: "one", frames: 10, elements: [talk]),
        const CanvasScene(id: "two", frames: 10),
      ]));
      c.playAll = true;
      c.play();
      for (var i = 0; i < 12; i++) {
        c.tickForTest();
        await pumpEventQueue();
      }
      expect(c.sceneAt, 1);
      var voice = engine.voices.single;
      expect(voice.alive, isFalse);
      expect(engine.softStops.map((s) => s.$1), [voice]);
      c.pause();
    });

    test("playing starts what starts by itself, on a still page too", () async {
      var doc = CanvasDocument(
        frames: 1,
        elements: [
          speaker("auto", clip: clipOf(song, autoplay: true)),
          speaker("pressed", clip: clipOf(bell)),
        ],
        master: CanvasScene(
            id: "m",
            elements: [speaker("bed", clip: clipOf(bell, autoplay: true))]),
        masterOn: true,
      );
      var c = with_(doc);
      c.play();
      await pumpEventQueue();
      expect(c.audio.playingIds, {"auto", "bed"});
    });

    test("deleting a speaker silences it", () async {
      var c =
          with_(CanvasDocument(elements: [speaker("s", clip: clipOf(song))]));
      await c.audio.play(c.document.elements.single as AudioElement);
      c.selectOnly("s");
      c.deleteSelected();
      expect(c.audio.isPlaying("s"), isFalse);
      expect(engine.last.alive, isFalse);
    });

    test("pressing the volume bar turns a muted sound back on", () async {
      var e = speaker("s",
          clip: clipOf(song).copyWith(muted: true),
          controls: const [AudioControl.volume]);
      var c = with_(CanvasDocument(elements: [e]));
      c.pressAudio(e, AudioControl.volume, volume: 0.3);
      var state = c.audioState(e);
      expect(state.volume, 0.3);
      expect(state.muted, isFalse);
    });
  });

  group("in the editor", () {
    Future<void> show(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(1400, 900);
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
        child: MaterialApp(home: Scaffold(body: child)),
      ));
      await tester.pumpAndSettle();
    }

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

    testWidgets("Add offers a speaker, and it arrives empty", (tester) async {
      var c = CanvasController(const CanvasDocument(), audioEngine: engine);
      addTearDown(c.dispose);
      await show(tester, CanvasElementsPanel(controller: c));
      await tester.tap(find.text("Audio"));
      await tester.pumpAndSettle();
      var added = c.document.elements.single;
      expect(added, isA<AudioElement>());
      expect((added as AudioElement).clip.isEmpty, isTrue);
    });

    testWidgets("turning the volume bar on widens the speaker to use it",
        (tester) async {
      var c = CanvasController(CanvasDocument(elements: [speaker("s")]),
          audioEngine: engine);
      addTearDown(c.dispose);
      c.selectOnly("s");
      await show(tester, settingsOf(c));

      var before = c.document.elements.single.width;
      await tester.tap(find.byKey(const ValueKey("audioControlvolume")));
      await tester.pumpAndSettle();
      var after = c.document.elements.single as AudioElement;
      expect(after.has(AudioControl.volume), isTrue);
      expect(after.width, greaterThan(before * 3));
      expect(audioParts(after, after.bounds).volume, isNotNull,
          reason: "wide enough that the bar is actually drawn");

      c.undo();
      expect(c.document.elements.single.width, before,
          reason: "one step, and undoable");
    });

    testWidgets("the playback settings write the clip", (tester) async {
      var c = CanvasController(
          CanvasDocument(elements: [speaker("s", clip: clipOf(song))]),
          audioEngine: engine);
      addTearDown(c.dispose);
      c.selectOnly("s");
      await show(tester, settingsOf(c));

      await tester.tap(find.byKey(const ValueKey("audioAutoplay")));
      await tester.pumpAndSettle();
      expect(
          (c.document.elements.single as AudioElement).clip.autoplay, isTrue);

      await tester.tap(find.byKey(const ValueKey("audioLoop")));
      await tester.pumpAndSettle();
      await tester.tap(find.text(MediaLoop.all.label).last);
      await tester.pumpAndSettle();
      expect((c.document.elements.single as AudioElement).clip.loop,
          MediaLoop.all);

      expect(find.byKey(const ValueKey("audioAcross")), findsNothing,
          reason: "only the master can carry a sound across pages");
    });

    testWidgets("on the master it can be told to keep playing", (tester) async {
      var c = CanvasController(
          CanvasDocument(
              scenes: const [CanvasScene(id: "one")],
              master: CanvasScene(
                  id: "m", elements: [speaker("s", clip: clipOf(song))]),
              masterOn: true,
              onMaster: true),
          audioEngine: engine);
      addTearDown(c.dispose);
      c.selectOnly("s");
      await show(tester, settingsOf(c));
      await tester.tap(find.byKey(const ValueKey("audioAcross")));
      await tester.pumpAndSettle();
      expect((c.document.elements.single as AudioElement).clip.acrossPages,
          isFalse);
    });

    testWidgets(
        "a button's sound is chosen from the speakers, the master's too",
        (tester) async {
      var button = ButtonElement(const ElementBase(id: "b"),
          action: const ButtonAction(kind: ButtonActionKind.playSound));
      var c = CanvasController(
          CanvasDocument(
            elements: [button, speaker("here")],
            master: CanvasScene(id: "m", elements: [speaker("there")]),
            masterOn: true,
          ),
          audioEngine: engine);
      addTearDown(c.dispose);
      c.selectOnly("b");
      await show(
          tester,
          ListenableBuilder(
              listenable: c,
              builder: (context, _) => CanvasControlScope(
                    maxWidth: 400,
                    child: Wrap(
                        children: buttonSettings(
                            context, c, c.selected as ButtonElement, (e) {
                      c.replaceElement(e);
                    }, () {}, () {})),
                  )));
      await tester.tap(find.byKey(const ValueKey("buttonSound")));
      await tester.pumpAndSettle();
      expect(find.text("Audio"), findsWidgets);
      expect(find.text("Audio (master)"), findsWidgets);
    });
  });

  group("pressed on the stage", () {
    const viewport = Size(1200, 800);

    Future<CanvasStageState> stage(
        WidgetTester tester, CanvasController controller) async {
      var key = GlobalKey<CanvasStageState>();
      tester.view.physicalSize = viewport;
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
            body: SizedBox(
              width: viewport.width,
              height: viewport.height,
              child: CanvasStage(key: key, controller: controller),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return key.currentState!;
    }

    /// idle lets real file I/O finish inside a widget test: one turn of the
    /// real event loop and one pump of the fake one, per step of the chain.
    Future<void> idle(WidgetTester tester) async {
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 4)));
        await tester.pump();
      }
    }

    Offset onScreen(CanvasStageState view, CanvasDocument doc, Offset point) {
      var page = view.pageRect;
      var scale = page.width / doc.size.size.width;
      return page.topLeft + point * scale;
    }

    const doc = CanvasDocument(
        size: CanvasSize(ratio: CanvasRatio.wide, width: 1280), frames: 10);

    testWidgets("a selected speaker plays when pressed, and moves when dragged",
        (tester) async {
      var e = speaker("s",
          clip: clipOf(song),
          controls: const [AudioControl.playPause, AudioControl.volume],
          at: const Rect.fromLTWH(200, 200, 400, 80));
      var c =
          CanvasController(doc.copyWith(elements: [e]), audioEngine: engine);
      c.selectOnly("s");
      var view = await stage(tester, c);
      var parts = audioParts(e, e.bounds);

      await tester.tapAt(onScreen(view, c.document, parts.icon.center));
      await idle(tester);
      expect(c.audio.isPlaying("s"), isTrue);

      // Three quarters of the way along the bar.
      var bar = parts.volume!;
      var at = Offset(bar.left + bar.width * 0.75, bar.center.dy);
      await tester.tapAt(onScreen(view, c.document, at));
      await tester.pump();
      expect(c.audioState(e).volume, closeTo(volumeAt(bar, at.dx), 0.02));

      // A drag from the icon is a move, not a press.
      var before = c.document.elements.single.x;
      await tester.dragFrom(
          onScreen(view, c.document, parts.icon.center), const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(c.document.elements.single.x, greaterThan(before));
      expect(c.audio.isPlaying("s"), isTrue,
          reason: "the drag did not press it again");

      c.stopAudio();
      c.dispose();
    });

    testWidgets("a speaker on the master is pressed from a page",
        (tester) async {
      var music = speaker("music",
          clip: clipOf(song), at: const Rect.fromLTWH(1100, 40, 80, 80));
      var c = CanvasController(
          doc.copyWith(
            scenes: const [CanvasScene(id: "one")],
            master: CanvasScene(id: "m", elements: [music]),
            masterOn: true,
          ),
          audioEngine: engine);
      var view = await stage(tester, c);

      await tester.tapAt(onScreen(
          view, c.document, audioParts(music, music.bounds).icon.center));
      await idle(tester);
      expect(c.audio.isPlaying("music"), isTrue);
      expect(c.selection, isEmpty, reason: "pressed, not selected");

      c.stopAudio();
      c.dispose();
    });
  });
}
