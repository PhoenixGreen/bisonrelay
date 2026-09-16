import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_data.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/components/paint_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_chart_gradient_test.dart is a series drawn in two colours.
//
// Where it runs is the part worth pinning: an angle read off a compass, the
// same way a text shadow's direction is read, and a radial one that runs out
// from the middle instead of across.

const _from = Color(0xFF3D7EFF);
const _to = Color(0xFFFF3DAA);

ChartElement _bars(GradientSpec? gradient) => ChartElement(
      const ElementBase(id: "c", width: 200, height: 160),
      type: ChartType.bar,
      showLegend: false,
      showXLabels: false,
      showYLabels: false,
      showGrid: false,
      data: ChartData(categories: const [
        "a"
      ], series: [
        ChartSeries(
            name: "s", color: _from, values: const [100], gradient: gradient),
      ]),
    );

/// _colours is what the chart actually painted, by where.
Future<List<int>> _row(ChartElement e, double atY) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 200, 160),
      Paint()..color = const Color(0xFF000000));
  paintChart(canvas, const Rect.fromLTWH(0, 0, 200, 160), e);
  var image = await recorder.endRecording().toImage(200, 160);
  var bytes = (await image.toByteData())!;
  var y = atY.round();
  var out = <int>[];
  for (var x = 0; x < 200; x++) {
    out.add(bytes.getUint32(((y * 200) + x) * 4));
  }
  image.dispose();
  return out;
}

/// _pinkness is how far along the gradient a pixel is, roughly: the second
/// colour is red and the first is blue, so the ratio says which end it is.
///
/// Minus one for anything that is not solidly the bar. The edges of a bar are
/// blended with the background, and a blend of the first colour reads as a
/// slightly different colour without being a different end of anything.
double _pinkness(int pixel) {
  var r = (pixel >> 24) & 0xFF;
  var b = (pixel >> 8) & 0xFF;
  if (r + b < 180) return -1;
  // And nothing grey: the axis line crosses the bar's row and is neither end
  // of anything. Both of these colours are strongly one side or the other.
  if ((r - b).abs() < 40) return -1;
  return r / (r + b);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("a series in two colours", () {
    testWidgets("is one colour until a second one is chosen", (tester) async {
      // Null rather than a gradient with a flag turned off: the second
      // colour is set in the picker now, and there either is one or there
      // is not.
      late List<int> flat;
      await tester.runAsync(() async {
        flat = await _row(_bars(null), 80);
      });
      var lit = [
        for (var p in flat)
          if (_pinkness(p) >= 0) _pinkness(p),
      ];
      expect(lit.length, greaterThan(20));
      expect(lit.reduce(math.max) - lit.reduce(math.min), lessThan(0.02),
          reason: "a series with no second colour is one flat colour");
    });

    testWidgets("runs down the bar by default", (tester) async {
      // 180 on a compass is downwards, so the series' own colour is at the
      // top and the second is at the bottom.
      late double top;
      late double bottom;
      await tester.runAsync(() async {
        var e = _bars(const GradientSpec(to: _to));
        top = (await _row(e, 30)).map(_pinkness).reduce(math.max);
        bottom = (await _row(e, 150)).map(_pinkness).reduce(math.max);
      });
      expect(bottom, greaterThan(top),
          reason: "it is pinker at the bottom than the top");
    });

    testWidgets("and across it when it is pointed across", (tester) async {
      late List<int> row;
      await tester.runAsync(() async {
        row = await _row(_bars(const GradientSpec(to: _to, angle: 90)), 80);
      });
      var lit = [
        for (var (x, p) in row.indexed)
          if (_pinkness(p) >= 0) (x, _pinkness(p)),
      ];
      expect(lit.length, greaterThan(20));
      expect(lit.last.$2, greaterThan(lit.first.$2),
          reason: "90 on a compass is to the right");
    });

    test("where it starts and ends is read off a compass", () {
      const square = Rect.fromLTWH(0, 0, 100, 100);
      var (up, _) = const GradientSpec(angle: 0).endsOf(square);
      expect(up.dy, greaterThan(50),
          reason: "0 runs upwards, so it starts low");
      var (right, _) = const GradientSpec(angle: 90).endsOf(square);
      expect(right.dx, lessThan(50),
          reason: "90 runs right, so it starts left");
    });

    test("it survives being saved, and costs nothing when unused", () {
      const series = ChartSeries(
          name: "s",
          color: _from,
          values: [1],
          gradient: GradientSpec(to: _to, angle: 45, radial: true));
      var back = ChartSeries.fromJson(series.toJson(), 0);
      expect(back.gradient, series.gradient);

      const plain = ChartSeries(name: "s", color: _from, values: [1]);
      expect(plain.toJson().containsKey("gradient"), isFalse);
      expect(ChartSeries.fromJson(plain.toJson(), 0).gradient, isNull);
    });

    test("and going back to one colour forgets it", () {
      const series = ChartSeries(
          name: "s",
          color: _from,
          values: [1],
          gradient: GradientSpec(to: _to));
      expect(series.copyWith(name: "t").gradient, isNotNull);
      expect(series.copyWith(oneColour: true).gradient, isNull);
    });
  });

  group("the dots on a line", () {
    // A line says the shape of a series and a dot says where a reading
    // actually is. Eleven points joined up look like a hundred until the
    // dots are on them.
    ChartElement lined({bool points = false, double size = 0, Color? colour}) =>
        ChartElement(
          const ElementBase(id: "c", width: 200, height: 160),
          type: ChartType.line,
          showLegend: false,
          showXLabels: false,
          showYLabels: false,
          showGrid: false,
          showPoints: points,
          pointSize: size,
          pointColor: colour ?? const Color(0x00000000),
          data: ChartData(categories: const [
            "a",
            "b",
            "c"
          ], series: [
            const ChartSeries(name: "s", color: _from, values: [50, 100, 50]),
          ]),
        );

    /// _inkOf counts the pixels of one colour in the whole picture.
    Future<int> inkOf(
        ChartElement e, bool Function(int r, int g, int b) is_) async {
      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 200, 160),
          Paint()..color = const Color(0xFF000000));
      paintChart(canvas, const Rect.fromLTWH(0, 0, 200, 160), e);
      var image = await recorder.endRecording().toImage(200, 160);
      var bytes = (await image.toByteData())!;
      var n = 0;
      for (var i = 0; i < bytes.lengthInBytes; i += 4) {
        var p = bytes.getUint32(i);
        if (is_((p >> 24) & 0xFF, (p >> 16) & 0xFF, (p >> 8) & 0xFF)) n++;
      }
      image.dispose();
      return n;
    }

    bool blue(int r, int g, int b) => b > 0x90 && b > r + 0x40;
    bool amber(int r, int g, int b) => r > 0x90 && g > 0x70 && b < 0x80;

    testWidgets("are off until they are asked for", (tester) async {
      late int without;
      late int with_;
      await tester.runAsync(() async {
        without = await inkOf(lined(), blue);
        with_ = await inkOf(lined(points: true), blue);
      });
      expect(without, greaterThan(0), reason: "the line itself is drawn");
      expect(with_, greaterThan(without),
          reason: "and the dots are ink the line did not have");
    });

    testWidgets("and a bigger one is more ink still", (tester) async {
      // Against the line's own ink rather than against nothing: most of the
      // blue in the picture is the line, whatever the dots are doing.
      late int line;
      late int small;
      late int large;
      await tester.runAsync(() async {
        line = await inkOf(lined(), blue);
        small = await inkOf(lined(points: true, size: 3), blue);
        large = await inkOf(lined(points: true, size: 9), blue);
      });
      expect(large - line, greaterThan((small - line) * 2),
          reason: "three times the radius is a good deal more dot");
    });

    testWidgets("in their own colour where one is given", (tester) async {
      late int dots;
      late int none;
      await tester.runAsync(() async {
        none = await inkOf(lined(points: true), amber);
        dots = await inkOf(
            lined(points: true, size: 6, colour: const Color(0xFFFFD166)),
            amber);
      });
      expect(none, 0, reason: "a dot is the series' colour until one is set");
      expect(dots, greaterThan(100));
    });

    test("and the settings survive being saved", () {
      var e = ChartElement(
        const ElementBase(id: "c"),
        showPoints: true,
        pointSize: 7,
        pointColor: const Color(0xFFFFD166),
      );
      var back = ChartElement.fromJson(e.toJson(), e.base);
      expect(back.showPoints, isTrue);
      expect(back.pointSize, 7);
      expect(back.pointColor, const Color(0xFFFFD166));

      // And a chart that has never had them saves nothing.
      const plain = ChartElement(ElementBase(id: "c"));
      expect(plain.toJson().containsKey("points"), isFalse);
      expect(plain.toJson().containsKey("pointSize"), isFalse);
    });

    testWidgets("a series drawn at its own thickness", (tester) async {
      // So that a line laid over a set of bars can be heavy enough to read
      // against them without every other line on the chart thickening too.
      ChartElement at(double width) => ChartElement(
            const ElementBase(id: "c", width: 200, height: 160),
            type: ChartType.line,
            showLegend: false,
            showXLabels: false,
            showYLabels: false,
            showGrid: false,
            strokeWidth: 2,
            data: ChartData(categories: const [
              "a",
              "b",
              "c"
            ], series: [
              ChartSeries(
                  name: "s",
                  color: _from,
                  values: const [50, 100, 50],
                  width: width),
            ]),
          );

      late int chart;
      late int own;
      await tester.runAsync(() async {
        chart = await inkOf(at(0), blue);
        own = await inkOf(at(9), blue);
      });
      expect(own, greaterThan(chart * 2),
          reason: "nine is a good deal thicker than the chart's two");
    });
  });
}
