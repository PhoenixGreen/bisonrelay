import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_chart_draw_on_test.dart is a line being drawn on.
//
// It is traced from its start: at half way, the left half of the plot has a
// line in it and the right half has none. A dashed or dotted line is one path
// per stretch -- that is how a run of dashes is told from the solid part
// either side of it -- and trimming each of those by the fraction drew a
// fraction of every stretch at once, so the whole line appeared sparse and
// then filled in rather than arriving from the left.

const int _w = 400, _h = 200;
const Rect _rect = Rect.fromLTWH(0, 0, 400, 200);

ChartElement _chart(ChartLineStyle style) => ChartElement(
      const ElementBase(id: "c", width: 400, height: 200),
      type: ChartType.line,
      showLegend: false,
      showGrid: false,
      showAxes: false,
      showXLabels: false,
      showYLabels: false,
      showPoints: false,
      smooth: false,
      strokeWidth: 4,
      animation: const ChartAnimation(
          preset: ChartAnimationPreset.drawOn, ease: ChartEase.linear),
      data: ChartData(
        categories: const ["a", "b", "c", "d", "e", "f", "g"],
        series: [
          ChartSeries(
            name: "A",
            color: const Color(0xFF30E0A0),
            values: const [5, 5, 5, 5, 5, 5, 5],
            lineStyle: style,
          )
        ],
      ),
    );

/// _half is how much ink is in the left half of the plot, and how much in the
/// right.
Future<(double, double)> _half(ChartElement e, double reveal) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(_rect, Paint()..color = const Color(0xFF000000));
  paintChart(canvas, _rect, e, reveal: reveal);
  var image = await recorder.endRecording().toImage(_w, _h);
  var bytes = (await image.toByteData())!;
  image.dispose();
  var left = 0.0, right = 0.0;
  for (var y = 0; y < _h; y++) {
    for (var x = 0; x < _w; x++) {
      var v = (bytes.getUint32((y * _w + x) * 4) >> 8) & 0xFF;
      if (x < _w / 2) {
        left += v;
      } else {
        right += v;
      }
    }
  }
  return (left, right);
}

void main() {
  for (var style in ChartLineStyle.values) {
    testWidgets("a ${style.label.toLowerCase()} line arrives from its start",
        (tester) async {
      late (double, double) half, whole;
      await tester.runAsync(() async {
        half = await _half(_chart(style), 0.5);
        whole = await _half(_chart(style), 1);
      });

      expect(whole.$1, greaterThan(0));
      expect(whole.$2, greaterThan(0), reason: "all of it, at the end");

      // Half way: the left half is drawn and the right half is not. Not "less
      // ink overall" -- a line that appeared everywhere at a third of its
      // dashes would pass that and is exactly the fault this is about.
      expect(half.$1, greaterThan(whole.$1 * 0.8),
          reason: "the left half is there: ${half.$1} of ${whole.$1}");
      expect(half.$2, lessThan(whole.$2 * 0.1),
          reason: "and the right half is not: ${half.$2} of ${whole.$2}");
    });
  }
}
