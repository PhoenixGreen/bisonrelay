import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:flutter/foundation.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/painting.dart';

// chart_cartesian.dart draws every chart type that has an x and a y axis:
// bars, grouped and stacked bars, horizontal bars, lines, areas and scatter.
//
// The value axis ends on round numbers (see _niceRange). The plot rectangle
// is what is left once the axis titles, tick labels and category names have
// taken the room they measure, never a guessed margin.

/// _ValueRange is the axis and its ticks, worked out together.
class _ValueRange {
  final double min;
  final double max;
  final List<double> ticks;

  /// log is whether the axis is spaced by decades. See [_logRange].
  final bool log;

  const _ValueRange(this.min, this.max, this.ticks, {this.log = false});

  double get span => max - min == 0 ? 1 : max - min;

  /// fraction is where [v] sits along the axis, 0 at the bottom.
  ///
  /// On a log axis zero and below sit at the bottom rather than at minus
  /// infinity: a bar's base is asked for as fraction(0) whatever the data.
  double fraction(double v) {
    if (!log) return (v - min) / span;
    if (v <= 0 || min <= 0 || max <= min) return 0;
    return (math.log(v) - math.log(min)) / (math.log(max) - math.log(min));
  }
}

/// acrossRange is a scatter's numbers across, where every category is a
/// number: a true x-y plot, its points placed by them on an axis of its own
/// (Ken, 2026-11-14: across was only the place in the list). Null for any
/// other chart, or where a category is not a number.
_ValueRange? _acrossRangeOf(ChartElement e) {
  if (e.type != ChartType.scatter) return null;
  var xs = acrossValuesOf(e);
  if (xs == null) return null;
  var lo = xs.reduce(math.min), hi = xs.reduce(math.max);
  if (hi <= lo) return null;
  var step = _stepFor(lo, hi, 6);
  var start = (lo / step).floor() * step, end = (hi / step).ceil() * step;
  return _ValueRange(start, end, [
    for (var t = start; t <= end + step * 1e-6; t += step)
      double.parse(t.toStringAsFixed(10)),
  ]);
}

/// acrossValuesOf is each category read as a number, or null where any is
/// not or there are under two.
List<double>? acrossValuesOf(ChartElement e) {
  var cats = e.data.categories;
  if (cats.length < 2) return null;
  var out = <double>[];
  for (var c in cats) {
    var v = double.tryParse(c.replaceAll(",", "").trim());
    if (v == null || !v.isFinite) return null;
    out.add(v);
  }
  return out;
}

/// _plain writes a number across as briefly as it reads: 5, not 5.0.
String _plain(double v) {
  if (v == v.roundToDouble()) return v.round().toString();
  return v.toStringAsFixed(2).replaceFirst(RegExp(r"\.?0+$"), "");
}

/// _stepFor is the roundest step that rules [lo]..[hi] into about [want]
/// lines.
///
/// Searched rather than rounded: rounding to 1, 2, 2.5 or 5 lands on readable
/// numbers but ignores the count asked for. This tries every round step near
/// the right size and keeps the one closest to the count.
double _stepFor(double lo, double hi, int want) {
  var span = hi - lo;
  if (span <= 0 || !span.isFinite) return 1;
  var lines = want.clamp(2, 40);
  var mag =
      math.pow(10, (math.log(span / lines) / math.ln10).floor()).toDouble();

  // More multiples than _niceRange's walk: 3, 4 and 6 read well too, and
  // without them there is nothing between 2.5 and 5.
  const nice = [1.0, 1.25, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0];
  double? best;
  var bestScore = double.infinity;
  for (var scale in [mag / 10, mag, mag * 10]) {
    for (var m in nice) {
      var step = m * scale;
      if (step <= 0 || !step.isFinite) continue;
      var min = (lo / step).floor() * step;
      var max = (hi / step).ceil() * step;
      var count = ((max - min) / step).round() + 1;
      if (count < 2 || count > 200) continue;
      // A big step can hit a small count by running the axis far past the
      // data, so the wasted room is weighted to beat nearness to the count.
      var waste = (max - min) / span - 1;
      var score = (count - lines).abs() + math.max(0.0, waste) * 6;
      // A tie goes to the finer step: one line too many beats one too few.
      if (score < bestScore ||
          (score == bestScore && step < (best ?? double.infinity))) {
        best = step;
        bestScore = score;
      }
    }
  }
  return best ?? span / lines;
}

/// _logRange picks an axis by decades: 1, 10, 100, 1000.
///
/// The ends are pushed out to whole powers of ten. A range of two decades or
/// fewer is also ruled at 2 and 5 of each.
_ValueRange _logRange(double lo, double hi, {int want = 0}) {
  if (!lo.isFinite || !hi.isFinite || lo <= 0 || hi <= 0) {
    return _niceRange(lo, hi);
  }
  var low = math.pow(10, (math.log(lo) / math.ln10).floor()).toDouble();
  var high = math.pow(10, (math.log(hi) / math.ln10).ceil()).toDouble();
  if (high <= low) high = low * 10;

  var decades = (math.log(high / low) / math.ln10).round();
  var ticks = <double>[];
  // Every decade up to six, then every second, then every fifth. Asked for a
  // number of divisions ([want] > 0), every so many decades is the nearest a
  // log axis can come.
  var every = want > 0
      ? math.max(1, (decades / math.max(1, want)).round())
      : (decades <= 6 ? 1 : (decades <= 12 ? 2 : 5));
  for (var i = 0; i <= decades; i++) {
    if (i % every != 0 && i != decades) continue;
    var at = low * math.pow(10, i);
    if (decades <= 2) {
      // Without these a single decade has a line at each end and none between.
      for (var m in const [1, 2, 5]) {
        var v = at * m;
        if (v <= high) ticks.add(v.toDouble());
      }
    } else {
      ticks.add(at.toDouble());
    }
  }
  if (!ticks.contains(high)) ticks.add(high);
  return _ValueRange(low, high, ticks, log: true);
}

/// axisTicksForTest is the numbers a chart's value-axis gridlines are drawn
/// at. A test seam, like legendEntriesForTest.
@visibleForTesting
List<double> axisTicksForTest(double lo, double hi,
        {int want = 0, bool log = false, bool fromZero = true}) =>
    (log
            ? _logRange(lo, hi, want: want)
            : _niceRange(lo, hi, fromZero: fromZero, want: want))
        .ticks;

/// _niceRange picks an axis that ends on round numbers.
///
/// The standard "nice numbers" walk: round the rough step up to 1, 2, 2.5 or
/// 5 times a power of ten, then push the ends out to multiples of it.
///
/// [fromZero] is for types read as lengths (bars); a candlestick chart is read
/// as positions and must not be dragged down to zero.
_ValueRange _niceRange(double lo, double hi,
    {int target = 5, int want = 0, bool fromZero = true}) {
  if (!lo.isFinite || !hi.isFinite || lo == hi) {
    var base = lo.isFinite ? lo : 0.0;
    lo = fromZero ? math.min(0, base) : base * 0.9;
    hi = base == 0 ? 1 : base * 1.2;
  }
  if (fromZero) {
    if (lo > 0) lo = 0; // Bars must start from zero or they lie about ratios.
    if (hi < 0) hi = 0;
  } else if (hi > lo) {
    // A tenth of the range as air above and below the highest and lowest
    // wicks.
    var air = (hi - lo) * 0.1;
    lo -= air;
    hi += air;
  }

  var rough = (hi - lo) / target;
  var mag = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
  var norm = rough / mag;
  var step = (norm <= 1
          ? 1
          : norm <= 2
              ? 2
              : norm <= 2.5
                  ? 2.5
                  : norm <= 5
                      ? 5
                      : 10) *
      mag;

  // The walk is too coarse to hit a requested count (over 0..100, five to
  // nine lines all come out as six), so a request searches. See _stepFor.
  if (want > 0) step = _stepFor(lo, hi, want);

  var min = (lo / step).floor() * step;
  var max = (hi / step).ceil() * step;
  // Counted rather than stepped: a step too small to change a large value
  // would never reach the top.
  var count = (max - min) / step;
  if (!count.isFinite || count > 1000) return _ValueRange(lo, hi, [lo, hi]);
  var ticks = <double>[];
  for (var i = 0; i <= count.round(); i++) {
    var v = min + i * step;
    ticks.add(v.abs() < step * 1e-9 ? 0 : v);
  }
  return _ValueRange(min, max, ticks);
}

/// paintCartesian draws every type that has an x and a y axis.
void paintCartesian(ui.Canvas canvas, Rect area, ChartElement e, double reveal,
    [List<double>? seriesReveal]) {
  var data = e.data;
  var horizontal = e.type == ChartType.horizontalBar;

  // The range covers every visible series, or their running totals when
  // stacked. It is seeded with zero only for types read as lengths; candles
  // and log axes take their bottom from the data.
  var fromZero = e.type.startsAtZero && !e.logs;
  var lo = fromZero ? 0.0 : double.infinity;
  var hi = fromZero ? 0.0 : double.negativeInfinity;
  if (e.type.isStacked) {
    for (var i = 0; i < data.categories.length; i++) {
      var pos = 0.0, neg = 0.0;
      for (var s = 0; s < data.series.length; s++) {
        if (data.series[s].hidden) continue;
        var v = data.valueAt(s, i);
        if (v.isNaN) continue; // A gap adds nothing.
        v >= 0 ? pos += v : neg += v;
      }
      hi = math.max(hi, pos);
      lo = math.min(lo, neg);
    }
  } else {
    for (var s in data.series) {
      // A hidden series does not size the axis, so hiding a large one shows
      // the small ones.
      if (s.hidden) continue;
      for (var v in s.values) {
        // A zero would make _logRange fall back to linear. Zeros are still
        // drawn, on the floor (see _ValueRange.fraction).
        if (e.logs && v <= 0) continue;
        if (v.isNaN) continue; // An empty cell.
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
  }
  if (!e.yMin.isNaN) lo = e.yMin;
  if (!e.yMax.isNaN) hi = e.yMax;
  var range = e.logs
      ? _logRange(lo, hi, want: e.axisSteps)
      : _niceRange(lo, hi, fromZero: fromZero, want: e.axisSteps);
  if (!e.yMin.isNaN || !e.yMax.isNaN) {
    range = _ValueRange(e.yMin.isNaN ? range.min : e.yMin,
        e.yMax.isNaN ? range.max : e.yMax, range.ticks,
        log: range.log);
  }

  // On horizontal bars the categories run up the side and the values along
  // the bottom. The label switches and type belong to the axis, so "X labels"
  // means whatever is written along the bottom either way.
  var sideSpec = e.yLabels, bottomSpec = e.xLabels;
  var sideOn = e.showYLabels, bottomOn = e.showXLabels;

  // The value labels' gutter is as wide as the widest of them.
  var valueGutter = 0.0;
  var valueSide = horizontal ? bottomOn : sideOn;
  var valueSpec = horizontal ? bottomSpec : sideSpec;
  if (valueSide && !horizontal) {
    for (var t in range.ticks) {
      var p = layoutText(formatAxis(e, t), valueSpec, maxWidth: area.width / 3);
      valueGutter = math.max(valueGutter, p.width);
    }
    valueGutter =
        math.max(0, valueGutter + valueSpec.fontSize * 0.5 + e.yLabelGap);
  }

  // No labels, no gutter: room kept for switched-off labels pushes the chart
  // off centre. The user's label gaps widen or narrow each gutter, never
  // below nothing.
  var categoryGutter =
      bottomOn ? math.max(0.0, bottomSpec.fontSize * 1.6 + e.xLabelGap) : 0.0;
  // An axis title sits 1.5 times its height from the plot, plus axisGap.
  var axisSpec = e.axisText;
  var axisTitleGutter = axisSpec.fontSize * 1.5 + math.max(0, e.axisGap);

  var left = area.left +
      (horizontal
          ? (sideOn
              ? math.max(
                  0.0,
                  _widestCategory(data.categories, sideSpec, area) +
                      e.yLabelGap)
              : 0.0)
          : valueGutter) +
      (e.showsYTitle ? axisTitleGutter : 0);
  // Room follows the title's switch, not whether a title has been typed.
  var bottom =
      area.bottom - categoryGutter - (e.showsXTitle ? axisTitleGutter : 0);

  // Air over the top label and past the last one so the edge does not cut
  // them, kept only while that axis has labels: otherwise the chart fills
  // the box it is aligned and snapped by.
  var topAir = sideOn ? sideSpec.fontSize : 0.0;
  var rightAir = bottomOn ? bottomSpec.fontSize : 0.0;
  var plot = Rect.fromLTRB(
      left, area.top + topAir * 0.6, area.right - rightAir * 0.5, bottom);
  if (plot.width <= 4 || plot.height <= 4) return;

  _grid(canvas, plot, range, e, horizontal);
  if (e.showAxisLabels) {
    _axisLabels(canvas, area, plot, range, e, horizontal, valueGutter,
        categoryGutter, axisTitleGutter);
  }

  // Split by how each series is drawn, so bars can have a line over them. A
  // series with no type of its own is drawn as the chart's type.
  var bars = <int>[];
  var lines = <int>[];
  var plainBarTaken = false;
  for (var i = 0; i < data.series.length; i++) {
    var series = data.series[i];
    // Hidden from the key: it keeps its key entry, so it can be shown again.
    if (series.hidden) continue;
    var kind = series.typeIn(e.type);
    if (kind.isBar) {
      // "Bars" draws one bar per category (the first untyped series); that is
      // what separates it from "Grouped bars". A series with its own type is
      // always drawn.
      if (e.type == ChartType.bar && series.type == null) {
        if (plainBarTaken) continue;
        plainBarTaken = true;
      }
      bars.add(i);
    } else if (kind.isLinear) {
      lines.add(i);
    }
  }

  // Bars, then candles, then lines, so lines are never hidden under them.
  if (bars.isNotEmpty) {
    _bars(canvas, plot, range, e, horizontal, bars, reveal, seriesReveal);
  }
  if (e.type.isCandles) _candles(canvas, plot, range, e, reveal);
  if (lines.isNotEmpty) {
    _lines(canvas, plot, range, e, lines, reveal, seriesReveal);
  }
}

double _widestCategory(List<String> categories, TextSpec spec, Rect area) {
  var w = 0.0;
  for (var c in categories) {
    w = math.max(w, layoutText(c, spec, maxWidth: area.width / 3).width);
  }
  return w + spec.fontSize * 0.5;
}

/// _grid is the ruled matrix behind the plot, plus the two axis lines.
void _grid(ui.Canvas canvas, Rect plot, _ValueRange range, ChartElement e,
    bool horizontal) {
  if (e.showGrid) {
    var paint = Paint()
      ..color = e.gridColor
      ..strokeWidth = 1;
    for (var t in range.ticks) {
      var f = range.fraction(t);
      if (horizontal) {
        var x = plot.left + plot.width * f;
        canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), paint);
      } else {
        var y = plot.bottom - plot.height * f;
        canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), paint);
      }
    }
    // A scatter by numbers has lines across too.
    if (_acrossRangeOf(e) case var across? when !horizontal) {
      for (var t in across.ticks) {
        var x = plot.left + plot.width * across.fraction(t);
        canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), paint);
      }
    }
  }
  if (e.showAxes) {
    var paint = Paint()
      ..color = e.axisColor
      ..strokeWidth = math.max(1, e.strokeWidth * 0.4);
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, paint);
    canvas.drawLine(plot.topLeft, plot.bottomLeft, paint);
  }
}

/// _axisLabels writes the tick values, the category names and the two axis
/// titles.
void _axisLabels(
  ui.Canvas canvas,
  Rect area,
  Rect plot,
  _ValueRange range,
  ChartElement e,
  bool horizontal,
  double valueGutter,
  double categoryGutter,
  double axisTitleGutter,
) {
  // Ticks go on the value axis and names on the other, each in its axis' type.
  var tickSpec = horizontal ? e.xLabels : e.yLabels;
  var nameSpec = horizontal ? e.yLabels : e.xLabels;
  var showTicks = horizontal ? e.showXLabels : e.showYLabels;
  var showNames = horizontal ? e.showYLabels : e.showXLabels;
  var categories = e.data.categories;

  var spec = tickSpec;
  for (var t in showTicks ? range.ticks : const <double>[]) {
    var f = range.fraction(t);
    var text = formatAxis(e, t);
    if (horizontal) {
      var x = plot.left + plot.width * f;
      paintTextInBox(
          canvas,
          text,
          spec.copyWith(
              align: TextAlignSpec.center,
              verticalAlign: VerticalAlignSpec.top),
          Rect.fromLTWH(
              x - spec.fontSize * 2,
              plot.bottom + spec.fontSize * 0.3 + e.xLabelGap,
              spec.fontSize * 4,
              spec.fontSize * 1.6));
    } else {
      var y = plot.bottom - plot.height * f;
      paintTextInBox(
          canvas,
          text,
          spec.copyWith(
              align: TextAlignSpec.right,
              verticalAlign: VerticalAlignSpec.middle),
          Rect.fromLTRB(
              plot.left - valueGutter,
              y - spec.fontSize,
              plot.left - spec.fontSize * 0.4 - e.yLabelGap,
              y + spec.fontSize));
    }
  }

  spec = nameSpec;
  // A scatter by numbers: its across axis's own marks, not a name a slot.
  var across = horizontal ? null : _acrossRangeOf(e);
  if (across != null && showNames) {
    for (var t in across.ticks) {
      var x = plot.left + plot.width * across.fraction(t);
      paintTextInBox(
          canvas,
          _plain(t),
          spec.copyWith(
              align: TextAlignSpec.center,
              verticalAlign: VerticalAlignSpec.top),
          Rect.fromLTWH(
              x - spec.fontSize * 3,
              plot.bottom + spec.fontSize * 0.35 + e.xLabelGap,
              spec.fontSize * 6,
              spec.fontSize * 1.6));
    }
  }
  var slots = showNames && across == null ? categories.length : 0;
  for (var i = 0; i < slots; i++) {
    if (horizontal) {
      var slot = plot.height / slots;
      var y = plot.top + slot * i;
      paintTextInBox(
          canvas,
          categories[i],
          spec.copyWith(
              align: TextAlignSpec.right,
              verticalAlign: VerticalAlignSpec.middle),
          Rect.fromLTRB(area.left, y,
              plot.left - spec.fontSize * 0.4 - e.yLabelGap, y + slot),
          clip: true);
    } else {
      var slot = plot.width / slots;
      var x = plot.left + slot * i;
      paintTextInBox(
          canvas,
          categories[i],
          spec.copyWith(
              align: TextAlignSpec.center,
              verticalAlign: VerticalAlignSpec.top),
          Rect.fromLTWH(x, plot.bottom + spec.fontSize * 0.35 + e.xLabelGap,
              slot, spec.fontSize * 1.6),
          clip: true);
    }
  }

  // Titles have their own type (ChartElement.axisText), separate from the
  // tick labels.
  var titleSpec = e.axisText;
  if (e.showsXTitle) {
    paintTextInBox(
        canvas,
        e.xAxisLabel,
        titleSpec.copyWith(
            align: TextAlignSpec.center,
            verticalAlign: VerticalAlignSpec.bottom,
            weight: 600),
        Rect.fromLTRB(
            plot.left, area.bottom - axisTitleGutter, plot.right, area.bottom));
  }
  if (e.showsYTitle) {
    // Turned on its side against the axis.
    canvas.save();
    canvas.translate(area.left + axisTitleGutter * 0.5, plot.center.dy);
    canvas.rotate(-math.pi / 2);
    paintTextInBox(
        canvas,
        e.yAxisLabel,
        titleSpec.copyWith(
            align: TextAlignSpec.center,
            verticalAlign: VerticalAlignSpec.middle,
            weight: 600),
        Rect.fromCenter(
            center: Offset.zero, width: plot.height, height: axisTitleGutter));
    canvas.restore();
  }
}

/// _candles draws the open, high, low and close of each period as one mark.
///
/// A wick from low to high and a body from open to close, coloured by whether
/// the period closed up or down. The four numbers come from four series (see
/// ChartData.ohlcAt). A body of no height is drawn as a line, not nothing.
void _candles(ui.Canvas canvas, Rect plot, _ValueRange range, ChartElement e,
    double reveal) {
  var slots = e.data.categories.length;
  if (slots == 0 || e.data.series.length < 4) return;

  var slotSize = plot.width / slots;
  var bodyWidth = math.max(1.0, slotSize * (1 - e.barGap.clamp(0.0, 0.9)));
  // A fraction of the body, so hundreds of candles do not merge into wicks.
  var wickWidth = math.max(1.0, math.min(bodyWidth * 0.18, e.strokeWidth));

  double y(double v) => plot.bottom - plot.height * range.fraction(v);

  for (var i = 0; i < slots; i++) {
    var ohlc = e.data.ohlcAt(i);
    if (ohlc == null) continue;

    var centre = plot.left + slotSize * (i + 0.5);
    var colour = ohlc.rose ? e.riseColor : e.fallColor;

    var arrived = 1.0;
    if (e.animation.on && reveal < 1) {
      var p = e.animation.progressAt(reveal, i, slots);
      if (p <= 0) continue;
      switch (e.animation.preset) {
        case ChartAnimationPreset.fadeIn:
          colour = colour.withValues(alpha: colour.a * p.clamp(0.0, 1.0));
        case ChartAnimationPreset.grow:
        case ChartAnimationPreset.popIn:
        case ChartAnimationPreset.random:
        case ChartAnimationPreset.drawOn:
          // About its own middle: grown from the axis it would pass through
          // prices the period never traded at.
          arrived = p.clamp(0.0, 1.0);
        case ChartAnimationPreset.none:
        case ChartAnimationPreset.wipe:
        case ChartAnimationPreset.sweep:
          break;
      }
    }

    var paint = Paint()..color = colour;
    var top = y(ohlc.top);
    var bottom = y(ohlc.bottom);
    var middle = (top + bottom) / 2;

    var wickTop = y(ohlc.high);
    var wickBottom = y(ohlc.low);
    if (arrived < 1) {
      var wickMiddle = (wickTop + wickBottom) / 2;
      wickTop = wickMiddle + (wickTop - wickMiddle) * arrived;
      wickBottom = wickMiddle + (wickBottom - wickMiddle) * arrived;
      top = middle + (top - middle) * arrived;
      bottom = middle + (bottom - middle) * arrived;
    }

    canvas.drawRect(
        Rect.fromLTRB(centre - wickWidth / 2, wickTop, centre + wickWidth / 2,
            wickBottom),
        paint);

    var body = Rect.fromLTRB(centre - bodyWidth / 2, top,
        centre + bodyWidth / 2, math.max(bottom, top + wickWidth));
    var r = math.min(e.barRadius, math.min(body.width, body.height) / 2);
    canvas.drawRRect(
        RRect.fromRectAndRadius(body, Radius.circular(math.max(0, r))), paint);

    if (e.showValues) {
      // Only the close is written.
      paintTextInBox(
          canvas,
          formatSeries(e, 0, ohlc.close),
          e.valueSpec.copyWith(
              align: TextAlignSpec.center,
              verticalAlign: VerticalAlignSpec.bottom),
          Rect.fromLTWH(
              centre - slotSize / 2,
              wickTop - e.valueSpec.fontSize * 1.5,
              slotSize,
              e.valueSpec.fontSize * 1.4));
    }
  }
}

/// _bars draws the bar types, for the series in [which].
///
/// [which] are the bar series (see paintCartesian). Two or more share a slot
/// side by side, unless the chart is a stacked type.
void _bars(ui.Canvas canvas, Rect plot, _ValueRange range, ChartElement e,
    bool horizontal, List<int> which, double reveal,
    [List<double>? seriesReveal]) {
  var data = e.data;
  var slots = data.categories.length;
  if (slots == 0 || which.isEmpty) return;

  var stacked = e.type.isStacked && which.length > 1;
  var grouped = !stacked && which.length > 1;
  var seriesCount = grouped ? which.length : 1;

  var slotSize = (horizontal ? plot.height : plot.width) / slots;
  var barSpan = slotSize * (1 - e.barGap.clamp(0.0, 0.9));
  var barSize = barSpan / seriesCount;
  var zero = range.fraction(0).clamp(0.0, 1.0);

  // Every backdrop first, so one wider than its bar sits under its
  // neighbour. Backdrops are drawn whole; only the bars animate.
  for (var at = 0; at < which.length; at++) {
    var back = data.series[which[at]].backdrop;
    if (back == null || !back.on) continue;
    var thick = grouped ? barSize : barSpan;
    var across = thick * back.width;
    var lead = switch (back.grow) {
      ChartBackdropGrow.left => 0.0,
      ChartBackdropGrow.right => thick - across,
      _ => (thick - across) / 2,
    };
    // Along the bars: from the axis, the far edge or the middle, as a share
    // of the plot's length.
    var length = horizontal ? plot.width : plot.height;
    var long = length * back.height;
    var from = switch (back.grow) {
      ChartBackdropGrow.top => length - long,
      ChartBackdropGrow.centre => (length - long) / 2,
      _ => 0.0,
    };
    var fill = Paint()..color = back.fill;
    var edge = back.borderWidth > 0 && back.border.a > 0
        ? (Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = back.borderWidth
          ..color = back.border)
        : null;
    for (var i = 0; i < slots; i++) {
      var start = (horizontal ? plot.top : plot.left) +
          slotSize * i +
          (slotSize - barSpan) / 2 +
          (grouped ? barSize * at : 0) +
          lead;
      var panel = horizontal
          ? Rect.fromLTWH(plot.left + from, start, long, across)
          : Rect.fromLTWH(start, plot.bottom - from - long, across, long);
      var r = math.min(back.radius, math.min(panel.width, panel.height) / 2);
      var shape =
          RRect.fromRectAndRadius(panel, Radius.circular(math.max(0, r)));
      canvas.drawRRect(shape, fill);
      if (edge != null) {
        // Inside the panel, so a thick border does not make it bigger.
        var inner = shape.deflate(back.borderWidth / 2);
        if (inner.width > 0 && inner.height > 0) canvas.drawRRect(inner, edge);
      }
    }
  }

  // Values are written after every bar is drawn, so a stack's next part
  // does not cover the one before's (Ken, 2026-11-14: the Charts canvas).
  var labels = <(String, Rect, TextAlignSpec, Color?)>[];
  var fs = e.valueSpec.fontSize;
  for (var i = 0; i < slots; i++) {
    var slotStart = (horizontal ? plot.top : plot.left) + slotSize * i;
    var inset = (slotSize - barSpan) / 2;

    var stackPos = 0.0, stackNeg = 0.0;
    // The stack's ends as drawn, for its totals.
    Rect? posEnd, negEnd;
    var posTotal = 0.0, negTotal = 0.0, stackArrived = 1.0;
    for (var at = 0; at < which.length; at++) {
      var s = which[at];
      var series = data.series[s];
      var v = data.valueAt(s, i);
      // No bar where there is no reading: an empty cell is not a zero.
      if (v.isNaN) continue;

      double from, to;
      if (stacked) {
        var base = v >= 0 ? stackPos : stackNeg;
        from = range.fraction(base);
        to = range.fraction(base + v);
        v >= 0 ? stackPos += v : stackNeg += v;
      } else {
        from = zero;
        to = range.fraction(v);
      }

      var lo = math.min(from, to), hi = math.max(from, to);
      // barFloor gives a zero reading a visible mark, so it differs from an
      // empty cell. It grows the way the bar would, so negatives push down.
      if (e.barFloor > 0) {
        var span = horizontal ? plot.width : plot.height;
        var least = span <= 0 ? 0.0 : e.barFloor / span;
        if (hi - lo < least) {
          if (to < from) {
            lo = hi - least;
          } else {
            hi = lo + least;
          }
        }
      }

      Rect bar;
      if (horizontal) {
        var y = slotStart + inset + (grouped ? barSize * at : 0);
        bar = Rect.fromLTWH(plot.left + plot.width * lo, y,
            plot.width * (hi - lo), grouped ? barSize : barSpan);
      } else {
        var x = slotStart + inset + (grouped ? barSize * at : 0);
        bar = Rect.fromLTWH(x, plot.bottom - plot.height * hi,
            grouped ? barSize : barSpan, plot.height * (hi - lo));
      }

      // A bar with its own colour (see barsTakeColours) is drawn flat: the
      // series' gradient is a ramp of the series' colour.
      var ownColour = barsTakeColours(e) && i < e.sliceColors.length;
      var colour = ownColour ? barColour(e, i) : series.color;
      var arrived = 1.0;
      if (e.animation.on && (reveal < 1 || seriesReveal != null)) {
        // Staggered by category, so grouped bars arrive together. The
        // series' own reveal allows for ChartSeries.delay.
        var p = e.animation
            .progressAt(_revealOf(seriesReveal, s, reveal), i, slots);
        if (p <= 0) continue;
        switch (e.animation.preset) {
          case ChartAnimationPreset.fadeIn:
            colour = colour.withValues(alpha: colour.a * p.clamp(0.0, 1.0));
          case ChartAnimationPreset.popIn:
          case ChartAnimationPreset.random:
            arrived = p;
            // About its own centre, not from the axis.
            bar = Rect.fromCenter(
                center: bar.center,
                width: bar.width * p,
                height: bar.height * p);
          case ChartAnimationPreset.grow:
          case ChartAnimationPreset.drawOn:
            arrived = p;
            // Out of the axis -- its own base, which for a negative bar is
            // its far edge -- and an overshooting ease passes the true
            // length.
            var down = to < from;
            bar = horizontal
                ? (down
                    ? Rect.fromLTWH(bar.right - bar.width * p, bar.top,
                        bar.width * p, bar.height)
                    : Rect.fromLTWH(
                        bar.left, bar.top, bar.width * p, bar.height))
                : (down
                    ? Rect.fromLTWH(
                        bar.left, bar.top, bar.width, bar.height * p)
                    : Rect.fromLTWH(bar.left, bar.bottom - bar.height * p,
                        bar.width, bar.height * p));
          case ChartAnimationPreset.none:
          case ChartAnimationPreset.wipe:
          case ChartAnimationPreset.sweep:
            break;
        }
      }

      // An estimated figure is drawn faint.
      if (data.isEstimated(i)) {
        colour = colour.withValues(alpha: colour.a * estimatedFade);
      }

      var r = math.min(
          series.cornerOn(e.barRadius), math.min(bar.width, bar.height) / 2);
      // The series gradient runs across each bar, not across the plot.
      var barShader = ownColour
          ? null
          : seriesShader(series, bar,
              alpha: series.color.a == 0 ? 1 : colour.a / series.color.a);
      canvas.drawRRect(
          RRect.fromRectAndRadius(bar, Radius.circular(math.max(0, r))),
          Paint()
            // See underShader: the ramp already carries the fade.
            ..color = underShader(colour, barShader)
            ..shader = barShader);

      if (e.showValues && v != 0) {
        // Counts up with the bar, clamped so an overshoot never shows a number
        // larger than the data.
        var label = formatTick(e, v * arrived.clamp(0.0, 1.0));
        if (stacked) {
          // Inside its own part, where it fits, in a colour that reads on
          // it; the stack's total goes past its end (below).
          var room = horizontal ? bar.width : bar.height;
          var need = horizontal ? fs * (label.length * 0.62 + 0.6) : fs * 1.25;
          if (room >= need) {
            labels.add((label, bar, TextAlignSpec.center, _inkOn(colour)));
          }
          if (v >= 0) {
            posEnd = bar;
            posTotal += v;
          } else {
            negEnd = bar;
            negTotal += v;
          }
          stackArrived = arrived.clamp(0.0, 1.0);
        } else {
          labels.add((
            label,
            _pastEnd(bar, horizontal, v < 0, fs),
            _alongEnd(horizontal, v < 0),
            null
          ));
        }
      }
    }
    // A stack's totals, past each end it has.
    if (stacked && e.showValues) {
      for (var (end, total) in [(posEnd, posTotal), (negEnd, negTotal)]) {
        if (end == null || total == 0) continue;
        // One part alone already says it.
        labels.add((
          formatTick(e, total * stackArrived),
          _pastEnd(end, horizontal, total < 0, fs),
          _alongEnd(horizontal, total < 0),
          null
        ));
      }
    }
  }
  for (var (text, box, align, ink) in labels) {
    paintTextInBox(
        canvas,
        text,
        e.valueSpec.copyWith(
            align: align,
            verticalAlign: VerticalAlignSpec.middle,
            color: ink ?? e.valueSpec.color),
        box);
  }
}

/// _pastEnd is where a bar's value goes: past the end it grows to -- above
/// a bar going up, below one going down, right or left of a sideways one.
Rect _pastEnd(Rect bar, bool horizontal, bool negative, double fs) => horizontal
    ? (negative
        ? Rect.fromLTWH(
            bar.left - fs * 0.3 - fs * 5, bar.center.dy - fs, fs * 5, fs * 2)
        : Rect.fromLTWH(
            bar.right + fs * 0.3, bar.center.dy - fs, fs * 5, fs * 2))
    : (negative
        ? Rect.fromLTWH(bar.left, bar.bottom + fs * 0.1, bar.width, fs * 1.4)
        : Rect.fromLTWH(bar.left, bar.top - fs * 1.5, bar.width, fs * 1.4));

/// _alongEnd is how a value past a bar's end is set: away from the bar.
TextAlignSpec _alongEnd(bool horizontal, bool negative) => horizontal
    ? (negative ? TextAlignSpec.right : TextAlignSpec.left)
    : TextAlignSpec.center;

/// _inkOn is black or white, whichever reads on [fill].
Color _inkOn(Color fill) => fill.computeLuminance() > 0.45
    ? const Color(0xFF111111)
    : const Color(0xFFFFFFFF);

/// _lines draws the line, area and scatter types, for the series in [which].
///
/// Each series is drawn by its own type, so one can be an area and the next a
/// scatter.
void _lines(ui.Canvas canvas, Rect plot, _ValueRange range, ChartElement e,
    List<int> which, double reveal,
    [List<double>? seriesReveal]) {
  var data = e.data;
  var n = data.categories.length;
  if (n == 0) return;

  // Points sit mid-slot so lines line up with bars.
  // By its number across, for a scatter by numbers; else mid-slot.
  var across = _acrossRangeOf(e);
  var acrossAt = across == null ? null : acrossValuesOf(e);
  double xAt(int i) => acrossAt != null
      ? plot.left + plot.width * across!.fraction(acrossAt[i])
      : plot.left + plot.width * (n == 1 ? 0.5 : (i + 0.5) / n);
  double yAt(double v) =>
      plot.bottom - plot.height * range.fraction(v).clamp(-0.2, 1.2);

  var animation = e.animation;
  // An offset series is still arriving after the chart's own reveal has
  // reached one, so the gate cannot be the chart's reveal alone.
  var animating = animation.on && (reveal < 1 || seriesReveal != null);

  for (var at = 0; at < which.length; at++) {
    var s = which[at];
    var series = data.series[s];
    var kind = series.typeIn(e.type);
    // An empty cell is a hole in the line. [points] stays full length so
    // indexes match the rows; [present] says which are real.
    var present = [for (var i = 0; i < n; i++) data.hasValueAt(s, i)];
    var points = [
      for (var i = 0; i < n; i++)
        Offset(xAt(i), yAt(present[i] ? data.valueAt(s, i) : 0)),
    ];
    if (points.isEmpty || !present.contains(true)) continue;

    // Lines are staggered by series. The exception is a scatter under a
    // scrambling preset, where each dot is its own item across all series.
    var perPoint = animation.preset.scrambles && kind == ChartType.scatter;
    var mine = _revealOf(seriesReveal, s, reveal);
    var progress = animating && !perPoint
        ? animation.progressAt(mine, at, which.length)
        : 1.0;
    if (animating && !perPoint && progress <= 0) continue;

    // The settled points, before a preset lifts them: a band is drawn between
    // two settled lines, since its other edge is never lifted.
    var seated = points;

    var alpha = 1.0;
    if (animating) {
      switch (animation.preset) {
        case ChartAnimationPreset.fadeIn:
          alpha = progress.clamp(0.0, 1.0);
        case ChartAnimationPreset.grow:
        case ChartAnimationPreset.popIn:
        case ChartAnimationPreset.random:
          // Up out of the baseline, like the bars. A per-point scatter is
          // handled dot by dot below.
          points = [
            for (var point in points)
              Offset(
                  point.dx, plot.bottom - (plot.bottom - point.dy) * progress),
          ];
        case ChartAnimationPreset.drawOn:
        case ChartAnimationPreset.none:
        case ChartAnimationPreset.wipe:
        case ChartAnimationPreset.sweep:
          break;
      }
    }
    var colour = alpha >= 1
        ? series.color
        : series.color.withValues(alpha: series.color.a * alpha);
    var weight = series.widthOn(e.strokeWidth);

    // Runs of consecutive readings, each its own path, so no line crosses a
    // gap. A run of one is only a dot.
    var runs = <List<int>>[];
    for (var i = 0; i < n; i++) {
      if (!present[i]) continue;
      if (runs.isEmpty || i == 0 || !present[i - 1]) runs.add(<int>[]);
      runs.last.add(i);
    }

    if (kind != ChartType.scatter) {
      var smooth = series.smoothOn(e.smooth) && kind.usesSmooth;
      // path is the whole line: the area is closed from it and drawing-on
      // measures along it. The stroke is split into solid and dashed: when
      // the data marks estimates, a stretch touching one is dashed.
      var path = Path();
      var solid = Path();
      var dashed = Path();
      var marks = data.marksEstimates;
      for (var run in runs) {
        if (run.length < 2) continue;
        var pts = [for (var i in run) points[i]];
        path.addPath(_linePath(pts, smooth), Offset.zero);
        for (var k = 0; k < run.length - 1; k++) {
          var soft = marks &&
              (data.isEstimated(run[k]) || data.isEstimated(run[k + 1]));
          (soft ? dashed : solid)
              .addPath(_segmentPath(pts, k, smooth), Offset.zero);
        }
      }
      // Which points have readings, before drawing-on hides the ones not yet
      // reached. The band is built from this, and fades in instead (see
      // _bandFade).
      var whole = [...present];

      var drawnTo = double.infinity;
      if (animating &&
          animation.preset == ChartAnimationPreset.drawOn &&
          progress < 1) {
        // Drawn on from the start: the line is cut at its tip. The styled
        // strokes are one path per stretch, so they are clipped at drawnTo
        // below rather than each trimmed by the fraction.
        path = _trimmed(path, progress);
        drawnTo = _lastX(path);
        // A point not reached yet gets no dot or value.
        for (var i = 0; i < n; i++) {
          if (points[i].dx > drawnTo) present[i] = false;
        }
      }
      var shader = seriesShader(series, plot, alpha: alpha);

      // The band between this line and the next drawn one, shaded from this
      // series' colour to the next's, and drawn under both lines.
      if (series.band) {
        var next = _nextDrawn(data, s);
        var settled = !animating
            ? 1.0
            : _bandFade(
                _revealOf(seriesReveal, s, reveal),
                next < 0 ? 1.0 : _revealOf(seriesReveal, next, reveal),
                e,
                which,
                at,
                next);
        if (next >= 0 && settled > 0) {
          var pair = _bandPath(
            data, next, seated, whole, n, xAt, yAt, double.infinity,
            // Each edge curved as its line is.
            series.smoothOn(e.smooth) && kind.usesSmooth,
            data.series[next].smoothOn(e.smooth) &&
                data.series[next].typeIn(e.type).usesSmooth,
          );
          if (pair != null) {
            var wash = 0.30 * alpha * settled;
            canvas.drawPath(
                pair,
                Paint()
                  ..shader = ui.Gradient.linear(
                      Offset(0, plot.top), Offset(0, plot.bottom), [
                    colour.withValues(alpha: colour.a * wash),
                    data.series[next].color
                        .withValues(alpha: data.series[next].color.a * wash),
                  ]));
          }
        }
      }

      if (kind == ChartType.area) {
        // Closed at the line's tip, not its last reached point, so the fill
        // keeps pace with the line rather than jumping per category.
        var drawn = [
          for (var i = 0; i < n; i++)
            if (present[i]) points[i]
        ];
        if (drawn.isEmpty) drawn = [points.first];
        var tip = _pathEnd(path) ?? drawn.last;
        var fill = Path.from(path)
          ..lineTo(tip.dx, plot.bottom)
          ..lineTo(drawn.first.dx, plot.bottom)
          ..close();
        // The series' gradient, or a fade to nothing.
        canvas.drawPath(
            fill,
            Paint()
              ..shader = shader ??
                  ui.Gradient.linear(
                      Offset(0, plot.top), Offset(0, plot.bottom), [
                    colour.withValues(alpha: 0.45 * alpha),
                    colour.withValues(alpha: 0.02 * alpha),
                  ]));
      }
      var stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = weight
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = underShader(colour, shader)
        // Across the plot, not per segment.
        ..shader = shader;
      // The series' own line style. A dashed or dotted series keeps its
      // pattern over an estimated stretch; faintness alone marks the estimate.
      var pattern = series.lineStyle.pattern;
      if (!marks && pattern == null) {
        canvas.drawPath(path, stroke);
      } else {
        var clipped = drawnTo.isFinite;
        if (clipped) {
          canvas.save();
          // Only the tip edge matters; the others are generous.
          canvas.clipRect(Rect.fromLTRB(plot.left - weight * 2,
              plot.top - plot.height, drawnTo, plot.bottom + plot.height));
        }
        canvas.drawPath(
            pattern == null ? solid : _dashed(solid, weight, pattern), stroke);
        // Estimated stretches: dashed and faint.
        canvas.drawPath(
            _dashed(dashed, weight, pattern ?? estimatedDash),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = weight
              // Round, or a dot (a dash of almost no length) is invisible.
              // See ChartLineStyle.pattern.
              ..strokeCap = pattern == null ? StrokeCap.butt : StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..color = underShader(
                  colour.withValues(alpha: colour.a * estimatedFade * 2),
                  shader)
              ..shader = shader);
        if (clipped) canvas.restore();
      }
    }

    // Dots for a scatter, for written values, and where points are on.
    if (kind == ChartType.scatter ||
        e.showValues ||
        series.pointsOn(e.showPoints)) {
      for (var i = 0; i < points.length; i++) {
        if (!present[i]) continue;
        var dot = perPoint
            ? animation.progressAt(mine, at * n + i, which.length * n)
            : progress;
        if (animating && dot <= 0) continue;

        var swelling = animating &&
            (animation.preset == ChartAnimationPreset.popIn ||
                animation.preset == ChartAnimationPreset.random);
        var size = series.pointSizeOn(e.pointSize);
        // A scatter's dots are what it is: bigger by default than a line's
        // points.
        var radius = size > 0
            ? size
            : kind == ChartType.scatter
                ? math.max(4.5, weight * 2.4)
                : weight * 1.4;
        // The point colour, or the series'. Either takes the line's arrival
        // fade, so dot and line come on together.
        var dotPaint = series.pointColorOn(e.pointColor);
        var dotColour = dotPaint.a > 0
            ? dotPaint.withValues(
                alpha: dotPaint.a *
                    (colour.a / (series.color.a == 0 ? 1 : series.color.a)))
            : colour;
        canvas.drawCircle(
            points[i],
            radius * (swelling ? dot.clamp(0.0, 1.4) : 1),
            Paint()
              ..color = perPoint && dot < 1
                  ? dotColour.withValues(
                      alpha: dotColour.a * dot.clamp(0.0, 1.0))
                  : dotColour);
        if (e.showValues) {
          // Counts up only while the point itself grows; drawn on, a passed
          // point shows its full value.
          var shown = swelling ||
                  (animating &&
                      !perPoint &&
                      animation.preset == ChartAnimationPreset.grow)
              ? dot.clamp(0.0, 1.0)
              : 1.0;
          paintTextInBox(
              canvas,
              formatSeries(e, s, data.valueAt(s, i) * shown),
              e.valueSpec.copyWith(
                  align: TextAlignSpec.center,
                  verticalAlign: VerticalAlignSpec.bottom),
              Rect.fromCenter(
                  center: points[i].translate(0, -e.valueSpec.fontSize * 1.4),
                  width: e.valueSpec.fontSize * 6,
                  height: e.valueSpec.fontSize * 1.6));
        }
      }
    }
  }
}

/// estimatedFade is the share of its alpha a mark keeps where its figure is
/// estimated. See ChartData.isEstimated.
const double estimatedFade = 0.34;

/// estimatedDash is the on-off pattern an estimated stretch of line is drawn
/// with, in multiples of the line's own weight.
const List<double> estimatedDash = [2.2, 1.8];

/// _nextDrawn is the first series after [s] that is not hidden, or -1. A band
/// never ends on a hidden series.
int _nextDrawn(ChartData data, int s) {
  for (var i = s + 1; i < data.series.length; i++) {
    if (!data.series[i].hidden) return i;
  }
  return -1;
}

/// _bandFade is how much of the band between two lines is showing.
///
/// Nought until both edges are three quarters on, then fading in over the
/// rest of the slower one, so it completes with its lines. Faded rather than
/// drawn on because the band is built from whole readings and would step a
/// category at a time.
double _bandFade(double mine, double other, ChartElement e, List<int> which,
    int at, int next) {
  var animation = e.animation;
  var here = animation.progressAt(mine, at, which.length);
  // The other edge may be bars, which are not in this stagger.
  var there = which.indexOf(next);
  var theirs =
      there < 0 ? 1.0 : animation.progressAt(other, there, which.length);
  const from = 0.75;
  var least = math.min(here, theirs);
  return least <= from ? 0 : ((least - from) / (1 - from)).clamp(0.0, 1.0);
}

/// _revealOf is how far through its own arrival series [s] is: its entry in
/// [seriesReveal] when there is one, else the chart's [reveal].
double _revealOf(List<double>? seriesReveal, int s, double reveal) =>
    seriesReveal != null && s < seriesReveal.length ? seriesReveal[s] : reveal;

/// _bandPath is the closed shape between one line and the next.
///
/// Only across runs where both have a reading.
Path? _bandPath(
  ChartData data,
  int other,
  List<Offset> points,
  List<bool> present,
  int n,
  double Function(int) xAt,
  double Function(double) yAt,
  double drawnTo,
  bool topSmooth,
  bool bottomSmooth,
) {
  var path = Path();
  var any = false;
  var run = <int>[];

  void close() {
    if (run.length < 2) {
      run = [];
      return;
    }
    // Both edges through _linePath, so the band follows the curves.
    // extendWithPath joins the top edge's end to the bottom's start.
    var top = _linePath([for (var i in run) points[i]], topSmooth);
    var bottom = _linePath([
      for (var i in run.reversed) Offset(xAt(i), yAt(data.valueAt(other, i)))
    ], bottomSmooth);
    top.extendWithPath(bottom, Offset.zero);
    top.close();
    path.addPath(top, Offset.zero);
    any = true;
    run = [];
  }

  for (var i = 0; i < n; i++) {
    // Both sides, and only as far as the drawing has got.
    if (present[i] && data.hasValueAt(other, i) && points[i].dx <= drawnTo) {
      run.add(i);
      continue;
    }
    close();
  }
  close();
  return any ? path : null;
}

/// _segmentPath is the one stretch from `points[i]` to `points[i + 1]`, drawn
/// exactly as [_linePath] would draw it.
///
/// The same control points, so splitting a smoothed line into solid and
/// dashed stretches does not change its shape.
Path _segmentPath(List<Offset> points, int i, bool smooth) {
  var p1 = points[i], p2 = points[i + 1];
  var path = Path()..moveTo(p1.dx, p1.dy);
  if (!smooth || points.length < 3) {
    path.lineTo(p2.dx, p2.dy);
    return path;
  }
  var p0 = i == 0 ? p1 : points[i - 1];
  var p3 = i + 2 < points.length ? points[i + 2] : p2;
  var c1 = p1 + (p2 - p0) / 6;
  var c2 = p2 - (p3 - p1) / 6;
  path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  return path;
}

/// _dashed is [path] as a run of dashes or dots, or the path itself where the
/// weight makes no sense.
Path _dashed(Path path, double weight, [List<double> pattern = estimatedDash]) {
  if (weight <= 0) return path;
  var on = pattern[0] * weight, off = pattern[1] * weight;
  if (on + off <= 0) return path;
  var out = Path();
  for (var metric in path.computeMetrics()) {
    var at = 0.0;
    while (at < metric.length) {
      out.addPath(metric.extractPath(at, math.min(at + on, metric.length)),
          Offset.zero);
      at += on + off;
    }
  }
  return out;
}

/// _trimmed is the first [fraction] of a path, by length.
Path _trimmed(Path path, double fraction) {
  var out = Path();
  for (var metric in path.computeMetrics()) {
    var want = metric.length * fraction.clamp(0.0, 1.0);
    if (want <= 0) continue;
    out.addPath(metric.extractPath(0, want), Offset.zero);
  }
  return out;
}

/// _lastX is the right edge of the drawn part, which decides which points
/// have arrived.
double _lastX(Path path) => path.getBounds().right;

/// _pathEnd is where a path stops, from its metrics: a smoothed line can
/// overshoot, so the bounding box is not the same.
Offset? _pathEnd(Path path) {
  Offset? out;
  for (var metric in path.computeMetrics()) {
    var tangent = metric.getTangentForOffset(metric.length);
    if (tangent != null) out = tangent.position;
  }
  return out;
}

/// _linePath joins the points, optionally through a Catmull-Rom style smooth.
///
/// The control points are a sixth of the gap between neighbours, which keeps
/// overshoot past a peak small.
Path _linePath(List<Offset> points, bool smooth) {
  var path = Path()..moveTo(points.first.dx, points.first.dy);
  if (!smooth || points.length < 3) {
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    return path;
  }
  for (var i = 0; i < points.length - 1; i++) {
    var p0 = i == 0 ? points[i] : points[i - 1];
    var p1 = points[i];
    var p2 = points[i + 1];
    var p3 = i + 2 < points.length ? points[i + 2] : p2;
    var c1 = p1 + (p2 - p0) / 6;
    var c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path;
}
