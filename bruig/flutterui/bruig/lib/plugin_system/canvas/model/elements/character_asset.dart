import 'package:bruig/plugin_system/canvas/model/canvas_document.dart'
    show elementFromJson;
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';

// character_asset.dart is a character kept in the library: made once, in
// the Character Studio, and placed in as many scenes as it is in. What it
// is -- its body, its drawing, its rig, its face -- is the library's; where
// it stands, how it is posed on the timeline, what it feels and says, is
// each scene's. Every placed copy carries the design too, so a canvas is
// whole on its own, published or sent; the Studio writes a change back to
// every copy. Ken's decision, 2026-11-01: a scene may change a character's
// Look and its expression, not its design.

/// designKeys are a character's JSON keys that are its design: kept in the
/// library, the same in every scene it is in.
const Set<String> designKeys = {
  "dna",
  "style",
  "pose",
  "life",
  "bareView",
  "puppet",
  "body",
  "drawings",
  "faceRigs",
  "hiddenLayers",
  "views",
  "reference",
  "palette",
  "outfits",
  "physics",
  "expressions",
  "feel",
  "gameMotions",
};

/// designOf is [e]'s design: its JSON, design keys only.
Map<String, dynamic> designOf(CharacterElement e) => {
      for (var MapEntry(:key, :value) in e.props().entries)
        if (designKeys.contains(key)) key: value,
    };

/// withDesign is [e] made as [design] says: its design replaced, its scene
/// -- where it stands, its timeline, its face, which way it is turned --
/// kept as it was.
CharacterElement withDesign(CharacterElement e, Map<String, dynamic> design) {
  var json = e.toJson();
  for (var k in designKeys) {
    json.remove(k);
  }
  json.addAll(design);
  var made = elementFromJson(json);
  if (made is! CharacterElement) return e;
  return made.copyWith(
      pose: made.pose
          .withTurn(e.pose.turn)
          .withLift(e.pose.lift)
          .withTilt(e.pose.tilt));
}

/// CharacterAsset is one character in the library: its id -- what a placed
/// copy names it by, see CharacterElement.characterId -- its name, its
/// design and when it was last changed.
class CharacterAsset {
  final String id;
  final String name;
  final Map<String, dynamic> design;
  final DateTime updated;
  const CharacterAsset(this.id, this.name, this.design, this.updated);

  /// element is the character as a placed copy would draw it, standing in
  /// [base]'s box: for a library tile, and for placing it.
  CharacterElement element(ElementBase base) =>
      withDesign(CharacterElement(base, characterId: id), design);

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "updated": updated.toUtc().toIso8601String(),
        "design": design,
      };

  static CharacterAsset? fromJson(Object? json) {
    if (json is! Map ||
        json["id"] is! String ||
        json["design"] is! Map<String, dynamic>) {
      return null;
    }
    return CharacterAsset(
        json["id"] as String,
        json["name"] is String ? json["name"] as String : "",
        json["design"] as Map<String, dynamic>,
        DateTime.tryParse("${json["updated"]}") ?? DateTime(2026));
  }
}
