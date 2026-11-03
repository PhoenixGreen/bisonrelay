// character_outfit.dart is what a new 3D character wears: for each piece
// of clothing, the body's own (the VRoid model's top, bottom or shoes), none,
// or one made to fit from the body itself -- its kind, cut, colour and
// pattern. What is made from these is in render/vrm/vrm_wear.dart.

/// WearSlot is a piece of clothing, in the order they are put on.
enum WearSlot {
  underwear("Underwear"),
  legwear("Socks and tights"),
  gloves("Gloves"),
  bottom("Bottom"),
  top("Top"),
  shoes("Shoes");

  final String label;
  const WearSlot(this.label);

  /// fromBody is whether a VRoid body comes with one of its own.
  bool get fromBody => this == top || this == bottom || this == shoes;
}

/// WearSource is where a piece of clothing comes from.
enum WearSource { own, none, made }

/// madeKinds are what can be made to fit, by slot, with their names.
const Map<WearSlot, List<(String, String)>> madeKinds = {
  WearSlot.underwear: [
    ("set", "Bra and briefs"),
    ("sports", "Sports set"),
    ("swim", "Swimsuit"),
    ("briefs", "Briefs"),
    ("boxers", "Boxers")
  ],
  WearSlot.top: [
    ("tee", "T-shirt"),
    ("long", "Long sleeves"),
    ("tank", "Tank top"),
    ("crop", "Crop top"),
    ("turtle", "Turtleneck")
  ],
  WearSlot.bottom: [
    ("trousers", "Trousers"),
    ("leggings", "Leggings"),
    ("shorts", "Shorts"),
    ("skirt", "Skirt")
  ],
  WearSlot.legwear: [
    ("ankle", "Ankle socks"),
    ("knee", "Knee socks"),
    ("thigh", "Thigh-highs"),
    ("tights", "Tights")
  ],
  WearSlot.gloves: [
    ("gloves", "Gloves"),
    ("long", "Long gloves"),
    ("fingerless", "Fingerless")
  ],
  WearSlot.shoes: [
    ("trainers", "Trainers"),
    ("flats", "Flats"),
    ("sandals", "Sandals"),
    ("ankle", "Ankle boots"),
    ("knee", "Knee boots")
  ],
};

const List<(String, String)> necklines = [
  ("crew", "Round"),
  ("scoop", "Scoop"),
  ("v", "V-neck"),
  ("boat", "Boat")
];
const List<(String, String)> wearPatterns = [
  ("solid", "Plain"), ("stripes", "Stripes"), ("pinstripe", "Pinstripe"), //
  ("checks", "Checks"), ("dots", "Dots"), ("plaid", "Plaid"),
];

/// clothPalette and underwearPalette are the colours offered, as 0xRRGGBB.
const List<int> clothPalette = [
  0xf4f1ea, 0x2e3038, 0x3f5a86, 0x263552, 0x3e6145, 0x8ea58a, //
  0xd9a93a, 0xb4562a, 0x9c3a32, 0x6a3d6e, 0xa996c8, 0xe07a5f,
];
const List<int> underwearPalette = [
  0xf4f1ea,
  0x1e1e24,
  0xe8a0b8,
  0xa996c8,
  0x9fb8d6,
  0xd9a93a,
  0xb23a3a,
  0x3e6145
];

/// Garment is one slot's clothing.
class Garment {
  final WearSource source;

  /// kind is what is made, from [madeKinds].
  final String kind;

  /// The top's cut: sleeves and hem from short to long, the neckline, its
  /// depth, and how loose.
  final double sleeves, hem, depth, fit;
  final String neckline;

  /// The bottom's: its length, how high the waist, a skirt's flare and
  /// pleats.
  final double length, rise, flare, pleats;

  /// Colours, as 0xRRGGBB: the cloth, the pattern on it, a shoe's sole.
  final int colour, patternColour, sole;
  final String pattern;

  /// scale is the pattern's size.
  final double scale;

  /// ownCut is how much of the body's own sleeves or trouser legs is left,
  /// from none to all.
  final double ownCut;

  const Garment({
    required this.source,
    required this.kind,
    this.sleeves = 0.3,
    this.hem = 0.7,
    this.depth = 0.3,
    this.fit = 0.2,
    this.neckline = "crew",
    this.length = 0.95,
    this.rise = 0.85,
    this.flare = 0.5,
    this.pleats = 0.4,
    this.colour = 0x3f5a86,
    this.patternColour = 0xf4f1ea,
    this.sole = 0x2e3038,
    this.pattern = "solid",
    this.scale = 0.5,
    this.ownCut = 1,
  });

  bool get made => source == WearSource.made;

  Garment copyWith({
    WearSource? source,
    String? kind,
    double? sleeves,
    double? hem,
    double? depth,
    double? fit,
    String? neckline,
    double? length,
    double? rise,
    double? flare,
    double? pleats,
    int? colour,
    int? patternColour,
    int? sole,
    String? pattern,
    double? scale,
    double? ownCut,
  }) =>
      Garment(
        source: source ?? this.source,
        kind: kind ?? this.kind,
        sleeves: sleeves ?? this.sleeves,
        hem: hem ?? this.hem,
        depth: depth ?? this.depth,
        fit: fit ?? this.fit,
        neckline: neckline ?? this.neckline,
        length: length ?? this.length,
        rise: rise ?? this.rise,
        flare: flare ?? this.flare,
        pleats: pleats ?? this.pleats,
        colour: colour ?? this.colour,
        patternColour: patternColour ?? this.patternColour,
        sole: sole ?? this.sole,
        pattern: pattern ?? this.pattern,
        scale: scale ?? this.scale,
        ownCut: ownCut ?? this.ownCut,
      );

  List<Object> get _fields => [
        source, kind, sleeves, hem, depth, fit, neckline, length, rise, flare,
        pleats, //
        colour, patternColour, sole, pattern, scale, ownCut,
      ];

  /// key says exactly what is made, so a garment the same as last time is
  /// not made again.
  String get key => _fields.join("|");

  Map<String, dynamic> toJson() => {
        "source": source.name,
        "kind": kind,
        "sleeves": sleeves,
        "hem": hem,
        "depth": depth,
        "fit": fit,
        "neckline": neckline,
        "length": length,
        "rise": rise,
        "flare": flare,
        "pleats": pleats,
        "colour": colour,
        "patternColour": patternColour,
        "sole": sole,
        "pattern": pattern,
        "scale": scale,
        "ownCut": ownCut,
      };

  factory Garment.fromJson(Map<String, dynamic> j, WearSlot slot, Garment d) {
    double n(String k, double v) => j[k] is num && (j[k] as num).isFinite
        ? (j[k] as num).toDouble().clamp(0.0, 1.0)
        : v;
    int c(String k, int v) => j[k] is int ? (j[k] as int) & 0xffffff : v;
    String s(String k, String v, Iterable<String> ok) =>
        ok.contains(j[k]) ? j[k] as String : v;
    return Garment(
      source: WearSource.values
          .firstWhere((x) => x.name == j["source"], orElse: () => d.source),
      kind: s("kind", d.kind, madeKinds[slot]!.map((e) => e.$1)),
      sleeves: n("sleeves", d.sleeves),
      hem: n("hem", d.hem),
      depth: n("depth", d.depth),
      fit: n("fit", d.fit),
      neckline: s("neckline", d.neckline, necklines.map((e) => e.$1)),
      length: n("length", d.length),
      rise: n("rise", d.rise),
      flare: n("flare", d.flare),
      pleats: n("pleats", d.pleats),
      colour: c("colour", d.colour),
      patternColour: c("patternColour", d.patternColour),
      sole: c("sole", d.sole),
      pattern: s("pattern", d.pattern, wearPatterns.map((e) => e.$1)),
      scale: n("scale", d.scale),
      ownCut: n("ownCut", d.ownCut),
    );
  }

  @override
  bool operator ==(Object other) => other is Garment && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// CharacterOutfit is everything worn. Immutable.
class CharacterOutfit {
  final Map<WearSlot, Garment> _slots;
  const CharacterOutfit._(this._slots);

  /// asDesigned is the body's own clothes, and made underwear under them.
  static const CharacterOutfit asDesigned = CharacterOutfit._({});

  static const Map<WearSlot, Garment> defaults = {
    WearSlot.underwear: Garment(
        source: WearSource.made,
        kind: "set",
        colour: 0xf4f1ea,
        patternColour: 0xe8a0b8),
    WearSlot.top: Garment(source: WearSource.own, kind: "tee"),
    WearSlot.bottom: Garment(
        source: WearSource.own, kind: "trousers", colour: 0x2e3038, fit: 0.25),
    WearSlot.legwear:
        Garment(source: WearSource.none, kind: "ankle", colour: 0x2e3038),
    WearSlot.gloves:
        Garment(source: WearSource.none, kind: "gloves", colour: 0x2e3038),
    WearSlot.shoes:
        Garment(source: WearSource.own, kind: "trainers", colour: 0xf4f1ea),
  };

  Garment operator [](WearSlot s) => _slots[s] ?? defaults[s]!;

  CharacterOutfit wear(WearSlot s, Garment g) =>
      CharacterOutfit._({..._slots, s: g});

  /// changed is whether [s] is not as designed.
  bool changed(WearSlot s) => this[s] != defaults[s];

  /// The quick changes: everything at once.
  CharacterOutfit underwearOnly({required bool male}) {
    var o = this;
    for (final s in [
      WearSlot.top,
      WearSlot.bottom,
      WearSlot.shoes,
      WearSlot.legwear,
      WearSlot.gloves
    ]) {
      o = o.wear(s, o[s].copyWith(source: WearSource.none));
    }
    final u = o[WearSlot.underwear];
    if (!u.made) {
      o = o.wear(WearSlot.underwear,
          u.copyWith(source: WearSource.made, kind: male ? "boxers" : "set"));
    }
    return o;
  }

  CharacterOutfit swimwear({required bool male}) {
    final o = underwearOnly(male: male);
    return o.wear(
        WearSlot.underwear,
        o[WearSlot.underwear].copyWith(
            source: WearSource.made,
            kind: male ? "briefs" : "swim",
            colour: 0x3f5a86,
            pattern: "solid"));
  }

  CharacterOutfit casual({required bool male}) => wear(WearSlot.top,
          this[WearSlot.top].copyWith(source: WearSource.made, kind: "tee"))
      .wear(
          WearSlot.bottom,
          this[WearSlot.bottom].copyWith(
              source: WearSource.made, kind: male ? "trousers" : "shorts"))
      .wear(
          WearSlot.legwear,
          this[WearSlot.legwear].copyWith(
              source: WearSource.made, kind: "ankle", colour: 0xf4f1ea));

  Map<String, dynamic> toJson() =>
      {for (final e in _slots.entries) e.key.name: e.value.toJson()};

  factory CharacterOutfit.fromJson(Map<String, dynamic> j) =>
      CharacterOutfit._({
        for (final s in WearSlot.values)
          if (j[s.name] is Map)
            s: Garment.fromJson(
                (j[s.name] as Map).cast<String, dynamic>(), s, defaults[s]!),
      });

  @override
  bool operator ==(Object other) =>
      other is CharacterOutfit &&
      WearSlot.values.every((s) => other[s] == this[s]);

  @override
  int get hashCode => Object.hashAll(WearSlot.values.map((s) => this[s]));
}
