import 'dart:io';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/layout_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/layout_presets.dart';
import 'package:bruig/plugin_system/canvas/model/layout_sync.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart' show SizedBox, GlobalKey, ValueKey;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'support/canvas_app.dart';

// canvas_layout_test.dart is the Layout element (layout_element.dart): a
// box divided into cells as Panels (cuts), a Grid (tracks) or Free shapes,
// and elements docked in its cells. Ken, 2026-11-18: comic panels "that
// can be reused and customised to change the panels lines positions,
// width, angle, stroke", box layouts "fully customised", that "could even
// act as masks". Set LAYOUT_PNG to a folder to see every preset drawn.

const _box = ElementBase(id: "L", x: 100, y: 100, width: 1000, height: 1400);
const _bounds = Rect.fromLTWH(100, 100, 1000, 1400);

LayoutElement _two(
        {bool vertical = true, double tilt = 0, double gutter = 20}) =>
    LayoutElement(_box,
        root: LayoutNode.cut(
            vertical: vertical,
            tilt: tilt,
            a: const LayoutNode.leaf("a"),
            b: const LayoutNode.leaf("b")),
        cells: const [LayoutCell(id: "a"), LayoutCell(id: "b")],
        gutter: gutter,
        rowGutter: gutter);

void main() {
  group("Panels", () {
    test("a cut leaves its gutter between two cells", () {
      var places = layoutPlaces(_two(), _bounds);
      expect(places.map((p) => p.cell.id), ["a", "b"]);
      var a = places[0].bounds, b = places[1].bounds;
      expect(a.left, 100);
      expect(b.right, 1100);
      expect(b.left - a.right, closeTo(20, 1e-6), reason: "the gutter");
      expect(a.right, closeTo(590, 1e-6), reason: "halfway, less half of it");
    });

    test("a tilted cut slants both edges", () {
      var places = layoutPlaces(_two(tilt: 10), _bounds);
      var a = places.first.points;
      var topRight = a.reduce(
          (p, q) => p.dy < q.dy || (p.dy == q.dy && p.dx > q.dx) ? p : q);
      var bottomRight = a.reduce(
          (p, q) => p.dy > q.dy || (p.dy == q.dy && p.dx > q.dx) ? p : q);
      expect((topRight.dx - bottomRight.dx).abs(), greaterThan(100),
          reason: "the edge runs at a slant, not straight down");
    });

    test("a cell is split, and merged back", () {
      var e = _two();
      var (cut, fresh) = e.split("b", vertical: false);
      expect(cut.root.cells, ["a", "b", fresh]);
      expect(layoutPlaces(cut, _bounds), hasLength(3));
      var (merged, gone) = cut.merge("b");
      expect(gone, [fresh]);
      expect(merged.root.cells, ["a", "b"]);
    });

    test("a cut's line can be grabbed, and moved to a point", () {
      var e = _two();
      var line = layoutCutLines(e, _bounds).single;
      expect(line.from.dx, closeTo(600, 1e-6));
      var at = cutAtPoint(e.root, line.box, const Offset(350, 700));
      expect(at, closeTo(0.25, 1e-6));
    });

    test("a received tree too deep, or junk, is read safely", () {
      Map<String, dynamic> deep(int n) => n == 0
          ? {"cell": "x"}
          : {
              "at": 0.5,
              "a": deep(n - 1),
              "b": {"cell": "y$n"}
            };
      var e = LayoutElement.fromJson({"root": deep(400)}, _box);
      expect(e.root.cells.length, lessThanOrEqualTo(13));
      var junk = LayoutElement.fromJson({"root": "nonsense", "cells": 3}, _box);
      expect(junk.root.isLeaf, isTrue);
    });
  });

  group("Grid", () {
    test("tracks by weight, cells spanning them, gaps between", () {
      var e = LayoutElement(_box,
          mode: LayoutMode.grid,
          columns: const [1, 3],
          rows: const [1],
          gutter: 40,
          margin: 30,
          cells: const [
            LayoutCell(id: "w", col: 0, row: 0),
            LayoutCell(id: "x", col: 1, row: 0),
          ]);
      var p = layoutPlaces(e, _bounds);
      // 1000 less 60 of margin, less 40 of gap: 900, split 1 to 3.
      expect(p[0].bounds.width, closeTo(225, 1e-6));
      expect(p[1].bounds.width, closeTo(675, 1e-6));
      expect(p[1].bounds.left - p[0].bounds.right, closeTo(40, 1e-6));
      expect(p[0].bounds.left, 130);
    });

    test("a line between tracks moves the two beside it", () {
      var w = tracksMoved(const [1, 1], 0, 100, 1000, 0);
      expect(w[0], closeTo(1.2, 1e-9));
      expect(w[1], closeTo(0.8, 1e-9));
      expect(w[0] + w[1], closeTo(2, 1e-9), reason: "the rest unchanged");
    });
  });

  group("Free", () {
    test("each shape in its share of the box", () {
      var e = layoutFrom(_box, LayoutPreset.circles);
      var p = layoutPlaces(e, _bounds);
      expect(p, hasLength(3));
      expect(p.first.path.contains(p.first.bounds.center), isTrue);
      expect(p.first.path.contains(p.first.bounds.topLeft + const Offset(2, 2)),
          isFalse,
          reason: "an ellipse misses its corners");
    });
  });

  test("every preset reads back as written", () {
    for (var p in LayoutPreset.values) {
      var e = layoutFrom(_box, p);
      var back = LayoutElement.fromJson(e.props(), _box);
      expect(back.props(), e.props(), reason: p.name);
      expect(layoutPlaces(back, _bounds), isNotEmpty, reason: p.name);
    }
  });

  group("docking", () {
    test("a docked element follows its cell as a cut moves", () {
      var layout = _two();
      var a = layoutPlaceOf(layout, layout.bounds, "a")!.bounds;
      var docked = ShapeElement(ElementBase(
          id: "s",
          x: a.left + 10,
          y: a.top + 10,
          width: a.width - 20,
          height: 200,
          dock: "L:a"));
      var was = const CanvasDocument().addElement(layout).addElement(docked);
      var moved = layout.copyWith(root: layout.root.withCut(at: 0.25));
      var now = layoutsSynced(was, was.withElement(moved));
      var s = now.elementById("s")!;
      var cell = layoutPlaceOf(moved, moved.bounds, "a")!.bounds;
      expect(s.x, closeTo(cell.left + 10 * cell.width / a.width, 1e-6));
      expect(s.width, closeTo((a.width - 20) * cell.width / a.width, 1e-6));
      expect(s.height, 200, reason: "the cell's height did not change");
    });

    test("one moved in the same change stays where it was put", () {
      var layout = _two();
      var docked = ShapeElement(const ElementBase(id: "s", dock: "L:a"));
      var was = const CanvasDocument().addElement(layout).addElement(docked);
      var both = was
          .withElement(layout.withBase(x: 300))
          .withElement(docked.withBase(x: 300));
      expect(layoutsSynced(was, both).elementById("s")!.x, 300);
    });

    test("merging a cell docks what was in it in the cell left", () {
      var layout = _two();
      var c = CanvasController(const CanvasDocument()
          .addElement(layout)
          .addElement(ShapeElement(const ElementBase(id: "s", dock: "L:b"))));
      addTearDown(c.dispose);
      c.removeLayoutCell(layout, "b");
      var l = c.document.elementById("L") as LayoutElement;
      expect(l.root.isLeaf, isTrue);
      expect(c.document.elementById("s")!.base.dock, "L:a");
    });

    testWidgets("a docked element is drawn inside its cell only",
        (tester) async {
      // The left cell; a red square docked in it reaching over the gutter.
      var layout = _two(gutter: 100);
      var a = layoutPlaceOf(layout, layout.bounds, "a")!.bounds;
      var red = ShapeElement(
          ElementBase(
              id: "s",
              x: a.right - 100,
              y: 300,
              width: 300,
              height: 300,
              dock: "L:a"),
          fill: const Color(0xFFFF0000));
      var doc = const CanvasDocument(
              size: CanvasSize(ratio: CanvasRatio.a4, width: 1240))
          .addElement(layout.copyWith(cellStyle: const BoxSpec(padding: 0)))
          .addElement(red);
      Future<Color> at(CanvasDocument d, Offset p) async {
        var rec = ui.PictureRecorder();
        paintCanvasDocument(ui.Canvas(rec), d, frame: 0);
        var pic = rec.endRecording();
        var img = await tester.runAsync(
            () => pic.toImage(d.size.width.round(), d.size.height.round()));
        var bytes = await tester.runAsync(
            () => img!.toByteData(format: ui.ImageByteFormat.rawRgba));
        var i = (p.dy.round() * img!.width + p.dx.round()) * 4;
        return Color.fromARGB(bytes!.getUint8(i + 3), bytes.getUint8(i),
            bytes.getUint8(i + 1), bytes.getUint8(i + 2));
      }

      expect(await at(doc, Offset(a.right - 20, 400)), const Color(0xFFFF0000));
      expect(await at(doc, Offset(a.right + 40, 400)),
          isNot(const Color(0xFFFF0000)),
          reason: "clipped at the cell's edge, in the gutter");
      var out = doc.withElement(red.withBase(dockOut: true));
      expect(await at(out, Offset(a.right + 40, 400)), const Color(0xFFFF0000),
          reason: "breaking out, it reaches over");
    });
  });

  testWidgets("every preset, drawn", (tester) async {
    var dir = Platform.environment["LAYOUT_PNG"];
    if (dir == null) return;
    Directory(dir).createSync(recursive: true);
    for (var p in LayoutPreset.values) {
      var doc = const CanvasDocument(
              size: CanvasSize(ratio: CanvasRatio.a4, width: 1240))
          .addElement(layoutFrom(
              const ElementBase(
                  id: "L", x: 60, y: 60, width: 1120, height: 1634),
              p));
      var rec = ui.PictureRecorder();
      paintCanvasDocument(ui.Canvas(rec), doc, frame: 0);
      var pic = rec.endRecording();
      await tester.runAsync(() async {
        var img = await pic.toImage(1240, doc.size.height.round());
        var png = await img.toByteData(format: ui.ImageByteFormat.png);
        File("$dir/${p.name}.png").writeAsBytesSync(png!.buffer.asUint8List());
      });
    }
  });

  group("on the canvas", () {
    Future<(CanvasController, CanvasStageState)> stage(
        WidgetTester tester, CanvasDocument doc) async {
      var c = CanvasController(doc);
      addTearDown(c.dispose);
      var key = GlobalKey<CanvasStageState>();
      setTestScreen(tester, const Size(1000, 1000));
      await tester.pumpWidget(canvasApp(SizedBox(
          width: 1000,
          height: 1000,
          child: CanvasStage(key: key, controller: c))));
      await tester.pumpAndSettle();
      return (c, key.currentState!);
    }

    CanvasDocument page(LayoutElement l) => const CanvasDocument(
            size: CanvasSize(ratio: CanvasRatio.a4, width: 1240))
        .addElement(l);

    double scaleOf(CanvasStageState s) =>
        (s.toStagePoint(const Offset(100, 0)) - s.toStagePoint(Offset.zero))
            .dx /
        100;

    testWidgets("a double-click picks the cell under it", (tester) async {
      var (c, s) = await stage(tester, page(_two()));
      c.selectOnly("L");
      await tester.pumpAndSettle();
      var at = s.toStagePoint(const Offset(900, 800));
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(c.layoutCell("L"), "b");
      expect(c.selection, {"L"});
    });

    testWidgets("a cut is dragged to move it", (tester) async {
      var (c, s) = await stage(tester, page(_two()));
      c.selectOnly("L");
      await tester.pumpAndSettle();
      await tester.timedDragFrom(s.toStagePoint(const Offset(600, 500)),
          Offset(-250 * scaleOf(s), 0), const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      var l = c.document.elementById("L") as LayoutElement;
      expect(l.root.at, closeTo(0.25, 0.01));
      expect(l.x, 100, reason: "the layout itself did not move");
    });

    testWidgets("Delete on a picked cell merges it", (tester) async {
      var (c, s) = await stage(tester, page(_two()));
      c.selectOnly("L");
      await tester.pumpAndSettle();
      // A click on the page gives it the keys; a double-click picks "b".
      var at = s.toStagePoint(const Offset(900, 800));
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(c.layoutCell("L"), "b");
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      var l = c.document.elementById("L") as LayoutElement?;
      expect(l, isNotNull, reason: "the layout stays");
      expect(l!.root.isLeaf, isTrue);
    });

    testWidgets("a picked Free cell is moved by its own box", (tester) async {
      var l = layoutFrom(_box, LayoutPreset.circles);
      var (c, s) = await stage(tester, page(l));
      c.selectOnly("L");
      var first = l.cells.first;
      c.pickLayoutCell("L", first.id);
      await tester.pumpAndSettle();
      var at = layoutPlaceOf(l, _bounds, first.id)!.bounds.center;
      await tester.timedDragFrom(s.toStagePoint(at),
          Offset(100 * scaleOf(s), 0), const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      var moved =
          (c.document.elementById("L") as LayoutElement).cellById(first.id)!;
      expect(moved.x, closeTo(first.x + 100 / 1000, 0.005));
    });
  });

  group("in the settings", () {
    testWidgets("a picked cell is cut down, and docked in", (tester) async {
      var doc = const CanvasDocument()
          .addElement(_two())
          .addElement(ShapeElement(const ElementBase(id: "s")));
      var c = CanvasController(doc);
      addTearDown(c.dispose);
      c.selectOnly("L");
      c.pickLayoutCell("L", "a");
      setTestScreen(tester, const Size(1400, 1400));
      await tester.pumpWidget(canvasApp(CanvasDesignPanel(controller: c)));
      await tester.pumpAndSettle();
      var cut = find.byKey(const ValueKey("layoutSplitDown"));
      await tester.ensureVisible(cut);
      await tester.pumpAndSettle();
      await tester.tap(cut);
      await tester.pumpAndSettle();
      var l = c.document.elementById("L") as LayoutElement;
      expect(l.root.cells, hasLength(3));

      // Another element's Layout section offers the cells.
      c.selectOnly("s");
      await tester.pumpAndSettle();
      if (find.byKey(const ValueKey("dockCell")).evaluate().isEmpty) {
        var heading = find.descendant(
            of: find.byKey(const ValueKey("elementSection-layout")),
            matching: find.text("Layout"));
        await tester.ensureVisible(heading.first);
        await tester.pumpAndSettle();
        await tester.tap(heading.first);
        await tester.pumpAndSettle();
      }
      var dock = find.byKey(const ValueKey("dockCell"));
      await tester.ensureVisible(dock);
      await tester.pumpAndSettle();
      await tester.tap(dock);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining("Cell 1").last);
      await tester.pumpAndSettle();
      expect(c.document.elementById("s")!.base.dock, "L:a");
    });
  });
}
