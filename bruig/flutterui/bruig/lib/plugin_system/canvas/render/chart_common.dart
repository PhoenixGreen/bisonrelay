import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:flutter/painting.dart';

// chart_common.dart is what chart_cartesian.dart, chart_circular.dart and the
// legend in chart_painter.dart must agree on: item progress, colours and
// number formats.

/// SliceProgress is what one item of a circular chart is doing: how big it
/// is, and how solid.
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
    case ChartAnimationPreset.fadeIn || ChartAnimationPreset.morph:
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

/// sliceColour is what the i-th value of a circular chart is drawn in, for
/// the painter and the legend alike.
Color sliceColour(ChartElement e, int i) {
  // A highlight's or a colour-by's colour first (ChartData.marks).
  if (e.data.markAt(i) case var mark?) return mark;
  if (i >= 0 && i < e.sliceColors.length) return e.sliceColors[i];
  var series = e.data.series;
  if (e.type != ChartType.radialBar && series.length > 1 && i < series.length) {
    return series[i].color;
  }
  return chartPalette[i % chartPalette.length];
}

/// barsTakeColours is whether [e] is bars of one series, which can take a
/// colour per bar from the slice colours.
bool barsTakeColours(ChartElement e) =>
    (e.type == ChartType.bar || e.type == ChartType.horizontalBar) &&
    e.data.series.length == 1;

/// barColour is what the bar for category [i] is drawn in, on a chart whose
/// bars take colours: its own where it has one, and the series' otherwise.
Color barColour(ChartElement e, int i) =>
    i >= 0 && i < e.sliceColors.length && barsTakeColours(e)
        ? e.sliceColors[i]
        : e.data.series.first.color;

/// seriesShader is the gradient a series is drawn with across [area], or null
/// where it is one colour.
///
/// Shared by bars, areas and lines so they agree. [alpha] is the arrival's
/// fade, applied to both ends.
ui.Shader? seriesShader(ChartSeries series, Rect area, {double alpha = 1}) =>
    series.paint.shaderFor(area, alpha: alpha);

/// underShader is the colour to give a paint that has been handed a shader.
///
/// Opaque when there is a shader: a paint's alpha multiplies its shader, so
/// a faded flat colour would apply the fade twice. Otherwise [flat].
ui.Color underShader(ui.Color flat, ui.Shader? shader) =>
    shader == null ? flat : const ui.Color(0xFF000000);

/// colouredByValue is whether a type takes its colours from the values rather
/// than from the series they are in.
bool colouredByValue(ChartType type) =>
    type == ChartType.pie ||
    type == ChartType.donut ||
    type == ChartType.waffle ||
    type == ChartType.radialBar ||
    (type.isInfographic &&
        // Coloured by their series -- the parts, the groups, the lines --
        // so their key names those.
        type != ChartType.marimekko &&
        type != ChartType.boxPlot &&
        type != ChartType.bump);

/// formatTick prints a value in the chart's number style (ChartNumbers).
String formatTick(ChartElement e, double v) => e.numbers.format(v);

/// formatSeries prints a value belonging to series [s], which may write its
/// numbers differently from the rest of the chart.
///
/// Falls back to the chart's style. See ChartSeries.numbers.
String formatSeries(ChartElement e, int s, double v) {
  var series = s >= 0 && s < e.data.series.length ? e.data.series[s] : null;
  // Whole numbers stay whole part-way between two dates, as a chart's
  // words do (ChartData.whole; found making the Charts canvas: a bar race
  // wrote 6.4 points).
  // And while counting up as it arrives, for a series of whole numbers.
  var whole = s >= 0 && s < e.data.whole.length
      ? e.data.whole[s]
      : series != null &&
          series.values.isNotEmpty &&
          series.values.every((x) => x.isNaN || x == x.roundToDouble());
  return (series?.numbers ?? e.numbers).format(whole ? v.roundToDouble() : v);
}

/// formatAxis prints a value-axis figure, in ChartElement.axisFigures (the
/// chart's number style unless the axis has its own).
String formatAxis(ChartElement e, double v) => e.axisFigures.format(v);

/// waffleCells shares a hundred squares out among [values] by how big each
/// is against their total -- the largest remainders taking what rounding
/// down leaves -- as how many squares each has, in order.
List<int> waffleCells(List<double> values, {int cells = 100}) {
  var total = values.fold<double>(0, (t, v) => t + v.abs());
  if (total <= 0) return [for (var _ in values) 0];
  var exact = [for (var v in values) v.abs() / total * cells];
  var whole = [for (var x in exact) x.floor()];
  var left = cells - whole.fold<int>(0, (t, n) => t + n);
  var order = [for (var i = 0; i < values.length; i++) i]
    ..sort((a, b) => (exact[b] - whole[b]).compareTo(exact[a] - whole[a]));
  for (var i = 0; i < left && i < order.length; i++) {
    whole[order[i]]++;
  }
  return whole;
}

/// ChartPartKind is a part of a drawn chart, for the Data Studio's Charts
/// tab to point at: the writing over it, its plot, the labels along each
/// side, and each mark (a bar, a point, a slice).
enum ChartPartKind {
  title,
  description,
  legend,
  plot,
  xLabels,
  yLabels,
  mark,
  note
}

/// ChartPart is where one part was drawn, in the painter's own coordinates.
/// A mark has its series and category; a slice its outline.
class ChartPart {
  final ChartPartKind kind;
  final Rect rect;
  final int series, index;
  final Path? path;
  const ChartPart(this.kind, this.rect,
      {this.series = -1, this.index = -1, this.path});

  bool contains(Offset p) => path?.contains(p) ?? rect.contains(p);
}

/// chartParts collects where things are drawn while it is set: the Charts
/// tab sets it around one paintChart and reads it back. Null otherwise, so
/// the canvas pays nothing.
List<ChartPart>? chartParts;

/// notePart writes one part down, when parts are being collected.
void notePart(ChartPartKind kind, Rect rect,
    {int series = -1, int index = -1, Path? path}) {
  chartParts
      ?.add(ChartPart(kind, rect, series: series, index: index, path: path));
}
