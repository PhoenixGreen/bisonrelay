import 'package:bruig/components/paint_spec.dart';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show EdgeInsets;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';

// text_spec.dart is how text looks, wherever it appears.
//
// Five things on a canvas draw text -- a text element, the label inside a
// shape, a button, a chart's title and axes, a table's cells -- and every one
// of them wants the same list of decisions. Written five times, the fifth
// would quietly be missing letter spacing, and the settings bar would need
// five nearly-identical panels. So the decisions are one object that all five
// hold, and one panel edits it.

/// TextCase is the transform applied on the way to the screen.
///
/// Applied at paint time rather than to the stored string, so turning it off
/// gives back what was typed. Somebody who set a title to upper case, typed
/// it, and then changed their mind should not be left holding SHOUTING.
enum TextCase {
  none("As typed"),
  upper("UPPER CASE"),
  lower("lower case"),
  title("Title Case");

  final String label;
  const TextCase(this.label);

  static TextCase fromName(String? name) =>
      values.firstWhere((c) => c.name == name, orElse: () => TextCase.none);

  String apply(String s) {
    switch (this) {
      case TextCase.none:
        return s;
      case TextCase.upper:
        return s.toUpperCase();
      case TextCase.lower:
        return s.toLowerCase();
      case TextCase.title:
        return s.split(" ").map((w) {
          if (w.isEmpty) return w;
          return w[0].toUpperCase() + w.substring(1).toLowerCase();
        }).join(" ");
    }
  }
}

/// TextAlignSpec is horizontal alignment, kept as our own enum rather than
/// Flutter's TextAlign so that a saved document does not depend on the index
/// of a value in somebody else's library.
enum TextAlignSpec {
  left("Left", TextAlign.left),
  center("Centre", TextAlign.center),
  right("Right", TextAlign.right),
  justify("Justify", TextAlign.justify);

  final String label;
  final TextAlign flutter;
  const TextAlignSpec(this.label, this.flutter);

  static TextAlignSpec fromName(String? name) => values.firstWhere(
        (a) => a.name == name,
        orElse: () => TextAlignSpec.left,
      );
}

/// VerticalAlignSpec is where the text sits in a box taller than it is.
enum VerticalAlignSpec {
  top("Top"),
  middle("Middle"),
  bottom("Bottom");

  final String label;
  const VerticalAlignSpec(this.label);

  static VerticalAlignSpec fromName(String? name) => values.firstWhere(
        (a) => a.name == name,
        orElse: () => VerticalAlignSpec.middle,
      );
}

/// canvasFonts are the faces offered in the font dropdown.
///
/// Only families the app already bundles or that every desktop has, because a
/// canvas is exported to a PNG on this machine and shared as a picture -- a
/// font that resolves to something else here silently changes the design, and
/// nobody would find out until they looked at what they had sent.
const List<String> canvasFonts = [
  "Inter",
  "Roboto",
  "RobotoMono",
  "Arial",
  "Helvetica",
  "Georgia",
  "Times New Roman",
  "Courier New",
  "Verdana",
  "Impact",
];

/// TextSpec is one set of type decisions.
/// TextFillKind is what the letters are painted with.
enum TextFillKind {
  color("Colour"),
  image("Picture"),
  pattern("Pattern");

  final String label;
  const TextFillKind(this.label);

  static TextFillKind fromName(String? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => color);
}

/// TextFill is a picture or a pattern showing through the letters.
///
/// The letters are the window, not the paint: whatever is chosen is drawn
/// across the whole word and then cut to the shape of the type. That is why
/// this is one setting on the type rather than a property of each glyph --
/// a flame that restarted inside every letter would be a row of little
/// flames, and what makes the effect work is that it does not.
///
/// The pattern is an ordinary [ProceduralSpec], the same recipe a generated
/// background is, so every style, colour and slider that exists for one works
/// here as well and a new style arrives in both places at once.
class TextFill {
  final TextFillKind kind;

  /// assetId is the picture, for [TextFillKind.image]. See CanvasAssets.
  final String assetId;

  final ProceduralSpec pattern;

  /// zoom sizes what is drawn against the words: 1 fits it across them, 2
  /// shows a quarter of it twice as large. What "it" is depends on the kind --
  /// the picture, or the pattern's own frame.
  final double zoom;

  /// tile repeats a picture instead of covering the words with one copy.
  final bool tile;

  /// locked carries what shows through the words along with them while they
  /// are arriving, instead of leaving it pinned to the box.
  ///
  /// The fill is cut to the letters at the moment they are drawn, so words
  /// sliding or growing through a fill that stays put sweep across it: the
  /// flame or the photograph inside the letters changes all the way through
  /// the animation, which is not what somebody who chose a picture for the
  /// word wanted. Locked, the picture travels with the words -- the same bit
  /// of it shows through the same letter from the first frame to the last.
  ///
  /// It applies to a whole-paragraph arrival, which is the one that moves the
  /// words as a block. Letter by letter there is no single movement to lock
  /// to, and the fill stays where it is.
  final bool locked;

  const TextFill({
    this.kind = TextFillKind.color,
    this.assetId = "",
    this.pattern = const ProceduralSpec(),
    this.zoom = 1,
    this.tile = false,
    this.locked = false,
  });

  /// on is whether anything but the plain colour is being used -- and, for a
  /// picture, whether one has actually been chosen.
  bool get on =>
      kind == TextFillKind.pattern ||
      (kind == TextFillKind.image && assetId.isNotEmpty);

  TextFill copyWith({
    TextFillKind? kind,
    String? assetId,
    ProceduralSpec? pattern,
    double? zoom,
    bool? tile,
    bool? locked,
  }) =>
      TextFill(
        kind: kind ?? this.kind,
        assetId: assetId ?? this.assetId,
        pattern: pattern ?? this.pattern,
        zoom: zoom ?? this.zoom,
        tile: tile ?? this.tile,
        locked: locked ?? this.locked,
      );

  Map<String, dynamic> toJson() => {
        if (kind != TextFillKind.color) "kind": kind.name,
        if (assetId.isNotEmpty) "assetId": assetId,
        if (kind == TextFillKind.pattern) "pattern": pattern.toJson(),
        if (zoom != 1) "zoom": zoom,
        if (tile) "tile": true,
        if (locked) "locked": true,
      };

  factory TextFill.fromJson(Map<String, dynamic> json) => TextFill(
        kind: TextFillKind.fromName(json["kind"] as String?),
        assetId: jsonString(json["assetId"], ""),
        pattern: json["pattern"] is Map<String, dynamic>
            ? ProceduralSpec.fromJson(json["pattern"] as Map<String, dynamic>)
            : const ProceduralSpec(),
        zoom: jsonDouble(json["zoom"], 1).clamp(0.05, 20),
        tile: jsonBool(json["tile"], false),
        locked: jsonBool(json["locked"], false),
      );
}

/// _angleOf is the light's direction that throws a shadow at [dx], [dy] --
/// the inverse of TextSpec.shadowOffset, for reading an older document.
double _angleOf(double dx, double dy) {
  if (dx == 0 && dy == 0) return 315;
  var degrees = math.atan2(-dx, dy) * 180 / math.pi;
  return degrees < 0 ? degrees + 360 : degrees;
}

class TextSpec {
  final String fontFamily;
  final double fontSize;

  /// weight is 100..900 in hundreds, matching CSS and FontWeight both.
  final int weight;
  final bool italic;
  final bool underline;

  /// letterSpacing is in design units, and may be negative.
  final double letterSpacing;

  /// lineHeight is a multiple of the font size, not an absolute leading, so
  /// changing the size keeps the paragraph's proportions.
  final double lineHeight;

  final TextAlignSpec align;
  final VerticalAlignSpec verticalAlign;
  final TextCase textCase;

  final Color color;

  /// fade is the second colour the words run to, or null for one flat colour.
  ///
  /// Chosen in the picker beside [color] -- see GradientSpec. Run across the
  /// box the text is drawn in rather than across the letters' own bounds: the
  /// letters are not measured until they are laid out, and a gradient that
  /// started again on every line is not what anybody means by a fade across a
  /// heading.
  ///
  /// Ignored where the letters are outlined rather than filled, and where a
  /// picture or a pattern is showing through them -- both of those already
  /// decide what the letters are painted with. See textStyleOf.
  final GradientSpec? fade;

  /// fill is a picture or a pattern showing through the letters, or nothing
  /// at all -- which is the usual answer and means [color].
  final TextFill fill;

  /// outlineWidth strokes the glyph outlines. Zero means no outline, which is
  /// why the colour is allowed to be meaningless when it is zero.
  final double outlineWidth;
  final Color outlineColor;

  final double shadowBlur;
  final Color shadowColor;

  /// shadowAngle is the direction the light comes *from*, in degrees, the way
  /// a compass is read: 0 is straight up, 90 to the right, 180 down. The
  /// shadow falls the opposite way, which is the thing being set -- somebody
  /// placing a shadow is placing a light.
  ///
  /// Kept as an angle and a distance rather than as an offset because that is
  /// how it is thought about: a scene has one light, and every element in it
  /// should agree about where it is. Two numbers that can be copied between
  /// elements do that; a dx and a dy have to be worked out again for every
  /// distance.
  final double shadowAngle;

  /// shadowDistance is how far the shadow is thrown, in design units. Zero
  /// leaves it directly underneath, which is a glow in the shadow's colour.
  final double shadowDistance;

  /// glowBlur is a soft light all round the letters, in [glowColor]. Zero is
  /// off.
  ///
  /// A shadow with no distance is nearly the same drawing, but not the same
  /// setting: a glow is light and a shadow is dark, and wanting both at once
  /// -- lit type that still sits above its background -- is ordinary. Kept
  /// apart so neither has to be spent to have the other.
  final double glowBlur;
  final Color glowColor;

  const TextSpec({
    this.fontFamily = "Inter",
    this.fontSize = 48,
    this.weight = 600,
    this.italic = false,
    this.underline = false,
    this.letterSpacing = 0,
    this.lineHeight = 1.2,
    this.align = TextAlignSpec.center,
    this.verticalAlign = VerticalAlignSpec.middle,
    this.textCase = TextCase.none,
    this.color = const Color(0xFFFFFFFF),
    this.fade,
    this.fill = const TextFill(),
    this.outlineWidth = 0,
    this.outlineColor = const Color(0xFF000000),
    this.shadowBlur = 0,
    this.shadowColor = const Color(0x80000000),
    this.shadowAngle = 315,
    this.shadowDistance = 0,
    this.glowBlur = 0,
    this.glowColor = const Color(0xFFFFFFFF),
  });

  /// shadowOffset is where the shadow lands: [shadowDistance] away from the
  /// letters, in the direction opposite the light.
  ///
  /// Screen coordinates have y going down, and the angle is read off a
  /// compass -- so up is -y, and the shadow is thrown the other way.
  Offset get shadowOffset {
    if (shadowDistance == 0) return Offset.zero;
    var radians = shadowAngle * math.pi / 180;
    return Offset(-math.sin(radians) * shadowDistance,
        math.cos(radians) * shadowDistance);
  }

  /// softPasses is whether anything is drawn behind the letters: a shadow, a
  /// glow, or both. See softFor, which lays them out.
  bool get softPasses => shadowBlur > 0 || glowBlur > 0 || shadowDistance > 0;

  TextSpec copyWith({
    String? fontFamily,
    double? fontSize,
    int? weight,
    bool? italic,
    bool? underline,
    double? letterSpacing,
    double? lineHeight,
    TextAlignSpec? align,
    VerticalAlignSpec? verticalAlign,
    TextCase? textCase,
    Color? color,
    GradientSpec? fade,
    bool flatText = false,
    TextFill? fill,
    double? outlineWidth,
    Color? outlineColor,
    double? shadowBlur,
    Color? shadowColor,
    double? shadowAngle,
    double? shadowDistance,
    double? glowBlur,
    Color? glowColor,
  }) =>
      TextSpec(
        fontFamily: fontFamily ?? this.fontFamily,
        fontSize: fontSize ?? this.fontSize,
        weight: weight ?? this.weight,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        letterSpacing: letterSpacing ?? this.letterSpacing,
        lineHeight: lineHeight ?? this.lineHeight,
        align: align ?? this.align,
        verticalAlign: verticalAlign ?? this.verticalAlign,
        textCase: textCase ?? this.textCase,
        color: color ?? this.color,
        fade: flatText ? null : (fade ?? this.fade),
        fill: fill ?? this.fill,
        outlineWidth: outlineWidth ?? this.outlineWidth,
        outlineColor: outlineColor ?? this.outlineColor,
        shadowBlur: shadowBlur ?? this.shadowBlur,
        shadowColor: shadowColor ?? this.shadowColor,
        shadowAngle: shadowAngle ?? this.shadowAngle,
        shadowDistance: shadowDistance ?? this.shadowDistance,
        glowBlur: glowBlur ?? this.glowBlur,
        glowColor: glowColor ?? this.glowColor,
      );

  /// fontWeight is [weight] as Flutter says it. Clamped and rounded to the
  /// nearest hundred, because FontWeight.values is indexed and a weight of
  /// 137 arriving from a saved file would otherwise be an index out of range.
  FontWeight get fontWeight =>
      FontWeight.values[((weight ~/ 100) - 1).clamp(0, 8)];

  Map<String, dynamic> toJson() => {
        "font": fontFamily,
        "size": fontSize,
        "weight": weight,
        if (italic) "italic": true,
        if (underline) "underline": true,
        if (letterSpacing != 0) "ls": letterSpacing,
        "lh": lineHeight,
        "align": align.name,
        "valign": verticalAlign.name,
        if (textCase != TextCase.none) "case": textCase.name,
        "color": colorToJson(color),
        if (fade != null) "fade": fade!.toJson(),
        if (fill.toJson().isNotEmpty) "fill": fill.toJson(),
        if (outlineWidth > 0) "ow": outlineWidth,
        if (outlineWidth > 0) "oc": colorToJson(outlineColor),
        if (shadowBlur > 0 || shadowDistance > 0) "sb": shadowBlur,
        if (shadowBlur > 0 || shadowDistance > 0)
          "sc": colorToJson(shadowColor),
        if (shadowDistance > 0) "sa": shadowAngle,
        if (shadowDistance > 0) "sd": shadowDistance,
        if (glowBlur > 0) "gb": glowBlur,
        if (glowBlur > 0) "gc": colorToJson(glowColor),
      };

  factory TextSpec.fromJson(Map<String, dynamic> json) => TextSpec(
        fontFamily: jsonString(json["font"], "Inter"),
        fontSize: jsonDouble(json["size"], 48),
        weight: jsonInt(json["weight"], 600),
        italic: jsonBool(json["italic"], false),
        underline: jsonBool(json["underline"], false),
        letterSpacing: jsonDouble(json["ls"], 0),
        lineHeight: jsonDouble(json["lh"], 1.2),
        align: TextAlignSpec.fromName(json["align"] as String?),
        verticalAlign: VerticalAlignSpec.fromName(json["valign"] as String?),
        textCase: TextCase.fromName(json["case"] as String?),
        color: colorFromJson(json["color"]),
        fade: json["fade"] is Map
            ? GradientSpec.fromJson(
                (json["fade"] as Map).cast<String, dynamic>())
            : null,
        fill: json["fill"] is Map<String, dynamic>
            ? TextFill.fromJson(json["fill"] as Map<String, dynamic>)
            : const TextFill(),
        outlineWidth: jsonDouble(json["ow"], 0),
        outlineColor: colorFromJson(json["oc"], const Color(0xFF000000)),
        shadowBlur: jsonDouble(json["sb"], 0),
        shadowColor: colorFromJson(json["sc"], const Color(0x80000000)),
        // An older document wrote the shadow as a dx and a dy. Read back as
        // the angle and the distance they describe, so a scene saved before
        // the light had a direction opens with its shadows where they were.
        shadowAngle: json["sa"] != null
            ? jsonDouble(json["sa"], 315)
            : _angleOf(jsonDouble(json["sx"], 0), jsonDouble(json["sy"], 0)),
        shadowDistance: json["sd"] != null
            ? jsonDouble(json["sd"], 0)
            : Offset(jsonDouble(json["sx"], 0), jsonDouble(json["sy"], 0))
                .distance,
        glowBlur: jsonDouble(json["gb"], 0),
        glowColor: colorFromJson(json["gc"], const Color(0xFFFFFFFF)),
      );

  /// Two specs are the same when every decision in them is.
  ///
  /// Worth having on a value object anyway, and needed by one thing in
  /// particular: laying out a line of text is the most expensive thing the
  /// renderer does, and it cannot be skipped for a line already laid out
  /// unless "the same type" is a question that can be asked. See
  /// paint_util's layout cache.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextSpec &&
          other.fontFamily == fontFamily &&
          other.fontSize == fontSize &&
          other.weight == weight &&
          other.italic == italic &&
          other.underline == underline &&
          other.letterSpacing == letterSpacing &&
          other.lineHeight == lineHeight &&
          other.align == align &&
          other.verticalAlign == verticalAlign &&
          other.textCase == textCase &&
          other.color == color &&
          other.fade == fade &&
          other.outlineWidth == outlineWidth &&
          other.outlineColor == outlineColor &&
          other.shadowBlur == shadowBlur &&
          other.shadowColor == shadowColor &&
          other.shadowAngle == shadowAngle &&
          other.shadowDistance == shadowDistance &&
          other.glowBlur == glowBlur &&
          other.glowColor == glowColor;

  @override
  int get hashCode => Object.hash(
        fontFamily,
        fontSize,
        weight,
        italic,
        underline,
        letterSpacing,
        lineHeight,
        align,
        verticalAlign,
        textCase,
        color,
        outlineWidth,
        outlineColor,
        shadowBlur,
        shadowColor,
        shadowAngle,
        shadowDistance,
        glowBlur,
        glowColor,
      );
}

/// BoxSpec is the frame around something: a fill, a border and a padding.
///
/// Shared for the same reason TextSpec is. A text element, a button, a table
/// and an image all want a rounded rectangle behind them with an outline on
/// it, and there is nothing about any of them that makes their version of it
/// different.
/// Corners is four corner radii with one number answering for whichever of
/// them has not been given its own.
///
/// Its own type because two things have corners -- the frame round an element
/// and a rectangle shape -- and they had better round them the same way. One
/// number and four overrides rather than four numbers: a box is almost always
/// even, that is how somebody wants to say it, and every document ever saved
/// has the one number in it.
class Corners {
  /// all is every corner that has not been given its own.
  final double all;

  /// tl, tr, br and bl are the corners that have, or null.
  final double? tl;
  final double? tr;
  final double? br;
  final double? bl;

  const Corners({this.all = 0, this.tl, this.tr, this.br, this.bl});

  double get topLeft => tl ?? all;
  double get topRight => tr ?? all;
  double get bottomRight => br ?? all;
  double get bottomLeft => bl ?? all;

  bool get isRounded =>
      topLeft > 0 || topRight > 0 || bottomRight > 0 || bottomLeft > 0;

  /// even is the one number all four share, or null where they differ --
  /// which is what the "all corners" field shows.
  double? get even => topLeft == topRight &&
          topRight == bottomRight &&
          bottomRight == bottomLeft
      ? topLeft
      : null;

  /// withEven sets all four at once, forgetting whatever they had.
  Corners withEven(double radius) => Corners(all: radius);

  Corners copyWith(
          {double? all, double? tl, double? tr, double? br, double? bl}) =>
      Corners(
        all: all ?? this.all,
        tl: tl ?? this.tl,
        tr: tr ?? this.tr,
        br: br ?? this.br,
        bl: bl ?? this.bl,
      );

  /// rrect is [rect] with these corners, inset by [by] all round -- which is
  /// how a border draws itself inside a fill without the two drifting out of
  /// step.
  RRect rrect(Rect rect, {double by = 0}) => RRect.fromRectAndCorners(
        by == 0 ? rect : rect.deflate(by),
        topLeft: Radius.circular(math.max(0, topLeft - by)),
        topRight: Radius.circular(math.max(0, topRight - by)),
        bottomRight: Radius.circular(math.max(0, bottomRight - by)),
        bottomLeft: Radius.circular(math.max(0, bottomLeft - by)),
      );

  /// inside is [inner] -- a rectangle some padding has already been taken off
  /// -- with corners that stay concentric with these.
  ///
  /// Each corner is pulled in by the wider of the two sides that meet there.
  /// With even padding that is the plain arithmetic; with uneven padding
  /// there is no single right answer, and the wider of the two is the one
  /// that keeps the curve inside the room it has.
  RRect inside(Rect inner, Room room) => RRect.fromRectAndCorners(
        inner,
        topLeft: Radius.circular(
            math.max(0, topLeft - math.max(room.left, room.top))),
        topRight: Radius.circular(
            math.max(0, topRight - math.max(room.right, room.top))),
        bottomRight: Radius.circular(
            math.max(0, bottomRight - math.max(room.right, room.bottom))),
        bottomLeft: Radius.circular(
            math.max(0, bottomLeft - math.max(room.left, room.bottom))),
      );

  Map<String, dynamic> toJson() => {
        if (all != 0) "r": all,
        if (tl != null) "tl": tl,
        if (tr != null) "tr": tr,
        if (br != null) "br": br,
        if (bl != null) "bl": bl,
      };

  factory Corners.fromJson(Map<String, dynamic> json) => Corners(
        all: jsonDouble(json["r"], 0),
        tl: json["tl"] == null ? null : jsonDouble(json["tl"], 0),
        tr: json["tr"] == null ? null : jsonDouble(json["tr"], 0),
        br: json["br"] == null ? null : jsonDouble(json["br"], 0),
        bl: json["bl"] == null ? null : jsonDouble(json["bl"], 0),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Corners &&
          other.topLeft == topLeft &&
          other.topRight == topRight &&
          other.bottomRight == bottomRight &&
          other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);
}

/// Room is the space kept on the four sides, with one number answering for
/// whichever side has not been given its own. See Corners, which is the same
/// idea for the corners.
class Room {
  final double all;
  final double? l;
  final double? t;
  final double? r;
  final double? b;

  const Room({this.all = 0, this.l, this.t, this.r, this.b});

  double get left => l ?? all;
  double get top => t ?? all;
  double get right => r ?? all;
  double get bottom => b ?? all;

  EdgeInsets get insets => EdgeInsets.fromLTRB(left, top, right, bottom);

  /// inner is [rect] with this room taken off it.
  Rect inner(Rect rect) => insets.deflateRect(rect);

  double? get even =>
      left == top && top == right && right == bottom ? left : null;

  Room withEven(double pad) => Room(all: pad);

  Room copyWith({double? all, double? l, double? t, double? r, double? b}) =>
      Room(
        all: all ?? this.all,
        l: l ?? this.l,
        t: t ?? this.t,
        r: r ?? this.r,
        b: b ?? this.b,
      );

  Map<String, dynamic> toJson() => {
        "all": all,
        if (l != null) "l": l,
        if (t != null) "t": t,
        if (r != null) "r": r,
        if (b != null) "b": b,
      };

  factory Room.fromJson(Map<String, dynamic> json) => Room(
        all: jsonDouble(json["all"], 0),
        l: json["l"] == null ? null : jsonDouble(json["l"], 0),
        t: json["t"] == null ? null : jsonDouble(json["t"], 0),
        r: json["r"] == null ? null : jsonDouble(json["r"], 0),
        b: json["b"] == null ? null : jsonDouble(json["b"], 0),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Room &&
          other.left == left &&
          other.top == top &&
          other.right == right &&
          other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

class BoxSpec {
  /// fill is what is painted behind whatever the box holds: the background.
  final Color fill;
  final double borderWidth;
  final Color borderColor;

  /// fillFade and borderFade are the second colours, where the fill or the
  /// border fades to one. Null for the flat ones, which is most of them.
  ///
  /// Chosen in the picker beside the colour itself -- see GradientSpec -- so
  /// there is no on/off flag and no row of gradient settings anywhere near
  /// the swatch.
  final GradientSpec? fillFade;
  final GradientSpec? borderFade;

  /// borderRadius is every corner that has not been given its own, and
  /// [padding] is every side that has not been given its own; padL..radBL are
  /// the ones that have.
  ///
  /// Stored flat rather than as the [Corners] and [Room] they describe,
  /// because a const constructor cannot build an object out of its own
  /// parameters -- and every BoxSpec in the codebase is written as a const.
  /// The *behaviour* is not duplicated: [corners] and [pad] hand back the two
  /// of them and everything below is asked of those, so a rectangle shape and
  /// a box round a picture round their corners by the same code.
  /// bwL, bwT, bwR and bwB are one side's own border, or null to take
  /// [borderWidth] -- the same shape as the padding above and for the same
  /// reason: a rule under a heading, a bar down the left of a quote, a box
  /// open on one side. All four even is what almost every box wants and is
  /// the one field; the rest are there for the boxes that are not boxes.
  final double? bwL;
  final double? bwT;
  final double? bwR;
  final double? bwB;

  final double borderRadius;
  final double padding;
  final double? padL;
  final double? padT;
  final double? padR;
  final double? padB;
  final double? radTL;
  final double? radTR;
  final double? radBR;
  final double? radBL;

  const BoxSpec({
    this.fill = const Color(0x00000000),
    this.borderWidth = 0,
    this.bwL,
    this.bwT,
    this.bwR,
    this.bwB,
    this.borderColor = const Color(0xFFFFFFFF),
    this.fillFade,
    this.borderFade,
    this.borderRadius = 0,
    this.padding = 8,
    this.padL,
    this.padT,
    this.padR,
    this.padB,
    this.radTL,
    this.radTR,
    this.radBR,
    this.radBL,
  });

  Corners get corners =>
      Corners(all: borderRadius, tl: radTL, tr: radTR, br: radBR, bl: radBL);
  Room get pad => Room(all: padding, l: padL, t: padT, r: padR, b: padB);

  /// borders is the four border widths, the same way [pad] is the four
  /// paddings.
  Room get borders => Room(all: borderWidth, l: bwL, t: bwT, r: bwR, b: bwB);

  /// evenBorder is the one number the four sides share, or null where they
  /// differ -- which is what the "all sides" field shows, and what decides
  /// whether the border can be drawn as one rounded rectangle.
  double? get evenBorder => borders.even;

  /// hasBorder is whether any side is drawn at all.
  bool get hasBorder =>
      borderColor.a > 0 &&
      (borders.left > 0 ||
          borders.top > 0 ||
          borders.right > 0 ||
          borders.bottom > 0);

  double get padLeft => pad.left;
  double get padTop => pad.top;
  double get padRight => pad.right;
  double get padBottom => pad.bottom;

  double get topLeft => corners.topLeft;
  double get topRight => corners.topRight;
  double get bottomRight => corners.bottomRight;
  double get bottomLeft => corners.bottomLeft;

  /// insets is the room the box keeps for itself on every side.
  EdgeInsets get insets => pad.insets;

  /// inner is [rect] with the padding taken off it.
  Rect inner(Rect rect) => pad.inner(rect);

  /// evenPad is the one number the four sides share, or null where they
  /// differ -- which is what the "all sides" field shows.
  double? get evenPad => pad.even;

  /// evenRadius is the same question for the corners.
  double? get evenRadius => corners.even;

  bool get isRounded => corners.isRounded;

  /// rounded is [rect] with this box's corners, inset by [by] all round.
  RRect rounded(Rect rect, {double by = 0}) => corners.rrect(rect, by: by);

  /// insetRounded is a rectangle the padding has already been taken off, with
  /// corners that stay concentric with the box's own.
  RRect insetRounded(Rect within) => corners.inside(within, pad);

  /// withCorners and withRoom replace the whole of one of them, overrides
  /// and all.
  ///
  /// Not copyWith: that fills a null with what was there before, which is
  /// right for "change this one field" and wrong here -- setting all four
  /// corners to one number means forgetting the three that had their own, and
  /// through copyWith they would have survived it.
  BoxSpec withCorners(Corners corners) => BoxSpec(
      fill: fill,
      borderWidth: borderWidth,
      bwL: bwL,
      bwT: bwT,
      bwR: bwR,
      bwB: bwB,
      borderColor: borderColor,
      fillFade: fillFade,
      borderFade: borderFade,
      borderRadius: corners.all,
      radTL: corners.tl,
      radTR: corners.tr,
      radBR: corners.br,
      radBL: corners.bl,
      padding: padding,
      padL: padL,
      padT: padT,
      padR: padR,
      padB: padB);

  BoxSpec withRoom(Room room) => BoxSpec(
      fill: fill,
      borderWidth: borderWidth,
      bwL: bwL,
      bwT: bwT,
      bwR: bwR,
      bwB: bwB,
      borderColor: borderColor,
      fillFade: fillFade,
      borderFade: borderFade,
      borderRadius: borderRadius,
      radTL: radTL,
      radTR: radTR,
      radBR: radBR,
      radBL: radBL,
      padding: room.all,
      padL: room.l,
      padT: room.t,
      padR: room.r,
      padB: room.b);

  /// withBorders replaces all four border widths, overrides and all -- see
  /// [withRoom], which is the same thing for the padding and says why it is
  /// not a copyWith.
  BoxSpec withBorders(Room room) => BoxSpec(
      fill: fill,
      borderWidth: room.all,
      bwL: room.l,
      bwT: room.t,
      bwR: room.r,
      bwB: room.b,
      borderColor: borderColor,
      fillFade: fillFade,
      borderFade: borderFade,
      borderRadius: borderRadius,
      radTL: radTL,
      radTR: radTR,
      radBR: radBR,
      radBL: radBL,
      padding: padding,
      padL: padL,
      padT: padT,
      padR: padR,
      padB: padB);

  /// withEvenPad sets all four sides at once, forgetting whatever they had.
  BoxSpec withEvenPad(double padding) => withRoom(pad.withEven(padding));

  /// withEvenRadius does the same for the corners.
  BoxSpec withEvenRadius(double radius) =>
      withCorners(corners.withEven(radius));

  BoxSpec copyWith({
    Color? fill,
    double? borderWidth,
    double? bwL,
    double? bwT,
    double? bwR,
    double? bwB,
    Color? borderColor,
    GradientSpec? fillFade,
    GradientSpec? borderFade,
    bool flatFill = false,
    bool flatBorder = false,
    double? borderRadius,
    double? padding,
    double? padL,
    double? padT,
    double? padR,
    double? padB,
    double? radTL,
    double? radTR,
    double? radBR,
    double? radBL,
  }) =>
      BoxSpec(
        fill: fill ?? this.fill,
        borderWidth: borderWidth ?? this.borderWidth,
        bwL: bwL ?? this.bwL,
        bwT: bwT ?? this.bwT,
        bwR: bwR ?? this.bwR,
        bwB: bwB ?? this.bwB,
        borderColor: borderColor ?? this.borderColor,
        fillFade: flatFill ? null : (fillFade ?? this.fillFade),
        borderFade: flatBorder ? null : (borderFade ?? this.borderFade),
        borderRadius: borderRadius ?? this.borderRadius,
        padding: padding ?? this.padding,
        padL: padL ?? this.padL,
        padT: padT ?? this.padT,
        padR: padR ?? this.padR,
        padB: padB ?? this.padB,
        radTL: radTL ?? this.radTL,
        radTR: radTR ?? this.radTR,
        radBR: radBR ?? this.radBR,
        radBL: radBL ?? this.radBL,
      );

  Map<String, dynamic> toJson() => {
        "fill": colorToJson(fill),
        if (fillFade != null) "fillFade": fillFade!.toJson(),
        if (borderFade != null) "borderFade": borderFade!.toJson(),
        if (borderWidth > 0) "bw": borderWidth,
        if (hasBorder) "bc": colorToJson(borderColor),
        // Only the sides somebody has actually singled out, like the paddings
        // and the corners below.
        if (bwL != null) "bwL": bwL,
        if (bwT != null) "bwT": bwT,
        if (bwR != null) "bwR": bwR,
        if (bwB != null) "bwB": bwB,
        if (borderRadius > 0) "br": borderRadius,
        "pad": padding,
        // Only the sides and corners somebody has actually singled out, so a
        // box that is simply even saves exactly what it always saved.
        if (padL != null) "padL": padL,
        if (padT != null) "padT": padT,
        if (padR != null) "padR": padR,
        if (padB != null) "padB": padB,
        if (radTL != null) "rTL": radTL,
        if (radTR != null) "rTR": radTR,
        if (radBR != null) "rBR": radBR,
        if (radBL != null) "rBL": radBL,
      };

  factory BoxSpec.fromJson(Map<String, dynamic> json) => BoxSpec(
        fill: colorFromJson(json["fill"], const Color(0x00000000)),
        fillFade: json["fillFade"] is Map
            ? GradientSpec.fromJson(
                (json["fillFade"] as Map).cast<String, dynamic>())
            : null,
        borderFade: json["borderFade"] is Map
            ? GradientSpec.fromJson(
                (json["borderFade"] as Map).cast<String, dynamic>())
            : null,
        borderWidth: jsonDouble(json["bw"], 0),
        bwL: json["bwL"] == null ? null : jsonDouble(json["bwL"], 0),
        bwT: json["bwT"] == null ? null : jsonDouble(json["bwT"], 0),
        bwR: json["bwR"] == null ? null : jsonDouble(json["bwR"], 0),
        bwB: json["bwB"] == null ? null : jsonDouble(json["bwB"], 0),
        borderColor: colorFromJson(json["bc"]),
        borderRadius: jsonDouble(json["br"], 0),
        padding: jsonDouble(json["pad"], 8),
        padL: json["padL"] == null ? null : jsonDouble(json["padL"], 0),
        padT: json["padT"] == null ? null : jsonDouble(json["padT"], 0),
        padR: json["padR"] == null ? null : jsonDouble(json["padR"], 0),
        padB: json["padB"] == null ? null : jsonDouble(json["padB"], 0),
        radTL: json["rTL"] == null ? null : jsonDouble(json["rTL"], 0),
        radTR: json["rTR"] == null ? null : jsonDouble(json["rTR"], 0),
        radBR: json["rBR"] == null ? null : jsonDouble(json["rBR"], 0),
        radBL: json["rBL"] == null ? null : jsonDouble(json["rBL"], 0),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoxSpec &&
          other.fill == fill &&
          other.fillFade == fillFade &&
          other.borderFade == borderFade &&
          other.borderWidth == borderWidth &&
          other.bwL == bwL &&
          other.bwT == bwT &&
          other.bwR == bwR &&
          other.bwB == bwB &&
          other.borderColor == borderColor &&
          other.corners == corners &&
          other.pad == pad;

  @override
  int get hashCode => Object.hash(fill, fillFade, borderFade, borderWidth,
      borderColor, corners, pad, borders);
}
