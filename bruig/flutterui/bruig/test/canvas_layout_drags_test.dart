import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/model/layout_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/layout_presets.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';

import 'support/canvas_app.dart';

// canvas_layout_drags_test.dart is each of a Layout's seven drags on the
// stage, as the person doing it sees it: a Panels cut moved, tilted by its
// ring knob and widened by its square knob; a Grid line moved; a picked
// Free cell moved, sized and turned by its own box. Each is held as let go
// (the layout changed, and it is one undo step), as cancelled by the system
// (what it did is kept and the step closed, as for every drag on the
// stage), and as a still press (nothing changes and no step is made); and
// with Shift, for the four that step or lock with it. A cell taken out
// with Delete while a drag is under way stays out.

const _box = ElementBase(id: "L", x: 100, y: 100, width: 1000, height: 1400);
const _bounds = Rect.fromLTWH(100, 100, 1000, 1400);

LayoutElement _two() => const LayoutElement(_box,
    root: LayoutNode.cut(
        vertical: true, a: LayoutNode.leaf("a"), b: LayoutNode.leaf("b")),
    cells: [LayoutCell(id: "a"), LayoutCell(id: "b")],
    gutter: 20,
    rowGutter: 20);

LayoutElement _grid() => const LayoutElement(_box,
    mode: LayoutMode.grid,
    columns: [1, 1],
    rows: [1],
    gutter: 20,
    cells: [
      LayoutCell(id: "w", col: 0, row: 0),
      LayoutCell(id: "x", col: 1, row: 0),
    ]);

// Made once: a preset's cells are given new ids each time it is made.
final _circles = layoutFrom(_box, LayoutPreset.circles);
LayoutElement _free() => _circles;

/// _Drag is one of the seven: its name, the layout it is tried on and the
/// cell picked first, where its press lands and the pointer's travel from
/// there (both on the stage), and what it did to the layout when let go.
typedef _Drag = (
  String,
  LayoutElement Function(),
  String?,
  Offset Function(CanvasStageState),
  Offset Function(CanvasStageState),
  void Function(LayoutElement was, LayoutElement now),
);

void main() {
  Future<(CanvasController, CanvasStageState)> pump(
      WidgetTester tester, LayoutElement l, String? pick) async {
    var c = CanvasController(const CanvasDocument(
            size: CanvasSize(ratio: CanvasRatio.a4, width: 1240))
        .addElement(l));
    addTearDown(c.dispose);
    c.selectOnly("L");
    if (pick != null) c.pickLayoutCell("L", pick);
    var key = GlobalKey<CanvasStageState>();
    setTestScreen(tester, const Size(1000, 1000));
    await tester.pumpWidget(canvasApp(SizedBox(
        width: 1000,
        height: 1000,
        child: CanvasStage(key: key, controller: c))));
    await tester.pumpAndSettle();
    return (c, key.currentState!);
  }

  double scaleOf(CanvasStageState s) =>
      (s.toStagePoint(const Offset(100, 0)) - s.toStagePoint(Offset.zero)).dx /
      100;

  /// cursor is the pointer's look over the stage's page.
  MouseCursor cursor(WidgetTester tester) => tester
      .widgetList<MouseRegion>(find.descendant(
          of: find.byType(CanvasStage), matching: find.byType(MouseRegion)))
      .firstWhere((m) => m.child is ClipRect)
      .cursor;

  /// drag presses at [from] and takes the pointer [by] on the stage, in two
  /// steps, then lets go there or, with [cancel], has the system take it.
  /// [between] is called, awaited, after the first step; [during] with the
  /// pointer still down after the last.
  Future<void> drag(WidgetTester tester, Offset from, Offset by,
      {bool cancel = false,
      Future<void> Function()? between,
      void Function()? during}) async {
    var g = await tester.startGesture(from,
        buttons: kPrimaryButton, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await g.moveBy(by / 2);
    await tester.pump();
    await between?.call();
    await g.moveBy(by / 2);
    await tester.pump();
    during?.call();
    if (cancel) {
      await g.cancel();
    } else {
      await g.up();
    }
    await tester.pumpAndSettle();
  }

  /// settled is that nothing of the last press is left: no gesture under
  /// way and no undo step open.
  void settled(CanvasStageState s, CanvasController c, String how) {
    expect(s.gestureUnderWay, isFalse, reason: "$how: no gesture left");
    expect(c.interacting, isFalse, reason: "$how: no undo step left open");
  }

  LayoutElement now(CanvasController c) =>
      c.document.elementById("L") as LayoutElement;

  /// cut is the one cut of [l], its direction along and across.
  (LayoutCutLine, Offset, Offset) cutOf(LayoutElement l) {
    var line = layoutCutLines(l, _bounds).single;
    var along = line.to - line.from;
    return (
      line,
      along / along.distance,
      Offset(-along.dy, along.dx) / along.distance
    );
  }

  Offset ringKnob(LayoutElement l) {
    var (line, _, _) = cutOf(l);
    return Offset.lerp(line.from, line.to, 0.88)!;
  }

  Offset gutterKnob(LayoutElement l, double scale) {
    var (line, _, normal) = cutOf(l);
    return Offset.lerp(line.from, line.to, 0.25)! +
        normal * math.max(10, 9 / scale);
  }

  /// tiltBy is the tilt the ring knob of [l] is given, dragged [by] in the
  /// document: the angle swept about the cut's pivot.
  double tiltBy(LayoutElement l, Offset by) {
    var pivot = cutPivot(l.root, layoutInner(l, _bounds));
    var a = ringKnob(l) - pivot, b = ringKnob(l) + by - pivot;
    return (math.atan2(b.dy, b.dx) - math.atan2(a.dy, a.dx)) * 180 / math.pi;
  }

  var first = _free().cells.first;
  Offset middle(CanvasStageState s) =>
      s.toStagePoint(freeCellRect(_free(), _bounds, first).center);

  /// turned is [v] turned by [degrees].
  Offset turned(Offset v, double degrees) {
    var a = degrees * math.pi / 180;
    return Offset(v.dx * math.cos(a) - v.dy * math.sin(a),
        v.dx * math.sin(a) + v.dy * math.cos(a));
  }

  final drags = <_Drag>[
    (
      "a cut moved",
      _two,
      null,
      (s) => s.toStagePoint(const Offset(600, 500)),
      (s) => Offset(-250 * scaleOf(s), 0),
      (was, now) {
        expect(now.root.at, closeTo(0.25, 0.01));
        expect(now.root.tilt, was.root.tilt);
        expect(now.x, was.x, reason: "the layout itself did not move");
      },
    ),
    (
      "a cut tilted by its ring knob",
      _two,
      null,
      (s) => s.toStagePoint(ringKnob(_two())),
      (s) => Offset(100 * scaleOf(s), 0),
      (was, now) {
        expect(now.root.tilt, closeTo(tiltBy(was, const Offset(100, 0)), 0.3));
        expect(now.root.tilt.abs(), greaterThan(5));
        expect(now.root.at, was.root.at, reason: "it turns about its place");
      },
    ),
    (
      "a cut's gutter widened by its square knob",
      _two,
      null,
      (s) => s.toStagePoint(gutterKnob(_two(), scaleOf(s))),
      (s) => cutOf(_two()).$3 * 37 * scaleOf(s),
      (was, now) {
        expect(now.root.gutter, closeTo(94, 1),
            reason: "20, and twice the 37 it was pulled out by");
        expect(now.root.at, was.root.at);
      },
    ),
    (
      "a Grid line moved",
      _grid,
      null,
      (s) {
        var line = layoutTrackLines(_grid(), _bounds).single;
        return s.toStagePoint(Offset.lerp(line.from, line.to, 0.5)!);
      },
      (s) => Offset(100 * scaleOf(s), 0),
      (was, now) {
        var want = tracksMoved(
            was.columns, 0, 100, layoutInner(was, _bounds).width, was.gutter);
        expect(now.columns[0], closeTo(want[0], 0.01));
        expect(now.columns[1], closeTo(want[1], 0.01));
        expect(now.columns[0], greaterThan(was.columns[0]));
        expect(now.rows, was.rows);
      },
    ),
    (
      "a Free cell moved from inside",
      _free,
      first.id,
      middle,
      (s) => Offset(100, 30) * scaleOf(s),
      (was, now) {
        var cell = now.cellById(first.id)!;
        var inner = layoutInner(was, _bounds);
        expect(cell.x, closeTo(first.x + 100 / inner.width, 0.005));
        expect(cell.y, closeTo(first.y + 30 / inner.height, 0.005));
        expect(cell.width, first.width);
        expect(now.x, was.x, reason: "the cell moved, not the layout");
      },
    ),
    (
      "a Free cell sized by a corner",
      _free,
      first.id,
      (s) => s.handleAt(StageHandle.bottomRight),
      // Pulled to twice as far from its middle: twice the size.
      (s) => s.handleAt(StageHandle.bottomRight) - middle(s),
      (was, now) {
        var cell = now.cellById(first.id)!;
        expect(cell.width, closeTo(first.width * 2, 0.01));
        expect(cell.height, closeTo(first.height * 2, 0.01));
        expect(
            cell.x + cell.width / 2, closeTo(first.x + first.width / 2, 1e-6),
            reason: "about its middle");
        expect(cell.turn, first.turn);
      },
    ),
    (
      "a Free cell turned by the ring",
      _free,
      first.id,
      (s) => s.handleAt(StageHandle.rotate),
      // From above its middle round to its right: a quarter turn.
      (s) {
        var mid = middle(s), ring = s.handleAt(StageHandle.rotate);
        return mid + Offset((ring - mid).distance, 0) - ring;
      },
      (was, now) {
        var cell = now.cellById(first.id)!;
        expect(cell.turn, closeTo(first.turn + 90, 1), reason: "a quarter");
        expect(cell.width, first.width);
        expect(cell.x, first.x);
      },
    ),
  ];

  for (var (name, layout, pick, at, by, changed) in drags) {
    group("$name on the stage", () {
      for (var cancel in [false, true]) {
        var how = cancel ? "cancelled" : "let go";
        testWidgets("$how: it changes the layout, as one undo step",
            (tester) async {
          var (c, s) = await pump(tester, layout(), pick);
          var was = now(c);
          await drag(tester, at(s), by(s), cancel: cancel, during: () {
            expect(s.gestureUnderWay, isTrue, reason: "a gesture under way");
            expect(c.interacting, isTrue, reason: "an undo step open");
            expect(cursor(tester), SystemMouseCursors.basic);
          });
          changed(was, now(c));
          expect(c.selection, {"L"}, reason: "still selected");
          expect(c.layoutCell("L"), pick, reason: "the same cell picked");
          settled(s, c, how);
          c.undo();
          expect(now(c).props(), was.props(), reason: "one undo puts it back");
          expect(c.canUndo, isFalse, reason: "and it was one step");
        });
      }

      testWidgets("pressed and let go still: nothing changes, no step",
          (tester) async {
        var (c, s) = await pump(tester, layout(), pick);
        var was = now(c).props();
        await drag(tester, at(s), Offset.zero, during: () {
          expect(s.gestureUnderWay, isTrue, reason: "a gesture under way");
        });
        expect(now(c).props(), was);
        settled(s, c, "clicked");
        expect(c.canUndo, isFalse);
        await drag(tester, at(s), Offset.zero, cancel: true);
        expect(now(c).props(), was);
        settled(s, c, "cancelled");
        expect(c.canUndo, isFalse);
      });
    });
  }

  group("with Shift held", () {
    Future<void> shifted(
        WidgetTester tester, Future<void> Function() go) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await go();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
    }

    testWidgets("a cut's tilt goes in steps of 5 degrees", (tester) async {
      var (c, s) = await pump(tester, _two(), null);
      var free = tiltBy(_two(), const Offset(100, 0));
      await shifted(
          tester,
          () => drag(tester, s.toStagePoint(ringKnob(_two())),
              Offset(100 * scaleOf(s), 0)));
      var tilt = now(c).root.tilt;
      expect(tilt % 5, 0, reason: "a whole step");
      expect(tilt, isNot(0));
      expect((tilt - free).abs(), lessThanOrEqualTo(2.5),
          reason: "the step nearest the free tilt of $free");
      settled(s, c, "let go");
    });

    testWidgets("a cut's gutter goes in steps of 10", (tester) async {
      var (c, s) = await pump(tester, _two(), null);
      await shifted(
          tester,
          () => drag(tester, s.toStagePoint(gutterKnob(_two(), scaleOf(s))),
              cutOf(_two()).$3 * 37 * scaleOf(s)));
      expect(now(c).root.gutter, 90, reason: "94 to the nearest 10");
      settled(s, c, "let go");
    });

    testWidgets("a Free cell's move keeps to one axis", (tester) async {
      var (c, s) = await pump(tester, _free(), first.id);
      await shifted(
          tester, () => drag(tester, middle(s), Offset(100, 30) * scaleOf(s)));
      var cell = now(c).cellById(first.id)!;
      var inner = layoutInner(_free(), _bounds);
      expect(cell.x, closeTo(first.x + 100 / inner.width, 0.005));
      expect(cell.y, first.y, reason: "the smaller way is held");
      settled(s, c, "let go");
    });

    testWidgets("a Free cell's turn goes in steps of 15 degrees",
        (tester) async {
      var (c, s) = await pump(tester, _free(), first.id);
      var mid = middle(s), ring = s.handleAt(StageHandle.rotate);
      // Swept 50 degrees: the nearest step is 45.
      await shifted(tester,
          () => drag(tester, ring, mid + turned(ring - mid, 50) - ring));
      var turn = now(c).cellById(first.id)!.turn;
      expect(turn, closeTo(first.turn + 45, 1e-6));
      settled(s, c, "let go");
    });
  });

  group("a cell taken out with Delete while a drag is under way", () {
    for (var (name, layout, pick, at) in [
      (
        "a cut moved",
        _two,
        "b",
        (CanvasStageState s) => s.toStagePoint(const Offset(600, 500))
      ),
      (
        "a Grid line moved",
        _grid,
        "x",
        (CanvasStageState s) {
          var line = layoutTrackLines(_grid(), _bounds).single;
          return s.toStagePoint(Offset.lerp(line.from, line.to, 0.5)!);
        }
      ),
      ("a Free cell moved", _free, first.id, middle),
    ]) {
      testWidgets("$name: the cell stays out", (tester) async {
        var (c, s) = await pump(tester, layout(), pick);
        var was = now(c).props();
        await drag(tester, at(s), Offset(-100 * scaleOf(s), 0),
            between: () async {
          await tester.sendKeyEvent(LogicalKeyboardKey.delete);
          await tester.pump();
          expect(now(c).cellById(pick), isNull, reason: "taken out");
        });
        expect(now(c).cellById(pick), isNull,
            reason: "the drag's next step does not put it back");
        settled(s, c, "let go");
        c.undo();
        expect(now(c).props(), was, reason: "one undo puts it all back");
        expect(c.canUndo, isFalse);
      });
    }
  });
}
