import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_face.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_look.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_move.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_outfit.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_shape.dart';

// character_cast3d.dart is the ready-made cast: characters made in the
// Character Studio and shipped with the app, to place as they are or to
// start a character from. Each is new when it is changed: it has no id of
// its own, so Done in the Studio keeps it as the user's.

/// ReadyMade is one of the cast: the character, and its picture among the
/// app's assets for the list.
typedef ReadyMade = ({CharacterDesign design, String picture});

CharacterShape _shape(String hair,
    {Map<String, double> values = const {},
    Map<String, int> colours = const {}}) {
  var s = const CharacterShape()
      .withHairStyle(hairStyles.firstWhere((h) => h.id == hair));
  for (final e in values.entries) {
    s = s.withValue(e.key, e.value);
  }
  for (final e in colours.entries) {
    s = s.withColour(e.key, e.value);
  }
  return s;
}

CharacterFace _face(String feeling) =>
    CharacterFace(name: feeling, mix: faceExpressions[feeling]!);

ReadyMade _made(String name, String body, CharacterShape shape,
        {String look = "Anime cel",
        CharacterOutfit outfit = CharacterOutfit.asDesigned,
        String feeling = "Neutral",
        String stance = "Relaxed"}) =>
    (
      design: CharacterDesign(
        id: "",
        name: name,
        body: body,
        shape: shape,
        outfit: outfit,
        lookName: look,
        look: characterLooks[look]!,
        face: _face(feeling),
        move: CharacterMove(stance: stance),
        updated: DateTime(2026, 11, 3),
      ),
      picture: "assets/canvas/character_cast/${name.toLowerCase()}.png",
    );

/// readyMadeCast is the cast, in the order it is listed.
final List<ReadyMade> readyMadeCast = [
  _made(
      "Ada",
      "Vivi",
      _shape("longbob",
          values: {"age": 28}, colours: {"colour.hair": 0x3b2a20}),
      outfit: CharacterOutfit.asDesigned.casual(male: false),
      feeling: "Happy"),
  _made(
      "Theo",
      "HairSample_Male",
      _shape("tousled",
          values: {"age": 34, "muscle.definition": 0.4},
          colours: {"colour.hair": 0x6b4a2b}),
      look: "Clean ink",
      outfit: CharacterOutfit.asDesigned.casual(male: true),
      stance: "Confident"),
  _made(
      "Mira",
      "Victoria_Rubin",
      _shape("sidetails",
          values: {"age": 22}, colours: {"colour.hair": 0x8c2f39}),
      look: "Pastel",
      feeling: "Happy",
      stance: "Hands behind"),
  _made("Juno", "Vita",
      _shape("pixie", values: {"age": 45}, colours: {"colour.hair": 0x1d1d22}),
      look: "Comic",
      outfit: CharacterOutfit.asDesigned.casual(male: false),
      stance: "Arms crossed"),
  _made("Walter", "HairSample_Male", _shape("spiky", values: {"age": 76}),
      look: "Watercolour",
      outfit: CharacterOutfit.asDesigned.casual(male: true),
      feeling: "Happy",
      stance: "Hands behind"),
  _made(
      "Kit",
      "Vivi",
      _shape("twintails",
          values: {"age": 18}, colours: {"colour.hair": 0xd8a7c9}),
      look: "Manga",
      feeling: "Happy",
      stance: "Peace"),
];
