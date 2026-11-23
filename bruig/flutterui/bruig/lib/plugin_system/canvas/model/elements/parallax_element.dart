import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
// cameraChannel: the same "cam." channels a stage's camera is keyed on.
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart'
    show cameraChannel;
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';

// parallax_element.dart is a parallax background: layers of scenery each
// moving a different amount with the camera, after Godot's Parallax2D (a
// scroll scale, a repeat, an autoscroll). Like a stage it is a kind of
// background (backdrop.dart), carried by the canvas's background or a
// Background element; its camera is keyed as "cam." channels on the
// carrier's track, which stay keyframes when tracks become clips.

/// ParallaxCamera is where the camera is looking: how far it has travelled
/// across and down the scene, in design units, and how far it is zoomed in.
class ParallaxCamera {
  final double x;
  final double y;
  final double zoom;

  const ParallaxCamera({this.x = 0, this.y = 0, this.zoom = 1});

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = ParallaxCamera();

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
        x: jsonDouble(json["x"], _defaults.x),
        y: jsonDouble(json["y"], _defaults.y),
        zoom: jsonDouble(json["zoom"], _defaults.zoom));
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

  /// drawn is whether it is drawn from settings, not a picture or pattern.
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
  /// camera moves: Godot's scroll scale. 0 is pinned to the screen, 1 the
  /// ground the camera travels over, more than 1 passing in front.
  final double scrollX;
  final double scrollY;

  /// repeatX and repeatY are whether it goes on for ever that way.
  final bool repeatX;
  final bool repeatY;

  /// autoX and autoY are its own drift, in design units a second.
  final double autoX;
  final double autoY;

  /// loopDrift evens that drift to a whole number of tiles each time the
  /// timeline loops, so a cloud comes back where it was rather than jumping.
  final bool loopDrift;

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
    this.loopDrift = true,
    this.offset = Offset.zero,
    this.size = 1,
    this.anchor = LayerAnchor.bottom,
    this.opacity = 1,
    this.visible = true,
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = ParallaxLayer();

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
    bool? loopDrift,
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
        loopDrift: loopDrift ?? this.loopDrift,
        offset: offset ?? this.offset,
        size: (size ?? this.size).clamp(0.1, 8.0),
        anchor: anchor ?? this.anchor,
        opacity: (opacity ?? this.opacity).clamp(0.0, 1.0),
        visible: visible ?? this.visible,
      );

  /// mapColours maps the layer's two colours, shown only for scenery drawn
  /// from settings, and its pattern, shown only for a pattern layer; all
  /// hidden while the layer is hidden or wholly faded. Its two colours are
  /// saved for every kind, its pattern only for a pattern layer.
  ParallaxLayer mapColours(ColourMap f) {
    var g = f.shownOnlyIf(visible && opacity > 0);
    var p = ColourPass(g);
    var color = p(this.color, shown: kind.drawn);
    var color2 = p(this.color2, shown: kind.drawn);
    var spec = p.part(this.spec,
        (s) => s.mapColours(g.shownOnlyIf(kind == SceneryKind.pattern)));
    if (!p.changed) return this;
    return copyWith(color: color, color2: color2, spec: spec);
  }

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
      if (autoX != _defaults.autoX) "autoX": autoX,
      if (autoY != _defaults.autoY) "autoY": autoY,
      if (!loopDrift) "freeDrift": true,
      if (offset != _defaults.offset) "offset": [offset.dx, offset.dy],
      if (size != _defaults.size) "size": size,
      "anchor": anchor.name,
      if (opacity != _defaults.opacity) "opacity": opacity,
      if (!visible) "visible": false,
    };
  }

  factory ParallaxLayer.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const ParallaxLayer();
    const d = ParallaxLayer();
    var off = json["offset"];
    return d.copyWith(
      name: jsonString(json["name"], _defaults.name),
      kind: SceneryKind.fromName(jsonStr(json["kind"])),
      color: colorFromJson(json["color"], d.color),
      color2: colorFromJson(json["color2"], d.color2),
      height: jsonDouble(json["height"], d.height),
      amount: jsonDouble(json["amount"], d.amount),
      seed: jsonInt(json["seed"], d.seed),
      assetId: jsonString(json["asset"], _defaults.assetId),
      spec: jsonSpec(json["spec"], ProceduralSpec.fromJson, _defaults.spec),
      scrollX: jsonDouble(json["scrollX"], d.scrollX),
      scrollY: jsonDouble(json["scrollY"], d.scrollY),
      repeatX: jsonBool(json["repeatX"], d.repeatX),
      repeatY: jsonBool(json["repeatY"], d.repeatY),
      autoX: jsonDouble(json["autoX"], _defaults.autoX),
      autoY: jsonDouble(json["autoY"], _defaults.autoY),
      loopDrift: json["freeDrift"] != true,
      offset: off is List && off.length == 2 && off[0] is num && off[1] is num
          ? Offset((off[0] as num).toDouble(), (off[1] as num).toDouble())
          : Offset.zero,
      // As copyWith holds it: a tiny received size is thousands of tiles.
      size: jsonDouble(json["size"], _defaults.size).clamp(0.1, 8).toDouble(),
      anchor: LayerAnchor.fromName(jsonStr(json["anchor"])),
      opacity: jsonDouble(json["opacity"], _defaults.opacity),
      visible: jsonBool(json["visible"], true),
    );
  }
}

/// maxParallaxLayers is as many layers as one parallax background has.
const int maxParallaxLayers = 12;

/// ParallaxElement is a parallax background: camera and layers.
class ParallaxElement extends CanvasElement {
  final ParallaxCamera camera;
  final List<ParallaxLayer> layers;

  const ParallaxElement(super.base,
      {this.camera = const ParallaxCamera(), this.layers = const []});

  @override
  ElementKind get kind => ElementKind.parallax;

  /// cameraAt is the camera on [frame], with what the track keys over it.
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

  @override
  ParallaxElement mapOwnColours(ColourMap f) {
    var next = mappedList(layers, (l) => l.mapColours(f));
    return identical(next, layers) ? this : copyWith(layers: next);
  }

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
