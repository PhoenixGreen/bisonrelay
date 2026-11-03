import 'package:bruig/plugin_system/canvas/model/elements/character_decal.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_face.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_look.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_outfit.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_sculpt.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_shape.dart';

// character_design.dart is a new 3D character as the Character Studio makes
// it, kept in the library (storage/character_designs.dart): the VRoid body it
// starts from, its shape, what it wears, how it is drawn, and its decals.

/// CharacterDesign is one character. Immutable.
class CharacterDesign {
  final String id, name;

  /// body is the VRoid body it starts from, by its id in vroid_assets.dart.
  final String body;
  final CharacterShape shape;
  final CharacterOutfit outfit;

  /// lookName is the look started from, and look the look as it is now.
  final String lookName;
  final CharacterLook look;
  final List<CharacterDecal> decals;

  /// sculpt is the body shaped by hand, stroke by stroke.
  final List<SculptStroke> sculpt;

  /// paint is what is painted on the skin and the clothes, stroke by
  /// stroke.
  final List<PaintStroke> paint;

  /// face is its expression, and what its face does by itself.
  final CharacterFace face;
  final DateTime updated;

  const CharacterDesign({
    required this.id,
    required this.name,
    required this.body,
    this.shape = const CharacterShape(),
    this.outfit = CharacterOutfit.asDesigned,
    this.lookName = "Anime cel",
    this.look = const CharacterLook(),
    this.decals = const [],
    this.sculpt = const [],
    this.paint = const [],
    this.face = const CharacterFace(),
    required this.updated,
  });

  /// pictureIds and vectorIds are the library's pictures and vectors its
  /// decals use, for a tidy of the library to keep.
  Set<String> get pictureIds => {
        for (final d in decals)
          if (d.source.startsWith("picture:")) d.source.substring(8)
      };
  Set<String> get vectorIds => {
        for (final d in decals)
          if (d.source.startsWith("vector:")) d.source.substring(7)
      };

  Map<String, dynamic> toJson() => {
        "version": 1,
        "id": id,
        "name": name,
        "body": body,
        "shape": shape.toJson(),
        "outfit": outfit.toJson(),
        "lookName": lookName,
        "look": look.toJson(),
        "decals": [for (final d in decals) d.toJson()],
        if (sculpt.isNotEmpty) "sculpt": [for (final s in sculpt) s.toJson()],
        if (paint.isNotEmpty) "paint": [for (final s in paint) s.toJson()],
        if (face != const CharacterFace()) "face": face.toJson(),
        "updated": updated.toIso8601String(),
      };

  /// fromJson reads what toJson wrote, or null for what is not a character.
  static CharacterDesign? fromJson(Object? json) {
    if (json is! Map) return null;
    final j = json.cast<String, dynamic>();
    final id = j["id"], body = j["body"];
    if (id is! String || id.isEmpty || body is! String || body.isEmpty) {
      return null;
    }
    Map<String, dynamic> map(String k) =>
        j[k] is Map ? (j[k] as Map).cast<String, dynamic>() : const {};
    final name = j["lookName"];
    return CharacterDesign(
      id: id,
      name: j["name"] is String ? j["name"] as String : "",
      body: body,
      shape: CharacterShape.fromJson(map("shape")),
      outfit: CharacterOutfit.fromJson(map("outfit")),
      lookName: name is String && characterLooks.containsKey(name)
          ? name
          : "Anime cel",
      look: CharacterLook.fromJson(map("look")),
      decals: [
        for (final d in (j["decals"] is List ? j["decals"] as List : const []))
          if (d is Map)
            if (CharacterDecal.fromJson(d.cast<String, dynamic>())
                case final x?)
              x
      ],
      sculpt: [
        for (final s in (j["sculpt"] is List ? j["sculpt"] as List : const []))
          if (SculptStroke.fromJson(s) case final x?) x
      ],
      paint: [
        for (final s in (j["paint"] is List ? j["paint"] as List : const []))
          if (PaintStroke.fromJson(s) case final x?) x
      ],
      face: CharacterFace.fromJson(j["face"]),
      updated: DateTime.tryParse("${j["updated"]}") ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
