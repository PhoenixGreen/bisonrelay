import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/components/paint_spec.dart';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show EdgeInsets;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';

// text_spec.dart is how text looks, wherever it appears: text elements, shape
// labels, buttons, chart titles and axes, table cells all hold one TextSpec,
// and one settings panel edits it.

/// TextCase is applied at paint time, not to the stored string, so turning
/// it off gives back what was typed.
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

/// TextAlignSpec is our own enum, not Flutter's TextAlign, so a saved
/// document does not depend on another library's value indices.
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

/// canvasFonts are the faces in the font dropdown: bundled or on every
/// desktop, since a font that resolves to another silently changes an
/// exported design.
const List<String> canvasFonts = [
  "Inter",
  "Roboto",
  "RobotoMono",
  // Condensed, for headlines on slabs: bundled.
  "Bebas Neue",
  "Oswald",
  // Comic lettering, for titles: bundled.
  "Bangers",
  // A serif whose figures all stand on the line, for a magazine page's
  // headlines and numbers: bundled.
  "PTSerif",
  "Arial",
  "Helvetica",
  "Georgia",
  "Times New Roman",
  "Courier New",
  "Verdana",
  "Impact",
];

enum TextFillKind {
  color("Colour"),
  image("Picture"),
  pattern("Pattern");

  final String label;
  const TextFillKind(this.label);

  static TextFillKind fromName(String? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => color);
}

/// TextFill is a picture or pattern showing through the letters. The fill is
/// drawn across the whole word and cut to the type, so it does not restart
/// in every letter. The pattern is a [ProceduralSpec], as backgrounds use.
class TextFill {
  final TextFillKind kind;

  /// assetId is the picture, for [TextFillKind.image].
  final String assetId;

  final ProceduralSpec pattern;

  /// zoom sizes the picture or pattern against the words: 1 fits it across
  /// them, 2 shows a quarter of it twice as large.
  final double zoom;

  /// tile repeats a picture instead of covering the words with one copy.
  final bool tile;

  /// filter, saturation and brightness mean what a picture element's do;
  /// both sliders are multipliers, 1 unchanged.
  final ImageFilterPreset filter;
  final double saturation;
  final double brightness;

  /// overlay is a colour laid over the picture, and blend how, as in a
  /// picture's Look; laid only where there is picture (paintThroughText).
  final Color overlay;
  final OverlayBlend blend;

  /// overlayFade fades the overlay to a second colour; null is flat.
  final GradientSpec? overlayFade;

  /// opacity is how much of the fill lands, 0..1, for knocking back a
  /// picture or pattern (a colour has its own alpha).
  final double opacity;

  /// locked carries the fill with the words as they arrive, so the same part
  /// shows through each letter throughout. Only for a whole-paragraph
  /// arrival: letter by letter there is no single movement to lock to.
  final bool locked;

  /// panX and panY move the picture or pattern inside its frame, as a
  /// share of the frame's width and height: a photo slid in a Layout cell
  /// to put a face in the middle.
  final double panX, panY;

  const TextFill({
    this.kind = TextFillKind.color,
    this.assetId = "",
    this.pattern = const ProceduralSpec(),
    this.zoom = 1,
    this.tile = false,
    this.filter = ImageFilterPreset.none,
    this.saturation = 1,
    this.brightness = 1,
    this.overlay = const Color(0x00000000),
    this.blend = OverlayBlend.none,
    this.overlayFade,
    this.opacity = 1,
    this.locked = false,
    this.panX = 0,
    this.panY = 0,
  });

  /// on is whether anything but plain colour is used and, for a picture,
  /// one has been chosen.
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
    ImageFilterPreset? filter,
    double? saturation,
    double? brightness,
    Color? overlay,
    OverlayBlend? blend,
    GradientSpec? overlayFade,
    double? opacity,
    double? panX,
    double? panY,

    /// flatOverlay clears [overlayFade], since a null there means "keep".
    bool flatOverlay = false,
  }) =>
      TextFill(
        kind: kind ?? this.kind,
        assetId: assetId ?? this.assetId,
        pattern: pattern ?? this.pattern,
        zoom: zoom ?? this.zoom,
        tile: tile ?? this.tile,
        locked: locked ?? this.locked,
        filter: filter ?? this.filter,
        saturation: saturation ?? this.saturation,
        brightness: brightness ?? this.brightness,
        overlay: overlay ?? this.overlay,
        blend: blend ?? this.blend,
        overlayFade: flatOverlay ? null : (overlayFade ?? this.overlayFade),
        opacity: opacity ?? this.opacity,
        panX: panX ?? this.panX,
        panY: panY ?? this.panY,
      );

  Map<String, dynamic> toJson() => {
        if (kind != TextFillKind.color) "kind": kind.name,
        if (assetId.isNotEmpty) "assetId": assetId,
        if (kind == TextFillKind.pattern) "pattern": pattern.toJson(),
        if (zoom != 1) "zoom": zoom,
        if (tile) "tile": true,
        if (locked) "locked": true,
        if (filter != ImageFilterPreset.none) "filter": filter.name,
        if (saturation != 1) "sat": saturation,
        if (brightness != 1) "bri": brightness,
        if (blend != OverlayBlend.none) "overlay": colorToJson(overlay),
        if (blend != OverlayBlend.none) "blend": blend.name,
        if (overlayFade != null) "overlayFade": overlayFade!.toJson(),
        if (opacity != 1) "opacity": opacity,
        if (panX != 0) "panX": panX,
        if (panY != 0) "panY": panY,
      };

  factory TextFill.fromJson(Map<String, dynamic> json) => TextFill(
        kind: TextFillKind.fromName(jsonStr(json["kind"])),
        assetId: jsonString(json["assetId"], ""),
        pattern: json["pattern"] is Map<String, dynamic>
            ? ProceduralSpec.fromJson(json["pattern"] as Map<String, dynamic>)
            : const ProceduralSpec(),
        zoom: jsonDouble(json["zoom"], 1).clamp(0.05, 20),
        tile: jsonBool(json["tile"], false),
        locked: jsonBool(json["locked"], false),
        filter: ImageFilterPreset.fromName(jsonStr(json["filter"])),
        saturation: jsonDouble(json["sat"], 1).clamp(0.0, 3.0),
        brightness: jsonDouble(json["bri"], 1).clamp(0.0, 3.0),
        overlay: colorFromJson(json["overlay"], const Color(0x00000000)),
        blend: OverlayBlend.fromName(jsonStr(json["blend"])),
        overlayFade: json["overlayFade"] is Map<String, dynamic>
            ? GradientSpec.fromJson(json["overlayFade"] as Map<String, dynamic>)
            : null,
        opacity: jsonDouble(json["opacity"], 1).clamp(0.0, 1.0),
        panX: jsonDouble(json["panX"], 0).clamp(-10.0, 10.0),
        panY: jsonDouble(json["panY"], 0).clamp(-10.0, 10.0),
      );
}

class TextSpec {
  final String fontFamily;
  final double fontSize;

  /// weight is 100..900 in hundreds, as CSS and FontWeight.
  final int weight;
  final bool italic;
  final bool underline;

  /// letterSpacing is in design units, and may be negative.
  final double letterSpacing;

  /// lineHeight is a multiple of the font size, so resizing keeps the
  /// paragraph's proportions.
  final double lineHeight;

  final TextAlignSpec align;
  final VerticalAlignSpec verticalAlign;
  final TextCase textCase;

  final Color color;

  /// fade is the second colour the words run to, or null for flat. Runs
  /// across the text's box so it does not restart each line. Ignored for
  /// outlined letters and under a [fill]. See textStyleOf.
  final GradientSpec? fade;

  /// fill shows through the letters; off, they are [color].
  final TextFill fill;

  /// outlineWidth strokes the glyph outlines; zero is no outline.
  final double outlineWidth;
  final Color outlineColor;

  final double shadowBlur;
  final Color shadowColor;

  /// shadowAngle is where the light comes *from*, in compass degrees (0 up,
  /// 90 right); the shadow falls opposite. An angle and distance, not an
  /// offset, so one light direction copies between elements.
  final double shadowAngle;

  /// shadowDistance is in design units; zero leaves it directly underneath.
  final double shadowDistance;

  /// glowBlur is a soft light all round, in [glowColor]; zero is off.
  /// Separate from the shadow so type can have both.
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

  /// shadowOffset is [shadowDistance] away, opposite the light (screen y
  /// runs down, so compass up is -y).
  Offset get shadowOffset {
    if (shadowDistance == 0) return Offset.zero;
    var radians = shadowAngle * math.pi / 180;
    return Offset(-math.sin(radians) * shadowDistance,
        math.cos(radians) * shadowDistance);
  }

  /// softPasses is whether a shadow or glow is drawn behind the letters.
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

  /// fontWeight is [weight] truncated to a hundred and clamped, so a stray
  /// saved value cannot index out of range.
  FontWeight get fontWeight =>
      FontWeight.values[((weight ~/ 100) - 1).clamp(0, 8)];

  /// scaledBy sizes the type and everything in design units by [by] (line
  /// height is relative already).
  TextSpec scaledBy(double by) => copyWith(
        fontSize: fontSize * by,
        letterSpacing: letterSpacing * by,
        outlineWidth: outlineWidth * by,
        shadowBlur: shadowBlur * by,
        shadowDistance: shadowDistance * by,
        glowBlur: glowBlur * by,
      );

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
        fontFamily: jsonLabel(json["font"], "Inter"),
        fontSize: jsonDouble(json["size"], 48).clamp(1.0, 4000.0),
        weight: jsonInt(json["weight"], 600),
        italic: jsonBool(json["italic"], false),
        underline: jsonBool(json["underline"], false),
        letterSpacing: jsonDouble(json["ls"], 0),
        lineHeight: jsonDouble(json["lh"], 1.2),
        align: TextAlignSpec.fromName(jsonStr(json["align"])),
        verticalAlign: VerticalAlignSpec.fromName(jsonStr(json["valign"])),
        textCase: TextCase.fromName(jsonStr(json["case"])),
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
        shadowAngle: jsonDouble(json["sa"], 315),
        shadowDistance: jsonDouble(json["sd"], 0),
        glowBlur: jsonDouble(json["gb"], 0),
        glowColor: colorFromJson(json["gc"], const Color(0xFFFFFFFF)),
      );

  /// Equality lets paint_util's layout cache reuse a laid-out line. It does
  /// not compare [fill].
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

  /// _hashes remembers each spec's hash: a spec never changes, and its
  /// nineteen fields cost more to hash than the text caches keyed on it cost
  /// to look up. A const spec cannot hold it, so an Expando does.
  static final _hashes = Expando<int>();

  @override
  int get hashCode => _hashes[this] ??= _hash();

  int _hash() => Object.hash(
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

/// Corners is four corner radii, one number answering for any not given
/// their own. Shared by an element's frame and a rectangle shape so both
/// round alike; a box is almost always even, and saved documents hold one
/// number.
class Corners {
  /// all is every corner not given its own.
  final double all;

  /// tl, tr, br and bl are the overrides, or null.
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

  /// even is the number all four share, or null where they differ: what the
  /// "all corners" field shows.
  double? get even => topLeft == topRight &&
          topRight == bottomRight &&
          bottomRight == bottomLeft
      ? topLeft
      : null;

  /// withEven sets all four, dropping overrides.
  Corners withEven(double radius) => Corners(all: radius);

  Corners scaledBy(double by) => Corners(
        all: all * by,
        tl: tl == null ? null : tl! * by,
        tr: tr == null ? null : tr! * by,
        br: br == null ? null : br! * by,
        bl: bl == null ? null : bl! * by,
      );

  Corners copyWith(
          {double? all, double? tl, double? tr, double? br, double? bl}) =>
      Corners(
        all: all ?? this.all,
        tl: tl ?? this.tl,
        tr: tr ?? this.tr,
        br: br ?? this.br,
        bl: bl ?? this.bl,
      );

  /// rrect is [rect] with these corners, inset by [by], so a border inside a
  /// fill stays concentric with it.
  RRect rrect(Rect rect, {double by = 0}) => RRect.fromRectAndCorners(
        by == 0 ? rect : rect.deflate(by),
        topLeft: Radius.circular(math.max(0, topLeft - by)),
        topRight: Radius.circular(math.max(0, topRight - by)),
        bottomRight: Radius.circular(math.max(0, bottomRight - by)),
        bottomLeft: Radius.circular(math.max(0, bottomLeft - by)),
      );

  /// inside is [inner], already padded, with corners concentric with these.
  /// Each corner is pulled in by the wider side meeting it, which keeps the
  /// curve in its room when the padding is uneven.
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

/// Room is the space kept on four sides, one number answering for any not
/// given its own, as [Corners] is for corners.
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

  Rect inner(Rect rect) => insets.deflateRect(rect);

  double? get even =>
      left == top && top == right && right == bottom ? left : null;

  Room withEven(double pad) => Room(all: pad);

  Room scaledBy(double by) => Room(
        all: all * by,
        l: l == null ? null : l! * by,
        t: t == null ? null : t! * by,
        r: r == null ? null : r! * by,
        b: b == null ? null : b! * by,
      );

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

/// BoxSpec is the frame round something: fill, border and padding, shared
/// by text, buttons, tables and images.
class BoxSpec {
  final Color fill;

  /// painted is a picture or pattern covering the box instead, cut to its
  /// corners (as TextFill does for letters); off, [fill] draws the box.
  final TextFill painted;
  final double borderWidth;
  final Color borderColor;

  /// fillFade and borderFade are second colours to fade to, or null for flat.
  final GradientSpec? fillFade;
  final GradientSpec? borderFade;

  /// bwL, bwT, bwR and bwB are one side's border width, or null for
  /// [borderWidth] (a rule under a heading, a bar down a quote).
  final double? bwL;
  final double? bwT;
  final double? bwR;
  final double? bwB;

  /// borderRadius is every corner not given its own, and [padding] every
  /// side; padL..radBL are the overrides. Stored flat because BoxSpecs are
  /// consts, and a const constructor cannot build [Corners] and [Room];
  /// [corners] and [pad] hand them back.
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
    this.painted = const TextFill(),
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
    this.borderInset = 0,
  });

  /// borderInset draws the border that far inside the box's edge, with the
  /// box's own rounding: a plaque's rule inside its frame. Uneven sides are
  /// inset as strips.
  final double borderInset;

  Corners get corners =>
      Corners(all: borderRadius, tl: radTL, tr: radTR, br: radBR, bl: radBL);
  Room get pad => Room(all: padding, l: padL, t: padT, r: padR, b: padB);

  /// borders is the four border widths.
  Room get borders => Room(all: borderWidth, l: bwL, t: bwT, r: bwR, b: bwB);

  /// evenBorder is the width all four sides share, or null: what the "all
  /// sides" field shows, and whether it can be drawn as one rounded rectangle.
  double? get evenBorder => borders.even;

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

  EdgeInsets get insets => pad.insets;

  Rect inner(Rect rect) => pad.inner(rect);

  /// evenPad and evenRadius are the shared value, or null where they differ:
  /// what the "all sides" field shows.
  double? get evenPad => pad.even;

  double? get evenRadius => corners.even;

  bool get isRounded => corners.isRounded;

  RRect rounded(Rect rect, {double by = 0}) => corners.rrect(rect, by: by);

  /// insetRounded is [within], already padded, with concentric corners.
  RRect insetRounded(Rect within) => corners.inside(within, pad);

  /// assetIds is the picture this box is painted with. Every element with a
  /// box must fold it into its own assetIds, or the sweep deletes it.
  Set<String> get assetIds =>
      painted.assetId.isEmpty ? const {} : {painted.assetId};

  /// scaledBy sizes corners, padding and border widths by [by].
  BoxSpec scaledBy(double by) => withCorners(corners.scaledBy(by))
      .withRoom(pad.scaledBy(by))
      .withBorders(borders.scaledBy(by))
      .copyWith(borderInset: borderInset * by);

  /// withCorners and withRoom replace one whole set, overrides and all, not
  /// as copyWith, whose nulls keep the old overrides.
  BoxSpec withCorners(Corners corners) => BoxSpec(
      fill: fill,
      painted: painted,
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
      padB: padB,
      borderInset: borderInset);

  BoxSpec withRoom(Room room) => BoxSpec(
      fill: fill,
      painted: painted,
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
      padB: room.b,
      borderInset: borderInset);

  /// withBorders replaces all four widths, as [withCorners] does.
  BoxSpec withBorders(Room room) => BoxSpec(
      fill: fill,
      painted: painted,
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
      padB: padB,
      borderInset: borderInset);

  /// withEvenPad sets all four sides, dropping overrides.
  BoxSpec withEvenPad(double padding) => withRoom(pad.withEven(padding));

  /// withEvenRadius does the same for corners.
  BoxSpec withEvenRadius(double radius) =>
      withCorners(corners.withEven(radius));

  BoxSpec copyWith({
    Color? fill,
    TextFill? painted,
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
    double? borderInset,
  }) =>
      BoxSpec(
        fill: fill ?? this.fill,
        painted: painted ?? this.painted,
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
        borderInset: borderInset ?? this.borderInset,
      );

  Map<String, dynamic> toJson() => {
        "fill": colorToJson(fill),
        if (painted.on) "painted": painted.toJson(),
        if (fillFade != null) "fillFade": fillFade!.toJson(),
        if (borderFade != null) "borderFade": borderFade!.toJson(),
        if (borderWidth > 0) "bw": borderWidth,
        if (hasBorder) "bc": colorToJson(borderColor),
        // Overrides are written only where set, so an even box saves only
        // its one number.
        if (bwL != null) "bwL": bwL,
        if (bwT != null) "bwT": bwT,
        if (bwR != null) "bwR": bwR,
        if (bwB != null) "bwB": bwB,
        if (borderRadius > 0) "br": borderRadius,
        "pad": padding,
        if (padL != null) "padL": padL,
        if (padT != null) "padT": padT,
        if (padR != null) "padR": padR,
        if (padB != null) "padB": padB,
        if (radTL != null) "rTL": radTL,
        if (radTR != null) "rTR": radTR,
        if (radBR != null) "rBR": radBR,
        if (radBL != null) "rBL": radBL,
        if (borderInset != 0) "bi": borderInset,
      };

  factory BoxSpec.fromJson(Map<String, dynamic> json) => BoxSpec(
        fill: colorFromJson(json["fill"], const Color(0x00000000)),
        painted: json["painted"] is Map
            ? TextFill.fromJson(
                (json["painted"] as Map).cast<String, dynamic>())
            : const TextFill(),
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
        borderInset: jsonDouble(json["bi"], 0).clamp(0, 4000),
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
          other.pad == pad &&
          other.borderInset == borderInset;

  @override
  int get hashCode => Object.hash(fill, fillFade, borderFade, borderWidth,
      borderColor, corners, pad, borders, borderInset);
}
