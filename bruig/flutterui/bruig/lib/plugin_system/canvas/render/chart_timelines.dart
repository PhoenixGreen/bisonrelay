import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/render/label_placer.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/painting.dart';

// chart_timelines.dart is the timeline's other ways (Ken, 2026-11-17: "more
// designs for the timeline chart, please do some research"; the research is
// in data-design-prototype/timeline-research/RESEARCH.md): spans from start
// to end packed into rows, the same in a lane a group, eras as bands behind
// the events, events numbered on a line of values, cards either side of a
// spine, bubbles sized by a number in lanes, a line folded down the page,
// and the past solid up to today with the future dashed.
//
// What they read: the first series is when each event starts; a second,
// where a way has ends (spans, swimlanes, eras), is when it ends -- blank
// for an event on one date; the last, where a way has numbers (the value
// line, bubbles), is its number. Groups are the column it is coloured by,
// and a card's words its row's point name (SheetLink.pointNames).

/// timelineWays is the ways drawn here.
const timelineWays = {
  "spans",
  "lanes",
  "eras",
  "value",
  "cards",
  "bubbles",
  "serpentine",
  "progress",
  "zoom",
  "spiral",
  "thenNow",
  "strip",
  "aligned",
};

/// paintTimelineWay draws timeline [e] its [mode] way, answering whether
/// it is one of these.
bool paintTimelineWay(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, String mode) {
  var evs = _events(e);
  if (evs.isEmpty) return timelineWays.contains(mode);
  switch (mode) {
    case "spans":
      _spans(canvas, area, e, reveal, evs);
    case "lanes":
      _lanes(canvas, area, e, reveal, evs);
    case "eras":
      _eras(canvas, area, e, reveal, evs);
    case "value":
      _valueLine(canvas, area, e, reveal, evs);
    case "cards":
      _cards(canvas, area, e, reveal, evs);
    case "bubbles":
      _bubbles(canvas, area, e, reveal, evs);
    case "serpentine":
      _serpentine(canvas, area, e, reveal, evs);
    case "progress":
      _progress(canvas, area, e, reveal, evs);
    case "zoom":
      _zoom(canvas, area, e, reveal, evs);
    case "spiral":
      _spiral(canvas, area, e, reveal, evs);
    case "thenNow":
      _thenNow(canvas, area, e, reveal, evs);
    case "strip":
      _strip(canvas, area, e, reveal, evs);
    case "aligned":
      _aligned(canvas, area, e, reveal, evs);
    default:
      return false;
  }
  return true;
}

// ------------------------------------------------------------ shared bits

/// _Ev is one event: its row, when it starts, and when it ends (null for
/// one on a single date).
class _Ev {
  final int i;
  final double start;
  final double? end;
  const _Ev(this.i, this.start, this.end);
  double get last => end ?? start;
}

/// _events is [e]'s events in order of when they start; those without a
/// date left out.
List<_Ev> _events(ChartElement e) {
  var d = e.data;
  var out = <_Ev>[];
  for (var i = 0; i < d.categories.length; i++) {
    if (d.series.isEmpty) break;
    var s = d.valueAt(0, i);
    if (s.isNaN) continue;
    double? end;
    if (d.series.length > 1) {
      var v = d.valueAt(1, i);
      if (!v.isNaN && v > s) end = v;
    }
    out.add(_Ev(i, s, end));
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// _years is whether [evs]' dates are years.
bool _years(List<_Ev> evs) => evs.every((v) =>
    v.start == v.start.roundToDouble() && v.start > 1000 && v.start < 3000);

/// _when writes a date: a year as itself (not "2,016"), else as its
/// series is written.
String _when(ChartElement e, double v, [int s = 0]) =>
    v == v.roundToDouble() && v > 1000 && v < 3000
        ? "${v.round()}"
        : formatSeries(e, s, v);

Color _colour(ChartElement e, int i) =>
    e.data.markAt(i) ??
    (i < e.sliceColors.length
        ? e.sliceColors[i]
        : chartPalette[i % chartPalette.length]);

Color _quiet(ChartElement e, [double a = 0.3]) =>
    e.labelSpec.color.withValues(alpha: a);

Color _ink(Color fill) => fill.computeLuminance() > 0.45
    ? const Color(0xFF1B1B1B)
    : const Color(0xFFFFFFFF);

TextSpec _lab(ChartElement e,
        {TextAlignSpec align = TextAlignSpec.center, double? size}) =>
    e.labelSpec.copyWith(
        align: align,
        verticalAlign: VerticalAlignSpec.middle,
        fontSize: size ?? e.labelSpec.fontSize);

TextSpec _fig(ChartElement e,
        {TextAlignSpec align = TextAlignSpec.center, double? size}) =>
    e.valueSpec.copyWith(
        align: align,
        verticalAlign: VerticalAlignSpec.middle,
        fontSize: size ?? e.valueSpec.fontSize);

void _say(ui.Canvas canvas, String s, TextSpec spec, Rect box) {
  if (s.isEmpty || box.width <= 1 || box.height <= 1) return;
  paintTextInBox(canvas, s, spec, box);
}

double _widthOf(String s, TextSpec spec) =>
    s.isEmpty ? 0 : layoutText(s, spec, maxWidth: double.infinity).width;

/// _drawn is how much of a line drawn on is showing.
double _drawn(ChartElement e, double reveal) =>
    e.animation.on ? reveal.clamp(0.0, 1.0) : 1.0;

/// _Scale places dates across a span of the page.
class _Scale {
  final double lo, hi, left, right;
  _Scale(double lo, double hi, this.left, this.right)
      : lo = lo,
        hi = hi > lo ? hi : lo + 1;
  double x(double v) => left + (v - lo) / (hi - lo) * (right - left);

  /// knots are the dates an even scale spaces evenly; empty for one by
  /// date.
  List<double> get knots => const [];
}

/// _EvenScale spaces [knots] -- the events' dates, in order -- evenly
/// across, a date between two of them part-way between: the timeline
/// research's Even, for events bunched in one stretch and scattered in
/// another. The time between neighbours is written in the gaps instead of
/// ticks (see _axis).
class _EvenScale extends _Scale {
  @override
  final List<double> knots;
  _EvenScale(this.knots, double left, double right)
      : super(knots.first, knots.last, left, right);

  double _at(int i) =>
      left + (right - left) * (i + 0.5) / math.max(1, knots.length);

  @override
  double x(double v) {
    var n = knots.length;
    if (n == 1) return _at(0);
    if (v <= knots.first) {
      var w = knots[1] - knots[0];
      return _at(0) - (knots.first - v) / (w <= 0 ? 1 : w) * (_at(1) - _at(0));
    }
    for (var i = 0; i < n - 1; i++) {
      if (v <= knots[i + 1]) {
        var w = knots[i + 1] - knots[i];
        var t = w <= 0 ? 0.0 : (v - knots[i]) / w;
        return _at(i) + t * (_at(i + 1) - _at(i));
      }
    }
    var w = knots[n - 1] - knots[n - 2];
    return _at(n - 1) +
        (v - knots.last) / (w <= 0 ? 1 : w) * (_at(n - 1) - _at(n - 2));
  }
}

/// _scaleOf is a scale over [evs] (and [also]) across [left] to [right],
/// with a little room either end.
_Scale _scaleOf(List<_Ev> evs, double left, double right,
    {double? also, ChartElement? e}) {
  if (e != null && e.design.even) {
    var knots = {
      for (var v in evs) v.start,
      for (var v in evs)
        if (v.end != null) v.end!,
      if (also != null) also,
    }.toList()
      ..sort();
    return _EvenScale(knots, left, right);
  }
  var lo = evs.map((v) => v.start).reduce(math.min);
  var hi = evs.map((v) => v.last).reduce(math.max);
  if (also != null) {
    lo = math.min(lo, also);
    hi = math.max(hi, also);
  }
  if (hi <= lo) hi = lo + 1;
  var pad = (hi - lo) * 0.04;
  return _Scale(lo - pad, hi + pad, left, right);
}

/// _step is a round gap between ticks, for at most [most] across [span].
double _step(double span, int most, {bool whole = false}) {
  var raw = span / math.max(1, most);
  var mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  var step = 10 * mag;
  for (var m in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (m * mag >= raw) {
      step = m * mag;
      break;
    }
  }
  return whole ? math.max(1.0, step.roundToDouble()) : step;
}

/// _axisHeight is the room a date axis takes under a plot.
double _axisHeight(ChartElement e) => e.labelSpec.fontSize * 1.9;

/// _axis draws dates along [y] from [sc]'s left to right, ticked at round
/// dates, their figures under it.
void _axis(ui.Canvas canvas, ChartElement e, _Scale sc, double y, bool years,
    double drawn) {
  var line = Paint()
    ..color = _quiet(e, 0.45)
    ..strokeWidth = 1.2;
  canvas.drawLine(Offset(sc.left, y),
      Offset(sc.left + (sc.right - sc.left) * drawn, y), line);
  var spec = _lab(e, size: e.labelSpec.fontSize * 0.85)
      .copyWith(color: _quiet(e, 0.7));
  var room = e.labelSpec.fontSize * 4.5;
  // Evenly spaced: the time between neighbours, in the gaps.
  if (sc.knots.length > 1) {
    var k = sc.knots;
    for (var i = 0; i < k.length - 1; i++) {
      var a = sc.x(k[i]), b = sc.x(k[i + 1]);
      if (b > sc.left + (sc.right - sc.left) * drawn) break;
      canvas.drawLine(Offset(a, y), Offset(a, y + 5), line);
      _say(
          canvas,
          _gapWords(k[i + 1] - k[i], years, e),
          spec.copyWith(italic: true),
          Rect.fromCenter(
              center: Offset((a + b) / 2, y + 5 + spec.fontSize * 0.75),
              width: b - a - 4,
              height: spec.fontSize * 1.5));
    }
    canvas.drawLine(Offset(sc.x(k.last), y), Offset(sc.x(k.last), y + 5), line);
    return;
  }
  var step = _step(
      sc.hi - sc.lo, ((sc.right - sc.left) / room).floor().clamp(2, 12),
      whole: years);
  var first = (sc.lo / step).ceil() * step;
  for (var v = first; v <= sc.hi + 1e-9; v += step) {
    var x = sc.x(v);
    if (x > sc.left + (sc.right - sc.left) * drawn) break;
    canvas.drawLine(Offset(x, y), Offset(x, y + 5), line);
    _say(
        canvas,
        _when(e, v),
        spec,
        Rect.fromCenter(
            center: Offset(x, y + 5 + spec.fontSize * 0.75),
            width: room,
            height: spec.fontSize * 1.5));
  }
}

/// _gapWords is the time between two neighbours: "12 yrs", or the
/// difference as its numbers are written.
String _gapWords(double d, bool years, ChartElement e) {
  if (years) {
    var n = d.round();
    return n == 0 ? "same year" : "$n yr${n == 1 ? "" : "s"}";
  }
  return "+${formatSeries(e, 0, d)}";
}

/// _pack puts each of [spans] (left and right, in order of left) on the
/// first row it fits, [gap] clear of the one before: each one's row, and
/// how many rows.
(List<int>, int) _pack(List<(double, double)> spans, double gap) {
  var ends = <double>[];
  var rows = <int>[];
  for (var (l, r) in spans) {
    var row = ends.indexWhere((end) => end + gap <= l);
    if (row < 0) {
      row = ends.length;
      ends.add(r);
    } else {
      ends[row] = r;
    }
    rows.add(row);
  }
  return (rows, ends.length);
}

/// _gutter is how wide group names are written at the left, capped.
double _gutter(ChartElement e, List<String> names, double cap) {
  var spec = _lab(e, align: TextAlignSpec.left);
  var w = 0.0;
  for (var n in names) {
    w = math.max(w, _widthOf(n, spec));
  }
  return w <= 0 ? 0 : math.min(cap, w + spec.fontSize);
}

/// _groupsOf is [evs]' groups, in order of first appearance; [""] for none.
List<String> _groupsOf(ChartElement e, List<_Ev> evs) {
  var out = <String>[];
  for (var v in evs) {
    var g = e.data.groupAt(v.i);
    if (!out.contains(g)) out.add(g);
  }
  return out.length == 1 && out.first.isEmpty ? const [""] : out;
}

// ------------------------------------------------------------ spans

/// _spans is each event a bar from its start to its end -- Priestley's
/// chart of lives, a Gantt chart -- packed into as few rows as fit, its name
/// inside it where it fits, else just past it. One on a single date is a
/// diamond.
void _spans(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, List<_Ev> evs) {
  var axisH = _axisHeight(e);
  var plot =
      Rect.fromLTRB(area.left, area.top, area.right, area.bottom - axisH);
  var sc = _scaleOf(evs, plot.left, plot.right, e: e);
  _spanRows(canvas, e, reveal, plot, sc, evs, 0, evs.length);
  _axis(canvas, e, sc, plot.bottom + 2, _years(evs), _drawn(e, reveal));
}

/// _spanRows draws [evs] as bars packed into rows in [band] on [sc]; [k0]
/// of [n] for their arrival.
void _spanRows(ui.Canvas canvas, ChartElement e, double reveal, Rect band,
    _Scale sc, List<_Ev> evs, int k0, int n) {
  var fs = e.labelSpec.fontSize;
  var spec = _lab(e, align: TextAlignSpec.left);
  var pad = fs * 0.5;
  var dia = fs * 0.55;
  // Where each would reach with its name: inside it, past it, or before it
  // where there's no room past it (the last event, at the right edge).
  var reach = <(double, double)>[];
  var side = <int>[]; // 0 inside, 1 past, -1 before
  for (var v in evs) {
    var l = sc.x(v.start), r = sc.x(v.last);
    var w = e.showXLabels ? _widthOf(e.data.categories[v.i], spec) : 0.0;
    var fits = v.end != null && w + pad * 2 <= r - l;
    if (v.end == null) {
      l -= dia;
      r += dia;
    }
    var at = fits || w == 0
        ? 0
        : r + pad + w <= band.right || l - band.left < band.right - r
            ? 1
            : -1;
    side.add(at);
    reach.add(switch (at) {
      1 => (l, r + pad + w),
      -1 => (l - pad - w, r),
      _ => (l, r),
    });
  }
  var (rows, count) = _pack(reach, pad);
  var rowH = math.min(band.height / math.max(1, count), fs * 2.6);
  var barH = rowH * 0.72;
  // The rows together, in the middle of the band.
  var top0 = band.top + (band.height - rowH * count) / 2;
  for (var (k, v) in evs.indexed) {
    var p = sliceProgress(e, reveal, k0 + k, n);
    if (p.gone) continue;
    var colour = p.tint(_colour(e, v.i));
    var y = top0 + rowH * rows[k] + (rowH - barH) / 2;
    var l = sc.x(v.start);
    Rect mark;
    if (v.end == null) {
      var c = Offset(l, y + barH / 2);
      var s = dia * p.size;
      canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - s)
            ..lineTo(c.dx + s, c.dy)
            ..lineTo(c.dx, c.dy + s)
            ..lineTo(c.dx - s, c.dy)
            ..close(),
          Paint()..color = colour);
      mark = Rect.fromCircle(center: c, radius: dia);
    } else {
      var w = (sc.x(v.end!) - l) * p.size;
      mark = Rect.fromLTWH(l, y, w, barH);
      canvas.drawRRect(
          RRect.fromRectAndRadius(mark, Radius.circular(barH * 0.2)),
          Paint()..color = colour);
    }
    notePart(ChartPartKind.mark, mark, series: 0, index: v.i);
    if (!e.showXLabels || p.size < 1) continue;
    var name = e.data.categories[v.i];
    var box = switch (side[k]) {
      0 => Rect.fromLTWH(mark.left + pad, y, mark.width - pad * 2, barH),
      1 => Rect.fromLTWH(mark.right + pad, y,
          math.max(0.0, band.right - mark.right - pad), barH),
      _ => Rect.fromLTRB(
          band.left, y, math.max(band.left, mark.left - pad), y + barH),
    };
    _say(
        canvas,
        name,
        spec.copyWith(
            align: side[k] < 0 ? TextAlignSpec.right : TextAlignSpec.left,
            color: side[k] == 0 ? _ink(colour) : e.labelSpec.color,
            fontSize: math.min(fs, barH * 0.7)),
        box);
  }
}

// ------------------------------------------------------------ swimlanes

/// _lanes is the spans in a lane a group (the column it is coloured by),
/// the lanes' names in a gutter at the left.
void _lanes(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, List<_Ev> evs) {
  var groups = _groupsOf(e, evs);
  var axisH = _axisHeight(e);
  var gutter = _gutter(e, groups, area.width * 0.28);
  var plot = Rect.fromLTRB(
      area.left + gutter, area.top, area.right, area.bottom - axisH);
  var sc = _scaleOf(evs, plot.left + 4, plot.right, e: e);
  var laneH = plot.height / groups.length;
  var spec = _lab(e, align: TextAlignSpec.left).copyWith(weight: 700);
  var k0 = 0;
  for (var (g, name) in groups.indexed) {
    var lane =
        Rect.fromLTWH(plot.left, plot.top + laneH * g, plot.width, laneH);
    if (g.isOdd) canvas.drawRect(lane, Paint()..color = _quiet(e, 0.06));
    canvas.drawLine(
        lane.bottomLeft, lane.bottomRight, Paint()..color = _quiet(e, 0.18));
    var mine = [
      for (var v in evs)
        if (groups.length == 1 || e.data.groupAt(v.i) == name) v
    ];
    _say(canvas, name, spec,
        Rect.fromLTWH(area.left, lane.top, gutter - 6, lane.height));
    _spanRows(canvas, e, reveal, lane.deflate(laneH * 0.08), sc, mine, k0,
        evs.length);
    k0 += mine.length;
  }
  _axis(canvas, e, sc, plot.bottom + 2, _years(evs), _drawn(e, reveal));
}

// ------------------------------------------------------------ stems

/// _stemmed puts [evs] as dots on a line at [y] across [band], each label
/// on a stem at the first level, up or down, where it is clear of those
/// placed before it (the research's stem levels: no label over another);
/// one with no room left gets its dot alone. [hollow] draws some as rings.
void _stemmed(ui.Canvas canvas, ChartElement e, double reveal, Rect band,
    double y, _Scale sc, List<_Ev> evs,
    {bool Function(_Ev)? hollow, int k0 = 0, int? n}) {
  var count = n ?? evs.length;
  var fs = e.labelSpec.fontSize, vs = e.valueSpec.fontSize;
  var dot = math.max(4.0, fs * 0.42);
  var half = math.min(y - band.top, band.bottom - y) - dot * 2;
  var h0 = (e.showXLabels ? fs * 1.3 : 0) + vs * 1.3;
  var fit = (half / (h0 + 4)).clamp(0.45, 1.0);
  var labSpec = _lab(e, size: fs * fit);
  var figSpec = _fig(e, size: vs * fit).copyWith(weight: 800);
  var labH = e.showXLabels ? fs * 1.3 * fit : 0.0, figH = vs * 1.3 * fit;
  var h = labH + figH;
  var gap = 4.0;
  var placed = <Rect>[];
  for (var (k, v) in evs.indexed) {
    var p = sliceProgress(e, reveal, k0 + k, count);
    if (p.gone) continue;
    var x = sc.x(v.start);
    var colour = p.tint(_colour(e, v.i));
    var name = e.data.categories[v.i];
    var w = math.min(
        math.max(e.showXLabels ? _widthOf(name, labSpec) : 0.0,
                _widthOf(_when(e, v.start), figSpec)) +
            8,
        band.width * 0.3);
    Rect? box;
    for (var level = 1; level <= 6 && box == null; level++) {
      for (var up in const [true, false]) {
        var off = dot * 2 + (level - 1) * (h + gap);
        var top = up ? y - off - h : y + off;
        var left = math.max(band.left, math.min(x - w / 2, band.right - w));
        var r = Rect.fromLTWH(left, top, w, h);
        if (r.top < band.top - 0.5 || r.bottom > band.bottom + 0.5) continue;
        if (placed.any((q) => q.overlaps(r.inflate(gap / 2)))) continue;
        box = r;
        break;
      }
    }
    var stemPaint = Paint()
      ..color = colour.withValues(alpha: colour.a * 0.7)
      ..strokeWidth = math.max(1.2, dot * 0.3);
    if (box != null && p.size >= 1) {
      placed.add(box);
      var up = box.bottom <= y;
      canvas.drawLine(
          Offset(x, y), Offset(x, up ? box.bottom : box.top), stemPaint);
      var top = box.top;
      _say(canvas, _when(e, v.start), figSpec.copyWith(color: colour),
          Rect.fromLTWH(box.left, top, box.width, figH));
      if (e.showXLabels) {
        _say(canvas, name, labSpec,
            Rect.fromLTWH(box.left, top + figH, box.width, labH));
      }
    }
    var ring = hollow?.call(v) ?? false;
    canvas.drawCircle(
        Offset(x, y),
        dot * p.size.clamp(0.0, 1.0),
        Paint()
          ..color = colour
          ..style = ring ? PaintingStyle.stroke : PaintingStyle.fill
          ..strokeWidth = math.max(1.5, dot * 0.4));
    notePart(ChartPartKind.mark,
        Rect.fromCircle(center: Offset(x, y), radius: dot * 1.5),
        series: 0, index: v.i);
  }
}

// ------------------------------------------------------------ eras

/// _eras is the events with an end drawn as bands behind -- periods, eras,
/// reigns, a recession's grey bars -- their names along the top, and the
/// rest as dots on a line in front.
void _eras(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, List<_Ev> evs) {
  var eras = [
    for (var v in evs)
      if (v.end != null) v
  ];
  var points = [
    for (var v in evs)
      if (v.end == null) v
  ];
  var fs = e.labelSpec.fontSize;
  var axisH = _axisHeight(e);
  var plot =
      Rect.fromLTRB(area.left, area.top, area.right, area.bottom - axisH);
  var sc = _scaleOf(evs, plot.left, plot.right, e: e);
  var spec =
      _lab(e, align: TextAlignSpec.left, size: fs * 0.9).copyWith(weight: 700);
  var nameH = fs * 1.5;
  var (rows, count) = _pack([
    for (var v in eras)
      (
        sc.x(v.start),
        math.max(sc.x(v.end!),
            sc.x(v.start) + _widthOf(e.data.categories[v.i], spec) + 8)
      )
  ], 4);
  var namesH = nameH * count;
  for (var (k, v) in eras.indexed) {
    var p = sliceProgress(e, reveal, k, evs.length);
    if (p.gone) continue;
    var colour = _colour(e, v.i);
    var l = sc.x(v.start), r = sc.x(v.end!);
    var band = Rect.fromLTRB(
        l, plot.top + nameH * rows[k], l + (r - l) * p.size, plot.bottom);
    canvas.drawRect(
        band, Paint()..color = colour.withValues(alpha: 0.16 * p.alpha));
    canvas.drawRect(Rect.fromLTWH(band.left, band.top, band.width, 3),
        Paint()..color = p.tint(colour));
    notePart(ChartPartKind.mark, band, series: 0, index: v.i);
    if (e.showXLabels && p.size >= 1) {
      _say(
          canvas,
          e.data.categories[v.i],
          spec.copyWith(color: p.tint(colour)),
          Rect.fromLTWH(l + 4, plot.top + nameH * rows[k] + 3,
              plot.right - l - 4, nameH));
    }
  }
  var below =
      Rect.fromLTRB(plot.left, plot.top + namesH, plot.right, plot.bottom);
  var y = below.center.dy;
  var drawn = _drawn(e, reveal);
  canvas.drawLine(
      Offset(plot.left, y),
      Offset(plot.left + plot.width * drawn, y),
      Paint()
        ..color = e.axisColor
        ..strokeWidth = math.max(2, fs * 0.15));
  _stemmed(canvas, e, reveal, below, y, sc, points,
      k0: eras.length, n: evs.length);
  _axis(canvas, e, sc, plot.bottom + 2, _years(evs), drawn);
}

// ------------------------------------------------------------ value line

/// _valueLine is a line of the events' numbers over time with each event a
/// numbered marker on it, and a key below saying what each number is: the
/// story and the measure together, the markers small enough not to crowd.
void _valueLine(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, List<_Ev> evs) {
  var d = e.data;
  var s = d.series.length - 1;
  double value(_Ev v) =>
      s <= 0 || d.valueAt(s, v.i).isNaN ? 0 : d.valueAt(s, v.i);
  var fs = e.labelSpec.fontSize;
  // The key: as many columns as fit, a row of each.
  var keySpec = _lab(e, align: TextAlignSpec.left, size: fs * 0.85);
  var colW = math.max(fs * 11, area.width / 4);
  var cols = math.max(1, (area.width / colW).floor());
  var keyRows = (evs.length / cols).ceil();
  var rowH = keySpec.fontSize * 1.6;
  var keyH = math.min(keyRows * rowH, area.height * 0.4);
  rowH = keyH / keyRows;
  var axisH = _axisHeight(e);
  var gutter = fs * 3.5;
  var plot = Rect.fromLTRB(area.left + gutter, area.top + fs, area.right - fs,
      area.bottom - keyH - axisH - fs * 0.6);
  var sc = _scaleOf(evs, plot.left, plot.right, e: e);
  var vals = evs.map(value).toList();
  var lo = math.min(0.0, vals.reduce(math.min)), hi = vals.reduce(math.max);
  if (hi <= lo) hi = lo + 1;
  double yOf(double v) => plot.bottom - (v - lo) / (hi - lo) * plot.height;
  // Three guides, their figures at the left.
  var guide = Paint()
    ..color = _quiet(e, 0.14)
    ..strokeWidth = 1;
  var step = _step(hi - lo, 3);
  var figSpec = _lab(e, align: TextAlignSpec.right, size: fs * 0.8)
      .copyWith(color: _quiet(e, 0.65));
  for (var v = (lo / step).ceil() * step; v <= hi + 1e-9; v += step) {
    var y = yOf(v);
    canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), guide);
    _say(canvas, formatSeries(e, s < 0 ? 0 : s, v), figSpec,
        Rect.fromLTWH(area.left, y - fs, gutter - 6, fs * 2));
  }
  var pts = [for (var v in evs) Offset(sc.x(v.start), yOf(value(v)))];
  var line = Path();
  for (var (k, p) in pts.indexed) {
    k == 0 ? line.moveTo(p.dx, p.dy) : line.lineTo(p.dx, p.dy);
  }
  var drawn = _drawn(e, reveal);
  var series = d.series.isEmpty ? null : d.series[math.max(0, s)];
  var lineColour = series?.color ?? e.axisColor;
  for (var m in line.computeMetrics()) {
    canvas.drawPath(
        m.extractPath(0, m.length * drawn),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, fs * 0.16)
          ..strokeJoin = StrokeJoin.round
          ..color = lineColour);
  }
  _axis(canvas, e, sc, plot.bottom + fs * 0.6, _years(evs), drawn);
  // The markers, numbered, and the key.
  var r = math.max(7.0, fs * 0.72);
  var numSpec = _fig(e, size: r * 1.1).copyWith(weight: 800);
  var reached =
      pts.isEmpty ? 0.0 : pts.first.dx + (pts.last.dx - pts.first.dx) * drawn;
  for (var (k, v) in evs.indexed) {
    var p = sliceProgress(e, reveal, k, evs.length);
    if (p.gone || pts[k].dx > reached + 0.5) continue;
    var colour = p.tint(_colour(e, v.i));
    var at = pts[k];
    canvas.drawCircle(at, r * p.size.clamp(0.0, 1.0) + 2,
        Paint()..color = e.panel.a > 0 ? e.panel : const Color(0x00000000));
    canvas.drawCircle(at, r * p.size.clamp(0.0, 1.0), Paint()..color = colour);
    notePart(ChartPartKind.mark, Rect.fromCircle(center: at, radius: r * 1.4),
        series: 0, index: v.i);
    if (p.size < 1) continue;
    _say(canvas, "${k + 1}", numSpec.copyWith(color: _ink(colour)),
        Rect.fromCircle(center: at, radius: r));
    // Its line in the key.
    var col = k ~/ keyRows, row = k % keyRows;
    var cell = Rect.fromLTWH(area.left + col * (area.width / cols),
        area.bottom - keyH + row * rowH, area.width / cols, rowH);
    var kr = math.min(r, rowH * 0.42);
    var c = Offset(cell.left + kr, cell.center.dy);
    canvas.drawCircle(c, kr, Paint()..color = colour);
    _say(
        canvas,
        "${k + 1}",
        numSpec.copyWith(color: _ink(colour), fontSize: kr * 1.1),
        Rect.fromCircle(center: c, radius: kr));
    var words = e.showXLabels
        ? "${d.categories[v.i]} · ${_when(e, v.start)}"
        : _when(e, v.start);
    if (s > 0 && e.showValues) words += " · ${formatSeries(e, s, value(v))}";
    _say(canvas, words, keySpec,
        Rect.fromLTRB(c.dx + kr + 6, cell.top, cell.right - 6, cell.bottom));
  }
}

// ------------------------------------------------------------ cards

/// _cards is each event a card -- its date large, its name, a line about it
/// (the row's point name) -- either side of a spine down the middle, evenly
/// spaced: the stepping stones of a story told in order.
void _cards(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, List<_Ev> evs) {
  var n = evs.length;
  var spine = area.center.dx;
  var gapY = 8.0;
  // Cards alternate sides, so one only has to clear the one two on: at
  // most this tall, the first and last inside the box.
  var cardH = n <= 1
      ? area.height
      : math.max(4.0, (2 * area.height - gapY * (n - 1)) / (n + 1));
  cardH = math.min(cardH, area.height);
  var gap = math.max(14.0, area.width * 0.03);
  var cardW = area.width / 2 - gap;
  var fs = e.labelSpec.fontSize, vs = e.valueSpec.fontSize;
  var any = evs.any((v) => e.data.pointNameAt(v.i).isNotEmpty);
  var need = vs * 1.6 + (e.showXLabels ? fs * 1.4 : 0) + (any ? fs * 2.5 : 0);
  var pad = math.min(fs * 0.6, cardH * 0.08);
  var fit = ((cardH - pad * 2) / need).clamp(0.4, 1.0);
  cardH = math.min(cardH, need * fit + pad * 2);
  var drawn = _drawn(e, reveal);
  canvas.drawLine(
      Offset(spine, area.top),
      Offset(spine, area.top + area.height * drawn),
      Paint()
        ..color = _quiet(e, 0.35)
        ..strokeWidth = 2);
  var dot = math.max(4.0, fs * 0.4);
  for (var (k, v) in evs.indexed) {
    var p = sliceProgress(e, reveal, k, n);
    if (p.gone) continue;
    var colour = _colour(e, v.i);
    var y = n <= 1
        ? area.center.dy
        : area.top + cardH / 2 + (area.height - cardH) * k / (n - 1);
    var left = k.isEven;
    // Sliding in from the spine as it arrives.
    var slide = (1 - p.size.clamp(0.0, 1.0)) * gap;
    var card = Rect.fromLTWH(
        left ? spine - gap - cardW + slide : spine + gap - slide,
        y - cardH / 2,
        cardW,
        cardH);
    canvas.drawCircle(Offset(spine, y), dot, Paint()..color = p.tint(colour));
    canvas.drawLine(
        Offset(spine, y),
        Offset(left ? card.right : card.left, y),
        Paint()
          ..color = p.tint(colour.withValues(alpha: 0.6))
          ..strokeWidth = 1.5);
    canvas.saveLayer(
        card.inflate(2),
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, p.alpha * p.size.clamp(0.0, 1.0)));
    canvas.drawRRect(RRect.fromRectAndRadius(card, const Radius.circular(8)),
        Paint()..color = colour.withValues(alpha: 0.12));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(
                left ? card.right - 4 : card.left, card.top, 4, card.height),
            const Radius.circular(2)),
        Paint()..color = colour);
    notePart(ChartPartKind.mark, card, series: 0, index: v.i);
    var align = left ? TextAlignSpec.right : TextAlignSpec.left;
    var inner = card.deflate(pad).translate(left ? -4 : 4, 0);
    var top = inner.top;
    var figH = vs * 1.6 * fit;
    _say(
        canvas,
        _when(e, v.start) + (v.end == null ? "" : "–${_when(e, v.end!)}"),
        _fig(e, align: align, size: vs * 1.25 * fit)
            .copyWith(color: colour, weight: 800),
        Rect.fromLTWH(inner.left, top, inner.width, figH));
    top += figH;
    if (e.showXLabels) {
      var h = fs * 1.4 * fit;
      _say(
          canvas,
          e.data.categories[v.i],
          _lab(e, align: align, size: fs * fit).copyWith(weight: 700),
          Rect.fromLTWH(inner.left, top, inner.width, h));
      top += h;
    }
    var about = e.data.pointNameAt(v.i);
    if (about.isNotEmpty && inner.bottom - top > fs * 0.8 * fit) {
      _say(
          canvas,
          about,
          _lab(e, align: align, size: fs * 0.82 * fit)
              .copyWith(color: _quiet(e, 0.75))
              .copyWith(verticalAlign: VerticalAlignSpec.top),
          Rect.fromLTRB(inner.left, top, inner.right, inner.bottom));
    }
    canvas.restore();
  }
}

// ------------------------------------------------------------ bubbles

/// _bubbles is each event a circle at its date, its area by its number --
/// a lane a group -- so the big moments stand out; the largest named
/// where there is room.
void _bubbles(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, List<_Ev> evs) {
  var d = e.data;
  var s = d.series.length - 1;
  double value(_Ev v) =>
      s <= 0 || d.valueAt(s, v.i).isNaN ? 1 : d.valueAt(s, v.i).abs();
  var groups = _groupsOf(e, evs);
  var axisH = _axisHeight(e);
  var gutter = groups.length > 1 ? _gutter(e, groups, area.width * 0.24) : 0.0;
  var plot = Rect.fromLTRB(
      area.left + gutter, area.top, area.right, area.bottom - axisH);
  var laneH = plot.height / groups.length;
  var most = evs.map(value).fold(0.0, math.max);
  if (most <= 0) most = 1;
  var maxR = math.min(laneH * 0.46, plot.width * 0.07);
  var sc = _scaleOf(evs, plot.left + maxR, plot.right - maxR, e: e);
  var fs = e.labelSpec.fontSize;
  var laneSpec = _lab(e, align: TextAlignSpec.left).copyWith(weight: 700);
  var marks = <(int, Offset, double)>[];
  for (var (g, name) in groups.indexed) {
    var y = plot.top + laneH * (g + 0.5);
    canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y),
        Paint()..color = _quiet(e, 0.18));
    if (gutter > 0) {
      _say(canvas, name, laneSpec,
          Rect.fromLTWH(area.left, y - laneH / 2, gutter - 6, laneH));
    }
    for (var (k, v) in evs.indexed) {
      if (groups.length > 1 && d.groupAt(v.i) != name) continue;
      var r = math.max(3.0, math.sqrt(value(v) / most) * maxR);
      marks.add((k, Offset(sc.x(v.start), y), r));
    }
  }
  // Largest at the back, so the small ones show.
  marks.sort((a, b) => b.$3.compareTo(a.$3));
  for (var (k, at, r) in marks) {
    var v = evs[k];
    var p = sliceProgress(e, reveal, k, evs.length);
    if (p.gone) continue;
    var colour = _colour(e, v.i);
    var rr = r * p.size.clamp(0.0, 1.0);
    canvas.drawCircle(
        at, rr, Paint()..color = colour.withValues(alpha: 0.5 * p.alpha));
    canvas.drawCircle(
        at,
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = p.tint(colour));
    notePart(ChartPartKind.mark, Rect.fromCircle(center: at, radius: r),
        series: 0, index: v.i);
  }
  if (e.showXLabels) {
    var placer = LabelPlacer(area);
    var spec = _lab(e, size: fs * 0.85);
    for (var (k, at, r) in marks) {
      if (sliceProgress(e, reveal, k, evs.length).size < 1) continue;
      var v = evs[k];
      var words = e.showValues && s > 0
          ? "${d.categories[v.i]} ${formatSeries(e, s, value(v))}"
          : d.categories[v.i];
      var size = labelSize(words, spec);
      var box = Size(size.width + 4, size.height);
      var got = placer.place(r > box.width * 0.55 && r * 2 > box.height * 1.2
          ? [Rect.fromCenter(center: at, width: box.width, height: box.height)]
          : LabelPlacer.around(at, box, r));
      if (got == null) continue;
      _say(
          canvas,
          words,
          spec.copyWith(
              color: got.contains(at)
                  ? _ink(_colour(e, v.i).withValues(alpha: 1))
                  : e.labelSpec.color),
          got);
    }
  }
  _axis(canvas, e, sc, plot.bottom + 2, _years(evs), _drawn(e, reveal));
}

// ------------------------------------------------------------ serpentine

/// _serpentine is the line folded down the page, a row at a time with a
/// half circle at each turn -- a long story told in little room, the line
/// drawing on as it plays and each event arriving as it reaches it.
void _serpentine(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, List<_Ev> evs) {
  var n = evs.length;
  var fs = e.labelSpec.fontSize, vs = e.valueSpec.fontSize;
  var per = (area.width / (fs * 10)).round().clamp(2, 6);
  if (n <= per) per = n;
  var rows = (n / per).ceil();
  var rowH = area.height / rows;
  var r = rowH / 2;
  var left = area.left + (rows > 1 ? r : 0),
      right = area.right - (rows > 1 ? r : 0);
  double yOf(int row) => area.top + rowH * row + rowH * 0.28;
  // The path, and how far along it each event sits.
  var path = Path()..moveTo(left, yOf(0));
  var along = <double>[];
  var run = 0.0;
  var rowLen = right - left, turn = math.pi * r;
  for (var row = 0; row < rows; row++) {
    var forward = row.isEven;
    var y = yOf(row);
    for (var j = 0; j < per && row * per + j < n; j++) {
      along.add(run + rowLen * (j + 0.5) / per);
    }
    path.lineTo(forward ? right : left, y);
    run += rowLen;
    if (row < rows - 1) {
      var x = forward ? right : left;
      path.arcToPoint(Offset(x, yOf(row + 1)),
          radius: Radius.circular(r), clockwise: forward);
      run += turn;
    }
  }
  var drawn = _drawn(e, reveal);
  var reach = run * drawn;
  var line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(3, fs * 0.3)
    ..strokeCap = StrokeCap.round
    ..color = e.axisColor;
  var total = 0.0;
  for (var m in path.computeMetrics()) {
    var take = (reach - total).clamp(0.0, m.length);
    if (take > 0) canvas.drawPath(m.extractPath(0, take), line);
    total += m.length;
  }
  var dot = math.max(5.0, fs * 0.5);
  var cell = rowLen / per;
  var labH = rowH * 0.62 - dot * 2;
  var need = vs * 1.4 + (e.showXLabels ? fs * 2.6 : 0);
  var fit = (labH / need).clamp(0.4, 1.0);
  for (var (k, v) in evs.indexed) {
    if (along[k] > reach + 0.5) continue;
    var p = sliceProgress(e, reveal, k, n);
    if (p.gone) continue;
    var row = k ~/ per, j = k % per;
    var t = (j + 0.5) / per;
    var x = row.isEven ? left + rowLen * t : right - rowLen * t;
    var y = yOf(row);
    var colour = p.tint(_colour(e, v.i));
    canvas.drawCircle(Offset(x, y), dot + 2, Paint()..color = e.axisColor);
    canvas.drawCircle(
        Offset(x, y), dot * p.size.clamp(0.0, 1.0), Paint()..color = colour);
    notePart(ChartPartKind.mark,
        Rect.fromCircle(center: Offset(x, y), radius: dot * 1.6),
        series: 0, index: v.i);
    if (p.size < 1) continue;
    var top = y + dot * 2;
    var figH = vs * 1.4 * fit;
    _say(
        canvas,
        _when(e, v.start),
        _fig(e, size: vs * fit).copyWith(weight: 800, color: colour),
        Rect.fromLTWH(x - cell * 0.46, top, cell * 0.92, figH));
    if (e.showXLabels) {
      _say(
          canvas,
          e.data.categories[v.i],
          _lab(e, size: fs * fit)
              .copyWith(verticalAlign: VerticalAlignSpec.top),
          Rect.fromLTWH(
              x - cell * 0.46, top + figH, cell * 0.92, fs * 2.6 * fit));
    }
  }
}

// ------------------------------------------------------------ progress

/// timelineNow is today as a timeline of years reads it: the year, and how
/// far through it. Set by tests for a picture that keeps still.
double Function() timelineNow = () {
  var t = DateTime.now();
  var start = DateTime(t.year);
  var days = DateTime(t.year + 1).difference(start).inDays;
  return t.year + t.difference(start).inDays / days;
};

/// _progress is the line solid up to today and dashed after it, today
/// marked, the events behind it filled and those ahead of it rings: a
/// roadmap, "we are here". Dates that aren't years have no today; the
/// latest event is where it is then.
void _progress(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, List<_Ev> evs) {
  var years = _years(evs);
  var now = years ? timelineNow() : evs.last.start;
  var fs = e.labelSpec.fontSize;
  var axisH = _axisHeight(e);
  var pillH = fs * 1.6;
  var plot = Rect.fromLTRB(
      area.left, area.top + pillH + 4, area.right, area.bottom - axisH);
  var sc = _scaleOf(evs, plot.left, plot.right, also: now, e: e);
  var y = plot.center.dy;
  var drawn = _drawn(e, reveal);
  var xNow = sc.x(now);
  var reach = plot.left + plot.width * drawn;
  var solid = Paint()
    ..color = e.axisColor
    ..strokeWidth = math.max(3, fs * 0.28)
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(
      Offset(plot.left, y), Offset(math.min(xNow, reach), y), solid);
  // Ahead, dashed and fainter.
  var dash = fs * 0.6;
  var faint = Paint()
    ..color = e.axisColor.withValues(alpha: e.axisColor.a * 0.5)
    ..strokeWidth = math.max(2, fs * 0.2)
    ..strokeCap = StrokeCap.round;
  for (var x = xNow; x < math.min(plot.right, reach); x += dash * 2) {
    canvas.drawLine(Offset(x, y), Offset(math.min(x + dash, reach), y), faint);
  }
  _stemmed(canvas, e, reveal, plot, y, sc, evs, hollow: (v) => v.start > now);
  if (reach >= xNow) {
    var accent =
        e.data.series.isEmpty ? e.axisColor : e.data.series.first.color;
    canvas.drawLine(
        Offset(xNow, area.top + pillH),
        Offset(xNow, plot.bottom),
        Paint()
          ..color = accent
          ..strokeWidth = 2);
    var said = years ? "Today" : "Latest";
    var spec = _lab(e, size: fs * 0.85).copyWith(weight: 800);
    var w = _widthOf(said, spec) + fs;
    var pill = Rect.fromLTWH(
        math.max(area.left, math.min(xNow - w / 2, area.right - w)),
        area.top,
        w,
        pillH);
    canvas.drawRRect(RRect.fromRectAndRadius(pill, Radius.circular(pillH / 2)),
        Paint()..color = accent);
    _say(canvas, said, spec.copyWith(color: _ink(accent)), pill);
  }
  _axis(canvas, e, sc, plot.bottom + 2, years, drawn);
}

// ------------------------------------------------------------ zoom

/// _window is the busiest stretch of [evs]: the third of their span with
/// the most events in it.
(double, double) _window(List<_Ev> evs) {
  var lo = evs.first.start, hi = evs.map((v) => v.last).reduce(math.max);
  var span = hi - lo;
  if (span <= 0) return (lo - 1, hi + 1);
  var w = span / 3;
  var best = (lo, lo + w), most = -1;
  for (var v in evs) {
    var a = v.start, b = v.start + w;
    var n = evs.where((x) => x.start >= a && x.start <= b).length;
    if (n > most) {
      most = n;
      best = (a, b);
    }
  }
  // A little room either side of what is in it.
  return (best.$1 - w * 0.08, best.$2 + w * 0.08);
}

/// _zoom is the whole story along a thin strip at the top, its busiest
/// stretch lit, and that stretch drawn large under it with its events
/// named: focus and context, so a crowded few years can be read without
/// losing where they sit.
void _zoom(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, List<_Ev> evs) {
  var fs = e.labelSpec.fontSize;
  var stripH = math.max(fs * 3.2, area.height * 0.2);
  var strip = Rect.fromLTWH(area.left, area.top, area.width, stripH);
  var whole = _scaleOf(evs, strip.left + 6, strip.right - 6);
  var (w0, w1) = _window(evs);
  var y0 = strip.top + stripH * 0.42;
  var drawn = _drawn(e, reveal);
  canvas.drawLine(
      Offset(whole.left, y0),
      Offset(whole.left + (whole.right - whole.left) * drawn, y0),
      Paint()
        ..color = _quiet(e, 0.5)
        ..strokeWidth = 1.5);
  var lit = Rect.fromLTRB(whole.x(w0), strip.top + 2, whole.x(w1), y0 + 8);
  var accent = e.data.series.isEmpty ? e.axisColor : e.data.series.first.color;
  canvas.drawRRect(RRect.fromRectAndRadius(lit, const Radius.circular(4)),
      Paint()..color = accent.withValues(alpha: 0.16));
  canvas.drawRRect(
      RRect.fromRectAndRadius(lit, const Radius.circular(4)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = accent.withValues(alpha: 0.7));
  for (var v in evs) {
    var x = whole.x(v.start);
    canvas.drawLine(
        Offset(x, y0 - 6),
        Offset(x, y0 + 6),
        Paint()
          ..color = _colour(e, v.i)
          ..strokeWidth = 2);
  }
  var small = _lab(e, size: fs * 0.75).copyWith(color: _quiet(e, 0.7));
  _say(canvas, _when(e, evs.first.start), small,
      Rect.fromLTWH(whole.left, y0 + 8, fs * 4, fs * 1.2));
  _say(canvas, _when(e, evs.map((v) => v.last).reduce(math.max)), small,
      Rect.fromLTWH(whole.right - fs * 4, y0 + 8, fs * 4, fs * 1.2));
  // The stretch, large.
  var axisH = _axisHeight(e);
  var detail = Rect.fromLTRB(
      area.left, strip.bottom + fs * 1.6, area.right, area.bottom - axisH);
  var inside = [
    for (var v in evs)
      if (v.start >= w0 && v.start <= w1) v
  ];
  var sc = _Scale(w0, w1, detail.left + 6, detail.right - 6);
  // The lit stretch opening out onto it.
  canvas.drawPath(
      Path()
        ..moveTo(lit.left, lit.bottom)
        ..lineTo(detail.left, detail.top)
        ..lineTo(detail.right, detail.top)
        ..lineTo(lit.right, lit.bottom)
        ..close(),
      Paint()..color = accent.withValues(alpha: 0.06));
  var y = detail.center.dy;
  canvas.drawLine(
      Offset(detail.left, y),
      Offset(detail.left + detail.width * drawn, y),
      Paint()
        ..color = e.axisColor
        ..strokeWidth = math.max(2, fs * 0.15));
  _stemmed(canvas, e, reveal, detail, y, sc, inside);
  // Those outside it still noted, as marks the Charts tab can find.
  for (var v in evs) {
    if (inside.contains(v)) continue;
    notePart(ChartPartKind.mark,
        Rect.fromCircle(center: Offset(whole.x(v.start), y0), radius: 6),
        series: 0, index: v.i);
  }
  _axis(canvas, e, sc, detail.bottom + 2, _years(evs), drawn);
}

// ------------------------------------------------------------ spiral

/// _spiral is time wound outwards from the middle, a turn every so many
/// years: a long story in a square, its rhythm -- what comes round again --
/// easier to see than its gaps (the research's caveat: it bends lengths,
/// so it is for the look, not for comparing).
void _spiral(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, List<_Ev> evs) {
  var lo = evs.first.start, hi = evs.map((v) => v.last).reduce(math.max);
  if (hi <= lo) hi = lo + 1;
  var c = area.center;
  var fs = e.labelSpec.fontSize;
  var outer = area.shortestSide / 2 - fs * 2.2;
  var inner = outer * 0.16;
  var turns = (evs.length / 4).clamp(1.5, 3.0);
  Offset at(double u) {
    var a = -math.pi / 2 + u * turns * 2 * math.pi;
    var r = inner + (outer - inner) * u;
    return c + Offset(math.cos(a), math.sin(a)) * r;
  }

  double u(double v) => ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
  var drawn = _drawn(e, reveal);
  var path = Path();
  const steps = 240;
  for (var k = 0; k <= steps * drawn; k++) {
    var p = at(k / steps);
    k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, fs * 0.18)
        ..strokeCap = StrokeCap.round
        ..color = _quiet(e, 0.45));
  var dot = math.max(4.0, fs * 0.45);
  var placer = LabelPlacer(area, keepClear: [
    for (var v in evs) Rect.fromCircle(center: at(u(v.start)), radius: dot)
  ]);
  var labSpec = _lab(e, size: fs * 0.85);
  var figSpec =
      _fig(e, size: e.valueSpec.fontSize * 0.85).copyWith(weight: 800);
  for (var (k, v) in evs.indexed) {
    if (u(v.start) > drawn + 1e-6) continue;
    var p = sliceProgress(e, reveal, k, evs.length);
    if (p.gone) continue;
    var colour = p.tint(_colour(e, v.i));
    var o = at(u(v.start));
    canvas.drawCircle(o, dot * p.size.clamp(0.0, 1.0), Paint()..color = colour);
    notePart(ChartPartKind.mark, Rect.fromCircle(center: o, radius: dot * 1.6),
        series: 0, index: v.i);
    if (p.size < 1) continue;
    var name = e.showXLabels ? e.data.categories[v.i] : "";
    var when = _when(e, v.start);
    var w = math.max(_widthOf(name, labSpec), _widthOf(when, figSpec)) + 6;
    var h =
        (name.isEmpty ? 0 : labSpec.fontSize * 1.3) + figSpec.fontSize * 1.3;
    // Away from the middle first.
    var out = o - c;
    var d = out.distance < 1 ? const Offset(0, -1) : out / out.distance;
    var reach = dot + 4;
    var first = Rect.fromCenter(
        center: o + d * (reach + math.max(w, h) / 2), width: w, height: h);
    var got =
        placer.place([first, ...LabelPlacer.around(o, Size(w, h), reach)]);
    if (got == null) continue;
    _say(canvas, when, figSpec.copyWith(color: colour),
        Rect.fromLTWH(got.left, got.top, got.width, figSpec.fontSize * 1.3));
    if (name.isNotEmpty) {
      _say(
          canvas,
          name,
          labSpec,
          Rect.fromLTWH(got.left, got.top + figSpec.fontSize * 1.3, got.width,
              labSpec.fontSize * 1.3));
    }
  }
}

// ------------------------------------------------------------ then and now

/// _thenNow is the first event and the last side by side, large -- their
/// dates, names, numbers and words -- with the time between them, and how
/// much its number changed, on the line joining them; the events between
/// as small marks on that line.
void _thenNow(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, List<_Ev> evs) {
  var d = e.data;
  var first = evs.first, last = evs.last;
  var s = d.series.length - 1;
  double? value(_Ev v) =>
      s <= 0 || d.valueAt(s, v.i).isNaN ? null : d.valueAt(s, v.i);
  var fs = e.labelSpec.fontSize, vs = e.valueSpec.fontSize;
  var cardW = area.width * 0.34;
  var left = Rect.fromLTWH(area.left, area.top, cardW, area.height);
  var right = Rect.fromLTWH(area.right - cardW, area.top, cardW, area.height);
  var p = _drawn(e, reveal);
  void card(Rect r, _Ev v, String said, int k) {
    var sp = sliceProgress(e, reveal, k, 2);
    if (sp.gone) return;
    var colour = _colour(e, v.i);
    canvas.saveLayer(
        r.inflate(2),
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, sp.alpha * sp.size.clamp(0, 1)));
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(12)),
        Paint()..color = colour.withValues(alpha: 0.12));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(r.left, r.top, r.width, 5), const Radius.circular(3)),
        Paint()..color = colour);
    notePart(ChartPartKind.mark, r, series: 0, index: v.i);
    var inner = r.deflate(math.min(fs, r.width * 0.08));
    var lines = <(String, TextSpec, double)>[
      (said, _lab(e, size: fs * 0.8).copyWith(color: _quiet(e, 0.7)), 1.3),
      (
        _when(e, v.start),
        _fig(e, size: vs * 2.4).copyWith(weight: 800, color: colour),
        1.15
      ),
      if (e.showXLabels)
        (d.categories[v.i], _lab(e, size: fs * 1.1).copyWith(weight: 700), 1.4),
      if (value(v) case var x?)
        (
          formatSeries(e, s, x),
          _fig(e, size: vs * 1.3).copyWith(weight: 700),
          1.4
        ),
      if (d.pointNameAt(v.i).isNotEmpty)
        (
          d.pointNameAt(v.i),
          _lab(e, size: fs * 0.85)
              .copyWith(color: _quiet(e, 0.75))
              .copyWith(verticalAlign: VerticalAlignSpec.top),
          3.6
        ),
    ];
    var need = lines.fold(0.0, (t, l) => t + l.$2.fontSize * l.$3);
    var fit = (inner.height / need).clamp(0.4, 1.0);
    var y = inner.top + (inner.height - need * fit) / 2;
    for (var (words, spec, h) in lines) {
      var hh = spec.fontSize * h * fit;
      _say(canvas, words, spec.copyWith(fontSize: spec.fontSize * fit),
          Rect.fromLTWH(inner.left, y, inner.width, hh));
      y += hh;
    }
    canvas.restore();
  }

  card(left, first, "Then", 0);
  card(right, last, "Now", 1);
  // Between: the line, the events on it, the years and the change.
  var a = Offset(left.right + fs, area.center.dy),
      b = Offset(right.left - fs, area.center.dy);
  canvas.drawLine(
      a,
      Offset.lerp(a, b, p)!,
      Paint()
        ..color = _quiet(e, 0.5)
        ..strokeWidth = 2);
  var span = last.start - first.start;
  for (var v in evs.skip(1).take(evs.length - 2)) {
    var t = span <= 0 ? 0.5 : (v.start - first.start) / span;
    if (t > p) continue;
    var x = Offset.lerp(a, b, t)!;
    canvas.drawCircle(x, 3.5, Paint()..color = _colour(e, v.i));
    notePart(ChartPartKind.mark, Rect.fromCircle(center: x, radius: 6),
        series: 0, index: v.i);
  }
  if (p < 1) return;
  var mid = Rect.fromCenter(
      center: (a + b) / 2 - Offset(0, fs * 1.4),
      width: (b - a).distance,
      height: fs * 1.6);
  _say(canvas, _gapWords(span, _years(evs), e),
      _lab(e, size: fs * 0.95).copyWith(weight: 700), mid);
  if (value(first) case var x0?) {
    if (value(last) case var x1?) {
      var change = x1 - x0;
      var by = x0 != 0 && x1 / x0 >= 2
          ? "×${(x1 / x0).toStringAsFixed(x1 / x0 >= 10 ? 0 : 1)}"
          : "${change >= 0 ? "+" : ""}${formatSeries(e, s, change)}";
      _say(canvas, by, _fig(e, size: vs * 1.1).copyWith(weight: 800),
          mid.shift(Offset(0, fs * 2.8)));
    }
  }
}

// ------------------------------------------------------------ strip

/// _strip is every event a thin tick along one line, with how crowded each
/// stretch is drawn as a soft hill over it: for many events, where the
/// pattern is the story. Only a few are named -- the first, the last and
/// the largest by their number -- where there is room.
void _strip(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, List<_Ev> evs) {
  var d = e.data;
  var s = d.series.length - 1;
  double value(_Ev v) =>
      s <= 0 || d.valueAt(s, v.i).isNaN ? 0 : d.valueAt(s, v.i).abs();
  var fs = e.labelSpec.fontSize;
  var axisH = _axisHeight(e);
  var plot = Rect.fromLTRB(
      area.left, area.top + fs * 1.6, area.right, area.bottom - axisH);
  var sc = _scaleOf(evs, plot.left, plot.right, e: e);
  var base = plot.top + plot.height * 0.72;
  var tick = plot.height * 0.16;
  var drawn = _drawn(e, reveal);
  var reach = plot.left + plot.width * drawn;
  // How crowded: a gentle hill from the events near each place.
  var accent = e.data.series.isEmpty ? e.axisColor : e.data.series.first.color;
  var bw = (sc.hi - sc.lo) / 14;
  double density(double v) {
    var t = 0.0;
    for (var x in evs) {
      var z = (v - x.start) / bw;
      t += math.exp(-z * z / 2);
    }
    return t;
  }

  var peak = 0.0;
  const steps = 120;
  var ds = [
    for (var k = 0; k <= steps; k++)
      density(sc.lo + (sc.hi - sc.lo) * k / steps)
  ];
  for (var v in ds) {
    peak = math.max(peak, v);
  }
  if (peak > 0) {
    var hillTop = plot.top + fs * 0.4;
    var hill = Path()..moveTo(sc.left, base - tick);
    for (var k = 0; k <= steps; k++) {
      var x = sc.left + (sc.right - sc.left) * k / steps;
      if (x > reach) break;
      hill.lineTo(x, base - tick - (base - tick - hillTop) * ds[k] / peak);
    }
    hill.lineTo(math.min(reach, sc.right), base - tick);
    hill.close();
    canvas.drawPath(hill, Paint()..color = accent.withValues(alpha: 0.14));
  }
  canvas.drawLine(
      Offset(plot.left, base),
      Offset(reach, base),
      Paint()
        ..color = _quiet(e, 0.5)
        ..strokeWidth = 1.2);
  for (var (k, v) in evs.indexed) {
    var x = sc.x(v.start);
    if (x > reach + 0.5) continue;
    var p = sliceProgress(e, reveal, k, evs.length);
    if (p.gone) continue;
    canvas.drawLine(
        Offset(x, base - tick * p.size.clamp(0.0, 1.0)),
        Offset(x, base),
        Paint()
          ..color = p.tint(_colour(e, v.i)).withValues(alpha: 0.85)
          ..strokeWidth = math.max(1.5, fs * 0.14));
    notePart(ChartPartKind.mark, Rect.fromLTRB(x - 3, base - tick, x + 3, base),
        series: 0, index: v.i);
  }
  // A few named: the first, the last, then the largest.
  var named = <_Ev>[evs.first, if (evs.length > 1) evs.last];
  var byValue = [...evs]..sort((a, b) => value(b).compareTo(value(a)));
  for (var v in byValue) {
    if (named.length >= 5) break;
    if (!named.contains(v) && value(v) > 0) named.add(v);
  }
  var placer = LabelPlacer(plot);
  var spec = _lab(e, size: fs * 0.85);
  if (drawn >= 1 && e.showXLabels) {
    for (var v in named) {
      var words = "${d.categories[v.i]} ${_when(e, v.start)}";
      var size = labelSize(words, spec);
      var x = sc.x(v.start);
      var got = placer.place([
        Rect.fromLTWH(x - size.width / 2, base + 4, size.width, size.height),
        Rect.fromLTWH(x + 4, base + 4, size.width, size.height),
        Rect.fromLTWH(x - size.width - 4, base + 4, size.width, size.height),
      ]);
      if (got == null) continue;
      _say(canvas, words, spec, got);
    }
  }
  _say(
      canvas,
      "${evs.length} events",
      _lab(e, align: TextAlignSpec.left, size: fs * 0.85)
          .copyWith(color: _quiet(e, 0.7)),
      Rect.fromLTWH(area.left, area.top, area.width / 2, fs * 1.4));
  _axis(canvas, e, sc, plot.bottom + 2, _years(evs), drawn);
}

// ------------------------------------------------------------ aligned

/// _aligned is each group's events measured from that group's first, a
/// lane a group, all starting together at nought: how long each took to
/// get from its start to each step, not when (the research's "aligned at
/// zero" -- careers, products, seasons compared).
void _aligned(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal, List<_Ev> evs) {
  var groups = _groupsOf(e, evs);
  var starts = <String, double>{};
  for (var v in evs) {
    var g = groups.length == 1 ? "" : e.data.groupAt(v.i);
    starts[g] = math.min(starts[g] ?? double.infinity, v.start);
  }
  double from(_Ev v) =>
      starts[groups.length == 1 ? "" : e.data.groupAt(v.i)] ?? v.start;
  var moved = [
    for (var v in evs)
      _Ev(v.i, v.start - from(v), v.end == null ? null : v.end! - from(v))
  ];
  var axisH = _axisHeight(e);
  var gutter = groups.length > 1 ? _gutter(e, groups, area.width * 0.26) : 0.0;
  var plot = Rect.fromLTRB(
      area.left + gutter, area.top, area.right, area.bottom - axisH);
  var lo = 0.0, hi = moved.map((v) => v.last).reduce(math.max);
  if (hi <= 0) hi = 1;
  var sc = _Scale(lo - hi * 0.03, hi * 1.04, plot.left + 4, plot.right);
  var laneH = plot.height / groups.length;
  var spec = _lab(e, align: TextAlignSpec.left).copyWith(weight: 700);
  var zero = sc.x(0);
  canvas.drawLine(
      Offset(zero, plot.top),
      Offset(zero, plot.bottom),
      Paint()
        ..color = _quiet(e, 0.5)
        ..strokeWidth = 1.5);
  var k0 = 0;
  for (var (g, name) in groups.indexed) {
    var lane =
        Rect.fromLTWH(plot.left, plot.top + laneH * g, plot.width, laneH);
    if (g.isOdd) canvas.drawRect(lane, Paint()..color = _quiet(e, 0.06));
    var mine = [
      for (var v in moved)
        if (groups.length == 1 || e.data.groupAt(v.i) == name) v
    ]..sort((a, b) => a.start.compareTo(b.start));
    if (gutter > 0) {
      _say(canvas, name, spec,
          Rect.fromLTWH(area.left, lane.top, gutter - 6, lane.height));
    }
    _spanRows(canvas, e, reveal, lane.deflate(laneH * 0.08), sc, mine, k0,
        evs.length);
    k0 += mine.length;
  }
  // Its axis in time since the start: "+3 yrs".
  var y = plot.bottom + 2;
  var drawn = _drawn(e, reveal);
  var line = Paint()
    ..color = _quiet(e, 0.45)
    ..strokeWidth = 1.2;
  canvas.drawLine(Offset(sc.left, y),
      Offset(sc.left + (sc.right - sc.left) * drawn, y), line);
  var small = _lab(e, size: e.labelSpec.fontSize * 0.85)
      .copyWith(color: _quiet(e, 0.7));
  var room = e.labelSpec.fontSize * 4.5;
  var years = _years(evs);
  var step = _step(hi, ((sc.right - sc.left) / room).floor().clamp(2, 10),
      whole: years);
  for (var v = 0.0; v <= hi + 1e-9; v += step) {
    var x = sc.x(v);
    canvas.drawLine(Offset(x, y), Offset(x, y + 5), line);
    _say(
        canvas,
        v == 0 ? "start" : "+${_gapWords(v, years, e).replaceAll("+", "")}",
        small,
        Rect.fromCenter(
            center: Offset(x, y + 5 + small.fontSize * 0.75),
            width: room,
            height: small.fontSize * 1.5));
  }
}
