import 'dart:ui';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Color, Offset, Rect;
import 'package:provider/provider.dart';
import 'package:bruig/plugin_system/canvas/model/vector_cut.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_shapes.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_vector_cut_test.dart is the knife's geometry: a shape cut along a
// line into pieces that cover what it covered, overlap nowhere, and stay one
// shape.

/// square is a filled 100-wide square at the origin.
VectorShape square() =>
    shapeOf(VectorShapeKind.box, const Rect.fromLTWH(0, 0, 100, 100),
        fill: const Color(0xFF000000));

/// ring is a square with a square hole in the middle, both run the same
/// way round, filled even-odd -- as a drawing from a file often is.
VectorShape ring() {
  VectorPath box(double a, double b) => VectorPath([
        VectorNode(a, a),
        VectorNode(b, a),
        VectorNode(b, b),
        VectorNode(a, b),
      ], closed: true);
  return VectorShape(
      paths: [box(0, 100), box(30, 70)],
      fill: const Color(0xFF000000),
      evenOdd: true);
}

/// coverage is, at each point of a grid over [-10, 110], how many of
/// [shape]'s parts cover it.
List<int> coverage(VectorShape shape) {
  var parts = partsOf(shape).toList();
  var paths = [for (var p in parts) partPath(shape, p)];
  return [
    for (var y = -10.0; y <= 110; y += 1.7)
      for (var x = -10.0; x <= 110; x += 1.7)
        paths.where((p) => p.contains(Offset(x, y))).length,
  ];
}

List<int> covered(VectorShape shape) => [
      for (var y = -10.0; y <= 110; y += 1.7)
        for (var x = -10.0; x <= 110; x += 1.7)
          shape.path.contains(Offset(x, y)) ? 1 : 0,
    ];

/// same is whether the pieces cover what [before] covered and nothing
/// twice: a point at most [slack] grid points off, for the gap.
void expectSameCover(VectorShape before, VectorShape after, {int slack = 80}) {
  var was = covered(before), now = coverage(after);
  expect(now.where((c) => c > 1), isEmpty, reason: "no overlap");
  var differ = 0;
  for (var i = 0; i < was.length; i++) {
    if ((was[i] > 0) != (now[i] > 0)) differ++;
  }
  expect(differ, lessThan(slack), reason: "the same area, less the gap");
}

void main() {
  test("a line straight across a square: two pieces, one shape", () {
    var cut = cutShape(square(), const [Offset(50, -20), Offset(50, 120)], 1)!;
    expect(partsOf(cut).length, 2);
    expect(cut.paths.length, 2);
    expect(cut.paths.every((r) => r.closed), isTrue);
    expectSameCover(square(), cut);
    // Each on its own side of the cut, a gap between.
    var sides = [
      for (var p in partsOf(cut)) partPath(cut, p).getBounds(),
    ]..sort((a, b) => a.left.compareTo(b.left));
    expect(sides[0].right, closeTo(49.5, 0.01));
    expect(sides[1].left, closeTo(50.5, 0.01));
  });

  test("through a hole: each half takes its half of the hole", () {
    var cut = cutShape(ring(), const [Offset(50, -20), Offset(50, 120)], 1)!;
    expect(partsOf(cut).length, 2);
    expectSameCover(ring(), cut);
    expect(cut.path.contains(const Offset(40, 50)), isFalse,
        reason: "the hole is still a hole");
  });

  test("across a corner, missing the hole: the hole stays with the rest", () {
    var cut = cutShape(ring(), const [Offset(-10, 20), Offset(20, -10)], 1)!;
    expect(partsOf(cut).length, 2);
    expectSameCover(ring(), cut);
    var big = partsOf(cut)
        .firstWhere((p) => cut.paths.where((r) => r.part == p).length == 2);
    expect(partPath(cut, big).contains(const Offset(50, 50)), isFalse,
        reason: "the piece with the hole in it");
  });

  test("a curve stays a curve, with a point at each end of the cut", () {
    var circle = shapeOf(
        VectorShapeKind.circle, const Rect.fromLTWH(0, 0, 100, 100),
        fill: const Color(0xFF000000));
    var cut = cutShape(circle, const [Offset(30, -20), Offset(30, 120)], 1)!;
    expect(partsOf(cut).length, 2);
    expectSameCover(circle, cut);
    var nodes = cut.paths.fold(0, (n, r) => n + r.nodes.length);
    expect(nodes, lessThan(16), reason: "not flattened into many points");
  });

  test("a freehand zigzag cuts along the zigzag", () {
    var cut = cutShape(
        square(),
        const [
          Offset(-10, 50),
          Offset(25, 30),
          Offset(50, 70),
          Offset(75, 30),
          Offset(110, 50),
        ],
        1)!;
    expect(partsOf(cut).length, 2);
    expectSameCover(square(), cut, slack: 120);
  });

  test("a line that stops inside cuts nothing", () {
    expect(
        cutShape(square(), const [Offset(50, -20), Offset(50, 60)], 1), isNull);
    expect(cutShape(square(), const [Offset(150, 0), Offset(150, 100)], 1),
        isNull);
  });

  test("a line is cut into two lines, a gap between", () {
    var line = shapeOf(VectorShapeKind.line, const Rect.fromLTWH(0, 0, 100, 0),
        from: const Offset(0, 50), to: const Offset(100, 50));
    var cut = cutShape(line, const [Offset(50, 0), Offset(50, 100)], 2)!;
    expect(cut.paths.length, 2);
    expect(partsOf(cut).length, 2);
    var ends = [for (var r in cut.paths) r.nodes.last.x]..sort();
    expect(ends.first, closeTo(49, 0.01));
  });

  test("cut again: three pieces, still one shape", () {
    var once = cutShape(square(), const [Offset(30, -20), Offset(30, 120)], 1)!;
    var twice = cutShape(once, const [Offset(-20, 50), Offset(120, 50)], 1)!;
    expect(partsOf(twice).length, 4, reason: "the line crosses both halves");
    expectSameCover(square(), twice, slack: 160);
  });

  testWidgets(
      "on the stage: the knife cuts, a click picks a piece and moves it alone",
      (tester) async {
    // A 100-unit square drawn 200 wide at (100, 100) on the canvas.
    var c = CanvasController(const CanvasDocument().addElement(VectorElement(
        const ElementBase(id: "v", x: 100, y: 100, width: 200, height: 200),
        viewBox: const Rect.fromLTWH(0, 0, 100, 100),
        shapes: [square()])));
    addTearDown(c.dispose);
    var key = GlobalKey<CanvasStageState>();
    tester.view.physicalSize = const Size(1200, 900);
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
                  width: 1200,
                  height: 900,
                  child: CanvasStage(key: key, controller: c)))),
    ));
    await tester.pumpAndSettle();
    var view = key.currentState!;
    Offset onScreen(Offset at) {
      var page = view.pageRect;
      return page.topLeft + at * (page.width / c.document.size.size.width);
    }

    VectorShape shape() =>
        (c.document.elementById("v") as VectorElement).shapes!.single;
    c.selectOnly("v");
    c.editVector("v");
    c.vectorTool = VectorTool.knife;
    await tester.pumpAndSettle();

    // Straight down through the middle, from above it to below.
    var gesture = await tester.startGesture(onScreen(const Offset(200, 60)));
    for (var y = 80.0; y <= 340; y += 20) {
      await gesture.moveTo(onScreen(Offset(200, y)));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(partsOf(shape()).length, 2, reason: "cut in two, one shape");
    c.undo();
    expect(partsOf(shape()).length, 1, reason: "one undo step");
    c.redo();
    await tester.pumpAndSettle();

    // A click on the left piece picks it; a drag moves it alone.
    c.vectorTool = VectorTool.select;
    await tester.pumpAndSettle();
    // Long enough after the knife's press not to be a double-click.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)));
    var leftPart = partAt(shape(), const Offset(25, 50), 0)!;
    var scale = view.pageRect.width / c.document.size.size.width;
    await tester.dragFrom(
        onScreen(const Offset(150, 200)), Offset(-20 * scale, 0));
    await tester.pumpAndSettle();
    var left = partPath(shape(), leftPart).getBounds();
    var right =
        partPath(shape(), partsOf(shape()).firstWhere((p) => p != leftPart))
            .getBounds();
    expect(left.left, closeTo(-10, 0.5), reason: "moved 20 left: 10 units");
    expect(right.right, closeTo(100, 0.5), reason: "the other stayed");
    expect(tester.takeException(), isNull);
  });
}
