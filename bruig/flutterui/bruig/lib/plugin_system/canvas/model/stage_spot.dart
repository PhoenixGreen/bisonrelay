import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';

// stage_spot.dart is where an element stands on a 3D stage: on which stage,
// where on its floor, how big in metres, which way round, and how it stands
// there -- upright like a piece of scenery, turned to the camera, laid on
// the floor, or hung on the back wall.
//
// Any element can stand on a stage. A 3D character stands there as itself,
// seen through the stage's camera; everything else -- a picture, words, a
// video, a chart -- is a flat, drawn as it is on the page and then set into
// the stage in perspective, so it moves with the camera as the set does.
// See render/stage/stage_painter.dart.

/// SpotStand is how an element stands on its spot.
enum SpotStand {
  upright("Stands upright"),
  camera("Faces the camera"),
  floor("Lies on the floor"),
  wall("On the back wall");

  final String label;
  const SpotStand(this.label);

  static SpotStand fromName(Object? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => upright);
}

/// spotChannel is the keyframe channel one spot setting is pinned on.
String spotChannel(String setting) => "spot.$setting";

/// StageSpot is where an element stands on a stage. Immutable.
class StageSpot {
  /// stage is the stage's id: a Background element showing one, or the
  /// canvas background's.
  final String stage;

  /// x is metres across the floor from its middle, to the right as the
  /// camera first sees it; z metres towards where the camera starts; lift
  /// metres off the floor -- or up the wall, for one hung on it.
  final double x, z, lift;

  /// height is how big it is, in metres: its box's longer side, the other
  /// following the box's shape -- how tall a picture stands, how long a
  /// line or a chart is. A 3D character is as tall as it was made, and
  /// ignores it.
  final double height;

  /// facing is which way round it stands, in degrees, before the camera is
  /// taken into account: nought faces where the camera starts.
  final double facing;
  final SpotStand stand;

  const StageSpot(this.stage,
      {this.x = 0,
      this.z = 0,
      this.lift = 0,
      this.height = 1.6,
      this.facing = 0,
      this.stand = SpotStand.upright});

  StageSpot copyWith(
          {String? stage,
          double? x,
          double? z,
          double? lift,
          double? height,
          double? facing,
          SpotStand? stand}) =>
      StageSpot(stage ?? this.stage,
          x: x ?? this.x,
          z: z ?? this.z,
          lift: (lift ?? this.lift).clamp(-10.0, 30.0),
          height: (height ?? this.height).clamp(0.05, 30.0),
          facing: facing ?? this.facing,
          stand: stand ?? this.stand);

  /// channels are the settings a keyframe pins, by their channels.
  Map<String, double> get channels => {
        spotChannel("x"): x,
        spotChannel("z"): z,
        spotChannel("lift"): lift,
        spotChannel("height"): height,
        spotChannel("facing"): facing,
      };

  /// over is this spot with whatever [frame]'s keyframe pins.
  StageSpot over(Keyframe frame) {
    final v = frame.values;
    if (v.isEmpty) return this;
    return copyWith(
        x: v[spotChannel("x")],
        z: v[spotChannel("z")],
        lift: v[spotChannel("lift")],
        height: v[spotChannel("height")],
        facing: v[spotChannel("facing")]);
  }

  Map<String, dynamic> toJson() => {
        "stage": stage,
        if (x != 0) "x": x,
        if (z != 0) "z": z,
        if (lift != 0) "lift": lift,
        if (height != 1.6) "height": height,
        if (facing != 0) "facing": facing,
        if (stand != SpotStand.upright) "stand": stand.name,
      };

  static StageSpot? fromJson(Object? json) {
    if (json is! Map || json["stage"] is! String) return null;
    final id = json["stage"] as String;
    if (id.isEmpty) return null;
    double n(String k, double d) => json[k] is num && (json[k] as num).isFinite
        ? (json[k] as num).toDouble()
        : d;
    return StageSpot(id, stand: SpotStand.fromName(json["stand"])).copyWith(
        x: n("x", 0).clamp(-100.0, 100.0),
        z: n("z", 0).clamp(-100.0, 100.0),
        lift: n("lift", 0),
        height: n("height", 1.6),
        facing: n("facing", 0));
  }

  @override
  bool operator ==(Object other) =>
      other is StageSpot &&
      other.stage == stage &&
      other.x == x &&
      other.z == z &&
      other.lift == lift &&
      other.height == height &&
      other.facing == facing &&
      other.stand == stand;

  @override
  int get hashCode => Object.hash(stage, x, z, lift, height, facing, stand);
}
