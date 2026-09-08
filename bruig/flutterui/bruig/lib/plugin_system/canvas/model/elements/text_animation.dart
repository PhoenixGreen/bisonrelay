import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';

// text_animation.dart is how a text element arrives.
//
// Built the same way a chart's is -- a closed set of presets, two settings,
// and a pair of keyframes on the element's own track so the length is dragged
// on the timeline like everything else. See ChartAnimation, whose ease and
// stagger are reused here rather than copied: a bounce is a bounce.
//
// The presets are not thirty separate animations. Each is a *scope* -- the
// whole block, a line, a word, a letter -- and a *motion*, and most of the
// list is one of half a dozen motions at a different scope. "Letters" and
// "Words" are the same fade and rise applied to smaller pieces, and writing
// them as one mechanism is what makes them consistent with each other rather
// than thirty things that each drift.

/// TextAnimationScope is what moves independently.
enum TextAnimationScope {
  /// block moves the whole paragraph as one, which is most of them.
  block,
  line,
  word,
  letter,
}

/// TextAnimationFamily groups the presets in the settings.
///
/// The list is long enough that a flat one is unreadable; grouped, the
/// question is "what kind of arrival" and then "which one".
enum TextAnimationFamily {
  fade("Fade"),
  slide("Slide"),
  scale("Scale"),
  reveal("Reveal"),
  sequential("Sequential"),
  impact("Impact"),
  transform("Transform"),
  draw("Draw");

  final String label;
  const TextAnimationFamily(this.label);
}

/// TextMotion is what one piece actually does between nothing and arrived.
///
/// The mechanisms, as opposed to the names people choose from. A preset is
/// one of these with its numbers set, and the painter knows only these -- so
/// adding a name to the list costs a row in a table rather than a branch in
/// the drawing.
enum TextMotion {
  /// fade is opacity alone.
  fade,

  /// rise moves the piece in from an offset as it fades, which is the
  /// direction presets and the default sequential one.
  rise,

  /// grow scales about the piece's own centre.
  grow,

  /// spin rotates about the centre.
  spin,

  /// flip squashes horizontally to nothing and back, which reads as a card
  /// turning over.
  flip,

  /// blur clears from out of focus.
  blur,

  /// wipe uncovers the piece behind a moving edge, without moving it.
  wipe,

  /// split uncovers from the middle outwards.
  split,

  /// shake settles from a jitter.
  shake,

  /// snap is no tween at all: the piece is not there and then it is.
  snap,

  /// scramble resolves each letter from a random one.
  scramble,

  /// underline draws a line along the text.
  underline,

  /// highlight sweeps a band behind it.
  highlight,

  /// strokeOn draws the outline, then fills it.
  strokeOn;

  /// keeps is whether the motion leaves something behind when it is over.
  ///
  /// The three drawn ones do: an underline that is taken away the moment it
  /// finishes being drawn is not an underline, it is a flicker. Everything
  /// else ends with the words exactly as they would have been without any
  /// animation at all, which is what lets the still drawing take over.
  bool get keeps =>
      this == TextMotion.underline || this == TextMotion.highlight;
}

/// TextAnimationPreset is the list somebody chooses from.
enum TextAnimationPreset {
  none("None", TextAnimationFamily.fade, TextAnimationScope.block,
      TextMotion.fade),

  // Fade.
  fadeIn("Fade in", TextAnimationFamily.fade, TextAnimationScope.block,
      TextMotion.fade),
  fadeUp("Fade up", TextAnimationFamily.fade, TextAnimationScope.block,
      TextMotion.rise,
      dy: 0.35),
  blurIn("Blur in", TextAnimationFamily.fade, TextAnimationScope.block,
      TextMotion.blur),

  // Slide. The distance is a fraction of the box, so the same preset reads
  // the same on a headline and on a caption.
  slideLeft("Slide from the left", TextAnimationFamily.slide,
      TextAnimationScope.block, TextMotion.rise,
      dx: -0.6),
  slideRight("Slide from the right", TextAnimationFamily.slide,
      TextAnimationScope.block, TextMotion.rise,
      dx: 0.6),
  slideUp("Slide up", TextAnimationFamily.slide, TextAnimationScope.block,
      TextMotion.rise,
      dy: 0.6),
  slideDown("Slide down", TextAnimationFamily.slide, TextAnimationScope.block,
      TextMotion.rise,
      dy: -0.6),

  // Scale.
  scaleIn("Scale in", TextAnimationFamily.scale, TextAnimationScope.block,
      TextMotion.grow,
      from: 0.6),
  zoomIn("Zoom in", TextAnimationFamily.scale, TextAnimationScope.block,
      TextMotion.grow,
      from: 0.1),
  pop("Pop", TextAnimationFamily.scale, TextAnimationScope.word,
      TextMotion.grow,
      from: 0.4),
  punch("Punch", TextAnimationFamily.scale, TextAnimationScope.block,
      TextMotion.grow,
      from: 2.2),

  // Reveal: the words stay where they are and something uncovers them.
  wipe("Wipe across", TextAnimationFamily.reveal, TextAnimationScope.block,
      TextMotion.wipe),
  wipeLines("Wipe line by line", TextAnimationFamily.reveal,
      TextAnimationScope.line, TextMotion.wipe),
  split("Split open", TextAnimationFamily.reveal, TextAnimationScope.block,
      TextMotion.split),
  maskUp("Rise behind a mask", TextAnimationFamily.reveal,
      TextAnimationScope.line, TextMotion.rise,
      dy: 1, clipped: true),

  // Sequential: the same arrival, one piece at a time.
  letters("Letter by letter", TextAnimationFamily.sequential,
      TextAnimationScope.letter, TextMotion.fade),
  letterRise("Letters rise", TextAnimationFamily.sequential,
      TextAnimationScope.letter, TextMotion.rise,
      dy: 0.5),
  words("Word by word", TextAnimationFamily.sequential, TextAnimationScope.word,
      TextMotion.rise,
      dy: 0.4),
  cascade("Cascade by line", TextAnimationFamily.sequential,
      TextAnimationScope.line, TextMotion.rise,
      dy: 0.4),
  scatter("Scatter", TextAnimationFamily.sequential, TextAnimationScope.letter,
      TextMotion.fade,
      scrambled: true),
  scramble("Scramble", TextAnimationFamily.sequential,
      TextAnimationScope.letter, TextMotion.scramble),

  // Impact.
  slam("Slam", TextAnimationFamily.impact, TextAnimationScope.block,
      TextMotion.grow,
      from: 3.5),
  snap("Snap", TextAnimationFamily.impact, TextAnimationScope.word,
      TextMotion.snap),
  shake("Shake", TextAnimationFamily.impact, TextAnimationScope.block,
      TextMotion.shake),
  bounce("Bounce", TextAnimationFamily.impact, TextAnimationScope.word,
      TextMotion.rise,
      dy: 0.8),
  whip("Whip", TextAnimationFamily.impact, TextAnimationScope.word,
      TextMotion.rise,
      dx: 0.5),

  // Transform.
  rotateIn("Rotate in", TextAnimationFamily.transform, TextAnimationScope.block,
      TextMotion.spin,
      turns: 0.25),
  spinLetters("Spin the letters", TextAnimationFamily.transform,
      TextAnimationScope.letter, TextMotion.spin,
      turns: 0.5),
  flipIn("Flip in", TextAnimationFamily.transform, TextAnimationScope.block,
      TextMotion.flip),
  flipLetters("Flip the letters", TextAnimationFamily.transform,
      TextAnimationScope.letter, TextMotion.flip),
  stretchIn("Stretch in", TextAnimationFamily.transform,
      TextAnimationScope.block, TextMotion.grow,
      from: 0.3, stretch: true),

  // Draw.
  underline("Underline", TextAnimationFamily.draw, TextAnimationScope.line,
      TextMotion.underline),
  highlight("Highlight", TextAnimationFamily.draw, TextAnimationScope.line,
      TextMotion.highlight),
  strokeOn("Draw the outline", TextAnimationFamily.draw,
      TextAnimationScope.block, TextMotion.strokeOn);

  final String label;
  final TextAnimationFamily family;
  final TextAnimationScope scope;
  final TextMotion motion;

  /// dx and dy are where a piece comes in from, as fractions of its own size.
  final double dx;
  final double dy;

  /// from is the scale a growing piece starts at. Above one it arrives too
  /// large and settles, which is what a slam is.
  final double from;

  /// turns is how far a spinning piece turns, in whole turns.
  final double turns;

  /// clipped keeps a moving piece inside its own line, so it rises out of
  /// nothing rather than sliding over the line below.
  final bool clipped;

  /// stretch scales the two axes against each other, so the piece arrives
  /// squashed rather than small.
  final bool stretch;

  /// scrambled shuffles the order the pieces arrive in, which is what makes a
  /// scatter read as a scatter rather than as a row being dealt.
  final bool scrambled;

  const TextAnimationPreset(
    this.label,
    this.family,
    this.scope,
    this.motion, {
    this.dx = 0,
    this.dy = 0,
    this.from = 1,
    this.turns = 0,
    this.clipped = false,
    this.stretch = false,
    this.scrambled = false,
  });

  static TextAnimationPreset fromName(String? name) => values.firstWhere(
        (p) => p.name == name,
        orElse: () => TextAnimationPreset.none,
      );

  /// inFamily is the presets of one family, in the order they are listed.
  static List<TextAnimationPreset> inFamily(TextAnimationFamily family) => [
        for (var preset in values)
          if (preset != none && preset.family == family) preset,
      ];

  /// staggers is whether the pieces arrive one after another, which is what
  /// the gap setting decides. A block is one piece and has nothing to space
  /// out.
  bool get staggers => this != none && scope != TextAnimationScope.block;
}

/// TextAnimation is the preset, the stagger and the ease -- and, as with a
/// chart, no duration: the length is the gap between two keyframes on the
/// timeline.
class TextAnimation {
  final TextAnimationPreset preset;

  /// exit is how it leaves, using the same presets played backwards. See
  /// ChartAnimation.exit, which this is deliberately identical to.
  final TextAnimationPreset exit;

  /// exitInOrder empties the words the way they arrived rather than
  /// unwinding. See ChartAnimation.exitInOrder.
  final bool exitInOrder;

  /// gap is how long after one piece starts before the next does, as a
  /// fraction of one piece's own movement.
  final double gap;

  final ChartEase ease;

  /// flipOrder is set on the copy the painter draws the way out with, and is
  /// never saved. See ChartAnimation.flipOrder.
  final bool flipOrder;

  const TextAnimation({
    this.preset = TextAnimationPreset.none,
    this.exit = TextAnimationPreset.none,
    this.exitInOrder = false,
    this.gap = 0.35,
    this.ease = ChartEase.easeOut,
    this.flipOrder = false,
  });

  bool get on => preset != TextAnimationPreset.none;
  bool get closes => exit != TextAnimationPreset.none;

  /// leaving is this animation as it is played on the way out.
  TextAnimation get leaving => copyWith(preset: exit, flipOrder: exitInOrder);

  TextAnimation copyWith({
    TextAnimationPreset? preset,
    TextAnimationPreset? exit,
    bool? exitInOrder,
    double? gap,
    ChartEase? ease,
    bool? flipOrder,
  }) =>
      TextAnimation(
        preset: preset ?? this.preset,
        exit: exit ?? this.exit,
        exitInOrder: exitInOrder ?? this.exitInOrder,
        gap: gap ?? this.gap,
        ease: ease ?? this.ease,
        flipOrder: flipOrder ?? this.flipOrder,
      );

  /// progressAt is how far piece [index] of [count] has got when the whole
  /// animation is [reveal] through.
  ///
  /// The same arithmetic a chart staggers its bars with, and deliberately the
  /// same function: two staggers that meant slightly different things would
  /// be a chart and a headline on one canvas that do not line up.
  double progressAt(double reveal, int index, int count) {
    if (!on) return 1;
    if (reveal >= 1) return 1;
    if (reveal <= 0) return 0;
    if (!preset.staggers || count <= 1) return ease.apply(reveal);

    var step = gap.clamp(0.0, 4.0);
    var total = 1 + step * (count - 1);
    var place = preset.scrambled
        ? ChartAnimation.scrambled(index, count)
        : index.toDouble();
    if (flipOrder) place = (count - 1) - place;
    var local = (reveal * total - step * place).clamp(0.0, 1.0);
    return ease.apply(local);
  }

  Map<String, dynamic> toJson() => {
        "preset": preset.name,
        if (closes) "exit": exit.name,
        if (closes && exitInOrder) "exitOrder": true,
        "gap": gap,
        "ease": ease.name,
      };

  factory TextAnimation.fromJson(Map<String, dynamic> json) => TextAnimation(
        preset: TextAnimationPreset.fromName(json["preset"] as String?),
        exit: TextAnimationPreset.fromName(json["exit"] as String?),
        exitInOrder: jsonBool(json["exitOrder"], false),
        gap: jsonDouble(json["gap"], 0.35).clamp(0.0, 4.0),
        ease: ChartEase.fromName(json["ease"] as String?),
      );
}
