import 'dart:ui' show Color;
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
  draw("Draw"),
  special("Special");

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
  strokeOn,

  /// trail is an arrival that leaves copies of itself behind it.
  ///
  /// The piece comes in from an offset the way a slide does, and the copies
  /// are strung out along the way it came, thinning as it settles until only
  /// the words are left. Where an echo *keeps* its copies, a trail spends
  /// them: what it draws is speed, not a stack.
  trail,

  /// echo repeats the words, fading, in a direction.
  ///
  /// A look as much as an arrival: the copies stay when it is over, which is
  /// what the reference somebody sent looked like -- a word with four
  /// quieter copies of itself under it. What it animates is the copies
  /// fanning out from the words, nearest first.
  echo;

  /// keeps is whether the motion leaves something behind when it is over.
  ///
  /// The three drawn ones do: an underline that is taken away the moment it
  /// finishes being drawn is not an underline, it is a flicker. Everything
  /// else ends with the words exactly as they would have been without any
  /// animation at all, which is what lets the still drawing take over.
  bool get keeps =>
      this == TextMotion.underline ||
      this == TextMotion.highlight ||
      this == TextMotion.echo;
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

  /// wants is the easing the preset was designed around, or null where it
  /// does not care.
  ///
  /// A bounce is not a movement, it is a *curve*: the same rise, eased so it
  /// overshoots and settles. Played with the ordinary ease-out it is a slide
  /// with a misleading name, which is exactly what it looked like. Chosen,
  /// the preset sets the End curve to this -- and leaves it alone afterwards,
  /// so it is a starting point rather than a setting that cannot be changed.
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
    this.wants,
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

/// TextDrawStart is what the words themselves do while something is being
/// drawn on them.
enum TextDrawStart {
  /// showText leaves the words where they are and draws only the mark, which
  /// is what an underline being drawn under a finished sentence looks like.
  ///
  /// The default, and it was not even an option: a draw preset hid the words
  /// until the first frame was over, so a highlight sweeping across a
  /// headline began with no headline.
  showText("Already there"),

  /// fadeText brings the words in with the mark.
  fadeText("Fades in with it");

  final String label;
  const TextDrawStart(this.label);

  static TextDrawStart fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => showText);
}

/// TextDrawSpec is what a drawn mark looks like: an underline's line, a
/// highlight's band.
///
/// Its own colour, because a highlight in the colour of the words it is
/// behind is a solid block, and its own padding, because a band tight around
/// the letters reads as a mistake where one with a little air reads as a
/// highlighter.
class TextDrawSpec {
  /// color is the mark's own, or null to take the text's.
  final Color? color;

  final TextDrawStart start;

  /// The four sides, kept separately so a band can be given more room above
  /// and below than at the ends -- which is what a highlighter actually
  /// looks like. The settings offer one field that writes all four and the
  /// four on their own.
  final double padLeft;
  final double padTop;
  final double padRight;
  final double padBottom;

  const TextDrawSpec({
    this.color,
    this.start = TextDrawStart.showText,
    this.padLeft = 0,
    this.padTop = 0,
    this.padRight = 0,
    this.padBottom = 0,
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
  }) =>
      TextDrawSpec(
        color: clearColor ? null : (color ?? this.color),
        start: start ?? this.start,
        padLeft: padLeft ?? this.padLeft,
        padTop: padTop ?? this.padTop,
        padRight: padRight ?? this.padRight,
        padBottom: padBottom ?? this.padBottom,
      );

  /// withEvenPad sets all four sides at once.
  TextDrawSpec withEvenPad(double pad) => TextDrawSpec(
      color: color,
      start: start,
      padLeft: pad,
      padTop: pad,
      padRight: pad,
      padBottom: pad);

  Map<String, dynamic> toJson() => {
        if (color != null) "color": colorToJson(color!),
        if (start != TextDrawStart.showText) "start": start.name,
        if (padLeft != 0) "l": padLeft,
        if (padTop != 0) "t": padTop,
        if (padRight != 0) "r": padRight,
        if (padBottom != 0) "b": padBottom,
      };

  factory TextDrawSpec.fromJson(Map<String, dynamic> json) => TextDrawSpec(
        color: json["color"] == null
            ? null
            : colorFromJson(json["color"], const Color(0xFFFFFFFF)),
        start: TextDrawStart.fromName(json["start"] as String?),
        padLeft: jsonDouble(json["l"], 0),
        padTop: jsonDouble(json["t"], 0),
        padRight: jsonDouble(json["r"], 0),
        padBottom: jsonDouble(json["b"], 0),
      );
}

/// TextEchoSpec is how the copies of an echo are arranged.
///
/// The three numbers that decide what it looks like: how many, how far apart,
/// and how much quieter each one is than the one before. The reference is
/// five copies a line apart, each about a third fainter.
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

  /// resolve sends the copies on their way instead of leaving them there.
  ///
  /// An echo is a look: the copies fan out and stay, which is the reference
  /// somebody sent. Resolved, it is an *arrival*: they fan out over the first
  /// half, carry on in the direction they were headed over the second, and
  /// are gone by the end -- leaving the words alone on the page. The same
  /// eight directions, either as a look or as a way in.
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

  /// draw is what a drawn mark looks like, for the presets that draw one.
  final TextDrawSpec draw;

  /// echo is how the copies are arranged, for the presets that make them.
  final TextEchoSpec echo;

  /// scale is where a growing preset starts from, as a fraction: 0.6 arrives
  /// from a little small, 0 from nothing, 2 from twice the size.
  ///
  /// A number rather than three presets with three fixed numbers, which is
  /// what "Scale in" and "Zoom in" were -- the same motion at 0.6 and at 0.1,
  /// near enough alike to be a puzzle rather than a choice. Above one it
  /// arrives too large and settles; on the way *out* the same number is where
  /// it goes, so 2.5 carries the words off the screen and 0 shrinks them to
  /// nothing.
  ///
  /// Zero means "use the preset's own", so a preset chosen and left alone
  /// looks the way it is named.
  final double scale;

  final ChartEase ease;

  /// length is how many frames the arrival takes, or 0 for the usual two
  /// seconds.
  ///
  /// A setting rather than a reading: the keyframes on the timeline are where
  /// the animation actually is, and this is what a new one is laid down with.
  /// Dragging those keyframes does not write back here -- the number somebody
  /// typed is what they asked for, and a field that changed itself every time
  /// the timeline was nudged would be a setting that could not be relied on.
  final int length;

  /// flipOrder is set on the copy the painter draws the way out with, and is
  /// never saved. See ChartAnimation.flipOrder.
  final bool flipOrder;

  const TextAnimation({
    this.preset = TextAnimationPreset.none,
    this.exit = TextAnimationPreset.none,
    this.exitInOrder = false,
    this.gap = 0.35,
    this.scale = 0,
    this.draw = const TextDrawSpec(),
    this.echo = const TextEchoSpec(),
    this.ease = ChartEase.easeOut,
    this.length = 0,
    this.flipOrder = false,
  });

  bool get on => preset != TextAnimationPreset.none;

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

  /// scales is whether the size setting means anything for what is chosen.
  bool get scales =>
      preset.motion == TextMotion.grow || exit.motion == TextMotion.grow;
  bool get closes => exit != TextAnimationPreset.none;

  /// leaving is this animation as it is played on the way out.
  TextAnimation get leaving => copyWith(preset: exit, flipOrder: exitInOrder);

  TextAnimation copyWith({
    TextAnimationPreset? preset,
    TextAnimationPreset? exit,
    bool? exitInOrder,
    double? gap,
    double? scale,
    TextDrawSpec? draw,
    TextEchoSpec? echo,
    ChartEase? ease,
    int? length,
    bool? flipOrder,
  }) =>
      TextAnimation(
        preset: preset ?? this.preset,
        exit: exit ?? this.exit,
        exitInOrder: exitInOrder ?? this.exitInOrder,
        gap: gap ?? this.gap,
        scale: scale ?? this.scale,
        draw: draw ?? this.draw,
        echo: echo ?? this.echo,
        ease: ease ?? this.ease,
        length: length ?? this.length,
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
        if (scale > 0) "scale": scale,
        if (draw.toJson().isNotEmpty) "draw": draw.toJson(),
        if (echo.toJson().isNotEmpty) "echo": echo.toJson(),
        "ease": ease.name,
        if (length > 0) "length": length,
      };

  factory TextAnimation.fromJson(Map<String, dynamic> json) => TextAnimation(
        preset: TextAnimationPreset.fromName(json["preset"] as String?),
        exit: TextAnimationPreset.fromName(json["exit"] as String?),
        exitInOrder: jsonBool(json["exitOrder"], false),
        gap: jsonDouble(json["gap"], 0.35).clamp(0.0, 4.0),
        scale: jsonDouble(json["scale"], 0).clamp(0.0, 8.0),
        draw: json["draw"] is Map<String, dynamic>
            ? TextDrawSpec.fromJson(json["draw"] as Map<String, dynamic>)
            : const TextDrawSpec(),
        echo: json["echo"] is Map<String, dynamic>
            ? TextEchoSpec.fromJson(json["echo"] as Map<String, dynamic>)
            : const TextEchoSpec(),
        ease: ChartEase.fromName(json["ease"] as String?),
        length: jsonInt(json["length"], 0).clamp(0, 100000),
      );
}
