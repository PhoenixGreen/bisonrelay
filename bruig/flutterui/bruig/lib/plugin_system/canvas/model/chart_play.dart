import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';

// chart_play.dart is a chart in motion (prototype v6): once it has arrived
// it plays through its dates -- a race, the bars overtaking one another --
// or through its steps, ChartElement.play seconds on each. Part-way, the
// chart is a blend of two readings of its sheet: each number between its
// two values, each bar between its two places. Everything else follows:
// highlights rank the blended numbers and live words read them.

/// easeBetween is the smooth step a chart moves between two readings by.
double easeBetween(double t) {
  var x = t.clamp(0.0, 1.0);
  return x < .5 ? 2 * x * x : 1 - math.pow(-2 * x + 2, 2) / 2;
}

/// chartBlend is the chart part-way, [f] from 0 to 1, from reading [a] to
/// reading [b]: [b]'s categories, each worth between what it was in [a]
/// (nothing, if it was not there) and what it is in [b], and drawn between
/// its place in [a] and its place in [b]. Whole numbers are kept whole for
/// the words from [a].
ChartData chartBlend(ChartData a, ChartData b, double f) {
  if (f <= 0) return a;
  if (f >= 1) return b;
  var from = {for (var (i, c) in a.categories.indexed) c: i};
  var series = [
    for (var (s, bs) in b.series.indexed)
      bs.copyWith(values: [
        for (var (i, c) in b.categories.indexed)
          () {
            var to = i < bs.values.length ? bs.values[i] : double.nan;
            var at = from[c];
            var was = at != null &&
                    s < a.series.length &&
                    at < a.series[s].values.length
                ? a.series[s].values[at]
                : double.nan;
            if (to.isNaN) return was.isNaN ? double.nan : was * (1 - f);
            if (was.isNaN) return to * f;
            return was + (to - was) * f;
          }(),
      ]),
  ];
  return b.copyWith(
    series: series,
    slots: [
      for (var (i, c) in b.categories.indexed)
        from[c] == null ? i.toDouble() : from[c]! + (i - from[c]!) * f,
    ],
    // The marks are [b]'s, in [b]'s order, as the categories are.
    at: f < 0.5 ? a.at : b.at,
    whole: [
      for (var s in a.series)
        s.values.every((v) => v.isNaN || v == v.roundToDouble())
    ],
  );
}

/// throughDates is the dates a chart plays through, in the sheet's order,
/// each once.
List<String> throughDates(DataSheet sheet, SheetLink link) {
  if (link.through < 0 || link.through >= link.range.cols) return const [];
  var g = link.range, out = <String>[];
  for (var r = g.r0 + 1; r <= g.r1; r++) {
    var v = sheetShown(sheet, r, g.c0 + link.through);
    if (!out.contains(v)) out.add(v);
  }
  return out;
}

/// stepOf is step [k] of [e] as it stands: the one being worked on is the
/// chart's own fields, the others as kept.
ChartStep stepOf(ChartElement e, int k) => k == e.stepAt
    ? ChartStep(
        name: e.steps[k].name,
        title: e.title,
        highlights: e.highlights,
        notes: e.notes,
        at: e.sheet?.at ?? "")
    : e.steps[k];

/// chartWithStep is [e] showing step [k]: its title, highlights, notes and
/// date. Its data is not read again: see [chartPlaying].
ChartElement chartWithStep(ChartElement e, int k) {
  var st = stepOf(e, k);
  return e.copyWith(
      title: st.title,
      highlights: st.highlights,
      notes: st.notes,
      sheet: e.sheet?.copyWith(at: st.at));
}

/// chartPlaying is [e] as it is [seconds] after it arrived, read from
/// [sheet]: through its steps, each held then eased into the next; or
/// through its dates, without a stop. [e] itself when it does not play.
ChartElement chartPlaying(ChartElement e, DataSheet sheet, double seconds) {
  var link = e.sheet;
  if (e.play <= 0 || link == null) return e;
  ChartData read(ChartElement c) => chartDataOf(sheet, c.sheet!, c.data,
      type: c.type, highlights: chartLights(c.highlights, sheet));

  if (e.steps.length > 1) {
    var n = e.steps.length;
    var pos = (math.max(0.0, seconds) / e.play).clamp(0.0, n - 1.0);
    var k = pos.floor().clamp(0, n - 1);
    // Held for most of its time, then eased into the next.
    var f = k >= n - 1 ? 0.0 : easeBetween(((pos - k) - 0.6) / 0.4);
    var here = chartWithStep(e, k);
    if (f <= 0) return here.copyWith(data: read(here));
    var next = chartWithStep(e, k + 1);
    var blended = chartBlend(read(here), read(next), f);
    return (f < 0.5 ? here : next).copyWith(data: blended);
  }

  var dates = throughDates(sheet, link);
  if (dates.length < 2) return e;
  var pos = (math.max(0.0, seconds) / e.play).clamp(0.0, dates.length - 1.0);
  var k = pos.floor().clamp(0, dates.length - 1);
  var f = easeBetween(pos - k);
  var a = e.copyWith(sheet: link.copyWith(at: dates[k]));
  if (k >= dates.length - 1 || f <= 0) return a.copyWith(data: read(a));
  var b = e.copyWith(sheet: link.copyWith(at: dates[k + 1]));
  return a.copyWith(data: chartBlend(read(a), read(b), f));
}

/// playLength is how long [e] plays for, in seconds, once it has arrived:
/// a stretch per date or step after the first.
double playLength(ChartElement e, DataSheet sheet) {
  var link = e.sheet;
  if (e.play <= 0 || link == null) return 0;
  var n =
      e.steps.length > 1 ? e.steps.length : throughDates(sheet, link).length;
  return math.max(0, n - 1) * e.play;
}
