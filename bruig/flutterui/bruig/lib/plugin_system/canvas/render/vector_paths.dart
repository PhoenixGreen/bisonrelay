import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';

// vector_paths.dart turns a Path -- strokes merged, an outline traced -- into
// a vector drawing's own paths: each outline as nodes with smooth handles,
// the points that add nothing left out.

/// vectorPathsOf is [path] as a drawing's paths: each of its outlines run
/// round finely, then thinned to the points it turns at -- within
/// [tolerance] of where it was -- each given handles to curve through as
/// smoothly as it ran.
List<VectorPath> vectorPathsOf(Path path, {double tolerance = 0.35}) {
  var out = <VectorPath>[];
  for (var metric in path.computeMetrics()) {
    var length = metric.length;
    if (length < 1e-3) continue;
    var step = math.max(tolerance * 0.6, length / 600);
    var pts = <Offset>[];
    for (var d = 0.0; d < length; d += step) {
      if (metric.getTangentForOffset(d) case var t?) pts.add(t.position);
    }
    var closed = metric.isClosed;
    if (!closed) {
      if (metric.getTangentForOffset(length) case var t?) pts.add(t.position);
    }
    if (pts.length < 2) continue;
    var kept = _simplify(pts, tolerance, closed: closed);
    if (kept.length < 2) continue;
    out.add(VectorPath(_smoothed(kept, closed), closed: closed));
  }
  return out;
}

/// _simplify is [pts] with every point left out that the line between its
/// neighbours passes within [tolerance] of.
List<Offset> _simplify(List<Offset> pts, double tolerance, {required bool closed}) {
  if (pts.length <= 3) return pts;
  // A closed outline is split at the point furthest from its start, so it
  // is simplified as two open runs that meet.
  if (closed) {
    var far = 0;
    var best = -1.0;
    for (var i = 0; i < pts.length; i++) {
      var d = (pts[i] - pts[0]).distanceSquared;
      if (d > best) {
        best = d;
        far = i;
      }
    }
    var a = _douglas(pts.sublist(0, far + 1), tolerance);
    var b = _douglas([...pts.sublist(far), pts[0]], tolerance);
    return [...a, ...b.sublist(1, b.length - 1)];
  }
  return _douglas(pts, tolerance);
}

List<Offset> _douglas(List<Offset> pts, double tolerance) {
  if (pts.length <= 2) return pts;
  var a = pts.first, b = pts.last;
  var ab = b - a;
  var len = ab.distance;
  var worst = -1.0;
  var at = 0;
  for (var i = 1; i < pts.length - 1; i++) {
    var d = len < 1e-9
        ? (pts[i] - a).distance
        : ((pts[i] - a).dx * ab.dy - (pts[i] - a).dy * ab.dx).abs() / len;
    if (d > worst) {
      worst = d;
      at = i;
    }
  }
  if (worst <= tolerance) return [a, b];
  var left = _douglas(pts.sublist(0, at + 1), tolerance);
  var right = _douglas(pts.sublist(at), tolerance);
  return [...left, ...right.skip(1)];
}

/// _smoothed is [pts] as nodes, each with handles along the way the
/// outline runs through it -- except where it turns sharply, a corner.
List<VectorNode> _smoothed(List<Offset> pts, bool closed) {
  var n = pts.length;
  return [
    for (var i = 0; i < n; i++)
      () {
        var p = pts[i];
        var hasPrev = closed || i > 0, hasNext = closed || i < n - 1;
        if (!hasPrev || !hasNext) return VectorNode(p.dx, p.dy);
        var prev = pts[(i - 1 + n) % n], next = pts[(i + 1) % n];
        var a = p - prev, b = next - p;
        var cos = (a.dx * b.dx + a.dy * b.dy) /
            math.max(1e-9, a.distance * b.distance);
        // Turning more than about sixty degrees: a corner, with no handles.
        if (cos < 0.5) return VectorNode(p.dx, p.dy);
        var t = (next - prev) / 6;
        return VectorNode(p.dx, p.dy,
            inX: -t.dx, inY: -t.dy, outX: t.dx, outY: t.dy, smooth: true);
      }(),
  ];
}
