import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_chart_series_lead_test.dart is the series that leads its kind of
// drawing, and the settings it owns.
//
// The first series drawn a given way owns the chart's own setting, and every
// other series drawn that way follows it. So the leading series' controls
// write the chart's value -- and if that series also carried an override of
// its own, the override went on winning: the panel wrote, nothing changed, and
// the switch read as dead.

void main() {
  Future<CanvasController> panel(WidgetTester tester, ChartData data) async {
    var element = ChartElement(
      const ElementBase(id: "c", width: 400, height: 300),
      data: data,
    );
    var controller =
        CanvasController(const CanvasDocument().addElement(element));
    addTearDown(controller.dispose);
    controller.selectOnly("c");

    tester.view.physicalSize = const Size(1400, 900);
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
      child: MaterialApp(
          home: Scaffold(body: CanvasDesignPanel(controller: controller))),
    ));
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> press(WidgetTester tester, Finder what) async {
    await tester.ensureVisible(what);
    await tester.pumpAndSettle();
    await tester.tap(what);
    await tester.pumpAndSettle();
  }

  testWidgets("its Smooth switch works even when it carried its own",
      (tester) async {
    // A line series given smooth: true by hand -- which is what a chart built
    // from a file or a preset looks like -- and which also happens to be the
    // first line on the chart, so it leads.
    var controller = await panel(
      tester,
      const ChartData(
        categories: ["a", "b", "c"],
        series: [
          ChartSeries(
              name: "Bars", color: Color(0xFF30E0A0), values: [1, 2, 3]),
          ChartSeries(
            name: "Received",
            color: Color(0xFFEAE6DA),
            values: [3, 2, 1],
            type: ChartType.line,
            smooth: true,
            points: true,
          ),
        ],
      ),
    );

    ChartElement chart() => controller.document.elements.single as ChartElement;
    expect(chart().data.series[1].smoothOn(chart().smooth), isTrue);

    await press(tester, find.byKey(const ValueKey("seriesMore1")));
    await press(tester, find.byKey(const ValueKey("seriesSmooth1")));

    // What the reader asked for is what the chart draws. Before, the panel
    // wrote the chart's own setting and the series' override went on winning.
    expect(chart().data.series[1].smoothOn(chart().smooth), isFalse,
        reason: "the switch has to change what is drawn");
    expect(chart().smooth, isFalse, reason: "and the chart's own with it");
    expect(chart().data.series[1].smooth, isNull,
        reason: "the leading series gives back its override rather than "
            "shadowing the value it just wrote");
  });

  testWidgets("and Points the same way", (tester) async {
    var controller = await panel(
      tester,
      const ChartData(
        categories: ["a", "b"],
        series: [
          ChartSeries(
            name: "Received",
            color: Color(0xFFEAE6DA),
            values: [3, 2],
            type: ChartType.line,
            points: true,
            pointSize: 4,
          ),
        ],
      ),
    );

    ChartElement chart() => controller.document.elements.single as ChartElement;
    await press(tester, find.byKey(const ValueKey("seriesMore0")));
    await press(tester, find.byKey(const ValueKey("seriesPoints0")));

    expect(chart().data.series[0].pointsOn(chart().showPoints), isFalse);
    expect(chart().data.series[0].points, isNull);
    expect(chart().data.series[0].pointSize, isNull,
        reason: "every drawing override goes back, not only the one pressed");
  });

  testWidgets("a series that does not lead keeps its own", (tester) async {
    // The overrides exist to differ from the leader, so the second line's
    // controls write its own and leave the chart alone.
    var controller = await panel(
      tester,
      const ChartData(
        categories: ["a", "b"],
        series: [
          ChartSeries(
              name: "One",
              color: Color(0xFFEAE6DA),
              values: [3, 2],
              type: ChartType.line),
          ChartSeries(
              name: "Two",
              color: Color(0xFFE8546B),
              values: [1, 2],
              type: ChartType.line),
        ],
      ),
    );

    ChartElement chart() => controller.document.elements.single as ChartElement;
    var was = chart().smooth;

    await press(tester, find.byKey(const ValueKey("seriesMore1")));
    await press(tester, find.byKey(const ValueKey("seriesSmooth1")));

    expect(chart().data.series[1].smooth, isNot(isNull));
    expect(chart().smooth, was, reason: "the chart's own is not touched");
    expect(chart().data.series[0].smooth, isNull, reason: "nor the leader's");
  });
}
