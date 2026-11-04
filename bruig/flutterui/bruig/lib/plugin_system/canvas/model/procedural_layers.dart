import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/layer_blend.dart';

export 'package:bruig/plugin_system/canvas/model/layer_blend.dart'
    show LayerBlend;

// procedural_layers.dart is the patterns laid over a background's own. Each
// layer is a whole background recipe, laid on with an opacity and a blend.

/// maxBackgroundLayers is how many layers can be laid over a background.
const int maxBackgroundLayers = 3;

/// BackgroundLayer is one pattern laid over a background.
///
/// Only the pattern of its [spec] is drawn: the base colour (except for a
/// plain layer, whose base is all it has), light and effects are the
/// background's. It keeps the background's time at its own speed.
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
        blend: LayerBlend.fromName(jsonStr(json["blend"])),
        visible: !jsonBool(json["hidden"], false),
      );
}
