import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';

// character_bvh.dart reads a BVH file -- motion capture as plain text, the
// form the CMU library and most capture tools give it out in -- and turns it
// into a character's poses, frame by frame.
//
// BVH is a skeleton (joints, where each sits from its parent, which way it
// may turn) and then a row of numbers per frame. Ours is a much simpler
// skeleton, so nothing is copied across by joint: each frame is played out
// on the BVH skeleton to find where its joints are, and then each of our
// bones is pointed the way the matching pair of joints point. That works
// whatever the BVH's own bone lengths and rest pose are, which differ from
// one source to the next.

/// BvhJoint is one joint of a BVH skeleton.
class BvhJoint {
  final String name;
  final int parent;
  final List<double> offset;
  final List<String> channels;

  /// first is where this joint's numbers start in a frame's row.
  final int first;

  const BvhJoint(this.name, this.parent, this.offset, this.channels, this.first);
}

/// Bvh is a whole BVH file: its skeleton and its frames.
class Bvh {
  final List<BvhJoint> joints;
  final List<List<double>> frames;

  /// frameTime is the seconds between frames.
  final double frameTime;

  const Bvh(this.joints, this.frames, this.frameTime);

  double get seconds => frames.length * frameTime;
}

/// MotionError is a motion file that cannot be read, or whose skeleton is
/// missing a joint our bones need -- BVH, FBX, glTF or capture alike.
class MotionError implements Exception {
  final String message;
  const MotionError(this.message);
  @override
  String toString() => message;
}

/// BvhError is the name a BVH's MotionError had first.
typedef BvhError = MotionError;

/// JointMotion is a skeleton moving, from whatever file or capture: its
/// joints' names and, frame by frame, where each joint is -- y up, in any
/// unit. What every source of motion is turned into before it is
/// retargeted on to a character; see motionPoses.
class JointMotion {
  final List<String> names;
  final int frameCount;

  /// frameTime is the seconds between frames.
  final double frameTime;

  /// positionsAt is where each joint is on frame [f], in the order of
  /// [names].
  final List<List<double>> Function(int f) positionsAt;

  const JointMotion(
      this.names, this.frameCount, this.frameTime, this.positionsAt);

  double get seconds => frameCount * frameTime;
}

/// parseBvh reads [text], or throws a BvhError saying what was wrong.
Bvh parseBvh(String text) {
  var words = text.split(RegExp(r"\s+")).where((w) => w.isNotEmpty).toList();
  var i = 0;
  String next() {
    if (i >= words.length) throw const BvhError("The file ends too soon.");
    return words[i++];
  }

  double number() {
    var w = next();
    var v = double.tryParse(w);
    if (v == null) throw BvhError("\"$w\" is not a number.");
    return v;
  }

  if (next().toUpperCase() != "HIERARCHY") {
    throw const BvhError("This is not a BVH file: it does not start with "
        "HIERARCHY.");
  }
  var joints = <BvhJoint>[];
  var stack = <int>[];
  var count = 0;
  while (i < words.length) {
    var w = next();
    var upper = w.toUpperCase();
    if (upper == "MOTION") break;
    if (upper == "ROOT" || upper == "JOINT") {
      var name = next();
      if (next() != "{") throw BvhError("Expected { after $name.");
      if (next().toUpperCase() != "OFFSET") {
        throw BvhError("$name has no OFFSET.");
      }
      var offset = [number(), number(), number()];
      var channels = <String>[];
      if (words[i].toUpperCase() == "CHANNELS") {
        i++;
        var n = number().round();
        for (var k = 0; k < n; k++) {
          channels.add(next().toLowerCase());
        }
      }
      joints.add(BvhJoint(name, stack.isEmpty ? -1 : stack.last, offset,
          channels, count));
      count += channels.length;
      stack.add(joints.length - 1);
    } else if (upper == "END") {
      // An end site: a point past the last joint, with no numbers of its
      // own. Skipped -- our bones end at joints.
      next();
      if (next() != "{") throw const BvhError("Expected { after End Site.");
      while (next() != "}") {}
    } else if (w == "}") {
      if (stack.isNotEmpty) stack.removeLast();
    }
  }
  if (joints.isEmpty) throw const BvhError("The file has no joints.");
  if (next().toUpperCase() != "FRAMES:") {
    throw const BvhError("Expected Frames: after MOTION.");
  }
  var frameCount = number().round();
  if (next().toUpperCase() != "FRAME") throw const BvhError("Expected Frame Time.");
  next(); // "Time:"
  var frameTime = number();
  var frames = <List<double>>[];
  for (var f = 0; f < frameCount && i < words.length; f++) {
    frames.add([for (var k = 0; k < count; k++) number()]);
  }
  if (frames.isEmpty) throw const BvhError("The file has no frames.");
  return Bvh(joints, frames, frameTime > 0 ? frameTime : 1 / 30);
}

/// _Mat is a turn, as a 3 by 3 matrix by rows.
typedef _Mat = List<double>;

_Mat _mul(_Mat a, _Mat b) => [
      for (var r = 0; r < 3; r++)
        for (var c = 0; c < 3; c++)
          a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c],
    ];

List<double> _apply(_Mat m, List<double> v) => [
      m[0] * v[0] + m[1] * v[1] + m[2] * v[2],
      m[3] * v[0] + m[4] * v[1] + m[5] * v[2],
      m[6] * v[0] + m[7] * v[1] + m[8] * v[2],
    ];

_Mat _turn(String axis, double degrees) {
  var r = degrees * math.pi / 180, c = math.cos(r), s = math.sin(r);
  return switch (axis) {
    "x" => [1, 0, 0, 0, c, -s, 0, s, c],
    "y" => [c, 0, s, 0, 1, 0, -s, 0, c],
    _ => [c, -s, 0, s, c, 0, 0, 0, 1],
  };
}

/// _positions is where each joint of [bvh] is in frame [f].
/// bvhPositions is where each joint of [bvh] is in frame [f].
List<List<double>> bvhPositions(Bvh bvh, int f) => _positions(bvh, f);

List<List<double>> _positions(Bvh bvh, int f) {
  var row = bvh.frames[f];
  var turns = <_Mat>[];
  var at = <List<double>>[];
  for (var j in bvh.joints) {
    var local = <double>[...j.offset];
    _Mat turn = const [1, 0, 0, 0, 1, 0, 0, 0, 1];
    for (var (k, ch) in j.channels.indexed) {
      var v = row[j.first + k];
      switch (ch) {
        case "xposition":
          local[0] += v;
        case "yposition":
          local[1] += v;
        case "zposition":
          local[2] += v;
        case "xrotation":
          turn = _mul(turn, _turn("x", v));
        case "yrotation":
          turn = _mul(turn, _turn("y", v));
        case "zrotation":
          turn = _mul(turn, _turn("z", v));
      }
    }
    if (j.parent < 0) {
      turns.add(turn);
      at.add(local);
    } else {
      var pt = turns[j.parent], pp = at[j.parent];
      var step = _apply(pt, local);
      at.add([pp[0] + step[0], pp[1] + step[1], pp[2] + step[2]]);
      turns.add(_mul(pt, turn));
    }
  }
  return at;
}

/// _find is the joint whose name, without any "prefix:", is one of [names],
/// ignoring case -- the names the common rigs use for the same joint.
int _find(List<String> joints, List<String> names) {
  for (var name in names) {
    for (var (i, j) in joints.indexed) {
      var n = j.split(":").last.toLowerCase();
      if (n == name) return i;
    }
  }
  return -1;
}

/// BvhRig is which joints of a BVH skeleton stand for which of ours.
class _BvhRig {
  final int hips, chest, head;
  final int lUpLeg, lLeg, lFoot, rUpLeg, rLeg, rFoot;
  final int lArm, lForeArm, lHand, rArm, rForeArm, rHand;

  _BvhRig(List<String> b)
      : hips = _find(b, ["hips", "hip", "pelvis", "root"]),
        chest = _find(b, ["neck", "spine2", "chest2", "chest", "spine1", "spine"]),
        head = _find(b, ["head"]),
        lUpLeg = _find(b, ["leftupleg", "lthigh", "leftthigh", "l_thigh", "lhipjoint"]),
        lLeg = _find(b, ["leftleg", "lshin", "leftshin", "l_knee", "leftlowleg"]),
        lFoot = _find(b, ["leftfoot", "lfoot", "l_foot", "leftankle"]),
        rUpLeg = _find(b, ["rightupleg", "rthigh", "rightthigh", "r_thigh", "rhipjoint"]),
        rLeg = _find(b, ["rightleg", "rshin", "rightshin", "r_knee", "rightlowleg"]),
        rFoot = _find(b, ["rightfoot", "rfoot", "r_foot", "rightankle"]),
        lArm = _find(b, ["leftarm", "lshldr", "leftuparm", "l_shoulder", "lhumerus"]),
        lForeArm = _find(b, ["leftforearm", "lforearm", "leftlowarm", "l_elbow", "lradius"]),
        lHand = _find(b, ["lefthand", "lhand", "l_wrist", "lwrist"]),
        rArm = _find(b, ["rightarm", "rshldr", "rightuparm", "r_shoulder", "rhumerus"]),
        rForeArm = _find(b, ["rightforearm", "rforearm", "rightlowarm", "r_elbow", "rradius"]),
        rHand = _find(b, ["righthand", "rhand", "r_wrist", "rwrist"]);

  List<String> get missing => [
        for (var (n, i) in [
          ("hips", hips),
          ("head", head),
          ("left thigh", lUpLeg),
          ("left knee", lLeg),
          ("left foot", lFoot),
          ("right thigh", rUpLeg),
          ("right knee", rLeg),
          ("right foot", rFoot),
          ("left arm", lArm),
          ("left forearm", lForeArm),
          ("left hand", lHand),
          ("right arm", rArm),
          ("right forearm", rForeArm),
          ("right hand", rHand),
        ])
          if (i < 0) n,
      ];
}

/// bvhPoses is [bvh] as poses of a character [headsTall] heads tall, one for
/// each frame at [frameRate], from its first frame. Throws a BvhError when
/// the skeleton is missing a joint our bones need.
List<CharacterPose> bvhPoses(Bvh bvh,
        {required int frameRate, required double headsTall}) =>
    motionPoses(
        JointMotion([for (var j in bvh.joints) j.name], bvh.frames.length,
            bvh.frameTime, (f) => _positions(bvh, f)),
        frameRate: frameRate,
        headsTall: headsTall);

/// motionPoses is [motion] as poses of a character [headsTall] heads tall,
/// one for each frame at [frameRate], from its first frame. Throws a
/// MotionError when the skeleton is missing a joint our bones need.
///
/// The skeleton's left is the character's own left, which faces the reader
/// on the page's right -- our "R" bones.
List<CharacterPose> motionPoses(JointMotion motion,
    {required int frameRate, required double headsTall}) {
  var rig = _BvhRig(motion.names);
  if (rig.missing.isNotEmpty) {
    throw MotionError("The skeleton has no joint for the "
        "${rig.missing.join(", ")}.");
  }
  if (motion.frameCount <= 0) {
    throw const MotionError("The file has no frames of motion in it.");
  }
  // How far a lift is: the skeleton's own leg length is our leg's, in
  // heads.
  var rest = motion.positionsAt(0);
  double dist(List<double> a, List<double> b) => math.sqrt(
      math.pow(a[0] - b[0], 2) + math.pow(a[1] - b[1], 2) + math.pow(a[2] - b[2], 2));
  var leg = dist(rest[rig.lUpLeg], rest[rig.lLeg]) +
      dist(rest[rig.lLeg], rest[rig.lFoot]);
  var ourLeg = 0.52 * (headsTall - 1);
  var groundHips = rest[rig.hips][1];

  var out = <CharacterPose>[];
  var count = math.max(1, (motion.seconds * frameRate).round());
  for (var f = 0; f < count; f++) {
    var src = math.min(motion.frameCount - 1,
        (f / frameRate / motion.frameTime).round());
    var p = motion.positionsAt(src);
    List<double> sub(int a, int b) =>
        [p[b][0] - p[a][0], p[b][1] - p[a][1], p[b][2] - p[a][2]];

    // The body's own frame: across from its right hip to its left, which is
    // the page's right facing the reader; down; and forwards.
    var across = sub(rig.rUpLeg, rig.lUpLeg);
    across = _unit([across[0], 0, across[2]]);
    // BVH is y up; ours is y down. Forward is across turned a quarter, in
    // the ground plane.
    var forward = [-across[2], 0.0, across[0]];
    var turn = math.atan2(-forward[0], forward[2]) * 180 / math.pi;
    List<double> body(List<double> v) {
      // Into the body's frame: x across, y down, z forward.
      return [
        v[0] * across[0] + v[2] * across[2],
        -v[1],
        v[0] * forward[0] + v[2] * forward[2],
      ];
    }

    var pose = CharacterPose.rest.withTurn(turn).withLift(
        leg <= 0 ? 0 : (p[rig.hips][1] - groundHips) / leg * ourLeg);

    // Each bone pointed as its pair of joints are, in its parent's frame.
    (double, double) angles(List<double> d) {
      var u = _unit(d);
      return (
        math.atan2(-u[0], u[1]) * 180 / math.pi,
        math.asin(u[2].clamp(-1.0, 1.0)) * 180 / math.pi
      );
    }

    _Mat frame(double spread, double swing) =>
        _mul(_turn("z", spread), _turn("x", swing));
    List<double> inFrame(_Mat m, List<double> v) => [
          m[0] * v[0] + m[3] * v[1] + m[6] * v[2],
          m[1] * v[0] + m[4] * v[1] + m[7] * v[2],
          m[2] * v[0] + m[5] * v[1] + m[8] * v[2],
        ];

    // The spine points up from the hips, and ours is a bone that would
    // hang down turned over: read the other way, the same two angles say
    // where it points.
    var spineDir = body(sub(rig.hips, rig.chest));
    var (ss, sw) = angles([-spineDir[0], -spineDir[1], -spineDir[2]]);
    // Our spine's swing counts forward lean as positive, the other way
    // round from a hanging bone's -- see CharacterRig.of.
    pose = pose.withAngle(CharacterBone.spine, ss).withSwing(CharacterBone.spine, -sw);
    var spine = frame(ss, sw);

    void limb(CharacterBone upper, CharacterBone lower, int a, int b, int c,
        _Mat parent) {
      var (us, uw) = angles(inFrame(parent, body(sub(a, b))));
      var upperFrame = _mul(parent, frame(us, uw));
      var (ls, lw) = angles(inFrame(upperFrame, body(sub(b, c))));
      pose = pose
          .withAngle(upper, us)
          .withSwing(upper, uw)
          .withAngle(lower, ls)
          .withSwing(lower, lw);
    }

    const flat = <double>[1, 0, 0, 0, 1, 0, 0, 0, 1];
    limb(CharacterBone.upperArmR, CharacterBone.foreArmR, rig.lArm,
        rig.lForeArm, rig.lHand, spine);
    limb(CharacterBone.upperArmL, CharacterBone.foreArmL, rig.rArm,
        rig.rForeArm, rig.rHand, spine);
    limb(CharacterBone.thighR, CharacterBone.shinR, rig.lUpLeg, rig.lLeg,
        rig.lFoot, flat);
    limb(CharacterBone.thighL, CharacterBone.shinL, rig.rUpLeg, rig.rLeg,
        rig.rFoot, flat);

    var neck = body(sub(rig.chest, rig.head));
    var (hs, _) = angles([-neck[0], -neck[1], -neck[2]]);
    pose = pose.withAngle(CharacterBone.head, hs - ss);
    out.add(pose);
  }
  return out;
}

List<double> _unit(List<double> v) {
  var l = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
  return l == 0 ? [0, 1, 0] : [v[0] / l, v[1] / l, v[2] / l];
}
