import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_wardrobe.dart';

// character_types.dart is the kinds of character there are to start from --
// a woman, a boy, a dog, a hedgehog -- each as a starting body and face,
// and what the panel offers it: people have body types and clothes,
// animals fur and a stance, creatures wings and horns.

/// TypeFamily is the kinds of type, as the panel groups them.
enum TypeFamily {
  people("People"),
  animals("Animals"),
  creatures("Creatures");

  final String label;
  const TypeFamily(this.label);
}

/// CharacterType is a kind of character.
enum CharacterType {
  woman("Woman", TypeFamily.people),
  man("Man", TypeFamily.people),
  girl("Girl", TypeFamily.people),
  boy("Boy", TypeFamily.people),
  baby("Baby", TypeFamily.people),
  elder("Older adult", TypeFamily.people),
  dog("Dog", TypeFamily.animals),
  cat("Cat", TypeFamily.animals),
  fox("Fox", TypeFamily.animals),
  rabbit("Rabbit", TypeFamily.animals),
  bear("Bear", TypeFamily.animals),
  mouse("Mouse", TypeFamily.animals),
  pig("Pig", TypeFamily.animals),
  hedgehog("Hedgehog", TypeFamily.animals),
  horse("Horse", TypeFamily.animals),
  bird("Bird", TypeFamily.animals),
  fish("Fish", TypeFamily.animals),
  dragon("Dragon", TypeFamily.creatures),
  monster("Monster", TypeFamily.creatures);

  final String label;
  final TypeFamily family;
  const CharacterType(this.label, this.family);

  bool get person => family == TypeFamily.people;

  static CharacterType? fromName(String? name) {
    for (var t in values) {
      if (t.name == name) return t;
    }
    return null;
  }

  /// guess is what a character saved before types most likely is, from its
  /// species and its size.
  static CharacterType guess(CharacterDna dna) {
    switch (dna.species) {
      case Species.human:
        var long = dna.hairStyle == HairStyle.long ||
            dna.hairStyle == HairStyle.bun;
        if (dna.headsTall < 3.2) return baby;
        if (dna.headsTall < 4.7) return long ? girl : boy;
        return long ? woman : man;
      case Species.cat:
        return cat;
      case Species.dog:
        return dog;
      case Species.fox:
        return fox;
      case Species.bear:
        return bear;
      case Species.rabbit:
        return rabbit;
      case Species.mouse:
        return mouse;
      case Species.pig:
        return pig;
      case Species.hedgehog:
        return hedgehog;
      case Species.horse:
        return horse;
      case Species.bird:
        return bird;
      case Species.fish:
        return fish;
      case Species.monster:
        return dna.wings != WingKind.none ? dragon : monster;
    }
  }

  /// dna is a new character of this type.
  CharacterDna get dna => switch (this) {
        woman => const CharacterDna(
            type: woman,
            headsTall: 6,
            build: 0.35,
            skin: Color(0xFFE9B994),
            hair: Color(0xFF2B1B14),
            hairStyle: HairStyle.long,
            eyes: Color(0xFF4A3426),
            look: Appearance({
              Look.shoulders: -0.3,
              Look.chest: 0.5,
              Look.waist: -0.45,
              Look.hips: 0.5,
              Look.neckWidth: -0.3,
              Look.jaw: -0.4,
              Look.chin: 0.3,
              Look.eyeSize: 0.2,
              Look.lashes: 0.6,
              Look.browThickness: -0.3,
              Look.browArch: 0.4,
              Look.upperLip: 0.3,
              Look.lowerLip: 0.4,
              Look.lipColour: 0.4,
              Look.noseWidth: -0.3,
            }),
            wardrobe: [
              ...baseLayer_,
              Garment(GarmentKind.jeans, color: Color(0xFF3E5A7A)),
              Garment(GarmentKind.tee, color: Color(0xFFF2EDE4)),
              Garment(GarmentKind.trainers, color: Color(0xFFF2F2F2)),
            ],
          ),
        man => const CharacterDna(
            type: man,
            headsTall: 6.5,
            build: 0.6,
            skin: Color(0xFFD9A17E),
            hair: Color(0xFF2A1E16),
            hairStyle: HairStyle.short,
            eyes: Color(0xFF3B2A1E),
            look: Appearance({
              Look.shoulders: 0.4,
              Look.neckWidth: 0.4,
              Look.jaw: 0.5,
              Look.chin: -0.2,
              Look.browThickness: 0.4,
              Look.browHeight: -0.2,
              Look.noseLength: 0.2,
              Look.upperLip: -0.2,
            }),
            wardrobe: [
              ...baseLayer_,
              Garment(GarmentKind.trousers, color: Color(0xFF2F3E5C)),
              Garment(GarmentKind.hoodie, color: Color(0xFF5B9CFF)),
              Garment(GarmentKind.trainers, color: Color(0xFFF2F2F2)),
            ],
          ),
        girl => const CharacterDna(
            type: girl,
            headsTall: 4.3,
            build: 0.3,
            skin: Color(0xFFF2C7A5),
            hair: Color(0xFF6B3A1E),
            hairStyle: HairStyle.long,
            eyes: Color(0xFF3F5F2A),
            look: Appearance({
              Look.eyeSize: 0.5,
              Look.iris: 0.3,
              Look.cheeks: 0.4,
              Look.noseLength: -0.5,
              Look.noseWidth: -0.3,
              Look.chin: -0.3,
              Look.lashes: 0.3,
              Look.freckles: 0.3,
            }),
            wardrobe: [
              ...baseLayer_,
              Garment(GarmentKind.dress, color: Color(0xFFE76F8A)),
              Garment(GarmentKind.trainers, color: Color(0xFFF2F2F2)),
            ],
          ),
        boy => const CharacterDna(
            type: boy,
            headsTall: 4.3,
            build: 0.4,
            skin: Color(0xFFC68E63),
            hair: Color(0xFF1C1410),
            hairStyle: HairStyle.short,
            eyes: Color(0xFF2E2016),
            look: Appearance({
              Look.eyeSize: 0.45,
              Look.cheeks: 0.35,
              Look.noseLength: -0.5,
              Look.chin: -0.3,
              Look.earSize: 0.2,
            }),
            wardrobe: [
              ...baseLayer_,
              Garment(GarmentKind.shorts, color: Color(0xFF355070)),
              Garment(GarmentKind.tee, color: Color(0xFFF2B33D)),
              Garment(GarmentKind.trainers, color: Color(0xFFF2F2F2)),
            ],
          ),
        baby => const CharacterDna(
            type: baby,
            headsTall: 3,
            build: 0.55,
            skin: Color(0xFFF6D3B8),
            hair: Color(0xFFB9874E),
            hairStyle: HairStyle.short,
            eyes: Color(0xFF3A5A7A),
            look: Appearance({
              Look.eyeSize: 0.7,
              Look.iris: 0.5,
              Look.cheeks: 0.9,
              Look.belly: 0.6,
              Look.armLength: -0.4,
              Look.legLength: -0.5,
              Look.noseLength: -0.8,
              Look.noseTip: 0.4,
              Look.chin: -0.6,
              Look.hairLength: -0.8,
              Look.hairVolume: -0.6,
              Look.blush: 0.4,
            }),
            wardrobe: [
              ...baseLayer_,
              Garment(GarmentKind.tee, color: Color(0xFFBFE3F2)),
              Garment(GarmentKind.shorts, color: Color(0xFFBFE3F2)),
            ],
          ),
        elder => const CharacterDna(
            type: elder,
            headsTall: 6.2,
            build: 0.45,
            skin: Color(0xFFE2B392),
            hair: Color(0xFFC9C7C2),
            hairStyle: HairStyle.short,
            eyes: Color(0xFF4F6B7A),
            look: Appearance({
              Look.age: 0.85,
              Look.posture: 0.45,
              Look.lids: 0.4,
              Look.cheeks: -0.3,
              Look.earSize: 0.3,
              Look.noseLength: 0.3,
              Look.hairVolume: -0.4,
              Look.hairline: -0.5,
              Look.belly: 0.3,
            }),
            wardrobe: [
              ...baseLayer_,
              Garment(GarmentKind.trousers, color: Color(0xFF4A4E5A)),
              Garment(GarmentKind.shirt, color: Color(0xFFE8E2D6)),
              Garment(GarmentKind.cardigan, color: Color(0xFF6B7FA6)),
              Garment(GarmentKind.boots, color: Color(0xFF3A2A20)),
            ],
          ),
        dog => const CharacterDna(
            type: dog,
            headsTall: 3.2,
            build: 0.6,
            skin: Color(0xFFC98F52),
            hair: Color(0xFF8A5A32),
            hairStyle: HairStyle.bald,
            eyes: Color(0xFF2A1A10),
            species: Species.dog,
            fourLegs: true,
            tail: TailKind.long,
            fur2: Color(0xFFF1D8B8),
            wardrobe: [],
          ),
        cat => const CharacterDna(
            type: cat,
            headsTall: 3,
            build: 0.4,
            skin: Color(0xFF6E6A66),
            hair: Color(0xFF4A4642),
            hairStyle: HairStyle.bald,
            eyes: Color(0xFF8FBF3A),
            species: Species.cat,
            fourLegs: true,
            tail: TailKind.long,
            fur2: Color(0xFFEDE8E2),
            wardrobe: [],
          ),
        fox => const CharacterDna(
            type: fox,
            headsTall: 4,
            build: 0.35,
            skin: Color(0xFFE8762C),
            hair: Color(0xFFE8762C),
            hairStyle: HairStyle.bald,
            eyes: Color(0xFF2A1A10),
            species: Species.fox,
            tail: TailKind.bushy,
            fur2: Color(0xFFFBF1E6),
            wardrobe: [Garment(GarmentKind.scarf, color: Color(0xFF3D7EFF))],
          ),
        rabbit => const CharacterDna(
            type: rabbit,
            headsTall: 3.6,
            build: 0.4,
            skin: Color(0xFFD8CFC4),
            hair: Color(0xFFBDB2A4),
            hairStyle: HairStyle.bald,
            eyes: Color(0xFF2A1A10),
            species: Species.rabbit,
            tail: TailKind.stub,
            fur2: Color(0xFFFFFFFF),
            wardrobe: [],
          ),
        bear => const CharacterDna(
            type: bear,
            headsTall: 3.8,
            build: 0.9,
            skin: Color(0xFF7A5234),
            hair: Color(0xFF5A3A22),
            hairStyle: HairStyle.bald,
            eyes: Color(0xFF1B1512),
            species: Species.bear,
            tail: TailKind.stub,
            fur2: Color(0xFFC9A37A),
            look: Appearance({Look.belly: 0.6}),
            wardrobe: [],
          ),
        mouse => const CharacterDna(
            type: mouse,
            headsTall: 3.2,
            build: 0.3,
            skin: Color(0xFF9E9A96),
            hair: Color(0xFF7A7672),
            hairStyle: HairStyle.bald,
            eyes: Color(0xFF1B1512),
            species: Species.mouse,
            tail: TailKind.long,
            fur2: Color(0xFFF2D6D6),
            wardrobe: [],
          ),
        pig => const CharacterDna(
            type: pig,
            headsTall: 3.4,
            build: 0.8,
            skin: Color(0xFFF2A9B5),
            hair: Color(0xFFE08A9A),
            hairStyle: HairStyle.bald,
            eyes: Color(0xFF1B1512),
            species: Species.pig,
            tail: TailKind.curly,
            fur2: Color(0xFFF7C9D1),
            look: Appearance({Look.belly: 0.7}),
            wardrobe: [],
          ),
        hedgehog => const CharacterDna(
            type: hedgehog,
            headsTall: 3,
            build: 0.6,
            skin: Color(0xFFD9B48C),
            hair: Color(0xFF5A4030),
            hairStyle: HairStyle.bald,
            eyes: Color(0xFF1B1512),
            species: Species.hedgehog,
            spikes: true,
            fur2: Color(0xFFF2DEC4),
            look: Appearance({Look.belly: 0.5}),
            wardrobe: [],
          ),
        horse => const CharacterDna(
            type: horse,
            headsTall: 3.6,
            build: 0.6,
            skin: Color(0xFF8B5A3C),
            hair: Color(0xFF2A1A12),
            hairStyle: HairStyle.short,
            eyes: Color(0xFF1B1512),
            species: Species.horse,
            fourLegs: true,
            tail: TailKind.bushy,
            fur2: Color(0xFFE8D6C4),
            look: Appearance({Look.legLength: 0.4}),
            wardrobe: [],
          ),
        bird => const CharacterDna(
            type: bird,
            headsTall: 2.8,
            build: 0.8,
            skin: Color(0xFF8A623F),
            hair: Color(0xFF6B4A33),
            hairStyle: HairStyle.bald,
            eyes: Color(0xFFF2A33A),
            species: Species.bird,
            fur2: Color(0xFFF2A33A),
            wardrobe: [],
          ),
        fish => const CharacterDna(
            type: fish,
            headsTall: 3,
            build: 0.7,
            skin: Color(0xFF3DA5D9),
            hair: Color(0xFF2A7AA8),
            hairStyle: HairStyle.bald,
            eyes: Color(0xFF1B1512),
            species: Species.fish,
            fur2: Color(0xFFE8F6FF),
            wardrobe: [],
          ),
        dragon => const CharacterDna(
            type: dragon,
            headsTall: 3.4,
            build: 0.8,
            skin: Color(0xFF8B6CD6),
            hair: Color(0xFF5A3FA0),
            hairStyle: HairStyle.bald,
            eyes: Color(0xFFF2C14E),
            species: Species.monster,
            fourLegs: true,
            tail: TailKind.dragon,
            wings: WingKind.bat,
            horns: HornKind.small,
            fangs: true,
            fur2: Color(0xFFF2C14E),
            wardrobe: [],
          ),
        monster => const CharacterDna(
            type: monster,
            headsTall: 2.6,
            build: 1,
            skin: Color(0xFF7BC96F),
            hair: Color(0xFF3A7A33),
            hairStyle: HairStyle.bald,
            eyes: Color(0xFF2A1D3A),
            species: Species.monster,
            eyeCount: 1,
            horns: HornKind.small,
            fangs: true,
            spikes: true,
            fur2: Color(0xFFE8F2C8),
            wardrobe: [],
          ),
      };

  /// becomes is [dna] made this type: its body, face and stance from the
  /// type, but -- between two kinds of person -- its colours and its
  /// clothes kept, so a woman made a girl is the same person younger.
  CharacterDna becomes(CharacterDna dna) {
    var base = this.dna;
    if (!person || !dna.kind.person) return base;
    return base.copyWith(
      skin: dna.skin,
      hair: dna.hair,
      hair2: dna.hair2,
      eyes: dna.eyes,
      wardrobe: dna.wardrobe,
      baseLayer: dna.baseLayer,
    );
  }
}
