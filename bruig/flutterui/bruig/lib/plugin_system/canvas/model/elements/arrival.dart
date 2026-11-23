import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';

// arrival.dart is what a shape's or picture's arrival (ElementAnimation)
// and a text's (TextAnimation) have in common: a preset in and a preset
// out, the direction and strength each is played at, how far it grows, its
// cut, its curve and its loop, and the questions asked of them. Each keeps
// its own preset list, its own settings beside these and its own saved
// form. A setting both should have goes here once; a part of a text's words
// holds a whole TextAnimation (see TextPartAnimation), so it comes too.

/// AnimationDirection is where a moving arrival comes in from, or a wipe
/// starts, in place of the preset's own: one control, not a preset for
/// every way round. [dx] and [dy] point from where the element ends up
/// toward where it starts.
enum AnimationDirection {
  left("From the left", -1, 0),
  right("From the right", 1, 0),
  above("From above", 0, -1),
  below("From below", 0, 1),
  aboveLeft("From top left", -1, -1),
  aboveRight("From top right", 1, -1),
  belowLeft("From bottom left", -1, 1),
  belowRight("From bottom right", 1, 1);

  final String label;
  final double dx;
  final double dy;
  const AnimationDirection(this.label, this.dx, this.dy);

  static AnimationDirection? fromName(String? name) =>
      values.where((d) => d.name == name).firstOrNull;

  /// of is the direction [dx], [dy] points in, to the nearest of the eight,
  /// or null where it points nowhere.
  static AnimationDirection? of(double dx, double dy) {
    if (dx == 0 && dy == 0) return null;
    int sign(double v, double other) =>
        v.abs() * 2.4 < other.abs() ? 0 : v.sign.toInt();
    var x = sign(dx, dy), y = sign(dy, dx);
    return values.firstWhere((d) => d.dx == x && d.dy == y);
  }
}

/// ArrivalPreset is what an Arrival asks of a preset: its motion and the
/// numbers it is played with as designed. ElementAnimationPreset and
/// TextAnimationPreset are the two lists.
abstract interface class ArrivalPreset {
  TextMotion get motion;
  double get dx;
  double get dy;
  double get from;
  double get turns;

  /// spec is the preset's motion as designed, before a direction or a
  /// strength turns or sizes it (see Arrival.specFor).
  MotionSpec get spec;

  /// isNone is whether this is the list's None: nothing chosen.
  bool get isNone;
}

/// Arrival is how a thing comes onto the page and leaves it. [P] is its
/// kind's preset list and [A] the kind's own type, so a copy or the way out
/// is one of the same.
abstract class Arrival<P extends ArrivalPreset, A extends Arrival<P, A>> {
  final P preset;

  /// exit is how it leaves: the same presets played backwards, so Build up
  /// reversed is a thing coming apart; identical by design to
  /// ChartAnimation.exit.
  final P exit;

  /// scale is where a growing preset starts, as a fraction (0.6 a little
  /// small, 2 twice the size); on the way out it is where it goes. Zero
  /// means the preset's own number (see [scaleFor]).
  final double scale;

  final EffectSpec effect;
  final ChartEase ease;

  /// length is the frames a new arrival is laid down with, or 0 for two
  /// seconds; see CanvasController.elementAnimationSpan. Dragging it on the
  /// timeline deliberately does not write back.
  final int length;

  /// loop is what it does after arriving, or instead: see ElementLoop.
  final ElementLoop loop;

  /// direction is where a moving arrival comes in from, or a wipe starts, or
  /// null for the preset's own.
  final AnimationDirection? direction;

  /// strength is how far it moves, how much it grows or how far it turns,
  /// against the preset's own: 1 is the preset as it is.
  final double strength;

  /// exitDirection and exitStrength are the same for the way out, so a thing
  /// can come in from the left and go out to the right.
  final AnimationDirection? exitDirection;
  final double exitStrength;

  const Arrival({
    required this.preset,
    required this.exit,
    this.scale = 0,
    this.effect = const EffectSpec(),
    this.ease = ChartEase.easeOut,
    this.length = 0,
    this.loop = const ElementLoop(),
    this.direction,
    this.strength = 1,
    this.exitDirection,
    this.exitStrength = 1,
  });

  /// copyWith is the kind's own, which may take more; these are the
  /// settings every arrival has.
  A copyWith({
    P? preset,
    P? exit,
    double? scale,
    EffectSpec? effect,
    ChartEase? ease,
    int? length,
    ElementLoop? loop,
    AnimationDirection? direction,
    bool clearDirection = false,
    double? strength,
    AnimationDirection? exitDirection,
    double? exitStrength,
  });

  bool get on => !preset.isNone;
  bool get closes => !exit.isNone;

  /// any is whether there is anything to it (an arrival, an exit or a loop):
  /// whether it is worth saving.
  bool get any => on || closes || loop.on;

  /// cuts is whether the effect settings mean anything for what is chosen.
  bool get cuts => preset.motion.cuts || exit.motion.cuts;

  /// scatters is whether how far the pieces are thrown means anything: a
  /// mosaic's blocks and a glitch's slices stay where they are.
  bool get scatters =>
      preset.motion == TextMotion.pieces || exit.motion == TextMotion.pieces;

  /// scales is whether the size setting means anything for what is chosen.
  bool get scales =>
      preset.motion == TextMotion.grow || exit.motion == TextMotion.grow;

  /// scaleFor is where [preset] starts from: as set, or its own number.
  double scaleFor(P preset) => scale > 0 ? scale : preset.from;

  /// directed is whether a direction means anything for what is chosen: a
  /// thing that slides in (or trails in), or is wiped on or out.
  bool get directed => _directs(preset) || _directs(exit);

  /// arrivalDirected, arrivalStrengthens, exitDirected and exitStrengthens
  /// are [directed] and [strengthens] for the way in or the way out alone.
  bool get arrivalDirected => _directs(preset);
  bool get exitDirected => _directs(exit);
  static bool _directs(ArrivalPreset p) =>
      !p.isNone &&
      ((p.motion == TextMotion.rise || p.motion == TextMotion.trail) &&
              (p.dx != 0 || p.dy != 0) ||
          p.motion == TextMotion.wipe);

  /// strengthens is whether strength means anything for what is chosen: a
  /// thing that slides, grows or turns.
  bool get strengthens => _strengthens(preset) || _strengthens(exit);
  static bool _strengthens(ArrivalPreset p) =>
      !p.isNone &&
      ((p.motion == TextMotion.rise && (p.dx != 0 || p.dy != 0)) ||
          p.motion == TextMotion.grow ||
          p.motion == TextMotion.spin);

  /// directionOf is the way [p] goes as this animation has it: its own
  /// direction where one is set, or the preset's.
  AnimationDirection? directionOf(P p) =>
      direction ??
      (p.motion == TextMotion.wipe
          ? AnimationDirection.left
          : AnimationDirection.of(p.dx, p.dy));

  /// specFor is [p]'s motion as this animation plays it: turned to its
  /// direction, and moved, grown and turned as far as its strength says.
  /// Everything that moves the thing reads this, not the preset's own
  /// numbers, or a chosen direction is lost.
  MotionSpec specFor(P p) {
    var base = p.spec;
    var dx = base.dx, dy = base.dy;
    var way = direction;
    if (way != null && base.motion == TextMotion.wipe) {
      // A wipe goes nowhere: what it takes is the edge it starts from.
      dx = way.dx;
      dy = way.dy;
    } else if (way != null && (dx != 0 || dy != 0)) {
      var far = math.sqrt(dx * dx + dy * dy);
      var unit = math.sqrt(way.dx * way.dx + way.dy * way.dy);
      dx = way.dx / unit * far;
      dy = way.dy / unit * far;
    }
    var s = base.motion == TextMotion.wipe ? 1.0 : strength;
    return MotionSpec(base.motion,
        dx: dx * s,
        dy: dy * s,
        from: 1 + (scaleFor(p) - 1) * strength,
        turns: base.turns * strength,
        clipped: base.clipped,
        stretch: base.stretch);
  }

  /// spec is the arrival's motion as played. The way out's is [leaving]'s.
  MotionSpec get spec => specFor(preset);

  /// leaving is this animation as played on the way out, with the way out's
  /// own direction and strength.
  A get leaving => copyWith(
      preset: exit,
      direction: exitDirection,
      clearDirection: exitDirection == null,
      strength: exitStrength);
}
