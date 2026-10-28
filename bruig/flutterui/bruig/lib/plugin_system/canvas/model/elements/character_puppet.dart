import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// character_puppet.dart is the body of the doll a sketch is posed and
// drawn over -- see character_doll.dart -- when it is not the character's
// own: a kind of person, how tall in heads and how broad, how much a
// woman's figure, and the body's own sliders. Saved with the character.

/// puppetBodies is the kinds of person the doll can be.
const List<CharacterType> puppetBodies = [
  CharacterType.woman,
  CharacterType.man,
  CharacterType.girl,
  CharacterType.boy,
  CharacterType.baby,
  CharacterType.elder,
];

/// puppetLooks is the sliders that shape the doll: the body's.
final List<Look> puppetLooks = Look.inGroup(AppearanceGroup.body)
    .where((l) => l != Look.posture && l != Look.wrists && l != Look.ankles)
    .toList();

class PuppetForm {
  /// body is the kind of person it starts as.
  final CharacterType body;
  final double headsTall;
  final double build;

  /// feminine is how much a woman's figure it has, nought to one.
  final double feminine;

  /// look is its body's sliders.
  final Appearance look;

  const PuppetForm({
    required this.body,
    required this.headsTall,
    required this.build,
    required this.feminine,
    this.look = Appearance.rest,
  });

  /// of is a doll of kind [t], as that kind is made.
  factory PuppetForm.of(CharacterType t) {
    var dna = t.dna;
    return PuppetForm(
      body: t,
      headsTall: dna.headsTall,
      build: dna.build,
      feminine: t == CharacterType.woman || t == CharacterType.girl ? 1 : 0,
      look: Appearance({
        for (var l in puppetLooks)
          if (dna.look[l] != 0) l: dna.look[l],
      }),
    );
  }

  /// dna is the body the doll is built from.
  CharacterDna get dna =>
      body.dna.copyWith(headsTall: headsTall, build: build, look: look);

  /// isAsMade is whether it is as its kind is made, nothing changed.
  bool get isAsMade => toJson().toString() == PuppetForm.of(body).toJson().toString();

  PuppetForm copyWith({
    double? headsTall,
    double? build,
    double? feminine,
    Appearance? look,
  }) =>
      PuppetForm(
        body: body,
        headsTall: headsTall ?? this.headsTall,
        build: build ?? this.build,
        feminine: feminine ?? this.feminine,
        look: look ?? this.look,
      );

  Map<String, dynamic> toJson() => {
        "body": body.name,
        "headsTall": headsTall,
        "build": build,
        "feminine": feminine,
        if (!look.isRest) "look": look.toJson(),
      };

  static PuppetForm? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    var t = CharacterType.fromName(json["body"] as String?);
    if (t == null || !puppetBodies.contains(t)) return null;
    var made = PuppetForm.of(t);
    return PuppetForm(
      body: t,
      headsTall: jsonDouble(json["headsTall"], made.headsTall).clamp(2.0, 9.0),
      build: jsonDouble(json["build"], made.build).clamp(0.0, 1.0),
      feminine: jsonDouble(json["feminine"], made.feminine).clamp(0.0, 1.0),
      look: Appearance.fromJson(json["look"]),
    );
  }
}
