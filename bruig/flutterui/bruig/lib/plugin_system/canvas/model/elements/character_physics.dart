import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// character_physics.dart is what follows a character's movement rather than
// being keyed: its hair, swinging after the head and settling, as Spine's
// physics constraints and Live2D's physics move hair and hems. Worked out
// from the movement itself, so it is the same in the editor, a game and an
// export. See render/character/character_physics.dart.

/// HairPhysics is how a character's hair follows it: [stiffness] how
/// quickly it comes back, [weight] how far it is thrown, [bounce] how long
/// it swings before it settles.
class HairPhysics {
  final bool on;
  final double stiffness;
  final double weight;
  final double bounce;
  const HairPhysics(
      {this.on = true,
      this.stiffness = 0.5,
      this.weight = 0.5,
      this.bounce = 0.5});

  HairPhysics copyWith(
          {bool? on, double? stiffness, double? weight, double? bounce}) =>
      HairPhysics(
          on: on ?? this.on,
          stiffness: (stiffness ?? this.stiffness).clamp(0.0, 1.0),
          weight: (weight ?? this.weight).clamp(0.0, 1.0),
          bounce: (bounce ?? this.bounce).clamp(0.0, 1.0));

  bool get isDefault => this == const HairPhysics();

  Map<String, dynamic> toJson() => {
        if (!on) "on": false,
        if (stiffness != 0.5) "stiffness": stiffness,
        if (weight != 0.5) "weight": weight,
        if (bounce != 0.5) "bounce": bounce,
      };

  static HairPhysics fromJson(Object? json) {
    if (json is! Map) return const HairPhysics();
    return HairPhysics(
        on: json["on"] != false,
        stiffness: jsonDouble(json["stiffness"], 0.5).clamp(0.0, 1.0),
        weight: jsonDouble(json["weight"], 0.5).clamp(0.0, 1.0),
        bounce: jsonDouble(json["bounce"], 0.5).clamp(0.0, 1.0));
  }

  @override
  bool operator ==(Object other) =>
      other is HairPhysics &&
      other.on == on &&
      other.stiffness == stiffness &&
      other.weight == weight &&
      other.bounce == bounce;

  @override
  int get hashCode => Object.hash(on, stiffness, weight, bounce);
}
