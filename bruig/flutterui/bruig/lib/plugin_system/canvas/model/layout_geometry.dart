import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/model/outline_points.dart';

// layout_geometry.dart is where a Layout's cells fall in its box, the one
// answer for the painter, the stage's hit tests and docked elements.
//
// A Panels cell is a convex polygon: the box (less the margin) cut by each
// cut above it in the tree, each side kept half the cut's gutter from the
// cut's line. A Grid cell is its tracks' rectangle; a Free cell its shape in
// its share of the box, turned.
//
// That is the layout in its own box. Where it is on the page on a frame is
// that geometry laid out by the layout's place there (LayoutFrame, by the
// ElementPlace the painter lays the layout out by), so whatever asks where a
// cell, a cut or a track is on the page (a docked element's clip, Panel
// mode, the stage's marks and presses) is answered where it is drawn,
// turned, slanted and moved by its motion.

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

  /// from and to are where it meets its box's edges.
  final Offset from, to;

  /// vertical is a cut from top to bottom, as its node's is.
  final bool vertical;

  /// box is the box the cut divides, which its place is a share of.
  final Rect box;

  const LayoutCutLine(
      {required this.path,
      required this.from,
      required this.to,
      required this.vertical,
      required this.box});
}

/// LayoutTrackLine is a Grid line between two columns (or rows), for the
/// stage to drag: [index] the track before it.
class LayoutTrackLine {
  final int index;

  /// column is a line between columns, running down; otherwise between
  /// rows, running across.
  final bool column;

  /// from and to are its ends, at the cells' edges.
  final Offset from, to;

  const LayoutTrackLine(
      {required this.index,
      required this.column,
      required this.from,
      required this.to});
}

/// LayoutGeometry is a layout laid out in a box, all at once: its cells,
/// and the Panels cuts or the Grid lines between tracks the stage grabs.
class LayoutGeometry {
  final List<LayoutPlace> places;
  final List<LayoutCutLine> cuts;
  final List<LayoutTrackLine> tracks;
  const LayoutGeometry(this.places, this.cuts, this.tracks);
}

/// _laidOut is the geometry last worked out for each layout, by the layout's
/// identity, with the box it was laid out in: the painter, every element
/// docked in it and the stage all ask on every frame, and a layout is a
/// value, so the same one in the same box is laid out the same. A changed
/// layout is another object, and is laid out afresh.
final _laidOut = Expando<(Rect, LayoutGeometry)>("layoutGeometry");

/// layoutGeometry is [e] laid out in [box]: see LayoutGeometry.
LayoutGeometry layoutGeometry(LayoutElement e, Rect box) {
  if (_laidOut[e] case (var at, var kept) when at == box) return kept;
  var inner = layoutInner(e, box);
  var laid = switch (e.mode) {
    LayoutMode.panels => _panels(e, inner),
    LayoutMode.grid =>
      LayoutGeometry(_grid(e, inner), const [], _trackLines(e, inner)),
    LayoutMode.free => LayoutGeometry(_free(e, inner), const [], const []),
  };
  // Kept and handed to every caller, so no caller can change it.
  var geometry = LayoutGeometry(List.unmodifiable(laid.places),
      List.unmodifiable(laid.cuts), List.unmodifiable(laid.tracks));
  _laidOut[e] = (box, geometry);
  return geometry;
}

/// layoutInner is the box the cells are laid out in: [box] less the margin.
Rect layoutInner(LayoutElement e, Rect box) {
  var m = math.min(e.margin, math.min(box.width, box.height) / 2 - 1);
  return m > 0 ? box.deflate(m) : box;
}

/// layoutPlaces is every cell of [e] in [box] (its bounds, unturned).
List<LayoutPlace> layoutPlaces(LayoutElement e, Rect box) =>
    layoutGeometry(e, box).places;

/// layoutPlaceOf is cell [id] of [e] in [box], or null.
LayoutPlace? layoutPlaceOf(LayoutElement e, Rect box, String id) {
  for (var p in layoutPlaces(e, box)) {
    if (p.cell.id == id) return p;
  }
  return null;
}

// ---- Panels ---------------------------------------------------------------

/// cutPivot is the point cut [n] turns about in [box], the box it divides:
/// where it crosses the box's middle, which its place (at) names.
Offset cutPivot(LayoutNode n, Rect box) => n.vertical
    ? Offset(box.left + n.at * box.width, box.center.dy)
    : Offset(box.center.dx, box.top + n.at * box.height);

/// _line is a cut's point and its normal (pointing towards [b]).
(Offset, Offset) _line(LayoutNode n, Rect box) {
  var t = n.tilt * math.pi / 180;
  var p = cutPivot(n, box);
  return n.vertical
      ? (p, Offset(math.cos(t), math.sin(t)))
      : (p, Offset(-math.sin(t), math.cos(t)));
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

/// cutGutter is the gap cut [n] of [e] leaves: its own, or the layout's
/// for its way (a cut down has the gutter between cells side by side).
double cutGutter(LayoutElement e, LayoutNode n) =>
    n.gutter ?? (n.vertical ? e.gutter : e.rowGutter);

/// _panels walks the tree of cuts once, cutting [inner] down to each cell
/// and noting each cut where it crosses the box it divides.
LayoutGeometry _panels(LayoutElement e, Rect inner) {
  var places = <LayoutPlace>[];
  var cuts = <LayoutCutLine>[];
  void walk(LayoutNode n, List<Offset> poly, List<bool> path) {
    if (poly.length < 3) return;
    if (n.isLeaf) {
      var cell = e.cellById(n.cell) ?? LayoutCell(id: n.cell);
      var radius = e.styleOf(cell).borderRadius;
      places.add(LayoutPlace(
          cell, _roundedPolygon(poly, radius), _boundsOf(poly), poly));
      return;
    }
    var box = _boundsOf(poly);
    var (at, normal) = _line(n, box);
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
      cuts.add(LayoutCutLine(
          path: path,
          from: hits[0],
          to: hits[1],
          vertical: n.vertical,
          box: box));
    }
    var g = cutGutter(e, n) / 2;
    walk(n.a!, _clip(poly, at, -normal, g), [...path, false]);
    walk(n.b!, _clip(poly, at, normal, g), [...path, true]);
  }

  walk(e.root, _rectPoly(inner), const []);
  return LayoutGeometry(places, cuts, const []);
}

/// layoutInMode is [e] made a layout of [mode], starting from the cells it
/// has, their names and styles kept and placed afresh: as Panels side by
/// side, then cut in rows of two; on a Grid in rows of up to three; Free,
/// each where it was drawn, as a share of the box.
LayoutElement layoutInMode(LayoutElement e, LayoutMode mode) {
  if (e.mode == mode) return e;
  var cells = e.shownCells;
  switch (mode) {
    case LayoutMode.panels:
      LayoutNode build(List<LayoutCell> list) {
        if (list.length == 1) return LayoutNode.leaf(list.single.id);
        var half = list.length ~/ 2;
        return LayoutNode.cut(
            vertical: list.length <= 2,
            at: half / list.length,
            a: build(list.sublist(0, half)),
            b: build(list.sublist(half)));
      }
      var start = cells.isEmpty ? const [LayoutCell(id: "c1")] : cells;
      return e.copyWith(mode: mode, root: build(start), cells: start);
    case LayoutMode.grid:
      var n = cells.length.clamp(1, 1000);
      var cols = n <= 2 ? n : (n <= 4 ? 2 : 3);
      var rows = (n / cols).ceil();
      return e.copyWith(
          mode: mode,
          columns: List.filled(cols, 1.0),
          rows: List.filled(rows, 1.0),
          cells: [
            for (var (i, c) in cells.indexed)
              c.copyWith(col: i % cols, row: i ~/ cols, colSpan: 1, rowSpan: 1)
          ]);
    case LayoutMode.free:
      var box = layoutInner(e, e.bounds);
      return e.copyWith(mode: mode, cells: [
        for (var p in layoutPlaces(e, e.bounds))
          p.cell.copyWith(
              x: (p.bounds.left - box.left) / box.width,
              y: (p.bounds.top - box.top) / box.height,
              width: p.bounds.width / box.width,
              height: p.bounds.height / box.height,
              turn: 0),
      ]);
  }
}

/// cutAtPoint is the place (0..1 of its box) that puts [cut] through
/// [point], its tilt kept.
double cutAtPoint(LayoutNode node, Rect box, Offset point) {
  var t = node.tilt * math.pi / 180;
  if (node.vertical) {
    // The line through point, tilted, where it crosses the box's middle.
    var x = point.dx + (box.center.dy - point.dy) * math.tan(-t);
    return ((x - box.left) / math.max(1, box.width))
        .clamp(LayoutRange.minCutAt, LayoutRange.maxCutAt);
  }
  var y = point.dy + (box.center.dx - point.dx) * math.tan(t);
  return ((y - box.top) / math.max(1, box.height))
      .clamp(LayoutRange.minCutAt, LayoutRange.maxCutAt);
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
              c, _roundedPolygon(_rectPoly(r), radius), r, _rectPoly(r));
        }(),
  ];
}

List<LayoutTrackLine> _trackLines(LayoutElement e, Rect inner) {
  var cols = _tracks(e.columns, inner.left, inner.right, e.gutter);
  var rows = _tracks(e.rows, inner.top, inner.bottom, e.rowGutter);
  return [
    for (var i = 0; i < cols.length - 1; i++)
      LayoutTrackLine(
          index: i,
          column: true,
          from: Offset((cols[i].$2 + cols[i + 1].$1) / 2, inner.top),
          to: Offset((cols[i].$2 + cols[i + 1].$1) / 2, inner.bottom)),
    for (var i = 0; i < rows.length - 1; i++)
      LayoutTrackLine(
          index: i,
          column: false,
          from: Offset(inner.left, (rows[i].$2 + rows[i + 1].$1) / 2),
          to: Offset(inner.right, (rows[i].$2 + rows[i + 1].$1) / 2)),
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

/// freeCellRect is Free cell [c]'s own rectangle in [e] laid out in [box],
/// before its turn: its share of the box less the margin.
Rect freeCellRect(LayoutElement e, Rect box, LayoutCell c) =>
    _freeRect(layoutInner(e, box), c);

Rect _freeRect(Rect inner, LayoutCell c) => Rect.fromLTWH(
    inner.left + c.x * inner.width,
    inner.top + c.y * inner.height,
    c.width * inner.width,
    c.height * inner.height);

List<LayoutPlace> _free(LayoutElement e, Rect inner) => [
      for (var c in e.cells)
        () {
          var r = _freeRect(inner, c);
          var radius = e.styleOf(c).borderRadius;
          var (path, points) = _shape(c.shape, r, radius);
          if (c.turn != 0) {
            // Turned about its own middle, as a box is (BoxFrame).
            var turn = BoxFrame(c.turn, 0, 0);
            path = turn.placePath(path, r.center);
            points = [for (var p in points) turn.place(p, r.center)];
          }
          return LayoutPlace(c, path,
              points.isEmpty ? path.getBounds() : _boundsOf(points), points);
        }(),
    ];

/// _shape is a Free cell's outline in [r], and its corners where it has
/// them: each straight-sided one is the shape's own (outline_points.dart),
/// with a cell's own numbers where they differ from a Shape's: its hexagon
/// has a corner at each side, not at the top, and its star is cut less deep.
(Path, List<Offset>) _shape(LayoutCellShape s, Rect r, double radius) {
  var c = r.center, rx = r.width / 2, ry = r.height / 2;
  List<Offset> points = switch (s) {
    LayoutCellShape.rectangle => _rectPoly(r),
    LayoutCellShape.ellipse => const [],
    LayoutCellShape.triangle => trianglePoints(r),
    LayoutCellShape.diamond => diamondPoints(r),
    LayoutCellShape.hexagon => regularPoints(c, rx, ry, 6, start: 0),
    LayoutCellShape.star => regularPoints(c, rx, ry, 10, inner: 0.45),
  };
  if (points.isEmpty) return (Path()..addOval(r), points);
  return (_roundedPolygon(points, radius), points);
}

// ---- Shared ---------------------------------------------------------------

/// _roundedPolygon is [points] joined, each corner rounded by up to
/// [radius] (never past half of either side meeting it).
Path _roundedPolygon(List<Offset> points, double radius) {
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

/// _layoutCellAt is the cell of [e] in [box] under [point], the last drawn
/// first, or null.
LayoutPlace? _layoutCellAt(LayoutElement e, Rect box, Offset point) {
  var places = layoutPlaces(e, box);
  for (var p in places.reversed) {
    if (p.path.contains(point)) return p;
  }
  return null;
}

/// LayoutFrame is a layout on the page on one frame: its geometry in its box
/// ([geometry]) laid out by [place], the ElementPlace the painter lays the
/// layout out by on that frame (turned, slanted, and moved, turned and sized
/// by its motion). Whatever asks where a cell, a cut or a track is on the
/// page asks it, there ([toPage], [pathOnPage]) and back ([fromPage]), so it
/// is answered where the cell is drawn.
class LayoutFrame {
  final LayoutElement layout;
  final ElementPlace place;
  const LayoutFrame(this.layout, this.place);

  /// geometry is its cells, cuts and tracks in its box as it rests.
  LayoutGeometry get geometry => layoutGeometry(layout, layout.bounds);

  /// toPage takes a point of the resting box to where it is drawn, fromPage
  /// brings one back, and pathOnPage takes an outline there.
  Offset toPage(Offset p) => place.place(p);
  Offset fromPage(Offset p) => place.unplace(p);
  Path pathOnPage(Path path) => place.placePath(path);

  /// cellAt is the cell under page point [p], the last drawn first, or
  /// null where it is a gutter or off the layout.
  LayoutPlace? cellAt(Offset p) =>
      _layoutCellAt(layout, layout.bounds, fromPage(p));

  /// freeCellBox is Free cell [c] as drawn on the page: its own box, before
  /// its turn, about where its middle lands, and the turn and slant it is
  /// drawn with. Its selection box and handles are this.
  (Rect, BoxFrame) freeCellBox(LayoutCell c) =>
      place.boxOnPage(freeCellRect(layout, layout.bounds, c), turn: c.turn);
}
