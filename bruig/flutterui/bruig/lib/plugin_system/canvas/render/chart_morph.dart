import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

// chart_morph.dart is a chart arriving out of the one before it: bars
// become a pie, one season becomes the next scene's. Each item travels from
// where the last chart drew it to where this one does, in its colour, so
// the eye follows it, and the chart comes up over them at the end. Items
// only in this one grow from their places; those only in the last shrink.

/// morphFrom is the chart [e] arrives out of: in the scene before [doc]'s,
/// a linked copy of it, else the first chart reading the same sheet. Null
/// where there is none (it then grows in).
ChartElement? morphFrom(ChartElement e, CanvasDocument doc) {
  if (doc.at <= 0 || doc.at > doc.allScenes.length - 1) return null;
  var before = doc.allScenes[doc.at - 1].elements.whereType<ChartElement>();
  if (e.base.cast.isNotEmpty) {
    for (var c in before) {
      if (c.base.cast == e.base.cast) return c;
    }
  }
  var sheet = e.sheet?.sheet;
  if (sheet == null) return null;
  for (var c in before) {
    if (c.sheet?.sheet == sheet) return c;
  }
  return null;
}

/// _marks is each item [e] draws in [rect], by name: its outline (a
/// slice's own shape, else its box), and its colour.
Map<String, (Path, Color)> _marks(ChartElement e, Rect rect) {
  var found = chartParts = <ChartPart>[];
  var recorder = ui.PictureRecorder();
  paintChart(
      ui.Canvas(recorder),
      rect,
      e.copyWith(
          animation: e.animation.copyWith(preset: ChartAnimationPreset.none)));
  recorder.endRecording().dispose();
  chartParts = null;
  var d = e.data;
  var out = <String, (Path, Color)>{};
  for (var p in found) {
    if (p.kind != ChartPartKind.mark || p.index < 0) continue;
    if (p.index >= d.categories.length || p.series > 0) continue;
    var name = d.categories[p.index];
    var colour = e.type.isCircular
        ? sliceColour(e, p.index)
        : d.markAt(p.index) ??
            (d.series.isEmpty ? const Color(0xFF888888) : d.series.first.color);
    // Several parts of one item (a stack's): their box together.
    var had = out[name]?.$1;
    out[name] = (
      had == null
          ? (p.path ?? (Path()..addRect(p.rect)))
          : (Path()..addRect(had.getBounds().expandToInclude(p.rect))),
      colour
    );
  }
  return out;
}

const _points = 64;

/// _outline is [path]'s outline as [_points] points, evenly along it,
/// starting from its point nearest its box's top-left.
List<Offset> _outline(Path path) {
  var metrics = path.computeMetrics().toList();
  if (metrics.isEmpty) return List.filled(_points, path.getBounds().center);
  var m = metrics.reduce((a, b) => a.length >= b.length ? a : b);
  var pts = [
    for (var i = 0; i < _points; i++)
      m.getTangentForOffset(m.length * i / _points)?.position ??
          path.getBounds().center
  ];
  var corner = path.getBounds().topLeft;
  var start = 0;
  for (var i = 1; i < _points; i++) {
    if ((pts[i] - corner).distance < (pts[start] - corner).distance) start = i;
  }
  return [...pts.skip(start), ...pts.take(start)];
}

Path _between(List<Offset> a, List<Offset> b, double t) {
  var path = Path();
  for (var i = 0; i < _points; i++) {
    var q = Offset.lerp(a[i], b[i], t)!;
    i == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
  }
  return path..close();
}

/// paintMorph draws [e] in [rect] out of [from] (in [fromRect]), [reveal] on.
void paintMorph(ui.Canvas canvas, Rect rect, ChartElement e, ChartElement from,
    Rect fromRect, double reveal) {
  var t = Curves.easeInOut.transform(reveal.clamp(0.0, 1.0));
  var to = _marks(e, rect), was = _marks(from, fromRect);
  // The items travel, then give way to the chart in its last quarter.
  var travel = (t / 0.8).clamp(0.0, 1.0);
  var settle = ((t - 0.75) / 0.25).clamp(0.0, 1.0);
  if (settle > 0) {
    canvas.saveLayer(rect.inflate(rect.shortestSide),
        Paint()..color = Color.fromRGBO(0, 0, 0, settle));
    paintChart(
        canvas,
        rect,
        e.copyWith(
            animation:
                e.animation.copyWith(preset: ChartAnimationPreset.none)));
    canvas.restore();
  }
  var tokens = 1 - settle;
  if (tokens <= 0) return;
  // Each outline bent from its old shape to its new: a column into a slice.
  void token(List<Offset> a, List<Offset> b, Color ca, Color cb) {
    var c = Color.lerp(ca, cb, travel)!;
    canvas.drawPath(_between(a, b, travel),
        Paint()..color = c.withValues(alpha: c.a * tokens));
  }

  List<Offset> point(Offset at) => List.filled(_points, at);
  for (var MapEntry(key: name, value: (b, cb)) in to.entries) {
    var old = was[name];
    var target = _outline(b);
    // New: grown from a point where it will be.
    var start = old == null ? point(b.getBounds().center) : _outline(old.$1);
    token(start, target, old?.$2 ?? cb, cb);
  }
  for (var MapEntry(key: name, value: (a, ca)) in was.entries) {
    if (to.containsKey(name)) continue;
    // Gone: shrunk to a point where it was.
    token(_outline(a), point(a.getBounds().center), ca, ca);
  }
}
