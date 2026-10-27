import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/ui/character_puppet.dart';

// character_body_area.dart shows the parts of the body a garment covers
// while it is drawn on -- see GarmentKind.covers -- washed over the
// character, so it is plain where what is drawn will be worn: a shape
// drawn there goes on the part under it, and goes with it.

/// areaColour is the wash over the parts a garment covers.
const Color areaColour = Color(0xFF7C5CFF);

/// bodyAreaPath is [parts] of [placed]'s body, as one shape on the page.
Path bodyAreaPath(CharacterPlacement placed, Set<CharacterPart> parts) {
  var rig = placed.rig;
  var out = Path();
  void add(List<Offset> local) {
    out = Path.combine(PathOperation.union, out,
        Path()..addPolygon([for (var p in local) placed.toPage(p)], true));
  }

  List<Offset> capsule(Offset a, Offset b, double r) {
    var d = b - a;
    var l = d.distance;
    var u = l == 0 ? const Offset(0, 1) : d / l;
    var n = Offset(-u.dy, u.dx);
    return [
      for (var i = 0; i <= 10; i++) a + _turn(n, math.pi * i / 10) * r,
      for (var i = 0; i <= 10; i++) b + _turn(-n, math.pi * i / 10) * r,
    ];
  }

  List<Offset> circle(Offset c, double rx, double ry) => [
        for (var i = 0; i < 24; i++)
          c +
              Offset(math.cos(i * math.pi / 12) * rx,
                  math.sin(i * math.pi / 12) * ry),
      ];

  for (var part in parts) {
    switch (part) {
      case CharacterPart.head:
        var r = rig.headRadii;
        add(circle(rig.headCentre, r.width * rig.headScale * 1.08,
            r.height * rig.headScale * 1.08));
      case CharacterPart.torso:
        // Shoulder to shoulder, down to the hips: not up over the face.
        var down = rig.hips - rig.chest;
        var hipL = rig.hips + (rig.hipL - rig.hips) * 1.7;
        var hipR = rig.hips + (rig.hipR - rig.hips) * 1.7;
        add([
          rig.shoulderL - down * 0.08,
          rig.shoulderR - down * 0.08,
          hipR + down * 0.12,
          hipL + down * 0.12,
        ]);
      default:
        var limb = switch (part) {
          CharacterPart.upperArmL ||
          CharacterPart.foreArmL ||
          CharacterPart.handL =>
            CharacterLimb.armL,
          CharacterPart.upperArmR ||
          CharacterPart.foreArmR ||
          CharacterPart.handR =>
            CharacterLimb.armR,
          CharacterPart.thighL ||
          CharacterPart.shinL ||
          CharacterPart.footL =>
            CharacterLimb.legL,
          _ => CharacterLimb.legR,
        };
        var a = rig.root(limb), b = rig.middle(limb), c = rig.end(limb);
        var r = (limb.isArm ? rig.limbWidth : rig.legWidth) * 0.62;
        switch (part) {
          case CharacterPart.upperArmL ||
                CharacterPart.upperArmR ||
                CharacterPart.thighL ||
                CharacterPart.thighR:
            add(capsule(a, b, r));
          case CharacterPart.foreArmL ||
                CharacterPart.foreArmR ||
                CharacterPart.shinL ||
                CharacterPart.shinR:
            add(capsule(b, c, r * 0.85));
          case CharacterPart.handL || CharacterPart.handR:
            var d = c - b;
            var dir = d.distance == 0 ? const Offset(0, 1) : d / d.distance;
            add(circle(c + dir * rig.handRadius, rig.handRadius * 1.3,
                rig.handRadius * 1.3));
          default:
            // A foot: on the ground under the ankle, as long as a foot.
            var f = rig.legWidth;
            add(capsule(
                c, c + Offset(0, rig.below * CharacterRig.footDrop), f * 0.8));
        }
    }
  }
  return out;
}

Offset _turn(Offset v, double a) {
  var c = math.cos(a), s = math.sin(a);
  return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
}

/// paintBodyArea washes [parts] of [placed]'s body over it -- [at] takes a
/// point on the page to the screen.
void paintBodyArea(Canvas canvas, CharacterPlacement placed,
    Set<CharacterPart> parts, Offset Function(Offset) at, double scale) {
  if (parts.isEmpty) return;
  var area = bodyAreaPath(placed, parts);
  canvas.save();
  var o = at(Offset.zero);
  canvas.translate(o.dx, o.dy);
  canvas.scale(scale);
  canvas.drawPath(area, Paint()..color = areaColour.withValues(alpha: 0.16));
  canvas.drawPath(
      area,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4 / scale
        ..color = areaColour.withValues(alpha: 0.7));
  canvas.restore();
}
