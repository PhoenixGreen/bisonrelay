import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:flutter/painting.dart';

// procedural_layers.dart is the patterns laid over a background's own.
//
// One pattern on one ground is a starting point; the backgrounds people
// actually want are usually several things at once -- a mesh of colour with a
// faint grid over it, stars over a nebula over a gradient. Each layer is a
// whole background recipe of its own, laid on with an opacity and a blend.

/// LayerBlend is how a layer is combined with what is under it.
enum LayerBlend {
  normal("Normal", BlendMode.srcOver),
  screen("Screen", BlendMode.screen),
  add("Add", BlendMode.plus),
  multiply("Multiply", BlendMode.multiply),
  overlay("Overlay", BlendMode.overlay),
  softLight("Soft light", BlendMode.softLight),
  dodge("Dodge", BlendMode.colorDodge),
  lighten("Lighten", BlendMode.lighten),
  darken("Darken", BlendMode.darken),
  difference("Difference", BlendMode.difference),
  colour("Colour", BlendMode.color);

  final String label;
  final BlendMode mode;
  const LayerBlend(this.label, this.mode);

  static LayerBlend fromName(String? name) =>
      values.firstWhere((b) => b.name == name, orElse: () => LayerBlend.normal);
}

/// maxBackgroundLayers is how many layers can be laid over a background.
const int maxBackgroundLayers = 3;

/// BackgroundLayer is one pattern laid over a background.
///
/// Its [spec] is a whole recipe, but only the pattern of it is drawn: the
/// base colour is the background's -- except for a plain layer, whose base
/// is all it has -- and the light, the lens and the film over the finished
/// picture are the background's too. Its movement keeps the background's
/// time, at the layer's own speed.
class BackgroundLayer {
  final ProceduralSpec spec;
  final double opacity;
  final LayerBlend blend;
  final bool visible;

  const BackgroundLayer({
    required this.spec,
    this.opacity = 1,
    this.blend = LayerBlend.normal,
    this.visible = true,
  });

  BackgroundLayer copyWith({
    ProceduralSpec? spec,
    double? opacity,
    LayerBlend? blend,
    bool? visible,
  }) =>
      BackgroundLayer(
        spec: spec ?? this.spec,
        opacity: opacity ?? this.opacity,
        blend: blend ?? this.blend,
        visible: visible ?? this.visible,
      );

  Map<String, dynamic> toJson() => {
        // A layer's own layers are not drawn, so they are not kept.
        "spec": spec.copyWith(layers: const []).toJson(),
        if (opacity != 1) "opacity": opacity,
        if (blend != LayerBlend.normal) "blend": blend.name,
        if (!visible) "hidden": true,
      };

  factory BackgroundLayer.fromJson(Map<String, dynamic> json) =>
      BackgroundLayer(
        spec: json["spec"] is Map
            ? ProceduralSpec.fromJson(
                    (json["spec"] as Map).cast<String, dynamic>())
                .copyWith(layers: const [])
            : const ProceduralSpec(),
        opacity: jsonDouble(json["opacity"], 1).clamp(0.0, 1.0),
        blend: LayerBlend.fromName(json["blend"] as String?),
        visible: !jsonBool(json["hidden"], false),
      );
}
