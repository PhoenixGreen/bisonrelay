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
}
