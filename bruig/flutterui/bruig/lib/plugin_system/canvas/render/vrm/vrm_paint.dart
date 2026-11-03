import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/elements/character_sculpt.dart';

// vrm_paint.dart draws paint strokes (character_sculpt.dart) into a picture
// laid out as a surface's own picture is -- by its triangles' texture
// coordinates -- so that it can be laid over the surface. Each pixel of a
// triangle is put back where it is on the body, in 3D, and painted by how
// near the stroke passed: so a dab painted across a seam in the picture is
// whole on the body, and a stroke is as wide on a stretched part of the
// picture as on any other. Plain Dart, run off the main isolate and tested
// without a GPU.

/// PaintLayer is a surface's paint: the picture, its size, and the
/// triangles any of it is on.
///
/// Laid out as the surface is, [triangles] are the surface's own vertices
/// and [uv] and [source] are null. Laid out in cells of its own -- for a
/// surface whose layout repeats, or overlaps -- each triangle has three
/// vertices of its own: [source] says which of the surface's each is, and
/// [uv] where it is in the picture.
class PaintLayer {
  final Uint8List rgba;
  final int size;
  final Uint32List triangles;
  final Float32List? uv;
  final Uint32List? source;
  const PaintLayer(this.rgba, this.size, this.triangles,
      {this.uv, this.source});
}

/// _Stroke is a stroke ready to paint with: its points, and its mirror
/// image's, as flat lists.
class _Stroke {
  final PaintStroke s;
  final Float64List p, n;
  final double lox, loy, loz, hix, hiy, hiz;
  _Stroke(this.s, this.p, this.n, this.lox, this.loy, this.loz, this.hix,
      this.hiy, this.hiz);

  factory _Stroke.of(PaintStroke s, double side) {
    final n = s.points.length;
    final p = Float64List(n * 3), nn = Float64List(n * 3);
    var lox = double.infinity, loy = double.infinity, loz = double.infinity;
    var hix = -double.infinity, hiy = -double.infinity, hiz = -double.infinity;
    for (var k = 0; k < n; k++) {
      final q = s.points[k];
      p[k * 3] = q.x * side;
      p[k * 3 + 1] = q.y;
      p[k * 3 + 2] = q.z;
      nn[k * 3] = q.nx * side;
      nn[k * 3 + 1] = q.ny;
      nn[k * 3 + 2] = q.nz;
      lox = math.min(lox, p[k * 3]);
      loy = math.min(loy, q.y);
      loz = math.min(loz, q.z);
      hix = math.max(hix, p[k * 3]);
      hiy = math.max(hiy, q.y);
      hiz = math.max(hiz, q.z);
    }
    final r = s.radius;
    return _Stroke(
        s, p, nn, lox - r, loy - r, loz - r, hix + r, hiy + r, hiz + r);
  }

  bool near(double x0, double y0, double z0, double x1, double y1, double z1) =>
      x1 >= lox &&
      x0 <= hix &&
      y1 >= loy &&
      y0 <= hiy &&
      z1 >= loz &&
      z0 <= hiz;

  /// reach is how much of the stroke reaches ([x], [y], [z]) facing
  /// ([fx], [fy], [fz]), nought to one.
  double reach(double x, double y, double z, double fx, double fy, double fz) {
    final r = s.radius, r2 = r * r;
    var best = r2;
    var k0 = -1;
    for (var k = 0; k < p.length; k += 3) {
      final dx = x - p[k], dy = y - p[k + 1], dz = z - p[k + 2];
      final q = dx * dx + dy * dy + dz * dz;
      if (q < best) {
        best = q;
        k0 = k;
      }
    }
    if (k0 < 0) return 0;
    // Not through to the far side of something thin.
    if (fx * n[k0] + fy * n[k0 + 1] + fz * n[k0 + 2] < 0) return 0;
    final d = math.sqrt(best) / r;
    // Full to (1 - softness) of the way out, fading to the edge.
    final soft = s.softness.clamp(0.02, 1.0);
    final t = ((1 - d) / soft).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }
}

/// paintLayer paints [strokes] over a surface of [positions] and [normals]
/// (the body as made) laid out by [uv], of [triangles], into a [size]
/// square picture -- or, with [cells], into a picture of its own, a cell
/// for each triangle, as big as they need. Null where none of them is on
/// it.
PaintLayer? paintLayer({
  required Float32List positions,
  required Float32List normals,
  required Float32List uv,
  required Uint32List triangles,
  required List<PaintStroke> strokes,
  int size = 1024,
  bool cells = false,
}) {
  final ready = [
    for (final s in strokes)
      if (s.points.isNotEmpty) ...[
        _Stroke.of(s, 1),
        if (s.mirror) _Stroke.of(s, -1),
      ]
  ];
  if (ready.isEmpty) return null;
  // The triangles near any stroke.
  final near = <int>[];
  final whose = <List<_Stroke>>[];
  for (var t = 0; t + 2 < triangles.length; t += 3) {
    final i0 = triangles[t], i1 = triangles[t + 1], i2 = triangles[t + 2];
    double c(int i, int a) => positions[i * 3 + a];
    final x0 = math.min(c(i0, 0), math.min(c(i1, 0), c(i2, 0))),
        x1 = math.max(c(i0, 0), math.max(c(i1, 0), c(i2, 0)));
    final y0 = math.min(c(i0, 1), math.min(c(i1, 1), c(i2, 1))),
        y1 = math.max(c(i0, 1), math.max(c(i1, 1), c(i2, 1)));
    final z0 = math.min(c(i0, 2), math.min(c(i1, 2), c(i2, 2))),
        z1 = math.max(c(i0, 2), math.max(c(i1, 2), c(i2, 2)));
    final by = [
      for (final s in ready)
        if (s.near(x0, y0, z0, x1, y1, z1)) s
    ];
    if (by.isEmpty) continue;
    near.add(t);
    whose.add(by);
  }
  if (near.isEmpty) return null;
  // Each triangle's corners in the picture, in pixels.
  final grid = cells ? math.sqrt(near.length).ceil() : 0;
  if (cells) {
    // Twenty-four pixels a cell at least, in a picture no bigger than 2048.
    size = 256;
    while (size < grid * 24 && size < 2048) {
      size *= 2;
    }
  }
  final corners = Float32List(near.length * 6);
  final cell = cells ? size / grid : 0.0;
  for (var j = 0; j < near.length; j++) {
    if (cells) {
      final x = (j % grid) * cell, y = (j ~/ grid) * cell;
      const pad = 2.5;
      corners.setAll(j * 6, [
        x + pad, y + pad, //
        x + cell - pad * 2, y + pad,
        x + pad, y + cell - pad * 2,
      ]);
    } else {
      final t = near[j];
      for (var k = 0; k < 3; k++) {
        final i = triangles[t + k];
        corners[j * 6 + k * 2] = uv[i * 2] * size;
        corners[j * 6 + k * 2 + 1] = uv[i * 2 + 1] * size;
      }
    }
  }

  // Premultiplied colour and coverage, painted stroke by stroke.
  final n = size * size;
  final col = Float32List(n * 3), cover = Float32List(n);
  // This stroke's reach at each pixel: the most of it, not the sum, so a
  // pixel two triangles share at a seam is not painted twice.
  final mask = Float32List(n);
  final hit = <int>[];
  final hitOnce = Uint8List(n);
  final kept = <int>{};
  for (final s in ready) {
    hit.clear();
    for (var j = 0; j < near.length; j++) {
      if (!whose[j].contains(s)) continue;
      final t = near[j];
      final i0 = triangles[t], i1 = triangles[t + 1], i2 = triangles[t + 2];
      if (_raster(s, size, positions, normals, corners, j, i0, i1, i2, mask,
          hit, hitOnce)) {
        kept.add(j);
      }
    }
    final st = s.s;
    final r = ((st.colour >> 16) & 0xff) / 255,
        g = ((st.colour >> 8) & 0xff) / 255,
        b = (st.colour & 0xff) / 255;
    for (final i in hit) {
      final a = mask[i] * st.opacity;
      mask[i] = 0;
      hitOnce[i] = 0;
      if (a <= 0) continue;
      final keep = 1 - a;
      if (st.tool == PaintTool.rubOut) {
        col[i * 3] *= keep;
        col[i * 3 + 1] *= keep;
        col[i * 3 + 2] *= keep;
        cover[i] *= keep;
      } else {
        col[i * 3] = col[i * 3] * keep + r * a;
        col[i * 3 + 1] = col[i * 3 + 1] * keep + g * a;
        col[i * 3 + 2] = col[i * 3 + 2] * keep + b * a;
        cover[i] = cover[i] * keep + a;
      }
    }
  }
  if (kept.isEmpty) return null;
  final out = Uint8List(n * 4);
  for (var i = 0; i < n; i++) {
    final a = cover[i];
    if (a <= 0.001) continue;
    out[i * 4] = (col[i * 3] / a * 255).round().clamp(0, 255);
    out[i * 4 + 1] = (col[i * 3 + 1] / a * 255).round().clamp(0, 255);
    out[i * 4 + 2] = (col[i * 3 + 2] / a * 255).round().clamp(0, 255);
    out[i * 4 + 3] = (a * 255).round().clamp(0, 255);
  }
  final order = kept.toList()..sort();
  if (!cells) {
    return PaintLayer(
        out,
        size,
        Uint32List.fromList([
          for (final j in order)
            for (var k = 0; k < 3; k++) triangles[near[j] + k]
        ]));
  }
  final source = Uint32List(order.length * 3),
      at = Float32List(order.length * 6);
  for (var m = 0; m < order.length; m++) {
    final j = order[m];
    for (var k = 0; k < 3; k++) {
      source[m * 3 + k] = triangles[near[j] + k];
      at[m * 6 + k * 2] = corners[j * 6 + k * 2] / size;
      at[m * 6 + k * 2 + 1] = corners[j * 6 + k * 2 + 1] / size;
    }
  }
  return PaintLayer(out, size,
      Uint32List.fromList([for (var i = 0; i < source.length; i++) i]),
      uv: at, source: source);
}

/// _raster paints stroke [s] into [mask] over triangle [i0] [i1] [i2],
/// whose corners in the picture are the [j]th three of [corners], a pixel
/// past its edge so no seam shows a gap; the pixels it reached go in [hit].
/// True if it reached any.
bool _raster(
    _Stroke s,
    int size,
    Float32List pos,
    Float32List nrm,
    Float32List corners,
    int j,
    int i0,
    int i1,
    int i2,
    Float32List mask,
    List<int> hit,
    Uint8List hitOnce) {
  final ax = corners[j * 6], ay = corners[j * 6 + 1];
  final bx = corners[j * 6 + 2], by = corners[j * 6 + 3];
  final cx = corners[j * 6 + 4], cy = corners[j * 6 + 5];
  final det = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy);
  if (det.abs() < 1e-9) return false;
  final x0 = math.max(0, (math.min(ax, math.min(bx, cx)) - 1).floor()),
      x1 = math.min(size - 1, (math.max(ax, math.max(bx, cx)) + 1).ceil());
  final y0 = math.max(0, (math.min(ay, math.min(by, cy)) - 1).floor()),
      y1 = math.min(size - 1, (math.max(ay, math.max(by, cy)) + 1).ceil());
  // How far outside, in barycentric terms, a pixel's middle may be and still
  // be painted: about a pixel and a half.
  final span = math.max(
      1.0,
      math.max(
          (ax - bx).abs() + (ay - by).abs(),
          math.max((bx - cx).abs() + (by - cy).abs(),
              (cx - ax).abs() + (cy - ay).abs())));
  final slack = -1.5 / span;
  var any = false;
  for (var y = y0; y <= y1; y++) {
    final py = y + 0.5;
    for (var x = x0; x <= x1; x++) {
      final px = x + 0.5;
      var w0 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / det;
      var w1 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / det;
      var w2 = 1 - w0 - w1;
      if (w0 < slack || w1 < slack || w2 < slack) continue;
      // Kept to the triangle, for where on the body it is.
      w0 = math.max(0, w0);
      w1 = math.max(0, w1);
      w2 = math.max(0, w2);
      final sum = w0 + w1 + w2;
      w0 /= sum;
      w1 /= sum;
      w2 /= sum;
      double at(Float32List a, int k) =>
          a[i0 * 3 + k] * w0 + a[i1 * 3 + k] * w1 + a[i2 * 3 + k] * w2;
      final reach = s.reach(at(pos, 0), at(pos, 1), at(pos, 2), at(nrm, 0),
          at(nrm, 1), at(nrm, 2));
      if (reach <= 0) continue;
      final i = y * size + x;
      if (reach > mask[i]) mask[i] = reach;
      if (hitOnce[i] == 0) {
        hitOnce[i] = 1;
        hit.add(i);
      }
      any = true;
    }
  }
  return any;
}
