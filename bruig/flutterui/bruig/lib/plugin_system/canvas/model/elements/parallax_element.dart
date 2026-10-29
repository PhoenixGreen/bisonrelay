import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
// cameraChannel: the same "cam." channels a stage's camera is keyed on, so
// the rules for keying a camera serve both.
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart'
    show cameraChannel;
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';

// parallax_element.dart is a parallax background: layers of scenery, each
// moving a different amount when the camera does, so the far hills slide
// slowly behind the near trees and the picture has depth.
//
// The model is Godot's Parallax2D. Each layer has a scroll scale -- how far
// it moves for each pixel the camera moves, 0 for a sky pinned to the screen,
// 1 for the ground the camera is travelling over, more than 1 for things
// passing in front -- a repeat, so that it goes on for ever, and an
// autoscroll, for clouds that drift whether or not the camera moves.
//
// Like a stage, it is a kind of background (see backdrop.dart) rather than an
// element that can be added: the canvas's own background or a Background
// element carries one. Its camera is keyed the way a stage's is, as "cam."
// channels on the track of whatever carries it, so a pan across the scene is
// two keyframes.

/// ParallaxCamera is where the camera is looking: how far it has travelled
/// across and down the scene, in design units, and how far it is zoomed in.
class ParallaxCamera {
  final double x;
  final double y;
  final double zoom;

  const ParallaxCamera({this.x = 0, this.y = 0, this.zoom = 1});

  ParallaxCamera copyWith({double? x, double? y, double? zoom}) =>
      ParallaxCamera(
          x: x ?? this.x,
          y: y ?? this.y,
          zoom: (zoom ?? this.zoom).clamp(0.25, 8.0));

  ParallaxCamera over(Keyframe frame) {
    var v = frame.values;
    if (v.isEmpty) return this;
    return copyWith(
        x: v[cameraChannel("x")],
        y: v[cameraChannel("y")],
        zoom: v[cameraChannel("zoom")]);
  }

  Map<String, double> get channels => {
        cameraChannel("x"): x,
        cameraChannel("y"): y,
        cameraChannel("zoom"): zoom,
      };

  Map<String, dynamic> toJson() => {"x": x, "y": y, "zoom": zoom};

  factory ParallaxCamera.fromJson(Object? json) {
    if (json is! Map) return const ParallaxCamera();
    return const ParallaxCamera().copyWith(
        x: jsonDouble(json["x"], 0),
        y: jsonDouble(json["y"], 0),
        zoom: jsonDouble(json["zoom"], 1));
  }
}

/// SceneryKind is what one layer is: scenery drawn from its settings, a
/// picture, or one of the generated patterns.
enum SceneryKind {
  sky("Sky"),
  clouds("Clouds"),
  mountains("Mountains"),
  hills("Hills"),
  trees("Trees"),
  city("City"),
  ground("Ground"),
  picture("Picture"),
  pattern("Pattern");

  final String label;
  const SceneryKind(this.label);

  static SceneryKind fromName(String? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => hills);

  /// drawn is whether it is drawn from its own settings, rather than from a
  /// picture or a pattern.
  bool get drawn => this != picture && this != pattern;

  /// silhouette is whether it is a shape standing on the bottom of its band:
  /// what [ParallaxLayer.height] is the height of.
  bool get silhouette =>
      this == mountains ||
      this == hills ||
      this == trees ||
      this == city ||
      this == ground;
}

/// LayerAnchor is where a layer sits in the page when it is shorter than
/// it: along the bottom, as hills and ground do, the top, or over all of it.
enum LayerAnchor {
  fill("Fill"),
  bottom("Bottom"),
  top("Top");

  final String label;
  const LayerAnchor(this.label);

  static LayerAnchor fromName(String? name) =>
      values.firstWhere((a) => a.name == name, orElse: () => fill);
}

/// ParallaxLayer is one layer of the scenery.
class ParallaxLayer {
  final String name;
  final SceneryKind kind;

  /// color and color2 are its colours: a silhouette's fill and the haze at
  /// its top; a sky's top and its horizon; the clouds' light and shade.
  final Color color;
  final Color color2;

  /// height is how tall a silhouette stands, as a share of the page; amount
  /// is how rough a ridge is, how many trees or buildings, how many clouds.
  final double height;
  final double amount;
  final int seed;

  /// assetId is a picture layer's picture; spec a pattern layer's pattern.
  final String assetId;
  final ProceduralSpec spec;

  /// scrollX and scrollY are how far it moves for each design unit the
  /// camera moves: Godot's scroll scale.
  final double scrollX;
  final double scrollY;

  /// repeatX and repeatY are whether it goes on for ever that way.
  final bool repeatX;
  final bool repeatY;

  /// autoX and autoY are how fast it drifts by itself, in design units a
  /// second.
  final double autoX;
  final double autoY;

  /// offset moves it from where it would be, in design units.
  final Offset offset;

  /// size scales its tile: one page across, times this.
  final double size;
  final LayerAnchor anchor;
  final double opacity;
  final bool visible;

  const ParallaxLayer({
    this.name = "",
    this.kind = SceneryKind.hills,
    this.color = const Color(0xFF6A9C5A),
    this.color2 = const Color(0xFFB7D7A8),
    this.height = 0.35,
    this.amount = 0.5,
    this.seed = 1,
    this.assetId = "",
    this.spec = const ProceduralSpec(),
    this.scrollX = 0.5,
    this.scrollY = 0.5,
    this.repeatX = true,
    this.repeatY = false,
    this.autoX = 0,
    this.autoY = 0,
    this.offset = Offset.zero,
    this.size = 1,
    this.anchor = LayerAnchor.bottom,
    this.opacity = 1,
    this.visible = true,
  });

  String get title => name.isNotEmpty ? name : kind.label;

  ParallaxLayer copyWith({
    String? name,
    SceneryKind? kind,
    Color? color,
    Color? color2,
    double? height,
    double? amount,
    int? seed,
    String? assetId,
    ProceduralSpec? spec,
    double? scrollX,
    double? scrollY,
    bool? repeatX,
    bool? repeatY,
    double? autoX,
    double? autoY,
    Offset? offset,
    double? size,
    LayerAnchor? anchor,
    double? opacity,
    bool? visible,
  }) =>
      ParallaxLayer(
        name: name ?? this.name,
        kind: kind ?? this.kind,
        color: color ?? this.color,
        color2: color2 ?? this.color2,
        height: (height ?? this.height).clamp(0.02, 1.0),
        amount: (amount ?? this.amount).clamp(0.0, 1.0),
        seed: seed ?? this.seed,
        assetId: assetId ?? this.assetId,
        spec: spec ?? this.spec,
        scrollX: (scrollX ?? this.scrollX).clamp(-4.0, 4.0),
        scrollY: (scrollY ?? this.scrollY).clamp(-4.0, 4.0),
        repeatX: repeatX ?? this.repeatX,
        repeatY: repeatY ?? this.repeatY,
        autoX: autoX ?? this.autoX,
        autoY: autoY ?? this.autoY,
        offset: offset ?? this.offset,
        size: (size ?? this.size).clamp(0.1, 8.0),
        anchor: anchor ?? this.anchor,
        opacity: (opacity ?? this.opacity).clamp(0.0, 1.0),
        visible: visible ?? this.visible,
      );

  Map<String, dynamic> toJson() {
    const d = ParallaxLayer();
    return {
      if (name.isNotEmpty) "name": name,
      "kind": kind.name,
      "color": colorToJson(color),
      "color2": colorToJson(color2),
      "height": height,
      "amount": amount,
      "seed": seed,
      if (assetId.isNotEmpty) "asset": assetId,
      if (kind == SceneryKind.pattern) "spec": spec.toJson(),
      "scrollX": scrollX,
      "scrollY": scrollY,
      if (repeatX != d.repeatX) "repeatX": repeatX,
      if (repeatY != d.repeatY) "repeatY": repeatY,
      if (autoX != 0) "autoX": autoX,
      if (autoY != 0) "autoY": autoY,
      if (offset != Offset.zero) "offset": [offset.dx, offset.dy],
      if (size != 1) "size": size,
      "anchor": anchor.name,
      if (opacity != 1) "opacity": opacity,
      if (!visible) "visible": false,
    };
  }

  factory ParallaxLayer.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const ParallaxLayer();
    const d = ParallaxLayer();
    var off = json["offset"];
    return d.copyWith(
      name: jsonString(json["name"], ""),
      kind: SceneryKind.fromName(json["kind"] as String?),
      color: colorFromJson(json["color"], d.color),
      color2: colorFromJson(json["color2"], d.color2),
      height: jsonDouble(json["height"], d.height),
      amount: jsonDouble(json["amount"], d.amount),
      seed: jsonInt(json["seed"], d.seed),
      assetId: jsonString(json["asset"], ""),
      spec: jsonSpec(
          json["spec"], ProceduralSpec.fromJson, const ProceduralSpec()),
      scrollX: jsonDouble(json["scrollX"], d.scrollX),
      scrollY: jsonDouble(json["scrollY"], d.scrollY),
      repeatX: jsonBool(json["repeatX"], d.repeatX),
      repeatY: jsonBool(json["repeatY"], d.repeatY),
      autoX: jsonDouble(json["autoX"], 0),
      autoY: jsonDouble(json["autoY"], 0),
      offset: off is List && off.length == 2 && off[0] is num && off[1] is num
          ? Offset((off[0] as num).toDouble(), (off[1] as num).toDouble())
          : Offset.zero,
      size: jsonDouble(json["size"], 1),
      anchor: LayerAnchor.fromName(json["anchor"] as String?),
      opacity: jsonDouble(json["opacity"], 1),
      visible: jsonBool(json["visible"], true),
    );
  }
}

/// maxParallaxLayers is as many layers as one parallax background has.
const int maxParallaxLayers = 12;

/// ParallaxElement is a parallax background's settings: its camera and its
/// layers, back to front.
class ParallaxElement extends CanvasElement {
  final ParallaxCamera camera;
  final List<ParallaxLayer> layers;

  const ParallaxElement(super.base,
      {this.camera = const ParallaxCamera(), this.layers = const []});

  @override
  ElementKind get kind => ElementKind.parallax;

  /// cameraAt is the camera on [frame]: its own setting with whatever the
  /// track keys over it.
  ParallaxCamera cameraAt(int frame) => camera.over(poseAt(frame));

  /// moves is whether it is ever a different picture from one frame to the
  /// next: a keyed camera, a layer drifting, a pattern that moves.
  bool get moves =>
      (track?.keys.isNotEmpty ?? false) ||
      layers.any((l) =>
          l.visible &&
          (l.autoX != 0 ||
              l.autoY != 0 ||
              (l.kind == SceneryKind.pattern && l.spec.animated)));

  @override
  Set<String> get assetIds => {
        for (var l in layers)
          if (l.kind == SceneryKind.picture && l.assetId.isNotEmpty) l.assetId,
      };

  @override
  CanvasElement rebase(ElementBase base) =>
      ParallaxElement(base, camera: camera, layers: layers);

  ParallaxElement copyWith(
          {ParallaxCamera? camera, List<ParallaxLayer>? layers}) =>
      ParallaxElement(base,
          camera: camera ?? this.camera, layers: layers ?? this.layers);

  /// withLayer is this with layer [i] replaced.
  ParallaxElement withLayer(int i, ParallaxLayer layer) =>
      copyWith(layers: [...layers]..[i] = layer);

  @override
  Map<String, dynamic> props() => {
        "camera": camera.toJson(),
        "layers": [for (var l in layers) l.toJson()],
      };

  factory ParallaxElement.fromJson(Map<String, dynamic> json, ElementBase b) =>
      ParallaxElement(b,
          camera: ParallaxCamera.fromJson(json["camera"]),
          layers: [
            if (json["layers"] case List list)
              for (var l in list.take(maxParallaxLayers))
                ParallaxLayer.fromJson(l),
          ]);
}
