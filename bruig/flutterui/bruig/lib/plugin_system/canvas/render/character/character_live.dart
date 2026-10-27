import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_life.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_outline.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_painter.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_parts.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';

// character_live.dart is a layer drawn on that its sliders still shape.
//
// Taking a layer apart keeps its shapes as the character drew them -- its
// base -- beside the shapes that are edited, each marked with which of the
// base's it began as. Drawn, the layer is drawn again as the sliders make
// it now, and each edited shape is the shape it began as, made now, with
// the edit carried onto it: every point moved as far as the outline under
// it has moved since -- along the outline, so a point added, taken away or
// dragged goes with the part of the outline it is on. A wider face carries
// a reshaped chin out with it; bigger eyes carry a redrawn lash.
//
// The edit is measured in the shape's own part's measure, so moving and
// turning the body moves it as it moves the body. A shape drawn by hand on
// the layer is left as it is. Where the sliders change what the layer is
// made of -- more shapes, or fewer -- its edits are kept as drawn until it
// is drawn on again, which takes it as it is then as its new base.

/// liveCharacter is [e] with what is drawn on the view it is seen from on
/// [frame] carried onto its layers as the character draws them now. For
/// drawing it: nothing of it is kept.
CharacterElement liveCharacter(CharacterElement e, int frame, int frameRate) {
  if (e.body.inThreeD) return e;
  var key = drawnKey(e, frame, frameRate);
  var (own, _) = e.drawingAt(key);
  var wears = [
    for (var (i, g) in e.dna.wardrobe.indexed)
      if (g.drawingAt(key).$1.bases.isNotEmpty) i,
  ];
  if (own.bases.isEmpty && wears.isEmpty) return e;
  var (rig, _, _) = drawnRig(e, frame, frameRate);
  var captured = _capture(e, frame, frameRate);
  var next = own.bases.isEmpty ? e : e.withDrawingAt(key, liveDrawing(own, captured, rig));
  if (wears.isEmpty) return next;
  var wardrobe = [...next.dna.wardrobe];
  for (var i in wears) {
    var g = wardrobe[i];
    wardrobe[i] = g.withDrawingAt(
        key, liveDrawing(g.drawingAt(key).$1, captured, rig, among: g.kind.covers));
  }
  return next.copyWith(dna: next.dna.copyWith(wardrobe: wardrobe));
}

/// rebasedCharacter is [e] with what is drawn on the view seen on [frame]
/// taken as it is drawn now -- edits carried onto the character as it is
/// -- and that, as the character draws it now, as its new base: what the
/// drawing tools are given to edit, so they edit what is seen.
CharacterElement rebasedCharacter(CharacterElement e, int frame, int frameRate) {
  if (e.body.inThreeD) return e;
  var key = drawnKey(e, frame, frameRate);
  var (own, mirrored) = e.drawingAt(key);
  var wears = [
    for (var (i, g) in e.dna.wardrobe.indexed)
      if (g.drawingAt(key).$1.bases.isNotEmpty) i,
  ];
  if (own.bases.isEmpty && wears.isEmpty) return e;
  var (rig, _, _) = drawnRig(e, frame, frameRate);
  var captured = _capture(e, frame, frameRate);
  var next = own.bases.isEmpty || mirrored
      ? e
      : e.withDrawingAt(key, liveDrawing(own, captured, rig, rebase: true));
  var wardrobe = [...next.dna.wardrobe];
  for (var i in wears) {
    var g = wardrobe[i];
    var (d, gm) = g.drawingAt(key);
    if (gm) continue;
    wardrobe[i] = g.withDrawingAt(
        key, liveDrawing(d, captured, rig, among: g.kind.covers, rebase: true));
  }
  return next.copyWith(dna: next.dna.copyWith(wardrobe: wardrobe));
}

/// liveDrawing is [d] with each of its layers' edits carried onto that
/// layer as [captured] -- the figure as the character draws it now, on
/// [rig] -- has it. With [rebase], those as its new bases too.
CharacterDrawing liveDrawing(
    CharacterDrawing d, List<CapturedShape> captured, CharacterRig rig,
    {Set<CharacterPart>? among, bool rebase = false}) {
  var shapes = [...d.shapes];
  var bases = {...d.bases};
  for (var MapEntry(key: layer, value: base) in d.bases.entries) {
    // A layer shaped through keyforms is shaped by them.
    if (d.keyed.containsKey(layer)) continue;
    var nowPage = [
      for (var c in captured)
        if (c.layer == layer) c.shape,
    ];
    // Made of other shapes now: as drawn, until drawn on again.
    if (nowPage.length != base.shapes.length) continue;
    var now = shapesOnParts(nowPage, rig, keep: base.parts, among: among).shapes;
    for (var i = 0; i < shapes.length; i++) {
      if (d.layerOf(i) != layer) continue;
      var j = int.tryParse(shapes[i].origin ?? "");
      if (j == null || j < 0 || j >= now.length) continue;
      shapes[i] = carried(shapes[i], base.shapes[j], now[j]);
    }
    if (rebase) {
      bases[layer] = CharacterDrawing(shapes: now, parts: base.parts);
    }
  }
  return d.copyWith(shapes: shapes, bases: bases);
}

/// carried is [edited] -- made from [was] -- carried onto [now], [was] as
/// it is made now: its own points, each moved as far as the outline under
/// it has moved, along it; its colours the new ones where it kept the old.
VectorShape carried(VectorShape edited, VectorShape was, VectorShape now) {
  bool same(Color? a, Color? b) =>
      a == b ||
      (a != null &&
          b != null &&
          (a.r - b.r).abs() < 1e-3 &&
          (a.g - b.g).abs() < 1e-3 &&
          (a.b - b.b).abs() < 1e-3 &&
          (a.a - b.a).abs() < 1e-3);
  var paths = <VectorPath>[];
  var runsMatch = was.paths.length == now.paths.length;
  // Where the runs do not match up, the shape is carried as a whole: from
  // where it was, as big as it was, to where it is now, as big.
  var from = was.path.getBounds(), to = now.path.getBounds();
  for (var (p, run) in edited.paths.indexed) {
    if (runsMatch && p < was.paths.length) {
      paths.add(_alongRun(run, was.paths[p], now.paths[p]));
    } else {
      paths.add(_boxed(run, from, to));
    }
  }
  return edited.copyWith(
    paths: paths,
    fill: same(edited.fill, was.fill) ? now.fill : null,
    clearFill: same(edited.fill, was.fill) && now.fill == null,
    stroke: same(edited.stroke, was.stroke) ? now.stroke : null,
    clearStroke: same(edited.stroke, was.stroke) && now.stroke == null,
    strokeWidth: (edited.strokeWidth - was.strokeWidth).abs() < 1e-6
        ? now.strokeWidth
        : null,
  );
}

/// _alongRun is [run] with each of its points moved as far as the run
/// [was] has moved to become [now], at the same share of the way round.
VectorPath _alongRun(VectorPath run, VectorPath was, VectorPath now) {
  var a = _Walk(was), b = _Walk(now);
  if (a.length <= 0 || b.length <= 0 || run.nodes.isEmpty) return run;
  var mine = _Walk(run);
  var grow = b.length / a.length;
  var nodes = <VectorNode>[];
  for (var (k, n) in run.nodes.indexed) {
    var t = mine.length <= 0 ? 0.0 : mine.at[k] / mine.length;
    var d = b.point(t) - a.point(t);
    nodes.add(n.copyWith(
      x: n.x + d.dx,
      y: n.y + d.dy,
      inX: n.inX * grow,
      inY: n.inY * grow,
      outX: n.outX * grow,
      outY: n.outY * grow,
    ));
  }
  return run.copyWith(nodes: nodes);
}

/// _boxed is [run] moved and scaled from [from] to [to].
VectorPath _boxed(VectorPath run, Rect from, Rect to) {
  double sx = from.width < 1e-6 ? 1 : to.width / from.width;
  double sy = from.height < 1e-6 ? 1 : to.height / from.height;
  return run.copyWith(nodes: [
    for (var n in run.nodes)
      n.copyWith(
        x: to.left + (n.x - from.left) * sx,
        y: to.top + (n.y - from.top) * sy,
        inX: n.inX * sx,
        inY: n.inY * sy,
        outX: n.outX * sx,
        outY: n.outY * sy,
      ),
  ]);
}

/// _Walk is a run walked from its first point: how far round it each of
/// its points is, and where any share of the way round it is.
class _Walk {
  final List<double> at = [];
  late final double length;
  final List<Offset> _pts = [];
  final List<double> _dist = [];

  _Walk(VectorPath run) {
    var nodes = run.nodes;
    if (nodes.isEmpty) {
      length = 0;
      return;
    }
    // Each segment in a few steps, its curve followed.
    Offset bez(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
      var s = 1 - t;
      return p0 * (s * s * s) + p1 * (3 * s * s * t) + p2 * (3 * s * t * t) + p3 * (t * t * t);
    }

    var total = 0.0;
    _pts.add(nodes.first.point);
    _dist.add(0);
    void segment(VectorNode a, VectorNode b) {
      var p0 = a.point, p3 = b.point;
      var p1 = a.outHandle, p2 = b.inHandle;
      const steps = 8;
      for (var k = 1; k <= steps; k++) {
        var q = bez(p0, p1, p2, p3, k / steps);
        total += (q - _pts.last).distance;
        _pts.add(q);
        _dist.add(total);
      }
    }

    at.add(0);
    for (var i = 1; i < nodes.length; i++) {
      segment(nodes[i - 1], nodes[i]);
      at.add(total);
    }
    if (run.closed && nodes.length > 1) segment(nodes.last, nodes.first);
    length = total;
  }

  /// point is where [t] of the way round it is.
  Offset point(double t) {
    if (_pts.length == 1) return _pts.first;
    var want = (t.clamp(0.0, 1.0)) * length;
    // The first step past it.
    var lo = 0, hi = _dist.length - 1;
    while (lo < hi) {
      var mid = (lo + hi) >> 1;
      if (_dist[mid] < want) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    var i = math.max(1, lo);
    var d0 = _dist[i - 1], d1 = _dist[i];
    var f = d1 - d0 < 1e-9 ? 0.0 : (want - d0) / (d1 - d0);
    return Offset.lerp(_pts[i - 1], _pts[i], f)!;
  }
}

/// _captured holds the figures last taken apart to carry edits onto, by
/// what they were drawn from: a frame drawn again -- the canvas repainted,
/// a tile drawn -- does not draw the figure over to find its shapes.
final LinkedHashMap<String, List<CapturedShape>> _captured = LinkedHashMap();

List<CapturedShape> _capture(CharacterElement e, int frame, int frameRate) {
  var shown = e.style.frameOf(frame);
  var (pose, face) = e.performanceAt(shown, frameRate);
  var key = "${identityHashCode(e.dna)}|${e.style.index}|${drawnKey(e, frame, frameRate)}|"
      "${e.inView(pose).toJson()}|${face.toJson()}|${identityHashCode(e.faceRigs)}|"
      "${e.width}x${e.height}";
  var hit = _captured.remove(key);
  if (hit != null) {
    _captured[key] = hit;
    return hit;
  }
  var (rig, _, _) = drawnRig(e, frame, frameRate);
  var made = captureFigure(rig, e.style.dnaOf(e.dna), face, lifeAt(e, shown, frameRate),
      e.style,
      faceRig: e.faceRigAt(drawnKey(e, frame, frameRate)).$1);
  _captured[key] = made;
  while (_captured.length > 16) {
    _captured.remove(_captured.keys.first);
  }
  return made;
}
