import 'dart:ui';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_effects.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_layers.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_light.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_params.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_rings.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_style_params.dart';

// procedural_spec.dart is the recipe for a generated background: which
// algorithm, which colours, how dense, and which seed.
//
// A recipe rather than a picture: it weighs nothing in a saved document,
// redraws sharp at any export width, and shuffling is one integer changing.
// The canvas background and a background element share it.

/// ProceduralStyle is which generator runs.
///
/// Ordered from quietest to loudest, the order the dropdown shows. See
/// render/procedural/ for what each one draws.
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
  circuit("Circuit", "Right-angled traces with pads at the corners"),
  rain("Symbol rain", "Columns of falling glyphs, brightest at the head"),
  rings("Rings", "Concentric rings radiating from a point"),
  blockchain("Blockchain",
      "Chained blocks, a node network, a ledger, a Merkle tree or a field of blocks"),
  // The drawn ones: pen and brush marks, suited to a pattern inside
  // lettering.
  halftone("Halftone", "Comic-book dots, bigger where the ink is heavier"),
  speedLines("Speed lines", "Rays bursting out from a point"),
  crosshatch("Crosshatch", "Inked hatching, crossed at an angle"),
  splatter("Paint splatter", "Thrown ink, with droplets and drips"),
  flames("Flames", "Tongues of fire licking upward"),
  pitch("Sports pitch", "A marked playing surface, drawn to scale"),
  // Surfaces: the ground itself rather than marks on one.
  metal("Metal texture", "Brushed metal, with rust, damage and a sheen"),
  surface("Surface",
      "Paper, concrete, wood, marble, carbon fibre, fabric or leather");

  final String label;
  final String description;
  const ProceduralStyle(this.label, this.description);

  /// family is which heading it is listed under.
  StyleFamily get family => switch (this) {
        plain ||
        gradientMesh ||
        bokeh ||
        flowWaves ||
        rings ||
        starfield =>
          StyleFamily.light,
        dotGrid ||
        lineGrid ||
        hexGrid ||
        circuit ||
        blockchain ||
        rain =>
          StyleFamily.tech,
        contours || flames => StyleFamily.organic,
        halftone || speedLines || crosshatch || splatter => StyleFamily.graphic,
        metal || surface => StyleFamily.surface,
        pitch => StyleFamily.sport,
      };

  /// params is the settings this style has of its own. See StyleParam.
  List<StyleParam> get params => paramsOf(this);

  static ProceduralStyle fromName(String? name) => values.firstWhere(
        (s) => s.name == name,
        orElse: () => ProceduralStyle.plain,
      );

  /// usesGlyphs is whether the settings bar shows the glyph set.
  bool get usesGlyphs => this == ProceduralStyle.rain;

  /// canAnimate is whether the style changes as the frame advances.
  bool get canAnimate => switch (this) {
        ProceduralStyle.plain ||
        ProceduralStyle.surface ||
        ProceduralStyle.pitch ||
        ProceduralStyle.metal =>
          false,
        _ => true,
      };
}

/// StyleFamily is a heading the styles are grouped under in the list.
enum StyleFamily {
  light("Gradient & light"),
  tech("Grids & tech"),
  organic("Organic"),
  graphic("Graphic & comic"),
  surface("Surfaces"),
  sport("Sport");

  final String label;
  const StyleFamily(this.label);
}

/// PitchSport is which surface [ProceduralStyle.pitch] marks out.
///
/// The markings keep the sport's real proportions and are letterboxed inside
/// the rectangle given, so players placed on a diagram stay in the right
/// places.
enum PitchSport {
  // The names are saved in documents; labels and order may change.
  football("Football", 105 / 68),
  futsal("Futsal", 40 / 20),
  basketball("Basketball (FIBA)", 28 / 15),
  basketballNba("Basketball (NBA)", 28.65 / 15.24),
  tennis("Tennis", 23.77 / 10.97),
  hockey("Field hockey", 91.4 / 55),
  iceHockey("Ice hockey (NHL)", 60.96 / 25.91),
  rugby("Rugby union", 100 / 70),
  rugbyLeague("Rugby league", 100 / 68),
  americanFootball("American football", 109.728 / 48.768),
  blank("Blank field", 105 / 68);

  final String label;

  /// aspect is length divided by width, from the sport's own laws.
  final double aspect;
  const PitchSport(this.label, this.aspect);

  static PitchSport fromName(String? name) => values
      .firstWhere((s) => s.name == name, orElse: () => PitchSport.football);
}

/// defaultGlyphs is the rain's default character set: half-width katakana and
/// digits, which read as rain rather than as text.
const String defaultGlyphs =
    "0123456789ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ";

/// ProceduralSpec is a background recipe.
class ProceduralSpec {
  final ProceduralStyle style;

  /// seed is what the shuffle button changes. Every generator draws from a
  /// pseudo-random sequence started from it, so the same seed is the same
  /// picture on every machine and at every export size.
  final int seed;

  /// background is painted before the generator runs; every style draws on
  /// top of it.
  final Color background;

  /// foreground and accent are the generator's own two colours; what they
  /// mean is up to the generator (for rain, the trail and the lit head).
  final Color foreground;
  final Color accent;

  /// gradient fades [background] towards a second colour behind the
  /// generator, or null for a flat one. Set in the Base colour's picker.
  final GradientSpec? gradient;

  /// foregroundFade and accentFade fade the generator's own two colours
  /// across the frame, or null for flat ones. See paintProcedural.
  final GradientSpec? foregroundFade;
  final GradientSpec? accentFade;

  /// density is roughly "how much of it": 0 draws nothing and 1 fills the
  /// frame. Turning it down should leave a quieter version of the same
  /// picture, not a different one.
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

  /// animated is whether the pattern moves with the frame. Off by default.
  final bool animated;

  /// speed multiplies how far the pattern advances per frame.
  final double speed;

  /// passFrames is how many frames one complete run takes, for a movement
  /// counted in runs (for rings, every ring born and dissolved). See
  /// proceduralRunSeconds.
  final int passFrames;

  /// loopTimes is how many runs play before the movement holds (nought is
  /// for ever), and loopGap is the frames of stillness between runs.
  ///
  /// Either one set makes the movement counted in runs ([inRuns]), timed by
  /// [passFrames] rather than [speed].
  final int loopTimes;
  final int loopGap;

  /// pauseAt, pauseFor and pauseEase are a rest in the middle of the
  /// movement: the frame it stops on, how many frames it stays stopped, and
  /// how many it spends easing into and out of the stop.
  ///
  /// The pattern's own clock is held while the document's runs on, so it
  /// picks up where it left off. pauseFor nought is no pause.
  final int pauseAt;
  final int pauseFor;
  final int pauseEase;

  /// sport is read only by [ProceduralStyle.pitch].
  final PitchSport sport;

  /// rings is read only by [ProceduralStyle.rings].
  final RingSpec rings;

  /// light is the one light thrown over the finished pattern, whatever the
  /// style. See LightSpec.
  final LightSpec light;

  /// metal is read only by [ProceduralStyle.metal].
  final MetalSpec metal;

  /// vignette darkens the edges, which is most of what makes a pattern read
  /// as a background.
  final double vignette;

  /// loopFrames makes the movement come back to where it began every this
  /// many frames, so that an exported GIF or video loops without a jump;
  /// nought leaves it running on. loopBlend is how much of the loop, at its
  /// end, is spent blending back into its start. See paintProcedural.
  final int loopFrames;
  final double loopBlend;

  /// seamless is whether the movement is made to loop.
  bool get seamless => animated && !inRuns && loopFrames > 0;

  /// effects is what is done to the pattern once it is drawn. See
  /// EffectsSpec.
  final EffectsSpec effects;

  /// params is the style's own settings, by id, where they differ from the
  /// style's defaults. Read through [p]. See StyleParam.
  final Map<String, double> params;

  /// layers is the patterns laid over this one, bottom first. See
  /// BackgroundLayer.
  final List<BackgroundLayer> layers;

  const ProceduralSpec({
    this.style = ProceduralStyle.plain,
    this.seed = 1,
    this.background = const Color(0xFF0B0F14),
    this.foreground = const Color(0xFF2FE08A),
    this.accent = const Color(0xFFDFFFF0),
    this.gradient,
    this.foregroundFade,
    this.accentFade,
    this.density = 0.5,
    this.scale = 0.05,
    this.intensity = 0.8,
    this.variation = 0.5,
    this.rotation = 0,
    this.glyphs = defaultGlyphs,
    this.animated = false,
    this.speed = 1,
    this.passFrames = 120,
    this.loopTimes = 0,
    this.loopGap = 0,
    this.pauseAt = 0,
    this.pauseFor = 0,
    this.pauseEase = 6,
    this.sport = PitchSport.football,
    this.rings = const RingSpec(),
    this.light = const LightSpec(),
    this.metal = const MetalSpec(),
    this.vignette = 0.25,
    this.loopFrames = 0,
    this.loopBlend = 0.3,
    this.effects = const EffectsSpec(),
    this.params = const {},
    this.layers = const [],
  });

  /// p is the style's own setting [id]: what it has been set to, or the
  /// style's default for it.
  double p(String id) {
    var set = params[id];
    for (var param in style.params) {
      if (param.id == id) {
        return set == null ? param.initial : param.clamped(set);
      }
    }
    return set ?? 0;
  }

  /// choice is [p] for a setting that is a choice, as the index chosen.
  int choice(String id) => p(id).round();

  /// on is [p] for a switch.
  bool on(String id) => p(id) >= 0.5;

  /// withParam is this with the style's own setting [id] set to [value].
  ProceduralSpec withParam(String id, double value) =>
      copyWith(params: {...params, id: value});

  /// inRuns is whether the movement is counted in runs rather than going
  /// round for ever: one run that then holds, a set number of them, or runs
  /// with a gap between. All three are timed in frames.
  bool get inRuns => animated && (loopTimes > 0 || loopGap > 0);

  ProceduralSpec copyWith({
    ProceduralStyle? style,
    int? seed,
    Color? background,
    Color? foreground,
    Color? accent,
    GradientSpec? gradient,
    bool flatBackground = false,
    GradientSpec? foregroundFade,
    bool flatForeground = false,
    GradientSpec? accentFade,
    bool flatAccent = false,
    double? density,
    double? scale,
    double? intensity,
    double? variation,
    double? rotation,
    String? glyphs,
    bool? animated,
    double? speed,
    int? passFrames,
    int? loopTimes,
    int? loopGap,
    int? pauseAt,
    int? pauseFor,
    int? pauseEase,
    PitchSport? sport,
    RingSpec? rings,
    LightSpec? light,
    MetalSpec? metal,
    double? vignette,
    EffectsSpec? effects,
    int? loopFrames,
    double? loopBlend,
    Map<String, double>? params,
    List<BackgroundLayer>? layers,
  }) =>
      ProceduralSpec(
        style: style ?? this.style,
        seed: seed ?? this.seed,
        background: background ?? this.background,
        foreground: foreground ?? this.foreground,
        accent: accent ?? this.accent,
        gradient: flatBackground ? null : (gradient ?? this.gradient),
        foregroundFade:
            flatForeground ? null : (foregroundFade ?? this.foregroundFade),
        accentFade: flatAccent ? null : (accentFade ?? this.accentFade),
        density: density ?? this.density,
        scale: scale ?? this.scale,
        intensity: intensity ?? this.intensity,
        variation: variation ?? this.variation,
        rotation: rotation ?? this.rotation,
        glyphs: glyphs ?? this.glyphs,
        animated: animated ?? this.animated,
        speed: speed ?? this.speed,
        passFrames: passFrames ?? this.passFrames,
        loopTimes: loopTimes ?? this.loopTimes,
        loopGap: loopGap ?? this.loopGap,
        pauseAt: pauseAt ?? this.pauseAt,
        pauseFor: pauseFor ?? this.pauseFor,
        pauseEase: pauseEase ?? this.pauseEase,
        sport: sport ?? this.sport,
        rings: rings ?? this.rings,
        light: light ?? this.light,
        metal: metal ?? this.metal,
        vignette: vignette ?? this.vignette,
        effects: effects ?? this.effects,
        loopFrames: loopFrames ?? this.loopFrames,
        loopBlend: loopBlend ?? this.loopBlend,
        params: params ?? this.params,
        layers: layers ?? this.layers,
      );

  /// shuffled is the next seed along: sequential rather than random, so the
  /// button walks a stable series and an earlier pick can be found again.
  ProceduralSpec shuffled() => copyWith(seed: seed + 1);

  Map<String, dynamic> toJson() => {
        "style": style.name,
        "seed": seed,
        "bg": colorToJson(background),
        "fg": colorToJson(foreground),
        "accent": colorToJson(accent),
        if (gradient != null) "gradient": gradient!.toJson(),
        if (foregroundFade != null) "fgFade": foregroundFade!.toJson(),
        if (accentFade != null) "accentFade": accentFade!.toJson(),
        "density": density,
        "scale": scale,
        "intensity": intensity,
        "variation": variation,
        if (rotation != 0) "rotation": rotation,
        if (glyphs != defaultGlyphs) "glyphs": glyphs,
        if (animated) "animated": true,
        if (animated) "speed": speed,
        if (animated && inRuns) "passFrames": passFrames,
        if (animated && loopTimes > 0) "loopTimes": loopTimes,
        if (animated && loopGap > 0) "loopGap": loopGap,
        if (animated && pauseFor > 0) "pauseAt": pauseAt,
        if (animated && pauseFor > 0) "pauseFor": pauseFor,
        if (animated && pauseFor > 0) "pauseEase": pauseEase,
        if (animated && loopFrames > 0) "loopFrames": loopFrames,
        if (animated && loopFrames > 0) "loopBlend": loopBlend,
        if (style == ProceduralStyle.pitch) "sport": sport.name,
        if (style == ProceduralStyle.rings) "rings": rings.toJson(),
        if (light.on) "light": light.toJson(),
        if (style == ProceduralStyle.metal) "metal": metal.toJson(),
        "vignette": vignette,
        if (effects.toJson() case var e when e.isNotEmpty) "effects": e,
        // Only this style's own, where they differ from its defaults.
        // Settings from a previous style are kept while open (switching
        // back finds them) and dropped on save.
        if (_ownParams() case var own when own.isNotEmpty) "params": own,
        if (layers.isNotEmpty) "layers": [for (var l in layers) l.toJson()],
      };

  Map<String, double> _ownParams() => {
        for (var param in style.params)
          if (params[param.id] case var v?)
            if (param.clamped(v) != param.initial) param.id: param.clamped(v),
      };

  /// A pitch's camera settings are left out where they are its View's (the
  /// writer drops a setting at its initial value), so they are filled back
  /// in from the View here.
  factory ProceduralSpec.fromJson(Map<String, dynamic> json) {
    var spec = ProceduralSpec._fromJson(json);
    if (spec.style != ProceduralStyle.pitch) return spec;
    return spec.copyWith(params: pitchCameraParams(spec.params));
  }

  factory ProceduralSpec._fromJson(Map<String, dynamic> json) => ProceduralSpec(
        style: ProceduralStyle.fromName(jsonString(json["style"], "")),
        seed: jsonInt(json["seed"], 1),
        background: colorFromJson(json["bg"], const Color(0xFF0B0F14)),
        foreground: colorFromJson(json["fg"], const Color(0xFF2FE08A)),
        accent: colorFromJson(json["accent"], const Color(0xFFDFFFF0)),
        gradient: json["gradient"] is Map
            ? GradientSpec.fromJson(
                (json["gradient"] as Map).cast<String, dynamic>())
            : null,
        foregroundFade: json["fgFade"] is Map
            ? GradientSpec.fromJson(
                (json["fgFade"] as Map).cast<String, dynamic>())
            : null,
        accentFade: json["accentFade"] is Map
            ? GradientSpec.fromJson(
                (json["accentFade"] as Map).cast<String, dynamic>())
            : null,
        density: jsonDouble(json["density"], 0.5).clamp(0.0, 1.0),
        scale: jsonDouble(json["scale"], 0.05).clamp(0.002, 0.5),
        intensity: jsonDouble(json["intensity"], 0.8).clamp(0.0, 1.0),
        variation: jsonDouble(json["variation"], 0.5).clamp(0.0, 1.0),
        rotation: jsonDouble(json["rotation"], 0).clamp(-3600.0, 3600.0),
        glyphs: jsonString(json["glyphs"], defaultGlyphs),
        animated: jsonBool(json["animated"], false),
        speed: jsonDouble(json["speed"], 1).clamp(-100.0, 100.0),
        passFrames: jsonInt(json["passFrames"], 120).clamp(1, 100000),
        loopTimes: jsonInt(json["loopTimes"], 0).clamp(0, 100000),
        loopGap: jsonInt(json["loopGap"], 0).clamp(0, 100000),
        pauseAt: jsonInt(json["pauseAt"], 0).clamp(0, 100000),
        pauseFor: jsonInt(json["pauseFor"], 0).clamp(0, 100000),
        pauseEase: jsonInt(json["pauseEase"], 6).clamp(0, 1000),
        loopFrames: jsonInt(json["loopFrames"], 0).clamp(0, 100000),
        loopBlend: jsonDouble(json["loopBlend"], 0.3).clamp(0.02, 1.0),
        sport: PitchSport.fromName(jsonString(json["sport"], "")),
        rings: json["rings"] is Map
            ? RingSpec.fromJson((json["rings"] as Map).cast<String, dynamic>())
            : const RingSpec(),
        light: json["light"] is Map
            ? LightSpec.fromJson((json["light"] as Map).cast<String, dynamic>())
            : const LightSpec(),
        metal: json["metal"] is Map
            ? MetalSpec.fromJson((json["metal"] as Map).cast<String, dynamic>())
            : const MetalSpec(),
        vignette: jsonDouble(json["vignette"], 0.25).clamp(0.0, 1.0),
        effects: json["effects"] is Map
            ? EffectsSpec.fromJson(
                (json["effects"] as Map).cast<String, dynamic>())
            : const EffectsSpec(),
        params: json["params"] is Map
            ? {
                for (var MapEntry(:key, :value)
                    in (json["params"] as Map).entries)
                  if (value is num && value.isFinite) "$key": value.toDouble(),
              }
            : const {},
        layers: json["layers"] is List
            ? [
                for (var l
                    in (json["layers"] as List).take(maxBackgroundLayers))
                  if (l is Map)
                    BackgroundLayer.fromJson(l.cast<String, dynamic>()),
              ]
            : const [],
      );
}
