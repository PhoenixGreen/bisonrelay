import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';

// path_element.dart is a bezier curve, and optionally the route something
// takes along it.
//
// Two jobs in one element, and they are the same job. A curve drawn on a
// tactics board is a run; a curve drawn on a diagram is an arrow. What makes
// it a *motion* path is that a follower is named, and the timing of each node
// is written down -- and then the shape and the movement are the same thing,
// edited in one place. Drawing the route and animating the player separately
// is how the two end up disagreeing.
//
// The movement is not evaluated live at paint time. It is baked into the
// follower's own keyframes (see CanvasController.applyPathFollow), which is
// what lets the exporter, the GIF encoder and a published interactive canvas
// replay a path without any of them knowing what a path is.

/// PathNode is one point on the curve, with the handles that shape the
/// segments either side of it.
///
/// The point and both handles are fractions of the element's box, exactly as a
/// player's position is, so moving or resizing the element takes the whole
/// curve with it rather than leaving the handles behind.
class PathNode {
  /// x and y are 0..1 within the element's box.
  final double x;
  final double y;

  /// inDx/inDy and outDx/outDy are the control handles, as offsets from the
  /// point itself in the same fractional units.
  ///
  /// Two handles rather than one mirrored pair, because a run that arrives
  /// along the touchline and leaves square across the box has a corner in it,
  /// and a curve that cannot have a corner cannot draw that.
  final double inDx;
  final double inDy;
  final double outDx;
  final double outDy;

  /// frame is when the follower reaches this node.
  ///
  /// On the node rather than in a separate list, because retiming a node and
  /// moving it are the same edit as far as the reader is concerned -- and two
  /// lists that have to stay the same length is a bug waiting for somebody to
  /// delete a point.
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

  /// withMirroredHandle moves one handle and swings the other to match, which
  /// is what keeps a curve smooth through a node.
  ///
  /// Held down, it is the ordinary behaviour of every pen tool there is; the
  /// corner case above is the exception, reached by moving a handle on its
  /// own.
  PathNode withMirroredHandle({required bool out, required Offset to}) {
    var d = to - point;
    return out
        ? copyWith(outDx: d.dx, outDy: d.dy, inDx: -d.dx, inDy: -d.dy)
        : copyWith(inDx: d.dx, inDy: d.dy, outDx: -d.dx, outDy: -d.dy);
  }

  Map<String, dynamic> toJson() => {
        "x": x,
        "y": y,
        if (inDx != 0) "ix": inDx,
        if (inDy != 0) "iy": inDy,
        if (outDx != 0) "ox": outDx,
        if (outDy != 0) "oy": outDy,
        "f": frame,
      };

  factory PathNode.fromJson(Map<String, dynamic> json) => PathNode(
        x: jsonDouble(json["x"], 0),
        y: jsonDouble(json["y"], 0),
        inDx: jsonDouble(json["ix"], 0),
        inDy: jsonDouble(json["iy"], 0),
        outDx: jsonDouble(json["ox"], 0),
        outDy: jsonDouble(json["oy"], 0),
        frame: jsonInt(json["f"], 0),
      );
}

/// PathFollow names what travels along the curve.
///
/// An element, or one player inside a team -- the second is why this is not
/// just an element id. A player is not an element and has no id of its own, so
/// a follower is addressed the same way the timeline addresses one: the team's
/// id and the row's index.
class PathFollow {
  final String elementId;

  /// playerIndex is set when the follower is a player of a team, and null when
  /// it is the element itself.
  final int? playerIndex;

  const PathFollow({required this.elementId, this.playerIndex});

  Map<String, dynamic> toJson() => {
        "id": elementId,
        if (playerIndex != null) "player": playerIndex,
      };

  factory PathFollow.fromJson(Map<String, dynamic> json) => PathFollow(
        elementId: jsonString(json["id"], ""),
        playerIndex: json["player"] is num ? (json["player"] as num).toInt() : null,
      );
}

/// PathElement is the curve.
class PathElement extends CanvasElement {
  final List<PathNode> nodes;

  final Color color;
  final double strokeWidth;
  final LineCapStyle cap;

  /// dash is the on/off length in design units. Zero draws a solid line.
  final double dash;

  final bool closed;

  /// guide draws the curve only while it is being edited, and leaves it out of
  /// anything published.
  ///
  /// On by default whenever the path has a follower, and that is the common
  /// case: the line showing where a player runs is scaffolding, and a diagram
  /// with every run drawn permanently on it is unreadable. A path with no
  /// follower is a drawing and shows.
  final bool guide;

  final PathFollow? follow;

  const PathElement(
    super.base, {
    this.nodes = const [],
    this.color = const Color(0xFFFFD166),
    this.strokeWidth = 3,
    this.cap = LineCapStyle.arrow,
    this.dash = 0,
    this.closed = false,
    this.guide = false,
    this.follow,
  });

  @override
  ElementKind get kind => ElementKind.path;

  /// pointOf maps a node's fractional point into document coordinates.
  Offset pointOf(PathNode node) =>
      Offset(x + node.x * width, y + node.y * height);

  Offset _scaled(Offset fractional) =>
      Offset(x + fractional.dx * width, y + fractional.dy * height);

  Offset inHandleOf(PathNode node) => _scaled(node.inHandle);
  Offset outHandleOf(PathNode node) => _scaled(node.outHandle);

  /// firstFrame and lastFrame are when the follower sets off and arrives.
  int get firstFrame => nodes.isEmpty ? 0 : nodes.first.frame;
  int get lastFrame => nodes.isEmpty ? 0 : nodes.last.frame;

  /// segments is the number of curve pieces: one fewer than the nodes, or one
  /// per node when the path is closed.
  int get segments =>
      nodes.length < 2 ? 0 : (closed ? nodes.length : nodes.length - 1);

  /// pointOnSegment evaluates one cubic piece at [t] in 0..1, in document
  /// coordinates.
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

  /// _arcSamples is how finely a segment is measured when converting a time
  /// into a distance along it.
  ///
  /// Sixteen is enough that the error is well under a pixel on any curve a
  /// hand draws, and small enough that baking a whole path is a few hundred
  /// arithmetic operations rather than a few thousand.
  static const int _arcSamples = 16;

  /// positionOnSegment is [t] of the way along a segment *by distance* rather
  /// than by the curve's own parameter.
  ///
  /// The two are not the same, and the difference is visible: a cubic's
  /// parameter runs fast through the straight part and slow round the bend, so
  /// a player crossing a curved run at a constant parameter appears to slow
  /// down in the turn and speed up out of it. Re-measuring by arc length is
  /// what makes the movement look like somebody running rather than like a
  /// value being interpolated.
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

  /// positionAtFrame is where a follower is on [frame].
  ///
  /// Before the first node and after the last it holds at the end it is
  /// nearest, for the same reason a track does: something that has finished
  /// its run stays where it finished rather than carrying on off the pitch.
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

  /// spreadFrames retimes every node evenly between [from] and [to].
  ///
  /// What the "even timing" button does, and what a freshly drawn path gets:
  /// clicking six points and being asked to type six frame numbers before
  /// anything moves is a tool nobody would use twice.
  PathElement spreadFrames(int from, int to) {
    if (nodes.length < 2) return this;
    var span = to - from;
    return copyWith(nodes: [
      for (var i = 0; i < nodes.length; i++)
        nodes[i].copyWith(
            frame: from + (span * i / (nodes.length - 1)).round()),
    ]);
  }

  /// withNode replaces one node, keeping the frames in order.
  ///
  /// Clamped between its neighbours rather than sorted afterwards, because
  /// sorting would reorder the *curve* -- the follower would visit the points
  /// in a different order from the one they are drawn in, and the line on
  /// screen would stop describing the movement.
  PathElement withNode(int index, PathNode node) {
    if (index < 0 || index >= nodes.length) return this;
    var lower = index == 0 ? 0 : nodes[index - 1].frame;
    var upper = index == nodes.length - 1 ? 1 << 30 : nodes[index + 1].frame;
    var next = [...nodes];
    next[index] = node.copyWith(frame: node.frame.clamp(lower, upper));
    return copyWith(nodes: next);
  }

  PathElement withoutNode(int index) {
    if (index < 0 || index >= nodes.length || nodes.length <= 2) return this;
    return copyWith(nodes: [...nodes]..removeAt(index));
  }

  @override
  CanvasElement rebase(ElementBase base) => PathElement(base,
      nodes: nodes,
      color: color,
      strokeWidth: strokeWidth,
      cap: cap,
      dash: dash,
      closed: closed,
      guide: guide,
      follow: follow);

  PathElement copyWith({
    List<PathNode>? nodes,
    Color? color,
    double? strokeWidth,
    LineCapStyle? cap,
    double? dash,
    bool? closed,
    bool? guide,
    PathFollow? follow,
    bool clearFollow = false,
  }) =>
      PathElement(base,
          nodes: nodes ?? this.nodes,
          color: color ?? this.color,
          strokeWidth: strokeWidth ?? this.strokeWidth,
          cap: cap ?? this.cap,
          dash: dash ?? this.dash,
          closed: closed ?? this.closed,
          guide: guide ?? this.guide,
          follow: clearFollow ? null : (follow ?? this.follow));

  @override
  Map<String, dynamic> props() => {
        "nodes": [for (var n in nodes) n.toJson()],
        "color": colorToJson(color),
        "sw": strokeWidth,
        "cap": cap.name,
        if (dash > 0) "dash": dash,
        if (closed) "closed": true,
        if (guide) "guide": true,
        if (follow != null) "follow": follow!.toJson(),
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
        color: colorFromJson(json["color"], const Color(0xFFFFD166)),
        strokeWidth: jsonDouble(json["sw"], 3),
        cap: LineCapStyle.fromName(json["cap"] as String?),
        dash: jsonDouble(json["dash"], 0),
        closed: jsonBool(json["closed"], false),
        guide: jsonBool(json["guide"], false),
        follow: followJson is Map<String, dynamic>
            ? PathFollow.fromJson(followJson)
            : null);
  }

  /// defaultNodes is the curve a freshly added path starts as: a shallow arc
  /// across its own box, so it is visibly a curve with handles rather than a
  /// straight line somebody has to discover how to bend.
  static List<PathNode> defaultNodes({int frames = 24}) => [
        PathNode(x: 0.05, y: 0.75, outDx: 0.18, outDy: -0.22, frame: 0),
        PathNode(
            x: 0.5,
            y: 0.3,
            inDx: -0.16,
            inDy: 0.06,
            outDx: 0.16,
            outDy: -0.06,
            frame: math.max(1, frames ~/ 2)),
        PathNode(
            x: 0.95, y: 0.62, inDx: -0.18, inDy: -0.2, frame: math.max(2, frames - 1)),
      ];
}
