import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
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
}
