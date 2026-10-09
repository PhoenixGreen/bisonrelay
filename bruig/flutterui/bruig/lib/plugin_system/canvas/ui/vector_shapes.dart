import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';

// vector_shapes.dart is the shape tool's shapes: boxes, circles, polygons,
// stars, lines, arrows, marks -- the starting points of a drawing or an
// icon. Each is made of the same points and handles as anything else in a
// drawing, so once it is down it is edited like anything else.

/// VectorShapeKind is one of the shapes the shape tool draws.
enum VectorShapeKind {
  box("Box"),
  roundedBox("Rounded box"),
  circle("Circle"),
  oval("Oval"),
  polygon("Polygon"),
  star("Star"),
  line("Line"),
  arrow("Arrow"),
  check("Check"),
  cross("Cross"),
  plus("Plus"),
  heart("Heart");

  final String label;
  const VectorShapeKind(this.label);

  /// lined is whether it is a line rather than an area: drawn with a line
  /// and no fill, whatever the fill is set to.
  bool get lined => switch (this) {
        line || arrow || check || cross || plus => true,
        _ => false,
      };

  /// fromEnds is whether it is drawn from where the drag starts to where it
  /// ends, rather than in the box between them.
  bool get fromEnds => this == line || this == arrow;

  /// even is whether its box is kept square: a circle is a round oval.
  bool get even => this == circle;
}

/// kappa is how long a circle's handles are, as a share of its radius: the
/// length that makes four cubic curves as near a circle as they can be.
const double kappa = 0.5522847498;

/// shapeOf is [kind] drawn in [box] -- or, for a line or an arrow, from
/// [from] to [to] -- in the drawing's units. [sides] is a polygon's sides
/// and a star's points, [inner] a star's inner points as a share of its
/// outer ones, and [corner] a rounded box's corner radius.
VectorShape shapeOf(
  VectorShapeKind kind,
  Rect box, {
  Offset? from,
  Offset? to,
  int sides = 5,
  double inner = 0.5,
  double corner = 10,
  Color? fill,
  Color? stroke,
  double strokeWidth = 2,
}) {
  var lined = kind.lined;
  var paths = _paths(kind, box,
      from: from ?? box.topLeft,
      to: to ?? box.bottomRight,
      sides: sides,
      inner: inner,
      corner: corner);
  return VectorShape(
    paths: paths,
    fill: lined ? null : fill,
    // A line with no colour would be nothing at all.
    stroke: lined ? (stroke ?? const Color(0xFF000000)) : stroke,
    strokeWidth: strokeWidth,
    cap: lined ? StrokeCap.round : StrokeCap.butt,
    join: lined ? StrokeJoin.round : StrokeJoin.miter,
  );
}

List<VectorPath> _paths(VectorShapeKind kind, Rect r,
    {required Offset from,
    required Offset to,
    required int sides,
    required double inner,
    required double corner}) {
  VectorNode at(double fx, double fy) =>
      VectorNode(r.left + r.width * fx, r.top + r.height * fy);
  switch (kind) {
    case VectorShapeKind.box:
      return [
        VectorPath([
          VectorNode(r.left, r.top),
          VectorNode(r.right, r.top),
          VectorNode(r.right, r.bottom),
          VectorNode(r.left, r.bottom),
        ], closed: true)
      ];
    case VectorShapeKind.roundedBox:
      var c = corner.clamp(0.0, math.min(r.width, r.height) / 2).toDouble();
      if (c <= 0) {
        return _paths(VectorShapeKind.box, r,
            from: from, to: to, sides: sides, inner: inner, corner: 0);
      }
      var h = c * kappa;
      return [
        VectorPath([
          VectorNode(r.left + c, r.top, inX: -h),
          VectorNode(r.right - c, r.top, outX: h),
          VectorNode(r.right, r.top + c, inY: -h),
          VectorNode(r.right, r.bottom - c, outY: h),
          VectorNode(r.right - c, r.bottom, inX: h),
          VectorNode(r.left + c, r.bottom, outX: -h),
          VectorNode(r.left, r.bottom - c, inY: h),
          VectorNode(r.left, r.top + c, outY: -h),
        ], closed: true)
      ];
    case VectorShapeKind.circle || VectorShapeKind.oval:
      var rx = r.width / 2, ry = r.height / 2, c = r.center;
      VectorNode round(double x, double y, double dx, double dy) =>
          VectorNode(x, y,
              inX: -dx,
              inY: -dy,
              outX: dx,
              outY: dy,
              smooth: true,
              mirrored: true);
      return [
        VectorPath([
          round(c.dx, r.top, rx * kappa, 0),
          round(r.right, c.dy, 0, ry * kappa),
          round(c.dx, r.bottom, -rx * kappa, 0),
          round(r.left, c.dy, 0, -ry * kappa),
        ], closed: true)
      ];
    case VectorShapeKind.polygon:
      return [
        VectorPath(
            _fitted(r, [
              for (var i = 0; i < math.max(3, sides); i++)
                _onCircle(i / math.max(3, sides), 1)
            ]),
            closed: true)
      ];
    case VectorShapeKind.star:
      var n = math.max(3, sides);
      return [
        VectorPath(
            _fitted(r, [
              for (var i = 0; i < n * 2; i++)
                _onCircle(i / (n * 2), i.isEven ? 1 : inner.clamp(0.05, 1.0))
            ]),
            closed: true)
      ];
    case VectorShapeKind.line:
      return [
        VectorPath([VectorNode(from.dx, from.dy), VectorNode(to.dx, to.dy)])
      ];
    case VectorShapeKind.arrow:
      var d = to - from;
      var len = d.distance;
      if (len == 0) {
        return _paths(VectorShapeKind.line, r,
            from: from, to: to, sides: sides, inner: inner, corner: corner);
      }
      var u = d / len;
      var head = math.min(len * 0.35, math.max(len * 0.2, 8.0));
      Offset side(double turn) {
        var a = math.atan2(-u.dy, -u.dx) + turn;
        return to + Offset(math.cos(a), math.sin(a)) * head;
      }

      var left = side(math.pi / 6), right = side(-math.pi / 6);
      return [
        VectorPath([VectorNode(from.dx, from.dy), VectorNode(to.dx, to.dy)]),
        VectorPath([
          VectorNode(left.dx, left.dy),
          VectorNode(to.dx, to.dy),
          VectorNode(right.dx, right.dy),
        ]),
      ];
    case VectorShapeKind.check:
      return [
        VectorPath([at(0.08, 0.55), at(0.38, 0.88), at(0.94, 0.12)])
      ];
    case VectorShapeKind.cross:
      return [
        VectorPath([at(0.1, 0.1), at(0.9, 0.9)]),
        VectorPath([at(0.9, 0.1), at(0.1, 0.9)]),
      ];
    case VectorShapeKind.plus:
      return [
        VectorPath([at(0.5, 0.05), at(0.5, 0.95)]),
        VectorPath([at(0.05, 0.5), at(0.95, 0.5)]),
      ];
    case VectorShapeKind.heart:
      // Two lobes and a point, each lobe a pair of curves, drawn in a unit
      // box and then stretched so the curves themselves -- not the points,
      // which sit inside them -- fill the box dragged.
      VectorNode n(double x, double y,
              {double ix = 0, double iy = 0, double ox = 0, double oy = 0}) =>
          VectorNode(x, y, inX: ix, inY: iy, outX: ox, outY: oy);
      var unit = VectorShape(paths: [
        VectorPath([
          n(0.5, 0.26, ix: 0.12, iy: -0.24, ox: -0.12, oy: -0.24),
          n(0.0, 0.33, ix: 0.0, iy: -0.3, ox: 0.0, oy: 0.26),
          n(0.5, 1.0, ix: -0.28, iy: -0.22, ox: 0.28, oy: -0.22),
          n(1.0, 0.33, ix: 0.0, iy: 0.26, ox: 0.0, oy: -0.3),
        ], closed: true)
      ]);
      var ext = shapeExtent(unit)!;
      var sx = r.width / ext.width, sy = r.height / ext.height;
      return [
        VectorPath([
          for (var v in unit.paths.single.nodes)
            VectorNode(
                r.left + (v.x - ext.left) * sx, r.top + (v.y - ext.top) * sy,
                inX: v.inX * sx,
                inY: v.inY * sy,
                outX: v.outX * sx,
                outY: v.outY * sy),
        ], closed: true)
      ];
  }
}

/// _onCircle is the point [turn] of the way round a circle of [radius],
/// starting at the top and going clockwise -- so a polygon or a star stands
/// on a side, with a point at the top.
Offset _onCircle(double turn, double radius) {
  var a = -math.pi / 2 + turn * 2 * math.pi;
  return Offset(math.cos(a), math.sin(a)) * radius;
}

/// _fitted is [points] stretched to fill [box] exactly: a five-sided shape
/// is not as tall as it is wide, and drawn in a box it should fill the box.
List<VectorNode> _fitted(Rect box, List<Offset> points) {
  var b = Rect.fromPoints(points.first, points.first);
  for (var p in points) {
    b = b.expandToInclude(Rect.fromPoints(p, p));
  }
  double sx(double x) => b.width == 0
      ? box.center.dx
      : box.left + (x - b.left) / b.width * box.width;
  double sy(double y) => b.height == 0
      ? box.center.dy
      : box.top + (y - b.top) / b.height * box.height;
  return [for (var p in points) VectorNode(sx(p.dx), sy(p.dy))];
}
