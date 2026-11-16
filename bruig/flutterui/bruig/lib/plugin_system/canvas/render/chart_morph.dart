import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

// chart_morph.dart is a chart arriving out of the one before it (Ken,
// 2026-11-17, the improvements report's eighth item): bars become a pie,
// one season becomes the next scene's -- each item travelling from where
// the last chart drew it to where this one does, in its colour, so the eye
// follows it; the chart itself coming up over them at the end. Items only
// in this one grow from their places; those only in the last shrink away.

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

/// _marks is each item [e] draws in [rect], by name: where, and its colour.
Map<String, (Rect, Color)> _marks(ChartElement e, Rect rect) {
  var found = chartParts = <ChartPart>[];
  var recorder = ui.PictureRecorder();
  paintChart(ui.Canvas(recorder), rect,
      e.copyWith(animation: e.animation.copyWith(preset: ChartAnimationPreset.none)));
  recorder.endRecording().dispose();
  chartParts = null;
  var d = e.data;
  var out = <String, (Rect, Color)>{};
  for (var p in found) {
    if (p.kind != ChartPartKind.mark || p.index < 0) continue;
    if (p.index >= d.categories.length || p.series > 0) continue;
    var name = d.categories[p.index];
    var colour = e.type.isCircular
        ? sliceColour(e, p.index)
        : d.markAt(p.index) ??
            (d.series.isEmpty ? const Color(0xFF888888) : d.series.first.color);
    var r = out[name]?.$1;
    out[name] = (r == null ? p.rect : r.expandToInclude(p.rect), colour);
  }
  return out;
}

/// paintMorph draws [e] in [rect] arriving out of [from] (drawn in
/// [fromRect]), [reveal] of the way.
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
    paintChart(canvas, rect,
        e.copyWith(animation: e.animation.copyWith(preset: ChartAnimationPreset.none)));
    canvas.restore();
  }
  var tokens = 1 - settle;
  if (tokens <= 0) return;
  void token(Rect a, Rect b, Color ca, Color cb) {
    var r = Rect.lerp(a, b, travel)!;
    var c = Color.lerp(ca, cb, travel)!;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            r, Radius.circular(r.shortestSide.clamp(0.0, 40.0) * 0.18)),
        Paint()..color = c.withValues(alpha: c.a * tokens));
  }

  for (var MapEntry(key: name, value: (b, cb)) in to.entries) {
    var old = was[name];
    // New: grown from a point where it will be.
    var a = old?.$1 ?? Rect.fromCenter(center: b.center, width: 0, height: 0);
    token(a, b, old?.$2 ?? cb, cb);
  }
  for (var MapEntry(key: name, value: (a, ca)) in was.entries) {
    if (to.containsKey(name)) continue;
    // Gone: shrunk to a point where it was.
    token(a, Rect.fromCenter(center: a.center, width: 0, height: 0), ca, ca);
  }
}
