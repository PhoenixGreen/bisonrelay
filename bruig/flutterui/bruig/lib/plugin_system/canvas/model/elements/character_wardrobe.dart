import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_drawing.dart';

// character_wardrobe.dart is what a character wears: an ordered list of
// garments, from the skin outwards.
//
// A garment is drawn from settings, like the rest of a character: a kind
// from the catalogue, and how long its sleeves are, how far down it comes,
// how loose it is, its colours and pattern, and how worn it is. That is what
// lets one shirt fit a chibi, a teenager and a fox, and redraw in any style.
//
// The kind says where a garment goes and what it starts as -- a hoodie has
// long sleeves and comes to the hip -- and the garment's own numbers say
// how this one differs. Shortening a hoodie's sleeves to the elbow is a
// setting, not another kind.

/// GarmentSlot is the part of the body a garment is worn on. The order here
/// is the order garments are put on, innermost first, so a new garment goes
/// where it belongs.
enum GarmentSlot {
  base("Base layer"),
  bottom("Bottoms"),
  top("Top"),
  full("Dresses & suits"),
  outer("Outerwear"),
  feet("Shoes"),
  neck("Neck"),
  face("Glasses"),
  head("Headwear");

  final String label;
  const GarmentSlot(this.label);
}

/// GarmentShape is how a garment is drawn: which parts of the body it
/// covers, and how.
enum GarmentShape {
  /// torso is over the body, with sleeves.
  torso,

  /// legs is down each leg from the hips.
  legs,

  /// skirt is a flared skirt from the waist.
  skirt,

  /// dress is a top and a skirt in one.
  dress,

  /// cape hangs from the shoulders behind the body.
  cape,

  shoes,
  hat,
  glasses,
  neck,
}

/// GarmentKind is one thing in the catalogue.
enum GarmentKind {
  // Base layer.
  briefs("Briefs", GarmentSlot.base, GarmentShape.legs, length: 0.1, fit: 0.97),
  boxers("Boxers", GarmentSlot.base, GarmentShape.legs, length: 0.28),
  braTop("Bra top", GarmentSlot.base, GarmentShape.torso,
      length: 0.32, sleeve: 0, fit: 0.97),
  vest("Vest", GarmentSlot.base, GarmentShape.torso,
      length: 1.0, sleeve: 0, fit: 0.97),
  swimsuit("Swimsuit", GarmentSlot.base, GarmentShape.torso,
      length: 1.1, sleeve: 0, fit: 0.97),
  tights("Tights", GarmentSlot.base, GarmentShape.legs,
      length: 1.0, fit: 0.9),
  socks("Socks", GarmentSlot.base, GarmentShape.legs,
      length: 1.0, from: 0.82, fit: 0.95),

  // Tops.
  tee("T-shirt", GarmentSlot.top, GarmentShape.torso, length: 1.05, sleeve: 0.45),
  tank("Tank top", GarmentSlot.top, GarmentShape.torso, length: 1.05, sleeve: 0),
  shirt("Shirt", GarmentSlot.top, GarmentShape.torso, length: 1.08, sleeve: 0.95),
  polo("Polo", GarmentSlot.top, GarmentShape.torso, length: 1.05, sleeve: 0.42),
  sweater("Sweater", GarmentSlot.top, GarmentShape.torso,
      length: 1.12, sleeve: 0.97, fit: 1.06),
  hoodie("Hoodie", GarmentSlot.top, GarmentShape.torso,
      length: 1.12, sleeve: 0.97, fit: 1.08),
  blouse("Blouse", GarmentSlot.top, GarmentShape.torso, length: 1.0, sleeve: 0.7),

  // Bottoms.
  trousers("Trousers", GarmentSlot.bottom, GarmentShape.legs, length: 1.0),
  jeans("Jeans", GarmentSlot.bottom, GarmentShape.legs, length: 1.0),

  /// joggers are loose trousers gathered into a ribbed cuff at the ankle.
  joggers("Joggers", GarmentSlot.bottom, GarmentShape.legs,
      length: 0.97, fit: 1.15),
  shorts("Shorts", GarmentSlot.bottom, GarmentShape.legs, length: 0.36),
  leggings("Leggings", GarmentSlot.bottom, GarmentShape.legs,
      length: 0.95, fit: 0.9),
  skirt("Skirt", GarmentSlot.bottom, GarmentShape.skirt, length: 0.45, flare: 1.5),
  longSkirt("Long skirt", GarmentSlot.bottom, GarmentShape.skirt,
      length: 0.95, flare: 1.4),

  // Dresses and suits.
  dress("Dress", GarmentSlot.full, GarmentShape.dress,
      length: 0.55, sleeve: 0.3, flare: 1.9),
  gown("Gown", GarmentSlot.full, GarmentShape.dress,
      length: 1.0, sleeve: 0, flare: 2.2),
  tubeDress("Strapless dress", GarmentSlot.full, GarmentShape.dress,
      length: 0.28, sleeve: 0, flare: 1.06, fit: 0.97),
  overalls("Overalls", GarmentSlot.full, GarmentShape.legs, length: 1.0, fit: 1.08),
  robe("Robe", GarmentSlot.full, GarmentShape.dress,
      length: 0.85, sleeve: 0.9, flare: 1.3),

  // Outerwear.
  jacket("Jacket", GarmentSlot.outer, GarmentShape.torso,
      length: 1.05, sleeve: 0.97, fit: 1.12),
  blazer("Blazer", GarmentSlot.outer, GarmentShape.torso,
      length: 1.28, sleeve: 0.97, fit: 1.1),
  coat("Coat", GarmentSlot.outer, GarmentShape.torso,
      length: 1.9, sleeve: 0.98, fit: 1.16),
  cardigan("Cardigan", GarmentSlot.outer, GarmentShape.torso,
      length: 1.15, sleeve: 0.95, fit: 1.1),
  cape("Cape", GarmentSlot.outer, GarmentShape.cape, length: 0.8, flare: 1.6),

  // Shoes.
  trainers("Trainers", GarmentSlot.feet, GarmentShape.shoes),
  boots("Boots", GarmentSlot.feet, GarmentShape.shoes, length: 0.3),
  heels("Heels", GarmentSlot.feet, GarmentShape.shoes),
  sandals("Sandals", GarmentSlot.feet, GarmentShape.shoes),
  slippers("Slippers", GarmentSlot.feet, GarmentShape.shoes),

  // Neck.
  scarf("Scarf", GarmentSlot.neck, GarmentShape.neck),
  tie("Tie", GarmentSlot.neck, GarmentShape.neck),
  bowTie("Bow tie", GarmentSlot.neck, GarmentShape.neck),
  necklace("Necklace", GarmentSlot.neck, GarmentShape.neck),

  // Glasses.
  roundGlasses("Round glasses", GarmentSlot.face, GarmentShape.glasses),
  squareGlasses("Square glasses", GarmentSlot.face, GarmentShape.glasses),
  sunglasses("Sunglasses", GarmentSlot.face, GarmentShape.glasses),

  // Headwear.
  cap("Cap", GarmentSlot.head, GarmentShape.hat),
  beanie("Beanie", GarmentSlot.head, GarmentShape.hat),
  topHat("Top hat", GarmentSlot.head, GarmentShape.hat),
  sunHat("Sun hat", GarmentSlot.head, GarmentShape.hat),
  crown("Crown", GarmentSlot.head, GarmentShape.hat);

  final String label;
  final GarmentSlot slot;
  final GarmentShape shape;

  /// length is how far down it comes. For a top, from the chest (0) to the
  /// hips (1) and on down the thighs; for something on the legs, the share
  /// of the leg from the hips; for a skirt or a dress, of the leg below the
  /// waist; for boots, of the shin.
  final double length;

  /// sleeve is how far down the arm a sleeve comes: 0 none, 0.5 to the
  /// elbow, 1 to the wrist.
  final double sleeve;

  /// fit is how loose: 1 as drawn, less tighter, more looser.
  final double fit;

  /// flare is how much wider the hem of a skirt is than its waist.
  final double flare;

  /// from is where on the leg it starts, for socks.
  final double from;

  const GarmentKind(this.label, this.slot, this.shape,
      {this.length = 1,
      this.sleeve = 0,
      this.fit = 1,
      this.flare = 1,
      this.from = 0});

  static GarmentKind? fromName(String? name) {
    for (var k in values) {
      if (k.name == name) return k;
    }
    return null;
  }

  /// hasSleeves is whether the sleeve setting means anything for it.
  bool get hasSleeves =>
      shape == GarmentShape.torso || shape == GarmentShape.dress;

  /// hasLength is whether its length can be changed.
  bool get hasLength =>
      shape == GarmentShape.torso ||
      shape == GarmentShape.legs ||
      shape == GarmentShape.skirt ||
      shape == GarmentShape.dress ||
      shape == GarmentShape.cape ||
      this == boots;

  /// coversLegs is whether it is drawn down the legs.
  bool get coversLegs => shape == GarmentShape.legs;

  /// strapless is a top edge straight across the chest under the arms,
  /// with nothing over the shoulders.
  bool get strapless => this == tubeDress;

  /// covers is the parts of the body it is worn on: what is drawn on it by
  /// hand is put on whichever of these it is drawn over. See
  /// Garment.drawings.
  Set<CharacterPart> get covers {
    const arms = {
      CharacterPart.upperArmL,
      CharacterPart.upperArmR,
      CharacterPart.foreArmL,
      CharacterPart.foreArmR,
    };
    const thighs = {CharacterPart.thighL, CharacterPart.thighR};
    const shins = {CharacterPart.shinL, CharacterPart.shinR};
    const feet = {CharacterPart.footL, CharacterPart.footR};
    return switch (shape) {
      GarmentShape.torso => {CharacterPart.torso, ...arms},
      GarmentShape.legs => {
          CharacterPart.torso,
          ...thighs,
          ...shins,
          if (this == socks || this == tights) ...feet,
        },
      GarmentShape.skirt => {CharacterPart.torso, ...thighs, ...shins},
      GarmentShape.dress => {CharacterPart.torso, ...arms, ...thighs, ...shins},
      GarmentShape.cape => {
          CharacterPart.torso,
          CharacterPart.upperArmL,
          CharacterPart.upperArmR,
          ...thighs,
        },
      GarmentShape.shoes => {...feet, ...shins},
      GarmentShape.hat || GarmentShape.glasses => {CharacterPart.head},
      GarmentShape.neck => {CharacterPart.head, CharacterPart.torso},
    };
  }
}

/// GarmentPattern is what is printed on a garment, in its second colour.
enum GarmentPattern {
  plain("Plain"),
  stripes("Stripes"),
  pinstripe("Pinstripe"),
  check("Check"),
  dots("Dots"),
  camo("Camo"),

  /// print is a picture on the front -- see Garment.printId.
  print("Picture print");

  final String label;
  const GarmentPattern(this.label);

  static GarmentPattern fromName(String? name) =>
      values.firstWhere((p) => p.name == name, orElse: () => plain);
}

/// GarmentCondition is how worn a garment is: each a share from nought (as
/// new) to one (as bad as it gets).
class GarmentCondition {
  /// fade washes the colour out towards grey.
  final double fade;

  /// dirt is smudges and mud splashes.
  final double dirt;

  /// rips are holes torn through, which show whatever is underneath.
  final double rips;

  /// frays is the hems and cuffs worn ragged.
  final double frays;

  /// patches is squares sewn over the worst of it.
  final double patches;

  const GarmentCondition(
      {this.fade = 0,
      this.dirt = 0,
      this.rips = 0,
      this.frays = 0,
      this.patches = 0});

  static const GarmentCondition asNew = GarmentCondition();

  bool get isNew =>
      fade == 0 && dirt == 0 && rips == 0 && frays == 0 && patches == 0;

  GarmentCondition copyWith(
          {double? fade,
          double? dirt,
          double? rips,
          double? frays,
          double? patches}) =>
      GarmentCondition(
        fade: (fade ?? this.fade).clamp(0.0, 1.0),
        dirt: (dirt ?? this.dirt).clamp(0.0, 1.0),
        rips: (rips ?? this.rips).clamp(0.0, 1.0),
        frays: (frays ?? this.frays).clamp(0.0, 1.0),
        patches: (patches ?? this.patches).clamp(0.0, 1.0),
      );

  Map<String, dynamic> toJson() => {
        if (fade != 0) "fade": fade,
        if (dirt != 0) "dirt": dirt,
        if (rips != 0) "rips": rips,
        if (frays != 0) "frays": frays,
        if (patches != 0) "patches": patches,
      };

  factory GarmentCondition.fromJson(Object? json) {
    if (json is! Map) return asNew;
    double v(String k) => jsonDouble(json[k], 0).clamp(0.0, 1.0);
    return GarmentCondition(
        fade: v("fade"),
        dirt: v("dirt"),
        rips: v("rips"),
        frays: v("frays"),
        patches: v("patches"));
  }
}

/// conditionPresets is the ready-made amounts of wear.
const List<(String, GarmentCondition)> conditionPresets = [
  ("Brand new", GarmentCondition.asNew),
  ("Lived-in", GarmentCondition(fade: 0.25, dirt: 0.15, frays: 0.2)),
  ("Worn out",
      GarmentCondition(fade: 0.55, dirt: 0.35, rips: 0.35, frays: 0.6, patches: 0.4)),
  ("Battle-damaged",
      GarmentCondition(fade: 0.3, dirt: 0.6, rips: 0.8, frays: 0.8)),
  ("Muddy", GarmentCondition(dirt: 0.9, fade: 0.1)),
  ("Shipwrecked",
      GarmentCondition(fade: 0.8, dirt: 0.4, rips: 0.6, frays: 1)),
];

/// Garment is one thing worn.
class Garment {
  final GarmentKind kind;
  final Color color;

  /// color2 is the pattern's colour, and a trim's.
  final Color color2;
  final GarmentPattern pattern;

  /// length, sleeve and fit are this garment's own -- see GarmentKind --
  /// or null for the kind's.
  final double? length;
  final double? sleeve;
  final double? fit;

  final GarmentCondition condition;

  /// outline is a shape of this garment's own, added to it: a collar, a
  /// peplum, a flared hem, shoulders. Points across the body -- 1 at the
  /// right shoulder, -1 at the left -- and down it -- nought at the chest,
  /// one at the hips -- so it goes with the body however it is turned and
  /// however tall it is. Empty for none.
  final List<Offset> outline;

  /// printId is the picture a print is of, and printSize how much of the
  /// front's width it covers.
  final String printId;
  final double printSize;

  /// seed is what its rips, smudges and patches are laid out by, so they
  /// are in the same places in every frame and every export, and two
  /// garments are not worn in the same places.
  final int seed;

  /// name is what it is called, where it is not just its kind: a garment
  /// drawn by hand.
  final String name;

  /// drawings is what is drawn on it by hand, panel by panel -- see
  /// character_drawing.dart -- each shape on the part of the body under it
  /// that the garment covers, so it is worn: it moves with the body.
  final Map<String, CharacterDrawing> drawings;

  /// drawnOnly leaves its own drawing out, for what is drawn on it by hand
  /// to be the garment: how a garment made from new is.
  final bool drawnOnly;

  /// hidden is its layer hidden: worn, but not drawn. See
  /// character_layers.dart.
  final bool hidden;

  /// title is what it is called in the wardrobe.
  String get title => name.isEmpty ? kind.label : name;

  /// drawingFor is what is drawn on it on the panel turned [turn] and tilted
  /// [tilt], and whether that is the other side's, mirrored.
  (CharacterDrawing, bool) drawingFor(double turn, double tilt) =>
      drawingOnPanel(drawings, turn, tilt);

  /// drawingAt and withDrawingAt are the same by a view's key -- see
  /// viewKeyOf.
  (CharacterDrawing, bool) drawingAt(String key) => drawingAtKey(drawings, key);

  Garment withDrawingAt(String key, CharacterDrawing drawing) =>
      copyWith(drawings: withDrawingAtKey(drawings, key, drawing));

  Garment withoutDrawingAt(String key) =>
      copyWith(drawings: withoutDrawingAtKey(drawings, key));

  Garment withDrawing(double turn, double tilt, CharacterDrawing drawing) =>
      copyWith(drawings: withPanelDrawing(drawings, turn, tilt, drawing));

  const Garment(
    this.kind, {
    required this.color,
    this.color2 = const Color(0xFFFFFFFF),
    this.pattern = GarmentPattern.plain,
    this.length,
    this.sleeve,
    this.fit,
    this.condition = GarmentCondition.asNew,
    this.seed = 0,
    this.outline = const [],
    this.printId = "",
    this.printSize = 0.6,
    this.name = "",
    this.drawings = const {},
    this.drawnOnly = false,
    this.hidden = false,
  });

  double get lengthOr => length ?? kind.length;
  double get sleeveOr => sleeve ?? kind.sleeve;
  double get fitOr => fit ?? kind.fit;

  Garment copyWith({
    GarmentKind? kind,
    Color? color,
    Color? color2,
    GarmentPattern? pattern,
    double? length,
    double? sleeve,
    double? fit,
    GarmentCondition? condition,
    int? seed,
    List<Offset>? outline,
    String? printId,
    double? printSize,
    String? name,
    Map<String, CharacterDrawing>? drawings,
    bool? drawnOnly,
    bool? hidden,
  }) =>
      Garment(
        kind ?? this.kind,
        color: color ?? this.color,
        color2: color2 ?? this.color2,
        pattern: pattern ?? this.pattern,
        // A new kind starts as that kind is, not as the last one was cut.
        length: kind != null && kind != this.kind
            ? null
            : (length ?? this.length)?.clamp(0.05, 2.0).toDouble(),
        sleeve: kind != null && kind != this.kind
            ? null
            : (sleeve ?? this.sleeve)?.clamp(0.0, 1.0).toDouble(),
        fit: kind != null && kind != this.kind
            ? null
            : (fit ?? this.fit)?.clamp(0.8, 1.4).toDouble(),
        condition: condition ?? this.condition,
        seed: seed ?? this.seed,
        outline: outline ?? this.outline,
        printId: printId ?? this.printId,
        printSize: (printSize ?? this.printSize).clamp(0.1, 1.5).toDouble(),
        name: name ?? this.name,
        drawings: drawings ?? this.drawings,
        drawnOnly: drawnOnly ?? this.drawnOnly,
        hidden: hidden ?? this.hidden,
      );

  Map<String, dynamic> toJson() => {
        "kind": kind.name,
        "color": colorToJson(color),
        if (color2 != const Color(0xFFFFFFFF)) "color2": colorToJson(color2),
        if (pattern != GarmentPattern.plain) "pattern": pattern.name,
        if (length != null) "length": length,
        if (sleeve != null) "sleeve": sleeve,
        if (fit != null) "fit": fit,
        if (!condition.isNew) "condition": condition.toJson(),
        if (seed != 0) "seed": seed,
        if (outline.isNotEmpty)
          "outline": [
            for (var p in outline) [_round(p.dx), _round(p.dy)]
          ],
        if (printId.isNotEmpty) "print": printId,
        if (printSize != 0.6) "printSize": printSize,
        if (name.isNotEmpty) "name": name,
        if (drawings.isNotEmpty)
          "drawings": {for (var e in drawings.entries) e.key: e.value.toJson()},
        if (drawnOnly) "drawnOnly": true,
        if (hidden) "hidden": true,
      };

  static double _round(double v) => (v * 1000).round() / 1000;

  static Garment? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    var kind = GarmentKind.fromName(json["kind"] as String?);
    if (kind == null) return null;
    double? opt(String k, double lo, double hi) =>
        json[k] is num ? (json[k] as num).toDouble().clamp(lo, hi).toDouble() : null;
    return Garment(
      kind,
      color: colorFromJson(json["color"], const Color(0xFF888888)),
      color2: colorFromJson(json["color2"], const Color(0xFFFFFFFF)),
      pattern: GarmentPattern.fromName(json["pattern"] as String?),
      length: opt("length", 0.05, 2),
      sleeve: opt("sleeve", 0, 1),
      fit: opt("fit", 0.8, 1.4),
      condition: GarmentCondition.fromJson(json["condition"]),
      seed: jsonInt(json["seed"], 0),
      outline: [
        if (json["outline"] case List points)
          for (var p in points)
            if (p is List && p.length == 2 && p[0] is num && p[1] is num)
              Offset((p[0] as num).toDouble().clamp(-3.0, 3.0),
                  (p[1] as num).toDouble().clamp(-1.0, 3.0)),
      ],
      printId: jsonString(json["print"], ""),
      printSize: jsonDouble(json["printSize"], 0.6).clamp(0.1, 1.5),
      name: jsonString(json["name"], ""),
      drawings: {
        if (json["drawings"] case Map raw)
          for (var e in raw.entries)
            if (e.value is Map<String, dynamic>)
              "${e.key}": CharacterDrawing.fromJson(e.value as Map<String, dynamic>),
      },
      drawnOnly: jsonBool(json["drawnOnly"], false),
      hidden: jsonBool(json["hidden"], false),
    );
  }
}

/// putOn is [wardrobe] with [g] put on in its place -- after everything
/// worn under it and before everything worn over it -- taking off whatever
/// it replaces: a second top replaces the first, but a scarf does not
/// replace glasses.
List<Garment> putOn(List<Garment> wardrobe, Garment g) {
  bool replaces(Garment old) {
    if (old.kind.slot != g.kind.slot) {
      // A dress or a suit is a top and bottoms at once.
      if (g.kind.slot == GarmentSlot.full) {
        return old.kind.slot == GarmentSlot.top ||
            old.kind.slot == GarmentSlot.bottom;
      }
      if (old.kind.slot == GarmentSlot.full) {
        return g.kind.slot == GarmentSlot.top ||
            g.kind.slot == GarmentSlot.bottom;
      }
      return false;
    }
    // The base layer has a top half and a bottom half; each replaces only
    // its own kind of thing.
    if (g.kind.slot == GarmentSlot.base) {
      return old.kind.shape == g.kind.shape && old.kind != GarmentKind.socks &&
          g.kind != GarmentKind.socks ||
          old.kind == g.kind;
    }
    return true;
  }

  var kept = [for (var old in wardrobe) if (!replaces(old)) old];
  var at = kept.indexWhere((o) => o.kind.slot.index > g.kind.slot.index);
  return at < 0 ? [...kept, g] : ([...kept]..insert(at, g));
}

/// moved is [wardrobe] with the garment at [i] moved [by] places: further
/// out with 1, further in with -1. Which is worn over which is the order.
List<Garment> moved(List<Garment> wardrobe, int i, int by) {
  var j = i + by;
  if (i < 0 || i >= wardrobe.length || j < 0 || j >= wardrobe.length) {
    return wardrobe;
  }
  var out = [...wardrobe];
  var g = out.removeAt(i);
  out.insert(j, g);
  return out;
}

/// newSeed is a seed for a garment's wear, from where it is in the
/// wardrobe and what it is -- the same every time the same wardrobe is made.
int newSeed(int index, GarmentKind kind) =>
    ((index + 1) * 7919 + kind.index * 104729) & 0x7FFFFFFF;

/// Costume is a whole outfit, ready to put on.
class Costume {
  final String name;
  final List<Garment> wardrobe;
  const Costume(this.name, this.wardrobe);
}

const _white = Color(0xFFF4F4F4);
const _black = Color(0xFF1E1E1E);

/// baseLayer_ is what a new character wears under everything.
const List<Garment> baseLayer_ = [
  Garment(GarmentKind.briefs, color: _white),
  Garment(GarmentKind.vest, color: _white),
];

/// costumes is the ready-made outfits.
const List<Costume> costumes = [
  Costume("Detective", [
    ...baseLayer_,
    Garment(GarmentKind.trousers, color: Color(0xFF4A4036)),
    Garment(GarmentKind.shirt, color: _white),
    Garment(GarmentKind.coat, color: Color(0xFFB08A5A)),
    Garment(GarmentKind.boots, color: Color(0xFF3A2A20)),
    Garment(GarmentKind.tie, color: Color(0xFF6A1F1F)),
    Garment(GarmentKind.topHat, color: Color(0xFF4A4036)),
  ]),
  Costume("Astronaut", [
    ...baseLayer_,
    Garment(GarmentKind.overalls, color: _white),
    Garment(GarmentKind.jacket, color: _white, color2: Color(0xFFE05A47)),
    Garment(GarmentKind.boots, color: Color(0xFFCCCCCC), length: 0.45),
  ]),
  Costume("Chef", [
    ...baseLayer_,
    Garment(GarmentKind.trousers, color: _black,
        pattern: GarmentPattern.check, color2: Color(0xFF666666)),
    Garment(GarmentKind.jacket, color: _white),
    Garment(GarmentKind.trainers, color: _black),
    Garment(GarmentKind.scarf, color: Color(0xFFE05A47)),
    Garment(GarmentKind.beanie, color: _white),
  ]),
  Costume("Knight", [
    ...baseLayer_,
    Garment(GarmentKind.tights, color: Color(0xFF7A7A82)),
    Garment(GarmentKind.sweater, color: Color(0xFFB8BCC4),
        pattern: GarmentPattern.check, color2: Color(0xFF8A8E96)),
    Garment(GarmentKind.cape, color: Color(0xFF8A1F2A)),
    Garment(GarmentKind.boots, color: Color(0xFF9A9EA6), length: 0.5),
  ]),
  Costume("Wizard", [
    ...baseLayer_,
    Garment(GarmentKind.robe, color: Color(0xFF3B2F7A),
        pattern: GarmentPattern.dots, color2: Color(0xFFF2C14E)),
    Garment(GarmentKind.slippers, color: Color(0xFF6A4A8A)),
    Garment(GarmentKind.topHat, color: Color(0xFF3B2F7A)),
  ]),
  Costume("Office", [
    ...baseLayer_,
    Garment(GarmentKind.trousers, color: Color(0xFF2B2F4A)),
    Garment(GarmentKind.shirt, color: Color(0xFFDCE8F5)),
    Garment(GarmentKind.blazer, color: Color(0xFF2B2F4A)),
    Garment(GarmentKind.heels, color: _black),
    Garment(GarmentKind.tie, color: Color(0xFF3D7EFF)),
  ]),
  Costume("Doctor", [
    ...baseLayer_,
    Garment(GarmentKind.trousers, color: Color(0xFF3A8A8A)),
    Garment(GarmentKind.tee, color: Color(0xFF3A8A8A)),
    Garment(GarmentKind.coat, color: _white, length: 1.5),
    Garment(GarmentKind.trainers, color: _white),
  ]),
  Costume("Footballer", [
    ...baseLayer_,
    Garment(GarmentKind.shorts, color: _white),
    Garment(GarmentKind.tee, color: Color(0xFFE05A47),
        pattern: GarmentPattern.stripes, color2: _white),
    Garment(GarmentKind.socks, color: Color(0xFFE05A47), length: 1, fit: 1),
    Garment(GarmentKind.trainers, color: _black),
  ]),
  Costume("Pirate", [
    ...baseLayer_,
    Garment(GarmentKind.trousers, color: Color(0xFF5A4632), length: 0.75),
    Garment(GarmentKind.blouse, color: _white,
        condition: GarmentCondition(fade: 0.3, frays: 0.5)),
    Garment(GarmentKind.jacket, color: Color(0xFF6A1F1F), length: 1.4),
    Garment(GarmentKind.boots, color: _black, length: 0.6),
    Garment(GarmentKind.scarf, color: Color(0xFFE05A47)),
  ]),
  Costume("Winter", [
    ...baseLayer_,
    Garment(GarmentKind.jeans, color: Color(0xFF3A5A8A)),
    Garment(GarmentKind.sweater, color: Color(0xFFB04A3A)),
    Garment(GarmentKind.coat, color: Color(0xFF2F3E5C)),
    Garment(GarmentKind.boots, color: Color(0xFF5A4632)),
    Garment(GarmentKind.scarf, color: Color(0xFFF2C14E),
        pattern: GarmentPattern.stripes, color2: Color(0xFFB04A3A)),
    Garment(GarmentKind.beanie, color: Color(0xFFF2C14E)),
  ]),
];

/// seeded is [wardrobe] with every garment given its own seed for its wear.
List<Garment> seeded(List<Garment> wardrobe) => [
      for (var (i, g) in wardrobe.indexed)
        g.seed != 0 ? g : g.copyWith(seed: newSeed(i, g.kind)),
    ];

/// wearUnit is a number from 0 to 1 that depends only on [seed] and [n]:
/// where a garment's rips and smudges go.
double wearUnit(int seed, int n) {
  var h = (seed ^ (n * 0x9E3779B1)) & 0xFFFFFFFF;
  h = ((h ^ (h >> 16)) * 0x85EBCA6B) & 0xFFFFFFFF;
  h = ((h ^ (h >> 13)) * 0xC2B2AE35) & 0xFFFFFFFF;
  h = h ^ (h >> 16);
  return h / 0xFFFFFFFF;
}

/// faded is [c] washed out by [amount].
Color faded(Color c, double amount) {
  if (amount <= 0) return c;
  var grey = (c.r * 0.3 + c.g * 0.59 + c.b * 0.11);
  var target = Color.from(
      alpha: c.a,
      red: math.min(1, grey + 0.15),
      green: math.min(1, grey + 0.15),
      blue: math.min(1, grey + 0.12));
  return Color.lerp(c, target, amount * 0.7)!;
}


/// outlineShapes is the ready-made shapes a garment's outline can start
/// from: name, and points in the outline's terms -- see Garment.outline.
const List<(String, List<Offset>)> outlineShapes = [
  ("Collar", [
    Offset(-0.55, -0.02), Offset(-0.3, 0.12), Offset(0, 0.04),
    Offset(0.3, 0.12), Offset(0.55, -0.02), Offset(0.2, -0.06),
    Offset(-0.2, -0.06),
  ]),
  ("Peplum", [
    Offset(-1.05, 0.6), Offset(1.05, 0.6), Offset(1.6, 0.98),
    Offset(0.5, 0.9), Offset(0, 0.98), Offset(-0.5, 0.9),
    Offset(-1.6, 0.98),
  ]),
  ("Flared hem", [
    Offset(-1.05, 0.85), Offset(1.05, 0.85), Offset(1.9, 1.4),
    Offset(0, 1.45), Offset(-1.9, 1.4),
  ]),
  ("Shoulders", [
    Offset(-1.3, -0.05), Offset(1.3, -0.05), Offset(1.2, 0.2),
    Offset(-1.2, 0.2),
  ]),
];
