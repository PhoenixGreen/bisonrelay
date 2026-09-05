import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/painting.dart';

// chart_cartesian.dart draws every chart type that has an x and a y axis:
// bars, grouped and stacked bars, horizontal bars, lines, areas and scatter.
//
// The part worth reading twice is the value axis. Its range is chosen to end
// on round numbers -- see _niceRange -- because an axis running to 8.3714 is
// not readable at any size, and a chart on a canvas is going to be looked at
// rather than hovered over.
//
// Everything else here is measurement: the plot rectangle is what is left
// once the axis titles, the tick labels and the category names have taken the
// room they actually need, never a guessed margin, so a chart with long
// category names and a chart with none both use the space they have.

/// _ValueRange is the axis and its ticks, worked out together.
class _ValueRange {
  final double min;
  final double max;
  final List<double> ticks;
  const _ValueRange(this.min, this.max, this.ticks);

  double get span => max - min == 0 ? 1 : max - min;

  /// fraction is where [v] sits along the axis, 0 at the bottom.
  double fraction(double v) => (v - min) / span;
}

/// _niceRange picks an axis that ends on round numbers.
///
/// The standard "nice numbers" walk: take the rough step the data implies,
/// round it up to the next 1, 2, 2.5 or 5 times a power of ten, then push the
/// ends of the axis out to multiples of it. The alternative -- running the
/// axis from the smallest value to the largest -- gives labels like 3.7, 5.4,
/// 7.1, which nobody can read a value off.
_ValueRange _niceRange(double lo, double hi, {int target = 5}) {
  if (!lo.isFinite || !hi.isFinite || lo == hi) {
    var base = lo.isFinite ? lo : 0.0;
    lo = math.min(0, base);
    hi = base == 0 ? 1 : base * 1.2;
  }
  if (lo > 0) lo = 0; // Bars must start from zero or they lie about ratios.
  if (hi < 0) hi = 0;

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

  var min = (lo / step).floor() * step;
  var max = (hi / step).ceil() * step;
  var ticks = <double>[];
  for (var v = min; v <= max + step * 0.001; v += step) {
    ticks.add(v.abs() < step * 1e-9 ? 0 : v);
  }
  return _ValueRange(min, max, ticks);
}

/// paintCartesian draws every type that has an x and a y axis.
void paintCartesian(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var data = e.data;
  var horizontal = e.type == ChartType.horizontalBar;

  // The range covers every series, or their running totals when stacked.
  var lo = 0.0, hi = 0.0;
  if (e.type.isStacked) {
    for (var i = 0; i < data.categories.length; i++) {
      var pos = 0.0, neg = 0.0;
      for (var s = 0; s < data.series.length; s++) {
        var v = data.valueAt(s, i);
        v >= 0 ? pos += v : neg += v;
      }
      hi = math.max(hi, pos);
      lo = math.min(lo, neg);
    }
  } else {
    for (var s in data.series) {
      for (var v in s.values) {
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
  }
  if (!e.yMin.isNaN) lo = e.yMin;
  if (!e.yMax.isNaN) hi = e.yMax;
  var range = _niceRange(lo, hi);
  if (!e.yMin.isNaN || !e.yMax.isNaN) {
    range = _ValueRange(e.yMin.isNaN ? range.min : e.yMin,
        e.yMax.isNaN ? range.max : e.yMax, range.ticks);
  }

  // Reserve room by measuring, not by guessing. The value labels decide the
  // left gutter and the category labels decide the bottom one.
  var labelSpec = e.labelSpec;
  var valueGutter = 0.0;
  if (e.showAxisLabels) {
    for (var t in range.ticks) {
      var p = layoutText(formatTick(t), labelSpec, maxWidth: area.width / 3);
      valueGutter = math.max(valueGutter, p.width);
    }
    valueGutter += labelSpec.fontSize * 0.5;
  }

  // No writing, no gutters. Switching the labels off and keeping the room
  // they took would be a chart with a margin of nothing down two sides.
  var categoryGutter = e.showAxisLabels ? labelSpec.fontSize * 1.6 : 0.0;
  var axisTitleGutter = e.showAxisLabels ? labelSpec.fontSize * 1.5 : 0.0;

  var left = area.left +
      (horizontal
          ? _widestCategory(data.categories, labelSpec, area)
          : valueGutter) +
      (e.yAxisLabel.isNotEmpty ? axisTitleGutter : 0);
  var bottom = area.bottom -
      (horizontal ? categoryGutter : categoryGutter) -
      (e.xAxisLabel.isNotEmpty ? axisTitleGutter : 0);
  var plot = Rect.fromLTRB(left, area.top + labelSpec.fontSize * 0.6,
      area.right - labelSpec.fontSize * 0.5, bottom);
  if (plot.width <= 4 || plot.height <= 4) return;

  _grid(canvas, plot, range, e, horizontal);
  if (e.showAxisLabels) {
    _axisLabels(canvas, area, plot, range, e, horizontal, valueGutter,
        categoryGutter, axisTitleGutter);
  }

  // Split by how each series is drawn rather than by what the chart is, so a
  // set of bars can have a line over it. A series with no type of its own is
  // drawn as the chart is, which is every series until somebody says
  // otherwise.
  var bars = <int>[];
  var lines = <int>[];
  var plainBarTaken = false;
  for (var i = 0; i < data.series.length; i++) {
    var series = data.series[i];
    var kind = series.typeIn(e.type);
    if (kind.isBar) {
      // "Bars" means one bar per category, so a chart set to it draws its
      // first series and no more -- that is the whole difference between it
      // and "Grouped bars", and letting it quietly group as well would make
      // choosing between them do nothing.
      //
      // A series with a type of its own is exempt. Asking for bars over a
      // line chart is asking for those bars specifically, not for the chart's
      // idea of how many series it draws.
      if (e.type == ChartType.bar && series.type == null) {
        if (plainBarTaken) continue;
        plainBarTaken = true;
      }
      bars.add(i);
    } else if (kind.isLinear) {
      lines.add(i);
    }
  }

  // Bars first. A line drawn under a bar is a line nobody can see, and the
  // reason for putting the two on one pair of axes is to read the line
  // against the bars.
  if (bars.isNotEmpty) {
    _bars(canvas, plot, range, e, horizontal, bars, reveal);
  }
  if (lines.isNotEmpty) _lines(canvas, plot, range, e, lines, reveal);
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
  var spec = e.labelSpec;
  var categories = e.data.categories;

  for (var t in range.ticks) {
    var f = range.fraction(t);
    var text = formatTick(t);
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
              plot.bottom + spec.fontSize * 0.3,
              spec.fontSize * 4,
              categoryGutter));
    } else {
      var y = plot.bottom - plot.height * f;
      paintTextInBox(
          canvas,
          text,
          spec.copyWith(
              align: TextAlignSpec.right,
              verticalAlign: VerticalAlignSpec.middle),
          Rect.fromLTWH(plot.left - valueGutter, y - spec.fontSize,
              valueGutter - spec.fontSize * 0.4, spec.fontSize * 2));
    }
  }

  var slots = categories.length;
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
          Rect.fromLTWH(
              area.left, y, plot.left - area.left - spec.fontSize * 0.4, slot),
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
          Rect.fromLTWH(
              x, plot.bottom + spec.fontSize * 0.35, slot, categoryGutter),
          clip: true);
    }
  }

  if (e.xAxisLabel.isNotEmpty) {
    paintTextInBox(
        canvas,
        e.xAxisLabel,
        spec.copyWith(
            align: TextAlignSpec.center,
            verticalAlign: VerticalAlignSpec.bottom,
            weight: 600),
        Rect.fromLTRB(
            plot.left, area.bottom - axisTitleGutter, plot.right, area.bottom));
  }
  if (e.yAxisLabel.isNotEmpty) {
    // Turned on its side against the axis, which is where a value-axis title
    // belongs and the only way it fits without eating a third of the plot.
    canvas.save();
    canvas.translate(area.left + axisTitleGutter * 0.5, plot.center.dy);
    canvas.rotate(-math.pi / 2);
    paintTextInBox(
        canvas,
        e.yAxisLabel,
        spec.copyWith(
            align: TextAlignSpec.center,
            verticalAlign: VerticalAlignSpec.middle,
            weight: 600),
        Rect.fromCenter(
            center: Offset.zero, width: plot.height, height: axisTitleGutter));
    canvas.restore();
  }
}

/// _bars draws the bar types, for the series in [which].
///
/// [which] rather than every series, because a chart may be a set of bars with
/// a line over it -- see paintCartesian. It is also what decides whether the bars
/// are side by side: two bar series share a slot however the chart's own type
/// is set, since drawing them on top of each other would hide one of them.
void _bars(ui.Canvas canvas, Rect plot, _ValueRange range, ChartElement e,
    bool horizontal, List<int> which, double reveal) {
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

  for (var i = 0; i < slots; i++) {
    var slotStart = (horizontal ? plot.top : plot.left) + slotSize * i;
    var inset = (slotSize - barSpan) / 2;

    var stackPos = 0.0, stackNeg = 0.0;
    for (var at = 0; at < which.length; at++) {
      var s = which[at];
      var series = data.series[s];
      var v = data.valueAt(s, i);

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

      // Where this bar has got to. Staggered by category rather than by
      // series, which is what "one bar after another, left to right" means --
      // grouped bars in the same slot arrive together, as a group.
      var colour = series.color;
      var arrived = 1.0;
      if (e.animation.on && reveal < 1) {
        var p = e.animation.progressAt(reveal, i, slots);
        if (p <= 0) continue;
        switch (e.animation.preset) {
          case ChartAnimationPreset.fadeIn:
            // Fading, not growing. The number is already its full self and
            // counting it up would say something the bar does not.
            colour = colour.withValues(alpha: colour.a * p.clamp(0.0, 1.0));
          case ChartAnimationPreset.popIn:
          case ChartAnimationPreset.random:
            arrived = p;
            // About its own centre, so it springs where it stands rather than
            // sliding in from the axis.
            bar = Rect.fromCenter(
                center: bar.center,
                width: bar.width * p,
                height: bar.height * p);
          case ChartAnimationPreset.grow:
          case ChartAnimationPreset.drawOn:
            arrived = p;
            // Out of the axis. An overshoot goes past the true height and
            // settles back, which is the whole reason the ease is a setting.
            bar = horizontal
                ? Rect.fromLTWH(bar.left, bar.top, bar.width * p, bar.height)
                : Rect.fromLTWH(bar.left, bar.bottom - bar.height * p,
                    bar.width, bar.height * p);
          case ChartAnimationPreset.none:
          case ChartAnimationPreset.wipe:
          case ChartAnimationPreset.sweep:
            break;
        }
      }

      var r = math.min(e.barRadius, math.min(bar.width, bar.height) / 2);
      canvas.drawRRect(
          RRect.fromRectAndRadius(bar, Radius.circular(math.max(0, r))),
          Paint()..color = colour);

      if (e.showValues && v != 0) {
        // Counting up with the bar. Clamped to the real value even when the
        // curve overshoots: a bar may stand a little proud of its mark for a
        // moment and be read as a flourish, and a number that says 21 where
        // the data says 20 is simply wrong.
        var label = formatTick(v * arrived.clamp(0.0, 1.0));
        var box = horizontal
            ? Rect.fromLTWH(
                bar.right + e.valueSpec.fontSize * 0.3,
                bar.center.dy - e.valueSpec.fontSize,
                e.valueSpec.fontSize * 5,
                e.valueSpec.fontSize * 2)
            : Rect.fromLTWH(bar.left, bar.top - e.valueSpec.fontSize * 1.5,
                bar.width, e.valueSpec.fontSize * 1.4);
        paintTextInBox(
            canvas,
            label,
            e.valueSpec.copyWith(
                align: horizontal ? TextAlignSpec.left : TextAlignSpec.center,
                verticalAlign: VerticalAlignSpec.middle),
            box);
      }
    }
  }
}

/// _lines draws the line, area and scatter types, for the series in [which].
///
/// Each of them by its *own* type rather than by the chart's, so one series
/// can be an area and the next a scatter over the same axes.
void _lines(ui.Canvas canvas, Rect plot, _ValueRange range, ChartElement e,
    List<int> which, double reveal) {
  var data = e.data;
  var n = data.categories.length;
  if (n == 0) return;

  // Points sit in the middle of their slot, not on the axis ends, so a line
  // chart and a bar chart of the same numbers line up with each other.
  double xAt(int i) => plot.left + plot.width * (n == 1 ? 0.5 : (i + 0.5) / n);
  double yAt(double v) =>
      plot.bottom - plot.height * range.fraction(v).clamp(-0.2, 1.2);

  var animation = e.animation;
  var animating = animation.on && reveal < 1;

  for (var at = 0; at < which.length; at++) {
    var s = which[at];
    var series = data.series[s];
    var kind = series.typeIn(e.type);
    var points = [
      for (var i = 0; i < n; i++) Offset(xAt(i), yAt(data.valueAt(s, i))),
    ];
    if (points.isEmpty) continue;

    // A line is staggered by *series*, not by point: the points of one line
    // are one movement, and drawing them in turn is what "draw on" already
    // does along the length of it.
    //
    // A scattered cloud is the exception, and Random is the preset for it:
    // there every dot is its own item and they are counted across the series
    // as well as along them, so two series fill in together rather than one
    // after the other.
    var perPoint = animation.preset.scrambles && kind == ChartType.scatter;
    var progress = animating && !perPoint
        ? animation.progressAt(reveal, at, which.length)
        : 1.0;
    if (animating && !perPoint && progress <= 0) continue;

    var alpha = 1.0;
    if (animating) {
      switch (animation.preset) {
        case ChartAnimationPreset.fadeIn:
          alpha = progress.clamp(0.0, 1.0);
        case ChartAnimationPreset.grow:
        case ChartAnimationPreset.popIn:
        case ChartAnimationPreset.random:
          // Up out of the baseline, so a line arrives the way the bars beside
          // it do. A scattered cloud never gets here -- it is dealt dot by dot
          // below.
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

    if (kind != ChartType.scatter) {
      var path = _linePath(points, e.smooth && kind.usesSmooth);
      // Traced from its start rather than grown from the axis: the line is
      // cut short at the point it has reached, and the area under it with it.
      if (animating &&
          animation.preset == ChartAnimationPreset.drawOn &&
          progress < 1) {
        path = _trimmed(path, progress);
        points = [
          for (var point in points)
            if (point.dx <= _lastX(path)) point,
        ];
        if (points.isEmpty) points = [_firstPoint(path)];
      }
      if (kind == ChartType.area) {
        // Closed at the line's own tip rather than at the last point it has
        // passed. Using the last *data* point left the fill's right edge
        // standing still while the line ran on ahead of it, so the area
        // caught up in jumps -- one jump per category.
        var tip = _pathEnd(path) ?? points.last;
        var fill = Path.from(path)
          ..lineTo(tip.dx, plot.bottom)
          ..lineTo(points.first.dx, plot.bottom)
          ..close();
        canvas.drawPath(
            fill,
            Paint()
              ..shader = ui.Gradient.linear(
                  Offset(0, plot.top), Offset(0, plot.bottom), [
                colour.withValues(alpha: 0.45 * alpha),
                colour.withValues(alpha: 0.02 * alpha),
              ]));
      }
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = e.strokeWidth
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = colour);
    }

    if (kind == ChartType.scatter || e.showValues) {
      for (var i = 0; i < points.length; i++) {
        // Each dot's own arrival, when they are being dealt one at a time.
        var dot = perPoint
            ? animation.progressAt(reveal, at * n + i, which.length * n)
            : progress;
        if (animating && dot <= 0) continue;

        var swelling = animating &&
            (animation.preset == ChartAnimationPreset.popIn ||
                animation.preset == ChartAnimationPreset.random);
        canvas.drawCircle(
            points[i],
            e.strokeWidth * 1.4 * (swelling ? dot.clamp(0.0, 1.4) : 1),
            Paint()
              ..color = perPoint && dot < 1
                  ? colour.withValues(alpha: colour.a * dot.clamp(0.0, 1.0))
                  : colour);
        if (e.showValues) {
          // Counting up only where the point itself is growing. Drawn on, a
          // point that has been passed is at its full value and saying
          // otherwise would contradict the line running through it.
          var shown = swelling ||
                  (animating &&
                      !perPoint &&
                      animation.preset == ChartAnimationPreset.grow)
              ? dot.clamp(0.0, 1.0)
              : 1.0;
          paintTextInBox(
              canvas,
              formatTick(data.valueAt(s, i) * shown),
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

/// _trimmed is the first [fraction] of a path, by length. What draws a line on
/// rather than growing it out of the axis.
Path _trimmed(Path path, double fraction) {
  var out = Path();
  for (var metric in path.computeMetrics()) {
    var want = metric.length * fraction.clamp(0.0, 1.0);
    if (want <= 0) continue;
    out.addPath(metric.extractPath(0, want), Offset.zero);
  }
  return out;
}

/// _lastX is how far along the drawn part has got, which is what decides
/// which of the line's points have arrived and may be dotted or labelled.
double _lastX(Path path) => path.getBounds().right;

/// _pathEnd is where a path actually stops.
///
/// Off the metrics rather than off the bounding box, which is the same thing
/// only for a line that runs left to right and never comes back -- and a
/// smoothed line overshoots its own points, so even that one is not quite
/// true.
Offset? _pathEnd(Path path) {
  Offset? out;
  for (var metric in path.computeMetrics()) {
    var tangent = metric.getTangentForOffset(metric.length);
    if (tangent != null) out = tangent.position;
  }
  return out;
}

Offset _firstPoint(Path path) => path.getBounds().topLeft;

/// _linePath joins the points, optionally through a Catmull-Rom style smooth.
///
/// The control points are a fraction of the gap to each neighbour, which keeps
/// the curve from overshooting past a peak -- overshoot on a chart is not a
/// style choice, it draws a value that is not in the data.
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
