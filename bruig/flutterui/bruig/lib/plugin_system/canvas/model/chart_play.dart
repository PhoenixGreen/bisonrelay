import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';

// chart_play.dart is a chart in motion: once arrived it plays through its
// dates (a race, bars overtaking) or its steps, ChartElement.play seconds
// each. Part-way, the chart blends two readings of its sheet: each number
// between its two values, each bar between its two places. Highlights rank
// the blended numbers and live words read them.

double easeBetween(double t) {
  var x = t.clamp(0.0, 1.0);
  return x < .5 ? 2 * x * x : 1 - math.pow(-2 * x + 2, 2) / 2;
}

/// chartBlend is the chart part-way, [f] from 0 to 1, from reading [a] to
/// [b]: [b]'s categories, each worth between its value in [a] (nothing if
/// absent) and in [b], drawn between its places in each. Whole numbers are
/// kept whole for the words from [a].
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

/// throughDates is the dates a chart plays through, each once, in order.
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

  // Steps that follow the marks or the scenes are not paced here: see
  // chartAtStep, and the renderer.
  if (e.steps.length > 1 && e.follow != ChartStepsFollow.time.name) return e;
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

/// playLength is [e]'s seconds of play after arriving, a stretch per step.
double playLength(ChartElement e, DataSheet sheet) {
  var link = e.sheet;
  if (e.play <= 0 || link == null) return 0;
  var n =
      e.steps.length > 1 ? e.steps.length : throughDates(sheet, link).length;
  return math.max(0, n - 1) * e.play;
}

// ---- Steps that follow the timeline's marks, or the scenes.

/// ChartStepsFollow is what moves a chart from step to step: its own pace
/// (ChartElement.play seconds each); the timeline's marks, a step from each
/// mark on (a Stop mark waits for a click, as a presentation does); or the
/// scenes (or pages), a step in each scene the chart is in.
enum ChartStepsFollow {
  time("Its own pace"),
  marks("Timeline marks"),
  scenes("Scenes or pages"),

  /// speech is a step per line of narration spoken (chart_story.dart).
  speech("The narration");

  final String label;
  const ChartStepsFollow(this.label);

  static ChartStepsFollow fromName(String? name) =>
      values.firstWhere((f) => f.name == name, orElse: () => time);
}

/// stepGlide is the seconds a chart eases into a step a mark moves it to.
const double stepGlide = 0.6;

/// chartAtStep is [e] on step [k], eased in from step [k] - 1 for the first
/// [stepGlide] seconds after [since] seconds into it.
ChartElement chartAtStep(ChartElement e, DataSheet sheet, int k, double since) {
  if (e.steps.isEmpty || e.sheet == null) return e;
  k = k.clamp(0, e.steps.length - 1);
  ChartData read(ChartElement c) => chartDataOf(sheet, c.sheet!, c.data,
      type: c.type, highlights: chartLights(c.highlights, sheet));
  var here = chartWithStep(e, k);
  var f = easeBetween(since / stepGlide);
  if (k == 0 || f >= 1) return here.copyWith(data: read(here));
  var was = chartWithStep(e, k - 1);
  var data = chartBlend(read(was), read(here), f);
  return (f < 0.5 ? was : here).copyWith(data: data);
}

/// stepByMarks is which step a chart following the timeline's marks is on
/// at [frame] of a document with marks at [marks], and how many seconds it
/// has been on it: a step from each mark on, the first before any.
(int, double) stepByMarks(List<int> marks, int steps, double frame, int rate) {
  var at = [...marks]..sort();
  var k = 0;
  var from = double.negativeInfinity;
  for (var m in at) {
    if (m > frame) break;
    k++;
    from = m.toDouble();
  }
  k = k.clamp(0, math.max(0, steps - 1));
  var since = from.isInfinite ? double.infinity : (frame - from) / rate;
  return (k, since);
}

/// stepByScenes is which step a chart following the scenes is on: the place
/// of [at], the scene shown, among [inScenes] (the scenes holding it or a
/// linked copy).
int stepByScenes(List<int> inScenes, int at) {
  var k = inScenes.indexOf(at);
  return k < 0 ? 0 : k;
}

// ---- Gliding when the numbers change, in the editor.

/// chartGlides are charts easing from the numbers they had to those after a
/// change (a refresh, an edit): by id, what they were drawn as and when the
/// glide began (null until first drawn). Kept here, not in the document: it
/// is how the editor draws a moment, not the design; an export never sees it.
final Map<String, (ChartData, Duration?)> chartGlides = {};

const Duration chartGlideTime = Duration(milliseconds: 650);

/// chartGlideBeat ticks after each frame a chart was drawn part-way through
/// a glide, so whoever draws charts draws the next frame (the controller
/// passes it to the stage, see CanvasController). Frames, not a timer: a
/// glide never outlives what draws it, and runs on a test's clock.
final ValueNotifier<int> chartGlideBeat = ValueNotifier(0);

bool _beating = false;

/// _frameNow is the time of the frame being drawn, or null where there is
/// no scheduler (a plain test, an export in another isolate).
Duration? _frameNow() {
  try {
    return SchedulerBinding.instance.currentSystemFrameTimeStamp;
  } catch (_) {
    return null;
  }
}

/// startGlide eases chart [id] from [from] (what it was drawn as, part way
/// through any glide) to whatever it is next drawn with.
void startGlide(String id, ChartData from) {
  chartGlides[id] = (from, null);
}

/// glided is [now] as chart [id] is drawn in this frame: part-way from what
/// it was if it is gliding, else [now] itself. A finished glide is
/// forgotten; one under way asks for the next frame.
ChartData glided(String id, ChartData now) {
  var g = chartGlides[id];
  if (g == null) return now;
  var at = _frameNow();
  if (at == null) {
    chartGlides.remove(id);
    return now;
  }
  var from = g.$2;
  if (from == null) {
    from = at;
    chartGlides[id] = (g.$1, at);
  }
  var t = (at - from).inMicroseconds / chartGlideTime.inMicroseconds;
  if (t >= 1 || t < 0) {
    chartGlides.remove(id);
    return now;
  }
  if (!_beating) {
    _beating = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _beating = false;
      chartGlideBeat.value++;
    });
  }
  return chartBlend(g.$1, now, easeBetween(t));
}
