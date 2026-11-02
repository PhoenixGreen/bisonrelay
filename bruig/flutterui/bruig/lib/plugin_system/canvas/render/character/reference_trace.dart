import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/reference_sheet.dart';

// reference_trace.dart turns a figure on a model sheet into shapes, as an
// image trace does: each pixel given the nearest of the character's own
// colours and the part of the body under it, each run of one colour on one
// part outlined, the outline smoothed, holes and all. A part's shapes are
// its own, so they go with it when it moves; and every colour is one of the
// palette's, so the drawing is in the character's paints, not in a JPEG's
// thousand shades of them. Plain functions over pixels, as the sheet's
// reading is.

/// TracedRegion is a run of one colour on one part: its outline -- the
/// first ring around it, any others holes in it -- in the sheet's pixels.
class TracedRegion {
  /// colour is which of the palette it is painted; part is which of the
  /// parts it is on, by the number partOf gave.
  final int colour;
  final int part;
  final List<List<Offset>> rings;

  /// area is how many pixels it covers.
  final int area;
  final Rect bounds;
  const TracedRegion(
      this.colour, this.part, this.rings, this.area, this.bounds);
}

/// traceRegions traces what is drawn in [cut] of [p] in [palette]'s
/// colours, split by [partOf] -- which part a point of the sheet is on, by
/// number -- its largest first. It is read [zoom] times finer than its
/// pixels, blended between them, so an outline follows the drawing's edge
/// between pixels rather than their steps. Specks smaller than [least] of
/// the sheet's pixels are taken into what is round them.
List<TracedRegion> traceRegions(SheetPixels p, Rect cut, List<Color> palette,
    int Function(Offset sheet) partOf,
    {double tolerance = 0.12,
    double least = 2,
    double smooth = 0.45,
    int zoom = 3}) {
  if (palette.isEmpty) return const [];
  var x0 = cut.left.floor().clamp(0, p.width - 1);
  var y0 = cut.top.floor().clamp(0, p.height - 1);
  var w = ((cut.right.ceil().clamp(1, p.width) - x0) * zoom).toInt();
  var h = ((cut.bottom.ceil().clamp(1, p.height) - y0) * zoom).toInt();
  if (w <= 0 || h <= 0) return const [];
  var ground = p.background;
  Offset sheetAt(double x, double y) => Offset(x0 + x / zoom, y0 + y / zoom);

  // Each pixel's colour: the nearest of the palette's, or none -- where it
  // is nearer the sheet's own than any of them, as the gap between two
  // legs, blended with both, is.
  var colour = List<int>.filled(w * h, -1);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var q = sheetAt(x + 0.5, y + 0.5);
      var c = p.sample(q.dx, q.dy);
      var toGround = _distance(c, ground);
      if (c.a < 0.5 || toGround <= tolerance) continue;
      var best = 0;
      var bestD = double.infinity;
      for (var (i, s) in palette.indexed) {
        var d = _distance(c, s);
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      }
      if (toGround < bestD) continue;
      // A blend of a paint and the sheet -- an outline's soft edge -- is
      // the paint where it is mostly the paint, and the sheet otherwise:
      // not a third colour, a halo round everything.
      var blended = blendOf(c, ground, palette);
      if (blended case (var i, var t) when bestD > 0.04) {
        if (t < 0.5) continue;
        best = i;
      }
      colour[y * w + x] = best;
    }
  }
  // A pixel unlike most round it is the picture's grain -- a JPEG's,
  // an edge's blend of two paints -- not the drawing: given theirs.
  colour = _majority(_majority(colour, w, h), w, h);

  // Each pixel's part, and so its key: colour and part together.
  var parts = <int>[];
  var key = List<int>.filled(w * h, -1);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var i = y * w + x;
      if (colour[i] < 0) continue;
      var part = partOf(sheetAt(x + 0.5, y + 0.5));
      var k = parts.indexOf(part);
      if (k < 0) {
        k = parts.length;
        parts.add(part);
      }
      key[i] = colour[i] * 64 + k;
    }
  }

  // Specks taken into their neighbours, a few times over: a speck next
  // to a speck finds a region the next time.
  var fewest = math.max(1, (least * zoom * zoom).round());
  for (var pass = 0; pass < 4; pass++) {
    var (label, sizes) = _components(key, w, h);
    var changed = false;
    for (var i = 0; i < key.length; i++) {
      if (key[i] < 0 || sizes[label[i]] >= fewest) continue;
      var x = i % w, y = i ~/ w;
      var best = -1, bestSize = 0;
      for (var (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        var nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        var j = ny * w + nx;
        if (key[j] < 0 || key[j] == key[i]) continue;
        if (sizes[label[j]] > bestSize) {
          bestSize = sizes[label[j]];
          best = key[j];
        }
      }
      if (best >= 0) {
        key[i] = best;
        changed = true;
      }
    }
    if (!changed) break;
  }

  var (label, sizes) = _components(key, w, h);
  var out = <TracedRegion>[];
  var firstOf = <int, int>{};
  for (var i = 0; i < key.length; i++) {
    if (label[i] >= 0) firstOf.putIfAbsent(label[i], () => i);
  }
  for (var MapEntry(key: l, value: first) in firstOf.entries) {
    if (sizes[l] < fewest) continue;
    var rings = [
      for (var ring in _rings(label, l, w, h))
        if (_simplified(ring, smooth * zoom) case var r when r.length >= 3)
          [for (var q in r) sheetAt(q.dx, q.dy)],
    ];
    if (rings.isEmpty) continue;
    // The outline first: the ring reaching furthest.
    rings.sort((a, b) => _extent(b).compareTo(_extent(a)));
    var k = key[first];
    var bounds = rings.first.skip(1).fold(
        Rect.fromPoints(rings.first.first, rings.first.first),
        (Rect r, q) => r.expandToInclude(Rect.fromPoints(q, q)));
    out.add(TracedRegion(k ~/ 64, parts[k % 64], rings,
        (sizes[l] / (zoom * zoom)).round(), bounds));
  }
  out.sort((a, b) => b.area.compareTo(a.area));
  return out;
}

/// traceShape is [region] as a shape, in [palette]'s colour, each point
/// put by [place] -- from the sheet to where it is drawn -- its outline
/// drawn smooth, and a line of its own colour round it, [seam] wide, so
/// two regions traced side by side meet without a crack between.
VectorShape traceShape(TracedRegion region, List<Color> palette,
    Offset Function(Offset sheet) place,
    {double seam = 0.6}) {
  var colour = palette[region.colour];
  return VectorShape(
    paths: [
      for (var ring in region.rings)
        VectorPath(_smoothNodes([for (var q in ring) place(q)]), closed: true),
    ],
    fill: colour,
    stroke: seam > 0 ? colour : null,
    strokeWidth: seam,
    join: StrokeJoin.round,
    evenOdd: true,
  );
}

/// blendOf is which of [palette] [c] is a blend of with [ground] -- and
/// how much of it, nought to one -- where it lies near the line between
/// them; null where it is no such blend.
(int, double)? blendOf(Color c, Color ground, List<Color> palette,
    {double near = 0.035}) {
  (int, double)? found;
  var closest = near;
  for (var (i, s) in palette.indexed) {
    var pr = s.r - ground.r, pg = s.g - ground.g, pb = s.b - ground.b;
    var len = pr * pr + pg * pg + pb * pb;
    if (len < 0.01) continue;
    var cr = c.r - ground.r, cg = c.g - ground.g, cb = c.b - ground.b;
    var t = (cr * pr + cg * pg + cb * pb) / len;
    if (t <= 0.05 || t >= 0.95) continue;
    var dr = cr - t * pr, dg = cg - t * pg, db = cb - t * pb;
    var off = math.sqrt(dr * dr + dg * dg + db * db);
    if (off < closest) {
      closest = off;
      found = (i, t);
    }
  }
  return found;
}

double _distance(Color a, Color b) {
  var dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b;
  return math.sqrt(dr * dr + dg * dg + db * db);
}

/// _majority is [labels] with each pixel given what most of the nine round
/// it are, where its own is in at most two of them.
List<int> _majority(List<int> labels, int w, int h) {
  var out = [...labels];
  var counts = <int, int>{};
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      counts.clear();
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          var nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          var l = labels[ny * w + nx];
          counts[l] = (counts[l] ?? 0) + 1;
        }
      }
      var own = labels[y * w + x];
      if ((counts[own] ?? 0) > 2) continue;
      var best = own, most = 0;
      for (var MapEntry(:key, :value) in counts.entries) {
        if (value > most) {
          most = value;
          best = key;
        }
      }
      if (most >= 4) out[y * w + x] = best;
    }
  }
  return out;
}

/// _components numbers each four-way joined run of one key, and counts
/// each; -1 where there is no key.
(List<int>, List<int>) _components(List<int> key, int w, int h) {
  var label = List<int>.filled(key.length, -1);
  var sizes = <int>[];
  var queue = Queue<int>();
  for (var start = 0; start < key.length; start++) {
    if (key[start] < 0 || label[start] >= 0) continue;
    var l = sizes.length;
    var n = 0;
    label[start] = l;
    queue.add(start);
    while (queue.isNotEmpty) {
      var i = queue.removeFirst();
      n++;
      var x = i % w, y = i ~/ w;
      for (var (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        var nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        var j = ny * w + nx;
        if (label[j] >= 0 || key[j] != key[start]) continue;
        label[j] = l;
        queue.add(j);
      }
    }
    sizes.add(n);
  }
  return (label, sizes);
}

/// _rings are the outlines of the pixels labelled [l]: each a loop round
/// their edges, clockwise, through the corners of the pixel grid.
List<List<Offset>> _rings(List<int> label, int l, int w, int h) {
  bool on(int x, int y) =>
      x >= 0 && y >= 0 && x < w && y < h && label[y * w + x] == l;
  int corner(int x, int y) => y * (w + 1) + x;
  // Each edge with the region on its right, from corner to corner.
  var from = <int, List<int>>{};
  void edge(int ax, int ay, int bx, int by) =>
      (from[corner(ax, ay)] ??= []).add(corner(bx, by));
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (!on(x, y)) continue;
      if (!on(x, y - 1)) edge(x, y, x + 1, y);
      if (!on(x + 1, y)) edge(x + 1, y, x + 1, y + 1);
      if (!on(x, y + 1)) edge(x + 1, y + 1, x, y + 1);
      if (!on(x - 1, y)) edge(x, y + 1, x, y);
    }
  }
  Offset at(int c) =>
      Offset((c % (w + 1)).toDouble(), (c ~/ (w + 1)).toDouble());
  var rings = <List<Offset>>[];
  while (from.isNotEmpty) {
    var start = from.keys.first;
    var ring = <Offset>[];
    var c = start;
    Offset? came;
    while (true) {
      var outs = from[c];
      if (outs == null || outs.isEmpty) break;
      // Where two corners of the region touch, turn the way that keeps it
      // on the right: the ring goes round one, not across both.
      var pick = 0;
      if (outs.length > 1 && came != null) {
        var here = at(c);
        var best = double.infinity;
        for (var (i, o) in outs.indexed) {
          var d = at(o) - here;
          var turn = came.dx * d.dy - came.dy * d.dx;
          if (turn < best) {
            best = turn;
            pick = i;
          }
        }
      }
      var next = outs.removeAt(pick);
      if (outs.isEmpty) from.remove(c);
      ring.add(at(c));
      came = at(next) - at(c);
      c = next;
      if (c == start) break;
    }
    if (ring.length >= 3) rings.add(ring);
  }
  return rings;
}

/// _simplified is [ring] with points in a straight line left out, then
/// those no further than [tolerance] from the line through their
/// neighbours: Douglas and Peucker's, closed.
List<Offset> _simplified(List<Offset> ring, double tolerance) {
  if (ring.length < 4) return ring;
  // Split at the two points furthest apart, and simplify each half.
  var a = 0, b = 0;
  var far = 0.0;
  for (var i = 0; i < ring.length; i++) {
    var d = (ring[i] - ring[0]).distanceSquared;
    if (d > far) {
      far = d;
      b = i;
    }
  }
  if (b == 0) return ring;
  var first = _douglasPeucker(ring.sublist(a, b + 1), tolerance);
  var second = _douglasPeucker([...ring.sublist(b), ring[a]], tolerance);
  return [
    ...first.sublist(0, first.length - 1),
    ...second.sublist(0, second.length - 1)
  ];
}

List<Offset> _douglasPeucker(List<Offset> pts, double tolerance) {
  if (pts.length < 3) return pts;
  var a = pts.first, b = pts.last;
  var ab = b - a;
  var len = ab.distance;
  var worst = 0.0;
  var at = 0;
  for (var i = 1; i < pts.length - 1; i++) {
    var ap = pts[i] - a;
    var d =
        len == 0 ? ap.distance : (ab.dx * ap.dy - ab.dy * ap.dx).abs() / len;
    if (d > worst) {
      worst = d;
      at = i;
    }
  }
  if (worst <= tolerance) return [a, b];
  var left = _douglasPeucker(pts.sublist(0, at + 1), tolerance);
  var right = _douglasPeucker(pts.sublist(at), tolerance);
  return [...left.sublist(0, left.length - 1), ...right];
}

double _extent(List<Offset> ring) {
  var r = Rect.fromPoints(ring.first, ring.first);
  for (var q in ring) {
    r = r.expandToInclude(Rect.fromPoints(q, q));
  }
  return r.width + r.height;
}

/// _smoothNodes are [pts] as a smooth closed outline: each point's handles
/// along the line through its neighbours, a sixth of the way to each --
/// Catmull and Rom's curve -- except at a sharp corner, kept sharp.
List<VectorNode> _smoothNodes(List<Offset> pts) {
  var n = pts.length;
  return [
    for (var i = 0; i < n; i++)
      () {
        var prev = pts[(i - 1 + n) % n], here = pts[i], next = pts[(i + 1) % n];
        var a = here - prev, b = next - here;
        var cos = a.distance == 0 || b.distance == 0
            ? 1.0
            : (a.dx * b.dx + a.dy * b.dy) / (a.distance * b.distance);
        // Turning by more than about a right angle, between sides not
        // short -- not a pixel's step -- a corner.
        var shortest = math.min(a.distance, b.distance);
        var longest = math.max(a.distance, b.distance);
        if (cos < -0.1 && shortest > longest * 0.3) {
          return VectorNode(here.dx, here.dy);
        }
        var t = (next - prev) / 6;
        // Not past either neighbour: a short side beside a long one would
        // overshoot.
        var most = math.min(a.distance, b.distance) * 0.5;
        if (t.distance > most && t.distance > 0) t = t * (most / t.distance);
        return VectorNode(here.dx, here.dy,
            inX: -t.dx, inY: -t.dy, outX: t.dx, outY: t.dy, smooth: true);
      }(),
  ];
}
