import 'dart:math' as math;
import 'dart:ui' show Color;
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';

// text_animation.dart is how a text element arrives: a closed set of
// presets, built like a chart's (ChartAnimation's ease and stagger are reused,
// not copied), with the length set on the timeline rather than here.
//
// Each preset is a scope (block, line, word, letter) and a motion, so most of
// the list is a handful of motions at different scopes; "Letters" and "Words"
// stay consistent because they are one mechanism.

/// TextAnimationScope is what moves independently.
enum TextAnimationScope {
  /// block moves the whole paragraph as one, which is most of them.
  block,
  line,
  word,
  letter,
}

/// TextAnimationFamily groups the presets in the settings.
enum TextAnimationFamily {
  fade("Fade"),
  slide("Slide"),
  scale("Scale"),
  reveal("Reveal"),
  sequential("Sequential"),
  impact("Impact"),
  transform("Transform"),
  draw("Draw"),
  effect("Effect"),
  special("Special");

  final String label;
  const TextAnimationFamily(this.label);
}

/// TextMotion is what one piece does between nothing and arrived.
///
/// The painter knows only these; a preset is one with its numbers set, so a
/// new preset is a row in a table rather than a branch in the drawing.
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

  /// strokeOn draws the type's outline, like a pen, onto words that are
  /// already there. See TextDrawStart for fading the words in with it.
  strokeOn,

  /// trail comes in from an offset like a slide, with copies strung out
  /// behind it that thin away as it settles. An echo keeps its copies; a
  /// trail spends them.
  trail,

  /// mosaic resolves out of blocks: the piece is drawn coarse and comes into
  /// focus. Nothing moves -- what changes is how finely it is drawn.
  mosaic,

  /// glitch tears the piece into horizontal slices and slides them against
  /// each other, settling into register as it arrives.
  glitch,

  /// pieces cuts the piece into a grid of tiles, each arriving from somewhere
  /// of its own. Built up or broken apart is the same motion: it depends on
  /// how far they are thrown and turn (see EffectSpec) and on whether it is
  /// the arrival or the exit, which is the arrival played backwards.
  pieces,

  /// echo repeats the words, fading, in a direction. The copies fan out
  /// from the words, nearest first, and stay when it is over.
  echo;

  /// keeps is whether the motion leaves something behind when it is over:
  /// the drawn marks and an echo's copies. Everything else ends with the
  /// words as they would be without animation, which lets the still drawing
  /// take over. strokeOn is a mark drawn on words already there, not an
  /// arrival that hides them; see [TextDrawStart].
  bool get keeps =>
      this == TextMotion.underline ||
      this == TextMotion.highlight ||
      this == TextMotion.strokeOn ||
      this == TextMotion.echo;

  /// cuts is whether the motion draws the thing more than once -- in tiles,
  /// in slices, or through a filter -- rather than moving it as a whole.
  /// These cannot go through applyMotion, which only sets a transform: they
  /// take the drawing as a closure. See paintCutEffect.
  bool get cuts =>
      this == TextMotion.mosaic ||
      this == TextMotion.glitch ||
      this == TextMotion.pieces;
}

/// MotionSpec is a motion with its numbers: the whole of what applyMotion
/// needs to know. Separate from the preset so shapes and pictures use the
/// same motions as text.
class MotionSpec {
  final TextMotion motion;

  /// dx and dy are where it comes in from, as fractions of its own size.
  final double dx;
  final double dy;

  /// from is the scale a growing thing starts at.
  final double from;

  /// turns is how far a spinning thing turns, in whole turns.
  final double turns;

  /// clipped keeps a moving thing inside its own box.
  final bool clipped;

  /// stretch scales the two axes against each other.
  final bool stretch;

  const MotionSpec(
    this.motion, {
    this.dx = 0,
    this.dy = 0,
    this.from = 1,
    this.turns = 0,
    this.clipped = false,
    this.stretch = false,
  });
}

/// EffectSpec is how a cutting motion cuts: how many pieces, how far they are
/// thrown, how much they turn. A mosaic's blocks, a glitch's slices and a
/// shatter's tiles are the same cut read three ways.
class EffectSpec {
  /// pieces is how many across the element is cut: 1 is not cut at all, 24 is
  /// fine gravel. The rows follow from it, so that a tile is roughly square
  /// whatever shape the element is.
  final int pieces;

  /// scatter is how far a piece is thrown from its place, as a fraction of
  /// the element's own size. 0 leaves every piece where it belongs and the
  /// effect is a fade in tiles; 1 throws them a whole element away.
  final double scatter;

  /// spin is how far a thrown piece turns on its way, in whole turns.
  final double spin;

  /// stagger is how long after the first piece starts the last one does, as a
  /// fraction of the whole. 0 moves them all together.
  final double stagger;

  /// seed decides which piece goes where, so the scatter is the same on
  /// every frame, machine and export size.
  final int seed;

  const EffectSpec({
    this.pieces = 10,
    this.scatter = 0.35,
    this.spin = 0,
    this.stagger = 0.5,
    this.seed = 1,
  });

  EffectSpec copyWith({
    int? pieces,
    double? scatter,
    double? spin,
    double? stagger,
    int? seed,
  }) =>
      EffectSpec(
        pieces: pieces ?? this.pieces,
        scatter: scatter ?? this.scatter,
        spin: spin ?? this.spin,
        stagger: stagger ?? this.stagger,
        seed: seed ?? this.seed,
      );

  Map<String, dynamic> toJson() => {
        "pieces": pieces,
        "scatter": scatter,
        if (spin != 0) "spin": spin,
        "stagger": stagger,
        if (seed != 1) "seed": seed,
      };

  factory EffectSpec.fromJson(Map<String, dynamic> json) => EffectSpec(
        pieces: jsonInt(json["pieces"], 10).clamp(1, 64),
        scatter: jsonDouble(json["scatter"], 0.35).clamp(0, 8),
        spin: jsonDouble(json["spin"], 0).clamp(-8, 8),
        stagger: jsonDouble(json["stagger"], 0.5).clamp(0, 1),
        seed: jsonInt(json["seed"], 1),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EffectSpec &&
          other.pieces == pieces &&
          other.scatter == scatter &&
          other.spin == spin &&
          other.stagger == stagger &&
          other.seed == seed;

  @override
  int get hashCode => Object.hash(pieces, scatter, spin, stagger, seed);
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
  pop("Pop", TextAnimationFamily.scale, TextAnimationScope.word,
      TextMotion.grow,
      from: 0.4, wants: ChartEase.overshoot),
  punch("Punch", TextAnimationFamily.scale, TextAnimationScope.block,
      TextMotion.grow,
      from: 2.2, wants: ChartEase.overshoot),

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
      TextAnimationScope.letter, TextMotion.scramble,
      wants: ChartEase.linear),

  // Impact.
  slam("Slam", TextAnimationFamily.impact, TextAnimationScope.block,
      TextMotion.grow,
      from: 3.5, wants: ChartEase.overshoot),
  snap("Snap", TextAnimationFamily.impact, TextAnimationScope.word,
      TextMotion.snap),
  shake("Shake", TextAnimationFamily.impact, TextAnimationScope.block,
      TextMotion.shake,
      wants: ChartEase.linear),
  bounce("Bounce", TextAnimationFamily.impact, TextAnimationScope.word,
      TextMotion.rise,
      dy: 0.8, wants: ChartEase.bounce),
  whip("Whip", TextAnimationFamily.impact, TextAnimationScope.word,
      TextMotion.rise,
      dx: 0.5, wants: ChartEase.overshoot),

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
      TextAnimationScope.block, TextMotion.strokeOn),

  // Effect: the ones that cut the thing up rather than move it. They read
  // the same on a photograph, a shape and a headline, which is why they are
  // here rather than in a picture's own settings.
  mosaic("Mosaic", TextAnimationFamily.effect, TextAnimationScope.block,
      TextMotion.mosaic,
      wants: ChartEase.linear),
  glitch("Glitch", TextAnimationFamily.effect, TextAnimationScope.block,
      TextMotion.glitch,
      wants: ChartEase.linear),
  assemble("Build up", TextAnimationFamily.effect, TextAnimationScope.block,
      TextMotion.pieces,
      effect: EffectSpec(pieces: 10, scatter: 0.22, stagger: 0.7)),
  shatter("Break apart", TextAnimationFamily.effect, TextAnimationScope.block,
      TextMotion.pieces,
      effect: EffectSpec(pieces: 12, scatter: 1.1, spin: 0.4, stagger: 0.35),
      wants: ChartEase.linear),

  // Special: the copies. Every direction, since which one reads best depends
  // entirely on where the words sit on the page -- a headline at the top of a
  // canvas echoes downwards and one at the bottom cannot.
  echoDown("Echo downwards", TextAnimationFamily.special,
      TextAnimationScope.block, TextMotion.echo),
  echoUp("Echo upwards", TextAnimationFamily.special, TextAnimationScope.block,
      TextMotion.echo,
      dy: -1),
  echoBoth("Echo both ways", TextAnimationFamily.special,
      TextAnimationScope.block, TextMotion.echo,
      turns: 1),
  echoRight("Echo to the right", TextAnimationFamily.special,
      TextAnimationScope.block, TextMotion.echo,
      dx: 1),
  echoLeft("Echo to the left", TextAnimationFamily.special,
      TextAnimationScope.block, TextMotion.echo,
      dx: -1),
  echoWords("Echo each word", TextAnimationFamily.special,
      TextAnimationScope.word, TextMotion.echo),
  echoLetters("Echo each letter", TextAnimationFamily.special,
      TextAnimationScope.letter, TextMotion.echo),

  // The trails: the same copies, spent rather than kept. The words come in
  // from somewhere and what is behind them catches up and goes out.
  trailDown("Drops in trailing", TextAnimationFamily.special,
      TextAnimationScope.block, TextMotion.trail,
      dy: -0.9),
  trailUp("Rises trailing", TextAnimationFamily.special,
      TextAnimationScope.block, TextMotion.trail,
      dy: 0.9),
  trailFromLeft("Streaks in from the left", TextAnimationFamily.special,
      TextAnimationScope.block, TextMotion.trail,
      dx: -0.9),
  trailFromRight("Streaks in from the right", TextAnimationFamily.special,
      TextAnimationScope.block, TextMotion.trail,
      dx: 0.9),
  trailWords("Words drop in trailing", TextAnimationFamily.special,
      TextAnimationScope.word, TextMotion.trail,
      dy: -0.9),
  trailLetters("Letters drop in trailing", TextAnimationFamily.special,
      TextAnimationScope.letter, TextMotion.trail,
      dy: -0.9);

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

  /// effect is how a cutting preset cuts, where it is one: Build up and
  /// Break apart are the same motion and differ only in these numbers. Like
  /// [wants], a starting point written in when the preset is chosen.
  final EffectSpec? effect;

  /// wants is the easing the preset was designed around, or null where it
  /// does not care: a bounce is a rise eased to overshoot and settle.
  /// Choosing the preset sets the End curve to this and then leaves it alone.
  final ChartEase? wants;

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
    this.effect,
    this.wants,
  });

  /// spec is the motion and its numbers, for whatever is being moved.
  MotionSpec get spec => MotionSpec(motion,
      dx: dx,
      dy: dy,
      from: from,
      turns: turns,
      clipped: clipped,
      stretch: stretch);

  /// cuts is whether this preset draws the thing in pieces. See TextMotion.
  bool get cuts => motion.cuts;

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

/// TextDrawStart is what the words themselves do while something is being
/// drawn on them.
enum TextDrawStart {
  /// showText leaves the words where they are and draws only the mark: an
  /// underline drawn under a finished sentence. The default.
  showText("Already there"),

  /// fadeText brings the words in with the mark.
  fadeText("Fades in with it");

  final String label;
  const TextDrawStart(this.label);

  static TextDrawStart fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => showText);
}

/// TextDrawSpec is what a drawn mark looks like: an underline's line, a
/// highlight's band. It has its own colour, since a band in the words' own
/// colour is a solid block, and its own padding.
class TextDrawSpec {
  /// color is the mark's own, or null to take the text's.
  final Color? color;

  final TextDrawStart start;

  /// The four sides are kept apart so a band can have more room above and
  /// below than at the ends.
  final double padLeft;
  final double padTop;
  final double padRight;
  final double padBottom;

  /// radius rounds the band's corners, as a part's own highlight can be.
  final double radius;

  const TextDrawSpec({
    this.color,
    this.start = TextDrawStart.showText,
    this.padLeft = 0,
    this.padTop = 0,
    this.padRight = 0,
    this.padBottom = 0,
    this.radius = 0,
  });

  /// evenPad is the one number the four sides share, or null where they
  /// differ -- which is what the "all sides" field shows.
  double? get evenPad =>
      padLeft == padTop && padTop == padRight && padRight == padBottom
          ? padLeft
          : null;

  TextDrawSpec copyWith({
    Color? color,
    bool clearColor = false,
    TextDrawStart? start,
    double? padLeft,
    double? padTop,
    double? padRight,
    double? padBottom,
    double? radius,
  }) =>
      TextDrawSpec(
        color: clearColor ? null : (color ?? this.color),
        start: start ?? this.start,
        padLeft: padLeft ?? this.padLeft,
        padTop: padTop ?? this.padTop,
        padRight: padRight ?? this.padRight,
        padBottom: padBottom ?? this.padBottom,
        radius: radius ?? this.radius,
      );

  /// withEvenPad sets all four sides at once.
  TextDrawSpec withEvenPad(double pad) => TextDrawSpec(
      color: color,
      start: start,
      padLeft: pad,
      padTop: pad,
      padRight: pad,
      padBottom: pad,
      radius: radius);

  Map<String, dynamic> toJson() => {
        if (color != null) "color": colorToJson(color!),
        if (start != TextDrawStart.showText) "start": start.name,
        if (padLeft != 0) "l": padLeft,
        if (padTop != 0) "t": padTop,
        if (padRight != 0) "r": padRight,
        if (padBottom != 0) "b": padBottom,
        if (radius != 0) "radius": radius,
      };

  factory TextDrawSpec.fromJson(Map<String, dynamic> json) => TextDrawSpec(
        color: json["color"] == null
            ? null
            : colorFromJson(json["color"], const Color(0xFFFFFFFF)),
        start: TextDrawStart.fromName(jsonStr(json["start"])),
        padLeft: jsonDouble(json["l"], 0),
        padTop: jsonDouble(json["t"], 0),
        padRight: jsonDouble(json["r"], 0),
        padBottom: jsonDouble(json["b"], 0),
        radius: jsonDouble(json["radius"], 0),
      );
}

/// TextEchoSpec is how the copies of an echo or trail are arranged: how
/// many, how far apart, and how much quieter each is than the one before.
class TextEchoSpec {
  /// copies is how many there are, not counting the words themselves.
  final int copies;

  /// spacing is the gap between one copy and the next, as a fraction of the
  /// line's own height -- so the same setting reads the same on a headline
  /// and on a caption.
  final double spacing;

  /// fade is how much of the previous copy's strength each one keeps. 0.6
  /// means each is a little over half the one before it, which is a trail;
  /// 1 means they are all as solid as the words, which is a stack.
  final double fade;

  /// shrink is how much smaller each copy is than the one before, or 1 for
  /// copies the same size. Below 1 the trail recedes.
  final double shrink;

  /// resolve sends the copies on their way instead of leaving them: they fan
  /// out over the first half and carry on out of sight over the second,
  /// leaving the words alone, so the echo is an arrival rather than a look.
  final bool resolve;

  const TextEchoSpec({
    this.copies = 4,
    this.spacing = 1,
    this.fade = 0.55,
    this.shrink = 1,
    this.resolve = false,
  });

  TextEchoSpec copyWith({
    int? copies,
    double? spacing,
    double? fade,
    double? shrink,
    bool? resolve,
  }) =>
      TextEchoSpec(
        copies: copies ?? this.copies,
        spacing: spacing ?? this.spacing,
        fade: fade ?? this.fade,
        shrink: shrink ?? this.shrink,
        resolve: resolve ?? this.resolve,
      );

  Map<String, dynamic> toJson() => {
        if (copies != 4) "copies": copies,
        if (spacing != 1) "spacing": spacing,
        if (fade != 0.55) "fade": fade,
        if (shrink != 1) "shrink": shrink,
        if (resolve) "resolve": true,
      };

  factory TextEchoSpec.fromJson(Map<String, dynamic> json) => TextEchoSpec(
        copies: jsonInt(json["copies"], 4).clamp(1, 24),
        spacing: jsonDouble(json["spacing"], 1).clamp(0.05, 8),
        fade: jsonDouble(json["fade"], 0.55).clamp(0.05, 1),
        shrink: jsonDouble(json["shrink"], 1).clamp(0.2, 1),
        resolve: jsonBool(json["resolve"], false),
      );
}

/// TextAnimation is the preset, the stagger and the ease. As with a chart's,
/// the length is not here: it is where the arrival sits on the timeline.
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

  /// draw is what a drawn mark looks like, for the presets that draw one.
  final TextDrawSpec draw;

  /// echo is how the copies are arranged, for the presets that make them.
  final TextEchoSpec echo;

  /// effect is how the cutting presets cut, for the ones that do.
  final EffectSpec effect;

  /// scale is where a growing preset starts from, as a fraction: 0.6 arrives
  /// a little small, 2 from twice the size and settles. On the way out it is
  /// where the words go. Zero means the preset's own number (see [scaleFor]).
  final double scale;

  final ChartEase ease;

  /// length is how many frames a new arrival is laid down with, or 0 for the
  /// usual two seconds. The timeline is where the arrival actually is;
  /// dragging it there deliberately does not write back here.
  final int length;

  /// flipOrder is set on the copy the painter draws the way out with, and is
  /// never saved. See ChartAnimation.flipOrder.
  final bool flipOrder;

  /// direction and strength turn and size a moving arrival, as a shape's do
  /// (see ElementAnimation.specFor); exitDirection and exitStrength do the
  /// same for the way out.
  final AnimationDirection? direction;
  final double strength;
  final AnimationDirection? exitDirection;
  final double exitStrength;

  /// loop is what the words go on doing after they have arrived, or instead
  /// of arriving: see ElementLoop.
  final ElementLoop loop;

  /// piecesInTurn brings the pieces in the box (see TextItem) in one after
  /// another -- the words first, then each piece in the order of its layers
  /// -- rather than all at once; each starts [piecesGap] of the way through
  /// the one before. A kicker or a badge arriving just after its headline
  /// (Ken, 2026-11-11: no arrivals of their own, which would crowd the
  /// timeline; this, on the text's own).
  final bool piecesInTurn;
  final double piecesGap;

  const TextAnimation({
    this.preset = TextAnimationPreset.none,
    this.exit = TextAnimationPreset.none,
    this.exitInOrder = false,
    this.gap = 0.35,
    this.scale = 0,
    this.draw = const TextDrawSpec(),
    this.echo = const TextEchoSpec(),
    this.effect = const EffectSpec(),
    this.ease = ChartEase.easeOut,
    this.length = 0,
    this.flipOrder = false,
    this.direction,
    this.strength = 1,
    this.exitDirection,
    this.exitStrength = 1,
    this.loop = const ElementLoop(),
    this.piecesInTurn = false,
    this.piecesGap = 0.5,
  });

  bool get on => preset != TextAnimationPreset.none;

  /// pieceReveal is how far layer [index] of [count] -- the words 0, then
  /// each piece -- has got when the whole arrival is [reveal] through: all
  /// at once, or in turn (see [piecesInTurn]), the last finishing as the
  /// arrival does.
  double pieceReveal(double reveal, int index, int count) {
    if (!piecesInTurn || count <= 1) return reveal;
    var g = piecesGap.clamp(0.0, 1.0).toDouble();
    var share = 1 / (1 + (count - 1) * g);
    return (reveal / share - index * g).clamp(0.0, 1.0).toDouble();
  }

  /// scaleFor is where [preset] actually starts from: whatever has been set,
  /// or the preset's own number when nothing has.
  double scaleFor(TextAnimationPreset preset) =>
      scale > 0 ? scale : preset.from;

  /// echoes is whether the copy settings mean anything for what is chosen.
  bool get echoes =>
      preset.motion == TextMotion.echo ||
      exit.motion == TextMotion.echo ||
      preset.motion == TextMotion.trail ||
      exit.motion == TextMotion.trail;

  /// keeps is whether this animation leaves something behind when it is over.
  ///
  /// The motion's own answer, except for an echo that has been told to
  /// resolve -- its copies fly off and are gone, so what is left is the words
  /// and the still drawing can take over. See TextEchoSpec.resolve.
  bool get keeps {
    if (echo.resolve &&
        (preset.motion == TextMotion.echo || exit.motion == TextMotion.echo)) {
      return false;
    }
    return preset.motion.keeps;
  }

  /// draws is whether the mark settings mean anything for what is chosen.
  bool get draws => preset.motion.keeps || exit.motion.keeps;

  /// cuts is whether the effect settings mean anything for what is chosen.
  bool get cuts => preset.cuts || exit.cuts;

  /// scatters is whether how far the pieces are thrown means anything: a
  /// mosaic's blocks and a glitch's slices stay where they are.
  bool get scatters =>
      preset.motion == TextMotion.pieces || exit.motion == TextMotion.pieces;

  /// scales is whether the size setting means anything for what is chosen.
  bool get scales =>
      preset.motion == TextMotion.grow || exit.motion == TextMotion.grow;
  bool get closes => exit != TextAnimationPreset.none;

  /// leaving is this animation as it is played on the way out.
  TextAnimation get leaving => copyWith(
      preset: exit,
      flipOrder: exitInOrder,
      direction: exitDirection,
      clearDirection: exitDirection == null,
      strength: exitStrength);

  /// any is whether there is anything to it: an arrival, an exit or a loop.
  bool get any => on || closes || loop.on;

  static bool _directs(TextAnimationPreset p) =>
      p != TextAnimationPreset.none &&
      ((p.motion == TextMotion.rise || p.motion == TextMotion.trail) &&
              (p.dx != 0 || p.dy != 0) ||
          p.motion == TextMotion.wipe);
  static bool _strengthens(TextAnimationPreset p) =>
      p != TextAnimationPreset.none &&
      (((p.motion == TextMotion.rise || p.motion == TextMotion.trail) &&
              (p.dx != 0 || p.dy != 0)) ||
          p.motion == TextMotion.grow ||
          p.motion == TextMotion.spin);

  /// arrivalDirected and the rest are whether a direction, or a strength,
  /// means anything for the way in, or the way out.
  bool get arrivalDirected => _directs(preset);
  bool get exitDirected => _directs(exit);
  bool get arrivalStrengthens => _strengthens(preset);
  bool get exitStrengthens => _strengthens(exit);

  /// spec is the arrival's motion as this animation plays it: turned to its
  /// direction, and moved, grown and turned as far as its strength says.
  /// The way out's is [leaving]'s.
  MotionSpec get spec {
    var p = preset;
    var base = p.spec;
    var dx = base.dx, dy = base.dy;
    var way = direction;
    if (way != null && base.motion == TextMotion.wipe) {
      dx = way.dx;
      dy = way.dy;
    } else if (way != null && (dx != 0 || dy != 0)) {
      var far = math.sqrt(dx * dx + dy * dy);
      var unit = math.sqrt(way.dx * way.dx + way.dy * way.dy);
      dx = way.dx / unit * far;
      dy = way.dy / unit * far;
    }
    var k = base.motion == TextMotion.wipe ? 1.0 : strength;
    return MotionSpec(base.motion,
        dx: dx * k,
        dy: dy * k,
        from: 1 + (scaleFor(p) - 1) * strength,
        turns: base.turns * strength,
        clipped: base.clipped,
        stretch: base.stretch);
  }

  TextAnimation copyWith({
    TextAnimationPreset? preset,
    TextAnimationPreset? exit,
    bool? exitInOrder,
    double? gap,
    double? scale,
    TextDrawSpec? draw,
    TextEchoSpec? echo,
    EffectSpec? effect,
    ChartEase? ease,
    int? length,
    bool? flipOrder,
    AnimationDirection? direction,
    bool clearDirection = false,
    double? strength,
    AnimationDirection? exitDirection,
    double? exitStrength,
    ElementLoop? loop,
    bool? piecesInTurn,
    double? piecesGap,
  }) =>
      TextAnimation(
        preset: preset ?? this.preset,
        exit: exit ?? this.exit,
        exitInOrder: exitInOrder ?? this.exitInOrder,
        gap: gap ?? this.gap,
        scale: scale ?? this.scale,
        draw: draw ?? this.draw,
        echo: echo ?? this.echo,
        effect: effect ?? this.effect,
        ease: ease ?? this.ease,
        length: length ?? this.length,
        flipOrder: flipOrder ?? this.flipOrder,
        direction: clearDirection ? null : direction ?? this.direction,
        strength: strength ?? this.strength,
        exitDirection: exitDirection ?? this.exitDirection,
        exitStrength: exitStrength ?? this.exitStrength,
        loop: loop ?? this.loop,
        piecesInTurn: piecesInTurn ?? this.piecesInTurn,
        piecesGap: piecesGap ?? this.piecesGap,
      );

  /// progressAt is how far piece [index] of [count] has got when the whole
  /// animation is [reveal] through. Deliberately the chart's own stagger, so
  /// a chart and a headline on one canvas line up.
  double progressAt(double reveal, int index, int count) => staggeredProgress(
        reveal,
        index,
        count,
        on: on,
        staggers: preset.staggers,
        scrambles: preset.scrambled,
        flipOrder: flipOrder,
        gap: gap,
        ease: ease,
      );

  Map<String, dynamic> toJson() => {
        "preset": preset.name,
        if (closes) "exit": exit.name,
        if (closes && exitInOrder) "exitOrder": true,
        "gap": gap,
        if (scale > 0) "scale": scale,
        if (draw.toJson().isNotEmpty) "draw": draw.toJson(),
        if (echo.toJson().isNotEmpty) "echo": echo.toJson(),
        if (cuts) "effect": effect.toJson(),
        "ease": ease.name,
        if (length > 0) "length": length,
        if (direction != null) "direction": direction!.name,
        if (strength != 1) "strength": strength,
        if (exitDirection != null) "exitDirection": exitDirection!.name,
        if (exitStrength != 1) "exitStrength": exitStrength,
        if (loop.on) "loop": loop.toJson(),
        if (piecesInTurn) "piecesInTurn": true,
        if (piecesInTurn) "piecesGap": piecesGap,
      };

  factory TextAnimation.fromJson(Map<String, dynamic> json) => TextAnimation(
        preset: TextAnimationPreset.fromName(jsonStr(json["preset"])),
        exit: TextAnimationPreset.fromName(jsonStr(json["exit"])),
        exitInOrder: jsonBool(json["exitOrder"], false),
        gap: jsonDouble(json["gap"], 0.35).clamp(0.0, 4.0),
        scale: jsonDouble(json["scale"], 0).clamp(0.0, 8.0),
        draw: json["draw"] is Map<String, dynamic>
            ? TextDrawSpec.fromJson(json["draw"] as Map<String, dynamic>)
            : const TextDrawSpec(),
        echo: json["echo"] is Map<String, dynamic>
            ? TextEchoSpec.fromJson(json["echo"] as Map<String, dynamic>)
            : const TextEchoSpec(),
        effect: json["effect"] is Map<String, dynamic>
            ? EffectSpec.fromJson(json["effect"] as Map<String, dynamic>)
            : const EffectSpec(),
        ease: ChartEase.fromName(jsonStr(json["ease"])),
        length: jsonInt(json["length"], 0).clamp(0, 100000),
        direction: AnimationDirection.fromName(jsonStr(json["direction"])),
        strength: jsonDouble(json["strength"], 1).clamp(0.0, 10.0),
        exitDirection:
            AnimationDirection.fromName(jsonStr(json["exitDirection"])),
        exitStrength: jsonDouble(json["exitStrength"], 1).clamp(0.0, 10.0),
        loop: json["loop"] is Map<String, dynamic>
            ? ElementLoop.fromJson(json["loop"] as Map<String, dynamic>)
            : const ElementLoop(),
        piecesInTurn: jsonBool(json["piecesInTurn"], false),
        piecesGap: jsonDouble(json["piecesGap"], 0.5).clamp(0.0, 1.0),
      );
}
