import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// image_warp.dart is a picture bent by a grid of points over it: each point
// moved, and the picture following in smooth curves through them. The grid is
// fractions of the picture's own box -- nought to one across and down -- so a
// warp moves, sizes and turns with the picture it is on.

/// mostWarpCells is the most cells a warp grid has across or down.
const int mostWarpCells = 10;

/// ImageWarp is a picture's warp grid: [cols] by [rows] cells, so one more
/// point than that each way.
class ImageWarp {
  final int cols;
  final int rows;

  /// points are where each grid point is, row by row from the top-left, as
  /// fractions of the picture's box -- or empty for an even grid, a picture
  /// not warped at all.
  final List<Offset> points;

  const ImageWarp({this.cols = 4, this.rows = 4, this.points = const []});

  /// even is a grid of [cols] by [rows] cells, nothing moved.
  factory ImageWarp.even(int cols, int rows) =>
      ImageWarp(cols: cols, rows: rows, points: [
        for (var i = 0; i <= rows; i++)
          for (var j = 0; j <= cols; j++) Offset(j / cols, i / rows)
      ]);

  int get across => cols + 1;
  int get down => rows + 1;

  /// active is whether the picture is bent at all.
  bool get active {
    if (points.length != across * down) return false;
    for (var i = 0; i <= rows; i++) {
      for (var j = 0; j <= cols; j++) {
        var p = points[i * across + j];
        if ((p.dx - j / cols).abs() > 1e-6 || (p.dy - i / rows).abs() > 1e-6) {
          return true;
        }
      }
    }
    return false;
  }

  /// grid is every point, the even grid where none has been moved yet.
  List<Offset> get grid => points.length == across * down
      ? points
      : ImageWarp.even(cols, rows).points;

  /// at is the point [j] across and [i] down; past the edges, the grid
  /// carried on straight, so the curve runs on through the outermost points
  /// rather than bending back at them.
  Offset at(List<Offset> g, int i, int j) {
    if (i < 0) return at(g, 0, j) * 2 - at(g, 1, j);
    if (i > rows) return at(g, rows, j) * 2 - at(g, rows - 1, j);
    if (j < 0) return at(g, i, 0) * 2 - at(g, i, 1);
    if (j > cols) return at(g, i, cols) * 2 - at(g, i, cols - 1);
    return g[i * across + j];
  }

  /// sample is where the point [u] across and [v] down the picture -- its
  /// own fractions -- is drawn: through every grid point, in smooth curves
  /// between them (Catmull-Rom, across then down). Past nought or one, the
  /// warp carried on.
  Offset sample(double u, double v, [List<Offset>? g]) {
    g ??= grid;
    var x = u * cols, y = v * rows;
    var j = x.floor().clamp(0, cols - 1), i = y.floor().clamp(0, rows - 1);
    var tx = x - j, ty = y - i;
    Offset row(int r) => _catmull(
        at(g!, r, j - 1), at(g, r, j), at(g, r, j + 1), at(g, r, j + 2), tx);
    return _catmull(row(i - 1), row(i), row(i + 1), row(i + 2), ty);
  }

  static Offset _catmull(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    var t2 = t * t, t3 = t2 * t;
    return (p1 * 2 +
            (p2 - p0) * t +
            (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 +
            (p1 * 3 - p0 - p2 * 3 + p3) * t3) *
        0.5;
  }

  /// regridded is this warp with [cols] by [rows] cells, each new point
  /// where the warp already puts it: the shape kept, the grid finer or
  /// coarser.
  ImageWarp regridded(int cols, int rows) {
    cols = cols.clamp(1, mostWarpCells);
    rows = rows.clamp(1, mostWarpCells);
    if (cols == this.cols && rows == this.rows) return this;
    if (!active) return ImageWarp(cols: cols, rows: rows);
    var g = grid;
    return ImageWarp(cols: cols, rows: rows, points: [
      for (var i = 0; i <= rows; i++)
        for (var j = 0; j <= cols; j++) sample(j / cols, i / rows, g)
    ]);
  }

  /// withPoints is this warp with [next] as its points.
  ImageWarp withPoints(List<Offset> next) =>
      ImageWarp(cols: cols, rows: rows, points: List.unmodifiable(next));

  /// reset is the even grid of this many cells.
  ImageWarp get reset => ImageWarp(cols: cols, rows: rows);

  Map<String, dynamic> toJson() => {
        "c": cols,
        "r": rows,
        if (active)
          "p": [
            for (var p in points) ...[_round(p.dx), _round(p.dy)]
          ],
      };

  static double _round(double v) => (v * 100000).round() / 100000;

  factory ImageWarp.fromJson(Map<String, dynamic> json) {
    var cols = jsonInt(json["c"], 4).clamp(1, mostWarpCells);
    var rows = jsonInt(json["r"], 4).clamp(1, mostWarpCells);
    var raw = json["p"];
    var points = <Offset>[];
    if (raw is List && raw.length == (cols + 1) * (rows + 1) * 2) {
      for (var k = 0; k + 1 < raw.length; k += 2) {
        points.add(
            Offset((raw[k] as num).toDouble(), (raw[k + 1] as num).toDouble()));
      }
    }
    return ImageWarp(cols: cols, rows: rows, points: points);
  }

  @override
  bool operator ==(Object other) =>
      other is ImageWarp &&
      other.cols == cols &&
      other.rows == rows &&
      _samePoints(other.points, points);

  static bool _samePoints(List<Offset> a, List<Offset> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(cols, rows, points.length,
      points.isEmpty ? 0 : points.first, points.isEmpty ? 0 : points.last);
}

/// warpMesh is [warp] as triangles for Canvas.drawVertices: [box] -- the
/// picture's box -- bent, each grid cell cut [fine] times each way so the
/// curves are smooth, with [texture] saying where each corner of it is in
/// the picture as drawn (a raster of [room], [scale] pixels to a unit).
Vertices warpMesh(ImageWarp warp, Rect box, Rect room, double scale,
    {int fine = 8}) {
  var g = warp.grid;
  var nx = warp.cols * fine, ny = warp.rows * fine;
  // The mesh covers the room the picture is drawn in, its fractions of the
  // box past nought and one where the room is larger.
  double u0 = (room.left - box.left) / box.width;
  double u1 = (room.right - box.left) / box.width;
  double v0 = (room.top - box.top) / box.height;
  double v1 = (room.bottom - box.top) / box.height;
  var positions = <Offset>[];
  var texture = <Offset>[];
  for (var i = 0; i <= ny; i++) {
    for (var j = 0; j <= nx; j++) {
      var u = u0 + (u1 - u0) * j / nx, v = v0 + (v1 - v0) * i / ny;
      var p = warp.sample(u, v, g);
      positions.add(box.topLeft + Offset(p.dx * box.width, p.dy * box.height));
      texture.add(Offset((box.left + u * box.width - room.left) * scale,
          (box.top + v * box.height - room.top) * scale));
    }
  }
  var indices = <int>[];
  for (var i = 0; i < ny; i++) {
    for (var j = 0; j < nx; j++) {
      var a = i * (nx + 1) + j, b = a + 1, c = a + nx + 1, d = c + 1;
      indices.addAll([a, b, c, b, d, c]);
    }
  }
  return Vertices(VertexMode.triangles, positions,
      textureCoordinates: texture, indices: indices);
}

/// warpBounds is where [warp] draws [box]'s corners and edges, to the
/// nearest box round them all: what a warped picture reaches.
Rect warpBounds(ImageWarp warp, Rect box) {
  if (!warp.active) return box;
  var g = warp.grid;
  var lo = const Offset(double.infinity, double.infinity);
  var hi = const Offset(-double.infinity, -double.infinity);
  for (var k = 0; k <= 20; k++) {
    for (var (u, v) in [
      (k / 20, 0.0),
      (k / 20, 1.0),
      (0.0, k / 20),
      (1.0, k / 20)
    ]) {
      var p = warp.sample(u, v, g);
      lo = Offset(math.min(lo.dx, p.dx), math.min(lo.dy, p.dy));
      hi = Offset(math.max(hi.dx, p.dx), math.max(hi.dy, p.dy));
    }
  }
  return Rect.fromLTRB(
      box.left + lo.dx * box.width,
      box.top + lo.dy * box.height,
      box.left + hi.dx * box.width,
      box.top + hi.dy * box.height);
}
