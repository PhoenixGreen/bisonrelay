import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// character_rig_points.dart is a sketched character's limbs reshaped point
// by point. Each arm and leg runs through its three joints -- the root, the
// elbow or knee, and the wrist or ankle -- and through any points added
// between them. Every point can be moved off the bone, which bends the
// limb there; made thicker or thinner, down to nothing; and turned, which
// slants the limb's cross-section through it.
//
// A point is kept in its bone's own measure -- how far along it, and
// moved along and across it in head units -- so it goes with the bone
// whatever the pose, and is the same on every panel.

/// RigPoint is one point a limb runs through.
class RigPoint {
  /// bone is the upper bone (0) or the lower (1); f how far along it, 0 at
  /// its root and 1 at its end. The joints are points too: the root is
  /// (0, 0), the elbow or knee (0, 1), and the wrist or ankle (1, 1).
  final int bone;
  final double f;

  /// along and across are how far it is moved off the bone, along it and
  /// square to it, in head units.
  final double along;
  final double across;

  /// scale is how thick the limb is there, against the usual: 0 thins it
  /// to nothing.
  final double scale;

  /// turn is how far the limb's cross-section through it is turned, in
  /// degrees.
  final double turn;

  const RigPoint(this.bone, this.f,
      {this.along = 0, this.across = 0, this.scale = 1, this.turn = 0});

  static const RigPoint root = RigPoint(0, 0);
  static const RigPoint middle = RigPoint(0, 1);
  static const RigPoint end = RigPoint(1, 1);

  /// joints are the three every limb has, which can be changed but not
  /// taken away.
  static const List<RigPoint> joints = [root, middle, end];

  bool get isJoint => (bone == 0 && f == 0) || f == 1;

  /// sameSpot is whether [o] is at the same place on the limb.
  bool sameSpot(RigPoint o) => o.bone == bone && (o.f - f).abs() < 1e-6;

  /// order is where on the limb it is, root to end.
  double get order => bone + f;

  bool get isRest => along == 0 && across == 0 && scale == 1 && turn == 0;

  RigPoint copyWith({double? along, double? across, double? scale, double? turn}) =>
      RigPoint(bone, f,
          along: along ?? this.along,
          across: across ?? this.across,
          scale: (scale ?? this.scale).clamp(0.0, 4.0),
          turn: turn ?? this.turn);

  @override
  bool operator ==(Object other) =>
      other is RigPoint &&
      other.bone == bone &&
      other.f == f &&
      other.along == along &&
      other.across == across &&
      other.scale == scale &&
      other.turn == turn;

  @override
  int get hashCode => Object.hash(bone, f, along, across, scale, turn);

  Map<String, dynamic> toJson() => {
        "bone": bone,
        "f": f,
        if (along != 0) "along": along,
        if (across != 0) "across": across,
        if (scale != 1) "scale": scale,
        if (turn != 0) "turn": turn,
      };

  static RigPoint? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    var bone = jsonInt(json["bone"], 0).clamp(0, 1);
    var f = jsonDouble(json["f"], 0).clamp(0.0, 1.0);
    return RigPoint(bone, f,
        along: jsonDouble(json["along"], 0),
        across: jsonDouble(json["across"], 0),
        scale: jsonDouble(json["scale"], 1).clamp(0.0, 4.0),
        turn: jsonDouble(json["turn"], 0));
  }
}

/// RigPoints is every limb's points that are not as they were: points
/// added, and joints changed. Keyed by the limb's name -- armL, armR, legL,
/// legR -- see CharacterLimb.
class RigPoints {
  final Map<String, List<RigPoint>> limbs;
  const RigPoints([this.limbs = const {}]);

  static const RigPoints none = RigPoints();

  bool get isEmpty => limbs.values.every((l) => l.isEmpty);

  /// of is [limb]'s points, root to end: its three joints, as changed, and
  /// the points added between.
  List<RigPoint> of(String limb) {
    var own = limbs[limb] ?? const [];
    var all = <RigPoint>[
      for (var j in RigPoint.joints)
        own.firstWhere((p) => p.sameSpot(j), orElse: () => j),
      for (var p in own)
        if (!p.isJoint) p,
    ]..sort((a, b) => a.order.compareTo(b.order));
    return all;
  }

  /// edited is whether [limb] has anything changed.
  bool edited(String limb) => limbs[limb]?.isNotEmpty ?? false;

  /// withPoint is this with [point] on [limb]: in place of the one at the
  /// same spot, or added. A joint put back as it was is kept no longer.
  RigPoints withPoint(String limb, RigPoint point) {
    var own = [
      for (var p in limbs[limb] ?? const <RigPoint>[])
        if (!p.sameSpot(point)) p,
      if (!(point.isJoint && point.isRest)) point,
    ];
    return RigPoints({...limbs, limb: own});
  }

  /// without is this with the point at [point]'s spot on [limb] taken away
  /// -- a joint put back as it was.
  RigPoints without(String limb, RigPoint point) => RigPoints({
        ...limbs,
        limb: [
          for (var p in limbs[limb] ?? const <RigPoint>[])
            if (!p.sameSpot(point)) p,
        ],
      });

  /// cleared is this with [limb] as it was made.
  RigPoints cleared(String limb) => RigPoints({...limbs}..remove(limb));

  @override
  bool operator ==(Object other) {
    if (other is! RigPoints) return false;
    var keys = {...limbs.keys, ...other.limbs.keys};
    for (var k in keys) {
      var a = limbs[k] ?? const [], b = other.limbs[k] ?? const [];
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll([
        for (var k in limbs.keys.toList()..sort())
          if (limbs[k]!.isNotEmpty) Object.hash(k, Object.hashAll(limbs[k]!)),
      ]);

  Map<String, dynamic> toJson() => {
        for (var e in limbs.entries)
          if (e.value.isNotEmpty) e.key: [for (var p in e.value) p.toJson()],
      };

  factory RigPoints.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return none;
    return RigPoints({
      for (var e in json.entries)
        if (e.value is List)
          e.key: [
            for (var p in e.value as List)
              if (RigPoint.fromJson(p) case var point?) point,
          ],
    });
  }
}
