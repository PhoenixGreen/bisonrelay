import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/painting.dart';

// chart_analysis.dart is the kinds analysis needs that the gallery lacked
// (Ken, 2026-11-17, the improvements report's ninth item): a box plot (or
// violin) of how each column's numbers spread, a bump chart of places over
// many periods, and a marimekko of each row's parts sized by its total.
// Drawn like the new kinds (chart_extra.dart): no axes of the chart's own,
// arriving an item at a time, noting their marks.

/// paintAnalysis draws [e], one of the analysis kinds, in [area].
void paintAnalysis(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  if (e.data.series.isEmpty || e.data.categories.isEmpty) return;
  var mode = modeOf(e.design, e.type.name);
  switch (e.type) {
    case ChartType.boxPlot:
      _boxPlot(canvas, area, e, reveal, mode);
    case ChartType.bump:
      _bump(canvas, area, e, reveal, mode);
    case ChartType.marimekko:
      _marimekko(canvas, area, e, reveal);
    default:
      break;
  }
}

TextSpec _lab(ChartElement e, TextAlignSpec align, [double? size]) =>
    e.labelSpec.copyWith(
        align: align,
        verticalAlign: VerticalAlignSpec.middle,
        fontSize: size ?? e.labelSpec.fontSize);

void _say(ui.Canvas canvas, String s, TextSpec spec, Rect box) {
  if (s.isEmpty || box.width <= 1 || box.height <= 1) return;
  paintTextInBox(canvas, s, spec, box);
}

Color _ink(Color fill) => fill.computeLuminance() > 0.45
    ? const Color(0xFF1B1B1B)
    : const Color(0xFFFFFFFF);

Color _quiet(ChartElement e, [double a = 0.3]) =>
    e.labelSpec.color.withValues(alpha: a);

String _num(ChartElement e, double v, [int s = 0]) => formatSeries(e, s, v);

/// _scale writes a few values up the left of [plot], from [lo] to [hi],
/// with faint lines across.
void _scale(ui.Canvas canvas, Rect plot, ChartElement e, double lo, double hi,
    double left) {
  var spec = _lab(e, TextAlignSpec.right, e.labelSpec.fontSize * 0.85);
  for (var k = 0; k <= 4; k++) {
    var v = lo + (hi - lo) * k / 4;
    var y = plot.bottom - plot.height * k / 4;
    if (e.showGrid) {
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y),
          Paint()..color = e.gridColor);
    }
    if (e.showYLabels) {
      _say(
          canvas,
          formatAxis(e, v),
          spec,
          Rect.fromLTRB(
              left, y - spec.fontSize, plot.left - 6, y + spec.fontSize));
    }
  }
}

// ------------------------------------------------------------ box plot

/// Quartiles of sorted [v] by straight-line interpolation.
double _q(List<double> v, double p) {
  if (v.isEmpty) return double.nan;
  var at = (v.length - 1) * p;
  var lo = at.floor(), hi = at.ceil();
  return v[lo] + (v[hi] - v[lo]) * (at - lo);
}

/// _boxPlot is a box for each series -- each column of numbers, its rows
/// the samples: the middle half, the median, whiskers to the furthest
/// within one and a half of the box's height, beyond them dots. As a
/// violin, the spread's shape mirrored; with "dots", every value over a
/// faint box.
void _boxPlot(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, String mode) {
  var d = e.data;
  var groups = [
    for (var s = 0; s < d.series.length; s++)
      [
        for (var i = 0; i < d.categories.length; i++)
          if (!d.valueAt(s, i).isNaN) d.valueAt(s, i)
      ]..sort(),
  ];
  var all = groups.expand((g) => g).toList();
  if (all.isEmpty) return;
  var lo = all.reduce(math.min), hi = all.reduce(math.max);
  var pad = (hi - lo) * 0.08 + 1e-9;
  lo -= pad;
  hi += pad;
  var fs = e.labelSpec.fontSize;
  var left = area.left;
  var plot = Rect.fromLTRB(
      area.left + (e.showYLabels ? fs * 3.2 : 4),
      area.top + fs * 0.6,
      area.right - 4,
      area.bottom - (e.showXLabels ? fs * 2 : 4));
  _scale(canvas, plot, e, lo, hi, left);
  double y(double v) => plot.bottom - (v - lo) / (hi - lo) * plot.height;
  var n = groups.length;
  var slot = plot.width / n;
  var w = math.min(slot * 0.5, fs * 6);
  for (var (s, g) in groups.indexed) {
    if (g.isEmpty) continue;
    var p = sliceProgress(e, reveal, s, n);
    if (p.gone) continue;
    var cx = plot.left + slot * (s + 0.5);
    var colour = d.series[s].color;
    var q1 = _q(g, 0.25), med = _q(g, 0.5), q3 = _q(g, 0.75);
    var iqr = q3 - q1;
    var low = g.firstWhere((v) => v >= q1 - 1.5 * iqr, orElse: () => g.first);
    var high = g.lastWhere((v) => v <= q3 + 1.5 * iqr, orElse: () => g.last);
    // Grown from the median.
    double grow(double v) => med + (v - med) * p.size.clamp(0.0, 1.0);
    var line = Paint()
      ..color = p.tint(colour)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    if (mode == "violin") {
      // A gentle shape: how many values lie near each height, mirrored.
      var bw = (hi - lo) / 12;
      var steps = 40;
      var dens = <double>[];
      for (var k = 0; k <= steps; k++) {
        var at = lo + (hi - lo) * k / steps;
        dens.add(g.fold(
            0.0, (t, v) => t + math.exp(-0.5 * math.pow((v - at) / bw, 2))));
      }
      var most = dens.reduce(math.max);
      var path = Path();
      for (var k = 0; k <= steps; k++) {
        var at = lo + (hi - lo) * k / steps;
        var half = w / 2 * dens[k] / most * p.size.clamp(0.0, 1.0);
        k == 0 ? path.moveTo(cx + half, y(at)) : path.lineTo(cx + half, y(at));
      }
      for (var k = steps; k >= 0; k--) {
        var at = lo + (hi - lo) * k / steps;
        var half = w / 2 * dens[k] / most * p.size.clamp(0.0, 1.0);
        path.lineTo(cx - half, y(at));
      }
      path.close();
      canvas.drawPath(
          path, Paint()..color = p.tint(colour.withValues(alpha: 0.35)));
      canvas.drawPath(path, line);
      canvas.drawLine(Offset(cx - w * 0.18, y(med)),
          Offset(cx + w * 0.18, y(med)), line..strokeWidth = 2.4);
    } else {
      var box = Rect.fromLTRB(cx - w / 2, y(grow(q3)), cx + w / 2, y(grow(q1)));
      canvas.drawRect(
          box,
          Paint()
            ..color =
                p.tint(colour.withValues(alpha: mode == "dots" ? 0.12 : 0.3)));
      canvas.drawRect(box, line);
      canvas.drawLine(Offset(cx, y(grow(q3))), Offset(cx, y(grow(high))), line);
      canvas.drawLine(Offset(cx, y(grow(q1))), Offset(cx, y(grow(low))), line);
      for (var v in [high, low]) {
        canvas.drawLine(Offset(cx - w * 0.2, y(grow(v))),
            Offset(cx + w * 0.2, y(grow(v))), line);
      }
      canvas.drawLine(
          Offset(box.left, y(med)),
          Offset(box.right, y(med)),
          Paint()
            ..color = p.tint(colour)
            ..strokeWidth = 3);
      // Beyond the whiskers, or (dots) every value, a little apart.
      var r = math.max(2.5, fs * 0.2);
      for (var (k, v) in g.indexed) {
        var out = v < low || v > high;
        if (!out && mode != "dots") continue;
        var jitter =
            mode == "dots" ? ((k * 37 % 11) / 10 - 0.5) * w * 0.7 : 0.0;
        canvas.drawCircle(Offset(cx + jitter, y(v)), r,
            Paint()..color = p.tint(colour.withValues(alpha: out ? 1 : 0.7)));
      }
    }
    notePart(ChartPartKind.mark,
        Rect.fromLTRB(cx - w / 2, y(g.last), cx + w / 2, y(g.first)),
        series: s, index: s);
    if (e.showValues && p.size >= 1) {
      _say(
          canvas,
          _num(e, med, s),
          e.valueSpec.copyWith(
              align: TextAlignSpec.left,
              verticalAlign: VerticalAlignSpec.middle),
          Rect.fromLTWH(cx + w / 2 + 4, y(med) - fs, slot / 2 - w / 2, fs * 2));
    }
    if (e.showXLabels) {
      _say(canvas, d.series[s].name, _lab(e, TextAlignSpec.center),
          Rect.fromLTWH(cx - slot / 2, plot.bottom + 4, slot, fs * 1.8));
    }
  }
}

// ------------------------------------------------------------ bump chart

/// _bump is each series' place over the periods (the categories): ranked
/// by its value in each, the largest first -- or (mode "places") its
/// values already the places, 1 the top. A line each through its places,
/// its name at both ends.
void _bump(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, String mode) {
  var d = e.data, periods = d.categories.length, n = d.series.length;
  if (periods < 1 || n < 2) return;
  // places[s][t]: the place of series s in period t, 1 the top.
  var places = List.generate(n, (_) => List<int?>.filled(periods, null));
  for (var t = 0; t < periods; t++) {
    var order = [
      for (var s = 0; s < n; s++)
        if (!d.valueAt(s, t).isNaN) s
    ];
    if (mode == "places") {
      for (var s in order) {
        places[s][t] = d.valueAt(s, t).round();
      }
    } else {
      order.sort((a, b) => d.valueAt(b, t).compareTo(d.valueAt(a, t)));
      for (var (k, s) in order.indexed) {
        places[s][t] = k + 1;
      }
    }
  }
  var most = places
      .expand((p) => p)
      .whereType<int>()
      .fold(n, (a, b) => math.max(a, b));
  var fs = e.labelSpec.fontSize;
  var spec = _lab(e, TextAlignSpec.left);
  var nameW = e.showXLabels
      ? math.min(
          area.width * 0.22,
          d.series
                  .map((s) =>
                      layoutText(s.name, spec, maxWidth: double.infinity).width)
                  .fold(0.0, math.max) +
              fs)
      : 0.0;
  var plot = Rect.fromLTRB(area.left + nameW, area.top + fs * 1.8,
      area.right - nameW, area.bottom - fs * 0.6);
  double x(int t) =>
      plot.left +
      (periods == 1 ? plot.width / 2 : plot.width * t / (periods - 1));
  double y(int place) =>
      plot.top + (most == 1 ? 0 : plot.height * (place - 1) / (most - 1));
  // The periods across the top.
  for (var t = 0; t < periods; t++) {
    _say(
        canvas,
        d.categories[t],
        _lab(e, TextAlignSpec.center, fs * 0.85),
        Rect.fromCenter(
            center: Offset(x(t), area.top + fs * 0.7),
            width: fs * 6,
            height: fs * 1.6));
  }
  var p0 = e.animation.on ? reveal.clamp(0.0, 1.0) : 1.0;
  for (var s = 0; s < n; s++) {
    var colour = d.series[s].color;
    var pts = [
      for (var t = 0; t < periods; t++)
        if (places[s][t] case var pl?) Offset(x(t), y(pl))
    ];
    if (pts.isEmpty) continue;
    // Drawn on along the periods as it arrives.
    var path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var k = 1; k < pts.length; k++) {
      var a = pts[k - 1], b = pts[k];
      var mid = (a.dx + b.dx) / 2;
      path.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    var stroke = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.5, fs * 0.3)
      ..strokeCap = StrokeCap.round;
    for (var m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * p0), stroke);
    }
    for (var (k, pt) in pts.indexed) {
      if (k / math.max(1, pts.length - 1) > p0 + 1e-6) break;
      canvas.drawCircle(pt, math.max(4, fs * 0.35), Paint()..color = colour);
    }
    notePart(ChartPartKind.mark,
        Rect.fromPoints(pts.first, pts.last).inflate(fs * 0.5),
        series: s, index: s);
    if (e.showXLabels) {
      _say(
          canvas,
          d.series[s].name,
          spec.copyWith(align: TextAlignSpec.right, color: colour),
          Rect.fromLTRB(area.left, pts.first.dy - fs, plot.left - fs * 0.5,
              pts.first.dy + fs));
      if (p0 >= 1) {
        _say(
            canvas,
            d.series[s].name,
            spec.copyWith(color: colour),
            Rect.fromLTRB(plot.right + fs * 0.5, pts.last.dy - fs, area.right,
                pts.last.dy + fs));
      }
    }
  }
}

// ------------------------------------------------------------ marimekko

/// _marimekko is each row a column as wide as its total, split from the
/// bottom by its parts' shares (the series): market share by region, where
/// both the size and the split matter.
void _marimekko(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var d = e.data, n = d.categories.length, parts = d.series.length;
  var totals = [
    for (var i = 0; i < n; i++)
      [for (var s = 0; s < parts; s++) d.valueAt(s, i)]
          .where((v) => !v.isNaN && v > 0)
          .fold(0.0, (a, b) => a + b)
  ];
  var whole = totals.fold(0.0, (a, b) => a + b);
  if (whole <= 0) return;
  var fs = e.labelSpec.fontSize;
  var plot = Rect.fromLTRB(area.left, area.top + (e.showLegend ? 0 : 0),
      area.right, area.bottom - (e.showXLabels ? fs * 2.2 : 0));
  var gap = math.max(1.5, plot.width * 0.004);
  var x = plot.left;
  for (var i = 0; i < n; i++) {
    var w = plot.width * totals[i] / whole;
    var p = sliceProgress(e, reveal, i, n);
    if (!p.gone && totals[i] > 0) {
      var y = plot.bottom;
      for (var s = 0; s < parts; s++) {
        var v = d.valueAt(s, i);
        if (v.isNaN || v <= 0) continue;
        var h = plot.height * v / totals[i] * p.size.clamp(0.0, 1.0);
        var r = Rect.fromLTWH(x + gap / 2, y - h, math.max(0, w - gap), h);
        var fill = p.tint(d.series[s].color);
        canvas.drawRect(r, Paint()..color = fill);
        notePart(ChartPartKind.mark, r, series: s, index: i);
        if (e.showValues &&
            p.size >= 1 &&
            r.width > fs * 2.4 &&
            r.height > fs * 1.4) {
          _say(
              canvas,
              "${(v / totals[i] * 100).round()}%",
              e.valueSpec.copyWith(
                  color: _ink(fill),
                  align: TextAlignSpec.center,
                  verticalAlign: VerticalAlignSpec.middle),
              r);
        }
        y -= h;
      }
    }
    if (e.showXLabels) {
      _say(canvas, d.categories[i], _lab(e, TextAlignSpec.center, fs * 0.85),
          Rect.fromLTWH(x, plot.bottom + 4, w, fs * 1.8));
    }
    x += w;
  }
  // A faint line along the floor.
  canvas.drawLine(
      plot.bottomLeft, plot.bottomRight, Paint()..color = _quiet(e));
}
