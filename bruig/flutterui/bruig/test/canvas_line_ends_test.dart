import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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
              child: CanvasStage(key: key, controller: controller),
            ),
          ),
        ),
      ));
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
}
