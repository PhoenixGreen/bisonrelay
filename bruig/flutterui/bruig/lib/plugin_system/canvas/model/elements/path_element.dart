import 'package:bruig/components/paint_spec.dart';
import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_limits.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stroke.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';
import 'package:bruig/plugin_system/canvas/model/cubic_segment.dart';

// path_element.dart is a bezier curve, and optionally the route a named
// follower takes along it, timed node by node. The movement is not worked
// out at paint time: it is baked into the follower's own keyframes (see
// CanvasController.applyPathFollow), so exports and a published canvas
// replay it without knowing what a path is.

/// PathNode is one point on the curve, with the handles that shape the
/// segments either side. The point and both handles are fractions of the
/// element's box, so moving or resizing the element takes the curve along.
class PathNode {
  /// x and y are 0..1 within the element's box.
  final double x;
  final double y;

  /// inDx/inDy and outDx/outDy are the handles, offsets from the point:
  /// two, not a mirrored pair, so a node can be a corner.
  final double inDx;
  final double inDy;
  final double outDx;
  final double outDy;

  /// frame is when the follower reaches this node: on the node, not in a
  /// parallel list that would have to stay the same length.
  final int frame;

  const PathNode({
    required this.x,
    required this.y,
    this.inDx = 0,
    this.inDy = 0,
    this.outDx = 0,
    this.outDy = 0,
    this.frame = 0,
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = PathNode(x: 0, y: 0);

  Offset get point => Offset(x, y);
  Offset get inHandle => Offset(x + inDx, y + inDy);
  Offset get outHandle => Offset(x + outDx, y + outDy);

  /// hasIn and hasOut are whether a handle is pulled out of the point, so
  /// is drawn and can be taken: one that is not lies on the point, and its
  /// side of the curve leaves the point straight.
  bool get hasIn => inDx != 0 || inDy != 0;
  bool get hasOut => outDx != 0 || outDy != 0;

  /// gripOf is where [grip] is, as a fraction of the box.
  Offset gripOf(PathGrip grip) => switch (grip) {
        PathGrip.point => point,
        PathGrip.inHandle => inHandle,
        PathGrip.outHandle => outHandle,
      };

  /// hasGrip is whether [grip] can be taken apart from the point: the point
  /// always, a handle when it is pulled out.
  bool hasGrip(PathGrip grip) => switch (grip) {
        PathGrip.point => true,
        PathGrip.inHandle => hasIn,
        PathGrip.outHandle => hasOut,
      };

  PathNode copyWith({
    double? x,
    double? y,
    double? inDx,
    double? inDy,
    double? outDx,
    double? outDy,
    int? frame,
  }) =>
      PathNode(
        x: x ?? this.x,
        y: y ?? this.y,
        inDx: inDx ?? this.inDx,
        inDy: inDy ?? this.inDy,
        outDx: outDx ?? this.outDx,
        outDy: outDy ?? this.outDy,
        frame: frame ?? this.frame,
      );

  /// withMirroredHandle moves one handle and swings the other to match,
  /// keeping the curve smooth through the node.
  PathNode withMirroredHandle({required bool out, required Offset to}) {
    var d = to - point;
    return out
        ? copyWith(outDx: d.dx, outDy: d.dy, inDx: -d.dx, inDy: -d.dy)
        : copyWith(inDx: d.dx, inDy: d.dy, outDx: -d.dx, outDy: -d.dy);
  }

  Map<String, dynamic> toJson() => {
        "x": x,
        "y": y,
        if (inDx != _defaults.inDx) "ix": inDx,
        if (inDy != _defaults.inDy) "iy": inDy,
        if (outDx != _defaults.outDx) "ox": outDx,
        if (outDy != _defaults.outDy) "oy": outDy,
        "f": frame,
      };

  /// PathNode.fromJson reads one saved by [toJson], its point and handles
  /// no further than maxPathFraction from the box and its frame within the
  /// longest a scene can be.
  factory PathNode.fromJson(Map<String, dynamic> json) {
    double fraction(String key, double fallback) =>
        jsonDouble(json[key], fallback)
            .clamp(-maxPathFraction, maxPathFraction);
    return PathNode(
      x: fraction("x", 0),
      y: fraction("y", 0),
      inDx: fraction("ix", _defaults.inDx),
      inDy: fraction("iy", _defaults.inDy),
      outDx: fraction("ox", _defaults.outDx),
      outDy: fraction("oy", _defaults.outDy),
      frame: jsonInt(json["f"], _defaults.frame).clamp(0, maxFrameCount),
    );
  }
}

/// PathGrip is which part of a path's point is taken: the point, or one of
/// its handles.
enum PathGrip { point, inHandle, outHandle }

/// PathFollow names what travels the curve: an element, or a team's
/// player, by the team's id and row index, as the timeline does.
class PathFollow {
  final String elementId;

  /// playerIndex is set when the follower is a team's player.
  final int? playerIndex;

  const PathFollow({required this.elementId, this.playerIndex});

  Map<String, dynamic> toJson() => {
        "id": elementId,
        if (playerIndex != null) "player": playerIndex,
      };

  /// PathFollow.fromJson reads one saved by [toJson]; null for a player
  /// no team can have, which nothing here writes, so that nothing follows
  /// rather than somebody else.
  static PathFollow? fromJson(Map<String, dynamic> json) {
    var player = json["player"];
    if (player is! num) return PathFollow(elementId: jsonId(json["id"], ""));
    var index = jsonDouble(player, -1);
    if (index < 0 || index >= maxTeamPlayers) return null;
    return PathFollow(
        elementId: jsonId(json["id"], ""), playerIndex: index.toInt());
  }
}

/// followTrack is a follower's keys with its place on the path baked in: a
/// key on every frame of the run, [from] to [to], and on every frame it has
/// a key of its own, each shifted from its rest by [shiftAt] (null where it
/// has no place on that frame). What else it has keyed is kept as it plays:
/// a key of its own keeps its turn, size, fade, channels and easing; a key
/// the bake adds between takes them as the follower's keys give them there.
/// A bake already in [track] is taken back first ([ownTrack]), so baking
/// again replaces the route rather than adding to it.
ElementTrack followTrack(ElementTrack? track,
    Offset? Function(int frame) shiftAt, int from, int to) {
  var own = ownTrack(track);
  var frames = {
    for (var f = from; f <= to; f++) f,
    for (var k in own.keys) k.frame
  };
  var keys = <Keyframe>[];
  for (var f in frames) {
    var mine = own.keyAt(f);
    var shift = shiftAt(f);
    if (shift == null) {
      if (mine != null) keys.add(mine);
      continue;
    }
    var key = mine ?? _sampled(own, f);
    keys.add(key.copyWith(dx: shift.dx, dy: shift.dy));
  }
  return ElementTrack(keys);
}

/// _sampled is a key on [frame] holding what [own] plays there besides a
/// place, eased straight to the next: one of a run of keys a frame apart,
/// which plays as [own] did on every frame.
Keyframe _sampled(ElementTrack own, int frame) {
  if (own.isEmpty) return Keyframe(frame: frame);
  var p = own.at(frame);
  return Keyframe(
      frame: frame,
      scale: p.scale,
      rotate: p.rotate,
      opacity: p.opacity,
      values: p.values);
}

/// ownTrack is [track] with a bake taken back off: the follower's own keys,
/// with no place. The keys kept are the fewest that play as all of them do
/// in everything but place, so every key a bake added (each lies on the
/// way between the follower's own) goes. A key that holds nothing but a
/// place goes too, whoever keyed it: a place keyed by hand and a place
/// baked over it cannot be told apart, and the bake wrote over that place.
/// Where nothing is left but rest, no keys at all.
ElementTrack ownTrack(ElementTrack? track) {
  var keys = track?.keys ?? const <Keyframe>[];
  if (keys.isEmpty) return ElementTrack.empty;

  // From each key kept, the furthest key that every key between lies on
  // the way to, eased as the kept one eases: the next one kept.
  var kept = [keys.first];
  var held = <String, double>{...keys.first.values};
  var i = 0;
  while (i < keys.length - 1) {
    var next = i + 1;
    for (var j = keys.length - 1; j > i + 1; j--) {
      if (_between(keys, i, j, held)) {
        next = j;
        break;
      }
    }
    kept.add(keys[next]);
    held.addAll(keys[next].values);
    i = next;
  }
  // A key at the start the next one holds back to, and at the end one
  // that only holds what came before, play as nothing.
  while (kept.length > 1 && _sameAs(kept[0], kept[1], kept[1].values)) {
    kept.removeAt(0);
  }
  while (kept.length > 1) {
    var before = <String, double>{};
    for (var k in kept.take(kept.length - 1)) {
      before.addAll(k.values);
    }
    if (!_sameAs(kept.last, kept[kept.length - 2], before)) break;
    kept.removeLast();
  }

  var placeless = [for (var k in kept) k.copyWith(dx: 0, dy: 0)];
  if (placeless.every((k) => k.isRest)) return ElementTrack.empty;
  return ElementTrack(placeless);
}

/// _between is whether every key strictly between [keys]'s [i] and [j]
/// plays, in all but place, as the way from one to the other gives it, with
/// [held], the channels held from before [i].
bool _between(List<Keyframe> keys, int i, int j, Map<String, double> held) {
  var a = keys[i], b = keys[j];
  var span = b.frame - a.frame;
  if (span <= 0) return false;
  for (var m = i + 1; m < j; m++) {
    var way = a.lerp(b, a.ease((keys[m].frame - a.frame) / span));
    if (!_sameAs(keys[m], way, {...held, ...way.values})) return false;
  }
  return true;
}

/// _sameAs is whether [k] plays as [as] does, in all but place, with
/// [values] as the channels [as] gives.
bool _sameAs(Keyframe k, Keyframe as, Map<String, double> values) {
  bool near(double x, double y) => (x - y).abs() <= 1e-9 * (1 + x.abs());
  if (!near(k.scale, as.scale) ||
      !near(k.rotate, as.rotate) ||
      !near(k.opacity, as.opacity) ||
      k.values.length != values.length) {
    return false;
  }
  for (var e in k.values.entries) {
    var v = values[e.key];
    if (v == null || !near(e.value, v)) return false;
  }
  return true;
}

/// PathElement is a stroke along a bezier curve through its nodes. Its
/// stroke is a StrokedElement's: yellow, 3 wide, round, with an arrow at its
/// end.
class PathElement extends StrokedElement {
  final List<PathNode> nodes;

  final bool closed;

  /// guide draws the curve only while editing, never published; on once a
  /// follower is attached, since a path without one is a drawing.
  final bool guide;

  final PathFollow? follow;

  final ElementAnimation animation;

  const PathElement(
    super.base, {
    this.nodes = const [],
    super.color = const Color(0xFFFFD166),
    super.fade,
    super.strokeWidth = 3,
    super.cap = LineStrokeCap.round,
    super.startEnd = LineEnd.none,
    super.endEnd = LineEnd.arrow,
    super.endSize = 1,
    super.dash = 0,
    this.closed = false,
    this.guide = false,
    this.follow,
    this.animation = const ElementAnimation(),
  });

  PathElement._of(
    super.base,
    super.stroke, {
    required this.nodes,
    required this.closed,
    required this.guide,
    required this.follow,
    required this.animation,
  }) : super.of();

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = PathElement(ElementBase(id: ""));

  @override
  ElementKind get kind => ElementKind.path;

  /// pointOf is where [node] is in the box as it is drawn before its turn
  /// and slant (the space [curve] is in); gripOnPage is where it, or a
  /// handle of it, is on the page.
  Offset pointOf(PathNode node) =>
      Offset(x + node.x * width, y + node.y * height);

  Offset _inBox(Offset fractional) =>
      Offset(x + fractional.dx * width, y + fractional.dy * height);

  /// gripOnPage is where [grip] of [node] is drawn on the page: through the
  /// element's turn and slant, as the curve is.
  Offset gripOnPage(PathNode node, PathGrip grip) =>
      onPage(_inBox(node.gripOf(grip)));

  /// fractionAt is [page], a point on the page, as a fraction of the box,
  /// which is what a node keeps: the way back from [gripOnPage], for a
  /// point or a handle dragged there. A box with no width or height is
  /// taken as one unit across, so the fraction stays finite.
  Offset fractionAt(Offset page) {
    var p = fromPage(page);
    var w = width == 0 ? 1.0 : width;
    var h = height == 0 ? 1.0 : height;
    return Offset((p.dx - x) / w, (p.dy - y) / h);
  }

  /// firstFrame and lastFrame are when the follower sets off and arrives.
  int get firstFrame => nodes.isEmpty ? 0 : nodes.first.frame;
  int get lastFrame => nodes.isEmpty ? 0 : nodes.last.frame;

  /// segments is the curve pieces: nodes less one, or one each if closed.
  int get segments =>
      nodes.length < 2 ? 0 : (closed ? nodes.length : nodes.length - 1);

  /// segment is the curve piece after node [index] (the last back to the
  /// first, on a closed path), in the box as it is drawn before its turn and
  /// slant. Asked only of a path with two nodes or more.
  CubicSegment segment(int index) {
    var a = nodes[index % nodes.length];
    var b = nodes[(index + 1) % nodes.length];
    // A node with no handle gives a straight side, which is what a path
    // drawn by clicking rather than dragging should be: its handle is its
    // point.
    return CubicSegment(
        pointOf(a), _inBox(a.outHandle), _inBox(b.inHandle), pointOf(b));
  }

  @override
  Path get curve {
    var path = Path();
    if (nodes.length < 2) return path;
    var start = pointOf(nodes.first);
    path.moveTo(start.dx, start.dy);
    for (var i = 0; i < segments; i++) {
      var s = segment(i);
      path.cubicTo(s.c1.dx, s.c1.dy, s.c2.dx, s.c2.dy, s.p3.dx, s.p3.dy);
    }
    if (closed) path.close();
    return path;
  }

  @override
  List<Offset> get curvePoints => [
        for (var i = 0; i < segments; i++)
          ...segment(i).points().skip(i == 0 ? 0 : 1),
      ];

  /// positionAtFrame is where a follower is on [frame], on the page: along
  /// each segment by distance, holding at the nearer end before the first
  /// node and after the last.
  Offset? positionAtFrame(int frame) {
    var inBox = _positionInBox(frame);
    return inBox == null ? null : onPage(inBox);
  }

  Offset? _positionInBox(int frame) {
    if (nodes.isEmpty) return null;
    if (nodes.length == 1) return pointOf(nodes.first);
    if (frame <= nodes.first.frame) return pointOf(nodes.first);
    if (frame >= nodes.last.frame) return pointOf(nodes.last);

    for (var i = 0; i < nodes.length - 1; i++) {
      var a = nodes[i], b = nodes[i + 1];
      if (frame < a.frame || frame > b.frame) continue;
      var span = b.frame - a.frame;
      if (span <= 0) return pointOf(b);
      return segment(i).along((frame - a.frame) / span);
    }
    return pointOf(nodes.last);
  }

  /// spreadFrames retimes every node evenly between [from] and [to]: the
  /// "even timing" button, and what a freshly drawn path gets.
  PathElement spreadFrames(int from, int to) {
    if (nodes.length < 2) return this;
    var span = to - from;
    return copyWith(nodes: [
      for (var i = 0; i < nodes.length; i++)
        nodes[i]
            .copyWith(frame: from + (span * i / (nodes.length - 1)).round()),
    ]);
  }

  /// withNode replaces one node, keeping the frames in order: clamped between
  /// its neighbours, not sorted, since sorting would reorder the curve.
  PathElement withNode(int index, PathNode node) {
    if (index < 0 || index >= nodes.length) return this;
    var lower = index == 0 ? 0 : nodes[index - 1].frame;
    var upper = index == nodes.length - 1 ? 1 << 30 : nodes[index + 1].frame;
    var next = [...nodes];
    next[index] = node.copyWith(frame: node.frame.clamp(lower, upper));
    return copyWith(nodes: next);
  }

  /// insertAfter splits the segment after [index] without changing the
  /// curve: de Casteljau gives two cubics exactly the original.
  PathElement insertAfter(int index, {int maxFrame = 1 << 30}) {
    if (index < 0 || index >= nodes.length - 1) return this;
    var a = nodes[index];
    var b = nodes[index + 1];

    // In the element's own fractional space, which is what the nodes store.
    var (before, after) =
        CubicSegment(a.point, a.outHandle, b.inHandle, b.point).split(0.5);
    var mid = before.p3;

    var frame = (a.frame + b.frame) ~/ 2;
    var made = PathNode(
      x: mid.dx,
      y: mid.dy,
      inDx: before.c2.dx - mid.dx,
      inDy: before.c2.dy - mid.dy,
      outDx: after.c1.dx - mid.dx,
      outDy: after.c1.dy - mid.dy,
      frame: frame,
    );

    var next = [...nodes];
    next[index] =
        a.copyWith(outDx: before.c1.dx - a.x, outDy: before.c1.dy - a.y);
    next[index + 1] =
        b.copyWith(inDx: after.c2.dx - b.x, inDy: after.c2.dy - b.y);
    next.insert(index + 1, made);
    // Two neighbours a single frame apart leave no whole frame between them,
    // so the halved frame lands on one of them.
    return copyWith(nodes: next).withDistinctFrames(maxFrame: maxFrame);
  }

  /// withDistinctFrames gives every point its own frame (two sharing one
  /// put the follower in two places), re-spacing the whole run.
  PathElement withDistinctFrames({int maxFrame = 1 << 30}) {
    if (nodes.length < 2) return this;

    var collides = false;
    for (var i = 1; i < nodes.length; i++) {
      if (nodes[i].frame <= nodes[i - 1].frame) collides = true;
    }
    if (!collides) return this;

    // Keep the span where it is wide enough; otherwise stretch it, backwards
    // from the end if it already finishes on the last frame.
    var needed = nodes.length - 1;
    var to = math.min(maxFrame, math.max(lastFrame, firstFrame + needed));
    var from = math.max(0, math.min(firstFrame, to - needed));
    return spreadFrames(from, to);
  }

  /// appendNode carries the path on past its end, the way it was going.
  PathElement appendNode({int maxFrame = 1 << 30}) {
    if (nodes.isEmpty) {
      return copyWith(nodes: const [PathNode(x: 0.5, y: 0.5, frame: 0)]);
    }
    var last = nodes.last;
    var previous = nodes.length > 1 ? nodes[nodes.length - 2] : null;
    var direction = previous == null
        ? const Offset(0.25, 0)
        : Offset(last.x - previous.x, last.y - previous.y);
    if (direction.distance < 0.01) direction = const Offset(0.25, 0);

    var gap = nodes.length > 1
        ? math.max(1, last.frame - nodes[nodes.length - 2].frame)
        : 6;
    return copyWith(nodes: [
      ...nodes,
      PathNode(
        x: last.x + direction.dx,
        y: last.y + direction.dy,
        frame: math.min(maxFrame, last.frame + gap),
      ),
      // Clamped to the last frame, the new point can land on the old end;
      // withDistinctFrames spreads them apart.
    ]).withDistinctFrames(maxFrame: maxFrame);
  }

  /// insertAtFrame adds a point at [frame], splitting whichever segment spans
  /// it without changing its shape (see [insertAfter]).
  PathElement insertAtFrame(int frame) {
    for (var i = 0; i < nodes.length - 1; i++) {
      if (frame <= nodes[i].frame || frame >= nodes[i + 1].frame) continue;
      return insertAfter(i).retimeNode(i + 1, frame);
    }
    return this;
  }

  /// nodeIndexAtFrame is which point sits exactly on [frame], if any.
  int? nodeIndexAtFrame(int frame) {
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].frame == frame) return i;
    }
    return null;
  }

  /// retimeNode moves one point along the timeline, keeping the order.
  PathElement retimeNode(int index, int frame) {
    if (index < 0 || index >= nodes.length) return this;
    return withNode(index, nodes[index].copyWith(frame: frame));
  }

  PathElement withoutNode(int index) {
    if (index < 0 || index >= nodes.length || nodes.length <= 2) return this;
    return copyWith(nodes: [...nodes]..removeAt(index));
  }

  @override
  CanvasElement rebase(ElementBase base) => _with(base, stroke);

  @override
  PathElement withStroke(StrokeSpec stroke) => _with(base, stroke);

  /// drawnStroke has no ends on a closed path, which has none to put them
  /// on.
  @override
  StrokeSpec get drawnStroke => closed
      ? stroke.copyWith(startEnd: LineEnd.none, endEnd: LineEnd.none)
      : stroke;

  PathElement _with(ElementBase base, StrokeSpec stroke) =>
      PathElement._of(base, stroke,
          nodes: nodes,
          closed: closed,
          guide: guide,
          follow: follow,
          animation: animation);

  PathElement copyWith({
    List<PathNode>? nodes,
    Color? color,
    GradientSpec? fade,
    bool flat = false,
    double? strokeWidth,
    LineStrokeCap? cap,
    LineEnd? startEnd,
    LineEnd? endEnd,
    double? endSize,
    double? dash,
    bool? closed,
    bool? guide,
    PathFollow? follow,
    bool clearFollow = false,
    ElementAnimation? animation,
  }) =>
      PathElement._of(
          base,
          stroke.copyWith(
              color: color,
              fade: fade,
              flat: flat,
              strokeWidth: strokeWidth,
              cap: cap,
              startEnd: startEnd,
              endEnd: endEnd,
              endSize: endSize,
              dash: dash),
          nodes: nodes ?? this.nodes,
          closed: closed ?? this.closed,
          guide: guide ?? this.guide,
          follow: clearFollow ? null : (follow ?? this.follow),
          animation: animation ?? this.animation);

  @override
  PathElement mapOwnColours(ColourMap f) {
    var p = ColourPass(f);
    var stroke = p.part(this.stroke, (s) => s.mapColours(f));
    var animation = p.part(this.animation, (a) => a.mapColours(f));
    if (!p.changed) return this;
    return PathElement._of(base, stroke,
        nodes: nodes,
        closed: closed,
        guide: guide,
        follow: follow,
        animation: animation);
  }

  @override
  Map<String, dynamic> props() => {
        "nodes": [for (var n in nodes) n.toJson()],
        ...stroke.toJson(_defaults.stroke),
        if (closed) "closed": true,
        if (guide) "guide": true,
        if (follow != null) "follow": follow!.toJson(),
        if (animation.any) "anim": animation.toJson(),
      };

  factory PathElement.fromJson(Map<String, dynamic> json, ElementBase b) {
    var followJson = json["follow"];
    return PathElement._of(b, StrokeSpec.fromJson(json, _defaults.stroke),
        nodes:
            jsonObjects(json["nodes"], PathNode.fromJson, most: maxPathNodes),
        closed: jsonBool(json["closed"], false),
        guide: jsonBool(json["guide"], false),
        follow: followJson is Map<String, dynamic>
            ? PathFollow.fromJson(followJson)
            : null,
        animation: jsonSpec(
            json["anim"], ElementAnimation.fromJson, _defaults.animation));
  }

  /// defaultNodes is the curve a freshly added path starts as: a shallow arc
  /// across its own box, so it visibly has handles.
  static List<PathNode> defaultNodes({int frames = 24}) => [
        const PathNode(x: 0.05, y: 0.75, outDx: 0.18, outDy: -0.22, frame: 0),
        PathNode(
            x: 0.5,
            y: 0.3,
            inDx: -0.16,
            inDy: 0.06,
            outDx: 0.16,
            outDy: -0.06,
            frame: math.max(1, frames ~/ 2)),
        PathNode(
            x: 0.95,
            y: 0.62,
            inDx: -0.18,
            inDy: -0.2,
            frame: math.max(2, frames - 1)),
      ];
}
