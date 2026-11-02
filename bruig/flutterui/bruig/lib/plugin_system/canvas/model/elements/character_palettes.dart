import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_reference.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_wardrobe.dart';

// character_palettes.dart is what a character is made from when it is not
// drawn by hand: a few colours chosen to go together, people to mix, and a
// character made from them at random. A character creator's good results
// come from what it offers, not from how much it lets you change -- a few
// skins in even steps, natural hair and eyes, clothes in colours that sit
// together (Ken's pick, pjanaya's 2D character creator: 2026-11-01).

/// skinTones are skins in even steps, light to deep, each with a warmer and
/// a cooler of its depth.
const List<Swatch> skinTones = [
  Swatch("Porcelain", Color(0xFFF8E1D3)),
  Swatch("Ivory", Color(0xFFF3D2B9)),
  Swatch("Rose", Color(0xFFEDBFA8)),
  Swatch("Beige", Color(0xFFE2B48C)),
  Swatch("Honey", Color(0xFFD69E6E)),
  Swatch("Olive", Color(0xFFC08F62)),
  Swatch("Caramel", Color(0xFFAE7448)),
  Swatch("Bronze", Color(0xFF9A6240)),
  Swatch("Chestnut", Color(0xFF7E4A2E)),
  Swatch("Espresso", Color(0xFF5E3620)),
  Swatch("Ebony", Color(0xFF452617)),
];

/// hairColours are natural hair, dark to fair, then three dyed.
const List<Swatch> hairColours = [
  Swatch("Black", Color(0xFF17120F)),
  Swatch("Soft black", Color(0xFF2B211C)),
  Swatch("Dark brown", Color(0xFF3F2A1E)),
  Swatch("Brown", Color(0xFF6A4128)),
  Swatch("Auburn", Color(0xFF8A3B22)),
  Swatch("Copper", Color(0xFFB4562A)),
  Swatch("Light brown", Color(0xFF9A6E45)),
  Swatch("Dark blonde", Color(0xFFB8925A)),
  Swatch("Blonde", Color(0xFFDDBB7C)),
  Swatch("Platinum", Color(0xFFEDE3C9)),
  Swatch("Grey", Color(0xFF9C9A98)),
  Swatch("Plum", Color(0xFF5A2E5E)),
  Swatch("Teal", Color(0xFF1F6F75)),
  Swatch("Rose pink", Color(0xFFD978A0)),
];

/// eyeColours are natural eyes.
const List<Swatch> eyeColours = [
  Swatch("Dark brown", Color(0xFF3A2416)),
  Swatch("Brown", Color(0xFF6B4226)),
  Swatch("Amber", Color(0xFFA0702A)),
  Swatch("Hazel", Color(0xFF7D7A3E)),
  Swatch("Green", Color(0xFF4E7A45)),
  Swatch("Blue", Color(0xFF3E6E9E)),
  Swatch("Light blue", Color(0xFF7FA6C8)),
  Swatch("Grey", Color(0xFF7A8590)),
];

/// clothingColours are colours a wardrobe is made in: muted, so any three
/// go together, with a white and a near black.
const List<Swatch> clothingColours = [
  Swatch("White", Color(0xFFF4F1EA)),
  Swatch("Charcoal", Color(0xFF2E3038)),
  Swatch("Denim", Color(0xFF3F5A86)),
  Swatch("Navy", Color(0xFF263552)),
  Swatch("Forest", Color(0xFF3E6145)),
  Swatch("Sage", Color(0xFF8EA58A)),
  Swatch("Mustard", Color(0xFFD9A93A)),
  Swatch("Rust", Color(0xFFB4562A)),
  Swatch("Brick", Color(0xFF9C3A32)),
  Swatch("Plum", Color(0xFF6A3D6E)),
  Swatch("Lilac", Color(0xFFA996C8)),
  Swatch("Sand", Color(0xFFD8C4A0)),
  Swatch("Coral", Color(0xFFE07A5F)),
  Swatch("Teal", Color(0xFF2F7F86)),
];

/// mixDna is the people in [mix] blended by their weights: how tall in
/// heads, their build, every shape of the face and body, and their skin and
/// eyes. What is not a measure -- the type, the hair, the clothes -- is
/// [onto]'s.
CharacterDna mixDna(CharacterDna onto, List<(CharacterDna, double)> mix) {
  var total = mix.fold(0.0, (t, m) => t + math.max(0.0, m.$2));
  if (mix.isEmpty || total <= 0) return onto;
  double each(double Function(CharacterDna) of) =>
      mix.fold(0.0, (t, m) => t + of(m.$1) * math.max(0.0, m.$2) / total);
  Color colour(Color Function(CharacterDna) of) => Color.from(
      alpha: 1,
      red: each((d) => of(d).r),
      green: each((d) => of(d).g),
      blue: each((d) => of(d).b));
  var look = onto.look;
  for (var l in Look.values) {
    look = look.withValue(l, each((d) => d.look[l]));
  }
  return onto.copyWith(
    headsTall: each((d) => d.headsTall),
    build: each((d) => d.build),
    look: look,
    skin: colour((d) => d.skin),
    eyes: colour((d) => d.eyes),
  );
}

/// _neutrals are the clothing colours anything goes with.
const _neutrals = ["White", "Charcoal", "Denim", "Navy", "Sand"];

Color _clothing(String name) =>
    clothingColours.firstWhere((c) => c.name == name).color;

/// generatedDna is a grown-up made at random from what goes together: two
/// of the cast mixed; a skin, hair -- natural four times in five -- and eyes
/// from the palettes; a hairstyle; facial hair on some men only; and
/// everyday clothes, coloured as a dresser would: the bottom a neutral, the
/// top a colour or another neutral, a layer over it sometimes, one accent.
/// The same [seed] makes the same person.
CharacterDna generatedDna(CharacterDna onto, int seed) {
  var r = math.Random(seed);
  T pick<T>(List<T> from) => from[r.nextInt(from.length)];
  bool chance(double p) => r.nextDouble() < p;
  var woman = chance(0.5);
  var type = woman ? CharacterType.woman : CharacterType.man;
  var adults = [
    for (var c in characterCast)
      if (c.dna.kind == CharacterType.woman || c.dna.kind == CharacterType.man)
        c.dna,
  ];
  var a = pick(adults), b = pick(adults);
  var w = 0.35 + r.nextDouble() * 0.3;
  var dna = mixDna(onto.copyWith(type: type), [(a, w), (b, 1 - w)]);
  // A little of everyone's own -- the face and body, never facial hair.
  const facial = {Look.stubble, Look.moustache, Look.beard, Look.beardLength};
  var look = dna.look;
  for (var l in Look.values) {
    if (facial.contains(l)) {
      look = look.withValue(l, 0);
    } else if (r.nextDouble() < 0.35) {
      look = look.withValue(l, look[l] + (r.nextDouble() - 0.5) * 0.5);
    }
  }
  if (!woman && chance(0.4)) {
    for (var MapEntry(:key, :value) in pick(const [
      {Look.stubble: 0.8},
      {Look.moustache: 0.9},
      {Look.moustache: 0.8, Look.beard: 0.8, Look.beardLength: -0.4},
      {Look.moustache: 0.9, Look.beard: 1.0, Look.beardLength: 0.2},
    ]).entries) {
      look = look.withValue(key, value);
    }
  }
  // The clothes: what is worn, then its colours.
  var dress = woman && chance(0.25);
  var top = dress
      ? null
      : pick(woman
          ? const [
              GarmentKind.tee,
              GarmentKind.blouse,
              GarmentKind.sweater,
              GarmentKind.tank,
              GarmentKind.shirt,
              GarmentKind.hoodie
            ]
          : const [
              GarmentKind.tee,
              GarmentKind.shirt,
              GarmentKind.polo,
              GarmentKind.sweater,
              GarmentKind.hoodie
            ]);
  var bottom = dress
      ? null
      : pick(woman
          ? const [
              GarmentKind.jeans,
              GarmentKind.trousers,
              GarmentKind.skirt,
              GarmentKind.longSkirt,
              GarmentKind.shorts,
              GarmentKind.leggings
            ]
          : const [
              GarmentKind.jeans,
              GarmentKind.trousers,
              GarmentKind.joggers,
              GarmentKind.shorts
            ]);
  var shoes = pick([
    GarmentKind.trainers,
    GarmentKind.trainers,
    GarmentKind.boots,
    GarmentKind.sandals,
    if (woman) GarmentKind.heels,
  ]);
  var layer = chance(0.3)
      ? pick(
          const [GarmentKind.jacket, GarmentKind.cardigan, GarmentKind.blazer])
      : null;
  var mains = [
    for (var c in clothingColours)
      if (!_neutrals.contains(c.name)) c.name,
  ]..shuffle(r);
  var neutrals = [..._neutrals]..shuffle(r);
  var bottomColour = bottom == GarmentKind.jeans ? "Denim" : neutrals.first;
  var topColour =
      chance(0.65) ? mains[0] : neutrals.firstWhere((n) => n != bottomColour);
  var accent = mains[1];
  var wardrobe = [
    ...baseLayer_,
    if (dress) Garment(GarmentKind.dress, color: _clothing(mains[0])),
    if (top != null) Garment(top, color: _clothing(topColour)),
    if (bottom != null) Garment(bottom, color: _clothing(bottomColour)),
    if (layer != null)
      Garment(layer,
          color: _clothing(
              neutrals.firstWhere((n) => n != bottomColour && n != topColour))),
    Garment(shoes, color: _clothing(chance(0.5) ? accent : neutrals.last)),
    if (chance(0.15))
      Garment(pick(const [GarmentKind.roundGlasses, GarmentKind.squareGlasses]),
          color: const Color(0xFF1E1E1E)),
  ];
  return dna.copyWith(
    look: look,
    skin: pick(skinTones).color,
    hair: (chance(0.8)
            ? pick(hairColours.sublist(0, 11))
            : pick(hairColours.sublist(11)))
        .color,
    eyes: pick(eyeColours).color,
    hairStyle: woman
        ? pick(const [
            HairStyle.long,
            HairStyle.bun,
            HairStyle.curly,
            HairStyle.short
          ])
        : pick(const [
            HairStyle.short,
            HairStyle.short,
            HairStyle.curly,
            HairStyle.bald
          ]),
    wardrobe: wardrobe,
    headsTall: (dna.headsTall + (r.nextDouble() - 0.5) * 0.6).clamp(5.0, 7.5),
    build: (dna.build + (r.nextDouble() - 0.5) * 0.3).clamp(0.0, 1.0),
  );
}
