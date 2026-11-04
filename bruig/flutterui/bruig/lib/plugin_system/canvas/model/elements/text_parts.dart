import 'package:bruig/components/paint_spec.dart';
import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

// text_parts.dart is "these words, not the others": ranges of a text
// element's words or letters that are coloured, marked or animated
// differently. Shared by every feature that asks the question, and a list so
// different ranges can be styled differently.

/// TextUnit is what a part counts in.
enum TextUnit {
  words("Words"),
  characters("Characters");

  final String label;
  const TextUnit(this.label);

  static TextUnit fromName(String? name) =>
      values.firstWhere((u) => u.name == name, orElse: () => words);
}

/// PartLineStyle is what a line drawn under a part looks like.
///
/// The [drawn] styles wobble. The wobble comes from the line's own position
/// rather than a random number, so a frame exported twice is the same.
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

  /// drawn is whether the style is stroked along a wobbling path instead of
  /// a straight one.
  bool get drawn =>
      this == hand || this == marker || this == sketch || this == wavy;

  static PartLineStyle fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => solid);
}

/// PartHighlight is a band behind some of the words, with its own colour and
/// padding on each side.
class PartHighlight {
  final Color color;

  /// fade is the second colour the band runs to, or null for a flat one.
  final GradientSpec? fade;
  final double padLeft;
  final double padTop;
  final double padRight;
  final double padBottom;

  /// radius rounds the band's corners.
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

  /// evenPad is the one number the four sides share, or null where they
  /// differ.
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

  PartHighlight withEvenPad(double pad) =>
      copyWith(padLeft: pad, padTop: pad, padRight: pad, padBottom: pad);

  Map<String, dynamic> toJson() => {
        "color": colorToJson(color),
        if (fade != null) "fade": fade!.toJson(),
        "l": padLeft,
        "t": padTop,
        "r": padRight,
        "b": padBottom,
        if (radius != 0) "radius": radius,
      };

  factory PartHighlight.fromJson(Map<String, dynamic> json) => PartHighlight(
        color: colorFromJson(json["color"], const Color(0x66FFD54F)),
        fade: json["fade"] is Map
            ? GradientSpec.fromJson(
                (json["fade"] as Map).cast<String, dynamic>())
            : null,
        padLeft: jsonDouble(json["l"], 4),
        padTop: jsonDouble(json["t"], 2),
        padRight: jsonDouble(json["r"], 4),
        padBottom: jsonDouble(json["b"], 2),
        radius: jsonDouble(json["radius"], 0),
      );
}

/// PartUnderline is a line under some of the words.
class PartUnderline {
  /// color is the line's own, or null to take the words'.
  final Color? color;

  /// fade is the second colour the line runs to, or null for a flat one.
  final GradientSpec? fade;

  /// width is how thick it is, in design pixels.
  final double width;

  final PartLineStyle style;

  /// away is how far under the letters it sits; zero is where an ordinary
  /// underline goes.
  final double away;

  const PartUnderline({
    this.color,
    this.fade,
    this.width = 3,
    this.style = PartLineStyle.solid,
    this.away = 2,
  });

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

  Map<String, dynamic> toJson() => {
        if (color != null) "color": colorToJson(color!),
        if (fade != null) "fade": fade!.toJson(),
        "width": width,
        if (style != PartLineStyle.solid) "style": style.name,
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
        width: jsonDouble(json["width"], 3).clamp(0.1, 80),
        style: PartLineStyle.fromName(jsonStr(json["style"])),
        away: jsonDouble(json["away"], 2),
      );
}

/// TextPartAnimation is how one part of the text arrives, and when: its own
/// animation, timed in frames from the start of the element's arrival, so a
/// word can land after (or before) the line it is in.
class TextPartAnimation {
  final TextAnimationPreset preset;

  /// offset is how many frames after the arrival starts this one does;
  /// negative brings it forward.
  final int offset;

  /// length is how many frames it takes, or 0 for as long as the arrival.
  final int length;

  final double gap;
  final double scale;
  final TextEchoSpec echo;
  final TextDrawSpec draw;
  final ChartEase ease;

  /// marks is whether this part's highlight and underline are drawn on
  /// rather than simply there, with their own timing so a word can arrive
  /// and then be underlined.
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
    this.marks = false,
    this.markOffset = 0,
    this.markLength = 0,
  });

  bool get on => preset != TextAnimationPreset.none;

  /// asAnimation is this as a TextAnimation, so a part is animated by the
  /// same code as a paragraph.
  TextAnimation get asAnimation => TextAnimation(
        preset: preset,
        gap: gap,
        scale: scale,
        echo: echo,
        draw: draw,
        ease: ease,
      );

  /// fromAnimation is the reverse of [asAnimation]: it takes back what the
  /// settings panel changed and keeps this part's own timing.
  TextPartAnimation fromAnimation(TextAnimation a) => copyWith(
        preset: a.preset,
        gap: a.gap,
        scale: a.scale,
        echo: a.echo,
        draw: a.draw,
        ease: a.ease,
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
        marks: marks ?? this.marks,
        markOffset: markOffset ?? this.markOffset,
        markLength: markLength ?? this.markLength,
      );

  Map<String, dynamic> toJson() => {
        if (on) "preset": preset.name,
        if (offset != 0) "offset": offset,
        if (length != 0) "length": length,
        if (gap != 0.35) "gap": gap,
        if (scale > 0) "scale": scale,
        if (echo.toJson().isNotEmpty) "echo": echo.toJson(),
        if (draw.toJson().isNotEmpty) "draw": draw.toJson(),
        if (ease != ChartEase.easeOut) "ease": ease.name,
        if (marks) "marks": true,
        if (markOffset != 0) "markOffset": markOffset,
        if (markLength != 0) "markLength": markLength,
      };

  factory TextPartAnimation.fromJson(Map<String, dynamic> json) =>
      TextPartAnimation(
        preset: TextAnimationPreset.fromName(jsonStr(json["preset"])),
        offset: jsonInt(json["offset"], 0),
        length: jsonInt(json["length"], 0).clamp(0, 100000),
        gap: jsonDouble(json["gap"], 0.35).clamp(0.0, 4.0),
        scale: jsonDouble(json["scale"], 0).clamp(0.0, 8.0),
        echo: json["echo"] is Map<String, dynamic>
            ? TextEchoSpec.fromJson(json["echo"] as Map<String, dynamic>)
            : const TextEchoSpec(),
        draw: json["draw"] is Map<String, dynamic>
            ? TextDrawSpec.fromJson(json["draw"] as Map<String, dynamic>)
            : const TextDrawSpec(),
        ease: ChartEase.fromName(jsonStr(json["ease"])),
        marks: jsonBool(json["marks"], false),
        markOffset: jsonInt(json["markOffset"], 0),
        markLength: jsonInt(json["markLength"], 0).clamp(0, 100000),
      );
}

/// partsOutline is whether any of [parts] draws its own outline, in which
/// case the paragraph needs an outline pass even if the element has none.
bool partsOutline(List<TextPart> parts) {
  for (var part in parts) {
    if ((part.outlineWidth ?? 0) > 0) return true;
  }
  return false;
}

/// partsFrom is [parts] as they apply to a slice of the text that begins
/// [words] words in.
///
/// Used by a box further along a chain, which draws the tail of the head's
/// text: parts are renumbered from the slice's first word, those ending
/// before it are dropped and those straddling it trimmed.
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

/// wordsIn counts the whitespace-separated words of [text].
int wordsIn(String text) {
  var words = 0;
  var inWord = false;
  for (var i = 0; i < text.length; i++) {
    var space = text[i].trim().isEmpty;
    if (!space && !inWord) words++;
    inWord = !space;
  }
  return words;
}

/// partsAnimate is whether any of [parts] has its own arrival or drawn-on
/// mark, in which case the paragraph must go through the animator even when
/// the element's own arrival is over.
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

/// timingOf is where [part] has got to on [frame].
///
/// [from] is the frame the element's own arrival starts on and [span] how
/// many frames it takes. Everything a part does is measured from those, so
/// moving the arrival carries the parts with it.
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

/// TextPart is a range of the words or letters, and what is different about
/// it. Counted from one, as the settings panel shows it.
class TextPart {
  final TextUnit unit;

  /// from is the first word or letter, counting from one.
  final int from;

  /// to is the last, counting from one and included, or zero for "to the
  /// end", which stays right when the text is edited.
  final int to;

  /// color is what this part is drawn in, or null for the element's.
  final Color? color;

  /// weight and italic override the element's; null leaves them.
  final int? weight;
  final bool? italic;

  /// scale sizes these words against the rest, as a multiplier; null is the
  /// element's size.
  final double? scale;

  /// family is the face these words are set in, or null for the element's.
  final String? family;

  /// outlineWidth and outlineColor override the element's outline for these
  /// words; null is the element's. A width of zero is not null: it takes the
  /// outline off these words.
  final double? outlineWidth;
  final Color? outlineColor;

  /// highlight is a band behind these words, and underline a line under
  /// them, or null for neither. They are always there; [animation]'s marks
  /// setting draws them on.
  final PartHighlight? highlight;
  final PartUnderline? underline;

  /// animation is how these words arrive on their own account; nothing
  /// happens unless a preset is chosen. See TextPartAnimation.
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

  bool get toTheEnd => to <= 0;

  /// says is this part's range in words, for the settings panel.
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

  Map<String, dynamic> toJson() => {
        if (unit != TextUnit.words) "unit": unit.name,
        "from": from,
        if (to > 0) "to": to,
        if (color != null) "color": colorToJson(color!),
        if (weight != null) "weight": weight,
        if (italic != null) "italic": italic,
        if (scale != null) "scale": scale,
        if (family != null) "family": family,
        if (scale != null) "scale": scale,
        if (outlineWidth != null) "outlineWidth": outlineWidth,
        if (outlineColor != null) "outlineColor": colorToJson(outlineColor!),
        if (highlight != null) "highlight": highlight!.toJson(),
        if (underline != null) "underline": underline!.toJson(),
        if (animation.toJson().isNotEmpty) "animation": animation.toJson(),
      };

  factory TextPart.fromJson(Map<String, dynamic> json) => TextPart(
        unit: TextUnit.fromName(jsonStr(json["unit"])),
        from: jsonInt(json["from"], 1).clamp(1, 100000),
        to: jsonInt(json["to"], 0).clamp(0, 100000),
        color: json["color"] == null
            ? null
            : colorFromJson(json["color"], const Color(0xFFFFFFFF)),
        weight: json["weight"] is num ? (json["weight"] as num).toInt() : null,
        italic: json["italic"] is bool ? json["italic"] as bool : null,
        scale: json["scale"] is num
            ? (json["scale"] as num).toDouble().clamp(0.05, 20.0)
            : null,
        family: json["family"] is String ? json["family"] as String : null,
        outlineWidth: json["outlineWidth"] is num
            ? (json["outlineWidth"] as num).toDouble().clamp(0.0, 80.0)
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

/// rangeOf is the characters a part covers, as a start and an end offset into
/// [text].
///
/// Null where the part starts past the end of the text, rather than clamping
/// it onto the wrong words.
(int, int)? rangeOf(String text, TextPart part) {
  if (text.isEmpty || part.from < 1) return null;

  if (part.unit == TextUnit.characters) {
    // Letters skip whitespace: the third letter is the third visible one.
    var at = <int>[];
    for (var i = 0; i < text.length; i++) {
      if (text[i].trim().isNotEmpty) at.add(i);
    }
    if (at.length < part.from) return null;
    var last = part.toTheEnd ? at.length : part.to;
    if (last < part.from) return null;
    var end = at[(last.clamp(part.from, at.length)) - 1] + 1;
    return (at[part.from - 1], end);
  }

  var words = <(int, int)>[];
  var i = 0;
  while (i < text.length) {
    while (i < text.length && text[i].trim().isEmpty) {
      i++;
    }
    var start = i;
    while (i < text.length && text[i].trim().isNotEmpty) {
      i++;
    }
    if (i > start) words.add((start, i));
  }
  if (words.length < part.from) return null;
  var last = part.toTheEnd ? words.length : part.to;
  if (last < part.from) return null;
  return (
    words[part.from - 1].$1,
    words[last.clamp(part.from, words.length) - 1].$2
  );
}

/// partAt is the part covering [index], or null.
///
/// The last one wins where two overlap.
TextPart? partAt(String text, List<TextPart> parts, int index) {
  TextPart? found;
  for (var part in parts) {
    var range = rangeOf(text, part);
    if (range == null) continue;
    if (index >= range.$1 && index < range.$2) found = part;
  }
  return found;
}

/// IconPlace is where an older document's single icon sat relative to the
/// words; read only to pick the slot it becomes (see _slotForIcon in
/// text_element.dart).
enum IconPlace {
  start("Before the text"),
  end("After the text"),
  over("Above the text"),
  under("Below the text");

  final String label;
  const IconPlace(this.label);

  /// beside is whether the icon is at the side rather than above or below.
  bool get beside => this == start || this == end;

  static IconPlace fromName(String? name) =>
      values.firstWhere((p) => p.name == name, orElse: () => start);
}

/// TextIcon is the picture a picture piece (TextItem.icon) shows.
///
/// [place], [gap], [align] and [animate] are from when a text element had a
/// single icon of its own; they are kept for reading and writing, but only
/// place and align are used, to pick the slot an old icon becomes.
class TextIcon {
  final String assetId;
  final IconPlace place;

  /// size is how tall the icon is drawn, in design pixels.
  final double size;

  /// color tints it (the picture cut to its own shape and filled), or null
  /// to draw it in its own colours.
  final Color? color;

  /// gap was the room between an old icon and the words.
  final double gap;

  /// align was where an old icon sat along the edge it was on.
  final TextIconAlign align;

  /// outlineWidth draws the icon's silhouette behind it in outlineColor: a
  /// sticker outline.
  final double outlineWidth;
  final Color outlineColor;

  final BoxSpec box;

  /// underline is a line under the icon, or null for none.
  final PartUnderline? underline;

  /// animate was whether an old icon moved with the words as they arrived.
  final bool animate;

  const TextIcon({
    this.assetId = "",
    this.place = IconPlace.start,
    this.size = 64,
    this.color,
    this.gap = 12,
    this.align = TextIconAlign.middle,
    this.outlineWidth = 0,
    this.outlineColor = const Color(0xFF000000),
    this.box = const BoxSpec(padding: 0),
    this.underline,
    this.animate = true,
  });

  bool get on => assetId.isNotEmpty;

  TextIcon copyWith({
    String? assetId,
    IconPlace? place,
    double? size,
    Color? color,
    bool clearColor = false,
    double? gap,
    TextIconAlign? align,
    double? outlineWidth,
    Color? outlineColor,
    BoxSpec? box,
    PartUnderline? underline,
    bool clearUnderline = false,
    bool? animate,
  }) =>
      TextIcon(
        assetId: assetId ?? this.assetId,
        place: place ?? this.place,
        size: size ?? this.size,
        color: clearColor ? null : (color ?? this.color),
        gap: gap ?? this.gap,
        align: align ?? this.align,
        outlineWidth: outlineWidth ?? this.outlineWidth,
        outlineColor: outlineColor ?? this.outlineColor,
        box: box ?? this.box,
        underline: clearUnderline ? null : (underline ?? this.underline),
        animate: animate ?? this.animate,
      );

  Map<String, dynamic> toJson() => {
        "assetId": assetId,
        if (place != IconPlace.start) "place": place.name,
        "size": size,
        if (color != null) "color": colorToJson(color!),
        "gap": gap,
        if (align != TextIconAlign.middle) "align": align.name,
        if (outlineWidth > 0) "ow": outlineWidth,
        if (outlineWidth > 0) "oc": colorToJson(outlineColor),
        "box": box.toJson(),
        if (underline != null) "underline": underline!.toJson(),
        // Always written, since the default is true.
        "animate": animate,
      };

  factory TextIcon.fromJson(Map<String, dynamic> json) => TextIcon(
        assetId: jsonString(json["assetId"], ""),
        place: IconPlace.fromName(jsonStr(json["place"])),
        size: jsonDouble(json["size"], 64).clamp(1, 4000),
        color: json["color"] == null
            ? null
            : colorFromJson(json["color"], const Color(0xFFFFFFFF)),
        gap: jsonDouble(json["gap"], 12).clamp(-4000, 4000),
        align: TextIconAlign.fromName(jsonStr(json["align"])),
        outlineWidth: jsonDouble(json["ow"], 0).clamp(0, 200),
        outlineColor: colorFromJson(json["oc"], const Color(0xFF000000)),
        box: json["box"] is Map<String, dynamic>
            ? BoxSpec.fromJson(json["box"] as Map<String, dynamic>)
            : const BoxSpec(padding: 0),
        underline: json["underline"] is Map<String, dynamic>
            ? PartUnderline.fromJson(json["underline"] as Map<String, dynamic>)
            : null,
        animate: jsonBool(json["animate"], true),
      );
}

/// TextIconAlign is where an old icon sat along the edge it was on.
enum TextIconAlign {
  start("Start"),
  middle("Middle"),
  end("End");

  final String label;
  const TextIconAlign(this.label);

  static TextIconAlign fromName(String? name) =>
      values.firstWhere((a) => a.name == name, orElse: () => middle);
}
