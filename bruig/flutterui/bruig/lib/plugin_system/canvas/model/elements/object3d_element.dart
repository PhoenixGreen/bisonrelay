import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/glb_info.dart';

// object3d_element.dart is a 3D object: a model from the library's 3D
// objects -- a .glb -- drawn in its box, or standing on a 3D stage as
// anything can (see StageSpot). Turned, tilted and brought closer in its
// box; its own animations, read from the file, are its clips: "From the
// model", in its slots, played, placed and layered as any clip is.

/// Object3dElement is a 3D object; see the top of this file.
class Object3dElement extends CanvasElement {
  /// assetId is the model in the library's store, or "" for none yet.
  final String assetId;

  /// animations are the model's own, as the file has them: what its clips
  /// can play.
  final List<ModelAnimation> animations;

  /// turn and tilt are how it is seen in its box, in degrees: round to its
  /// right, and from above. zoom is how close, 1 fitting it whole.
  final double turn, tilt, zoom;

  const Object3dElement(super.base,
      {this.assetId = "",
      this.animations = const [],
      this.turn = 25,
      this.tilt = 12,
      this.zoom = 1});

  @override
  ElementKind get kind => ElementKind.object3d;

  /// mediaIds is its model, carried with the canvas when it is sent.
  @override
  Set<String> get mediaIds => assetId.isEmpty ? const {} : {assetId};

  @override
  CanvasElement rebase(ElementBase base) => copyWith(base: base);

  Object3dElement copyWith({
    ElementBase? base,
    String? assetId,
    List<ModelAnimation>? animations,
    double? turn,
    double? tilt,
    double? zoom,
  }) =>
      Object3dElement(base ?? this.base,
          assetId: assetId ?? this.assetId,
          animations: animations ?? this.animations,
          turn: turn ?? this.turn,
          tilt: (tilt ?? this.tilt).clamp(-89.0, 89.0),
          zoom: (zoom ?? this.zoom).clamp(0.2, 8.0));

  @override
  Map<String, dynamic> props() => {
        if (assetId.isNotEmpty) "asset": assetId,
        if (animations.isNotEmpty)
          "anims": [
            for (var (name, length) in animations) [name, length]
          ],
        if (turn != 25) "turn": turn,
        if (tilt != 12) "tilt": tilt,
        if (zoom != 1) "zoom": zoom,
      };

  static Object3dElement fromJson(Map<String, dynamic> json, ElementBase base) {
    double n(String key, double or) =>
        json[key] is num ? (json[key] as num).toDouble() : or;
    return Object3dElement(base,
        assetId: json["asset"] is String ? json["asset"] as String : "",
        animations: [
          if (json["anims"] case List anims)
            for (var a in anims)
              if (a case [String name, num length]) (name, length.toDouble()),
        ],
        turn: n("turn", 25),
        tilt: n("tilt", 12).clamp(-89.0, 89.0),
        zoom: n("zoom", 1).clamp(0.2, 8.0));
  }
}
