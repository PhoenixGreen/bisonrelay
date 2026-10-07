import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/scene_strip.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_scene_strip_test.dart is the row of scenes between the ruler and the
// keyframes while Play runs the whole document: there only then, a box per
// scene on the ruler's own scale -- so the ruler's frames for a scene run over
// its box, and zooming zooms both -- the one playing lit, and the grips
// between the boxes, which move the join between two scenes.

void main() {
  Future<CanvasController> show(WidgetTester tester,
      {List<int> lengths = const [100, 50, 80]}) async {
    var c = CanvasController(
        CanvasDocument(frameRate: 10, scenes: [
          for (var (i, f) in lengths.indexed) CanvasScene(id: "s$i", frames: f),
        ]),
        audioEngine: FakeEngine(const {}));
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(1200, 700);
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
            child: CanvasTimeline(controller: c, height: timelineHeight + 120),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return c;
  }

  List<int> lengths(CanvasController c) => [for (var s in c.scenes) s.frames];

  Future<void> playAll(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey("playAll")));
    await tester.pumpAndSettle();
  }

  Rect rectOf(WidgetTester tester, String key) =>
      tester.getRect(find.byKey(ValueKey(key)));

  /// perFrame is how many pixels a frame is across the ruler, showing the
  /// whole run.
  double perFrame(WidgetTester tester, CanvasController c) =>
      rectOf(tester, "keyframeStrip").width / c.document.sequenceFrames;

  testWidgets("is there only while Play runs every scene, under the ruler",
      (tester) async {
    var c = await show(tester);
    var before = tester.getSize(find.byType(CanvasTimeline)).height;
    expect(find.byType(CanvasSceneStrip), findsNothing);

    await playAll(tester);
    expect(c.playAll, isTrue);
    expect(find.byType(CanvasSceneStrip), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(ValueKey("sceneBox$i")), findsOneWidget);
    }
    expect(find.text("Scenes 3"), findsOneWidget);
    expect(tester.getSize(find.byType(CanvasTimeline)).height,
        closeTo(before + sceneStripHeight, 0.5),
        reason: "the timeline grows by the strip, the channels keep theirs");

    // Between the ruler and the keyframes.
    var strip = rectOf(tester, "keyframeStrip");
    var box = rectOf(tester, "sceneBox0");
    expect(box.top, greaterThan(strip.top + 20), reason: "under the ruler");
    var keyframes = tester.getRect(find.text("Keyframes"));
    expect(keyframes.top, greaterThan(box.bottom),
        reason: "over the keyframes");
    expect(tester.takeException(), isNull);

    await playAll(tester);
    expect(find.byType(CanvasSceneStrip), findsNothing);
  });

  testWidgets("each scene sits under its own frames of the ruler",
      (tester) async {
    var c = await show(tester);
    await playAll(tester);
    var strip = rectOf(tester, "keyframeStrip");
    var px = perFrame(tester, c);
    // The ruler runs the whole document: 230 frames across the strip. A box
    // starts half a grip after its first frame.
    for (var (i, start) in [0, 100, 150].indexed) {
      var box = rectOf(tester, "sceneBox$i");
      expect(box.left, closeTo(strip.left + start * px + 4, 1),
          reason: "scene $i starts at frame $start of the run");
    }
    expect(rectOf(tester, "sceneBox0").width + 8,
        closeTo((rectOf(tester, "sceneBox1").width + 8) * 2, 1),
        reason: "100 frames against 50");
    expect(tester.widget<Text>(find.byKey(const ValueKey("sceneFrames0"))).data,
        "100");
  });

  testWidgets("zooming zooms the scenes with the ruler", (tester) async {
    await show(tester);
    await playAll(tester);
    var wide = rectOf(tester, "sceneBox1").width + 8;
    await tester.tap(find.byKey(const ValueKey("timelineZoomIn")));
    await tester.pumpAndSettle();
    expect(rectOf(tester, "sceneBox1").width + 8, closeTo(wide * 2, 1),
        reason: "twice the pixels per frame for the box as for the ruler");
  });

  testWidgets("the ruler over another scene goes to it, at that frame",
      (tester) async {
    var c = await show(tester);
    await playAll(tester);
    var strip = rectOf(tester, "keyframeStrip");
    var px = perFrame(tester, c);
    // Frame 120 of the run is frame 20 of the second scene.
    await tester.tapAt(Offset(strip.left + 120 * px, strip.top + 5));
    await tester.pumpAndSettle();
    expect(c.sceneAt, 1);
    expect(c.frame, closeTo(20, 1));
  });

  testWidgets("a click on a box opens its scene", (tester) async {
    var c = await show(tester);
    await playAll(tester);
    await tester.tap(find.byKey(const ValueKey("sceneBox2")));
    await tester.pumpAndSettle();
    expect(c.sceneAt, 2);
  });

  testWidgets("the grip between two scenes moves the join", (tester) async {
    var c = await show(tester);
    await playAll(tester);
    var px = perFrame(tester, c);

    await tester.drag(
        find.byKey(const ValueKey("sceneGrip0")), Offset(20 * px, 0));
    await tester.pumpAndSettle();
    expect(lengths(c), [120, 30, 80],
        reason: "what the first gains the second gives");

    c.undo();
    await tester.pumpAndSettle();
    expect(lengths(c), [100, 50, 80], reason: "one drag, one undo");

    // Never past a single frame either way.
    await tester.drag(
        find.byKey(const ValueKey("sceneGrip0")), Offset(500 * px, 0));
    await tester.pumpAndSettle();
    expect(lengths(c), [149, 1, 80]);
    expect(tester.takeException(), isNull,
        reason: "a scene of one frame is a sliver, not an overflow");
  });

  testWidgets("the grip after the last scene lengthens it alone",
      (tester) async {
    var c = await show(tester);
    await playAll(tester);
    var px = perFrame(tester, c);
    await tester.drag(
        find.byKey(const ValueKey("sceneGrip2")), Offset(-30 * px, 0));
    await tester.pumpAndSettle();
    expect(lengths(c), [100, 50, 50]);
  });

  testWidgets("playing lights the scene it has reached", (tester) async {
    var c = await show(tester, lengths: [5, 5, 5]);
    await playAll(tester);
    c.play();
    for (var i = 0; i < 7; i++) {
      c.tickForTest();
    }
    await tester.pump();
    expect(c.sceneAt, 1, reason: "seven frames into five, five and five");
    var box = tester.widget<Container>(find
        .descendant(
            of: find.byKey(const ValueKey("sceneBox1")),
            matching: find.byType(Container))
        .first);
    var border = (box.decoration as BoxDecoration).border as Border;
    expect(border.top.width, 1.5, reason: "the one playing is lit");
    c.pause();
  });

  group("playing every scene", () {
    CanvasController run(List<int> lengths) {
      var c = CanvasController(
          CanvasDocument(frameRate: 10, scenes: [
            for (var (i, f) in lengths.indexed)
              CanvasScene(id: "s$i", frames: f),
          ]),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.playAll = true;
      return c;
    }

    test("starts from the playhead, wherever it was put", () {
      var c = run([100, 50, 80]);
      c.goToScene(1);
      c.frame = 20;
      c.play();
      c.tickForTest();
      expect([c.sceneAt, c.frame], [1, 21], reason: "on from the playhead");
      expect(c.previewAt, 121, reason: "frame 120 of the run, and one on");
      c.pause();
    });

    // Paused and moved to edit, the next Play goes on from where it was
    // moved to -- not from where the last run stopped.
    test("paused, moved and played again goes on from the move", () {
      var c = run([100, 50, 80]);
      c.play();
      for (var i = 0; i < 30; i++) {
        c.tickForTest();
      }
      c.pause();
      expect(c.previewAt, isNull,
          reason: "stopped, the canvas shows the scene at the playhead");
      expect([c.sceneAt, c.frame], [0, 30]);

      c.frame = 5;
      c.play();
      c.tickForTest();
      expect([c.sceneAt, c.frame], [0, 6]);
      c.pause();
    });

    test("at the very end, starts again from the beginning", () {
      var c = run([10, 10]);
      c.goToScene(1);
      c.frame = 9;
      c.play();
      c.tickForTest();
      expect([c.sceneAt, c.frame], [0, 1]);
      c.pause();
    });
  });

  group("the ruler", () {
    // Every scene's frames, numbered on through the run rather than starting
    // again at each scene, from one.
    test("numbers the whole run where the timeline runs", () {
      // Frame 0 of the second scene, which starts 100 frames in.
      expect(rulerNumber(0, 100), 101);
      expect(rulerNumber(0, 0), 1, reason: "the first frame is 1");
    });

    test("writes numbers on whole seconds, never crowded", () {
      for (var px in [0.05, 0.5, 2.0, 8.0, 40.0]) {
        var (major, medium, minor) = rulerSteps(px, 24);
        expect(major % 24, 0, reason: "on a whole second at $px px a frame");
        expect(major * px, greaterThanOrEqualTo(90),
            reason: "room around each number at $px px a frame");
        if (medium != null) expect(major % medium, 0);
        if (minor != null && medium != null) expect(medium % minor, 0);
      }
      var (_, medium, _) = rulerSteps(40, 24);
      expect(medium, 1, reason: "close in, a tick every frame");
    });
  });

  group("channels by scene", () {
    AudioElement sound(String id, {int at = 0}) =>
        AudioElement(ElementBase(id: id, visible: false),
            clip: MediaClip(
                timed: true,
                at: at,
                playlist: const [MediaSource(assetId: "x.mp3", length: 2)]));

    CanvasDocument doc() => CanvasDocument(
          frameRate: 10,
          scenes: [
            CanvasScene(id: "one", frames: 100, elements: [sound("a")]),
            CanvasScene(id: "two", frames: 50, elements: [sound("b", at: 5)]),
            CanvasScene(id: "three", frames: 50, elements: [sound("c")]),
          ],
          master: CanvasScene(id: "m", elements: [sound("music")]),
          masterOn: true,
        );

    List<String> order(CanvasController c) =>
        [for (var ch in c.timelineChannels) ch.first.element.id];

    test("each channel is labelled with its scene: M for the master", () {
      var c = CanvasController(doc(), audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.goToScene(1);
      var labels = {
        for (var ch in c.timelineChannels) ch.first.element.id: ch.sceneLabel
      };
      expect(labels, {"b": "S2", "music": "M"},
          reason: "only this scene's and the master's, as it was");
    });

    test("Play all scenes shows every scene's, in place, to be changed", () {
      var c = CanvasController(doc(), audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.goToScene(1);
      c.playAll = true;
      expect(c.allChannels, isTrue);
      var other = c.timedLanes.firstWhere((l) => l.element.id == "a");
      expect(other.sceneLabel, "S1");
      expect(other.editable, isTrue, reason: "changed from here");
      expect(other.offset, 100,
          reason: "scene one is a hundred frames before scene two");

      c.playAll = false;
      expect(c.timedLanes.any((l) => l.element.id == "a"), isFalse);
    });

    AudioElement lane(CanvasController c, String id) =>
        c.timedLanes.firstWhere((l) => l.element.id == id).element
            as AudioElement;
    AudioElement onScene(CanvasController c, int scene, String id) =>
        c.document.allScenes[scene].elements.firstWhere((e) => e.id == id)
            as AudioElement;

    test("another scene's clip is moved on that scene, and held to it", () {
      var c = CanvasController(doc(), audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.playAll = true; // scene one open
      var b = lane(c, "b");
      c.setTimedClip(b, b.clip.copyWith(at: 30));
      expect(onScene(c, 1, "b").clip.at, 30, reason: "written on scene two");
      expect(c.sceneAt, 0, reason: "and the scene open stays open");

      c.setTimedClip(b, b.clip.copyWith(at: 400));
      expect(onScene(c, 1, "b").clip.at, 49,
          reason: "no later than scene two's last frame");
      c.undo();
      expect(onScene(c, 1, "b").clip.at, 30, reason: "an undo step like any");
    });

    test("the master's clip is moved anywhere along the run", () {
      var c = CanvasController(doc(), audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.playAll = true;
      c.goToScene(1);
      var music = c.timedLanes.firstWhere((l) => l.element.id == "music");
      expect(music.editable, isTrue, reason: "from a scene, while all play");
      var e = music.element as AudioElement;
      c.setTimedClip(e, e.clip.copyWith(at: 180));
      var onMaster = c.document.master!.elements.single as AudioElement;
      expect(onMaster.clip.at, 180, reason: "past any one scene's end");

      c.playAll = false;
      expect(c.timedLanes.firstWhere((l) => l.element.id == "music").editable,
          isFalse,
          reason: "one scene at a time, the master's is changed there");
    });

    test("another scene's clip is cut on that scene", () {
      var c = CanvasController(doc(), audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.playAll = true; // scene one open; scene two starts 100 frames in
      var b = c.timedLanes.firstWhere((l) => l.element.id == "b");
      // Ten frames into scene two's clip, which starts at its frame 5.
      // Scene two's clip starts at its frame 5: frame 105 of scene one's
      // timeline. Ten frames into it is 115.
      expect(c.splitClip(b, 115), isTrue);
      expect(c.document.allScenes[1].elements, hasLength(2),
          reason: "both halves on scene two");
      expect(c.document.allScenes[0].elements, hasLength(1));
    });

    test("a clip goes only onto a channel of its own canvas", () {
      var c = CanvasController(doc(), audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.playAll = true;
      var a = c.timedLanes.firstWhere((l) => l.element.id == "a");
      var master = c.timelineChannels.firstWhere((ch) => ch.sceneLabel == "M");
      c.moveClipToChannel(a, master);
      expect(onScene(c, 0, "a").clip.channel, isNot(master.key));
    });

    testWidgets("another scene's channel is picked and its clip dragged",
        (tester) async {
      var c = CanvasController(doc(), audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1200, 800);
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
              child:
                  CanvasTimeline(controller: c, height: timelineHeight + 260),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("playAll")));
      await tester.pumpAndSettle();

      var three = c.timelineChannels.firstWhere((ch) => ch.sceneLabel == "S3");
      // On its label, clear of its buttons.
      var strip =
          tester.getRect(find.byKey(ValueKey("channelStrip-${three.key}")));
      await tester.tapAt(Offset(strip.left + 16, strip.center.dy));
      // Past the wait for a second click, which renames.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(c.selectedChannel, three.key, reason: "picked from scene one");

      // Scene three's clip: run frames 150 to 170, of 200.
      var ruler = tester.getRect(find.byKey(const ValueKey("keyframeStrip")));
      var px = ruler.width / c.document.sequenceFrames;
      var row = tester.getRect(find.byKey(ValueKey("lane-${three.key}")));
      await tester.dragFrom(
          Offset(ruler.left + 160 * px, row.top + row.height * 0.85),
          Offset(10 * px, 0));
      await tester.pumpAndSettle();
      expect(onScene(c, 2, "c").clip.at, closeTo(10, 1),
          reason: "moved along scene three");
      expect(c.clipSelection, contains("c"),
          reason: "and picked, though it is on another scene");
      expect(c.sceneAt, 0, reason: "without leaving scene one");
      expect(tester.takeException(), isNull);
    });

    // Picked on the timeline, a clip on another canvas is lit like one on
    // this canvas -- and moved with the others picked with it.
    test("clips on other canvases are picked, lit, and moved together", () {
      var c = CanvasController(doc(), audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.playAll = true; // scene one open
      c.pickClip("b");
      expect(c.clipSelection, {"b"});
      expect(c.selection, isEmpty, reason: "the selection is this canvas's");

      c.pickClip("a", toggle: true);
      c.pickClip("music", toggle: true);
      expect(c.clipSelection, {"a", "b", "music"});

      c.pickClip("a");
      expect(c.clipSelection, {"a"}, reason: "one picked on its own");

      c.pickClips({"a", "c"});
      expect(c.selection, {"a"});
      expect(c.clipSelection, {"a", "c"});

      c.playAll = false;
      expect(c.clipSelection, {"a"},
          reason: "other canvases are out of reach with one scene");
      c.clearSelection();
      expect(c.clipSelection, isEmpty);
    });

    test("listed S1, S2, S3 and the master last, whichever scene is open", () {
      var c = CanvasController(doc(), audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.playAll = true;
      c.goToScene(1);
      expect(order(c), ["a", "b", "c", "music"]);
      c.goToScene(2);
      expect(order(c), ["a", "b", "c", "music"],
          reason: "the scene being edited does not jump to the top");
    });

    test("a channel moved stays where it was put", () {
      var c = CanvasController(doc(), audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.playAll = true;
      var music = c.timelineChannels.last.key;
      c.moveChannel(music, 0);
      expect(order(c), ["music", "a", "b", "c"]);
      c.goToScene(2);
      expect(order(c), ["music", "a", "b", "c"]);

      // Only this scene's and the master's with every scene off: the two
      // keep the order they were put in.
      c.playAll = false;
      expect(order(c), ["music", "c"]);
    });

    testWidgets("a strip dragged down the list moves its channel",
        (tester) async {
      var c = CanvasController(doc(), audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1200, 800);
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
              child:
                  CanvasTimeline(controller: c, height: timelineHeight + 260),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("timelineAllChannels")), findsNothing,
          reason: "Play all scenes is the switch");
      expect(tester.getSize(find.byKey(const ValueKey("timelineZoomIn"))).width,
          greaterThanOrEqualTo(24),
          reason: "the zoom buttons are big enough to hit");

      await tester.tap(find.byKey(const ValueKey("playAll")));
      await tester.pumpAndSettle();
      Finder strip(String id) => find.byKey(ValueKey(
          "channelStrip-${c.timelineChannels.firstWhere((ch) => ch.first.element.id == id).key}"));
      expect(strip("c"), findsOneWidget, reason: "every scene's channels");

      // S1's strip, from its middle to below S3's.
      var from = tester.getCenter(strip("a"));
      var below = tester.getRect(strip("c")).bottom + 4;
      var gesture = await tester.startGesture(from);
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveTo(Offset(from.dx, below));
      await tester.pump();
      // Lit across the whole of it, strip and lane, and already shown where
      // it is going.
      var lit = tester.getRect(find.byKey(const ValueKey("channelMoving")));
      expect(lit.left, lessThanOrEqualTo(tester.getRect(strip("b")).left),
          reason: "over its strip");
      expect(lit.width, greaterThan(800), reason: "and its lane");
      expect(lit.top, greaterThan(tester.getRect(strip("c")).top),
          reason: "under S3 already, while it is dragged");
      await gesture.up();
      await tester.pumpAndSettle();
      expect(order(c), ["b", "c", "a", "music"]);
      expect(tester.takeException(), isNull);
    });
  });

  // The playhead keeps time by the clock: a late tick catches up, so the
  // picture and the sound -- which plays on the sound card's own clock --
  // stay together instead of drifting apart until the sound is pulled back.
  group("the playhead keeps time", () {
    test("a late tick moves on by the frames that have passed", () {
      var c = CanvasController(const CanvasDocument(frames: 400, frameRate: 10),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      var now = 0;
      c.clockForTest = () => now;
      c.play();
      c.tickClockForTest();
      expect(c.frame, 0, reason: "no time, no frames");

      now = 350000; // a tick a third of a second late
      c.tickClockForTest();
      expect(c.frame, 3);

      now = 400000;
      c.tickClockForTest();
      expect(c.frame, 4, reason: "and on time again after");

      // A stall of seconds is let go, not raced through.
      now = 10400000;
      c.tickClockForTest();
      expect(c.frame, 10);
      now = 10500000;
      c.tickClockForTest();
      expect(c.frame, 11, reason: "carrying on from the clock");
      c.pause();
    });
  });

  // With every scene playing, the transport goes across them too.
  group("the transport across scenes", () {
    CanvasController run() {
      var c = CanvasController(
          CanvasDocument(frameRate: 10, scenes: const [
            CanvasScene(id: "a", frames: 10),
            CanvasScene(id: "b", frames: 20),
          ]),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.playAll = true;
      return c;
    }

    test("a frame back from a scene's first is the last of the one before", () {
      var c = run();
      c.goToScene(1);
      c.frame = 0;
      c.stepFrame(-1);
      expect([c.sceneAt, c.frame], [0, 9]);
      c.stepFrame(1);
      expect([c.sceneAt, c.frame], [1, 0], reason: "and on again");
    });

    test("back to the start: this scene's, then the one before's", () {
      var c = run();
      c.goToScene(1);
      c.frame = 12;
      c.rewind();
      expect([c.sceneAt, c.frame], [1, 0]);
      c.rewind();
      expect([c.sceneAt, c.frame], [0, 0]);
    });

    test("with one scene at a time, a scene's ends are its own", () {
      var c = run();
      c.playAll = false;
      c.goToScene(1);
      c.frame = 0;
      c.stepFrame(-1);
      expect([c.sceneAt, c.frame], [1, 0]);
      c.rewind();
      expect([c.sceneAt, c.frame], [1, 0]);
    });
  });
}
