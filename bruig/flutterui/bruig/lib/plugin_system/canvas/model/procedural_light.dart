import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// procedural_light.dart is the light thrown across a generated background.
//
// It is drawn over the finished pattern rather than known to each generator,
// so it works on every style and a new style needs no lighting code.

/// LightSpec is one light (a spotlight) over a background.
class LightSpec {
  /// on is whether there is a light at all. Off by default.
  final bool on;

  /// color is the colour of the light itself, not the surface.
  final Color color;

  /// brightness is how strong it is. Past one it burns towards white.
  final double brightness;

  /// size is the pool's radius as a fraction of the longer side, so it holds
  /// at any export width.
  final double size;

  /// falloff is how sharply the light stops: 0 is a pool that fades all the
  /// way out from the middle, 1 is a hard-edged circle of light.
  final double falloff;

  /// x and y are where it is, from 0 at the left and top to 1 at the right
  /// and bottom.
  final double x;
  final double y;

  /// direction is which way the light is thrown, as a compass bearing in
  /// degrees (0 up the page, 90 to the right). It shows only with [reach]: a
  /// light shone straight on lands as a circle whichever way it points.
  final double direction;

  /// reach is how far the light rakes: 0 is straight on and lands as a round
  /// pool, 1 is almost along the surface and throws a long one.
  ///
  /// The pool is thrown forward from [x], [y] rather than growing both ways,
  /// so those place the near edge of the light, not its middle.
  final double reach;

  const LightSpec({
    this.on = false,
    this.color = const Color(0xFFFFF2D0),
    this.brightness = 0.8,
    this.size = 0.45,
    this.falloff = 0.35,
    this.x = 0.5,
    this.y = 0.3,
    this.direction = 180,
    this.reach = 0,
  });

  LightSpec copyWith({
    bool? on,
    Color? color,
    double? brightness,
    double? size,
    double? falloff,
    double? x,
    double? y,
    double? direction,
    double? reach,
  }) =>
      LightSpec(
        on: on ?? this.on,
        color: color ?? this.color,
        brightness: brightness ?? this.brightness,
        size: size ?? this.size,
        falloff: falloff ?? this.falloff,
        x: x ?? this.x,
        y: y ?? this.y,
        direction: direction ?? this.direction,
        reach: reach ?? this.reach,
      );

  Map<String, dynamic> toJson() => {
        "on": on,
        "color": colorToJson(color),
        "brightness": brightness,
        "size": size,
        "falloff": falloff,
        "x": x,
        "y": y,
        "direction": direction,
        "reach": reach,
      };

  factory LightSpec.fromJson(Map<String, dynamic> json) => LightSpec(
        on: jsonBool(json["on"], false),
        color: colorFromJson(json["color"], const Color(0xFFFFF2D0)),
        brightness: jsonDouble(json["brightness"], 0.8).clamp(0.0, 2.0),
        size: jsonDouble(json["size"], 0.45).clamp(0.01, 3.0),
        falloff: jsonDouble(json["falloff"], 0.35).clamp(0.0, 1.0),
        x: jsonDouble(json["x"], 0.5).clamp(-1.0, 2.0),
        y: jsonDouble(json["y"], 0.3).clamp(-1.0, 2.0),
        direction: jsonDouble(json["direction"], 180),
        reach: jsonDouble(json["reach"], 0).clamp(0.0, 1.0),
      );
}

/// MetalSpec is the Metal texture background's own settings.
///
/// The colours are the shared ones: the base colour is the metal, the main
/// colour the sheen along the brushing, and the accent the rust.
class MetalSpec {
  /// roughness is how coarse the brushing is: 0 is a poured, almost glassy
  /// sheet and 1 is heavily ground.
  final double roughness;

  /// rust is how far the corrosion has spread, from none to eaten through.
  final double rust;

  /// damage is the knocks: scratches across the grain and dents in it.
  final double damage;

  /// shine is polished against matt: the width and strength of the highlight
  /// along the sheet.
  final double shine;

  const MetalSpec({
    this.roughness = 0.45,
    this.rust = 0,
    this.damage = 0.15,
    this.shine = 0.55,
  });

  MetalSpec copyWith({
    double? roughness,
    double? rust,
    double? damage,
    double? shine,
  }) =>
      MetalSpec(
        roughness: roughness ?? this.roughness,
        rust: rust ?? this.rust,
        damage: damage ?? this.damage,
        shine: shine ?? this.shine,
      );

  Map<String, dynamic> toJson() => {
        "roughness": roughness,
        "rust": rust,
        "damage": damage,
        "shine": shine,
      };

  factory MetalSpec.fromJson(Map<String, dynamic> json) => MetalSpec(
        roughness: jsonDouble(json["roughness"], 0.45).clamp(0.0, 1.0),
        rust: jsonDouble(json["rust"], 0).clamp(0.0, 1.0),
        damage: jsonDouble(json["damage"], 0.15).clamp(0.0, 1.0),
        shine: jsonDouble(json["shine"], 0.55).clamp(0.0, 1.0),
      );
}
