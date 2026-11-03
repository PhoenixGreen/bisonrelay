// character_shape.dart is how a new 3D character is shaped from the VRoid
// body it starts from: every setting a number, nought as the body was made,
// and the presets last picked. What the numbers do to the body is in
// render/vrm/vrm_shape.dart; which settings there are, and how they are
// grouped for the page, is [characterShapeParts] below.

/// CharacterShape is one character's shaping. Immutable: each change is a
/// new one.
class CharacterShape {
  /// values are the settings changed from their defaults, by path
  /// ("eyes.size").
  final Map<String, double> values;

  /// choices are the named settings: presets ("shapes.face": "Round") and
  /// the choices that are not numbers ("muscle.shape": "long").
  final Map<String, String> choices;

  const CharacterShape({this.values = const {}, this.choices = const {}});

  static const Map<String, double> _defaults = {
    "age": 25,
    "navel.size": 0.5,
    "navel.depth": 0.5
  };
  static const Map<String, String> _defaultChoices = {
    "muscle.shape": "balanced",
    "navel.shape": "As made",
    "hair.source": "own",
    "hair.fringe": "same",
    "hair.tails": "own",
  };

  /// defaultOf is what [path] is before anything is changed.
  static double defaultOf(String path) => _defaults[path] ?? 0;

  /// get is [path]'s setting.
  double get(String path) => values[path] ?? defaultOf(path);

  /// choice is [path]'s named setting: a preset's name, or "As made".
  String choice(String path) =>
      choices[path] ?? _defaultChoices[path] ?? "As made";

  double get age => get("age");

  /// effective is [path] with what the years do added: see [ageShift].
  double effective(String path) => get(path) + (ageShift(age)[path] ?? 0);

  CharacterShape withValue(String path, double v) {
    final next = Map<String, double>.of(values);
    if ((v - defaultOf(path)).abs() < 1e-9) {
      next.remove(path);
    } else {
      next[path] = v;
    }
    return CharacterShape(values: next, choices: choices);
  }

  /// withChoice sets [path] to [v]. A hair source picked by hand is no
  /// longer the hairstyle it was started from.
  CharacterShape withChoice(String path, String v) =>
      CharacterShape(values: values, choices: {
        for (final e in choices.entries)
          if (!(path.startsWith("hair.") && e.key == "hair.style"))
            e.key: e.value,
        path: v,
      });

  /// withPreset picks [name] from [c]: the settings the preset is about go
  /// back to their defaults, then take the preset's values, and go on from
  /// there.
  CharacterShape withPreset(ShapePresets c, String name) {
    final next = Map<String, double>.of(values);
    for (final p in c.paths) {
      next.remove(p);
    }
    for (final e in (c.presets[name] ?? const <String, double>{}).entries) {
      next[e.key] = e.value;
    }
    return CharacterShape(values: next, choices: {...choices, c.key: name});
  }

  /// reset puts back every setting of [part] as the body was made.
  CharacterShape reset(ShapePart part) {
    final next = Map<String, double>.of(values);
    final picks = Map<String, String>.of(choices);
    for (final c in part.controls) {
      switch (c) {
        case ShapeSlider(:final key):
          next.remove(key);
        case ShapePresets():
          picks.remove(c.key);
          for (final p in c.paths) {
            next.remove(p);
          }
        case ShapeChoice(:final key):
          picks.remove(key);
        case ShapeColour(:final key):
          picks.remove(key);
        case ShapeHairStyles():
          for (final k in hairChoiceKeys) {
            picks.remove(k);
          }
          next.remove("hairShape.length");
          next.remove("hairShape.volume");
      }
    }
    return CharacterShape(values: next, choices: picks);
  }

  /// changed is whether anything in [part] is not as made.
  bool changed(ShapePart part) => part.controls.any((c) => switch (c) {
        ShapeSlider(:final key) => values.containsKey(key),
        ShapePresets() =>
          choices.containsKey(c.key) || c.paths.any(values.containsKey),
        ShapeChoice(:final key) => choices.containsKey(key) &&
            choices[key] != (_defaultChoices[key] ?? "As made"),
        ShapeColour(:final key) => choices.containsKey(key),
        ShapeHairStyles() => hairChoiceKeys.any((k) =>
            choices.containsKey(k) &&
            choices[k] != (_defaultChoices[k] ?? "As made")),
      });

  /// withHairStyle starts the hair from [h]: where its back, fringe and
  /// tails come from, and how long and full it is.
  CharacterShape withHairStyle(HairStyle h) {
    final next = Map<String, double>.of(values)
      ..remove("hairShape.length")
      ..remove("hairShape.volume");
    if (h.length != 0) next["hairShape.length"] = h.length;
    if (h.volume != 0) next["hairShape.volume"] = h.volume;
    return CharacterShape(values: next, choices: {
      ...choices,
      "hair.style": h.id,
      "hair.source": h.source,
      "hair.fringe": h.fringe,
      "hair.tails": h.tails,
    });
  }

  /// colour is [path]'s colour, 0xRRGGBB, or null as made.
  int? colour(String path) => int.tryParse(choices[path] ?? "", radix: 16);

  CharacterShape withColour(String path, int? c) => c == null
      ? CharacterShape(values: values, choices: {...choices}..remove(path))
      : withChoice(path, c.toRadixString(16).padLeft(6, '0'));

  /// hair is where [base]'s hair comes from, as set: the back and sides,
  /// the fringe, and the tails (null for none).
  ({String back, String fringe, String? tails}) hair(String base) {
    final source = choice("hair.source");
    final back = source == "own" ? base : source;
    final fringe = choice("hair.fringe");
    final tails = choice("hair.tails");
    return (
      back: back,
      fringe: fringe == "same" ? back : fringe,
      tails: tails == "own" ? back : (tails == "none" ? null : tails),
    );
  }

  Map<String, dynamic> toJson() => {
        if (values.isNotEmpty) "values": values,
        if (choices.isNotEmpty) "choices": choices,
      };

  factory CharacterShape.fromJson(Map<String, dynamic> j) => CharacterShape(
        values: {
          for (final e in ((j["values"] as Map?) ?? const {}).entries)
            if (e.value is num && (e.value as num).isFinite)
              "${e.key}": (e.value as num).toDouble(),
        },
        choices: {
          for (final e in ((j["choices"] as Map?) ?? const {}).entries)
            if (e.value is String) "${e.key}": e.value as String,
        },
      );

  @override
  bool operator ==(Object other) =>
      other is CharacterShape &&
      _mapEq(values, other.values) &&
      _mapEq(choices, other.choices);

  @override
  int get hashCode => Object.hash(
      Object.hashAllUnordered(
          values.entries.map((e) => Object.hash(e.key, e.value))),
      Object.hashAllUnordered(
          choices.entries.map((e) => Object.hash(e.key, e.value))));

  static bool _mapEq<V>(Map<String, V> a, Map<String, V> b) =>
      a.length == b.length &&
      a.entries.every((e) => b.containsKey(e.key) && b[e.key] == e.value);
}

/// ageShift is what the years do, added to what is set: from a young adult
/// (rounder face, bigger eyes) to old age (longer nose and ears, thinner
/// lips, a lower brow, a softer, more stooped body).
Map<String, double> ageShift(double age) {
  final y = ((25 - age) / 7).clamp(0.0, 1.0);
  final o = ((age - 35) / 50).clamp(0.0, 1.0);
  return {
    "eyes.size": 0.12 * y - 0.12 * o,
    "cheeks.fullness": 0.2 * y - 0.1 * o,
    "nose.size": -0.08 * y + 0.22 * o,
    "jaw.width": -0.08 * y + 0.12 * o,
    "nose.length": 0.25 * o,
    "ears.size": 0.3 * o,
    "mouth.lips": -0.35 * o,
    "mouth.upper": -0.3 * o,
    "mouth.corners": -0.5 * o,
    "cheeks.height": -0.4 * o,
    "brows.height": -0.25 * o,
    "eyes.round": -0.25 * o,
    "eyes.depth": 0.3 * o,
    "body.height": -0.12 * o,
    "body.slope": 0.6 * o,
    "body.belly": 0.4 * o,
    "body.muscle": -0.35 * o,
    "body.chest": -0.1 * o,
    "chest.hang": 0.6 * o,
    "chest.perk": -0.3 * o,
    "bum.lift": -0.45 * o,
    "bum.firm": -0.4 * o,
    "muscle.fat": 0.25 * o,
    "face.length": 0.12 * o,
    "face.cheekbones": 0.15 * o,
  };
}

/// ShapeControl is one control on a part's page.
sealed class ShapeControl {
  const ShapeControl();
}

/// ShapeSlider is a number, from [min] to [max].
class ShapeSlider extends ShapeControl {
  final String key, label;
  final double min, max;

  /// whole says it is counted in whole numbers (years), not a share.
  final bool whole;
  const ShapeSlider(this.key, this.label,
      {this.min = -1, this.max = 1, this.whole = false});
}

/// ShapePresets is a list of starting points, each setting the sliders it
/// names.
class ShapePresets extends ShapeControl {
  final String key, label;
  final Map<String, Map<String, double>> presets;

  /// group, when set, is the run of settings the presets own: picking one
  /// puts back every setting under it, not only those some preset names.
  final String? group;

  /// groupPaths are the settings under [group], for the presets that own
  /// one.
  final List<String> groupPaths;
  const ShapePresets(this.key, this.label, this.presets,
      {this.group, this.groupPaths = const []});

  /// paths are the settings picking a preset puts back first.
  Iterable<String> get paths =>
      group != null ? groupPaths : {for (final p in presets.values) ...p.keys};
}

/// ShapeChoice is one of a few named options.
class ShapeChoice extends ShapeControl {
  final String key, label;
  final List<(String, String)> options;
  const ShapeChoice(this.key, this.label, this.options);
}

/// ShapeColour is a colour picked from [palette], 0xRRGGBB, or the colour
/// as made.
class ShapeColour extends ShapeControl {
  final String key, label;
  final List<int> palette;
  const ShapeColour(this.key, this.label, this.palette);
}

/// The colours offered for hair, skin and eyes, as 0xRRGGBB.
const List<int> hairPalette = [
  0x17120f, 0x3f2a1e, 0x6a4128, 0x9a6e45, 0xddbb7c, 0xede3c9, //
  0x9c9a98, 0x8a3b22, 0x5a2e5e, 0x1f6f75, 0xd978a0, 0x4a6fd0,
];
const List<int> skinPalette = [
  0xf8e1d3, 0xf3d2b9, 0xedbfa8, 0xe2b48c, 0xd69e6e, //
  0xc08f62, 0xae7448, 0x9a6240, 0x7e4a2e, 0x5e3620,
];
const List<int> eyePalette = [
  0x3a2416, 0x6b4226, 0xa0702a, 0x7d7a3e, 0x4e7a45, //
  0x3e6e9e, 0x7fa6c8, 0x7a8590, 0x8a3d8f, 0xc23a3a,
];

/// ageGrey is how grey the years have turned the hair, nought to one.
double ageGrey(double age) => ((age - 42) / 30).clamp(0.0, 1.0);

/// ShapeHairStyles is the hairstyles to start from: see [hairStyles].
class ShapeHairStyles extends ShapeControl {
  const ShapeHairStyles();
}

/// hairChoiceKeys are the named settings of the hair.
const List<String> hairChoiceKeys = [
  "hair.style",
  "hair.source",
  "hair.fringe",
  "hair.tails"
];

/// hairSources are the characters whose hair can be worn: the four bodies,
/// and four kept only for their hair (vroid_assets.dart), by their ids
/// there, with what their hair is.
const List<(String, String)> hairSources = [
  ("Vivi", "Bob with buns"),
  ("Victoria_Rubin", "Long, side tails"),
  ("Vita", "Short and choppy"),
  ("HairSample_Male", "Short and spiky"),
  ("Sendagaya_Shino", "Long and straight"),
  ("Sendagaya_Shibu", "Bob with a fringe"),
  ("HairSample_Female", "Twin tails, cat ears"),
  ("Sakurada_Fumiriya", "Short and tousled"),
];

/// HairStyle is a hairstyle to start from: one character's hair as made,
/// longer, shorter or fuller, or mixed -- one's fringe with another's back,
/// or the twin tails of one on another. Every strand is a model's own.
class HairStyle {
  final String id, name, source;

  /// fringe is "same" or a source; tails "own", "none" or a source.
  final String fringe, tails;
  final double length, volume;
  const HairStyle(this.id, this.name, this.source,
      {this.fringe = "same",
      this.tails = "own",
      this.length = 0,
      this.volume = 0});
}

const List<HairStyle> hairStyles = [
  HairStyle("buns", "Bob with buns", "Vivi"),
  HairStyle("sidetails", "Long with a side tie", "Victoria_Rubin"),
  HairStyle("pixie", "Pixie", "Vita"),
  HairStyle("spiky", "Spiky", "HairSample_Male"),
  HairStyle("tousled", "Tousled", "Sakurada_Fumiriya"),
  HairStyle("long", "Long and straight", "Sendagaya_Shino"),
  HairStyle("shoulder", "Shoulder length", "Sendagaya_Shino", length: -0.5),
  HairStyle("full", "Big and full", "Sendagaya_Shino", volume: 1, length: 0.2),
  HairStyle("bob", "Bob", "Sendagaya_Shibu"),
  HairStyle("longbob", "Long bob", "Sendagaya_Shibu", length: 0.45),
  HairStyle("twintails", "Twin tails, cat ears", "HairSample_Female"),
  HairStyle("sweptlong", "Long, swept fringe", "Sendagaya_Shino",
      fringe: "Victoria_Rubin"),
  HairStyle("bobtails", "Bob with twin tails", "Sendagaya_Shibu",
      tails: "HairSample_Female"),
  HairStyle("longtails", "Long with twin tails", "Sendagaya_Shino",
      tails: "HairSample_Female"),
  HairStyle("pixietails", "Pixie with twin tails", "Vita",
      tails: "HairSample_Female"),
  HairStyle("choppybob", "Bob, choppy fringe", "Sendagaya_Shibu",
      fringe: "Vita"),
  HairStyle("tousledlong", "Shoulder, tousled fringe", "Sendagaya_Shino",
      fringe: "Sakurada_Fumiriya", length: -0.4),
  HairStyle("spikylong", "Spiky fringe, long back", "Sendagaya_Shino",
      fringe: "HairSample_Male", length: -0.2),
];

/// ShapeFrame is what the camera looks at while a part is open.
enum ShapeFrame { body, head, torso, bum, feet }

/// ShapePart is one entry in the page's list: a heading over it, its name,
/// what it changes, and its controls.
class ShapePart {
  final String id, group, name, says;
  final ShapeFrame frame;
  final List<ShapeControl> controls;
  const ShapePart(
      this.id, this.group, this.name, this.says, this.frame, this.controls);
}

/// The kind of figure: how many heads tall, how big its eyes, how long its
/// limbs.
const Map<String, Map<String, double>> figureShapes = {
  "As made": {},
  "Realistic": {
    "figure.head": -0.3,
    "figure.eyes": -0.45,
    "figure.legs": 0.25,
    "figure.torso": 0.1,
    "figure.arms": 0.1
  },
  "Heroic": {
    "figure.head": -0.4,
    "figure.eyes": -0.3,
    "figure.legs": 0.4,
    "figure.torso": 0.15,
    "figure.arms": 0.15,
    "figure.hands": 0.15
  },
  "Cartoon": {
    "figure.head": 0.35,
    "figure.eyes": 0.4,
    "figure.legs": -0.15,
    "figure.hands": 0.45,
    "figure.feet": 0.45
  },
  "Chibi": {
    "figure.head": 1,
    "figure.eyes": 0.8,
    "figure.torso": -0.55,
    "figure.arms": -0.6,
    "figure.legs": -0.75,
    "figure.hands": -0.2,
    "figure.feet": 0.1
  },
  "Doll": {
    "figure.head": 0.55,
    "figure.eyes": 0.6,
    "figure.torso": -0.2,
    "figure.legs": 0.15,
    "figure.arms": -0.1,
    "figure.hands": -0.3,
    "figure.feet": -0.3
  },
  "Lanky": {
    "figure.head": -0.2,
    "figure.torso": 0.3,
    "figure.arms": 0.45,
    "figure.legs": 0.5,
    "figure.hands": 0.2,
    "figure.feet": 0.2
  },
};

const Map<String, Map<String, double>> faceShapes = {
  "As made": {},
  "Oval": {"face.length": 0.2, "jaw.width": -0.15, "face.cheekbones": 0.1},
  "Round": {
    "head.width": 0.35,
    "face.length": -0.3,
    "cheeks.fullness": 0.6,
    "jaw.width": 0.2,
    "jaw.chin": -0.3
  },
  "Heart": {
    "face.forehead": 0.4,
    "face.cheekbones": 0.4,
    "jaw.width": -0.45,
    "jaw.chinWidth": -0.4,
    "jaw.chin": 0.2
  },
  "Square": {
    "jaw.width": 0.7,
    "jaw.chinWidth": 0.5,
    "face.length": 0.1,
    "cheeks.fullness": -0.2
  },
  "Long": {
    "face.length": 0.7,
    "head.width": -0.25,
    "jaw.chin": 0.4,
    "cheeks.fullness": -0.3
  },
  "Diamond": {
    "face.cheekbones": 0.8,
    "face.forehead": -0.3,
    "jaw.width": -0.4,
    "jaw.chin": 0.35
  },
  "Sharp": {
    "jaw.width": -0.3,
    "jaw.chin": 0.5,
    "jaw.forward": 0.4,
    "face.cheekbones": 0.5,
    "cheeks.fullness": -0.5
  },
};

const Map<String, Map<String, double>> eyeShapes = {
  "As made": {},
  "Big": {"eyes.size": 0.6, "eyes.iris": 0.3, "eyes.round": 0.3},
  "Almond": {"eyes.round": -0.5, "eyes.tilt": 0.25, "eyes.size": -0.1},
  "Upturned": {"eyes.tilt": 0.7, "eyes.round": -0.3},
  "Downturned": {"eyes.tilt": -0.6, "eyes.round": -0.1},
  "Narrow": {"eyes.round": -0.8, "eyes.size": -0.3, "eyes.iris": -0.2},
  "Wide-set": {"eyes.spacing": 0.7},
  "Deep": {"eyes.depth": 0.8, "brows.height": -0.4, "eyes.size": -0.2},
};

const Map<String, Map<String, double>> noseShapes = {
  "As made": {},
  "Button": {"nose.size": -0.4, "nose.tip": 0.6, "nose.length": -0.3},
  "Straight": {"nose.bridge": 0.6, "nose.length": 0.3, "nose.size": 0.1},
  "Roman": {
    "nose.bridge": 0.9,
    "nose.length": 0.5,
    "nose.tip": -0.4,
    "nose.size": 0.3
  },
  "Wide": {"nose.width": 0.7, "nose.nostrils": 0.6, "nose.bridge": -0.2},
  "Small": {"nose.size": -0.8, "nose.length": -0.4},
};

const Map<String, Map<String, double>> mouthShapes = {
  "As made": {},
  "Full": {"mouth.lips": 0.7, "mouth.upper": 0.3, "mouth.lower": 0.5},
  "Wide": {"mouth.width": 0.7, "mouth.corners": 0.2},
  "Small": {"mouth.size": -0.5, "mouth.width": -0.3},
  "Smiling": {"mouth.corners": 0.8},
  "Pouty": {"mouth.lower": 0.6, "mouth.size": -0.2, "mouth.corners": -0.3},
  "Thin": {"mouth.lips": -0.7, "mouth.width": 0.2},
};

const Map<String, Map<String, double>> chestShapes = {
  "As made": {},
  "Round": {"chest.upper": 0.45, "chest.perk": 0.2, "chest.hang": -0.2},
  "Teardrop": {"chest.upper": -0.3, "chest.hang": 0.25, "chest.perk": 0.2},
  "Close-set": {"chest.close": 0.7, "chest.out": -0.4},
  "Wide-set": {"chest.close": -0.6, "chest.out": 0.6},
  "Lifted": {"chest.hang": -0.7, "chest.perk": 0.4, "chest.upper": 0.2},
  "Relaxed": {
    "chest.hang": 0.7,
    "chest.perk": -0.3,
    "chest.out": 0.3,
    "chest.upper": -0.3
  },
};

const Map<String, Map<String, double>> bumShapes = {
  "As made": {},
  "Round": {"bum.round": 0.6, "bum.upper": 0.3, "bum.lower": 0.3},
  "Heart": {
    "bum.upper": -0.3,
    "bum.lower": 0.6,
    "bum.width": 0.4,
    "bum.lift": 0.2
  },
  "Square": {
    "bum.width": 0.4,
    "bum.round": -0.35,
    "bum.upper": 0.2,
    "bum.lower": 0.25,
    "bum.lift": -0.15
  },
  "V-shape": {
    "bum.upper": 0.45,
    "bum.lower": -0.45,
    "bum.width": -0.3,
    "bum.lift": -0.2
  },
  "Bubble": {
    "bum.size": 0.4,
    "bum.round": 0.6,
    "bum.lift": 0.35,
    "bum.upper": 0.3,
    "bum.firm": 0.3
  },
  "Flat": {"bum.size": -0.6, "bum.round": -0.7, "bum.upper": -0.3},
};

const Map<String, Map<String, double>> muscleBuilds = {
  "As made": {},
  "Soft": {
    "muscle.fat": 0.5,
    "muscle.shoulders": -0.2,
    "muscle.pecs": -0.2,
    "muscle.biceps": -0.2,
    "muscle.triceps": -0.2,
    "muscle.forearms": -0.2,
    "muscle.back": -0.2,
    "muscle.abs": -0.3,
    "muscle.quads": -0.1,
    "muscle.calves": -0.1
  },
  "Slim": {
    "muscle.fat": -0.5,
    "muscle.definition": 0.15,
    "muscle.shoulders": -0.35,
    "muscle.pecs": -0.3,
    "muscle.biceps": -0.4,
    "muscle.triceps": -0.4,
    "muscle.forearms": -0.3,
    "muscle.back": -0.3,
    "muscle.quads": -0.35,
    "muscle.calves": -0.3
  },
  "Toned": {
    "muscle.fat": -0.3,
    "muscle.definition": 0.45,
    "muscle.shoulders": 0.15,
    "muscle.pecs": 0.1,
    "muscle.biceps": 0.15,
    "muscle.triceps": 0.15,
    "muscle.forearms": 0.1,
    "muscle.back": 0.15,
    "muscle.abs": 0.3,
    "muscle.traps": 0.05,
    "muscle.glutes": 0.2,
    "muscle.quads": 0.2,
    "muscle.calves": 0.2
  },
  "Athletic": {
    "muscle.fat": -0.4,
    "muscle.definition": 0.6,
    "muscle.shoulders": 0.45,
    "muscle.pecs": 0.35,
    "muscle.biceps": 0.35,
    "muscle.triceps": 0.3,
    "muscle.forearms": 0.3,
    "muscle.back": 0.45,
    "muscle.abs": 0.5,
    "muscle.traps": 0.25,
    "muscle.glutes": 0.3,
    "muscle.quads": 0.45,
    "muscle.calves": 0.4
  },
  "Muscular": {
    "muscle.fat": -0.2,
    "muscle.definition": 0.7,
    "muscle.shoulders": 0.75,
    "muscle.pecs": 0.7,
    "muscle.biceps": 0.7,
    "muscle.triceps": 0.65,
    "muscle.forearms": 0.6,
    "muscle.back": 0.8,
    "muscle.abs": 0.6,
    "muscle.traps": 0.6,
    "muscle.glutes": 0.5,
    "muscle.quads": 0.7,
    "muscle.calves": 0.6
  },
  "Bodybuilder": {
    "muscle.fat": -0.6,
    "muscle.definition": 1,
    "muscle.shoulders": 1,
    "muscle.pecs": 1,
    "muscle.biceps": 1,
    "muscle.triceps": 1,
    "muscle.forearms": 0.9,
    "muscle.back": 1,
    "muscle.abs": 0.9,
    "muscle.traps": 1,
    "muscle.glutes": 0.7,
    "muscle.quads": 1,
    "muscle.calves": 0.9
  },
  "Strongman": {
    "muscle.fat": 0.55,
    "muscle.definition": 0.15,
    "muscle.shoulders": 0.8,
    "muscle.pecs": 0.6,
    "muscle.biceps": 0.8,
    "muscle.triceps": 0.8,
    "muscle.forearms": 0.8,
    "muscle.back": 0.9,
    "muscle.abs": -0.2,
    "muscle.traps": 1,
    "muscle.glutes": 0.6,
    "muscle.quads": 0.9,
    "muscle.calves": 0.7
  },
};

const List<String> _figurePaths = [
  "figure.head",
  "figure.eyes",
  "figure.torso",
  "figure.arms",
  "figure.legs",
  "figure.hands",
  "figure.feet"
];
const List<String> _chestPaths = [
  "chest.close",
  "chest.hang",
  "chest.perk",
  "chest.out",
  "chest.upper",
  "chest.width"
];
const List<String> _bumPaths = [
  "bum.size",
  "bum.lift",
  "bum.round",
  "bum.width",
  "bum.upper",
  "bum.lower",
  "bum.firm"
];
const List<String> _musclePaths = [
  "muscle.definition", "muscle.fat", "muscle.shoulders", "muscle.traps",
  "muscle.pecs", "muscle.back", "muscle.abs", //
  "muscle.biceps", "muscle.triceps", "muscle.forearms", "muscle.glutes",
  "muscle.quads", "muscle.calves",
];

/// characterShapeParts are the page's parts, in its order, under their
/// headings.
const List<ShapePart> characterShapeParts = [
  ShapePart(
      "age",
      "Character",
      "Age",
      "How old they are, from a young adult to old age. The face and the build follow, and every other setting still applies on top. These bodies are grown-ups, so the youngest is 18.",
      ShapeFrame.body,
      [ShapeSlider("age", "Age", min: 18, max: 85, whole: true)]),
  ShapePart(
      "figure",
      "Character",
      "Proportions",
      "The kind of figure: realistic, heroic, cartoon, chibi and more. How many heads tall it is, how big its eyes, and how long its limbs.",
      ShapeFrame.body, [
    ShapePresets("figure.style", "Figure", figureShapes,
        group: "figure", groupPaths: _figurePaths),
    ShapeSlider("figure.head", "Head"),
    ShapeSlider("figure.eyes", "Eyes"),
    ShapeSlider("figure.torso", "Body length"),
    ShapeSlider("figure.arms", "Arm length"),
    ShapeSlider("figure.legs", "Leg length"),
    ShapeSlider("figure.hands", "Hands"),
    ShapeSlider("figure.feet", "Feet"),
  ]),
  ShapePart(
      "head",
      "Head",
      "Head shape",
      "The whole head and face: size, width, the length of the face, the forehead and the cheekbones.",
      ShapeFrame.head, [
    ShapePresets("shapes.face", "Face shape", faceShapes),
    ShapeSlider("head.size", "Size"),
    ShapeSlider("head.width", "Width"),
    ShapeSlider("face.length", "Face length"),
    ShapeSlider("face.forehead", "Forehead"),
    ShapeSlider("face.cheekbones", "Cheekbones"),
  ]),
  ShapePart(
      "eyes", "Head", "Eyes", "Both eyes, kept a pair.", ShapeFrame.head, [
    ShapePresets("shapes.eyes", "Eye shape", eyeShapes),
    ShapeSlider("eyes.size", "Size"),
    ShapeSlider("eyes.spacing", "Spacing"),
    ShapeSlider("eyes.height", "Height"),
    ShapeSlider("eyes.tilt", "Tilt"),
    ShapeSlider("eyes.round", "Roundness"),
    ShapeSlider("eyes.iris", "Iris size"),
    ShapeSlider("eyes.depth", "Set deep"),
    ShapeColour("colour.eyes", "Iris colour", eyePalette),
  ]),
  ShapePart(
      "brows",
      "Head",
      "Brows",
      "Where the brows sit, how they slant, how thick and how long.",
      ShapeFrame.head, [
    ShapeSlider("brows.height", "Height"),
    ShapeSlider("brows.angle", "Angle"),
    ShapeSlider("brows.thickness", "Thickness"),
    ShapeSlider("brows.length", "Length"),
    ShapeColour("colour.brows", "Colour", hairPalette),
  ]),
  ShapePart(
      "nose",
      "Head",
      "Nose",
      "Its size, length, height and width; the bridge, the tip and the nostrils.",
      ShapeFrame.head, [
    ShapePresets("shapes.nose", "Nose shape", noseShapes),
    ShapeSlider("nose.size", "Size"),
    ShapeSlider("nose.length", "Length"),
    ShapeSlider("nose.height", "Height"),
    ShapeSlider("nose.width", "Width"),
    ShapeSlider("nose.bridge", "Bridge"),
    ShapeSlider("nose.tip", "Tip up"),
    ShapeSlider("nose.nostrils", "Nostrils"),
  ]),
  ShapePart(
      "mouth",
      "Head",
      "Mouth",
      "Its width, size and height; each lip, and the corners.",
      ShapeFrame.head, [
    ShapePresets("shapes.mouth", "Mouth shape", mouthShapes),
    ShapeSlider("mouth.width", "Width"),
    ShapeSlider("mouth.size", "Size"),
    ShapeSlider("mouth.height", "Height"),
    ShapeSlider("mouth.lips", "Fullness"),
    ShapeSlider("mouth.upper", "Upper lip"),
    ShapeSlider("mouth.lower", "Lower lip"),
    ShapeSlider("mouth.corners", "Corners up"),
  ]),
  ShapePart(
      "ears",
      "Head",
      "Ears",
      "Size, how far they stand out, and a point at the top.",
      ShapeFrame.head, [
    ShapeSlider("ears.size", "Size"),
    ShapeSlider("ears.out", "Stick out"),
    ShapeSlider("ears.point", "Pointed", min: 0),
  ]),
  ShapePart("cheeks", "Head", "Cheeks",
      "How full the cheeks are, and how high.", ShapeFrame.head, [
    ShapeSlider("cheeks.fullness", "Fullness"),
    ShapeSlider("cheeks.height", "Height"),
  ]),
  ShapePart(
      "jaw",
      "Head",
      "Jaw and chin",
      "The jaw's width, and the chin's length, width and how far forward.",
      ShapeFrame.head, [
    ShapeSlider("jaw.width", "Jaw width"),
    ShapeSlider("jaw.chin", "Chin length"),
    ShapeSlider("jaw.chinWidth", "Chin width"),
    ShapeSlider("jaw.forward", "Chin forward"),
  ]),
  ShapePart(
      "hair",
      "Hair",
      "Hair",
      "Pick a hairstyle to start from, then make it yours: its length and "
          "fullness, and the fringe and tails of any other.",
      ShapeFrame.head,
      [
        ShapeHairStyles(),
        ShapeColour("colour.hair", "Colour", hairPalette),
        ShapeSlider("hairShape.length", "Length"),
        ShapeSlider("hairShape.volume", "Volume"),
        ShapeChoice("hair.source", "Back and sides from",
            [("own", "Its own"), ...hairSources]),
        ShapeChoice("hair.fringe", "Fringe from",
            [("same", "The same"), ...hairSources]),
        ShapeChoice("hair.tails", "Tails", [
          ("own", "As it has"),
          ("none", "None"),
          ("HairSample_Female", "Twin tails")
        ]),
      ]),
  ShapePart("body", "Body", "Body",
      "Height and build. The clothes follow the body.", ShapeFrame.body, [
    ShapeSlider("body.height", "Height"),
    ShapeSlider("body.torso", "Torso length"),
    ShapeSlider("body.neck", "Neck length"),
    ShapeSlider("body.neckWidth", "Neck thickness"),
    ShapeSlider("body.shoulders", "Shoulders"),
    ShapeSlider("body.slope", "Shoulder slope"),
    ShapeSlider("body.waist", "Waist"),
    ShapeSlider("body.hips", "Hips"),
    ShapeSlider("body.belly", "Belly"),
  ]),
  ShapePart("navel", "Body", "Belly button", "Its shape, size and depth.",
      ShapeFrame.torso, [
    ShapeChoice("navel.shape", "Shape", [
      ("As made", "As made"),
      ("round", "Round"),
      ("vertical", "Long"),
      ("wide", "Wide"),
      ("outie", "Outie")
    ]),
    ShapeSlider("navel.size", "Size", min: 0),
    ShapeSlider("navel.depth", "Depth", min: 0),
  ]),
  ShapePart(
      "chest",
      "Body",
      "Chest",
      "Its size and shape: how close set, how it hangs or lifts, how it points, and how full above.",
      ShapeFrame.torso, [
    ShapePresets("chest.shape", "Shape", chestShapes,
        group: "chest", groupPaths: _chestPaths),
    ShapeSlider("body.chest", "Size"),
    ShapeSlider("chest.width", "Width"),
    ShapeSlider("chest.close", "Close set"),
    ShapeSlider("chest.hang", "Hang"),
    ShapeSlider("chest.perk", "Perk"),
    ShapeSlider("chest.out", "Points outward"),
    ShapeSlider("chest.upper", "Fullness above"),
  ]),
  ShapePart(
      "bum",
      "Body",
      "Bum",
      "Its shape and size, how high and round it sits, its width, and how firm.",
      ShapeFrame.bum, [
    ShapePresets("bum.shape", "Shape", bumShapes,
        group: "bum", groupPaths: _bumPaths),
    ShapeSlider("bum.size", "Size"),
    ShapeSlider("bum.lift", "Lift"),
    ShapeSlider("bum.round", "Roundness"),
    ShapeSlider("bum.width", "Width"),
    ShapeSlider("bum.upper", "Fullness above"),
    ShapeSlider("bum.lower", "Fullness below"),
    ShapeSlider("bum.firm", "Firmness"),
  ]),
  ShapePart(
      "muscles",
      "Body",
      "Muscles",
      "A build to start from, the shape the muscles take, and each muscle on its own.",
      ShapeFrame.body, [
    ShapePresets("muscle.build", "Build", muscleBuilds,
        group: "muscle", groupPaths: _musclePaths),
    ShapeChoice("muscle.shape", "Muscle shape", [
      ("long", "Long and lean"),
      ("balanced", "Balanced"),
      ("round", "Round and full"),
      ("peaked", "Peaked")
    ]),
    ShapeSlider("body.muscle", "All muscle"),
    ShapeSlider("muscle.fat", "Body fat"),
    ShapeSlider("muscle.shoulders", "Shoulders"),
    ShapeSlider("muscle.traps", "Neck and traps"),
    ShapeSlider("muscle.pecs", "Chest"),
    ShapeSlider("muscle.back", "Back"),
    ShapeSlider("muscle.abs", "Stomach"),
    ShapeSlider("muscle.biceps", "Biceps"),
    ShapeSlider("muscle.triceps", "Triceps"),
    ShapeSlider("muscle.forearms", "Forearms"),
    ShapeSlider("muscle.glutes", "Glutes"),
    ShapeSlider("muscle.quads", "Thighs"),
    ShapeSlider("muscle.calves", "Calves"),
  ]),
  ShapePart(
      "arms",
      "Body",
      "Arms",
      "How long the arms are, and how thick above and below the elbow.",
      ShapeFrame.body, [
    ShapeSlider("arms.length", "Length"),
    ShapeSlider("arms.upper", "Upper arms"),
    ShapeSlider("arms.fore", "Forearms"),
  ]),
  ShapePart("hands", "Body", "Hands",
      "How big the hands are, and how long the fingers.", ShapeFrame.body, [
    ShapeSlider("hands.size", "Size"),
    ShapeSlider("hands.fingers", "Fingers"),
  ]),
  ShapePart(
      "legs",
      "Body",
      "Legs",
      "How long the legs are, and how thick the thighs and calves.",
      ShapeFrame.body, [
    ShapeSlider("legs.length", "Length"),
    ShapeSlider("legs.thigh", "Thighs"),
    ShapeSlider("legs.calf", "Calves"),
  ]),
  ShapePart("feet", "Body", "Feet", "How big the feet are.", ShapeFrame.feet,
      [ShapeSlider("feet.size", "Size")]),
  ShapePart(
      "skin",
      "Body",
      "Skin",
      "The skin's colour, face and body together.",
      ShapeFrame.body,
      [ShapeColour("colour.skin", "Skin", skinPalette)]),
];
