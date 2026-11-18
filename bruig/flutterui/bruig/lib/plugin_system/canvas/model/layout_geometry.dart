import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';

// layout_geometry.dart is where a Layout's cells fall in its box, the one
// answer for the painter, the stage's hit tests and docked elements.
//
// A Panels cell is a convex polygon: the box (less the margin) cut by each
// cut above it in the tree, each side kept half the cut's gutter from the
// cut's line. A Grid cell is its tracks' rectangle; a Free cell its shape in
// its share of the box, turned.

/// LayoutPlace is one cell as drawn.
class LayoutPlace {
  final LayoutCell cell;

  /// path is its outline, its corners rounded by its style; bounds the
  /// rectangle round it, which a docked element is fitted to.
  final Path path;
  final Rect bounds;

  /// points is a straight-sided cell's corners, unrounded, or empty.
  final List<Offset> points;

  const LayoutPlace(this.cell, this.path, this.bounds, this.points);
}

/// LayoutCutLine is a Panels cut where it crosses its box, for the stage to
/// grab: [path] is the way to its node down the tree.
class LayoutCutLine {
  final List<bool> path;
  final Offset from, to;
  final bool vertical;

  /// box is the box the cut divides, which its place is a share of.
  final Rect box;

  const LayoutCutLine(this.path, this.from, this.to, this.vertical, this.box);
}

/// LayoutTrackLine is a Grid line between two columns (or rows), for the
/// stage to drag: [index] the track before it.
class LayoutTrackLine {
  final int index;
  final bool column;
  final Offset from, to;
  const LayoutTrackLine(this.index, this.column, this.from, this.to);
}

/// layoutInner is the box the cells are laid out in: [box] less the margin.
Rect layoutInner(LayoutElement e, Rect box) {
  var m = math.min(e.margin, math.min(box.width, box.height) / 2 - 1);
  return m > 0 ? box.deflate(m) : box;
}

/// layoutPlaces is every cell of [e] in [box] (its bounds, unturned).
List<LayoutPlace> layoutPlaces(LayoutElement e, Rect box) {
  var inner = layoutInner(e, box);
  return switch (e.mode) {
    LayoutMode.panels => _panels(e, inner),
    LayoutMode.grid => _grid(e, inner),
    LayoutMode.free => _free(e, inner),
  };
}

/// layoutPlaceOf is cell [id] of [e] in [box], or null.
LayoutPlace? layoutPlaceOf(LayoutElement e, Rect box, String id) {
  for (var p in layoutPlaces(e, box)) {
    if (p.cell.id == id) return p;
  }
  return null;
}

// ---- Panels ---------------------------------------------------------------

/// _line is a cut's point and its normal (pointing towards [b]).
(Offset, Offset) _line(LayoutNode n, Rect box) {
  var t = n.tilt * math.pi / 180;
  if (n.vertical) {
    var p = Offset(box.left + n.at * box.width, box.center.dy);
    return (p, Offset(math.cos(t), math.sin(t)));
  }
  var p = Offset(box.center.dx, box.top + n.at * box.height);
  return (p, Offset(-math.sin(t), math.cos(t)));
}

double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

/// _clip keeps the part of convex [poly] where (p - at)·normal >= keep.
List<Offset> _clip(List<Offset> poly, Offset at, Offset normal, double keep) {
  if (poly.isEmpty) return poly;
  double f(Offset p) => _dot(p - at, normal) - keep;
  var out = <Offset>[];
  for (var i = 0; i < poly.length; i++) {
    var p = poly[i], q = poly[(i + 1) % poly.length];
    var fp = f(p), fq = f(q);
    if (fp >= 0) out.add(p);
    if ((fp >= 0) != (fq >= 0)) {
      var t = fp / (fp - fq);
      out.add(Offset.lerp(p, q, t)!);
    }
  }
  return out;
}

Rect _boundsOf(List<Offset> poly) {
  if (poly.isEmpty) return Rect.zero;
  var l = poly.first.dx, r = l, t = poly.first.dy, b = t;
  for (var p in poly) {
    l = math.min(l, p.dx);
    r = math.max(r, p.dx);
    t = math.min(t, p.dy);
    b = math.max(b, p.dy);
  }
  return Rect.fromLTRB(l, t, r, b);
}

List<Offset> _rectPoly(Rect r) =>
    [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];

double _cutGutter(LayoutElement e, LayoutNode n) =>
    n.gutter ?? (n.vertical ? e.gutter : e.rowGutter);

List<LayoutPlace> _panels(LayoutElement e, Rect inner) {
  var out = <LayoutPlace>[];
  void walk(LayoutNode n, List<Offset> poly) {
    if (poly.length < 3) return;
    if (n.isLeaf) {
      var cell = e.cellById(n.cell) ?? LayoutCell(id: n.cell);
      var radius = e.styleOf(cell).borderRadius;
      out.add(LayoutPlace(
          cell, roundedPolygon(poly, radius), _boundsOf(poly), poly));
      return;
    }
    var box = _boundsOf(poly);
    var (at, normal) = _line(n, box);
    var g = _cutGutter(e, n) / 2;
    walk(n.a!, _clip(poly, at, -normal, g));
    walk(n.b!, _clip(poly, at, normal, g));
  }

  walk(e.root, _rectPoly(inner));
  return out;
}

/// layoutCutLines is each Panels cut where it crosses its box.
List<LayoutCutLine> layoutCutLines(LayoutElement e, Rect box) {
  if (e.mode != LayoutMode.panels) return const [];
  var out = <LayoutCutLine>[];
  void walk(LayoutNode n, List<Offset> poly, List<bool> path) {
    if (n.isLeaf || poly.length < 3) return;
    var bounds = _boundsOf(poly);
    var (at, normal) = _line(n, bounds);
    // Where the line meets the polygon's edges.
    var hits = <Offset>[];
    for (var i = 0; i < poly.length; i++) {
      var p = poly[i], q = poly[(i + 1) % poly.length];
      var fp = _dot(p - at, normal), fq = _dot(q - at, normal);
      if ((fp >= 0) != (fq >= 0)) {
        hits.add(Offset.lerp(p, q, fp / (fp - fq))!);
      }
    }
    if (hits.length >= 2) {
      out.add(LayoutCutLine(path, hits[0], hits[1], n.vertical, bounds));
    }
    var g = _cutGutter(e, n) / 2;
    walk(n.a!, _clip(poly, at, -normal, g), [...path, false]);
    walk(n.b!, _clip(poly, at, normal, g), [...path, true]);
  }

  walk(e.root, _rectPoly(layoutInner(e, box)), const []);
  return out;
}

/// cutAtPoint is the place (0..1 of its box) that puts [cut] through
/// [point], its tilt kept.
double cutAtPoint(LayoutNode node, Rect box, Offset point) {
  var t = node.tilt * math.pi / 180;
  if (node.vertical) {
    // The line through point, tilted, where it crosses the box's middle.
    var x = point.dx + (box.center.dy - point.dy) * math.tan(-t);
    return ((x - box.left) / math.max(1, box.width)).clamp(0.02, 0.98);
  }
  var y = point.dy + (box.center.dx - point.dx) * math.tan(t);
  return ((y - box.top) / math.max(1, box.height)).clamp(0.02, 0.98);
}

// ---- Grid -----------------------------------------------------------------

/// _tracks is each track's start and end along [from]..[to].
List<(double, double)> _tracks(
    List<double> weights, double from, double to, double gap) {
  var n = weights.length;
  var room = math.max(0.0, (to - from) - gap * (n - 1));
  var total = weights.fold(0.0, (a, b) => a + b);
  var out = <(double, double)>[];
  var at = from;
  for (var w in weights) {
    var size = total <= 0 ? room / n : room * w / total;
    out.add((at, at + size));
    at += size + gap;
  }
  return out;
}

List<LayoutPlace> _grid(LayoutElement e, Rect inner) {
  var cols = _tracks(e.columns, inner.left, inner.right, e.gutter);
  var rows = _tracks(e.rows, inner.top, inner.bottom, e.rowGutter);
  return [
    for (var c in e.cells)
      if (c.col < cols.length && c.row < rows.length)
        () {
          var lastCol = math.min(cols.length - 1, c.col + c.colSpan - 1);
          var lastRow = math.min(rows.length - 1, c.row + c.rowSpan - 1);
          var r = Rect.fromLTRB(cols[c.col].$1, rows[c.row].$1,
              cols[lastCol].$2, rows[lastRow].$2);
          var radius = e.styleOf(c).borderRadius;
          return LayoutPlace(
              c, roundedPolygon(_rectPoly(r), radius), r, _rectPoly(r));
        }(),
  ];
}

/// layoutTrackLines is a Grid's lines between tracks, down the middle of
/// each gap.
List<LayoutTrackLine> layoutTrackLines(LayoutElement e, Rect box) {
  if (e.mode != LayoutMode.grid) return const [];
  var inner = layoutInner(e, box);
  var cols = _tracks(e.columns, inner.left, inner.right, e.gutter);
  var rows = _tracks(e.rows, inner.top, inner.bottom, e.rowGutter);
  return [
    for (var i = 0; i < cols.length - 1; i++)
      LayoutTrackLine(
          i,
          true,
          Offset((cols[i].$2 + cols[i + 1].$1) / 2, inner.top),
          Offset((cols[i].$2 + cols[i + 1].$1) / 2, inner.bottom)),
    for (var i = 0; i < rows.length - 1; i++)
      LayoutTrackLine(
          i,
          false,
          Offset(inner.left, (rows[i].$2 + rows[i + 1].$1) / 2),
          Offset(inner.right, (rows[i].$2 + rows[i + 1].$1) / 2)),
  ];
}

/// tracksMoved is [weights] with the line after track [index] moved by
/// [by] (in the box's units), the two tracks beside it sharing the change.
List<double> tracksMoved(
    List<double> weights, int index, double by, double length, double gap) {
  if (index < 0 || index >= weights.length - 1) return weights;
  var room = math.max(1.0, length - gap * (weights.length - 1));
  var total = weights.fold(0.0, (a, b) => a + b);
  var perUnit = total / room;
  var a = weights[index], b = weights[index + 1];
  var shift = (by * perUnit).clamp(-(a - total * 0.02), b - total * 0.02);
  return [
    for (var (i, w) in weights.indexed)
      i == index
          ? a + shift
          : i == index + 1
              ? b - shift
              : w
  ];
}

// ---- Free -----------------------------------------------------------------

List<LayoutPlace> _free(LayoutElement e, Rect inner) => [
      for (var c in e.cells)
        () {
          var r = Rect.fromLTWH(
              inner.left + c.x * inner.width,
              inner.top + c.y * inner.height,
              c.width * inner.width,
              c.height * inner.height);
          var radius = e.styleOf(c).borderRadius;
          var (path, points) = _shape(c.shape, r, radius);
          if (c.turn != 0) {
            var m = _turnAbout(r.center, c.turn);
            path = path.transform(m);
            points = [for (var p in points) _apply(m, p)];
          }
          return LayoutPlace(c, path,
              points.isEmpty ? path.getBounds() : _boundsOf(points), points);
        }(),
    ];

(Path, List<Offset>) _shape(LayoutCellShape s, Rect r, double radius) {
  List<Offset> regular(int n, double start, {double inner = 1}) => [
        for (var i = 0; i < n; i++)
          () {
            var a = start + i * 2 * math.pi / n;
            var k = inner != 1 && i.isOdd ? inner : 1.0;
            return Offset(r.center.dx + math.cos(a) * r.width / 2 * k,
                r.center.dy + math.sin(a) * r.height / 2 * k);
          }(),
      ];
  List<Offset> points = switch (s) {
    LayoutCellShape.rectangle => _rectPoly(r),
    LayoutCellShape.ellipse => const [],
    LayoutCellShape.triangle => [
        Offset(r.center.dx, r.top),
        r.bottomRight,
        r.bottomLeft
      ],
    LayoutCellShape.diamond => [
        Offset(r.center.dx, r.top),
        Offset(r.right, r.center.dy),
        Offset(r.center.dx, r.bottom),
        Offset(r.left, r.center.dy)
      ],
    LayoutCellShape.hexagon => regular(6, 0),
    LayoutCellShape.star => regular(10, -math.pi / 2, inner: 0.45),
  };
  if (points.isEmpty) return (Path()..addOval(r), points);
  return (roundedPolygon(points, radius), points);
}

Float64List _turnAbout(Offset c, double degrees) {
  var a = degrees * math.pi / 180;
  var cs = math.cos(a), sn = math.sin(a);
  // Column-major 4x4: translate(c) * rotate(a) * translate(-c).
  return Float64List.fromList([
    cs, sn, 0, 0, //
    -sn, cs, 0, 0,
    0, 0, 1, 0,
    c.dx - cs * c.dx + sn * c.dy, c.dy - sn * c.dx - cs * c.dy, 0, 1,
  ]);
}

Offset _apply(Float64List m, Offset p) => Offset(
    m[0] * p.dx + m[4] * p.dy + m[12], m[1] * p.dx + m[5] * p.dy + m[13]);

// ---- Shared ---------------------------------------------------------------

/// roundedPolygon is [points] joined, each corner rounded by up to
/// [radius] (never past half of either side meeting it).
Path roundedPolygon(List<Offset> points, double radius) {
  var path = Path();
  if (points.length < 3) return path;
  if (radius <= 0) {
    path.addPolygon(points, true);
    return path;
  }
  var n = points.length;
  for (var i = 0; i < n; i++) {
    var prev = points[(i - 1 + n) % n],
        p = points[i],
        next = points[(i + 1) % n];
    var toPrev = prev - p, toNext = next - p;
    var r = math.min(radius, math.min(toPrev.distance, toNext.distance) / 2);
    var a = p + toPrev / math.max(1e-9, toPrev.distance) * r;
    var b = p + toNext / math.max(1e-9, toNext.distance) * r;
    if (i == 0) {
      path.moveTo(a.dx, a.dy);
    } else {
      path.lineTo(a.dx, a.dy);
    }
    path.quadraticBezierTo(p.dx, p.dy, b.dx, b.dy);
  }
  path.close();
  return path;
}

/// layoutCellAt is the cell of [e] in [box] under [point], the last drawn
/// first, or null.
LayoutPlace? layoutCellAt(LayoutElement e, Rect box, Offset point) {
  var places = layoutPlaces(e, box);
  for (var p in places.reversed) {
    if (p.path.contains(point)) return p;
  }
  return null;
}
