import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';

// element_animation.dart is how a shape or a picture arrives and leaves.
//
// The same idea a text element has had all along -- choose an arrival, get
// two keyframes on the timeline, drag them to say when and how long -- for
// the elements that had nothing but the pose channels. A shape could be moved
// and faded by hand, keyframe by keyframe, and that is not the same thing as
// asking for it to fly in.
//
// Deliberately not a second animation system. The motions are the ones the
// text animator already has (see MotionSpec, which was pulled out of
// TextAnimationPreset for exactly this), the easing is the one a chart uses,
// and the keyframes are the same reveal and close channels. What is here is
// the list somebody chooses from, which is shorter than the text one: a
// picture has no words, so nothing scoped to letters, lines or parts, and
// nothing that draws a mark on anything.

/// ElementAnimationFamily groups the presets, so choosing is "what kind" and
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

/// ElementAnimationPreset is the list a shape or a picture chooses from.
///
/// The same names as the text element's where the animation is the same
/// animation, on purpose: a headline and the picture beside it should be able
/// to arrive the same way, and two lists that named the same movement
/// differently would make that a puzzle.
enum ElementAnimationPreset {
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

  // The cutting ones. These are what a picture wants that a headline mostly
  // does not, and they are the reason this list exists at all.
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
  final TextMotion motion;
  final double dx;
  final double dy;
  final double from;
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

  /// spec is the motion and its numbers, which is all the painter needs.
  MotionSpec get spec =>
      MotionSpec(motion, dx: dx, dy: dy, from: from, turns: turns);

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

/// ElementAnimation is one element's arrival and exit.
class ElementAnimation {
  final ElementAnimationPreset preset;

  /// exit is how it leaves, the same presets played backwards -- which is
  /// where a destruction comes from: Build up reversed is a thing coming
  /// apart, and Break apart reversed is one being thrown together.
  final ElementAnimationPreset exit;

  /// scale is where a growing preset starts from, or 0 for the preset's own.
  final double scale;

  final EffectSpec effect;
  final ChartEase ease;

  /// length is how many frames a new arrival is laid down with, or 0 for the
  /// usual two seconds. What the timeline holds is the truth -- see
  /// CanvasController.elementAnimationSpan -- and this is what a new one is
  /// laid down with.
  final int length;

  const ElementAnimation({
    this.preset = ElementAnimationPreset.none,
    this.exit = ElementAnimationPreset.none,
    this.scale = 0,
    this.effect = const EffectSpec(),
    this.ease = ChartEase.easeOut,
    this.length = 0,
  });

  bool get on => preset != ElementAnimationPreset.none;
  bool get closes => exit != ElementAnimationPreset.none;

  /// cuts is whether the effect settings mean anything for what is chosen.
  bool get cuts => preset.cuts || exit.cuts;

  /// scatters is whether how far the pieces are thrown means anything: a
  /// mosaic's blocks and a glitch's slices stay where they are.
  bool get scatters =>
      preset.motion == TextMotion.pieces || exit.motion == TextMotion.pieces;

  /// scales is whether the size setting means anything for what is chosen.
  bool get scales =>
      preset.motion == TextMotion.grow || exit.motion == TextMotion.grow;

  /// scaleFor is where [preset] actually starts from: whatever has been set,
  /// or the preset's own number when nothing has.
  double scaleFor(ElementAnimationPreset preset) =>
      scale > 0 ? scale : preset.from;

  /// progressAt eases [reveal] the way this animation asks for.
  ///
  /// One piece rather than a stagger: an element is a single thing. What the
  /// cutting presets stagger is their own pieces, which they work out
  /// themselves from EffectSpec.stagger -- the tiles of one picture are not
  /// elements and have no keyframes.
  double progressAt(double reveal) =>
      on ? ease.apply(reveal.clamp(0.0, 1.0)) : reveal.clamp(0.0, 1.0);

  /// leaving is this animation as it is played on the way out.
  ElementAnimation get leaving => copyWith(preset: exit);

  ElementAnimation copyWith({
    ElementAnimationPreset? preset,
    ElementAnimationPreset? exit,
    double? scale,
    EffectSpec? effect,
    ChartEase? ease,
    int? length,
  }) =>
      ElementAnimation(
        preset: preset ?? this.preset,
        exit: exit ?? this.exit,
        scale: scale ?? this.scale,
        effect: effect ?? this.effect,
        ease: ease ?? this.ease,
        length: length ?? this.length,
      );

  Map<String, dynamic> toJson() => {
        if (on) "preset": preset.name,
        if (closes) "exit": exit.name,
        if (scale > 0) "scale": scale,
        if (cuts) "effect": effect.toJson(),
        "ease": ease.name,
        if (length > 0) "length": length,
      };

  factory ElementAnimation.fromJson(Map<String, dynamic> json) =>
      ElementAnimation(
        preset: ElementAnimationPreset.fromName(json["preset"] as String?),
        exit: ElementAnimationPreset.fromName(json["exit"] as String?),
        scale: jsonDouble(json["scale"], 0).clamp(0.0, 8.0),
        effect: json["effect"] is Map<String, dynamic>
            ? EffectSpec.fromJson(json["effect"] as Map<String, dynamic>)
            : const EffectSpec(),
        ease: ChartEase.fromName(json["ease"] as String?),
        length: jsonInt(json["length"], 0).clamp(0, 100000),
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
          other.length == length;

  @override
  int get hashCode => Object.hash(preset, exit, scale, effect, ease, length);
}
