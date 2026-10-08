import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:ui';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/svg_import.dart';
import 'package:bruig/plugin_system/canvas/model/vector_brush.dart';
import 'package:bruig/plugin_system/canvas/render/vector_painter.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/quick_fill.dart';
import 'package:bruig/plugin_system/canvas/ui/tablet_input.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Path;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_vector_editing_test.dart is a drawing edited point by point: where
// its points are on the canvas, what a press takes hold of, the edits, the
// controller's part, the panel -- and the store the drawings are kept in.

/// drawing is a Vector element 100 x 100 on the canvas at (100, 100), its
/// drawing 100 units square: a canvas unit is a drawing unit, offset by 100.
VectorElement drawing(String svg, {double rotation = 0}) {
  var parts = importSvg(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">$svg</svg>')!;
  return VectorElement(
      ElementBase(
          id: "v", x: 100, y: 100, width: 100, height: 100, rotation: rotation),
      assetId: "0123456789abcdef.svg",
      viewBox: parts.viewBox,
      shapes: parts.shapes);
}

const square = '<path d="M10 10 L90 10 L90 90 L10 90 Z" fill="red"/>';
const curve = '<path d="M0 50 C0 0 100 0 100 50" stroke="blue" fill="none"/>';

/// painted is [e] with a stroke like [like] painted across the canvas from
/// [from] to [to], laid -- as the stage lays one -- on the shapes it passes
/// over: a tint, or with [rubOut] a rub-out.
VectorElement painted(VectorElement e, VectorTint like, Offset from, Offset to,
    {bool rubOut = false}) {
  var space = VectorSpace(e);
  var pts = [
    for (var k = 0; k <= 20; k++)
      space.toDrawing(Offset.lerp(from, to, k / 20)!)
  ];
  var on = <int>{for (var p in pts) ...shapesUnder(e, p, like.width / 2)};
  return withStrokeOn(
      e,
      on,
      VectorTint(
          points: pts,
          paint: like.paint,
          width: like.width,
          soft: like.soft,
          line: like.line,
          fill: like.fill,
          erase: like.erase),
      rubOut: rubOut);
}

/// tintsOf and rubsOf are every tint stroke, and every rub-out, on the
/// shapes of [e].
List<VectorTint> tintsOf(VectorElement e) =>
    [for (var s in e.shapes ?? const <VectorShape>[]) ...s.tints];
List<VectorTint> rubsOf(VectorElement e) =>
    [for (var s in e.shapes ?? const <VectorShape>[]) ...s.erasures];

/// picksOfAll is every point of shape [shape].
Set<VectorPick> picksOfAll(VectorElement e, int shape) => {
      for (var (p, run) in e.shapes![shape].paths.indexed)
        for (var n = 0; n < run.nodes.length; n++) VectorPick(shape, p, n),
    };

void main() {
  group("where a point is", () {
    test("on the canvas and back, turned too", () {
      var e = drawing(square, rotation: 90);
      var space = VectorSpace(e);
      var at = space.toCanvas(const Offset(10, 10));
      // Turned a quarter, clockwise, about the box's centre (150, 150):
      // (-40, -40) from the centre goes to (40, -40).
      expect(at.dx, closeTo(190, 1e-6));
      expect(at.dy, closeTo(110, 1e-6));
      var back = space.toDrawing(at);
      expect(back.dx, closeTo(10, 1e-6));
      expect(back.dy, closeTo(10, 1e-6));
    });
  });

  group("a press", () {
    test(
        "takes a point of the picked shape, and the picked point's handles "
        "first", () {
      var e = drawing(curve);
      var hit = hitVector(e, const Offset(200, 150), 6, shape: 0)!;
      expect(hit.pick, const VectorPick(0, 0, 1));
      expect(hit.part, VectorPart.point);
      // The last point's handle sits at (100, 0) in the drawing.
      var handle = hitVector(e, const Offset(200, 100), 6,
          shape: 0, picked: const VectorPick(0, 0, 1))!;
      expect(handle.part, VectorPart.inHandle);
      expect(hitVector(e, const Offset(200, 100), 6, shape: 0), isNull,
          reason: "a handle only shows on the point picked");
    });

    test("picks the shape it lands on", () {
      var e = drawing('$square<circle cx="50" cy="50" r="10" fill="blue"/>');
      expect(shapeAt(e, const Offset(150, 150), 4), 1, reason: "the top one");
      expect(shapeAt(e, const Offset(120, 120), 4), 0);
      expect(shapeAt(e, const Offset(102, 102), 4), -1);
    });
  });

  group("the edits", () {
    test("a point moved takes its handles with it", () {
      var e = drawing(curve);
      var moved = movedVector(e, const VectorPick(0, 0, 1), VectorPart.point,
          const Offset(210, 160));
      var node = vectorNodeAt(moved, const VectorPick(0, 0, 1))!;
      expect(node.point, const Offset(110, 60));
      expect(Offset(node.inX, node.inY), const Offset(0, -50),
          reason: "the handle is relative to its point");
    });

    test("a smooth point's other handle swings round; Alt breaks it", () {
      var e = drawing('<path d="M0 50 C0 0 40 50 50 50 S100 0 100 50" '
          'stroke="black" fill="none"/>');
      var pick = const VectorPick(0, 0, 1);
      expect(vectorNodeAt(e, pick)!.smooth, isTrue);
      // The out handle pulled straight up, 20 units.
      var swung =
          movedVector(e, pick, VectorPart.outHandle, const Offset(150, 130));
      var n = vectorNodeAt(swung, pick)!;
      expect(Offset(n.outX, n.outY), const Offset(0, -20));
      expect(n.inX, closeTo(0, 1e-6));
      expect(n.inY, closeTo(10, 1e-6),
          reason: "straight down, keeping its own length of ten");
      var broken = movedVector(
          e, pick, VectorPart.outHandle, const Offset(150, 130),
          breakHandles: true);
      var b = vectorNodeAt(broken, pick)!;
      expect(Offset(b.inX, b.inY), const Offset(-10, 0), reason: "left alone");
      expect(b.smooth, isFalse, reason: "now a corner");
    });

    test("a point put in a curve does not change its shape", () {
      var e = drawing(curve);
      var before = e.shapes!.single.path.computeMetrics().single;
      var (added, pick) = withPointAdded(e, 0, 0, 0, 0.5);
      expect(pick, const VectorPick(0, 0, 1));
      expect(added.shapes!.single.paths.single.nodes, hasLength(3));
      var after = added.shapes!.single.path.computeMetrics().single;
      expect(after.length, closeTo(before.length, 0.01));
      var mid = vectorNodeAt(added, pick)!;
      expect(mid.point.dx, closeTo(50, 1e-6));
      expect(mid.point.dy, closeTo(12.5, 1e-6), reason: "the curve's top");
      expect(mid.smooth, isTrue);
    });

    test("a point put in a straight edge is a corner with no handles", () {
      var (added, _) = withPointAdded(drawing(square), 0, 0, 0, 0.5);
      var mid = added.shapes!.single.paths.single.nodes[1];
      expect(mid.point, const Offset(50, 10));
      expect(mid.hasIn || mid.hasOut, isFalse);
    });

    test("points taken out, and the run and shape with the last of them", () {
      var e = drawing(square);
      var less = withoutPoint(e, const VectorPick(0, 0, 0));
      expect(less.shapes!.single.paths.single.nodes, hasLength(3));
      var line = drawing('<line x1="0" y1="0" x2="10" y2="10" stroke="red"/>');
      expect(withoutPoint(line, const VectorPick(0, 0, 0)).shapes, isEmpty);
    });

    test("a corner made smooth, and back", () {
      var e = drawing(square);
      var pick = const VectorPick(0, 0, 1); // (90, 10)
      var smooth = withSmoothToggled(e, pick);
      var n = vectorNodeAt(smooth, pick)!;
      expect(n.smooth, isTrue);
      expect(n.hasIn && n.hasOut, isTrue);
      var corner = withSmoothToggled(smooth, pick);
      var c = vectorNodeAt(corner, pick)!;
      expect([c.smooth, c.hasIn, c.hasOut], [false, false, false]);
    });
  });

  group("the controller", () {
    CanvasController withDrawing() {
      var c =
          CanvasController(const CanvasDocument().addElement(drawing(square)));
      addTearDown(c.dispose);
      c.selectOnly("v");
      return c;
    }

    test("Delete takes out the point picked, not the drawing", () {
      var c = withDrawing();
      c.editVector("v");
      c.pickVectorPoint(const VectorPick(0, 0, 0));
      c.deleteSelected();
      var e = c.document.elementById("v") as VectorElement;
      expect(e.shapes!.single.paths.single.nodes, hasLength(3));
      expect(c.vectorPick, isNull);
      c.undo();
      expect(
          (c.document.elementById("v") as VectorElement)
              .shapes!
              .single
              .paths
              .single
              .nodes,
          hasLength(4));
    });

    test("picking something else finishes the editing", () {
      var c = withDrawing();
      c.editVector("v");
      c.pickVectorShape(0);
      expect(c.editingVector, isNotNull);
      c.clearSelection();
      expect(c.vectorEditing, isNull);
      expect(c.vectorShape, -1);
    });
  });

  group("the panel", () {
    Future<CanvasController> show(WidgetTester tester, VectorElement e) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(const CanvasDocument().addElement(e));
      addTearDown(c.dispose);
      c.selectOnly(e.id);
      tester.view.physicalSize = const Size(1400, 1600);
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
        child:
            MaterialApp(home: Scaffold(body: CanvasDesignPanel(controller: c))),
      ));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets(
        "editing brings out the tools; the brush's settings sit by its colour",
        (tester) async {
      var c = await show(tester, drawing(square));
      c.editVector("v");
      await tester.pumpAndSettle();
      for (var t in VectorTool.values) {
        expect(find.byKey(ValueKey("vectorTool-${t.name}")), findsOneWidget);
      }
      expect(find.byKey(const ValueKey("vectorTintColour")), findsNothing);
      expect(find.byKey(const ValueKey("vectorTintFill")), findsNothing);
      var tint = find.byKey(const ValueKey("vectorTool-tint"));
      await tester.ensureVisible(tint);
      await tester.tap(tint);
      await tester.pumpAndSettle();
      expect(c.vectorTool, VectorTool.tint);
      expect(find.byKey(const ValueKey("vectorTintColour")), findsOneWidget);
      var colour = find.byKey(const ValueKey("vectorTintColour"));
      var line = find.byKey(const ValueKey("vectorTintLine"));
      var fill = find.byKey(const ValueKey("vectorTintFill"));
      // On the colour's row, to its right: line, then fill.
      expect(tester.getTopLeft(line).dx,
          greaterThan(tester.getTopRight(colour).dx - 1));
      expect(tester.getTopLeft(fill).dx,
          greaterThan(tester.getTopRight(line).dx - 1));
      expect(
          tester.getCenter(line).dy, closeTo(tester.getCenter(colour).dy, 12));
      // The whole row under the tools, never beside them.
      var tools = find.byKey(const ValueKey("vectorTool-select"));
      expect(tester.getTopLeft(colour).dy,
          greaterThan(tester.getBottomLeft(tools).dy - 1));
      expect(line.evaluate().single.widget, isA<CanvasIconButton>(),
          reason: "icon only");
      await tester.ensureVisible(line);
      await tester.tap(line);
      await tester.pumpAndSettle();
      expect([c.vectorTintLine, c.vectorTintFill], [false, true]);
      expect(find.byKey(const ValueKey("vectorBrushSize")), findsOneWidget);
      expect(find.byKey(const ValueKey("vectorBrushSoft")), findsOneWidget);
      // A filled square, no line: nothing to say about ends or corners.
      expect(find.byKey(const ValueKey("vectorCap")), findsNothing);
      expect(find.byKey(const ValueKey("vectorJoin")), findsNothing);
      var edit = find.byKey(const ValueKey("vectorEdit"));
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(c.vectorEditing, isNull, reason: "the icon stops editing too");
    });

    testWidgets("each tool's settings are on the row below the tools",
        (tester) async {
      var c = await show(tester, drawing(square));
      c.editVector("v");
      var two = {const VectorPick(0, 0, 0), const VectorPick(0, 0, 1)};
      c.pickVectorPoints(two);
      await tester.pumpAndSettle();
      var toolsBottom = tester
          .getBottomLeft(find.byKey(const ValueKey("vectorTool-select")))
          .dy;
      for (var (tool, key) in const [
        (VectorTool.select, "vectorHandles"),
        (VectorTool.align, "vectorAlign-left"),
        (VectorTool.corner, "vectorCornerSize"),
        (VectorTool.boolean, "vectorCombine-subtract"),
      ]) {
        c.vectorTool = tool;
        c.pickVectorPoints(two);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.byKey(ValueKey(key))).dy,
            greaterThan(toolsBottom - 1),
            reason: "$tool");
      }
      // Lined up from the panel: both top corners to the left.
      c.vectorTool = VectorTool.align;
      c.pickVectorPoints(two);
      await tester.pumpAndSettle();
      var left = find.byKey(const ValueKey("vectorAlign-left"));
      await tester.ensureVisible(left);
      await tester.tap(left);
      await tester.pumpAndSettle();
      var nodes = c.editingVector!.shapes!.single.paths.single.nodes;
      expect(nodes[1].point, const Offset(10, 10));
      expect(tester.takeException(), isNull);
    });

    testWidgets("the pencil's row: fill, its colour, quick fill; mirrors after",
        (tester) async {
      var c = await show(tester, drawing(square));
      c.editVector("v");
      c.vectorTool = VectorTool.pencil;
      c.vectorQuickFill = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // In reading order: down the rows, then along each.
      Offset at(String key) => tester.getTopLeft(find.byKey(ValueKey(key)));
      bool before(String a, String b) {
        var p = at(a), q = at(b);
        return (p.dy - q.dy).abs() < 8 ? p.dx < q.dx : p.dy < q.dy;
      }

      var order = [
        "vectorBrushFill",
        "vectorPencilFill",
        "vectorQuickFill",
        "vectorFillGap",
        "vectorBrushWidth",
        "vectorBrushSmoothing",
        "vectorMirrorAcross",
        "vectorMirrorDown",
      ];
      for (var i = 0; i + 1 < order.length; i++) {
        expect(before(order[i], order[i + 1]), isTrue,
            reason: "${order[i]} before ${order[i + 1]}");
      }
      c.vectorTool = VectorTool.select;
      c.editVector(null);
      await tester.pumpAndSettle();
    });

    testWidgets("Thickness types the picked points' line width",
        (tester) async {
      var c = await show(
          tester,
          drawing('<path d="M10 50 L50 50 L90 50" stroke="black" '
              'stroke-width="4" fill="none"/>'));
      c.editVector("v");
      c.vectorTool = VectorTool.scale;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("vectorPointWidth")), findsNothing,
          reason: "nothing picked, nothing to type");
      c.pickVectorPoint(const VectorPick(0, 0, 1));
      await tester.pumpAndSettle();
      tester
          .widget<CanvasNumberField>(
              find.byKey(const ValueKey("vectorPointWidth")))
          .onChanged(3);
      await tester.pumpAndSettle();
      var nodes = c.editingVector!.shapes!.single.paths.single.nodes;
      expect([for (var n in nodes) n.width], [1, 3, 1]);
      var reset = find.byKey(const ValueKey("vectorPointWidthReset"));
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(c.editingVector!.shapes!.single.paths.single.nodes[1].width, 1);
      c.editVector(null);
      await tester.pumpAndSettle();
    });

    testWidgets("a point picked takes its own end or corner", (tester) async {
      var c = await show(
          tester,
          drawing('<path d="M10 80 L50 20 L90 80" stroke="black" '
              'stroke-width="6" fill="none"/>'));
      c.editVector("v");
      c.pickVectorPoint(const VectorPick(0, 0, 1));
      await tester.pumpAndSettle();
      if (find.byKey(const ValueKey("vectorPointJoin")).evaluate().isEmpty) {
        var more = find.byKey(const ValueKey("more-vectorShapeMore"));
        await tester.ensureVisible(more);
        await tester.tap(more);
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const ValueKey("vectorPointCap")), findsNothing,
          reason: "the middle point has no end");
      var join = tester.widget<CanvasDropdown<StrokeJoin?>>(
          find.byKey(const ValueKey("vectorPointJoin")));
      expect(join.value, isNull, reason: "as the shape's, to start");
      join.onChanged(StrokeJoin.bevel);
      await tester.pumpAndSettle();
      var nodes = c.editingVector!.shapes!.single.paths.single.nodes;
      expect([for (var n in nodes) n.join], [null, StrokeJoin.bevel, null],
          reason: "that point alone");
      expect(c.editingVector!.shapes!.single.join, StrokeJoin.miter);

      c.pickVectorPoint(const VectorPick(0, 0, 2));
      await tester.pumpAndSettle();
      tester
          .widget<CanvasDropdown<StrokeCap?>>(
              find.byKey(const ValueKey("vectorPointCap")))
          .onChanged(StrokeCap.round);
      await tester.pumpAndSettle();
      nodes = c.editingVector!.shapes!.single.paths.single.nodes;
      expect([for (var n in nodes) n.cap], [null, null, StrokeCap.round]);
      expect(tester.takeException(), isNull);
    });

    testWidgets("a drawing not yet edited offers Edit points, no colours",
        (tester) async {
      await show(
          tester,
          const VectorElement(ElementBase(id: "v"),
              assetId: "0123456789abcdef.svg"));
      expect(find.byKey(const ValueKey("vectorEdit")), findsOneWidget);
      expect(find.byKey(const ValueKey("vectorShapeGroup")), findsNothing);
      expect(find.byKey(const ValueKey("vectorTool-pen")), findsNothing,
          reason: "the tools come out with the editing");
    });

    testWidgets("an edited one's colours change the shape picked, or all",
        (tester) async {
      var c = await show(tester,
          drawing('$square<circle cx="50" cy="50" r="10" fill="blue"/>'));
      String group() => tester
          .widget<CanvasMoreGroup>(
              find.byKey(const ValueKey("vectorShapeGroup")))
          .label;
      expect(group(), "All shapes");

      c.editVector("v");
      c.pickVectorShape(1);
      await tester.pumpAndSettle();
      expect(group(), "Shape 2 of 2");
      var fillOn = find.byKey(const ValueKey("vectorFillOn"));
      await tester.ensureVisible(fillOn);
      await tester.tap(fillOn);
      await tester.pumpAndSettle();
      var shapes = (c.document.elementById("v") as VectorElement).shapes!;
      expect(shapes[1].fill, isNull, reason: "the picked shape's fill off");
      expect(shapes[0].fill, const Color(0xFFFF0000), reason: "not the other");
    });
  });

  group("on the stage", () {
    const viewport = Size(1200, 900);

    Future<(CanvasController, CanvasStageState)> stage(WidgetTester tester,
        {VectorElement? element}) async {
      var c = CanvasController(
          const CanvasDocument().addElement(element ?? drawing(curve)));
      addTearDown(c.dispose);
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
              child: CanvasStage(key: key, controller: c),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return (c, key.currentState!);
    }

    Offset onScreen(CanvasStageState view, CanvasController c, Offset at) {
      var page = view.pageRect;
      return page.topLeft + at * (page.width / c.document.size.size.width);
    }

    testWidgets("a second click opens it; a point is dragged; Escape leaves",
        (tester) async {
      var (c, view) = await stage(tester);
      // The curve's middle point is at (200, 150) on the canvas.
      var point = onScreen(view, c, const Offset(200, 150));
      await tester.tapAt(onScreen(view, c, const Offset(150, 113)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(c.selection, {"v"});
      await tester.tapAt(onScreen(view, c, const Offset(150, 113)));
      await tester.pumpAndSettle();
      expect(c.vectorEditing, "v", reason: "the second click opens it");

      // On the curve itself, whose top is at (150, 112.5).
      expect(c.vectorShape, 0,
          reason: "the shape double-clicked is picked, its points shown");
      var scale = view.pageRect.width / c.document.size.size.width;
      await tester.dragFrom(point, Offset(0, 20 * scale));
      await tester.pumpAndSettle();
      var node = vectorNodeAt(c.document.elementById("v") as VectorElement,
          const VectorPick(0, 0, 1))!;
      expect(node.point.dx, closeTo(100, 0.5));
      expect(node.point.dy, closeTo(70, 0.5), reason: "dragged 20 down");
      expect(c.vectorPick, const VectorPick(0, 0, 1));

      c.undo();
      expect(
          vectorNodeAt(c.document.elementById("v") as VectorElement,
                  const VectorPick(0, 0, 1))!
              .point
              .dy,
          closeTo(50, 0.5),
          reason: "one drag, one undo");

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(c.vectorPick, isNull, reason: "first the point");
      expect(c.vectorEditing, "v");
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(c.vectorEditing, isNull, reason: "then the editing");
      expect(c.selection, {"v"}, reason: "still selected");
      expect(tester.takeException(), isNull);
    });

    /// open selects the drawing at [at] and opens it for editing.
    Future<void> open(WidgetTester tester, CanvasController c,
        CanvasStageState view, Offset at) async {
      await tester.tapAt(onScreen(view, c, at));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(onScreen(view, c, at));
      await tester.pumpAndSettle();
      expect(c.vectorEditing, "v");
    }

    VectorElement now(CanvasController c) =>
        c.document.elementById("v") as VectorElement;

    // In edit mode a drag picks points, wherever it starts -- a shape
    // included. Moving the drawing whole is what a drag does out of it.
    testWidgets("a drag on a shape picks points; a click picks the shape",
        (tester) async {
      var (c, view) = await stage(tester, element: drawing(square));
      await open(tester, c, view, const Offset(150, 150));
      await tester.pump(const Duration(milliseconds: 500));
      // From inside the square out past its top-left corner at (110, 110).
      await tester.dragFrom(
          onScreen(view, c, const Offset(130, 130)),
          onScreen(view, c, const Offset(105, 105)) -
              onScreen(view, c, const Offset(130, 130)));
      await tester.pumpAndSettle();
      var nodes = now(c).shapes!.single.paths.single.nodes;
      expect(nodes.first.point, const Offset(10, 10), reason: "nothing moved");
      expect(c.vectorPicks, {const VectorPick(0, 0, 0)});

      await tester.pump(const Duration(milliseconds: 500));
      await tester.tapAt(onScreen(view, c, const Offset(150, 150)));
      await tester.pumpAndSettle();
      expect(c.vectorShape, 0, reason: "a click on it picks it");
      expect(c.vectorPicks, isEmpty);
    });

    testWidgets("a box picks the points in it; one of them drags them all",
        (tester) async {
      var (c, view) = await stage(tester, element: drawing(curve));
      await open(tester, c, view, const Offset(150, 140));
      // From empty space inside the drawing, leftwards out past its left
      // end: a box may run outside the drawing, though it starts in it.
      // (Below the curve: on it, a press takes hold of the shape.)
      await tester.dragFrom(
          onScreen(view, c, const Offset(150, 190)),
          onScreen(view, c, const Offset(95, 140)) -
              onScreen(view, c, const Offset(150, 190)));
      await tester.pumpAndSettle();
      expect(c.vectorPicks, {const VectorPick(0, 0, 0)});

      // Shift and a click adds the other end.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tapAt(onScreen(view, c, const Offset(200, 150)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(c.vectorPicks,
          {const VectorPick(0, 0, 0), const VectorPick(0, 0, 1)});

      var scale = view.pageRect.width / c.document.size.size.width;
      await tester.pump(const Duration(milliseconds: 500));
      await tester.dragFrom(
          onScreen(view, c, const Offset(100, 150)), Offset(0, 10 * scale));
      await tester.pumpAndSettle();
      var nodes = now(c).shapes!.single.paths.single.nodes;
      expect(nodes[0].point.dy, closeTo(60, 0.5));
      expect(nodes[1].point.dy, closeTo(60, 0.5), reason: "both moved");

      c.deleteSelected();
      expect(now(c).shapes, isEmpty, reason: "both taken out, and the line");
    });

    // A box can start outside the drawing -- the easy way to sweep up its
    // edge points -- and editing stays on through it. A click out there that
    // does not move is what finishes.
    testWidgets("a box from outside picks points; a click outside finishes",
        (tester) async {
      var (c, view) = await stage(tester, element: drawing(curve));
      await open(tester, c, view, const Offset(150, 140));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.dragFrom(
          onScreen(view, c, const Offset(80, 130)),
          onScreen(view, c, const Offset(120, 170)) -
              onScreen(view, c, const Offset(80, 130)));
      await tester.pumpAndSettle();
      expect(c.vectorEditing, "v", reason: "still editing");
      expect(c.vectorPicks, {const VectorPick(0, 0, 0)});

      await tester.pump(const Duration(milliseconds: 500));
      await tester.tapAt(onScreen(view, c, const Offset(60, 400)));
      await tester.pumpAndSettle();
      expect(c.vectorEditing, isNull, reason: "a click off it finishes");
      expect(c.selection, isEmpty, reason: "and picks what it landed on");
      expect(tester.takeException(), isNull);
    });

    // What is picked stays picked -- and shown -- while a box is dragged,
    // and is only replaced when the box is let go.
    testWidgets("points stay picked until the box is let go", (tester) async {
      var (c, view) = await stage(tester, element: drawing(curve));
      await open(tester, c, view, const Offset(150, 140));
      c.pickVectorPoint(const VectorPick(0, 0, 1));
      await tester.pump(const Duration(milliseconds: 500));
      var gesture =
          await tester.startGesture(onScreen(view, c, const Offset(80, 130)));
      await gesture.moveTo(onScreen(view, c, const Offset(100, 150)));
      await gesture.moveTo(onScreen(view, c, const Offset(120, 170)));
      await tester.pump();
      expect(c.vectorPicks, {const VectorPick(0, 0, 1)},
          reason: "still picked half way through");
      expect(c.vectorShape, 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(c.vectorPicks, {const VectorPick(0, 0, 0)},
          reason: "the box's, once let go");
    });

    // Several points picked are dragged by the middle of the box round them,
    // not only by one of them.
    testWidgets("several picked points are dragged by their middle",
        (tester) async {
      var (c, view) = await stage(tester, element: drawing(square));
      await open(tester, c, view, const Offset(150, 150));
      // The square's two top corners, at (110, 110) and (190, 110).
      c.pickVectorPoints(
          {const VectorPick(0, 0, 0), const VectorPick(0, 0, 1)});
      // Out of the double-click's reach, which is timed on the real clock.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 450)));
      var scale = view.pageRect.width / c.document.size.size.width;
      await tester.dragFrom(
          onScreen(view, c, const Offset(150, 111)), Offset(0, 10 * scale));
      await tester.pumpAndSettle();
      var nodes = now(c).shapes!.single.paths.single.nodes;
      expect(nodes[0].point.dy, closeTo(20, 0.5));
      expect(nodes[1].point.dy, closeTo(20, 0.5));
      expect(nodes[2].point.dy, closeTo(90, 0.5), reason: "the rest stay");
      expect(c.vectorPicks, hasLength(2), reason: "still picked");
    });

    testWidgets("the pen draws a shape and closes it on its first point",
        (tester) async {
      var empty = VectorElement(
          const ElementBase(id: "v", x: 100, y: 100, width: 100, height: 100));
      var (c, view) = await stage(tester, element: empty);
      await open(tester, c, view, const Offset(150, 150));
      expect(c.vectorPen, isTrue, reason: "an empty drawing opens on the pen");
      for (var at in const [
        Offset(110, 110),
        Offset(190, 110),
        Offset(150, 190)
      ]) {
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tapAt(onScreen(view, c, at));
        await tester.pumpAndSettle();
      }
      expect(now(c).shapes!.single.paths.single.nodes, hasLength(3));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tapAt(onScreen(view, c, const Offset(110, 110)));
      await tester.pumpAndSettle();
      var run = now(c).shapes!.single.paths.single;
      expect(run.closed, isTrue);
      expect(run.nodes, hasLength(3));
      expect(c.vectorPenShape, -1, reason: "finished, the pen still out");
      expect(c.vectorPen, isTrue);

      // A drag as a point goes down pulls a curve out of it.
      await tester.pump(const Duration(milliseconds: 500));
      var scale = view.pageRect.width / c.document.size.size.width;
      await tester.dragFrom(
          onScreen(view, c, const Offset(120, 180)), Offset(20 * scale, 0));
      await tester.pumpAndSettle();
      var started = now(c).shapes![1].paths.single.nodes.single;
      expect(started.smooth, isTrue);
      expect(started.outX, closeTo(20, 0.5));
      expect(started.inX, closeTo(-20, 0.5));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(c.vectorPenShape, -1, reason: "Return finishes it, open");
      expect(tester.takeException(), isNull);
    });

    Future<void> settle(WidgetTester tester) => tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 450)));

    testWidgets("the pen on a point picks it, and the next point joins on",
        (tester) async {
      var (c, view) = await stage(tester,
          element: drawing(
              '<path d="M10 10 L50 10 L90 10" stroke="black" fill="none"/>'));
      await open(tester, c, view, const Offset(150, 150));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.pump();
      expect(c.vectorTool, VectorTool.pen);
      await settle(tester);
      await tester.tapAt(onScreen(view, c, const Offset(150, 110)));
      await tester.pumpAndSettle();
      expect(now(c).shapes!.single.paths.single.nodes, hasLength(3),
          reason: "a point already there puts nothing down");
      expect(c.vectorPenFrom, const VectorPick(0, 0, 1));
      await settle(tester);
      await tester.tapAt(onScreen(view, c, const Offset(150, 190)));
      await tester.pumpAndSettle();
      var paths = now(c).shapes!.single.paths;
      expect(paths, hasLength(2), reason: "a branch from the middle");
      expect([for (var n in paths[1].nodes) n.point],
          [const Offset(50, 10), const Offset(50, 90)]);
      expect(tester.takeException(), isNull);
    });

    testWidgets("the pen drags a point as picking does, then joins from it",
        (tester) async {
      var (c, view) = await stage(tester,
          element: drawing(
              '<path d="M10 10 L50 10 L90 10" stroke="black" fill="none"/>'));
      await open(tester, c, view, const Offset(150, 150));
      c.vectorTool = VectorTool.pen;
      await settle(tester);
      var scale = view.pageRect.width / c.document.size.size.width;
      await tester.dragFrom(
          onScreen(view, c, const Offset(150, 110)), Offset(0, 20 * scale));
      await tester.pumpAndSettle();
      var run = now(c).shapes!.single.paths.single;
      expect(run.nodes, hasLength(3), reason: "moved, nothing put down");
      expect(run.nodes[1].point.dy, closeTo(30, 0.5));
      expect(c.vectorPenFrom, const VectorPick(0, 0, 1));
      await settle(tester);
      await tester.tapAt(onScreen(view, c, const Offset(150, 190)));
      await tester.pumpAndSettle();
      expect(now(c).shapes!.single.paths, hasLength(2),
          reason: "the next point branches from the point moved");
      expect(tester.takeException(), isNull);
    });

    testWidgets("the corner tool rounds the corner clicked", (tester) async {
      var (c, view) = await stage(tester, element: drawing(square));
      await open(tester, c, view, const Offset(150, 150));
      c.vectorTool = VectorTool.corner;
      c.vectorCornerSize = 20;
      await settle(tester);
      await tester.tapAt(onScreen(view, c, const Offset(190, 110)));
      await tester.pumpAndSettle();
      var nodes = now(c).shapes!.single.paths.single.nodes;
      expect(nodes, hasLength(5));
      expect(nodes[1].point.dx, closeTo(70, 1e-6));
      expect(c.vectorPicks, hasLength(2), reason: "the two new points picked");
      c.undo();
      expect(now(c).shapes!.single.paths.single.nodes, hasLength(4),
          reason: "one undo step");
      expect(tester.takeException(), isNull);
    });

    testWidgets("a corner still picked goes on being shaped, until let go",
        (tester) async {
      var (c, view) = await stage(tester, element: drawing(square));
      await open(tester, c, view, const Offset(150, 150));
      c.vectorTool = VectorTool.corner;
      c.vectorCornerSize = 10;
      await settle(tester);
      await tester.tapAt(onScreen(view, c, const Offset(190, 110)));
      await tester.pumpAndSettle();
      expect(c.vectorCornerActive, isTrue);
      double startX() => now(c).shapes!.single.paths.single.nodes[1].point.dx;
      expect(startX(), closeTo(80, 1e-6));
      // The size setting reshapes it, rather than waiting for the next one.
      c.vectorCornerSize = 25;
      await tester.pump();
      expect(startX(), closeTo(65, 1e-6));
      expect(now(c).shapes!.single.paths.single.nodes, hasLength(5),
          reason: "the same corner, not another");
      // A drag from one of its points shapes it again -- by eye.
      await settle(tester);
      var scale = view.pageRect.width / c.document.size.size.width;
      await tester.dragFrom(
          onScreen(view, c, const Offset(165, 110)), Offset(-15 * scale, 0));
      await tester.pumpAndSettle();
      expect(now(c).shapes!.single.paths.single.nodes, hasLength(5));
      expect(c.vectorCornerSize, closeTo(40, 1.5),
          reason: "how far out from where the corner was");
      // Picking anything else finishes it.
      c.pickVectorPoint(const VectorPick(0, 0, 0));
      expect(c.vectorCornerActive, isFalse);
      c.vectorCornerSize = 5;
      expect(now(c).shapes!.single.paths.single.nodes, hasLength(5));
      expect(tester.takeException(), isNull);
    });

    testWidgets("the pencil draws a stroke; the pen's buttons do as set",
        (tester) async {
      var (c, view) = await stage(tester, element: drawing(square));
      await open(tester, c, view, const Offset(150, 150));
      c.vectorTool = VectorTool.pencil;
      c.vectorPencilColour = const Color(0xFF00AA00);
      await tester.pump();
      bool bare() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<StagePainter>()
          .single
          .editingVector!
          .bare;
      expect(bare(), isTrue, reason: "the points hidden to start with");
      expect(
          tester
              .widgetList<MouseRegion>(find.byType(MouseRegion))
              .any((m) => m.cursor == SystemMouseCursors.none),
          isTrue,
          reason: "no arrow over the drawing: the brush's ring is the pointer");
      c.vectorPencilPoints = true;
      await tester.pump();
      expect(bare(), isFalse, reason: "shown when asked for");
      c.vectorPencilPoints = false;
      await settle(tester);
      var from = onScreen(view, c, const Offset(120, 130));
      var g = await tester.startGesture(from);
      for (var k = 1; k <= 20; k++) {
        await g.moveTo(from + Offset(k * 6.0, k * 2.0));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await g.up();
      await tester.pumpAndSettle();
      var shapes = now(c).shapes!;
      expect(shapes, hasLength(2), reason: "a stroke is a shape of its own");
      var stroke = shapes.last;
      expect(stroke.fill, isNull);
      expect(stroke.stroke!.g, greaterThan(0.6));
      expect(stroke.paths.single.nodes.length, greaterThan(1));
      c.undo();
      expect(now(c).shapes, hasLength(1), reason: "one stroke, one undo");

      // Button 1 -- a right click -- picks the square's colour up.
      c.setStylusButton(0, StylusAction.pickColour);
      await settle(tester);
      await tester.tapAt(onScreen(view, c, const Offset(150, 150)),
          buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(c.vectorPencilColour, const Color(0xFFFF0000));
      expect(now(c).shapes, hasLength(1), reason: "nothing drawn");

      // Shift held as the pen touches stands in for Button 1.
      c.vectorPencilColour = const Color(0xFF000000);
      await settle(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tapAt(onScreen(view, c, const Offset(150, 150)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(c.vectorPencilColour, const Color(0xFFFF0000));
      expect(now(c).shapes, hasLength(1), reason: "nothing drawn");

      // Button 3 -- a back click -- set to erase, rubs the square out.
      c.setStylusButton(2, StylusAction.erase);
      await settle(tester);
      await tester.tapAt(onScreen(view, c, const Offset(150, 150)),
          buttons: kBackMouseButton);
      await tester.pumpAndSettle();
      expect(now(c).shapes, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets("the tablet's pressure and eraser end reach the pencil",
        (tester) async {
      var tablet = TabletInput.instance;
      addTearDown(tablet.reset);
      var (c, view) = await stage(tester, element: drawing(square));
      await open(tester, c, view, const Offset(150, 150));
      c.vectorTool = VectorTool.pencil;
      c.vectorBrush = const VectorBrush(
          name: "t", thinnest: 0, smoothing: 0, curve: 1, size: 10);
      await settle(tester);
      // A light press, as the runner reads it, then heavier.
      var from = onScreen(view, c, const Offset(120, 130));
      tablet.handle({"pressure": 0.2, "tiltX": 0.0, "tiltY": 0.0});
      var g = await tester.startGesture(from);
      for (var k = 1; k <= 10; k++) {
        tablet.handle({"pressure": 0.2 + k * 0.08, "tiltX": 0.0, "tiltY": 0.0});
        await g.moveTo(from + Offset(k * 8.0, 0));
        await tester.pump();
      }
      await g.up();
      await tester.pumpAndSettle();
      var nodes = now(c).shapes!.last.paths.single.nodes;
      expect(nodes.first.width, closeTo(0.2, 0.01));
      expect(nodes.last.width, closeTo(1.0, 0.01));

      // A button the tablet reports, held as the pen touches: Button 1's
      // action, not a stroke.
      c.setStylusButton(0, StylusAction.pickColour);
      c.vectorPencilColour = const Color(0xFF000000);
      tablet.handle(
          {"pressure": 0.5, "tiltX": 0.0, "tiltY": 0.0, "buttons": 1 | 2});
      var count = now(c).shapes!.length;
      await settle(tester);
      tablet.handle(
          {"pressure": 0.5, "tiltX": 0.0, "tiltY": 0.0, "buttons": 1 | 2});
      await tester.tapAt(onScreen(view, c, const Offset(150, 150)));
      await tester.pumpAndSettle();
      expect(c.vectorPencilColour, const Color(0xFFFF0000));
      expect(now(c).shapes, hasLength(count), reason: "nothing drawn");
      tablet
          .handle({"pressure": 0.0, "tiltX": 0.0, "tiltY": 0.0, "buttons": 0});

      // The pen turned over: its eraser end near, a press rubs out.
      tablet.handle({"proximity": true, "eraser": true});
      expect(tablet.eraser, isTrue);
      await settle(tester);
      await tester.tapAt(onScreen(view, c, const Offset(150, 150)));
      await tester.pumpAndSettle();
      expect(now(c).shapes!.any((s) => s.fill != null), isFalse,
          reason: "the square rubbed out");
      tablet.handle({"proximity": false, "eraser": true});
      expect([tablet.eraser, tablet.near], [false, false]);
      expect(tester.takeException(), isNull);
    });

    test("the runner's readings: pressure, tilt, and only when fresh", () {
      var tablet = TabletInput.instance;
      addTearDown(tablet.reset);
      expect(tablet.fresh, isFalse);
      tablet
          .handle({"pressure": 1.4, "tiltX": 1.0, "tiltY": 0.0, "buttons": 1});
      expect(tablet.pressure, 1, reason: "kept within 0 to 1");
      expect(tablet.tilt, closeTo(math.pi / 2, 1e-9));
      expect(tablet.fresh, isTrue);
      tablet.handle("nonsense");
      expect(tablet.pressure, 1);
    });

    testWidgets("the pencil's quick fill fills, and recolours what it filled",
        (tester) async {
      var (c, view) = await stage(tester,
          element: drawing('<path d="M20 20 L80 20 L80 80 L20 80 Z" '
              'stroke="black" stroke-width="2" fill="none"/>'));
      await open(tester, c, view, const Offset(150, 150));
      c.vectorTool = VectorTool.pencil;
      c.vectorQuickFill = true;
      c.vectorPencilFill = const Color(0xFF0000FF);
      await settle(tester);
      await tester.tapAt(onScreen(view, c, const Offset(150, 150)));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      var shapes = now(c).shapes!;
      expect(shapes, hasLength(2));
      expect(shapes.first.fill, const Color(0xFF0000FF));
      c.vectorPencilFill = const Color(0xFFFF0000);
      await settle(tester);
      await tester.tapAt(onScreen(view, c, const Offset(150, 150)));
      await tester.pumpAndSettle();
      shapes = now(c).shapes!;
      expect(shapes, hasLength(2), reason: "recoloured, not filled again");
      expect(shapes.first.fill, const Color(0xFFFF0000));
      expect(tester.takeException(), isNull);
    });

    testWidgets("with a mirror on, the pencil draws a mirrored pair",
        (tester) async {
      var (c, view) = await stage(tester, element: drawing(square));
      await open(tester, c, view, const Offset(150, 150));
      c.vectorTool = VectorTool.pencil;
      c.vectorMirrorAcross = true;
      await settle(tester);
      var from = onScreen(view, c, const Offset(110, 120));
      var g = await tester.startGesture(from);
      for (var k = 1; k <= 10; k++) {
        await g.moveTo(from + Offset(k * 2.0, k * 3.0));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await g.up();
      await tester.pumpAndSettle();
      var shapes = now(c).shapes!;
      expect(shapes, hasLength(3), reason: "the square, a stroke, its mirror");
      var a = shapes[1].paths.single.nodes.first.point;
      var b = shapes[2].paths.single.nodes.first.point;
      expect(a.dx + b.dx, closeTo(100, 0.5), reason: "either side of 50");
      expect(a.dy, closeTo(b.dy, 0.5));
      c.undo();
      expect(now(c).shapes, hasLength(1), reason: "both in one undo step");
      expect(tester.takeException(), isNull);
    });

    testWidgets("the pencil draws only on the page", (tester) async {
      var (c, view) = await stage(tester, element: drawing(square));
      await open(tester, c, view, const Offset(150, 150));
      c.vectorTool = VectorTool.pencil;
      await settle(tester);
      // The desk below the page: what the stage shows past its bottom edge.
      var bottom = c.document.size.size.height;
      var off = Offset(150, bottom + 20);
      expect(onScreen(view, c, off).dy, lessThan(900),
          reason: "the stage shows some desk below the page");
      // A palm resting off the page: nothing.
      await tester.dragFrom(onScreen(view, c, off), const Offset(10, -5));
      await tester.pumpAndSettle();
      expect(now(c).shapes, hasLength(1));
      // On the page, off its bottom edge, and back: two lines, not one
      // jumping across the desk.
      await settle(tester);
      var g = await tester
          .startGesture(onScreen(view, c, Offset(150, bottom - 30)));
      for (var d in [-20.0, -10.0, 10.0, 20.0, 10.0, -10.0, -20.0, -30.0]) {
        await g.moveTo(onScreen(
            view, c, Offset(d < 0 && d > -25 ? 170 : 160, bottom + d)));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await g.up();
      await tester.pumpAndSettle();
      var shapes = now(c).shapes!;
      expect(shapes, hasLength(3));
      var space = VectorSpace(now(c));
      for (var s in shapes.skip(1)) {
        for (var n in s.paths.single.nodes) {
          expect(space.toCanvas(n.point).dy, lessThanOrEqualTo(bottom + 0.5));
        }
      }
      c.undo();
      expect(now(c).shapes, hasLength(1), reason: "one stroke, one undo");
      expect(tester.takeException(), isNull);
    });

    testWidgets("the eraser rubs out, or takes out whole lines",
        (tester) async {
      var (c, view) = await stage(tester, element: drawing(square));
      await open(tester, c, view, const Offset(150, 150));
      c.vectorTool = VectorTool.eraser;
      c.vectorEraseSize = 12;
      await settle(tester);
      var scale = view.pageRect.width / c.document.size.size.width;
      await tester.dragFrom(
          onScreen(view, c, const Offset(130, 150)), Offset(40 * scale, 0));
      await tester.pumpAndSettle();
      var rub = rubsOf(now(c)).single;
      expect(rub.points.length, greaterThan(1));
      expect(rub.width, closeTo(12 / scale, 0.5),
          reason: "its size on screen, in the drawing's units");
      expect(now(c).shapes, hasLength(1), reason: "the square still there");
      c.undo();
      expect(rubsOf(now(c)), isEmpty, reason: "one rub-out, one undo");

      // Off the page: nothing.
      var bottom = c.document.size.size.height;
      await settle(tester);
      await tester.dragFrom(
          onScreen(view, c, Offset(150, bottom + 20)), const Offset(10, 0));
      await tester.pumpAndSettle();
      expect(rubsOf(now(c)), isEmpty);

      // Whole lines: the square goes.
      c.vectorEraseWhole = true;
      await settle(tester);
      await tester.tapAt(onScreen(view, c, const Offset(150, 150)));
      await tester.pumpAndSettle();
      expect(now(c).shapes, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets("Command A, C and V pick, copy and paste points",
        (tester) async {
      var (c, view) = await stage(tester, element: drawing(square));
      await open(tester, c, view, const Offset(150, 150));
      Future<void> command(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
      }

      await command(LogicalKeyboardKey.keyA);
      expect(c.vectorPicks, hasLength(4));
      c.pickVectorPoints(
          {const VectorPick(0, 0, 0), const VectorPick(0, 0, 1)});
      await command(LogicalKeyboardKey.keyC);
      await command(LogicalKeyboardKey.keyV);
      var shapes = now(c).shapes!;
      expect(shapes, hasLength(2),
          reason: "the points copied, not the drawing");
      expect(c.document.elements, hasLength(1));
      var pasted = shapes.last.paths.single;
      expect(pasted.closed, isFalse);
      expect(pasted.nodes, hasLength(2));
      expect(c.vectorPicks, hasLength(2), reason: "the pasted points picked");
      expect(tester.takeException(), isNull);
    });

    testWidgets("a double-click with the pen finishes the line",
        (tester) async {
      var empty = VectorElement(
          const ElementBase(id: "v", x: 100, y: 100, width: 100, height: 100));
      var (c, view) = await stage(tester, element: empty);
      await open(tester, c, view, const Offset(150, 150));
      for (var at in const [Offset(120, 120), Offset(170, 120)]) {
        await settle(tester);
        await tester.tapAt(onScreen(view, c, at));
        await tester.pumpAndSettle();
      }
      // The second click of a double-click puts nothing down.
      await tester.tapAt(onScreen(view, c, const Offset(170, 170)));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(onScreen(view, c, const Offset(170, 170)));
      await tester.pumpAndSettle();
      expect(c.vectorPenShape, -1, reason: "finished");
      expect(c.vectorPen, isTrue, reason: "the pen still out");
      expect(now(c).shapes!.single.paths.single.nodes, hasLength(3));
      await settle(tester);
      await tester.tapAt(onScreen(view, c, const Offset(130, 180)));
      await tester.pumpAndSettle();
      expect(now(c).shapes, hasLength(2), reason: "the next starts afresh");
      expect(tester.takeException(), isNull);
    });

    testWidgets("a point pressed is picked, and its thickness changes alone",
        (tester) async {
      var (c, view) = await stage(tester,
          element: drawing('<path d="M10 50 L40 50 L70 50 L90 50" '
              'stroke="black" stroke-width="4" fill="none"/>'));
      await open(tester, c, view, const Offset(150, 120));
      c.vectorTool = VectorTool.scale;
      c.pickVectorPoints(const {});
      await settle(tester);
      // From the second point, right along the line past the third: 150
      // pixels on screen, twice as thick -- that point alone.
      var from = onScreen(view, c, const Offset(140, 150));
      var g = await tester.startGesture(from);
      for (var k = 1; k <= 10; k++) {
        await g.moveTo(from + Offset(k * 15.0, 0));
        await tester.pump();
      }
      await g.up();
      await tester.pumpAndSettle();
      var nodes = now(c).shapes!.single.paths.single.nodes;
      expect(c.vectorPicks, {const VectorPick(0, 0, 1)});
      expect(nodes[1].width, closeTo(2, 0.01));
      expect(nodes[2].width, 1, reason: "passed over, but not picked");
      c.undo();
      expect(now(c).shapes!.single.paths.single.nodes[1].width, 1,
          reason: "one undo step");

      // A click off every point lets it go.
      await settle(tester);
      await tester.tapAt(onScreen(view, c, const Offset(150, 180)));
      await tester.pumpAndSettle();
      expect(c.vectorPicks, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets("with nothing picked, a drag thickens the points it passes",
        (tester) async {
      var (c, view) = await stage(tester,
          element: drawing('<path d="M10 50 L40 50 L70 50 L90 50" '
              'stroke="black" stroke-width="4" fill="none"/>'));
      await open(tester, c, view, const Offset(150, 120));
      c.vectorTool = VectorTool.scale;
      c.pickVectorPoints(const {});
      await settle(tester);
      bool bare() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<StagePainter>()
          .single
          .editingVector!
          .bare;
      expect(bare(), isFalse, reason: "the points shown before the drag");
      // From beside the second point, not on it, along and past the third.
      var from = onScreen(view, c, const Offset(140, 168));
      var g = await tester.startGesture(from);
      for (var k = 1; k <= 10; k++) {
        await g.moveTo(from + Offset(k * 15.0, 0));
        await tester.pump();
        if (k == 5) expect(bare(), isTrue, reason: "hidden while dragging");
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(bare(), isFalse, reason: "back once let go");
      var nodes = now(c).shapes!.single.paths.single.nodes;
      expect(nodes[0].width, 1, reason: "never near the drag");
      expect(nodes[1].width, greaterThan(1.5),
          reason: "the nearest point at the press");
      expect(nodes[2].width, greaterThan(1.5), reason: "passed near");
      expect(now(c).width, 100, reason: "the drawing's box left alone");
      expect(tester.takeException(), isNull);
    });

    testWidgets("the tint brush never boxes, and the points are put away",
        (tester) async {
      var (c, view) = await stage(tester, element: drawing(square));
      await open(tester, c, view, const Offset(150, 150));
      c.vectorTool = VectorTool.tint;
      await settle(tester);
      // From off the drawing onto it: a stroke, no box.
      var scale = view.pageRect.width / c.document.size.size.width;
      await tester.dragFrom(
          onScreen(view, c, const Offset(60, 150)), Offset(80 * scale, 0));
      await tester.pump();
      expect(view.marqueeForTest, isNull);
      await tester.pumpAndSettle();
      expect(tintsOf(now(c)), hasLength(1));
      expect(c.vectorPicks, isEmpty);
      expect(c.vectorEditing, "v");
      // A click off it, unmoved, finishes the editing.
      await settle(tester);
      await tester.tapAt(onScreen(view, c, const Offset(40, 40)));
      await tester.pumpAndSettle();
      expect(c.vectorEditing, isNull);
      expect(tintsOf(now(c)), hasLength(1), reason: "nothing painted by it");
      expect(tester.takeException(), isNull);
    });

    testWidgets("the tint brush paints a stroke anywhere over the drawing",
        (tester) async {
      var (c, view) = await stage(tester, element: drawing(square));
      await open(tester, c, view, const Offset(150, 150));
      c.vectorTool = VectorTool.tint;
      c.vectorTint = const PaintSpec(Color(0xFF00FF00));
      c.vectorBrushSize = 30;
      await settle(tester);
      var scale = view.pageRect.width / c.document.size.size.width;
      // Across the middle, nowhere near a point.
      await tester.dragFrom(
          onScreen(view, c, const Offset(130, 150)), Offset(40 * scale, 0));
      await tester.pumpAndSettle();
      var tints = tintsOf(now(c));
      expect(tints, hasLength(1));
      var t = tints.single;
      expect(t.points.length, greaterThan(2));
      expect(t.points.first.dx, closeTo(30, 1));
      expect(t.points.last.dx, closeTo(70, 1));
      expect(t.width, closeTo(30 / scale, 0.5),
          reason: "the brush's size on screen, in the drawing's units");
      expect([t.line, t.fill, t.erase], [true, true, false]);
      c.undo();
      expect(tintsOf(now(c)), isEmpty, reason: "one stroke, one undo");
      expect(tester.takeException(), isNull);
    });

    testWidgets("the pen taken out with a point picked carries on from it",
        (tester) async {
      var (c, view) = await stage(tester,
          element: drawing(
              '<path d="M10 10 L50 10 L90 10" stroke="black" fill="none"/>'));
      await open(tester, c, view, const Offset(150, 150));
      c.pickVectorPoint(const VectorPick(0, 0, 2));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.pump();
      expect(c.vectorPenFrom, const VectorPick(0, 0, 2));
      await settle(tester);
      await tester.tapAt(onScreen(view, c, const Offset(190, 190)));
      await tester.pumpAndSettle();
      var paths = now(c).shapes!.single.paths;
      expect(paths, hasLength(1), reason: "joined on, not a new line");
      expect(paths.single.nodes.last.point, const Offset(90, 90));
      expect(tester.takeException(), isNull);
    });

    testWidgets("a pen click that shifts a little puts down a corner",
        (tester) async {
      var empty = VectorElement(
          const ElementBase(id: "v", x: 100, y: 100, width: 100, height: 100));
      var (c, view) = await stage(tester, element: empty);
      await open(tester, c, view, const Offset(150, 150));
      await settle(tester);
      await tester.dragFrom(
          onScreen(view, c, const Offset(120, 120)), const Offset(6, 0));
      await tester.pumpAndSettle();
      var n = now(c).shapes!.single.paths.single.nodes.single;
      expect([n.hasIn, n.hasOut, n.smooth], [false, false, false]);
      expect(tester.takeException(), isNull);
    });

    testWidgets("the Boolean tool picks shapes and subtracts one from another",
        (tester) async {
      var (c, view) = await stage(tester,
          element: drawing('$square<path d="M40 40 L60 40 L60 60 L40 60 Z" '
              'fill="blue"/>'));
      await open(tester, c, view, const Offset(150, 150));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.pump();
      expect(c.vectorTool, VectorTool.boolean);
      expect(c.vectorCombining, {1},
          reason: "it starts from the shape the double-click picked");
      await settle(tester);
      await tester.tapAt(onScreen(view, c, const Offset(120, 120)));
      await tester.pumpAndSettle();
      expect(c.vectorCombining, {0, 1});
      c.combineVector(VectorCombine.subtract);
      await tester.pumpAndSettle();
      var shapes = now(c).shapes!;
      expect([shapes[0].combine, shapes[1].combine],
          [null, VectorCombine.subtract]);
      expect(c.vectorCombining, {0}, reason: "the result picked");
      // A click on the hole picks the whole result, not the cutter alone.
      c.clearCombining();
      await settle(tester);
      await tester.tapAt(onScreen(view, c, const Offset(150, 150)));
      await tester.pumpAndSettle();
      expect(c.vectorCombining, {0});
      c.separateVector();
      expect(now(c).shapes![1].combine, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        "a double-click on a fill picks its points; on its line adds one",
        (tester) async {
      var (c, view) = await stage(tester,
          element: drawing('<path d="M10 10 L90 10 L90 90 L10 90 Z" '
              'fill="red" stroke="black" stroke-width="4"/>'
              '<path d="M90 90 L95 95" stroke="black"/>'));
      await open(tester, c, view, const Offset(150, 150));
      await settle(tester);
      Future<void> twice(Offset at) async {
        await tester.tapAt(onScreen(view, c, at));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(onScreen(view, c, at));
        await tester.pumpAndSettle();
      }

      await twice(const Offset(140, 160));
      expect(now(c).shapes!.first.paths.single.nodes, hasLength(4),
          reason: "nothing added on the fill");
      expect(
          c.vectorPicks,
          {
            for (var n = 0; n < 4; n++) VectorPick(0, 0, n),
            const VectorPick(1, 0, 0),
            const VectorPick(1, 0, 1),
          },
          reason: "the square, and the line joined to its corner");

      await settle(tester);
      await twice(const Offset(150, 111));
      expect(now(c).shapes!.first.paths.single.nodes, hasLength(5),
          reason: "on the line, a point there");
      expect(tester.takeException(), isNull);
    });
  });

  group("the store", () {
    late Directory root;
    setUp(() async {
      root = await Directory.systemTemp.createTemp("canvas_vectors");
      CanvasStorage.rootOverride = root.path;
      CanvasLibrary.resetForTest();
    });
    tearDown(() async {
      CanvasStorage.rootOverride = null;
      if (await root.exists()) await root.delete(recursive: true);
    });

    const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1">'
        '<rect width="1" height="1"/></svg>';

    test("a drawing is kept in Canvas > Vectors", () async {
      var id = (await CanvasMedia.saveVector(svg.codeUnits))!;
      expect(id, endsWith(".svg"));
      var where = await CanvasMedia.existingPath(MediaKind.vector, id);
      expect(
          where,
          contains("${Platform.pathSeparator}Vectors"
              "${Platform.pathSeparator}"));
      expect(CanvasMedia.kindOf(id), MediaKind.vector);
    });

    test("drawings in the pictures move out, and are found either way",
        () async {
      var id = "0123456789abcdef.svg";
      await CanvasAssets.saveAs(id, svg.codeUnits);
      expect(await CanvasMedia.existingPath(MediaKind.vector, id),
          contains("Pictures"),
          reason: "found among the pictures before it is moved");
      expect(await CanvasMedia.migrateVectors(), 1);
      expect(await CanvasAssets.pathOf(id), isNull);
      expect(await CanvasMedia.existingPath(MediaKind.vector, id),
          contains("Vectors"));
      expect(await CanvasMedia.migrateVectors(), 0, reason: "once is enough");
    });

    test("a drawing listed as a picture is listed as a drawing", () {
      var a = LibraryAsset.fromJson({
        "id": "0123456789abcdef.svg",
        "kind": "picture",
        "name": "Logo",
        "added": DateTime(2026).toIso8601String(),
      })!;
      expect(a.kind, AssetKind.vector);
    });
  });
  group("more edits", () {
    test("several points moved", () {
      var e = drawing(square);
      var moved = withPointsMoved(
          e,
          {const VectorPick(0, 0, 0), const VectorPick(0, 0, 2)},
          const Offset(5, -5));
      var n = moved.shapes!.single.paths.single.nodes;
      expect([n[0].point, n[1].point, n[2].point],
          const [Offset(15, 5), Offset(90, 10), Offset(95, 85)]);
    });

    test("a box picks every point inside it, of every shape", () {
      var e = drawing('$square<circle cx="50" cy="50" r="10" fill="blue"/>');
      // The square's top-left corner and the circle's top: canvas (110, 110)
      // and (150, 140).
      var picks = picksIn(e, const Rect.fromLTRB(105, 105, 155, 145));
      expect(picks, {const VectorPick(0, 0, 0), const VectorPick(1, 0, 3)});
    });

    test("several points taken out, in any order", () {
      var e = drawing(square);
      var less = withoutPoints(
          e, {const VectorPick(0, 0, 0), const VectorPick(0, 0, 2)});
      expect([for (var n in less.shapes!.single.paths.single.nodes) n.point],
          const [Offset(90, 10), Offset(10, 90)]);
    });

    test("the pen starts a shape like the one picked, then goes on with it",
        () {
      var e = blankDrawing(VectorElement(
          const ElementBase(id: "v", x: 100, y: 100, width: 100, height: 100)));
      expect(e.viewBox, const Rect.fromLTWH(0, 0, 100, 100));
      expect(e.edited, isTrue);
      var like = const VectorShape(
          paths: [], stroke: Color(0xFFFF0000), strokeWidth: 4);
      var (one, first) =
          withPenPoint(e, null, const Offset(110, 120), like: like);
      expect(first, const VectorPick(0, 0, 0));
      expect(one.shapes!.single.stroke, const Color(0xFFFF0000));
      expect(one.shapes!.single.strokeWidth, 4);
      var (two, second) = withPenPoint(one, first, const Offset(150, 120));
      expect(second, const VectorPick(0, 0, 1));
      var curved = withPenHandles(two, second, const Offset(160, 120));
      var n = curved.shapes!.single.paths.single.nodes[1];
      expect([n.outX, n.inX, n.smooth], [10, -10, true]);
      expect(withPenClosed(curved, second).shapes!.single.paths.single.closed,
          isTrue);
    });

    test("the pen joins on from a point: on, turned round, or a branch", () {
      var e = drawing(
          '<path d="M10 10 L50 10 L90 10" stroke="black" fill="none"/>');
      List<Offset> run(VectorElement e, int p) =>
          [for (var n in e.shapes!.single.paths[p].nodes) n.point];
      // From its end, the line goes on.
      var (on, onPick) =
          withPenPoint(e, const VectorPick(0, 0, 2), const Offset(190, 150));
      expect(onPick, const VectorPick(0, 0, 3));
      expect(run(on, 0).last, const Offset(90, 50));
      expect(on.shapes, hasLength(1), reason: "no new shape");
      // From its start, it is turned round and goes on from there.
      var (back, backPick) =
          withPenPoint(e, const VectorPick(0, 0, 0), const Offset(110, 150));
      expect(backPick, const VectorPick(0, 0, 3));
      expect(run(back, 0), const [
        Offset(90, 10),
        Offset(50, 10),
        Offset(10, 10),
        Offset(10, 50)
      ]);
      // From the middle, a branch: a new run in the same shape, from there.
      var (branch, branchPick) =
          withPenPoint(e, const VectorPick(0, 0, 1), const Offset(150, 190));
      expect(branchPick, const VectorPick(0, 1, 1));
      expect(run(branch, 1), const [Offset(50, 10), Offset(50, 90)]);
      expect(run(branch, 0), hasLength(3), reason: "the line left alone");
    });

    test("a curve turned round keeps its shape", () {
      var e = drawing(curve);
      var before = e.shapes!.single.paths.single;
      var (turned, _) =
          withPenPoint(e, const VectorPick(0, 0, 0), const Offset(150, 190));
      var after = turned.shapes!.single.paths.single.nodes;
      // The old last point is first now, its handles swapped.
      var was = before.nodes.last;
      expect(after.first.point, was.point);
      expect([after.first.outX, after.first.outY], [was.inX, was.inY]);
      expect([after.first.inX, after.first.inY], [was.outX, was.outY]);
    });

    test("a joint moves as one point: a branch stays on its line", () {
      var e = drawing(
          '<path d="M10 10 L50 10 L90 10" stroke="black" fill="none"/>');
      var (branched, _) =
          withPenPoint(e, const VectorPick(0, 0, 1), const Offset(150, 190));
      var moved = withPointsMoved(
          branched, {const VectorPick(0, 0, 1)}, const Offset(0, 20));
      var runs = moved.shapes!.single.paths;
      expect(runs[0].nodes[1].point, const Offset(50, 30));
      expect(runs[1].nodes[0].point, const Offset(50, 30),
          reason: "the branch's end went with it");
      expect(runs[1].nodes[1].point, const Offset(50, 90));
      var dragged = movedVector(branched, const VectorPick(0, 1, 0),
          VectorPart.point, const Offset(160, 120));
      expect(
          dragged.shapes!.single.paths[0].nodes[1].point, const Offset(60, 20),
          reason: "and from the branch's side too");
    });

    test("points taken out together, a whole short line with them", () {
      var e = drawing('$square<path d="M10 50 L90 50" stroke="black"/>');
      var less = withoutPoints(e, {
        const VectorPick(1, 0, 0),
        const VectorPick(1, 0, 1),
        const VectorPick(0, 0, 3),
        const VectorPick(7, 0, 0),
      });
      expect(less.shapes, hasLength(1), reason: "the line went whole");
      expect(less.shapes!.single.paths.single.nodes, hasLength(3));
      expect(withoutPoint(e, const VectorPick(0, 0, 9)).shapes, hasLength(2),
          reason: "a point not there is passed over");
    });

    test("a point's own end and corner are kept, and drawn", () async {
      var e = drawing('<path d="M10 80 L50 20 L90 80" stroke="#000000" '
          'stroke-width="8" fill="none"/>');
      e = withVectorNode(
          e,
          const VectorPick(0, 0, 1),
          vectorNodeAt(e, const VectorPick(0, 0, 1))!
              .copyWith(join: StrokeJoin.bevel));
      e = withVectorNode(
          e,
          const VectorPick(0, 0, 0),
          vectorNodeAt(e, const VectorPick(0, 0, 0))!
              .copyWith(cap: StrokeCap.round));
      expect(e.shapes!.single.ownLine, isTrue);
      var back = (elementFromJson(
              jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>)
          as VectorElement);
      var nodes = back.shapes!.single.paths.single.nodes;
      expect([nodes[0].cap, nodes[1].join, nodes[2].cap, nodes[2].join],
          [StrokeCap.round, StrokeJoin.bevel, null, null]);

      Future<List<int>> draw(VectorElement e) async {
        var rec = PictureRecorder();
        paintVector(Canvas(rec), const Rect.fromLTWH(0, 0, 100, 100), e, null);
        var img = await rec.endRecording().toImage(100, 100);
        return (await img.toByteData())!.buffer.asUint8List();
      }

      int alpha(List<int> px, int x, int y) => px[(y * 100 + x) * 4 + 3];
      var px = await draw(e);
      // Cut at the top, where a sharp corner would reach up to about 13.
      expect(alpha(px, 50, 14), 0, reason: "the corner cut off");
      expect(alpha(px, 50, 19), greaterThan(200));
      // Round at the start, flat at the end: past each point along the line.
      expect(alpha(px, 7, 82), greaterThan(100), reason: "round start");
      expect(alpha(px, 93, 82), 0, reason: "flat end");
    });

    test("a picked joint lights every end lying on it", () {
      var e = drawing(
          '<path d="M10 10 L50 10 L90 10" stroke="black" fill="none"/>');
      var (branched, _) =
          withPenPoint(e, const VectorPick(0, 0, 1), const Offset(150, 190));
      expect(joinedTo(branched, {const VectorPick(0, 0, 1)}),
          {const VectorPick(0, 0, 1), const VectorPick(0, 1, 0)});
    });

    test("points lined up, and spread with even gaps", () {
      var e = drawing('<path d="M10 10 L30 50 L80 20 L90 90" stroke="black" '
          'fill="none"/>');
      var all = picksOfAll(e, 0);
      List<Offset> at(VectorElement e) =>
          [for (var n in e.shapes!.single.paths.single.nodes) n.point];
      List<double> xs(VectorAlign how) =>
          [for (var p in at(withAligned(e, all, how))) p.dx];
      List<double> ys(VectorAlign how) =>
          [for (var p in at(withAligned(e, all, how))) p.dy];
      expect(xs(VectorAlign.left), [10, 10, 10, 10]);
      expect(xs(VectorAlign.right), [90, 90, 90, 90]);
      expect(xs(VectorAlign.centreX), [50, 50, 50, 50]);
      expect(ys(VectorAlign.top), [10, 10, 10, 10]);
      expect(ys(VectorAlign.bottom), [90, 90, 90, 90]);
      expect(ys(VectorAlign.centreY), [50, 50, 50, 50]);
      // Even gaps across: in the order they were across, 10 to 90.
      var spread = at(withAligned(e, all, VectorAlign.spreadX));
      expect(spread[0].dx, 10);
      expect(spread[1].dx, closeTo(36.67, 0.01));
      expect(spread[2].dx, closeTo(63.33, 0.01));
      expect(spread[3].dx, 90);
      expect([for (var p in spread) p.dy], [10, 50, 20, 90],
          reason: "only across");
      var down = at(withAligned(e, all, VectorAlign.spreadY));
      expect([for (var p in down) p.dy],
          [10, closeTo(63.33, 0.01), closeTo(36.67, 0.01), 90]);
      expect(
          identical(withAligned(e, {all.first}, VectorAlign.left), e), isTrue,
          reason: "one point has nothing to line up with");
    });

    test("a corner rounded, or cut, back along each side", () {
      var e = drawing(square);
      var (round, picks) = withCornered(e, const VectorPick(0, 0, 1), 20)!;
      var nodes = round.shapes!.single.paths.single.nodes;
      expect(nodes, hasLength(5));
      expect(picks, {const VectorPick(0, 0, 1), const VectorPick(0, 0, 2)});
      expect(nodes[1].point.dx, closeTo(70, 1e-6));
      expect(nodes[1].point.dy, closeTo(10, 1e-6));
      expect(nodes[2].point.dx, closeTo(90, 1e-6));
      expect(nodes[2].point.dy, closeTo(30, 1e-6));
      // A quarter circle's handles: 0.552 of the reach, towards the corner.
      expect(nodes[1].outX, closeTo(20 * 0.5523, 0.01));
      expect(nodes[2].inY, closeTo(-20 * 0.5523, 0.01));
      var (cut, _) =
          withCornered(e, const VectorPick(0, 0, 1), 20, round: false)!;
      var c = cut.shapes!.single.paths.single.nodes;
      expect([c[1].hasOut, c[2].hasIn], [false, false]);
      // Never past halfway along a side.
      var (far, _) = withCornered(e, const VectorPick(0, 0, 1), 500)!;
      expect(far.shapes!.single.paths.single.nodes[1].point.dx,
          closeTo(90 - 80 * 0.49, 1e-6));
      // The first point of a closed run has a corner too.
      expect(withCornered(e, const VectorPick(0, 0, 0), 10), isNotNull);
      // A line's end has none.
      var line = drawing('<path d="M10 10 L50 50 L90 10" stroke="black"/>');
      expect(withCornered(line, const VectorPick(0, 0, 0), 10), isNull);
      expect(withCornered(line, const VectorPick(0, 0, 1), 10), isNotNull);
    });

    test("handles: mirrored, turned only, stretched only, snapped", () {
      var line = drawing('<path d="M10 50 L50 50 L90 50" stroke="black"/>');
      const mid = VectorPick(0, 0, 1);
      var aligned = withHandles(line, {mid}, VectorHandles.aligned);
      var n = vectorNodeAt(aligned, mid)!;
      expect(n.handles, VectorHandles.aligned);
      expect(n.outX, closeTo(13.33, 0.01));
      expect(n.inX, closeTo(-13.33, 0.01));
      var mirrored = withHandles(aligned, {mid}, VectorHandles.mirrored);
      // Out pulled to 20 right, 20 up: the in handle is its exact mirror.
      var m = vectorNodeAt(
          movedVector(
              mirrored, mid, VectorPart.outHandle, const Offset(170, 130)),
          mid)!;
      expect([m.outX, m.outY, m.inX, m.inY], [20, -20, -20, 20]);
      // Aligned: the other swings round to stay in line, its length kept.
      var keep = vectorNodeAt(
          movedVector(
              aligned, mid, VectorPart.outHandle, const Offset(150, 130)),
          mid)!;
      expect(Offset(keep.inX, keep.inY).distance, closeTo(13.33, 0.01));
      expect(keep.inY, greaterThan(0));
      // Turned only: its length kept. Stretched only: its line kept.
      var turned = vectorNodeAt(
          movedVector(
              aligned, mid, VectorPart.outHandle, const Offset(150, 100),
              drag: VectorHandleDrag.turn),
          mid)!;
      expect(Offset(turned.outX, turned.outY).distance, closeTo(13.33, 0.01));
      expect(turned.outX, closeTo(0, 1e-9));
      var stretched = vectorNodeAt(
          movedVector(
              aligned, mid, VectorPart.outHandle, const Offset(180, 120),
              drag: VectorHandleDrag.stretch),
          mid)!;
      expect(stretched.outX, closeTo(30, 1e-9));
      expect(stretched.outY, closeTo(0, 1e-9));
      // Snapped to fifteen degrees: 40 degrees up goes to 45.
      var a = -40 * math.pi / 180;
      var snapped = vectorNodeAt(
          movedVector(aligned, mid, VectorPart.outHandle,
              Offset(150 + 20 * math.cos(a), 150 + 20 * math.sin(a)),
              snap: true),
          mid)!;
      expect(math.atan2(snapped.outY, snapped.outX) * 180 / math.pi,
          closeTo(-45, 1e-6));
      // Kept: mirrored is saved as such.
      var back = (elementFromJson(
              jsonDecode(jsonEncode(mirrored.toJson())) as Map<String, dynamic>)
          as VectorElement);
      expect(vectorNodeAt(back, mid)!.handles, VectorHandles.mirrored);
      // Evened, and taken off.
      var uneven = withVectorNode(
          aligned, mid, vectorNodeAt(aligned, mid)!.copyWith(outX: 30));
      var even = vectorNodeAt(withEvenHandles(uneven, {mid}), mid)!;
      expect(even.outX, closeTo(21.67, 0.01));
      expect(even.inX, closeTo(-21.67, 0.01));
      var off = vectorNodeAt(withoutHandles(aligned, {mid}), mid)!;
      expect([off.hasIn, off.hasOut, off.handles],
          [false, false, VectorHandles.free]);
      // The pen pulls a mirrored pair.
      var (pen, pick) = withPenPoint(line, null, const Offset(120, 120));
      var pulled = vectorNodeAt(
          withPenHandles(pen, pick, const Offset(130, 120)), pick)!;
      expect(pulled.handles, VectorHandles.mirrored);
    });

    test("the points copied are the stretches picked, whole runs whole", () {
      var e = drawing(square);
      // Corners 3, 0 and 1 of the closed square: one stretch, round its end.
      var bit = copiedShapes(e, {
        const VectorPick(0, 0, 3),
        const VectorPick(0, 0, 0),
        const VectorPick(0, 0, 1),
      });
      expect(bit.single.paths.single.closed, isFalse);
      expect([for (var n in bit.single.paths.single.nodes) n.point],
          const [Offset(10, 90), Offset(10, 10), Offset(90, 10)]);
      expect(bit.single.fill, const Color(0xFFFF0000), reason: "its colours");
      var whole = copiedShapes(e, picksOfAll(e, 0));
      expect(whole.single.paths.single.closed, isTrue);
      expect(copiedShapes(e, {const VectorPick(0, 0, 2)}), isEmpty,
          reason: "a lone point has no line");
      var (pasted, picks) = withPasted(e, whole, const Offset(5, 5));
      expect(pasted.shapes, hasLength(2));
      expect(pasted.shapes![1].paths.single.nodes.first.point,
          const Offset(15, 15));
      expect(picks, hasLength(4));
      expect(allPicks(pasted), hasLength(8));
    });

    test("a pencil stroke: pressure, speed, tapers, nib, few points", () {
      var e = drawing(square);
      List<PenSample> line(
              {double? pressure,
              bool noPressure = false,
              int ms = 8,
              Offset to = const Offset(80, 0)}) =>
          [
            for (var i = 0; i <= 60; i++)
              PenSample(const Offset(110, 150) + to * (i / 60),
                  pressure:
                      noPressure ? null : pressure ?? (i < 30 ? 0.1 : 1.0),
                  time: Duration(milliseconds: i * ms)),
          ];
      VectorShape draw(VectorBrush b, List<PenSample> s) =>
          pencilShape(e, s, b, const Color(0xFF000000), 4)!;
      var liner = builtInBrushes.firstWhere((b) => b.name == "Fine liner");
      var nodes = draw(liner, line()).paths.single.nodes;
      expect(nodes.every((n) => n.width == 1), isTrue,
          reason: "a fine liner pays pressure no mind");
      expect(nodes.length, lessThan(10), reason: "a straight line, few points");
      var soft = const VectorBrush(name: "t", thinnest: 0.2, smoothing: 0);
      nodes = draw(soft, line()).paths.single.nodes;
      expect(nodes.first.width, closeTo(0.2 + 0.8 * 0.1, 0.01));
      expect(nodes.last.width, closeTo(1, 0.01));
      // No pressure from the pen: slow is heavy, fast is light.
      var slow = draw(soft, line(noPressure: true, ms: 40)).paths.single.nodes;
      var fast = draw(soft, line(noPressure: true, ms: 1)).paths.single.nodes;
      expect(slow.last.width, greaterThan(fast.last.width));
      // Tapered: nothing at the ends, full in the middle.
      var tapered =
          draw(soft.copyWith(taperIn: 0.3, taperOut: 0.3), line(pressure: 1))
              .paths
              .single
              .nodes;
      expect(tapered.first.width, lessThan(0.1));
      expect(tapered.last.width, lessThan(0.1));
      // A broad nib at 0 degrees: thin going across, wide going down.
      var nib = soft.copyWith(nib: 1, nibAngle: 0);
      var across = draw(nib, line(pressure: 1)).paths.single.nodes;
      var down = draw(nib, line(pressure: 1, to: const Offset(0, 40)))
          .paths
          .single
          .nodes;
      expect(across[1].width, lessThan(0.2));
      expect(down[1].width, greaterThan(0.9));
      // See-through as the brush says.
      expect(draw(soft.copyWith(opacity: 0.5), line()).stroke!.a,
          closeTo(0.5, 0.01));
      // Kept, and found again.
      var back = VectorBrush.fromJson(
          jsonDecode(jsonEncode(nib.toJson())) as Map<String, dynamic>);
      expect(back.sameAs(nib), isTrue);
      expect(back.name, "t");
      // The eraser takes out what it goes over.
      expect(withoutShapesAt(e, const Offset(150, 150), 2).shapes, isEmpty);
    });

    test("a fill brush closes its stroke and fills it", () {
      var e = drawing(square);
      var samples = [
        for (var i = 0; i <= 40; i++)
          PenSample(
              const Offset(150, 150) +
                  Offset(math.cos(i / 40 * 2 * math.pi),
                          math.sin(i / 40 * 2 * math.pi)) *
                      30,
              time: Duration(milliseconds: i * 8)),
      ];
      var fill = builtInBrushes.firstWhere((b) => b.name == "Fill");
      var s = pencilShape(e, samples, fill, const Color(0xFF000000), 2,
          fillColour: const Color(0xFF00FF00))!;
      expect(s.paths.single.closed, isTrue);
      expect(s.fill, const Color(0xFF00FF00));
      expect(s.stroke, isNull, reason: "the Fill brush draws no line");
      var both = pencilShape(
          e, samples, fill.copyWith(line: true), const Color(0xFF000000), 2,
          fillColour: const Color(0xFF00FF00))!;
      expect(both.stroke, const Color(0xFF000000));
      var plain = pencilShape(
          e, samples, builtInBrushes.first, const Color(0xFF000000), 2)!;
      expect([plain.paths.single.closed, plain.fill], [false, null]);
      var back = VectorBrush.fromJson(
          jsonDecode(jsonEncode(fill.toJson())) as Map<String, dynamic>);
      expect([back.fill, back.line], [true, false]);
      expect(back.sameAs(fill), isTrue);
    });

    testWidgets("a slider's number can be typed", (tester) async {
      var value = 0.5;
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, set) => CanvasSlider(
                label: "Soft",
                value: value,
                onChanged: (v) => set(() => value = v),
              ),
            ),
          ),
        ),
      ));
      var field = find.byType(TextField);
      expect(tester.widget<TextField>(field).controller!.text, "0.50");
      await tester.enterText(field, "0.73");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(value, 0.73);
      await tester.enterText(field, "9");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(value, 1, reason: "kept to the slider's range");
      expect(tester.widget<TextField>(field).controller!.text, "1.00");
    });

    test("quick fill: the area lines close round, holes and all", () async {
      // Four separate strokes crossing at the corners of a box, a loop in
      // the middle of it, and a fill-only background under them all.
      var e =
          drawing('<rect x="0" y="0" width="100" height="100" fill="#eeeeee"/>'
              '<path d="M10 20 L90 20" stroke="black" stroke-width="2"/>'
              '<path d="M80 10 L80 90" stroke="black" stroke-width="2"/>'
              '<path d="M90 80 L10 80" stroke="black" stroke-width="2"/>'
              '<path d="M20 90 L20 10" stroke="black" stroke-width="2"/>'
              '<path d="M45 45 L55 45 L55 55 L45 55 Z" stroke="black" '
              'stroke-width="2" fill="none"/>');
      const green = Color(0xFF00AA00);
      var filled = await quickFilled(e, const Offset(130, 130), green);
      expect(filled, isNotNull);
      var shapes = filled!.shapes!;
      expect(shapes, hasLength(e.shapes!.length + 1));
      var fill = shapes[1];
      expect(shapes[0].stroke, isNull, reason: "the background stays under");
      expect([fill.fill, fill.stroke], [green, null]);
      for (var s in shapes.skip(2)) {
        expect(s.stroke, isNotNull, reason: "the lines stay over the fill");
      }
      var outline = fill.path;
      expect(outline.contains(const Offset(30, 30)), isTrue);
      expect(outline.contains(const Offset(70, 70)), isTrue);
      expect(outline.contains(const Offset(50, 50)), isFalse,
          reason: "the loop inside is a hole");
      expect(outline.contains(const Offset(5, 50)), isFalse,
          reason: "nothing outside the lines");
      expect(outline.contains(const Offset(20.97, 50)), isTrue,
          reason: "tucked under the line it met");

      // Outside every line: nothing closes round it.
      expect(await quickFilled(e, const Offset(105, 105), green), isNull);

      // Lines drawn out past the drawing's box, as the pencil does while
      // the drawing is edited: the area is still found.
      var past = drawing('<path d="M60 60 L160 60 L160 160 L60 160 Z" '
          'stroke="black" stroke-width="2" fill="none"/>');
      var beyond = await quickFilled(past, const Offset(240, 240), green);
      expect(beyond, isNotNull);
      expect(
          beyond!.shapes!.first.path.contains(const Offset(140, 140)), isTrue);

      // A box with a two-unit opening fills only with the gap allowed.
      var open = drawing('<path d="M20 20 L80 20 L80 80 L20 80 L20 51" '
          'stroke="black" stroke-width="1" fill="none"/>'
          '<path d="M20 49 L20 20" stroke="black" stroke-width="1"/>');
      expect(await quickFilled(open, const Offset(150, 150), green), isNull);
      expect(await quickFilled(open, const Offset(150, 150), green, gap: 2),
          isNotNull);
    });

    test("a stroke mirrored across, down, or both", () {
      var e = drawing(square);
      var nib = const VectorBrush(name: "n", nib: 1, nibAngle: 30);
      var one = [const PenSample(Offset(120, 130))];
      expect(mirroredStrokes(e, one, nib), hasLength(1));
      var all = mirroredStrokes(e, one, nib, across: true, down: true);
      expect([
        for (var (s, _) in all) s.single.at
      ], const [
        Offset(120, 130),
        Offset(180, 130),
        Offset(120, 170),
        Offset(180, 170),
      ], reason: "about the drawing's middle, (150, 150) on the canvas");
      expect([for (var (_, b) in all) b.nibAngle], [30, 150, -30, -150],
          reason: "a broad nib turned with its stroke");
    });

    test("rub-outs take out lines, fills, or both, and are kept", () async {
      Future<List<int>> draw(VectorElement e) async {
        var rec = PictureRecorder();
        paintVector(Canvas(rec), const Rect.fromLTWH(0, 0, 100, 100), e, null);
        var img = await rec.endRecording().toImage(100, 100);
        return (await img.toByteData())!.buffer.asUint8List();
      }

      int alpha(List<int> px, int x, int y) => px[(y * 100 + x) * 4 + 3];
      // A grey square with a thick black edge, rubbed across the middle.
      var e = drawing('<path d="M20 20 L80 20 L80 80 L20 80 Z" '
          'fill="#808080" stroke="#000000" stroke-width="6"/>');
      VectorElement rubbed({bool line = true, bool fill = true}) => painted(
          e,
          VectorTint(
              points: const [],
              paint: const PaintSpec(Color(0xFF000000)),
              width: 10,
              soft: 0,
              line: line,
              fill: fill,
              erase: true),
          const Offset(105, 150),
          const Offset(195, 150),
          rubOut: true);

      var px = await draw(rubbed());
      expect(alpha(px, 50, 50), 0, reason: "the fill rubbed out");
      expect(alpha(px, 20, 50), 0, reason: "and the line");
      expect(alpha(px, 50, 30), 255, reason: "not where it did not go");

      px = await draw(rubbed(line: false));
      expect(alpha(px, 50, 50), 0);
      expect(alpha(px, 20, 50), 255, reason: "the line left");

      px = await draw(rubbed(fill: false));
      expect(alpha(px, 50, 50), 255, reason: "the fill left");
      expect(alpha(px, 20, 50), lessThan(5),
          reason: "the line's own pixels taken");

      var back = (elementFromJson(
          jsonDecode(jsonEncode(rubbed(line: false).toJson()))
              as Map<String, dynamic>) as VectorElement);
      var t = rubsOf(back).single;
      expect([t.line, t.fill, t.width, t.erase], [false, true, 10, true]);
    });

    test("a line made thicker at its points, and kept", () {
      var e = drawing('<path d="M10 50 L50 50 L90 50" stroke="black" '
          'stroke-width="4" fill="none"/>');
      var thick = withWidths(e, {const VectorPick(0, 0, 1): 1}, 3);
      var nodes = thick.shapes!.single.paths.single.nodes;
      expect([for (var n in nodes) n.width], [1, 3, 1]);
      expect(thick.shapes!.single.tapered, isTrue);
      expect(
          withWidths(e, {const VectorPick(0, 0, 1): 1}, 1000)
              .shapes!
              .single
              .paths
              .single
              .nodes[1]
              .width,
          20,
          reason: "kept within reason");
      var back = (elementFromJson(
              jsonDecode(jsonEncode(thick.toJson())) as Map<String, dynamic>)
          as VectorElement);
      expect([for (var n in back.shapes!.single.paths.single.nodes) n.width],
          [1, 3, 1]);
      // A point put in between is as thick as the line was there.
      var (added, pick) = withPointAdded(thick, 0, 0, 0, 0.5);
      expect(vectorNodeAt(added, pick)!.width, closeTo(2, 1e-9));
    });

    test("a tapered line is drawn thick where its points say", () async {
      var e = drawing('<path d="M10 50 L50 50 L90 50" stroke="#000000" '
          'stroke-width="4" fill="none"/>');
      e = withWidths(e, {const VectorPick(0, 0, 1): 1}, 5);
      var rec = PictureRecorder();
      paintVector(Canvas(rec), const Rect.fromLTWH(0, 0, 100, 100), e, null);
      var img = await rec.endRecording().toImage(100, 100);
      var px = (await img.toByteData())!.buffer.asUint8List();
      int alpha(int x, int y) => px[(y * 100 + x) * 4 + 3];
      expect(alpha(50, 58), greaterThan(200), reason: "10 thick at the middle");
      expect(alpha(12, 55), 0, reason: "2 thick at the end");
      expect(alpha(5, 50), 0, reason: "flat ends stop at the point");
    });

    test("a joint taken out breaks every line there; a point joins up", () {
      var e = drawing('<path d="M10 10 L30 10 L50 10 L70 10 L90 10" '
          'stroke="black" fill="none"/>');
      var (branched, _) =
          withPenPoint(e, const VectorPick(0, 0, 2), const Offset(150, 150));
      (branched, _) = withPenPoint(
          branched, const VectorPick(0, 1, 1), const Offset(150, 190));
      List<List<Offset>> runs(VectorElement e) => [
            for (var r in e.shapes!.single.paths)
              [for (var n in r.nodes) n.point]
          ];
      // Picked from the branch's end: the line through it breaks too.
      var gone = withoutPoints(branched, {const VectorPick(0, 1, 0)});
      expect(runs(gone), [
        [const Offset(10, 10), const Offset(30, 10)],
        [const Offset(70, 10), const Offset(90, 10)],
        [const Offset(50, 50), const Offset(50, 90)],
      ]);
      // A point no other line meets is still joined across.
      var bridged = withoutPoints(e, {const VectorPick(0, 0, 1)});
      expect(runs(bridged).single, hasLength(4));
      // A closed run broken at a joint opens there.
      var closed = drawing('$square<path d="M10 10 L0 0" stroke="black"/>');
      var opened = withoutPoints(closed, {const VectorPick(0, 0, 0)});
      var run = opened.shapes!.first.paths.single;
      expect(run.closed, isFalse);
      expect([for (var n in run.nodes) n.point],
          const [Offset(90, 10), Offset(90, 90), Offset(10, 90)]);
    });

    test("shapes combined draw as one, and part again", () async {
      var e = drawing('$square<path d="M40 40 L60 40 L60 60 L40 60 Z" '
          'fill="blue"/><path d="M0 0 L5 0 L5 5 Z" fill="green"/>');
      var (cut, at) = withCombined(e, {1, 0}, VectorCombine.subtract);
      expect(at, 0);
      expect(groupMembers(cut, 0), [0, 1]);
      expect(groupOf(cut, 1), 0);
      Future<List<int>> draw(VectorElement e) async {
        var rec = PictureRecorder();
        paintVector(Canvas(rec), const Rect.fromLTWH(0, 0, 100, 100), e, null);
        var img = await rec.endRecording().toImage(100, 100);
        return (await img.toByteData())!.buffer.asUint8List();
      }

      var px = await draw(cut);
      int alpha(int x, int y) => px[(y * 100 + x) * 4 + 3];
      expect(alpha(50, 50), 0, reason: "a hole where the blue was");
      expect(px[(20 * 100 + 20) * 4], greaterThan(200), reason: "red round it");
      var back = (elementFromJson(
              jsonDecode(jsonEncode(cut.toJson())) as Map<String, dynamic>)
          as VectorElement);
      expect(back.shapes![1].combine, VectorCombine.subtract);

      // Moved up next to the shape it combines into, past the green one.
      var (joined, _) = withCombined(e, {0, 2}, VectorCombine.unite);
      expect([for (var s in joined.shapes!) s.combine],
          [null, VectorCombine.unite, null]);
      expect(joined.shapes![1].fill, const Color(0xFF008000));

      // Its first shape taken out, the next is a shape of its own.
      var lost = withoutPoints(cut, picksOfAll(cut, 0));
      expect(lost.shapes!.first.combine, isNull);

      expect(withSeparated(cut, 0).shapes![1].combine, isNull);
    });

    test("a tint stroke is laid down, carried on, and kept", () {
      var e = drawing(square);
      var like = const VectorTint(
          points: [],
          paint: PaintSpec(Color(0xFFFF0000),
              gradient: GradientSpec(to: Color(0xFF0000FF))),
          width: 8,
          fill: false);
      var two =
          painted(e, like, const Offset(120, 150), const Offset(180, 150));
      var laid = tintsOf(two);
      expect(laid, hasLength(1), reason: "on the square it went over");
      expect(laid.single.points.first, const Offset(20, 50));
      expect(laid.single.points.last, const Offset(80, 50));
      var back = (elementFromJson(
              jsonDecode(jsonEncode(two.toJson())) as Map<String, dynamic>)
          as VectorElement);
      var t = tintsOf(back).single;
      expect(t.points, laid.single.points);
      expect(t.paint, like.paint);
      expect([t.width, t.line, t.fill, t.erase], [8, true, false, false]);
    });

    test("a tint shows only on the drawing: its fill, its line, or both",
        () async {
      Future<List<int>> draw(VectorElement e) async {
        var rec = PictureRecorder();
        paintVector(Canvas(rec), const Rect.fromLTWH(0, 0, 100, 100), e, null);
        var img = await rec.endRecording().toImage(100, 100);
        var data = await img.toByteData();
        return data!.buffer.asUint8List();
      }

      Color at(List<int> px, int x, int y) {
        var i = (y * 100 + x) * 4;
        return Color.fromARGB(px[i + 3], px[i], px[i + 1], px[i + 2]);
      }

      // A grey square with a thick black edge, and a hard red stroke right
      // across it, past both sides.
      var e = drawing('<path d="M20 20 L80 20 L80 80 L20 80 Z" '
          'fill="#808080" stroke="#000000" stroke-width="6"/>');
      VectorElement tinted({bool line = true, bool fill = true}) => painted(
          e,
          VectorTint(
              points: const [],
              paint: const PaintSpec(Color(0xFFFF0000)),
              width: 10,
              soft: 0,
              line: line,
              fill: fill),
          const Offset(105, 150),
          const Offset(195, 150));

      var px = await draw(tinted());
      expect(at(px, 50, 50).r, greaterThan(0.9), reason: "on the fill");
      expect(at(px, 20, 50).r, greaterThan(0.9), reason: "on the line");
      expect(at(px, 10, 50).a, 0, reason: "nothing off the drawing");
      expect(at(px, 50, 30).r, closeTo(0.5, 0.05), reason: "not painted");

      px = await draw(tinted(line: false));
      expect(at(px, 50, 50).r, greaterThan(0.9));
      expect(at(px, 20, 50).r, lessThan(0.1), reason: "the line left black");

      px = await draw(tinted(fill: false));
      expect(at(px, 50, 50).r, closeTo(0.5, 0.05), reason: "the fill left");
      expect(at(px, 20, 50).r, greaterThan(0.9));

      // Rubbed out again by an eraser over half of it.
      var rubbed = tinted();
      rubbed = painted(
          rubbed,
          const VectorTint(
              points: [],
              paint: PaintSpec(Color(0xFF000000)),
              width: 20,
              soft: 0,
              erase: true),
          const Offset(150, 150),
          const Offset(195, 150));
      px = await draw(rubbed);
      expect(at(px, 30, 50).r, greaterThan(0.9));
      expect(at(px, 70, 50).r, closeTo(0.5, 0.05), reason: "rubbed off");
    });

    test("tints and rub-outs are their shapes': what comes later is its own",
        () async {
      Future<List<int>> draw(VectorElement e) async {
        var rec = PictureRecorder();
        paintVector(Canvas(rec), const Rect.fromLTWH(0, 0, 100, 100), e, null);
        var img = await rec.endRecording().toImage(100, 100);
        return (await img.toByteData())!.buffer.asUint8List();
      }

      Color at(List<int> px, int x, int y) {
        var i = (y * 100 + x) * 4;
        return Color.fromARGB(px[i + 3], px[i], px[i + 1], px[i + 2]);
      }

      var e = drawing('<path d="M20 20 L80 20 L80 80 L20 80 Z" '
          'fill="#808080"/>');
      var red = const VectorTint(
          points: [], paint: PaintSpec(Color(0xFFFF0000)), width: 20, soft: 0);
      var tinted =
          painted(e, red, const Offset(105, 150), const Offset(195, 150));
      // A blue shape drawn afterwards, over the tint.
      var later = tinted.copyWith(shapes: [
        ...tinted.shapes!,
        const VectorShape(paths: [
          VectorPath([
            VectorNode(40, 40),
            VectorNode(60, 40),
            VectorNode(60, 60),
            VectorNode(40, 60)
          ], closed: true)
        ], fill: Color(0xFF0000FF)),
      ]);
      var px = await draw(later);
      expect(at(px, 50, 50).b, greaterThan(0.9),
          reason: "the shape drawn later is its own colour");
      expect(at(px, 30, 50).r, greaterThan(0.9),
          reason: "the square under the tint still tinted");

      // So with a rub-out: a shape drawn after it is whole.
      var rubbed = painted(
          e,
          const VectorTint(
              points: [],
              paint: PaintSpec(Color(0xFF000000)),
              width: 20,
              soft: 0,
              erase: true),
          const Offset(105, 150),
          const Offset(195, 150),
          rubOut: true);
      later = rubbed.copyWith(shapes: [...rubbed.shapes!, later.shapes!.last]);
      px = await draw(later);
      expect(at(px, 50, 50).a, 1.0, reason: "drawn after: not rubbed out");
      expect(at(px, 30, 50).a, 0, reason: "the square rubbed out");

      // Moved whole, a shape takes its tint with it.
      var moved =
          withPointsMoved(tinted, picksOfAll(tinted, 0), const Offset(5, 0));
      expect(tintsOf(moved).single.points.first.dx,
          tintsOf(tinted).single.points.first.dx + 5);
    });

    test("tints kept for the whole drawing, before, go to its shapes", () {
      var json =
          drawing('$square<path d="M0 95 L5 95" stroke="black"/>').toJson();
      json["tints"] = [
        {
          "p": [30, 50, 70, 50],
          "c": 0xFFFF0000,
          "w": 4,
        }
      ];
      var e = elementFromJson(json) as VectorElement;
      expect(e.shapes!.first.tints, hasLength(1), reason: "under it");
      expect(e.shapes!.last.tints, isEmpty, reason: "nowhere near it");
    });

    test("a drawing saved mid-edit opens with its box round it", () {
      // The box 100 square, but a line drawn out past it to (150, 50).
      var stale = drawing('<path d="M10 50 L150 50" stroke="black"/>');
      var c = CanvasController(const CanvasDocument());
      addTearDown(c.dispose);
      c.load(const CanvasDocument().addElement(stale));
      var e = c.document.elementById("v") as VectorElement;
      expect(e.width, greaterThan(100), reason: "fitted on opening");
      expect(e.viewBox.right, closeTo(150, 1));
    });

    test("Fill covers the box, cut off rather than squashed", () {
      var e = VectorElement(const ElementBase(id: "v"),
          viewBox: const Rect.fromLTWH(0, 0, 100, 50), fit: VectorFit.cover);
      var p = e.placement(const Rect.fromLTWH(0, 0, 100, 100), e.viewBox);
      expect([p.sx, p.sy], [2, 2]);
      expect(p.dx, -50, reason: "centred, its sides cut off");
    });
  });

  // A point dragged out past the drawing's box: when the editing is left,
  // the box grows to take it in -- and the drawing does not move on the page.
  group("the box after editing", () {
    void samePlace(VectorElement before, VectorElement after) {
      for (var (i, shape) in before.shapes!.indexed) {
        for (var (p, path) in shape.paths.indexed) {
          for (var (n, node) in path.nodes.indexed) {
            var was = VectorSpace(before).toCanvas(node.point);
            var now = VectorSpace(after)
                .toCanvas(after.shapes![i].paths[p].nodes[n].point);
            expect((now - was).distance, lessThan(1e-6),
                reason: "point $i/$p/$n stays where it was on the page");
          }
        }
      }
    }

    for (var turn in [0.0, 30.0]) {
      test("grows to the whole drawing, turned $turn", () {
        var e = drawing(square, rotation: turn);
        // Out past the right edge of the drawing's own 100 units.
        var out = withPointsMoved(
            e, {const VectorPick(0, 0, 1)}, const Offset(50, 0));
        var fitted = boxedToDrawing(out);
        // The square ran 10 to 90; its corner is out at 140 now.
        expect(fitted.viewBox.left, closeTo(10, 1e-6));
        expect(fitted.viewBox.right, closeTo(140, 1e-6));
        expect(fitted.width, closeTo(130, 1e-6),
            reason: "a canvas unit to a drawing unit, as before");
        samePlace(out, fitted);
      });
    }

    // Room to spare in the drawing's space -- the file's own margin, or what
    // points moved in leave behind -- is taken in, so the box is round the
    // drawing and nothing else.
    test("drawn in to the drawing where there is room to spare", () {
      var e = drawing(square);
      var fitted = boxedToDrawing(e);
      expect(fitted.viewBox, const Rect.fromLTRB(10, 10, 90, 90));
      expect(fitted.bounds, const Rect.fromLTRB(110, 110, 190, 190));
      samePlace(e, fitted);
    });

    // A curve's handles reach further than the curve does; the box goes to
    // the curve. (A path's own bounds go to the handles.)
    test("to the curve, not out to its handles", () {
      var shape = drawing(curve).shapes!.single;
      var extent = shapeExtent(shape)!;
      expect(extent.top, closeTo(12.5 - 0.5, 1e-6),
          reason: "the top of the curve, less half its line");
      expect(shape.path.getBounds().top, closeTo(0, 1e-6),
          reason: "where its handles are");
    });

    test("is grown as the editing is left", () {
      var c =
          CanvasController(const CanvasDocument().addElement(drawing(square)));
      addTearDown(c.dispose);
      c.selectOnly("v");
      c.editVector("v");
      var e = c.editingVector!;
      c.replaceElement(
          withPointsMoved(e, {const VectorPick(0, 0, 2)}, const Offset(0, 60)));
      c.editVector(null);
      var after = c.document.elementById("v") as VectorElement;
      // The square ran 10 to 90 down; its corner is at 150 now.
      expect(after.height, closeTo(140, 1e-6));
      c.selectOnly("v");
      c.editVector("v");
      c.clearSelection();
      expect((c.document.elementById("v") as VectorElement).height,
          closeTo(140, 1e-6),
          reason: "and nothing more to fit");
    });
  });

  group("the controller's picks", () {
    test("Shift adds and takes away; one picked shows its handles", () {
      var c =
          CanvasController(const CanvasDocument().addElement(drawing(square)));
      addTearDown(c.dispose);
      c.selectOnly("v");
      c.editVector("v");
      c.pickVectorPoint(const VectorPick(0, 0, 0));
      expect(c.vectorPick, const VectorPick(0, 0, 0));
      c.pickVectorPoint(const VectorPick(0, 0, 1), toggle: true);
      expect(c.vectorPicks, hasLength(2));
      expect(c.vectorPick, isNull, reason: "handles for one point only");
      c.pickVectorPoint(const VectorPick(0, 0, 0), toggle: true);
      expect(c.vectorPicks, {const VectorPick(0, 0, 1)});
      c.vectorPen = true;
      c.editVector(null);
      expect([c.vectorPen, c.vectorPicks.isEmpty], [false, true],
          reason: "leaving puts it all away");
    });
  });

  group("a background drawing", () {
    test("a background picture that was a drawing is the drawing now", () {
      var bg = CanvasBackground.fromJson({
        "picture": {
          "kind": "image",
          "id": "p",
          "asset": "0123456789abcdef.svg",
          "fit": "cover"
        },
      });
      expect(bg.picture, isNull);
      expect(bg.drawing?.assetId, "0123456789abcdef.svg");
      expect(bg.drawing?.fit, VectorFit.cover);
      var old = CanvasBackground.fromJson(
          {"image": "fedcba9876543210.svg", "fit": "contain"});
      expect(old.imageAssetId, isEmpty);
      expect(old.drawing?.fit, VectorFit.contain);
    });

    test("is saved, and keeps its file", () {
      var bg = CanvasBackground(
          drawing: const VectorElement(ElementBase(id: "d"),
              assetId: "0123456789abcdef.svg", fit: VectorFit.cover));
      var back = CanvasBackground.fromJson(bg.toJson());
      expect(back.drawing?.assetId, "0123456789abcdef.svg");
      expect(back.mediaIds, contains("0123456789abcdef.svg"));
    });
  });
}
