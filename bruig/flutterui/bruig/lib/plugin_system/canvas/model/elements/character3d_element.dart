import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_performance.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';

// character3d_element.dart is a new 3D character on the canvas: one made in
// the Character Studio (character_design.dart), drawn by Flutter GPU
// (render/vrm/vrm_character.dart) inside its box, from the side and as close
// as the element says.
//
// The design is kept in the element, whole, rather than looked up in the
// library by its id: a canvas sent to somebody else, or published, has no
// library to look in. The id is kept as well, so that changing the character
// in the Studio changes every copy of it.

/// Character3dFraming is how much of the character the box shows.
enum Character3dFraming {
  body("Whole body"),
  waist("Waist up"),
  head("Head");

  final String label;
  const Character3dFraming(this.label);

  static Character3dFraming fromName(Object? name) =>
      values.where((f) => f.name == name).firstOrNull ?? body;
}

class Character3dElement extends CanvasElement {
  final CharacterDesign design;
  final Character3dFraming framing;

  /// turn is which way round it is seen, -1 to 1: a half turn either way
  /// from the front. tilt is from how far above, -0.5 (from below) to 1
  /// (from overhead), as a share of a quarter turn.
  final double turn, tilt;

  /// zoom is how much closer than the framing, 0.5 to 3.
  final double zoom;

  /// performance is what it does in this scene: how it stands, the
  /// motions it plays, its feeling, the line it says (character_
  /// performance.dart).
  final CharacterPerformance performance;

  /// expression is the expression it wears in this scene, by name -- one
  /// of its face's -- or null for the one it was designed with: the
  /// performance's feeling.
  String? get expression => performance.feeling;

  /// worn is the design in what the scene has it wear: one of the Studio's
  /// quick changes, or as designed.
  CharacterDesign get worn {
    final o = design.outfit, male = design.body == "HairSample_Male";
    return switch (performance.wearing) {
      "Underwear only" => design.dressed(o.underwearOnly(male: male)),
      "Swimwear" => design.dressed(o.swimwear(male: male)),
      "Casual" => design.dressed(o.casual(male: male)),
      _ => design,
    };
  }

  final ElementAnimation animation;

  const Character3dElement(
    super.base, {
    required this.design,
    this.framing = Character3dFraming.body,
    this.turn = 0,
    this.tilt = 0,
    this.zoom = 1,
    this.performance = const CharacterPerformance(),
    this.animation = const ElementAnimation(),
  });

  @override
  ElementKind get kind => ElementKind.character3d;

  /// assetIds are the library pictures its decals are cut from; mediaIds
  /// the vectors.
  @override
  Set<String> get assetIds => design.pictureIds;

  @override
  Set<String> get mediaIds => design.vectorIds;

  @override
  CanvasElement rebase(ElementBase base) => Character3dElement(base,
      design: design,
      framing: framing,
      turn: turn,
      tilt: tilt,
      zoom: zoom,
      performance: performance,
      animation: animation);

  /// wearing is this with expression [name] in this scene, or with null the
  /// one it was designed with.
  Character3dElement wearing(String? name) => Character3dElement(base,
      design: design,
      framing: framing,
      turn: turn,
      tilt: tilt,
      zoom: zoom,
      performance: CharacterPerformance.fromJson(
          performance.toJson()..remove("feeling"),
          feeling: name),
      animation: animation);

  /// performing is this doing [p] in this scene.
  Character3dElement performing(CharacterPerformance p) =>
      Character3dElement(base,
          design: design,
          framing: framing,
          turn: turn,
          tilt: tilt,
          zoom: zoom,
          performance: p,
          animation: animation);

  Character3dElement copyWith({
    CharacterDesign? design,
    Character3dFraming? framing,
    double? turn,
    double? tilt,
    double? zoom,
    ElementAnimation? animation,
  }) =>
      Character3dElement(base,
          design: design ?? this.design,
          framing: framing ?? this.framing,
          turn: turn ?? this.turn,
          tilt: tilt ?? this.tilt,
          zoom: zoom ?? this.zoom,
          performance: performance,
          animation: animation ?? this.animation);

  @override
  Map<String, dynamic> props() => {
        "design": design.toJson(),
        if (framing != Character3dFraming.body) "framing": framing.name,
        if (turn != 0) "turn": turn,
        if (tilt != 0) "tilt": tilt,
        if (zoom != 1) "zoom": zoom,
        if (!performance.isEmpty) "performance": performance.toJson(),
        "animation": animation.toJson(),
      };

  /// fromJson reads what props wrote. A design that cannot be read is a
  /// body as it was made: the box is kept, and can be given a character.
  factory Character3dElement.fromJson(
          Map<String, dynamic> json, ElementBase b) =>
      Character3dElement(b,
          design: CharacterDesign.fromJson(json["design"]) ??
              CharacterDesign(
                  id: "", name: "", body: "Vivi", updated: DateTime(2026)),
          framing: Character3dFraming.fromName(json["framing"]),
          turn: jsonDouble(json["turn"], 0).clamp(-1.0, 1.0),
          tilt: jsonDouble(json["tilt"], 0).clamp(-0.5, 1.0),
          zoom: jsonDouble(json["zoom"], 1).clamp(0.5, 3.0),
          // An expression kept before performances is its feeling.
          performance: CharacterPerformance.fromJson(json["performance"],
              feeling: json["expression"] is String
                  ? json["expression"] as String
                  : null),
          animation: jsonSpec(json["animation"], ElementAnimation.fromJson,
              const ElementAnimation()));
}
