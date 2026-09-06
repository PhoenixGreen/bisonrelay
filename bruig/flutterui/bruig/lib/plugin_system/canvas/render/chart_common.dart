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

/// colouredByValue is whether a type takes its colours from the values rather
/// than from the series they are in.
bool colouredByValue(ChartType type) =>
    type == ChartType.pie ||
    type == ChartType.donut ||
    type == ChartType.radialBar;

/// formatTick prints an axis value without trailing noise.
String formatTick(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) {
    var n = v.round();
    if (n.abs() >= 1000000) return "${(n / 1000000).toStringAsFixed(1)}M";
    if (n.abs() >= 10000) return "${(n / 1000).toStringAsFixed(0)}k";
    return "$n";
  }
  return v.toStringAsFixed(v.abs() < 1 ? 2 : 1);
}
