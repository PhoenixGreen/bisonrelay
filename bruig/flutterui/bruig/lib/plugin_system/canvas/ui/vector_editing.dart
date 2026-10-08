import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/svg_import.dart';
import 'package:bruig/plugin_system/canvas/render/vector_painter.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';

// vector_editing.dart is the arithmetic of editing a drawing point by point:
// where a point of the drawing is on the canvas and back, what is under the
// pointer, and the edits themselves -- move a point or a handle, put a point
// in a curve, take one out, make one a corner or smooth. Kept out of the
// stage, which only has to ask.

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
    {bool breakHandles = false}) {
  var node = _nodeAt(e, pick);
  if (node == null) return e;
  var to = VectorSpace(e).toDrawing(canvasPoint);
  switch (part) {
    case VectorPart.point:
      return withVectorNode(e, pick, node.moved(to));
    case VectorPart.inHandle || VectorPart.outHandle:
      var out = part == VectorPart.outHandle;
      var d = to - node.point;
      var next = out
          ? node.copyWith(outX: d.dx, outY: d.dy)
          : node.copyWith(inX: d.dx, inY: d.dy);
      if (node.smooth && !breakHandles) {
        var other =
            out ? Offset(node.inX, node.inY) : Offset(node.outX, node.outY);
        var length = other.distance;
        var dir = d.distance == 0 ? Offset.zero : d / d.distance;
        var mirrored = -dir * length;
        next = out
            ? next.copyWith(inX: mirrored.dx, inY: mirrored.dy)
            : next.copyWith(outX: mirrored.dx, outY: mirrored.dy);
      }
      if (breakHandles) next = next.copyWith(smooth: false);
      return withVectorNode(e, pick, next);
  }
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
  var u = 1 - t;
  return p0 * (u * u * u) +
      p1 * (3 * u * u * t) +
      p2 * (3 * u * t * t) +
      p3 * (t * t * t);
}

/// withPointAdded is [e] with a point put into the segment of [path] that
/// starts at point [from], [t] of the way along -- the curve split there so
/// its shape does not change. The new point's pick is returned with it.
(VectorElement, VectorPick) withPointAdded(
    VectorElement e, int shape, int path, int from, double t) {
  var s = e.shapes![shape];
  var run = s.paths[path];
  var nodes = [...run.nodes];
  var a = nodes[from], bIndex = (from + 1) % nodes.length, b = nodes[bIndex];
  // de Casteljau: the curve split in two at t, through the same points.
  var p0 = a.point, p1 = a.outHandle, p2 = b.inHandle, p3 = b.point;
  Offset lerp(Offset x, Offset y) => x + (y - x) * t;
  var q0 = lerp(p0, p1), q1 = lerp(p1, p2), q2 = lerp(p2, p3);
  var r0 = lerp(q0, q1), r1 = lerp(q1, q2);
  var m = lerp(r0, r1);
  var straight = !a.hasOut && !b.hasIn;
  var added = straight
      ? VectorNode(m.dx, m.dy)
      : VectorNode(m.dx, m.dy,
          inX: r0.dx - m.dx,
          inY: r0.dy - m.dy,
          outX: r1.dx - m.dx,
          outY: r1.dy - m.dy,
          smooth: true);
  if (!straight) {
    nodes[from] = a.copyWith(outX: q0.dx - p0.dx, outY: q0.dy - p0.dy);
    nodes[bIndex] = b.copyWith(inX: q2.dx - p3.dx, inY: q2.dy - p3.dy);
  }
  nodes.insert(from + 1, added);
  var paths = [...s.paths];
  paths[path] = run.copyWith(nodes: nodes);
  return (
    e.withShape(shape, s.copyWith(paths: paths)),
    VectorPick(shape, path, from + 1)
  );
}

/// withoutPoint is [e] with the point at [pick] taken out. A run left with
/// fewer than two points goes, and a shape left with no runs goes with it.
VectorElement withoutPoint(VectorElement e, VectorPick pick) {
  var shapes = [...?e.shapes];
  if (pick.shape >= shapes.length) return e;
  var s = shapes[pick.shape];
  var paths = [...s.paths];
  var nodes = [...paths[pick.path].nodes]..removeAt(pick.node);
  if (nodes.length < 2) {
    paths.removeAt(pick.path);
  } else {
    paths[pick.path] = paths[pick.path].copyWith(nodes: nodes);
  }
  if (paths.isEmpty) {
    shapes.removeAt(pick.shape);
  } else {
    shapes[pick.shape] = s.copyWith(paths: paths);
  }
  return e.copyWith(shapes: shapes);
}

/// withSmoothToggled makes the point at [pick] a corner, or smooth: a corner
/// loses its handles, and a point made smooth is given a pair along the line
/// between its neighbours, a third of the way to each.
VectorElement withSmoothToggled(VectorElement e, VectorPick pick) {
  var node = _nodeAt(e, pick);
  if (node == null) return e;
  if (node.smooth || node.hasIn || node.hasOut) {
    return withVectorNode(e, pick,
        node.copyWith(inX: 0, inY: 0, outX: 0, outY: 0, smooth: false));
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
  for (var pick in picks) {
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
  return e.copyWith(shapes: shapes);
}

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

/// withoutPoints is [e] with every point in [picks] taken out -- last first,
/// so taking one out does not move the others' places in their lists.
VectorElement withoutPoints(VectorElement e, Set<VectorPick> picks) {
  var order = [...picks]..sort((a, b) {
      var by = b.shape.compareTo(a.shape);
      if (by != 0) return by;
      by = b.path.compareTo(a.path);
      return by != 0 ? by : b.node.compareTo(a.node);
    });
  var next = e;
  for (var pick in order) {
    next = withoutPoint(next, pick);
  }
  return next;
}

/// blankDrawing is [e] ready to be drawn on from nothing: no shapes yet, in
/// a space the size of its own box.
VectorElement blankDrawing(VectorElement e) => e.copyWith(
    viewBox: Rect.fromLTWH(0, 0, math.max(1, e.width), math.max(1, e.height)),
    shapes: const []);

/// withPenPoint is [e] with a point put down by the pen at [canvasPoint]: on
/// the end of the shape the pen is drawing, or -- where it is drawing none --
/// as the first point of a new shape, painted like [like] or plainly. The
/// shape's index and the new point's pick come back with it.
(VectorElement, VectorPick) withPenPoint(
    VectorElement e, int drawing, Offset canvasPoint,
    {VectorShape? like}) {
  var at = VectorSpace(e).toDrawing(canvasPoint);
  var shapes = [...?e.shapes];
  if (drawing >= 0 && drawing < shapes.length) {
    var s = shapes[drawing];
    var paths = [...s.paths];
    var run = paths.last;
    paths[paths.length - 1] =
        run.copyWith(nodes: [...run.nodes, VectorNode(at.dx, at.dy)]);
    shapes[drawing] = s.copyWith(paths: paths);
    return (
      e.copyWith(shapes: shapes),
      VectorPick(drawing, paths.length - 1, run.nodes.length)
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
          smooth: d != Offset.zero));
}

/// withPenClosed closes the run the pen is drawing in shape [shape].
VectorElement withPenClosed(VectorElement e, int shape) {
  var s = e.shapes![shape];
  var paths = [...s.paths];
  paths[paths.length - 1] = paths.last.copyWith(closed: true);
  return e.withShape(shape, s.copyWith(paths: paths));
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
