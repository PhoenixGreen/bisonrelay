import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_data.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/chart_data_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_series_style_test.dart is where a chart's drawing settings live now.
//
// They were three groups under the table -- Bars, Lines, Points -- which on
// the commonest interesting chart, a set of bars with a line over it, were
// three groups each about half of the chart with nothing to say which half.
// Every one of them is on the series it draws now, behind that series' own
// button.
//
// That leaves the question of what a second set of bars is drawn like before
// anybody has said. The answer is: like the first set. The first series drawn
// a given way writes the chart's own setting, and every other series drawn the
// same way reads it until it is given one of its own -- so there is always a
// sensible answer and never a series that has to be set up from scratch.

void main() {
  group("a series drawn like the first one", () {
    test("follows it", () {
      const plain = ChartSeries(name: "A", color: Colors.blue, values: [1]);
      expect(plain.cornerOn(6), 6);
      expect(plain.smoothOn(true), isTrue);
      expect(plain.pointsOn(true), isTrue);
      expect(plain.pointSizeOn(3), 3);
      expect(
          plain.pointColorOn(const Color(0xFF00FF00)), const Color(0xFF00FF00));
    });

    test("and stops following once it has its own", () {
      const own = ChartSeries(
        name: "A",
        color: Colors.blue,
        values: [1],
        corner: 0,
        smooth: false,
        points: false,
        pointSize: 0,
      );
      // Every one of these has a meaningful zero -- a corner of nought is a
      // square bar, points off is points off -- which is why "mine" is null
      // and not a sentinel.
      expect(own.cornerOn(6), 0);
      expect(own.smoothOn(true), isFalse);
      expect(own.pointsOn(true), isFalse);
      expect(own.pointSizeOn(3), 0);
    });

    test("and a saved file only carries what was actually set", () {
      const plain = ChartSeries(name: "A", color: Colors.blue, values: [1]);
      var json = plain.toJson();
      expect(json.containsKey("corner"), isFalse);
      expect(json.containsKey("smooth"), isFalse);

      var own = plain.copyWith(corner: 0, smooth: true, pointSize: 5);
      var back = ChartSeries.fromJson(own.toJson(), 0);
      expect(back.corner, 0);
      expect(back.smooth, isTrue);
      expect(back.pointSize, 5);
      expect(back.points, isNull, reason: "untouched, so still following");
    });
  });

  group("the series that leads its kind", () {
    late ChartData? wroteData;
    late ChartStyleDefaults? wroteStyle;

    Future<void> show(
      WidgetTester tester,
      ChartData data, {
      ChartType type = ChartType.bar,
      ChartStyleDefaults style = const ChartStyleDefaults(),
    }) async {
      wroteData = null;
      wroteStyle = null;
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => ThemeNotifier(doLoad: false),
          child: Scaffold(
            body: SingleChildScrollView(
              child: CanvasControlScope(
                maxWidth: 380,
                child: SizedBox(
                  width: 380,
                  child: ChartDataEditor(
                    data: data,
                    chartType: type,
                    style: style,
                    onChanged: (d) => wroteData = d,
                    onStyleChanged: (s) => wroteStyle = s,
                    onCommit: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> open(WidgetTester tester, int i) async {
      await tester.tap(find.byKey(ValueKey("seriesMore$i")));
      await tester.pumpAndSettle();
    }

    void set(WidgetTester tester, String key, double value) => tester
        .widget<CanvasNumberField>(find.byKey(ValueKey(key)))
        .onChanged(value);

    testWidgets("writes the chart's own setting, so the rest follow it",
        (tester) async {
      await show(tester, ChartData.parse("Cat\tOne\tTwo\nx\t10\t4"));
      await open(tester, 0);
      set(tester, "seriesCorner0", 12);

      expect(wroteStyle?.corner, 12);
      expect(wroteData, isNull,
          reason: "nothing of its own: this is the chart's answer now");
    });

    testWidgets("while the ones behind it keep their own", (tester) async {
      await show(tester, ChartData.parse("Cat\tOne\tTwo\nx\t10\t4"));
      await open(tester, 1);
      set(tester, "seriesCorner1", 12);

      expect(wroteStyle, isNull, reason: "the first set of bars is untouched");
      expect(wroteData?.series[1].corner, 12);
      expect(wroteData?.series[0].corner, isNull);
    });

    testWidgets("and a second series opens on what it inherits",
        (tester) async {
      await show(tester, ChartData.parse("Cat\tOne\tTwo\nx\t10\t4"),
          style: const ChartStyleDefaults(corner: 9));
      await open(tester, 1);
      expect(
          tester
              .widget<CanvasNumberField>(
                  find.byKey(const ValueKey("seriesCorner1")))
              .value,
          9,
          reason: "never a bare nought that has to be decoded");
    });

    testWidgets("is worked out per kind of drawing, not per position",
        (tester) async {
      // The commonest interesting chart: a set of bars with a line over it.
      // The line is the second series and the first line, so it is the one
      // that answers for lines.
      var data = ChartData.parse("Cat\tBars\tLine\nx\t10\t4");
      data = ChartData(categories: data.categories, series: [
        data.series[0],
        data.series[1].copyWith(type: ChartType.line),
      ]);
      await show(tester, data);

      await open(tester, 1);
      set(tester, "seriesWidth1", 7);
      expect(wroteStyle?.width, 7, reason: "it leads the lines");
      expect(wroteData, isNull);
    });

    testWidgets("so the first set of bars still answers for the bars",
        (tester) async {
      var data = ChartData.parse("Cat\tBars\tLine\nx\t10\t4");
      data = ChartData(categories: data.categories, series: [
        data.series[0],
        data.series[1].copyWith(type: ChartType.line),
      ]);
      await show(tester, data);

      await open(tester, 0);
      set(tester, "seriesCorner0", 3);
      expect(wroteStyle?.corner, 3);
    });

    testWidgets("spacing is only on the bars that lead", (tester) async {
      // The bars all stand in the same slots, so how wide those slots are is
      // one number for the chart -- not one per series that would quietly
      // overrule the others.
      await show(tester, ChartData.parse("Cat\tOne\tTwo\nx\t10\t4"));
      await open(tester, 0);
      await open(tester, 1);
      expect(find.byKey(const ValueKey("seriesGap0")), findsOneWidget);
      expect(find.byKey(const ValueKey("seriesGap1")), findsNothing);
      expect(find.byKey(const ValueKey("seriesCorner1")), findsOneWidget);
    });
  });

  group("and the drawing follows the series, not the chart", () {
    // The wiring the settings are worth nothing without: a per-series answer
    // the painter never reads is a control that does nothing, which is
    // indistinguishable from a broken one.
    const size = Rect.fromLTWH(0, 0, 200, 160);

    ChartElement lined(List<ChartSeries> series) => ChartElement(
          const ElementBase(id: "c", width: 200, height: 160),
          type: ChartType.line,
          showLegend: false,
          showXLabels: false,
          showYLabels: false,
          showGrid: false,
          data: ChartData(categories: const ["a", "b", "c"], series: series),
        );

    const blue = Color(0xFF3D7EFF);
    const amber = Color(0xFFFFB020);

    /// amberInk counts the pixels of the second series' colour.
    Future<int> amberInk(ChartElement e) async {
      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      canvas.drawRect(size, Paint()..color = const Color(0xFF000000));
      paintChart(canvas, size, e);
      var image = await recorder.endRecording().toImage(200, 160);
      var bytes = (await image.toByteData())!;
      var n = 0;
      for (var i = 0; i < bytes.lengthInBytes; i += 4) {
        var p = bytes.getUint32(i);
        var r = (p >> 24) & 0xFF, g = (p >> 16) & 0xFF, b = (p >> 8) & 0xFF;
        if (r > 0x90 && g > 0x70 && b < 0x80) n++;
      }
      image.dispose();
      return n;
    }

    testWidgets("one series can be dotted while the other is not",
        (tester) async {
      late int following, own;
      await tester.runAsync(() async {
        const first = ChartSeries(name: "a", color: blue, values: [50, 90, 50]);
        const second =
            ChartSeries(name: "b", color: amber, values: [20, 60, 20]);
        following = await amberInk(lined(const [first, second]));
        own = await amberInk(
            lined([first, second.copyWith(points: true, pointSize: 5)]));
      });
      expect(own, greaterThan(following),
          reason: "the dots are on the series that asked for them");
    });

    testWidgets("and one can be thicker than the other", (tester) async {
      late int thin, thick;
      await tester.runAsync(() async {
        const first = ChartSeries(name: "a", color: blue, values: [50, 90, 50]);
        const second =
            ChartSeries(name: "b", color: amber, values: [20, 60, 20]);
        thin = await amberInk(lined(const [first, second]));
        thick = await amberInk(lined([first, second.copyWith(width: 9)]));
      });
      expect(thick, greaterThan(thin));
    });
  });
}
