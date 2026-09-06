import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// procedural_spec.dart is the recipe for a generated background: which
// algorithm, which colours, how dense, and which seed.
//
// A generated background is a handful of numbers rather than a picture, and
// that is the entire point of having one. It weighs nothing in a saved
// document, it redraws sharp at any export width, and pressing the shuffle
// button is one integer changing -- so a reader can try forty variations of
// the same idea in forty seconds and the document never grows.
//
// The spec is shared by two different things and deliberately so. The canvas
// has one background of its own covering the whole document, and a background
// *element* is the same generator placed in a rectangle, so a panel of matrix
// rain can sit behind a title without taking over the page. One recipe, two
// places it can be pointed at.

/// ProceduralStyle is which generator runs.
///
/// The list is ordered from quietest to loudest, which is the order the
/// dropdown shows and the order somebody building a background wants to walk:
/// start with nothing and add until it is enough. See render/procedural/ for
/// what each one actually draws.
enum ProceduralStyle {
  plain("Plain", "A flat fill, or a gradient between the two colours"),
  gradientMesh("Gradient mesh", "Soft blended blooms of colour"),
  dotGrid("Dot grid", "An even field of dots, sized by the density"),
  lineGrid("Line grid", "Ruled lines, square or isometric"),
  hexGrid("Hex grid", "A honeycomb of outlined cells"),
  contours("Contours", "Nested contour lines from a smooth noise field"),
  flowWaves("Flow waves", "Ribbons of light bent through a flow field"),
  bokeh("Bokeh", "Soft out-of-focus discs of light"),
  starfield("Starfield", "Scattered points of light, brightest in the middle"),
  ledGrid("LED grid", "A dot-matrix wall of lit and unlit cells"),
  circuit("Circuit", "Right-angled traces with pads at the corners"),
  rain("Symbol rain", "Columns of falling glyphs, brightest at the head"),
  symbolField("Symbol field", "Scattered glyphs at varying size and angle"),
  rings("Rings", "Concentric rings radiating from a point"),
  pitch("Sports pitch", "A marked playing surface, drawn to scale");

  final String label;
  final String description;
  const ProceduralStyle(this.label, this.description);

  static ProceduralStyle fromName(String? name) => values.firstWhere(
        (s) => s.name == name,
        orElse: () => ProceduralStyle.plain,
      );

  /// usesGlyphs is whether the glyph set is worth showing in the settings
  /// bar. Showing every control for every style buries the three that matter.
  bool get usesGlyphs =>
      this == ProceduralStyle.rain || this == ProceduralStyle.symbolField;

  /// canAnimate is whether the style has anything to do when the frame
  /// advances. A ruled grid does not; rain does.
  bool get canAnimate => switch (this) {
        ProceduralStyle.plain ||
        ProceduralStyle.lineGrid ||
        ProceduralStyle.hexGrid ||
        ProceduralStyle.pitch =>
          false,
        _ => true,
      };
}

/// PitchSport is which surface [ProceduralStyle.pitch] marks out.
///
/// The markings are drawn to the real proportions of the sport rather than to
/// the canvas, and letterboxed inside whatever rectangle they are given. A
/// pitch stretched to 21:9 is not a pitch, and a strategy diagram drawn on a
/// stretched one puts the players in the wrong places.
enum PitchSport {
  football("Football", 105 / 68),
  basketball("Basketball", 28 / 15),
  tennis("Tennis", 23.77 / 10.97),
  hockey("Hockey", 91.4 / 55),
  rugby("Rugby", 100 / 70),
  americanFootball("American football", 109.7 / 48.8),
  blank("Blank field", 105 / 68);

  final String label;

  /// aspect is length divided by width, from the sport's own laws.
  final double aspect;
  const PitchSport(this.label, this.aspect);

  static PitchSport fromName(String? name) => values
      .firstWhere((s) => s.name == name, orElse: () => PitchSport.football);
}

/// defaultGlyphs is what the rain falls in when nobody has said otherwise.
///
/// Half-width katakana and digits, which is what the film used and what reads
/// as rain rather than as text: the shapes are dense, roughly square, and
/// unfamiliar enough that the eye does not stop to read them.
const String defaultGlyphs =
    "0123456789ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ";

/// ProceduralSpec is a background recipe.
class ProceduralSpec {
  final ProceduralStyle style;

  /// seed is what the shuffle button changes. Every generator draws from a
  /// pseudo-random sequence started from it, so the same seed is the same
  /// picture on every machine and at every export size.
  final int seed;

  /// background is what is painted before the generator runs. Every style
  /// draws on top of it, so it is the one colour that is always in effect.
  final Color background;

  /// foreground and accent are the generator's own two colours. What they
  /// mean is the generator's business -- for rain, the trail and the lit
  /// head; for a pitch, the lines and the floodlight.
  final Color foreground;
  final Color accent;

  /// gradient blends [background] towards [gradientTo] behind the generator.
  final bool gradient;
  final Color gradientTo;

  /// gradientAngle is in degrees, clockwise from left-to-right.
  final double gradientAngle;

  /// density is roughly "how much of it": 0 draws nothing at all and 1 fills
  /// the frame. Every generator is written so that turning this down leaves a
  /// quieter version of the same picture rather than a different one.
  final double density;

  /// scale sizes the generator's repeating unit -- the cell of a grid, the
  /// glyph of the rain, the disc of the bokeh -- as a fraction of the shorter
  /// side, so a background looks the same at every export width.
  final double scale;

  /// intensity is how bright the brightest parts get.
  final double intensity;

  /// variation is how much the generator is allowed to differ from itself:
  /// jitter in a grid, spread of sizes in a bokeh, curl in a flow field.
  final double variation;

  /// rotation turns the whole pattern, in degrees.
  final double rotation;

  /// glyphs is the character set the glyph styles draw from.
  final String glyphs;

  /// animated is whether the pattern moves with the frame. Off by default:
  /// most canvases are still pictures, and a background that moves is a
  /// decision rather than the default.
  final bool animated;

  /// speed multiplies how far the pattern advances per frame.
  final double speed;

  /// sport is read only by [ProceduralStyle.pitch].
  final PitchSport sport;

  /// vignette darkens the edges. Its own field rather than part of intensity
  /// because it is what makes almost all of these read as a background rather
  /// than as a pattern -- it puts the middle of the canvas forward.
  final double vignette;

  const ProceduralSpec({
    this.style = ProceduralStyle.plain,
    this.seed = 1,
    this.background = const Color(0xFF0B0F14),
    this.foreground = const Color(0xFF2FE08A),
    this.accent = const Color(0xFFDFFFF0),
    this.gradient = false,
    this.gradientTo = const Color(0xFF16202B),
    this.gradientAngle = 90,
    this.density = 0.5,
    this.scale = 0.05,
    this.intensity = 0.8,
    this.variation = 0.5,
    this.rotation = 0,
    this.glyphs = defaultGlyphs,
    this.animated = false,
    this.speed = 1,
    this.sport = PitchSport.football,
    this.vignette = 0.25,
  });

  ProceduralSpec copyWith({
    ProceduralStyle? style,
    int? seed,
    Color? background,
    Color? foreground,
    Color? accent,
    bool? gradient,
    Color? gradientTo,
    double? gradientAngle,
    double? density,
    double? scale,
    double? intensity,
    double? variation,
    double? rotation,
    String? glyphs,
    bool? animated,
    double? speed,
    PitchSport? sport,
    double? vignette,
  }) =>
      ProceduralSpec(
        style: style ?? this.style,
        seed: seed ?? this.seed,
        background: background ?? this.background,
        foreground: foreground ?? this.foreground,
        accent: accent ?? this.accent,
        gradient: gradient ?? this.gradient,
        gradientTo: gradientTo ?? this.gradientTo,
        gradientAngle: gradientAngle ?? this.gradientAngle,
        density: density ?? this.density,
        scale: scale ?? this.scale,
        intensity: intensity ?? this.intensity,
        variation: variation ?? this.variation,
        rotation: rotation ?? this.rotation,
        glyphs: glyphs ?? this.glyphs,
        animated: animated ?? this.animated,
        speed: speed ?? this.speed,
        sport: sport ?? this.sport,
        vignette: vignette ?? this.vignette,
      );

  /// shuffled is the next seed along. Sequential rather than random, so the
  /// button walks a stable series -- pressing it four times and then wanting
  /// the second one back is three presses away rather than gone forever.
  ProceduralSpec shuffled() => copyWith(seed: seed + 1);

  Map<String, dynamic> toJson() => {
        "style": style.name,
        "seed": seed,
        "bg": colorToJson(background),
        "fg": colorToJson(foreground),
        "accent": colorToJson(accent),
        if (gradient) "gradient": true,
        if (gradient) "gradientTo": colorToJson(gradientTo),
        if (gradient) "gradientAngle": gradientAngle,
        "density": density,
        "scale": scale,
        "intensity": intensity,
        "variation": variation,
        if (rotation != 0) "rotation": rotation,
        if (glyphs != defaultGlyphs) "glyphs": glyphs,
        if (animated) "animated": true,
        if (animated) "speed": speed,
        if (style == ProceduralStyle.pitch) "sport": sport.name,
        "vignette": vignette,
      };

  factory ProceduralSpec.fromJson(Map<String, dynamic> json) => ProceduralSpec(
        style: ProceduralStyle.fromName(json["style"] as String?),
        seed: jsonInt(json["seed"], 1),
        background: colorFromJson(json["bg"], const Color(0xFF0B0F14)),
        foreground: colorFromJson(json["fg"], const Color(0xFF2FE08A)),
        accent: colorFromJson(json["accent"], const Color(0xFFDFFFF0)),
        gradient: jsonBool(json["gradient"], false),
        gradientTo: colorFromJson(json["gradientTo"], const Color(0xFF16202B)),
        gradientAngle: jsonDouble(json["gradientAngle"], 90),
        density: jsonDouble(json["density"], 0.5).clamp(0.0, 1.0),
        scale: jsonDouble(json["scale"], 0.05).clamp(0.002, 0.5),
        intensity: jsonDouble(json["intensity"], 0.8).clamp(0.0, 1.0),
        variation: jsonDouble(json["variation"], 0.5).clamp(0.0, 1.0),
        rotation: jsonDouble(json["rotation"], 0),
        glyphs: jsonString(json["glyphs"], defaultGlyphs),
        animated: jsonBool(json["animated"], false),
        speed: jsonDouble(json["speed"], 1),
        sport: PitchSport.fromName(json["sport"] as String?),
        vignette: jsonDouble(json["vignette"], 0.25).clamp(0.0, 1.0),
      );
}
