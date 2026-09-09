import 'dart:ui';

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

  const TextFill({
    this.kind = TextFillKind.color,
    this.assetId = "",
    this.pattern = const ProceduralSpec(),
    this.zoom = 1,
    this.tile = false,
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
  }) =>
      TextFill(
        kind: kind ?? this.kind,
        assetId: assetId ?? this.assetId,
        pattern: pattern ?? this.pattern,
        zoom: zoom ?? this.zoom,
        tile: tile ?? this.tile,
      );

  Map<String, dynamic> toJson() => {
        if (kind != TextFillKind.color) "kind": kind.name,
        if (assetId.isNotEmpty) "assetId": assetId,
        if (kind == TextFillKind.pattern) "pattern": pattern.toJson(),
        if (zoom != 1) "zoom": zoom,
        if (tile) "tile": true,
      };

  factory TextFill.fromJson(Map<String, dynamic> json) => TextFill(
        kind: TextFillKind.fromName(json["kind"] as String?),
        assetId: jsonString(json["assetId"], ""),
        pattern: json["pattern"] is Map<String, dynamic>
            ? ProceduralSpec.fromJson(json["pattern"] as Map<String, dynamic>)
            : const ProceduralSpec(),
        zoom: jsonDouble(json["zoom"], 1).clamp(0.05, 20),
        tile: jsonBool(json["tile"], false),
      );
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

  /// fill is a picture or a pattern showing through the letters, or nothing
  /// at all -- which is the usual answer and means [color].
  final TextFill fill;

  /// outlineWidth strokes the glyph outlines. Zero means no outline, which is
  /// why the colour is allowed to be meaningless when it is zero.
  final double outlineWidth;
  final Color outlineColor;

  final double shadowBlur;
  final Color shadowColor;
  final Offset shadowOffset;

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
    this.fill = const TextFill(),
    this.outlineWidth = 0,
    this.outlineColor = const Color(0xFF000000),
    this.shadowBlur = 0,
    this.shadowColor = const Color(0x80000000),
    this.shadowOffset = Offset.zero,
  });

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
    TextFill? fill,
    double? outlineWidth,
    Color? outlineColor,
    double? shadowBlur,
    Color? shadowColor,
    Offset? shadowOffset,
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
        fill: fill ?? this.fill,
        outlineWidth: outlineWidth ?? this.outlineWidth,
        outlineColor: outlineColor ?? this.outlineColor,
        shadowBlur: shadowBlur ?? this.shadowBlur,
        shadowColor: shadowColor ?? this.shadowColor,
        shadowOffset: shadowOffset ?? this.shadowOffset,
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
        if (fill.toJson().isNotEmpty) "fill": fill.toJson(),
        if (outlineWidth > 0) "ow": outlineWidth,
        if (outlineWidth > 0) "oc": colorToJson(outlineColor),
        if (shadowBlur > 0) "sb": shadowBlur,
        if (shadowBlur > 0) "sc": colorToJson(shadowColor),
        if (shadowOffset != Offset.zero) "sx": shadowOffset.dx,
        if (shadowOffset != Offset.zero) "sy": shadowOffset.dy,
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
        fill: json["fill"] is Map<String, dynamic>
            ? TextFill.fromJson(json["fill"] as Map<String, dynamic>)
            : const TextFill(),
        outlineWidth: jsonDouble(json["ow"], 0),
        outlineColor: colorFromJson(json["oc"], const Color(0xFF000000)),
        shadowBlur: jsonDouble(json["sb"], 0),
        shadowColor: colorFromJson(json["sc"], const Color(0x80000000)),
        shadowOffset:
            Offset(jsonDouble(json["sx"], 0), jsonDouble(json["sy"], 0)),
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
          other.outlineWidth == outlineWidth &&
          other.outlineColor == outlineColor &&
          other.shadowBlur == shadowBlur &&
          other.shadowColor == shadowColor &&
          other.shadowOffset == shadowOffset;

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
        shadowOffset,
      );
}

/// BoxSpec is the frame around something: a fill, a border and a padding.
///
/// Shared for the same reason TextSpec is. A text element, a button, a table
/// and an image all want a rounded rectangle behind them with an outline on
/// it, and there is nothing about any of them that makes their version of it
/// different.
class BoxSpec {
  final Color fill;
  final double borderWidth;
  final Color borderColor;
  final double borderRadius;
  final double padding;

  const BoxSpec({
    this.fill = const Color(0x00000000),
    this.borderWidth = 0,
    this.borderColor = const Color(0xFFFFFFFF),
    this.borderRadius = 0,
    this.padding = 8,
  });

  BoxSpec copyWith({
    Color? fill,
    double? borderWidth,
    Color? borderColor,
    double? borderRadius,
    double? padding,
  }) =>
      BoxSpec(
        fill: fill ?? this.fill,
        borderWidth: borderWidth ?? this.borderWidth,
        borderColor: borderColor ?? this.borderColor,
        borderRadius: borderRadius ?? this.borderRadius,
        padding: padding ?? this.padding,
      );

  Map<String, dynamic> toJson() => {
        "fill": colorToJson(fill),
        if (borderWidth > 0) "bw": borderWidth,
        if (borderWidth > 0) "bc": colorToJson(borderColor),
        if (borderRadius > 0) "br": borderRadius,
        "pad": padding,
      };

  factory BoxSpec.fromJson(Map<String, dynamic> json) => BoxSpec(
        fill: colorFromJson(json["fill"], const Color(0x00000000)),
        borderWidth: jsonDouble(json["bw"], 0),
        borderColor: colorFromJson(json["bc"]),
        borderRadius: jsonDouble(json["br"], 0),
        padding: jsonDouble(json["pad"], 8),
      );
}
