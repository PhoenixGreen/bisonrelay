import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';

// vector_cut.dart is the knife: a freehand line drawn through a shape cuts
// it into pieces. The shape stays one shape -- one fill, one animation, one
// row in the playlist -- and its runs are shared out among the pieces, each
// piece a part of its own (see VectorPath.part) that can be picked and moved
// on its own.
//
// Cut along the curves rather than through a flattened copy of them: the
// shape's own segments are split where the knife crosses them, so a curve
// stays a curve with two points to edit, and only the cut itself -- the
// knife's line -- is new. The two sides of a cut are pulled apart by a
// hairline [gap], so they touch nowhere and overlap nowhere.

/// _Bez is one segment of a run: a cubic, or a straight line where [line].
class _Bez {
  final Offset p0, c1, c2, p3;
  final bool line;
  const _Bez(this.p0, this.c1, this.c2, this.p3, {this.line = false});

  factory _Bez.straight(Offset a, Offset b) => _Bez(a, a, b, b, line: true);

  Offset at(double t) {
    if (line) return Offset.lerp(p0, p3, t)!;
    var u = 1 - t;
    return p0 * (u * u * u) +
        c1 * (3 * u * u * t) +
        c2 * (3 * u * t * t) +
        p3 * (t * t * t);
  }

  /// tangent is the direction it runs in at [t].
  Offset tangent(double t) {
    if (line) return p3 - p0;
    var u = 1 - t;
    var d = (c1 - p0) * (3 * u * u) +
        (c2 - c1) * (6 * u * t) +
        (p3 - c2) * (3 * t * t);
    // At an end whose handle is folded onto it, the next handle along.
    if (d.distanceSquared < 1e-18) d = t < 0.5 ? c2 - p0 : p3 - c1;
    if (d.distanceSquared < 1e-18) d = p3 - p0;
    return d;
  }

  /// split is the two halves either side of [t].
  (_Bez, _Bez) split(double t) {
    if (line) {
      var m = at(t);
      return (_Bez.straight(p0, m), _Bez.straight(m, p3));
    }
    var a = Offset.lerp(p0, c1, t)!,
        b = Offset.lerp(c1, c2, t)!,
        c = Offset.lerp(c2, p3, t)!;
    var d = Offset.lerp(a, b, t)!, e = Offset.lerp(b, c, t)!;
    var m = Offset.lerp(d, e, t)!;
    return (_Bez(p0, a, d, m), _Bez(m, e, c, p3));
  }

  /// between is the stretch of it from [t0] to [t1].
  _Bez between(double t0, double t1) {
    if (t0 <= 0 && t1 >= 1) return this;
    var tail = t0 <= 0 ? this : split(t0).$2;
    if (t1 >= 1) return tail;
    var local = t0 <= 0 ? t1 : (t1 - t0) / (1 - t0);
    return tail.split(local.clamp(0.0, 1.0)).$1;
  }

  _Bez get reversed => _Bez(p3, c2, c1, p0, line: line);

  _Bez moved({Offset start = Offset.zero, Offset end = Offset.zero}) =>
      _Bez(p0 + start, c1 + start, c2 + end, p3 + end, line: line);
}

/// _segments is [run] as segments, the closing one included where it is
/// closed.
List<_Bez> _segments(VectorPath run) {
  var nodes = run.nodes;
  var out = <_Bez>[];
  void add(VectorNode a, VectorNode b) => out.add(!a.hasOut && !b.hasIn
      ? _Bez.straight(a.point, b.point)
      : _Bez(a.point, a.outHandle, b.inHandle, b.point));
  for (var i = 1; i < nodes.length; i++) {
    add(nodes[i - 1], nodes[i]);
  }
  if (run.closed && nodes.length > 1) add(nodes.last, nodes.first);
  return out;
}

/// _run is [segs], end to end, as a run of points -- closed where [closed],
/// the last segment then ending where the first starts.
VectorPath _run(List<_Bez> segs, {required bool closed, int part = 0}) {
  var nodes = <VectorNode>[];
  for (var (i, s) in segs.indexed) {
    var before = i > 0 ? segs[i - 1] : (closed ? segs.last : null);
    nodes.add(_node(s.p0, before, s));
  }
  if (!closed && segs.isNotEmpty)
    nodes.add(_node(segs.last.p3, segs.last, null));
  return VectorPath(nodes, closed: closed, part: part);
}

/// _node is a point at [at] with the handles of the segment coming into it
/// and the one going out.
VectorNode _node(Offset at, _Bez? into, _Bez? outOf) {
  var inH = into == null || into.line ? Offset.zero : into.c2 - at;
  var outH = outOf == null || outOf.line ? Offset.zero : outOf.c1 - at;
  // Smooth where the two handles carry on in one line.
  var smooth = inH.distanceSquared > 1e-12 &&
      outH.distanceSquared > 1e-12 &&
      (inH.dx * outH.dy - inH.dy * outH.dx).abs() <
          1e-3 * inH.distance * outH.distance &&
      inH.dx * outH.dx + inH.dy * outH.dy < 0;
  return VectorNode(at.dx, at.dy,
      inX: inH.dx, inY: inH.dy, outX: outH.dx, outY: outH.dy, smooth: smooth);
}

/// _left is the side of [d] a run's filled area is kept on.
Offset _left(Offset d) {
  var l = d.distance;
  return l == 0 ? Offset.zero : Offset(d.dy, -d.dx) / l;
}

/// _crossings is where [s] crosses the knife's stretch from [a] to [b]: the
/// distance along [s], and along the stretch, both 0 to 1.
List<(double, double)> _crossings(_Bez s, Offset a, Offset b) {
  var d = b - a;
  var len2 = d.distanceSquared;
  if (len2 == 0) return const [];
  double side(Offset p) => (d.dx * (p.dy - a.dy) - d.dy * (p.dx - a.dx));
  double along(Offset p) =>
      ((p.dx - a.dx) * d.dx + (p.dy - a.dy) * d.dy) / len2;
  var out = <(double, double)>[];
  void take(double t) {
    var u = along(s.at(t));
    if (u < -1e-9 || u > 1 + 1e-9) return;
    out.add((t, u.clamp(0.0, 1.0)));
  }

  if (s.line) {
    var f0 = side(s.p0), f1 = side(s.p3);
    if ((f0 > 0 && f1 > 0) || (f0 < 0 && f1 < 0) || f0 == f1) return out;
    take(f0 / (f0 - f1));
    return out;
  }
  // Where the cubic's distance from the knife's line changes sign: found by
  // stepping along it and narrowing in on each change.
  const steps = 32;
  double f(double t) => side(s.at(t));
  var prev = f(0);
  for (var i = 1; i <= steps; i++) {
    var t1 = i / steps, cur = f(t1);
    if (prev == 0 && i == 1) take(0);
    if ((prev < 0 && cur >= 0) || (prev > 0 && cur <= 0)) {
      var lo = (i - 1) / steps, hi = t1, flo = prev;
      for (var k = 0; k < 40; k++) {
        var mid = (lo + hi) / 2, fm = f(mid);
        if ((flo < 0) == (fm < 0)) {
          lo = mid;
          flo = fm;
        } else {
          hi = mid;
        }
      }
      take((lo + hi) / 2);
    }
    prev = cur;
  }
  return out;
}

/// _Hit is one place the knife crosses a run: which run, how far round it
/// (segment and distance along it), how far along the knife, and where.
class _Hit {
  final int run;
  final double c;
  final double s;
  final Offset at;
  _Hit(this.run, this.c, this.s, this.at);
}

/// _knifeAt is the point [s] along [knife] -- a whole number for each of
/// its points.
Offset _knifeAt(List<Offset> knife, double s) {
  var k = s.floor().clamp(0, knife.length - 2);
  return Offset.lerp(knife[k], knife[k + 1], s - k)!;
}

/// _knifeBetween is the knife from [s0] to [s1], its own points included.
List<Offset> _knifeBetween(List<Offset> knife, double s0, double s1) => [
      _knifeAt(knife, s0),
      for (var k = s0.floor() + 1; k <= s1.ceil() - 1; k++)
        if (k > s0 && k < s1) knife[k],
      _knifeAt(knife, s1),
    ];

/// _area is how much a closed polygon covers, signed by which way round it
/// goes.
double _area(List<Offset> pts) {
  var a = 0.0;
  for (var i = 0; i < pts.length; i++) {
    var p = pts[i], q = pts[(i + 1) % pts.length];
    a += p.dx * q.dy - q.dx * p.dy;
  }
  return a / 2;
}

/// _flat is a closed run of segments as a polygon, for asking what is
/// inside it.
List<Offset> _flat(List<_Bez> segs) => [
      for (var s in segs)
        if (s.line)
          s.p0
        else
          for (var i = 0; i < 8; i++) s.at(i / 8),
    ];

Path _polygon(List<Offset> pts) => Path()..addPolygon(pts, true);

/// partsOf is the parts [shape] is in: one, until it has been cut.
Set<int> partsOf(VectorShape shape) => {for (var r in shape.paths) r.part};

/// cutShape is [shape] cut along [knife] -- a line of points, in the
/// drawing's own units -- each piece a part of its own, the two sides of
/// every cut [gap] apart. Null where the knife cuts nothing: a line that
/// does not go right through, or misses it.
VectorShape? cutShape(VectorShape shape, List<Offset> knife, double gap) {
  var pts = <Offset>[];
  for (var p in knife) {
    if (pts.isEmpty || (p - pts.last).distanceSquared > 1e-10) pts.add(p);
  }
  if (pts.length < 2 || shape.paths.isEmpty) return null;
  var area = shape.path;
  var bounds = area.getBounds();
  var eps = math.max(1e-4, bounds.longestSide * 1e-4);
  var nextPart = partsOf(shape).fold(0, math.max) + 1;
  var cutAny = false;

  // The runs that close round an area, each turned so the filled area is on
  // its left: what lets the walk below round a piece go one way for all of
  // them, holes and all.
  var runs = <List<_Bez>>[];
  var runOf = <int>[];
  for (var (i, run) in shape.paths.indexed) {
    if (!run.closed || run.nodes.length < 2) continue;
    var segs = _segments(run);
    var probe = segs.first;
    var mid = probe.at(0.5), toward = _left(probe.tangent(0.5));
    if (!area.contains(mid + toward * eps) &&
        area.contains(mid - toward * eps)) {
      segs = [for (var s in segs.reversed) s.reversed];
    }
    runs.add(segs);
    runOf.add(i);
  }

  // Everywhere the knife crosses them.
  var hits = <_Hit>[];
  for (var (r, segs) in runs.indexed) {
    var mine = <_Hit>[];
    for (var (j, seg) in segs.indexed) {
      for (var k = 0; k < pts.length - 1; k++) {
        for (var (t, u) in _crossings(seg, pts[k], pts[k + 1])) {
          mine.add(_Hit(r, j + t, k + u, seg.at(t)));
        }
      }
    }
    // One crossing, not two, where the knife goes through a point between
    // two segments.
    mine.sort((a, b) => a.c.compareTo(b.c));
    for (var h in mine) {
      if (hits.any((o) => o.run == r && (o.at - h.at).distance < eps * 4)) {
        continue;
      }
      hits.add(h);
    }
  }

  var pieces = <VectorPath>[];
  var touched = <int>{};

  if (hits.length >= 2) {
    hits.sort((a, b) => a.s.compareTo(b.s));
    // The stretches of knife inside the shape, between one crossing and
    // the next: the cuts. Each crossing ends one cut, and is where the
    // walk round a piece turns off its run onto it.
    var partner = <_Hit, (_Hit, List<Offset>)>{};
    var ok = true;
    for (var i = 0; i + 1 < hits.length; i++) {
      var a = hits[i], b = hits[i + 1];
      if ((b.s - a.s) < 1e-9) continue;
      if (!area.contains(_knifeAt(pts, (a.s + b.s) / 2))) continue;
      if (partner.containsKey(a) || partner.containsKey(b)) {
        ok = false;
        break;
      }
      var line = _knifeBetween(pts, a.s, b.s);
      partner[a] = (b, line);
      partner[b] = (a, line.reversed.toList());
    }

    if (ok && partner.isNotEmpty) {
      // Each run cut where the cuts meet it, into the stretches between.
      var arcFrom = <_Hit, (_Hit, List<_Bez>)>{};
      for (var r = 0; r < runs.length; r++) {
        var on = [
          for (var h in partner.keys)
            if (h.run == r) h
        ]..sort((a, b) => a.c.compareTo(b.c));
        if (on.isEmpty) continue;
        touched.add(r);
        var segs = runs[r];
        for (var i = 0; i < on.length; i++) {
          var a = on[i], b = on[(i + 1) % on.length];
          arcFrom[a] = (b, _arc(segs, a.c, b.c, wraps: i == on.length - 1));
        }
      }

      // Round each piece: along a run to a cut, across the cut, and on
      // along the run it comes out on, until back where it began.
      var done = <_Hit>{};
      var faces = <List<_Bez>>[];
      for (var start in arcFrom.keys) {
        if (done.contains(start)) continue;
        var face = <_Bez>[];
        var cur = start;
        var guard = 0;
        while (guard++ < 4 * arcFrom.length + 4) {
          done.add(cur);
          var (end, arc) = arcFrom[cur]!;
          var (across, line) = partner[end]!;
          // The cut pulled to this side by half the gap: the piece is on
          // its left, as it is of every run it follows.
          var q = _offsetLine(line, gap / 2);
          var lead = q.first - end.at, trail = q.last - across.at;
          var moved = [...arc];
          if (moved.isNotEmpty) {
            moved[moved.length - 1] = moved.last.moved(end: lead);
          }
          face.addAll(moved);
          for (var i = 0; i + 1 < q.length; i++) {
            face.add(_Bez.straight(q[i], q[i + 1]));
          }
          cur = across;
          if (identical(cur, start)) break;
          // The next run starts where this cut ends.
          var (_, nextArc) = arcFrom[cur]!;
          if (nextArc.isNotEmpty) {
            arcFrom[cur] = (
              arcFrom[cur]!.$1,
              [nextArc.first.moved(start: trail), ...nextArc.skip(1)]
            );
          }
        }
        if (!identical(cur, start)) {
          ok = false;
          break;
        }
        // The first run's start, where the walk came back round to it.
        if (face.isNotEmpty) {
          var gapAt = face.last.p3 - face.first.p0;
          face[0] = face.first.moved(start: gapAt);
        }
        faces.add(face);
      }

      if (ok) {
        cutAny = true;
        var shapes = <(List<Offset>, int)>[];
        for (var face in faces) {
          var part = nextPart++;
          shapes.add((_flat(face), part));
          pieces.add(_run(face, closed: true, part: part));
        }
        // The runs the knife missed -- a hole it went round, an island it
        // never reached -- go with the piece they are inside, and keep
        // their own part where they are inside none.
        for (var r = 0; r < runs.length; r++) {
          if (touched.contains(r)) continue;
          var original = shape.paths[runOf[r]];
          var probe = runs[r].first.at(0.5);
          (List<Offset>, int)? home;
          for (var s in shapes) {
            if (!_polygon(s.$1).contains(probe)) continue;
            if (home == null || _area(s.$1).abs() < _area(home.$1).abs()) {
              home = s;
            }
          }
          pieces
              .add(home == null ? original : original.copyWith(part: home.$2));
        }
      } else {
        touched.clear();
        pieces.clear();
      }
    }
  }
  if (!cutAny) {
    // The closed runs as they were.
    for (var r = 0; r < runs.length; r++) {
      pieces.add(shape.paths[runOf[r]]);
    }
  }

  // The open runs -- lines -- cut wherever the knife crosses them, each
  // stretch a part of its own, with the gap taken out at each cut.
  for (var run in shape.paths) {
    if (run.closed && run.nodes.length >= 2) continue;
    if (run.nodes.length < 2) {
      pieces.add(run);
      continue;
    }
    var segs = _segments(run);
    var at = <double>[];
    for (var (j, seg) in segs.indexed) {
      for (var k = 0; k < pts.length - 1; k++) {
        for (var (t, _) in _crossings(seg, pts[k], pts[k + 1])) {
          var c = j + t;
          if (at.every((o) => (o - c).abs() > 1e-6)) at.add(c);
        }
      }
    }
    if (at.isEmpty) {
      pieces.add(run);
      continue;
    }
    cutAny = true;
    at.sort();
    var cuts = [0.0, ...at, segs.length.toDouble()];
    for (var i = 0; i + 1 < cuts.length; i++) {
      var from = cuts[i], to = cuts[i + 1];
      // Half the gap off each end that was cut, measured along the run.
      if (i > 0) from = _alongBy(segs, from, gap / 2);
      if (i + 2 < cuts.length) to = _alongBy(segs, to, -gap / 2);
      if (to <= from) continue;
      var stretch = _arc(segs, from, to, wraps: false);
      if (stretch.isEmpty) continue;
      pieces.add(_run(stretch, closed: false, part: nextPart++));
    }
  }

  if (!cutAny) return null;
  return shape.copyWith(paths: pieces);
}

/// _alongBy is the place [by] further along [segs] from [c] -- back, where
/// it is less than nought -- in the same segment-and-distance terms.
double _alongBy(List<_Bez> segs, double c, double by) {
  var j = c.floor().clamp(0, segs.length - 1);
  var t = c - j;
  var speed = segs[j].tangent(t.clamp(0.0, 1.0)).distance;
  if (speed <= 0) return c;
  return (c + by / speed).clamp(j.toDouble(), j + 1.0);
}

/// _arc is [segs] from [c0] round to [c1] -- each a segment's number and a
/// distance along it -- carrying on past the end and round from the start
/// where it [wraps].
List<_Bez> _arc(List<_Bez> segs, double c0, double c1, {required bool wraps}) {
  var n = segs.length;
  var out = <_Bez>[];
  var j0 = c0.floor().clamp(0, n - 1), t0 = c0 - j0;
  var end = wraps ? c1 + n : c1;
  var j1 = end.floor(), t1 = end - j1;
  if (t1 == 0 && j1 > j0) {
    j1 -= 1;
    t1 = 1;
  }
  for (var j = j0; j <= j1; j++) {
    var seg = segs[j % n];
    var a = j == j0 ? t0 : 0.0;
    var b = j == j1 ? t1 : 1.0;
    if (b - a < 1e-9) continue;
    out.add(seg.between(a, b));
  }
  return out;
}

/// _offsetLine is [line] moved [by] to its left, each point along the
/// average of the two stretches it joins.
List<Offset> _offsetLine(List<Offset> line, double by) {
  if (by == 0 || line.length < 2) return line;
  return [
    for (var i = 0; i < line.length; i++)
      line[i] +
          (() {
            var a = i > 0 ? _left(line[i] - line[i - 1]) : null;
            var b = i + 1 < line.length ? _left(line[i + 1] - line[i]) : null;
            var n = a == null ? b! : (b == null ? a : a + b);
            var l = n.distance;
            return l == 0 ? Offset.zero : n / l * by;
          })(),
  ];
}

/// simplifiedKnife is a freehand line with the points that add nothing
/// taken out -- any within [tolerance] of the straight line past them.
List<Offset> simplifiedKnife(List<Offset> pts, double tolerance) {
  if (pts.length < 3) return pts;
  var keep = List<bool>.filled(pts.length, false);
  keep[0] = keep[pts.length - 1] = true;
  void rdp(int a, int b) {
    if (b <= a + 1) return;
    var far = -1.0, at = -1;
    var d = pts[b] - pts[a];
    var len = d.distance;
    for (var i = a + 1; i < b; i++) {
      var p = pts[i] - pts[a];
      var dist =
          len == 0 ? p.distance : (d.dx * p.dy - d.dy * p.dx).abs() / len;
      if (dist > far) {
        far = dist;
        at = i;
      }
    }
    if (far > tolerance) {
      keep[at] = true;
      rdp(a, at);
      rdp(at, b);
    }
  }

  rdp(0, pts.length - 1);
  return [
    for (var i = 0; i < pts.length; i++)
      if (keep[i]) pts[i]
  ];
}

/// partPath is the area -- and lines -- of [shape]'s part [part] alone.
Path partPath(VectorShape shape, int part) => VectorShape(
      paths: [
        for (var r in shape.paths)
          if (r.part == part) r
      ],
      evenOdd: shape.evenOdd,
    ).path;

/// partAt is the part of [shape] at [at] -- inside one of its areas, or
/// within [reach] of one of its lines -- or null. Where one sits inside
/// another, the smaller.
int? partAt(VectorShape shape, Offset at, double reach) {
  int? best;
  var bestSize = double.infinity;
  for (var part in partsOf(shape)) {
    var runs = [
      for (var r in shape.paths)
        if (r.part == part) r
    ];
    var area = VectorShape(paths: [
      for (var r in runs)
        if (r.closed) r
    ], evenOdd: shape.evenOdd)
        .path;
    var hit = area.contains(at);
    if (!hit) {
      var lines = VectorShape(paths: runs).path;
      var near = math.max(reach, shape.strokeWidth / 2);
      for (var m in lines.computeMetrics()) {
        for (var d = 0.0; d <= m.length && !hit; d += math.max(0.5, near / 2)) {
          var p = m.getTangentForOffset(d)?.position;
          if (p != null && (p - at).distance <= near) hit = true;
        }
        if (hit) break;
      }
    }
    if (!hit) continue;
    var b = VectorShape(paths: runs).path.getBounds();
    var size = b.width * b.height;
    if (size < bestSize) {
      best = part;
      bestSize = size;
    }
  }
  return best;
}
