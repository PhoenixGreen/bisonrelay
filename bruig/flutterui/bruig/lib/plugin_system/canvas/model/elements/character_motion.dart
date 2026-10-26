import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';

// character_motion.dart is the motions a character can be given -- walking,
// waving, jumping -- and how a clip of one is laid over its pose.
//
// Each motion is written as a sum of time, not as keyframes: a walk is legs
// swinging on a sine and knees bending on the forward half of it. That is
// what lets a clip run at any speed and for any length, loop without a
// seam, and cost nothing to ship -- and, like every other movement here, it
// is the same on every play and in every export.
//
// A clip sits on one of three layers. A whole-body clip takes the pose over
// (a walk is the legs and the arms); an upper-body clip takes over the arms,
// the body and the head and leaves the legs to whatever they were doing (a
// wave while walking); an added clip is laid on top of everything (a nod,
// a sway).

/// MotionLayer is how a clip is laid over the pose.
enum MotionLayer {
  body("Whole body"),
  upper("Upper body"),
  added("Added on top");

  final String label;
  const MotionLayer(this.label);

  static MotionLayer fromName(String? name) =>
      values.firstWhere((l) => l.name == name, orElse: () => body);
}

/// MotionKind is one motion of the library.
enum MotionKind {
  walk("Walk", MotionLayer.body, 1.0, true),
  run("Run", MotionLayer.body, 0.62, true),
  jump("Jump", MotionLayer.body, 1.0, false),
  dance("Dance", MotionLayer.body, 0.9, true),
  wave("Wave", MotionLayer.upper, 0.9, true),
  point("Point", MotionLayer.upper, 1.2, false),
  clap("Clap", MotionLayer.upper, 0.5, true),
  cheer("Cheer", MotionLayer.upper, 0.7, true),
  shrug("Shrug", MotionLayer.upper, 1.1, false),
  talk("Talk with hands", MotionLayer.upper, 2.4, true),
  idle("Idle sway", MotionLayer.added, 4.0, true),
  nod("Nod", MotionLayer.added, 0.6, true),
  shake("Shake head", MotionLayer.added, 0.7, true),
  fly("Fly", MotionLayer.added, 0.5, true),
  swim("Swim", MotionLayer.added, 1.2, true);

  final String label;

  /// layer is the layer a new clip of this motion goes on.
  final MotionLayer layer;

  /// seconds is one cycle of it at its own speed: a stride and back for a
  /// walk, the whole of a jump.
  final double seconds;

  /// loops is whether it repeats for as long as its clip lasts, rather than
  /// playing once and holding its last pose.
  final bool loops;

  const MotionKind(this.label, this.layer, this.seconds, this.loops);

  static MotionKind fromName(String? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => walk);

  /// travels is how far this motion carries a character -- what "Walk
  /// across" moves it by -- in its own heights a second, at its own speed.
  double get travels => switch (this) {
        walk => 0.6,
        run => 1.5,
        _ => 0,
      };
}

/// MotionMove is what a motion does at one moment: the pose -- the whole of
/// it for a body or upper-body motion, an amount to add for an added one --
/// and what it adds to the face.
typedef MotionMove = ({CharacterPose pose, Map<FaceControl, double> face});

/// motionAt is [kind] [t] seconds in, at speed 1, mirrored left for right
/// with [mirror].
MotionMove motionAt(MotionKind kind, double t, {bool mirror = false}) {
  var move = _motion(kind, kind.loops ? t : t.clamp(0.0, kind.seconds));
  return mirror ? _mirrored(move) : move;
}

const _none = <FaceControl, double>{};

MotionMove _motion(MotionKind kind, double t) {
  var p = 2 * math.pi * t / kind.seconds;
  double s(double x) => math.sin(x);
  double c(double x) => math.cos(x);
  double fwd(double x) => math.max(0.0, x);
  // Arms a little away from the body, as a standing pose has them.
  const arms = {
    CharacterBone.upperArmL: 8.0,
    CharacterBone.upperArmR: -8.0,
  };
  switch (kind) {
    case MotionKind.walk:
      return (
        pose: CharacterPose(arms, {
          CharacterBone.spine: 4,
          CharacterBone.thighL: 24 * s(p),
          CharacterBone.thighR: -24 * s(p),
          // A knee bends while its leg comes through, and is straight when
          // the foot is planted.
          CharacterBone.shinL: -8 - 34 * fwd(c(p)),
          CharacterBone.shinR: -8 - 34 * fwd(-c(p)),
          CharacterBone.upperArmL: -20 * s(p),
          CharacterBone.upperArmR: 20 * s(p),
          CharacterBone.foreArmL: 12 + 10 * fwd(-s(p)),
          CharacterBone.foreArmR: 12 + 10 * fwd(s(p)),
        }, 0, 0.035 * (1 - c(2 * p)) / 2),
        face: _none,
      );
    case MotionKind.run:
      return (
        pose: CharacterPose(arms, {
          CharacterBone.spine: 12,
          CharacterBone.thighL: 40 * s(p),
          CharacterBone.thighR: -40 * s(p),
          CharacterBone.shinL: -20 - 70 * fwd(c(p)),
          CharacterBone.shinR: -20 - 70 * fwd(-c(p)),
          CharacterBone.upperArmL: -40 * s(p),
          CharacterBone.upperArmR: 40 * s(p),
          CharacterBone.foreArmL: 75,
          CharacterBone.foreArmR: 75,
        }, 0, 0.14 * s(2 * p).abs()),
        face: _none,
      );
    case MotionKind.jump:
      // Down, up, and down again: a crouch, a quarter of a second in the
      // air at its highest, and a crouch to land.
      var u = t / kind.seconds;
      double crouch(double x) => x < 0.25
          ? s(math.pi * x / 0.25 / 2)
          : x > 0.75
              ? s(math.pi * (1 - x) / 0.25 / 2)
              : 0;
      var air = u > 0.25 && u < 0.75 ? s(math.pi * (u - 0.25) / 0.5) : 0.0;
      var k = u < 0.25 ? crouch(u) : (u > 0.75 ? crouch(u) * 0.6 : 0.0);
      return (
        pose: CharacterPose({
          CharacterBone.upperArmL: 10 + 140 * air,
          CharacterBone.upperArmR: -10 - 140 * air,
          CharacterBone.thighL: 4 + 6 * air,
          CharacterBone.thighR: -4 - 6 * air,
        }, {
          CharacterBone.spine: 18 * k,
          CharacterBone.thighL: 45 * k,
          CharacterBone.thighR: 45 * k,
          CharacterBone.shinL: -80 * k,
          CharacterBone.shinR: -80 * k,
        }, 0, 0.9 * air - 0.25 * k),
        face: {FaceControl.browRaise: 0.6 * air, FaceControl.jaw: 0.3 * air},
      );
    case MotionKind.dance:
      return (
        pose: CharacterPose({
          CharacterBone.spine: 8 * s(p),
          CharacterBone.head: -6 * s(p),
          CharacterBone.upperArmL: 100 + 40 * s(p),
          CharacterBone.foreArmL: 40 * c(p),
          CharacterBone.upperArmR: -100 + 40 * s(p),
          CharacterBone.foreArmR: -40 * c(p),
          CharacterBone.thighL: 8 + 8 * s(p),
          CharacterBone.thighR: -8 + 8 * s(p),
        }, const {}, 0, 0.05 * s(2 * p).abs()),
        face: {FaceControl.smile: 0.6},
      );
    case MotionKind.wave:
      return (
        pose: const CharacterPose({
          CharacterBone.upperArmL: 8,
          CharacterBone.foreArmL: -4,
          CharacterBone.upperArmR: -130,
        }).withAngle(CharacterBone.foreArmR, -20 + 28 * s(p)),
        face: {FaceControl.smile: 0.6},
      );
    case MotionKind.point:
      // Raised in the first third, held, lowered in the last.
      var u = t / kind.seconds;
      var up = u < 0.25 ? s(math.pi * u / 0.5) : (u > 0.8 ? s(math.pi * (1 - u) / 0.4) : 1.0);
      return (
        pose: CharacterPose({
          CharacterBone.upperArmL: 8,
          CharacterBone.upperArmR: -8 - 87 * up,
          CharacterBone.head: -4 * up,
        }),
        face: _none,
      );
    case MotionKind.clap:
      var meet = fwd(s(p));
      return (
        pose: CharacterPose({
          CharacterBone.upperArmL: -10 + 18 * (1 - meet),
          CharacterBone.upperArmR: 10 - 18 * (1 - meet),
          CharacterBone.foreArmL: -60 + 20 * (1 - meet),
          CharacterBone.foreArmR: 60 - 20 * (1 - meet),
        }, const {
          CharacterBone.upperArmL: 30,
          CharacterBone.upperArmR: 30,
          CharacterBone.foreArmL: 50,
          CharacterBone.foreArmR: 50,
        }),
        face: {FaceControl.smile: 0.7},
      );
    case MotionKind.cheer:
      var pump = s(p);
      return (
        pose: CharacterPose({
          CharacterBone.upperArmL: 140 + 15 * pump,
          CharacterBone.foreArmL: 20 * pump,
          CharacterBone.upperArmR: -140 + 15 * pump,
          CharacterBone.foreArmR: 20 * pump,
          CharacterBone.head: 4 * pump,
        }),
        face: {FaceControl.smile: 1, FaceControl.jaw: 0.5},
      );
    case MotionKind.shrug:
      var up = s(math.pi * (t / kind.seconds).clamp(0.0, 1.0));
      return (
        // Elbows kept in, forearms out and towards the reader: palms up.
        pose: CharacterPose({
          CharacterBone.upperArmL: 8 + 8 * up,
          CharacterBone.foreArmL: 40 * up,
          CharacterBone.upperArmR: -8 - 8 * up,
          CharacterBone.foreArmR: -40 * up,
          CharacterBone.head: 10 * up,
        }, {
          CharacterBone.foreArmL: 70 * up,
          CharacterBone.foreArmR: 70 * up,
        }, 0, 0.03 * up),
        face: {FaceControl.browRaise: 0.7 * up, FaceControl.smile: -0.2 * up},
      );
    case MotionKind.talk:
      // Two hands moving at different paces, never quite in step.
      var a = s(p), b = s(p * 1.37 + 1);
      return (
        pose: CharacterPose({
          CharacterBone.upperArmL: 14 + 6 * a,
          CharacterBone.foreArmL: -50 - 25 * a,
          CharacterBone.upperArmR: -14 - 6 * b,
          CharacterBone.foreArmR: 50 + 25 * b,
          CharacterBone.head: 3 * b,
        }, {
          CharacterBone.upperArmL: 15,
          CharacterBone.upperArmR: 15,
          CharacterBone.foreArmL: 30 + 15 * a,
          CharacterBone.foreArmR: 30 + 15 * b,
        }),
        face: _none,
      );
    case MotionKind.idle:
      return (
        pose: CharacterPose({
          CharacterBone.spine: 1.5 * s(p),
          CharacterBone.head: 2 * s(p * 1.3 + 0.5),
          CharacterBone.upperArmL: 1.5 * s(p + 1),
          CharacterBone.upperArmR: -1.5 * s(p + 1),
        }),
        face: _none,
      );
    case MotionKind.nod:
      return (
        pose: CharacterPose.rest,
        face: {FaceControl.nod: 14 * fwd(s(p))},
      );
    case MotionKind.shake:
      return (
        pose: CharacterPose.rest,
        face: {FaceControl.turn: 22 * s(p)},
      );
    case MotionKind.fly:
      // Wings beating -- quicker up than down is not needed at this size --
      // the body lifted off the ground and bobbing with each beat, the legs
      // tucked up under it.
      return (
        pose: CharacterPose({
          CharacterBone.wings: 55 + 50 * s(p),
        }, {
          CharacterBone.thighL: 30,
          CharacterBone.thighR: 30,
          CharacterBone.shinL: -60,
          CharacterBone.shinR: -60,
        }, 0, 0.6 + 0.06 * s(p + 1)),
        face: _none,
      );
    case MotionKind.swim:
      // A sway down the body, the fins paddling in turn, floating.
      return (
        pose: CharacterPose({
          CharacterBone.spine: 8 * s(p),
          CharacterBone.head: -4 * s(p),
          CharacterBone.upperArmL: 20 * s(p),
          CharacterBone.upperArmR: -20 * s(p + math.pi),
          CharacterBone.wings: 20 + 20 * s(p),
        }, const {}, 0, 0.05 * s(p * 0.5)),
        face: _none,
      );
  }
}

/// _mirrored is [move] left for right: each bone's angles given to its
/// partner on the other side, the spreads turned the other way.
MotionMove _mirrored(MotionMove move) {
  CharacterBone other(CharacterBone b) => switch (b) {
        CharacterBone.upperArmL => CharacterBone.upperArmR,
        CharacterBone.upperArmR => CharacterBone.upperArmL,
        CharacterBone.foreArmL => CharacterBone.foreArmR,
        CharacterBone.foreArmR => CharacterBone.foreArmL,
        CharacterBone.thighL => CharacterBone.thighR,
        CharacterBone.thighR => CharacterBone.thighL,
        CharacterBone.shinL => CharacterBone.shinR,
        CharacterBone.shinR => CharacterBone.shinL,
        _ => b,
      };
  var p = move.pose;
  return (
    pose: CharacterPose({
      for (var b in CharacterBone.values) other(b): -p[b],
    }, {
      for (var b in CharacterBone.values) other(b): p.swing(b),
    }, -p.turn, p.lift),
    face: {
      for (var e in move.face.entries)
        e.key: e.key == FaceControl.turn || e.key == FaceControl.lookX
            ? -e.value
            : e.value,
    },
  );
}

/// upperBones are the bones an upper-body clip takes over.
const Set<CharacterBone> upperBones = {
  CharacterBone.spine,
  CharacterBone.head,
  CharacterBone.upperArmL,
  CharacterBone.foreArmL,
  CharacterBone.upperArmR,
  CharacterBone.foreArmR,
};

/// MotionClip is a motion laid on a character for a stretch of frames.
class MotionClip {
  final String id;
  final MotionKind kind;
  final MotionLayer layer;

  /// start and length are the frames it covers, on the character's own
  /// timeline.
  final int start;
  final int length;

  /// speed plays it faster or slower than its own pace.
  final double speed;

  /// strength is how much of it is laid on, nought to one.
  final double strength;

  /// blend is how many frames it takes to come in and to go out again.
  final int blend;

  final bool mirror;

  const MotionClip({
    required this.id,
    required this.kind,
    required this.layer,
    required this.start,
    required this.length,
    this.speed = 1,
    this.strength = 1,
    this.blend = 6,
    this.mirror = false,
  });

  int get end => start + length;

  /// weightAt is how much of it is on at [frame]: nothing outside it, coming
  /// in and going out over [blend] frames, [strength] in the middle.
  double weightAt(int frame) {
    if (frame < start || frame >= end) return 0;
    var into = frame - start, left = end - 1 - frame;
    var w = 1.0;
    if (blend > 0) {
      w = math.min(w, (into + 1) / (blend + 1));
      w = math.min(w, (left + 1) / (blend + 1));
    }
    return w * strength;
  }

  /// moveAt is the motion at [frame], at [frameRate].
  MotionMove moveAt(int frame, int frameRate) => motionAt(
      kind, (frame - start) / math.max(1, frameRate) * speed,
      mirror: mirror);

  MotionClip copyWith({
    MotionKind? kind,
    MotionLayer? layer,
    int? start,
    int? length,
    double? speed,
    double? strength,
    int? blend,
    bool? mirror,
  }) =>
      MotionClip(
        id: id,
        kind: kind ?? this.kind,
        layer: layer ?? this.layer,
        start: start ?? this.start,
        length: math.max(1, length ?? this.length),
        speed: (speed ?? this.speed).clamp(0.1, 4.0),
        strength: (strength ?? this.strength).clamp(0.0, 1.0),
        blend: math.max(0, blend ?? this.blend),
        mirror: mirror ?? this.mirror,
      );

  Map<String, dynamic> toJson() => {
        "id": id,
        "kind": kind.name,
        "layer": layer.name,
        "start": start,
        "length": length,
        if (speed != 1) "speed": speed,
        if (strength != 1) "strength": strength,
        if (blend != 6) "blend": blend,
        if (mirror) "mirror": true,
      };

  static MotionClip? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    var kind = MotionKind.fromName(json["kind"] as String?);
    return MotionClip(
      id: jsonString(json["id"], newElementId()),
      kind: kind,
      layer: json["layer"] is String
          ? MotionLayer.fromName(json["layer"] as String)
          : kind.layer,
      start: jsonInt(json["start"], 0),
      length: math.max(1, jsonInt(json["length"], 24)),
      speed: jsonDouble(json["speed"], 1).clamp(0.1, 4.0),
      strength: jsonDouble(json["strength"], 1).clamp(0.0, 1.0),
      blend: math.max(0, jsonInt(json["blend"], 6)),
      mirror: jsonBool(json["mirror"], false),
    );
  }
}

/// withMotions is [pose] and [face] with every clip of [clips] laid over
/// them at [frame], in order: whole body, then upper body, then added.
(CharacterPose, CharacterFace) withMotions(CharacterPose pose,
    CharacterFace face, List<MotionClip> clips, int frame, int frameRate) {
  if (clips.isEmpty) return (pose, face);
  for (var layer in MotionLayer.values) {
    for (var clip in clips) {
      if (clip.layer != layer) continue;
      var w = clip.weightAt(frame);
      if (w <= 0) continue;
      var move = clip.moveAt(frame, frameRate);
      pose = switch (layer) {
        // The body's own turn is where it is facing, which a walk does not
        // change.
        MotionLayer.body =>
          pose.lerp(move.pose.withTurn(pose.turn).withTilt(pose.tilt), w),
        MotionLayer.upper => pose.only(move.pose, upperBones, w),
        MotionLayer.added => pose.plus(move.pose, w),
      };
      if (move.face.isNotEmpty) {
        face = face.withControls({
          for (var e in move.face.entries)
            e.key: layer == MotionLayer.added
                ? face[e.key] + e.value * w
                : face[e.key] + (e.value - face[e.key]) * w,
        });
      }
    }
  }
  return (pose, face);
}
