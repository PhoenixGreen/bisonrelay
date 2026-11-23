import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_performance.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';

// character3d_element.dart is a Character Studio character on the canvas,
// drawn by Flutter GPU (render/vrm/vrm_character.dart). Its design is kept
// whole, as a sent canvas has no library; its id too, so a Studio change
// reaches every copy.

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

  /// turn is which way round it is seen, -1 to 1 (half a turn each way);
  /// tilt how far above, -0.5 (below) to 1 (overhead), of a quarter turn.
  final double turn, tilt;

  /// zoom is how much closer than the framing, 0.5 to 3.
  final double zoom;

  /// round is whether it is seen through its box's circle rather than the
  /// whole box: a portrait in a ring, as a game's narrator on its HUD.
  final bool round;

  /// performance is what it does in this scene: how it stands, its motions,
  /// its feeling, its line (character_performance.dart).
  final CharacterPerformance performance;

  /// expression is the face expression it wears in this scene by name, or
  /// null for the one it was designed with: the performance's feeling.
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
    this.round = false,
    this.performance = const CharacterPerformance(),
    this.animation = const ElementAnimation(),
  });

  @override
  ElementKind get kind => ElementKind.character3d;

  /// assetIds are its decals' library pictures; mediaIds the vectors.
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
      round: round,
      performance: performance,
      animation: animation);

  /// wearing is this with expression [name] here, or null for as designed.
  Character3dElement wearing(String? name) => Character3dElement(base,
      design: design,
      framing: framing,
      turn: turn,
      tilt: tilt,
      zoom: zoom,
      round: round,
      performance: CharacterPerformance.fromJson(
          performance.toJson()..remove("feeling"),
          feeling: name),
      animation: animation);

  Character3dElement performing(CharacterPerformance p) =>
      Character3dElement(base,
          design: design,
          framing: framing,
          turn: turn,
          tilt: tilt,
          zoom: zoom,
          round: round,
          performance: p,
          animation: animation);

  Character3dElement copyWith({
    CharacterDesign? design,
    Character3dFraming? framing,
    double? turn,
    double? tilt,
    double? zoom,
    bool? round,
    ElementAnimation? animation,
  }) =>
      Character3dElement(base,
          design: design ?? this.design,
          framing: framing ?? this.framing,
          turn: turn ?? this.turn,
          tilt: tilt ?? this.tilt,
          zoom: zoom ?? this.zoom,
          round: round ?? this.round,
          performance: performance,
          animation: animation ?? this.animation);

  @override
  Character3dElement mapOwnColours(ColourMap f) {
    var p = ColourPass(f);
    var design = p.part(this.design, (d) => d.mapColours(f));
    var animation = p.part(this.animation, (a) => a.mapColours(f));
    if (!p.changed) return this;
    return copyWith(design: design, animation: animation);
  }

  @override
  Map<String, dynamic> props() => {
        "design": design.toJson(),
        if (framing != Character3dFraming.body) "framing": framing.name,
        if (turn != 0) "turn": turn,
        if (tilt != 0) "tilt": tilt,
        if (zoom != 1) "zoom": zoom,
        if (round) "round": true,
        if (!performance.isEmpty) "performance": performance.toJson(),
        "animation": animation.toJson(),
      };

  /// fromJson reads what props wrote. A design that cannot be read leaves a
  /// plain body: the box is kept, and can be given a character.
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
          round: json["round"] == true,
          performance: CharacterPerformance.fromJson(json["performance"]),
          animation: jsonSpec(json["animation"], ElementAnimation.fromJson,
              const ElementAnimation()));
}
