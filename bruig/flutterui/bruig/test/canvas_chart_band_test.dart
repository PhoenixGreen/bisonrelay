import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
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
  bool smooth = false,
  ChartAnimation animation = const ChartAnimation(),
  List<double> upper = const [9, 9, 9, 9],
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
      smooth: smooth,
      animation: animation,
      strokeWidth: 2,
      yMin: 0,
      yMax: 12,
      data: ChartData(
        categories: const ["a", "b", "c", "d"],
        series: [
          ChartSeries(
            name: "Upper",
            color: const Color(0xFFEAE6DA),
            values: upper,
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
Future<int> _between(ChartElement e, {double reveal = 1}) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(_rect, Paint()..color = const Color(0xFF000000));
  paintChart(canvas, _rect, e, reveal: reveal);
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

/// _gaps is how many columns have a dark row between the top of the upper
/// line and the top of the band under it.
///
/// Which is exactly what a chorded edge leaves behind: the line bows above
/// the straight run between two readings, and the band stops at the straight
/// run. Nothing else on these charts can put a hole there.
Future<int> _gaps(ChartElement e) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(_rect, Paint()..color = const Color(0xFF000000));
  paintChart(canvas, _rect, e);
  var image = await recorder.endRecording().toImage(_w, _h);
  var bytes = (await image.toByteData())!;
  image.dispose();

  bool lit(int x, int y) {
    var p = bytes.getUint32((y * _w + x) * 4);
    return ((p >> 24) & 0xFF) > 10 ||
        ((p >> 16) & 0xFF) > 10 ||
        ((p >> 8) & 0xFF) > 10;
  }

  var holed = 0;
  // Between the readings, where a chord and a curve differ. Not at them,
  // where the two meet whatever the edge is made of.
  for (var x in [60, 80, 100, 120, 180, 220, 240]) {
    var top = -1, bottom = -1;
    for (var y = 0; y < _h; y++) {
      if (!lit(x, y)) continue;
      if (top < 0) top = y;
      bottom = y;
    }
    if (top < 0) continue;
    for (var y = top; y < bottom; y++) {
      if (!lit(x, y)) {
        holed++;
        break;
      }
    }
  }
  return holed;
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

    testWidgets("follows the lines when they are curved", (tester) async {
      // Both edges were drawn as chords while the lines bowed away from them,
      // so between every pair of readings the band stood clear of its own
      // edge and left a stripe of background between the two.
      late int holed;
      await tester.runAsync(() async {
        holed = await _gaps(_chart(
            band: true,
            smooth: true,
            upper: const [3, 11, 11, 3],
            lower: const [1, 2, 2, 1]));
      });
      expect(holed, 0,
          reason: "$holed of the sampled columns have background showing "
              "between the line and the band it bounds");
    });

    testWidgets("arrives with its lines rather than under them",
        (tester) async {
      // Drawing it on with the first line was glitchy in two ways at once.
      // The shape is built out of whole readings, so it stepped across a
      // category at a time under a line moving smoothly -- and the lines are
      // staggered, so for the first half of the arrival it was a band with
      // one edge and nothing on the other.
      const drawing = ChartAnimation(preset: ChartAnimationPreset.drawOn);
      late int lines, early, whole;
      await tester.runAsync(() async {
        lines = await _between(_chart(animation: drawing), reveal: 0.5);
        early =
            await _between(_chart(band: true, animation: drawing), reveal: 0.5);
        whole =
            await _between(_chart(band: true, animation: drawing), reveal: 1);
      });
      expect(early, lessThan(lines + 50),
          reason: "$early lit against $lines with no band asked for at all");
      expect(whole, greaterThan(2000), reason: "and all of it at the end");
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
