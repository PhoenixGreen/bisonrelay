import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_extremities.dart';

// character_rig.dart is where a character's joints are, for a pose: the one
// answer the painter draws from and the stage puts its pins on.
//
// Forward, a pose's angles are walked down the skeleton to points. Backward,
// a point a hand or a foot is dragged to is turned into the two angles of the
// arm or leg that reach it (solveLimb). Both are plain arithmetic on the box
// the character is drawn in, so the stage, the export and the tests agree to
// the last decimal.

/// CharacterLimb is an arm or a leg: two bones and the joint they end at.
enum CharacterLimb {
  armL(CharacterBone.upperArmL, CharacterBone.foreArmL),
  armR(CharacterBone.upperArmR, CharacterBone.foreArmR),
  legL(CharacterBone.thighL, CharacterBone.shinL),
  legR(CharacterBone.thighR, CharacterBone.shinR);

  final CharacterBone upper;
  final CharacterBone lower;
  const CharacterLimb(this.upper, this.lower);

  bool get isArm => this == armL || this == armR;
  bool get onLeft => this == armL || this == legL;

  /// bend is which way the middle joint points: elbows out from the body
  /// and knees out over the feet, which is how a figure seen from the front
  /// reads as natural. 1 is towards the page's left.
  double get bend => onLeft ? 1 : -1;
}

/// RigJoint is a joint of [CharacterRig.joints3].
enum RigJoint {
  hips,
  chest,
  neck,
  head,
  shoulderL,
  elbowL,
  wristL,
  shoulderR,
  elbowR,
  wristR,
  hipL,
  kneeL,
  ankleL,
  hipR,
  kneeR,
  ankleR,
}

/// CharacterRig is a character's joints for one pose, in the box it is drawn
/// in.
class CharacterRig {
  /// unit is one head length on the page.
  final double unit;

  /// headScale is how big the head is drawn against [unit]: smaller on four
  /// legs, where a head the size a person's is reads as a cub's.
  final double headScale;

  /// below is the length of the body under the chin.
  final double below;

  final double shoulderHalf;
  final double hipHalf;

  final double neckLength;
  final double torsoLength;
  final double upperArm;
  final double foreArm;
  final double thigh;
  final double shin;

  /// limbWidth is how thick an arm is drawn, and legWidth a leg.
  final double limbWidth;
  final double legWidth;

  /// Joints, on the page.
  final Offset hips;
  final Offset chest;
  final Offset neck;
  final Offset headCentre;
  /// headTurn and bodyTurn are how far the head and the body lean on the
  /// page, in degrees: their tilt as drawn, whatever way they are turned.
  final double headTurn;
  final double bodyTurn;
  final Offset shoulderL, shoulderR, elbowL, elbowR, wristL, wristR;
  final Offset hipL, hipR, kneeL, kneeR, ankleL, ankleR;

  /// yaw is the whole body turned away from the reader, in degrees -- see
  /// CharacterPose.turn.
  final double yaw;

  /// depths is how near the reader each limb is, from the middle of the
  /// body: more is nearer. What decides which arm is drawn in front.
  final Map<CharacterLimb, double> depths;

  /// swings is how far each limb's two bones are swung forward of the body,
  /// in degrees: what a side view needs to point a foot.
  final Map<CharacterLimb, double> footSwing;

  /// plan is what the body plan adds to each bone's swing before the pose
  /// is laid on it: on four legs, the body pitched forward and the arms
  /// brought down to stand on. A pin sets the swing it sees less this.
  final Map<CharacterBone, double> plan;

  /// wingFlap is how far wings are raised from folded, in degrees.
  final double wingFlap;

  /// joints3 is every joint in the body's own space, before it is turned
  /// to the page: x across it to the page's right when it faces the
  /// reader, y down, z towards the reader, from the hips. What a figure
  /// drawn in 3D -- a mannequin, a model -- is posed from.
  final Map<RigJoint, List<double>> joints3;

  /// headBasis is how the head is turned in the body's space, as a 3x3
  /// matrix row by row: its own across, down and forward in its columns.
  final List<double> headBasis;

  /// look is the shape the character's body and face are made -- see
  /// character_appearance.dart -- for whatever draws from this rig.
  final Appearance look;

  /// tilt is the body seen from above, in degrees -- see CharacterPose.tilt
  /// -- tipped about [ground], how far below the hips the feet stand.
  final double tilt;
  final double ground;

  /// frames is the frame each hand and foot is made on, in the body's
  /// space, row by row -- see character_extremities.dart. A hand's: across
  /// it to the thumb, along it to the fingers, and out of its back. A
  /// foot's: out from the body, down, and forward to the toes.
  final Map<CharacterLimb, List<double>> frames;

  /// hands is how each hand is made: each finger's curl, the thumb first,
  /// and how far they spread. toes is how far each foot's toes bend up.
  final Map<CharacterLimb, List<double>> hands;
  final Map<CharacterLimb, double> toes;

  /// planted is how far the body is lifted to keep its feet on the ground
  /// as they point: up on to the toes.
  final double planted;

  const CharacterRig._({
    required this.unit,
    this.headScale = 1,
    required this.below,
    required this.shoulderHalf,
    required this.hipHalf,
    required this.neckLength,
    required this.torsoLength,
    required this.upperArm,
    required this.foreArm,
    required this.thigh,
    required this.shin,
    required this.limbWidth,
    required this.legWidth,
    required this.hips,
    required this.chest,
    required this.neck,
    required this.headCentre,
    required this.headTurn,
    required this.bodyTurn,
    required this.shoulderL,
    required this.shoulderR,
    required this.elbowL,
    required this.elbowR,
    required this.wristL,
    required this.wristR,
    required this.hipL,
    required this.hipR,
    required this.kneeL,
    required this.kneeR,
    required this.ankleL,
    required this.ankleR,
    required this.yaw,
    required this.depths,
    required this.footSwing,
    this.plan = const {},
    this.wingFlap = 0,
    this.joints3 = const {},
    this.headBasis = const [1, 0, 0, 0, 1, 0, 0, 0, 1],
    this.tilt = 0,
    this.ground = 0,
    this.look = Appearance.rest,
    this.frames = const {},
    this.hands = const {},
    this.toes = const {},
    this.planted = 0,
  });

  /// footDrop is how far below the ankle the sole is, as a share of the
  /// body under the chin; the rest of that body is neck, torso -- what is
  /// left, 0.36 at rest -- and legs.
  static const double _neck = 0.06,
      _thigh = 0.26,
      _shin = 0.26,
      footDrop = 0.06;

  /// of lays out [dna] standing in [pose], filling the height of [box].
  /// [breath] lifts the chest, and the shoulders and head with it, as a
  /// breath in does: 0 out, 1 in.
  factory CharacterRig.of(CharacterDna dna, CharacterPose pose, Rect box,
      {double breath = 0}) {
    var plan = dna.species.legless
        ? fishPlan
        : dna.fourLegs
            ? fourLegPlan
            : const <CharacterBone, double>{};
    // A bird's arms are its wings: they rise as the wings do.
    if (dna.species == Species.bird) {
      var flap = pose[CharacterBone.wings];
      pose = pose.withAngles({
        CharacterBone.upperArmL: pose[CharacterBone.upperArmL] + flap,
        CharacterBone.upperArmR: pose[CharacterBone.upperArmR] - flap,
      });
    }
    var lk = dna.look;
    // Stooped: leaning forward from the waist, the head brought up to look
    // ahead again.
    if (lk[Look.posture] != 0 && plan.isEmpty) {
      pose = pose.withSwings({
        CharacterBone.spine: pose.swing(CharacterBone.spine) + lk[Look.posture] * 14,
        CharacterBone.head: pose.swing(CharacterBone.head) - lk[Look.posture] * 10,
      });
    }
    if (plan.isNotEmpty) {
      pose = pose.withSwings({
        for (var e in plan.entries) e.key: pose.swing(e.key) + e.value,
      });
    }
    var heads = dna.headsTall;
    var unit = box.height / heads;
    var below = (heads - 1) * unit;
    var broad = 0.85 + 0.3 * dna.build;
    var shoulderBase = (0.25 + 0.1 * heads) * unit * broad;
    var shoulderHalf = shoulderBase *
        (1 + 0.28 * lk[Look.shoulders] + 0.08 * lk[Look.muscle]);
    var hipHalf = shoulderBase * 0.62 * (1 + 0.3 * lk[Look.hips]);
    // Longer legs or neck are made of the body between them: the feet stay
    // on the ground and the head on top, whatever is longer.
    var neckShare = _neck * (1 + 0.6 * lk[Look.neckLength]);
    // Shorter goes further than longer: a cartoon animal's stubby legs.
    var legShare = 1 + (lk[Look.legLength] < 0 ? 0.35 : 0.18) * lk[Look.legLength];
    var thigh = below * _thigh * legShare;
    var shin = below * _shin * legShare;
    var neckLength = below * neckShare;
    var torsoLength =
        below * (1 - neckShare - (_thigh + _shin) * legShare - footDrop);
    // Arms reach to about the middle of the thigh, at any height.
    var arm = (torsoLength + thigh * 0.45) * (1 + 0.22 * lk[Look.armLength]);
    var upperArm = arm * 0.52;
    var foreArm = arm * 0.48;
    if (dna.fourLegs) {
      // Front legs as long as back legs, and shoulders as narrow as hips.
      upperArm = thigh;
      foreArm = shin;
      shoulderHalf = hipHalf * 1.1;
    }
    var limbWidth = (dna.fourLegs
            ? hipHalf * 0.7
            : shoulderBase * (0.27 + 0.1 * dna.build)) *
        (1 + 0.45 * lk[Look.armWidth] + 0.15 * lk[Look.muscle]);
    var legWidth = shoulderBase *
        0.62 *
        0.78 *
        (1 + 0.4 * lk[Look.legWidth] + 0.12 * lk[Look.muscle]);

    var cx = box.center.dx;
    var hipY =
        box.top + unit + neckLength + torsoLength - pose.lift * unit;
    // A body carried level is longer than one standing up, and needs more
    // neck to hold its head up -- worked out after the hips are placed, so
    // the feet still stand on the bottom of the box.
    var headScale = 1.0;
    if (dna.species.legless) {
      // A fish floats, its middle half way up the box, its head on the
      // front of its body with no neck between.
      hipY -= unit * (heads * 0.25);
      torsoLength *= 1.5;
      neckLength *= 0.1;
      headScale = 0.9;
    } else if (dna.fourLegs) {
      torsoLength *= 1.4;
      neckLength *= 2.2;
      headScale = 0.78;
    }
    var yawR = pose.turn * math.pi / 180;
    var cosY = math.cos(yawR), sinY = math.sin(yawR);
    // Seen from above, tipped towards the reader about the feet: nearer is
    // lower on the page, and up is shorter.
    var tiltR = pose.tilt * math.pi / 180;
    var cosT = math.cos(tiltR), sinT = math.sin(tiltR);
    var ground = box.bottom - hipY;

    // Worked out in the body's own space -- x across it to the page's
    // right when it faces the reader, y down, z towards the reader -- from
    // the hips, then turned with the body and laid flat on the page.
    _M3 bone(CharacterBone b) =>
        _M3.z(pose[b]) * _M3.x(pose.swing(b));
    Offset page(_V3 v) {
      var near = v.x * sinY + v.z * cosY;
      return Offset(cx + v.x * cosY - v.z * sinY,
          hipY + ground + (v.y - ground) * cosT + near * sinT);
    }

    double depth(_V3 v) =>
        -(v.y - ground) * sinT + (v.x * sinY + v.z * cosY) * cosT;

    const origin = _V3(0, 0, 0);
    // The spine stands up from the hips rather than hanging from them, so
    // the same turn that swings a hanging bone's end forwards would lean it
    // back. Turned over here, a positive swing leans the body forwards --
    // the way a walk, a run and a four-legged stance all mean it.
    var spine = _M3.z(pose[CharacterBone.spine]) *
        _M3.x(-pose.swing(CharacterBone.spine));
    var chest3 =
        origin + spine.on(_V3(0, -(torsoLength + breath * unit * 0.035), 0));
    var neck3 = chest3 + spine.on(_V3(0, -neckLength, 0));
    var head = spine *
        _M3.z(pose[CharacterBone.head]) *
        _M3.x(pose.swing(CharacterBone.head));
    // A fish's head is the front of its body, not something on a neck.
    var head3 = dna.species.legless
        ? neck3
        : neck3 + head.on(_V3(0, -unit * 0.5 * headScale, 0));

    var shoulderL3 = chest3 + spine.on(_V3(-shoulderHalf * 0.86, 0, 0));
    var shoulderR3 = chest3 + spine.on(_V3(shoulderHalf * 0.86, 0, 0));
    // The hips tilt on their own -- one higher, the weight on that leg.
    var pelvis = _M3.z(pose[CharacterBone.hips]);
    var hipL3 = pelvis.on(_V3(-hipHalf * 0.55, 0, 0));
    var hipR3 = pelvis.on(_V3(hipHalf * 0.55, 0, 0));

    (_V3, _V3) reach(_V3 from, _M3 parent, CharacterLimb limb, double a,
        double b) {
      var upper = parent * bone(limb.upper);
      var mid = from + upper.on(_V3(0, a, 0));
      var lower = upper * bone(limb.lower);
      return (mid, mid + lower.on(_V3(0, b, 0)));
    }

    var (elbowL3, wristL3) =
        reach(shoulderL3, spine, CharacterLimb.armL, upperArm, foreArm);
    var (elbowR3, wristR3) =
        reach(shoulderR3, spine, CharacterLimb.armR, upperArm, foreArm);
    // The legs hang from the hips, which the spine turns above: leaning
    // over does not swing the legs with it.
    var (kneeL3, ankleL3) =
        reach(hipL3, _M3.identity, CharacterLimb.legL, thigh, shin);
    var (kneeR3, ankleR3) =
        reach(hipR3, _M3.identity, CharacterLimb.legR, thigh, shin);

    // The hands, on the end of the forearms: bent at the wrist, and turned
    // so the back of the hand is half towards the reader at rest -- the
    // palm towards the body, the thumb forward.
    List<double> handFrame(CharacterLimb limb) {
      var left = limb.onLeft;
      var forearm = bone(limb.upper) * bone(limb.lower);
      var turn = spine * forearm;
      var wrist = wristBone(left);
      var a = (45 + pose[palmBone(left)]) * math.pi / 180;
      var c = math.cos(a), sn = math.sin(a);
      var side = left ? 1.0 : -1.0;
      // Columns: the thumb's way, along the hand, out of its back.
      var rest = _M3([side * c, 0, -side * sn, 0, 1, 0, sn, 0, c]);
      return (turn * bone(wrist) * rest).m;
    }

    // The feet: flat to the floor however the shin is turned, only tipping
    // a little with it, or a kick would point the sole at the sky; then
    // pointed at the ankle and turned out.
    var feetLook = FootSize.of(legWidth, lk, below * footDrop);
    _M3 footTurn(CharacterLimb limb, {bool posed = true}) {
      var left = limb.onLeft;
      var ankle = ankleBone(left);
      var tip = _M3.z(0.25 * (pose[limb.upper] + pose[limb.lower])) *
          _M3.x(0.25 * (pose.swing(limb.upper) + pose.swing(limb.lower)));
      var side = left ? -1.0 : 1.0;
      var outward = _M3([side, 0, 0, 0, 1, 0, 0, 0, 1]);
      if (!posed) return tip * outward;
      return tip *
          _M3.y(side * pose[ankle]) *
          _M3.x(-pose.swing(ankle)) *
          outward;
    }

    // Kept on the ground: a foot pointed lower than it stood lifts the body
    // as far as it goes into the floor -- on to the toes -- and no further,
    // nor at all when it was off the ground already.
    double lowest(CharacterLimb limb, _V3 ankle, bool posed) {
      var turn = footTurn(limb, posed: posed);
      var toes = posed ? pose.swing(toesBone(limb.onLeft)) : 0.0;
      var low = -double.infinity;
      for (var (x, y, z)
          in footBottoms(feetLook, toes, legWidth * footOutward)) {
        low = math.max(low, ankle.y + turn.on(_V3(x, y, z)).y);
      }
      return low;
    }

    var planted = 0.0;
    if (!dna.species.legless && !dna.fourLegs && dna.species != Species.bird) {
      var floor = ground;
      double under(bool posed) => math.max(
          0,
          math.max(lowest(CharacterLimb.legL, ankleL3, posed),
                  lowest(CharacterLimb.legR, ankleR3, posed)) -
              floor);
      planted = math.max(0.0, under(true) - under(false));
      hipY -= planted;
      ground += planted;
    }

    var hips = page(origin), chest = page(chest3), neck = page(neck3);
    var headCentre = page(head3);
    double tilt(Offset from, Offset to) => from == to
        ? 0
        : _wrap(turnOf(to - from) - 180);

    double swingOf(CharacterLimb l) =>
        pose.swing(l.upper) + pose.swing(l.lower) * 0.5;

    return CharacterRig._(
      unit: unit,
      headScale: headScale,
      below: below,
      shoulderHalf: shoulderHalf,
      hipHalf: hipHalf,
      neckLength: neckLength,
      torsoLength: torsoLength,
      upperArm: upperArm,
      foreArm: foreArm,
      thigh: thigh,
      shin: shin,
      limbWidth: limbWidth,
      legWidth: legWidth,
      hips: hips,
      chest: chest,
      neck: neck,
      headCentre: headCentre,
      headTurn: tilt(neck, headCentre),
      bodyTurn: tilt(hips, chest),
      shoulderL: page(shoulderL3),
      shoulderR: page(shoulderR3),
      elbowL: page(elbowL3),
      elbowR: page(elbowR3),
      wristL: page(wristL3),
      wristR: page(wristR3),
      hipL: page(hipL3),
      hipR: page(hipR3),
      kneeL: page(kneeL3),
      kneeR: page(kneeR3),
      ankleL: page(ankleL3),
      ankleR: page(ankleR3),
      yaw: pose.turn,
      depths: {
        CharacterLimb.armL: depth(shoulderL3) + depth(wristL3) * 0.01,
        CharacterLimb.armR: depth(shoulderR3) + depth(wristR3) * 0.01,
        CharacterLimb.legL: depth(hipL3) + depth(ankleL3) * 0.01,
        CharacterLimb.legR: depth(hipR3) + depth(ankleR3) * 0.01,
      },
      plan: plan,
      wingFlap: pose[CharacterBone.wings],
      joints3: {
        for (var (j, v) in [
          (RigJoint.hips, origin),
          (RigJoint.chest, chest3),
          (RigJoint.neck, neck3),
          (RigJoint.head, head3),
          (RigJoint.shoulderL, shoulderL3),
          (RigJoint.elbowL, elbowL3),
          (RigJoint.wristL, wristL3),
          (RigJoint.shoulderR, shoulderR3),
          (RigJoint.elbowR, elbowR3),
          (RigJoint.wristR, wristR3),
          (RigJoint.hipL, hipL3),
          (RigJoint.kneeL, kneeL3),
          (RigJoint.ankleL, ankleL3),
          (RigJoint.hipR, hipR3),
          (RigJoint.kneeR, kneeR3),
          (RigJoint.ankleR, ankleR3),
        ])
          j: [v.x, v.y, v.z],
      },
      headBasis: head.m,
      tilt: pose.tilt,
      ground: ground,
      look: lk,
      footSwing: {
        for (var l in [CharacterLimb.legL, CharacterLimb.legR]) l: swingOf(l),
      },
      frames: {
        CharacterLimb.armL: handFrame(CharacterLimb.armL),
        CharacterLimb.armR: handFrame(CharacterLimb.armR),
        CharacterLimb.legL: footTurn(CharacterLimb.legL).m,
        CharacterLimb.legR: footTurn(CharacterLimb.legR).m,
      },
      hands: {
        for (var l in [CharacterLimb.armL, CharacterLimb.armR])
          l: [
            for (var f in Finger.values) pose[f.bone(l.onLeft)],
            pose[spreadBone(l.onLeft)],
          ],
      },
      toes: {
        for (var l in [CharacterLimb.legL, CharacterLimb.legR])
          l: pose.swing(toesBone(l.onLeft)),
      },
      planted: planted,
    );
  }

  /// stepOnPage is a step in the body's own space as a step on the page:
  /// turned with the body, and seen from above or below.
  Offset stepOnPage(double x, double y, double z) {
    var yr = yaw * math.pi / 180, tr = tilt * math.pi / 180;
    var cy = math.cos(yr), sy = math.sin(yr);
    var near = x * sy + z * cy;
    return Offset(x * cy - z * sy, y * math.cos(tr) + near * math.sin(tr));
  }

  /// stepDepth is how much nearer the reader a step in the body's own space
  /// takes a point.
  double stepDepth(double x, double y, double z) {
    var yr = yaw * math.pi / 180, tr = tilt * math.pi / 180;
    var near = x * math.sin(yr) + z * math.cos(yr);
    return -y * math.sin(tr) + near * math.cos(tr);
  }

  /// footSize is how big a foot is drawn under a leg [legWidth] thick.
  FootSize footSize([double? width]) =>
      FootSize.of(width ?? legWidth, look, below * footDrop);

  /// root, middle and end are a limb's three joints.
  Offset root(CharacterLimb limb) => switch (limb) {
        CharacterLimb.armL => shoulderL,
        CharacterLimb.armR => shoulderR,
        CharacterLimb.legL => hipL,
        CharacterLimb.legR => hipR,
      };

  Offset middle(CharacterLimb limb) => switch (limb) {
        CharacterLimb.armL => elbowL,
        CharacterLimb.armR => elbowR,
        CharacterLimb.legL => kneeL,
        CharacterLimb.legR => kneeR,
      };

  Offset end(CharacterLimb limb) => switch (limb) {
        CharacterLimb.armL => wristL,
        CharacterLimb.armR => wristR,
        CharacterLimb.legL => ankleL,
        CharacterLimb.legR => ankleR,
      };

  (double, double) lengths(CharacterLimb limb) =>
      limb.isArm ? (upperArm, foreArm) : (thigh, shin);

  /// parentTurn is the turn a limb's upper bone is measured from: the
  /// body's for an arm, nothing for a leg.
  double parentTurn(CharacterLimb limb) => limb.isArm ? bodyTurn : 0;

  /// handRadius is the size a hand is drawn.
  double get handRadius => limbWidth * 0.62 * (1 + 0.3 * look[Look.hands]);

  /// headRadii is the head's half width and half height.
  Size get headRadii => Size(
      unit * 0.46 * (1 + 0.18 * look[Look.headWidth] + 0.05 * look[Look.cheeks]),
      unit * 0.5 * (1 + 0.14 * look[Look.headHeight]));

  /// sideOn is how far round the body is turned towards side on: 0 facing
  /// the reader or away, 1 side on. Which of a bone's two angles a drag on
  /// the page moves: its spread facing the reader, its swing side on.
  double get sideOn => math.sin(yaw * math.pi / 180).abs();

  /// _facing is which way a forward swing goes on the page side on: to the
  /// left when the body is turned to the left.
  double get _facing => math.sin(yaw * math.pi / 180) >= 0 ? 1 : -1;

  /// _set is [pose] with [bone] turned [degrees] on the page from its
  /// parent: its spread facing the reader, its swing side on.
  /// _untilted is [v], a step on the page, as it would be seen straight on:
  /// seen from above or below, up the body is shorter on the page, and a
  /// pin dragged a step is a step the body takes longer.
  Offset _untilted(Offset v) {
    if (tilt == 0) return v;
    var c = math.cos(tilt * math.pi / 180).abs().clamp(0.2, 1.0);
    return Offset(v.dx, v.dy / c);
  }

  CharacterPose _set(CharacterPose pose, CharacterBone bone, double degrees) {
    var d = _wrap(degrees);
    // The spine stands up rather than hanging down, so its forward swing
    // turns it the other way on the page -- see CharacterRig.of.
    var up = bone == CharacterBone.spine ? -1 : 1;
    return sideOn > 0.7
        ? pose
            .withSwing(bone, _wrap(d * _facing * up - (plan[bone] ?? 0)))
            .withAngle(bone, 0)
        : pose.withAngle(bone, d).withSwing(bone, 0);
  }

  /// solveLimb is the pose with [limb] bent to reach [target], or as near it
  /// as it can get: a two-bone reach, folding the middle joint the limb's own
  /// way. The other bones are left as they are. Facing the reader the limb
  /// is spread; side on it is swung, as a leg is in a stride.
  CharacterPose solveLimb(
      CharacterPose pose, CharacterLimb limb, Offset target) {
    var from = root(limb);
    var (a, b) = lengths(limb);
    var toTarget = _untilted(target - from);
    var d = toTarget.distance
        .clamp((a - b).abs() + 1e-6, a + b - 1e-6)
        .toDouble();
    // The angle at the root between the line to the target and the upper
    // bone, by the cosine rule; the lower bone then closes the triangle.
    var cosRoot = ((a * a + d * d - b * b) / (2 * a * d)).clamp(-1.0, 1.0);
    var atRoot = math.acos(cosRoot) * 180 / math.pi;
    var cosMid = ((a * a + b * b - d * d) / (2 * a * b)).clamp(-1.0, 1.0);
    var atMid = math.acos(cosMid) * 180 / math.pi;
    var toward = turnOf(toTarget);
    // A turn clockwise swings a hanging bone towards the page's left, so a
    // left limb opens its middle joint outwards with the upper bone turned
    // further clockwise than the line to the target, and the lower bone
    // turned back to meet it. Side on, a knee bends forwards and an elbow
    // backwards -- the way the face is pointing, or away from it.
    var bend = sideOn > 0.7
        ? (limb.isArm ? -_facing : _facing)
        : limb.bend;
    var upperTurn = toward + bend * atRoot;
    var lowerTurn = -bend * (180 - atMid);
    var posed = _set(pose, limb.upper, upperTurn - parentTurn(limb));
    return _set(posed, limb.lower, lowerTurn);
  }

  /// solveHead is the pose with the head tilted to look along the line from
  /// the neck to [target], as near as a neck allows.
  CharacterPose solveHead(CharacterPose pose, Offset target) {
    var turn = turnOf(_untilted(target - neck)) - 180;
    var tilt = _wrap(turn - bodyTurn).clamp(-50.0, 50.0);
    return pose.withAngle(CharacterBone.head, tilt);
  }

  /// solveLean is the pose with the body leaning so its chest is over
  /// [target], as near as a waist allows: sideways facing the reader,
  /// forwards and back side on.
  CharacterPose solveLean(CharacterPose pose, Offset target) {
    var turn = (turnOf(_untilted(target - hips)) - 180);
    return _set(pose, CharacterBone.spine, _wrap(turn).clamp(-60.0, 60.0));
  }
}

/// fourLegPlan is what standing on four legs adds to a pose: the body
/// pitched forward until it is level, the arms brought down under it to be
/// front legs, and the head brought back up to look ahead.
const Map<CharacterBone, double> fourLegPlan = {
  CharacterBone.spine: 80,
  CharacterBone.upperArmL: 80,
  CharacterBone.upperArmR: 80,
  CharacterBone.head: 72,
};

/// fishPlan is what swimming adds to a pose: the body level, and the head
/// turned back upright, so its face reads -- it is centred on the front of
/// the body rather than on a neck; see CharacterRig.of.
const Map<CharacterBone, double> fishPlan = {
  CharacterBone.spine: 90,
  CharacterBone.head: 90,
};

/// _V3 is a point or a step in a body's own space.
class _V3 {
  final double x, y, z;
  const _V3(this.x, this.y, this.z);
  _V3 operator +(_V3 o) => _V3(x + o.x, y + o.y, z + o.z);
}

/// _M3 is a turn in a body's own space.
class _M3 {
  final List<double> m;
  const _M3(this.m);

  static const identity = _M3([1, 0, 0, 0, 1, 0, 0, 0, 1]);

  /// z is a turn of [degrees] on the page, clockwise: the way _along turns.
  factory _M3.z(double degrees) {
    if (degrees == 0) return identity;
    var r = degrees * math.pi / 180, c = math.cos(r), s = math.sin(r);
    return _M3([c, -s, 0, s, c, 0, 0, 0, 1]);
  }

  /// x is a swing of [degrees] towards the reader: a hanging bone's foot
  /// coming forwards.
  factory _M3.x(double degrees) {
    if (degrees == 0) return identity;
    var r = degrees * math.pi / 180, c = math.cos(r), s = math.sin(r);
    return _M3([1, 0, 0, 0, c, -s, 0, s, c]);
  }

  /// y is a turn of [degrees] about the body's up, as seen from above:
  /// towards the page's right facing the reader.
  factory _M3.y(double degrees) {
    if (degrees == 0) return identity;
    var r = degrees * math.pi / 180, c = math.cos(r), s = math.sin(r);
    return _M3([c, 0, s, 0, 1, 0, -s, 0, c]);
  }

  /// on is [v] turned by this.
  _V3 on(_V3 v) => _V3(m[0] * v.x + m[1] * v.y + m[2] * v.z,
      m[3] * v.x + m[4] * v.y + m[5] * v.z, m[6] * v.x + m[7] * v.y + m[8] * v.z);

  _M3 operator *(_M3 o) {
    var n = o.m;
    return _M3([
      for (var r = 0; r < 3; r++)
        for (var c = 0; c < 3; c++)
          m[r * 3] * n[c] + m[r * 3 + 1] * n[3 + c] + m[r * 3 + 2] * n[6 + c],
    ]);
  }
}

/// turnOf is the turn a bone pointing along [v] has: nought straight down,
/// clockwise on the page.
double turnOf(Offset v) => math.atan2(-v.dx, v.dy) * 180 / math.pi;

/// _wrap is [degrees] brought into -180..180, so a pose never carries an
/// arm turned round three times on the way to where it is.
double _wrap(double degrees) {
  var d = degrees % 360;
  if (d > 180) d -= 360;
  if (d <= -180) d += 360;
  return d;
}
