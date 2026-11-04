import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
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
  testWidgets("an element with clips has its row, the clip on it",
      (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey("motionRow-a")), findsOneWidget);
    expect(find.text("Logo"), findsOneWidget);
  });

  testWidgets("a click opens the clip in the Animation panel", (tester) async {
    var c = await pump(tester);
    var p = c.motionOf("a").placed.single;
    await tester.tapAt(at(tester, c, 2.3));
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.pickedPlacement, p.id);
    expect(c.pickedMotion, p.clip);
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
    await tester.tap(find.byKey(const ValueKey("makeMotion-Pop")));
    await tester.pumpAndSettle();
    var placed = c.motionOf("a").placed;
    expect(placed, hasLength(2));
    var made = placed.last;
    expect(c.motionOf("a").clip(made.clip)!.name, "Pop");
    expect(c.spanOf(made.id)!.start, closeTo(6, 0.3));
    expect(c.animationOpen, isTrue, reason: "opened to be shaped");
  });
}
