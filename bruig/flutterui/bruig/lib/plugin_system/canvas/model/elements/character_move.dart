// character_move.dart is how a new 3D character stands and moves, as the
// Character Studio's Move step sets it: a stance -- placed by where its
// hands and feet go, worked out for the body's own limbs (vrm_pose.dart) --
// the shape of each hand, each foot turned at the ankle, and the body
// turned by hand.

/// moveStances are the stances, by name.
const List<String> moveStances = [
  "Relaxed",
  "Confident",
  "Hands on hips",
  "Arms crossed",
  "Thinking",
  "Wave",
  "Pointing",
  "Peace",
  "Cheer",
  "Hands behind",
  "Shy",
  "Shrug",
  "Hero",
  "Weight on one leg",
  "Crouch",
  "Fighting guard",
];

/// handShapes are the hand shapes, with their names. "relaxed" is also
/// "as the stance has it".
const List<(String, String)> handShapes = [
  ("relaxed", "Relaxed"),
  ("open", "Open"),
  ("fist", "Fist"),
  ("point", "Point"),
  ("peace", "Peace"),
  ("thumbsup", "Thumbs up"),
];

/// moveBody are the body's turns by hand, -1 to 1, with their names.
const List<(String, String)> moveBody = [
  ("lean", "Lean forward"),
  ("twist", "Twist"),
  ("side", "Bend sideways"),
  ("headTurn", "Head turn"),
  ("headNod", "Head nod"),
  ("headTilt", "Head tilt"),
  ("crouch", "Crouch"),
  ("shift", "Weight across"),
];

/// moveFoot are a foot's turns at the ankle, with their names: flex -1
/// (pointed) to 1 (flexed), roll -1 to 1, heel and toes nought to one.
const List<(String, String)> moveFoot = [
  ("flex", "Point / flex"),
  ("roll", "Roll in / out"),
  ("heel", "Heel up"),
  ("toes", "Toes"),
];

/// moveMotions are the motions, by name: made as they play, from the
/// stance and this body, so they never come out the wrong size.
const List<String> moveMotions = [
  "Still",
  "Idle",
  "Walk",
  "Run",
  "Jump",
  "Wave",
  "Nod",
  "Shake head",
  "Clap",
  "Bow",
  "Dance",
  "Look around",
];

/// moveWalk are how it walks and runs, nought to one, with their names.
const List<(String, String)> moveWalk = [
  ("pace", "Pace"),
  ("stride", "Stride"),
  ("bounce", "Bounce"),
  ("swing", "Arm swing"),
  ("push", "Push-off"),
  ("lean", "Lean"),
  ("sway", "Hip sway"),
];
const Map<String, double> moveWalkDefaults = {
  "pace": 0.5,
  "stride": 0.5,
  "bounce": 0.5,
  "swing": 0.5,
  "push": 0.5,
  "lean": 0.3,
  "sway": 0.4,
};

/// movePhysics are how the hair and clothes swing, with their names and
/// ranges: as made at one, wind at nought.
const List<(String, String, double)> movePhysics = [
  ("hair", "Hair swing", 2),
  ("clothes", "Clothes swing", 2),
  ("gravity", "Weight", 2),
  ("wind", "Wind", 1),
];
const Map<String, double> movePhysicsDefaults = {
  "hair": 1,
  "clothes": 1,
  "gravity": 1,
  "wind": 0,
};

/// moveDots are the dots dragged on the character in the Move step: the
/// hands, feet and hips move, the head turns.
const List<String> moveDots = [
  "handL",
  "handR",
  "footL",
  "footR",
  "hips",
  "head"
];

/// CharacterMove is how the character stands and moves. Immutable.
class CharacterMove {
  final String stance;

  /// handL and handR are each hand's shape, by its name in [handShapes].
  final String handL, handR;

  /// body is each of [moveBody] changed from nought.
  final Map<String, double> body;

  /// footL and footR are each foot's [moveFoot] changed from nought.
  final Map<String, double> footL, footR;

  /// motion is the motion it plays, at [speed] times as fast, while
  /// [playing].
  final String motion;
  final double speed;
  final bool playing;

  /// walk and physics are each of [moveWalk] and [movePhysics] changed.
  final Map<String, double> walk, physics;

  /// offsets are where the hands, feet and hips have been dragged to, from
  /// where the stance puts them: [x, y, z] in metres, in the body's own
  /// space (up is +y, it faces +z, its left is +x), by [moveDots] name.
  final Map<String, List<double>> offsets;

  const CharacterMove({
    this.stance = "Relaxed",
    this.handL = "relaxed",
    this.handR = "relaxed",
    this.body = const {},
    this.footL = const {},
    this.footR = const {},
    this.motion = "Idle",
    this.speed = 1,
    this.playing = true,
    this.walk = const {},
    this.physics = const {},
    this.offsets = const {},
  });

  double bodyOf(String k) => body[k] ?? 0;
  double walkOf(String k) => walk[k] ?? moveWalkDefaults[k] ?? 0.5;
  double physicsOf(String k) => physics[k] ?? movePhysicsDefaults[k] ?? 1;
  double footOf(String side, String k) => (side == "L" ? footL : footR)[k] ?? 0;

  CharacterMove copyWith(
          {String? stance,
          String? handL,
          String? handR,
          Map<String, double>? body,
          Map<String, double>? footL,
          Map<String, double>? footR,
          String? motion,
          double? speed,
          bool? playing,
          Map<String, double>? walk,
          Map<String, double>? physics,
          Map<String, List<double>>? offsets}) =>
      CharacterMove(
          stance: stance ?? this.stance,
          handL: handL ?? this.handL,
          handR: handR ?? this.handR,
          body: body ?? this.body,
          footL: footL ?? this.footL,
          footR: footR ?? this.footR,
          motion: motion ?? this.motion,
          speed: speed ?? this.speed,
          playing: playing ?? this.playing,
          walk: walk ?? this.walk,
          physics: physics ?? this.physics,
          offsets: offsets ?? this.offsets);

  /// offsetOf is dot [k]'s offset, nought where it has none.
  List<double> offsetOf(String k) => offsets[k] ?? const [0.0, 0.0, 0.0];

  /// withOffset is this with dot [k] dragged to [o].
  CharacterMove withOffset(String k, List<double> o) => copyWith(
      offsets: {...offsets, k: o}
        ..removeWhere((_, v) => v.every((x) => x.abs() < 1e-6)));

  CharacterMove withWalk(String k, double v) => copyWith(
      walk: {...walk, k: v}..removeWhere((k, x) => x == moveWalkDefaults[k]));

  CharacterMove withPhysics(String k, double v) => copyWith(
      physics: {...physics, k: v}
        ..removeWhere((k, x) => x == movePhysicsDefaults[k]));

  CharacterMove withBody(String k, double v) =>
      copyWith(body: {...body, k: v}..removeWhere((_, x) => x == 0));

  CharacterMove withFoot(String side, String k, double v) => side == "L"
      ? copyWith(footL: {...footL, k: v}..removeWhere((_, x) => x == 0))
      : copyWith(footR: {...footR, k: v}..removeWhere((_, x) => x == 0));

  Map<String, dynamic> toJson() => {
        if (stance != "Relaxed") "stance": stance,
        if (handL != "relaxed") "handL": handL,
        if (handR != "relaxed") "handR": handR,
        if (body.isNotEmpty) "body": body,
        if (footL.isNotEmpty) "footL": footL,
        if (footR.isNotEmpty) "footR": footR,
        if (motion != "Idle") "motion": motion,
        if (speed != 1) "speed": speed,
        if (!playing) "playing": false,
        if (walk.isNotEmpty) "walk": walk,
        if (physics.isNotEmpty) "physics": physics,
        if (offsets.isNotEmpty) "offsets": offsets,
      };

  static CharacterMove fromJson(Object? json) {
    if (json is! Map) return const CharacterMove();
    Map<String, double> nums(
            Object? m, List<(String, String)> keys, double lo) =>
        {
          if (m is Map)
            for (final (k, _) in keys)
              if (m[k] is num && (m[k] as num).isFinite && m[k] != 0)
                k: (m[k] as num).toDouble().clamp(lo, 1.0)
        };
    String hand(Object? v) =>
        handShapes.any((h) => h.$1 == v) ? v as String : "relaxed";
    final stance = json["stance"], motion = json["motion"];
    Map<String, double> ranged(Object? m, Map<String, double> defaults,
            double Function(String) hi) =>
        {
          if (m is Map)
            for (final k in defaults.keys)
              if (m[k] is num && (m[k] as num).isFinite && m[k] != defaults[k])
                k: (m[k] as num).toDouble().clamp(0.0, hi(k))
        };
    return CharacterMove(
      stance: moveStances.contains(stance) ? stance as String : "Relaxed",
      handL: hand(json["handL"]),
      handR: hand(json["handR"]),
      body: nums(json["body"], moveBody, -1),
      footL: nums(json["footL"], moveFoot, -1),
      footR: nums(json["footR"], moveFoot, -1),
      motion: moveMotions.contains(motion) ? motion as String : "Idle",
      speed: json["speed"] is num && (json["speed"] as num).isFinite
          ? (json["speed"] as num).toDouble().clamp(0.25, 2.0)
          : 1,
      playing: json["playing"] != false,
      walk: ranged(json["walk"], moveWalkDefaults, (_) => 1),
      physics: ranged(json["physics"], movePhysicsDefaults,
          (k) => movePhysics.firstWhere((p) => p.$1 == k).$3),
      offsets: {
        if (json["offsets"] case final Map o)
          for (final k in moveDots)
            if (o[k] case final List v
                when v.length == 3 && v.every((x) => x is num && x.isFinite))
              k: [for (final x in v) (x as num).toDouble().clamp(-1.0, 1.0)]
      },
    );
  }

  static bool _same(Map<String, double> a, Map<String, double> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  @override
  bool operator ==(Object other) =>
      other is CharacterMove &&
      other.stance == stance &&
      other.handL == handL &&
      other.handR == handR &&
      _same(other.body, body) &&
      _same(other.footL, footL) &&
      _same(other.footR, footR) &&
      other.motion == motion &&
      other.speed == speed &&
      other.playing == playing &&
      _same(other.walk, walk) &&
      _same(other.physics, physics) &&
      other.offsets.length == offsets.length &&
      offsets.entries.every((e) =>
          other.offsets[e.key] != null &&
          List.generate(3, (i) => other.offsets[e.key]![i] == e.value[i])
              .every((x) => x));

  @override
  int get hashCode => Object.hash(
      stance, handL, handR, body.length, footL.length, footR.length);
}
