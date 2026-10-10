import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/vector_cut.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_items.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_shapes.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Color, Offset, Rect;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_vector_select_shapes_test.dart is the select shapes tool: whole
// shapes, and pieces of cut ones, picked and moved, sized and turned by a
// box round them -- and lined up by the align tool.

/// drawing is two squares -- 100 across at the left, 50 across further
/// right and lower -- drawn at (100, 100) on the canvas, one unit a pixel.
VectorElement drawing({List<VectorShape>? shapes}) => VectorElement(
    const ElementBase(id: "v", x: 100, y: 100, width: 300, height: 100),
    viewBox: const Rect.fromLTWH(0, 0, 300, 100),
    shapes: shapes ??
        [
          shapeOf(VectorShapeKind.box, const Rect.fromLTWH(0, 0, 100, 100),
              fill: const Color(0xFF0000FF)),
          shapeOf(VectorShapeKind.box, const Rect.fromLTWH(200, 25, 50, 50),
              fill: const Color(0xFFFF0000)),
        ]);

void main() {
  test("a shape's box: moved, sized, turned, lined up", () {
    var e = drawing();
    const a = (shape: 0, part: 0), b = (shape: 1, part: 0);
    expect(itemExtent(e, a), const Rect.fromLTWH(0, 0, 100, 100));
    var sized = withItemsFitted(e, [a], const Rect.fromLTWH(0, 0, 100, 100),
        const Rect.fromLTWH(10, 10, 50, 200));
    expect(itemExtent(sized, a), const Rect.fromLTWH(10, 10, 50, 200));
    expect(itemExtent(sized, b), itemExtent(e, b), reason: "the other stays");
    var turned = withItemsTurned(
        withItemsFitted(e, [a], const Rect.fromLTWH(0, 0, 100, 100),
            const Rect.fromLTWH(0, 0, 100, 40)),
        [a],
        const Offset(50, 20),
        3.14159265 / 2);
    var t = itemExtent(turned, a)!;
    expect(t.width, closeTo(40, 0.01), reason: "a quarter turn: on its side");
    expect(t.height, closeTo(100, 0.01));
    var top = withItemsAligned(e, [a, b], VectorAlign.top);
    expect(itemExtent(top, b)!.top, closeTo(0, 1e-9));
    var mid = withItemsAligned(e, [a, b], VectorAlign.centreY);
    expect(itemExtent(mid, a)!.center.dy, closeTo(50, 1e-9));
    expect(itemExtent(mid, b)!.center.dy, closeTo(50, 1e-9));
  });

  testWidgets("on the stage: picked, dragged, sized, turned and aligned",
      (tester) async {
    var c = CanvasController(const CanvasDocument().addElement(drawing()));
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
    var page = key.currentState!.pageRect;
    var scale = page.width / c.document.size.size.width;
    Offset at(Offset doc) => page.topLeft + doc * scale;
    VectorElement e() => c.document.elementById("v") as VectorElement;
    Rect box(int shape) => itemExtent(e(), (shape: shape, part: 0))!;
    Future<void> pause() => tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)));

    c.selectOnly("v");
    c.editVector("v");
    c.vectorTool = VectorTool.selectShapes;
    await tester.pumpAndSettle();

    // A drag on the big square picks it and moves it alone.
    await tester.dragFrom(
        at(const Offset(150, 150)), const Offset(30, 0) * scale);
    await tester.pumpAndSettle();
    expect(c.vectorItems, {(shape: 0, part: 0)});
    expect(box(0).left, closeTo(30, 0.5));
    expect(box(1), const Rect.fromLTWH(200, 25, 50, 50));
    c.undo();
    expect(box(0).left, closeTo(0, 0.5), reason: "one undo step");
    await tester.pumpAndSettle();

    // Its bottom-right handle, dragged out: twice the size.
    await pause();
    await tester.dragFrom(
        at(const Offset(200, 200)), const Offset(100, 100) * scale);
    await tester.pumpAndSettle();
    expect(box(0).width, closeTo(200, 1));
    c.undo();
    await tester.pumpAndSettle();

    // The round handle above, swung round to the right: a quarter turn.
    await pause();
    var knob = at(const Offset(150, 100)) - const Offset(0, shapeTurnReach);
    var gesture = await tester.startGesture(knob);
    for (var k = 1; k <= 10; k++) {
      // Round the box's middle, from straight up to straight right.
      var a = -1.5708 + 1.5708 * k / 10;
      await gesture.moveTo(at(const Offset(150, 150)) +
          Offset(80 * scale * math.cos(a), 80 * scale * math.sin(a)));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    var turned = box(0);
    expect(turned.width, closeTo(100, 1), reason: "a square stays a square");
    var corner = e().shapes![0].paths.first.nodes.first.point;
    expect(corner.dx, closeTo(100, 1), reason: "its first corner turned round");
    c.undo();
    await tester.pumpAndSettle();

    // Shift-click the small one as well, then the align tool lines them up.
    await pause();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tapAt(at(const Offset(325, 150)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(c.vectorItems.length, 2);
    c.vectorTool = VectorTool.align;
    expect(c.vectorAlignsShapes, isTrue);
    c.alignVectorItems(VectorAlign.top);
    expect(box(1).top, closeTo(0, 1e-6));
    expect(box(0).top, closeTo(0, 1e-6));

    // Points again with Select points: the align tool follows.
    c.vectorTool = VectorTool.select;
    c.vectorTool = VectorTool.align;
    expect(c.vectorAlignsShapes, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets("a piece of a cut shape is picked and moved on its own",
      (tester) async {
    var cut = cutShape(
        shapeOf(VectorShapeKind.box, const Rect.fromLTWH(0, 0, 100, 100),
            fill: const Color(0xFF0000FF)),
        const [Offset(50, -20), Offset(50, 120)],
        1)!;
    var c = CanvasController(
        const CanvasDocument().addElement(drawing(shapes: [cut])));
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
    var page = key.currentState!.pageRect;
    var scale = page.width / c.document.size.size.width;
    Offset at(Offset doc) => page.topLeft + doc * scale;
    c.selectOnly("v");
    c.editVector("v");
    c.vectorTool = VectorTool.selectShapes;
    await tester.pumpAndSettle();

    await tester.dragFrom(
        at(const Offset(120, 150)), const Offset(0, 40) * scale);
    await tester.pumpAndSettle();
    var shape = (c.document.elementById("v") as VectorElement).shapes!.single;
    var left = partAt(shape, const Offset(20, 90), 0)!;
    expect(c.vectorItems, {(shape: 0, part: left)});
    expect(partPath(shape, left).getBounds().top, closeTo(40, 0.5),
        reason: "the piece picked, moved down");
    var other = partsOf(shape).firstWhere((p) => p != left);
    expect(partPath(shape, other).getBounds().top, closeTo(0, 0.5),
        reason: "the other piece stays");
    expect(tester.takeException(), isNull);
  });

  testWidgets("a box picks the shapes it touches; copied, pasted, all",
      (tester) async {
    var c = CanvasController(const CanvasDocument().addElement(drawing()));
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
    var page = key.currentState!.pageRect;
    var scale = page.width / c.document.size.size.width;
    Offset at(Offset doc) => page.topLeft + doc * scale;
    VectorElement e() => c.document.elementById("v") as VectorElement;
    c.selectOnly("v");
    c.editVector("v");
    c.vectorTool = VectorTool.selectShapes;
    await tester.pumpAndSettle();

    // From the empty space between them, across both.
    await tester.dragFrom(
        at(const Offset(250, 110)), const Offset(150, 80) * scale);
    await tester.pumpAndSettle();
    expect(c.vectorItems, {(shape: 1, part: 0)},
        reason: "the box reached only the small one");
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.dragFrom(
        at(const Offset(380, 95)), const Offset(-230, 65) * scale);
    await tester.pumpAndSettle();
    expect(c.vectorItems.length, 2, reason: "across both");

    // Copied and pasted: a copy of each, picked as shapes.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(e().shapes!.length, 4);
    expect(c.vectorItems, {(shape: 2, part: 0), (shape: 3, part: 0)});
    expect(c.vectorPicks, isEmpty, reason: "shapes, not points");

    // And all of them.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(c.vectorItems.length, 4);
    expect(tester.takeException(), isNull);
  });
}
