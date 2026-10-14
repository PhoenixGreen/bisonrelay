import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';

// image_effects.dart is what is done to a layer as it is drawn -- a shadow
// under it, a glow round it, a blur through it -- and what a texture layer
// draws: grain, paper, grunge, a vignette.
//
// Both are settings listed per kind, as adjustments are (see AdjustParam), so
// the panel is built from the lists and a document holds only what was moved.
//
// Distances are thousandths of the frame's shorter side, as a picture layer's
// place is in thousandths of the frame: a shadow stays the same shadow when
// the poster is drawn twice the size.

/// EffectKind is something done to a layer as it is drawn.
enum EffectKind {
  dropShadow("Drop shadow", [
    AdjustParam("angle", "Angle", 0, 360, 135, percent: false),
    AdjustParam("distance", "Distance", 0, 200, 12, percent: false),
    AdjustParam("blur", "Blur", 0, 200, 18, percent: false),
    AdjustParam("spread", "Spread", 0, 100, 0, percent: false),
    AdjustParam("opacity", "Opacity", 0, 1, 0.6),
  ]),
  outerGlow("Outer glow", [
    AdjustParam("size", "Size", 0, 200, 30, percent: false),
    AdjustParam("spread", "Spread", 0, 100, 6, percent: false),
    AdjustParam("opacity", "Opacity", 0, 1, 0.8),
  ]),
  innerShadow("Inner shadow", [
    AdjustParam("angle", "Angle", 0, 360, 135, percent: false),
    AdjustParam("distance", "Distance", 0, 200, 8, percent: false),
    AdjustParam("blur", "Blur", 0, 200, 14, percent: false),
    AdjustParam("opacity", "Opacity", 0, 1, 0.6),
  ]),
  blur("Blur", [
    AdjustParam("amount", "Amount", 0, 200, 8, percent: false),
  ]),
  motionBlur("Motion blur", [
    AdjustParam("angle", "Angle", 0, 360, 0, percent: false),
    AdjustParam("distance", "Distance", 0, 400, 40, percent: false),
  ]),
  zoomBlur("Zoom blur", [
    AdjustParam("amount", "Amount", 0, 1, 0.15),
    AdjustParam("x", "Across", 0, 1, 0.5),
    AdjustParam("y", "Down", 0, 1, 0.5),
  ]),
  fringe("Colour fringe", [
    AdjustParam("angle", "Angle", 0, 360, 0, percent: false),
    AdjustParam("distance", "Distance", 0, 60, 4, percent: false),
  ]);

  final String label;
  final List<AdjustParam> params;
  const EffectKind(this.label, this.params);

  static EffectKind fromName(String? name) => values
      .firstWhere((k) => k.name == name, orElse: () => EffectKind.dropShadow);

  /// behind is whether the effect is drawn under the layer rather than
  /// done to it.
  bool get behind => this == dropShadow || this == outerGlow;

  bool get usesColour =>
      this == dropShadow || this == outerGlow || this == innerShadow;

  Color get startColour =>
      this == outerGlow ? const Color(0xFFFFE9A8) : const Color(0xFF000000);
}

/// LayerEffect is one effect on a layer.
class LayerEffect {
  final EffectKind kind;
  final bool on;
  final Map<String, double> values;
  final Color? _colour;

  const LayerEffect({
    required this.kind,
    this.on = true,
    this.values = const {},
    Color? colour,
  }) : _colour = colour;

  Color get colour => _colour ?? kind.startColour;

  double value(String key) {
    var given = values[key];
    if (given != null) return given;
    for (var p in kind.params) {
      if (p.key == key) return p.initial;
    }
    return 0;
  }

  LayerEffect copyWith({bool? on, Map<String, double>? values, Color? colour}) =>
      LayerEffect(
          kind: kind,
          on: on ?? this.on,
          values: values ?? this.values,
          colour: colour ?? _colour);

  LayerEffect withValue(String key, double v) {
    for (var p in kind.params) {
      if (p.key == key) v = v.clamp(p.min, p.max).toDouble();
    }
    return copyWith(values: {...values, key: v});
  }

  Map<String, dynamic> toJson() => {
        "k": kind.name,
        if (!on) "off": true,
        if (values.isNotEmpty) "v": values,
        if (_colour != null) "c": colorToJson(_colour),
      };

  factory LayerEffect.fromJson(Map<String, dynamic> json) => LayerEffect(
        kind: EffectKind.fromName(json["k"] as String?),
        on: !jsonBool(json["off"], false),
        values: _numbers(json["v"]),
        colour: json["c"] == null ? null : colorFromJson(json["c"]),
      );
}

Map<String, double> _numbers(Object? raw) => {
      if (raw is Map)
        for (var e in raw.entries)
          if (e.key is String && e.value is num)
            e.key as String: (e.value as num).toDouble()
    };

/// TextureKind is what a texture layer draws. [mode] is the texture
/// shader's mode, as an adjustment's is.
enum TextureKind {
  grain("Film grain", 0, "overlay", [
    AdjustParam("size", "Size", 0.5, 20, 1.5, decimals: 1, percent: false),
    AdjustParam("amount", "Amount", 0, 1, 0.4),
    AdjustParam("colourful", "Colour", 0, 1, 0),
  ]),
  paper("Paper", 1, "multiply", [
    AdjustParam("scale", "Scale", 5, 400, 60, percent: false),
    AdjustParam("fibres", "Fibres", 0, 1, 0.5),
    AdjustParam("amount", "Amount", 0, 1, 0.5),
  ]),
  grunge("Grunge", 2, "multiply", [
    AdjustParam("scale", "Scale", 5, 600, 120, percent: false),
    AdjustParam("cover", "Cover", 0, 1, 0.35),
    AdjustParam("roughness", "Roughness", 0, 1, 0.6),
  ]),
  dust("Dust and scratches", 3, "screen", [
    AdjustParam("specks", "Specks", 0, 1, 0.3),
    AdjustParam("scratches", "Scratches", 0, 1, 0.3),
    AdjustParam("size", "Size", 0.5, 10, 2, decimals: 1, percent: false),
  ]),
  vignette("Vignette", 4, "multiply", [
    AdjustParam("radius", "Radius", 0, 1, 0.55),
    AdjustParam("softness", "Softness", 0, 1, 0.5),
    AdjustParam("roundness", "Roundness", 0, 1, 0.5),
  ]),
  lightLeak("Light leak", 5, "screen", [
    AdjustParam("size", "Size", 0, 1, 0.5),
    AdjustParam("softness", "Softness", 0, 1, 0.7),
    AdjustParam("strength", "Strength", 0, 1, 0.8),
  ]),
  halftone("Halftone dots", 6, "multiply", [
    AdjustParam("cell", "Cell", 2, 100, 10, percent: false),
    AdjustParam("angle", "Angle", 0, 90, 45, percent: false),
    AdjustParam("dot", "Dot", 0, 1, 0.4),
  ]),
  lines("Scan lines", 7, "multiply", [
    AdjustParam("spacing", "Spacing", 1, 100, 6, percent: false),
    AdjustParam("thickness", "Thickness", 0, 1, 0.4),
    AdjustParam("angle", "Angle", 0, 180, 0, percent: false),
  ]);

  final String label;
  final int mode;

  /// blend is the blend a new layer of this texture starts with, by name --
  /// grain lies over a picture, paper under its colours.
  final String blend;
  final List<AdjustParam> params;
  const TextureKind(this.label, this.mode, this.blend, this.params);

  static TextureKind fromName(String? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => TextureKind.grain);

  Color get startColour => switch (this) {
        paper => const Color(0xFFE9DFCB),
        grunge => const Color(0xFF3B3226),
        dust => const Color(0xFFFFFFFF),
        vignette => const Color(0xFF000000),
        lightLeak => const Color(0xFFFF7A2E),
        halftone || lines => const Color(0xFF1A1A1A),
        grain => const Color(0xFF808080),
      };

  Color get startSecond => this == lightLeak
      ? const Color(0xFFFFD25E)
      : const Color(0xFFFFFFFF);

  bool get usesColour => this != grain;
  bool get usesSecond => this == lightLeak;
}

/// TextureSpec is what a texture layer draws.
class TextureSpec {
  final TextureKind kind;
  final Map<String, double> values;
  final Color? _colour, _second;

  /// seed picks which grain, which blotches, which leak: the same seed draws
  /// the same texture every time.
  final int seed;

  const TextureSpec({
    this.kind = TextureKind.grain,
    this.values = const {},
    Color? colour,
    Color? second,
    this.seed = 1,
  })  : _colour = colour,
        _second = second;

  Color get colour => _colour ?? kind.startColour;
  Color get second => _second ?? kind.startSecond;

  double value(String key) {
    var given = values[key];
    if (given != null) return given;
    for (var p in kind.params) {
      if (p.key == key) return p.initial;
    }
    return 0;
  }

  TextureSpec copyWith({
    TextureKind? kind,
    Map<String, double>? values,
    Color? colour,
    Color? second,
    int? seed,
    bool plainColours = false,
  }) =>
      TextureSpec(
        kind: kind ?? this.kind,
        values: values ?? this.values,
        colour: plainColours ? null : colour ?? _colour,
        second: plainColours ? null : second ?? _second,
        seed: seed ?? this.seed,
      );

  TextureSpec withValue(String key, double v) {
    for (var p in kind.params) {
      if (p.key == key) v = v.clamp(p.min, p.max).toDouble();
    }
    return copyWith(values: {...values, key: v});
  }

  Map<String, dynamic> toJson() => {
        "k": kind.name,
        if (values.isNotEmpty) "v": values,
        if (_colour != null) "c": colorToJson(_colour),
        if (_second != null) "c2": colorToJson(_second),
        if (seed != 1) "seed": seed,
      };

  factory TextureSpec.fromJson(Map<String, dynamic> json) => TextureSpec(
        kind: TextureKind.fromName(json["k"] as String?),
        values: _numbers(json["v"]),
        colour: json["c"] == null ? null : colorFromJson(json["c"]),
        second: json["c2"] == null ? null : colorFromJson(json["c2"]),
        seed: jsonDouble(json["seed"], 1).round(),
      );
}
