import 'package:bruig/components/paint_spec.dart';
import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';

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

  factory PathNode.fromJson(Map<String, dynamic> json) => PathNode(
        x: jsonDouble(json["x"], 0),
        y: jsonDouble(json["y"], 0),
        inDx: jsonDouble(json["ix"], _defaults.inDx),
        inDy: jsonDouble(json["iy"], _defaults.inDy),
        outDx: jsonDouble(json["ox"], _defaults.outDx),
        outDy: jsonDouble(json["oy"], _defaults.outDy),
        frame: jsonInt(json["f"], _defaults.frame),
      );
}

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

  factory PathFollow.fromJson(Map<String, dynamic> json) => PathFollow(
        elementId: jsonString(json["id"], ""),
        playerIndex:
            json["player"] is num ? (json["player"] as num).toInt() : null,
      );
}

class PathElement extends CanvasElement {
  final List<PathNode> nodes;

  final Color color;

  /// fade is the stroke's second colour, or null (see GradientSpec).
  final GradientSpec? fade;
  final double strokeWidth;

  /// cap, startEnd and endEnd finish the stroke, as on a line.
  final LineStrokeCap cap;
  final LineEnd startEnd;
  final LineEnd endEnd;

  /// endSize scales whatever is drawn at the ends. See LineElement.endSize.
  final double endSize;

  /// dash is the on/off length in design units. Zero draws a solid line.
  final double dash;

  final bool closed;

  /// guide draws the curve only while editing, never published; on once a
  /// follower is attached, since a path without one is a drawing.
  final bool guide;

  final PathFollow? follow;

  final ElementAnimation animation;

  const PathElement(
    super.base, {
    this.nodes = const [],
    this.color = const Color(0xFFFFD166),
    this.fade,
    this.strokeWidth = 3,
    this.cap = LineStrokeCap.round,
    this.startEnd = LineEnd.none,
    this.endEnd = LineEnd.arrow,
    this.endSize = 1,
    this.dash = 0,
    this.closed = false,
    this.guide = false,
    this.follow,
    this.animation = const ElementAnimation(),
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = PathElement(ElementBase(id: ""));

  @override
  ElementKind get kind => ElementKind.path;

  Offset pointOf(PathNode node) =>
      Offset(x + node.x * width, y + node.y * height);

  Offset _scaled(Offset fractional) =>
      Offset(x + fractional.dx * width, y + fractional.dy * height);

  Offset inHandleOf(PathNode node) => _scaled(node.inHandle);
  Offset outHandleOf(PathNode node) => _scaled(node.outHandle);

  /// firstFrame and lastFrame are when the follower sets off and arrives.
  int get firstFrame => nodes.isEmpty ? 0 : nodes.first.frame;
  int get lastFrame => nodes.isEmpty ? 0 : nodes.last.frame;

  /// segments is the curve pieces: nodes less one, or one each if closed.
  int get segments =>
      nodes.length < 2 ? 0 : (closed ? nodes.length : nodes.length - 1);

  /// pointOnSegment is one cubic piece at [t], in document coordinates.
  Offset pointOnSegment(int index, double t) {
    if (nodes.length < 2) {
      return nodes.isEmpty ? center : pointOf(nodes.first);
    }
    var a = nodes[index % nodes.length];
    var b = nodes[(index + 1) % nodes.length];

    var p0 = pointOf(a);
    var p3 = pointOf(b);
    // A node with no handles gives a straight segment, which is what a path
    // drawn by clicking rather than dragging should be.
    var p1 = a.outDx == 0 && a.outDy == 0 ? p0 : outHandleOf(a);
    var p2 = b.inDx == 0 && b.inDy == 0 ? p3 : inHandleOf(b);

    var u = 1 - t;
    return Offset(
      u * u * u * p0.dx +
          3 * u * u * t * p1.dx +
          3 * u * t * t * p2.dx +
          t * t * t * p3.dx,
      u * u * u * p0.dy +
          3 * u * u * t * p1.dy +
          3 * u * t * t * p2.dy +
          t * t * t * p3.dy,
    );
  }

  /// _arcSamples is how finely a segment is measured when turning a time into
  /// a distance: well under a pixel of error, and cheap enough to bake a path.
  static const int _arcSamples = 16;

  /// positionOnSegment is [t] along a segment *by distance*: the curve's
  /// own parameter runs slow round a bend, slowing a follower there.
  Offset positionOnSegment(int index, double t) {
    if (t <= 0) return pointOnSegment(index, 0);
    if (t >= 1) return pointOnSegment(index, 1);

    var lengths = <double>[0];
    var previous = pointOnSegment(index, 0);
    var total = 0.0;
    for (var i = 1; i <= _arcSamples; i++) {
      var at = pointOnSegment(index, i / _arcSamples);
      total += (at - previous).distance;
      lengths.add(total);
      previous = at;
    }
    if (total <= 0) return previous;

    var wanted = t * total;
    for (var i = 1; i < lengths.length; i++) {
      if (lengths[i] < wanted) continue;
      var span = lengths[i] - lengths[i - 1];
      var within = span <= 0 ? 0.0 : (wanted - lengths[i - 1]) / span;
      return pointOnSegment(index, (i - 1 + within) / _arcSamples);
    }
    return pointOnSegment(index, 1);
  }

  /// positionAtFrame is where a follower is on [frame], holding at the nearer
  /// end before the first node and after the last.
  Offset? positionAtFrame(int frame) {
    if (nodes.isEmpty) return null;
    if (nodes.length == 1) return pointOf(nodes.first);
    if (frame <= nodes.first.frame) return pointOf(nodes.first);
    if (frame >= nodes.last.frame) return pointOf(nodes.last);

    for (var i = 0; i < nodes.length - 1; i++) {
      var a = nodes[i], b = nodes[i + 1];
      if (frame < a.frame || frame > b.frame) continue;
      var span = b.frame - a.frame;
      if (span <= 0) return pointOf(b);
      return positionOnSegment(i, (frame - a.frame) / span);
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

    Offset lerp(Offset p, Offset q) =>
        Offset((p.dx + q.dx) / 2, (p.dy + q.dy) / 2);

    // In the element's own fractional space, which is what the nodes store.
    var p0 = a.point;
    var p1 = (a.outDx == 0 && a.outDy == 0) ? a.point : a.outHandle;
    var p2 = (b.inDx == 0 && b.inDy == 0) ? b.point : b.inHandle;
    var p3 = b.point;

    var q0 = lerp(p0, p1);
    var q1 = lerp(p1, p2);
    var q2 = lerp(p2, p3);
    var r0 = lerp(q0, q1);
    var r1 = lerp(q1, q2);
    var mid = lerp(r0, r1);

    var frame = (a.frame + b.frame) ~/ 2;
    var made = PathNode(
      x: mid.dx,
      y: mid.dy,
      inDx: r0.dx - mid.dx,
      inDy: r0.dy - mid.dy,
      outDx: r1.dx - mid.dx,
      outDy: r1.dy - mid.dy,
      frame: frame,
    );

    var next = [...nodes];
    next[index] = a.copyWith(outDx: q0.dx - a.x, outDy: q0.dy - a.y);
    next[index + 1] = b.copyWith(inDx: q2.dx - b.x, inDy: q2.dy - b.y);
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
  CanvasElement rebase(ElementBase base) => PathElement(base,
      nodes: nodes,
      color: color,
      fade: fade,
      strokeWidth: strokeWidth,
      cap: cap,
      startEnd: startEnd,
      endEnd: endEnd,
      endSize: endSize,
      dash: dash,
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
      PathElement(base,
          nodes: nodes ?? this.nodes,
          color: color ?? this.color,
          fade: flat ? null : (fade ?? this.fade),
          strokeWidth: strokeWidth ?? this.strokeWidth,
          cap: cap ?? this.cap,
          startEnd: startEnd ?? this.startEnd,
          endEnd: endEnd ?? this.endEnd,
          endSize: endSize ?? this.endSize,
          dash: dash ?? this.dash,
          closed: closed ?? this.closed,
          guide: guide ?? this.guide,
          follow: clearFollow ? null : (follow ?? this.follow),
          animation: animation ?? this.animation);

  @override
  Map<String, dynamic> props() => {
        "nodes": [for (var n in nodes) n.toJson()],
        "color": colorToJson(color),
        if (fade != null) "fade": fade!.toJson(),
        "sw": strokeWidth,
        "strokeCap": cap.name,
        if (startEnd != _defaults.startEnd) "startEnd": startEnd.name,
        if (endEnd != _defaults.endEnd) "endEnd": endEnd.name,
        if (endSize != _defaults.endSize) "endSize": endSize,
        if (dash > 0) "dash": dash,
        if (closed) "closed": true,
        if (guide) "guide": true,
        if (follow != null) "follow": follow!.toJson(),
        if (animation.any) "anim": animation.toJson(),
      };

  factory PathElement.fromJson(Map<String, dynamic> json, ElementBase b) {
    var raw = json["nodes"];
    var followJson = json["follow"];
    return PathElement(b,
        nodes: [
          if (raw is List)
            for (var n in raw)
              if (n is Map<String, dynamic>) PathNode.fromJson(n),
        ],
        color: colorFromJson(json["color"], _defaults.color),
        fade: json["fade"] is Map
            ? GradientSpec.fromJson(
                (json["fade"] as Map).cast<String, dynamic>())
            : null,
        strokeWidth: jsonDouble(json["sw"], _defaults.strokeWidth),
        cap: json["strokeCap"] is String
            ? LineStrokeCap.fromName(jsonStr(json["strokeCap"]))
            : LineStrokeCap.round,
        startEnd: LineEnd.fromName(jsonStr(json["startEnd"])),
        endSize: jsonDouble(json["endSize"], _defaults.endSize),
        // The writer leaves the end out when it is the arrow a path starts
        // with, so no "endEnd" is an arrow.
        endEnd: json.containsKey("endEnd")
            ? LineEnd.fromName(jsonStr(json["endEnd"]))
            : LineEnd.arrow,
        dash: jsonDouble(json["dash"], _defaults.dash).clamp(0.0, 200.0),
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
