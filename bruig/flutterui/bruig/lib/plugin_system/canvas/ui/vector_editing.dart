import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/svg_import.dart';
import 'package:bruig/plugin_system/canvas/model/vector_brush.dart';
import 'package:bruig/plugin_system/canvas/render/vector_painter.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';

// vector_editing.dart is the arithmetic of editing a drawing point by point:
// where a point of the drawing is on the canvas and back, what is under the
// pointer, and the edits themselves -- move a point or a handle, put a point
// in a curve, take one out, make one a corner or smooth. Kept out of the
// stage, which only has to ask.

/// VectorTool is what a press on a drawing being edited does.
enum VectorTool {
  select("Select points"),
  pen("Pen"),
  scale("Line thickness"),
  tint("Tint"),
  boolean("Combine shapes"),
  align("Align points"),
  corner("Round corners"),
  pencil("Pencil"),
  eraser("Eraser");

  final String label;
  const VectorTool(this.label);
}

/// VectorPick is one point of a drawing: which shape, which run of it, and
/// which point along the run.
class VectorPick {
  final int shape;
  final int path;
  final int node;
  const VectorPick(this.shape, this.path, this.node);

  @override
  bool operator ==(Object other) =>
      other is VectorPick &&
      other.shape == shape &&
      other.path == path &&
      other.node == node;

  @override
  int get hashCode => Object.hash(shape, path, node);
}

/// VectorPart is which part of a point is taken hold of.
enum VectorPart { point, inHandle, outHandle }

/// VectorHit is what is under the pointer while a drawing is being edited.
class VectorHit {
  final VectorPick pick;
  final VectorPart part;
  const VectorHit(this.pick, this.part);
}

/// VectorSpace turns the drawing's own units into the canvas's and back, for
/// one element as it stands: its box, its fit, and its turn.
class VectorSpace {
  final VectorElement e;
  final ({double sx, double sy, double dx, double dy}) _p;
  final Offset _centre;
  final double _cos, _sin;

  VectorSpace(this.e)
      : _p = e.placement(e.bounds, e.viewBox),
        _centre = e.bounds.center,
        _cos = math.cos(e.rotation * math.pi / 180),
        _sin = math.sin(e.rotation * math.pi / 180);

  /// toCanvas is where a point of the drawing is on the canvas.
  Offset toCanvas(Offset v) {
    var at = Offset(v.dx * _p.sx + _p.dx, v.dy * _p.sy + _p.dy) - _centre;
    return _centre +
        Offset(at.dx * _cos - at.dy * _sin, at.dx * _sin + at.dy * _cos);
  }

  /// toDrawing is the point of the drawing under a point of the canvas.
  Offset toDrawing(Offset c) {
    var at = c - _centre;
    var un = _centre +
        Offset(at.dx * _cos + at.dy * _sin, -at.dx * _sin + at.dy * _cos);
    return Offset((un.dx - _p.dx) / (_p.sx == 0 ? 1 : _p.sx),
        (un.dy - _p.dy) / (_p.sy == 0 ? 1 : _p.sy));
  }

  /// unitsPer is how many of the drawing's units one canvas unit is, for
  /// turning a reach on the canvas into one in the drawing.
  double get unitsPer {
    var s = math.min(_p.sx.abs(), _p.sy.abs());
    return s == 0 ? 1 : 1 / s;
  }
}

/// hitVector is what is under [canvasPoint] on [e] within [reach] canvas
/// units: a handle of the point picked, then any point of the shape picked,
/// then nothing. Handles first, so one sitting on its own point can still be
/// pulled out.
///
/// [picks] are the points picked, which can be taken hold of whichever shape
/// they are on: a box can pick from several.
VectorHit? hitVector(VectorElement e, Offset canvasPoint, double reach,
    {required int shape,
    VectorPick? picked,
    Set<VectorPick> picks = const {}}) {
  var shapes = e.shapes;
  if (shapes == null) return null;
  var space = VectorSpace(e);
  bool near(Offset v) => (space.toCanvas(v) - canvasPoint).distance <= reach;
  // The one point picked's handles first, so a handle lying on its own
  // point can still be pulled out of it.
  if (picked != null) {
    var node = _nodeAt(e, picked);
    if (node != null) {
      if (node.hasOut && near(node.outHandle)) {
        return VectorHit(picked, VectorPart.outHandle);
      }
      if (node.hasIn && near(node.inHandle)) {
        return VectorHit(picked, VectorPart.inHandle);
      }
    }
  }
  // Then any point picked, whichever shape it is on.
  for (var pick in picks) {
    var node = _nodeAt(e, pick);
    if (node != null && near(node.point)) {
      return VectorHit(pick, VectorPart.point);
    }
  }
  if (shape < 0 || shape >= shapes.length) return null;
  var paths = shapes[shape].paths;
  for (var p = 0; p < paths.length; p++) {
    for (var n = 0; n < paths[p].nodes.length; n++) {
      if (near(paths[p].nodes[n].point)) {
        return VectorHit(VectorPick(shape, p, n), VectorPart.point);
      }
    }
  }
  return null;
}

/// shapeAt is the topmost shape of [e] under [canvasPoint] -- inside its
/// fill, or within [reach] of its stroke -- or -1.
int shapeAt(VectorElement e, Offset canvasPoint, double reach) {
  var shapes = e.shapes;
  if (shapes == null) return -1;
  var space = VectorSpace(e);
  var at = space.toDrawing(canvasPoint);
  var slack = reach * space.unitsPer;
  for (var i = shapes.length - 1; i >= 0; i--) {
    var shape = shapes[i];
    var path = vectorShapePath(shape);
    if (shape.fill != null && path.contains(at)) return i;
    if (_nearOutline(path, at, slack + shape.strokeWidth / 2)) return i;
  }
  return -1;
}

bool _nearOutline(Path path, Offset at, double within) {
  if (!path.getBounds().inflate(within).contains(at)) return false;
  for (var m in path.computeMetrics()) {
    var step = math.max(1.0, within / 2);
    for (var d = 0.0; d <= m.length; d += step) {
      var t = m.getTangentForOffset(d);
      if (t != null && (t.position - at).distance <= within) return true;
    }
  }
  return false;
}

VectorNode? _nodeAt(VectorElement e, VectorPick pick) {
  var shapes = e.shapes;
  if (shapes == null || pick.shape >= shapes.length) return null;
  var paths = shapes[pick.shape].paths;
  if (pick.path >= paths.length) return null;
  var nodes = paths[pick.path].nodes;
  return pick.node < nodes.length ? nodes[pick.node] : null;
}

VectorNode? vectorNodeAt(VectorElement e, VectorPick pick) => _nodeAt(e, pick);

/// withVectorNode is [e] with the point at [pick] replaced.
VectorElement withVectorNode(VectorElement e, VectorPick pick, VectorNode n) {
  var shape = e.shapes![pick.shape];
  var paths = [...shape.paths];
  var nodes = [...paths[pick.path].nodes];
  nodes[pick.node] = n;
  paths[pick.path] = paths[pick.path].copyWith(nodes: nodes);
  return e.withShape(pick.shape, shape.copyWith(paths: paths));
}

/// movedVector is [e] with the part [part] of the point at [pick] put at
/// [canvasPoint]. A smooth point's other handle swings round with the one
/// moved, keeping its own length; [breakHandles] moves the one alone, which
/// is how a smooth point is made a corner by hand.
VectorElement movedVector(
    VectorElement e, VectorPick pick, VectorPart part, Offset canvasPoint,
    {bool breakHandles = false,
    VectorHandleDrag drag = VectorHandleDrag.any,
    bool snap = false}) {
  var node = _nodeAt(e, pick);
  if (node == null) return e;
  var to = VectorSpace(e).toDrawing(canvasPoint);
  switch (part) {
    case VectorPart.point:
      return withPointsMoved(e, {pick}, to - node.point);
    case VectorPart.inHandle || VectorPart.outHandle:
      var out = part == VectorPart.outHandle;
      var was = out ? Offset(node.outX, node.outY) : Offset(node.inX, node.inY);
      var d = to - node.point;
      // Snapped, it turns in steps of fifteen degrees.
      if (snap && d.distance > 0) {
        const step = math.pi / 12;
        var angle = (math.atan2(d.dy, d.dx) / step).round() * step;
        d = Offset(math.cos(angle), math.sin(angle)) * d.distance;
      }
      // Turned only, it keeps its length; stretched only, its line.
      if (was.distance > 0) {
        var along = was / was.distance;
        switch (drag) {
          case VectorHandleDrag.any:
            break;
          case VectorHandleDrag.turn:
            if (d.distance > 0) d = d / d.distance * was.distance;
          case VectorHandleDrag.stretch:
            d = along * math.max(0.0, d.dx * along.dx + d.dy * along.dy);
        }
      }
      var next = out
          ? node.copyWith(outX: d.dx, outY: d.dy)
          : node.copyWith(inX: d.dx, inY: d.dy);
      if (node.smooth && !breakHandles) {
        var other =
            out ? Offset(node.inX, node.inY) : Offset(node.outX, node.outY);
        var dir = d.distance == 0 ? Offset.zero : d / d.distance;
        // Mirrored, the other is this one turned round; aligned, it swings
        // round to stay in line, keeping its own length.
        var opposite = node.mirrored ? -d : -dir * other.distance;
        next = out
            ? next.copyWith(inX: opposite.dx, inY: opposite.dy)
            : next.copyWith(outX: opposite.dx, outY: opposite.dy);
      }
      if (breakHandles) next = next.copyWith(smooth: false, mirrored: false);
      return withVectorNode(e, pick, next);
  }
}

/// VectorHandleDrag is what dragging a handle may change.
enum VectorHandleDrag {
  any("Any way"),
  turn("Turn only"),
  stretch("Stretch only");

  final String label;
  const VectorHandleDrag(this.label);
}

/// withHandles gives the points in [picks] handles that move as [mode]
/// says. Free leaves them where they are, free of each other. Aligned and
/// mirrored line them up -- a point with none is given a pair first, along
/// the line between its neighbours -- and mirrored evens their lengths.
VectorElement withHandles(
    VectorElement e, Set<VectorPick> picks, VectorHandles mode) {
  var next = e;
  for (var pick in picks) {
    var node = _nodeAt(next, pick);
    if (node == null) continue;
    if (mode == VectorHandles.free) {
      next = withVectorNode(
          next, pick, node.copyWith(smooth: false, mirrored: false));
      continue;
    }
    if (!node.hasIn && !node.hasOut) {
      next = withSmoothToggled(next, pick);
      node = _nodeAt(next, pick)!;
    }
    var outH = Offset(node.outX, node.outY), inH = Offset(node.inX, node.inY);
    var dir = outH.distance > 0
        ? outH / outH.distance
        : inH.distance > 0
            ? -inH / inH.distance
            : const Offset(1, 0);
    var (lin, lout) = mode == VectorHandles.mirrored
        ? (
            (outH.distance + inH.distance) / 2,
            (outH.distance + inH.distance) / 2
          )
        : (inH.distance, outH.distance);
    next = withVectorNode(
        next,
        pick,
        node.copyWith(
            outX: dir.dx * lout,
            outY: dir.dy * lout,
            inX: -dir.dx * lin,
            inY: -dir.dy * lin,
            smooth: true,
            mirrored: mode == VectorHandles.mirrored));
  }
  return next;
}

/// withEvenHandles makes each picked point's two handles the same length --
/// the two lengths' middle -- each keeping its line.
VectorElement withEvenHandles(VectorElement e, Set<VectorPick> picks) {
  var next = e;
  for (var pick in picks) {
    var node = _nodeAt(next, pick);
    if (node == null || !node.hasIn || !node.hasOut) continue;
    var outH = Offset(node.outX, node.outY), inH = Offset(node.inX, node.inY);
    var l = (outH.distance + inH.distance) / 2;
    var o = outH / outH.distance * l, i = inH / inH.distance * l;
    next = withVectorNode(next, pick,
        node.copyWith(outX: o.dx, outY: o.dy, inX: i.dx, inY: i.dy));
  }
  return next;
}

/// withoutHandles takes the picked points' handles off: corners again.
VectorElement withoutHandles(VectorElement e, Set<VectorPick> picks) {
  var next = e;
  for (var pick in picks) {
    var node = _nodeAt(next, pick);
    if (node == null) continue;
    next = withVectorNode(
        next,
        pick,
        node.copyWith(
            inX: 0, inY: 0, outX: 0, outY: 0, smooth: false, mirrored: false));
  }
  return next;
}

/// VectorAlign is how the align tool lines points up.
enum VectorAlign {
  left("Align left"),
  centreX("Centre across"),
  right("Align right"),
  top("Align top"),
  centreY("Centre down"),
  bottom("Align bottom"),
  spreadX("Even across"),
  spreadY("Even down");

  final String label;
  const VectorAlign(this.label);
}

/// withAligned lines the points in [picks] up as [how] says, in the
/// drawing's own units -- to the edge or middle of the box round them, or
/// spread evenly between the two outermost. A joint is one point: every end
/// lying there goes with it, and counts once.
VectorElement withAligned(
    VectorElement e, Set<VectorPick> picks, VectorAlign how) {
  var all = joinedTo(e, picks);
  var places = <Offset>{
    for (var p in all)
      if (_nodeAt(e, p) case var n?) n.point,
  }.toList();
  if (places.length < 2) return e;
  var box = Rect.fromPoints(places.first, places.first);
  for (var p in places) {
    box = box.expandToInclude(Rect.fromPoints(p, p));
  }
  Map<Offset, Offset> spread(bool across) {
    var order = [...places]
      ..sort((a, b) => across ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
    var from = across ? box.left : box.top;
    var step = ((across ? box.right : box.bottom) - from) / (order.length - 1);
    return {
      for (var (k, p) in order.indexed)
        p: across
            ? Offset(from + k * step, p.dy)
            : Offset(p.dx, from + k * step),
    };
  }

  var to = switch (how) {
    VectorAlign.left => {for (var p in places) p: Offset(box.left, p.dy)},
    VectorAlign.centreX => {
        for (var p in places) p: Offset(box.center.dx, p.dy)
      },
    VectorAlign.right => {for (var p in places) p: Offset(box.right, p.dy)},
    VectorAlign.top => {for (var p in places) p: Offset(p.dx, box.top)},
    VectorAlign.centreY => {
        for (var p in places) p: Offset(p.dx, box.center.dy)
      },
    VectorAlign.bottom => {for (var p in places) p: Offset(p.dx, box.bottom)},
    VectorAlign.spreadX => spread(true),
    VectorAlign.spreadY => spread(false),
  };
  var next = e;
  for (var pick in all) {
    var node = _nodeAt(e, pick);
    if (node == null) continue;
    next = withVectorNode(next, pick, node.moved(to[node.point]!));
  }
  return next;
}

/// joinedTo is [picks] and every point lying exactly on one of them: the
/// other ends of a joint -- where a branch leaves a line, or two lines were
/// drawn to meet -- which move as one point.
Set<VectorPick> joinedTo(VectorElement e, Set<VectorPick> picks) {
  var at = <Offset>{
    for (var p in picks)
      if (_nodeAt(e, p) case var n?) n.point,
  };
  if (at.isEmpty) return picks;
  return {
    ...picks,
    for (var (s, shape) in (e.shapes ?? const <VectorShape>[]).indexed)
      for (var (p, run) in shape.paths.indexed)
        for (var (n, node) in run.nodes.indexed)
          if (at.any((a) => (a - node.point).distance < 1e-6))
            VectorPick(s, p, n),
  };
}

/// nearestSegment is the segment of shape [shape] nearest [canvasPoint], as
/// the run it is on, the point it starts from, and how far along it is --
/// or null where none is within [reach].
(int path, int from, double t)? nearestSegment(
    VectorElement e, int shape, Offset canvasPoint, double reach) {
  var shapes = e.shapes;
  if (shapes == null || shape < 0 || shape >= shapes.length) return null;
  var space = VectorSpace(e);
  (int, int, double)? best;
  var bestDistance = reach;
  var paths = shapes[shape].paths;
  for (var p = 0; p < paths.length; p++) {
    var nodes = paths[p].nodes;
    var count = paths[p].closed ? nodes.length : nodes.length - 1;
    for (var i = 0; i < count; i++) {
      var a = nodes[i], b = nodes[(i + 1) % nodes.length];
      for (var k = 0; k <= 40; k++) {
        var t = k / 40;
        var at = space.toCanvas(_bezier(a, b, t));
        var d = (at - canvasPoint).distance;
        if (d < bestDistance) {
          bestDistance = d;
          best = (p, i, t);
        }
      }
    }
  }
  return best;
}

Offset _bezier(VectorNode a, VectorNode b, double t) {
  var p0 = a.point, p1 = a.outHandle, p2 = b.inHandle, p3 = b.point;
  // A straight segment is straight in t too: as far along as t says.
  if (!a.hasOut && !b.hasIn) return p0 + (p3 - p0) * t;
  var u = 1 - t;
  return p0 * (u * u * u) +
      p1 * (3 * u * u * t) +
      p2 * (3 * u * t * t) +
      p3 * (t * t * t);
}

/// _split is the segment from [a] to [b] split [t] of the way along, so
/// its shape does not change: [a] with its out handle shortened, the new
/// point between, and [b] with its in handle shortened. The new point is as
/// thick as the line was there.
(VectorNode, VectorNode, VectorNode) _split(
    VectorNode a, VectorNode b, double t) {
  // de Casteljau: the curve split in two at t, through the same points.
  var p0 = a.point, p1 = a.outHandle, p2 = b.inHandle, p3 = b.point;
  Offset lerp(Offset x, Offset y) => x + (y - x) * t;
  var q0 = lerp(p0, p1), q1 = lerp(p1, p2), q2 = lerp(p2, p3);
  var r0 = lerp(q0, q1), r1 = lerp(q1, q2);
  var m = lerp(r0, r1);
  var width = a.width + (b.width - a.width) * t * t * (3 - 2 * t);
  if (!a.hasOut && !b.hasIn) {
    var on = p0 + (p3 - p0) * t;
    return (a, VectorNode(on.dx, on.dy, width: width), b);
  }
  return (
    a.copyWith(outX: q0.dx - p0.dx, outY: q0.dy - p0.dy),
    VectorNode(m.dx, m.dy,
        inX: r0.dx - m.dx,
        inY: r0.dy - m.dy,
        outX: r1.dx - m.dx,
        outY: r1.dy - m.dy,
        smooth: true,
        width: width),
    b.copyWith(inX: q2.dx - p3.dx, inY: q2.dy - p3.dy),
  );
}

/// withPointAdded is [e] with a point put into the segment of [path] that
/// starts at point [from], [t] of the way along -- the curve split there so
/// its shape does not change. The new point's pick is returned with it.
(VectorElement, VectorPick) withPointAdded(
    VectorElement e, int shape, int path, int from, double t) {
  var s = e.shapes![shape];
  var run = s.paths[path];
  var nodes = [...run.nodes];
  var bIndex = (from + 1) % nodes.length;
  var (a, added, b) = _split(nodes[from], nodes[bIndex], t);
  nodes[from] = a;
  nodes[bIndex] = b;
  nodes.insert(from + 1, added);
  var paths = [...s.paths];
  paths[path] = run.copyWith(nodes: nodes);
  return (
    e.withShape(shape, s.copyWith(paths: paths)),
    VectorPick(shape, path, from + 1)
  );
}

/// withCornered rounds -- or, with [round] off, cuts -- the corner at
/// [pick], [reach] back along each side of it (in the drawing's units, and
/// never past halfway along either): the point is replaced by two, one on
/// each side, joined by a quarter-circle-like curve or a straight cut. Null
/// where the point has no corner to round: an end of a line, or a joint,
/// whose other lines would be left behind.
(VectorElement, Set<VectorPick>)? withCornered(
    VectorElement e, VectorPick pick, double reach,
    {bool round = true}) {
  var shapes = e.shapes;
  if (shapes == null || pick.shape >= shapes.length) return null;
  var s = shapes[pick.shape];
  if (pick.path >= s.paths.length) return null;
  var run = s.paths[pick.path];
  var nodes = [...run.nodes];
  var i = pick.node, n = nodes.length;
  if (i >= n || n < 3 && !run.closed || n < 2) return null;
  if (!run.closed && (i == 0 || i == n - 1)) return null;
  if (joinedTo(e, {pick}).length > 1) return null;
  var prev = (i - 1 + n) % n, next = (i + 1) % n;
  double length(VectorNode a, VectorNode b) {
    var seg = Path()..moveTo(a.x, a.y);
    if (!a.hasOut && !b.hasIn) {
      seg.lineTo(b.x, b.y);
    } else {
      seg.cubicTo(a.outHandle.dx, a.outHandle.dy, b.inHandle.dx, b.inHandle.dy,
          b.x, b.y);
    }
    var m = seg.computeMetrics().toList();
    return m.isEmpty ? 0 : m.first.length;
  }

  var p = nodes[i];
  var l1 = length(nodes[prev], p), l2 = length(p, nodes[next]);
  if (l1 <= 0 || l2 <= 0) return null;
  var d = math.min(reach, math.min(l1, l2) * 0.49);
  if (d <= 0) return null;
  var (a2, m1, _) = _split(nodes[prev], p, 1 - d / l1);
  var (_, m2, b2) = _split(p, nodes[next], d / l2);
  // Which way the line runs at each new point, towards the corner and away.
  Offset unit(Offset v) => v.distance == 0 ? Offset.zero : v / v.distance;
  var u1 =
      m1.hasOut ? unit(Offset(m1.outX, m1.outY)) : unit(p.point - m1.point);
  var u2 =
      m2.hasOut ? unit(Offset(m2.outX, m2.outY)) : unit(m2.point - p.point);
  var h = 0.0;
  if (round) {
    var turn = math.acos((u1.dx * u2.dx + u1.dy * u2.dy).clamp(-1.0, 1.0));
    // The handle length that makes the curve a circle's arc, as near as a
    // cubic can, for a corner turning [turn].
    if (turn > 1e-3 && turn < math.pi - 1e-3) {
      h = 4 / 3 * math.tan(turn / 4) * d / math.tan(turn / 2);
    }
  }
  var c1 = m1.copyWith(
      outX: u1.dx * h, outY: u1.dy * h, smooth: false, mirrored: false);
  var c2 = m2.copyWith(
      inX: -u2.dx * h, inY: -u2.dy * h, smooth: false, mirrored: false);
  nodes[prev] = a2;
  nodes[next] = b2;
  nodes.replaceRange(i, i + 1, [c1, c2]);
  var paths = [...s.paths];
  paths[pick.path] = run.copyWith(nodes: nodes);
  return (
    e.withShape(pick.shape, s.copyWith(paths: paths)),
    {
      VectorPick(pick.shape, pick.path, i),
      VectorPick(pick.shape, pick.path, i + 1)
    }
  );
}

/// withoutPoint is [e] with the point at [pick] taken out. A run left with
/// fewer than two points goes, and a shape left with no runs goes with it.
VectorElement withoutPoint(VectorElement e, VectorPick pick) =>
    withoutPoints(e, {pick});

/// withSmoothToggled makes the point at [pick] a corner, or smooth: a corner
/// loses its handles, and a point made smooth is given a pair along the line
/// between its neighbours, a third of the way to each.
VectorElement withSmoothToggled(VectorElement e, VectorPick pick) {
  var node = _nodeAt(e, pick);
  if (node == null) return e;
  if (node.smooth || node.hasIn || node.hasOut) {
    return withVectorNode(
        e,
        pick,
        node.copyWith(
            inX: 0, inY: 0, outX: 0, outY: 0, smooth: false, mirrored: false));
  }
  var run = e.shapes![pick.shape].paths[pick.path];
  var nodes = run.nodes;
  var i = pick.node;
  var hasPrev = run.closed || i > 0,
      hasNext = run.closed || i < nodes.length - 1;
  var prev =
      hasPrev ? nodes[(i - 1 + nodes.length) % nodes.length].point : null;
  var next = hasNext ? nodes[(i + 1) % nodes.length].point : null;
  var along = prev != null && next != null
      ? next - prev
      : next != null
          ? (next - node.point) * 2
          : prev != null
              ? (node.point - prev) * 2
              : const Offset(10, 0);
  var dir = along.distance == 0 ? const Offset(1, 0) : along / along.distance;
  var reachIn = prev == null ? 0.0 : (node.point - prev).distance / 3;
  var reachOut = next == null ? 0.0 : (next - node.point).distance / 3;
  return withVectorNode(
      e,
      pick,
      node.copyWith(
          inX: -dir.dx * reachIn,
          inY: -dir.dy * reachIn,
          outX: dir.dx * reachOut,
          outY: dir.dy * reachOut,
          smooth: true));
}

/// withPointsMoved is [e] with every point in [picks] moved by [by], in the
/// drawing's units -- their handles going with them.
VectorElement withPointsMoved(
    VectorElement e, Set<VectorPick> picks, Offset by) {
  var shapes = [...?e.shapes];
  for (var pick in joinedTo(e, picks)) {
    if (pick.shape >= shapes.length) continue;
    var s = shapes[pick.shape];
    if (pick.path >= s.paths.length) continue;
    var paths = [...s.paths];
    var nodes = [...paths[pick.path].nodes];
    if (pick.node >= nodes.length) continue;
    var n = nodes[pick.node];
    nodes[pick.node] = n.moved(n.point + by);
    paths[pick.path] = paths[pick.path].copyWith(nodes: nodes);
    shapes[pick.shape] = s.copyWith(paths: paths);
  }
  // A shape moved whole takes its tints and rub-outs with it; one moved in
  // part leaves them where they were painted.
  var moved = joinedTo(e, picks);
  for (var (i, s) in (e.shapes ?? const <VectorShape>[]).indexed) {
    if (s.tints.isEmpty && s.erasures.isEmpty) continue;
    var whole = [
      for (var (p, run) in s.paths.indexed)
        for (var n = 0; n < run.nodes.length; n++) VectorPick(i, p, n),
    ].every(moved.contains);
    if (whole) shapes[i] = _strokesMoved(shapes[i], by);
  }
  return e.copyWith(shapes: shapes);
}

/// _strokesMoved is [s] with its tints and rub-outs moved [by].
VectorShape _strokesMoved(VectorShape s, Offset by) => s.copyWith(
      tints: [for (var t in s.tints) t.mapped((p) => p + by)],
      erasures: [for (var t in s.erasures) t.mapped((p) => p + by)],
    );

/// picksIn is every point of [e] whose place on the canvas is inside
/// [canvasRect] -- a box dragged across the drawing.
Set<VectorPick> picksIn(VectorElement e, Rect canvasRect) {
  var space = VectorSpace(e);
  return {
    for (var (s, shape) in (e.shapes ?? const <VectorShape>[]).indexed)
      for (var (p, path) in shape.paths.indexed)
        for (var (n, node) in path.nodes.indexed)
          if (canvasRect.contains(space.toCanvas(node.point)))
            VectorPick(s, p, n),
  };
}

/// picksBox is the box round the points in [picks], on the canvas, or null
/// for fewer than two -- the box a press in the middle of drags them all by.
Rect? picksBox(VectorElement e, Set<VectorPick> picks) {
  if (picks.length < 2) return null;
  var space = VectorSpace(e);
  Rect? box;
  for (var pick in picks) {
    var node = _nodeAt(e, pick);
    if (node == null) continue;
    var at = space.toCanvas(node.point);
    box = box == null
        ? Rect.fromPoints(at, at)
        : box.expandToInclude(Rect.fromPoints(at, at));
  }
  return box;
}

/// withoutPoints is [e] with every point in [picks] taken out, all at once.
///
/// A point taken out of the middle of a line joins its neighbours up, as
/// one would expect of a point. A joint -- a point that several lines meet
/// at -- breaks them there instead: there is no one neighbour to join to,
/// and joining the wrong two would draw a line nobody drew. Every line
/// meeting at it loses its end there, wherever it was picked from.
///
/// A run left with fewer than two points goes, and a shape left with no
/// runs goes with it. Picks that are not there any more are passed over.
VectorElement withoutPoints(VectorElement e, Set<VectorPick> picks) {
  var all = e.shapes ?? const <VectorShape>[];
  var joints = <Offset>{};
  var count = <Offset, int>{};
  for (var shape in all) {
    for (var run in shape.paths) {
      for (var n in run.nodes) {
        count[n.point] = (count[n.point] ?? 0) + 1;
      }
    }
  }
  for (var pick in picks) {
    if (_nodeAt(e, pick) case var n? when (count[n.point] ?? 0) > 1) {
      joints.add(n.point);
    }
  }
  // Every end of a joint taken out goes, not only the one picked.
  var gone = joinedTo(e, picks);

  var shapes = <VectorShape>[];
  var droppedBase = false;
  for (var (si, s) in all.indexed) {
    var paths = <VectorPath>[];
    var changed = false;
    for (var (pi, run) in s.paths.indexed) {
      var nodes = run.nodes;
      bool out(int ni) => gone.contains(VectorPick(si, pi, ni));
      if (![for (var i = 0; i < nodes.length; i++) i].any(out)) {
        paths.add(run);
        continue;
      }
      changed = true;
      bool breaks(int ni) => out(ni) && joints.contains(nodes[ni].point);
      var order = [for (var i = 0; i < nodes.length; i++) i];
      var closed = run.closed;
      // A closed run broken at a joint opens there: read from just after
      // the break, round to it.
      if (closed) {
        var at = order.indexWhere(breaks);
        if (at >= 0) {
          order = [...order.sublist(at + 1), ...order.sublist(0, at + 1)];
          closed = false;
        }
      }
      var piece = <VectorNode>[];
      void finish() {
        if (piece.length >= 2) paths.add(VectorPath(piece, closed: closed));
        piece = [];
      }

      for (var ni in order) {
        if (breaks(ni)) {
          finish();
        } else if (!out(ni)) {
          piece.add(nodes[ni]);
        }
      }
      finish();
    }
    if (!changed) {
      // A shape combining into one that went combines into nothing: it is
      // a shape of its own now.
      shapes.add(droppedBase && s.combine != null
          ? s.copyWith(clearCombine: true)
          : s);
      droppedBase = false;
    } else if (paths.isNotEmpty) {
      shapes.add(s.copyWith(
          paths: paths, clearCombine: droppedBase && s.combine != null));
      droppedBase = false;
    } else {
      droppedBase = s.combine == null || droppedBase;
    }
  }
  return e.copyWith(shapes: shapes);
}

/// connectedPicks is every point connected to the part of shape [shape]
/// at [at] (in the drawing's units): the run whose inside it is in -- or,
/// off every run's inside, the shape's first -- and every run joined to that
/// one at a joint, and every run joined to those, of any shape.
Set<VectorPick> connectedPicks(VectorElement e, int shape, Offset at) {
  var shapes = e.shapes ?? const <VectorShape>[];
  if (shape < 0 || shape >= shapes.length) return const {};
  var runs = shapes[shape].paths;
  if (runs.isEmpty) return const {};
  var start = 0;
  for (var (p, run) in runs.indexed) {
    if (run.closed &&
        (VectorShape(paths: [run]).path..fillType = PathFillType.nonZero)
            .contains(at)) {
      start = p;
    }
  }
  Set<VectorPick> whole(int s, int p) => {
        for (var n = 0; n < shapes[s].paths[p].nodes.length; n++)
          VectorPick(s, p, n),
      };
  var picks = whole(shape, start);
  var seen = {(shape, start)};
  while (true) {
    var more = <VectorPick>{};
    for (var j in joinedTo(e, picks).difference(picks)) {
      if (seen.add((j.shape, j.path))) more.addAll(whole(j.shape, j.path));
    }
    if (more.isEmpty) return picks;
    picks = {...picks, ...more};
  }
}

/// copiedShapes is what copying the points in [picks] copies: of each run,
/// the stretches of points picked one after another -- the whole run where
/// every point of it is picked, closed if it was -- each in a copy of the
/// shape it came from. A point picked on its own has no line to copy.
List<VectorShape> copiedShapes(VectorElement e, Set<VectorPick> picks) {
  var out = <VectorShape>[];
  for (var (si, s) in (e.shapes ?? const <VectorShape>[]).indexed) {
    var runs = <VectorPath>[];
    for (var (pi, run) in s.paths.indexed) {
      var n = run.nodes.length;
      bool picked(int i) => picks.contains(VectorPick(si, pi, i));
      var count = [for (var i = 0; i < n; i++) i].where(picked).length;
      if (count == n) {
        runs.add(run);
        continue;
      }
      if (count < 2) continue;
      // Read from just after a point not picked, so a stretch running round
      // the end of a closed run comes out in one piece.
      var start = run.closed
          ? [for (var i = 0; i < n; i++) i].firstWhere((i) => !picked(i)) + 1
          : 0;
      var piece = <VectorNode>[];
      void finish() {
        if (piece.length >= 2) runs.add(VectorPath(piece));
        piece = [];
      }

      for (var k = 0; k < n; k++) {
        var i = (start + k) % n;
        if (picked(i)) {
          piece.add(run.nodes[i]);
        } else {
          finish();
        }
      }
      finish();
    }
    if (runs.isNotEmpty) {
      out.add(s.copyWith(paths: runs, clearCombine: true));
    }
  }
  return out;
}

/// withPasted is [e] with [shapes] added on top, moved [by] in the
/// drawing's units, and every point of them -- to be picked.
(VectorElement, Set<VectorPick>) withPasted(
    VectorElement e, List<VectorShape> shapes, Offset by) {
  var before = e.shapes ?? const <VectorShape>[];
  var added = [
    for (var s in shapes)
      _strokesMoved(s, by).copyWith(paths: [
        for (var run in s.paths)
          run.copyWith(nodes: [for (var n in run.nodes) n.moved(n.point + by)]),
      ]),
  ];
  var next = e.copyWith(shapes: [...before, ...added]);
  return (
    next,
    {
      for (var (k, s) in added.indexed)
        for (var (p, run) in s.paths.indexed)
          for (var n = 0; n < run.nodes.length; n++)
            VectorPick(before.length + k, p, n),
    }
  );
}

/// allPicks is every point of [e].
Set<VectorPick> allPicks(VectorElement e) => {
      for (var (s, shape) in (e.shapes ?? const <VectorShape>[]).indexed)
        for (var (p, run) in shape.paths.indexed)
          for (var n = 0; n < run.nodes.length; n++) VectorPick(s, p, n),
    };

/// pencilShape is a stroke of the pencil as a shape: the pen's [samples],
/// drawn with [brush] in [colour], [width] wide at full pressure (in the
/// drawing's units). Null with no samples.
///
/// The hand's wobble is smoothed out as the brush says; the width at each
/// point comes from the pen's pressure -- or, where the pen gives none, from
/// how fast it moved, slow being heavy -- and its tilt, and from which way
/// the stroke runs for a broad nib; the ends taper. What is left is thinned
/// to the points the line needs and given smooth handles through them, so a
/// stroke of hundreds of readings is a few dozen points to edit.
VectorShape? pencilShape(VectorElement e, List<PenSample> samples,
    VectorBrush brush, Color colour, double width,
    {Color? fillColour}) {
  if (samples.isEmpty) return null;
  var space = VectorSpace(e);
  var pts = [for (var s in samples) space.toDrawing(s.at)];

  // Steadied: each point eased towards where the pen is, the last left
  // where the pen let go so the line reaches it.
  var follow = 1 - brush.smoothing.clamp(0.0, 1.0) * 0.85;
  for (var i = 1; i < pts.length - 1; i++) {
    pts[i] = pts[i - 1] + (pts[i] - pts[i - 1]) * follow;
  }

  // Pressure: the pen's own, or made up from its speed.
  var weight = <double>[];
  var eased = 0.6;
  for (var (i, s) in samples.indexed) {
    double p;
    if (s.pressure case var given?) {
      p = given.clamp(0.0, 1.0);
    } else if (i == 0) {
      p = eased;
    } else {
      var gap = (s.time - samples[i - 1].time).inMicroseconds / 1000;
      var moved = (s.at - samples[i - 1].at).distance;
      var speed = gap > 0 ? moved / gap : 0.0;
      // Two pixels a millisecond is a quick flick: lightest.
      var target = (1 - speed / 2).clamp(0.15, 1.0);
      eased += (target - eased) * 0.3;
      p = eased;
    }
    weight.add(p);
  }

  var tiltMax = math.pi / 2;
  var nibAngle = brush.nibAngle * math.pi / 180;
  double widthAt(int i) {
    var f = brush.pressure
        ? brush.thinnest +
            (1 - brush.thinnest) * math.pow(weight[i], brush.curve).toDouble()
        : 1.0;
    if (samples[i].tilt case var t?) {
      f *= 1 + brush.tilt * (t / tiltMax).clamp(0.0, 1.0);
    }
    if (brush.nib > 0 && pts.length > 1) {
      var a = pts[math.max(0, i - 1)], b = pts[math.min(pts.length - 1, i + 1)];
      var d = b - a;
      if (d.distance > 0) {
        var across = (math.sin(math.atan2(d.dy, d.dx) - nibAngle)).abs();
        f *= math.max(0.12, 1 - brush.nib + brush.nib * across);
      }
    }
    return f;
  }

  var widths = [for (var i = 0; i < pts.length; i++) widthAt(i)];

  // Only the points the line needs: where it bends, and where it swells or
  // thins, to within a small share of its width.
  var keep = _simplified(pts, [for (var w in widths) w * width / 2],
      math.max(width * 0.04, 0.25 * space.unitsPer));

  // Tapered in and out, by distance along the stroke.
  var along = <double>[0];
  for (var i = 1; i < pts.length; i++) {
    along.add(along.last + (pts[i] - pts[i - 1]).distance);
  }
  var total = along.last;
  double taper(int i) {
    var f = 1.0;
    if (brush.taperIn > 0 && total > 0) {
      var t =
          (along[i] / (total * brush.taperIn.clamp(0.0, 0.5))).clamp(0.0, 1.0);
      f *= math.max(0.05, math.sin(t * math.pi / 2));
    }
    if (brush.taperOut > 0 && total > 0) {
      var t = ((total - along[i]) / (total * brush.taperOut.clamp(0.0, 0.5)))
          .clamp(0.0, 1.0);
      f *= math.max(0.05, math.sin(t * math.pi / 2));
    }
    return f;
  }

  var kept = [for (var i in keep) pts[i]];
  var nodes = <VectorNode>[];
  for (var (k, i) in keep.indexed) {
    // Through the points kept, smoothly: each handle along the line from
    // the point before to the point after, a third as long as its own side
    // -- the points thinning leaves are spaced unevenly, and one length for
    // both sides flattens the long side and kinks the short.
    var inside = k > 0 && k < kept.length - 1;
    var dir = inside ? kept[k + 1] - kept[k - 1] : Offset.zero;
    dir = dir.distance == 0 ? Offset.zero : dir / dir.distance;
    var outLen = inside ? (kept[k + 1] - kept[k]).distance / 3 : 0.0;
    var inLen = inside ? (kept[k] - kept[k - 1]).distance / 3 : 0.0;
    nodes.add(VectorNode(pts[i].dx, pts[i].dy,
        outX: dir.dx * outLen,
        outY: dir.dy * outLen,
        inX: -dir.dx * inLen,
        inY: -dir.dy * inLen,
        smooth: inside,
        width: double.parse((widths[i] * taper(i)).toStringAsFixed(3))));
  }
  var opacity = brush.opacity.clamp(0.0, 1.0);
  // A fill brush closes the stroke round on itself and fills it.
  var filled = brush.fill && nodes.length > 2;
  var fill = fillColour ?? colour;
  return VectorShape(
    paths: [VectorPath(nodes, closed: filled)],
    fill: filled ? fill.withValues(alpha: fill.a * opacity) : null,
    stroke: brush.line || !filled
        ? colour.withValues(alpha: colour.a * opacity)
        : null,
    strokeWidth: width,
    cap: brush.cap,
    join: StrokeJoin.round,
  );
}

/// mirroredStrokes is a pencil stroke and its mirror images: [samples] as
/// drawn, then reflected across the drawing's upright middle line where
/// [across], across its level middle line where [down], and across both
/// where both -- one, two or four strokes. Each with the brush it is drawn
/// with: a broad nib's angle is mirrored with the stroke, so a calligraphy
/// stroke's mirror is as thick and thin as it.
List<(List<PenSample>, VectorBrush)> mirroredStrokes(
    VectorElement e, List<PenSample> samples, VectorBrush brush,
    {bool across = false, bool down = false}) {
  var space = VectorSpace(e);
  var c = e.viewBox.center;
  List<PenSample> reflect(bool x, bool y) => [
        for (var s in samples)
          (() {
            var d = space.toDrawing(s.at);
            var m =
                Offset(x ? 2 * c.dx - d.dx : d.dx, y ? 2 * c.dy - d.dy : d.dy);
            return PenSample(space.toCanvas(m),
                pressure: s.pressure, tilt: s.tilt, time: s.time);
          })(),
      ];
  VectorBrush nib(bool x, bool y) {
    var a = brush.nibAngle;
    if (x) a = 180 - a;
    if (y) a = -a;
    return brush.copyWith(nibAngle: a);
  }

  return [
    (samples, brush),
    if (across) (reflect(true, false), nib(true, false)),
    if (down) (reflect(false, true), nib(false, true)),
    if (across && down) (reflect(true, true), nib(true, true)),
  ];
}

/// _simplified is which of [pts] a line through them needs, to within
/// [tolerance] -- Douglas and Peucker's thinning, the first and last always
/// kept. A point is needed for its half-width in [halves] as well as for
/// where it is: a stroke that swells on a straight stretch keeps the points
/// it swells at.
List<int> _simplified(List<Offset> pts, List<double> halves, double tolerance) {
  if (pts.length < 3) return [for (var i = 0; i < pts.length; i++) i];
  var keep = List<bool>.filled(pts.length, false);
  keep[0] = keep[pts.length - 1] = true;
  var stack = [(0, pts.length - 1)];
  while (stack.isNotEmpty) {
    var (a, b) = stack.removeLast();
    var far = -1;
    var most = tolerance;
    var line = pts[b] - pts[a];
    var len = line.distance;
    for (var i = a + 1; i < b; i++) {
      var v = pts[i] - pts[a];
      var d =
          len == 0 ? v.distance : (v.dx * line.dy - v.dy * line.dx).abs() / len;
      var t = (i - a) / (b - a);
      var w = (halves[i] - (halves[a] + (halves[b] - halves[a]) * t)).abs();
      if (w > d) d = w;
      if (d > most) {
        most = d;
        far = i;
      }
    }
    if (far >= 0) {
      keep[far] = true;
      stack.add((a, far));
      stack.add((far, b));
    }
  }
  return [
    for (var i = 0; i < pts.length; i++)
      if (keep[i]) i
  ];
}

/// withoutShapesAt is [e] with every shape under [canvasPoint] taken out --
/// the pen's eraser.
VectorElement withoutShapesAt(
    VectorElement e, Offset canvasPoint, double reach) {
  var next = e;
  while (true) {
    var hit = shapeAt(next, canvasPoint, reach);
    if (hit < 0) return next;
    var shapes = [...next.shapes!]..removeAt(hit);
    // One combined into it is a shape of its own now.
    if (hit < shapes.length && shapes[hit].combine != null) {
      shapes[hit] = shapes[hit].copyWith(clearCombine: true);
    }
    next = next.copyWith(shapes: shapes);
  }
}

/// groupOf is the shape the run of combining shapes that shape [index] is
/// in starts from: itself, for a shape of its own.
int groupOf(VectorElement e, int index) {
  var shapes = e.shapes ?? const <VectorShape>[];
  if (index < 0 || index >= shapes.length) return index;
  var i = index;
  while (i > 0 && shapes[i].combine != null) {
    i--;
  }
  return i;
}

/// groupMembers is every shape in the run of combining shapes starting at
/// [base]: it, and those combining into it.
List<int> groupMembers(VectorElement e, int base) {
  var shapes = e.shapes ?? const <VectorShape>[];
  if (base < 0 || base >= shapes.length) return const [];
  return [
    base,
    for (var i = base + 1; i < shapes.length && shapes[i].combine != null; i++)
      i,
  ];
}

/// withCombined is the shapes in [picked] combined by [op]: the lowest of
/// them is what the others are combined into, and they are moved up to sit
/// just after it, in the order they were. Each picked shape brings the
/// shapes already combined into it. Returns the drawing and where the
/// result now starts.
(VectorElement, int) withCombined(
    VectorElement e, Set<int> picked, VectorCombine op) {
  var shapes = e.shapes ?? const <VectorShape>[];
  var bases = {for (var i in picked) groupOf(e, i)}.toList()..sort();
  if (bases.length < 2) return (e, bases.firstOrNull ?? -1);
  var base = bases.first;
  var joining = [
    for (var b in bases.skip(1))
      for (var (k, i) in groupMembers(e, b).indexed)
        k == 0 ? shapes[i].copyWith(combine: op) : shapes[i],
  ];
  var moved = {for (var b in bases.skip(1)) ...groupMembers(e, b)};
  var baseGroup = groupMembers(e, base);
  var next = <VectorShape>[];
  var at = -1;
  for (var i = 0; i < shapes.length; i++) {
    if (moved.contains(i)) continue;
    if (i == base) at = next.length;
    next.add(shapes[i]);
    if (i == baseGroup.last) next.addAll(joining);
  }
  return (e.copyWith(shapes: next), at);
}

/// withSeparated undoes the combining of the run starting at [base]: every
/// shape in it is a shape of its own again, in its own colours.
VectorElement withSeparated(VectorElement e, int base) {
  var shapes = [...?e.shapes];
  for (var i in groupMembers(e, base).skip(1)) {
    shapes[i] = shapes[i].copyWith(clearCombine: true);
  }
  return e.copyWith(shapes: shapes);
}

/// blankDrawing is [e] ready to be drawn on from nothing: no shapes yet, in
/// a space the size of its own box.
VectorElement blankDrawing(VectorElement e) => e.copyWith(
    viewBox: Rect.fromLTWH(0, 0, math.max(1, e.width), math.max(1, e.height)),
    shapes: const []);

/// withPenPoint is [e] with a point put down by the pen at [canvasPoint],
/// joined on from the point [from] -- or, with none, as the first point of
/// a new shape, painted like [like] or plainly. The new point's pick comes
/// back with it, and is what the next point joins on from.
///
/// From the end of an open run, the run goes on. From its first point, the
/// run is turned round and goes on from there. From anywhere else -- a
/// point in the middle, or on a closed run -- a new run starts at that
/// point, in the same shape: a branch, joined where it leaves.
(VectorElement, VectorPick) withPenPoint(
    VectorElement e, VectorPick? from, Offset canvasPoint,
    {VectorShape? like}) {
  var at = VectorSpace(e).toDrawing(canvasPoint);
  var shapes = [...?e.shapes];
  var node = from == null ? null : _nodeAt(e, from);
  if (from != null && node != null) {
    var s = shapes[from.shape];
    var paths = [...s.paths];
    var run = paths[from.path];
    var nodes = run.nodes;
    var added = VectorNode(at.dx, at.dy, width: node.width);
    if (!run.closed && from.node == nodes.length - 1) {
      paths[from.path] = run.copyWith(nodes: [...nodes, added]);
      shapes[from.shape] = s.copyWith(paths: paths);
      return (
        e.copyWith(shapes: shapes),
        VectorPick(from.shape, from.path, nodes.length)
      );
    }
    if (!run.closed && from.node == 0 && nodes.length > 1) {
      paths[from.path] = run.copyWith(nodes: [
        for (var n in nodes.reversed) n.reversed,
        added,
      ]);
      shapes[from.shape] = s.copyWith(paths: paths);
      return (
        e.copyWith(shapes: shapes),
        VectorPick(from.shape, from.path, nodes.length)
      );
    }
    paths.add(
        VectorPath([VectorNode(node.x, node.y, width: node.width), added]));
    shapes[from.shape] = s.copyWith(paths: paths);
    return (
      e.copyWith(shapes: shapes),
      VectorPick(from.shape, paths.length - 1, 1)
    );
  }
  // A line a hundredth of the drawing across, so it can be seen whatever
  // size the drawing's own units are.
  var view = e.viewBox;
  var width = math.max(1.0, math.min(view.width, view.height) / 100);
  shapes.add(VectorShape(
    paths: [
      VectorPath([VectorNode(at.dx, at.dy)])
    ],
    fill: like?.fill,
    stroke: like?.stroke ?? const Color(0xFF000000),
    strokeWidth: like?.strokeWidth ?? width,
    cap: like?.cap ?? StrokeCap.round,
    join: like?.join ?? StrokeJoin.round,
  ));
  return (e.copyWith(shapes: shapes), VectorPick(shapes.length - 1, 0, 0));
}

/// withWidths is [e] with each point in [from] given its width there times
/// [factor]: a line made thicker or thinner at those points. Kept between
/// nothing and twenty times the shape's stroke width.
VectorElement withWidths(
    VectorElement e, Map<VectorPick, double> from, double factor) {
  var next = e;
  for (var MapEntry(key: pick, value: width) in from.entries) {
    var node = _nodeAt(next, pick);
    if (node == null) continue;
    next = withVectorNode(
        next, pick, node.copyWith(width: (width * factor).clamp(0.0, 20.0)));
  }
  return next;
}

/// shapesUnder is the shapes of [e] a brush [radius] wide at [at] (in the
/// drawing's units) lies over -- its fill, or within reach of its line --
/// each as the first of its run of combined shapes, which is the one that
/// carries tints and rub-outs for the run. What a tint or a rub-out painted
/// there is laid on.
Set<int> shapesUnder(VectorElement e, Offset at, double radius) {
  var shapes = e.shapes ?? const <VectorShape>[];
  var out = <int>{};
  var i = 0;
  for (var d in vectorDrawn(shapes)) {
    var s = d.style;
    var reach = radius + (s.stroke == null ? 0 : s.strokeWidth / 2);
    var outline = d.outline;
    if (outline.getBounds().inflate(reach).contains(at) &&
        ((s.fill != null && outline.contains(at)) ||
            _nearOutline(outline, at, reach))) {
      out.add(i);
    }
    i += d.members.length;
  }
  return out;
}

/// withStrokeOn is [e] with [stroke] laid on each shape in [on] -- as a
/// rub-out where [rubOut], as a tint otherwise. See VectorShape.tints.
VectorElement withStrokeOn(VectorElement e, Set<int> on, VectorTint stroke,
    {bool rubOut = false}) {
  if (on.isEmpty) return e;
  var shapes = [...?e.shapes];
  for (var i in on) {
    if (i < 0 || i >= shapes.length) continue;
    var s = shapes[i];
    shapes[i] = rubOut
        ? s.copyWith(erasures: [...s.erasures, stroke])
        : s.copyWith(tints: [...s.tints, stroke]);
  }
  return e.copyWith(shapes: shapes);
}

/// hasTints and hasErasures are whether any shape of [e] carries a tint, or
/// a rub-out.
bool hasTints(VectorElement e) =>
    (e.shapes ?? const <VectorShape>[]).any((s) => s.tints.isNotEmpty);
bool hasErasures(VectorElement e) =>
    (e.shapes ?? const <VectorShape>[]).any((s) => s.erasures.isNotEmpty);

/// withoutTints and withoutErasures are [e] with every tint, or every
/// rub-out, taken off.
VectorElement withoutTints(VectorElement e) => e.copyWith(shapes: [
      for (var s in e.shapes ?? const <VectorShape>[])
        s.tints.isEmpty ? s : s.copyWith(tints: const []),
    ]);
VectorElement withoutErasures(VectorElement e) => e.copyWith(shapes: [
      for (var s in e.shapes ?? const <VectorShape>[])
        s.erasures.isEmpty ? s : s.copyWith(erasures: const []),
    ]);

/// withPenHandles is the point at [pick] given a smooth pair of handles,
/// the out one pulled to [canvasPoint] -- what dragging as a point is put
/// down does.
VectorElement withPenHandles(
    VectorElement e, VectorPick pick, Offset canvasPoint) {
  var node = _nodeAt(e, pick);
  if (node == null) return e;
  var d = VectorSpace(e).toDrawing(canvasPoint) - node.point;
  return withVectorNode(
      e,
      pick,
      node.copyWith(
          outX: d.dx,
          outY: d.dy,
          inX: -d.dx,
          inY: -d.dy,
          smooth: d != Offset.zero,
          // Pulled out by the pen, the pair is each other's mirror.
          mirrored: d != Offset.zero));
}

/// withPenClosed closes the run at [run] -- the one the pen is drawing.
VectorElement withPenClosed(VectorElement e, VectorPick run) {
  var s = e.shapes![run.shape];
  var paths = [...s.paths];
  paths[run.path] = paths[run.path].copyWith(closed: true);
  return e.withShape(run.shape, s.copyWith(paths: paths));
}

/// pointsNear is every point of [e] within [reach] of [canvasPoint].
Set<VectorPick> pointsNear(VectorElement e, Offset canvasPoint, double reach) {
  var space = VectorSpace(e);
  return {
    for (var (s, shape) in (e.shapes ?? const <VectorShape>[]).indexed)
      for (var (p, path) in shape.paths.indexed)
        for (var (n, node) in path.nodes.indexed)
          if ((space.toCanvas(node.point) - canvasPoint).distance <= reach)
            VectorPick(s, p, n),
  };
}

/// anyPointAt is the point of any shape of [e] within [reach] of
/// [canvasPoint], the nearest -- or null.
VectorPick? anyPointAt(VectorElement e, Offset canvasPoint, double reach) {
  var space = VectorSpace(e);
  VectorPick? best;
  var nearest = reach;
  for (var (s, shape) in (e.shapes ?? const <VectorShape>[]).indexed) {
    for (var (p, path) in shape.paths.indexed) {
      for (var (n, node) in path.nodes.indexed) {
        var d = (space.toCanvas(node.point) - canvasPoint).distance;
        if (d <= nearest) {
          nearest = d;
          best = VectorPick(s, p, n);
        }
      }
    }
  }
  return best;
}

/// shapeExtent is how far [shape]'s outline actually reaches, in the
/// drawing's units -- through its curves, not out to their handles, which is
/// what a path's own bounds go to.
Rect? shapeExtent(VectorShape shape) {
  Rect? box;
  void add(Offset p) => box = box == null
      ? Rect.fromPoints(p, p)
      : box!.expandToInclude(Rect.fromPoints(p, p));
  for (var run in shape.paths) {
    var nodes = run.nodes;
    for (var n in nodes) {
      add(n.point);
    }
    var count = run.closed ? nodes.length : nodes.length - 1;
    for (var i = 0; i < count && nodes.length > 1; i++) {
      var a = nodes[i], b = nodes[(i + 1) % nodes.length];
      if (!a.hasOut && !b.hasIn) continue;
      // Where the curve turns back on itself along each axis: the roots of
      // its derivative, a quadratic.
      var p0 = a.point, p1 = a.outHandle, p2 = b.inHandle, p3 = b.point;
      for (var axis = 0; axis < 2; axis++) {
        double c(Offset o) => axis == 0 ? o.dx : o.dy;
        var qa = -c(p0) + 3 * c(p1) - 3 * c(p2) + c(p3);
        var qb = 2 * (c(p0) - 2 * c(p1) + c(p2));
        var qc = c(p1) - c(p0);
        var roots = <double>[];
        if (qa.abs() < 1e-12) {
          if (qb.abs() > 1e-12) roots.add(-qc / qb);
        } else {
          var disc = qb * qb - 4 * qa * qc;
          if (disc >= 0) {
            var r = math.sqrt(disc);
            roots.add((-qb + r) / (2 * qa));
            roots.add((-qb - r) / (2 * qa));
          }
        }
        for (var t in roots) {
          if (t > 0 && t < 1) add(_bezier(a, b, t));
        }
      }
    }
  }
  if (box != null && shape.stroke != null) {
    box = box!.inflate(shape.strokeWidth / 2);
  }
  return box;
}

/// boxedToDrawing is [e] with its box fitted to the whole of what is drawn
/// -- every shape, and half of each stroke -- grown where editing has carried
/// any of it out, and drawn in where there is room to spare, so the box round
/// the drawing is round the drawing and nothing else. The drawing stays
/// exactly where it is on the page: the box and the drawing's own space
/// change together, and a turned element is shifted so it turns about the
/// right point.
VectorElement boxedToDrawing(VectorElement e) {
  var shapes = e.shapes;
  if (shapes == null || shapes.isEmpty) return e;
  var view = e.viewBox;
  if (view.width <= 0 || view.height <= 0) return e;
  Rect? reach;
  for (var shape in shapes) {
    // A shape cutting another, or keeping only its overlap, draws nothing
    // outside the shape it is combined into.
    if (shape.combine == VectorCombine.subtract ||
        shape.combine == VectorCombine.intersect) {
      continue;
    }
    var b = shapeExtent(shape);
    if (b == null) continue;
    reach = reach == null ? b : reach.expandToInclude(b);
  }
  if (reach == null || reach.width <= 0 || reach.height <= 0) return e;
  bool same(double a, double b) => (a - b).abs() < 1e-6;
  if (same(reach.left, view.left) &&
      same(reach.top, view.top) &&
      same(reach.right, view.right) &&
      same(reach.bottom, view.bottom)) {
    return e;
  }

  var p = e.placement(e.bounds, view);
  var box = Rect.fromLTRB(reach.left * p.sx + p.dx, reach.top * p.sy + p.dy,
      reach.right * p.sx + p.dx, reach.bottom * p.sy + p.dy);
  // Turned about a new centre, the drawing would land somewhere else; the
  // box is moved by whatever puts it back.
  var c = e.bounds.center, c2 = box.center;
  var a = e.rotation * math.pi / 180;
  var d = c2 - c;
  var turned = Offset(d.dx * math.cos(a) - d.dy * math.sin(a),
      d.dx * math.sin(a) + d.dy * math.cos(a));
  var shift = c - c2 + turned;
  return e.copyWith(viewBox: reach).withBase(
      x: box.left + shift.dx,
      y: box.top + shift.dy,
      width: box.width,
      height: box.height) as VectorElement;
}

/// takeApart reads [e]'s file and takes it apart into shapes, or returns
/// null where the file cannot be found or read.
Future<SvgImport?> takeApart(VectorElement e) async {
  if (e.assetId.isEmpty) return null;
  var bytes = await CanvasMedia.load(MediaKind.vector, e.assetId);
  if (bytes == null) return null;
  return importSvg(utf8.decode(bytes, allowMalformed: true));
}
