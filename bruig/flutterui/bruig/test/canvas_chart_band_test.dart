import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_chart_band_test.dart is the space between two lines.
//
// A budget against what was paid out of it, a high against a low, a forecast
// against an outturn: the distance between the pair is the thing being shown,
// and two bare lines leave the reader to measure it by eye. An area series
// fills to zero, which answers a different question.

const int _w = 300, _h = 200;
const Rect _rect = Rect.fromLTWH(0, 0, 300, 200);

ChartElement _chart({
  bool band = false,
  bool hideSecond = false,
  List<double> lower = const [4, 4, 4, 4],
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
      strokeWidth: 2,
      yMin: 0,
      yMax: 12,
      data: ChartData(
        categories: const ["a", "b", "c", "d"],
        series: [
          ChartSeries(
            name: "Upper",
            color: const Color(0xFFEAE6DA),
            values: const [9, 9, 9, 9],
            band: band,
          ),
          ChartSeries(
            name: "Lower",
            color: const Color(0xFFE8546B),
            values: lower,
            hidden: hideSecond,
          ),
        ],
      ),
    );

/// _between is how many pixels are lit in the strip between the two lines,
/// clear of both strokes.
Future<int> _between(ChartElement e) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(_rect, Paint()..color = const Color(0xFF000000));
  paintChart(canvas, _rect, e);
  var image = await recorder.endRecording().toImage(_w, _h);
  var bytes = (await image.toByteData())!;
  image.dispose();
  // The middle of the plot vertically, and clear of the left and right edges.
  var n = 0;
  for (var y = (_h * 0.35).round(); y < (_h * 0.55).round(); y++) {
    for (var x = 40; x < _w - 40; x++) {
      var p = bytes.getUint32((y * _w + x) * 4);
      if (((p >> 24) & 0xFF) > 12 ||
          ((p >> 16) & 0xFF) > 12 ||
          ((p >> 8) & 0xFF) > 12) {
        n++;
      }
    }
  }
  return n;
}

void main() {
  group("a band between two lines", () {
    test("is remembered, and saved", () {
      var data = _chart(band: true).data;
      expect(data.series.first.band, isTrue);
      expect(ChartData.fromJson(data.toJson()).series.first.band, isTrue);
      // A chart without one saves the file it always did.
      expect(_chart().data.series.first.toJson().containsKey("band"), isFalse);
    });

    testWidgets("fills the space that was empty", (tester) async {
      late int bare, filled;
      await tester.runAsync(() async {
        bare = await _between(_chart());
        filled = await _between(_chart(band: true));
      });
      expect(bare, lessThan(50), reason: "two lines and air between them");
      expect(filled, greaterThan(2000), reason: "$filled against $bare");
    });

    testWidgets("goes when the line it fills to is switched off",
        (tester) async {
      // A band between a line and something nobody can see is a shape with
      // one visible edge.
      late int filled, alone;
      await tester.runAsync(() async {
        filled = await _between(_chart(band: true));
        alone = await _between(_chart(band: true, hideSecond: true));
      });
      expect(filled, greaterThan(2000));
      expect(alone, lessThan(50));
    });

    testWidgets("stops where either line has no reading", (tester) async {
      // A band over a year one of the two has no figure for would be a claim
      // about the distance between a number and nothing.
      late int whole, holed;
      await tester.runAsync(() async {
        whole = await _between(_chart(band: true));
        holed = await _between(
            _chart(band: true, lower: const [4, missingValue, 4, 4]));
      });
      expect(holed, lessThan(whole * 0.8), reason: "$holed of $whole");
      expect(holed, greaterThan(0),
          reason: "and the rest of it is still there");
    });
  });
}
