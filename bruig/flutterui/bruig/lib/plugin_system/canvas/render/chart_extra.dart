export 'package:bruig/plugin_system/canvas/model/tile_maps.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/chart_analysis.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/model/tile_maps.dart';
import 'package:bruig/plugin_system/canvas/render/label_placer.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/painting.dart';

// chart_extra.dart draws the kinds the research added (Ken, 2026-11-17:
// "all" nine; prototype v7): diverging bars, dumbbell, waterfall, heatmap,
// big number, dot spread, parliament, tile map and pyramid. Like the
// infographic kinds they have no axes; they read the chart's categories and
// series, arrive an item at a time (sliceProgress), take a highlight's
// colour where one reaches, and note their marks so the Charts tab can pick
// them. Which way each is drawn is its ChartDesign.mode (chartModes).

/// paintExtra draws [e], one of the new kinds, in [area].
void paintExtra(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  if (e.data.series.isEmpty || e.data.categories.isEmpty) return;
  var mode = modeOf(e.design, e.type.name);
  switch (e.type) {
    case ChartType.diverging:
      _diverging(canvas, area, e, reveal, mode);
    case ChartType.dumbbell:
      _dumbbell(canvas, area, e, reveal, mode);
    case ChartType.waterfall:
      _waterfall(canvas, area, e, reveal, mode);
    case ChartType.heatmap:
      _heatmap(canvas, area, e, reveal, mode);
    case ChartType.bigNumber:
      _bigNumber(canvas, area, e, reveal, mode);
    case ChartType.beeswarm:
      _beeswarm(canvas, area, e, reveal, mode);
    case ChartType.parliament:
      _parliament(canvas, area, e, reveal, mode);
    case ChartType.tileMap:
      _tileMap(canvas, area, e, reveal, mode);
    case ChartType.pyramid:
      _pyramid(canvas, area, e, reveal, mode);
    default:
      paintAnalysis(canvas, area, e, reveal);
  }
}

// ------------------------------------------------------------ shared bits

double _v(ChartElement e, int s, int i) =>
    s < e.data.series.length ? e.data.valueAt(s, i) : double.nan;

/// _col is item [i]'s own colour where a highlight or colour-by gives one,
/// else [or].
Color _col(ChartElement e, int i, Color or) => e.data.markAt(i) ?? or;

TextSpec _lab(ChartElement e, TextAlignSpec align, [double? size]) =>
    e.labelSpec.copyWith(
        align: align,
        verticalAlign: VerticalAlignSpec.middle,
        fontSize: size ?? e.labelSpec.fontSize);

TextSpec _fig(ChartElement e, TextAlignSpec align, [double? size]) =>
    e.valueSpec.copyWith(
        align: align,
        verticalAlign: VerticalAlignSpec.middle,
        fontSize: size ?? e.valueSpec.fontSize);

void _say(ui.Canvas canvas, String s, TextSpec spec, Rect box) {
  if (s.isEmpty || box.width <= 1 || box.height <= 1) return;
  paintTextInBox(canvas, s, spec, box);
}

double _width(String s, TextSpec spec) =>
    s.isEmpty ? 0 : layoutText(s, spec, maxWidth: double.infinity).width;

String _num(ChartElement e, double v, [int s = 0]) => formatSeries(e, s, v);

Color _ink(Color fill) => fill.computeLuminance() > 0.45
    ? const Color(0xFF1B1B1B)
    : const Color(0xFFFFFFFF);

/// _quiet is a muted ink for connectors and tracks, from the labels'.
Color _quiet(ChartElement e, [double a = 0.3]) =>
    e.labelSpec.color.withValues(alpha: a);

Color _shade(Color lo, Color hi, double f) =>
    Color.lerp(lo, hi, f.clamp(0.0, 1.0)) ?? hi;

/// _nameRoom is how wide the widest of [names] is written, capped.
double _nameRoom(ChartElement e, Iterable<String> names, double cap) {
  if (!e.showXLabels) return 0;
  var spec = _lab(e, TextAlignSpec.right);
  var w = 0.0;
  for (var n in names) {
    w = math.max(w, _width(n, spec));
  }
  return math.min(cap, w + spec.fontSize * 0.6);
}

// ------------------------------------------------------------ diverging

void _diverging(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, String mode) {
  var d = e.data, n = d.categories.length;
  if (mode == "likert" && d.series.length >= 2) {
    _likert(canvas, area, e, reveal);
    return;
  }
  var values = [for (var i = 0; i < n; i++) _v(e, 0, i)];
  var most = values.fold(0.0, (m, v) => v.isNaN ? m : math.max(m, v.abs()));
  if (most <= 0) return;
  var fs = e.valueSpec.fontSize;
  if (mode == "columns") {
    var labelH = e.showXLabels ? e.labelSpec.fontSize * 1.8 : 0.0;
    var plot = Rect.fromLTRB(
        area.left, area.top + fs * 1.4, area.right, area.bottom - labelH);
    var mid = plot.center.dy, half = plot.height / 2 - fs * 1.2;
    var slot = plot.width / n, bw = slot * (1 - e.barGap.clamp(0.0, 0.9));
    for (var i = 0; i < n; i++) {
      var v = values[i];
      if (v.isNaN) continue;
      var p = sliceProgress(e, reveal, i, n);
      if (p.gone) continue;
      var h = v / most * half * p.size;
      var r = Rect.fromLTWH(plot.left + slot * i + (slot - bw) / 2,
          math.min(mid, mid - h), bw, h.abs());
      var c = p.tint(_col(e, i, v >= 0 ? e.riseColor : e.fallColor));
      notePart(ChartPartKind.mark, r, series: 0, index: i);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              r, Radius.circular(math.min(e.barRadius, bw / 2))),
          Paint()..color = c);
      if (e.showValues && p.size > 0.9) {
        _say(
            canvas,
            "${v > 0 ? "+" : ""}${_num(e, v)}",
            _fig(e, TextAlignSpec.center),
            Rect.fromCenter(
                center: Offset(r.center.dx,
                    v >= 0 ? r.top - fs * 0.7 : r.bottom + fs * 0.7),
                width: slot,
                height: fs * 1.4));
      }
      if (e.showXLabels && (n <= 16 || i % (n ~/ 8) == 0)) {
        _say(
            canvas,
            d.categories[i],
            _lab(e, TextAlignSpec.center),
            Rect.fromLTWH(
                plot.left + slot * i - slot, plot.bottom, slot * 3, labelH));
      }
    }
    canvas.drawLine(
        Offset(plot.left, mid),
        Offset(plot.right, mid),
        Paint()
          ..color = e.axisColor
          ..strokeWidth = 1.2);
    return;
  }
  // Bars either side of a line at zero; each name on the far side of it.
  var rowH = area.height / n;
  var bh = rowH * (1 - e.barGap.clamp(0.0, 0.9));
  var nameW = _nameRoom(e, d.categories, area.width * 0.3);
  var valueW = e.showValues ? fs * 3.2 : 0.0;
  var zero = area.center.dx;
  var half = area.width / 2 - math.max(nameW, valueW) - 4;
  if (half < 10) half = area.width / 2 - 4;
  for (var i = 0; i < n; i++) {
    var v = values[i];
    if (v.isNaN) continue;
    var p = sliceProgress(e, reveal, i, n);
    if (p.gone) continue;
    var w = v / most * half * p.size;
    var y = area.top + rowH * i + (rowH - bh) / 2;
    var r = Rect.fromLTWH(math.min(zero, zero + w), y, w.abs(), bh);
    var c = p.tint(_col(e, i, v >= 0 ? e.riseColor : e.fallColor));
    notePart(ChartPartKind.mark, r, series: 0, index: i);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            r, Radius.circular(math.min(e.barRadius, bh / 2))),
        Paint()..color = c);
    if (e.showXLabels) {
      var box = v >= 0
          ? Rect.fromLTRB(area.left, y, zero - 6, y + bh)
          : Rect.fromLTRB(zero + 6, y, area.right, y + bh);
      _say(canvas, d.categories[i],
          _lab(e, v >= 0 ? TextAlignSpec.right : TextAlignSpec.left), box);
    }
    if (e.showValues && p.size > 0.9) {
      var box = v >= 0
          ? Rect.fromLTWH(r.right + 4, y, valueW, bh)
          : Rect.fromLTWH(r.left - 4 - valueW, y, valueW, bh);
      _say(canvas, "${v > 0 ? "+" : ""}${_num(e, v)}",
          _fig(e, v >= 0 ? TextAlignSpec.left : TextAlignSpec.right), box);
    }
  }
  canvas.drawLine(
      Offset(zero, area.top),
      Offset(zero, area.bottom),
      Paint()
        ..color = e.axisColor
        ..strokeWidth = 1.4);
}

/// _likert is survey answers -- the series, least to most agreeing --
/// centred on the middle answer.
void _likert(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var d = e.data, n = d.categories.length, k = d.series.length;
  var nameW = _nameRoom(e, d.categories, area.width * 0.35);
  var plot =
      Rect.fromLTRB(area.left + nameW, area.top, area.right, area.bottom);
  var rowH = plot.height / n, bh = rowH * 0.66;
  var centre = plot.center.dx;
  // Disagree is the fall colour, agree the rise, the middle a quiet grey.
  Color answer(int s) {
    if (k.isOdd && s == k ~/ 2) return _quiet(e, 0.35);
    var f = s < k / 2 ? 1 - s / (k / 2) : (s - (k - 1) / 2) / (k / 2);
    var base = s < k / 2 ? e.fallColor : e.riseColor;
    return base.withValues(alpha: 0.45 + 0.55 * f.clamp(0.0, 1.0));
  }

  // Scaled so the longer side of any row fits its half.
  var widest = 0.0;
  for (var i = 0; i < n; i++) {
    var vals = [
      for (var s = 0; s < k; s++) _v(e, s, i).isNaN ? 0.0 : _v(e, s, i).abs()
    ];
    var left = 0.0, right = 0.0;
    for (var s = 0; s < k; s++) {
      var share = k.isOdd && s == k ~/ 2 ? vals[s] / 2 : vals[s];
      if (s < k / 2) left += share;
      if (s >= (k - 1) / 2) right += share;
    }
    widest = math.max(widest, math.max(left, right));
  }
  if (widest <= 0) return;
  var scale = (plot.width / 2 - 2) / widest;
  for (var i = 0; i < n; i++) {
    var p = sliceProgress(e, reveal, i, n);
    if (p.gone) continue;
    var vals = [
      for (var s = 0; s < k; s++) _v(e, s, i).isNaN ? 0.0 : _v(e, s, i).abs()
    ];
    var left = 0.0;
    for (var s = 0; s < k ~/ 2; s++) {
      left += vals[s];
    }
    if (k.isOdd) left += vals[k ~/ 2] / 2;
    var x = centre - left * scale * p.size;
    var y = plot.top + rowH * i + (rowH - bh) / 2;
    for (var s = 0; s < k; s++) {
      var w = vals[s] * scale * p.size;
      var r = Rect.fromLTWH(x, y, w, bh);
      var c = p.tint(answer(s));
      notePart(ChartPartKind.mark, r, series: s, index: i);
      canvas.drawRect(r, Paint()..color = c);
      if (e.showValues && w > e.valueSpec.fontSize * 2.4) {
        _say(
            canvas,
            _num(e, vals[s], s),
            _fig(e, TextAlignSpec.center)
                .copyWith(color: _ink(c.withValues(alpha: 1))),
            r);
      }
      x += w;
    }
    if (e.showXLabels) {
      _say(canvas, d.categories[i], _lab(e, TextAlignSpec.right),
          Rect.fromLTRB(area.left, y, plot.left - 6, y + bh));
    }
  }
  canvas.drawLine(
      Offset(centre, plot.top),
      Offset(centre, plot.bottom),
      Paint()
        ..color = e.axisColor
        ..strokeWidth = 1);
}

// ------------------------------------------------------------ dumbbell

void _dumbbell(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, String mode) {
  var d = e.data, n = d.categories.length;
  if (d.series.length < 2) return;
  var all = [
    for (var i = 0; i < n; i++) ...[_v(e, 0, i), _v(e, 1, i)]
  ].where((v) => !v.isNaN).toList();
  if (all.isEmpty) return;
  var lo = all.reduce(math.min), hi = all.reduce(math.max);
  var pad = (hi - lo) * 0.08 + 1e-9;
  lo -= pad;
  hi += pad;
  var fs = e.labelSpec.fontSize;
  var head = fs * 1.6;
  var nameW = _nameRoom(e, d.categories, area.width * 0.3);
  var plot = Rect.fromLTRB(
      area.left + nameW, area.top + head, area.right - 6, area.bottom);
  double x(double v) => plot.left + (v - lo) / (hi - lo) * plot.width;
  var rowH = plot.height / n;
  var dot = math.min(rowH * 0.22, 9.0);
  var a = d.series[0].color, b = d.series[1].color;
  // The key, once, over the first row at its two dots -- kept apart where
  // the dots are close (the shared label rule: "20242025" before).
  if (n > 0 && !_v(e, 0, 0).isNaN && !_v(e, 1, 0).isNaN) {
    var placer = LabelPlacer(
        Rect.fromLTWH(area.left, area.top, area.width, head),
        gap: fs * 0.6);
    for (var (k, colour) in [(0, a), (1, b)]) {
      var spec = _lab(e, TextAlignSpec.center).copyWith(color: colour);
      var size = labelSize(d.series[k].name, spec);
      var cx = x(_v(e, k, 0)), cy = area.top + head / 2;
      Rect box(double left) =>
          Rect.fromLTWH(left, cy - size.height / 2, size.width, size.height);
      // Over its dot; else the side away from the other's.
      var away = _v(e, k, 0) < _v(e, 1 - k, 0);
      var at = placer.place([
        box(cx - size.width / 2),
        box(away ? cx - size.width : cx),
        box(away ? cx : cx - size.width),
        box(away ? area.left : area.right - size.width),
      ]);
      if (at != null) _say(canvas, d.series[k].name, spec, at.inflate(1));
    }
  }
  for (var i = 0; i < n; i++) {
    var v0 = _v(e, 0, i), v1 = _v(e, 1, i);
    if (v0.isNaN || v1.isNaN) continue;
    var p = sliceProgress(e, reveal, i, n);
    if (p.gone) continue;
    var y = plot.top + rowH * (i + 0.5);
    var x0 = x(v0), x1 = x0 + (x(v1) - x0) * p.size;
    var lit = d.markAt(i);
    notePart(
        ChartPartKind.mark,
        Rect.fromLTRB(
            math.min(x0, x1) - dot, y - dot, math.max(x0, x1) + dot, y + dot),
        series: 1,
        index: i);
    if (e.showXLabels) {
      _say(canvas, d.categories[i], _lab(e, TextAlignSpec.right),
          Rect.fromLTRB(area.left, y - rowH / 2, plot.left - 6, y + rowH / 2));
    }
    switch (mode) {
      case "arrows":
        var c = p.tint(lit ?? (v1 >= v0 ? e.riseColor : e.fallColor));
        var paint = Paint()
          ..color = c
          ..strokeWidth = math.max(2, dot * 0.45)
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(x0, y), Offset(x1, y), paint);
        var dir = x1 >= x0 ? 1.0 : -1.0;
        canvas.drawPath(
            Path()
              ..moveTo(x1 + dir * dot * 0.4, y)
              ..lineTo(x1 - dir * dot, y - dot * 0.8)
              ..lineTo(x1 - dir * dot, y + dot * 0.8)
              ..close(),
            Paint()..color = c);
      case "range":
        var r = Rect.fromLTRB(
            math.min(x0, x1), y - dot * 0.7, math.max(x0, x1), y + dot * 0.7);
        canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(dot * 0.7)),
            Paint()..color = p.tint(lit ?? a.withValues(alpha: 0.35)));
        canvas.drawLine(
            Offset(x1, y - dot * 1.1),
            Offset(x1, y + dot * 1.1),
            Paint()
              ..color = p.tint(lit ?? b)
              ..strokeWidth = 2.5);
      default:
        canvas.drawLine(
            Offset(x0, y),
            Offset(x1, y),
            Paint()
              ..color = p.tint(_quiet(e, 0.35))
              ..strokeWidth = math.max(2, dot * 0.5)
              ..strokeCap = StrokeCap.round);
        canvas.drawCircle(Offset(x0, y), dot,
            Paint()..color = p.tint(lit?.withValues(alpha: 0.5) ?? a));
        canvas.drawCircle(
            Offset(x1, y), dot, Paint()..color = p.tint(lit ?? b));
    }
    if (e.showValues && p.size > 0.9) {
      var right = x1 >= x0;
      _say(
          canvas,
          _num(e, v1, 1),
          _fig(e, right ? TextAlignSpec.left : TextAlignSpec.right),
          right
              ? Rect.fromLTWH(
                  x1 + dot + 3, y - rowH / 2, e.valueSpec.fontSize * 4, rowH)
              : Rect.fromLTWH(x1 - dot - 3 - e.valueSpec.fontSize * 4,
                  y - rowH / 2, e.valueSpec.fontSize * 4, rowH));
    }
  }
}

// ------------------------------------------------------------ waterfall

/// _isTotal is whether step [name] is a running total ("Total", "End",
/// "Subtotal") rather than a change.
bool _isTotal(String name) =>
    RegExp(r"total|^end$|^start$|balance", caseSensitive: false)
        .hasMatch(name.trim());

void _waterfall(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, String mode) {
  var d = e.data;
  // The steps: the first is where it starts, a total-named one is the
  // running total, and the end is added when it isn't there.
  var steps = <(String, double, double, bool)>[]; // name, from, to, total
  var acc = 0.0;
  for (var i = 0; i < d.categories.length; i++) {
    var v = _v(e, 0, i);
    if (v.isNaN) continue;
    var name = d.categories[i];
    if (steps.isEmpty) {
      steps.add((name, 0, v, true));
      acc = v;
    } else if (_isTotal(name)) {
      steps.add((name, 0, acc, true));
    } else {
      steps.add((name, acc, acc + v, false));
      acc += v;
    }
  }
  if (steps.isEmpty) return;
  if (!steps.last.$4) steps.add(("End", 0, acc, true));
  var lo = 0.0, hi = 0.0;
  for (var s in steps) {
    lo = math.min(lo, math.min(s.$2, s.$3));
    hi = math.max(hi, math.max(s.$2, s.$3));
  }
  if (hi - lo <= 0) return;
  var n = steps.length, fs = e.valueSpec.fontSize;
  var totalColour = _quiet(e, 0.55);
  Color colourOf(int i) {
    var s = steps[i];
    var c = s.$4 ? totalColour : (s.$3 >= s.$2 ? e.riseColor : e.fallColor);
    return i < d.categories.length ? _col(e, i, c) : c;
  }

  String says(int i) {
    var s = steps[i];
    if (s.$4) return _num(e, s.$3);
    var ch = s.$3 - s.$2;
    return "${ch >= 0 ? "+" : "−"}${_num(e, ch.abs())}";
  }

  if (mode == "down") {
    var nameW = _nameRoom(e, steps.map((s) => s.$1), area.width * 0.3);
    var plot = Rect.fromLTRB(
        area.left + nameW, area.top, area.right - fs * 3.5, area.bottom);
    double x(double v) => plot.left + (v - lo) / (hi - lo) * plot.width;
    var rowH = plot.height / n, bh = rowH * (1 - e.barGap.clamp(0.0, 0.9));
    for (var i = 0; i < n; i++) {
      var p = sliceProgress(e, reveal, i, n);
      if (p.gone) continue;
      var s = steps[i];
      var y = plot.top + rowH * i + (rowH - bh) / 2;
      var a = x(math.min(s.$2, s.$3)), b = x(math.max(s.$2, s.$3));
      var r = Rect.fromLTWH(a, y, (b - a) * p.size, bh);
      notePart(ChartPartKind.mark, r, series: 0, index: i);
      canvas.drawRect(r, Paint()..color = p.tint(colourOf(i)));
      if (e.showXLabels) {
        _say(canvas, s.$1, _lab(e, TextAlignSpec.right),
            Rect.fromLTRB(area.left, y, plot.left - 6, y + bh));
      }
      if (e.showValues && p.size > 0.9) {
        _say(canvas, says(i), _fig(e, TextAlignSpec.left),
            Rect.fromLTWH(r.right + 4, y, fs * 3.4, bh));
      }
    }
    return;
  }
  var labelH = e.showXLabels ? e.labelSpec.fontSize * 1.8 : 0.0;
  var plot = Rect.fromLTRB(
      area.left, area.top + fs * 1.5, area.right, area.bottom - labelH);
  double y(double v) => plot.bottom - (v - lo) / (hi - lo) * plot.height;
  var slot = plot.width / n, bw = slot * (1 - e.barGap.clamp(0.0, 0.9));
  var connector = Paint()
    ..color = _quiet(e, 0.45)
    ..strokeWidth = 1;
  for (var i = 0; i < n; i++) {
    var p = sliceProgress(e, reveal, i, n);
    if (p.gone) continue;
    var s = steps[i];
    var x = plot.left + slot * i + (slot - bw) / 2;
    var top = y(math.max(s.$2, s.$3)), bottom = y(math.min(s.$2, s.$3));
    var grow = (bottom - top) * p.size;
    // Down steps hang from their top; the rest stand on their bottom.
    var r = s.$3 >= s.$2 || s.$4
        ? Rect.fromLTRB(x, bottom - grow, x + bw, bottom)
        : Rect.fromLTRB(x, top, x + bw, top + grow);
    notePart(ChartPartKind.mark, r, series: 0, index: i);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            r, Radius.circular(math.min(e.barRadius, bw / 4))),
        Paint()..color = p.tint(colourOf(i)));
    if (p.size > 0.95 && i < n - 1) {
      var level = y(s.$3);
      canvas.drawLine(
          Offset(x + bw, level), Offset(x + slot, level), connector);
    }
    if (e.showValues && p.size > 0.9) {
      _say(
          canvas,
          says(i),
          _fig(e, TextAlignSpec.center),
          Rect.fromCenter(
              center: Offset(x + bw / 2, top - fs * 0.8),
              width: slot * 1.2,
              height: fs * 1.4));
    }
    if (e.showXLabels) {
      _say(canvas, s.$1, _lab(e, TextAlignSpec.center),
          Rect.fromLTWH(x - (slot - bw) / 2, plot.bottom + 2, slot, labelH));
    }
  }
  canvas.drawLine(
      Offset(plot.left, y(0)),
      Offset(plot.right, y(0)),
      Paint()
        ..color = e.axisColor
        ..strokeWidth = 1);
}

// ------------------------------------------------------------ heatmap

void _heatmap(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, String mode) {
  var d = e.data, n = d.categories.length, k = d.series.length;
  var hiC = d.series.first.color;
  var loC =
      Color.lerp(e.panel.a > 0 ? e.panel : const Color(0xFFF4F4F4), hiC, 0.08)!;
  if (mode == "stripes") {
    var vals = [for (var i = 0; i < n; i++) _v(e, 0, i)];
    var ok = vals.where((v) => !v.isNaN).toList();
    if (ok.isEmpty) return;
    var mean = ok.reduce((a, b) => a + b) / ok.length;
    var spread = ok.fold(0.0, (m, v) => math.max(m, (v - mean).abs()));
    var labelH = e.showXLabels ? e.labelSpec.fontSize * 1.8 : 0.0;
    var w = area.width / n;
    for (var i = 0; i < n; i++) {
      var v = vals[i];
      if (v.isNaN) continue;
      var p = sliceProgress(e, reveal, i, n);
      if (p.gone) continue;
      var f = spread <= 0 ? 0.0 : (v - mean) / spread;
      // Cool below the average, warm above (the warming stripes).
      var c = f >= 0
          ? _shade(const Color(0xFFFBE7DE), const Color(0xFFB2182B), f)
          : _shade(const Color(0xFFDDEBF6), const Color(0xFF2166AC), -f);
      var r = Rect.fromLTWH(area.left + w * i, area.top, w + 0.6,
          (area.height - labelH) * p.size);
      notePart(ChartPartKind.mark, r, series: 0, index: i);
      canvas.drawRect(r, Paint()..color = _col(e, i, c));
    }
    if (e.showXLabels) {
      _say(
          canvas,
          d.categories.first,
          _lab(e, TextAlignSpec.left),
          Rect.fromLTWH(
              area.left, area.bottom - labelH, area.width / 2, labelH));
      _say(
          canvas,
          d.categories.last,
          _lab(e, TextAlignSpec.right),
          Rect.fromLTWH(
              area.center.dx, area.bottom - labelH, area.width / 2, labelH));
    }
    return;
  }
  var all = [
    for (var s = 0; s < k; s++)
      for (var i = 0; i < n; i++) _v(e, s, i)
  ].where((v) => !v.isNaN).toList();
  if (all.isEmpty) return;
  var lo = all.reduce(math.min), hi = all.reduce(math.max);
  double f(double v) => hi - lo <= 0 ? 1 : (v - lo) / (hi - lo);
  if (mode == "calendar") {
    var rows = 7, cols = (n / rows).ceil();
    var cell = math.min(area.width / cols, area.height / rows);
    var gap = math.max(1.0, cell * 0.12);
    var left = area.left + (area.width - cell * cols) / 2;
    for (var i = 0; i < n; i++) {
      var v = _v(e, 0, i);
      var p = sliceProgress(e, reveal, i, n);
      if (p.gone) continue;
      var r = Rect.fromLTWH(left + (i ~/ rows) * cell,
          area.top + (i % rows) * cell, cell - gap, cell - gap);
      r = Rect.fromCenter(
          center: r.center,
          width: r.width * p.size.clamp(0.0, 1.0),
          height: r.height * p.size.clamp(0.0, 1.0));
      var c = v.isNaN ? _quiet(e, 0.08) : _shade(loC, hiC, f(v));
      notePart(ChartPartKind.mark, r, series: 0, index: i);
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(cell * 0.18)),
          Paint()..color = p.tint(_col(e, i, c)));
    }
    return;
  }
  // A grid: a row per category, a column per series.
  var headH = e.showXLabels ? e.labelSpec.fontSize * 1.8 : 0.0;
  var nameW = _nameRoom(e, d.categories, area.width * 0.3);
  var grid = Rect.fromLTRB(
      area.left + nameW, area.top + headH, area.right, area.bottom);
  var cw = grid.width / k, ch = grid.height / n;
  var gap = math.max(1.0, math.min(cw, ch) * 0.06);
  for (var s = 0; s < k; s++) {
    if (e.showXLabels) {
      _say(canvas, d.series[s].name, _lab(e, TextAlignSpec.center),
          Rect.fromLTWH(grid.left + cw * s, area.top, cw, headH));
    }
  }
  for (var i = 0; i < n; i++) {
    var p = sliceProgress(e, reveal, i, n);
    if (p.gone) continue;
    if (e.showXLabels) {
      _say(
          canvas,
          d.categories[i],
          _lab(e, TextAlignSpec.right),
          Rect.fromLTRB(area.left, grid.top + ch * i, grid.left - 6,
              grid.top + ch * (i + 1)));
    }
    for (var s = 0; s < k; s++) {
      var v = _v(e, s, i);
      var r = Rect.fromLTWH(grid.left + cw * s + gap / 2,
          grid.top + ch * i + gap / 2, cw - gap, ch - gap);
      // Each cell grows in from its middle as its row arrives.
      var grown = p.size.clamp(0.0, 1.0);
      r = Rect.fromCenter(
          center: r.center, width: r.width * grown, height: r.height * grown);
      var c = v.isNaN ? _quiet(e, 0.06) : _shade(loC, hiC, f(v));
      c = p.tint(
          i < d.categories.length && d.markAt(i) != null ? d.markAt(i)! : c);
      notePart(ChartPartKind.mark, r, series: s, index: i);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              r, Radius.circular(math.min(e.barRadius, ch / 3))),
          Paint()..color = c);
      if (e.showValues &&
          !v.isNaN &&
          p.size > 0.9 &&
          ch > e.valueSpec.fontSize * 1.2) {
        _say(canvas, _num(e, v, s),
            _fig(e, TextAlignSpec.center).copyWith(color: _ink(c)), r);
      }
    }
  }
}

// ------------------------------------------------------------ big number

void _bigNumber(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, String mode) {
  var d = e.data, n = d.categories.length;
  var head = e.titleSpec;
  var arrived = e.animation.on ? reveal.clamp(0.0, 1.0) : 1.0;
  if (mode == "tiles") {
    var tiles = math.min(4, n);
    var cols = tiles <= 2 ? tiles : 2, rows = (tiles / cols).ceil();
    var tw = area.width / cols, th = area.height / rows;
    for (var i = 0; i < tiles; i++) {
      var p = sliceProgress(e, reveal, i, tiles);
      if (p.gone) continue;
      var r = Rect.fromLTWH(
              area.left + tw * (i % cols), area.top + th * (i ~/ cols), tw, th)
          .deflate(4);
      notePart(ChartPartKind.mark, r, series: 0, index: i);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              r, Radius.circular(math.min(12, e.barRadius + 4))),
          Paint()..color = p.tint(_quiet(e, 0.08)));
      var v = _v(e, 0, i);
      _say(canvas, d.categories[i], _lab(e, TextAlignSpec.left),
          Rect.fromLTWH(r.left + 10, r.top + 6, r.width - 20, r.height * 0.3));
      _say(
          canvas,
          v.isNaN ? "–" : _num(e, v * p.size.clamp(0.0, 1.0)),
          head.copyWith(
              align: TextAlignSpec.left,
              verticalAlign: VerticalAlignSpec.middle,
              fontSize: math.min(r.height * 0.38, r.width / 4),
              color: _col(e, i, head.color)),
          Rect.fromLTWH(r.left + 10, r.top + r.height * 0.32, r.width - 20,
              r.height * 0.5));
      if (d.series.length > 1 && !_v(e, 1, i).isNaN) {
        var ch = _v(e, 1, i);
        _say(
            canvas,
            "${ch >= 0 ? "▲" : "▼"} ${_num(e, ch.abs(), 1)}",
            _fig(e, TextAlignSpec.right)
                .copyWith(color: ch >= 0 ? e.riseColor : e.fallColor),
            Rect.fromLTWH(r.left + 10, r.bottom - r.height * 0.28, r.width - 20,
                r.height * 0.24));
      }
    }
    return;
  }
  // The latest figure, large; what it is under it.
  var last = n - 1;
  while (last > 0 && _v(e, 0, last).isNaN) {
    last--;
  }
  var v = _v(e, 0, last);
  if (v.isNaN) return;
  var spark = mode == "spark" && n > 1;
  var delta = mode == "delta" && n > 1;
  var numberH = area.height *
      (spark
          ? 0.42
          : delta
              ? 0.5
              : 0.62);
  var numberBox = Rect.fromLTWH(area.left, area.top, area.width, numberH);
  // It grows as it counts up, arriving.
  var size = math.min(
          numberH * 0.9, area.width / math.max(3, _num(e, v).length * 0.62)) *
      (0.5 + 0.5 * arrived);
  notePart(ChartPartKind.mark, numberBox, series: 0, index: last);
  _say(
      canvas,
      _num(e, v * arrived),
      head.copyWith(
          align: TextAlignSpec.center,
          verticalAlign: VerticalAlignSpec.middle,
          fontSize: size,
          weight: 800,
          color: _col(e, last, head.color)),
      numberBox);
  var caption =
      d.series.first.name.isNotEmpty ? d.series.first.name : d.categories[last];
  var capH = e.labelSpec.fontSize * 2;
  var y = numberBox.bottom;
  if (e.showXLabels) {
    _say(
        canvas,
        caption,
        _lab(e, TextAlignSpec.center, e.labelSpec.fontSize * 1.15),
        Rect.fromLTWH(area.left, y, area.width, capH));
    y += capH;
  }
  if (delta) {
    var prev = _v(e, 0, last - 1);
    if (!prev.isNaN && prev != 0) {
      var ch = v - prev, pct = ch / prev.abs() * 100;
      _say(
          canvas,
          "${ch >= 0 ? "▲" : "▼"} ${pct.abs().toStringAsFixed(1)}% on ${d.categories[last - 1]}",
          _fig(e, TextAlignSpec.center, e.valueSpec.fontSize * 1.2).copyWith(
              color: ch >= 0 ? e.riseColor : e.fallColor, weight: 700),
          Rect.fromLTWH(area.left, y, area.width, capH * 1.1));
    }
  }
  if (spark) {
    var vals = [for (var i = 0; i < n; i++) _v(e, 0, i)];
    var ok = vals.where((x) => !x.isNaN).toList();
    var lo = ok.reduce(math.min), hi = ok.reduce(math.max);
    var box = Rect.fromLTRB(area.left + area.width * 0.18, y + 4,
        area.right - area.width * 0.18, area.bottom - 4);
    if (box.height < 8) return;
    var pts = <Offset>[
      for (var i = 0; i < n; i++)
        if (!vals[i].isNaN)
          Offset(
              box.left + box.width * i / (n - 1),
              box.bottom -
                  (hi - lo <= 0 ? 0.5 : (vals[i] - lo) / (hi - lo)) *
                      box.height)
    ];
    var shown = math.max(2, (pts.length * arrived).ceil());
    var path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var p in pts.take(shown).skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.6, e.strokeWidth * 0.8)
          ..color = d.series.first.color);
    canvas.drawCircle(pts[shown - 1], math.max(3, e.strokeWidth * 1.2),
        Paint()..color = d.series.first.color);
  }
}

// ------------------------------------------------------------ dot spread

void _beeswarm(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, String mode) {
  var d = e.data, n = d.categories.length, k = d.series.length;
  var all = [
    for (var s = 0; s < k; s++)
      for (var i = 0; i < n; i++) _v(e, s, i)
  ].where((v) => !v.isNaN).toList();
  if (all.isEmpty) return;
  var lo = all.reduce(math.min), hi = all.reduce(math.max);
  if (hi - lo <= 0) {
    lo -= 1;
    hi += 1;
  }
  var nameW = k > 1
      ? _nameRoom(e, d.series.map((s) => s.name), area.width * 0.25)
      : 0.0;
  var axisH = e.showYLabels ? e.labelSpec.fontSize * 1.8 : 0.0;
  // In from both edges by about a dot, so the end ones aren't cut.
  var plot = Rect.fromLTRB(
      area.left + nameW + 7, area.top, area.right - 7, area.bottom - axisH);
  double x(double v) => plot.left + (v - lo) / (hi - lo) * plot.width;
  var rowH = plot.height / k;
  var r = math.max(2.0, math.min(rowH / 9, plot.width / (n * 1.4 + 4)));
  // Small enough that the tallest pile of dots fits its row.
  for (var pass = 0; pass < 3; pass++) {
    var tallest = 1;
    for (var s = 0; s < k; s++) {
      var piles = <int, int>{};
      for (var i = 0; i < n; i++) {
        var v = _v(e, s, i);
        if (v.isNaN) continue;
        var b = (x(v) / (r * 2)).round();
        piles[b] = (piles[b] ?? 0) + 1;
      }
      for (var c in piles.values) {
        tallest = math.max(tallest, c);
      }
    }
    var fits = rowH / (tallest * 1.95 + 1);
    if (fits >= r) break;
    r = math.max(1.5, fits);
  }
  for (var s = 0; s < k; s++) {
    var cy = plot.top + rowH * (s + 0.5);
    if (k > 1 && e.showXLabels) {
      _say(
          canvas,
          d.series[s].name,
          _lab(e, TextAlignSpec.right),
          Rect.fromLTRB(
              area.left, cy - rowH / 2, plot.left - 6, cy + rowH / 2));
    }
    var placed = <Offset>[];
    for (var i = 0; i < n; i++) {
      var v = _v(e, s, i);
      if (v.isNaN) continue;
      var p = sliceProgress(e, reveal, i, n);
      if (p.gone) continue;
      var c = p.tint(_col(e, i,
          d.series[s].color.withValues(alpha: mode == "strip" ? 0.6 : 0.9)));
      var px = x(v);
      if (mode == "barcode") {
        var tick = Rect.fromLTWH(px - 1, cy - rowH * 0.32, 2, rowH * 0.64);
        notePart(ChartPartKind.mark, tick, series: s, index: i);
        canvas.drawRect(tick, Paint()..color = c);
        continue;
      }
      var py = cy;
      if (mode != "strip") {
        // Pushed up and down from the middle until it overlaps nothing.
        for (var step = 0; step < 60; step++) {
          var off = (step.isOdd ? 1 : -1) * ((step + 1) ~/ 2) * r * 1.9;
          var at = Offset(px, cy + off);
          if (placed.every((q) => (q - at).distance >= r * 2)) {
            py = cy + off;
            break;
          }
        }
      } else {
        py = cy + math.sin(i * 7.31) * rowH * 0.18;
      }
      var at = Offset(px, py - (1 - p.size.clamp(0.0, 1.0)) * rowH * 0.5);
      placed.add(Offset(px, py));
      notePart(ChartPartKind.mark, Rect.fromCircle(center: at, radius: r),
          series: s, index: i);
      canvas.drawCircle(at, r, Paint()..color = c);
    }
  }
  if (e.showYLabels) {
    var spec = _lab(e, TextAlignSpec.center);
    // The ends kept inside the box: the first written from its edge left,
    // the last right.
    var y0 = area.bottom - axisH;
    _say(canvas, _num(e, lo), spec.copyWith(align: TextAlignSpec.left),
        Rect.fromLTWH(plot.left, y0, 80, axisH));
    _say(
        canvas,
        _num(e, (lo + hi) / 2),
        spec,
        Rect.fromCenter(
            center: Offset(x((lo + hi) / 2), y0 + axisH / 2),
            width: 80,
            height: axisH));
    _say(canvas, _num(e, hi), spec.copyWith(align: TextAlignSpec.right),
        Rect.fromLTWH(plot.right - 80, y0, 80, axisH));
    canvas.drawLine(
        Offset(plot.left, plot.bottom),
        Offset(plot.right, plot.bottom),
        Paint()
          ..color = e.axisColor
          ..strokeWidth = 1);
  }
}

// ------------------------------------------------------------ parliament

void _parliament(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, String mode) {
  var d = e.data, n = d.categories.length;
  var seats = [
    for (var i = 0; i < n; i++)
      math.max(0, _v(e, 0, i).isNaN ? 0 : _v(e, 0, i).round())
  ];
  var total = seats.fold(0, (a, b) => a + b);
  if (total <= 0) return;
  var keyH = e.showLegend ? 0.0 : e.labelSpec.fontSize * 2.2;
  var outer = math.min(area.width / 2, (area.height - keyH) * 0.92);
  var centre =
      Offset(area.center.dx, area.top + (area.height - keyH + outer) / 2);
  var inner = outer * 0.38;
  if (mode == "wedges") {
    var a = math.pi;
    for (var i = 0; i < n; i++) {
      var sweep = math.pi * seats[i] / total;
      var p = sliceProgress(e, reveal, i, n);
      if (!p.gone && sweep > 0) {
        var path = Path()
          ..arcTo(Rect.fromCircle(center: centre, radius: outer), a,
              sweep * p.size, true)
          ..arcTo(Rect.fromCircle(center: centre, radius: inner),
              a + sweep * p.size, -sweep * p.size, false)
          ..close();
        notePart(ChartPartKind.mark, path.getBounds(),
            series: 0, index: i, path: path);
        canvas.drawPath(path, Paint()..color = p.tint(sliceColour(e, i)));
      }
      a += sweep;
    }
  } else {
    // Rows of seats, each row's share of the seats by its length.
    var rows = math.max(2, math.min(14, (math.sqrt(total / 2.6)).round()));
    var radii = [
      for (var r = 0; r < rows; r++) inner + (outer - inner) * (r + 0.5) / rows
    ];
    var lengths = radii.fold(0.0, (a, b) => a + b);
    var perRow = [for (var r in radii) (total * r / lengths).floor()];
    var short = total - perRow.fold(0, (a, b) => a + b);
    for (var r = rows - 1; short > 0; r = (r - 1 + rows) % rows, short--) {
      perRow[r]++;
    }
    var spots = <(double, Offset)>[];
    for (var r = 0; r < rows; r++) {
      var m = perRow[r];
      for (var j = 0; j < m; j++) {
        var a = math.pi + math.pi * (m == 1 ? 0.5 : j / (m - 1));
        spots.add((a, centre + Offset(math.cos(a), math.sin(a)) * radii[r]));
      }
    }
    spots.sort((a, b) => a.$1.compareTo(b.$1));
    var dot = (outer - inner) / rows * 0.4;
    var at = 0;
    for (var i = 0; i < n; i++) {
      var p = sliceProgress(e, reveal, i, n);
      var c = p.tint(sliceColour(e, i));
      var first = at;
      for (var j = 0; j < seats[i] && at < spots.length; j++, at++) {
        if (!p.gone) {
          canvas.drawCircle(
              spots[at].$2, dot * p.size.clamp(0.0, 1.0), Paint()..color = c);
        }
      }
      if (at > first) {
        var pts = spots.sublist(first, at).map((s) => s.$2);
        var box = pts.fold<Rect?>(
            null,
            (b, q) => b == null
                ? Rect.fromCircle(center: q, radius: dot)
                : b.expandToInclude(Rect.fromCircle(center: q, radius: dot)));
        if (box != null) notePart(ChartPartKind.mark, box, series: 0, index: i);
      }
    }
  }
  // The majority, and the whole house.
  var need = total ~/ 2 + 1;
  canvas.drawLine(
      centre - Offset(0, outer + 4),
      centre - Offset(0, inner - 4),
      Paint()
        ..color = e.axisColor
        ..strokeWidth = 1.4);
  _say(
      canvas,
      "$total",
      e.titleSpec.copyWith(
          align: TextAlignSpec.center,
          verticalAlign: VerticalAlignSpec.bottom,
          fontSize: inner * 0.5,
          weight: 800),
      Rect.fromCenter(
          center: centre - Offset(0, inner * 0.52),
          width: inner * 1.8,
          height: inner * 0.56));
  if (e.showValues) {
    // Under the total, inside the arch, clear of a title above.
    _say(
        canvas,
        "$need for a majority",
        _lab(e, TextAlignSpec.center,
            math.min(e.labelSpec.fontSize, inner * 0.2)),
        Rect.fromCenter(
            center: centre - Offset(0, inner * 0.06),
            width: inner * 1.9,
            height: e.labelSpec.fontSize * 1.6));
  }
  if (!e.showLegend && e.showXLabels) {
    // A key underneath: each party and its seats.
    var spec = _lab(e, TextAlignSpec.left);
    var x = area.left, y = area.bottom - keyH * 0.6;
    for (var i = 0; i < n; i++) {
      var text = "${d.categories[i]} ${seats[i]}";
      var w = _width(text, spec) + spec.fontSize * 1.8;
      if (x + w > area.right) break;
      canvas.drawCircle(Offset(x + spec.fontSize * 0.45, y),
          spec.fontSize * 0.4, Paint()..color = sliceColour(e, i));
      _say(
          canvas,
          text,
          spec,
          Rect.fromLTWH(x + spec.fontSize * 1.1, y - spec.fontSize, w,
              spec.fontSize * 2));
      x += w;
    }
  }
}

// ------------------------------------------------------------ tile map

void _tileMap(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, String mode) {
  var d = e.data, n = d.categories.length;
  var codes = [for (var c in d.categories) c.trim().toUpperCase()];
  // On a map -- the US, Europe, the UK -- when most are its places;
  // otherwise in a grid, in order.
  var map = tileMapOf(codes);
  var places = <(int, int)>[];
  if (map case (var tiles, var named)) {
    var spare = tiles.values.fold(0, (m, p) => math.max(m, p.$1)) + 1;
    for (var c in named) {
      places.add(tiles[c] ?? (spare, 0));
    }
  } else {
    var cols = math.max(
        1, math.sqrt(n * area.width / math.max(1, area.height)).ceil());
    for (var i = 0; i < n; i++) {
      places.add((i % cols, i ~/ cols));
    }
  }
  // On a map, the whole of it; else the places.
  var spread = [...places, ...?map?.$1.values];
  var cols = spread.fold(0, (m, p) => math.max(m, p.$1)) + 1;
  var rows = spread.fold(0, (m, p) => math.max(m, p.$2)) + 1;
  var cell = math.min(
      area.width / (cols + (mode == "hex" ? 0.5 : 0)), area.height / rows);
  var left = area.left + (area.width - cell * cols) / 2,
      top = area.top + (area.height - cell * rows) / 2;
  var vals = [for (var i = 0; i < n; i++) _v(e, 0, i)];
  var ok = vals.where((v) => !v.isNaN).toList();
  if (ok.isEmpty) return;
  var lo = ok.reduce(math.min), hi = ok.reduce(math.max);
  var hiC = d.series.first.color;
  var loC =
      Color.lerp(e.panel.a > 0 ? e.panel : const Color(0xFFF4F4F4), hiC, 0.1)!;
  // The rest of the map, faint, so its shape reads (on the Charts canvas,
  // twelve states floated in the empty).
  if (map case (var tiles, _)) {
    var taken = places.toSet();
    for (var t in tiles.values.toSet()) {
      if (taken.contains(t)) continue;
      var x = left + t.$1 * cell + (mode == "hex" && t.$2.isOdd ? cell / 2 : 0);
      var r =
          Rect.fromLTWH(x, top + t.$2 * cell, cell, cell).deflate(cell * 0.05);
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(cell * 0.12)),
          Paint()..color = Color.lerp(loC, hiC, 0.04)!.withValues(alpha: 0.7));
    }
  }
  for (var i = 0; i < n; i++) {
    var p = sliceProgress(e, reveal, i, n);
    if (p.gone) continue;
    var v = vals[i];
    var f = v.isNaN || hi - lo <= 0 ? 0.5 : (v - lo) / (hi - lo);
    var (cx, cy) = places[i];
    var x = left + cx * cell + (mode == "hex" && cy.isOdd ? cell / 2 : 0);
    var r = Rect.fromLTWH(x, top + cy * cell, cell, cell).deflate(cell * 0.05);
    var c = p.tint(_col(e, i, v.isNaN ? _quiet(e, 0.1) : _shade(loC, hiC, f)));
    notePart(ChartPartKind.mark, r, series: 0, index: i);
    switch (mode) {
      case "hex":
        var path = Path();
        for (var k = 0; k < 6; k++) {
          var a = math.pi / 6 + k * math.pi / 3;
          var q = r.center +
              Offset(math.cos(a), math.sin(a)) * r.width * 0.56 * p.size;
          k == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
        }
        canvas.drawPath(path..close(), Paint()..color = c);
      case "circles":
        canvas.drawRRect(
            RRect.fromRectAndRadius(r, Radius.circular(cell * 0.12)),
            Paint()..color = _quiet(e, 0.08));
        canvas.drawCircle(
            r.center,
            r.width * 0.48 * math.sqrt(f.clamp(0.05, 1)) * p.size,
            Paint()..color = _col(e, i, hiC));
      default:
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: r.center,
                    width: r.width * p.size,
                    height: r.height * p.size),
                Radius.circular(math.min(e.barRadius + 2, cell * 0.2))),
            Paint()..color = c);
    }
    var ink = mode == "circles" ? e.labelSpec.color : _ink(c);
    if (e.showXLabels) {
      _say(
          canvas,
          d.categories[i],
          _lab(e, TextAlignSpec.center,
                  math.min(e.labelSpec.fontSize, cell * 0.3))
              .copyWith(color: ink, weight: 700),
          Rect.fromLTWH(r.left, r.top + r.height * (e.showValues ? 0.12 : 0.25),
              r.width, r.height * 0.45));
    }
    if (e.showValues && !v.isNaN && mode != "circles") {
      _say(
          canvas,
          _num(e, v),
          _fig(e, TextAlignSpec.center,
                  math.min(e.valueSpec.fontSize, cell * 0.24))
              .copyWith(color: ink),
          Rect.fromLTWH(
              r.left, r.top + r.height * 0.52, r.width, r.height * 0.36));
    }
  }
}

// ------------------------------------------------------------ pyramid

void _pyramid(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, String mode) {
  var d = e.data, n = d.categories.length;
  if (d.series.length < 2) return;
  var butterfly = mode == "butterfly";
  var fs = e.labelSpec.fontSize;
  var headH = fs * 1.8;
  var mid = e.showXLabels
      ? _nameRoom(e, d.categories, area.width * 0.3) + fs
      : fs * 0.6;
  var valueW = butterfly && e.showValues ? e.valueSpec.fontSize * 3 : 0.0;
  var most = 0.0;
  for (var i = 0; i < n; i++) {
    for (var s = 0; s < 2; s++) {
      var v = _v(e, s, i);
      if (!v.isNaN) most = math.max(most, v.abs());
    }
  }
  if (most <= 0) return;
  var plot =
      Rect.fromLTRB(area.left, area.top + headH, area.right, area.bottom);
  var half = (plot.width - mid) / 2 - valueW;
  var cx = plot.center.dx;
  var rowH = plot.height / n;
  var bh = butterfly ? rowH * (1 - e.barGap.clamp(0.0, 0.9)) : rowH * 0.96;
  for (var s = 0; s < 2; s++) {
    _say(
        canvas,
        d.series[s].name,
        _lab(e, s == 0 ? TextAlignSpec.right : TextAlignSpec.left)
            .copyWith(color: d.series[s].color, weight: 700),
        s == 0
            ? Rect.fromLTWH(
                area.left, area.top, cx - mid / 2 - area.left, headH)
            : Rect.fromLTWH(
                cx + mid / 2, area.top, area.right - cx - mid / 2, headH));
  }
  for (var i = 0; i < n; i++) {
    var p = sliceProgress(e, reveal, i, n);
    if (p.gone) continue;
    var y = plot.top + rowH * i + (rowH - bh) / 2;
    for (var s = 0; s < 2; s++) {
      var v = _v(e, s, i);
      if (v.isNaN) continue;
      var w = v.abs() / most * half * p.size;
      var r = s == 0
          ? Rect.fromLTWH(cx - mid / 2 - w, y, w, bh)
          : Rect.fromLTWH(cx + mid / 2, y, w, bh);
      notePart(ChartPartKind.mark, r, series: s, index: i);
      canvas.drawRRect(
          RRect.fromRectAndRadius(r,
              Radius.circular(butterfly ? math.min(e.barRadius, bh / 2) : 0)),
          Paint()..color = p.tint(_col(e, i, d.series[s].color)));
      if (butterfly && e.showValues && p.size > 0.9) {
        _say(
            canvas,
            _num(e, v, s),
            _fig(e, s == 0 ? TextAlignSpec.right : TextAlignSpec.left),
            s == 0
                ? Rect.fromLTWH(r.left - valueW - 3, y, valueW, bh)
                : Rect.fromLTWH(r.right + 3, y, valueW, bh));
      }
    }
    if (e.showXLabels) {
      _say(canvas, d.categories[i], _lab(e, TextAlignSpec.center),
          Rect.fromLTWH(cx - mid / 2, y, mid, bh));
    }
  }
}
