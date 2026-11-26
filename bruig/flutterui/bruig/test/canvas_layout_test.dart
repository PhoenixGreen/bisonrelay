import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/layout_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/layout_presets.dart';
import 'package:bruig/plugin_system/canvas/model/layout_sync.dart';
import 'package:bruig/plugin_system/canvas/model/outline_points.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/render/layout_painter.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart'
    show CustomPaint, SizedBox, GlobalKey, ValueKey;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_painter.dart';
import 'support/canvas_app.dart';
import 'support/canvas_sidebar_host.dart';

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

    test("a cell is split, and the new half removed again", () {
      var e = _two();
      var (cut, fresh) = e.split("b", vertical: false);
      expect(cut.root.cells, ["a", "b", fresh]);
      expect(layoutPlaces(cut, _bounds), hasLength(3));
      var (back, into) = cut.removeCell(fresh);
      expect(into, "b");
      expect(back.root.cells, ["a", "b"]);
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

    // A cell's straight-sided outlines are the shapes' own (outline_points
    // .dart); its hexagon and star keep their own numbers, so a saved
    // layout looks as it did: a corner at each side, and a shallower cut.
    test("a cell's outline is the shape's, with a cell's own numbers", () {
      const r = Rect.fromLTWH(100, 100, 400, 300);
      List<Offset> cornersOf(LayoutCellShape shape) => layoutPlaces(
              LayoutElement(_box,
                  mode: LayoutMode.free,
                  margin: 0,
                  cellStyle: const BoxSpec(),
                  cells: [
                    LayoutCell(
                        id: "c",
                        x: 0,
                        y: 0,
                        width: 0.4,
                        height: 300 / 1400,
                        shape: shape)
                  ]),
              _bounds)
          .single
          .points;
      void same(List<Offset> a, List<Offset> b) {
        expect(a.length, b.length);
        for (var (i, p) in a.indexed) {
          expect((p - b[i]).distance, lessThan(1e-9), reason: "corner $i");
        }
      }

      same(cornersOf(LayoutCellShape.triangle), trianglePoints(r));
      same(cornersOf(LayoutCellShape.diamond), diamondPoints(r));
      var hexagon = cornersOf(LayoutCellShape.hexagon);
      same(hexagon, regularPoints(r.center, 200, 150, 6, start: 0));
      expect((hexagon.first - r.centerRight).distance, lessThan(1e-9),
          reason: "a cell's hexagon has a corner at its side");
      var star = cornersOf(LayoutCellShape.star);
      same(star, regularPoints(r.center, 200, 150, 10, inner: 0.45));
      expect(
          (star[1] - r.center).distance,
          greaterThan(
              (regularPoints(r.center, 200, 150, 10, inner: 0.42)[1] - r.center)
                  .distance),
          reason: "cut less deep than a Shape's star");
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
    // Ken, 2026-11-18: moving and editing gutters "shouldn't edit the
    // content in the panel e.g. it shouldn't make the content of a panel
    // smaller or cropped"; what goes outside is hidden, and shows with the
    // layout hidden.
    test("a cut moved, tilted or widened leaves what is docked be", () {
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
      for (var edit in [
        layout.root.withCut(at: 0.25),
        layout.root.withCut(tilt: 12),
        layout.root.withCut(gutter: 120),
      ]) {
        var now =
            layoutsSynced(was, was.withElement(layout.copyWith(root: edit)));
        var s = now.elementById("s")!;
        expect(s.bounds, docked.bounds, reason: "not moved, sized or cut");
      }
      // And the layout resized from its far corner.
      var bigger = layout.withBase(width: 600, height: 900);
      expect(
          layoutsSynced(was, was.withElement(bigger)).elementById("s")!.bounds,
          docked.bounds);
    });

    test("the whole layout moved carries what is docked with it", () {
      var layout = _two();
      var docked = ShapeElement(const ElementBase(
          id: "s", x: 150, y: 160, width: 80, height: 90, dock: "L:a"));
      var loose = ShapeElement(const ElementBase(id: "t", x: 150));
      var was = const CanvasDocument()
          .addElement(layout)
          .addElement(docked)
          .addElement(loose);
      var now =
          layoutsSynced(was, was.withElement(layout.withBase(x: 130, y: 70)));
      var s = now.elementById("s")!;
      expect(s.bounds, const Rect.fromLTWH(180, 130, 80, 90),
          reason: "by as far as the layout went, its size kept");
      expect(now.elementById("t")!.x, 150, reason: "not docked: not moved");
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

    test("a dock is saved as it always was, and read back", () {
      var docked = ShapeElement(const ElementBase(id: "s", dock: "L:a"));
      expect(docked.base.docked, const LayoutDock("L", "a"));
      expect(docked.base.toJson()["dock"], "L:a");
      expect(ElementBase.fromJson(docked.base.toJson(), "Shape").docked,
          const LayoutDock("L", "a"));
      expect(const LayoutDock("L", "a").toJson(), "L:a");
      for (var none in ["", "L:", ":a", "La"]) {
        expect(LayoutDock.read(none), isNull, reason: "'$none' names no cell");
      }
      expect(const ElementBase(id: "t").docked, isNull);
    });

    test("only what is docked in a cell the layout has moves with it", () {
      var layout = _two();
      var stray = ShapeElement(const ElementBase(id: "s", x: 10, dock: "L:x"));
      var was = const CanvasDocument().addElement(layout).addElement(stray);
      var now = layoutsSynced(was, was.withElement(layout.withBase(x: 300)));
      expect(now.elementById("s")!.x, 10, reason: "no cell x in L");
    });

    // A preset makes every cell afresh, with new ids: what was docked in
    // the old ones is let go where it is, as the tile says, not left docked
    // in nothing and still carried about with the layout.
    testWidgets("choosing a preset lets go of what was docked in it",
        (tester) async {
      var doc = const CanvasDocument().addElement(_two()).addElement(
          ShapeElement(
              const ElementBase(id: "s", x: 150, y: 160, dock: "L:a")));
      var c = CanvasController(doc);
      addTearDown(c.dispose);
      c.selectOnly("L");
      setTestScreen(tester, const Size(1400, 1400));
      await tester.pumpWidget(canvasApp(designSidebar(c)));
      await tester.pumpAndSettle();
      var tile = find.byKey(const ValueKey("layoutPreset-sixPanels"));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      var s = c.document.elementById("s")!;
      expect(s.base.dock, "", reason: "its cell has gone");
      expect(s.bounds.topLeft, const Offset(150, 160), reason: "where it was");
      var l = c.document.elementById("L") as LayoutElement;
      c.setLayout(l.withBase(x: 400) as LayoutElement);
      expect(c.document.elementById("s")!.x, 150,
          reason: "not carried with the layout");
      c.undo();
      c.undo();
      expect(c.document.elementById("s")!.base.dock, "L:a",
          reason: "undone with the preset");
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
      var hidden =
          doc.withElement(doc.elementById("L")!.withBase(visible: false));
      expect(
          await at(hidden, Offset(a.right + 40, 400)), const Color(0xFFFF0000),
          reason: "the layout hidden, all of what is docked shows");
    });

    // A layout slanted, or moved by its keys, is drawn there, and what is
    // docked in it is drawn through its cell where the cell is drawn, not
    // where it would be upright and at rest.
    testWidgets("a docked element is cut to its cell as the layout is drawn",
        (tester) async {
      Future<Color> at(CanvasDocument d, Offset p, {int frame = 0}) async {
        var rec = ui.PictureRecorder();
        paintCanvasDocument(ui.Canvas(rec), d, frame: frame);
        var pic = rec.endRecording();
        var img = await tester.runAsync(
            () => pic.toImage(d.size.width.round(), d.size.height.round()));
        var bytes = await tester.runAsync(
            () => img!.toByteData(format: ui.ImageByteFormat.rawRgba));
        var i = (p.dy.round() * img!.width + p.dx.round()) * 4;
        return Color.fromARGB(bytes!.getUint8(i + 3), bytes.getUint8(i),
            bytes.getUint8(i + 1), bytes.getUint8(i + 2));
      }

      const red = Color(0xFFFF0000);
      // Cell a is left of 550 at rest; the red square covers it and more.
      var layout = _two(gutter: 100).copyWith(cellStyle: const BoxSpec());
      var square = ShapeElement(
          const ElementBase(
              id: "s", x: 250, y: 300, width: 550, height: 900, dock: "L:a"),
          fill: red);
      CanvasDocument page(LayoutElement l) => const CanvasDocument(
              size: CanvasSize(ratio: CanvasRatio.a4, width: 1240), frames: 48)
          .addElement(l)
          .addElement(square);

      // Slanted 25 degrees about its middle (600, 800): the cut leans, so
      // the cell's right edge is left of 550 above the middle and right of
      // it below.
      var slanted = page(layout.withBase(skewX: 25) as LayoutElement);
      var lean = math.tan(25 * math.pi / 180);
      double edgeAt(double y) => 550 + lean * (y - 800);
      expect(await at(slanted, Offset(edgeAt(1100) - 20, 1100)), red,
          reason: "inside the cell as drawn, right of where it rests");
      expect(await at(slanted, Offset(edgeAt(400) + 40, 400)), isNot(red),
          reason: "in the gutter as drawn, inside where the cell rests");

      // Moved 200 to the left by its keys on frame 24: cell a is left of
      // 350 there, and the gutter after it.
      var moved = page(layout.withBase(
          track: ElementTrack(const [
        Keyframe(frame: 0),
        Keyframe(frame: 24, dx: -200),
      ])) as LayoutElement);
      expect(await at(moved, const Offset(400, 700), frame: 24), isNot(red),
          reason: "the cell has gone left of it: in the gutter there");
      expect(await at(moved, const Offset(300, 700), frame: 24), red,
          reason: "inside the moved cell");
    });
  });

  // Removing a cell takes that cell out and no other: every other cell
  // stays with its id, and with what is docked in it.
  group("removing a cell", () {
    LayoutNode down(LayoutNode a, LayoutNode b) =>
        LayoutNode.cut(vertical: true, a: a, b: b);
    LayoutNode across(LayoutNode a, LayoutNode b) =>
        LayoutNode.cut(vertical: false, at: 0.4, a: a, b: b);
    LayoutNode leaf(String id) => LayoutNode.leaf(id);
    LayoutElement panels(LayoutNode root) => LayoutElement(_box,
        root: root,
        cells: [for (var id in root.cells) LayoutCell(id: id, name: id)],
        order: root.cells.reversed.toList());

    /// removed is [l] in a document with a shape docked in each of its
    /// cells ("s" and the cell's id), after [cell] is removed through the
    /// controller as the panel and the Delete key do.
    CanvasDocument removed(LayoutElement l, String cell) {
      var doc = const CanvasDocument().addElement(l);
      for (var c in l.shownCells) {
        doc = doc.addElement(ShapeElement(ElementBase(
            id: "s${c.id}", dock: LayoutDock(l.id, c.id).toJson())));
      }
      var c = CanvasController(doc);
      addTearDown(c.dispose);
      c.removeLayoutCell(l, cell);
      return c.document;
    }

    /// holds checks that only [cell] went from [l], and that what was docked
    /// in it went into [into] (let go where that is null).
    void holds(LayoutElement l, String cell, String? into) {
      var doc = removed(l, cell);
      var next = doc.elementById("L") as LayoutElement;
      var rest = [
        for (var c in l.shownCells)
          if (c.id != cell) c.id
      ];
      expect([for (var c in next.shownCells) c.id], rest,
          reason: "$cell is gone, and only it");
      for (var id in rest) {
        expect(next.cellById(id)?.name, id, reason: "$id kept as it was");
        expect(doc.elementById("s$id")!.base.dock, "L:$id",
            reason: "what is docked in $id stays there");
      }
      expect(next.order, [
        for (var o in l.order)
          if (o != cell) o
      ]);
      expect(
          doc.elementById("s$cell")!.base.dock, into == null ? "" : "L:$into",
          reason: "what was docked in $cell");
      if (l.mode == LayoutMode.panels) {
        // What was beside it fills its room: the cells still cover the box.
        var cover = layoutPlaces(next, _bounds)
            .map((p) => p.bounds)
            .reduce((a, b) => a.expandToInclude(b));
        expect(cover, _bounds);
      }
    }

    // a over b, b over c.
    var tiers = panels(across(leaf("a"), across(leaf("b"), leaf("c"))));
    for (var (cell, into) in [("a", "b"), ("b", "c"), ("c", "b")]) {
      test("of three tiers, $cell", () => holds(tiers, cell, into));
    }

    // a beside b over c beside d: cut three deep.
    var deep = panels(down(leaf("a"),
        across(leaf("b"), down(leaf("c"), across(leaf("d"), leaf("e"))))));
    for (var (cell, into) in [
      ("a", "b"),
      ("b", "c"),
      ("c", "d"),
      ("d", "e"),
      ("e", "d"),
    ]) {
      test("of a tree cut three deep, $cell", () => holds(deep, cell, into));
    }
    // Into the cell that met it across the cut: the last of what was before
    // it.
    test("of a tree cut three deep, before a cut of its own", () {
      var l = panels(down(across(leaf("a"), leaf("b")), leaf("c")));
      holds(l, "c", "b");
    });

    test("of the last two", () {
      holds(panels(down(leaf("a"), leaf("b"))), "a", "b");
      holds(panels(down(leaf("a"), leaf("b"))), "b", "a");
    });

    test("not the only one", () {
      var l = panels(leaf("a"));
      expect(identical(l.removeCell("a").$1, l), isTrue);
      expect(identical(l.removeCell("x").$1, l), isTrue);
    });

    test("of a Grid or a Free layout: it goes, and what was in it is let go",
        () {
      for (var mode in [LayoutMode.grid, LayoutMode.free]) {
        var l = LayoutElement(_box, mode: mode, columns: const [
          1,
          1
        ], rows: const [
          1,
          1
        ], cells: const [
          LayoutCell(id: "a", name: "a"),
          LayoutCell(id: "b", name: "b", col: 1, x: 0.5),
          LayoutCell(id: "c", name: "c", row: 1, y: 0.5),
        ], order: const [
          "c",
          "b",
          "a"
        ]);
        holds(l, "b", null);
      }
    });
  });

  // Ken, 2026-11-18: "customise panel order so that if you build a comic
  // ebook a user can go into panel mode and use the page back and forward
  // buttons to move through the panels and pages".
  group("reading order", () {
    // Three panels: a over b|c.
    LayoutElement three() => LayoutElement(_box,
            root: const LayoutNode.cut(
                vertical: false,
                a: LayoutNode.leaf("a"),
                b: LayoutNode.cut(
                    vertical: true,
                    a: LayoutNode.leaf("b"),
                    b: LayoutNode.leaf("c"))),
            cells: const [
              LayoutCell(id: "a"),
              LayoutCell(id: "b"),
              LayoutCell(id: "c")
            ]);
    List<String> ids(LayoutElement l) => [for (var c in l.reading) c.id];

    test("by default, down the cuts; a grid row by row", () {
      expect(ids(three()), ["a", "b", "c"]);
      var grid = LayoutElement(_box, mode: LayoutMode.grid, cells: const [
        LayoutCell(id: "low", col: 0, row: 1),
        LayoutCell(id: "right", col: 1, row: 0),
        LayoutCell(id: "left", col: 0, row: 0),
      ]);
      expect(ids(grid), ["left", "right", "low"]);
    });

    test("set, with a cell left out; one cut off since read after it", () {
      var l = three().copyWith(order: ["c", "a"], unread: ["b"]);
      expect(ids(l), ["c", "a"]);
      expect(l.numberOf("b"), isNull);
      var (cut, fresh) = l.split("c", vertical: false);
      expect(ids(cut), ["c", fresh, "a"], reason: "straight after its half");
      var (back, _) = cut.removeCell(fresh);
      expect(back.order, ["c", "a"]);
    });

    test("kept in the file, and junk in it read safely", () {
      var l = three().copyWith(order: ["c", "a"], unread: ["b"]);
      var back = LayoutElement.fromJson(l.props(), _box);
      expect(back.order, ["c", "a"]);
      expect(back.unread, ["b"]);
      var junk = LayoutElement.fromJson({
        ...l.props(),
        "order": [1, null, "", "a", "a" * 500],
        "unread": 7
      }, _box);
      // An id too long is cut as a cell's own id is, so it still names the
      // cell whose id was cut the same way; here it names none.
      expect(junk.order, ["a", "a" * maxIdLength]);
      expect(junk.unread, isEmpty);
      expect(ids(junk), ["a", "b", "c"], reason: "a twice is read once");
    });

    Future<(CanvasController, CanvasStageState)> stage(
        WidgetTester tester, LayoutElement l) async {
      var c = CanvasController(const CanvasDocument(
              size: CanvasSize(ratio: CanvasRatio.a4, width: 1240))
          .addElement(l));
      addTearDown(c.dispose);
      var key = GlobalKey<CanvasStageState>();
      setTestScreen(tester, const Size(1000, 1000));
      await tester.pumpWidget(canvasApp(SizedBox(
          width: 1000,
          height: 1000,
          child: CanvasStage(key: key, controller: c))));
      c.selectOnly("L");
      await tester.pumpAndSettle();
      return (c, key.currentState!);
    }

    Offset middle(LayoutElement l, String id) =>
        layoutPlaceOf(l, _bounds, id)!.bounds.center;

    for (var locked in [false, true]) {
      testWidgets(
          "set by clicking the cells in turn${locked ? ", locked too" : ""}",
          (tester) async {
        var l = three().withBase(locked: locked) as LayoutElement;
        var (c, s) = await stage(tester, l);
        c.beginReadingOrder(l);
        await tester.pumpAndSettle();
        // c, then a; b never clicked. A click on the page gives it the keys.
        for (var id in ["c", "a"]) {
          await tester.tapAt(s.toStagePoint(middle(l, id)));
          await tester.pump(const Duration(milliseconds: 400));
        }
        expect(c.orderClicked, ["c", "a"]);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(c.orderingLayout, isNull);
        var set = c.document.elementById("L") as LayoutElement;
        expect(ids(set), ["c", "a"]);
        expect(set.unread, ["b"]);
        expect(set.root, l.root, reason: "its shape untouched");
        expect(c.selection, {"L"}, reason: "clicking numbered, not picked");
      });
    }

    testWidgets("Escape puts it back as it was", (tester) async {
      var l = three().copyWith(order: ["b", "a", "c"]);
      var (c, s) = await stage(tester, l);
      c.beginReadingOrder(l);
      await tester.tapAt(s.toStagePoint(middle(l, "c")));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
          ids(c.document.elementById("L") as LayoutElement), ["b", "a", "c"]);
      expect(c.orderingLayout, isNull);
    });

    testWidgets("nudged, left out and put back in the settings",
        (tester) async {
      var c = CanvasController(const CanvasDocument().addElement(three()));
      addTearDown(c.dispose);
      c.selectOnly("L");
      setTestScreen(tester, const Size(1400, 1600));
      await tester.pumpWidget(canvasApp(designSidebar(c)));
      await tester.pumpAndSettle();
      LayoutElement now() => c.document.elementById("L") as LayoutElement;
      Future<void> tap(String key) async {
        var f = find.byKey(ValueKey(key));
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      await tap("layoutReadUp-c");
      expect(ids(now()), ["a", "c", "b"]);
      await tap("layoutReadOn-a");
      expect(ids(now()), ["c", "b"]);
      expect(now().unread, ["a"]);
      await tap("layoutReadOn-a");
      expect(ids(now()), ["c", "b", "a"], reason: "put back, at the end");
      await tap("layoutResetOrder");
      expect(ids(now()), ["a", "b", "c"]);
      await tap("layoutSetOrder");
      expect(c.orderingLayout, "L");
      await tap("layoutOrderCancel");
      expect(c.orderingLayout, isNull);
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

  testWidgets("every preset's preview, as the Start from card draws it",
      (tester) async {
    var dir = Platform.environment["LAYOUT_PNG"];
    // A strip of previews at a tile's size, for a tall and a wide layout.
    for (var (name, box) in [
      ("tall", const Size(1116, 1579)),
      ("wide", const Size(1728, 972)),
    ]) {
      const tile = Size(88, 74), gap = 8.0;
      var rec = ui.PictureRecorder();
      var canvas = ui.Canvas(rec);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 11 * (88 + gap), 74),
          Paint()..color = const Color(0xFF1E2230));
      for (var (i, p) in LayoutPreset.values.indexed) {
        canvas.save();
        canvas.translate(i * (tile.width + gap), 0);
        paintLayoutPreview(canvas, tile, p, boxSize: box);
        canvas.restore();
      }
      var pic = rec.endRecording();
      if (dir == null) continue;
      Directory(dir).createSync(recursive: true);
      await tester.runAsync(() async {
        var img = await pic.toImage(11 * (88 + 8), 74);
        var png = await img.toByteData(format: ui.ImageByteFormat.png);
        File("$dir/previews_$name.png")
            .writeAsBytesSync(png!.buffer.asUint8List());
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

    // The stage's painter as last built, to ask whether it would draw again.
    StagePainter painted(WidgetTester tester) => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<StagePainter>()
        .first;

    testWidgets(
        "a picked cell and the reading numbers are drawn as they change",
        (tester) async {
      var l = _two();
      var (c, _) = await stage(tester, page(l));
      c.selectOnly("L");
      await tester.pumpAndSettle();
      var before = painted(tester);
      c.pickLayoutCell("L", "b");
      await tester.pump();
      expect(painted(tester).shouldRepaint(before), isTrue,
          reason: "the picked cell's outline");
      c.pickLayoutCell("L", null);
      c.beginReadingOrder(l);
      await tester.pumpAndSettle();
      before = painted(tester);
      c.clickReadingOrder("b");
      await tester.pump();
      expect(painted(tester).shouldRepaint(before), isTrue,
          reason: "the clicked cell's number");
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

    // A cut's line and the knobs on it, as the stage places them.
    (LayoutCutLine, Offset, Offset) cutOf(LayoutElement l) {
      var line = layoutCutLines(l, _bounds).single;
      var along = line.to - line.from;
      return (
        line,
        along / along.distance,
        Offset(-along.dy, along.dx) / along.distance
      );
    }

    testWidgets("a cut's ring knob tilts it", (tester) async {
      var l = _two();
      var (c, s) = await stage(tester, page(l));
      c.selectOnly("L");
      await tester.pumpAndSettle();
      var (line, _, _) = cutOf(l);
      var knob = Offset.lerp(line.from, line.to, 0.88)!;
      await tester.timedDragFrom(s.toStagePoint(knob),
          Offset(100 * scaleOf(s), 0), const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      // Now through the pivot and where the knob was let go.
      var b = knob + const Offset(100, 0) - const Offset(600, 800);
      var want = math.atan2(-b.dx, b.dy) * 180 / math.pi;
      want = (want + 90) % 180 - 90;
      var moved = c.document.elementById("L") as LayoutElement;
      expect(moved.root.tilt, closeTo(want, 0.3));
      expect(moved.root.tilt.abs(), greaterThan(5));
      expect(moved.root.at, 0.5, reason: "it turns about its own place");
    });

    testWidgets("a cut's square knob widens its gutter", (tester) async {
      var l = _two();
      var (c, s) = await stage(tester, page(l));
      c.selectOnly("L");
      await tester.pumpAndSettle();
      var (line, _, normal) = cutOf(l);
      var knob = Offset.lerp(line.from, line.to, 0.25)! +
          normal * math.max(10, 9 / scaleOf(s));
      await tester.timedDragFrom(s.toStagePoint(knob), normal * 40 * scaleOf(s),
          const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      var moved = c.document.elementById("L") as LayoutElement;
      expect(moved.root.gutter, closeTo(100, 2),
          reason: "20, and twice the 40 it was pulled out by");
      expect(moved.root.at, 0.5);
      expect(moved.root.tilt, 0);
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

    // A slanted layout, or one its keys have moved, is drawn there; its
    // lines, knobs, picked cell and a Free cell's box are shown there, and
    // pressed and dragged there.
    testWidgets(
        "a slanted layout's lines and picked cell are where it is drawn",
        (tester) async {
      var l = _two().withBase(skewX: 20) as LayoutElement;
      var (c, _) = await stage(tester, page(l));
      c.selectOnly("L");
      c.pickLayoutCell("L", "b");
      await tester.pumpAndSettle();
      var marks = painted(tester).inputs.elements.layout!;
      var slant = l.boxFrame;
      Offset drawn(Offset p) => slant.place(p, l.bounds.center);
      var line = layoutCutLines(l, _bounds).single;
      var (from, to) = marks.lines.single;
      expect((from - drawn(line.from)).distance, lessThan(1e-6));
      expect((to - drawn(line.to)).distance, lessThan(1e-6));
      var cell = layoutPlaceOf(l, _bounds, "b")!;
      var picked = marks.picked.value!.getBounds();
      var want = slant.placePath(cell.path, l.bounds.center).getBounds();
      expect((picked.topLeft - want.topLeft).distance, lessThan(1e-6));
      expect((picked.bottomRight - want.bottomRight).distance, lessThan(1e-6));
    });

    testWidgets("a cut dragged on a slanted layout goes under the pointer",
        (tester) async {
      var l = _two().withBase(skewX: 20) as LayoutElement;
      var (c, s) = await stage(tester, page(l));
      c.selectOnly("L");
      await tester.pumpAndSettle();
      // A point on the cut as drawn, well above the middle where the slant
      // has carried it furthest from where the cut rests.
      var slant = l.boxFrame;
      var on = slant.place(const Offset(600, 300), l.bounds.center);
      await tester.timedDragFrom(s.toStagePoint(on),
          Offset(-150 * scaleOf(s), 0), const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      var moved = c.document.elementById("L") as LayoutElement;
      expect(moved.x, 100, reason: "the layout itself did not move");
      var line = layoutCutLines(moved, _bounds).single;
      var a = slant.place(line.from, l.bounds.center);
      var b = slant.place(line.to, l.bounds.center);
      var let = on - const Offset(150, 0);
      // How far the pointer is from the cut as drawn now.
      var ab = b - a;
      var away =
          ((let - a).dx * ab.dy - (let - a).dy * ab.dx).abs() / ab.distance;
      expect(away, lessThan(2), reason: "the cut is drawn where it was let go");
    });

    testWidgets("a Free cell is moved where its layout's keys have moved it",
        (tester) async {
      var l = layoutFrom(_box, LayoutPreset.circles).withBase(
              track: ElementTrack(const [Keyframe(frame: 0, dx: 400)]))
          as LayoutElement;
      var (c, s) = await stage(
          tester,
          const CanvasDocument(
                  size: CanvasSize(ratio: CanvasRatio.a4, width: 1240),
                  frames: 48)
              .addElement(l));
      c.frame = 10;
      c.selectOnly("L");
      var first = l.cells.first;
      c.pickLayoutCell("L", first.id);
      await tester.pumpAndSettle();
      // Its middle where it is drawn: 400 right of where it rests.
      var at = layoutPlaceOf(l, _bounds, first.id)!.bounds.center +
          const Offset(400, 0);
      await tester.timedDragFrom(s.toStagePoint(at),
          Offset(100 * scaleOf(s), 0), const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      var moved =
          (c.document.elementById("L") as LayoutElement).cellById(first.id)!;
      expect(moved.x, closeTo(first.x + 100 / 1000, 0.005));
      expect((c.document.elementById("L") as LayoutElement).x, 100,
          reason: "the cell moved, not the layout");
    });
  });

  group("in the settings", () {
    // Ken, 2026-11-18: "if I lock the layout element the layout changes
    // e.g. the layout edits get removed". The layer list is rebuilt only
    // when what it shows changes, and its buttons wrote back the element
    // it was built with.
    testWidgets("locking it in the layers keeps the edits made since",
        (tester) async {
      var doc = const CanvasDocument()
          .addElement(_two())
          .addElement(ShapeElement(const ElementBase(id: "s", x: 10)));
      var c = CanvasController(doc);
      addTearDown(c.dispose);
      setTestScreen(tester, const Size(1400, 1400));
      await tester.pumpWidget(canvasApp(designSidebar(c)));
      await tester.pumpAndSettle();

      // A cut moved and tilted, as dragging its knobs would.
      var l = c.document.elementById("L") as LayoutElement;
      c.setLayout(l.copyWith(root: l.root.withCut(at: 0.3, tilt: 8)));
      // And a shape moved, which the list does not show either.
      c.replaceElement(c.document.elementById("s")!.withBase(x: 400));
      await tester.pumpAndSettle();

      // The layout's row first (the bottom one; the shape is on top), with
      // nothing in between to rebuild the list.
      await tester.tap(byTip("Lock").last);
      await tester.pumpAndSettle();
      var locked = c.document.elementById("L") as LayoutElement;
      expect(locked.locked, isTrue);
      expect(locked.root.at, closeTo(0.3, 1e-9));
      expect(locked.root.tilt, 8);
      await tester.tap(byTip("Lock").first);
      await tester.pumpAndSettle();
      var shape = c.document.elementById("s")!;
      expect(shape.locked, isTrue);
      expect(shape.x, 400, reason: "a move is not undone by its lock");

      await tester.tap(byTip("Hide").first);
      await tester.pumpAndSettle();
      // The top row is the shape, added last.
      shape = c.document.elementById("s")!;
      expect(shape.visible, isFalse);
      expect(shape.x, 400);
    });

    testWidgets("a preset is started from by its picture", (tester) async {
      var c = CanvasController(const CanvasDocument().addElement(_two()));
      addTearDown(c.dispose);
      c.selectOnly("L");
      setTestScreen(tester, const Size(1400, 1400));
      await tester.pumpWidget(canvasApp(designSidebar(c)));
      await tester.pumpAndSettle();
      var tile = find.byKey(const ValueKey("layoutPreset-sixPanels"));
      expect(tile, findsOneWidget, reason: "shut, a scrolling line of them");
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      var l = c.document.elementById("L") as LayoutElement;
      expect(l.shownCells, hasLength(6));
      expect(l.x, 100, reason: "in the place the old one had");
    });

    testWidgets("a picked cell is cut down, and docked in", (tester) async {
      var doc = const CanvasDocument()
          .addElement(_two())
          .addElement(ShapeElement(const ElementBase(id: "s")));
      var c = CanvasController(doc);
      addTearDown(c.dispose);
      c.selectOnly("L");
      c.pickLayoutCell("L", "a");
      setTestScreen(tester, const Size(1400, 1400));
      await tester.pumpWidget(canvasApp(designSidebar(c)));
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

    testWidgets("a text is docked in a cell from its own Layout section",
        (tester) async {
      // The text panel builds its own sections, so it has to offer the cells
      // itself: the canvas has no other way to dock a text.
      var doc = const CanvasDocument()
          .addElement(_two())
          .addElement(const TextElement(ElementBase(id: "t"), text: "Words"));
      var c = CanvasController(doc);
      addTearDown(c.dispose);
      c.selectOnly("t");
      setTestScreen(tester, const Size(1400, 1400));
      await tester.pumpWidget(canvasApp(designSidebar(c)));
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
      expect(dock, findsOneWidget);
      await tester.ensureVisible(dock);
      await tester.pumpAndSettle();
      await tester.tap(dock);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining("Cell 1").last);
      await tester.pumpAndSettle();
      expect(c.document.elementById("t")!.base.dock, "L:a");
    });
  });
}
