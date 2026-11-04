import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';

// motion_presets.dart is the ready-made motions. Each writes a clip's keys;
// after that the clip is only its keys, and editing one sets
// MotionClip.edited.
//
// Where a motion means a place it keys a place, not a number: a slide in
// comes from just off the edge whatever the page's shape.

/// MotionWay is which way a slide goes.
enum MotionWay {
  left("The left edge"),
  right("The right edge"),
  top("Above"),
  bottom("Below");

  final String label;
  const MotionWay(this.label);
}

/// MotionPreset is one ready-made motion.
class MotionPreset {
  final String name;
  final MotionKind kind;

  /// ways is the directions it can go, where it has a choice; the first is
  /// its own.
  final List<MotionWay> ways;

  /// aims is whether it goes to, or looks at, another element.
  final bool aims;
  final double length;
  final ClipHold? after;

  /// loops is whether it goes round: every loop does, and so does a camera
  /// that follows somebody.
  final bool loops;
  final Map<MotionProp, List<MotionKey>> Function(MotionWay way, String target)
      write;

  const MotionPreset(this.name, this.kind, this.length, this.write,
      {this.ways = const [], this.aims = false, this.after, bool? loops})
      : loops = loops ?? kind == MotionKind.loop;

  /// clip is a new clip of this motion, called [id].
  MotionClip clip(String id,
      {MotionWay? way, String target = "", int layer = 0}) {
    var c = MotionClip.ofKind(id, kind,
        name: name.replaceAll("…", ""),
        preset: name,
        length: length,
        layer: layer,
        keys:
            write(way ?? (ways.isEmpty ? MotionWay.left : ways.first), target));
    return c.copyWith(after: after, loop: loops);
  }

  /// onto is [c] rewritten as this motion: its keys replaced, its name too
  /// unless it was given its own.
  MotionClip onto(MotionClip c, {MotionWay? way, String target = ""}) =>
      c.copyWith(
        kind: kind,
        preset: name,
        edited: false,
        name: c.name.isEmpty || c.name == c.preset.replaceAll("…", "")
            ? name.replaceAll("…", "")
            : c.name,
        length: length,
        loop: loops,
        before: kind.before,
        after: after ?? kind.after,
        keys:
            write(way ?? (ways.isEmpty ? MotionWay.left : ways.first), target),
      );
}

MotionKey _k(double t, double v, [KeyframeEasing e = KeyframeEasing.linear]) =>
    MotionKey(t, MotionNumber(v), ease: e);
MotionKey _p(double t, MotionPlaceKind kind,
        [String target = "", KeyframeEasing e = KeyframeEasing.linear]) =>
    MotionKey(t, MotionPlace(kind, target: target), ease: e);

const _out = KeyframeEasing.easeOut, _in = KeyframeEasing.easeIn;
const _inOut = KeyframeEasing.easeInOut;
const _sides = [
  MotionWay.left,
  MotionWay.right,
  MotionWay.top,
  MotionWay.bottom
];

MotionPlaceKind _edge(MotionWay w) => switch (w) {
      MotionWay.left => MotionPlaceKind.offLeft,
      MotionWay.right => MotionPlaceKind.offRight,
      MotionWay.top => MotionPlaceKind.offTop,
      MotionWay.bottom => MotionPlaceKind.offBottom,
    };
MotionProp _axis(MotionWay w) =>
    w == MotionWay.left || w == MotionWay.right ? MotionProp.x : MotionProp.y;

/// motionPresets are every ready-made motion, in the order they are listed.
final List<MotionPreset> motionPresets = [
  // Arriving.
  MotionPreset(
      "Slide in",
      MotionKind.arrive,
      0.8,
      (w, _) => {
            _axis(w): [_p(0, _edge(w)), _k(0.8, 0, _out)],
          },
      ways: _sides),
  MotionPreset(
      "Fade up",
      MotionKind.arrive,
      0.6,
      (_, __) => {
            MotionProp.opacity: [_k(0, 0), _k(0.6, 1, _out)],
            MotionProp.y: [_k(0, 24), _k(0.6, 0, _out)],
          }),
  MotionPreset(
      "Pop",
      MotionKind.arrive,
      0.5,
      (_, __) => {
            MotionProp.scale: [_k(0, 0), _k(0.5, 1, KeyframeEasing.overshoot)],
            MotionProp.opacity: [_k(0, 0), _k(0.12, 1)],
          }),
  MotionPreset(
      "Drop in",
      MotionKind.arrive,
      0.9,
      (_, __) => {
            MotionProp.y: [
              _p(0, MotionPlaceKind.offTop),
              _k(0.9, 0, KeyframeEasing.bounce)
            ],
          }),
  // Looping.
  MotionPreset(
      "Float",
      MotionKind.loop,
      2,
      (_, __) => {
            MotionProp.y: [_k(0, 0), _k(1, -14, _inOut), _k(2, 0, _inOut)],
          }),
  MotionPreset(
      "Pulse",
      MotionKind.loop,
      1,
      (_, __) => {
            MotionProp.scale: [
              _k(0, 1),
              _k(0.5, 1.1, _inOut),
              _k(1, 1, _inOut)
            ],
          }),
  MotionPreset(
      "Spin",
      MotionKind.loop,
      2,
      (_, __) => {
            MotionProp.turn: [_k(0, 0), _k(2, 360)],
          }),
  MotionPreset(
      "Wiggle",
      MotionKind.loop,
      0.6,
      (_, __) => {
            MotionProp.turn: [
              _k(0, 0),
              _k(0.15, -7, _inOut),
              _k(0.45, 7, _inOut),
              _k(0.6, 0, _inOut)
            ],
          }),
  // Leaving.
  MotionPreset(
      "Slide out",
      MotionKind.leave,
      0.8,
      (w, _) => {
            _axis(w): [_k(0, 0), _p(0.8, _edge(w), "", _in)],
          },
      ways: const [
        MotionWay.right,
        MotionWay.left,
        MotionWay.top,
        MotionWay.bottom
      ]),
  MotionPreset(
      "Fade out",
      MotionKind.leave,
      0.6,
      (_, __) => {
            MotionProp.opacity: [_k(0, 1), _k(0.6, 0, _in)],
          }),
  MotionPreset(
      "Shrink",
      MotionKind.leave,
      0.5,
      (_, __) => {
            MotionProp.scale: [_k(0, 1), _k(0.5, 0, _in)],
          }),
  MotionPreset(
      "Collect",
      MotionKind.leave,
      0.55,
      (_, __) => {
            MotionProp.y: [_k(0, 0), _k(0.55, -60, _out)],
            MotionProp.scale: [_k(0, 1), _k(0.55, 1.5, _out)],
            MotionProp.opacity: [_k(0.2, 1), _k(0.55, 0)],
          }),
  // Actions.
  MotionPreset(
      "Jump",
      MotionKind.action,
      0.7,
      (_, __) => {
            MotionProp.y: [_k(0, 0), _k(0.35, -95, _out), _k(0.7, 0, _in)],
          }),
  MotionPreset(
      "Shake",
      MotionKind.action,
      0.5,
      (_, __) => {
            MotionProp.x: [
              _k(0, 0),
              _k(0.08, -10),
              _k(0.18, 10),
              _k(0.28, -8),
              _k(0.38, 8),
              _k(0.5, 0)
            ],
          }),
  MotionPreset(
      "Spin once",
      MotionKind.action,
      0.7,
      (_, __) => {
            MotionProp.turn: [_k(0, 0), _k(0.7, 360, _inOut)],
          }),
  MotionPreset(
      "Bump",
      MotionKind.action,
      0.35,
      (_, __) => {
            MotionProp.scale: [
              _k(0, 1),
              _k(0.12, 1.3, _out),
              _k(0.35, 1, _inOut)
            ],
          }),
  MotionPreset(
      "Go to…",
      MotionKind.action,
      2.4,
      (_, t) => {
            MotionProp.x: [
              _k(0, 0),
              _p(2.4, MotionPlaceKind.beside, t, _inOut)
            ],
            MotionProp.y: [
              _k(0, 0),
              _p(2.4, MotionPlaceKind.ground, t, _inOut)
            ],
          },
      aims: true,
      after: ClipHold.last),
  // Camera moves.
  MotionPreset(
      "Push in on…",
      MotionKind.camera,
      1.5,
      (_, t) => {
            MotionProp.x: [_k(0, 0), _p(1.5, MotionPlaceKind.on, t, _inOut)],
            MotionProp.y: [_k(0, 0), _p(1.5, MotionPlaceKind.on, t, _inOut)],
            MotionProp.scale: [_k(0, 1), _k(1.5, 1.7, _inOut)],
          },
      aims: true),
  MotionPreset(
      "Follow…",
      MotionKind.camera,
      1,
      (_, t) => {
            MotionProp.x: [
              _p(0, MotionPlaceKind.on, t),
              _p(1, MotionPlaceKind.on, t)
            ],
            MotionProp.y: [
              _p(0, MotionPlaceKind.on, t),
              _p(1, MotionPlaceKind.on, t)
            ],
            MotionProp.scale: [_k(0, 1.7), _k(1, 1.7)],
          },
      aims: true,
      loops: true),
  MotionPreset(
      "Pull back",
      MotionKind.camera,
      1.5,
      (_, t) => {
            MotionProp.x: [_p(0, MotionPlaceKind.on, t), _k(1.5, 0, _inOut)],
            MotionProp.y: [_p(0, MotionPlaceKind.on, t), _k(1.5, 0, _inOut)],
            MotionProp.scale: [_k(0, 1.7), _k(1.5, 1, _inOut)],
          },
      aims: true),
  MotionPreset(
      "Camera shake",
      MotionKind.camera,
      0.45,
      (_, __) => {
            MotionProp.x: [
              _k(0, 0),
              _k(0.06, 9),
              _k(0.14, -8),
              _k(0.24, 6),
              _k(0.34, -4),
              _k(0.45, 0)
            ],
            MotionProp.y: [
              _k(0, 0),
              _k(0.1, -6),
              _k(0.2, 5),
              _k(0.32, -3),
              _k(0.45, 0)
            ],
          },
      after: ClipHold.rest),
];

/// presetsFor are the ready-made motions of [kind].
List<MotionPreset> presetsFor(MotionKind kind) => [
      for (var p in motionPresets)
        if (p.kind == kind) p
    ];

/// presetNamed is the ready-made motion called [name], or null.
MotionPreset? presetNamed(String name) =>
    motionPresets.where((p) => p.name == name).firstOrNull;
