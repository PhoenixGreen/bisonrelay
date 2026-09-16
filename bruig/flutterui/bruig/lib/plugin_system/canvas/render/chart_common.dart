import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:flutter/painting.dart';

// chart_common.dart is the handful of things both halves of the chart painter
// need.
//
// A chart is drawn by one of two quite different painters -- see
// chart_cartesian.dart and chart_circular.dart -- and neither is the natural
// home for these. How far through its own animation one item is, what colour
// it takes and how a number is written are decisions that have to come out
// the same on a pie and on a bar chart, and the legend has to agree with both
// or its swatches quietly stop matching the picture.

/// SliceProgress is what one item of a circular chart is doing: how big it
/// is, and how solid.
///
/// One little object rather than two doubles, because every circular type
/// needs both and the branches that use them are already long enough.
class SliceProgress {
  final double size;
  final double alpha;
  const SliceProgress(this.size, this.alpha);

  bool get gone => size <= 0 || alpha <= 0;

  Color tint(Color colour) =>
      alpha >= 1 ? colour : colour.withValues(alpha: colour.a * alpha);
}

/// sliceProgress works out both from the chart's animation.
SliceProgress sliceProgress(
    ChartElement e, double reveal, int index, int count) {
  if (!e.animation.on || reveal >= 1) return const SliceProgress(1, 1);
  var p = e.animation.progressAt(reveal, index, count);
  switch (e.animation.preset) {
    case ChartAnimationPreset.fadeIn:
      return SliceProgress(1, p.clamp(0.0, 1.0));
    case ChartAnimationPreset.grow:
    case ChartAnimationPreset.popIn:
    case ChartAnimationPreset.random:
    case ChartAnimationPreset.drawOn:
      return SliceProgress(p, 1);
    case ChartAnimationPreset.none:
    case ChartAnimationPreset.wipe:
    case ChartAnimationPreset.sweep:
      return const SliceProgress(1, 1);
  }
}

/// sliceColour is what the i-th value of a circular chart is drawn in.
///
/// Shared with the painter deliberately. A legend whose swatches were worked
/// out separately would be a legend that quietly stopped matching the chart
/// the first time either changed.
Color sliceColour(ChartElement e, int i) {
  var series = e.data.series;
  if (e.type != ChartType.radialBar && series.length > 1 && i < series.length) {
    return series[i].color;
  }
  return chartPalette[i % chartPalette.length];
}

/// seriesShader is the gradient a series is drawn with across [area], or null
/// where it is one colour.
///
/// One definition, because the bars, the area under a line and the line
/// itself all ask: a gradient that ran one way on the bars and another on the
/// line over them would be two gradients wearing one setting. [alpha] is
/// whatever the arrival has done to it, applied to both ends so a series
/// fading in fades as a whole.
ui.Shader? seriesShader(ChartSeries series, Rect area, {double alpha = 1}) =>
    series.paint.shaderFor(area, alpha: alpha);

/// colouredByValue is whether a type takes its colours from the values rather
/// than from the series they are in.
bool colouredByValue(ChartType type) =>
    type == ChartType.pie ||
    type == ChartType.donut ||
    type == ChartType.radialBar;

/// formatTick prints a value the way the chart writes them: on a bar, on a
/// point, in a legend that carries values.
///
/// Through the element rather than as a bare function, because how a number
/// is written is a setting -- and the places a chart writes one have to
/// agree with each other. See ChartNumbers.
String formatTick(ChartElement e, double v) => e.numbers.format(v);

/// formatSeries prints a value belonging to series [s], which may write its
/// numbers differently from the rest of the chart.
///
/// A price beside a market cap is two series four orders of magnitude apart,
/// and one style across both writes either "0.0B" against the price or eleven
/// digits against the cap. Where a series says nothing, it is the chart's own
/// style -- which is every series on almost every chart. See
/// ChartSeries.numbers.
String formatSeries(ChartElement e, int s, double v) {
  var series = s >= 0 && s < e.data.series.length ? e.data.series[s] : null;
  return (series?.numbers ?? e.numbers).format(v);
}

/// formatAxis prints a figure up the side.
///
/// Its own function because it is its own setting, or rather it is the same
/// one until somebody says otherwise: a value is a reading and wants to be
/// exact, an axis is a scale and wants to be round, so 2.049M on the bar
/// against 2.0M on the axis is a deliberate pairing.
String formatAxis(ChartElement e, double v) => e.axisFigures.format(v);
