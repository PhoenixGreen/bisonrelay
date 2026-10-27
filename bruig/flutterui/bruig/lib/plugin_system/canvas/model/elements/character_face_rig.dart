import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// character_face_rig.dart is a sketch's face set feature by feature, panel
// by panel: each eye, each brow, the nose, the mouth and each corner of the
// mouth moved, made bigger or smaller, and turned, as the face is seen
// from that panel. On top of the expression the face is making, not in
// place of it: a brow raised here is raised in every expression.
//
// Its own for each panel, because a face is drawn differently from each
// side -- the far eye tucked in turned three-quarters, the mouth pulled
// round. A panel seen from the other side mirrors it until it is set
// itself, as a drawing does: see CharacterElement.drawingFor.
//
// Moves are in head units, across and down the face; turns in degrees.

/// FacePoint is one feature of the face to set. Left and right are the
/// character's own.
enum FacePoint {
  browL("Left brow"),
  browR("Right brow"),
  eyeL("Left eye"),
  eyeR("Right eye"),
  nose("Nose"),
  mouth("Mouth"),
  cornerL("Left corner of the mouth"),
  cornerR("Right corner of the mouth");

  final String label;
  const FacePoint(this.label);

  static FacePoint? fromName(String? name) {
    for (var p in values) {
      if (p.name == name) return p;
    }
    return null;
  }

  FacePoint get mirrored => switch (this) {
        browL => browR,
        browR => browL,
        eyeL => eyeR,
        eyeR => eyeL,
        cornerL => cornerR,
        cornerR => cornerL,
        _ => this,
      };

  /// movesOnly is whether only moving it means anything: a corner of the
  /// mouth is a point, not a shape.
  bool get movesOnly => this == cornerL || this == cornerR;
}

/// FaceAdjust is how one feature is set.
class FaceAdjust {
  final double dx, dy;
  final double scale;
  final double turn;
  const FaceAdjust({this.dx = 0, this.dy = 0, this.scale = 1, this.turn = 0});

  static const FaceAdjust rest = FaceAdjust();

  bool get isRest => dx == 0 && dy == 0 && scale == 1 && turn == 0;

  FaceAdjust copyWith({double? dx, double? dy, double? scale, double? turn}) =>
      FaceAdjust(
          dx: dx ?? this.dx,
          dy: dy ?? this.dy,
          scale: (scale ?? this.scale).clamp(0.0, 4.0),
          turn: turn ?? this.turn);

  FaceAdjust get mirrored =>
      FaceAdjust(dx: -dx, dy: dy, scale: scale, turn: -turn);

  @override
  bool operator ==(Object other) =>
      other is FaceAdjust &&
      other.dx == dx &&
      other.dy == dy &&
      other.scale == scale &&
      other.turn == turn;

  @override
  int get hashCode => Object.hash(dx, dy, scale, turn);

  Map<String, dynamic> toJson() => {
        if (dx != 0) "dx": dx,
        if (dy != 0) "dy": dy,
        if (scale != 1) "scale": scale,
        if (turn != 0) "turn": turn,
      };

  factory FaceAdjust.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return rest;
    return FaceAdjust(
        dx: jsonDouble(json["dx"], 0),
        dy: jsonDouble(json["dy"], 0),
        scale: jsonDouble(json["scale"], 1).clamp(0.0, 4.0),
        turn: jsonDouble(json["turn"], 0));
  }
}

/// FaceRig is a panel's face, feature by feature: those set, and the rest
/// as they are.
class FaceRig {
  final Map<FacePoint, FaceAdjust> points;
  const FaceRig([this.points = const {}]);

  static const FaceRig none = FaceRig();

  bool get isEmpty => points.isEmpty;

  FaceAdjust operator [](FacePoint p) => points[p] ?? FaceAdjust.rest;

  /// withPoint is this with [p] set as [a]; set back as it was, it is kept
  /// no longer.
  FaceRig withPoint(FacePoint p, FaceAdjust a) {
    var next = {...points};
    if (a.isRest) {
      next.remove(p);
    } else {
      next[p] = a;
    }
    return FaceRig(next);
  }

  /// mirrored is this seen from the other side.
  FaceRig get mirrored =>
      FaceRig({for (var e in points.entries) e.key.mirrored: e.value.mirrored});

  @override
  bool operator ==(Object other) {
    if (other is! FaceRig || other.points.length != points.length) return false;
    for (var e in points.entries) {
      if (other.points[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
      [for (var e in points.entries) Object.hash(e.key, e.value)]);

  Map<String, dynamic> toJson() => {
        for (var e in points.entries) e.key.name: e.value.toJson(),
      };

  factory FaceRig.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return none;
    return FaceRig({
      for (var e in json.entries)
        if (FacePoint.fromName(e.key) case var p?)
          p: FaceAdjust.fromJson(e.value),
    });
  }
}
