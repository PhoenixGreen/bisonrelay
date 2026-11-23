import 'package:bruig/components/paint_spec.dart';
import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';

// text_parts.dart is "these words, not the others": ranges of a text
// element's words or letters coloured, marked or animated differently.

enum TextUnit {
  words("Words"),
  characters("Characters");

  final String label;
  const TextUnit(this.label);

  static TextUnit fromName(String? name) =>
      values.firstWhere((u) => u.name == name, orElse: () => words);
}

/// PartLineStyle is what a line drawn under a part looks like. The [drawn]
/// styles wobble by the line's own position, not a random number, so a
/// frame exported twice is the same.
enum PartLineStyle {
  solid("Solid"),
  dashed("Dashed"),
  dotted("Dotted"),
  twin("Double"),
  wavy("Wavy"),
  hand("Hand drawn"),
  marker("Marker"),
  sketch("Sketched");

  final String label;
  const PartLineStyle(this.label);

  /// drawn is whether the style is stroked along a wobbling path.
  bool get drawn =>
      this == hand || this == marker || this == sketch || this == wavy;

  static PartLineStyle fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => solid);
}

/// PartHighlight is a band behind some of the words.
class PartHighlight {
  final Color color;

  /// fade is the second colour the band runs to, or null for a flat one.
  final GradientSpec? fade;
  final double padLeft;
  final double padTop;
  final double padRight;
  final double padBottom;

  final double radius;

  const PartHighlight({
    this.color = const Color(0x66FFD54F),
    this.fade,
    this.padLeft = 4,
    this.padTop = 2,
    this.padRight = 4,
    this.padBottom = 2,
    this.radius = 0,
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = PartHighlight();

  /// evenPad is the padding all four sides share, or null where they differ.
  double? get evenPad =>
      padLeft == padTop && padTop == padRight && padRight == padBottom
          ? padLeft
          : null;

  PartHighlight copyWith({
    Color? color,
    GradientSpec? fade,
    bool flat = false,
    double? padLeft,
    double? padTop,
    double? padRight,
    double? padBottom,
    double? radius,
  }) =>
      PartHighlight(
        color: color ?? this.color,
        fade: flat ? null : (fade ?? this.fade),
        padLeft: padLeft ?? this.padLeft,
        padTop: padTop ?? this.padTop,
        padRight: padRight ?? this.padRight,
        padBottom: padBottom ?? this.padBottom,
        radius: radius ?? this.radius,
      );

  PartHighlight mapColours(ColourMap f) {
    var p = ColourPass(f);
    var color = p(this.color);
    var fade = p.partOrNone(this.fade, (g) => g.mapColours(f));
    if (!p.changed) return this;
    return copyWith(color: color, fade: fade);
  }

  PartHighlight withEvenPad(double pad) =>
      copyWith(padLeft: pad, padTop: pad, padRight: pad, padBottom: pad);

  /// scaledBy sizes the padding and corners by [by].
  PartHighlight scaledBy(double by) => copyWith(
        padLeft: padLeft * by,
        padTop: padTop * by,
        padRight: padRight * by,
        padBottom: padBottom * by,
        radius: radius * by,
      );

  Map<String, dynamic> toJson() => {
        "color": colorToJson(color),
        if (fade != null) "fade": fade!.toJson(),
        "l": padLeft,
        "t": padTop,
        "r": padRight,
        "b": padBottom,
        if (radius != _defaults.radius) "radius": radius,
      };

  factory PartHighlight.fromJson(Map<String, dynamic> json) => PartHighlight(
        color: colorFromJson(json["color"], _defaults.color),
        fade: json["fade"] is Map
            ? GradientSpec.fromJson(
                (json["fade"] as Map).cast<String, dynamic>())
            : null,
        padLeft: jsonLength(json["l"], _defaults.padLeft, signed: true),
        padTop: jsonLength(json["t"], _defaults.padTop, signed: true),
        padRight: jsonLength(json["r"], _defaults.padRight, signed: true),
        padBottom: jsonLength(json["b"], _defaults.padBottom, signed: true),
        radius: jsonLength(json["radius"], _defaults.radius),
      );
}

class PartUnderline {
  /// color is the line's own, or null to take the words'.
  final Color? color;

  /// fade is the second colour the line runs to, or null for a flat one.
  final GradientSpec? fade;

  final double width;

  final PartLineStyle style;

  /// away is how far under the letters it sits; zero is an ordinary
  /// underline's place.
  final double away;

  const PartUnderline({
    this.color,
    this.fade,
    this.width = 3,
    this.style = PartLineStyle.solid,
    this.away = 2,
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = PartUnderline();

  PartUnderline copyWith({
    Color? color,
    GradientSpec? fade,
    bool flat = false,
    bool clearColor = false,
    double? width,
    PartLineStyle? style,
    double? away,
  }) =>
      PartUnderline(
        color: clearColor ? null : (color ?? this.color),
        fade: flat ? null : (fade ?? this.fade),
        width: width ?? this.width,
        style: style ?? this.style,
        away: away ?? this.away,
      );

  /// scaledBy sizes the line and its distance under the letters by [by].
  PartUnderline scaledBy(double by) =>
      copyWith(width: width * by, away: away * by);

  /// mapColours maps the line's colour (none is the words', and stays none)
  /// and its fade.
  PartUnderline mapColours(ColourMap f) {
    var p = ColourPass(f);
    var color = p.orNone(this.color);
    var fade = p.partOrNone(this.fade, (g) => g.mapColours(f));
    if (!p.changed) return this;
    return copyWith(color: color, fade: fade);
  }

  Map<String, dynamic> toJson() => {
        if (color != null) "color": colorToJson(color!),
        if (fade != null) "fade": fade!.toJson(),
        "width": width,
        if (style != _defaults.style) "style": style.name,
        "away": away,
      };

  factory PartUnderline.fromJson(Map<String, dynamic> json) => PartUnderline(
        color: json["color"] == null
            ? null
            : colorFromJson(json["color"], const Color(0xFFFFFFFF)),
        fade: json["fade"] is Map
            ? GradientSpec.fromJson(
                (json["fade"] as Map).cast<String, dynamic>())
            : null,
        width: jsonDouble(json["width"], _defaults.width)
            .clamp(0.1, maxDesignLength),
        style: PartLineStyle.fromName(jsonStr(json["style"])),
        away: jsonLength(json["away"], _defaults.away, signed: true),
      );
}

/// TextPartAnimation is how one part of the text arrives, timed in frames
/// from the start of the element's arrival, so a word can land after (or
/// before) its line.
class TextPartAnimation {
  final TextAnimationPreset preset;

  /// offset is frames after the arrival starts; negative brings it forward.
  final int offset;

  /// length is how many frames it takes, or 0 for as long as the arrival.
  final int length;

  final double gap;
  final double scale;
  final TextEchoSpec echo;
  final TextDrawSpec draw;
  final ChartEase ease;

  /// effect is how a cutting preset cuts this part's words (see EffectSpec).
  final EffectSpec effect;

  /// marks is whether this part's highlight and underline are drawn on, with
  /// their own timing, so a word can arrive and then be underlined.
  final bool marks;
  final int markOffset;
  final int markLength;

  const TextPartAnimation({
    this.preset = TextAnimationPreset.none,
    this.offset = 0,
    this.length = 0,
    this.gap = 0.35,
    this.scale = 0,
    this.echo = const TextEchoSpec(),
    this.draw = const TextDrawSpec(),
    this.ease = ChartEase.easeOut,
    this.effect = const EffectSpec(),
    this.marks = false,
    this.markOffset = 0,
    this.markLength = 0,
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = TextPartAnimation();

  bool get on => preset != TextAnimationPreset.none;

  TextAnimation get asAnimation => TextAnimation(
        preset: preset,
        gap: gap,
        scale: scale,
        echo: echo,
        draw: draw,
        ease: ease,
        effect: effect,
      );

  /// fromAnimation takes back settings-panel changes to [asAnimation],
  /// keeping this part's own timing.
  TextPartAnimation fromAnimation(TextAnimation a) => copyWith(
        preset: a.preset,
        gap: a.gap,
        scale: a.scale,
        echo: a.echo,
        draw: a.draw,
        ease: a.ease,
        effect: a.effect,
      );

  TextPartAnimation copyWith({
    TextAnimationPreset? preset,
    int? offset,
    int? length,
    double? gap,
    double? scale,
    TextEchoSpec? echo,
    TextDrawSpec? draw,
    ChartEase? ease,
    EffectSpec? effect,
    bool? marks,
    int? markOffset,
    int? markLength,
  }) =>
      TextPartAnimation(
        preset: preset ?? this.preset,
        offset: offset ?? this.offset,
        length: length ?? this.length,
        gap: gap ?? this.gap,
        scale: scale ?? this.scale,
        echo: echo ?? this.echo,
        draw: draw ?? this.draw,
        ease: ease ?? this.ease,
        effect: effect ?? this.effect,
        marks: marks ?? this.marks,
        markOffset: markOffset ?? this.markOffset,
        markLength: markLength ?? this.markLength,
      );

  TextPartAnimation mapColours(ColourMap f) {
    var next = draw.mapColours(f);
    return identical(next, draw) ? this : copyWith(draw: next);
  }

  Map<String, dynamic> toJson() => {
        if (on) "preset": preset.name,
        if (offset != _defaults.offset) "offset": offset,
        if (length != _defaults.length) "length": length,
        if (gap != _defaults.gap) "gap": gap,
        if (scale > 0) "scale": scale,
        if (echo.toJson().isNotEmpty) "echo": echo.toJson(),
        if (draw.toJson().isNotEmpty) "draw": draw.toJson(),
        if (ease != _defaults.ease) "ease": ease.name,
        if (effect != _defaults.effect) "effect": effect.toJson(),
        if (marks) "marks": true,
        if (markOffset != _defaults.markOffset) "markOffset": markOffset,
        if (markLength != _defaults.markLength) "markLength": markLength,
      };

  factory TextPartAnimation.fromJson(Map<String, dynamic> json) =>
      TextPartAnimation(
        preset: TextAnimationPreset.fromName(jsonStr(json["preset"])),
        offset: jsonInt(json["offset"], _defaults.offset),
        length: jsonInt(json["length"], _defaults.length).clamp(0, 100000),
        gap: jsonDouble(json["gap"], _defaults.gap).clamp(0.0, 4.0),
        scale: jsonDouble(json["scale"], _defaults.scale).clamp(0.0, 8.0),
        echo: json["echo"] is Map<String, dynamic>
            ? TextEchoSpec.fromJson(json["echo"] as Map<String, dynamic>)
            : const TextEchoSpec(),
        draw: json["draw"] is Map<String, dynamic>
            ? TextDrawSpec.fromJson(json["draw"] as Map<String, dynamic>)
            : const TextDrawSpec(),
        ease: ChartEase.fromName(jsonStr(json["ease"])),
        effect: json["effect"] is Map<String, dynamic>
            ? EffectSpec.fromJson(json["effect"] as Map<String, dynamic>)
            : const EffectSpec(),
        marks: jsonBool(json["marks"], false),
        markOffset: jsonInt(json["markOffset"], _defaults.markOffset),
        markLength:
            jsonInt(json["markLength"], _defaults.markLength).clamp(0, 100000),
      );
}

/// partsOutline is whether any of [parts] draws its own outline, so the
/// paragraph needs an outline pass even if the element has none.
bool partsOutline(List<TextPart> parts) {
  for (var part in parts) {
    if ((part.outlineWidth ?? 0) > 0) return true;
  }
  return false;
}

/// partsFrom is [parts] for a slice of the text that begins [words] words
/// in, as a box further along a chain draws: renumbered from the slice's
/// first word, those ending before it dropped, those straddling it trimmed.
List<TextPart> partsFrom(List<TextPart> parts, int words) {
  if (words <= 0 || parts.isEmpty) return parts;
  var out = <TextPart>[];
  for (var part in parts) {
    // Only word ranges shift; letter ranges are dropped.
    if (part.unit != TextUnit.words) continue;
    if (!part.toTheEnd && part.to <= words) continue;
    out.add(part.copyWith(
      from: math.max(1, part.from - words),
      to: part.toTheEnd ? 0 : part.to - words,
    ));
  }
  return out;
}

/// isWordSpace is whether [c], one character, comes between words:
/// whitespace, as String.trim sees it. Parts count words by it, so whatever
/// cuts a text into words (an arrival, a line, a chain of boxes, a
/// document's runs) goes by it too, or a part and an arrival would mean
/// different words by "the third".
bool isWordSpace(String c) => c.trim().isEmpty;

/// wordRanges is where each word of [text] starts and ends.
List<({int start, int end})> wordRanges(String text) {
  var out = <({int start, int end})>[];
  var i = 0;
  while (i < text.length) {
    while (i < text.length && isWordSpace(text[i])) {
      i++;
    }
    var start = i;
    while (i < text.length && !isWordSpace(text[i])) {
      i++;
    }
    if (i > start) out.add((start: start, end: i));
  }
  return out;
}

/// wordsIn is how many words [text] has.
int wordsIn(String text) => wordRanges(text).length;

/// partsAnimate is whether any of [parts] has its own arrival or drawn-on
/// mark: the paragraph must then go through the animator even after the
/// element's own arrival is over.
bool partsAnimate(List<TextPart> parts) {
  for (var part in parts) {
    if (part.animation.on || part.animation.marks) return true;
  }
  return false;
}

/// PartTiming is how far one part has got on this frame, 0..1: its words,
/// and separately the mark drawn on them.
class PartTiming {
  final double words;
  final double mark;
  const PartTiming(this.words, this.mark);

  static const there = PartTiming(1, 1);
}

/// timingOf is where [part] has got to on [frame]. [from] is the frame the
/// element's arrival starts on and [span] its length; parts are measured
/// from those, so moving the arrival carries them with it.
PartTiming timingOf(TextPart part,
    {required int frame, required int from, required int span}) {
  var animation = part.animation;
  if (span <= 0) return PartTiming.there;

  double at(int offset, int length) {
    var over = length > 0 ? length : span;
    if (over <= 0) return 1;
    return ((frame - (from + offset)) / over).clamp(0.0, 1.0);
  }

  return PartTiming(
    animation.on ? at(animation.offset, animation.length) : 1,
    animation.marks ? at(animation.markOffset, animation.markLength) : 1,
  );
}

/// TextPart is a range of the words or letters, and what is different
/// about it. Counted from one, as the settings panel shows it.
class TextPart {
  final TextUnit unit;

  final int from;

  /// to is the last, included, or zero for "to the end", which stays right
  /// when the text is edited.
  final int to;

  /// color is this part's colour, or null for the element's.
  final Color? color;

  /// weight and italic override the element's; null leaves them.
  final int? weight;
  final bool? italic;

  /// scale sizes these words against the rest; null is the element's size.
  final double? scale;

  final String? family;

  /// outlineWidth and outlineColor override the element's outline; null is
  /// the element's, and a width of zero takes the outline off these words.
  final double? outlineWidth;
  final Color? outlineColor;

  /// highlight is a band behind these words, and underline a line under
  /// them; [animation]'s marks setting draws them on.
  final PartHighlight? highlight;
  final PartUnderline? underline;

  /// animation is how these words arrive on their own; nothing happens
  /// unless a preset is chosen.
  final TextPartAnimation animation;

  const TextPart({
    this.unit = TextUnit.words,
    this.from = 1,
    this.to = 0,
    this.color,
    this.weight,
    this.italic,
    this.scale,
    this.family,
    this.outlineWidth,
    this.outlineColor,
    this.highlight,
    this.underline,
    this.animation = const TextPartAnimation(),
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = TextPart();

  bool get toTheEnd => to <= 0;

  String get says {
    var what = unit == TextUnit.words ? "word" : "letter";
    if (toTheEnd) {
      return from <= 1 ? "Every $what" : "From $what $from to the end";
    }
    if (from == to) return "${what[0].toUpperCase()}${what.substring(1)} $from";
    return "${what[0].toUpperCase()}${what.substring(1)}s $from to $to";
  }

  TextPart copyWith({
    TextUnit? unit,
    int? from,
    int? to,
    Color? color,
    bool clearColor = false,
    int? weight,
    bool? italic,
    double? scale,
    String? family,
    double? outlineWidth,
    bool clearOutline = false,
    Color? outlineColor,
    PartHighlight? highlight,
    bool clearHighlight = false,
    PartUnderline? underline,
    bool clearUnderline = false,
    TextPartAnimation? animation,
  }) =>
      TextPart(
        unit: unit ?? this.unit,
        from: from ?? this.from,
        to: to ?? this.to,
        color: clearColor ? null : (color ?? this.color),
        weight: weight ?? this.weight,
        italic: italic ?? this.italic,
        scale: scale ?? this.scale,
        family: family ?? this.family,
        outlineWidth: clearOutline ? null : (outlineWidth ?? this.outlineWidth),
        outlineColor: clearOutline ? null : (outlineColor ?? this.outlineColor),
        highlight: clearHighlight ? null : (highlight ?? this.highlight),
        underline: clearUnderline ? null : (underline ?? this.underline),
        animation: animation ?? this.animation,
      );

  /// scaledBy sizes the part's outline and marks, drawn ones too, by [by];
  /// its own size is a share of the element's, which scales already.
  TextPart scaledBy(double by) => copyWith(
        outlineWidth: outlineWidth == null ? null : outlineWidth! * by,
        highlight: highlight?.scaledBy(by),
        underline: underline?.scaledBy(by),
        animation: animation.copyWith(draw: animation.draw.scaledBy(by)),
      );

  /// mapColours maps the part's own colour and outline colour (none is the
  /// element's, and stays none; the outline's is hidden where the part's
  /// own outline width is nought), its highlight, underline and drawn mark.
  TextPart mapColours(ColourMap f) {
    var p = ColourPass(f);
    var color = p.orNone(this.color);
    var outlineColor =
        p.orNone(this.outlineColor, shown: (outlineWidth ?? 1) > 0);
    var highlight = p.partOrNone(this.highlight, (h) => h.mapColours(f));
    var underline = p.partOrNone(this.underline, (u) => u.mapColours(f));
    var animation = p.part(this.animation, (a) => a.mapColours(f));
    if (!p.changed) return this;
    return copyWith(
      color: color,
      outlineColor: outlineColor,
      highlight: highlight,
      underline: underline,
      animation: animation,
    );
  }

  Map<String, dynamic> toJson() => {
        if (unit != _defaults.unit) "unit": unit.name,
        "from": from,
        if (to > 0) "to": to,
        if (color != null) "color": colorToJson(color!),
        if (weight != null) "weight": weight,
        if (italic != null) "italic": italic,
        if (scale != null) "scale": scale,
        if (family != null) "family": family,
        if (outlineWidth != null) "outlineWidth": outlineWidth,
        if (outlineColor != null) "outlineColor": colorToJson(outlineColor!),
        if (highlight != null) "highlight": highlight!.toJson(),
        if (underline != null) "underline": underline!.toJson(),
        if (animation.toJson().isNotEmpty) "animation": animation.toJson(),
      };

  factory TextPart.fromJson(Map<String, dynamic> json) => TextPart(
        unit: TextUnit.fromName(jsonStr(json["unit"])),
        from: jsonInt(json["from"], _defaults.from).clamp(1, 100000),
        to: jsonInt(json["to"], _defaults.to).clamp(0, 100000),
        color: json["color"] == null
            ? null
            : colorFromJson(json["color"], const Color(0xFFFFFFFF)),
        weight: json["weight"] is num
            ? jsonInt(json["weight"], 400).clamp(1, 1000)
            : null,
        italic: json["italic"] is bool ? json["italic"] as bool : null,
        scale: json["scale"] is num
            ? (json["scale"] as num).toDouble().clamp(0.05, 20.0)
            : null,
        family: json["family"] is String ? jsonLabel(json["family"], "") : null,
        outlineWidth: json["outlineWidth"] is num
            ? jsonLength(json["outlineWidth"], 0)
            : null,
        outlineColor: json["outlineColor"] == null
            ? null
            : colorFromJson(json["outlineColor"], const Color(0xFFFFFFFF)),
        highlight: json["highlight"] is Map<String, dynamic>
            ? PartHighlight.fromJson(json["highlight"] as Map<String, dynamic>)
            : null,
        underline: json["underline"] is Map<String, dynamic>
            ? PartUnderline.fromJson(json["underline"] as Map<String, dynamic>)
            : null,
        animation: json["animation"] is Map<String, dynamic>
            ? TextPartAnimation.fromJson(
                json["animation"] as Map<String, dynamic>)
            : const TextPartAnimation(),
      );
}

/// rangeOf is the characters a part covers in [text], from [start] up to
/// [end]. Null where the part starts past the end, rather than clamping it
/// onto the wrong words.
({int start, int end})? rangeOf(String text, TextPart part) {
  if (text.isEmpty || part.from < 1) return null;

  if (part.unit == TextUnit.characters) {
    // Letters skip whitespace: the third letter is the third visible one.
    var at = <int>[];
    for (var i = 0; i < text.length; i++) {
      if (!isWordSpace(text[i])) at.add(i);
    }
    if (at.length < part.from) return null;
    var last = part.toTheEnd ? at.length : part.to;
    if (last < part.from) return null;
    var end = at[(last.clamp(part.from, at.length)) - 1] + 1;
    return (start: at[part.from - 1], end: end);
  }

  var words = wordRanges(text);
  if (words.length < part.from) return null;
  var last = part.toTheEnd ? words.length : part.to;
  if (last < part.from) return null;
  return (
    start: words[part.from - 1].start,
    end: words[last.clamp(part.from, words.length) - 1].end
  );
}

/// partAt is the part covering [index], or null; the last wins on overlap.
TextPart? partAt(String text, List<TextPart> parts, int index) {
  TextPart? found;
  for (var part in parts) {
    var range = rangeOf(text, part);
    if (range == null) continue;
    if (index >= range.start && index < range.end) found = part;
  }
  return found;
}

class TextIcon {
  final String assetId;

  final double size;

  /// color tints it (cut to its own shape and filled), or null for its own
  /// colours.
  final Color? color;

  /// outlineWidth draws its silhouette behind it in outlineColor, a sticker
  /// outline.
  final double outlineWidth;
  final Color outlineColor;

  final BoxSpec box;

  final PartUnderline? underline;

  /// turn is how far the picture is turned about its middle, in degrees
  /// clockwise; its room in the slot stays square and upright.
  final double turn;

  const TextIcon({
    this.assetId = "",
    this.size = 64,
    this.turn = 0,
    this.color,
    this.outlineWidth = 0,
    this.outlineColor = const Color(0xFF000000),
    this.box = const BoxSpec(padding: 0),
    this.underline,
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = TextIcon();

  bool get on => assetId.isNotEmpty;

  TextIcon copyWith({
    String? assetId,
    double? size,
    Color? color,
    bool clearColor = false,
    double? outlineWidth,
    Color? outlineColor,
    BoxSpec? box,
    PartUnderline? underline,
    bool clearUnderline = false,
    double? turn,
  }) =>
      TextIcon(
        assetId: assetId ?? this.assetId,
        size: size ?? this.size,
        turn: turn ?? this.turn,
        color: clearColor ? null : (color ?? this.color),
        outlineWidth: outlineWidth ?? this.outlineWidth,
        outlineColor: outlineColor ?? this.outlineColor,
        box: box ?? this.box,
        underline: clearUnderline ? null : (underline ?? this.underline),
      );

  /// mapColours maps its tint (none is its own colours, and stays none), its
  /// outline colour (shown only with an outline, as it is saved), its box
  /// and its underline.
  TextIcon mapColours(ColourMap f) {
    var p = ColourPass(f);
    var color = p.orNone(this.color);
    var outlineColor = p(this.outlineColor, shown: outlineWidth > 0);
    var box = p.part(this.box, (b) => b.mapColours(f));
    var underline = p.partOrNone(this.underline, (u) => u.mapColours(f));
    if (!p.changed) return this;
    return copyWith(
      color: color,
      outlineColor: outlineColor,
      box: box,
      underline: underline,
    );
  }

  Map<String, dynamic> toJson() => {
        "assetId": assetId,
        "size": size,
        if (turn != _defaults.turn) "turn": turn,
        if (color != null) "color": colorToJson(color!),
        if (outlineWidth > 0) "ow": outlineWidth,
        if (outlineWidth > 0) "oc": colorToJson(outlineColor),
        "box": box.toJson(),
        if (underline != null) "underline": underline!.toJson(),
      };

  factory TextIcon.fromJson(Map<String, dynamic> json) => TextIcon(
        assetId: jsonString(json["assetId"], _defaults.assetId),
        size: jsonDouble(json["size"], _defaults.size).clamp(1, 4000),
        turn: jsonDouble(json["turn"], _defaults.turn).clamp(-360, 360),
        color: json["color"] == null
            ? null
            : colorFromJson(json["color"], const Color(0xFFFFFFFF)),
        outlineWidth: jsonLength(json["ow"], _defaults.outlineWidth),
        outlineColor: colorFromJson(json["oc"], _defaults.outlineColor),
        box: json["box"] is Map<String, dynamic>
            ? BoxSpec.fromJson(json["box"] as Map<String, dynamic>)
            : const BoxSpec(padding: 0),
        underline: json["underline"] is Map<String, dynamic>
            ? PartUnderline.fromJson(json["underline"] as Map<String, dynamic>)
            : null,
      );
}
