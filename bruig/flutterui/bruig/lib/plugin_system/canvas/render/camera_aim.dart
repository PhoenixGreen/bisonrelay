import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/chart_story.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:flutter/painting.dart';

// camera_aim.dart is a Camera that frames part of a chart (Ken, 2026-11-17,
// the improvements report's sixth item): one club's bar, the top three,
// whoever leads -- found where the chart draws them on that frame, so the
// camera follows the leader through a race.

/// aimChoices is what a camera can frame in [e]: the whole chart, its
/// leader, its top three, or one of its marks by name.
List<(String, String)> aimChoices(ChartElement e) => [
      ("", "The whole chart"),
      ("leader", "Whoever leads"),
      ("top:3", "The top three"),
      if (e.steps.length > 1) ("lit", "What the narration names"),
      for (var c in e.data.categories) ("item:$c", c),
    ];

/// chartAimRect is where [aimAt] of chart [e] is on the page on [frame]:
/// the marks it names, as the chart draws them then; null where it names
/// none.
Rect? chartAimRect(
    ChartElement e, String aimAt, int frame, CanvasDocument doc) {
  var bounds = e.bounds;
  if (aimAt.isEmpty) return bounds;
  // The chart as it is then: at its step, part-way through its race.
  e = chartShownAt(e, doc, frame);
  var d = e.data;
  if (d.categories.isEmpty || d.series.isEmpty) return null;
  // Which marks, by name or by size.
  Set<int> wanted;
  if (aimAt == "lit") {
    // What its step lights: the names the line being spoken says; the
    // whole chart where it names none.
    wanted = litOf(e.highlights, d.categories,
        (_) => [for (var i = 0; i < d.categories.length; i++) d.valueAt(0, i)]);
    if (wanted.isEmpty) return bounds;
  } else if (aimAt.startsWith("item:")) {
    var i = d.categories.indexOf(aimAt.substring(5));
    if (i < 0) return null;
    wanted = {i};
  } else {
    var n = aimAt == "leader" ? 1 : int.tryParse(aimAt.split(":").last) ?? 1;
    var order = [
      for (var i = 0; i < d.categories.length; i++)
        if (d.hasValueAt(0, i)) i
    ]..sort((a, b) => d.valueAt(0, b).compareTo(d.valueAt(0, a)));
    wanted = order.take(n).toSet();
  }
  // Where the chart draws them: its own parts, as the Charts tab finds them.
  var rect = bounds.deflate(bounds.shortestSide * 0.02);
  var found = chartParts = <ChartPart>[];
  var recorder = ui.PictureRecorder();
  paintChart(ui.Canvas(recorder), rect, e);
  recorder.endRecording().dispose();
  chartParts = null;
  Rect? out;
  for (var p in found) {
    if (p.kind != ChartPartKind.mark || !wanted.contains(p.index)) continue;
    out = out == null ? p.rect : out.expandToInclude(p.rect);
  }
  if (out == null) return null;
  // A long mark -- a column, a bar -- framed at its end, where its value
  // and words are, in a page-shaped box, not the whole of it (which would
  // hardly come closer).
  var w = out.width, h = out.height;
  if (h > w * 1.5) {
    return Rect.fromCenter(
        center: out.topCenter.translate(0, w * 0.35),
        width: w * 1.8,
        height: w * 1.2);
  }
  if (w > h * 1.5) {
    return Rect.fromCenter(
        center: out.centerRight.translate(-h, 0),
        width: h * 4,
        height: h * 2.4);
  }
  return out;
}

/// aimedFraming is [cam]'s framing [zoom] and [centre] turned towards its
/// aim on [frame], by [mix] (0, its own; 1, the aim): close enough that
/// what it aims at fills its share of the frame. The given framing where
/// it aims at nothing.
(double, Offset) aimedFraming(CameraElement cam, double zoom, Offset centre,
    int frame, CanvasDocument doc, double mix) {
  if (cam.aim.isEmpty || mix <= 0) return (zoom, centre);
  var chart = doc.elementById(cam.aim);
  if (chart is! ChartElement) return (zoom, centre);
  var target = chartAimRect(chart, cam.aimAt, frame, doc);
  if (target == null || target.isEmpty) return (zoom, centre);
  var page = doc.size.rect;
  // Some room round a thin bar: never closer than its own short side
  // allows at the fill asked.
  var w = target.width < page.width * 0.02 ? page.width * 0.02 : target.width;
  var h =
      target.height < page.height * 0.02 ? page.height * 0.02 : target.height;
  var want = [page.width * cam.aimFill / w, page.height * cam.aimFill / h]
      .reduce((a, b) => a < b ? a : b)
      .clamp(1.0, 8.0);
  var m = mix.clamp(0.0, 1.0);
  return (
    zoom + (want - zoom) * m,
    Offset.lerp(centre, target.center, m)!,
  );
}
