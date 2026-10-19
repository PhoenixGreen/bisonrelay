import 'package:flutter/painting.dart';

// layer_blend.dart is how one thing is laid over what is under it: a
// picture's layer, a video over the scene, a pattern over a background.
// One list for all three, so a blend learned in one panel is the same blend,
// called the same thing, in the others.

/// LayerBlend is how a layer is laid over what is under it.
enum LayerBlend {
  normal("Normal", BlendMode.srcOver),
  darken("Darken", BlendMode.darken),
  multiply("Multiply", BlendMode.multiply),
  colorBurn("Colour burn", BlendMode.colorBurn),
  lighten("Lighten", BlendMode.lighten),
  screen("Screen", BlendMode.screen),
  colorDodge("Colour dodge", BlendMode.colorDodge),
  add("Add", BlendMode.plus),
  overlay("Overlay", BlendMode.overlay),
  softLight("Soft light", BlendMode.softLight),
  hardLight("Hard light", BlendMode.hardLight),
  difference("Difference", BlendMode.difference),
  exclusion("Exclusion", BlendMode.exclusion),
  hue("Hue", BlendMode.hue),
  saturation("Saturation", BlendMode.saturation),
  colour("Colour", BlendMode.color),
  luminosity("Luminosity", BlendMode.luminosity);

  final String label;
  final BlendMode flutter;
  const LayerBlend(this.label, this.flutter);

  /// lightens is whether the blend only ever brightens what is under it --
  /// so a layer laid by it shows where it is bright, not where it is drawn,
  /// and an effect that follows its outline should follow its brightness.
  bool get lightens =>
      this == screen || this == add || this == lighten || this == colorDodge;

  static LayerBlend fromName(String? name) => switch (name) {
        // A background layer's dodge, saved before there was one list.
        "dodge" => colorDodge,
        _ => values.firstWhere((b) => b.name == name, orElse: () => normal),
      };
}
