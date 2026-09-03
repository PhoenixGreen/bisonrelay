import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/painting.dart';

// chart_painter.dart draws a ChartElement.
//
// The shape of it is one layout pass followed by one draw pass. The layout
// works out what is left for the plot once the title, the axis labels, the
// tick labels and the legend have taken their share; the draw puts the series
// into that rectangle. Everything is measured, nothing is a guessed margin, so
// a chart with long category names and a chart with none both use the space
// they have.
//
// The value axis is the part worth reading twice. Its range is chosen to end
// on round numbers -- see _niceRange -- because an axis running to 8.3714 is
// not readable at any size, and a chart on a canvas is going to be looked at
// rather than hovered over.

/// paintChart draws [e] filling [rect].
void paintChart(ui.Canvas canvas, Rect rect, ChartElement e) {
  if (rect.width <= 8 || rect.height <= 8) return;
  var data = e.data;
  if (data.series.isEmpty) {
    _placeholder(canvas, rect, e);
    return;
  }

  var area = rect;

  // The two labels, each either laid out by the chart or sitting where it was
  // put. A placed label is drawn last, over the plot, because a label somebody
  // has dragged onto the plot was dragged there on purpose -- and because
  // taking room away from the plot for a label that is no longer above it
  // would leave a band of nothing where it used to be.
  area = _flowLabel(canvas, area, rect, e.title, e.titleBox, e.titleSpec);
  area = _flowLabel(canvas, area, rect, e.description, e.descriptionBox,
      descriptionSpec(e));

  // Not "and more than one series". A one-series chart with the legend turned
  // on used to draw nothing at all, which reads as the switch being broken
  // rather than as the legend being unnecessary -- and a single series with a
  // name worth reading is a perfectly good reason to want one.
  if (e.showLegend && data.series.isNotEmpty) {
    area = _legend(canvas, area, e);
  }

  if (e.type.isCircular) {
    _circular(canvas, area, e);
  } else {
    _cartesian(canvas, area, e);
  }

  _placedLabel(canvas, rect, e.title, e.titleBox, e.titleSpec);
  _placedLabel(canvas, rect, e.description, e.descriptionBox,
      descriptionSpec(e));
}

/// descriptionSpec is the description's type: the label size, softened, so it
/// reads as a note under the title rather than as a second title.
TextSpec descriptionSpec(ChartElement e) => e.labelSpec.copyWith(
      color: e.labelSpec.color.withValues(alpha: 0.75),
      verticalAlign: VerticalAlignSpec.top,
    );

/// _flowLabel draws a label the chart is laying out itself, and returns what
/// is left below it. A hidden, empty or placed label takes no room and draws
/// nothing here.
Rect _flowLabel(ui.Canvas canvas, Rect area, Rect rect, String text,
    ChartLabel box, TextSpec spec) {
  if (!box.show || text.isEmpty || box.placed) return area;
  var h = paintTextInBox(
      canvas, text, spec, Rect.fromLTWH(area.left, area.top, area.width,
          area.height),
      clip: true);
  return Rect.fromLTRB(
      area.left, area.top + h + rect.height * 0.02, area.right, area.bottom);
}

/// _placedLabel draws a label that has been moved, in its own box over
/// everything else.
void _placedLabel(ui.Canvas canvas, Rect rect, String text, ChartLabel box,
    TextSpec spec) {
  if (!box.show || text.isEmpty || !box.placed) return;
  paintTextInBox(canvas, text, spec, box.rectIn(rect), clip: true);
}

/// _placeholder is what an empty chart looks like: a labelled frame rather
/// than nothing, so a chart just dragged in is visible and selectable before
/// any numbers have been typed into it.
void _placeholder(ui.Canvas canvas, Rect rect, ChartElement e) {
  canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = e.axisColor);
  paintTextInBox(
      canvas,
      "No chart data yet",
      e.labelSpec.copyWith(
          align: TextAlignSpec.center, verticalAlign: VerticalAlignSpec.middle),
      rect,
      clip: true);
}

/// _legend draws the series keys along the top and returns what is left.
Rect _legend(ui.Canvas canvas, Rect area, ChartElement e) {
  var spec = e.labelSpec;
  var swatch = spec.fontSize * 0.7;
  var gap = spec.fontSize * 0.5;
  var x = area.left;
  var y = area.top;
  var rowHeight = spec.fontSize * 1.6;

  for (var s in e.data.series) {
    var painter = layoutText(s.name, spec, maxWidth: area.width);
    var itemWidth = swatch + gap * 0.6 + painter.width + gap * 1.6;
    if (x + itemWidth > area.right && x > area.left) {
      x = area.left;
      y += rowHeight;
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y + (rowHeight - swatch) / 2, swatch, swatch),
          Radius.circular(swatch * 0.25)),
      Paint()..color = s.color,
    );
    painter.paint(
        canvas, Offset(x + swatch + gap * 0.6, y + (rowHeight - painter.height) / 2));
    x += itemWidth;
  }

  return Rect.fromLTRB(
      area.left, y + rowHeight + e.labelSpec.fontSize * 0.4, area.right, area.bottom);
}

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
  var step = (norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 2.5 ? 2.5 : norm <= 5 ? 5 : 10) * mag;

  var min = (lo / step).floor() * step;
  var max = (hi / step).ceil() * step;
  var ticks = <double>[];
  for (var v = min; v <= max + step * 0.001; v += step) {
    ticks.add(v.abs() < step * 1e-9 ? 0 : v);
  }
  return _ValueRange(min, max, ticks);
}

/// _formatTick prints an axis value without trailing noise.
String _formatTick(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) {
    var n = v.round();
    if (n.abs() >= 1000000) return "${(n / 1000000).toStringAsFixed(1)}M";
    if (n.abs() >= 10000) return "${(n / 1000).toStringAsFixed(0)}k";
    return "$n";
  }
  return v.toStringAsFixed(v.abs() < 1 ? 2 : 1);
}

/// _cartesian draws every type that has an x and a y axis.
void _cartesian(ui.Canvas canvas, Rect area, ChartElement e) {
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
  for (var t in range.ticks) {
    var p = layoutText(_formatTick(t), labelSpec, maxWidth: area.width / 3);
    valueGutter = math.max(valueGutter, p.width);
  }
  valueGutter += labelSpec.fontSize * 0.5;

  var categoryGutter = labelSpec.fontSize * 1.6;
  var axisTitleGutter = labelSpec.fontSize * 1.5;

  var left = area.left +
      (horizontal ? _widestCategory(data.categories, labelSpec, area) : valueGutter) +
      (e.yAxisLabel.isNotEmpty ? axisTitleGutter : 0);
  var bottom = area.bottom -
      (horizontal ? categoryGutter : categoryGutter) -
      (e.xAxisLabel.isNotEmpty ? axisTitleGutter : 0);
  var plot = Rect.fromLTRB(
      left, area.top + labelSpec.fontSize * 0.6, area.right - labelSpec.fontSize * 0.5, bottom);
  if (plot.width <= 4 || plot.height <= 4) return;

  _grid(canvas, plot, range, e, horizontal);
  _axisLabels(canvas, area, plot, range, e, horizontal, valueGutter,
      categoryGutter, axisTitleGutter);

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
  if (bars.isNotEmpty) _bars(canvas, plot, range, e, horizontal, bars);
  if (lines.isNotEmpty) _lines(canvas, plot, range, e, lines);
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
    var text = _formatTick(t);
    if (horizontal) {
      var x = plot.left + plot.width * f;
      paintTextInBox(
          canvas,
          text,
          spec.copyWith(
              align: TextAlignSpec.center, verticalAlign: VerticalAlignSpec.top),
          Rect.fromLTWH(x - spec.fontSize * 2, plot.bottom + spec.fontSize * 0.3,
              spec.fontSize * 4, categoryGutter));
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
          Rect.fromLTWH(area.left, y, plot.left - area.left - spec.fontSize * 0.4,
              slot),
          clip: true);
    } else {
      var slot = plot.width / slots;
      var x = plot.left + slot * i;
      paintTextInBox(
          canvas,
          categories[i],
          spec.copyWith(
              align: TextAlignSpec.center, verticalAlign: VerticalAlignSpec.top),
          Rect.fromLTWH(x, plot.bottom + spec.fontSize * 0.35, slot,
              categoryGutter),
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
        Rect.fromLTRB(plot.left, area.bottom - axisTitleGutter, plot.right,
            area.bottom));
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
/// a line over it -- see _cartesian. It is also what decides whether the bars
/// are side by side: two bar series share a slot however the chart's own type
/// is set, since drawing them on top of each other would hide one of them.
void _bars(ui.Canvas canvas, Rect plot, _ValueRange range, ChartElement e,
    bool horizontal, List<int> which) {
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

      var r = math.min(e.barRadius,
          math.min(bar.width, bar.height) / 2);
      canvas.drawRRect(
          RRect.fromRectAndRadius(bar, Radius.circular(math.max(0, r))),
          Paint()..color = series.color);

      if (e.showValues && v != 0) {
        var label = _formatTick(v);
        var box = horizontal
            ? Rect.fromLTWH(bar.right + e.valueSpec.fontSize * 0.3,
                bar.center.dy - e.valueSpec.fontSize, e.valueSpec.fontSize * 5,
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
    List<int> which) {
  var data = e.data;
  var n = data.categories.length;
  if (n == 0) return;

  // Points sit in the middle of their slot, not on the axis ends, so a line
  // chart and a bar chart of the same numbers line up with each other.
  double xAt(int i) =>
      plot.left + plot.width * (n == 1 ? 0.5 : (i + 0.5) / n);
  double yAt(double v) =>
      plot.bottom - plot.height * range.fraction(v).clamp(-0.2, 1.2);

  for (var s in which) {
    var series = data.series[s];
    var kind = series.typeIn(e.type);
    var points = [
      for (var i = 0; i < n; i++) Offset(xAt(i), yAt(data.valueAt(s, i))),
    ];
    if (points.isEmpty) continue;

    if (kind != ChartType.scatter) {
      var path = _linePath(points, e.smooth && kind.usesSmooth);
      if (kind == ChartType.area) {
        var fill = Path.from(path)
          ..lineTo(points.last.dx, plot.bottom)
          ..lineTo(points.first.dx, plot.bottom)
          ..close();
        canvas.drawPath(
            fill,
            Paint()
              ..shader = ui.Gradient.linear(
                  Offset(0, plot.top), Offset(0, plot.bottom), [
                series.color.withValues(alpha: 0.45),
                series.color.withValues(alpha: 0.02),
              ]));
      }
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = e.strokeWidth
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = series.color);
    }

    if (kind == ChartType.scatter || e.showValues) {
      for (var i = 0; i < points.length; i++) {
        canvas.drawCircle(points[i], e.strokeWidth * 1.4,
            Paint()..color = series.color);
        if (e.showValues) {
          paintTextInBox(
              canvas,
              _formatTick(data.valueAt(s, i)),
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

/// _circular draws the pie, donut, radial-bar and radar types.
void _circular(ui.Canvas canvas, Rect area, ChartElement e) {
  var side = math.min(area.width, area.height);
  var box = Rect.fromCenter(
      center: area.center, width: side, height: side).deflate(side * 0.06);
  var centre = box.center;
  var radius = box.width / 2;
  var data = e.data;

  switch (e.type) {
    case ChartType.pie:
    case ChartType.donut:
      var values = data.series.first.values;
      var total = values.fold<double>(0, (t, v) => t + v.abs());
      if (total <= 0) return;
      var start = -math.pi / 2;
      var inner = e.type == ChartType.donut ? radius * e.innerRadius : 0.0;

      for (var i = 0; i < values.length; i++) {
        var sweep = values[i].abs() / total * math.pi * 2;
        var color = i < data.series.length && data.series.length > 1
            ? data.series[i].color
            : chartPalette[i % chartPalette.length];

        var path = Path()
          ..moveTo(centre.dx + math.cos(start) * inner,
              centre.dy + math.sin(start) * inner)
          ..lineTo(centre.dx + math.cos(start) * radius,
              centre.dy + math.sin(start) * radius)
          ..arcTo(Rect.fromCircle(center: centre, radius: radius), start, sweep,
              false);
        if (inner > 0) {
          path.arcTo(Rect.fromCircle(center: centre, radius: inner),
              start + sweep, -sweep, false);
        } else {
          path.lineTo(centre.dx, centre.dy);
        }
        path.close();
        canvas.drawPath(path, Paint()..color = color);

        if (e.showValues) {
          var mid = start + sweep / 2;
          var at = centre +
              Offset(math.cos(mid), math.sin(mid)) * (radius + inner) / 2;
          paintTextInBox(
              canvas,
              "${(values[i].abs() / total * 100).round()}%",
              e.valueSpec.copyWith(
                  align: TextAlignSpec.center,
                  verticalAlign: VerticalAlignSpec.middle),
              Rect.fromCenter(
                  center: at,
                  width: radius,
                  height: e.valueSpec.fontSize * 2));
        }
        start += sweep;
      }

    case ChartType.radialBar:
      var values = data.series.first.values;
      var maxV = values.fold<double>(
          0, (m, v) => math.max(m, v.abs()));
      if (maxV <= 0) return;
      var ring = radius * (1 - e.innerRadius) / math.max(1, values.length);
      for (var i = 0; i < values.length; i++) {
        var r = radius - ring * i - ring / 2;
        var color = chartPalette[i % chartPalette.length];
        var track = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring * 0.7
          ..color = e.gridColor;
        canvas.drawCircle(centre, r, track);
        canvas.drawArc(
            Rect.fromCircle(center: centre, radius: r),
            -math.pi / 2,
            math.pi * 2 * (values[i].abs() / maxV),
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = ring * 0.7
              ..strokeCap = StrokeCap.round
              ..color = color);
      }

    case ChartType.radar:
      var axes = data.categories.length;
      if (axes < 3) return;
      var maxV = 0.0;
      for (var s in data.series) {
        for (var v in s.values) {
          maxV = math.max(maxV, v.abs());
        }
      }
      if (maxV <= 0) return;

      Offset spoke(int i, double frac) {
        var a = -math.pi / 2 + i * 2 * math.pi / axes;
        return centre + Offset(math.cos(a), math.sin(a)) * radius * frac;
      }

      var web = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = e.gridColor;
      for (var ringIndex = 1; ringIndex <= 4; ringIndex++) {
        var path = Path();
        for (var i = 0; i <= axes; i++) {
          var p = spoke(i % axes, ringIndex / 4);
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, web);
      }
      for (var i = 0; i < axes; i++) {
        canvas.drawLine(centre, spoke(i, 1), web);
        paintTextInBox(
            canvas,
            data.categories[i],
            e.labelSpec.copyWith(
                align: TextAlignSpec.center,
                verticalAlign: VerticalAlignSpec.middle),
            Rect.fromCenter(
                center: spoke(i, 1.14),
                width: radius * 0.7,
                height: e.labelSpec.fontSize * 2));
      }

      for (var s = 0; s < data.series.length; s++) {
        var path = Path();
        for (var i = 0; i <= axes; i++) {
          var p = spoke(i % axes, data.valueAt(s, i % axes).abs() / maxV);
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        path.close();
        canvas.drawPath(path,
            Paint()..color = data.series[s].color.withValues(alpha: 0.28));
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = e.strokeWidth
              ..color = data.series[s].color);
      }

    default:
      break;
  }
}
