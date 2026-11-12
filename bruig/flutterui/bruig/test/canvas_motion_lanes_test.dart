import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_lanes.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// The elements' rows on the timeline: a placed clip opened by a click,
// moved by a drag, stretched by its end, cut with the knife -- and a clip
// made by a double-click on an empty stretch.

Future<CanvasController> pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  var c =
      CanvasController(CanvasDocument(frames: 240, frameRate: 24, elements: [
    ShapeElement(const ElementBase(
        id: "a", name: "Logo", x: 10, y: 10, width: 50, height: 50)),
  ]));
  addTearDown(c.dispose);
  var clip = c.newClip("a", preset: presetNamed("Jump")); // 0.7 s
  c.placeClip("a", clip, seconds: 2);
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
                child: CanvasTimeline(controller: c, height: 400)))),
  ));
  await tester.pumpAndSettle();
  return c;
}

/// at is where [seconds] is on the lanes, in the middle of [lane].
Offset at(WidgetTester tester, CanvasController c, double seconds,
    {int lane = 0}) {
  var box = tester.getRect(find.byKey(const ValueKey("motionLanesPaint-a")));
  var frames = c.document.frames;
  return Offset(box.left + box.width * seconds * 24 / frames,
      box.top + 2 + 22 * lane + 11);
}

void main() {
  // Ken, 2026-11-11: an arrival, an exit and a loop on one layer drew over
  // each other, and the row's arrow opened nothing new.
  group("overlapping clips", () {
    CanvasController withThree() {
      var c = CanvasController(const CanvasDocument(frames: 240, frameRate: 24)
          .addElement(ShapeElement(const ElementBase(id: "s"))));
      addTearDown(c.dispose);
      var arrive = c.newClip("s", preset: presetNamed("Fade up")!);
      var leave = c.newClip("s", preset: presetNamed("Fade out")!);
      var loop = c.newClip("s", preset: presetNamed("Float")!);
      c.placeClip("s", arrive, seconds: 0, layer: 0);
      c.placeClip("s", leave, seconds: 0.5, layer: 0);
      c.placeClip("s", loop, seconds: 4, layer: 0);
      return c;
    }

    test("each that overlaps another is stacked under it", () {
      var c = withThree();
      var e = c.document.elementById("s")!;
      var times = motionTimesOf(c.document);
      var stacks = clipStacks(e.base.motion.placed, times);
      var placed = e.base.motion.placed;
      expect([for (var p in placed) stacks[p.id]], [0, 1, 0],
          reason: "the exit starts before the arrival ends; the loop after");
      expect(
          motionTracksOf(e, times),
          [
            (layer: 0, stack: 0),
            (layer: 0, stack: 1),
            (layer: 1, stack: 0),
          ],
          reason: "a lane for each stack, and the next layer's to drop on");
    });

    // Ken, 2026-11-12: folded (small) rows lay their clips over each other,
    // each a step lower; open rows (medium, large, or opened) a lane each.
    test("open, no two drawn over each other; folded, each a step lower", () {
      var c = withThree();
      var e = c.document.elementById("s")!;
      var times = motionTimesOf(c.document);
      for (var folded in [true, false]) {
        var placed = e.base.motion.placed;
        var stacks = clipStacks(placed, times, together: folded);
        var rects = [
          for (var p in placed)
            motionClipRect(p,
                folded: folded,
                tracks: folded ? const [] : motionTracksOf(e, times),
                stacks: stacks,
                lane: 24,
                y: 0,
                rowHeight: 100,
                left: times.span(p.id)!.start * 50,
                right: times.span(p.id)!.end * 50)!
        ];
        if (!folded) {
          expect(rects[0].overlaps(rects[1]), isFalse, reason: "a lane each");
        }
        expect(rects[1].top, greaterThan(rects[0].top),
            reason: "the later one under the first");
      }
    });
  });

  testWidgets("an element with clips has its row, the clip on it",
      (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey("motionRow-a")), findsOneWidget);
    expect(find.text("Logo"), findsOneWidget);
  });

  // Ken, 2026-11-08: a click picks it; only a double-click opens the
  // Chain, unless the Chain is out already.
  testWidgets("a click picks the clip; a double-click opens the Chain",
      (tester) async {
    var c = await pump(tester);
    var p = c.motionOf("a").placed.single;
    await tester.tapAt(at(tester, c, 2.3));
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.pickedPlacement, p.id);
    expect(c.pickedMotion, p.clip);
    expect(c.animationOpen, isFalse, reason: "a single click, picked only");
    await tester.tapAt(at(tester, c, 2.3));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(at(tester, c, 2.3));
    await tester.pumpAndSettle();
    expect(c.animationOpen, isTrue);
  });

  testWidgets("dragged, it moves along; by its end, it is stretched",
      (tester) async {
    var c = await pump(tester);
    var p = c.motionOf("a").placed.single;
    await tester.timedDragFrom(
        at(tester, c, 2.3),
        Offset(
            tester
                    .getRect(find.byKey(const ValueKey("motionLanesPaint-a")))
                    .width *
                24 /
                240,
            0),
        const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(c.spanOf(p.id)!.start, closeTo(3, 0.3));
    var end = c.spanOf(p.id)!.end;
    await tester.timedDragFrom(
        at(tester, c, end) - const Offset(2, 0),
        Offset(
            tester
                    .getRect(find.byKey(const ValueKey("motionLanesPaint-a")))
                    .width *
                24 /
                240,
            0),
        const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(c.spanOf(p.id)!.end, closeTo(end + 1, 0.3));
    expect(c.spanOf(p.id)!.speed, lessThan(1), reason: "retimed to fill it");
  });

  // Ken, 2026-11-11: "click and drag over multiple clips on the timeline to
  // select multiple audio/motion clips and then be able to move them".
  testWidgets("a box picks clips on several rows; moved and deleted together",
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var c =
        CanvasController(CanvasDocument(frames: 240, frameRate: 24, elements: [
      ShapeElement(
          const ElementBase(id: "a", name: "A", width: 50, height: 50)),
      ShapeElement(
          const ElementBase(id: "b", name: "B", width: 50, height: 50)),
      AudioElement(const ElementBase(id: "snd", visible: false),
          clip: const MediaClip(
              timed: true,
              at: 48,
              channel: "ch1",
              channelName: "Sound",
              playlist: [MediaSource(assetId: "s.mp3", length: 1)])),
    ]));
    addTearDown(c.dispose);
    for (var id in ["a", "b"]) {
      c.placeClip(id, c.newClip(id, preset: presetNamed("Jump")), seconds: 2);
    }
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
                  child: CanvasTimeline(controller: c, height: 500)))),
    ));
    await tester.pumpAndSettle();
    Offset on(String row, double seconds) {
      var box = tester.getRect(find.byKey(ValueKey("motionLanesPaint-$row")));
      return Offset(box.left + box.width * seconds * 24 / 240, box.top + 12);
    }

    // From an empty spot on A's row to past B's clip.
    var from = on("a", 0.5), to = on("b", 3.5) + const Offset(0, 6);
    var g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await g.moveTo(from + const Offset(20, 4));
    await tester.pump();
    await g.moveTo(to);
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    var pa = c.motionOf("a").placed.single, pb = c.motionOf("b").placed.single;
    expect(c.motionPicks, {("a", pa.id), ("b", pb.id)}, reason: "both picked");
    expect(c.selection, isNot(contains("a")),
        reason: "the clips are picked, not their elements");

    // The sound picked with them, then one clip dragged a second on.
    c.pickClips({"snd"});
    await tester.pump();
    var width =
        tester.getRect(find.byKey(const ValueKey("motionLanesPaint-a"))).width;
    await tester.timedDragFrom(on("a", 2.3), Offset(width * 24 / 240, 0),
        const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(c.spanOf(pa.id)!.start, closeTo(3, 0.3));
    expect(c.spanOf(pb.id)!.start, closeTo(c.spanOf(pa.id)!.start, 1e-6),
        reason: "the other clip by as much");
    expect(
        (c.document.elementById("snd") as AudioElement).clip.at, closeTo(72, 7),
        reason: "the sound by as much");

    // Delete: the clips and the sound; not the elements.
    c.pickMotions({("a", pa.id), ("b", pb.id)});
    c.pickClips({"snd"});
    c.deleteSelected();
    expect(c.motionOf("a").placed, isEmpty);
    expect(c.motionOf("b").placed, isEmpty);
    expect(c.document.elementById("a"), isNotNull);
    expect(c.document.elementById("snd"), isNull);
  });

  testWidgets("with the knife, a click cuts it in two", (tester) async {
    var c = await pump(tester);
    c.timelineTool = TimelineTool.knife;
    await tester.pump();
    await tester.tapAt(at(tester, c, 2.4));
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.motionOf("a").placed, hasLength(2));
  });

  testWidgets("a double-click on an empty stretch makes a clip there",
      (tester) async {
    var c = await pump(tester);
    var spot = at(tester, c, 6);
    await tester.tapAt(spot);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(spot);
    await tester.pumpAndSettle();
    // A short clip there at once, no list to pick from (Ken).
    var placed = c.motionOf("a").placed;
    expect(placed, hasLength(2));
    var made = placed.last;
    expect(c.motionOf("a").clip(made.clip)!.length, 1);
    expect(c.spanOf(made.id)!.start, closeTo(6, 0.3));
    expect(c.pickedPlacement, made.id, reason: "picked, to be set up");
    expect(c.animationOpen, isFalse,
        reason: "double-clicked again, it opens in the Chain");
  });

  // Ken, 2026-11-12: small rows overlay their layers; medium, large and a
  // row opened show a lane each; a row's bottom edge drags it taller.
  testWidgets("small overlays, medium a lane a layer, and the grip",
      (tester) async {
    var c = await pump(tester);
    var clip = c.newClip("a", preset: presetNamed("Jump"));
    c.placeClip("a", clip, seconds: 2.2); // overlaps the first
    await tester.pumpAndSettle();
    double row() =>
        tester.getSize(find.byKey(const ValueKey("motionRow-a"))).height;
    expect(c.laneSize, isNot(0));
    expect(c.rowFolded("a"), isFalse, reason: "open at medium");
    var open = row();
    while (c.laneSize != 0) {
      c.nextLaneSize();
    }
    await tester.pumpAndSettle();
    expect(c.rowFolded("a"), isTrue, reason: "folded, overlaid, at small");
    expect(row(), lessThan(open));
    c.toggleRowFold("a");
    await tester.pumpAndSettle();
    expect(row(), open, reason: "opened at small: a lane a layer");
    var was = row();
    await tester.drag(
        find.byKey(const ValueKey("motionGrip-a")), const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(row(), closeTo(was + 40, 1));
    expect(tester.takeException(), isNull);
  });
}
