import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// stage_element.dart is a 3D stage: a floor and a back wall seen through a
// camera, that characters stand on.
//
// It is drawn behind everything as a scene's set -- see render/stage -- and
// characters placed on it stand at a spot on its floor rather than at a
// place on the page: the camera decides where on the page that is, how big
// they are for how far away, and which way round they are seen. Moving the
// camera moves them all together, which is what makes a stage worth having
// over a picture behind them.
//
// The camera is keyed like everything else: each of its settings is a
// channel of the stage's own track (see cameraChannel), so a camera move is
// two keyframes and the timeline, easing and undo treat it as they treat
// any other animation.

/// StageCamera is one camera setting. See render/stage/stage_camera.dart for
/// what it sees.
class StageCamera {
  /// yaw is how far round the stage the camera has been swung, in degrees:
  /// round to its right as it grows.
  final double yaw;

  /// pitch is how far above the stage it looks down from, in degrees.
  final double pitch;

  /// distance is how far from what it looks at, in metres.
  final double distance;

  /// lens is its focal length in millimetres, as on a real camera: 24 is
  /// wide, 50 natural, 85 a portrait lens.
  final double lens;

  const StageCamera(
      {this.yaw = 0, this.pitch = 12, this.distance = 7, this.lens = 35});

  static const double minDistance = 1.5;
  static const double maxDistance = 40;

  StageCamera copyWith(
          {double? yaw, double? pitch, double? distance, double? lens}) =>
      StageCamera(
        yaw: yaw ?? this.yaw,
        pitch: (pitch ?? this.pitch).clamp(-10.0, 89.0),
        distance: (distance ?? this.distance).clamp(minDistance, maxDistance),
        lens: (lens ?? this.lens).clamp(12.0, 200.0),
      );

  /// over is this camera with whatever [frame]'s keyframe pins.
  StageCamera over(Keyframe frame) {
    var v = frame.values;
    if (v.isEmpty) return this;
    return copyWith(
        yaw: v[cameraChannel("yaw")],
        pitch: v[cameraChannel("pitch")],
        distance: v[cameraChannel("distance")],
        lens: v[cameraChannel("lens")]);
  }

  Map<String, double> get channels => {
        cameraChannel("yaw"): yaw,
        cameraChannel("pitch"): pitch,
        cameraChannel("distance"): distance,
        cameraChannel("lens"): lens,
      };

  Map<String, dynamic> toJson() =>
      {"yaw": yaw, "pitch": pitch, "distance": distance, "lens": lens};

  factory StageCamera.fromJson(Object? json) {
    if (json is! Map) return const StageCamera();
    const d = StageCamera();
    return d.copyWith(
        yaw: jsonDouble(json["yaw"], d.yaw),
        pitch: jsonDouble(json["pitch"], d.pitch),
        distance: jsonDouble(json["distance"], d.distance),
        lens: jsonDouble(json["lens"], d.lens));
  }
}

/// cameraChannel is the keyframe channel one camera setting is pinned on.
String cameraChannel(String setting) => "cam.$setting";

/// CameraShot is a ready-made camera.
class CameraShot {
  final String name;
  final StageCamera camera;
  const CameraShot(this.name, this.camera);
}

const List<CameraShot> cameraShots = [
  CameraShot("Wide", StageCamera(pitch: 14, distance: 11, lens: 24)),
  CameraShot("Medium", StageCamera(pitch: 10, distance: 7, lens: 35)),
  CameraShot("Close-up", StageCamera(pitch: 4, distance: 3.2, lens: 85)),
  CameraShot("Low angle", StageCamera(pitch: -6, distance: 6, lens: 28)),
  CameraShot("High angle", StageCamera(pitch: 40, distance: 9, lens: 35)),
  CameraShot("Top down", StageCamera(pitch: 85, distance: 12, lens: 35)),
  CameraShot("Side on", StageCamera(yaw: 90, pitch: 8, distance: 8, lens: 35)),
  CameraShot("Three quarter",
      StageCamera(yaw: 35, pitch: 12, distance: 7, lens: 35)),
];

/// FloorPattern is what the floor is made of.
enum FloorPattern {
  plain("Plain"),
  grid("Grid"),
  tiles("Tiles"),
  boards("Boards"),
  grass("Grass");

  final String label;
  const FloorPattern(this.label);

  static FloorPattern fromName(String? name) =>
      values.firstWhere((p) => p.name == name, orElse: () => grid);
}

/// StageLight is how the stage is lit: a colour laid over everything on
/// it, how strongly, and which way the shadows fall.
enum StageLight {
  studio("Studio", Color(0x00000000), 0),
  daylight("Daylight", Color(0xFFFFF4D6), 0.08),
  goldenHour("Golden hour", Color(0xFFFF9A3C), 0.22),
  night("Night", Color(0xFF1B2A6B), 0.45),
  noir("Noir", Color(0xFF000000), 0.35),
  toonFlat("Toon flat", Color(0x00000000), 0);

  final String label;
  final Color tint;
  final double strength;
  const StageLight(this.label, this.tint, this.strength);

  static StageLight fromName(String? name) =>
      values.firstWhere((l) => l.name == name, orElse: () => studio);

  /// shadows is whether things cast shadows on the floor in this light.
  bool get shadows => this != toonFlat;

  /// shadowSlant is which way and how far the shadows fall, as metres
  /// across the floor for each metre of height.
  double get shadowSlant => switch (this) {
        goldenHour => 1.2,
        daylight => 0.35,
        night => -0.2,
        _ => 0.15,
      };
}

class StageElement extends CanvasElement {
  final StageCamera camera;
  final Color floor;
  final FloorPattern pattern;

  /// size is how far the floor runs each way from the middle, in metres.
  final double size;

  /// wall is whether there is a back wall; without one the floor runs to
  /// the horizon under the sky.
  final bool wall;
  final Color wallColor;
  final Color sky;
  final StageLight light;

  const StageElement(
    super.base, {
    this.camera = const StageCamera(),
    this.floor = const Color(0xFFC9B391),
    this.pattern = FloorPattern.grid,
    this.size = 6,
    this.wall = true,
    this.wallColor = const Color(0xFFE9DCC6),
    this.sky = const Color(0xFFBFE0F4),
    this.light = StageLight.studio,
  });

  @override
  ElementKind get kind => ElementKind.stage;

  /// cameraAt is the camera on [frame]: its own setting with whatever the
  /// track keys over it.
  StageCamera cameraAt(int frame) => camera.over(poseAt(frame));

  @override
  CanvasElement rebase(ElementBase base) => StageElement(base,
      camera: camera,
      floor: floor,
      pattern: pattern,
      size: size,
      wall: wall,
      wallColor: wallColor,
      sky: sky,
      light: light);

  StageElement copyWith({
    StageCamera? camera,
    Color? floor,
    FloorPattern? pattern,
    double? size,
    bool? wall,
    Color? wallColor,
    Color? sky,
    StageLight? light,
  }) =>
      StageElement(base,
          camera: camera ?? this.camera,
          floor: floor ?? this.floor,
          pattern: pattern ?? this.pattern,
          size: (size ?? this.size).clamp(1.0, 50.0),
          wall: wall ?? this.wall,
          wallColor: wallColor ?? this.wallColor,
          sky: sky ?? this.sky,
          light: light ?? this.light);

  @override
  Map<String, dynamic> props() => {
        "camera": camera.toJson(),
        "floor": colorToJson(floor),
        "pattern": pattern.name,
        "size": size,
        "wall": wall,
        "wallColor": colorToJson(wallColor),
        "sky": colorToJson(sky),
        "light": light.name,
      };

  factory StageElement.fromJson(Map<String, dynamic> json, ElementBase b) {
    const d = StageElement(ElementBase(id: ""));
    return StageElement(b,
        camera: StageCamera.fromJson(json["camera"]),
        floor: colorFromJson(json["floor"], d.floor),
        pattern: FloorPattern.fromName(json["pattern"] as String?),
        size: jsonDouble(json["size"], d.size).clamp(1.0, 50.0),
        wall: jsonBool(json["wall"], true),
        wallColor: colorFromJson(json["wallColor"], d.wallColor),
        sky: colorFromJson(json["sky"], d.sky),
        light: StageLight.fromName(json["light"] as String?));
  }
}
