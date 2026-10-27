import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_life.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_painter.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/render/vector_painter.dart';

// character_parts.dart is where each part of a sketched character's body is
// on the page as the rig has it -- a frame for each: a root, the way down
// the bone, and a size -- for the shapes drawn on it by hand to be kept in
// the part's own measure and drawn wherever the pose puts it. See
// character_drawing.dart.

/// PartFrame is a part's measure on the page: [origin] its root, [along]
/// the way down it, and [scale] how big a unit of it is.
class PartFrame {
  final Offset origin;
  final Offset along;
  final double scale;
  const PartFrame(this.origin, this.along, this.scale);

  /// across is square to [along]: what the other measure runs along.
  Offset get across => Offset(-along.dy, along.dx);

  Offset toPage(double a, double b) =>
      origin + along * (a * scale) + across * (b * scale);

  (double, double) toLocal(Offset p) {
    var d = p - origin;
    var s = scale == 0 ? 1.0 : scale;
    return (
      (d.dx * along.dx + d.dy * along.dy) / s,
      (d.dx * across.dx + d.dy * across.dy) / s,
    );
  }
}

Offset _unit(Offset d, [Offset otherwise = const Offset(0, 1)]) {
  var l = d.distance;
  return l < 1e-9 ? otherwise : d / l;
}

/// partFrames is every part's frame as [rig] has the body.
Map<CharacterPart, PartFrame> partFrames(CharacterRig rig) {
  var u = rig.unit;
  var down = const Offset(0, 1);
  var turn = rig.headTurn * math.pi / 180;
  // Down the face, as the head is tipped.
  var face = Offset(-math.sin(turn), math.cos(turn));
  PartFrame bone(Offset from, Offset to) =>
      PartFrame(from, _unit(to - from), u);
  var frames = <CharacterPart, PartFrame>{
    CharacterPart.head: PartFrame(rig.headCentre, face, u * rig.headScale),
    CharacterPart.torso: bone(rig.chest, rig.hips),
  };
  for (var (limb, upper, lower, end) in [
    (
      CharacterLimb.armL,
      CharacterPart.upperArmL,
      CharacterPart.foreArmL,
      CharacterPart.handL
    ),
    (
      CharacterLimb.armR,
      CharacterPart.upperArmR,
      CharacterPart.foreArmR,
      CharacterPart.handR
    ),
    (
      CharacterLimb.legL,
      CharacterPart.thighL,
      CharacterPart.shinL,
      CharacterPart.footL
    ),
    (
      CharacterLimb.legR,
      CharacterPart.thighR,
      CharacterPart.shinR,
      CharacterPart.footR
    ),
  ]) {
    var a = rig.root(limb), b = rig.middle(limb), c = rig.end(limb);
    frames[upper] = bone(a, b);
    frames[lower] = bone(b, c);
    // A hand goes on the way the forearm points; a foot keeps to the floor.
    frames[end] =
        limb.isArm ? PartFrame(c, _unit(c - b), u) : PartFrame(c, down, u);
  }
  return frames;
}

double _toSegment(Offset p, Offset a, Offset b) {
  var ab = b - a;
  var len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 < 1e-9) return (p - a).distance;
  var t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// partAt is the part of the body [rig] has nearest [p] -- what a shape
/// drawn there is drawn on.
CharacterPart partAt(CharacterRig rig, Offset p) {
  var best = CharacterPart.torso;
  var bestD = double.infinity;
  void consider(CharacterPart part, double d) {
    if (d < bestD) {
      bestD = d;
      best = part;
    }
  }

  var r = rig.headRadii;
  var h = rig.headScale;
  consider(CharacterPart.head,
      (p - rig.headCentre).distance - math.max(r.width, r.height) * h);
  consider(CharacterPart.torso,
      _toSegment(p, rig.chest, rig.hips) - rig.shoulderHalf * 0.8);
  for (var (limb, upper, lower, end) in [
    (
      CharacterLimb.armL,
      CharacterPart.upperArmL,
      CharacterPart.foreArmL,
      CharacterPart.handL
    ),
    (
      CharacterLimb.armR,
      CharacterPart.upperArmR,
      CharacterPart.foreArmR,
      CharacterPart.handR
    ),
    (
      CharacterLimb.legL,
      CharacterPart.thighL,
      CharacterPart.shinL,
      CharacterPart.footL
    ),
    (
      CharacterLimb.legR,
      CharacterPart.thighR,
      CharacterPart.shinR,
      CharacterPart.footR
    ),
  ]) {
    var a = rig.root(limb), b = rig.middle(limb), c = rig.end(limb);
    var half = (limb.isArm ? rig.limbWidth : rig.legWidth) / 2;
    consider(upper, _toSegment(p, a, b) - half);
    consider(lower, _toSegment(p, b, c) - half * 0.8);
    var reach = limb.isArm ? rig.handRadius * 2 : rig.legWidth * 1.4;
    var tip =
        limb.isArm ? c + _unit(c - b) * reach : c + Offset(0, reach * 0.5);
    consider(end, _toSegment(p, c, tip) - half * 0.7);
  }
  return best;
}

/// shapeCentre is the middle of [shape]'s points: what decides its part.
Offset shapeCentre(VectorShape shape) {
  var sum = Offset.zero;
  var n = 0;
  for (var path in shape.paths) {
    for (var node in path.nodes) {
      sum += node.point;
      n++;
    }
  }
  return n == 0 ? Offset.zero : sum / n.toDouble();
}

/// drawingOnPage is [drawing]'s shapes on the page, each where [frames] put
/// its part.
List<VectorShape> drawingOnPage(
        CharacterDrawing drawing, Map<CharacterPart, PartFrame> frames) =>
    [
      for (var (i, shape) in drawing.shapes.indexed)
        if (frames[drawing.parts[i]] case var f?)
          mapShape(shape, (a, b) {
            var p = f.toPage(a, b);
            return (p.dx, p.dy);
          }, f.scale),
    ];

/// shapesOnParts is [shapes] -- on the page -- each put on the part of
/// [rig]'s body it was drawn on, in that part's measure: the reverse of
/// drawingOnPage. [keep] are the parts already known, shape by shape, to
/// keep where there is one; a new shape is put on the part under it.
CharacterDrawing shapesOnParts(List<VectorShape> shapes, CharacterRig rig,
    {List<CharacterPart> keep = const [],
    Set<CharacterRegion> hidden = const {}}) {
  var frames = partFrames(rig);
  var parts = <CharacterPart>[];
  var local = <VectorShape>[];
  for (var (i, shape) in shapes.indexed) {
    var part = i < keep.length ? keep[i] : partAt(rig, shapeCentre(shape));
    var f = frames[part]!;
    parts.add(part);
    local.add(mapShape(shape, (x, y) => f.toLocal(Offset(x, y)),
        1 / (f.scale == 0 ? 1 : f.scale)));
  }
  return CharacterDrawing(shapes: local, parts: parts, hidden: hidden);
}

/// paintDrawing draws what is drawn by hand on the panel, where [rig] has
/// the body, as a drawing element draws its shapes.
void paintDrawing(
    Canvas canvas, CharacterRig rig, CharacterDrawing drawing, Rect room) {
  if (drawing.shapes.isEmpty) return;
  var shapes = drawingOnPage(drawing, partFrames(rig));
  paintVector(
      canvas,
      room,
      VectorElement(
          ElementBase(id: "drawn", width: room.width, height: room.height),
          viewBox: room,
          shapes: shapes),
      null);
}

/// drawnRig is where [e]'s body is on [frame] -- in its own box, from its
/// corner -- as it is drawn there, and the panel it is seen from: what a
/// drawing on it is laid against. See paintCharacter, which it follows.
(CharacterRig, double turn, double tilt) drawnRig(
    CharacterElement e, int frame, int frameRate) {
  frame = e.style.frameOf(frame);
  var (pose, _) = e.performanceAt(frame, frameRate);
  pose = pose.inPanel;
  var box = characterBox(e, frame, Offset.zero & Size(e.width, e.height));
  var rig = CharacterRig.of(e.style.dnaOf(e.dna), pose, box,
      breath: lifeAt(e, frame, frameRate).breath);
  return (rig, pose.panelTurn, pose.panelTilt);
}

/// drawingProxy is the drawing that stands in for [e]'s panel on [frame]
/// while it is drawn on -- see drawingProxyId -- laid exactly over it: the
/// shapes drawn on the panel, where the pose has them, in the character's
/// own box. It draws nothing itself; the character draws what is on it.
VectorElement drawingProxy(CharacterElement e, int frame, int frameRate) {
  var (rig, turn, tilt) = drawnRig(e, frame, frameRate);
  var (drawing, _) = e.drawingFor(turn, tilt);
  return VectorElement(
    // Where the character is, and moved as it is moved.
    e.base.copyWith(
        id: drawingProxyId(e.id),
        name: "Drawing on ${e.name}",
        opacity: 0,
        locked: false),
    viewBox: Rect.fromLTWH(0, 0, e.width, e.height),
    fit: VectorFit.stretch,
    shapes: drawingOnPage(drawing, partFrames(rig)),
  );
}

/// drawnFromProxy is [e] with what is on [proxy] -- see drawingProxy --
/// taken onto the panel it is seen from on [frame]: each shape on the part
/// it is over. [before] is the stand-in as it was, whose shapes, when there
/// are as many, keep the parts they were on; a shape added or taken away
/// puts them all where they now are.
CharacterElement drawnFromProxy(
    CharacterElement e, VectorElement proxy, int frame, int frameRate,
    {VectorElement? before}) {
  var (rig, turn, tilt) = drawnRig(e, frame, frameRate);
  var (old, mirrored) = e.drawingFor(turn, tilt);
  var shapes = proxy.shapes ?? const <VectorShape>[];
  var same = !mirrored &&
      before != null &&
      (before.shapes?.length ?? -1) == shapes.length &&
      old.parts.length == shapes.length;
  var drawing = shapesOnParts(shapes, rig,
      keep: same ? old.parts : const [], hidden: old.hidden);
  return e.withDrawing(turn, tilt, drawing);
}

/// zoomRect is the stretch of the body [rig] has that [zoom] names, in the
/// rig's own measure, with room round it to draw in.
Rect zoomRect(CharacterRig rig, CharacterZoom zoom) {
  var r = rig.headRadii;
  var head = Rect.fromCenter(
      center: rig.headCentre,
      width: r.width * 2 * rig.headScale,
      height: r.height * 2 * rig.headScale);
  Rect round(Iterable<Offset> points, double pad) {
    var list = points.toList();
    var box = Rect.fromPoints(list.first, list.first);
    for (var p in list.skip(1)) {
      box = box.expandToInclude(Rect.fromPoints(p, p));
    }
    return box.inflate(pad);
  }

  var hand = rig.handRadius * 2.4;
  var foot = rig.legWidth * 1.6;
  var feet = [rig.ankleL, rig.ankleR];
  var whole = round([
    rig.shoulderL,
    rig.shoulderR,
    rig.elbowL,
    rig.elbowR,
    rig.wristL,
    rig.wristR,
    rig.hipL,
    rig.hipR,
    rig.kneeL,
    rig.kneeR,
    ...feet,
  ], hand)
      .expandToInclude(head);
  return switch (zoom) {
    CharacterZoom.fullBody => whole.inflate(rig.unit * 0.3),
    CharacterZoom.head => head.inflate(r.width * rig.headScale * 0.5),
    CharacterZoom.headAndChest => head
        .expandToInclude(
            round([rig.shoulderL, rig.shoulderR, rig.chest], rig.unit * 0.3))
        .inflate(rig.unit * 0.2),
    CharacterZoom.upperBody => head.expandToInclude(
        round([rig.shoulderL, rig.shoulderR, rig.hips], rig.unit * 0.4)),
    CharacterZoom.lowerBody =>
      round([rig.hipL, rig.hipR, rig.kneeL, rig.kneeR, ...feet], foot),
    CharacterZoom.hands => round([rig.wristL, rig.wristR], hand),
    CharacterZoom.feet => round(feet, foot),
  };
}

/// PlacedRigPoint is one of a limb's points where the rig puts it: see
/// character_rig_points.dart.
class PlacedRigPoint {
  final RigPoint point;

  /// at is where it is drawn, and on where it would be unmoved: on its bone.
  final Offset at;
  final Offset on;

  /// dir is the way its bone runs.
  final Offset dir;

  /// t is how far down the whole limb it is, root 0 to end 1.
  final double t;
  const PlacedRigPoint(this.point, this.at, this.on, this.dir, this.t);

  Offset get across => Offset(-dir.dy, dir.dx);
}

/// placedRigPoints is [limb]'s points, root to end, where [rig] puts them,
/// as [points] has them changed.
List<PlacedRigPoint> placedRigPoints(CharacterRig rig, CharacterLimb limb, RigPoints points) {
  var a = rig.root(limb), b = rig.middle(limb), c = rig.end(limb);
  var (upper, lower) = rig.lengths(limb);
  var whole = upper + lower;
  var u = rig.unit;
  return [
    for (var p in points.of(limb.name))
      () {
        var (from, to) = p.bone == 0 ? (a, b) : (b, c);
        var dir = _unit(to - from, p.bone == 0 ? _unit(c - b) : _unit(b - a));
        var on = Offset.lerp(from, to, p.f)!;
        var across = Offset(-dir.dy, dir.dx);
        var t = whole == 0 ? 0.0 : (p.bone == 0 ? p.f * upper : upper + p.f * lower) / whole;
        return PlacedRigPoint(p, on + dir * (p.along * u) + across * (p.across * u), on, dir, t);
      }(),
  ];
}

/// rigPointFor is the point a limb would have at [page] -- a click on its
/// line -- unmoved: on the bone nearest, how far along it.
RigPoint rigPointFor(CharacterRig rig, CharacterLimb limb, RigPoints points, Offset page) {
  var placed = placedRigPoints(rig, limb, points);
  var best = (0, 0.5);
  var bestD = double.infinity;
  for (var i = 0; i + 1 < placed.length; i++) {
    var p = placed[i], q = placed[i + 1];
    var ab = q.at - p.at;
    var len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    var k = len2 < 1e-9
        ? 0.0
        : (((page - p.at).dx * ab.dx + (page - p.at).dy * ab.dy) / len2).clamp(0.0, 1.0);
    var d = (page - (p.at + ab * k)).distance;
    if (d < bestD) {
      bestD = d;
      // Along the limb, between the two -- on the bone they share, or
      // across the joint between.
      var order = p.point.order + (q.point.order - p.point.order) * k;
      var bone = order >= 1 ? 1 : 0;
      best = (bone, (order - bone).clamp(0.02, 0.98));
    }
  }
  return RigPoint(best.$1, best.$2);
}
