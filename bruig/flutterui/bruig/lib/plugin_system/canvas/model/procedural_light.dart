import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// procedural_light.dart is the light thrown across a generated background.
//
// Every style here is a flat field: a grid, a scatter, a set of marks, lit the
// same from edge to edge. That is what makes a generated background read as
// wallpaper rather than as a place -- and a single light is the cheapest thing
// there is that fixes it. A pool of warm light low on the left turns a plain
// gradient into a room; the same field of dots with a hard white spot on it
// turns into a stage.
//
// It is drawn over the finished pattern rather than being something each
// generator knows about, which is why it works on all of them and why adding
// a style does not mean writing lighting code again.

/// LightSpec is one light over a background.
///
/// A spotlight for now -- the light that has somewhere it is coming from, as
/// against an ambient wash, which is what the pattern's own brightness already
/// is. More kinds would be more of these, which is why what a light is told is
/// gathered here rather than spread across [ProceduralSpec] as seven more
/// fields that mean nothing to the other styles.
class LightSpec {
  /// on is whether there is a light at all. Off by default: an unasked-for
  /// light on every background in the app would change every one of them.
  final bool on;

  /// color is the light itself, not the surface. A warm light on a cold
  /// ground is most of what makes this worth having.
  final Color color;

  /// brightness is how strong it is. Past one it burns towards white, which
  /// is what an overexposed light does and what a hot spot on metal needs.
  final double brightness;

  /// size is the pool's radius as a fraction of the longer side, so a light
  /// set on a banner is in the same place and the same size when the same
  /// document is exported at four times the width.
  final double size;

  /// falloff is how sharply the light stops: 0 is a pool that fades all the
  /// way out from the middle, 1 is a hard-edged circle of light.
  final double falloff;

  /// x and y are where it is, from 0 at the left and top to 1 at the right
  /// and bottom. A fraction rather than pixels for the same reason [size] is
  /// one.
  final double x;
  final double y;

  /// direction is which way the light is thrown, in degrees off a compass --
  /// 0 up the page, 90 to the right -- the same way every other direction in
  /// a canvas is read.
  ///
  /// It means nothing on its own, which is what [reach] is for: a light shone
  /// straight at a surface lands as a circle whichever way it was pointed,
  /// and only a raking one has a direction you can see.
  final double direction;

  /// reach is how far the light rakes: 0 is straight on and lands as a round
  /// pool, 1 is almost along the surface and throws a long one.
  ///
  /// The pool is thrown *forward* from where the light is rather than growing
  /// both ways, so moving [x] and [y] moves the near edge of the light and
  /// not its middle. That is what makes a light at the top of the frame with
  /// a reach on it look like it is coming in from off the page.
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

/// MetalSpec is what the Metal texture background can be told.
///
/// Its own settings rather than the five every generator shares, for the same
/// reason a set of rings has its own: "more" and "bigger" are not the
/// questions anybody has about a sheet of metal. The questions are how coarse
/// the brushing is, how far the rust has got, how badly it has been knocked
/// about, and whether it is polished or dull -- and none of those is density.
///
/// The colours come from the ones every style already has: the base colour is
/// the metal, the main colour is the sheen along the brushing, and the accent
/// is the rust. So a brass plate and a galvanised panel are the same four
/// numbers with different swatches.
class MetalSpec {
  /// roughness is how coarse the brushing is: 0 is a poured, almost glassy
  /// sheet and 1 is heavily ground.
  final double roughness;

  /// rust is how far the corrosion has spread, from none to eaten through.
  final double rust;

  /// damage is the knocks: scratches across the grain and dents in it.
  final double damage;

  /// shine is polished against matt. It is the width and the strength of the
  /// highlight along the sheet -- a mirror has a narrow hard one, a
  /// bead-blasted panel has almost none.
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
