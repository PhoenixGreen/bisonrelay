import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/character_move.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_scene.dart';
import 'package:flutter_vrm/flutter_vrm.dart';
import 'package:vector_math/vector_math.dart' as vm;

// vrm_pose.dart stands a new 3D character as its Move settings say
// (character_move.dart): the hips, spine and head turned; the legs solved
// to feet planted where the stance puts them; each hand shaped, the thumb
// closed round a fist; and the arms solved to where the stance has the
// hands -- worked out from where this body's shoulders, hips and head are,
// so a stance fits however long its arms and legs are, and kept outside
// the body. Ported from the Studio's approved prototype. All in the
// model's own space: up is +y, it faces +z, and its left is +x.

typedef _V = vm.Vector3;
typedef _Q = vm.Quaternion;

_V _v(double x, double y, double z) => _V(x, y, z);

/// _euler is a turn by [x], then [y], then [z] about the axes, as the
/// prototype's three.js Euler of order XYZ.
_Q _euler(double x, double y, double z) =>
    _Q.axisAngle(_v(1, 0, 0), x) *
    _Q.axisAngle(_v(0, 1, 0), y) *
    _Q.axisAngle(_v(0, 0, 1), z);

double _clamp(double v, double lo, double hi) => v.clamp(lo, hi).toDouble();

/// _HandShape is a hand: each finger's three joints curled toward the
/// palm, how far apart they spread, the thumb's curl and its turn across
/// the palm, and which fingers a closed thumb lies over.
class _HandShape {
  final List<double> f;
  final double spread;
  final List<double> thumb;
  final List<double>? opp;
  final Map<String, List<double>> finger;
  final List<String> wrap;
  const _HandShape(
      {required this.f,
      this.spread = 0,
      required this.thumb,
      this.opp,
      this.finger = const {},
      this.wrap = const []});
}

const _fistF = [1.5, 1.65, 1.05], _fistThumb = [0.6, 0.75, 0.8];
const _fistOpp = [0.45, 0.0, 0.0];
const Map<String, _HandShape> _hands = {
  "relaxed": _HandShape(
      f: [0.38, 0.55, 0.32],
      spread: 0.03,
      thumb: [0.25, 0.2, 0.25],
      finger: {
        "Index": [0.22, 0.38, 0.22],
        "Ring": [0.45, 0.62, 0.36],
        "Little": [0.52, 0.68, 0.4],
      }),
  "open": _HandShape(f: [0, 0.02, 0], spread: 0.12, thumb: [-0.1, 0, 0]),
  "fist": _HandShape(
      f: _fistF,
      thumb: _fistThumb,
      opp: _fistOpp,
      wrap: ["Middle", "Middle", "Ring"]),
  "point": _HandShape(f: _fistF, thumb: _fistThumb, opp: _fistOpp, finger: {
    "Index": [0, 0.02, 0]
  }, wrap: [
    "Middle",
    "Ring"
  ]),
  "peace": _HandShape(
      f: _fistF,
      thumb: _fistThumb,
      opp: _fistOpp,
      spread: 0.22,
      finger: {
        "Index": [0, 0.02, 0],
        "Middle": [0, 0.02, 0]
      },
      wrap: [
        "Ring",
        "Little"
      ]),
  "thumbsup": _HandShape(f: _fistF, thumb: [-0.2, -0.05, 0], opp: [0, 0, 0]),
  "loose": _HandShape(
      f: [0.85, 1.1, 0.7],
      spread: 0.02,
      thumb: [0.45, 0.4, 0.4],
      opp: [0.3, 0, 0]),
};

/// _Landmarks are where the body's parts are now, for placing the hands:
/// [s] is 1 for the left, -1 for the right.
class _Landmarks {
  final double u, arm;
  final Map<int, _V> shoulder, hip, knee;
  final _V chest, head, navel, chin;
  _Landmarks(this.u, this.arm, this.shoulder, this.hip, this.knee, this.chest,
      this.head, this.navel)
      : chin = head + _v(0, -0.07, 0.07) * u;
  _V v(double x, double y, double z) => _v(x * u, y * u, z * u);
}

typedef _Place = _V Function(_Landmarks l, int s);

/// _Stance is one of [moveStances]: body turns, feet apart, and where the
/// hands go.
class _Stance {
  final List<double>? spine, head;
  final double feet, hipShift, hipRoll, knees, crouch, shoulders;
  final Map<String, double> footFwd;
  final _Place? hand;
  final Map<String, _Place> hands;
  final Map<String, String> handShape;
  final List<double> Function(int s)? pole;

  /// palm is the way the left palm faces -- the right's mirrored -- or by
  /// hand, as [palms] has it.
  final List<double>? palm;
  final Map<String, List<double>> palms;
  const _Stance(
      {this.spine,
      this.head,
      this.feet = 0,
      this.hipShift = 0,
      this.hipRoll = 0,
      this.knees = 0,
      this.crouch = 0,
      this.shoulders = 0,
      this.footFwd = const {},
      this.hand,
      this.hands = const {},
      this.handShape = const {},
      this.pole,
      this.palm,
      this.palms = const {}});

  List<double> palmOf(String k, int s) {
    final p = palm;
    if (p != null) return [s * p[0], p[1], p[2]];
    return palms[k] ?? [-s.toDouble(), 0, 0];
  }
}

final Map<String, _Stance> _stances = {
  "Relaxed": const _Stance(),
  "Confident":
      const _Stance(spine: [-0.06, 0, 0], head: [-0.06, 0, 0], feet: 0.06),
  "Hands on hips": _Stance(
      feet: 0.05,
      hand: (l, s) => l.hip[s]! + l.v(s * 0.075, 0.07, 0),
      pole: (s) => [s * 1.0, 0.1, -0.7],
      spine: const [-0.04, 0, 0]),
  "Arms crossed": _Stance(
      hand: (l, s) => l.chest + l.v(-s * 0.06, -0.11, 0.14),
      pole: (s) => [s * 0.9, -0.7, -0.1],
      spine: const [-0.05, 0, 0],
      head: const [-0.04, 0, 0],
      palm: const [0, 0.3, -1]),
  "Thinking": _Stance(
      hands: {
        "R": (l, s) => l.chin + l.v(0, -0.035, 0.06),
        "L": (l, s) => l.navel + l.v(-0.06, 0.02, 0.12),
      },
      handShape: const {"R": "fist"},
      pole: (s) => [s * 0.6, -1, 0.1],
      head: const [0.12, 0.1, 0.12],
      palms: const {
        "R": [0, 0.6, -1],
        "L": [0, 1, 0]
      }),
  "Wave": _Stance(
      hands: {"R": (l, s) => l.shoulder[-1]! + l.v(-0.17, 0.3, 0.06)},
      handShape: const {"R": "open"},
      pole: (s) => [s * 1.0, -0.8, 0.2],
      head: const [0, 0, 0.1],
      palms: const {
        "R": [0, 0, 1]
      }),
  "Pointing": _Stance(
      hands: {"R": (l, s) => l.shoulder[-1]! + l.v(-0.06, 0.04, l.arm * 0.92)},
      handShape: const {"R": "point"},
      pole: (s) => [s * 0.5, -1, 0],
      spine: const [0, 0.12, 0],
      palms: const {
        "R": [0, -1, 0]
      }),
  "Peace": _Stance(
      hands: {"R": (l, s) => l.head + l.v(-0.13, -0.03, 0.12)},
      handShape: const {"R": "peace"},
      pole: (s) => [s * 1.0, -0.8, 0],
      head: const [0, 0, 0.18],
      palms: const {
        "R": [0, 0, 1]
      }),
  "Cheer": _Stance(
      hand: (l, s) => l.shoulder[s]! + l.v(s * 0.13, l.arm * 0.88, 0.06),
      handShape: const {"L": "fist", "R": "fist"},
      pole: (s) => [s * 1.0, 0, -0.4],
      spine: const [-0.08, 0, 0],
      head: const [-0.15, 0, 0],
      palm: const [0, 0, 1]),
  "Hands behind": _Stance(
      hand: (l, s) => l.hip[s]! + l.v(-s * 0.035, -0.01, -0.13),
      pole: (s) => [s * 1.0, -0.3, -0.4],
      spine: const [-0.06, 0, 0],
      palm: const [0, 0, -1]),
  "Shy": _Stance(
      hand: (l, s) => l.navel + l.v(s * 0.02, -0.16, 0.14),
      pole: (s) => [s * 1.0, -0.4, -0.5],
      head: const [0.2, 0.15, 0.18],
      feet: -0.02,
      knees: 0.06),
  "Shrug": _Stance(
      hand: (l, s) => l.shoulder[s]! + l.v(s * 0.2, -0.27, 0.17),
      handShape: const {"L": "open", "R": "open"},
      pole: (s) => [s * 0.3, -1, -0.2],
      head: const [0, 0, 0.16],
      shoulders: 0.12,
      palm: const [0, 1, 0]),
  "Hero": _Stance(
      feet: 0.14,
      hand: (l, s) => l.hip[s]! + l.v(s * 0.075, 0.07, 0),
      handShape: const {"L": "fist", "R": "fist"},
      pole: (s) => [s * 1.0, 0.1, -0.7],
      spine: const [-0.1, 0, 0],
      head: const [-0.1, 0, 0]),
  "Weight on one leg": const _Stance(
      hipShift: 0.035,
      hipRoll: 0.07,
      spine: [0, 0, -0.06],
      footFwd: {"R": 0.08},
      knees: 0.08,
      head: [0, 0, 0.06]),
  "Crouch": _Stance(
      crouch: 0.16,
      feet: 0.08,
      hand: (l, s) => l.knee[s]! + l.v(s * 0.01, 0.06, 0.07),
      pole: (s) => [s * 1.0, 0, -0.3],
      spine: const [0.35, 0, 0],
      head: const [-0.25, 0, 0],
      palm: const [0, -1, 0]),
  "Fighting guard": _Stance(
      feet: 0.1,
      footFwd: const {"L": 0.12, "R": -0.06},
      crouch: 0.05,
      hand: (l, s) => l.chin + l.v(s * 0.09, -0.05, 0.17 + (s > 0 ? 0.06 : 0)),
      handShape: const {"L": "fist", "R": "fist"},
      pole: (s) => [s * 1.0, -1, -0.2],
      spine: const [0.08, -0.25, 0],
      head: const [0.05, 0.2, 0],
      palm: const [-1, 0, -0.4]),
};

/// _Motion is one frame of a motion: what it adds to the stance, in metres
/// and radians -- the hips' move and turn, the spine and head, each foot
/// ([forward, up, heel-up pitch, toes bend, on the ground]), each hand --
/// and where it takes the hands instead of the stance.
class _Motion {
  double dy = 0, dx = 0, yaw = 0, roll = 0, root = 0;
  List<double> spine = [0, 0, 0], head = [0, 0, 0];
  Map<String, List<double>> foot = {
    "L": [0, 0, 0],
    "R": [0, 0, 0]
  };
  Map<String, List<double>> hand = {};
  Map<String, _Place> handAt = {};
  Map<String, String> handShape = {};
  Map<String, List<double>> palm = {};
  Map<String, List<double> Function(int s)> pole = {};
  Map<String, double>? armSwing;
  bool run = false;
  double? bend, clap, bow;
}

double _smooth(double x) {
  final t = x.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// _motionAt is motion [name] [t] seconds in, walked as [walk] says, for a
/// body of size [u]. Walk and run step properly: the foot on the ground
/// slides back steadily for most of the step, then swings forward, lifted.
_Motion _motionAt(String name, double t, Map<String, double> walk, double u) {
  final o = _Motion();
  double w(String k) => walk[k] ?? moveWalkDefaults[k]!;
  const tau = math.pi * 2;
  switch (name) {
    case "Idle":
      o.spine[0] = 0.015 * math.sin(t * 1.6);
      o.dx = 0.006 * u * math.sin(t * 0.5);
      o.head[1] = 0.05 * math.sin(t * 0.37);
      o.roll = 0.015 * math.sin(t * 0.5);
    case "Walk" || "Run":
      final run = name == "Run";
      final cad = (run ? 1.4 : 0.85) * (0.7 + 0.6 * w("pace")),
          sf = run ? 0.38 : 0.6;
      final stride = (run ? 0.42 : 0.26) * u * (0.5 + w("stride")),
          lift = (run ? 0.18 : 0.07) * u * (0.6 + 0.8 * w("stride"));
      final legZ = <String, double>{};
      for (final (k, off) in const [("L", 0.0), ("R", 0.5)]) {
        final p = (t * cad + off) % 1;
        final strike = run ? -0.12 : -0.34,
            flatAt = run ? 0.08 : 0.14,
            riseAt = run ? 0.42 : 0.6,
            toeOff = (run ? 0.85 : 0.62) + 0.35 * w("push");
        double z, y, pitch, toes, planted;
        if (p < sf) {
          final q = p / sf;
          z = stride * (0.5 - q);
          y = 0;
          planted = 1;
          pitch = q < flatAt
              ? strike * (1 - _smooth(q / flatAt))
              : q > riseAt
                  ? toeOff * _smooth((q - riseAt) / (1 - riseAt))
                  : 0;
          toes = pitch > 0 ? -pitch * 0.95 : 0;
        } else {
          final q = (p - sf) / (1 - sf);
          z = stride * (-0.5 + _smooth(q));
          y = lift * math.sin(math.pi * math.min(1, q * 1.08));
          planted = 0;
          pitch = q < 0.45
              ? toeOff + (-0.15 - toeOff) * _smooth(q / 0.45)
              : -0.15 + (strike + 0.15) * _smooth((q - 0.45) / 0.55);
          toes = 0.12 * math.sin(math.pi * q);
        }
        o.foot[k] = [z, y, pitch, toes, planted];
        legZ[k] = z;
      }
      // Each arm swings against its own leg, in an arc from the shoulder;
      // the hips turn with the legs and the chest against them.
      o.armSwing = {
        "L": legZ["L"]! / (stride / 2),
        "R": legZ["R"]! / (stride / 2)
      };
      o.run = run;
      if (run) o.handShape = {"L": "loose", "R": "loose"};
      final pL = (t * cad) % 1;
      o.dy = (run ? -0.035 : -0.02) *
              u *
              (0.3 + 1.4 * w("bounce")) *
              (0.5 + 0.5 * math.cos(tau * 2 * pL)) +
          (run ? 0.03 * u : 0.008 * u);
      o.dx = 0.018 * u * w("sway") * math.sin(tau * pL);
      o.roll = 0.05 * w("sway") * math.sin(tau * pL);
      o.yaw = -1.6 * (legZ["L"]! - legZ["R"]!) / u * 0.12;
      o.spine = [(run ? 0.2 : 0.04) * (0.3 + 1.4 * w("lean")), -0.6 * o.yaw, 0];
      o.head = [-0.4 * o.spine[0], 0.4 * o.yaw, 0];
      o.bend = run ? 1.4 : 0.25;
    case "Jump":
      final c = (t * 0.8) % 1;
      double bump(double x, double a, double b) => x <= a || x >= b
          ? 0
          : math.pow(math.sin((x - a) / (b - a) * math.pi), 2).toDouble();
      final crouch = bump(c, 0, 0.3),
          air = bump(c, 0.22, 0.62),
          land = bump(c, 0.55, 0.85);
      o.dy = (-0.12 * crouch - 0.08 * land) * u;
      o.root = 0.28 * u * air;
      o.spine[0] = 0.25 * (crouch + land) - 0.08 * air;
      for (final k in const ["L", "R"]) {
        o.hand[k] = [
          0,
          (0.4 * air - 0.05 * crouch) * u,
          (-0.1 * crouch + 0.08 * air) * u
        ];
        o.foot[k] = [0, 0, 0.4 * air];
      }
    case "Wave":
      o.handAt = {"R": (l, s) => l.shoulder[s]! + l.v(s * 0.17, 0.3, 0.06)};
      o.handShape = {"R": "open"};
      o.palm = {
        "R": [0, 0, 1]
      };
      o.pole = {
        "R": (s) => [s * 1.0, -0.8, 0.2]
      };
      o.hand["R"] = [0.07 * u * math.sin(t * 8), 0, 0];
      o.head[2] = 0.08 * math.sin(t * 1.5);
    case "Nod":
      o.head[0] = 0.18 * math.max(0, math.sin(t * 5));
    case "Shake head":
      o.head[1] = 0.3 * math.sin(t * 6);
    case "Clap":
      o.clap = 0.5 + 0.5 * math.cos(t * 9);
      o.handShape = {"L": "open", "R": "open"};
    case "Bow":
      final c = _smooth(math.sin(t * 1.2) * 1.2);
      o.spine[0] = 0.85 * c;
      o.head[0] = 0.25 * c;
      o.bow = c;
    case "Dance":
      final ph = t * tau * 1.1;
      o.dy = -0.03 * u * math.sin(ph).abs();
      o.dx = 0.03 * u * math.sin(ph / 2);
      o.roll = 0.08 * math.sin(ph / 2);
      o.yaw = 0.15 * math.sin(ph / 4);
      o.hand["L"] = [0, 0.25 * u * math.max(0, math.sin(ph / 2)), 0.08 * u];
      o.hand["R"] = [0, 0.25 * u * math.max(0, -math.sin(ph / 2)), 0.08 * u];
      o.head = [0.06 * math.sin(ph), 0, 0.1 * math.sin(ph / 2)];
    case "Look around":
      o.head[1] = 0.6 * math.sin(t * 0.7);
      o.head[0] = 0.1 * math.sin(t * 0.45);
      o.spine[1] = 0.15 * math.sin(t * 0.7);
  }
  return o;
}

/// _motionParts are what each motion takes over from the stance; the rest
/// of the body keeps the stance.
const Map<String, Set<String>> _motionParts = {
  "Walk": {"legs", "spine", "head", "arms"},
  "Run": {"legs", "spine", "head", "arms"},
  "Jump": {"legs", "spine", "head", "arms"},
  "Dance": {"legs", "spine", "head", "arms"},
  "Bow": {"legs", "spine", "head", "arms"},
  "Clap": {"arms"},
  "Wave": {"armR", "head"},
  "Nod": {"head"},
  "Shake head": {"head"},
  "Look around": {"head", "spine"},
};

/// _scaled is [o] at [w] of its strength, mirrored left for right with
/// [mirror].
_Motion _scaled(_Motion o, double w, bool mirror) {
  if (w == 1 && !mirror) return o;
  List<double> k(List<double> v) => [for (final x in v) x * w];
  o
    ..dy *= w
    ..dx *= w
    ..yaw *= w
    ..roll *= w
    ..root *= w
    ..spine = k(o.spine)
    ..head = k(o.head)
    ..foot = {
      for (final e in o.foot.entries)
        e.key: [for (final (i, x) in e.value.indexed) i == 4 ? x : x * w]
    }
    ..hand = {for (final e in o.hand.entries) e.key: k(e.value)};
  if (o.bend != null) o.bend = o.bend! * w;
  if (o.bow != null) o.bow = o.bow! * w;
  if (o.armSwing != null) {
    o.armSwing = {for (final e in o.armSwing!.entries) e.key: e.value * w};
  }
  if (o.clap != null && w < 0.35) o.clap = null;
  if (mirror) {
    Map<String, T> swap<T>(Map<String, T> m) =>
        {for (final e in m.entries) e.key == "L" ? "R" : "L": e.value};
    o
      ..foot = swap(o.foot)
      ..hand = {
        for (final e in swap(o.hand).entries)
          e.key: [-e.value[0], e.value[1], e.value[2]]
      }
      ..handAt = swap(o.handAt)
      ..handShape = swap(o.handShape)
      ..palm = swap(o.palm)
      ..pole = swap(o.pole)
      ..dx = -o.dx
      ..yaw = -o.yaw
      ..roll = -o.roll
      ..spine = [o.spine[0], -o.spine[1], -o.spine[2]]
      ..head = [o.head[0], -o.head[1], -o.head[2]];
    if (o.armSwing != null) o.armSwing = swap(o.armSwing!);
  }
  return o;
}

bool _ownsArm(Set<String> own, String k) =>
    own.contains("arms") || own.contains("arm$k");

/// _Rest is the body at rest: where its feet stand, how big it is, its
/// limbs' lengths, and its torso's shape slice by slice -- clothes and all
/// -- for keeping hands, elbows and forearms outside it.
class _Rest {
  final _V fL, fR, hips;
  final double u, ua, fa, arm, foot;

  /// slices are, below the spine (0) and above it (1), each two
  /// centimetres up from the hips or the chest: the least and most x and z.
  final List<Map<int, List<double>>> slices;
  _Rest(this.fL, this.fR, this.hips, this.u, this.ua, this.fa, this.arm,
      this.foot, this.slices);
}

/// VrmPoser poses one avatar.
class VrmPoser {
  final ShapedAvatar avatar;
  VrmPoser(this.avatar);

  VrmHumanoidRig get _h => avatar.avatar.humanoid;

  _Rest? _rest;
  int _restVersion = -1;

  /// _restWorld is where the body's bones are at rest, in the scene: for
  /// framing it, steady while it jumps or crouches.
  final Map<VrmHumanBone, _V> _restWorld = {};

  /// restWorld is where [b] is at rest, in the scene, once measured.
  _V? restWorld(VrmHumanBone b) => _restWorld[b]?.clone();

  /// What each eased value was last frame.
  final Map<String, Object> _eased = {};

  _V _p(VrmHumanBone b) => _h.modelPosition(b) ?? _V.zero();

  bool _has(VrmHumanBone b) => _h.node(b) != null;

  void _sync() => _h.apply();

  /// _acc is how far [b] is turned from rest, in the model's space.
  _Q _acc(VrmHumanBone b) {
    final m = _h.normalizedModelRotation(b);
    return m == null ? _Q.identity() : _Q.fromRotation(m);
  }

  /// _parentAcc is how far [b]'s parent is turned: [b]'s own, less its own.
  _Q _parentAcc(VrmHumanBone b) =>
      _acc(b) * (_h.normalizedRotation(b) ?? _Q.identity()).inverted();

  /// _turnBy turns [b] further by [r], a turn in the model's space.
  void _turnBy(VrmHumanBone b, _Q r) {
    final np = _parentAcc(b);
    final n = _h.normalizedRotation(b) ?? _Q.identity();
    _h.setNormalizedRotation(b, (np.inverted() * r * np * n)..normalize());
  }

  /// _turnTo turns [b] to [want], a turn from rest in the model's space.
  void _turnTo(VrmHumanBone b, _Q want) {
    final np = _parentAcc(b);
    _h.setNormalizedRotation(b, (np.inverted() * want)..normalize());
  }

  static _Q _between(_V from, _V to) {
    final a = from.normalized(), b = to.normalized();
    final d = a.dot(b);
    if (d > 0.999999) return _Q.identity();
    if (d < -0.999999) {
      var axis = _v(1, 0, 0).cross(a);
      if (axis.length2 < 1e-6) axis = _v(0, 1, 0).cross(a);
      return _Q.axisAngle(axis.normalized(), math.pi);
    }
    return _Q.axisAngle(a.cross(b).normalized(), math.acos(d.clamp(-1.0, 1.0)));
  }

  // Eased values: each moves toward what it is set to by [a] of the way.
  double _e1(String k, double v, double a) {
    final was = _eased[k];
    final next = was is double ? was + (v - was) * a : v;
    _eased[k] = next;
    return next;
  }

  _V _ev(String k, _V v, double a) {
    final was = _eased[k];
    final next = was is _V ? was + (v - was) * a : v.clone();
    _eased[k] = next;
    return next.clone();
  }

  List<double> _el(String k, List<double> v, double a) {
    final was = _eased[k];
    final next = was is List<double>
        ? [for (var i = 0; i < v.length; i++) was[i] + (v[i] - was[i]) * a]
        : List<double>.of(v);
    _eased[k] = next;
    return next;
  }

  /// _measure measures the body at rest.
  _Rest _measure() {
    _h.resetPose();
    _sync();
    final fL = _p(VrmHumanBone.leftFoot), fR = _p(VrmHumanBone.rightFoot);
    final hd = _p(VrmHumanBone.head), hips = _p(VrmHumanBone.hips);
    final ua = _p(VrmHumanBone.leftUpperArm),
        la = _p(VrmHumanBone.leftLowerArm),
        ha = _p(VrmHumanBone.leftHand);
    final toe = _has(VrmHumanBone.leftToes)
        ? _p(VrmHumanBone.leftToes)
        : fL + _v(0, -0.06, 0.1);
    final u = (hd.y - fL.y) / 1.08;
    _restWorld.clear();
    for (final b in _h.bones) {
      final n = _h.node(b);
      if (n != null) _restWorld[b] = n.globalTransform.getTranslation();
    }
    final spineY = _p(VrmHumanBone.spine).y;
    final frames = [
      hips,
      _p(_has(VrmHumanBone.upperChest)
          ? VrmHumanBone.upperChest
          : VrmHumanBone.chest),
    ];
    final slices = [<int, List<double>>{}, <int, List<double>>{}];
    final cloth = [<int, List<double>>{}, <int, List<double>>{}];
    for (final p in avatar.bodyAtRest()) {
      final k = p.y < spineY ? 0 : 1;
      final lx = p.x - frames[k].x,
          ly = p.y - frames[k].y,
          lz = p.z - frames[k].z;
      // Close-fitting clothes count as the body; a skirt's flare a third
      // of the way out, or the legs could not move under it.
      final into = p.loose ? cloth[k] : slices[k];
      final key = (ly / 0.02).round();
      final r = into[key];
      if (r == null) {
        into[key] = [lx, lx, lz, lz];
      } else {
        r[0] = math.min(r[0], lx);
        r[1] = math.max(r[1], lx);
        r[2] = math.min(r[2], lz);
        r[3] = math.max(r[3], lz);
      }
    }
    // Loose cloth reaches a third of the way from the body to its edge.
    for (final k in const [0, 1]) {
      for (final MapEntry(key: key, value: c) in cloth[k].entries) {
        final b = slices[k][key] ??
            [
              (c[0] + c[1]) / 2,
              (c[0] + c[1]) / 2,
              (c[2] + c[3]) / 2,
              (c[2] + c[3]) / 2
            ];
        double soft(double x, double y) => x + (y - x) * 0.3;
        slices[k][key] = [
          math.min(b[0], soft(b[0], c[0])),
          math.max(b[1], soft(b[1], c[1])),
          math.min(b[2], soft(b[2], c[2])),
          math.max(b[3], soft(b[3], c[3])),
        ];
      }
    }
    return _Rest(
        fL,
        fR,
        hips,
        u,
        ua.distanceTo(la),
        la.distanceTo(ha),
        ua.distanceTo(la) + la.distanceTo(ha),
        fL.distanceTo(toe) + 0.03 * u,
        slices);
  }

  /// _outOfBody is [p] moved out of the body to its surface, and [margin]
  /// past it; null where it is not inside.
  _V? _outOfBody(_V p, double margin) {
    final r = _rest!;
    final k = p.y < _p(VrmHumanBone.spine).y ? 0 : 1;
    final bone = k == 0
        ? VrmHumanBone.hips
        : _has(VrmHumanBone.upperChest)
            ? VrmHumanBone.upperChest
            : VrmHumanBone.chest;
    final at = _p(bone), turn = _acc(bone);
    final loc = turn.inverted().rotated(p - at);
    final key = (loc.y / 0.02).round();
    List<double>? box;
    for (final kk in [key - 1, key, key + 1]) {
      final x = r.slices[k][kk];
      if (x == null) continue;
      box = box == null
          ? List.of(x)
          : [
              math.min(box[0], x[0]),
              math.max(box[1], x[1]),
              math.min(box[2], x[2]),
              math.max(box[3], x[3])
            ];
    }
    if (box == null) return null;
    final cx = (box[0] + box[1]) / 2, cz = (box[2] + box[3]) / 2;
    final rx = (box[1] - box[0]) / 2 + margin,
        rz = (box[3] - box[2]) / 2 + margin;
    final dx = loc.x - cx, dz = loc.z - cz;
    final q = (dx / rx) * (dx / rx) + (dz / rz) * (dz / rz);
    if (q >= 1) return null;
    final f = 1 / math.sqrt(math.max(q, 1e-4));
    loc
      ..x = cx + dx * f
      ..z = cz + dz * f;
    return turn.rotated(loc) + at;
  }

  /// _outOfArm is [p] moved out of arm [side]'s upper arm and forearm to
  /// [r] from them, where it is nearer.
  _V _outOfArm(int side, _V p, double r) {
    final upper =
            side > 0 ? VrmHumanBone.leftUpperArm : VrmHumanBone.rightUpperArm,
        lower =
            side > 0 ? VrmHumanBone.leftLowerArm : VrmHumanBone.rightLowerArm,
        hand = side > 0 ? VrmHumanBone.leftHand : VrmHumanBone.rightHand;
    if (!_has(upper) || !_has(lower) || !_has(hand)) return p;
    var out = p;
    final s0 = _p(upper), e0 = _p(lower), h0 = _p(hand);
    for (final (a, b) in [(s0, e0), (e0, h0)]) {
      final ab = b - a;
      final t = ab.length2 < 1e-12
          ? 0.0
          : ((out - a).dot(ab) / ab.length2).clamp(0.0, 1.0);
      final c = a + ab * t, d = out - c;
      if (d.length >= r) continue;
      final dir = d.length2 < 1e-10 ? _v(0, 0, 1) : d.normalized();
      out = c + dir * r;
    }
    return out;
  }

  /// _solveLimb turns two bones -- upper arm and forearm, thigh and shin --
  /// so that [end] reaches [target], the middle joint bending toward
  /// [pole] and never further than a real joint bends. An elbow that would
  /// go into the body bends away from it; a palm is turned to face [palm],
  /// mostly in the forearm, a little at the wrist.
  void _solveLimb(VrmHumanBone upper, VrmHumanBone lower, VrmHumanBone end,
      _V target, List<double> pole,
      {double minBend = 0.45,
      int side = 1,
      List<double>? palm,
      _V? Function(_V)? avoid,
      double? ease,
      VrmHumanBone? hand}) {
    if (!_has(upper) || !_has(lower) || !_has(end)) return;
    final s0 = _p(upper), e0 = _p(lower), w0 = _p(end);
    final a = s0.distanceTo(e0), b = e0.distanceTo(w0);
    if (a < 1e-6 || b < 1e-6) return;
    final dMin = math.sqrt(a * a + b * b - 2 * a * b * math.cos(minBend));
    final toT = target - s0;
    final d = _clamp(toT.length, dMin, a + b - 1e-4);
    final u = toT.length2 < 1e-12 ? _v(0, -1, 0) : toT.normalized();
    _V elbowFor(List<double> pl) {
      var p = _v(pl[0], pl[1], pl[2]).normalized();
      // A pole along the reach gives no bend: lean on a sideways one.
      if (p.dot(u).abs() > 0.97) {
        p = _v(0, 0, 1).cross(u).length2 > 1e-4
            ? _v(-u.z, 0, u.x).normalized()
            : _v(1, 0, 0);
      }
      final v = (p - u * p.dot(u)).normalized();
      final cosA = _clamp((a * a + d * d - b * b) / (2 * a * d), -1, 1);
      return s0 + u * (a * cosA) + v * (a * math.sqrt(1 - cosA * cosA));
    }

    var e = elbowFor(pole);
    final out = avoid?.call(e);
    if (out != null) {
      final push = (out - e).normalized();
      e = elbowFor([
        pole[0] * 0.3 + push.x,
        pole[1] * 0.3 + push.y,
        pole[2] * 0.3 + push.z
      ]);
    }
    // The middle joint's direction eases, so a pose crossing a hard case
    // swings the elbow round rather than flipping it.
    if (ease != null) {
      final dir = _ev("mid-${upper.name}", (e - s0).normalized(), ease)
        ..normalize();
      e = s0 + dir * a;
    }
    _turnBy(upper, _between(e0 - s0, e - s0));
    _sync();
    final e1 = _p(lower), w1 = _p(end);
    _turnBy(lower, _between(w1 - e1, s0 + u * d - e1));
    _sync();
    if (palm == null || hand == null) return;
    final k = side > 0 ? "left" : "right";
    final index = VrmHumanBone.values.byName("${k}IndexProximal"),
        little = VrmHumanBone.values.byName("${k}LittleProximal");
    if (!_has(index) || !_has(little)) return;
    void twist(VrmHumanBone node, double share) {
      final w = _p(end), axis = (w - _p(lower)).normalized();
      final i = _p(index), l = _p(little);
      var n = (i - w).cross(l - i);
      if (side > 0) n = -n;
      _V flat(_V x) => (x - axis * x.dot(axis)).normalized();
      final p0 = flat(n), p1 = flat(_v(palm[0], palm[1], palm[2]));
      var raw = math.atan2(axis.dot(p0.cross(p1)), p0.dot(p1));
      // Keep turning the way it was going: no jump from +180 to -180.
      final key = "tw-${upper.name}-$share", prev = _eased[key];
      if (prev is double) {
        while (raw - prev > math.pi) {
          raw -= 2 * math.pi;
        }
        while (prev - raw > math.pi) {
          raw += 2 * math.pi;
        }
      }
      raw = _clamp(raw, -1.9, 1.9);
      final ang = (ease != null ? _e1(key, raw, ease) : raw) * share;
      _turnBy(node, _Q.axisAngle(axis, ang));
      _sync();
    }

    twist(lower, 0.7);
    twist(hand, 1);
  }

  VrmHumanBone? _bone(String name) =>
      VrmHumanBone.values.where((b) => b.name == name).firstOrNull;

  /// _fingers shapes hand [side] ("left" or "right") as [shape], [amt] of
  /// the way closed. In the model's space the left hand's fingers lie
  /// along +x, palm down, so curling toward the palm is a turn of -angle
  /// about z (and +angle for the right): the prototype's +side*angle was
  /// for three-vrm's rig, and here bent the fingers back.
  void _fingers(String side, String shape, double amt) {
    final sh = _hands[shape] ?? _hands["relaxed"]!;
    final s = side == "left" ? 1.0 : -1.0;
    for (final (fi, f) in const ["Index", "Middle", "Ring", "Little"].indexed) {
      final c = sh.finger[f] ?? sh.f;
      final spread = sh.spread * (fi - 1.2);
      for (final (ji, j)
          in const ["Proximal", "Intermediate", "Distal"].indexed) {
        final b = _bone("$side$f$j");
        if (b == null || !_has(b)) continue;
        _h.setNormalizedRotation(
            b, _euler(0, ji == 0 ? -s * spread : 0, -s * c[ji] * amt));
      }
    }
    // The thumb: turned under the palm about the hand's length, then each
    // joint curled about the axis across its own bend.
    final t = sh.thumb, opp = sh.opp ?? [0.25 * t[0], 0, 0];
    final flex = _v(1, 0, -s).normalized(), along = _v(1, 0, 0);
    for (final (ji, j) in const ["Metacarpal", "Proximal", "Distal"].indexed) {
      final b = _bone("${side}Thumb$j");
      if (b == null || !_has(b)) continue;
      _h.setNormalizedRotation(
          b, _Q.axisAngle(along, -opp[ji]) * _Q.axisAngle(flex, -t[ji] * amt));
    }
  }

  /// _wrapThumb lays a closed hand's thumb across the curled fingers: its
  /// tip brought, a joint at a time, onto the outside of their middle
  /// joints -- worked out on this hand's own bones.
  void _wrapThumb(String side, String shape, double amt) {
    final sh = _hands[shape];
    if (sh == null || sh.wrap.isEmpty || amt < 0.05) return;
    final hand = _bone("${side}Hand"),
        i1 = _bone("${side}IndexProximal"),
        l1 = _bone("${side}LittleProximal");
    final fingers = [
      for (final f in sh.wrap)
        if (_bone("$side${f}Intermediate") case final b? when _has(b)) b
    ];
    final t = [
      for (final j in const ["Metacarpal", "Proximal", "Distal"])
        _bone("${side}Thumb$j")
    ];
    if (hand == null ||
        i1 == null ||
        l1 == null ||
        !_has(hand) ||
        !_has(i1) ||
        !_has(l1) ||
        fingers.length < 2 ||
        t.any((b) => b == null || !_has(b))) {
      return;
    }
    _sync();
    final w = _p(hand);
    var n = (_p(i1) - w).cross(_p(l1) - _p(i1));
    if (side == "left") n = -n;
    n.normalize();
    final reach = _p(i1).distanceTo(_p(l1)) * 0.4;
    final mid = _V.zero();
    for (final b in fingers) {
      mid.add(_p(b));
    }
    final target = mid / fingers.length.toDouble() + n * reach;
    _V tip() {
      final a = _p(t[1]!), b = _p(t[2]!);
      return b + (b - a) * 0.85;
    }

    final order = [t[2]!, t[1]!, t[0]!];
    for (var pass = 0; pass < 6; pass++) {
      for (final b in order) {
        final j = _p(b);
        final full = _between(tip() - j, target - j);
        // As far as the hand is closed.
        final r = _nlerp(_Q.identity(), full, math.min(1, amt));
        _turnBy(b, r);
        _sync();
      }
    }
  }

  static _Q _nlerp(_Q a, _Q b, double t) {
    final dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
    final s = dot < 0 ? -1.0 : 1.0;
    return _Q(a.x + (b.x * s - a.x) * t, a.y + (b.y * s - a.y) * t,
        a.z + (b.z * s - a.z) * t, a.w + (b.w * s - a.w) * t)
      ..normalize();
  }

  /// pose stands the avatar as [m] says, [dt] seconds on from the last
  /// pose -- what changed eases there, as a body moves; at nought it is
  /// there at once -- and its motion [t] seconds in.
  ///
  /// A scene's motion clip plays at [strength], mirrored left for right
  /// with [mirror], taking over the parts it moves by [weight] -- nought to
  /// one as it fades in and out, the stance holding the rest.
  void pose(CharacterMove m, double dt,
      {double t = 0,
      double strength = 1,
      double weight = 1,
      bool mirror = false}) {
    if (_rest == null || _restVersion != avatar.restVersion) {
      _restVersion = avatar.restVersion;
      _rest = _measure();
    }
    final r = _rest!, u = r.u;
    final a = dt <= 0 ? 1.0 : 1 - math.exp(-dt / 0.16);
    final st0 = _stances[m.stance] ?? _stances["Relaxed"]!;
    final mo = _scaled(_motionAt(m.motion, t, m.walk, u),
        strength * weight.clamp(0.0, 1.0), mirror);
    var own = _motionParts[m.motion] ?? const <String>{};
    if (mirror && (own.contains("armR") || own.contains("armL"))) {
      own = {
        for (final p in own)
          p == "armR"
              ? "armL"
              : p == "armL"
                  ? "armR"
                  : p
      };
    }
    // The stance, with what the motion takes over let go as far as it has.
    final w = weight.clamp(0.0, 1.0), keep = 1 - w;
    final legs = own.contains("legs") ? keep : 1.0;
    List<double>? sc(List<double>? v, bool owned) =>
        v == null || !owned ? v : [for (final x in v) x * keep];
    final st = _Stance(
      spine: sc(st0.spine, own.contains("spine")),
      head: sc(st0.head, own.contains("head")),
      feet: st0.feet * legs,
      hipShift: st0.hipShift * legs,
      hipRoll: st0.hipRoll * legs,
      knees: st0.knees * legs,
      crouch: st0.crouch * legs,
      shoulders: _ownsArm(own, "L") || _ownsArm(own, "R")
          ? st0.shoulders * keep
          : st0.shoulders,
      footFwd: {for (final e in st0.footFwd.entries) e.key: e.value * legs},
      handShape: st0.handShape,
    );
    double bd(String k) => m.bodyOf(k);
    _h.resetPose();

    // The body: hips, spine and head, each kept within what a body can do.
    final crouch = st.crouch + 0.3 * bd("crouch");
    // Dragged by hand, the hips go no further than a body bends.
    _V off(String k) {
      final o = m.offsetOf(k);
      return _v(o[0], o[1], o[2]);
    }

    final hd0 = off("hips");
    final hipRaw = _v(
        _clamp((st.hipShift + 0.05 * bd("shift")) * u + mo.dx + hd0.x,
            -0.15 * u, 0.15 * u),
        _clamp(-crouch * u + mo.dy + hd0.y, -0.42 * u, 0.04 * u) + mo.root,
        _clamp(hd0.z, -0.15 * u, 0.15 * u));
    final hipOff = _ev("hip", hipRaw, a);
    _h.setHipsPosition(r.hips + hipOff);
    final hr = _el(
        "hipRot",
        [
          0,
          _clamp(mo.yaw + 0.2 * bd("twist"), -0.5, 0.5),
          _clamp(st.hipRoll + mo.roll + 0.1 * bd("shift"), -0.25, 0.25)
        ],
        a);
    _h.setNormalizedRotation(VrmHumanBone.hips, _euler(hr[0], hr[1], hr[2]));
    final sp = st.spine ?? const [0.0, 0.0, 0.0],
        hd = st.head ?? const [0.0, 0.0, 0.0];
    final spine = _el(
        "spine",
        [
          _clamp(sp[0] + mo.spine[0] + 0.35 * bd("lean"), -0.45, 1.0),
          _clamp(sp[1] + mo.spine[1] + 0.4 * bd("twist"), -0.7, 0.7),
          _clamp(sp[2] + mo.spine[2] + 0.25 * bd("side"), -0.4, 0.4)
        ],
        a);
    for (final (b, k) in const [
      (VrmHumanBone.spine, 0.5),
      (VrmHumanBone.chest, 0.3),
      (VrmHumanBone.upperChest, 0.2)
    ]) {
      if (_has(b)) {
        _h.setNormalizedRotation(
            b, _euler(spine[0] * k, spine[1] * k, spine[2] * k));
      }
    }
    final hh = _el(
        "head",
        [
          _clamp(hd[0] + mo.head[0] + 0.4 * bd("headNod"), -0.6, 0.75),
          _clamp(hd[1] + mo.head[1] + 0.6 * bd("headTurn"), -1.1, 1.1),
          _clamp(hd[2] + mo.head[2] + 0.3 * bd("headTilt"), -0.45, 0.45)
        ],
        a);
    _h.setNormalizedRotation(
        VrmHumanBone.neck, _euler(hh[0] * 0.4, hh[1] * 0.4, hh[2] * 0.4));
    _h.setNormalizedRotation(
        VrmHumanBone.head, _euler(hh[0] * 0.6, hh[1] * 0.6, hh[2] * 0.6));
    final sh = _e1("shoulders", st.shoulders, a);
    if (sh != 0) {
      _h.setNormalizedRotation(VrmHumanBone.leftShoulder, _euler(0, 0, -sh));
      _h.setNormalizedRotation(VrmHumanBone.rightShoulder, _euler(0, 0, sh));
    }
    _sync();

    // Where things are now, for placing the hands.
    final l = _Landmarks(
      u,
      r.arm / u,
      {1: _p(VrmHumanBone.leftUpperArm), -1: _p(VrmHumanBone.rightUpperArm)},
      {1: _p(VrmHumanBone.leftUpperLeg), -1: _p(VrmHumanBone.rightUpperLeg)},
      {1: _p(VrmHumanBone.leftLowerLeg), -1: _p(VrmHumanBone.rightLowerLeg)},
      _p(_has(VrmHumanBone.upperChest)
          ? VrmHumanBone.upperChest
          : VrmHumanBone.chest),
      _p(VrmHumanBone.head),
      _p(VrmHumanBone.spine),
    );

    // Legs: feet planted where the stance puts them, knees forward; each
    // ankle turns, and a raised heel lifts onto the ball of the foot.
    final footAt = <String, _V>{};
    for (final s in const [1, -1]) {
      final k = s > 0 ? "L" : "R";
      final rest = s > 0 ? r.fL : r.fR;
      final heel = _clamp(m.footOf(k, "heel"), 0, 1) * 0.9;
      final f = mo.foot[k]!;
      final base = _v(
          rest.x + s * st.feet * u, rest.y, rest.z + (st.footFwd[k] ?? 0) * u);
      // A foot on the ground rolls: back on the heel, up on the ball.
      final p = f[2], planted = f.length > 4 ? f[4] : 0.0;
      final rollUp = planted *
              (p > 0
                  ? r.foot * math.sin(p) * 0.92
                  : 0.28 * r.foot * math.sin(-p)),
          rollBack = planted * (p > 0 ? r.foot * (1 - math.cos(p)) * 0.5 : 0);
      final tgt = base +
          _v(0, f[1] + mo.root + r.foot * math.sin(heel) + rollUp,
              f[0] - r.foot * (1 - math.cos(heel)) * 0.5 - rollBack);
      // Dragged by hand: on or over the floor, never so high the thigh goes
      // into the body, and within a stride of where it stands.
      tgt.add(off("foot$k"));
      final hipsY = r.hips.y + hipOff.y;
      tgt
        ..y = math.min(tgt.y, hipsY - 0.25 * u)
        ..z = _clamp(tgt.z, rest.z - 0.6 * u, rest.z + 0.6 * u)
        ..x = _clamp(tgt.x, rest.x - 0.4 * u, rest.x + 0.4 * u);
      tgt.y = math.max(rest.y + mo.root * 0.9, tgt.y);
      footAt[k] =
          _ev("foot$k", tgt, f[0] != 0 || f[1] != 0 ? math.max(a, 0.6) : a);
    }
    // Feet never cross: each keeps to its own side.
    final gap = 0.06 * u;
    if (footAt["L"]!.x - footAt["R"]!.x < gap) {
      final mid = (footAt["L"]!.x + footAt["R"]!.x) / 2;
      footAt["L"]!.x = mid + gap / 2;
      footAt["R"]!.x = mid - gap / 2;
    }
    for (final s in const [1, -1]) {
      final k = s > 0 ? "L" : "R";
      _solveLimb(
          s > 0 ? VrmHumanBone.leftUpperLeg : VrmHumanBone.rightUpperLeg,
          s > 0 ? VrmHumanBone.leftLowerLeg : VrmHumanBone.rightLowerLeg,
          s > 0 ? VrmHumanBone.leftFoot : VrmHumanBone.rightFoot,
          footAt[k]!,
          [s * 0.1 - s * st.knees * 3, 0, 1],
          minBend: 0.55,
          ease: math.max(a, 0.5));
      final heel = _clamp(m.footOf(k, "heel"), 0, 1) * 0.9;
      final f = mo.foot[k]!;
      final pitch = _e1("pitch$k", f[2] + 0.6 * m.footOf(k, "flex") + heel,
              f.length > 4 ? math.max(a, 0.6) : a),
          roll = _e1("roll$k", 0.35 * m.footOf(k, "roll"), a);
      final foot = s > 0 ? VrmHumanBone.leftFoot : VrmHumanBone.rightFoot;
      if (_has(foot)) {
        _turnTo(foot, _euler(_clamp(pitch, -0.6, 1.2), hr[1] * 0.5, s * roll));
      }
      final toes = _e1(
          "toes$k",
          -heel * 0.9 + 0.5 * m.footOf(k, "toes") + (f.length > 3 ? f[3] : 0),
          math.max(a, 0.6));
      final tb = s > 0 ? VrmHumanBone.leftToes : VrmHumanBone.rightToes;
      if (_has(tb)) {
        _h.setNormalizedRotation(tb, _euler(_clamp(toes, -1, 0.6), 0, 0));
      }
    }
    _sync();

    // Hands: each shaped as asked, or as the stance has it.
    for (final (side, k) in const [("left", "L"), ("right", "R")]) {
      final asked = k == "L" ? m.handL : m.handR;
      // A motion moving this arm shapes its hand as it moves -- a thumb
      // held up through a walk looked wrong; otherwise as asked, or as the
      // stance has it.
      final shape = _ownsArm(own, k) && w > 0.5
          ? mo.handShape[k] ?? "relaxed"
          : asked != "relaxed"
              ? asked
              : st.handShape[k] ?? "relaxed";
      if (_eased["shape$k"] != shape) {
        _eased["shape$k"] = shape;
        if (_eased.containsKey("curl$k")) _eased["curl$k"] = 0.2;
      }
      final curl = _e1("curl$k", 1, a);
      _fingers(side, shape, curl);
      _wrapThumb(side, shape, curl);
    }

    // Arms: each hand where the stance puts it, or hanging at the side --
    // never inside the body, nor reaching behind it to the other side.
    final margin = 0.045 * u;
    for (final s in const [1, -1]) {
      final k = s > 0 ? "L" : "R";
      final place = st0.hands[k] ?? st0.hand, mine = _ownsArm(own, k);
      final hang = l.shoulder[s]! + l.v(s * 0.06, -l.arm * 0.93, 0.03);
      var base = place == null ? hang : place(l, s);
      if (mine) {
        // Where the motion has the hand, in place of the stance.
        var mb = mo.handAt[k]?.call(l, s) ?? hang;
        final swing = mo.armSwing;
        if (swing != null) {
          // The upper arm swings from the shoulder; the elbow bends more as
          // it comes forward walking, and holds near a right angle running.
          final sw = swing[k] ?? 0,
              amp = (mo.run ? 0.8 : 0.42) *
                  (0.3 + 1.4 * (m.walk["swing"] ?? moveWalkDefaults["swing"]!));
          final th = sw * amp,
              e = mo.run ? 1.5 + 0.25 * sw : 0.18 + 0.4 * math.max(0, sw);
          final d1 = _v(s * 0.12, -math.cos(th), math.sin(th)).normalized();
          final d2 = _v(-s * (mo.run ? 0.3 : 0.04), -math.cos(th + e),
                  math.sin(th + e))
              .normalized();
          mb = l.shoulder[s]! + d1 * r.ua + d2 * r.fa;
        }
        final bend = mo.bend;
        if (bend != null && !mo.handAt.containsKey(k) && swing == null) {
          mb = l.shoulder[s]! +
              l.v(s * 0.07, -l.arm * (1 - 0.18 * bend), 0.04 + 0.12 * bend);
        }
        final clap = mo.clap;
        if (clap != null) {
          mb = l.chest + l.v(s * (0.02 + 0.12 * clap), -0.08, 0.24);
        }
        final bow = mo.bow;
        if (bow != null) {
          mb = mb + (l.knee[s]! + l.v(s * 0.05, 0.12, 0.06) - mb) * (bow * 0.6);
        }
        // From where the stance has it, as far as the motion has taken it.
        base = base + (mb - base) * w;
      }
      final hv =
          mine ? mo.hand[k] ?? const [0.0, 0.0, 0.0] : const [0.0, 0.0, 0.0];
      // Dragged by hand as well: then kept out of the body as any hand is.
      var tgt = base + _v(hv[0], hv[1], hv[2]) + off("hand$k");
      if (tgt.z < l.chest.z - 0.04 * u && s * (tgt.x - l.chest.x) < 0.03 * u) {
        tgt.x = l.chest.x + s * 0.03 * u;
      }
      // Not through the other arm: the hand kept out of its upper arm and
      // forearm, as they are now.
      tgt = _outOfArm(-s, tgt, 0.05 * u);
      final inside = _outOfBody(tgt, margin);
      if (inside != null) {
        _V? front;
        for (var dz = 0.01; dz <= 0.2; dz += 0.01) {
          final p = tgt + _v(0, 0, dz * u);
          if (_outOfBody(p, margin) == null) {
            front = p;
            break;
          }
        }
        tgt = front != null &&
                (front.x - l.shoulder[s]!.x).abs() <
                    (inside.x - l.shoulder[s]!.x).abs()
            ? front
            : inside;
      }
      // The forearm too: its middle kept out of the body.
      final mid = l.shoulder[s]! + (tgt - l.shoulder[s]!) * 0.62;
      final midOut = _outOfBody(mid, 0.04 * u);
      if (midOut != null) tgt = tgt + (midOut - mid);
      final tE = _ev("hand$k", tgt, a);
      final pole = _ev("pole$k", () {
        final def = [s * 0.35, -0.2, -1.0];
        final p = mine && w > 0.5
            ? mo.pole[k]?.call(s) ?? def
            : st0.pole?.call(s) ?? def;
        return _v(p[0], p[1], p[2]);
      }(), a);
      final pl = mine && w > 0.5
          ? mo.palm[k] ?? [-s.toDouble(), 0, 0]
          : st0.palmOf(k, s);
      final palm = _ev("palm$k", _v(pl[0], pl[1], pl[2]), a);
      _solveLimb(
          s > 0 ? VrmHumanBone.leftUpperArm : VrmHumanBone.rightUpperArm,
          s > 0 ? VrmHumanBone.leftLowerArm : VrmHumanBone.rightLowerArm,
          s > 0 ? VrmHumanBone.leftHand : VrmHumanBone.rightHand,
          tE,
          [pole.x, pole.y, pole.z],
          minBend: 0.5,
          side: s,
          palm: [palm.x, palm.y, palm.z],
          avoid: (e) => _outOfBody(e, 0.03 * u),
          ease: a,
          hand: s > 0 ? VrmHumanBone.leftHand : VrmHumanBone.rightHand);
    }
  }
}
