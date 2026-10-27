import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';

// character_hands.dart is a sketch's hands and feet as a pose has them:
// how far each finger curls, how far apart they fan, how the wrist bends
// and the palm turns, and how a foot points and its toes bend. They are
// bones of the pose -- see CharacterBone -- so they key, ease and mirror as
// the arms and legs do, and a hand closing into a fist is a keyframe away.
//
// A hand is picked from a library of named shapes, as animators keep a
// hand chart -- open, a fist, pointing -- and each finger fine-tuned after;
// a foot from a few stances -- flat, on tiptoe, on the heel, pointed. A
// foot stays on the ground: rising on to the toes lifts the body, rather
// than pushing the toes through the floor. See CharacterRig.of.

/// Finger is one finger of a hand, the thumb first.
enum Finger {
  thumb("Thumb"),
  pointer("Index"),
  middle("Middle"),
  ring("Ring"),
  little("Little");

  final String label;
  const Finger(this.label);

  /// bone is this finger's bone on the hand on the page's left, or right.
  CharacterBone bone(bool left) => switch (this) {
        thumb => left ? CharacterBone.thumbL : CharacterBone.thumbR,
        pointer => left ? CharacterBone.indexL : CharacterBone.indexR,
        middle => left ? CharacterBone.middleL : CharacterBone.middleR,
        ring => left ? CharacterBone.ringL : CharacterBone.ringR,
        little => left ? CharacterBone.littleL : CharacterBone.littleR,
      };
}

CharacterBone spreadBone(bool left) =>
    left ? CharacterBone.spreadL : CharacterBone.spreadR;
CharacterBone wristBone(bool left) =>
    left ? CharacterBone.wristL : CharacterBone.wristR;
CharacterBone palmBone(bool left) =>
    left ? CharacterBone.palmL : CharacterBone.palmR;
CharacterBone ankleBone(bool left) =>
    left ? CharacterBone.ankleL : CharacterBone.ankleR;
CharacterBone toesBone(bool left) =>
    left ? CharacterBone.toesL : CharacterBone.toesR;

/// HandShape is a hand as a shape: how far each finger curls, thumb first,
/// in degrees at each knuckle, and how far apart they fan.
class HandShape {
  final String name;
  final List<double> curls;
  final double spread;
  const HandShape(this.name, this.curls, this.spread);

  /// of is the shape the hand on the page's left, or right, has in [pose].
  factory HandShape.of(CharacterPose pose, bool left) => HandShape("", [
        for (var f in Finger.values) pose[f.bone(left)],
      ], pose[spreadBone(left)]);

  /// on is [pose] with the hand on the page's left, or right, made this
  /// shape.
  CharacterPose on(CharacterPose pose, bool left) => pose.withAngles({
        for (var f in Finger.values) f.bone(left): curls[f.index],
        spreadBone(left): spread,
      });

  /// same is whether [other] is this shape, to a degree or so.
  bool same(HandShape other) {
    for (var i = 0; i < Finger.values.length; i++) {
      if ((curls[i] - other.curls[i]).abs() > 1) return false;
    }
    return (spread - other.spread).abs() <= 1;
  }
}

/// handShapes is the hand chart: the shapes a hand is picked from. At rest
/// is a hand as a character starts, the fingers together and straight.
const List<HandShape> handShapes = [
  HandShape("At rest", [0, 0, 0, 0, 0], 0),
  HandShape("Relaxed", [15, 20, 26, 32, 38], 3),
  HandShape("Open", [0, 0, 0, 0, 0], 12),
  HandShape("Fist", [70, 92, 94, 96, 98], 0),
  HandShape("Point", [70, 0, 94, 96, 98], 0),
  HandShape("Peace", [70, 0, 0, 94, 96], 9),
  HandShape("Grip", [35, 52, 58, 62, 66], 1),
  HandShape("Thumbs up", [0, 92, 94, 96, 98], 0),
  HandShape("Claw", [25, 55, 55, 55, 55], 10),
];

/// handShapeName is the name of the shape in [handShapes] the hand on the
/// page's left, or right, has in [pose], or null for one of its own.
String? handShapeName(CharacterPose pose, bool left) {
  var shape = HandShape.of(pose, left);
  for (var s in handShapes) {
    if (s.same(shape)) return s.name;
  }
  return null;
}

/// FootStance is a foot as it stands: how far it points its toes down --
/// up as it goes negative -- and how far its toes bend up at the ball.
class FootStance {
  final String name;
  final double point;
  final double toes;
  const FootStance(this.name, this.point, this.toes);

  /// of is the stance the foot on the page's left, or right, has in [pose].
  factory FootStance.of(CharacterPose pose, bool left) => FootStance(
      "", pose.swing(ankleBone(left)), pose.swing(toesBone(left)));

  CharacterPose on(CharacterPose pose, bool left) => pose.withSwings({
        ankleBone(left): point,
        toesBone(left): toes,
      });

  bool same(FootStance other) =>
      (point - other.point).abs() <= 1 && (toes - other.toes).abs() <= 1;
}

/// footStances is what a foot stands like: flat, the heel raised with the
/// toes kept on the ground, the toes raised with the heel kept there, and
/// pointed, as a dancer or a diver points one.
const List<FootStance> footStances = [
  FootStance("Flat", 0, 0),
  FootStance("Tiptoe", 42, 42),
  FootStance("On the heel", -25, 0),
  FootStance("Pointed", 65, -10),
];

String? footStanceName(CharacterPose pose, bool left) {
  var stance = FootStance.of(pose, left);
  for (var s in footStances) {
    if (s.same(stance)) return s.name;
  }
  return null;
}
