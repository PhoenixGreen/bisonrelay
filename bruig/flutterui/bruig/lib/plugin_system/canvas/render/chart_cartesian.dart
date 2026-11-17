import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/chart_words.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/render/chart_infographic.dart'
    show inkOn;
import 'package:bruig/plugin_system/canvas/render/label_placer.dart';
import 'package:flutter/foundation.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/painting.dart';
import 'package:bruig/plugin_system/canvas/export/vector_canvas.dart';

// chart_cartesian.dart draws every chart with an x and a y axis: bars,
// grouped, stacked and horizontal bars, lines, areas and scatter. The value
// axis ends on round numbers (_niceRange). The plot is what is left once
// titles, ticks and names take the room they measure, never a guessed margin.

/// _ValueRange is the axis and its ticks, worked out together.
class _ValueRange {
  final double min;
  final double max;
  final List<double> ticks;

  /// log is whether the axis is spaced by decades. See [_logRange].
  final bool log;

  const _ValueRange(this.min, this.max, this.ticks, {this.log = false});

  double get span => max - min == 0 ? 1 : max - min;

  /// fraction is where [v] sits along the axis, 0 at the bottom. On a log
  /// axis zero and below sit at the bottom, not at minus infinity: a bar's
  /// base is asked for as fraction(0) whatever the data.
  double fraction(double v) {
    if (!log) return (v - min) / span;
    if (v <= 0 || min <= 0 || max <= min) return 0;
    return (math.log(v) - math.log(min)) / (math.log(max) - math.log(min));
  }
}

/// acrossRange is a scatter's numbers across, where every category is a
/// number: a true x-y plot, its points placed on an axis of their own. Null
/// for any other chart, or where a category is not a number.
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

/// acrossValuesOf is each category as a number; null if any is not, or < 2.
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
/// lines: every round step near the right size is tried and the closest to
/// the count kept, since rounding to 1, 2, 2.5 or 5 ignores the count.
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

/// _logRange picks an axis by decades: 1, 10, 100, 1000, the ends pushed out
/// to whole powers of ten. Two decades or fewer are also ruled at 2 and 5.
_ValueRange _logRange(double lo, double hi, {int want = 0}) {
  if (!lo.isFinite || !hi.isFinite || lo <= 0 || hi <= 0) {
    return _niceRange(lo, hi);
  }
  var low = math.pow(10, (math.log(lo) / math.ln10).floor()).toDouble();
  var high = math.pow(10, (math.log(hi) / math.ln10).ceil()).toDouble();
  if (high <= low) high = low * 10;

  var decades = (math.log(high / low) / math.ln10).round();
  var ticks = <double>[];
  // Every decade up to six, then every second, then every fifth. Asked for
  // [want] divisions, every so many decades is the nearest a log axis gets.
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

/// _niceRange picks an axis that ends on round numbers: the rough step
/// rounded up to 1, 2, 2.5 or 5 times a power of ten, the ends pushed out to
/// multiples of it. [fromZero] is for types read as lengths (bars); candles
/// are read as positions and must not be dragged down to zero.
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
    // A tenth of the range as air beyond the highest and lowest wicks.
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
  // Counted, not stepped: a step too small to change a large value never ends.
  var count = (max - min) / step;
  if (!count.isFinite || count > 1000) return _ValueRange(lo, hi, [lo, hi]);
  var ticks = <double>[];
  for (var i = 0; i <= count.round(); i++) {
    var v = min + i * step;
    ticks.add(v.abs() < step * 1e-9 ? 0 : v);
  }
  return _ValueRange(min, max, ticks);
}

void paintCartesian(ui.Canvas canvas, Rect area, ChartElement e, double reveal,
    [List<double>? seriesReveal]) {
  var data = e.data;
  var horizontal = e.type == ChartType.horizontalBar;

  // The range covers every visible series, or their running totals when
  // stacked. Seeded with zero only for types read as lengths; candles and
  // log axes take their bottom from the data.
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
      // A hidden series does not size the axis, so hiding a large one helps.
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
  // the bottom. Label switches belong to the axis, so "X labels" means
  // whatever is written along the bottom either way.
  var sideSpec = e.yLabels, bottomSpec = e.xLabels;
  // Names over sideways bars take no gutter: each sits above its bar
  // (ChartDesign.labelsAbove), written by _bars.
  var above = horizontal && e.design.labelsAbove;
  var sideOn = e.showYLabels && !above, bottomOn = e.showXLabels;

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
  // off centre. The label gaps widen or narrow each gutter, never below 0.
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

  // Air over the top label and past the last, so the edge does not cut them,
  // only while that axis has labels: otherwise the chart fills its box.
  var topAir = sideOn ? sideSpec.fontSize : 0.0;
  var rightAir = bottomOn ? bottomSpec.fontSize : 0.0;
  // Room on the right for the names written at the ends of lines.
  var nameRoom = 0.0;
  for (var i in data.named) {
    if (i < 0 || i >= data.series.length) continue;
    var tp = TextPainter(
        text: TextSpan(
            text: data.series[i].name,
            style: TextStyle(
                fontSize: e.labelSpec.fontSize * 0.9,
                fontWeight: FontWeight.w700,
                fontFamily: e.labelSpec.fontFamily)),
        textDirection: TextDirection.ltr)
      ..layout();
    nameRoom = math.max(nameRoom, tp.width + 12);
    tp.dispose();
  }
  nameRoom = math.min(nameRoom, area.width * 0.3);
  var plot = Rect.fromLTRB(left, area.top + topAir * 0.6,
      area.right - rightAir * 0.5 - nameRoom, bottom);
  if (plot.width <= 4 || plot.height <= 4) return;
  notePart(ChartPartKind.plot, plot);
  notePart(ChartPartKind.xLabels,
      Rect.fromLTRB(plot.left, plot.bottom, plot.right, area.bottom));
  notePart(ChartPartKind.yLabels,
      Rect.fromLTRB(area.left, plot.top, plot.left, plot.bottom));

  _grid(canvas, plot, range, e, horizontal);
  // The date a chart playing through dates shows, large and faint behind it.
  if (data.at.isNotEmpty) {
    var tp = TextPainter(
        text: TextSpan(
            text: data.at,
            style: TextStyle(
                fontSize: math.min(plot.height * 0.16, 80),
                fontWeight: FontWeight.w800,
                color: e.titleSpec.color.withValues(alpha: 0.16),
                fontFamily: e.titleSpec.fontFamily)),
        textDirection: TextDirection.ltr)
      ..layout(maxWidth: plot.width);
    paintTp(tp, canvas,
        Offset(plot.right - tp.width - 8, plot.bottom - tp.height - 4));
    tp.dispose();
  }
  if (e.showAxisLabels) {
    _axisLabels(
        canvas,
        area,
        plot,
        range,
        above ? e.copyWith(showYLabels: false) : e,
        horizontal,
        valueGutter,
        categoryGutter,
        axisTitleGutter);
  }
  // Bands go behind the marks; lines and words over them (_notes).
  _notes(canvas, plot, range, e, horizontal, behind: true);

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
      // "Bars" draws one bar per category (the first untyped series), which
      // separates it from "Grouped bars". A typed series is always drawn.
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
  _lineNames(canvas, plot, range, e);
  // Notes bound to the data draw on once the data has arrived.
  _notes(canvas, plot, range, e, horizontal,
      behind: false,
      arrived: e.animation.on ? ((reveal - 0.6) / 0.4).clamp(0.0, 1.0) : 1.0);
}

/// _lineNames writes the named lines' names (ChartData.named) past each
/// end, in its colour, nudged apart where two end close together.
void _lineNames(
    ui.Canvas canvas, Rect plot, _ValueRange range, ChartElement e) {
  var data = e.data;
  var n = data.categories.length;
  if (data.named.isEmpty || n == 0) return;
  var placed = <(double, TextPainter)>[];
  for (var s in data.named) {
    if (s < 0 || s >= data.series.length) continue;
    var series = data.series[s];
    if (series.hidden || !series.typeIn(e.type).isLinear) continue;
    var at = -1;
    for (var i = series.values.length - 1; i >= 0; i--) {
      if (!series.values[i].isNaN) {
        at = i;
        break;
      }
    }
    if (at < 0) continue;
    var y = plot.bottom -
        plot.height * range.fraction(series.values[at]).clamp(0.0, 1.0);
    var tp = TextPainter(
        text: TextSpan(
            text: series.name,
            style: TextStyle(
                fontSize: e.labelSpec.fontSize * 0.9,
                fontWeight: FontWeight.w700,
                color: series.color,
                fontFamily: e.labelSpec.fontFamily)),
        textDirection: TextDirection.ltr)
      ..layout();
    placed.add((y - tp.height / 2, tp));
  }
  placed.sort((a, b) => a.$1.compareTo(b.$1));
  var last = double.negativeInfinity;
  for (var (y, tp) in placed) {
    var top = math.max(y, last);
    paintTp(tp, canvas, Offset(plot.right + 6, top));
    last = top + tp.height;
    tp.dispose();
  }
}

/// _notes draws a chart's notes (ChartNote): with [behind], its bands as a
/// wash; otherwise its lines across the plot and its words over a mark.
void _notes(ui.Canvas canvas, Rect plot, _ValueRange range, ChartElement e,
    bool horizontal,
    {required bool behind, double arrived = 1}) {
  var data = e.data;
  var n = data.categories.length;
  if (n == 0 || e.notes.isEmpty) return;
  var slot = (horizontal ? plot.height : plot.width) / n;
  var size = math.max(9.0, e.labelSpec.fontSize * 0.85);

  TextPainter words(String text, Color colour) => TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w700,
              color: colour,
              fontFamily: e.labelSpec.fontFamily)),
      textDirection: TextDirection.ltr)
    ..layout();

  String number(double v) =>
      v == v.roundToDouble() ? "${v.round()}" : v.toStringAsFixed(1);

  // Where a named mark is, by name, so a note follows it through a re-sort.
  Offset? anchorOf(String who) {
    var i = data.categories.indexOf(who);
    if (i < 0 || data.series.isEmpty || !data.hasValueAt(0, i)) return null;
    var f = range.fraction(data.valueAt(0, i)).clamp(0.0, 1.0);
    var mid = slot * (data.slotAt(i) + 0.5);
    return horizontal
        ? Offset(plot.left + plot.width * f, plot.top + mid)
        : Offset(plot.left + mid, plot.bottom - plot.height * f);
  }

  // Notes bound to the data keep their words apart and off the marks (the
  // shared rule): each bar, or each point.
  var bars = e.type.isBar;
  var placer = LabelPlacer(plot.inflate(size * 2), keepClear: [
    if (!behind)
      for (var c in data.categories)
        if (anchorOf(c) case var at?)
          bars
              ? (horizontal
                  ? Rect.fromLTRB(plot.left, at.dy - slot * 0.32, at.dx,
                      at.dy + slot * 0.32)
                  : Rect.fromLTRB(at.dx - slot * 0.32, at.dy,
                      at.dx + slot * 0.32, plot.bottom))
              : Rect.fromCircle(center: at, radius: 5),
  ]);

  for (var (k, note) in e.notes.indexed) {
    if (note.off) continue;
    switch (note.kind) {
      case ChartNoteKind.band:
        if (!behind) continue;
        var a = note.from.clamp(1, n) - 1;
        var b = math.max(a + 1, note.to.clamp(1, n));
        var r = horizontal
            ? Rect.fromLTRB(
                plot.left, plot.top + slot * a, plot.right, plot.top + slot * b)
            : Rect.fromLTRB(plot.left + slot * a, plot.top,
                plot.left + slot * b, plot.bottom);
        canvas.drawRect(
            r, Paint()..color = note.colour.withValues(alpha: 0.18));
        if (note.text.isNotEmpty) {
          var tp = words(liveWords(data, note.text), note.colour);
          paintTp(
              tp,
              canvas,
              horizontal
                  ? Offset(r.right - tp.width - 4, r.top + 2)
                  : Offset(r.center.dx - tp.width / 2, r.top + 3));
          tp.dispose();
        }
        notePart(ChartPartKind.note, r, index: k);

      case ChartNoteKind.line:
        if (behind) continue;
        var v = note.value;
        if (v.isNaN) {
          var values = [
            if (data.series.isNotEmpty)
              for (var x in data.series.first.values)
                if (!x.isNaN) x
          ];
          if (values.isEmpty) continue;
          v = values.fold(0.0, (a, b) => a + b) / values.length;
        }
        var f = range.fraction(v).clamp(0.0, 1.0);
        var paint = Paint()
          ..color = note.colour
          ..strokeWidth = 2;
        Rect hit;
        if (horizontal) {
          var x = plot.left + plot.width * f;
          for (var y = plot.top; y < plot.bottom; y += 10) {
            canvas.drawLine(
                Offset(x, y), Offset(x, math.min(plot.bottom, y + 6)), paint);
          }
          hit = Rect.fromLTRB(x - 5, plot.top, x + 5, plot.bottom);
        } else {
          var y = plot.bottom - plot.height * f;
          for (var x = plot.left; x < plot.right; x += 10) {
            canvas.drawLine(
                Offset(x, y), Offset(math.min(plot.right, x + 6), y), paint);
          }
          hit = Rect.fromLTRB(plot.left, y - 5, plot.right, y + 5);
        }
        var said = note.text.isEmpty
            ? number(v)
            : "${liveWords(data, note.text)} ${number(v)}";
        var tp = words(said, note.colour);
        paintTp(
            tp,
            canvas,
            horizontal
                ? Offset(hit.center.dx + 4, plot.top)
                : Offset(
                    plot.right - tp.width - 2, hit.center.dy - tp.height - 3));
        tp.dispose();
        notePart(ChartPartKind.note, hit, index: k);

      case ChartNoteKind.label:
        if (behind) continue;
        var i = data.categories.indexOf(note.who);
        if (i < 0 || data.series.isEmpty || !data.hasValueAt(0, i)) continue;
        var f = range.fraction(data.valueAt(0, i)).clamp(0.0, 1.0);
        var tp = words(
            note.text.isEmpty ? note.who : liveWords(data, note.text),
            const Color(0xFF1D2127));
        var at = horizontal
            ? Offset(plot.left + plot.width * f + 8,
                plot.top + slot * (i + 0.5) - tp.height / 2)
            : Offset(plot.left + slot * (i + 0.5) - tp.width / 2,
                plot.bottom - plot.height * f - tp.height - 12);
        var pill =
            Rect.fromLTWH(at.dx - 6, at.dy - 3, tp.width + 12, tp.height + 6);
        canvas.drawRRect(
            RRect.fromRectAndRadius(pill, const Radius.circular(5)),
            Paint()..color = note.colour);
        paintTp(tp, canvas, at);
        tp.dispose();
        notePart(ChartPartKind.note, pill, index: k);

      case ChartNoteKind.callout || ChartNoteKind.arrow:
        if (behind || arrived <= 0) continue;
        var to = anchorOf(note.who);
        if (to == null) continue;
        var tp = words(
            note.text.isEmpty ? note.who : liveWords(data, note.text),
            inkOn(note.colour) ?? const Color(0xFF1D2127));
        var box = Size(tp.width + 14, tp.height + 8);
        var arrow = note.kind == ChartNoteKind.arrow;
        // A callout close by; an arrow's words further off, room for the arrow.
        var reach = arrow ? size * 4 : size * 1.6;
        // Past a sideways bar's end first; over an upright one's top.
        var places = LabelPlacer.around(to, box, reach);
        if (horizontal) {
          places = [places[1], ...places.where((r) => r != places[1])];
        }
        var at = placer.place(places) ??
            Rect.fromCenter(
                center: to.translate(0, -reach - box.height / 2),
                width: box.width,
                height: box.height);
        // The line first, then the words: drawn on as the chart arrives.
        var line = (arrived / 0.6).clamp(0.0, 1.0);
        var shown = ((arrived - 0.4) / 0.6).clamp(0.0, 1.0);
        // From the edge of the box nearest the mark.
        var from = Offset(
            to.dx.clamp(at.left, at.right), to.dy.clamp(at.top, at.bottom));
        var end = to + (from - to) / math.max(1, (from - to).distance) * 4;
        var path = Path()..moveTo(from.dx, from.dy);
        if (arrow) {
          var mid = (from + end) / 2;
          var bend = Offset(-(end - from).dy, (end - from).dx) * 0.25;
          path.quadraticBezierTo(
              mid.dx + bend.dx, mid.dy + bend.dy, end.dx, end.dy);
        } else {
          path.lineTo(end.dx, end.dy);
        }
        var stroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = arrow ? 2.2 : 1.5
          ..strokeCap = StrokeCap.round
          ..color = note.colour;
        for (var m in path.computeMetrics()) {
          var drawn = m.extractPath(0, m.length * line);
          canvas.drawPath(drawn, stroke);
          if (arrow && line >= 1) {
            var tip = m.getTangentForOffset(m.length);
            if (tip != null) {
              var a = tip.angle;
              var head = size * 0.7;
              for (var side in [-0.45, 0.45]) {
                canvas.drawLine(
                    tip.position,
                    tip.position -
                        Offset(math.cos(-a + side), math.sin(-a + side)) * head,
                    stroke);
              }
            }
          }
        }
        if (!arrow) {
          canvas.drawCircle(to, 2.5, Paint()..color = note.colour);
        }
        if (shown > 0) {
          canvas.saveLayer(
              at.inflate(2), Paint()..color = Color.fromRGBO(0, 0, 0, shown));
          canvas.drawRRect(
              RRect.fromRectAndRadius(at, const Radius.circular(5)),
              Paint()..color = note.colour);
          paintTp(tp, canvas, Offset(at.left + 7, at.top + 4));
          canvas.restore();
        }
        tp.dispose();
        notePart(ChartPartKind.note, at, index: k);

      case ChartNoteKind.bracket:
        if (behind || arrived <= 0) continue;
        var a = anchorOf(note.who), b = anchorOf(note.whom);
        if (a == null || b == null) continue;
        var ia = data.categories.indexOf(note.who);
        var ib = data.categories.indexOf(note.whom);
        var gap = data.valueAt(0, ib) - data.valueAt(0, ia);
        var said = note.text.isEmpty
            ? "${gap > 0 ? "+" : ""}${number(gap)}"
            : liveWords(data, note.text);
        var stroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = note.colour;
        // Beside the later of two, spanning their values; grown from its mid.
        var grow = (arrived / 0.7).clamp(0.0, 1.0);
        Rect hit;
        if (horizontal) {
          var y = math.max(a.dy, b.dy) + slot * 0.42;
          var x0 = math.min(a.dx, b.dx), x1 = math.max(a.dx, b.dx);
          var mid = (x0 + x1) / 2, half = (x1 - x0) / 2 * grow;
          var path = Path()
            ..moveTo(mid - half, y - 5)
            ..lineTo(mid - half, y)
            ..lineTo(mid + half, y)
            ..lineTo(mid + half, y - 5);
          canvas.drawPath(path, stroke);
          hit = Rect.fromLTRB(x0, y - 6, x1, y + size * 1.4);
          if (grow >= 1) {
            var tp = words(said, note.colour);
            paintTp(tp, canvas, Offset(mid - tp.width / 2, y + 2));
            tp.dispose();
          }
        } else {
          var x = math.max(a.dx, b.dx) + slot * 0.42;
          var y0 = math.min(a.dy, b.dy), y1 = math.max(a.dy, b.dy);
          var mid = (y0 + y1) / 2, half = (y1 - y0) / 2 * grow;
          var path = Path()
            ..moveTo(x - 5, mid - half)
            ..lineTo(x, mid - half)
            ..lineTo(x, mid + half)
            ..lineTo(x - 5, mid + half);
          canvas.drawPath(path, stroke);
          var tp = words(said, note.colour);
          hit = Rect.fromLTWH(x - 6, y0, tp.width + 12, y1 - y0);
          if (grow >= 1) {
            paintTp(tp, canvas, Offset(x + 4, mid - tp.height / 2));
          }
          tp.dispose();
        }
        notePart(ChartPartKind.note, hit, index: k);
    }
  }
}

/// _rowNames is how names beside bars [slot] tall are written: smaller
/// where a row is short for them, then every second or third row's.
AxisNames _rowNames(TextSpec spec, double slot) {
  var need = spec.fontSize * 1.25;
  if (need <= slot) return const AxisNames(1, 1);
  var scale = slot / need;
  if (scale >= 0.75) return AxisNames(scale, 1);
  return AxisNames(0.75, math.max(2, (need * 0.75 / slot).ceil()));
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

/// _axisLabels writes the tick values, category names and axis titles.
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
  // Too many to write in full: smaller, then every second or third, rather
  // than each cut to a few letters (the shared label rule, label_placer).
  var names = slots == 0
      ? const AxisNames(1, 1)
      : horizontal
          ? _rowNames(spec, plot.height / slots)
          : AxisNames.of(categories, spec, plot.width / slots);
  var nameSpec2 = names.scale < 1
      ? spec.copyWith(fontSize: spec.fontSize * names.scale)
      : spec;
  for (var i = 0; i < slots; i++) {
    if (!names.shows(i, slots)) continue;
    if (horizontal) {
      var slot = plot.height / slots;
      // Part-way to a new place while the chart plays (ChartData.slots).
      var y = plot.top + slot * e.data.slotAt(i);
      var tall = slot * names.every;
      paintTextInBox(
          canvas,
          categories[i],
          nameSpec2.copyWith(
              align: TextAlignSpec.right,
              verticalAlign: VerticalAlignSpec.middle),
          Rect.fromLTRB(
              area.left,
              y + slot / 2 - tall / 2,
              plot.left - spec.fontSize * 0.4 - e.yLabelGap,
              y + slot / 2 + tall / 2),
          clip: true);
    } else {
      var slot = plot.width / slots;
      var x = plot.left + slot * e.data.slotAt(i);
      var wide = slot * names.every;
      paintTextInBox(
          canvas,
          categories[i],
          nameSpec2.copyWith(
              align: TextAlignSpec.center,
              verticalAlign: VerticalAlignSpec.top),
          Rect.fromLTWH(
              x + slot / 2 - wide / 2,
              plot.bottom + spec.fontSize * 0.35 + e.xLabelGap,
              wide,
              spec.fontSize * 1.6),
          clip: true);
    }
  }

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

/// _candles draws each period's open, high, low and close as one mark: a
/// wick from low to high and a body from open to close, coloured by whether
/// it closed up or down. The numbers come from four series (see
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
        case ChartAnimationPreset.fadeIn || ChartAnimationPreset.morph:
          colour = colour.withValues(alpha: colour.a * p.clamp(0.0, 1.0));
        case ChartAnimationPreset.grow:
        case ChartAnimationPreset.popIn:
        case ChartAnimationPreset.random:
        case ChartAnimationPreset.drawOn:
          // About its middle: from the axis it would cross prices never traded.
          arrived = p.clamp(0.0, 1.0);
        case ChartAnimationPreset.none:
        case ChartAnimationPreset.wipe:
        case ChartAnimationPreset.sweep:
          break;
      }
    }

    var paint = Paint()..color = colour;
    // Its way (ChartDesign.mode): candles; print mono (up hollow, down
    // solid, one ink); price bars (a tick each side for open and close); or
    // a range, high to low with a dot at the close.
    var way = modeOf(e.design, "candlestick");
    if (way == "mono") {
      paint.color = e.labelSpec.color.withValues(alpha: paint.color.a);
    }
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

    notePart(
        ChartPartKind.mark,
        Rect.fromLTRB(centre - bodyWidth / 2, wickTop, centre + bodyWidth / 2,
            wickBottom),
        series: 0,
        index: i);
    if (way == "range") {
      var thick = math.max(2.0, bodyWidth * 0.5);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTRB(
                  centre - thick / 2, wickTop, centre + thick / 2, wickBottom),
              Radius.circular(thick / 2)),
          Paint()..color = e.labelSpec.color.withValues(alpha: 0.25));
      var close = y(ohlc.close);
      canvas.drawCircle(Offset(centre, middle + (close - middle) * arrived),
          math.max(2.5, thick * 0.6), paint);
    } else if (way == "bars") {
      canvas.drawRect(
          Rect.fromLTRB(centre - wickWidth / 2, wickTop, centre + wickWidth / 2,
              wickBottom),
          paint);
      var tick = Paint()
        ..color = paint.color
        ..strokeWidth = wickWidth * 1.4;
      var open = y(ohlc.open), close = y(ohlc.close);
      canvas.drawLine(
          Offset(centre - bodyWidth / 2, middle + (open - middle) * arrived),
          Offset(centre, middle + (open - middle) * arrived),
          tick);
      canvas.drawLine(
          Offset(centre, middle + (close - middle) * arrived),
          Offset(centre + bodyWidth / 2, middle + (close - middle) * arrived),
          tick);
    } else {
      canvas.drawRect(
          Rect.fromLTRB(centre - wickWidth / 2, wickTop, centre + wickWidth / 2,
              wickBottom),
          paint);

      var body = Rect.fromLTRB(centre - bodyWidth / 2, top,
          centre + bodyWidth / 2, math.max(bottom, top + wickWidth));
      var r = math.min(e.barRadius, math.min(body.width, body.height) / 2);
      if (way == "mono" && ohlc.rose) {
        // Up candles hollow: an outline on the ground.
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                body.deflate(wickWidth / 2), Radius.circular(math.max(0, r))),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = wickWidth
              ..color = paint.color);
      } else {
        canvas.drawRRect(
            RRect.fromRectAndRadius(body, Radius.circular(math.max(0, r))),
            paint);
      }
    }

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

/// _bars draws the bar types for the bar series in [which]. Two or more
/// share a slot side by side, unless the chart is stacked.
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
    // Along the bars, from the axis, far edge or middle, as a share of length.
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
          slotSize * e.data.slotAt(i) +
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

  // A name over each sideways bar: the bar takes the lower part of its slot
  // and its name the line above (ChartDesign.labelsAbove).
  var above = horizontal && e.design.labelsAbove;
  if (above) {
    var spec = e.yLabels;
    for (var i = 0; i < slots; i++) {
      var top = plot.top + slotSize * e.data.slotAt(i);
      paintTextInBox(
          canvas,
          data.categories[i],
          spec.copyWith(
              align: TextAlignSpec.left,
              verticalAlign: VerticalAlignSpec.bottom),
          Rect.fromLTWH(plot.left, top, plot.width, slotSize * 0.46));
    }
  }
  Rect inSlot(Rect bar) => above
      ? Rect.fromLTWH(
          bar.left, bar.top + bar.height * 0.42, bar.width, bar.height * 0.58)
      : bar;

  // A pale full-length track behind each bar (ChartDesign.track): the whole.
  if (e.design.track && !stacked) {
    // From the labels' ink, so it shows on a dark ground as on a light one.
    var track = Paint()..color = e.labelSpec.color.withValues(alpha: 0.16);
    for (var i = 0; i < slots; i++) {
      for (var at = 0; at < which.length; at++) {
        var start = (horizontal ? plot.top : plot.left) +
            slotSize * e.data.slotAt(i) +
            (slotSize - barSpan) / 2 +
            (grouped ? barSize * at : 0);
        var thick = grouped ? barSize : barSpan;
        var rect = inSlot(horizontal
            ? Rect.fromLTWH(plot.left, start, plot.width, thick)
            : Rect.fromLTWH(start, plot.top, thick, plot.height));
        var r = math.min(e.barRadius, math.min(rect.width, rect.height) / 2);
        canvas.drawRRect(
            RRect.fromRectAndRadius(rect, Radius.circular(math.max(0, r))),
            track);
      }
    }
  }

  // Values written after every bar, so a stack's next part does not cover.
  var labels = <(String, Rect, TextAlignSpec, Color?)>[];
  var fs = e.valueSpec.fontSize;
  for (var i = 0; i < slots; i++) {
    var slotStart =
        (horizontal ? plot.top : plot.left) + slotSize * e.data.slotAt(i);
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
      // barFloor gives a zero reading a visible mark, unlike an empty cell.
      // It grows the way the bar would, so negatives push down.
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
        bar = inSlot(Rect.fromLTWH(plot.left + plot.width * lo, y,
            plot.width * (hi - lo), grouped ? barSize : barSpan));
      } else {
        var x = slotStart + inset + (grouped ? barSize * at : 0);
        bar = Rect.fromLTWH(x, plot.bottom - plot.height * hi,
            grouped ? barSize : barSpan, plot.height * (hi - lo));
      }

      // A highlight's or colour-by's colour first (ChartData.marks). A bar
      // with its own colour is flat: the series' gradient is its colour's.
      var mark = e.data.markAt(i);
      var ownColour =
          mark != null || (barsTakeColours(e) && i < e.sliceColors.length);
      var colour = mark ?? (ownColour ? barColour(e, i) : series.color);
      var arrived = 1.0;
      if (e.animation.on && (reveal < 1 || seriesReveal != null)) {
        // Staggered by category, so grouped bars arrive together; the
        // series' reveal allows for ChartSeries.delay.
        var p = e.animation
            .progressAt(_revealOf(seriesReveal, s, reveal), i, slots);
        if (p <= 0) continue;
        switch (e.animation.preset) {
          case ChartAnimationPreset.fadeIn || ChartAnimationPreset.morph:
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
            // Out of its own base (for a negative bar, its far edge); an
            // overshooting ease passes the true length.
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
      notePart(ChartPartKind.mark, bar, series: s, index: i);
      canvas.drawRRect(
          RRect.fromRectAndRadius(bar, Radius.circular(math.max(0, r))),
          Paint()
            // See underShader: the ramp already carries the fade.
            ..color = underShader(colour, barShader)
            ..shader = barShader);

      if (e.showValues && v != 0) {
        // Counts up with the bar, clamped so an overshoot never overstates.
        var label = formatSeries(e, s, v * arrived.clamp(0.0, 1.0));
        if (stacked) {
          // Inside its own part where it fits, in an ink that reads on it;
          // the stack's total goes past its end (below).
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
        } else if (e.design.valuesInside &&
            (horizontal ? bar.width : bar.height) >=
                (horizontal ? fs * (label.length * 0.62 + 1.2) : fs * 1.8) &&
            // Across too: a narrow column would write a digit a line.
            (horizontal ||
                bar.width >=
                    layoutText(label, e.valueSpec, maxWidth: double.infinity)
                            .width +
                        fs * 0.3)) {
          // Inside its end, in an ink that reads on it (ChartDesign).
          var pad = fs * 0.45;
          var box = horizontal
              ? (v < 0
                  ? Rect.fromLTWH(
                      bar.left + pad, bar.top, bar.width - pad * 2, bar.height)
                  : Rect.fromLTWH(
                      bar.left + pad, bar.top, bar.width - pad * 2, bar.height))
              : Rect.fromLTWH(bar.left, bar.top + pad, bar.width, fs * 1.3);
          labels.add((
            label,
            box,
            horizontal
                ? (v < 0 ? TextAlignSpec.left : TextAlignSpec.right)
                : TextAlignSpec.center,
            _inkOn(colour)
          ));
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

/// _pastEnd is where a bar's value goes: past the end it grows to.
Rect _pastEnd(Rect bar, bool horizontal, bool negative, double fs) => horizontal
    ? (negative
        ? Rect.fromLTWH(
            bar.left - fs * 0.3 - fs * 5, bar.center.dy - fs, fs * 5, fs * 2)
        : Rect.fromLTWH(
            bar.right + fs * 0.3, bar.center.dy - fs, fs * 5, fs * 2))
    // Centred over a column, at least wide enough for a number: a column
    // still narrow as it arrives would write it a digit a line.
    : (negative
        ? Rect.fromCenter(
            center: Offset(bar.center.dx, bar.bottom + fs * 0.8),
            width: math.max(bar.width, fs * 4),
            height: fs * 1.4)
        : Rect.fromCenter(
            center: Offset(bar.center.dx, bar.top - fs * 0.8),
            width: math.max(bar.width, fs * 4),
            height: fs * 1.4));

/// _alongEnd is how a value past a bar's end is set: away from the bar.
TextAlignSpec _alongEnd(bool horizontal, bool negative) => horizontal
    ? (negative ? TextAlignSpec.right : TextAlignSpec.left)
    : TextAlignSpec.center;

/// _inkOn is black or white, whichever reads on [fill].
Color _inkOn(Color fill) => fill.computeLuminance() > 0.45
    ? const Color(0xFF111111)
    : const Color(0xFFFFFFFF);

/// _lines draws the line, area and scatter types for the series in [which],
/// each by its own type, so one can be an area and the next a scatter.
void _lines(ui.Canvas canvas, Rect plot, _ValueRange range, ChartElement e,
    List<int> which, double reveal,
    [List<double>? seriesReveal]) {
  var data = e.data;
  var n = data.categories.length;
  if (n == 0) return;

  // By its number for a scatter by numbers; else mid-slot, in line with bars.
  var across = _acrossRangeOf(e);
  var acrossAt = across == null ? null : acrossValuesOf(e);
  double xAt(int i) => acrossAt != null
      ? plot.left + plot.width * across!.fraction(acrossAt[i])
      // Part-way to a new place while the chart plays (ChartData.slots).
      : plot.left + plot.width * (n == 1 ? 0.5 : (data.slotAt(i) + 0.5) / n);
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

    // Lines are staggered by series, except a scatter under a scrambling
    // preset, where each dot is its own item across all series.
    var perPoint = animation.preset.scrambles && kind == ChartType.scatter;
    var mine = _revealOf(seriesReveal, s, reveal);
    var progress = animating && !perPoint
        ? animation.progressAt(mine, at, which.length)
        : 1.0;
    if (animating && !perPoint && progress <= 0) continue;

    // The settled points, before a preset lifts them: a band is drawn
    // between two settled lines, since its other edge is never lifted.
    var seated = points;

    var alpha = 1.0;
    if (animating) {
      switch (animation.preset) {
        case ChartAnimationPreset.fadeIn || ChartAnimationPreset.morph:
          alpha = progress.clamp(0.0, 1.0);
        case ChartAnimationPreset.grow:
        case ChartAnimationPreset.popIn:
        case ChartAnimationPreset.random:
          // Up out of the baseline, as bars; a per-point scatter dot by dot.
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

    // Runs of readings, a path each, so no line crosses a gap; one is a dot.
    var runs = <List<int>>[];
    for (var i = 0; i < n; i++) {
      if (!present[i]) continue;
      if (runs.isEmpty || i == 0 || !present[i - 1]) runs.add(<int>[]);
      runs.last.add(i);
    }

    // A scatter's extras, under its dots (ChartDesign): its points joined in
    // row order, a straight trend, and once, dashed lines at the averages.
    if (kind == ChartType.scatter) {
      var dots = [
        for (var i = 0; i < n; i++)
          if (present[i]) points[i]
      ];
      var faint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, weight * 0.6)
        ..color =
            colour.withValues(alpha: colour.a * 0.7 * progress.clamp(0.0, 1.0));
      if (e.design.connect && dots.length > 1) {
        canvas.drawPath(_linePath(dots, false), faint);
      }
      if (e.design.trend && dots.length > 1) {
        var mx = dots.fold(0.0, (a, p) => a + p.dx) / dots.length;
        var my = dots.fold(0.0, (a, p) => a + p.dy) / dots.length;
        var sxx = 0.0, sxy = 0.0;
        for (var p in dots) {
          sxx += (p.dx - mx) * (p.dx - mx);
          sxy += (p.dx - mx) * (p.dy - my);
        }
        if (sxx > 0) {
          var k = sxy / sxx;
          double yAt(double x) =>
              (my + k * (x - mx)).clamp(plot.top, plot.bottom);
          canvas.drawLine(
              Offset(plot.left, yAt(plot.left)),
              Offset(plot.right, yAt(plot.right)),
              faint..strokeWidth = math.max(1.2, weight * 0.7));
        }
      }
      if (e.design.quadrants && at == 0 && dots.isNotEmpty) {
        var mx = dots.fold(0.0, (a, p) => a + p.dx) / dots.length;
        var my = dots.fold(0.0, (a, p) => a + p.dy) / dots.length;
        var dash = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = e.axisColor.withValues(alpha: 0.7);
        canvas.drawPath(
            _dashed(
                Path()
                  ..moveTo(mx, plot.top)
                  ..lineTo(mx, plot.bottom),
                1.4),
            dash);
        canvas.drawPath(
            _dashed(
                Path()
                  ..moveTo(plot.left, my)
                  ..lineTo(plot.right, my),
                1.4),
            dash);
      }
    }

    if (kind != ChartType.scatter) {
      // Steps (ChartDesign.step): flat to the next point, then up or down.
      var stepped = e.design.step && kind == ChartType.line;
      var smooth = !stepped && series.smoothOn(e.smooth) && kind.usesSmooth;
      // path is the whole line: the area is closed from it and drawing-on
      // measures along it. The stroke is split into solid and dashed
      // stretches, dashed where it touches an estimate.
      var path = Path();
      var solid = Path();
      var dashed = Path();
      var marks = data.marksEstimates;
      for (var run in runs) {
        if (run.length < 2) continue;
        var pts = [for (var i in run) points[i]];
        path.addPath(
            _linePath(stepped ? _stepped(pts) : pts, smooth), Offset.zero);
        for (var k = 0; k < run.length - 1; k++) {
          var soft = marks &&
              (data.isEstimated(run[k]) || data.isEstimated(run[k + 1]));
          (soft ? dashed : solid).addPath(
              stepped
                  ? _linePath(_stepped([pts[k], pts[k + 1]]), false)
                  : _segmentPath(pts, k, smooth),
              Offset.zero);
        }
      }
      // Which points have readings, before drawing-on hides the ones not
      // reached. The band is built from this, and fades in (see _bandFade).
      var whole = [...present];

      var drawnTo = double.infinity;
      if (animating &&
          animation.preset == ChartAnimationPreset.drawOn &&
          progress < 1) {
        // Drawn on from the start, the line cut at its tip; the styled
        // strokes, a path per stretch, are clipped at drawnTo below.
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
        // Closed at the line's tip, not its last point, so the fill keeps pace.
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
        // Shares of the whole: solid bands, each over the next (chart_painter
        // stacks them); else the series' gradient, or a fade to nothing.
        if (modeOf(e.design, "area") == "share") {
          canvas.drawPath(fill, Paint()..color = colour);
        } else {
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
      // pattern over an estimated stretch; faintness alone marks it.
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
        canvas.drawPath(
            _dashed(dashed, weight, pattern ?? estimatedDash),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = weight
              // Round, or a dot (a near-zero dash) is invisible: see pattern.
              ..strokeCap = pattern == null ? StrokeCap.butt : StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..color = underShader(
                  colour.withValues(alpha: colour.a * estimatedFade * 2),
                  shader)
              ..shader = shader);
        if (clipped) canvas.restore();
      }
    }

    if (chartParts != null) {
      for (var i = 0; i < points.length; i++) {
        if (present[i]) {
          notePart(
              ChartPartKind.mark, Rect.fromCircle(center: points[i], radius: 8),
              series: s, index: i);
        }
      }
    }

    // Dots for a scatter, for written values, and where points are on.
    if (kind == ChartType.scatter ||
        e.showValues ||
        series.pointsOn(e.showPoints)) {
      // A scatter's words kept apart and off the dots (the shared label
      // rule): each in the first clear place round its point, else none.
      LabelPlacer? placer;
      if (kind == ChartType.scatter && e.showValues) {
        var r0 = series.pointSizeOn(e.pointSize) > 0
            ? series.pointSizeOn(e.pointSize)
            : math.max(4.5, weight * 2.4);
        placer = LabelPlacer(plot.inflate(e.valueSpec.fontSize), keepClear: [
          for (var i = 0; i < points.length; i++)
            if (present[i]) Rect.fromCircle(center: points[i], radius: r0),
        ]);
      }
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
        // A scatter's dots are what it is: bigger by default than a line's.
        var radius = size > 0
            ? size
            : kind == ChartType.scatter
                ? math.max(4.5, weight * 2.4)
                : weight * 1.4;
        // Sized by a third number: from a small dot to six times one, a
        // little see-through where they overlap.
        var sized = kind == ChartType.scatter && i < data.sizes.length;
        if (sized) radius = radius * (0.6 + 5.4 * data.sizes[i]);
        // The point colour, or the series'. Either takes the line's arrival
        // fade, so dot and line come on together.
        var dotPaint = e.data.markAt(i) ?? series.pointColorOn(e.pointColor);
        var dotColour = dotPaint.a > 0
            ? dotPaint.withValues(
                alpha: dotPaint.a *
                    (colour.a / (series.color.a == 0 ? 1 : series.color.a)))
            : colour;
        if (sized) dotColour = dotColour.withValues(alpha: dotColour.a * 0.75);
        canvas.drawCircle(
            points[i],
            radius * (swelling ? dot.clamp(0.0, 1.4) : 1),
            Paint()
              ..color = perPoint && dot < 1
                  ? dotColour.withValues(
                      alpha: dotColour.a * dot.clamp(0.0, 1.0))
                  : dotColour);
        if (e.showValues) {
          // Counts up while the point grows; drawn on, a passed point is full.
          var shown = swelling ||
                  (animating &&
                      !perPoint &&
                      animation.preset == ChartAnimationPreset.grow)
              ? dot.clamp(0.0, 1.0)
              : 1.0;
          // A scatter's point written as its name where it has one.
          var name = kind == ChartType.scatter ? data.pointNameAt(i) : "";
          if (placer != null) {
            var words = name.isNotEmpty
                ? name
                : formatSeries(e, s, data.valueAt(s, i) * shown);
            var spec = e.valueSpec.copyWith(
                align: TextAlignSpec.center,
                verticalAlign: VerticalAlignSpec.middle);
            var at = placer.place(
                LabelPlacer.around(points[i], labelSize(words, spec), radius));
            if (at != null) {
              paintTextInBox(canvas, words, spec, at.inflate(1));
            }
            continue;
          }
          paintTextInBox(
              canvas,
              name.isNotEmpty
                  ? name
                  : formatSeries(e, s, data.valueAt(s, i) * shown),
              e.valueSpec.copyWith(
                  align: TextAlignSpec.center,
                  verticalAlign: VerticalAlignSpec.bottom),
              Rect.fromCenter(
                  center: points[i].translate(0, -e.valueSpec.fontSize * 1.4),
                  width: e.valueSpec.fontSize * (name.isNotEmpty ? 10 : 6),
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

/// _nextDrawn is the first unhidden series after [s], or -1: a band's end.
int _nextDrawn(ChartData data, int s) {
  for (var i = s + 1; i < data.series.length; i++) {
    if (!data.series[i].hidden) return i;
  }
  return -1;
}

/// _bandFade is how much of the band between two lines is showing: nought
/// until both edges are three quarters on, then fading in over the rest of
/// the slower one. Faded, not drawn on, because the band is built from whole
/// readings and would step a category at a time.
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

/// _bandPath is the shape between one line and the next, where both read.
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

/// _segmentPath is the stretch from `points[i]` to `points[i + 1]` with
/// [_linePath]'s control points, so splitting a smoothed line into solid
/// and dashed stretches does not change its shape.
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

/// _dashed is [path] as dashes or dots, or itself where the weight is bad.
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

Path _trimmed(Path path, double fraction) {
  var out = Path();
  for (var metric in path.computeMetrics()) {
    var want = metric.length * fraction.clamp(0.0, 1.0);
    if (want <= 0) continue;
    out.addPath(metric.extractPath(0, want), Offset.zero);
  }
  return out;
}

/// _lastX is the drawn part's right edge, which decides what has arrived.
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

/// _stepped is [points] with a corner before each: flat along to the next
/// point's place, then up or down to it.
List<Offset> _stepped(List<Offset> points) => [
      for (var i = 0; i < points.length; i++) ...[
        if (i > 0) Offset(points[i].dx, points[i - 1].dy),
        points[i],
      ],
    ];

/// _linePath joins the points, optionally through a Catmull-Rom style
/// smooth. Control points a sixth of the gap keep overshoot small.
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
