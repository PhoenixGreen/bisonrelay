// character_decal.dart is a picture or a vector from the canvas library laid
// on a new 3D character's skin or clothes: a tattoo, a brand on a shirt, a
// patch. It lies on the surface itself, so it follows the body's shape and
// moves with it; what is made of it is in render/vrm/vrm_decal.dart.

/// DecalArea is the part of the body a decal is placed on, and the line it
/// is placed along: up the torso, down a limb.
enum DecalArea {
  torso("Body"),
  neck("Neck"),
  head("Head"),
  leftArm("Left arm"),
  rightArm("Right arm"),
  leftLeg("Left leg"),
  rightLeg("Right leg");

  final String label;
  const DecalArea(this.label);
}

/// decalModes are how a decal is drawn, with their names: as printed, as a
/// tattoo (muted and inked into the skin), faded, or in one ink colour.
const List<(String, String)> decalModes = [
  ("print", "Printed"),
  ("tattoo", "Tattoo"),
  ("faded", "Faded"),
  ("ink", "One ink"),
];

/// CharacterDecal is one decal. Immutable.
class CharacterDecal {
  final String id;

  /// source is what is laid on: `picture:<path in the library>` or
  /// `vector:<the vector's id>`.
  final String source;

  /// name is what the page calls it.
  final String name;

  /// on is the surface: "skin", or a piece of clothing by its slot's name
  /// ("top"), whichever of its own or made to fit is worn.
  final String on;
  final DecalArea area;

  /// along is how far along [area]'s line, nought to one; around how far
  /// round it from the front, -1 to 1 (a half turn either way).
  final double along, around;

  /// size is how big, as a share of the body's height; turn its rotation,
  /// -1 to 1 (a half turn either way).
  final double size, turn;

  final String mode;
  final double opacity;

  /// ink is the colour of a one-ink decal, 0xRRGGBB.
  final int ink;

  const CharacterDecal({
    required this.id,
    required this.source,
    this.name = "",
    this.on = "skin",
    this.area = DecalArea.torso,
    this.along = 0.6,
    this.around = 0,
    this.size = 0.08,
    this.turn = 0,
    this.mode = "print",
    this.opacity = 1,
    this.ink = 0x1b1a22,
  });

  CharacterDecal copyWith({
    String? source,
    String? name,
    String? on,
    DecalArea? area,
    double? along,
    double? around,
    double? size,
    double? turn,
    String? mode,
    double? opacity,
    int? ink,
  }) =>
      CharacterDecal(
        id: id,
        source: source ?? this.source,
        name: name ?? this.name,
        on: on ?? this.on,
        area: area ?? this.area,
        along: along ?? this.along,
        around: around ?? this.around,
        size: size ?? this.size,
        turn: turn ?? this.turn,
        mode: mode ?? this.mode,
        opacity: opacity ?? this.opacity,
        ink: ink ?? this.ink,
      );

  /// shapeKey says what the decal's shape depends on; pictureKey what its
  /// picture does.
  String get shapeKey => "$on|${area.name}|$along|$around|$size|$turn";
  String get pictureKey => "$source|$mode|$opacity|$ink";

  Map<String, dynamic> toJson() => {
        "id": id,
        "source": source,
        "name": name,
        "on": on,
        "area": area.name,
        "along": along,
        "around": around,
        "size": size,
        "turn": turn,
        "mode": mode,
        "opacity": opacity,
        "ink": ink,
      };

  /// fromJson reads what toJson wrote, or null for what is not a decal.
  static CharacterDecal? fromJson(Map<String, dynamic> j) {
    final id = j["id"], source = j["source"];
    if (id is! String || source is! String || source.isEmpty) return null;
    double n(String k, double d, double lo, double hi) =>
        j[k] is num && (j[k] as num).isFinite
            ? (j[k] as num).toDouble().clamp(lo, hi)
            : d;
    return CharacterDecal(
      id: id,
      source: source,
      name: j["name"] is String ? j["name"] as String : "",
      on: j["on"] is String ? j["on"] as String : "skin",
      area: DecalArea.values.where((a) => a.name == j["area"]).firstOrNull ??
          DecalArea.torso,
      along: n("along", 0.6, 0, 1),
      around: n("around", 0, -1, 1),
      size: n("size", 0.08, 0.01, 0.5),
      turn: n("turn", 0, -1, 1),
      mode: decalModes.any((m) => m.$1 == j["mode"])
          ? j["mode"] as String
          : "print",
      opacity: n("opacity", 1, 0, 1),
      ink: j["ink"] is int ? (j["ink"] as int) & 0xffffff : 0x1b1a22,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CharacterDecal &&
      other.id == id &&
      other.shapeKey == shapeKey &&
      other.pictureKey == pictureKey &&
      other.name == name;

  @override
  int get hashCode => Object.hash(id, shapeKey, pictureKey, name);
}
