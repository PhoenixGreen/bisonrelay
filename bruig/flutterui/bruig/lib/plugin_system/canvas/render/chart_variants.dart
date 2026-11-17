import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/render/chart_timelines.dart';
import 'package:bruig/plugin_system/canvas/render/label_placer.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/painting.dart';

// chart_variants.dart is the other ways the older kinds can be drawn: a
// funnel as bars, bubble rows and clusters, a timeline down the page, a
// gauge needle, pictogram rows, a market treemap, share bars, lollipops,
// slope ranks, radial rings and roses, radar and waffle dots. Each is a
// ChartDesign.mode; a kind's first way is its own painter.

/// paintVariant draws [e] its chosen way, answering whether it did (false:
/// its first way, which its own painter draws).
bool paintVariant(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var ways = chartModes[e.type.name];
  if (ways == null || e.data.series.isEmpty || e.data.categories.isEmpty) {
    return false;
  }
  var mode = modeOf(e.design, e.type.name);
  if (mode == ways.first.$1) return false;
  switch ((e.type, mode)) {
    case (ChartType.funnel, "bars" || "ghost"):
      _funnelBars(canvas, area, e, reveal, ghost: mode == "ghost");
    case (ChartType.bubbles, "row"):
      _bubbleRow(canvas, area, e, reveal);
    case (ChartType.bubbles, "clusters"):
      _bubbleClusters(canvas, area, e, reveal);
    case (ChartType.timeline, "down"):
      _timelineDown(canvas, area, e, reveal);
    case (ChartType.timeline, var way) when timelineWays.contains(way):
      paintTimelineWay(canvas, area, e, reveal, way);
    case (ChartType.gauge, "bands" || "dial"):
      _gaugeNeedle(canvas, area, e, reveal, dial: mode == "dial");
    case (ChartType.pictogram, "rows"):
      _pictoRows(canvas, area, e, reveal);
    case (ChartType.pictogram, "big"):
      _pictoBig(canvas, area, e, reveal);
    case (ChartType.treemap, "market"):
      _market(canvas, area, e, reveal);
    case (ChartType.shareBar, "middle"):
      _fromMiddle(canvas, area, e, reveal);
    case (ChartType.shareBar, "majority"):
      _shareMajority(canvas, area, e, reveal);
    case (ChartType.lollipop, "average" || "big"):
      _lollies(canvas, area, e, reveal, mode);
    case (ChartType.slope, "rank"):
      _slopeRank(canvas, area, e, reveal);
    case (ChartType.radialBar, "rings" || "bars" || "rose"):
      _radialWays(canvas, area, e, reveal, mode);
    case (ChartType.radar, "dots" || "compare"):
      _radarDots(canvas, area, e, reveal, compare: mode == "compare");
    case (ChartType.waffle, "dots" || "rising"):
      _waffleWays(canvas, area, e, reveal, mode);
    default:
      return false;
  }
  return true;
}

// ------------------------------------------------------------ shared bits

double _val(ChartElement e, int s, int i) =>
    s < e.data.series.length ? e.data.valueAt(s, i) : double.nan;

List<double> _vals(ChartElement e, [int s = 0]) => [
      for (var i = 0; i < e.data.categories.length; i++)
        _val(e, s, i).isNaN ? 0.0 : _val(e, s, i).abs()
    ];

Color _item(ChartElement e, int i) =>
    e.data.markAt(i) ??
    (i < e.sliceColors.length ? e.sliceColors[i] : e.data.series.first.color);

TextSpec _lab(ChartElement e, TextAlignSpec a, [double? size]) =>
    e.labelSpec.copyWith(
        align: a,
        verticalAlign: VerticalAlignSpec.middle,
        fontSize: size ?? e.labelSpec.fontSize);

TextSpec _fig(ChartElement e, TextAlignSpec a, [double? size]) =>
    e.valueSpec.copyWith(
        align: a,
        verticalAlign: VerticalAlignSpec.middle,
        fontSize: size ?? e.valueSpec.fontSize);

void _say(ui.Canvas canvas, String s, TextSpec spec, Rect box) {
  if (s.isEmpty || box.width <= 1 || box.height <= 1) return;
  paintTextInBox(canvas, s, spec, box);
}

String _num(ChartElement e, double v, [int s = 0]) => formatSeries(e, s, v);

Color _quiet(ChartElement e, [double a = 0.3]) =>
    e.labelSpec.color.withValues(alpha: a);

Color _ink(Color fill) => fill.computeLuminance() > 0.45
    ? const Color(0xFF1B1B1B)
    : const Color(0xFFFFFFFF);

double _names(ChartElement e, double cap) {
  if (!e.showXLabels) return 0;
  var spec = _lab(e, TextAlignSpec.right);
  var w = 0.0;
  for (var n in e.data.categories) {
    w = math.max(w, layoutText(n, spec, maxWidth: double.infinity).width);
  }
  return math.min(cap, w + spec.fontSize * 0.6);
}

// ------------------------------------------------------------ funnel

/// _funnelBars is each stage a bar from one edge, so lengths compare; the
/// share kept from the stage before beside it, or (ghost) the stage before
/// as a pale bar behind, so what was lost shows.
void _funnelBars(ui.Canvas canvas, Rect area, ChartElement e, double reveal,
    {required bool ghost}) {
  var v = _vals(e), n = v.length;
  var most = v.fold(0.0, math.max);
  if (most <= 0) return;
  var nameW = _names(e, area.width * 0.32);
  var fs = e.valueSpec.fontSize;
  var tail = fs * 6;
  var plot = Rect.fromLTRB(
      area.left + nameW, area.top, area.right - tail, area.bottom);
  var rowH = plot.height / n, bh = rowH * 0.62;
  for (var i = 0; i < n; i++) {
    var p = sliceProgress(e, reveal, i, n);
    if (p.gone) continue;
    var y = plot.top + rowH * i + (rowH - bh) / 2;
    if (ghost && i > 0) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(plot.left, y, plot.width * v[i - 1] / most, bh),
              Radius.circular(math.min(e.barRadius, bh / 2))),
          Paint()..color = _quiet(e, 0.14));
    }
    var r = Rect.fromLTWH(plot.left, y, plot.width * v[i] / most * p.size, bh);
    notePart(ChartPartKind.mark, r, series: 0, index: i);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            r, Radius.circular(math.min(e.barRadius, bh / 2))),
        Paint()..color = p.tint(_item(e, i)));
    if (e.showXLabels) {
      _say(canvas, e.data.categories[i], _lab(e, TextAlignSpec.right),
          Rect.fromLTRB(area.left, y, plot.left - 6, y + bh));
    }
    if (e.showValues && p.size > 0.9) {
      var kept =
          i > 0 && v[i - 1] > 0 ? " · ${(v[i] / v[i - 1] * 100).round()}%" : "";
      _say(canvas, "${_num(e, v[i])}$kept", _fig(e, TextAlignSpec.left),
          Rect.fromLTWH(r.right + 5, y, tail + plot.right - r.right - 5, bh));
    }
  }
}

// ------------------------------------------------------------ bubbles

/// bubblePack packs one circle a value, radius its square root, the largest
/// in the middle and each next as near as it goes without overlapping:
/// centres (null for nothing) and radii, unscaled, about the origin.
(List<Offset?>, List<double>) bubblePack(List<double> values) {
  var order = [for (var i = 0; i < values.length; i++) i]
    ..sort((a, b) => values[b].compareTo(values[a]));
  var r = [for (var v in values) math.sqrt(math.max(0, v))];
  var placed = <int, Offset>{};
  for (var i in order) {
    if (r[i] <= 0) continue;
    if (placed.isEmpty) {
      placed[i] = Offset.zero;
      continue;
    }
    Offset? best;
    for (var (j, c) in placed.entries.map((x) => (x.key, x.value))) {
      for (var a = 0; a < 72; a++) {
        var ang = a * math.pi / 36;
        var p = c + Offset(math.cos(ang), math.sin(ang)) * (r[j] + r[i] + 0.5);
        var clear = placed.entries
            .every((o) => (o.value - p).distance >= r[o.key] + r[i] + 0.01);
        if (clear && (best == null || p.distance < best.distance)) best = p;
      }
    }
    placed[i] = best ?? Offset(placed.length * r[i] * 2, 0);
  }
  return ([for (var i = 0; i < values.length; i++) placed[i]], r);
}

Rect bubbleBounds(List<Offset?> placed, List<double> r) =>
    [
      for (var i = 0; i < placed.length; i++)
        if (placed[i] != null) Rect.fromCircle(center: placed[i]!, radius: r[i])
    ].fold<Rect?>(null, (a, b) => a == null ? b : a.expandToInclude(b)) ??
    Rect.zero;

/// _bubbleClusters is the circles packed in a cluster a group, each named above
/// it, all on one scale so sizes compare. A group is the word in the column the
/// chart is coloured by; with none, each series is a group; with neither, one.
void _bubbleClusters(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var d = e.data, n = d.categories.length;
  // Each cluster: its name and its members as (category, series, value).
  var clusters = <(String, List<(int, int, double)>)>[];
  if (d.groups.any((g) => g.isNotEmpty)) {
    var v = _vals(e);
    var names = <String>[];
    for (var i = 0; i < n; i++) {
      if (!names.contains(d.groupAt(i))) names.add(d.groupAt(i));
    }
    for (var g in names) {
      clusters.add((
        g,
        [
          for (var i = 0; i < n; i++)
            if (d.groupAt(i) == g && v[i] > 0) (i, 0, v[i])
        ]
      ));
    }
  } else if (d.series.length > 1) {
    for (var s = 0; s < d.series.length; s++) {
      var v = _vals(e, s);
      clusters.add((
        d.series[s].name,
        [
          for (var i = 0; i < n; i++)
            if (v[i] > 0) (i, s, v[i])
        ]
      ));
    }
  } else {
    var v = _vals(e);
    clusters.add((
      "",
      [
        for (var i = 0; i < n; i++)
          if (v[i] > 0) (i, 0, v[i])
      ]
    ));
  }
  clusters.removeWhere((c) => c.$2.isEmpty);
  if (clusters.isEmpty) return;
  var packs = [
    for (var c in clusters) bubblePack([for (var m in c.$2) m.$3])
  ];
  var bounds = [for (var p in packs) bubbleBounds(p.$1, p.$2)];
  // Laid out in a row, or a grid past three; one scale for them all.
  var cols = clusters.length <= 3
      ? clusters.length
      : math.sqrt(clusters.length).ceil();
  var rows = (clusters.length / cols).ceil();
  var titleH =
      clusters.any((c) => c.$1.isNotEmpty) ? e.labelSpec.fontSize * 2 : 0.0;
  var gap = area.width * 0.03;
  var cellW = (area.width - gap * (cols - 1)) / cols;
  var cellH = area.height / rows;
  var k = double.infinity;
  for (var b in bounds) {
    if (b.width <= 0 || b.height <= 0) continue;
    k = math.min(k, math.min(cellW / b.width, (cellH - titleH) / b.height));
  }
  if (!k.isFinite || k <= 0) return;
  var total = clusters.fold(0, (a, c) => a + c.$2.length), at = 0;
  for (var (ci, c) in clusters.indexed) {
    var cell = Rect.fromLTWH(area.left + (ci % cols) * (cellW + gap),
        area.top + (ci ~/ cols) * cellH, cellW, cellH);
    var room =
        Rect.fromLTRB(cell.left, cell.top + titleH, cell.right, cell.bottom);
    var (placed, r) = packs[ci];
    var b = bounds[ci];
    if (c.$1.isNotEmpty && e.showXLabels) {
      _say(canvas, c.$1, _lab(e, TextAlignSpec.center).copyWith(weight: 700),
          Rect.fromLTWH(cell.left, cell.top, cell.width, titleH));
    }
    for (var (j, (i, s, v)) in c.$2.indexed) {
      var p = sliceProgress(e, reveal, at++, total);
      if (p.gone || placed[j] == null) continue;
      var centre = room.center + (placed[j]! - b.center) * k;
      var rad = r[j] * k;
      // A colour a group: the colour-by's own, else the series', else
      // the palette's in turn; alone, a colour each as packed bubbles.
      var fill = d.markAt(i) ??
          (d.series.length > 1
              ? d.series[s].color
              : clusters.length > 1
                  ? (ci < e.sliceColors.length
                      ? e.sliceColors[ci]
                      : chartPalette[ci % chartPalette.length])
                  : _item(e, i));
      notePart(ChartPartKind.mark, Rect.fromCircle(center: centre, radius: rad),
          series: s, index: i);
      canvas.drawCircle(
          centre, rad * p.size.clamp(0.0, 1.0), Paint()..color = p.tint(fill));
      if (p.size < 0.9 || rad < e.labelSpec.fontSize * 1.4) continue;
      // A name broken mid-word reads worse than none.
      var spec = _lab(e, TextAlignSpec.center);
      var fits = d.categories[i].split(RegExp(r"\s+")).every((w) =>
          layoutText(w, spec, maxWidth: double.infinity).width <= rad * 1.6);
      var lines = [
        if (e.showXLabels && fits) d.categories[i],
        if (e.showValues) _num(e, v, s),
      ].join("\n");
      _say(
          canvas,
          lines,
          _lab(e, TextAlignSpec.center).copyWith(color: _ink(fill)),
          Rect.fromCenter(center: centre, width: rad * 1.6, height: rad * 1.2));
    }
  }
}

/// _bubbleRow is the circles side by side on one floor, so sizes compare.
void _bubbleRow(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var v = _vals(e), n = v.length;
  var most = v.fold(0.0, math.max);
  if (most <= 0) return;
  var labelH = e.showXLabels ? e.labelSpec.fontSize * 1.8 : 0.0;
  var radii = [for (var x in v) math.sqrt(x / most)];
  var sum = radii.fold(0.0, (a, b) => a + b) * 2;
  var k = math.min((area.width - (n - 1) * 6) / math.max(1e-9, sum),
      (area.height - labelH) / 2);
  var x = area.left + (area.width - (sum * k + (n - 1) * 6)) / 2;
  var floor = area.bottom - labelH;
  for (var i = 0; i < n; i++) {
    var r = radii[i] * k;
    var p = sliceProgress(e, reveal, i, n);
    var c = Offset(x + r, floor - r);
    if (!p.gone) {
      notePart(ChartPartKind.mark, Rect.fromCircle(center: c, radius: r),
          series: 0, index: i);
      canvas.drawCircle(
          c, r * p.size.clamp(0.0, 1.0), Paint()..color = p.tint(_item(e, i)));
      if (e.showValues && r > e.valueSpec.fontSize * 1.1 && p.size > 0.9) {
        _say(
            canvas,
            _num(e, v[i]),
            _fig(e, TextAlignSpec.center).copyWith(color: _ink(_item(e, i))),
            Rect.fromCircle(center: c, radius: r));
      }
      if (e.showXLabels) {
        _say(
            canvas,
            e.data.categories[i],
            _lab(e, TextAlignSpec.center),
            Rect.fromCenter(
                center: Offset(c.dx, floor + labelH / 2),
                width: math.max(r * 2, 40),
                height: labelH));
      }
    }
    x += r * 2 + 6;
  }
}

// ------------------------------------------------------------ timeline

/// _timelineDown is the events down the page, a dot each on a line at the
/// left and its words beside it: for a long story or portrait video.
void _timelineDown(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var d = e.data, n = d.categories.length;
  var line = area.left + area.width * 0.08;
  var rowH = area.height / n;
  var p0 = e.animation.on ? reveal.clamp(0.0, 1.0) : 1.0;
  canvas.drawLine(
      Offset(line, area.top),
      Offset(line, area.top + area.height * p0),
      Paint()
        ..color = _quiet(e, 0.5)
        ..strokeWidth = 2);
  for (var i = 0; i < n; i++) {
    var p = sliceProgress(e, reveal, i, n);
    if (p.gone) continue;
    var y = area.top + rowH * (i + 0.5);
    var dot = math.min(rowH * 0.18, 8.0);
    canvas.drawCircle(Offset(line, y), dot * p.size.clamp(0.0, 1.0),
        Paint()..color = p.tint(_item(e, i)));
    var box = Rect.fromLTWH(
        line + dot * 2.5, y - rowH / 2, area.right - line - dot * 2.5, rowH);
    notePart(ChartPartKind.mark, box, series: 0, index: i);
    var v = _val(e, 0, i);
    var when = v.isNaN ? "" : _num(e, v);
    _say(
        canvas,
        when,
        _fig(e, TextAlignSpec.left, e.valueSpec.fontSize * 1.2)
            .copyWith(weight: 800, color: p.tint(_item(e, i))),
        Rect.fromLTWH(box.left, box.top, box.width, rowH * 0.5));
    _say(canvas, d.categories[i], _lab(e, TextAlignSpec.left),
        Rect.fromLTWH(box.left, box.top + rowH * 0.45, box.width, rowH * 0.45));
  }
}

// ------------------------------------------------------------ gauge

/// _gaugeNeedle is a needle over graduated bands (darker is worse), or a
/// ticked dial open at the bottom: the first value as a share, as _gauge.
void _gaugeNeedle(ui.Canvas canvas, Rect area, ChartElement e, double reveal,
    {required bool dial}) {
  var v = _vals(e);
  // Its top as the dial's: the axis's top where set, else the values'
  // total where there are several, else a hundred.
  var total = e.yMax.isFinite && e.yMax > 0
      ? e.yMax
      : v.length > 1
          ? v.fold(0.0, (a, b) => a + b)
          : 100.0;
  if (total <= 0) return;
  var share = (v.first / total).clamp(0.0, 1.0) *
      (e.animation.on ? reveal.clamp(0.0, 1.0) : 1.0);
  var sweep = dial ? math.pi * 1.5 : math.pi;
  var start = dial ? math.pi * 0.75 : math.pi;
  // Bands: the arch standing on room below its hub for the figure.
  var r = dial
      ? math.min(area.width, area.height) * 0.44
      : math.min(area.width / 2, area.height * 0.72) * 0.92;
  var c = dial
      ? area.center
      : Offset(area.center.dx, area.top + (area.height - r * 0.36 + r) / 2);
  var thick = r * 0.2;
  var arc = Rect.fromCircle(center: c, radius: r - thick / 2);
  if (dial) {
    canvas.drawArc(
        arc,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = thick * 0.35
          ..color = _quiet(e, 0.2));
    for (var t = 0; t <= 10; t++) {
      var a = start + sweep * t / 10;
      var dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
          c + dir * (r * (t % 5 == 0 ? 0.78 : 0.84)),
          c + dir * r * 0.9,
          Paint()
            ..color = _quiet(e, 0.7)
            ..strokeWidth = t % 5 == 0 ? 2 : 1);
    }
  } else {
    var shades = [0.18, 0.32, 0.5];
    for (var b = 0; b < 3; b++) {
      canvas.drawArc(
          arc,
          start + sweep * b / 3,
          sweep / 3,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = thick
            ..color = _quiet(e, shades[b]));
    }
  }
  var a = start + sweep * share;
  var tip = c + Offset(math.cos(a), math.sin(a)) * r * 0.86;
  var colour = _item(e, 0);
  canvas.drawLine(
      c,
      tip,
      Paint()
        ..color = colour
        ..strokeWidth = math.max(2.5, r * 0.035)
        ..strokeCap = StrokeCap.round);
  canvas.drawCircle(c, r * 0.06, Paint()..color = colour);
  notePart(ChartPartKind.mark, Rect.fromCircle(center: c, radius: r),
      series: 0, index: 0);
  if (e.showValues) {
    _say(
        canvas,
        "${(share * 100).round()}%",
        e.titleSpec.copyWith(
            align: TextAlignSpec.center,
            verticalAlign: VerticalAlignSpec.middle,
            fontSize: r * 0.28,
            weight: 800),
        Rect.fromCenter(
            center: c + Offset(0, dial ? r * 0.42 : r * 0.24),
            width: r * 1.2,
            height: r * 0.36));
  }
}

// ------------------------------------------------------------ pictogram

Path _person(Rect b) {
  var w = b.width, h = b.height;
  return Path()
    ..addOval(Rect.fromCircle(
        center: Offset(b.center.dx, b.top + h * 0.2), radius: w * 0.2))
    ..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(b.left + w * 0.18, b.top + h * 0.44, w * 0.64, h * 0.56),
        topLeft: Radius.circular(w * 0.3),
        topRight: Radius.circular(w * 0.3)));
}

/// _pictoRows is a row of icons per category, a icon a unit, so the rows'
/// lengths compare like bars (Isotype).
void _pictoRows(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var v = _vals(e), n = v.length;
  var most = v.fold(0.0, math.max);
  if (most <= 0) return;
  var nameW = _names(e, area.width * 0.3);
  var rowH = area.height / n;
  var per = math.max(1, (most / 20).ceil());
  var size = math.min(rowH * 0.78,
      (area.width - nameW - e.valueSpec.fontSize * 4) / (most / per + 1));
  for (var i = 0; i < n; i++) {
    var p = sliceProgress(e, reveal, i, n);
    if (p.gone) continue;
    var y = area.top + rowH * i + (rowH - size) / 2;
    var count = (v[i] / per * p.size).round();
    for (var k = 0; k < count; k++) {
      canvas.drawPath(
          _person(Rect.fromLTWH(
              area.left + nameW + k * size * 1.05, y, size, size)),
          Paint()..color = _item(e, i));
    }
    notePart(ChartPartKind.mark,
        Rect.fromLTWH(area.left + nameW, y, count * size * 1.05, size),
        series: 0, index: i);
    if (e.showXLabels) {
      _say(canvas, e.data.categories[i], _lab(e, TextAlignSpec.right),
          Rect.fromLTRB(area.left, y, area.left + nameW - 6, y + size));
    }
    if (e.showValues) {
      _say(
          canvas,
          _num(e, v[i]),
          _fig(e, TextAlignSpec.left),
          Rect.fromLTWH(area.left + nameW + count * size * 1.05 + 4, y,
              e.valueSpec.fontSize * 4, size));
    }
  }
}

/// _pictoBig is one large figure filled to the first share, as a glass fills.
void _pictoBig(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var v = _vals(e);
  var total = v.fold(0.0, (a, b) => a + b);
  if (total <= 0) return;
  var share =
      (v.first / total) * (e.animation.on ? reveal.clamp(0.0, 1.0) : 1.0);
  var h = area.height * 0.96, w = h * 0.62;
  var box = Rect.fromLTWH(
      area.left + area.width * 0.12, area.top + (area.height - h) / 2, w, h);
  var shape = _person(box);
  canvas.drawPath(shape, Paint()..color = _quiet(e, 0.16));
  canvas.save();
  canvas.clipRect(
      Rect.fromLTRB(box.left, box.bottom - h * share, box.right, box.bottom));
  canvas.drawPath(shape, Paint()..color = _item(e, 0));
  canvas.restore();
  notePart(ChartPartKind.mark, box, series: 0, index: 0);
  var text = Rect.fromLTRB(
      box.right + area.width * 0.06, area.top, area.right, area.bottom);
  _say(
      canvas,
      "${(share * 100).round()}%",
      e.titleSpec.copyWith(
          align: TextAlignSpec.left,
          verticalAlign: VerticalAlignSpec.bottom,
          fontSize: math.min(text.width / 3, area.height * 0.3),
          weight: 800,
          color: _item(e, 0)),
      Rect.fromLTWH(text.left, text.top, text.width, text.height * 0.55));
  if (e.showXLabels) {
    _say(
        canvas,
        e.data.categories.first,
        _lab(e, TextAlignSpec.left, e.labelSpec.fontSize * 1.2),
        Rect.fromLTWH(text.left, text.top + text.height * 0.56, text.width,
            text.height * 0.2));
  }
}

// ------------------------------------------------------------ treemap

/// _market is a market map: tiles sized by the first series, coloured by
/// the second's sign (rise or fall), stronger the bigger the change.
void _market(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var v = _vals(e), n = v.length;
  var change = [
    for (var i = 0; i < n; i++) _val(e, e.data.series.length > 1 ? 1 : 0, i)
  ];
  var spread = change.fold(0.0, (m, c) => c.isNaN ? m : math.max(m, c.abs()));
  var order = [for (var i = 0; i < n; i++) i]
    ..sort((a, b) => v[b].compareTo(v[a]));
  var total = v.fold(0.0, (a, b) => a + b);
  if (total <= 0) return;
  // Slice and dice, alternating, largest first.
  var r = area;
  var left = total;
  for (var (k, i) in order.indexed) {
    var f = left <= 0 ? 1.0 : v[i] / left;
    var across = k.isEven;
    var tile = across
        ? Rect.fromLTWH(r.left, r.top, r.width * f, r.height)
        : Rect.fromLTWH(r.left, r.top, r.width, r.height * f);
    r = across
        ? Rect.fromLTRB(tile.right, r.top, r.right, r.bottom)
        : Rect.fromLTRB(r.left, tile.bottom, r.right, r.bottom);
    left -= v[i];
    var p = sliceProgress(e, reveal, i, n);
    if (p.gone) continue;
    var c = change[i];
    var strength =
        spread <= 0 || c.isNaN ? 0.3 : 0.35 + 0.65 * c.abs() / spread;
    var base = c.isNaN || c == 0
        ? _quiet(e, 0.4)
        : (c > 0 ? e.riseColor : e.fallColor);
    var fill = e.data.markAt(i) ?? base.withValues(alpha: strength);
    var shown = Rect.fromCenter(
        center: tile.center,
        width: (tile.width - 2) * p.size,
        height: (tile.height - 2) * p.size);
    notePart(ChartPartKind.mark, tile, series: 0, index: i);
    canvas.drawRect(shown, Paint()..color = fill);
    if (tile.width > 40 && tile.height > 22 && p.size > 0.9) {
      var ink = _ink(Color.alphaBlend(
          fill, e.panel.a > 0 ? e.panel : const Color(0xFFFFFFFF)));
      // Its name smaller where it won't go across the tile, and left out
      // where even that won't do: never broken mid-word.
      var spec = _lab(e, TextAlignSpec.left).copyWith(color: ink, weight: 700);
      // On one line, over the change written under it.
      var wide = labelSize(e.data.categories[i], spec).width;
      var room = tile.width - 12;
      var k = wide <= room ? 1.0 : room / wide;
      if (k >= 0.55) {
        _say(
            canvas,
            e.data.categories[i],
            spec.copyWith(fontSize: spec.fontSize * k),
            Rect.fromLTWH(tile.left + 6, tile.top + 4, room + 2,
                e.labelSpec.fontSize * 1.6));
      }
      if (!c.isNaN) {
        _say(
            canvas,
            "${c > 0 ? "+" : ""}${_num(e, c, 1)}",
            _fig(e, TextAlignSpec.left).copyWith(color: ink),
            Rect.fromLTWH(
                tile.left + 6,
                tile.top + 4 + e.labelSpec.fontSize * 1.5,
                tile.width - 12,
                e.valueSpec.fontSize * 1.6));
      }
    }
  }
}

// ------------------------------------------------------------ share bar

/// _fromMiddle is two sides growing out from a centre line (the first half
/// of the shares one way, the rest the other): a tug of war.
void _fromMiddle(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var v = _vals(e), n = v.length;
  var total = v.fold(0.0, (a, b) => a + b);
  if (total <= 0) return;
  var p0 = e.animation.on ? reveal.clamp(0.0, 1.0) : 1.0;
  var bh = math.min(area.height * 0.34, 80.0);
  var y = area.center.dy - bh / 2;
  var mid = area.center.dx;
  var half = (n / 2).ceil();
  // Scaled so the longer side fits its half of the box.
  var leftSum = v.take(half).fold(0.0, (a, b) => a + b);
  var rightSum = v.skip(half).fold(0.0, (a, b) => a + b);
  var scale =
      (area.width / 2 - 4) / math.max(1e-9, math.max(leftSum, rightSum));
  var leftX = mid, rightX = mid;
  for (var i = 0; i < n; i++) {
    var w = v[i] * scale * p0;
    var r = i < half
        ? Rect.fromLTWH(leftX - w, y, w, bh)
        : Rect.fromLTWH(rightX, y, w, bh);
    if (i < half) {
      leftX -= w;
    } else {
      rightX += w;
    }
    notePart(ChartPartKind.mark, r, series: 0, index: i);
    canvas.drawRect(r, Paint()..color = _item(e, i));
    if (e.showValues && r.width > e.valueSpec.fontSize * 2.6) {
      _say(canvas, "${(v[i] / total * 100).round()}%",
          _fig(e, TextAlignSpec.center).copyWith(color: _ink(_item(e, i))), r);
    }
    if (e.showXLabels && r.width > 30) {
      _say(
          canvas,
          e.data.categories[i],
          _lab(e, TextAlignSpec.center),
          Rect.fromLTWH(r.left, y - e.labelSpec.fontSize * 1.8, r.width,
              e.labelSpec.fontSize * 1.6));
    }
  }
  canvas.drawLine(
      Offset(mid, y - 8),
      Offset(mid, y + bh + 8),
      Paint()
        ..color = e.axisColor
        ..strokeWidth = 2);
}

/// _shareMajority is the shares in one bar with a line at the halfway
/// mark, and how many make a majority under it (an election).
void _shareMajority(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var v = _vals(e), n = v.length;
  var total = v.fold(0.0, (a, b) => a + b);
  if (total <= 0) return;
  var bh = math.min(area.height * 0.32, 72.0);
  var y = area.center.dy - bh / 2;
  var x = area.left;
  for (var i = 0; i < n; i++) {
    var p = sliceProgress(e, reveal, i, n);
    var w = area.width * v[i] / total;
    var r = Rect.fromLTWH(x, y, w * (p.gone ? 0 : p.size.clamp(0.0, 1.0)), bh);
    notePart(ChartPartKind.mark, Rect.fromLTWH(x, y, w, bh),
        series: 0, index: i);
    canvas.drawRect(r, Paint()..color = p.tint(_item(e, i)));
    if (e.showValues && w > e.valueSpec.fontSize * 2.2) {
      _say(
          canvas,
          _num(e, v[i]),
          _fig(e, TextAlignSpec.center).copyWith(color: _ink(_item(e, i))),
          Rect.fromLTWH(x, y, w, bh));
    }
    if (e.showXLabels && w > 34) {
      _say(
          canvas,
          e.data.categories[i],
          _lab(e, TextAlignSpec.center),
          Rect.fromLTWH(x, y - e.labelSpec.fontSize * 1.8, w,
              e.labelSpec.fontSize * 1.6));
    }
    x += w;
  }
  var mid = area.center.dx;
  canvas.drawLine(
      Offset(mid, y - 6),
      Offset(mid, y + bh + 6),
      Paint()
        ..color = e.labelSpec.color
        ..strokeWidth = 2);
  var need = (total / 2).floor() + 1;
  _say(
      canvas,
      "$need for a majority",
      _lab(e, TextAlignSpec.center),
      Rect.fromLTWH(
          area.left, y + bh + 8, area.width, e.labelSpec.fontSize * 1.8));
}

// ------------------------------------------------------------ lollipop

/// _lollies is lollipops from the average (out either side, rise and fall
/// colours) or with the value written in a large dot.
void _lollies(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, String mode) {
  var d = e.data, n = d.categories.length;
  var v = [for (var i = 0; i < n; i++) _val(e, 0, i)];
  var ok = v.where((x) => !x.isNaN).toList();
  if (ok.isEmpty) return;
  var avg = ok.reduce((a, b) => a + b) / ok.length;
  var big = mode == "big";
  var nameW = _names(e, area.width * 0.3);
  var plot =
      Rect.fromLTRB(area.left + nameW, area.top, area.right - 8, area.bottom);
  var rowH = plot.height / n;
  var dot = big ? math.min(rowH * 0.42, 22.0) : math.min(rowH * 0.2, 7.0);
  var lo = big ? 0.0 : ok.reduce(math.min), hi = ok.reduce(math.max);
  if (!big) {
    var pad = (hi - lo) * 0.1 + 1e-9;
    lo -= pad;
    hi += pad;
  }
  double x(double t) =>
      plot.left + dot + (t - lo) / (hi - lo) * (plot.width - dot * 2);
  var from = big ? x(lo) : x(avg);
  if (!big) {
    canvas.drawLine(
        Offset(from, plot.top),
        Offset(from, plot.bottom),
        Paint()
          ..color = _quiet(e, 0.6)
          ..strokeWidth = 1);
  }
  for (var i = 0; i < n; i++) {
    if (v[i].isNaN) continue;
    var p = sliceProgress(e, reveal, i, n);
    if (p.gone) continue;
    var y = plot.top + rowH * (i + 0.5);
    var to = from + (x(v[i]) - from) * p.size;
    var c = p.tint(d.markAt(i) ??
        (big
            ? d.series.first.color
            : (v[i] >= avg ? e.riseColor : e.fallColor)));
    canvas.drawLine(
        Offset(from, y),
        Offset(to, y),
        Paint()
          ..color = c
          ..strokeWidth = big ? 3 : 2);
    canvas.drawCircle(Offset(to, y), dot, Paint()..color = c);
    notePart(
        ChartPartKind.mark, Rect.fromCircle(center: Offset(to, y), radius: dot),
        series: 0, index: i);
    if (e.showValues && p.size > 0.9) {
      if (big) {
        _say(
            canvas,
            _num(e, v[i]),
            _fig(e, TextAlignSpec.center, dot * 0.7)
                .copyWith(color: _ink(c), weight: 800),
            Rect.fromCircle(center: Offset(to, y), radius: dot));
      } else {
        var right = v[i] >= avg;
        _say(
            canvas,
            _num(e, v[i]),
            _fig(e, right ? TextAlignSpec.left : TextAlignSpec.right),
            right
                ? Rect.fromLTWH(to + dot + 3, y - rowH / 2, 60, rowH)
                : Rect.fromLTWH(to - dot - 63, y - rowH / 2, 60, rowH));
      }
    }
    if (e.showXLabels) {
      _say(canvas, d.categories[i], _lab(e, TextAlignSpec.right),
          Rect.fromLTRB(area.left, y - rowH / 2, plot.left - 6, y + rowH / 2));
    }
  }
}

// ------------------------------------------------------------ slope

/// _slopeRank is each one from its start place to its end place, named.
void _slopeRank(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var d = e.data, n = d.categories.length;
  if (d.series.length < 2) return;
  List<int> places(int s) {
    var order = [for (var i = 0; i < n; i++) i]
      ..sort((a, b) => _val(e, s, b).compareTo(_val(e, s, a)));
    var at = List.filled(n, 0);
    for (var (k, i) in order.indexed) {
      at[i] = k;
    }
    return at;
  }

  var a = places(0), b = places(1);
  var nameW = math.min(area.width * 0.32,
      _names(e, area.width * 0.32) + e.labelSpec.fontSize * 2);
  var x0 = area.left + nameW, x1 = area.right - nameW;
  var head = e.labelSpec.fontSize * 1.8;
  var rowH = (area.height - head) / n;
  double y(int place) => area.top + head + rowH * (place + 0.5);
  _say(
      canvas,
      d.series[0].name,
      _lab(e, TextAlignSpec.center).copyWith(weight: 700),
      Rect.fromCenter(
          center: Offset(x0, area.top + head / 2),
          width: nameW * 1.6,
          height: head));
  _say(
      canvas,
      d.series[1].name,
      _lab(e, TextAlignSpec.center).copyWith(weight: 700),
      Rect.fromCenter(
          center: Offset(x1, area.top + head / 2),
          width: nameW * 1.6,
          height: head));
  var p0 = e.animation.on ? reveal.clamp(0.0, 1.0) : 1.0;
  for (var i = 0; i < n; i++) {
    var c = d.markAt(i) ??
        (b[i] < a[i]
            ? e.riseColor
            : b[i] > a[i]
                ? e.fallColor
                : _quiet(e, 0.6));
    var from = Offset(x0, y(a[i])), to = Offset(x1, y(b[i]));
    var tip = Offset.lerp(from, to, p0)!;
    canvas.drawLine(
        from,
        tip,
        Paint()
          ..color = c
          ..strokeWidth = 2.2);
    canvas.drawCircle(from, 4, Paint()..color = c);
    if (p0 >= 1) canvas.drawCircle(to, 4, Paint()..color = c);
    notePart(ChartPartKind.mark, Rect.fromPoints(from, to).inflate(4),
        series: 1, index: i);
    _say(
        canvas,
        "${d.categories[i]}  ${a[i] + 1}",
        _lab(e, TextAlignSpec.right),
        Rect.fromLTRB(
            area.left, from.dy - rowH / 2, x0 - 8, from.dy + rowH / 2));
    if (p0 >= 1) {
      _say(
          canvas,
          "${b[i] + 1}  ${d.categories[i]}",
          _lab(e, TextAlignSpec.left).copyWith(color: c),
          Rect.fromLTRB(
              x1 + 8, to.dy - rowH / 2, area.right, to.dy + rowH / 2));
    }
  }
}

// ------------------------------------------------------------ radial

/// _radialWays is radial bars as full rings on pale tracks (activity
/// rings); bars standing out from a centre circle; or a rose, a wedge per
/// category with its area matching its value.
void _radialWays(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, String mode) {
  var v = _vals(e), n = v.length;
  var most = v.fold(0.0, math.max);
  if (most <= 0) return;
  if (e.yMax.isFinite && e.yMax > 0) most = e.yMax;
  var c = area.center;
  var R = math.min(area.width, area.height) * 0.46;
  if (mode == "rings") {
    var ring = R * 0.62 / n;
    for (var i = 0; i < n; i++) {
      var p = sliceProgress(e, reveal, i, n);
      var r = R - ring * i - ring / 2;
      var track = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring * 0.72
        ..color = _quiet(e, 0.14);
      canvas.drawCircle(c, r, track);
      if (p.gone) continue;
      var sweep = math.pi * 2 * (v[i] / most).clamp(0.0, 1.0) * p.size;
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: r),
          -math.pi / 2,
          sweep,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = ring * 0.72
            ..strokeCap = StrokeCap.round
            ..color = p.tint(_item(e, i)));
      notePart(
          ChartPartKind.mark, Rect.fromCircle(center: c, radius: r + ring / 2),
          series: 0, index: i);
      if (e.showXLabels) {
        _say(
            canvas,
            e.data.categories[i],
            _lab(e, TextAlignSpec.right,
                math.min(e.labelSpec.fontSize, ring * 0.6)),
            Rect.fromLTRB(
                area.left, c.dy - r - ring / 2, c.dx - 6, c.dy - r + ring / 2));
      }
    }
    return;
  }
  var inner = mode == "rose" ? R * 0.08 : R * 0.32;
  for (var i = 0; i < n; i++) {
    var p = sliceProgress(e, reveal, i, n);
    if (p.gone) continue;
    var share = mode == "rose" ? math.sqrt(v[i] / most) : v[i] / most;
    var r = inner + (R * 0.86 - inner) * share * p.size;
    var gap = mode == "rose" ? 0.02 : 0.08;
    var a0 = -math.pi / 2 + math.pi * 2 * i / n + gap,
        a1 = -math.pi / 2 + math.pi * 2 * (i + 1) / n - gap;
    var path = Path()
      ..arcTo(Rect.fromCircle(center: c, radius: r), a0, a1 - a0, true)
      ..arcTo(Rect.fromCircle(center: c, radius: inner), a1, a0 - a1, false)
      ..close();
    notePart(ChartPartKind.mark, path.getBounds(),
        series: 0, index: i, path: path);
    canvas.drawPath(
        path,
        Paint()
          ..color = p.tint(mode == "rose"
              ? (e.data.markAt(i) ??
                  e.data.series.first.color
                      .withValues(alpha: 0.5 + 0.5 * share))
              : _item(e, i)));
    if (e.showXLabels && p.size > 0.9) {
      var mid = (a0 + a1) / 2;
      _say(
          canvas,
          e.data.categories[i],
          _lab(e, TextAlignSpec.center, e.labelSpec.fontSize * 0.85),
          Rect.fromCenter(
              center: c +
                  Offset(math.cos(mid), math.sin(mid)) *
                      (r + e.labelSpec.fontSize * 1.2),
              width: 80,
              height: e.labelSpec.fontSize * 1.6));
    }
  }
}

// ------------------------------------------------------------ radar

/// _radarDots is each series' values as dots on the spokes, joined by thin
/// lines, with no filled area to exaggerate the differences; or, with
/// [compare], the first series filled and the others grey outlines behind.
void _radarDots(ui.Canvas canvas, Rect area, ChartElement e, double reveal,
    {bool compare = false}) {
  var d = e.data, n = d.categories.length;
  if (n < 3) return;
  var c = area.center;
  var R = math.min(area.width, area.height) * 0.38;
  var most = 0.0;
  for (var s = 0; s < d.series.length; s++) {
    for (var v in _vals(e, s)) {
      most = math.max(most, v);
    }
  }
  if (most <= 0) return;
  Offset at(int i, double f) {
    var a = -math.pi / 2 + math.pi * 2 * i / n;
    return c + Offset(math.cos(a), math.sin(a)) * R * f;
  }

  var grid = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = e.gridColor;
  for (var lv = 1; lv <= 4; lv++) {
    var path = Path()..moveTo(at(0, lv / 4).dx, at(0, lv / 4).dy);
    for (var i = 1; i <= n; i++) {
      path.lineTo(at(i % n, lv / 4).dx, at(i % n, lv / 4).dy);
    }
    canvas.drawPath(path, grid);
  }
  for (var i = 0; i < n; i++) {
    canvas.drawLine(c, at(i, 1), grid);
    if (e.showXLabels) {
      _say(
          canvas,
          d.categories[i],
          _lab(e, TextAlignSpec.center, e.labelSpec.fontSize * 0.9),
          Rect.fromCenter(
              center: at(i, 1.18),
              width: 90,
              height: e.labelSpec.fontSize * 1.8));
    }
  }
  var p0 = e.animation.on ? reveal.clamp(0.0, 1.0) : 1.0;
  // Compared, the others first so the subject lies over them.
  var order = [
    for (var s = d.series.length - 1; s >= 0; s--)
      if (compare) s,
    for (var s = 0; s < d.series.length; s++)
      if (!compare) s,
  ];
  for (var s in order) {
    var col = d.series[s].color;
    var vs = _vals(e, s);
    var pts = [for (var i = 0; i < n; i++) at(i, vs[i] / most * p0)];
    var path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var q in pts.skip(1)) {
      path.lineTo(q.dx, q.dy);
    }
    path.close();
    if (compare) {
      var subject = s == 0;
      var line = subject ? col : _quiet(e, 0.6);
      if (subject) {
        canvas.drawPath(path, Paint()..color = col.withValues(alpha: 0.25));
      }
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = subject ? 2.5 : 1.5
            ..color = line);
      for (var (i, q) in pts.indexed) {
        notePart(ChartPartKind.mark, Rect.fromCircle(center: q, radius: 6),
            series: s, index: i);
      }
      continue;
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = col.withValues(alpha: 0.45));
    for (var (i, q) in pts.indexed) {
      canvas.drawCircle(
          q, math.max(3, R * 0.03), Paint()..color = d.markAt(i) ?? col);
      notePart(ChartPartKind.mark, Rect.fromCircle(center: q, radius: 6),
          series: s, index: i);
    }
  }
}

// ------------------------------------------------------------ waffle

/// _waffleWays is the hundred as dots rather than squares, or squares
/// filling from the bottom up in columns, so the share rises like a bar.
void _waffleWays(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, String mode) {
  var v = _vals(e), n = v.length;
  var total = v.fold(0.0, (a, b) => a + b);
  if (total <= 0) return;
  var side = math.min(area.width, area.height);
  var cell = side / 10;
  var left = area.left + (area.width - side) / 2,
      top = area.top + (area.height - side) / 2;
  // Which category each of the hundred belongs to, in order.
  var owner = <int>[];
  for (var i = 0; i < n; i++) {
    owner.addAll(List.filled((v[i] / total * 100).round(), i));
  }
  while (owner.length < 100) {
    owner.add(-1);
  }
  var p0 = e.animation.on ? reveal.clamp(0.0, 1.0) : 1.0;
  for (var k = 0; k < 100; k++) {
    var col = mode == "rising" ? k ~/ 10 : k % 10;
    var row = mode == "rising" ? 9 - k % 10 : k ~/ 10;
    var o = owner[k];
    var lit = o >= 0 && k < 100 * p0;
    var colour = lit ? _item(e, o) : _quiet(e, 0.12);
    var r = Rect.fromLTWH(left + col * cell, top + row * cell, cell, cell)
        .deflate(cell * 0.08);
    if (mode == "dots") {
      canvas.drawCircle(r.center, r.width / 2, Paint()..color = colour);
    } else {
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(cell * 0.12)),
          Paint()..color = colour);
    }
  }
  for (var i = 0; i < n; i++) {
    notePart(ChartPartKind.mark, Rect.fromLTWH(left, top, side, side),
        series: 0, index: i);
  }
}
