import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';

// human_targets.dart is how a character's Appearance and type become the
// shapes of the MakeHuman body -- its "targets", each a set of offsets on
// the base mesh. The downloader fetches exactly the targets named here and
// the builder applies exactly these, so the two cannot disagree.
//
// MakeHuman's assets are CC0: free to use for anything, with nothing owed.
// See https://static.makehumancommunity.org/makehuman/faq/are_makehuman_files_free.html

/// makeHumanCommit is the version of MakeHuman's files fetched: pinned, so
/// what is downloaded is always what this code was written against.
const String makeHumanCommit = "a8bc2d54ff0ac92e78ff71431b1023eda42bf482";

/// TargetPair is a control's two ends, as targets: the one it moves towards
/// below nought, and the one above. "X-" in a name stands for both sides --
/// "l-" and "r-" -- applied alike.
typedef TargetPair = (String? low, String? high);

/// lookTargets is each Appearance control's targets. A control not here --
/// lashes, freckles, a hairstyle -- is drawn rather than sculpted.
const Map<Look, List<TargetPair>> lookTargets = {
  Look.shoulders: [("torso/torso-vshape-decr", "torso/torso-vshape-incr")],
  Look.chest: [
    ("torso/torso-muscle-pectoral-decr", "torso/torso-muscle-pectoral-incr")
  ],
  Look.waist: [("hip/hip-waist-down", "hip/hip-waist-up")],
  Look.hips: [("hip/hip-scale-horiz-decr", "hip/hip-scale-horiz-incr")],
  Look.belly: [
    ("stomach/stomach-pregnant-decr", "stomach/stomach-pregnant-incr")
  ],
  Look.neckLength: [("neck/neck-scale-vert-decr", "neck/neck-scale-vert-incr")],
  Look.neckWidth: [
    ("neck/neck-scale-horiz-decr", "neck/neck-scale-horiz-incr")
  ],
  Look.armLength: [
    ("armslegs/X-upperarm-scale-vert-decr", "armslegs/X-upperarm-scale-vert-incr"),
    ("armslegs/X-lowerarm-scale-vert-decr", "armslegs/X-lowerarm-scale-vert-incr"),
  ],
  Look.armWidth: [
    ("armslegs/X-upperarm-scale-horiz-decr", "armslegs/X-upperarm-scale-horiz-incr"),
    ("armslegs/X-lowerarm-scale-horiz-decr", "armslegs/X-lowerarm-scale-horiz-incr"),
  ],
  Look.legLength: [
    ("armslegs/X-upperleg-scale-vert-decr", "armslegs/X-upperleg-scale-vert-incr"),
    ("armslegs/X-lowerleg-scale-vert-decr", "armslegs/X-lowerleg-scale-vert-incr"),
  ],
  Look.legWidth: [
    ("armslegs/X-upperleg-scale-horiz-decr", "armslegs/X-upperleg-scale-horiz-incr"),
    ("armslegs/X-lowerleg-scale-horiz-decr", "armslegs/X-lowerleg-scale-horiz-incr"),
  ],
  Look.hands: [("armslegs/X-hand-scale-decr", "armslegs/X-hand-scale-incr")],
  Look.feet: [("armslegs/X-foot-scale-decr", "armslegs/X-foot-scale-incr")],
  Look.headWidth: [
    ("head/head-scale-horiz-decr", "head/head-scale-horiz-incr")
  ],
  Look.headHeight: [("head/head-scale-vert-decr", "head/head-scale-vert-incr")],
  Look.forehead: [
    ("forehead/forehead-scale-vert-decr", "forehead/forehead-scale-vert-incr")
  ],
  Look.cheekbones: [("cheek/X-cheek-bones-decr", "cheek/X-cheek-bones-incr")],
  Look.cheeks: [("cheek/X-cheek-volume-decr", "cheek/X-cheek-volume-incr")],
  Look.jaw: [
    ("chin/chin-width-decr", "chin/chin-width-incr"),
    (null, "head/head-square"),
  ],
  Look.chin: [("chin/chin-bones-decr", "chin/chin-triangle")],
  Look.chinLength: [("chin/chin-height-decr", "chin/chin-height-incr")],
  Look.eyeSize: [("eyes/X-eye-scale-decr", "eyes/X-eye-scale-incr")],
  Look.eyeSpacing: [("eyes/X-eye-trans-in", "eyes/X-eye-trans-out")],
  Look.eyeHeight: [("eyes/X-eye-trans-down", "eyes/X-eye-trans-up")],
  Look.eyeTilt: [
    ("eyes/X-eye-eyefold-angle-down", "eyes/X-eye-eyefold-angle-up")
  ],
  Look.eyeShape: [("eyes/X-eye-height2-incr", "eyes/X-eye-height2-decr")],
  Look.lids: [("eyes/X-eye-eyefold-up", "eyes/X-eye-eyefold-down")],
  Look.browHeight: [
    ("eyebrows/eyebrows-trans-down", "eyebrows/eyebrows-trans-up")
  ],
  Look.browAngle: [
    ("eyebrows/eyebrows-angle-down", "eyebrows/eyebrows-angle-up")
  ],
  Look.noseWidth: [("nose/nose-scale-horiz-decr", "nose/nose-scale-horiz-incr")],
  Look.noseLength: [("nose/nose-scale-vert-decr", "nose/nose-scale-vert-incr")],
  Look.noseHeight: [("nose/nose-trans-down", "nose/nose-trans-up")],
  Look.noseBridge: [("nose/nose-hump-decr", "nose/nose-hump-incr")],
  Look.noseTip: [("nose/nose-volume-decr", "nose/nose-volume-incr")],
  Look.nostrils: [(null, "nose/nose-flaring-incr")],
  Look.mouthWidth: [
    ("mouth/mouth-scale-horiz-decr", "mouth/mouth-scale-horiz-incr")
  ],
  Look.mouthHeight: [("mouth/mouth-trans-down", "mouth/mouth-trans-up")],
  Look.upperLip: [
    ("mouth/mouth-upperlip-volume-decr", "mouth/mouth-upperlip-volume-incr")
  ],
  Look.lowerLip: [
    ("mouth/mouth-lowerlip-volume-decr", "mouth/mouth-lowerlip-volume-incr")
  ],
  Look.corners: [("mouth/mouth-angles-down", "mouth/mouth-angles-up")],
  Look.earSize: [("ears/X-ear-scale-decr", "ears/X-ear-scale-incr")],
  Look.earAngle: [("ears/X-ear-wing-decr", "ears/X-ear-wing-incr")],
  Look.earPoint: [("ears/X-ear-shape-round", "ears/X-ear-shape-pointed")],
  Look.earHeight: [("ears/X-ear-trans-down", "ears/X-ear-trans-up")],
  Look.age: [(null, "head/head-age-incr")],
};

/// humanFaceUnits are the face's own movements, as MakeHuman sculpted
/// them: each a shape of the head -- a lid shut, a brow raised, a lip
/// pulled -- kept whole on the body as a target of its own, and mixed by
/// humanUnitsOf into every face control and every mouth lip sync uses.
/// The face is the body's geometry; nothing is drawn on it.
const List<String> humanFaceUnits = [
  "eye-left-closure", "eye-right-closure",
  "eye-left-opened-up", "eye-right-opened-up",
  "eye-left-slit", "eye-right-slit",
  "eyebrows-left-down", "eyebrows-right-down",
  "eyebrows-left-up", "eyebrows-right-up",
  "eyebrows-left-inner-up", "eyebrows-right-inner-up",
  "eyebrows-left-extern-up", "eyebrows-right-extern-up",
  "mouth-compression", "mouth-corner-puller", "mouth-depression",
  "mouth-depression-retraction", "mouth-elevation", "mouth-eversion",
  "mouth-open", "mouth-parling", "mouth-part-later", "mouth-protusion",
  "mouth-pursing", "mouth-retraction", "mouth-upward-retraction",
  "nose-compression", "nose-depression",
  "nose-left-dilatation", "nose-right-dilatation",
  "nose-left-elevation", "nose-right-elevation",
  "neck-platysma",
];

/// unitTarget is the expression named [unit]'s target, by its path in
/// MakeHuman's data/targets.
String unitTarget(String unit) => "expression/units/caucasian/$unit";

/// humanUnitsOf is how far each of the face's units is moved for [face],
/// by name: its controls -- eyes, brows, smile, jaw -- and, while it
/// speaks, the mouth for the sound it is making, sculpted from the lips'
/// own units as an animator would key them.
Map<String, double> humanUnitsOf(CharacterFace face) {
  var out = <String, double>{};
  void put(String unit, double w) {
    if (w <= 0.001) return;
    out[unit] = ((out[unit] ?? 0) + w).clamp(0.0, 1.0);
  }

  void both(String unit, double w) {
    put(unit.replaceFirst("X-", "left-"), w);
    put(unit.replaceFirst("X-", "right-"), w);
  }

  // The eyes: shut by a blink or a smile's squint, wide when surprised.
  var open = face[FaceControl.eyesOpen];
  var squint = face[FaceControl.squint];
  var smile = face[FaceControl.smile];
  both("eye-X-closure", (1 - open).clamp(0.0, 1.0));
  both("eye-X-opened-up", ((open - 1) * 2).clamp(0.0, 1.0));
  both("eye-X-slit", squint + math.max(0.0, smile) * 0.25);
  // The brows.
  var raise = face[FaceControl.browRaise];
  both("eyebrows-X-up", raise);
  both("eyebrows-X-down", -raise + face[FaceControl.browSqueeze]);
  both("eyebrows-X-inner-up", face[FaceControl.browWorry]);
  put("nose-compression", face[FaceControl.browSqueeze] * 0.4);
  // The smile, or its frown; the cheeks and nose lift with a smile.
  put("mouth-corner-puller", smile);
  put("mouth-elevation", smile * 0.25);
  both("nose-X-elevation", smile * 0.2);
  put("mouth-depression", -smile);
  put("mouth-depression-retraction", -smile * 0.3);
  switch (face.mouth) {
    case MouthShape.rest:
      put("mouth-open", face[FaceControl.jaw]);
      var wide = face[FaceControl.wide];
      put("mouth-retraction", wide * 0.7);
      put("mouth-pursing", -wide * 0.8);
      put("mouth-protusion", -wide * 0.4);
    case MouthShape.closed:
      // M, B, P: the lips pressed together.
      put("mouth-compression", 0.8);
    case MouthShape.teeth:
      // K, S, T, EE: teeth together, lips drawn back.
      put("mouth-retraction", 0.6);
      put("mouth-upward-retraction", 0.35);
      put("mouth-open", 0.12);
    case MouthShape.open:
      // EH, AE.
      put("mouth-open", 0.45);
      put("mouth-retraction", 0.3);
    case MouthShape.wide:
      // AA, I: the jaw well down.
      put("mouth-open", 0.9);
      put("mouth-retraction", 0.15);
    case MouthShape.round:
      // AO, ER.
      put("mouth-open", 0.5);
      put("mouth-pursing", 0.45);
    case MouthShape.pucker:
      // OO, W: the lips pushed forward and round.
      put("mouth-pursing", 1);
      put("mouth-protusion", 0.6);
    case MouthShape.lip:
      // F, V: the lower lip tucked under the top teeth.
      put("mouth-depression-retraction", 0.5);
      put("mouth-eversion", 0.4);
      put("mouth-open", 0.1);
    case MouthShape.tongue:
      // L: open, the tongue behind the teeth.
      put("mouth-open", 0.45);
      put("mouth-upward-retraction", 0.2);
  }
  return out;
}

const List<String> _genders = ["female", "male"];
const List<String> _ages = ["baby", "child", "young", "old"];
const List<String> _levels = ["min", "average", "max"];
const List<String> _races = ["african", "asian", "caucasian"];

/// macroRaceTargets is the targets of each sex and age, one per people:
/// blended evenly when they are stored, into one per sex and age.
List<String> macroRaceTargets(String gender, String age) =>
    [for (var r in _races) "macrodetails/$r-$gender-$age"];

/// universalTarget is the target of a sex, age, muscle and weight.
String universalTarget(String gender, String age, String muscle, String weight) =>
    "macrodetails/universal-$gender-$age-${muscle}muscle-${weight}weight";

/// cupTargets are the chest of a woman, smaller and fuller.
const String smallCup =
    "breast/female-young-averagemuscle-averageweight-mincup-averagefirmness";
const String fullCup =
    "breast/female-young-averagemuscle-averageweight-maxcup-averagefirmness";

/// humanTargetFiles is every target the body needs, by its path in
/// MakeHuman's data/targets, without ".target".
List<String> humanTargetFiles() {
  var out = <String>{};
  void side(String name) {
    if (name.contains("X-")) {
      out.add(name.replaceFirst("X-", "l-"));
      out.add(name.replaceFirst("X-", "r-"));
    } else {
      out.add(name);
    }
  }

  for (var pairs in lookTargets.values) {
    for (var (low, high) in pairs) {
      if (low != null) side(low);
      if (high != null) side(high);
    }
  }
  for (var unit in humanFaceUnits) {
    out.add(unitTarget(unit));
  }
  for (var g in _genders) {
    for (var a in _ages) {
      out.addAll(macroRaceTargets(g, a));
      for (var m in _levels) {
        for (var w in _levels) {
          out.add(universalTarget(g, a, m, w));
        }
      }
    }
  }
  out.add(smallCup);
  out.add(fullCup);
  return out.toList()..sort();
}

/// HumanMacro is a body's age, sex, muscle and weight, as MakeHuman has
/// them: each from nought to one.
typedef HumanMacro = ({double gender, double age, double muscle, double weight});

/// humanMacroOf is [dna]'s body as MakeHuman's sliders -- [gender], when
/// given, how much a man's from nought to one, in place of its type's.
HumanMacro humanMacroOf(CharacterDna dna, {double? gender}) {
  var type = dna.kind;
  gender ??= switch (type) {
    CharacterType.woman || CharacterType.girl => 0.0,
    CharacterType.man || CharacterType.boy => 1.0,
    _ => 0.5,
  };
  // MakeHuman's age slider: a year old at nought, eleven at 0.1875,
  // twenty-five at a half, ninety at one.
  var age = switch (type) {
    CharacterType.baby => 0.0,
    CharacterType.girl || CharacterType.boy => 0.2,
    CharacterType.elder => 0.9,
    _ => 0.5,
  };
  var look = dna.look;
  return (
    gender: gender,
    age: age,
    muscle: (0.5 + 0.5 * look[Look.muscle]).clamp(0.0, 1.0),
    weight: (0.5 + 0.9 * (dna.build - 0.4) + 0.3 * look[Look.belly])
        .clamp(0.0, 1.0),
  );
}

/// macroWeights is how much of each macro target -- by its stored name --
/// makes up [m]: MakeHuman's own blending, sex by age by muscle by weight.
Map<String, double> macroWeights(HumanMacro m) {
  var gender = {"female": 1 - m.gender, "male": m.gender};
  // Age between its four steps.
  var a = m.age;
  var ages = <String, double>{};
  if (a < 0.1875) {
    var t = a / 0.1875;
    ages = {"baby": 1 - t, "child": t};
  } else if (a < 0.5) {
    var t = (a - 0.1875) / (0.5 - 0.1875);
    ages = {"child": 1 - t, "young": t};
  } else {
    var t = (a - 0.5) / 0.5;
    ages = {"young": 1 - t, "old": t};
  }
  Map<String, double> level(double v) => v < 0.5
      ? {"min": 1 - 2 * v, "average": 2 * v}
      : {"average": 2 - 2 * v, "max": 2 * v - 1};
  var muscle = level(m.muscle), weight = level(m.weight);
  var out = <String, double>{};
  for (var g in gender.entries) {
    for (var ag in ages.entries) {
      var gw = g.value * ag.value;
      if (gw <= 0) continue;
      out["macro/${g.key}-${ag.key}"] = gw;
      for (var mu in muscle.entries) {
        for (var we in weight.entries) {
          var w = gw * mu.value * we.value;
          if (w > 0) out[universalTarget(g.key, ag.key, mu.key, we.key)] = w;
        }
      }
    }
  }
  return out;
}
