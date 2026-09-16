import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_data.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_chart_bounds_test.dart is how much of its own box a chart fills.
//
// Reported while lining elements up: a chart's box sat well away from the
// chart in it, so aligning a chart with anything else looked wrong. The room
// was being kept for labels and axis titles that were switched off -- a
// margin around nothing, and the element's box is what snapping and the
// alignment tools work on.

const _size = 200;

ChartElement _chart({
  bool labels = false,
  bool titles = false,
  String xLabel = "",
  String yLabel = "",
}) =>
    ChartElement(
      const ElementBase(id: "c", width: 200, height: 200),
      type: ChartType.line,
      showLegend: false,
      showGrid: false,
      showXLabels: labels,
      showYLabels: labels,
      showXTitle: titles,
      showYTitle: titles,
      xAxisLabel: xLabel,
      yAxisLabel: yLabel,
      data: const ChartData(categories: [
        "a",
        "b"
      ], series: [
        // Corner to corner, so the drawn line touches all four sides of the
        // plot and the ink is the plot.
        ChartSeries(name: "s", color: Color(0xFF3D7EFF), values: [0, 100]),
      ]),
    );

/// _inked is the box the bars are drawn in.
///
/// The bars rather than every drawn pixel: the labels are ink too, and they
/// sit in the gutters -- so a chart whose plot has moved inwards still has ink
/// out at the edges, and measuring all of it would say nothing had changed.
Future<Rect> _inked(ChartElement e) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  paintChart(canvas, const Rect.fromLTWH(0, 0, 200, 200), e);
  var image = await recorder.endRecording().toImage(_size, _size);
  var bytes = (await image.toByteData())!;
  var left = _size, top = _size, right = -1, bottom = -1;
  for (var y = 0; y < _size; y++) {
    for (var x = 0; x < _size; x++) {
      var pixel = bytes.getUint32((y * _size + x) * 4);
      var r = (pixel >> 24) & 0xFF;
      var g = (pixel >> 16) & 0xFF;
      var b = (pixel >> 8) & 0xFF;
      // The series' own blue, and nothing else on the canvas is it.
      if (!(b > 0x90 && b > r + 0x40 && b > g + 0x20)) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  image.dispose();
  return Rect.fromLTRB(
      left.toDouble(), top.toDouble(), right.toDouble(), bottom.toDouble());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("with the labels and titles off it fills its box",
      (tester) async {
    // A line from the bottom left to the top right, so what is drawn is the
    // plot: with nothing else on the chart it should reach all four edges but
    // for half the line's own width.
    late Rect ink;
    await tester.runAsync(() async => ink = await _inked(_chart()));

    // Top and bottom exactly: the first value is the range's floor and the
    // last is its ceiling, so the line starts on the plot's bottom edge and
    // ends on its top one. Left and right are not the plot's edges even in
    // principle -- a categorical x puts its points at the middle of each
    // category -- so those are compared against a labelled chart below rather
    // than asserted outright.
    expect(ink.top, lessThan(6), reason: "nothing kept over the top");
    expect(ink.bottom, greaterThan(_size - 6),
        reason: "nor under the bottom, which is where the strip of nothing "
            "an axis title would have taken used to be");
  });

  testWidgets("a name typed for an axis costs nothing while it is hidden",
      (tester) async {
    // The room was kept for whether a title had been *typed* rather than for
    // whether it is shown, so naming an axis and turning titles off left a
    // strip of nothing along the bottom.
    late Rect bare;
    late Rect named;
    await tester.runAsync(() async {
      bare = await _inked(_chart());
      named = await _inked(_chart(xLabel: "Coin", yLabel: "Price"));
    });
    expect(named, bare);
  });

  testWidgets("and turning them on does take room", (tester) async {
    // The other half: the gutters are not gone, they are conditional.
    late Rect bare;
    late Rect shown;
    await tester.runAsync(() async {
      bare = await _inked(_chart());
      shown = await _inked(
          _chart(labels: true, titles: true, xLabel: "Coin", yLabel: "Price"));
    });
    // Measured on the left rather than the bottom: the labels are ink too,
    // so the drawn box still reaches the bottom edge -- it is the plot inside
    // it that has moved, and the value gutter is what shows that.
    expect(shown.left, greaterThan(bare.left + 10),
        reason: "the value labels take a gutter down the left");
  });

  testWidgets("labels off leaves no air over the top tick", (tester) async {
    // The air exists so the topmost label is not cut in half by the edge.
    // With no labels there is nothing to cut.
    late Rect bare;
    late Rect labelled;
    await tester.runAsync(() async {
      bare = await _inked(_chart());
      labelled = await _inked(_chart(labels: true));
    });
    expect(bare.top, lessThanOrEqualTo(labelled.top));
    expect(bare.top, lessThan(6), reason: "the line reaches the top edge");
  });
}
