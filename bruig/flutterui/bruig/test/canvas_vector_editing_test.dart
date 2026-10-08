import 'dart:io';
import 'dart:ui';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/svg_import.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
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

    testWidgets("a drawing not yet edited offers Edit points, no colours",
        (tester) async {
      await show(
          tester,
          const VectorElement(ElementBase(id: "v"),
              assetId: "0123456789abcdef.svg"));
      expect(find.byKey(const ValueKey("vectorEdit")), findsOneWidget);
      expect(find.byKey(const ValueKey("vectorShapeGroup")), findsNothing);
      expect(find.byKey(const ValueKey("vectorHandleColour")), findsNothing);
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
      expect(find.byKey(const ValueKey("vectorHandleColour")), findsOneWidget);

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
          withPenPoint(e, -1, const Offset(110, 120), like: like);
      expect(first, const VectorPick(0, 0, 0));
      expect(one.shapes!.single.stroke, const Color(0xFFFF0000));
      expect(one.shapes!.single.strokeWidth, 4);
      var (two, second) = withPenPoint(one, 0, const Offset(150, 120));
      expect(second, const VectorPick(0, 0, 1));
      var curved = withPenHandles(two, second, const Offset(160, 120));
      var n = curved.shapes!.single.paths.single.nodes[1];
      expect([n.outX, n.inX, n.smooth], [10, -10, true]);
      expect(
          withPenClosed(curved, 0).shapes!.single.paths.single.closed, isTrue);
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
