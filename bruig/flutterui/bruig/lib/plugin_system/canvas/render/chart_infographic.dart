import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/painting.dart';

// chart_infographic.dart draws the infographic types (Ken, 2026-11-13: "I'd
// like all 6 suggestions and any other infographic elements you think would
// be useful for building future infographics"): gauge, pictogram, sankey,
// treemap, timeline, funnel, bubbles, bullet, slope, share bar and lollipop.
//
// None has axes. Each reads the chart's own data as the others do -- its
// categories and its series -- and arrives an item at a time by the chart's
// animation (sliceProgress), as a pie's slices do. Labels show with the
// x-axis labels' switch, values with Values.

/// paintInfographic draws [e], one of the infographic types, in [area].
void paintInfographic(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  if (e.data.series.isEmpty || e.data.categories.isEmpty) return;
  switch (e.type) {
    case ChartType.gauge:
      _gauge(canvas, area, e, reveal);
    case ChartType.pictogram:
      _pictogram(canvas, area, e, reveal);
    case ChartType.sankey:
      _sankey(canvas, area, e, reveal);
    case ChartType.treemap:
      _treemap(canvas, area, e, reveal);
    case ChartType.timeline:
      _timeline(canvas, area, e, reveal);
    case ChartType.funnel:
      _funnel(canvas, area, e, reveal);
    case ChartType.bubbles:
      _bubbles(canvas, area, e, reveal);
    case ChartType.bullet:
      _bullet(canvas, area, e, reveal);
    case ChartType.slope:
      _slope(canvas, area, e, reveal);
    case ChartType.shareBar:
      _shareBar(canvas, area, e, reveal);
    case ChartType.lollipop:
      _lollipop(canvas, area, e, reveal);
    default:
      break;
  }
}

// ------------------------------------------------------------ shared bits

List<double> _values(ChartElement e, [int s = 0]) => [
      for (var i = 0; i < e.data.categories.length; i++)
        s < e.data.series.length ? e.data.valueAt(s, i).abs() : 0.0,
    ];

/// itemColour is item [i]'s colour: the chart's slice colours, else the
/// palette -- one colour an item whatever the series.
Color itemColour(ChartElement e, int i) => i < e.sliceColors.length
    ? e.sliceColors[i]
    : chartPalette[i % chartPalette.length];

String _value(ChartElement e, double v, [int s = 0]) => formatSeries(e, s, v);

TextSpec _label(ChartElement e,
        {TextAlignSpec align = TextAlignSpec.center, double? size}) =>
    e.labelSpec.copyWith(
        align: align,
        verticalAlign: VerticalAlignSpec.middle,
        fontSize: size ?? e.labelSpec.fontSize);

TextSpec _figure(ChartElement e,
        {TextAlignSpec align = TextAlignSpec.center, double? size}) =>
    e.valueSpec.copyWith(
        align: align,
        verticalAlign: VerticalAlignSpec.middle,
        fontSize: size ?? e.valueSpec.fontSize);

void _text(ui.Canvas canvas, String s, TextSpec spec, Rect box) {
  if (s.isEmpty || box.width <= 1 || box.height <= 1) return;
  paintTextInBox(canvas, s, spec, box);
}

/// _grown is [r] grown from its centre to [size] of itself.
Rect _grown(Rect r, double size) => size >= 1
    ? r
    : Rect.fromCenter(
        center: r.center, width: r.width * size, height: r.height * size);

// ------------------------------------------------------------------ gauge

/// The first value as a share: of the values' total where there are
/// several, else of the axis's top (yMax) or a hundred. The shares round a
/// dial of 240 degrees, the number in the middle.
void _gauge(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var values = _values(e);
  var several = values.length > 1;
  var total = several
      ? values.fold<double>(0, (t, v) => t + v)
      : (e.yMax.isFinite && e.yMax > 0 ? e.yMax : 100.0);
  if (total <= 0) return;
  // The dial's box: as wide as it is, its open bottom a third of its height.
  var r = math.min(area.width / 2, area.height / 1.5) * 0.94;
  var centre =
      Offset(area.center.dx, area.top + (area.height - r * 1.5) / 2 + r);
  var thick = r * (1 - e.innerRadius).clamp(0.08, 0.9) * 0.5;
  var ring = Rect.fromCircle(center: centre, radius: r - thick / 2);
  const start = math.pi * 5 / 6, sweep = math.pi * 4 / 3;
  canvas.drawArc(
      ring,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thick
        ..strokeCap = StrokeCap.round
        ..color = e.gridColor);
  var from = start;
  var shown = several ? values.length : 1;
  for (var i = 0; i < shown; i++) {
    var share = (values[i] / total).clamp(0.0, 1.0);
    var slice = sliceProgress(e, reveal, i, shown);
    var arc = sweep * share;
    if (!slice.gone && arc > 0) {
      canvas.drawArc(
          ring,
          from,
          arc * slice.size,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = thick
            ..strokeCap = i == 0 ? StrokeCap.round : StrokeCap.butt
            ..color = slice.tint(itemColour(e, i)));
    }
    from += arc;
  }
  var first = sliceProgress(e, reveal, 0, shown).size.clamp(0.0, 1.0);
  var middle = e.centreLabel.trim().isNotEmpty
      ? e.centreLabel
      : several || !(e.yMax.isFinite && e.yMax > 0)
          ? "${(values.first / total * 100 * first).round()}%"
          : _value(e, values.first * first);
  _text(canvas, middle, _figure(e, size: r * 0.42),
      Rect.fromCenter(center: centre, width: r * 1.5, height: r * 0.6));
  if (e.showXLabels) {
    _text(
        canvas,
        e.data.categories.first,
        _label(e),
        Rect.fromCenter(
            center: centre + Offset(0, r * 0.42),
            width: r * 1.4,
            height: e.labelSpec.fontSize * 2.2));
  }
}

// -------------------------------------------------------------- pictogram

/// A row -- or rows of ten -- of drawn icons, shared out among the values as
/// a waffle's squares are.
void _pictogram(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var n = e.pictoCount.clamp(1, 200);
  var shares = waffleCells(_values(e), cells: n);
  var cols = n <= 12 ? n : 10;
  var rows = (n / cols).ceil();
  var cell = math.min(area.width / cols, area.height / rows);
  var left = area.left + (area.width - cell * cols) / 2;
  var top = area.top + (area.height - cell * rows) / 2;
  var k = 0;
  for (var (i, count) in shares.indexed) {
    var colour = itemColour(e, i);
    for (var j = 0; j < count && k < n; j++, k++) {
      var slice = sliceProgress(e, reveal, k, n);
      if (slice.gone) continue;
      var box = Rect.fromLTWH(
              left + (k % cols) * cell, top + (k ~/ cols) * cell, cell, cell)
          .deflate(cell * 0.08);
      canvas.drawPath(pictoPath(e.pictoShape, _grown(box, slice.size)),
          Paint()..color = slice.tint(colour));
    }
  }
}

/// pictoPath is [shape] drawn to fill [b].
Path pictoPath(PictoShape shape, Rect b) {
  var w = b.width, h = b.height;
  Offset at(double x, double y) => Offset(b.left + x * w, b.top + y * h);
  switch (shape) {
    case PictoShape.dot:
      return Path()..addOval(b.deflate(w * 0.05));
    case PictoShape.square:
      return Path()
        ..addRRect(RRect.fromRectAndRadius(
            b.deflate(w * 0.06), Radius.circular(w * 0.12)));
    case PictoShape.coin:
      return Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(b.deflate(w * 0.04))
        ..addOval(b.deflate(w * 0.2))
        ..addOval(b.deflate(w * 0.27));
    case PictoShape.person:
      return Path()
        ..addOval(Rect.fromCircle(center: at(0.5, 0.2), radius: w * 0.17))
        ..addRRect(RRect.fromRectAndCorners(
            Rect.fromLTRB(
                b.left + w * 0.2, b.top + h * 0.42, b.left + w * 0.8, b.bottom),
            topLeft: Radius.circular(w * 0.28),
            topRight: Radius.circular(w * 0.28),
            bottomLeft: Radius.circular(w * 0.06),
            bottomRight: Radius.circular(w * 0.06)));
    case PictoShape.star:
      var p = Path();
      for (var i = 0; i < 10; i++) {
        var r = i.isEven ? 0.5 : 0.21;
        var a = -math.pi / 2 + i * math.pi / 5;
        var pt = at(0.5 + math.cos(a) * r, 0.53 + math.sin(a) * r);
        i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
      }
      return p..close();
    case PictoShape.heart:
      return Path()
        ..moveTo(at(0.5, 0.92).dx, at(0.5, 0.92).dy)
        ..cubicTo(at(0.05, 0.62).dx, at(0.05, 0.62).dy, at(-0.02, 0.18).dx,
            at(-0.02, 0.18).dy, at(0.27, 0.12).dx, at(0.27, 0.12).dy)
        ..cubicTo(at(0.4, 0.1).dx, at(0.4, 0.1).dy, at(0.47, 0.18).dx,
            at(0.47, 0.18).dy, at(0.5, 0.26).dx, at(0.5, 0.26).dy)
        ..cubicTo(at(0.53, 0.18).dx, at(0.53, 0.18).dy, at(0.6, 0.1).dx,
            at(0.6, 0.1).dy, at(0.73, 0.12).dx, at(0.73, 0.12).dy)
        ..cubicTo(at(1.02, 0.18).dx, at(1.02, 0.18).dy, at(0.95, 0.62).dx,
            at(0.95, 0.62).dy, at(0.5, 0.92).dx, at(0.5, 0.92).dy)
        ..close();
    case PictoShape.ticket:
      var body = Path()
        ..addRRect(RRect.fromRectAndRadius(
            Rect.fromLTRB(
                b.left, b.top + h * 0.22, b.right, b.bottom - h * 0.22),
            Radius.circular(w * 0.08)));
      var notches = Path()
        ..addOval(Rect.fromCircle(center: at(0, 0.5), radius: w * 0.12))
        ..addOval(Rect.fromCircle(center: at(1, 0.5), radius: w * 0.12));
      return Path.combine(PathOperation.difference, body, notches);
    case PictoShape.house:
      return Path()
        ..moveTo(at(0.5, 0.06).dx, at(0.5, 0.06).dy)
        ..lineTo(at(0.96, 0.46).dx, at(0.96, 0.46).dy)
        ..lineTo(at(0.84, 0.46).dx, at(0.84, 0.46).dy)
        ..lineTo(at(0.84, 0.94).dx, at(0.84, 0.94).dy)
        ..lineTo(at(0.16, 0.94).dx, at(0.16, 0.94).dy)
        ..lineTo(at(0.16, 0.46).dx, at(0.16, 0.46).dy)
        ..lineTo(at(0.04, 0.46).dx, at(0.04, 0.46).dy)
        ..close();
  }
}

// ----------------------------------------------------------------- sankey

/// SankeyFlow is one flow: a category "From > To" (or "From → To"); a
/// category with neither flows out of the series' name.
typedef SankeyFlow = ({String from, String to, double value});

List<SankeyFlow> sankeyFlows(ChartElement e) {
  var source = e.data.series.first.name.trim().isEmpty
      ? "Total"
      : e.data.series.first.name.trim();
  var values = _values(e);
  return [
    for (var (i, c) in e.data.categories.indexed)
      if (values[i] > 0)
        switch (RegExp(r"\s*(?:->|→|>)\s*").firstMatch(c)) {
          var m? => (
              from: c.substring(0, m.start).trim(),
              to: c.substring(m.end).trim(),
              value: values[i]
            ),
          null => (from: source, to: c.trim(), value: values[i]),
        },
  ];
}

void _sankey(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var flows = sankeyFlows(e);
  if (flows.isEmpty) return;
  var names = <String>[];
  for (var f in flows) {
    if (!names.contains(f.from)) names.add(f.from);
    if (!names.contains(f.to)) names.add(f.to);
  }
  // Each node's column: one after the furthest that flows into it.
  var column = {for (var n in names) n: 0};
  for (var pass = 0; pass < names.length; pass++) {
    for (var f in flows) {
      if (column[f.to]! <= column[f.from]!) column[f.to] = column[f.from]! + 1;
    }
  }
  var columns = column.values.fold<int>(0, math.max) + 1;
  double inOf(String n) =>
      flows.where((f) => f.to == n).fold(0, (t, f) => t + f.value);
  double outOf(String n) =>
      flows.where((f) => f.from == n).fold(0, (t, f) => t + f.value);
  var size = {for (var n in names) n: math.max(inOf(n), outOf(n))};
  // Labels need room on the right of all but the last column, and on its
  // left for the last.
  var labelW = e.showXLabels ? area.width * 0.22 : 0.0;
  var nodeW = math.max(6.0, area.width * 0.025);
  var span = area.width - labelW - nodeW;
  double xOf(int col) =>
      area.left + (columns == 1 ? 0 : span * col / (columns - 1));
  var gap = area.height * 0.04;
  var scale = double.infinity;
  for (var col = 0; col < columns; col++) {
    var inCol = names.where((n) => column[n] == col).toList();
    var total = inCol.fold<double>(0, (t, n) => t + size[n]!);
    if (total > 0) {
      scale = math.min(
          scale, (area.height - gap * math.max(0, inCol.length - 1)) / total);
    }
  }
  if (!scale.isFinite) return;
  var box = <String, Rect>{};
  for (var col = 0; col < columns; col++) {
    var inCol = names.where((n) => column[n] == col).toList();
    var height = inCol.fold<double>(0, (t, n) => t + size[n]! * scale) +
        gap * math.max(0, inCol.length - 1);
    var y = area.top + (area.height - height) / 2;
    for (var n in inCol) {
      box[n] = Rect.fromLTWH(xOf(col), y, nodeW, size[n]! * scale);
      y += size[n]! * scale + gap;
    }
  }
  // The ribbons, each from where the last left its node to where the last
  // arrived at the other, in their order.
  var outAt = {for (var n in names) n: box[n]!.top};
  var inAt = {for (var n in names) n: box[n]!.top};
  for (var (i, f) in flows.indexed) {
    var slice = sliceProgress(e, reveal, i, flows.length);
    var t = f.value * scale;
    var a = box[f.from]!, b = box[f.to]!;
    var y0 = outAt[f.from]!, y1 = inAt[f.to]!;
    outAt[f.from] = y0 + t;
    inAt[f.to] = y1 + t;
    if (slice.gone) continue;
    var x0 = a.right, x1 = x0 + (b.left - x0) * slice.size.clamp(0.0, 1.0);
    var mid = (x0 + b.left) / 2;
    var path = Path()
      ..moveTo(x0, y0)
      ..cubicTo(mid, y0, mid, y1, x1, y1)
      ..lineTo(x1, y1 + t)
      ..cubicTo(mid, y1 + t, mid, y0 + t, x0, y0 + t)
      ..close();
    var colour = itemColour(
        e, names.indexOf(f.to) - 1 < 0 ? 0 : names.indexOf(f.to) - 1);
    canvas.drawPath(path,
        Paint()..color = slice.tint(colour.withValues(alpha: colour.a * 0.55)));
  }
  for (var (i, n) in names.indexed) {
    var r = box[n]!;
    var colour = i == 0 ? e.axisColor : itemColour(e, i - 1);
    canvas.drawRect(r, Paint()..color = colour);
    if (!e.showXLabels) continue;
    var last = column[n] == columns - 1;
    var words = e.showValues ? "$n  ${_value(e, size[n]!)}" : n;
    _text(
        canvas,
        words,
        _label(e, align: last ? TextAlignSpec.left : TextAlignSpec.left),
        // Kept inside the chart: a small node at an edge had its name cut.
        Rect.fromLTWH(
            r.right + 6,
            (r.center.dy - e.labelSpec.fontSize * 1.2).clamp(area.top,
                math.max(area.top, area.bottom - e.labelSpec.fontSize * 2.4)),
            labelW - 8,
            e.labelSpec.fontSize * 2.4));
  }
}

// ---------------------------------------------------------------- treemap

/// treemapRects lays [values] out in [area] squarified: rows of rectangles
/// as near square as they can be, the largest first. In the values' order.
List<Rect> treemapRects(List<double> values, Rect area) {
  var out = List<Rect>.filled(values.length, Rect.zero);
  var order = [for (var i = 0; i < values.length; i++) i]
    ..removeWhere((i) => values[i] <= 0)
    ..sort((a, b) => values[b].compareTo(values[a]));
  var total = order.fold<double>(0, (t, i) => t + values[i]);
  if (total <= 0) return out;
  var free = area;
  var scale = area.width * area.height / total;
  var row = <int>[];
  double worst(List<int> items, double side) {
    var sum = items.fold<double>(0, (t, i) => t + values[i] * scale);
    var most = items.fold<double>(0, (m, i) => math.max(m, values[i] * scale));
    var least = items.fold<double>(
        double.infinity, (m, i) => math.min(m, values[i] * scale));
    return math.max(
        side * side * most / (sum * sum), sum * sum / (side * side * least));
  }

  void lay(List<int> items) {
    var sum = items.fold<double>(0, (t, i) => t + values[i] * scale);
    var wide = free.width >= free.height;
    var thick = sum / (wide ? free.height : free.width);
    var at = 0.0;
    for (var i in items) {
      var len = values[i] * scale / thick;
      out[i] = wide
          ? Rect.fromLTWH(free.left, free.top + at, thick, len)
          : Rect.fromLTWH(free.left + at, free.top, len, thick);
      at += len;
    }
    free = wide
        ? Rect.fromLTRB(free.left + thick, free.top, free.right, free.bottom)
        : Rect.fromLTRB(free.left, free.top + thick, free.right, free.bottom);
  }

  for (var i in order) {
    var side = math.min(free.width, free.height);
    if (row.isEmpty || worst([...row, i], side) <= worst(row, side)) {
      row.add(i);
    } else {
      lay(row);
      row = [i];
    }
  }
  if (row.isNotEmpty) lay(row);
  return out;
}

void _treemap(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var values = _values(e);
  var rects = treemapRects(values, area);
  for (var (i, r) in rects.indexed) {
    if (r.isEmpty) continue;
    var slice = sliceProgress(e, reveal, i, rects.length);
    if (slice.gone) continue;
    var tile = _grown(r.deflate(1.5), slice.size);
    canvas.drawRRect(RRect.fromRectAndRadius(tile, const Radius.circular(4)),
        Paint()..color = slice.tint(itemColour(e, i)));
    var room = tile.deflate(8);
    if (room.width < 30 || room.height < e.labelSpec.fontSize * 1.4) continue;
    var lines = [
      if (e.showXLabels) e.data.categories[i],
      if (e.showValues) _value(e, values[i]),
    ].join("\n");
    _text(
        canvas,
        lines,
        _label(e, align: TextAlignSpec.left)
            .copyWith(verticalAlign: VerticalAlignSpec.top),
        room);
  }
}

// --------------------------------------------------------------- timeline

/// Events along a line, each at its value -- a year, a date as a number --
/// on a stem, above and below in turn.
void _timeline(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var values = [
    for (var i = 0; i < e.data.categories.length; i++) e.data.valueAt(0, i),
  ];
  var lo = values.reduce(math.min), hi = values.reduce(math.max);
  if (hi <= lo) hi = lo + 1;
  var pad = area.width * 0.08;
  double xOf(double v) =>
      area.left + pad + (v - lo) / (hi - lo) * (area.width - pad * 2);
  var y = area.center.dy;
  var axis = Paint()
    ..color = e.axisColor
    ..strokeWidth = math.max(2, area.height * 0.012)
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(Offset(area.left, y), Offset(area.right, y), axis);
  var order = [for (var i = 0; i < values.length; i++) i]
    ..sort((a, b) => values[a].compareTo(values[b]));
  var stem = area.height * 0.22;
  var dot = math.max(5.0, area.height * 0.035);
  var room = (area.width - pad * 2) / math.max(1, values.length - 1) * 1.8;
  for (var (k, i) in order.indexed) {
    var slice = sliceProgress(e, reveal, k, order.length);
    if (slice.gone) continue;
    var x = xOf(values[i]);
    var up = k.isEven;
    var end = y + (up ? -stem : stem) * slice.size;
    var colour = slice.tint(itemColour(e, i));
    canvas.drawLine(
        Offset(x, y),
        Offset(x, end),
        Paint()
          ..color = colour
          ..strokeWidth = math.max(1.5, dot * 0.35));
    canvas.drawCircle(Offset(x, y), dot, Paint()..color = colour);
    if (slice.size < 1) continue;
    var labelH = e.labelSpec.fontSize * 2.4;
    var figureH = e.valueSpec.fontSize * 1.4;
    var top = up ? end - labelH - (e.showValues ? figureH : 0) : end;
    if (e.showValues) {
      _text(canvas, _value(e, values[i]), _figure(e),
          Rect.fromLTWH(x - room / 2, up ? top : end, room, figureH));
      top = up ? top + figureH : end + figureH;
    }
    if (e.showXLabels) {
      _text(canvas, e.data.categories[i], _label(e),
          Rect.fromLTWH(x - room / 2, top, room, labelH));
    }
  }
}

// ----------------------------------------------------------------- funnel

/// Stages top to bottom, each as wide as its value, joined by slopes to the
/// next.
void _funnel(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var values = _values(e);
  var most = values.fold<double>(0, math.max);
  if (most <= 0) return;
  var n = values.length;
  var gap = area.height * 0.015;
  var h = (area.height - gap * (n - 1)) / n;
  var cx = area.center.dx;
  double widthOf(int i) => area.width * (0.18 + 0.82 * values[i] / most);
  for (var i = 0; i < n; i++) {
    var slice = sliceProgress(e, reveal, i, n);
    if (slice.gone) continue;
    var top = area.top + i * (h + gap);
    var w0 = widthOf(i) * slice.size,
        w1 = (i + 1 < n ? widthOf(i + 1) : widthOf(i) * 0.8) * slice.size;
    var path = Path()
      ..moveTo(cx - w0 / 2, top)
      ..lineTo(cx + w0 / 2, top)
      ..lineTo(cx + w1 / 2, top + h)
      ..lineTo(cx - w1 / 2, top + h)
      ..close();
    canvas.drawPath(path, Paint()..color = slice.tint(itemColour(e, i)));
    var words = [
      if (e.showXLabels) e.data.categories[i],
      if (e.showValues) _value(e, values[i]),
    ].join("   ");
    _text(canvas, words, _label(e), Rect.fromLTWH(cx - w0 / 2, top, w0, h));
  }
}

// ---------------------------------------------------------------- bubbles

/// bubbleCircles packs one circle a value, its area by the value, the
/// largest in the middle and each next as near it as it goes without
/// overlapping: centres and radii in [area], in the values' order.
List<(Offset, double)> bubbleCircles(List<double> values, Rect area) {
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
  if (placed.isEmpty) return [for (var _ in values) (area.center, 0.0)];
  var bounds = placed.entries
      .map((x) => Rect.fromCircle(center: x.value, radius: r[x.key]))
      .reduce((a, b) => a.expandToInclude(b));
  var k = math.min(area.width / bounds.width, area.height / bounds.height);
  return [
    for (var i = 0; i < values.length; i++)
      placed[i] == null
          ? (area.center, 0.0)
          : (
              area.center + (placed[i]! - bounds.center) * k,
              r[i] * k,
            ),
  ];
}

void _bubbles(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var values = _values(e);
  var circles = bubbleCircles(values, area);
  for (var (i, (c, r)) in circles.indexed) {
    if (r <= 0) continue;
    var slice = sliceProgress(e, reveal, i, circles.length);
    if (slice.gone) continue;
    canvas.drawCircle(
        c, r * slice.size, Paint()..color = slice.tint(itemColour(e, i)));
    var longest = e.data.categories[i]
        .split(RegExp(r"\s+"))
        .fold<int>(0, (m, w) => math.max(m, w.length));
    // A name broken mid-word ("Treas / ury") reads worse than none.
    if (r * 1.6 < longest * e.labelSpec.fontSize * 0.62 ||
        r < e.labelSpec.fontSize * 1.6 ||
        slice.size < 1) {
      continue;
    }
    var lines = [
      if (e.showXLabels) e.data.categories[i],
      if (e.showValues) _value(e, values[i]),
    ].join("\n");
    _text(canvas, lines, _label(e),
        Rect.fromCenter(center: c, width: r * 1.6, height: r * 1.2));
  }
}

// ----------------------------------------------------------------- bullet

/// A row a category: its value as a bar over three bands (the top, three
/// quarters and half of the scale), the second series' value as its target.
void _bullet(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var values = _values(e);
  var targets = e.data.series.length > 1 ? _values(e, 1) : null;
  var most = [...values, ...?targets].fold<double>(0, math.max);
  if (e.yMax.isFinite && e.yMax > 0) most = e.yMax;
  if (most <= 0) return;
  var n = values.length;
  var rowH = area.height / n;
  var labelW = e.showXLabels ? area.width * 0.26 : 0.0;
  var figureW = e.showValues ? area.width * 0.12 : 0.0;
  var left = area.left + labelW, width = area.width - labelW - figureW;
  for (var i = 0; i < n; i++) {
    var slice = sliceProgress(e, reveal, i, n);
    var top = area.top + i * rowH;
    var band = rowH * 0.62;
    var by = top + (rowH - band) / 2;
    for (var (k, share) in const [1.0, 0.75, 0.5].indexed) {
      canvas.drawRect(
          Rect.fromLTWH(left, by, width * share, band),
          Paint()
            // Each band a little stronger than the one it lies on: quiet
            // enough for the bar to read over them.
            ..color = e.gridColor.withValues(
                alpha: (e.gridColor.a * (0.5 + k * 0.35)).clamp(0.0, 1.0)));
    }
    if (e.showXLabels) {
      _text(canvas, e.data.categories[i], _label(e, align: TextAlignSpec.right),
          Rect.fromLTWH(area.left, top, labelW - 10, rowH));
    }
    if (slice.gone) continue;
    var bar = band * 0.42;
    var w = width * (values[i] / most).clamp(0.0, 1.0) * slice.size;
    canvas.drawRect(Rect.fromLTWH(left, top + (rowH - bar) / 2, w, bar),
        Paint()..color = slice.tint(itemColour(e, i)));
    if (targets != null && targets[i] > 0) {
      var x = left + width * (targets[i] / most).clamp(0.0, 1.0);
      canvas.drawLine(
          Offset(x, by + band * 0.12),
          Offset(x, by + band * 0.88),
          Paint()
            ..color = e.axisColor
            ..strokeWidth = math.max(2, band * 0.08));
    }
    if (e.showValues && slice.size >= 1) {
      _text(canvas, _value(e, values[i]), _figure(e, align: TextAlignSpec.left),
          Rect.fromLTWH(left + width + 8, top, figureW - 8, rowH));
    }
  }
}

// ------------------------------------------------------------------ slope

/// Each category a line from its first series' value on the left to its
/// second's on the right: what rose, what fell, and by how much.
void _slope(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  if (e.data.series.length < 2) return;
  var a = _values(e, 0), b = _values(e, 1);
  var all = [...a, ...b];
  var lo = all.reduce(math.min), hi = all.reduce(math.max);
  if (hi <= lo) hi = lo + 1;
  var headH = e.labelSpec.fontSize * 2;
  var plot = Rect.fromLTRB(area.left, area.top + headH, area.right,
      area.bottom - e.labelSpec.fontSize);
  var side = plot.width * 0.3;
  var x0 = plot.left + side, x1 = plot.right - side;
  double yOf(double v) => plot.bottom - (v - lo) / (hi - lo) * plot.height;
  var rule = Paint()
    ..color = e.gridColor
    ..strokeWidth = 1.5;
  canvas.drawLine(Offset(x0, plot.top), Offset(x0, plot.bottom), rule);
  canvas.drawLine(Offset(x1, plot.top), Offset(x1, plot.bottom), rule);
  for (var (s, x) in [(0, x0), (1, x1)]) {
    _text(
        canvas,
        e.data.series[s].name,
        _label(e),
        Rect.fromCenter(
            center: Offset(x, area.top + headH / 2),
            width: side * 1.4,
            height: headH));
  }
  var dot = math.max(4.0, plot.height * 0.02);
  for (var i = 0; i < a.length; i++) {
    var slice = sliceProgress(e, reveal, i, a.length);
    if (slice.gone) continue;
    var colour = slice.tint(itemColour(e, i));
    var p0 = Offset(x0, yOf(a[i])), p1 = Offset(x1, yOf(b[i]));
    var to = Offset.lerp(p0, p1, slice.size.clamp(0.0, 1.0))!;
    canvas.drawLine(
        p0,
        to,
        Paint()
          ..color = colour
          ..strokeWidth = math.max(2, dot * 0.6)
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(p0, dot, Paint()..color = colour);
    if (slice.size >= 1) canvas.drawCircle(p1, dot, Paint()..color = colour);
    var h = e.labelSpec.fontSize * 1.6;
    var left = [
      if (e.showXLabels) e.data.categories[i],
      if (e.showValues) _value(e, a[i]),
    ].join("  ");
    _text(canvas, left, _label(e, align: TextAlignSpec.right),
        Rect.fromLTWH(plot.left, p0.dy - h / 2, side - dot * 2, h));
    if (slice.size >= 1) {
      var right = [
        if (e.showValues) _value(e, b[i], 1),
        if (e.showXLabels) e.data.categories[i],
      ].join("  ");
      _text(canvas, right, _label(e, align: TextAlignSpec.left),
          Rect.fromLTWH(x1 + dot * 2, p1.dy - h / 2, side - dot * 2, h));
    }
  }
}

// -------------------------------------------------------------- share bar

/// One bar the width of the chart, split into the shares, each named under
/// its piece with its percentage.
void _shareBar(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var values = _values(e);
  var total = values.fold<double>(0, (t, v) => t + v);
  if (total <= 0) return;
  var under = e.showXLabels || e.showValues ? e.labelSpec.fontSize * 3.2 : 0.0;
  var barH = math.min(area.height - under, math.max(18.0, area.height * 0.36));
  var top = area.top + (area.height - barH - under) / 2;
  var x = area.left;
  for (var i = 0; i < values.length; i++) {
    var w = area.width * values[i] / total;
    var slice = sliceProgress(e, reveal, i, values.length);
    if (!slice.gone && w > 0) {
      var piece = Rect.fromLTWH(x, top, w * slice.size, barH);
      canvas.drawRect(
          piece.deflate(0.75), Paint()..color = slice.tint(itemColour(e, i)));
      // Named under its piece where the piece is wide enough for it: a
      // sliver's words ran into the next one's.
      var longest = e.data.categories[i]
          .split(RegExp(r"\s+"))
          .fold<int>(4, (m, w) => math.max(m, w.length));
      if (slice.size >= 1 &&
          under > 0 &&
          w >= longest * e.labelSpec.fontSize * 0.62 + 6) {
        var words = [
          if (e.showValues) "${(values[i] / total * 100).round()}%",
          if (e.showXLabels) e.data.categories[i],
        ].join("\n");
        _text(canvas, words, _label(e, align: TextAlignSpec.left),
            Rect.fromLTWH(x + 2, top + barH + 4, w - 4, under - 4));
      }
    }
    x += w;
  }
}

// --------------------------------------------------------------- lollipop

/// A row a category: a thin stick from the left to its value, a dot on its
/// end -- lighter to read than bars when there are many.
void _lollipop(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var values = _values(e);
  var most = values.fold<double>(0, math.max);
  if (e.yMax.isFinite && e.yMax > 0) most = e.yMax;
  if (most <= 0) return;
  var n = values.length;
  var rowH = area.height / n;
  var labelW = e.showXLabels ? area.width * 0.28 : 0.0;
  var figureW = e.showValues ? area.width * 0.12 : 0.0;
  var left = area.left + labelW, width = area.width - labelW - figureW;
  var dot = math.max(5.0, math.min(rowH * 0.22, 16.0));
  for (var i = 0; i < n; i++) {
    var y = area.top + rowH * (i + 0.5);
    canvas.drawLine(
        Offset(left, y),
        Offset(left + width, y),
        Paint()
          ..color = e.gridColor
          ..strokeWidth = 1);
    if (e.showXLabels) {
      _text(canvas, e.data.categories[i], _label(e, align: TextAlignSpec.right),
          Rect.fromLTWH(area.left, y - rowH / 2, labelW - 12, rowH));
    }
    var slice = sliceProgress(e, reveal, i, n);
    if (slice.gone) continue;
    var colour = slice.tint(itemColour(e, i));
    var end =
        left + (width - dot) * (values[i] / most).clamp(0.0, 1.0) * slice.size;
    canvas.drawLine(
        Offset(left, y),
        Offset(end, y),
        Paint()
          ..color = colour
          ..strokeWidth = math.max(2, dot * 0.4));
    canvas.drawCircle(Offset(end, y), dot, Paint()..color = colour);
    if (e.showValues && slice.size >= 1) {
      _text(
          canvas,
          _value(e, values[i]),
          _figure(e, align: TextAlignSpec.left),
          Rect.fromLTWH(end + dot + 6, y - rowH / 2,
              figureW + width - (end - left), rowH));
    }
  }
}
