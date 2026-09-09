import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

// text_parts.dart is "these words, not the others".
//
// Its own idea rather than a setting on any one feature, because it is the
// same question asked by several: colour these words, animate these letters,
// echo that one. Written once, the answer is the same wherever it is asked
// and a new feature gets it for nothing; written per feature, it is three
// range pickers that drift apart.
//
// A *list* of parts rather than one range, because one range cannot say
// "words 1 to 5 in red and 6 to 10 in blue" -- which is the first thing
// anybody wants after they have coloured one word.

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
/// The last three are drawn by hand rather than by the stroke: a straight
/// rule under a word reads as a hyperlink, and what somebody wants under the
/// word they are selling is the line they would have drawn themselves. Their
/// wobble comes from the line's own position rather than from a random
/// number, so a frame exported twice is the same frame twice.
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

  /// drawn is whether the style is one of the hand-made ones, which are
  /// stroked from a wobbling path instead of a straight one.
  bool get drawn =>
      this == hand || this == marker || this == sketch || this == wavy;

  static PartLineStyle fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => solid);
}

/// PartHighlight is a band behind some of the words.
///
/// Its own colour and its own padding for the reason a drawn mark has them:
/// a band in the colour of the words is a solid block, and one tight around
/// the letters reads as a mistake where one with a little air reads as a
/// highlighter. The four sides are kept separately so a band can be given
/// more room above and below than at the ends, which is what a highlighter
/// actually looks like.
class PartHighlight {
  final Color color;
  final double padLeft;
  final double padTop;
  final double padRight;
  final double padBottom;

  /// radius rounds the band's corners. A highlighter pen has no corners.
  final double radius;

  const PartHighlight({
    this.color = const Color(0x66FFD54F),
    this.padLeft = 4,
    this.padTop = 2,
    this.padRight = 4,
    this.padBottom = 2,
    this.radius = 0,
  });

  /// evenPad is the one number the four sides share, or null where they
  /// differ -- which is what the "all sides" field shows.
  double? get evenPad =>
      padLeft == padTop && padTop == padRight && padRight == padBottom
          ? padLeft
          : null;

  PartHighlight copyWith({
    Color? color,
    double? padLeft,
    double? padTop,
    double? padRight,
    double? padBottom,
    double? radius,
  }) =>
      PartHighlight(
        color: color ?? this.color,
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
        "l": padLeft,
        "t": padTop,
        "r": padRight,
        "b": padBottom,
        if (radius != 0) "radius": radius,
      };

  factory PartHighlight.fromJson(Map<String, dynamic> json) => PartHighlight(
        color: colorFromJson(json["color"], const Color(0x66FFD54F)),
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

  /// width is how thick it is, in design pixels.
  final double width;

  final PartLineStyle style;

  /// away is how far under the letters it sits. Nothing puts it where an
  /// ordinary underline goes; a few pixels drops it clear of the descenders.
  final double away;

  const PartUnderline({
    this.color,
    this.width = 3,
    this.style = PartLineStyle.solid,
    this.away = 2,
  });

  PartUnderline copyWith({
    Color? color,
    bool clearColor = false,
    double? width,
    PartLineStyle? style,
    double? away,
  }) =>
      PartUnderline(
        color: clearColor ? null : (color ?? this.color),
        width: width ?? this.width,
        style: style ?? this.style,
        away: away ?? this.away,
      );

  Map<String, dynamic> toJson() => {
        if (color != null) "color": colorToJson(color!),
        "width": width,
        if (style != PartLineStyle.solid) "style": style.name,
        "away": away,
      };

  factory PartUnderline.fromJson(Map<String, dynamic> json) => PartUnderline(
        color: json["color"] == null
            ? null
            : colorFromJson(json["color"], const Color(0xFFFFFFFF)),
        width: jsonDouble(json["width"], 3).clamp(0.1, 80),
        style: PartLineStyle.fromName(json["style"] as String?),
        away: jsonDouble(json["away"], 2),
      );
}

/// TextPartAnimation is how one part of the text arrives, and when.
///
/// Its own animation rather than the element's pointed at a part, which is
/// what this was. Pointing the arrival at some of the words meant the rest of
/// the sentence could not have an arrival of its own, and there was nowhere
/// to say *when*: the point of animating one word is that it lands after the
/// line it is in, not with it.
///
/// So a text element now plays up to three things in order -- the arrival,
/// each part's own animation at its own offset, and the exit -- out of one
/// pair of keyframes on the timeline. The offset is in frames because that is
/// what the timeline is counted in and what somebody nudging a landing by two
/// frames is thinking in; the length is in frames for the same reason, and
/// nothing means "as long as the arrival takes".
class TextPartAnimation {
  final TextAnimationPreset preset;

  /// offset is how many frames after the arrival starts this one does.
  /// Negative brings it forward, which is how a word lands *before* the line
  /// it belongs to.
  final int offset;

  /// length is how many frames it takes, or 0 for as long as the arrival.
  final int length;

  final double gap;
  final double scale;
  final TextEchoSpec echo;
  final TextDrawSpec draw;
  final ChartEase ease;

  /// marks is whether this part's own highlight and underline are drawn on
  /// rather than simply being there.
  ///
  /// Their own question, and their own offset, because the usual thing is a
  /// word that arrives and *then* gets underlined -- a mark that arrived with
  /// the word it marks is a mark nobody sees being drawn.
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

  /// asAnimation is this as the painter's own kind, so a part is animated by
  /// exactly the same code as a paragraph rather than by a second copy of it.
  TextAnimation get asAnimation => TextAnimation(
        preset: preset,
        gap: gap,
        scale: scale,
        echo: echo,
        draw: draw,
        ease: ease,
      );

  /// fromAnimation takes back whatever the settings changed, leaving this
  /// one's own timing alone.
  ///
  /// The pair to asAnimation, and the reason a part offers the same settings
  /// as the paragraph does: the panel edits one kind of animation, and the
  /// part keeps its offset and its length either side of that.
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
        preset: TextAnimationPreset.fromName(json["preset"] as String?),
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
        ease: ChartEase.fromName(json["ease"] as String?),
        marks: jsonBool(json["marks"], false),
        markOffset: jsonInt(json["markOffset"], 0),
        markLength: jsonInt(json["markLength"], 0).clamp(0, 100000),
      );
}

/// partsOutline is whether any of [parts] draws its own outline.
///
/// Asked before a paragraph is laid out a second time as a stroke: an
/// element with no outline of its own still needs one built when a part
/// inside it has asked for one.
bool partsOutline(List<TextPart> parts) {
  for (var part in parts) {
    if ((part.outlineWidth ?? 0) > 0) return true;
  }
  return false;
}

/// partsAnimate is whether any of [parts] arrives on its own account, or has
/// a mark that is drawn on rather than simply being there.
///
/// Asked before a still paragraph is drawn the quick way: a part with a
/// moment of its own means the paragraph has to go through the animator even
/// when the element's own arrival is over.
bool partsAnimate(List<TextPart> parts) {
  for (var part in parts) {
    if (part.animation.on || part.animation.marks) return true;
  }
  return false;
}

/// PartTiming is how far one part has got on this frame: its words, and the
/// mark drawn on them.
///
/// Two numbers rather than one because they are two arrivals -- the word
/// lands, and then the underline is drawn under it -- and a painter that was
/// handed one number could only ever have them happen together.
class PartTiming {
  final double words;
  final double mark;
  const PartTiming(this.words, this.mark);

  static const there = PartTiming(1, 1);
}

/// timingOf is where [part] has got to on [frame].
///
/// [from] is the frame the element's own arrival starts on and [span] how
/// many frames it takes -- everything a part does is measured from those, so
/// dragging the arrival's keyframes on the timeline carries the parts with
/// it rather than leaving them stranded at frame numbers of their own.
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

/// TextPart is a range of the words, and what is different about it.
///
/// Counted from one, because "the sixth word" is how somebody says it and
/// making them say "the fifth" is making them do arithmetic to talk to a
/// settings panel.
class TextPart {
  final TextUnit unit;

  /// from is the first word or letter, counting from one.
  final int from;

  /// to is the last, counting from one and included -- or zero for "to the
  /// end", which is what "words ten till the end" needs and what a range with
  /// a number in it cannot say when the text is edited afterwards.
  final int to;

  /// color is what this part is drawn in, or null to leave it alone.
  final Color? color;

  /// weight and italic are the other two things worth changing about a few
  /// words in a sentence. Null leaves them as the element's own.
  final int? weight;
  final bool? italic;

  /// outlineWidth and outlineColor draw these words in outline, or draw a
  /// heavier or a different-coloured one than the rest of the paragraph has.
  ///
  /// Null for both is "whatever the element says", which is what nearly every
  /// part wants. A width of zero is a real answer and not the same thing: it
  /// takes the outline *off* these words in a sentence that otherwise has
  /// one, which is how a single word is left plain inside an outlined
  /// headline.
  final double? outlineWidth;
  final Color? outlineColor;

  /// highlight is a band behind these words, and underline a line under
  /// them, or null for neither.
  ///
  /// Here rather than on the animation because they are a fact about the
  /// words -- this phrase is highlighted -- and not about an arrival. An
  /// animation that draws one is the same mark being *drawn*; this is the
  /// mark being there.
  final PartHighlight? highlight;
  final PartUnderline? underline;

  /// animation is how these words arrive, on their own account. See
  /// TextPartAnimation: none of it happens unless a preset is chosen, and
  /// then it happens at its own moment rather than with the rest of the line.
  final TextPartAnimation animation;

  const TextPart({
    this.unit = TextUnit.words,
    this.from = 1,
    this.to = 0,
    this.color,
    this.weight,
    this.italic,
    this.outlineWidth,
    this.outlineColor,
    this.highlight,
    this.underline,
    this.animation = const TextPartAnimation(),
  });

  bool get toTheEnd => to <= 0;

  /// says is this part in words, for the settings to show without the reader
  /// having to work it out from three numbers.
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
        if (outlineWidth != null) "outlineWidth": outlineWidth,
        if (outlineColor != null) "outlineColor": colorToJson(outlineColor!),
        if (highlight != null) "highlight": highlight!.toJson(),
        if (underline != null) "underline": underline!.toJson(),
        if (animation.toJson().isNotEmpty) "animation": animation.toJson(),
      };

  factory TextPart.fromJson(Map<String, dynamic> json) => TextPart(
        unit: TextUnit.fromName(json["unit"] as String?),
        from: jsonInt(json["from"], 1).clamp(1, 100000),
        to: jsonInt(json["to"], 0).clamp(0, 100000),
        color: json["color"] == null
            ? null
            : colorFromJson(json["color"], const Color(0xFFFFFFFF)),
        weight: json["weight"] is num ? (json["weight"] as num).toInt() : null,
        italic: json["italic"] is bool ? json["italic"] as bool : null,
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
/// Empty where the part names something that is not there -- word twelve of a
/// sentence with six in it -- rather than clamping to the last word: a part
/// that quietly moved to the end would be a part that appeared to work and
/// coloured the wrong thing.
(int, int)? rangeOf(String text, TextPart part) {
  if (text.isEmpty || part.from < 1) return null;

  if (part.unit == TextUnit.characters) {
    // Letters, not code units of whitespace: "the third letter" means the
    // third one somebody can see.
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
/// The last one wins where two overlap: the list is the reader's own order,
/// and the thing they added most recently is the thing they are working on.
TextPart? partAt(String text, List<TextPart> parts, int index) {
  TextPart? found;
  for (var part in parts) {
    var range = rangeOf(text, part);
    if (range == null) continue;
    if (index >= range.$1 && index < range.$2) found = part;
  }
  return found;
}

/// IconPlace is where an icon sits relative to the words.
enum IconPlace {
  start("Before the text"),
  end("After the text"),
  over("Above the text"),
  under("Below the text");

  final String label;
  const IconPlace(this.label);

  /// beside is whether the icon takes room from the side rather than from
  /// the top or the bottom, which is the one thing the layout needs to know.
  bool get beside => this == start || this == end;

  static IconPlace fromName(String? name) =>
      values.firstWhere((p) => p.name == name, orElse: () => start);
}

/// TextIcon is a picture set beside, above or below a text element's words.
///
/// Part of the text element rather than a picture element parked next to one,
/// because that is what it is *for*: a bullet, a logo, a mark that belongs to
/// the sentence and should move, resize and animate with it. Two elements
/// dragged into place beside each other come apart the first time either is
/// touched.
///
/// It reuses what a text element already has -- a box, an underline -- rather
/// than growing its own: an icon in a rounded box with a line under it is the
/// same rounded box and the same line, and writing them twice would be two
/// sets of settings that drift.
class TextIcon {
  final String assetId;
  final IconPlace place;

  /// size is how tall the icon is drawn, in design pixels.
  final double size;

  /// color tints it, or null to draw it in the colours it was drawn in.
  ///
  /// A tint rather than a repaint: the picture is cut to its own shape and
  /// filled, which is what makes a one-colour glyph take the headline's
  /// colour and is the only thing that can be done to an arbitrary drawing.
  final Color? color;

  /// gap is the room between the icon and the words.
  final double gap;

  /// align is where the icon sits along the edge it is on: the left, the
  /// middle or the right of an icon above the words; the top, the middle or
  /// the bottom of one beside them.
  final TextIconAlign align;

  /// outlineWidth draws the icon's silhouette behind it, in outlineColor --
  /// the sticker outline, which is the one outline an arbitrary drawing can
  /// be given without knowing anything about its shape.
  final double outlineWidth;
  final Color outlineColor;

  final BoxSpec box;

  /// underline is a line under the icon, the same kind a part of the text
  /// carries. Null for none.
  final PartUnderline? underline;

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
      };

  factory TextIcon.fromJson(Map<String, dynamic> json) => TextIcon(
        assetId: jsonString(json["assetId"], ""),
        place: IconPlace.fromName(json["place"] as String?),
        size: jsonDouble(json["size"], 64).clamp(1, 4000),
        color: json["color"] == null
            ? null
            : colorFromJson(json["color"], const Color(0xFFFFFFFF)),
        gap: jsonDouble(json["gap"], 12),
        align: TextIconAlign.fromName(json["align"] as String?),
        outlineWidth: jsonDouble(json["ow"], 0).clamp(0, 200),
        outlineColor: colorFromJson(json["oc"], const Color(0xFF000000)),
        box: json["box"] is Map<String, dynamic>
            ? BoxSpec.fromJson(json["box"] as Map<String, dynamic>)
            : const BoxSpec(padding: 0),
        underline: json["underline"] is Map<String, dynamic>
            ? PartUnderline.fromJson(json["underline"] as Map<String, dynamic>)
            : null,
      );
}

/// TextIconAlign is where an icon sits along the edge it is on.
enum TextIconAlign {
  start("Start"),
  middle("Middle"),
  end("End");

  final String label;
  const TextIconAlign(this.label);

  static TextIconAlign fromName(String? name) =>
      values.firstWhere((a) => a.name == name, orElse: () => middle);
}
