import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_chart_legend_press_test.dart is pressing the key on the canvas.
//
// The model half of this is canvas_chart_legend_toggle_test.dart. This is the
// half a model test cannot see: that the entry is where the painter says it
// is, that pressing it reaches the document, and that dragging from it still
// moves the chart.

const _viewport = Size(900, 700);

void main() {
  Future<CanvasStageState> pump(
      WidgetTester tester, CanvasController controller) async {
    var key = GlobalKey<CanvasStageState>();
    tester.view.physicalSize = _viewport;
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
            width: _viewport.width,
            height: _viewport.height,
            child: CanvasStage(key: key, controller: controller),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return key.currentState!;
  }

  CanvasController chart() => CanvasController(CanvasDocument(
        size: const CanvasSize(width: 800, ratio: CanvasRatio.wide),
        elements: [
          ChartElement(
            const ElementBase(id: "c", x: 40, y: 40, width: 600, height: 340),
            showLegend: true,
            data:
                ChartData.parse("Cat\tOne\tTwo\n2019\t10\t200\n2020\t20\t400"),
          ),
        ],
      ));

  ChartElement chartIn(CanvasController c) =>
      c.document.elementById("c") as ChartElement;

  testWidgets("pressing a key entry switches that series off and on",
      (tester) async {
    var controller = chart();
    addTearDown(controller.dispose);
    var stage = await pump(tester, controller);

    controller.selectOnly("c");
    await tester.pumpAndSettle();

    var element = chartIn(controller);
    var rects = chartLegendRects(element, element.bounds);
    expect(rects.length, 2);

    await tester.tapAt(stage.toStagePoint(rects[1].$2.center));
    await tester.pumpAndSettle();
    expect(chartIn(controller).data.series[1].hidden, isTrue);
    expect(chartIn(controller).data.series[0].hidden, isFalse,
        reason: "the entry pressed, and no other");

    // The entry is still there, in the same place, to press again.
    var again =
        chartLegendRects(chartIn(controller), chartIn(controller).bounds);
    await tester.tapAt(stage.toStagePoint(again[1].$2.center));
    await tester.pumpAndSettle();
    expect(chartIn(controller).data.series[1].hidden, isFalse);
  });

  testWidgets("but not until the chart is the thing selected", (tester) async {
    // A press anywhere on a chart that is not selected selects it, the same
    // way a button element and a counter's own buttons behave.
    var controller = chart();
    addTearDown(controller.dispose);
    var stage = await pump(tester, controller);

    var element = chartIn(controller);
    var rects = chartLegendRects(element, element.bounds);
    await tester.tapAt(stage.toStagePoint(rects[1].$2.center));
    await tester.pumpAndSettle();

    expect(chartIn(controller).data.series[1].hidden, isFalse);
    expect(controller.selection, ["c"], reason: "it selected it instead");
  });

  testWidgets("and dragging from it still moves the chart", (tester) async {
    var controller = chart();
    addTearDown(controller.dispose);
    var stage = await pump(tester, controller);

    controller.selectOnly("c");
    await tester.pumpAndSettle();

    var element = chartIn(controller);
    var rects = chartLegendRects(element, element.bounds);
    var was = chartIn(controller).x;

    await tester.dragFrom(
        stage.toStagePoint(rects[1].$2.center), const Offset(60, 0));
    await tester.pumpAndSettle();

    expect(chartIn(controller).x, greaterThan(was),
        reason: "a press that travels is a drag, not a press");
    expect(chartIn(controller).data.series[1].hidden, isFalse,
        reason: "and it did not switch the series off on the way");
  });

  testWidgets("holding a key entry picks the key up instead", (tester) async {
    // The key a chart lays out for itself has no grip of its own -- it is a
    // few words over the plot, and both ordinary gestures on it are taken:
    // pressing switches a series off and dragging moves the chart. Holding is
    // the third one, and it is the only way to move the key without first
    // putting the title over the chart.
    var controller = chart();
    addTearDown(controller.dispose);
    var stage = await pump(tester, controller);

    controller.selectOnly("c");
    await tester.pumpAndSettle();

    var element = chartIn(controller);
    expect(element.floatingLabels, isFalse, reason: "the case being fixed");
    expect(element.legend.hasPlace, isFalse);
    var was = chartLegendBlock(element, element.bounds);
    var wasX = element.x;

    // In document units, which is what the key is measured in: the stage
    // fits the page to its viewport, so fifty stage pixels is not a move of
    // fifty.
    var from = chartLegendRects(element, element.bounds)[1].$2.center;
    var by = stage.toStagePoint(from + const Offset(50, 70)) -
        stage.toStagePoint(from);

    var press = await tester.startGesture(stage.toStagePoint(from));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await press.moveBy(by);
    await tester.pumpAndSettle();
    await press.up();
    await tester.pumpAndSettle();

    var now = chartIn(controller);
    expect(now.legend.hasPlace, isTrue, reason: "the hold placed it");
    expect(now.data.series[1].hidden, isFalse,
        reason: "a hold is not a press on the switch");
    expect(now.x, closeTo(wasX, 0.01), reason: "the chart itself stayed put");

    var moved = chartLegendBlock(now, now.bounds);
    expect(moved.left - was.left, closeTo(50, 2));
    expect(moved.top - was.top, closeTo(70, 2));
  });

  testWidgets("and a key that has been placed is dragged directly",
      (tester) async {
    var controller = chart();
    addTearDown(controller.dispose);
    var stage = await pump(tester, controller);

    controller.selectOnly("c");
    var element = chartIn(controller);
    var was = chartLegendBlock(element, element.bounds);
    controller.replaceElement(element.copyWith(
        legend: element.legend.copyWith(
      x: (was.left - element.bounds.left) / element.bounds.width,
      y: (was.top - element.bounds.top) / element.bounds.height,
    )));
    await tester.pumpAndSettle();

    var placed = chartIn(controller);
    var from = chartLegendBlock(placed, placed.bounds);
    // Diagonally, and both of the chart's own coordinates are checked: a
    // drag that moved the whole element would move the key with it, so a
    // moved key on its own is only evidence if the chart did not follow.
    await tester.dragFrom(
        stage.toStagePoint(from.center),
        stage.toStagePoint(from.center + const Offset(60, 90)) -
            stage.toStagePoint(from.center));
    await tester.pumpAndSettle();

    var now = chartIn(controller);
    var went = chartLegendBlock(now, now.bounds);
    expect(went.left - from.left, closeTo(60, 2),
        reason: "no hold needed once it has a place of its own");
    expect(went.top - from.top, closeTo(90, 2));
    expect(now.x, closeTo(placed.x, 0.01), reason: "and the chart stayed put");
    expect(now.y, closeTo(placed.y, 0.01));

    // Still a row of switches: a press that does not travel is a press.
    var at = chartLegendRects(now, now.bounds);
    await tester.tapAt(stage.toStagePoint(at[1].$2.center));
    await tester.pumpAndSettle();
    expect(chartIn(controller).data.series[1].hidden, isTrue);
  });
}
