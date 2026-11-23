import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/arrival.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';

// element_animation.dart is how a shape or a picture arrives and leaves,
// placed and sized on the timeline as a text element's arrival is. Not a
// second animation system: the motions are the text animator's (MotionSpec),
// the easing a chart's, on the same reveal and close channels. Only the
// list is its own, shorter: nothing scoped to letters, lines or parts. All
// it has beyond the list it shares with a text's arrival, in Arrival.

/// ElementAnimationFamily groups the presets, so choosing is "what kind"
/// then "which one" rather than one list of twenty.
enum ElementAnimationFamily {
  fade("Fade"),
  slide("Slide"),
  scale("Scale"),
  reveal("Reveal"),
  transform("Transform"),
  effect("Effect");

  final String label;
  const ElementAnimationFamily(this.label);
}

/// ElementAnimationPreset is a shape's or picture's list, named as text's
/// where the movement is the same, so they can arrive alike.
enum ElementAnimationPreset implements ArrivalPreset {
  none("None", ElementAnimationFamily.fade, TextMotion.fade),

  fadeIn("Fade in", ElementAnimationFamily.fade, TextMotion.fade),
  fadeUp("Fade up", ElementAnimationFamily.fade, TextMotion.rise, dy: 0.35),
  blurIn("Blur in", ElementAnimationFamily.fade, TextMotion.blur),

  slideLeft(
      "Slide from the left", ElementAnimationFamily.slide, TextMotion.rise,
      dx: -0.9),
  slideRight(
      "Slide from the right", ElementAnimationFamily.slide, TextMotion.rise,
      dx: 0.9),
  slideUp("Slide up", ElementAnimationFamily.slide, TextMotion.rise, dy: 0.9),
  slideDown("Slide down", ElementAnimationFamily.slide, TextMotion.rise,
      dy: -0.9),

  scaleIn("Scale in", ElementAnimationFamily.scale, TextMotion.grow, from: 0.6),
  pop("Pop", ElementAnimationFamily.scale, TextMotion.grow,
      from: 0.4, wants: ChartEase.overshoot),
  punch("Punch", ElementAnimationFamily.scale, TextMotion.grow,
      from: 2.2, wants: ChartEase.overshoot),
  drop("Drop in", ElementAnimationFamily.scale, TextMotion.grow,
      from: 1.8, wants: ChartEase.bounce),

  wipe("Wipe across", ElementAnimationFamily.reveal, TextMotion.wipe),
  split("Split open", ElementAnimationFamily.reveal, TextMotion.split),
  snap("Snap on", ElementAnimationFamily.reveal, TextMotion.snap),

  spinIn("Spin in", ElementAnimationFamily.transform, TextMotion.spin,
      turns: 1),
  spinBack(
      "Spin in backwards", ElementAnimationFamily.transform, TextMotion.spin,
      turns: -1),
  flipIn("Flip in", ElementAnimationFamily.transform, TextMotion.flip),
  shake("Shake on", ElementAnimationFamily.transform, TextMotion.shake),

  // The cutting ones.
  mosaic("Mosaic", ElementAnimationFamily.effect, TextMotion.mosaic,
      wants: ChartEase.linear),
  glitch("Glitch", ElementAnimationFamily.effect, TextMotion.glitch,
      wants: ChartEase.linear),
  assemble("Build up", ElementAnimationFamily.effect, TextMotion.pieces,
      effect: EffectSpec(pieces: 10, scatter: 0.22, stagger: 0.7)),
  shatter("Break apart", ElementAnimationFamily.effect, TextMotion.pieces,
      effect: EffectSpec(pieces: 12, scatter: 1.1, spin: 0.4, stagger: 0.35),
      wants: ChartEase.linear);

  final String label;
  final ElementAnimationFamily family;
  @override
  final TextMotion motion;
  @override
  final double dx;
  @override
  final double dy;
  @override
  final double from;
  @override
  final double turns;
  final EffectSpec? effect;
  final ChartEase? wants;

  const ElementAnimationPreset(
    this.label,
    this.family,
    this.motion, {
    this.dx = 0,
    this.dy = 0,
    this.from = 1,
    this.turns = 0,
    this.effect,
    this.wants,
  });

  @override
  MotionSpec get spec =>
      MotionSpec(motion, dx: dx, dy: dy, from: from, turns: turns);

  @override
  bool get isNone => this == none;

  /// cuts is whether this preset draws the element in pieces.
  bool get cuts => motion.cuts;

  static ElementAnimationPreset fromName(String? name) => values.firstWhere(
        (p) => p.name == name,
        orElse: () => ElementAnimationPreset.none,
      );

  static List<ElementAnimationPreset> inFamily(ElementAnimationFamily family) =>
      [
        for (var preset in values)
          if (preset != none && preset.family == family) preset,
      ];
}

/// ElementAnimation is how a shape, a picture and most other kinds arrive
/// and leave (a text and a chart have their own): an Arrival with this list
/// of presets, eased as one piece.
class ElementAnimation
    extends Arrival<ElementAnimationPreset, ElementAnimation> {
  const ElementAnimation({
    super.preset = ElementAnimationPreset.none,
    super.exit = ElementAnimationPreset.none,
    super.scale,
    super.effect,
    super.ease,
    super.length,
    super.loop,
    super.direction,
    super.strength,
    super.exitDirection,
    super.exitStrength,
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = ElementAnimation();

  /// progressAt eases [reveal] the way this animation asks for. No stagger:
  /// the cutting presets stagger their own pieces from EffectSpec.stagger.
  double progressAt(double reveal) =>
      on ? ease.apply(reveal.clamp(0.0, 1.0)) : reveal.clamp(0.0, 1.0);

  @override
  ElementAnimation copyWith({
    ElementAnimationPreset? preset,
    ElementAnimationPreset? exit,
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
  }) =>
      ElementAnimation(
        preset: preset ?? this.preset,
        exit: exit ?? this.exit,
        scale: scale ?? this.scale,
        effect: effect ?? this.effect,
        ease: ease ?? this.ease,
        length: length ?? this.length,
        loop: loop ?? this.loop,
        direction: clearDirection ? null : direction ?? this.direction,
        strength: strength ?? this.strength,
        exitDirection: exitDirection ?? this.exitDirection,
        exitStrength: exitStrength ?? this.exitStrength,
      );

  ElementAnimation mapColours(ColourMap f) {
    var next = loop.mapColours(f);
    return identical(next, loop) ? this : copyWith(loop: next);
  }

  Map<String, dynamic> toJson() => {
        if (on) "preset": preset.name,
        if (closes) "exit": exit.name,
        if (scale > 0) "scale": scale,
        if (cuts) "effect": effect.toJson(),
        "ease": ease.name,
        if (length > 0) "length": length,
        if (loop.on) "loop": loop.toJson(),
        if (direction != null) "direction": direction!.name,
        if (strength != _defaults.strength) "strength": strength,
        if (exitDirection != null) "exitDirection": exitDirection!.name,
        if (exitStrength != _defaults.exitStrength)
          "exitStrength": exitStrength,
      };

  factory ElementAnimation.fromJson(Map<String, dynamic> json) =>
      ElementAnimation(
        preset: ElementAnimationPreset.fromName(jsonStr(json["preset"])),
        exit: ElementAnimationPreset.fromName(jsonStr(json["exit"])),
        scale: jsonDouble(json["scale"], _defaults.scale).clamp(0.0, 8.0),
        effect: json["effect"] is Map<String, dynamic>
            ? EffectSpec.fromJson(json["effect"] as Map<String, dynamic>)
            : const EffectSpec(),
        ease: ChartEase.fromName(jsonStr(json["ease"])),
        length: jsonInt(json["length"], _defaults.length).clamp(0, 100000),
        loop: json["loop"] is Map<String, dynamic>
            ? ElementLoop.fromJson(json["loop"] as Map<String, dynamic>)
            : const ElementLoop(),
        direction: AnimationDirection.fromName(jsonStr(json["direction"])),
        strength:
            jsonDouble(json["strength"], _defaults.strength).clamp(0.0, 10.0),
        exitDirection:
            AnimationDirection.fromName(jsonStr(json["exitDirection"])),
        exitStrength: jsonDouble(json["exitStrength"], _defaults.exitStrength)
            .clamp(0.0, 10.0),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ElementAnimation &&
          other.preset == preset &&
          other.exit == exit &&
          other.scale == scale &&
          other.effect == effect &&
          other.ease == ease &&
          other.length == length &&
          other.loop == loop &&
          other.direction == direction &&
          other.strength == strength &&
          other.exitDirection == exitDirection &&
          other.exitStrength == exitStrength;

  @override
  int get hashCode => Object.hash(preset, exit, scale, effect, ease, length,
      loop, direction, strength, exitDirection, exitStrength);
}
