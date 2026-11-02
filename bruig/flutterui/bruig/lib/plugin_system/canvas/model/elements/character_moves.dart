import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_motion.dart';

// character_moves.dart is how a character moves that is its own, not the
// motion's: a walk tuned to it -- a long stride, a bounce, arms that swing
// -- and which motion a game plays for each thing it does. Both are its
// design, kept in the library, the same in every scene. Ken's board,
// 2026-11-01: "each tuned to it: how long a stride, how much bounce. A game
// uses the actions mapped below."

/// MotionFeel is a walk and a run tuned to one character, each a share
/// from nought to one with a half as the motion is made.
class MotionFeel {
  /// stride is how far the legs swing, and so how far each step carries.
  final double stride;

  /// bounce is how far the body rises and falls with each step.
  final double bounce;

  /// armSwing is how far the arms swing against the legs.
  final double armSwing;

  /// pushOff is how far the foot behind points its toes as it leaves the
  /// ground.
  final double pushOff;

  /// lean is how far the body leans into the way it is going.
  final double lean;

  const MotionFeel(
      {this.stride = 0.5,
      this.bounce = 0.5,
      this.armSwing = 0.5,
      this.pushOff = 0.5,
      this.lean = 0.5});

  static const MotionFeel asMade = MotionFeel();

  bool get isDefault =>
      stride == 0.5 &&
      bounce == 0.5 &&
      armSwing == 0.5 &&
      pushOff == 0.5 &&
      lean == 0.5;

  /// strideScale is how much further a stride goes than the motion's own:
  /// what the legs swing by, and what a step carries the body.
  double get strideScale => 0.4 + 1.2 * stride;

  /// travels is how far [kind] carries a character tuned so, in its
  /// heights a second: further for a longer stride, or its feet slide.
  double travels(MotionKind kind) =>
      kind == MotionKind.walk || kind == MotionKind.run
          ? kind.travels * strideScale
          : kind.travels;

  MotionFeel copyWith(
          {double? stride,
          double? bounce,
          double? armSwing,
          double? pushOff,
          double? lean}) =>
      MotionFeel(
          stride: (stride ?? this.stride).clamp(0.0, 1.0),
          bounce: (bounce ?? this.bounce).clamp(0.0, 1.0),
          armSwing: (armSwing ?? this.armSwing).clamp(0.0, 1.0),
          pushOff: (pushOff ?? this.pushOff).clamp(0.0, 1.0),
          lean: (lean ?? this.lean).clamp(0.0, 1.0));

  Map<String, dynamic> toJson() => {
        if (stride != 0.5) "stride": stride,
        if (bounce != 0.5) "bounce": bounce,
        if (armSwing != 0.5) "armSwing": armSwing,
        if (pushOff != 0.5) "pushOff": pushOff,
        if (lean != 0.5) "lean": lean,
      };

  static MotionFeel fromJson(Object? json) {
    if (json is! Map) return asMade;
    double v(String k) => jsonDouble(json[k], 0.5).clamp(0.0, 1.0);
    return MotionFeel(
        stride: v("stride"),
        bounce: v("bounce"),
        armSwing: v("armSwing"),
        pushOff: v("pushOff"),
        lean: v("lean"));
  }

  @override
  bool operator ==(Object other) =>
      other is MotionFeel &&
      other.stride == stride &&
      other.bounce == bounce &&
      other.armSwing == armSwing &&
      other.pushOff == pushOff &&
      other.lean == lean;

  @override
  int get hashCode => Object.hash(stride, bounce, armSwing, pushOff, lean);
}

/// GameMove is a thing a character does in a game, which a motion is
/// played for.
enum GameMove {
  standing("Standing", MotionKind.idle),
  walking("Walking", MotionKind.walk),
  running("Running", MotionKind.run),
  jumping("Going up", MotionKind.jump),
  falling("Coming down", MotionKind.jump);

  final String label;

  /// usual is the motion played for it until another is chosen.
  final MotionKind usual;
  const GameMove(this.label, this.usual);
}

/// GameMotions is the motion a game plays for each thing the character
/// does: the usual ones, unless chosen otherwise.
class GameMotions {
  final Map<GameMove, MotionKind> chosen;
  const GameMotions([this.chosen = const {}]);

  MotionKind operator [](GameMove m) => chosen[m] ?? m.usual;

  GameMotions withMotion(GameMove m, MotionKind kind) =>
      GameMotions({...chosen, m: kind}..removeWhere((k, v) => v == k.usual));

  bool get isDefault => chosen.isEmpty;

  Map<String, dynamic> toJson() =>
      {for (var e in chosen.entries) e.key.name: e.value.name};

  static GameMotions fromJson(Object? json) {
    if (json is! Map) return const GameMotions();
    return GameMotions({
      for (var m in GameMove.values)
        if (MotionKind.values.where((k) => k.name == json[m.name]).firstOrNull
            case var k? when k != m.usual)
          m: k,
    });
  }

  @override
  bool operator ==(Object other) =>
      other is GameMotions &&
      other.chosen.length == chosen.length &&
      chosen.entries.every((e) => other.chosen[e.key] == e.value);

  @override
  int get hashCode => Object.hashAllUnordered(
      chosen.entries.map((e) => Object.hash(e.key, e.value)));
}
