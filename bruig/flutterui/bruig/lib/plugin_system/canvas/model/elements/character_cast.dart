import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_wardrobe.dart';

// character_cast.dart is the characters and poses Canvas comes with.
//
// Every one is a starting point rather than a finished thing: choosing one
// copies its DNA or its angles onto the character, and from then on they are
// the character's own to change.

/// CastMember is one ready-made character.
class CastMember {
  final String name;

  /// about is what they are, in a few words, under their tile.
  final String about;
  final CharacterDna dna;

  const CastMember(this.name, this.about, this.dna);
}

/// characterCast is who a new character can start as. The first is who
/// arrives when one is added.
const List<CastMember> characterCast = [
  CastMember("Juno", "Hoodie, short hair",
      CharacterDna(type: CharacterType.man)),
  CastMember(
      "Rosa",
      "Long hair, T-shirt",
      CharacterDna(
        type: CharacterType.woman,
        headsTall: 5.5,
        build: 0.35,
        skin: Color(0xFF8D5A3B),
        hair: Color(0xFF1A1210),
        hairStyle: HairStyle.long,
        eyes: Color(0xFF3A2416),
        wardrobe: [
          ...baseLayer_,
          Garment(GarmentKind.jeans, color: Color(0xFF3F4F3C)),
          Garment(GarmentKind.tee, color: Color(0xFFE6B33D)),
          Garment(GarmentKind.boots, color: Color(0xFF6A4A3A)),
        ],
      )),
  CastMember(
      "Kenji",
      "Shirt and tie, taller",
      CharacterDna(
        type: CharacterType.man,
        headsTall: 6.5,
        build: 0.55,
        skin: Color(0xFFF0CDAE),
        hair: Color(0xFF141414),
        hairStyle: HairStyle.short,
        eyes: Color(0xFF2E2016),
        wardrobe: [
          ...baseLayer_,
          Garment(GarmentKind.trousers, color: Color(0xFF2B2F4A)),
          Garment(GarmentKind.shirt, color: Color(0xFFF4F4F4)),
          Garment(GarmentKind.trainers, color: Color(0xFF3A2A20)),
          Garment(GarmentKind.tie, color: Color(0xFF3D7EFF)),
          Garment(GarmentKind.squareGlasses, color: Color(0xFF1E1E1E)),
        ],
      )),
  CastMember(
      "Mae",
      "Chibi, dress",
      CharacterDna(
        type: CharacterType.girl,
        headsTall: 3,
        build: 0.3,
        skin: Color(0xFFF6D3B8),
        hair: Color(0xFFC46A2F),
        hairStyle: HairStyle.bun,
        eyes: Color(0xFF4A6B2A),
        wardrobe: [
          ...baseLayer_,
          Garment(GarmentKind.dress, color: Color(0xFFF2A65A),
              pattern: GarmentPattern.dots, color2: Color(0xFFFFF3E0)),
          Garment(GarmentKind.sandals, color: Color(0xFFFFFFFF)),
        ],
      )),
  CastMember(
      "Ade",
      "Curly hair, shorts",
      CharacterDna(
        type: CharacterType.boy,
        headsTall: 5,
        build: 0.7,
        skin: Color(0xFF6B4029),
        hair: Color(0xFF151515),
        hairStyle: HairStyle.curly,
        eyes: Color(0xFF2A1A10),
        wardrobe: [
          ...baseLayer_,
          Garment(GarmentKind.shorts, color: Color(0xFF355070)),
          Garment(GarmentKind.tee, color: Color(0xFFE05A47),
              pattern: GarmentPattern.stripes, color2: Color(0xFFF4F4F4)),
          Garment(GarmentKind.trainers, color: Color(0xFFF2F2F2)),
          Garment(GarmentKind.cap, color: Color(0xFF355070)),
        ],
      )),
  CastMember(
      "Pip",
      "Fox, on two legs",
      CharacterDna(
        type: CharacterType.fox,
        headsTall: 4,
        build: 0.35,
        skin: Color(0xFFE8762C),
        hair: Color(0xFFE8762C),
        hairStyle: HairStyle.bald,
        eyes: Color(0xFF2A1A10),
        species: Species.fox,
        tail: TailKind.bushy,
        fur2: Color(0xFFFBF1E6),
        wardrobe: [
          Garment(GarmentKind.scarf, color: Color(0xFF3D7EFF)),
        ],
      )),
  CastMember(
      "Biscuit",
      "Dog, four legs",
      CharacterDna(
        type: CharacterType.dog,
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
      )),
  CastMember(
      "Grub",
      "Monster, one eye",
      CharacterDna(
        type: CharacterType.monster,
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
      )),
  CastMember(
      "Ember",
      "Dragon, wings and tail",
      CharacterDna(
        type: CharacterType.dragon,
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
      )),
  CastMember(
      "Ollie",
      "Owl",
      CharacterDna(
        type: CharacterType.bird,
        headsTall: 2.8,
        build: 0.8,
        skin: Color(0xFF8A623F),
        hair: Color(0xFF6B4A33),
        hairStyle: HairStyle.bald,
        eyes: Color(0xFFF2A33A),
        species: Species.bird,
        fur2: Color(0xFFF2A33A),
        wardrobe: [],
      )),
  CastMember(
      "Finn",
      "Fish",
      CharacterDna(
        type: CharacterType.fish,
        headsTall: 3,
        build: 0.7,
        skin: Color(0xFF3DA5D9),
        hair: Color(0xFF2A7AA8),
        hairStyle: HairStyle.bald,
        eyes: Color(0xFF1B1512),
        species: Species.fish,
        fur2: Color(0xFFE8F6FF),
        wardrobe: [],
      )),
  // Ken's anime boy: drawn in the Anime style, he is the reference.
  CastMember(
      "Kai",
      "Anime boy, oversized hoodie",
      CharacterDna(
        type: CharacterType.boy,
        headsTall: 3.7,
        build: 0.4,
        skin: Color(0xFFF6DCC6),
        hair: Color(0xFF1A1A1F),
        hairStyle: HairStyle.short,
        eyes: Color(0xFFC0303A),
        look: Appearance({
          Look.neckLength: 0.25,
          Look.eyeSize: 0.35,
          Look.mouthWidth: -0.35,
          Look.cheeks: 0.35,
          Look.noseLength: -0.5,
          Look.chin: -0.3,
          Look.earSize: 0.2,
        }),
        wardrobe: [
          ...baseLayer_,
          Garment(GarmentKind.joggers, color: Color(0xFF3B2A26), fit: 1.08),
          Garment(GarmentKind.hoodie, color: Color(0xFFF07A3E), fit: 1.3),
          Garment(GarmentKind.trainers, color: Color(0xFFE5393B)),
        ],
      )),
];

/// PosePreset is one ready-made stance.
class PosePreset {
  final String name;
  final CharacterPose pose;
  const PosePreset(this.name, this.pose);
}

/// posePresets is the stances the Pose section offers, standing first.
const List<PosePreset> posePresets = [
  PosePreset("Stand", CharacterElement.restPose),
  PosePreset(
      "Wave",
      CharacterPose({
        CharacterBone.upperArmL: 10,
        CharacterBone.foreArmL: -4,
        CharacterBone.upperArmR: -130,
        CharacterBone.foreArmR: -30,
        CharacterBone.head: 6,
        CharacterBone.thighL: 3,
        CharacterBone.thighR: -3,
      })),
  PosePreset(
      "Point",
      CharacterPose({
        CharacterBone.upperArmL: 8,
        CharacterBone.foreArmL: -4,
        CharacterBone.upperArmR: -95,
        CharacterBone.thighL: 4,
        CharacterBone.thighR: -2,
        CharacterBone.head: -4,
      })),
  PosePreset(
      "Cheer",
      CharacterPose({
        CharacterBone.upperArmL: 150,
        CharacterBone.foreArmL: 15,
        CharacterBone.upperArmR: -150,
        CharacterBone.foreArmR: -15,
        CharacterBone.thighL: 10,
        CharacterBone.thighR: -10,
      })),
  PosePreset(
      "Hands on hips",
      CharacterPose({
        CharacterBone.upperArmL: 45,
        CharacterBone.foreArmL: -95,
        CharacterBone.upperArmR: -45,
        CharacterBone.foreArmR: 95,
        CharacterBone.thighL: 7,
        CharacterBone.thighR: -7,
      })),
  PosePreset(
      "Shrug",
      CharacterPose({
        CharacterBone.upperArmL: 30,
        CharacterBone.foreArmL: 70,
        CharacterBone.upperArmR: -30,
        CharacterBone.foreArmR: -70,
        CharacterBone.head: 10,
        CharacterBone.thighL: 3,
        CharacterBone.thighR: -3,
      })),
  PosePreset(
      "Think",
      CharacterPose({
        CharacterBone.upperArmL: 25,
        CharacterBone.foreArmL: -110,
        CharacterBone.upperArmR: -20,
        CharacterBone.foreArmR: 150,
        CharacterBone.head: -8,
        CharacterBone.thighL: 3,
        CharacterBone.thighR: -3,
      })),
  // Weight on one leg. Not a walk: a stride only reads from the side, and
  // a character seen from the front with its arms swung across its body
  // looks like it is hugging itself.
  PosePreset(
      "Relaxed",
      CharacterPose({
        CharacterBone.spine: 4,
        CharacterBone.head: -6,
        CharacterBone.upperArmL: 6,
        CharacterBone.foreArmL: -3,
        CharacterBone.upperArmR: -8,
        CharacterBone.foreArmR: 6,
        CharacterBone.thighL: 9,
        CharacterBone.shinL: -3,
        CharacterBone.thighR: -2,
      })),
  // Weight on one leg, the hips tilted up on that side and the shoulders
  // the other way, the free knee easy and the head inclined: the stance a
  // character sheet draws a figure in.
  PosePreset(
      "Contrapposto",
      CharacterPose({
        CharacterBone.hips: 7,
        CharacterBone.spine: -4,
        CharacterBone.head: 6,
        CharacterBone.upperArmL: 9,
        CharacterBone.foreArmL: -8,
        CharacterBone.upperArmR: -14,
        CharacterBone.foreArmR: 18,
        CharacterBone.thighL: 4,
        CharacterBone.thighR: -9,
        CharacterBone.shinR: 10,
      })),
];

/// ExpressionPreset is one ready-made feeling.
class ExpressionPreset {
  final String name;
  final CharacterFace face;
  const ExpressionPreset(this.name, this.face);
}

/// expressionPresets is the feelings the Face section offers, neutral first.
const List<ExpressionPreset> expressionPresets = [
  ExpressionPreset("Neutral", CharacterFace.rest),
  ExpressionPreset(
      "Happy",
      CharacterFace({
        FaceControl.smile: 0.8,
        FaceControl.browRaise: 0.2,
        FaceControl.squint: 0.25,
      })),
  ExpressionPreset(
      "Laugh",
      CharacterFace({
        FaceControl.smile: 1,
        FaceControl.jaw: 0.7,
        FaceControl.squint: 0.65,
        FaceControl.browRaise: 0.3,
      })),
  ExpressionPreset(
      "Sad",
      CharacterFace({
        FaceControl.smile: -0.7,
        FaceControl.browWorry: 0.9,
        FaceControl.eyesOpen: 0.8,
        FaceControl.lookY: -0.4,
      })),
  ExpressionPreset(
      "Worried",
      CharacterFace({
        FaceControl.smile: -0.3,
        FaceControl.browWorry: 0.8,
        FaceControl.browRaise: 0.2,
        FaceControl.wide: -0.2,
      })),
  ExpressionPreset(
      "Angry",
      CharacterFace({
        FaceControl.browSqueeze: 1,
        FaceControl.browRaise: -0.4,
        FaceControl.smile: -0.6,
        FaceControl.squint: 0.3,
      })),
  ExpressionPreset(
      "Surprised",
      CharacterFace({
        FaceControl.browRaise: 1,
        FaceControl.eyesOpen: 1.3,
        FaceControl.jaw: 0.6,
        FaceControl.wide: -0.4,
      })),
  ExpressionPreset(
      "Scared",
      CharacterFace({
        FaceControl.browWorry: 1,
        FaceControl.browRaise: 0.6,
        FaceControl.eyesOpen: 1.3,
        FaceControl.jaw: 0.3,
        FaceControl.smile: -0.4,
        FaceControl.wide: 0.5,
      })),
  ExpressionPreset(
      "Disgusted",
      CharacterFace({
        FaceControl.browSqueeze: 0.7,
        FaceControl.squint: 0.6,
        FaceControl.smile: -0.5,
        FaceControl.wide: 0.4,
      })),
  ExpressionPreset(
      "Thinking",
      CharacterFace({
        FaceControl.browRaise: 0.3,
        FaceControl.lookX: 0.5,
        FaceControl.lookY: 0.6,
        FaceControl.smile: -0.1,
        FaceControl.wide: -0.3,
      })),
  ExpressionPreset(
      "Smug",
      CharacterFace({
        FaceControl.smile: 0.5,
        FaceControl.squint: 0.5,
        FaceControl.browRaise: -0.1,
        FaceControl.lookX: -0.3,
      })),
  ExpressionPreset(
      "Sleepy",
      CharacterFace({
        FaceControl.eyesOpen: 0.25,
        FaceControl.browRaise: -0.2,
        FaceControl.jaw: 0.08,
      })),
];
