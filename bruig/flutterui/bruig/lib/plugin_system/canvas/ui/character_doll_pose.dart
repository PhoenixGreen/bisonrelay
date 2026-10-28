import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_extremities.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/ui/character_puppet.dart';

// character_doll_pose.dart is posing the doll -- see character_doll.dart --
// joint by joint, on the canvas: a knob on every joint, dragged to move it
// by turning the bone above; picked, two rings round it, one to bend the
// bone below it in the picture and one to swing it towards the reader or
// away; and, on a wrist, a knob on each fingertip to curl that finger.

/// DollJoint is a joint of the doll that can be taken hold of: the bone
/// it turns -- the one below it -- and where it is.
enum DollJoint {
  neck(CharacterBone.head, RigJoint.neck, "Neck"),
  waist(CharacterBone.spine, RigJoint.hips, "Waist"),
  shoulderL(CharacterBone.upperArmL, RigJoint.shoulderL, "Left shoulder"),
  elbowL(CharacterBone.foreArmL, RigJoint.elbowL, "Left elbow"),
  wristL(CharacterBone.wristL, RigJoint.wristL, "Left wrist"),
  shoulderR(CharacterBone.upperArmR, RigJoint.shoulderR, "Right shoulder"),
  elbowR(CharacterBone.foreArmR, RigJoint.elbowR, "Right elbow"),
  wristR(CharacterBone.wristR, RigJoint.wristR, "Right wrist"),
  hipL(CharacterBone.thighL, RigJoint.hipL, "Left hip"),
  kneeL(CharacterBone.shinL, RigJoint.kneeL, "Left knee"),
  ankleL(CharacterBone.ankleL, RigJoint.ankleL, "Left ankle"),
  hipR(CharacterBone.thighR, RigJoint.hipR, "Right hip"),
  kneeR(CharacterBone.shinR, RigJoint.kneeR, "Right knee"),
  ankleR(CharacterBone.ankleR, RigJoint.ankleR, "Right ankle");

  final CharacterBone bone;
  final RigJoint at;
  final String label;
  const DollJoint(this.bone, this.at, this.label);

  /// above is the joint whose bone carries this one: what turns to move it.
  DollJoint? get above => switch (this) {
        elbowL => shoulderL,
        wristL => elbowL,
        elbowR => shoulderR,
        wristR => elbowR,
        kneeL => hipL,
        ankleL => kneeL,
        kneeR => hipR,
        ankleR => kneeR,
        shoulderL || shoulderR || neck => waist,
        _ => null,
      };

  /// hand is the arm whose hand this wrist is, or null.
  CharacterLimb? get hand => switch (this) {
        wristL => CharacterLimb.armL,
        wristR => CharacterLimb.armR,
        _ => null,
      };

  /// pin is the puppet's pin at this joint, which moves it the way the pin
  /// does: a hand or a foot reached to where it is dragged.
  CharacterPin? get pin => switch (this) {
        wristL => CharacterPin.handL,
        wristR => CharacterPin.handR,
        ankleL => CharacterPin.footL,
        ankleR => CharacterPin.footR,
        _ => null,
      };
}

/// dollFingerBones is each finger's bone, index first, the thumb last --
/// as the tips are listed by DollPosing.fingerTips.
List<CharacterBone> dollFingerBones(CharacterLimb arm) => arm == CharacterLimb.armL
    ? const [
        CharacterBone.indexL,
        CharacterBone.middleL,
        CharacterBone.ringL,
        CharacterBone.littleL,
        CharacterBone.thumbL,
      ]
    : const [
        CharacterBone.indexR,
        CharacterBone.middleR,
        CharacterBone.ringR,
        CharacterBone.littleR,
        CharacterBone.thumbR,
      ];

/// dollHandScale is how much bigger than a style draws it the doll's hand
/// is -- see dollPieces.
const double dollHandScale = 1.25;

extension DollPosing on CharacterPlacement {
  /// _base is the pose to change, and as it is seen: with the camera's
  /// turn.
  CharacterPose get _base => element.poseAtFrame(frame);
  CharacterPose get _seen => _base.withTurn(_base.turn + turn);

  /// dollRig is the doll's rig with [seen] -- a pose as seen -- in this
  /// placement's box: the puppet's body when it has one of its own.
  CharacterRig dollRig([CharacterPose? seen]) {
    var e = element;
    var p = seen ?? _seen;
    return CharacterRig.of(e.style.dnaOf(e.puppet?.dna ?? e.dna),
        e.body.inThreeD ? p : e.inView(p), bounds);
  }

  /// dollJoint is where [j] is on the page, with rig [r] or the doll's.
  Offset dollJoint(DollJoint j, [CharacterRig? r]) =>
      toPage(CharacterPlacement.rigJoint(r ?? dollRig(), j.at));

  /// _tip is where the far end of the bone [j] turns is, in the drawing.
  Offset _tip(DollJoint j, CharacterRig r) => switch (j) {
        DollJoint.neck => r.headCentre,
        DollJoint.waist => r.chest,
        DollJoint.shoulderL => r.elbowL,
        DollJoint.elbowL => r.wristL,
        DollJoint.shoulderR => r.elbowR,
        DollJoint.elbowR => r.wristR,
        DollJoint.hipL => r.kneeL,
        DollJoint.kneeL => r.ankleL,
        DollJoint.hipR => r.kneeR,
        DollJoint.kneeR => r.ankleR,
        DollJoint.wristL || DollJoint.wristR =>
          r.end(j.hand!) + handTip(r, j.hand!, r.handRadius * dollHandScale),
        DollJoint.ankleL => CharacterPlacement.toeOf(r, CharacterLimb.legL),
        DollJoint.ankleR => CharacterPlacement.toeOf(r, CharacterLimb.legR),
      };

  /// dollTip is where the far end of the bone [j] turns is, on the page.
  Offset dollTip(DollJoint j, [CharacterRig? r]) => toPage(_tip(j, r ?? dollRig()));

  /// bentTo is the pose with [j]'s bone bent in the picture so the far end
  /// of it points from [j] towards [page].
  CharacterPose bentTo(DollJoint j, Offset page) {
    var seen = _seen;
    double angleAt(double a) {
      var r = dollRig(seen.withAngle(j.bone, a));
      var d = dollTip(j, r) - dollJoint(j, r);
      return d.direction;
    }

    var want = (page - dollJoint(j)).direction;
    var a = seen[j.bone];
    double wrap(double x) => math.atan2(math.sin(x), math.cos(x));
    for (var k = 0; k < 8; k++) {
      var now = angleAt(a);
      var miss = wrap(want - now);
      if (miss.abs() < 0.002) break;
      var slope = wrap(angleAt(a + 1) - now);
      if (slope.abs() < 1e-5) break;
      a += (miss / slope).clamp(-45.0, 45.0);
    }
    return seen.withAngle(j.bone, a).withTurn(_base.turn).withTilt(_base.tilt);
  }

  /// swungBy is the pose with [j]'s bone swung [degrees] more towards the
  /// reader than in [from].
  CharacterPose swungBy(DollJoint j, CharacterPose from, double degrees) =>
      from.withSwing(j.bone, (from.swing(j.bone) + degrees).clamp(-170.0, 170.0));

  /// movedTo is the pose that dragging joint [j] to [page] asks for: the
  /// pin's there, or the bone above it turned to bring it there.
  CharacterPose? movedTo(DollJoint j, Offset page) {
    if (j.pin case var pin?) return posedBy(pin, page);
    var above = j.above;
    if (above == null) return null;
    return bentTo(above, page);
  }

  /// fingerTips is where the tips of [arm]'s fingers are on the page,
  /// index first, the thumb last.
  List<Offset> fingerTips(CharacterLimb arm, [CharacterRig? r]) {
    r ??= dollRig();
    var m = r.frames[arm];
    if (m == null) return const [];
    var frame = ExtremityFrame(r, m);
    var chains = handJoints(r, arm, r.handRadius * dollHandScale);
    return [
      for (var (k, (joints, _, _)) in chains.indexed)
        if (k != 4)
          () {
            var (x, y, z) = joints.last;
            return toPage(r!.end(arm) + frame.at(x, y, z));
          }(),
    ];
  }

  /// curledTo is the pose with finger [finger] of [arm] -- index first,
  /// the thumb last -- curled so its tip is as near [page] as it goes.
  CharacterPose curledTo(CharacterLimb arm, int finger, Offset page) {
    var seen = _seen;
    var bone = dollFingerBones(arm)[finger];
    double miss(double curl) {
      var tips = fingerTips(arm, dollRig(seen.withAngle(bone, curl)));
      return finger < tips.length ? (tips[finger] - page).distance : double.infinity;
    }

    var best = seen[bone], least = miss(best);
    for (var c = -20.0; c <= 110; c += 10) {
      var m = miss(c);
      if (m < least) (best, least) = (c, m);
    }
    for (var c = best - 8; c <= best + 8; c += 2) {
      var m = miss(c);
      if (m < least) (best, least) = (c, m);
    }
    return seen.withAngle(bone, best).withTurn(_base.turn).withTilt(_base.tilt);
  }

  /// dollJointUnder is the doll's joint within [reach] of [page], nearest
  /// first.
  DollJoint? dollJointUnder(Offset page, double reach) {
    var r = dollRig();
    DollJoint? best;
    var nearest = reach;
    for (var j in DollJoint.values) {
      if (element.dna.species.legless && j.bone.name.contains(RegExp(r"thigh|shin|ankle"))) {
        continue;
      }
      var d = (dollJoint(j, r) - page).distance;
      if (d <= nearest) {
        nearest = d;
        best = j;
      }
    }
    return best;
  }
}

/// DollRing is which ring round a picked joint is held: the one that bends
/// its bone in the picture, or the one that swings it towards the reader.
enum DollRing { bend, swing }

/// dollRingUnder is the ring round a joint at [centre], [radius] across,
/// that [page] is on -- within [reach] -- or null. The swing ring is an
/// upright ellipse half as wide as the bend ring; where they meet, the
/// nearer wins.
DollRing? dollRingUnder(Offset centre, double radius, Offset page, double reach) {
  var d = page - centre;
  var onBend = (d.distance - radius).abs();
  // How far off the ellipse, roughly: its own radius that way.
  var a = radius * 0.45, b = radius;
  var t = math.atan2(d.dy / b, d.dx / a);
  var onEllipse = (Offset(a * math.cos(t), b * math.sin(t)) - d).distance;
  if (onBend > reach && onEllipse > reach) return null;
  return onEllipse < onBend ? DollRing.swing : DollRing.bend;
}
