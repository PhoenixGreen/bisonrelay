import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_painter.dart';

import 'support/canvas_app.dart';

// canvas_snapping_test.dart is snapping as the person dragging meets it, on a
// real stage: the box moved and its edge dragged, and a guide dragged, each
// caught by what it should be caught by and by nothing else; Alt freeing
// each of them; the Snap switch and the Other elements switch; and the mark
// that shows a catch, there while it holds and gone when the drag ends.
//
// Every distance here is in document units, turned into the stage's pixels
// through toStagePoint, so the tests do not depend on the zoom the page
// fits at.

const _viewport = Size(1200, 800);

void main() {
  /// pump shows [controller] on a stage and hands back its state.
  Future<CanvasStageState> pump(
      WidgetTester tester, CanvasController controller) async {
    var key = GlobalKey<CanvasStageState>();
    setTestScreen(tester, _viewport);
    await tester.pumpWidget(canvasApp(SizedBox(
        width: _viewport.width,
        height: _viewport.height,
        child: CanvasStage(key: key, controller: controller))));
    await tester.pumpAndSettle();
    return key.currentState!;
  }

  /// painted is the stage's page painter as last built.
  StagePainter painted(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .expand((p) => [p.painter, p.foregroundPainter])
      .whereType<StagePainter>()
      .first;

  /// caught is whether the stage shows a snap mark now.
  bool caught(WidgetTester tester) =>
      painted(tester).inputs.guides.snapped?.caught ?? false;

  /// drag presses at [from] and takes the pointer to [to], both on the
  /// stage, in two steps, then lets go or, with [cancel], has the system
  /// take it. With [alt], Alt is held from just after the press to the end.
  /// [during] is run after the last step, before the pointer is let go.
  Future<void> drag(WidgetTester tester, Offset from, Offset to,
      {bool alt = false, bool cancel = false, void Function()? during}) async {
    var g = await tester.startGesture(from);
    await tester.pump();
    if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await g.moveBy((to - from) / 2);
    await tester.pump();
    await g.moveBy((to - from) / 2);
    await tester.pump();
    during?.call();
    if (cancel) {
      await g.cancel();
    } else {
      await g.up();
    }
    if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
  }

  CanvasController withElements(List<CanvasElement> elements,
      {CanvasGuides guides = const CanvasGuides()}) {
    var doc = const CanvasDocument().copyWith(guides: guides);
    for (var e in elements) {
      doc = doc.addElement(e);
    }
    var c = CanvasController(doc);
    addTearDown(c.dispose);
    return c;
  }

  ShapeElement box(String id, double x, double y, double w, double h) =>
      ShapeElement(ElementBase(id: id, x: x, y: y, width: w, height: h));

  CanvasElement now(CanvasController c, String id) =>
      c.document.elementById(id)!;

  /// moveBy drags element [id] of [c] from its middle by [by], in document
  /// units.
  Future<void> moveBy(WidgetTester tester, CanvasStageState stage,
      CanvasController c, String id, Offset by,
      {bool alt = false, bool cancel = false, void Function()? during}) {
    var centre = now(c, id).center;
    return drag(
        tester, stage.toStagePoint(centre), stage.toStagePoint(centre + by),
        alt: alt, cancel: cancel, during: during);
  }

  // A vertical guide at 400, and a box whose left edge a move takes to 403.
  const guideAt400 =
      CanvasGuides(guides: [CanvasGuide(axis: GuideAxis.vertical, at: 400)]);
  final loose = box("s", 500, 150, 100, 100);

  group("a move", () {
    testWidgets("snaps to a guide", (tester) async {
      var c = withElements([loose], guides: guideAt400);
      var stage = await pump(tester, c);
      await moveBy(tester, stage, c, "s", const Offset(-97, 0));
      expect(now(c, "s").x, closeTo(400, 0.01));
      expect(now(c, "s").y, closeTo(150, 0.5), reason: "nothing across");
    });

    testWidgets("snaps to the grid", (tester) async {
      // Its top at 330 and bottom at 430 are out of the grid's reach, and
      // its middle at 380 is not on the page's.
      var c = withElements([box("s", 510, 330, 100, 100)],
          guides: const CanvasGuides(showGrid: true, gridSize: 100));
      var stage = await pump(tester, c);
      await moveBy(tester, stage, c, "s", const Offset(-113, 0));
      expect(now(c, "s").x, closeTo(400, 0.01));
      expect(now(c, "s").y, closeTo(330, 0.5));
    });

    testWidgets("snaps its middle to the page's", (tester) async {
      var c = withElements([loose]);
      var stage = await pump(tester, c);
      var middle = c.document.size.size.width / 2;
      // Its middle taken to three short of the page's.
      await moveBy(tester, stage, c, "s", Offset(middle - 3 - 550, 0));
      expect(now(c, "s").x, closeTo(middle - 50, 0.01));
    });

    testWidgets("snaps to another element's side", (tester) async {
      // b's left edge is taken to 253, three past a's right edge.
      var c = withElements(
          [box("a", 100, 100, 150, 150), box("b", 600, 420, 100, 100)]);
      var stage = await pump(tester, c);
      await moveBy(tester, stage, c, "b", const Offset(-347, 0));
      expect(now(c, "b").x, closeTo(250, 0.01));
    });

    testWidgets("snaps its middle to another element's middle", (tester) async {
      // b's middle is taken to 178, three past a's at 175; its sides at 128
      // and 228 are out of reach of a's at 100 and 250.
      var c = withElements(
          [box("a", 100, 100, 150, 150), box("b", 600, 420, 100, 100)]);
      var stage = await pump(tester, c);
      await moveBy(tester, stage, c, "b", const Offset(-472, 0));
      expect(now(c, "b").x, closeTo(125, 0.01));
    });

    testWidgets("turned, snaps by the box it is seen in", (tester) async {
      // Turned 45 degrees about its middle at 550, its corners reach out
      // 50 * sqrt(2) on each side: what is seen starts at 479.3. A move of
      // -76.3 takes that to 403, three past the guide.
      var c = withElements(
          [box("s", 500, 150, 100, 100).withBase(rotation: 45)],
          guides: guideAt400);
      var stage = await pump(tester, c);
      var reach = 50 * math.sqrt2;
      await moveBy(tester, stage, c, "s", Offset(403 - (550 - reach), 0));
      expect(now(c, "s").x, closeTo(400 + reach - 50, 0.01),
          reason: "the turned corner on the guide");
    });

    testWidgets("with Alt held, goes where it is put", (tester) async {
      var c = withElements([loose], guides: guideAt400);
      var stage = await pump(tester, c);
      await moveBy(tester, stage, c, "s", const Offset(-97, 0), alt: true);
      expect(now(c, "s").x, closeTo(403, 0.5));
      expect(now(c, "s").x, isNot(closeTo(400, 0.01)));
    });

    testWidgets("with Snap off, goes where it is put", (tester) async {
      var c = withElements([loose], guides: guideAt400.copyWith(snap: false));
      var stage = await pump(tester, c);
      await moveBy(tester, stage, c, "s", const Offset(-97, 0));
      expect(now(c, "s").x, closeTo(403, 0.5));
      expect(now(c, "s").x, isNot(closeTo(400, 0.01)));
    });

    testWidgets("with Other elements off, passes another element by",
        (tester) async {
      var c = withElements(
          [box("a", 100, 100, 150, 150), box("b", 600, 420, 100, 100)],
          guides: const CanvasGuides(snapTo: SnapTo(objects: false)));
      var stage = await pump(tester, c);
      await moveBy(tester, stage, c, "b", const Offset(-347, 0));
      expect(now(c, "b").x, closeTo(253, 0.5));
      expect(now(c, "b").x, isNot(closeTo(250, 0.01)));
    });
  });

  group("a resize", () {
    // Selected, so its handles are there to take. Its bottom edge at 400 is
    // out of reach of everything.
    final sized = box("s", 400, 200, 300, 200);

    /// pullRight drags the selected box's bottom-right handle so its right
    /// edge goes to [x].
    Future<void> pullRight(
        WidgetTester tester, CanvasStageState stage, double x,
        {bool alt = false, bool cancel = false, void Function()? during}) {
      var handle = stage.handleAt(StageHandle.bottomRight);
      return drag(
          tester,
          handle,
          handle +
              stage.toStagePoint(Offset(x, 400)) -
              stage.toStagePoint(const Offset(700, 400)),
          alt: alt,
          cancel: cancel,
          during: during);
    }

    testWidgets("lands its dragged edge on a guide", (tester) async {
      var c = withElements([sized],
          guides: const CanvasGuides(
              guides: [CanvasGuide(axis: GuideAxis.vertical, at: 730)]));
      c.selectOnly("s");
      var stage = await pump(tester, c);
      await pullRight(tester, stage, 727);
      expect(now(c, "s").x, 400, reason: "the held side stays");
      expect(now(c, "s").bounds.right, closeTo(730, 0.01));
      expect(now(c, "s").height, closeTo(200, 0.5));
    });

    testWidgets("lands its dragged edge on another element", (tester) async {
      var c = withElements([sized, box("a", 800, 600, 100, 100)]);
      c.selectOnly("s");
      var stage = await pump(tester, c);
      await pullRight(tester, stage, 797);
      expect(now(c, "s").bounds.right, closeTo(800, 0.01));
    });

    testWidgets("with Alt held, goes where it is put", (tester) async {
      var c = withElements([sized],
          guides: const CanvasGuides(
              guides: [CanvasGuide(axis: GuideAxis.vertical, at: 730)]));
      c.selectOnly("s");
      var stage = await pump(tester, c);
      await pullRight(tester, stage, 727, alt: true);
      expect(now(c, "s").bounds.right, closeTo(727, 0.5));
      expect(now(c, "s").bounds.right, isNot(closeTo(730, 0.01)));
    });

    testWidgets("with Snap off, goes where it is put", (tester) async {
      var c = withElements([sized],
          guides: const CanvasGuides(
              snap: false,
              guides: [CanvasGuide(axis: GuideAxis.vertical, at: 730)]));
      c.selectOnly("s");
      var stage = await pump(tester, c);
      await pullRight(tester, stage, 727);
      expect(now(c, "s").bounds.right, closeTo(727, 0.5));
    });

    testWidgets("with Other elements off, passes another element by",
        (tester) async {
      var c = withElements([sized, box("a", 800, 600, 100, 100)],
          guides: const CanvasGuides(snapTo: SnapTo(objects: false)));
      c.selectOnly("s");
      var stage = await pump(tester, c);
      await pullRight(tester, stage, 797);
      expect(now(c, "s").bounds.right, closeTo(797, 0.5));
    });
  });

  group("a guide dragged", () {
    /// pull drags the one guide, upright at [from], to [to].
    Future<void> pull(
            WidgetTester tester, CanvasStageState stage, double from, double to,
            {bool alt = false}) =>
        drag(tester, stage.toStagePoint(Offset(from, 200)),
            stage.toStagePoint(Offset(to, 200)),
            alt: alt);

    double at(CanvasController c) => c.document.guides.guides.single.at;

    testWidgets("snaps to the grid", (tester) async {
      var c = withElements(const [],
          guides: const CanvasGuides(
              showGrid: true,
              gridSize: 100,
              guides: [CanvasGuide(axis: GuideAxis.vertical, at: 333)]));
      var stage = await pump(tester, c);
      await pull(tester, stage, 333, 397);
      expect(at(c), closeTo(400, 0.01));
    });

    testWidgets("snaps to the page's middle", (tester) async {
      var c = withElements(const [],
          guides: const CanvasGuides(
              guides: [CanvasGuide(axis: GuideAxis.vertical, at: 333)]));
      var stage = await pump(tester, c);
      var middle = c.document.size.size.width / 2;
      await pull(tester, stage, 333, middle + 3);
      expect(at(c), closeTo(middle, 0.01));
    });

    testWidgets("with Alt held, goes where it is put", (tester) async {
      var c = withElements(const [],
          guides: const CanvasGuides(
              showGrid: true,
              gridSize: 100,
              guides: [CanvasGuide(axis: GuideAxis.vertical, at: 333)]));
      var stage = await pump(tester, c);
      await pull(tester, stage, 333, 397, alt: true);
      expect(at(c), closeTo(397, 0.5));
      expect(at(c), isNot(closeTo(400, 0.01)));
    });

    testWidgets("with Snap off, goes where it is put", (tester) async {
      var c = withElements(const [],
          guides: const CanvasGuides(
              showGrid: true,
              gridSize: 100,
              snap: false,
              guides: [CanvasGuide(axis: GuideAxis.vertical, at: 333)]));
      var stage = await pump(tester, c);
      await pull(tester, stage, 333, 397);
      expect(at(c), closeTo(397, 0.5));
    });
  });

  group("the snap mark", () {
    for (var cancel in [false, true]) {
      var how = cancel ? "cancelled" : "let go";

      testWidgets("a move caught shows it, and $how it goes", (tester) async {
        var c = withElements([loose], guides: guideAt400);
        var stage = await pump(tester, c);
        var during = false;
        await moveBy(tester, stage, c, "s", const Offset(-97, 0),
            cancel: cancel, during: () => during = caught(tester));
        expect(during, isTrue, reason: "shown while caught");
        expect(caught(tester), isFalse, reason: "gone, $how");
        expect(painted(tester).inputs.guides.snapped, isNull,
            reason: "nothing left, $how");
      });

      testWidgets("a resize caught shows it, and $how it goes", (tester) async {
        var c = withElements([box("s", 400, 200, 300, 200)],
            guides: const CanvasGuides(
                guides: [CanvasGuide(axis: GuideAxis.vertical, at: 730)]));
        c.selectOnly("s");
        var stage = await pump(tester, c);
        var handle = stage.handleAt(StageHandle.bottomRight);
        var during = false;
        await drag(
            tester,
            handle,
            handle +
                stage.toStagePoint(const Offset(727, 400)) -
                stage.toStagePoint(const Offset(700, 400)),
            cancel: cancel,
            during: () => during = caught(tester));
        expect(during, isTrue, reason: "shown while caught");
        expect(caught(tester), isFalse, reason: "gone, $how");
        expect(painted(tester).inputs.guides.snapped, isNull,
            reason: "nothing left, $how");
      });
    }

    testWidgets("not shown while Alt frees the move", (tester) async {
      var c = withElements([loose], guides: guideAt400);
      var stage = await pump(tester, c);
      var during = true;
      await moveBy(tester, stage, c, "s", const Offset(-97, 0),
          alt: true, during: () => during = caught(tester));
      expect(during, isFalse);
    });

    testWidgets("not shown for a move that catches nothing", (tester) async {
      var c = withElements([loose]);
      var stage = await pump(tester, c);
      var during = true;
      await moveBy(tester, stage, c, "s", const Offset(-77, 23),
          during: () => during = caught(tester));
      expect(during, isFalse);
    });
  });
}
