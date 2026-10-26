// character_appearance.dart is every way a character's body and face can
// be shaped, as numbers: the one description a drawn character, a sculpted
// one and a mannequin are all made from, so switching what a character is
// made of keeps the same person.
//
// Every control runs from -1 to 1 with nought at rest -- the character as
// its type and build make it -- so a character saved before these existed,
// with none of them set, is drawn exactly as it was.

/// AppearanceGroup is a tab of the Appearance editor.
enum AppearanceGroup {
  body("Body"),
  head("Head"),
  eyes("Eyes"),
  brows("Brows"),
  nose("Nose"),
  mouth("Mouth"),
  ears("Ears"),
  skin("Skin"),
  hair("Hair"),
  facialHair("Facial hair");

  final String label;
  const AppearanceGroup(this.label);
}

/// Look is one control of the Appearance editor: its group, its name, and
/// what its two ends are called.
enum Look {
  // Body.
  shoulders(AppearanceGroup.body, "Shoulders", "Narrow", "Broad"),
  chest(AppearanceGroup.body, "Chest", "Flat", "Full"),
  waist(AppearanceGroup.body, "Waist", "Narrow", "Wide"),
  hips(AppearanceGroup.body, "Hips", "Narrow", "Wide"),
  belly(AppearanceGroup.body, "Belly", "Flat", "Round"),
  muscle(AppearanceGroup.body, "Muscle", "Soft", "Muscular"),
  neckLength(AppearanceGroup.body, "Neck length", "Short", "Long"),
  neckWidth(AppearanceGroup.body, "Neck width", "Thin", "Thick"),
  armLength(AppearanceGroup.body, "Arm length", "Short", "Long"),
  armWidth(AppearanceGroup.body, "Arm width", "Thin", "Thick"),

  /// wrists is how much the forearm narrows from the elbow to the wrist.
  wrists(AppearanceGroup.body, "Wrists", "Slender", "Thick"),
  legLength(AppearanceGroup.body, "Leg length", "Short", "Long"),
  legWidth(AppearanceGroup.body, "Leg width", "Thin", "Thick"),

  /// ankles is how much the shin narrows from the knee to the ankle.
  ankles(AppearanceGroup.body, "Ankles", "Slender", "Thick"),
  hands(AppearanceGroup.body, "Hands", "Small", "Big"),
  feet(AppearanceGroup.body, "Feet", "Small", "Big"),
  posture(AppearanceGroup.body, "Posture", "Upright", "Stooped"),

  // Head.
  headWidth(AppearanceGroup.head, "Head width", "Narrow", "Wide"),
  headHeight(AppearanceGroup.head, "Head height", "Short", "Long"),
  forehead(AppearanceGroup.head, "Forehead", "Low", "High"),
  cheekbones(AppearanceGroup.head, "Cheekbones", "Soft", "High"),
  cheeks(AppearanceGroup.head, "Cheeks", "Hollow", "Full"),
  jaw(AppearanceGroup.head, "Jaw", "Narrow", "Square"),
  chin(AppearanceGroup.head, "Chin", "Round", "Pointed"),
  chinLength(AppearanceGroup.head, "Chin length", "Short", "Long"),

  // Eyes.
  eyeSize(AppearanceGroup.eyes, "Size", "Small", "Big"),
  eyeSpacing(AppearanceGroup.eyes, "Spacing", "Close", "Wide"),
  eyeHeight(AppearanceGroup.eyes, "Height", "Low", "High"),
  eyeTilt(AppearanceGroup.eyes, "Tilt", "Down", "Up"),
  eyeShape(AppearanceGroup.eyes, "Shape", "Round", "Almond"),
  iris(AppearanceGroup.eyes, "Iris", "Small", "Big"),
  lids(AppearanceGroup.eyes, "Lids", "Open", "Heavy"),
  lashes(AppearanceGroup.eyes, "Lashes", "None", "Long"),

  // Brows.
  browThickness(AppearanceGroup.brows, "Thickness", "Thin", "Thick"),
  browLength(AppearanceGroup.brows, "Length", "Short", "Long"),
  browHeight(AppearanceGroup.brows, "Height", "Low", "High"),
  browAngle(AppearanceGroup.brows, "Angle", "Sad", "Stern"),
  browArch(AppearanceGroup.brows, "Arch", "Straight", "Arched"),

  // Nose.
  noseWidth(AppearanceGroup.nose, "Width", "Narrow", "Wide"),
  noseLength(AppearanceGroup.nose, "Length", "Short", "Long"),
  noseHeight(AppearanceGroup.nose, "Height", "Low", "High"),
  noseBridge(AppearanceGroup.nose, "Bridge", "Flat", "Prominent"),
  noseTip(AppearanceGroup.nose, "Tip", "Small", "Round"),
  nostrils(AppearanceGroup.nose, "Nostrils", "Hidden", "Shown"),

  // Mouth.
  mouthWidth(AppearanceGroup.mouth, "Width", "Small", "Wide"),
  mouthHeight(AppearanceGroup.mouth, "Height", "Low", "High"),
  upperLip(AppearanceGroup.mouth, "Upper lip", "Thin", "Full"),
  lowerLip(AppearanceGroup.mouth, "Lower lip", "Thin", "Full"),
  corners(AppearanceGroup.mouth, "Corners", "Down", "Up"),
  lipColour(AppearanceGroup.mouth, "Lip colour", "Natural", "Strong"),

  // Ears.
  earSize(AppearanceGroup.ears, "Size", "Small", "Big"),
  earAngle(AppearanceGroup.ears, "Angle", "Flat", "Sticking out"),
  earPoint(AppearanceGroup.ears, "Tips", "Round", "Pointed"),
  earHeight(AppearanceGroup.ears, "Height", "Low", "High"),

  // Skin.
  freckles(AppearanceGroup.skin, "Freckles", "None", "Many"),
  blush(AppearanceGroup.skin, "Blush", "None", "Rosy"),
  age(AppearanceGroup.skin, "Age lines", "Smooth", "Lined"),
  shine(AppearanceGroup.skin, "Shine", "Matt", "Glossy"),

  // Hair.
  hairLength(AppearanceGroup.hair, "Length", "Short", "Long"),
  hairVolume(AppearanceGroup.hair, "Volume", "Flat", "Full"),
  fringe(AppearanceGroup.hair, "Fringe", "Swept back", "Long"),
  parting(AppearanceGroup.hair, "Parting", "Left", "Right"),
  hairline(AppearanceGroup.hair, "Hairline", "High", "Low"),
  highlights(AppearanceGroup.hair, "Highlights", "None", "Strong"),

  // Facial hair.
  stubble(AppearanceGroup.facialHair, "Stubble", "None", "Heavy"),
  moustache(AppearanceGroup.facialHair, "Moustache", "None", "Full"),
  beard(AppearanceGroup.facialHair, "Beard", "None", "Full"),
  beardLength(AppearanceGroup.facialHair, "Beard length", "Short", "Long");

  final AppearanceGroup group;
  final String label;

  /// low and high are what the two ends of the control are called.
  final String low, high;
  const Look(this.group, this.label, this.low, this.high);

  /// oneSided is whether nought is the least it goes to -- an amount of
  /// something, not a shape either way of the usual.
  bool get oneSided => const {
        lashes,
        nostrils,
        lipColour,
        freckles,
        blush,
        age,
        shine,
        highlights,
        stubble,
        moustache,
        beard,
      }.contains(this);

  double get min => oneSided ? 0 : -1;

  /// needs is the control this one shapes, which has to be set for this to
  /// show: a beard's length needs a beard.
  Look? get needs => switch (this) {
        beardLength => beard,
        _ => null,
      };

  static Look? fromName(String? name) {
    for (var l in values) {
      if (l.name == name) return l;
    }
    return null;
  }

  static List<Look> inGroup(AppearanceGroup g) =>
      [for (var l in values) if (l.group == g) l];
}

/// Appearance is a character's shape: a value for each control set away
/// from rest.
class Appearance {
  final Map<Look, double> values;
  const Appearance([this.values = const {}]);

  static const Appearance rest = Appearance();

  double operator [](Look l) => values[l] ?? 0;

  Appearance withValue(Look l, double v) {
    var next = {...values};
    v = v.clamp(l.min, 1.0);
    if (v.abs() < 1e-4) {
      next.remove(l);
    } else {
      next[l] = v;
    }
    return Appearance(next);
  }

  /// over is this with [other]'s values laid on top: a preset applied.
  Appearance over(Appearance other) {
    var next = {...values, ...other.values};
    return Appearance(next);
  }

  /// without is this with every control of [group] back at rest.
  Appearance without(AppearanceGroup group) =>
      Appearance({
        for (var e in values.entries)
          if (e.key.group != group) e.key: e.value,
      });

  bool get isRest => values.isEmpty;

  Map<String, dynamic> toJson() => {
        for (var e in values.entries)
          e.key.name: (e.value * 1000).round() / 1000,
      };

  factory Appearance.fromJson(Object? json) {
    if (json is! Map) return rest;
    var out = <Look, double>{};
    for (var e in json.entries) {
      var l = Look.fromName("${e.key}");
      if (l == null || e.value is! num) continue;
      var v = (e.value as num).toDouble().clamp(l.min, 1.0);
      if (v != 0) out[l] = v;
    }
    return Appearance(out);
  }

  @override
  bool operator ==(Object other) {
    if (other is! Appearance || other.values.length != values.length) {
      return false;
    }
    for (var e in values.entries) {
      if (other.values[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
      [for (var e in values.entries) Object.hash(e.key, e.value)]);
}

/// AppearancePreset is a quick start for one group: a name and the values
/// it sets, the rest of the group going back to rest.
class AppearancePreset {
  final String name;
  final AppearanceGroup group;
  final Appearance look;

  /// build, when given, is the build it sets too -- see CharacterDna.build.
  final double? build;
  const AppearancePreset(this.name, this.group, this.look, {this.build});
}

/// appearancePresets is the quick starts, group by group.
const List<AppearancePreset> appearancePresets = [
  // Body types, as a character designer builds them from basic shapes.
  AppearancePreset("Average", AppearanceGroup.body, Appearance(), build: 0.4),
  AppearancePreset("Slim", AppearanceGroup.body,
      Appearance({Look.shoulders: -0.3, Look.waist: -0.4, Look.hips: -0.3,
        Look.armWidth: -0.5, Look.legWidth: -0.5, Look.neckWidth: -0.3,
        Look.legLength: 0.3}),
      build: 0.15),
  AppearancePreset("Curvy", AppearanceGroup.body,
      Appearance({Look.chest: 0.6, Look.waist: -0.5, Look.hips: 0.8,
        Look.legWidth: 0.4, Look.shoulders: -0.15}),
      build: 0.45),
  AppearancePreset("Broad", AppearanceGroup.body,
      Appearance({Look.shoulders: 0.8, Look.chest: 0.4, Look.neckWidth: 0.5,
        Look.armWidth: 0.4, Look.hips: -0.1}),
      build: 0.8),
  AppearancePreset("Muscular", AppearanceGroup.body,
      Appearance({Look.shoulders: 0.6, Look.chest: 0.5, Look.waist: -0.3,
        Look.muscle: 1, Look.armWidth: 0.6, Look.legWidth: 0.5,
        Look.neckWidth: 0.6}),
      build: 0.7),
  AppearancePreset("Round", AppearanceGroup.body,
      Appearance({Look.belly: 1, Look.waist: 0.8, Look.hips: 0.4,
        Look.chest: 0.3, Look.armWidth: 0.5, Look.legWidth: 0.5,
        Look.neckWidth: 0.5, Look.cheeks: 0.6}),
      build: 0.9),
  AppearancePreset("Lanky", AppearanceGroup.body,
      Appearance({Look.armLength: 0.6, Look.legLength: 0.7, Look.neckLength: 0.5,
        Look.armWidth: -0.6, Look.legWidth: -0.6, Look.shoulders: -0.2,
        Look.posture: 0.3}),
      build: 0.1),

  // Head shapes.
  AppearancePreset("Oval", AppearanceGroup.head, Appearance()),
  AppearancePreset("Round", AppearanceGroup.head,
      Appearance({Look.headWidth: 0.4, Look.headHeight: -0.2, Look.cheeks: 0.6,
        Look.chin: -0.6, Look.jaw: 0.1})),
  AppearancePreset("Square", AppearanceGroup.head,
      Appearance({Look.jaw: 1, Look.chin: -0.3, Look.headWidth: 0.2,
        Look.cheekbones: 0.3})),
  AppearancePreset("Heart", AppearanceGroup.head,
      Appearance({Look.jaw: -0.6, Look.chin: 0.8, Look.cheekbones: 0.7,
        Look.forehead: 0.3})),
  AppearancePreset("Long", AppearanceGroup.head,
      Appearance({Look.headHeight: 0.6, Look.headWidth: -0.3,
        Look.chinLength: 0.5})),
  AppearancePreset("Diamond", AppearanceGroup.head,
      Appearance({Look.cheekbones: 1, Look.jaw: -0.4, Look.chin: 0.5,
        Look.forehead: -0.3})),

  // Eyes.
  AppearancePreset("Even", AppearanceGroup.eyes, Appearance()),
  AppearancePreset("Round", AppearanceGroup.eyes,
      Appearance({Look.eyeShape: -0.8, Look.eyeSize: 0.3, Look.iris: 0.2})),
  AppearancePreset("Almond", AppearanceGroup.eyes,
      Appearance({Look.eyeShape: 0.8, Look.eyeTilt: 0.2})),
  AppearancePreset("Hooded", AppearanceGroup.eyes,
      Appearance({Look.lids: 0.8, Look.eyeShape: 0.3})),
  AppearancePreset("Upturned", AppearanceGroup.eyes,
      Appearance({Look.eyeTilt: 0.8, Look.eyeShape: 0.5, Look.lashes: 0.5})),
  AppearancePreset("Downturned", AppearanceGroup.eyes,
      Appearance({Look.eyeTilt: -0.7, Look.lids: 0.3})),
  AppearancePreset("Big", AppearanceGroup.eyes,
      Appearance({Look.eyeSize: 0.9, Look.iris: 0.6, Look.eyeShape: -0.5,
        Look.lashes: 0.6})),

  // Brows.
  AppearancePreset("Natural", AppearanceGroup.brows, Appearance()),
  AppearancePreset("Thick", AppearanceGroup.brows,
      Appearance({Look.browThickness: 0.9, Look.browLength: 0.3})),
  AppearancePreset("Thin", AppearanceGroup.brows,
      Appearance({Look.browThickness: -0.8, Look.browArch: 0.6})),
  AppearancePreset("Arched", AppearanceGroup.brows,
      Appearance({Look.browArch: 1, Look.browHeight: 0.3})),
  AppearancePreset("Stern", AppearanceGroup.brows,
      Appearance({Look.browAngle: 0.8, Look.browThickness: 0.5,
        Look.browHeight: -0.4})),
  AppearancePreset("Worried", AppearanceGroup.brows,
      Appearance({Look.browAngle: -0.8, Look.browHeight: 0.3})),

  // Noses.
  AppearancePreset("Straight", AppearanceGroup.nose, Appearance()),
  AppearancePreset("Button", AppearanceGroup.nose,
      Appearance({Look.noseLength: -0.7, Look.noseTip: 0.7,
        Look.noseBridge: -0.6})),
  AppearancePreset("Roman", AppearanceGroup.nose,
      Appearance({Look.noseBridge: 1, Look.noseLength: 0.6, Look.noseTip: -0.3})),
  AppearancePreset("Wide", AppearanceGroup.nose,
      Appearance({Look.noseWidth: 0.9, Look.nostrils: 0.7, Look.noseTip: 0.4})),
  AppearancePreset("Small", AppearanceGroup.nose,
      Appearance({Look.noseWidth: -0.6, Look.noseLength: -0.5,
        Look.noseTip: -0.5})),
  AppearancePreset("Long", AppearanceGroup.nose,
      Appearance({Look.noseLength: 1, Look.noseBridge: 0.5})),

  // Mouths.
  AppearancePreset("Even", AppearanceGroup.mouth, Appearance()),
  AppearancePreset("Full", AppearanceGroup.mouth,
      Appearance({Look.upperLip: 0.8, Look.lowerLip: 0.9, Look.lipColour: 0.4})),
  AppearancePreset("Thin", AppearanceGroup.mouth,
      Appearance({Look.upperLip: -0.8, Look.lowerLip: -0.6})),
  AppearancePreset("Wide", AppearanceGroup.mouth,
      Appearance({Look.mouthWidth: 0.9})),
  AppearancePreset("Small", AppearanceGroup.mouth,
      Appearance({Look.mouthWidth: -0.7, Look.upperLip: 0.2})),
  AppearancePreset("Smiling", AppearanceGroup.mouth,
      Appearance({Look.corners: 0.8})),

  // Ears.
  AppearancePreset("Natural", AppearanceGroup.ears, Appearance()),
  AppearancePreset("Small", AppearanceGroup.ears,
      Appearance({Look.earSize: -0.7, Look.earAngle: -0.5})),
  AppearancePreset("Big", AppearanceGroup.ears,
      Appearance({Look.earSize: 0.8, Look.earAngle: 0.6})),
  AppearancePreset("Elf", AppearanceGroup.ears,
      Appearance({Look.earPoint: 1, Look.earSize: 0.5, Look.earHeight: 0.3})),

  // Skin.
  AppearancePreset("Clear", AppearanceGroup.skin, Appearance()),
  AppearancePreset("Freckled", AppearanceGroup.skin,
      Appearance({Look.freckles: 0.8, Look.blush: 0.3})),
  AppearancePreset("Rosy", AppearanceGroup.skin,
      Appearance({Look.blush: 0.8})),
  AppearancePreset("Older", AppearanceGroup.skin,
      Appearance({Look.age: 0.8})),
  AppearancePreset("Glossy", AppearanceGroup.skin,
      Appearance({Look.shine: 0.8})),

  // Hair cuts, over whichever style of hair is worn.
  AppearancePreset("As it is", AppearanceGroup.hair, Appearance()),
  AppearancePreset("Cropped", AppearanceGroup.hair,
      Appearance({Look.hairLength: -0.8, Look.hairVolume: -0.6,
        Look.fringe: -0.8})),
  AppearancePreset("Big", AppearanceGroup.hair,
      Appearance({Look.hairVolume: 1, Look.hairLength: 0.3})),
  AppearancePreset("Bangs", AppearanceGroup.hair,
      Appearance({Look.fringe: 1, Look.hairline: 0.3})),
  AppearancePreset("Side part", AppearanceGroup.hair,
      Appearance({Look.parting: 0.8, Look.fringe: 0.3})),
  AppearancePreset("Streaked", AppearanceGroup.hair,
      Appearance({Look.highlights: 0.8})),

  // Facial hair.
  AppearancePreset("None", AppearanceGroup.facialHair, Appearance()),
  AppearancePreset("Stubble", AppearanceGroup.facialHair,
      Appearance({Look.stubble: 0.8})),
  AppearancePreset("Moustache", AppearanceGroup.facialHair,
      Appearance({Look.moustache: 0.9})),
  AppearancePreset("Goatee", AppearanceGroup.facialHair,
      Appearance({Look.moustache: 0.6, Look.beard: 0.35, Look.beardLength: 0.2})),
  AppearancePreset("Short beard", AppearanceGroup.facialHair,
      Appearance({Look.moustache: 0.8, Look.beard: 0.8, Look.beardLength: -0.4})),
  AppearancePreset("Full beard", AppearanceGroup.facialHair,
      Appearance({Look.moustache: 1, Look.beard: 1, Look.beardLength: 0.6})),
];

List<AppearancePreset> presetsFor(AppearanceGroup g) =>
    [for (var p in appearancePresets) if (p.group == g) p];
