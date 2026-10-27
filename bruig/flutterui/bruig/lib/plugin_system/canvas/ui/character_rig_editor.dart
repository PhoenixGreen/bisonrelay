import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_parts.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/ui/character_puppet.dart';

// character_rig_editor.dart is a sketch's limbs reshaped on the canvas,
// point by point -- see character_rig_points.dart. Each point has three
// things to take hold of: its middle, which moves it and bends the limb
// there; a ring round it as thick as the limb is there, which makes it
// thicker or thinner, down to nothing; and a knob on the ring, which turns
// its cross-section. A line between two points, taken hold of, has a
// point put there and is bent by it. A point is picked by taking hold of
// it, and Delete takes it away -- a joint put back as it was.

/// RigGrab is what of a point is taken hold of.
enum RigGrab { centre, ring, knob }

/// RigHold is one of a limb's points taken hold of, and what of it.
class RigHold {
  final CharacterLimb limb;
  final RigPoint point;
  final RigGrab grab;

  /// added is whether the point was put there by taking hold of the line.
  final bool added;
  const RigHold(this.limb, this.point, this.grab, {this.added = false});
}

/// rigPointNear is [p] -- one of [placed]'s -- as it is now there.
PlacedRigPoint? _find(List<PlacedRigPoint> placed, RigPoint p) {
  for (var q in placed) {
    if (q.point.sameSpot(p)) return q;
  }
  return null;
}

/// RigView is a sketch's limbs and their points where they are on the page,
/// as the stage shows them for reshaping.
class RigView {
  final CharacterElement element;
  final CharacterPlacement placed;
  final Map<CharacterLimb, List<PlacedRigPoint>> limbs;

  RigView._(this.element, this.placed, this.limbs);

  factory RigView.of(CharacterElement e, int frame,
      {int frameRate = 12, CanvasDocument? document}) {
    var placed = CharacterPlacement.of(e, frame,
        frameRate: frameRate, document: document);
    var dna = e.style.dnaOf(e.dna);
    return RigView._(e, placed, {
      for (var limb in CharacterLimb.values)
        if (!(dna.species.legless && !limb.isArm))
          limb: placedRigPoints(placed.rig, limb, e.dna.rigPoints),
    });
  }

  CharacterRig get rig => placed.rig;

  /// ring is how far round [p] its ring is, in the drawing's own space: as
  /// wide as the limb is there, and never too small to take hold of at
  /// [scale] -- screen pixels to a unit of the page.
  double ring(CharacterLimb limb, PlacedRigPoint p, double scale) {
    var half = (limb.isArm ? rig.limbWidth : rig.legWidth) / 2 * p.point.scale;
    return math.max(half, 12 / scale);
  }

  /// knob is where [p]'s turning knob is, in the drawing's own space: on
  /// its ring, square to the limb, turned as it is.
  Offset knob(CharacterLimb limb, PlacedRigPoint p, double scale) {
    var t = p.point.turn * math.pi / 180;
    var a = p.across;
    var c = math.cos(t), s = math.sin(t);
    return p.at +
        Offset(a.dx * c - a.dy * s, a.dx * s + a.dy * c) * ring(limb, p, scale);
  }

  /// under is what is under [page] -- a knob, a middle, a ring, or a line
  /// with a point to be put on it -- within [reach] page units, at
  /// [scale]. Knobs before middles before rings before lines: the small
  /// things on top of the large.
  RigHold? under(Offset page, double scale, double reach) {
    var local = placed.toLocal(page);
    for (var grab in const [RigGrab.knob, RigGrab.centre, RigGrab.ring]) {
      for (var MapEntry(key: limb, value: pts) in limbs.entries) {
        for (var p in pts) {
          var hit = switch (grab) {
            RigGrab.knob => (knob(limb, p, scale) - local).distance <= reach,
            RigGrab.centre => (p.at - local).distance <= reach,
            RigGrab.ring =>
              ((p.at - local).distance - ring(limb, p, scale)).abs() <=
                  reach * 0.7,
          };
          if (hit) return RigHold(limb, p.point, grab);
        }
      }
    }
    // A line: a point put on it there, its middle taken hold of.
    for (var MapEntry(key: limb, value: pts) in limbs.entries) {
      for (var i = 0; i + 1 < pts.length; i++) {
        if (_toSegment(local, pts[i].at, pts[i + 1].at) <= reach) {
          var point = rigPointFor(rig, limb, element.dna.rigPoints, local);
          return RigHold(limb, point, RigGrab.centre, added: true);
        }
      }
    }
    return null;
  }

  /// lines is each limb's line through its points, on the page.
  Iterable<List<Offset>> get lines =>
      limbs.values.map((pts) => [for (var p in pts) placed.toPage(p.at)]);
}

double _toSegment(Offset p, Offset a, Offset b) {
  var ab = b - a;
  var len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 < 1e-9) return (p - a).distance;
  var t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// withRigPoint is [e] with [point] on [limb].
CharacterElement withRigPoint(
        CharacterElement e, CharacterLimb limb, RigPoint point) =>
    e.copyWith(
        dna: e.dna
            .copyWith(rigPoints: e.dna.rigPoints.withPoint(limb.name, point)));

/// withoutRigPoint is [e] with the point at [point]'s spot on [limb] taken
/// away, or -- a joint -- put back as it was.
CharacterElement withoutRigPoint(
        CharacterElement e, CharacterLimb limb, RigPoint point) =>
    e.copyWith(
        dna: e.dna
            .copyWith(rigPoints: e.dna.rigPoints.without(limb.name, point)));

/// rigDragged is [start] -- as it was when [hold] was taken at [from], a
/// point on the page -- with it dragged to [to]. [scale] is screen pixels
/// to a unit of the page, which the ring is drawn at.
CharacterElement rigDragged(CharacterElement start, RigHold hold, Offset from,
    Offset to, int frame, double scale,
    {int frameRate = 12, CanvasDocument? document}) {
  var e = hold.added ? withRigPoint(start, hold.limb, hold.point) : start;
  var view = RigView.of(e, frame, frameRate: frameRate, document: document);
  var p = _find(view.limbs[hold.limb] ?? const [], hold.point);
  if (p == null) return start;
  var a = view.placed.toLocal(from), b = view.placed.toLocal(to);
  var u = view.rig.unit;
  var point = p.point;
  switch (hold.grab) {
    case RigGrab.centre:
      // Where it would be unmoved, and how far off it now: along the bone
      // and across it.
      var at = p.at + (b - a) - p.on;
      point = point.copyWith(
          along: (at.dx * p.dir.dx + at.dy * p.dir.dy) / u,
          across: (at.dx * p.across.dx + at.dy * p.across.dy) / u);
    case RigGrab.ring:
      // As much thicker as the ring is pulled out: to nothing in its middle.
      var r0 = (a - p.at).distance;
      if (r0 < 1e-6) return e;
      var next = point.scale * (b - p.at).distance / r0;
      point = point.copyWith(scale: next < 0.04 ? 0 : next);
    case RigGrab.knob:
      double angle(Offset d) => math.atan2(d.dy, d.dx);
      var by = (angle(b - p.at) - angle(a - p.at)) * 180 / math.pi;
      var turn = point.turn + by;
      turn = (turn + 180) % 360 - 180;
      point = point.copyWith(turn: turn);
  }
  return withRigPoint(e, hold.limb, point);
}

/// rigColour is the rig's colour: apart from the pins' blue and the
/// puppet's pink.
const Color rigColour = Color(0xFF16A37F);

/// paintRig draws [view]'s limbs and points for reshaping -- [at] takes a
/// point on the page to the screen, [scale] screen pixels to a page unit --
/// [picked] the point picked.
void paintRig(
    Canvas canvas, RigView view, Offset Function(Offset) at, double scale,
    {(CharacterLimb, RigPoint)? picked}) {
  Offset p(Offset local) => at(view.placed.toPage(local));
  var line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round
    ..color = rigColour.withValues(alpha: 0.8);
  var ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = rigColour.withValues(alpha: 0.55);
  var fill = Paint()..color = rigColour;
  var knob = Paint()..color = const Color(0xFFFFFFFF);
  for (var MapEntry(key: limb, value: pts) in view.limbs.entries) {
    canvas.drawPath(
        Path()..addPolygon([for (var q in pts) p(q.at)], false), line);
    for (var q in pts) {
      var isPicked =
          picked != null && picked.$1 == limb && picked.$2.sameSpot(q.point);
      var centre = p(q.at);
      // The ring, as the cross-section is seen: an ellipse turned with it.
      var r = view.ring(limb, q, scale);
      var ringPts = [
        for (var i = 0; i < 28; i++)
          () {
            var t = i * math.pi * 2 / 28;
            var turn = q.point.turn * math.pi / 180;
            var a = q.across;
            var c = math.cos(turn), s = math.sin(turn);
            var side = Offset(a.dx * c - a.dy * s, a.dx * s + a.dy * c);
            var flat = math.cos(turn).abs() * 0.6 + 0.4;
            return p(q.at +
                side * (r * math.cos(t)) +
                q.dir * (r * flat * math.sin(t)));
          }(),
      ];
      canvas.drawPath(Path()..addPolygon(ringPts, true),
          isPicked ? (Paint.from(ringPaint)..color = rigColour) : ringPaint);
      var k = p(view.knob(limb, q, scale));
      canvas.drawCircle(k, 3.5, knob);
      canvas.drawCircle(
          k,
          3.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = rigColour);
      // A joint square, a point put on round.
      var size = isPicked ? 6.0 : 4.5;
      var mark = q.point.isJoint
          ? (Path()
            ..addRect(Rect.fromCenter(
                center: centre, width: size * 2, height: size * 2)))
          : (Path()..addOval(Rect.fromCircle(center: centre, radius: size)));
      canvas.drawPath(mark, isPicked ? fill : knob);
      canvas.drawPath(
          mark,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = rigColour);
    }
  }
}
