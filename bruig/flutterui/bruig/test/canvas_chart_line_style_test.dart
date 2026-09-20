import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_chart_line_style_test.dart is a line drawn as dashes or as dots.
//
// A property of the series, and a different statement from the dashes that
// mark an estimated year: those say "this figure was worked out", this says
// "this line is a different kind of thing from the one beside it" -- a
// projection against a measurement, a target against a total.

const int _w = 300, _h = 200;
const Rect _rect = Rect.fromLTWH(0, 0, 300, 200);
const Color _ink = Color(0xFF30E0A0);

ChartElement _chart({
  ChartLineStyle style = ChartLineStyle.solid,
  List<bool> estimated = const [],
}) =>
    ChartElement(
      const ElementBase(id: "c", width: 300, height: 200),
      type: ChartType.line,
      showLegend: false,
      showGrid: false,
      showAxes: false,
      showXLabels: false,
      showYLabels: false,
      showPoints: false,
      smooth: false,
      strokeWidth: 4,
      data: ChartData(
        categories: const ["a", "b", "c", "d", "e"],
        estimated: estimated,
        series: [
          ChartSeries(
            name: "A",
            color: _ink,
            values: const [5, 5, 5, 5, 5],
            lineStyle: style,
          )
        ],
      ),
    );

/// _ink is how much of the line's colour was laid down.
Future<double> _weight(ChartElement e) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(_rect, Paint()..color = const Color(0xFF000000));
  paintChart(canvas, _rect, e);
  var image = await recorder.endRecording().toImage(_w, _h);
  var bytes = (await image.toByteData())!;
  image.dispose();
  var total = 0.0;
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    total += (bytes.getUint32(i) >> 8) & 0xFF;
  }
  return total;
}

void main() {
  group("a series drawn as dashes or dots", () {
    test("says which, and saves it", () {
      var dotted = _chart(style: ChartLineStyle.dotted).data;
      expect(dotted.series.single.lineStyle, ChartLineStyle.dotted);
      expect(ChartData.fromJson(dotted.toJson()).series.single.lineStyle,
          ChartLineStyle.dotted);
      // A solid line saves the file it always did.
      expect(_chart().data.series.single.toJson().containsKey("line"), isFalse);
    });

    testWidgets("lays down less ink than a solid one", (tester) async {
      late double solid, dashed, dotted;
      await tester.runAsync(() async {
        solid = await _weight(_chart());
        dashed = await _weight(_chart(style: ChartLineStyle.dashed));
        dotted = await _weight(_chart(style: ChartLineStyle.dotted));
      });
      expect(solid, greaterThan(0));
      expect(dashed, lessThan(solid * 0.8), reason: "$dashed of $solid");
      // Dots are the sparsest of the three, and still there.
      expect(dotted, lessThan(dashed), reason: "$dotted against $dashed");
      expect(dotted, greaterThan(solid * 0.05),
          reason: "a dot is a dash of almost no length, not nothing at all");
    });

    testWidgets("stays dotted across an estimated stretch", (tester) async {
      // The two marks would otherwise fight: a dotted series whose estimated
      // years turned into dashes would read as a different series there.
      // Faintness carries the estimate instead.
      late double all, some;
      await tester.runAsync(() async {
        all = await _weight(_chart(style: ChartLineStyle.dotted));
        some = await _weight(_chart(
            style: ChartLineStyle.dotted,
            estimated: const [false, true, true, false, false]));
      });
      expect(some, lessThan(all), reason: "the marked stretch is fainter");
      expect(some, greaterThan(all * 0.4),
          reason: "and still dotted, not gone");
    });
  });

  testWidgets("it is set on the series, from its own button", (tester) async {
    var element = ChartElement(
      const ElementBase(id: "c", width: 400, height: 300),
      type: ChartType.line,
      data: ChartData.parse("Cat\tA\nx\t1\ny\t2"),
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

    var more = find.byKey(const ValueKey("seriesMore0"));
    await tester.ensureVisible(more);
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pumpAndSettle();

    var picker = find.byKey(const ValueKey("seriesLineStyle0"));
    expect(picker, findsOneWidget);
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Dotted").last);
    await tester.pumpAndSettle();

    var chart = controller.document.elements.single as ChartElement;
    expect(chart.data.series.single.lineStyle, ChartLineStyle.dotted);
  });
}
