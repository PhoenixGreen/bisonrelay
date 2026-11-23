import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/components/paint_spec.dart';
import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';

export 'package:bruig/plugin_system/canvas/model/box_spec.dart';

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

/// canvasFonts are the faces in the font dropdown. Inter, RobotoMono and
/// those marked are bundled with the app; the rest are common desktop
/// faces that not every system has (Roboto is not bundled, Helvetica is not
/// on Windows or Linux, nor Impact on Linux). A face a system lacks is drawn
/// in its fallback, which changes an exported design without a word.
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

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = TextFill();

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

  /// mapColours maps the overlay (shown only with a blend, as it is saved),
  /// its fade and the pattern (shown only when the fill is a pattern).
  TextFill mapColours(ColourMap f) {
    var p = ColourPass(f);
    var overlay = p(this.overlay, shown: blend != _defaults.blend);
    var overlayFade = p.partOrNone(this.overlayFade, (g) => g.mapColours(f));
    var pattern = p.part(this.pattern,
        (s) => s.mapColours(f.shownOnlyIf(kind == TextFillKind.pattern)));
    if (!p.changed) return this;
    return copyWith(
        overlay: overlay, overlayFade: overlayFade, pattern: pattern);
  }

  Map<String, dynamic> toJson() => {
        if (kind != _defaults.kind) "kind": kind.name,
        if (assetId.isNotEmpty) "assetId": assetId,
        if (kind == TextFillKind.pattern) "pattern": pattern.toJson(),
        if (zoom != _defaults.zoom) "zoom": zoom,
        if (tile) "tile": true,
        if (locked) "locked": true,
        if (filter != _defaults.filter) "filter": filter.name,
        if (saturation != _defaults.saturation) "sat": saturation,
        if (brightness != _defaults.brightness) "bri": brightness,
        if (blend != _defaults.blend) "overlay": colorToJson(overlay),
        if (blend != _defaults.blend) "blend": blend.name,
        if (overlayFade != null) "overlayFade": overlayFade!.toJson(),
        if (opacity != _defaults.opacity) "opacity": opacity,
        if (panX != _defaults.panX) "panX": panX,
        if (panY != _defaults.panY) "panY": panY,
      };

  factory TextFill.fromJson(Map<String, dynamic> json) => TextFill(
        kind: TextFillKind.fromName(jsonStr(json["kind"])),
        assetId: jsonString(json["assetId"], _defaults.assetId),
        pattern: json["pattern"] is Map<String, dynamic>
            ? ProceduralSpec.fromJson(json["pattern"] as Map<String, dynamic>)
            : const ProceduralSpec(),
        zoom: jsonDouble(json["zoom"], _defaults.zoom).clamp(0.05, 20),
        tile: jsonBool(json["tile"], false),
        locked: jsonBool(json["locked"], false),
        filter: ImageFilterPreset.fromName(jsonStr(json["filter"])),
        saturation:
            jsonDouble(json["sat"], _defaults.saturation).clamp(0.0, 3.0),
        brightness:
            jsonDouble(json["bri"], _defaults.brightness).clamp(0.0, 3.0),
        overlay: colorFromJson(json["overlay"], _defaults.overlay),
        blend: OverlayBlend.fromName(jsonStr(json["blend"])),
        overlayFade: json["overlayFade"] is Map<String, dynamic>
            ? GradientSpec.fromJson(json["overlayFade"] as Map<String, dynamic>)
            : null,
        opacity: jsonDouble(json["opacity"], _defaults.opacity).clamp(0.0, 1.0),
        panX: jsonDouble(json["panX"], _defaults.panX).clamp(-10.0, 10.0),
        panY: jsonDouble(json["panY"], _defaults.panY).clamp(-10.0, 10.0),
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

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = TextSpec();

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

  /// mapColours maps the type's colour, fade and fill, and its outline,
  /// shadow and glow colours, each shown only while that effect is on (as
  /// they are saved).
  TextSpec mapColours(ColourMap f) {
    var p = ColourPass(f);
    var color = p(this.color);
    var fade = p.partOrNone(this.fade, (g) => g.mapColours(f));
    var fill = p.part(this.fill, (x) => x.mapColours(f));
    var outlineColor = p(this.outlineColor, shown: outlineWidth > 0);
    var shadowColor =
        p(this.shadowColor, shown: shadowBlur > 0 || shadowDistance > 0);
    var glowColor = p(this.glowColor, shown: glowBlur > 0);
    if (!p.changed) return this;
    return copyWith(
      color: color,
      fade: fade,
      fill: fill,
      outlineColor: outlineColor,
      shadowColor: shadowColor,
      glowColor: glowColor,
    );
  }

  FontWeight get fontWeight => weightOf(weight);

  /// weightOf is [weight] as Flutter's weight: the hundred at or below it,
  /// clamped, so a stray saved value cannot index out of range. Every place
  /// a weight is drawn or shown goes through here, so all agree on a weight
  /// typed between the hundreds.
  static FontWeight weightOf(int weight) =>
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
        if (letterSpacing != _defaults.letterSpacing) "ls": letterSpacing,
        "lh": lineHeight,
        "align": align.name,
        "valign": verticalAlign.name,
        if (textCase != _defaults.textCase) "case": textCase.name,
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
        fontFamily: jsonLabel(json["font"], _defaults.fontFamily),
        fontSize: jsonDouble(json["size"], _defaults.fontSize)
            .clamp(1.0, maxDesignLength),
        weight: jsonInt(json["weight"], _defaults.weight).clamp(1, 1000),
        italic: jsonBool(json["italic"], false),
        underline: jsonBool(json["underline"], false),
        letterSpacing:
            jsonLength(json["ls"], _defaults.letterSpacing, signed: true),
        // A multiple of the size: the panel's 0.5 to 5, ten times over.
        lineHeight: jsonDouble(json["lh"], _defaults.lineHeight).clamp(0, 50),
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
        outlineWidth: jsonLength(json["ow"], _defaults.outlineWidth),
        outlineColor: colorFromJson(json["oc"], _defaults.outlineColor),
        shadowBlur: jsonLength(json["sb"], _defaults.shadowBlur),
        shadowColor: colorFromJson(json["sc"], _defaults.shadowColor),
        // Ten turns either way: only its direction is ever used.
        shadowAngle:
            jsonDouble(json["sa"], _defaults.shadowAngle).clamp(-3600, 3600),
        shadowDistance: jsonLength(json["sd"], _defaults.shadowDistance),
        glowBlur: jsonLength(json["gb"], _defaults.glowBlur),
        glowColor: colorFromJson(json["gc"], _defaults.glowColor),
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
