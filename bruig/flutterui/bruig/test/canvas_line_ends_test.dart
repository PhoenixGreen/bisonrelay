import 'dart:math' as math;

import 'support/canvas_app.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_line_ends_test.dart is a line handled by its two ends.
//
// A line runs corner to corner of its box, and the box could never be less
// than a few pixels deep -- so no line in a canvas was ever quite level. The
// HUD brackets on the Inflationists video came out two pixels off square.

LineElement _line(Offset a, Offset b, {LineEnd end = LineEnd.none}) =>
    LineElement(const ElementBase(id: "l"), strokeWidth: 4, endEnd: end)
        .withEnds(a, b);

void main() {
  group("the model", () {
    test("a level line is drawn level", () {
      var l = _line(const Offset(100, 200), const Offset(500, 200));
      expect(l.start, const Offset(100, 200));
      expect(l.end.dx, 500);
      expect((l.end.dy - l.start.dy).abs(), lessThanOrEqualTo(lineSliver));
      expect(l.angle.abs(), lessThan(0.01));
      expect(l.height, greaterThan(0), reason: "nothing with no height draws");
    });

    test("a line drawn right to left keeps its arrow where it was", () {
      var l = _line(const Offset(500, 100), const Offset(100, 300),
          end: LineEnd.arrow);
      expect(l.start, const Offset(100, 300));
      expect(l.end, const Offset(500, 100));
      expect(l.startEnd, LineEnd.arrow,
          reason: "the arrow is still at (100, 300)");
      expect(l.endEnd, LineEnd.none);
    });

    test("level and plumb keep the length and the side", () {
      var l = _line(const Offset(100, 100), const Offset(400, 140));
      var flat = l.level;
      expect(flat.length, closeTo(l.length, 0.01));
      expect(flat.angle.abs(), lessThan(0.01));
      var up = l.plumb;
      expect(up.length, closeTo(l.length, 0.01));
      expect(up.angle, closeTo(90, 0.01));
    });

    test("an end within a few degrees of level is put on it", () {
      const fixed = Offset(0, 0);
      expect(snapLineAngle(fixed, const Offset(400, 10)).dy, 0,
          reason: "1.4 degrees off level");
      expect(snapLineAngle(fixed, const Offset(400, 80)), const Offset(400, 80),
          reason: "11 degrees is meant");
      var forced = snapLineAngle(fixed, const Offset(400, 80), always: true);
      expect(forced.dy, 0);
      var diagonal = snapLineAngle(fixed, const Offset(300, 310));
      expect(diagonal.dx, closeTo(diagonal.dy, 1e-9));
      expect(snapLineAngle(fixed, const Offset(5, 300)).dx, 0,
          reason: "upright too");
    });

    test("a new line is level", () {
      var l =
          newElement(ElementKind.line, const CanvasDocument()) as LineElement;
      expect(l.angle.abs(), lessThan(0.01));
    });
  });

  group("on the stage", () {
    const viewport = Size(1280, 800);

    Future<(CanvasStageState, CanvasController)> pump(
        WidgetTester tester, LineElement line) async {
      var controller =
          CanvasController(const CanvasDocument().addElement(line));
      addTearDown(controller.dispose);
      controller.selectOnly(line.id);
      var key = GlobalKey<CanvasStageState>();
      setTestScreen(tester, viewport);
      await tester.pumpWidget(canvasApp(SizedBox(
          width: viewport.width,
          height: viewport.height,
          child: CanvasStage(key: key, controller: controller))));
      await tester.pumpAndSettle();
      return (key.currentState!, controller);
    }

    /// _screen is where a document point is on screen.
    Offset screen(CanvasStageState stage, CanvasController c, Offset p) {
      var scale = stage.pageRect.width / c.document.size.width;
      return stage.pageRect.topLeft + p * scale;
    }

    Future<void> dragEnd(WidgetTester tester, CanvasStageState stage,
        CanvasController c, Offset by) async {
      var e = c.document.elements.single;
      var box = visualBoundsOf(e, c.document, 0);
      var scale = stage.pageRect.width / c.document.size.width;
      var gesture =
          await tester.startGesture(screen(stage, c, box.bottomRight));
      await tester.pump();
      // In steps, as a hand does, so the drag is recognised before it ends.
      for (var i = 1; i <= 4; i++) {
        await gesture
            .moveTo(screen(stage, c, box.bottomRight) + by * scale * (i / 4));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets("an end dragged nearly level lands exactly level",
        (tester) async {
      var (stage, c) = await pump(
          tester, _line(const Offset(200, 300), const Offset(600, 300)));
      await dragEnd(tester, stage, c, const Offset(80, 12));
      var l = c.document.elements.single as LineElement;
      expect(l.angle.abs(), lessThan(0.01), reason: "1.4 degrees, snapped");
      expect(l.start, const Offset(200, 300), reason: "the other end stays");
      expect(l.length, greaterThan(400),
          reason: "the end went where it was taken");
    });

    testWidgets("an end dragged well off level stays where it was put",
        (tester) async {
      var (stage, c) = await pump(
          tester, _line(const Offset(200, 300), const Offset(600, 300)));
      await dragEnd(tester, stage, c, const Offset(0, 120));
      var l = c.document.elements.single as LineElement;
      expect(l.angle, greaterThan(10));
      expect(l.start, const Offset(200, 300));
    });
  });

  group("a turned or slanted line's ends on the stage", () {
    const viewport = Size(1280, 800);

    /// drawn is where [c]'s line's two ends are drawn on [frame], start
    /// first.
    (Offset, Offset) drawn(CanvasController c, [int frame = 0]) {
      var curve =
          curveOfElement(c.document.elements.single, frame, c.document)!;
      return (curve.first, curve.last);
    }

    Future<(CanvasStageState, CanvasController)> pump(
        WidgetTester tester, LineElement line,
        {int frame = 0}) async {
      var controller =
          CanvasController(CanvasDocument(frames: 24, elements: [line]));
      addTearDown(controller.dispose);
      controller.frame = frame;
      controller.selectOnly(line.id);
      var key = GlobalKey<CanvasStageState>();
      setTestScreen(tester, viewport);
      await tester.pumpWidget(canvasApp(SizedBox(
          width: viewport.width,
          height: viewport.height,
          child: CanvasStage(key: key, controller: controller))));
      await tester.pumpAndSettle();
      return (key.currentState!, controller);
    }

    /// dragHandle takes the selection's [corner] handle [by], in document
    /// units, in steps as a hand does.
    Future<void> dragHandle(WidgetTester tester, CanvasStageState stage,
        CanvasController c, StageHandle corner, Offset by) async {
      var scale = stage.pageRect.width / c.document.size.width;
      var at = stage.handleAt(corner);
      var gesture = await tester.startGesture(at);
      await tester.pump();
      for (var i = 1; i <= 4; i++) {
        await gesture.moveTo(at + by * scale * (i / 4));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    // From (300, 300) to (700, 460), with an arrow on its end; each way it
    // is laid out puts its end at the box's bottom right.
    var plain = _line(const Offset(300, 300), const Offset(700, 460),
        end: LineEnd.arrow);
    var ways = <(String, LineElement, int)>[
      ("turned", plain.withBase(rotation: 25) as LineElement, 0),
      ("slanted", plain.withBase(skewX: 20) as LineElement, 0),
      (
        "turned by its keys, part-way through them",
        plain.withBase(
            track: ElementTrack(const [
          Keyframe(frame: 0),
          Keyframe(frame: 20, dx: 80, dy: -60, rotate: 50),
        ])) as LineElement,
        10
      ),
    ];

    for (var (name, line, frame) in ways) {
      testWidgets("$name: its end goes where it is taken, its start stays",
          (tester) async {
        var (stage, c) = await pump(tester, line, frame: frame);
        var (start, end) = drawn(c, frame);
        // Off any angle it would snap to.
        const by = Offset(70, -25);
        await dragHandle(tester, stage, c, StageHandle.bottomRight, by);
        var (startNow, endNow) = drawn(c, frame);
        expect(endNow.dx, closeTo(end.dx + by.dx, 0.5));
        expect(endNow.dy, closeTo(end.dy + by.dy, 0.5));
        expect(startNow.dx, closeTo(start.dx, 0.01), reason: "the start stays");
        expect(startNow.dy, closeTo(start.dy, 0.01));
        var l = c.document.elements.single as LineElement;
        expect(l.rotation, line.rotation, reason: "still turned as it was");
        expect(l.base.skewX, line.base.skewX);
        expect(l.track, line.track, reason: "its keys are its own");
      });
    }

    testWidgets("a turned line's start is taken by the handle at the top left",
        (tester) async {
      // The handle's inner half lies inside the box round the line, where a
      // press would otherwise take hold of the whole line to move it.
      var turned = plain.withBase(rotation: 25) as LineElement;
      var (stage, c) = await pump(tester, turned);
      var (start, end) = drawn(c);
      // Off any angle it would snap to.
      const by = Offset(20, -60);
      var scale = stage.pageRect.width / c.document.size.width;
      var at = stage.handleAt(StageHandle.topLeft) + const Offset(3, 3);
      var gesture = await tester.startGesture(at);
      await tester.pump();
      for (var i = 1; i <= 4; i++) {
        await gesture.moveTo(at + by * scale * (i / 4));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      var (startNow, endNow) = drawn(c);
      expect(startNow.dx, closeTo(start.dx + by.dx, 0.5));
      expect(startNow.dy, closeTo(start.dy + by.dy, 0.5));
      expect(endNow.dx, closeTo(end.dx, 0.01), reason: "the end stays");
    });

    testWidgets("a turned line's end dragged nearly level lands level",
        (tester) async {
      var turned = plain.withBase(rotation: 25) as LineElement;
      var (stage, c) = await pump(tester, turned);
      var (start, end) = drawn(c);
      // Two degrees short of level on the page.
      var length = (end - start).distance;
      var target = start + Offset(length, length * math.tan(2 * math.pi / 180));
      await dragHandle(tester, stage, c, StageHandle.bottomRight, target - end);
      var (startNow, endNow) = drawn(c);
      expect((endNow.dy - startNow.dy).abs(), lessThan(0.05),
          reason: "level on the page");
      expect(startNow.dx, closeTo(start.dx, 0.01), reason: "the start stays");
    });

    testWidgets("a turned line's end dragged past its start keeps its arrow",
        (tester) async {
      var turned = plain.withBase(rotation: 25) as LineElement;
      var (stage, c) = await pump(tester, turned);
      var (start, end) = drawn(c);
      // Back past the start, a good way beyond it.
      var to = start - (end - start) * 0.5 + const Offset(0, 30);
      await dragHandle(tester, stage, c, StageHandle.bottomRight, to - end);
      var l = c.document.elements.single as LineElement;
      var (first, last) = drawn(c);
      // The arrow is drawn where the pointer let go, the other end still.
      var (arrow, other) =
          l.endEnd == LineEnd.arrow ? (last, first) : (first, last);
      expect(l.startEnd == LineEnd.arrow || l.endEnd == LineEnd.arrow, isTrue);
      expect(arrow.dx, closeTo(to.dx, 0.5), reason: "the arrow is let go of");
      expect(arrow.dy, closeTo(to.dy, 0.5));
      expect(other.dx, closeTo(start.dx, 0.01), reason: "the start stays");
      expect(other.dy, closeTo(start.dy, 0.01));
    });
  });
}
