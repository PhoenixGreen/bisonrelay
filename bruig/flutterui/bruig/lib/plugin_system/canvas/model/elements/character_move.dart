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

/// CharacterMove is how the character stands. Immutable.
class CharacterMove {
  final String stance;

  /// handL and handR are each hand's shape, by its name in [handShapes].
  final String handL, handR;

  /// body is each of [moveBody] changed from nought.
  final Map<String, double> body;

  /// footL and footR are each foot's [moveFoot] changed from nought.
  final Map<String, double> footL, footR;

  const CharacterMove({
    this.stance = "Relaxed",
    this.handL = "relaxed",
    this.handR = "relaxed",
    this.body = const {},
    this.footL = const {},
    this.footR = const {},
  });

  double bodyOf(String k) => body[k] ?? 0;
  double footOf(String side, String k) => (side == "L" ? footL : footR)[k] ?? 0;

  CharacterMove copyWith(
          {String? stance,
          String? handL,
          String? handR,
          Map<String, double>? body,
          Map<String, double>? footL,
          Map<String, double>? footR}) =>
      CharacterMove(
          stance: stance ?? this.stance,
          handL: handL ?? this.handL,
          handR: handR ?? this.handR,
          body: body ?? this.body,
          footL: footL ?? this.footL,
          footR: footR ?? this.footR);

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
    final stance = json["stance"];
    return CharacterMove(
      stance: moveStances.contains(stance) ? stance as String : "Relaxed",
      handL: hand(json["handL"]),
      handR: hand(json["handR"]),
      body: nums(json["body"], moveBody, -1),
      footL: nums(json["footL"], moveFoot, -1),
      footR: nums(json["footR"], moveFoot, -1),
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
      _same(other.footR, footR);

  @override
  int get hashCode => Object.hash(
      stance, handL, handR, body.length, footL.length, footR.length);
}
