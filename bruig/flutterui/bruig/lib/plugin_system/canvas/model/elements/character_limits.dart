import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';

// character_limits.dart is how far each joint of a body can go: a knee
// bends one way, an elbow does not bend backwards, a head turns so far.
// What the doll is held to as it is posed -- see character_doll_pose.dart.

/// BoneLimit is how far a bone can turn: in the picture, and towards the
/// reader or away -- each from the least to the most, in degrees.
class BoneLimit {
  final double angleMin, angleMax, swingMin, swingMax;
  const BoneLimit(this.angleMin, this.angleMax, this.swingMin, this.swingMax);

  static const BoneLimit free = BoneLimit(-360, 360, -360, 360);
}

/// _limits is each bone's, as the page-left side has it; the right side's
/// turn in the picture is the same, mirrored.
const Map<CharacterBone, BoneLimit> _limits = {
  CharacterBone.spine: BoneLimit(-40, 40, -35, 80),
  CharacterBone.hips: BoneLimit(-25, 25, -20, 20),
  CharacterBone.head: BoneLimit(-45, 45, -50, 50),
  CharacterBone.upperArmL: BoneLimit(-60, 180, -80, 180),
  CharacterBone.foreArmL: BoneLimit(-160, 160, -5, 160),
  CharacterBone.thighL: BoneLimit(-35, 90, -45, 130),
  CharacterBone.shinL: BoneLimit(-20, 20, -160, 5),
  CharacterBone.wristL: BoneLimit(-80, 80, -80, 80),
  CharacterBone.palmL: BoneLimit(-90, 90, -90, 90),
  CharacterBone.thumbL: BoneLimit(-20, 110, -30, 30),
  CharacterBone.indexL: BoneLimit(-20, 110, -30, 30),
  CharacterBone.middleL: BoneLimit(-20, 110, -30, 30),
  CharacterBone.ringL: BoneLimit(-20, 110, -30, 30),
  CharacterBone.littleL: BoneLimit(-20, 110, -30, 30),
  CharacterBone.spreadL: BoneLimit(-10, 40, -10, 10),
  CharacterBone.ankleL: BoneLimit(-45, 45, -50, 60),
  CharacterBone.toesL: BoneLimit(-40, 60, -40, 60),
};

/// _left is the page-left bone a right one mirrors, and whether it is one.
(CharacterBone, bool) _left(CharacterBone bone) {
  if (!bone.name.endsWith("R")) return (bone, false);
  var name = "${bone.name.substring(0, bone.name.length - 1)}L";
  for (var b in CharacterBone.values) {
    if (b.name == name) return (b, true);
  }
  return (bone, false);
}

/// limitOf is how far [bone] can turn: the right side's turn in the
/// picture mirrored from the left's, for the bones whose turn mirrors.
BoneLimit limitOf(CharacterBone bone) {
  var (left, right) = _left(bone);
  var l = _limits[left];
  if (l == null) return BoneLimit.free;
  if (!right || !bone.mirrors) return l;
  return BoneLimit(-l.angleMax, -l.angleMin, l.swingMin, l.swingMax);
}

extension PoseLimits on CharacterPose {
  /// limited is this pose with every bone held within how far it can go.
  CharacterPose limited() {
    var angles = <CharacterBone, double>{};
    var swings = <CharacterBone, double>{};
    for (var e in this.angles.entries) {
      var l = limitOf(e.key);
      angles[e.key] = e.value.clamp(l.angleMin, l.angleMax).toDouble();
    }
    for (var e in this.swings.entries) {
      var l = limitOf(e.key);
      swings[e.key] = e.value.clamp(l.swingMin, l.swingMax).toDouble();
    }
    return withAngles(angles).withSwings(swings);
  }
}
