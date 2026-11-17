import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

// vector_canvas.dart draws a chart or a table as shapes and words. The
// painters draw onto a VectorCanvas as any canvas; it keeps outlines and
// words (via paintTp: a laid-out paragraph cannot be read back) and draws
// what has no vector form as a small picture in place.

/// VPoly is one closed or open run of points, in page space.
class VPoly {
  final List<Offset> points;
  final bool closed;
  const VPoly(this.points, this.closed);
}

/// VClip is one clip, inside its [parent] (-1, the page).
class VClip {
  final List<VPoly> polys;
  final int parent;
  const VClip(this.polys, this.parent);
}

/// VOp is one thing drawn: a shape, a line of words, or a picture.
sealed class VOp {
  /// clip is the clip it is in (-1, none); [alpha] its layers' opacity.
  final int clip;
  final double alpha;
  const VOp(this.clip, this.alpha);
}

class VShape extends VOp {
  final List<VPoly> polys;
  final Color? fill, stroke;
  final double strokeWidth;
  final StrokeCap cap;
  final StrokeJoin join;
  final bool evenOdd;
  const VShape(this.polys,
      {this.fill,
      this.stroke,
      this.strokeWidth = 1,
      this.cap = StrokeCap.butt,
      this.join = StrokeJoin.miter,
      this.evenOdd = false,
      required int clip,
      required double alpha})
      : super(clip, alpha);
}

/// VText is a line of words, its baseline's left end at [matrix]'s origin
/// (page = (a·x + c·y + e, b·x + d·y + f)), [width] wide on screen.
class VText extends VOp {
  final String text;
  final String family;
  final double size;
  final int weight;
  final bool italic;
  final Color colour;
  final double letterSpacing;
  final double width;
  final List<double> matrix;
  const VText(this.text,
      {required this.family,
      required this.size,
      required this.weight,
      required this.italic,
      required this.colour,
      required this.letterSpacing,
      required this.width,
      required this.matrix,
      required int clip,
      required double alpha})
      : super(clip, alpha);
}

/// VImage is a picture filling [rect], in page space.
class VImage extends VOp {
  final ui.Image image;
  final Rect rect;
  const VImage(this.image, this.rect,
      {required int clip, required double alpha})
      : super(clip, alpha);
}

/// paintTp draws [tp] at [at]: as words on a VectorCanvas, else as usual.
void paintTp(TextPainter tp, Canvas canvas, Offset at) {
  if (canvas is VectorCanvas && canvas.addText(tp, at)) return;
  tp.paint(canvas, at);
}

class _State {
  final Float64List matrix;
  final int clip;
  final double alpha;
  _State(this.matrix, this.clip, this.alpha);
}

/// VectorCanvas records what is drawn on it as vector shapes and words.
class VectorCanvas implements Canvas {
  /// size is the page; [rasterScale] how finely rasters are drawn.
  final Size size;
  final double rasterScale;
  VectorCanvas(this.size, {this.rasterScale = 3});

  final List<VOp> ops = [];
  final List<VClip> clips = [];

  Float64List _m = Matrix4.identity().storage;
  int _clip = -1;
  double _alpha = 1;
  final List<_State> _stack = [];

  void dispose() {
    for (var op in ops) {
      if (op is VImage) op.image.dispose();
    }
    ops.clear();
  }

  // ---- geometry

  Offset _p(Offset o) =>
      MatrixUtils.transformPoint(Matrix4.fromFloat64List(_m), o);

  /// _scaleOf is how much the current transform scales a length.
  double get _scaleOf {
    var a = _m[0], b = _m[1], c = _m[4], d = _m[5];
    return math.sqrt((a * d - b * c).abs());
  }

  List<Offset> _sampled(ui.PathMetric metric) {
    var len = metric.length;
    // A point every fraction of a pixel on the page, at least a few.
    var step = math.max(0.35, 0.75 / math.max(_scaleOf, 0.01));
    var n = math.max(2, (len / step).ceil());
    n = math.min(n, 4000);
    return [
      for (var i = 0; i <= n; i++)
        if (metric.getTangentForOffset(len * i / n) case var t?) _p(t.position),
    ];
  }

  List<VPoly> _polysOf(Path path) => [
        for (var m in path.computeMetrics()) VPoly(_sampled(m), m.isClosed),
      ];

  List<VPoly> _rect(Rect r) => [
        VPoly([
          _p(r.topLeft),
          _p(r.topRight),
          _p(r.bottomRight),
          _p(r.bottomLeft)
        ], true)
      ];

  List<VPoly> _oval(Rect r) {
    var radius = math.max(r.width, r.height) / 2 * _scaleOf;
    var n = (radius * 0.8).clamp(24, 256).round();
    return [
      VPoly([
        for (var i = 0; i < n; i++)
          _p(r.center +
              Offset(math.cos(2 * math.pi * i / n) * r.width / 2,
                  math.sin(2 * math.pi * i / n) * r.height / 2)),
      ], true)
    ];
  }

  /// _plain is whether [p] can be written as a plain colour.
  static bool _plain(Paint p) =>
      p.shader == null &&
      p.maskFilter == null &&
      p.imageFilter == null &&
      p.colorFilter == null &&
      (p.blendMode == BlendMode.srcOver || p.blendMode == BlendMode.src);

  void _shape(List<VPoly> polys, Paint p, {bool evenOdd = false}) {
    if (polys.isEmpty) return;
    if (p.color.a == 0 && p.shader == null) return;
    var stroke = p.style == PaintingStyle.stroke;
    ops.add(VShape(polys,
        fill: stroke ? null : p.color,
        stroke: stroke ? p.color : null,
        strokeWidth:
            math.max(p.strokeWidth, 0.5 / math.max(_scaleOf, 0.01)) * _scaleOf,
        cap: p.strokeCap,
        join: p.strokeJoin,
        evenOdd: evenOdd,
        clip: _clip,
        alpha: _alpha));
  }

  /// _pageBounds is [local]'s box on the page.
  Rect _pageBounds(Rect local) {
    var pts = [
      _p(local.topLeft),
      _p(local.topRight),
      _p(local.bottomRight),
      _p(local.bottomLeft)
    ];
    var l = pts.map((p) => p.dx).reduce(math.min),
        r = pts.map((p) => p.dx).reduce(math.max),
        t = pts.map((p) => p.dy).reduce(math.min),
        b = pts.map((p) => p.dy).reduce(math.max);
    return Rect.fromLTRB(l, t, r, b);
  }

  Path _clipPath(int id) {
    var path = Path();
    for (var poly in clips[id].polys) {
      if (poly.points.isEmpty) continue;
      path.moveTo(poly.points.first.dx, poly.points.first.dy);
      for (var q in poly.points.skip(1)) {
        path.lineTo(q.dx, q.dy);
      }
      path.close();
    }
    return path;
  }

  /// _raster draws what has no vector form as a picture over [local] --
  /// its own place, clipped as it would be -- at [rasterScale].
  void _raster(Rect local, void Function(Canvas c) draw) {
    var page = _pageBounds(local).intersect(Offset.zero & size);
    if (!page.isFinite || page.width <= 0.5 || page.height <= 0.5) return;
    var k = rasterScale;
    var rec = ui.PictureRecorder();
    var c = Canvas(rec);
    c.scale(k);
    c.translate(-page.left, -page.top);
    for (var id = _clip; id >= 0; id = clips[id].parent) {
      c.clipPath(_clipPath(id));
    }
    c.transform(_m);
    draw(c);
    var picture = rec.endRecording();
    var image = picture.toImageSync(math.max(1, (page.width * k).ceil()),
        math.max(1, (page.height * k).ceil()));
    picture.dispose();
    ops.add(VImage(image, page, clip: -1, alpha: _alpha));
  }

  // ---- words

  /// addText records [tp]'s lines as words at [at]; false where they can't
  /// be (a gradient through them), to be drawn as a picture instead.
  bool addText(TextPainter tp, Offset at) {
    var root = tp.text;
    if (root == null) return true;
    var plain = tp.plainText;
    var lines = tp.computeLineMetrics();
    var found = <VText>[];
    for (var lm in lines) {
      var pos = tp.getPositionForOffset(
          Offset(lm.left + lm.width / 2, lm.baseline - lm.ascent / 2));
      var range = tp.getLineBoundary(pos);
      if (!range.isValid || range.start >= plain.length) continue;
      var text = plain
          .substring(range.start, math.min(range.end, plain.length))
          .replaceAll("\n", "")
          .trimRight();
      if (text.isEmpty) continue;
      var span = root.getSpanForPosition(TextPosition(offset: range.start));
      var style = (root is TextSpan ? root.style : null) ?? const TextStyle();
      if (span is TextSpan && span.style != null) {
        style = style.merge(span.style);
      }
      if (style.foreground?.shader != null) return false;
      var colour =
          style.color ?? style.foreground?.color ?? const Color(0xFF000000);
      var family = style.fontFamily ?? "sans-serif";
      // Where its letters are, from their own boxes: a line's metrics run
      // the width of a box laid out to fill it.
      var boxes = tp.getBoxesForSelection(TextSelection(
          baseOffset: range.start, extentOffset: range.start + text.length));
      var left = lm.left, width = lm.width;
      if (boxes.isNotEmpty) {
        left = boxes.map((b) => b.left).reduce(math.min);
        width = boxes.map((b) => b.right).reduce(math.max) - left;
      }
      var k = _m;
      // The line's baseline-left on the page: the transform, moved there.
      var x = at.dx + left, y = at.dy + lm.baseline;
      found.add(VText(text,
          family: family,
          size: (style.fontSize ?? 14),
          weight: style.fontWeight?.value ?? 400,
          italic: style.fontStyle == FontStyle.italic,
          colour: colour,
          letterSpacing: style.letterSpacing ?? 0,
          width: width,
          matrix: [
            k[0],
            k[1],
            k[4],
            k[5],
            k[0] * x + k[4] * y + k[12],
            k[1] * x + k[5] * y + k[13],
          ],
          clip: _clip,
          alpha: _alpha));
    }
    ops.addAll(found);
    return true;
  }

  // ---- the Canvas

  @override
  void save() => _stack.add(_State(Float64List.fromList(_m), _clip, _alpha));

  @override
  void saveLayer(Rect? bounds, Paint paint) {
    save();
    // A layer's opacity carries to what is in it; its filters are lost.
    _alpha *= paint.color.a;
  }

  @override
  void restore() {
    if (_stack.isEmpty) return;
    var s = _stack.removeLast();
    _m = s.matrix;
    _clip = s.clip;
    _alpha = s.alpha;
  }

  @override
  void restoreToCount(int count) {
    while (_stack.length + 1 > count && _stack.isNotEmpty) {
      restore();
    }
  }

  @override
  int getSaveCount() => _stack.length + 1;

  void _mul(Matrix4 by) {
    _m = (Matrix4.fromFloat64List(_m)..multiply(by)).storage;
  }

  @override
  void translate(double dx, double dy) =>
      _mul(Matrix4.translationValues(dx, dy, 0));

  @override
  void scale(double sx, [double? sy]) =>
      _mul(Matrix4.diagonal3Values(sx, sy ?? sx, 1));

  @override
  void rotate(double radians) => _mul(Matrix4.rotationZ(radians));

  @override
  void skew(double sx, double sy) => _mul(Matrix4.identity()
    ..setEntry(0, 1, sx)
    ..setEntry(1, 0, sy));

  @override
  void transform(Float64List matrix4) => _mul(Matrix4.fromFloat64List(matrix4));

  @override
  Float64List getTransform() => Float64List.fromList(_m);

  void _addClip(List<VPoly> polys) {
    clips.add(VClip(polys, _clip));
    _clip = clips.length - 1;
  }

  @override
  void clipRect(Rect rect,
      {ui.ClipOp clipOp = ui.ClipOp.intersect, bool doAntiAlias = true}) {
    if (clipOp == ui.ClipOp.difference) return;
    _addClip(_rect(rect));
  }

  @override
  void clipRRect(RRect rrect, {bool doAntiAlias = true}) =>
      _addClip(_polysOf(Path()..addRRect(rrect)));

  @override
  void clipRSuperellipse(RSuperellipse rsuperellipse,
          {bool doAntiAlias = true}) =>
      _addClip(_polysOf(Path()..addRSuperellipse(rsuperellipse)));

  @override
  void clipPath(Path path, {bool doAntiAlias = true}) =>
      _addClip(_polysOf(path));

  @override
  Rect getLocalClipBounds() {
    var inverse = Matrix4.tryInvert(Matrix4.fromFloat64List(_m));
    var page = getDestinationClipBounds();
    return inverse == null ? page : MatrixUtils.transformRect(inverse, page);
  }

  @override
  Rect getDestinationClipBounds() {
    var r = Offset.zero & size;
    for (var id = _clip; id >= 0; id = clips[id].parent) {
      r = r.intersect(_clipPath(id).getBounds());
    }
    return r;
  }

  @override
  void drawColor(Color color, BlendMode blendMode) =>
      drawPaint(Paint()..color = color);

  @override
  void drawPaint(Paint paint) {
    var local = getLocalClipBounds();
    if (!_plain(paint)) {
      _raster(local, (c) => c.drawPaint(paint));
      return;
    }
    _shape(_rect(local), Paint()..color = paint.color);
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    if (!_plain(paint)) {
      _raster(Rect.fromPoints(p1, p2).inflate(paint.strokeWidth + 1),
          (c) => c.drawLine(p1, p2, paint));
      return;
    }
    _shape([
      VPoly([_p(p1), _p(p2)], false)
    ], paint..style = PaintingStyle.stroke);
  }

  @override
  void drawRect(Rect rect, Paint paint) {
    if (!_plain(paint)) {
      _raster(
          rect.inflate(paint.strokeWidth + 2), (c) => c.drawRect(rect, paint));
      return;
    }
    _shape(_rect(rect), paint);
  }

  @override
  void drawRRect(RRect rrect, Paint paint) {
    if (!_plain(paint)) {
      _raster(rrect.outerRect.inflate(paint.strokeWidth + 2),
          (c) => c.drawRRect(rrect, paint));
      return;
    }
    _shape(_polysOf(Path()..addRRect(rrect)), paint);
  }

  @override
  void drawDRRect(RRect outer, RRect inner, Paint paint) {
    if (!_plain(paint)) {
      _raster(
          outer.outerRect.inflate(2), (c) => c.drawDRRect(outer, inner, paint));
      return;
    }
    _shape(
        _polysOf(Path()
          ..addRRect(outer)
          ..addRRect(inner)),
        paint,
        evenOdd: true);
  }

  @override
  void drawRSuperellipse(RSuperellipse rsuperellipse, Paint paint) {
    if (!_plain(paint)) {
      _raster(rsuperellipse.outerRect.inflate(paint.strokeWidth + 2),
          (c) => c.drawRSuperellipse(rsuperellipse, paint));
      return;
    }
    _shape(_polysOf(Path()..addRSuperellipse(rsuperellipse)), paint);
  }

  @override
  void drawOval(Rect rect, Paint paint) {
    if (!_plain(paint)) {
      _raster(
          rect.inflate(paint.strokeWidth + 2), (c) => c.drawOval(rect, paint));
      return;
    }
    _shape(_oval(rect), paint);
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    var r = Rect.fromCircle(center: c, radius: radius);
    if (!_plain(paint)) {
      _raster(r.inflate(paint.strokeWidth + 2),
          (k) => k.drawCircle(c, radius, paint));
      return;
    }
    _shape(_oval(r), paint);
  }

  @override
  void drawArc(Rect rect, double startAngle, double sweepAngle, bool useCenter,
      Paint paint) {
    if (!_plain(paint)) {
      _raster(rect.inflate(paint.strokeWidth + 2),
          (c) => c.drawArc(rect, startAngle, sweepAngle, useCenter, paint));
      return;
    }
    var path = Path();
    if (useCenter) {
      path
        ..moveTo(rect.center.dx, rect.center.dy)
        ..arcTo(rect, startAngle, sweepAngle, false)
        ..close();
    } else {
      path.addArc(rect, startAngle, sweepAngle);
    }
    _shape(_polysOf(path), paint);
  }

  @override
  void drawPath(Path path, Paint paint) {
    if (!_plain(paint)) {
      _raster(path.getBounds().inflate(paint.strokeWidth + 2),
          (c) => c.drawPath(path, paint));
      return;
    }
    // A filled path's open runs are closed, as a fill closes them.
    var polys = _polysOf(path);
    if (paint.style == PaintingStyle.fill) {
      polys = [for (var p in polys) VPoly(p.points, true)];
    }
    _shape(polys, paint, evenOdd: path.fillType == PathFillType.evenOdd);
  }

  @override
  void drawImage(ui.Image image, Offset offset, Paint paint) => _raster(
      offset & Size(image.width.toDouble(), image.height.toDouble()),
      (c) => c.drawImage(image, offset, paint));

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) =>
      _raster(dst, (c) => c.drawImageRect(image, src, dst, paint));

  @override
  void drawImageNine(ui.Image image, Rect center, Rect dst, Paint paint) =>
      _raster(dst, (c) => c.drawImageNine(image, center, dst, paint));

  @override
  void drawPicture(ui.Picture picture) =>
      _raster(getLocalClipBounds(), (c) => c.drawPicture(picture));

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) {
    // Laid out with no width, it says so: as wide as its longest line then.
    var w = paragraph.width.isFinite
        ? paragraph.width
        : paragraph.maxIntrinsicWidth;
    _raster(
        Rect.fromLTWH(
            offset.dx - 4, offset.dy - 4, w + 8, paragraph.height + 8),
        (c) => c.drawParagraph(paragraph, offset));
  }

  @override
  void drawPoints(ui.PointMode pointMode, List<Offset> points, Paint paint) {
    if (points.isEmpty) return;
    if (!_plain(paint)) {
      var b = points.fold<Rect?>(
              null,
              (r, p) => r == null
                  ? Rect.fromCenter(center: p, width: 1, height: 1)
                  : r.expandToInclude(
                      Rect.fromCenter(center: p, width: 1, height: 1))) ??
          Rect.zero;
      _raster(b.inflate(paint.strokeWidth + 2),
          (c) => c.drawPoints(pointMode, points, paint));
      return;
    }
    switch (pointMode) {
      case ui.PointMode.points:
        for (var p in points) {
          drawCircle(p, paint.strokeWidth / 2, Paint()..color = paint.color);
        }
      case ui.PointMode.lines:
        for (var i = 0; i + 1 < points.length; i += 2) {
          drawLine(points[i], points[i + 1], paint);
        }
      case ui.PointMode.polygon:
        _shape([
          VPoly([for (var p in points) _p(p)], false)
        ], paint..style = PaintingStyle.stroke);
    }
  }

  @override
  void drawRawPoints(ui.PointMode pointMode, Float32List points, Paint paint) =>
      drawPoints(
          pointMode,
          [
            for (var i = 0; i + 1 < points.length; i += 2)
              Offset(points[i], points[i + 1])
          ],
          paint);

  @override
  void drawVertices(ui.Vertices vertices, BlendMode blendMode, Paint paint) =>
      _raster(getLocalClipBounds(),
          (c) => c.drawVertices(vertices, blendMode, paint));

  @override
  void drawAtlas(
          ui.Image atlas,
          List<RSTransform> transforms,
          List<Rect> rects,
          List<Color>? colors,
          BlendMode? blendMode,
          Rect? cullRect,
          Paint paint) =>
      _raster(
          cullRect ?? getLocalClipBounds(),
          (c) => c.drawAtlas(
              atlas, transforms, rects, colors, blendMode, cullRect, paint));

  @override
  void drawRawAtlas(
          ui.Image atlas,
          Float32List rstTransforms,
          Float32List rects,
          Int32List? colors,
          BlendMode? blendMode,
          Rect? cullRect,
          Paint paint) =>
      _raster(
          cullRect ?? getLocalClipBounds(),
          (c) => c.drawRawAtlas(
              atlas, rstTransforms, rects, colors, blendMode, cullRect, paint));

  @override
  void drawShadow(
          Path path, Color color, double elevation, bool transparentOccluder) =>
      _raster(path.getBounds().inflate(elevation * 3 + 4),
          (c) => c.drawShadow(path, color, elevation, transparentOccluder));
}
