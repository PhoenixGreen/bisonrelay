import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';

// stage_spot.dart is where an element stands on a 3D stage: which stage,
// where on its floor, how big in metres, which way round, and how it stands
// (upright, turned to the camera, laid flat, or hung on the back wall). A 3D
// character stands there as itself; any other element is drawn flat and set
// into the stage in perspective. See render/stage/stage_painter.dart.

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

/// StageSpot is immutable.
class StageSpot {
  /// stage is the stage's id: a Background element showing one, or the
  /// canvas background's.
  final String stage;

  /// x is metres across the floor from its middle, to the right as the
  /// camera first sees it; z metres towards where the camera starts; lift
  /// metres off the floor -- or up the wall, for one hung on it.
  final double x, z, lift;

  /// height is its box's longer side in metres, the other following the
  /// box's shape. A 3D character ignores it and keeps its made height.
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

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = StageSpot("");

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
        if (x != _defaults.x) "x": x,
        if (z != _defaults.z) "z": z,
        if (lift != _defaults.lift) "lift": lift,
        if (height != _defaults.height) "height": height,
        if (facing != _defaults.facing) "facing": facing,
        if (stand != _defaults.stand) "stand": stand.name,
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
