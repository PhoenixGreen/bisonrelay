import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';

// character_outline.dart takes a sketch's drawing apart into shapes: the
// figure is drawn once onto a canvas that keeps, instead of drawing, every
// outline it is given -- where it lands, its colour and its line -- and
// each is turned into points with handles, as a drawing from a file is.
// See takeApartPanel in character_parts.dart for what is done with them.

/// CapturedShape is one shape the figure drew: the shape, as a drawing has
/// it, in the order it was drawn, and a key that says where it was and in
/// what colour -- the same shape drawn by another drawing of the figure has
/// the same key.
class CapturedShape {
  final VectorShape shape;
  final String key;

  /// layer is the layer it was drawn in -- see character_layers.dart --
  /// or null for one drawn in none.
  final String? layer;
  const CapturedShape(this.shape, this.key, {this.layer});
}

/// CaptureCanvas is a canvas that draws nothing, and keeps what it is
/// asked to draw as shapes. A fill and the line round the same outline are
/// one shape.
class CaptureCanvas implements Canvas {
  final List<CapturedShape> _shapes = [];
  final List<Path> _sources = [];
  final List<(Float64List, Path?)> _stack = [];
  Float64List _m = _identity();

  /// _clip is what is drawn kept to, on the page: a shape drawn inside it
  /// is cut to it, as it would have been drawn.
  Path? _clip;

  /// layer is the layer being drawn now: what each shape kept is marked
  /// with. The drawing sets it as it goes.
  String? layer;

  /// tolerance is how far a shape's points may stray from its outline.
  final double tolerance;
  CaptureCanvas({this.tolerance = 0.35});

  List<CapturedShape> get shapes => List.unmodifiable(_shapes);

  static Float64List _identity() =>
      Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

  static Float64List _mul(Float64List a, Float64List b) {
    var out = Float64List(16);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        var v = 0.0;
        for (var k = 0; k < 4; k++) {
          v += a[k * 4 + r] * b[c * 4 + k];
        }
        out[c * 4 + r] = v;
      }
    }
    return out;
  }

  void _apply(Float64List t) => _m = _mul(_m, t);

  double get _scale => math.sqrt((_m[0] * _m[5] - _m[1] * _m[4]).abs());

  @override
  void save() => _stack.add((Float64List.fromList(_m), _clip));

  @override
  void saveLayer(Rect? bounds, Paint paint) => save();

  @override
  void restore() {
    if (_stack.isEmpty) return;
    var (m, clip) = _stack.removeLast();
    _m = m;
    _clip = clip;
  }

  @override
  void restoreToCount(int count) {
    while (_stack.length + 1 > count && _stack.isNotEmpty) {
      restore();
    }
  }

  @override
  int getSaveCount() => _stack.length + 1;

  @override
  void translate(double dx, double dy) =>
      _apply(Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, dx, dy, 0, 1]));

  @override
  void scale(double sx, [double? sy]) => _apply(
      Float64List.fromList([sx, 0, 0, 0, 0, sy ?? sx, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]));

  @override
  void rotate(double radians) {
    var c = math.cos(radians), s = math.sin(radians);
    _apply(Float64List.fromList([c, s, 0, 0, -s, c, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]));
  }

  @override
  void skew(double sx, double sy) =>
      _apply(Float64List.fromList([1, sy, 0, 0, sx, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]));

  @override
  void transform(Float64List matrix4) => _apply(matrix4);

  @override
  Float64List getTransform() => Float64List.fromList(_m);

  void _clipTo(Path path, {bool out = false}) {
    var at = path.transform(_m);
    if (out) {
      if (_clip case var c?) _clip = Path.combine(PathOperation.difference, c, at);
      return;
    }
    _clip = _clip == null ? at : Path.combine(PathOperation.intersect, _clip!, at);
  }

  @override
  void clipPath(Path path, {bool doAntiAlias = true}) => _clipTo(path);
  @override
  void clipRect(Rect rect, {ClipOp clipOp = ClipOp.intersect, bool doAntiAlias = true}) =>
      _clipTo(Path()..addRect(rect), out: clipOp == ClipOp.difference);
  @override
  void clipRRect(RRect rrect, {bool doAntiAlias = true}) =>
      _clipTo(Path()..addRRect(rrect));

  @override
  void drawPath(Path path, Paint paint) => _take(path, paint);

  @override
  void drawOval(Rect rect, Paint paint) => _take(Path()..addOval(rect), paint);

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      _take(Path()..addOval(Rect.fromCircle(center: c, radius: radius)), paint);

  @override
  void drawRect(Rect rect, Paint paint) => _take(Path()..addRect(rect), paint);

  @override
  void drawRRect(RRect rrect, Paint paint) => _take(Path()..addRRect(rrect), paint);

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => _take(
      Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy),
      Paint.from(paint)..style = PaintingStyle.stroke);

  @override
  void drawArc(Rect rect, double startAngle, double sweepAngle, bool useCenter,
      Paint paint) {
    var path = Path();
    if (useCenter) path.moveTo(rect.center.dx, rect.center.dy);
    path.arcTo(rect, startAngle, sweepAngle, !useCenter);
    if (useCenter) path.close();
    _take(path, paint);
  }

  /// _take keeps [path] drawn with [paint] as a shape: a line round an
  /// outline just filled is that shape's line.
  void _take(Path path, Paint paint) {
    // A wash of light or shade over what is drawn, a blur or a picture is
    // not a shape of its own.
    if (paint.maskFilter != null || paint.imageFilter != null) return;
    // A gradient is kept as the colour it is given beside it -- an iris is
    // its eye colour -- and left out where it has none: a sheen of light.
    if (paint.shader != null && paint.color.toARGB32() == 0xFF000000) return;
    // Nor is a band of shade laid over a shape and kept to it by how it is
    // blended: drawn alone, it is a rectangle over everything.
    if (paint.blendMode != BlendMode.srcOver) return;
    if (paint.color.a < 0.02) return;
    var stroke = paint.style == PaintingStyle.stroke;
    if (stroke && paint.strokeWidth * _scale < 0.05) return;
    var at = path.transform(_m);
    // A fill is cut to what it is kept to. A line is left whole: what it
    // runs along is what is seen.
    if (!stroke && _clip != null) {
      at = Path.combine(PathOperation.intersect, at, _clip!);
      if (at.getBounds().isEmpty) return;
    }
    if (stroke && _sources.isNotEmpty && identical(_sources.last, path)) {
      var last = _shapes.removeLast();
      _shapes.add(CapturedShape(
          last.shape.copyWith(
              stroke: paint.color,
              strokeWidth: paint.strokeWidth * _scale,
              cap: paint.strokeCap,
              join: paint.strokeJoin),
          last.key,
          layer: last.layer));
      return;
    }
    var paths = vectorPathsOf(at, tolerance: tolerance);
    if (paths.isEmpty) return;
    var shape = stroke
        ? VectorShape(
            paths: paths,
            stroke: paint.color,
            strokeWidth: paint.strokeWidth * _scale,
            cap: paint.strokeCap,
            join: paint.strokeJoin)
        : VectorShape(paths: paths, fill: paint.color);
    var b = at.getBounds();
    String r(double v) => (v * 2).round().toString();
    _shapes.add(CapturedShape(shape,
        "${paint.color.toARGB32()}|${stroke ? "s" : "f"}|${r(b.left)},${r(b.top)},${r(b.right)},${r(b.bottom)}",
        layer: layer));
    _sources.add(path);
  }

  // Nothing else is a shape: words, pictures, points.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

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
