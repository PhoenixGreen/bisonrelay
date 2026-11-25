import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_cartesian.dart'
    show ticksWithinForTest;
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_chart_fixed_range_test.dart is a chart whose value axis is set to
// run between two numbers (Ken, 2026-11-25, the bear market video's staked
// chart, set to 50..70): its lines and their numbers stay within it. An
// area chart's own range starts from zero, and the lines worked out for
// 0..80 were kept when the range was set, so "80" was drawn on the chart
// above and 0 and 40 below.

ChartElement _staked(ChartType type) => ChartElement(
      const ElementBase(id: "c", width: 400, height: 200),
      type: type,
      showLegend: false,
      showGrid: true,
      showAxes: true,
      showYLabels: true,
      showXLabels: false,
      axisSteps: 2,
      yMin: 50,
      yMax: 70,
      data: ChartData(
        categories: const ["a", "b", "c", "d", "e"],
        series: [
          ChartSeries(
              name: "Staked",
              color: const Color(0xFF2ED6A1),
              values: const [60.4, 57.5, 61.8, 62.9, 64.1]),
        ],
      ),
    );

/// _litOutside is how many pixels are drawn outside [box] on a page of
/// [page], the chart painted into [box].
Future<int> _litOutside(ChartElement e, Size page, Rect box) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(Offset.zero & page, Paint()..color = const Color(0xFF000000));
  paintChart(canvas, box, e);
  var w = page.width.toInt(), h = page.height.toInt();
  var image = await recorder.endRecording().toImage(w, h);
  var bytes = (await image.toByteData())!;
  image.dispose();
  var n = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      // A number sits centred on its line, so the ones at the top and
      // bottom stand half their height past the edge; no further.
      if (box.inflate(12).contains(Offset(x + 0.5, y + 0.5))) continue;
      var p = bytes.getUint32((y * w + x) * 4);
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
  for (var type in [ChartType.area, ChartType.line, ChartType.bar]) {
    testWidgets("${type.name} set to 50..70 draws nothing outside itself",
        (tester) async {
      late int outside;
      await tester.runAsync(() async {
        outside = await _litOutside(_staked(type), const Size(600, 600),
            const Rect.fromLTWH(100, 200, 400, 200));
      });
      expect(outside, 0, reason: "no line or number above or below it");
    });
  }

  test("the lines of a set range are round numbers within it", () {
    expect(ticksWithinForTest(50, 70, 2), [50, 60, 70]);
    expect(
        ticksWithinForTest(52, 69, 0).every((t) => t >= 52 && t <= 69), isTrue);
    expect(ticksWithinForTest(0, 1, 4), [0, 0.25, 0.5, 0.75, 1]);
  });
}
