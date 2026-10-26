import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_motion.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_wardrobe.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';

// character_element.dart is a person, an animal or a monster on a canvas: a
// cast member with a body, a look and a pose.
//
// A character is drawn from settings -- its "DNA" -- rather than kept as a
// picture. How tall it is in heads, how broad, its skin, hair and clothes are
// numbers and choices, and a style draws them. That is what lets the same
// person be redrawn in another style, a shirt fit any body, and a cast of
// dozens cost nothing to ship.
//
// It stands on a skeleton. Every bone's angle is relative to the bone it
// hangs from, in degrees, clockwise on the page, and nought is the bone at
// rest: arms and legs hanging straight down, the body and head upright. The
// pose it is put in by hand is [CharacterElement.pose]. Once it is animated,
// a pose is a keyframe: each bone is a channel of the element's own track
// (see boneChannel), so the timeline, easing and undo all treat a character
// the way they treat a chart told how much of itself to draw.

/// CharacterBone is one bone of the skeleton.
///
/// Named for the side of the page it is on, not the character's own left and
/// right: a character facing the reader has their right hand on the page's
/// left, and "the left arm" meaning the one on the right of the screen is the
/// sort of thing nobody should have to think about while posing.
///
/// Serialised by name, so the order is free to change and the names are not.
enum CharacterBone {
  spine("Body lean"),
  head("Head tilt"),
  upperArmL("Left upper arm"),
  foreArmL("Left forearm"),
  upperArmR("Right upper arm"),
  foreArmR("Right forearm"),
  thighL("Left thigh"),
  shinL("Left shin"),
  thighR("Right thigh"),
  shinR("Right shin"),

  /// wings is how far wings are raised from folded, in degrees: what a
  /// flap moves. A bird's arms are its wings, and rise with it.
  wings("Wing flap");

  final String label;
  const CharacterBone(this.label);

  static CharacterBone? fromName(String? name) {
    for (var b in values) {
      if (b.name == name) return b;
    }
    return null;
  }
}

/// boneChannelPrefix starts the name of every bone's keyframe channel.
const String boneChannelPrefix = "bone.";

/// boneChannel is the keyframe channel [bone]'s angle is pinned on.
String boneChannel(CharacterBone bone) => "$boneChannelPrefix${bone.name}";

/// swingChannelPrefix starts the name of every bone's forward-and-back
/// keyframe channel.
const String swingChannelPrefix = "swing.";

/// swingChannel is the keyframe channel [bone]'s swing is pinned on.
String swingChannel(CharacterBone bone) => "$swingChannelPrefix${bone.name}";

/// turnChannel and liftChannel are the keyframe channels the whole body's
/// turn and lift are pinned on.
const String turnChannel = "body.turn";
const String liftChannel = "body.lift";

/// tiltChannel is the channel the view of the body tilted is pinned on.
const String tiltChannel = "body.tilt";

/// CharacterPose is an angle for each bone, in degrees, relative to the bone
/// it hangs from -- two of them: [angles], the spread seen from the front,
/// and [swings], forward and back, seen from the side -- and how the whole
/// body is turned and lifted. A bone it does not name is at rest.
///
/// Two angles because a figure is not flat. A walk is legs swinging forward
/// and back: seen from the side that is the whole of it, and seen from the
/// front it is legs getting shorter and longer. See CharacterRig, which
/// works the joints out in three dimensions and lays them on the page.
class CharacterPose {
  final Map<CharacterBone, double> angles;
  final Map<CharacterBone, double> swings;

  /// turn is the whole body turned away from the reader, in degrees: to the
  /// page's left as it grows, side on at 90, the back at 180.
  final double turn;

  /// lift is the whole body raised off the ground, in head lengths: a jump,
  /// and the bounce in a walk.
  final double lift;

  /// tilt is the body seen from above, in degrees -- from below as it goes
  /// negative: an orbit round the character up and over, as [turn] is one
  /// round it. A body in 3D is seen from there; a drawn one has its limbs
  /// foreshortened as they would be.
  final double tilt;

  const CharacterPose(
      [this.angles = const {},
      this.swings = const {},
      this.turn = 0,
      this.lift = 0,
      this.tilt = 0]);

  static const CharacterPose rest = CharacterPose();

  double operator [](CharacterBone bone) => angles[bone] ?? 0;

  double swing(CharacterBone bone) => swings[bone] ?? 0;

  CharacterPose withAngle(CharacterBone bone, double degrees) =>
      CharacterPose({...angles, bone: degrees}, swings, turn, lift, tilt);

  CharacterPose withAngles(Map<CharacterBone, double> more) =>
      CharacterPose({...angles, ...more}, swings, turn, lift, tilt);

  CharacterPose withSwing(CharacterBone bone, double degrees) =>
      CharacterPose(angles, {...swings, bone: degrees}, turn, lift, tilt);

  CharacterPose withSwings(Map<CharacterBone, double> more) =>
      CharacterPose(angles, {...swings, ...more}, turn, lift, tilt);

  CharacterPose withTurn(double degrees) =>
      CharacterPose(angles, swings, degrees, lift, tilt);

  CharacterPose withLift(double heads) =>
      CharacterPose(angles, swings, turn, heads, tilt);

  CharacterPose withTilt(double degrees) =>
      CharacterPose(angles, swings, turn, lift, degrees);

  /// lerp is this pose [t] of the way to [other], bone by bone.
  CharacterPose lerp(CharacterPose other, double t) {
    if (t <= 0) return this;
    if (t >= 1) return other;
    double mix(double a, double b) => a + (b - a) * t;
    return CharacterPose({
      for (var b in CharacterBone.values) b: mix(this[b], other[b]),
    }, {
      for (var b in CharacterBone.values) b: mix(swing(b), other.swing(b)),
    }, mix(turn, other.turn), mix(lift, other.lift), mix(tilt, other.tilt));
  }

  /// plus is this pose with [other] added to it, [weight] of it: a motion
  /// laid on top of another -- breathing over a walk.
  CharacterPose plus(CharacterPose other, [double weight = 1]) =>
      CharacterPose({
        for (var b in CharacterBone.values) b: this[b] + other[b] * weight,
      }, {
        for (var b in CharacterBone.values)
          b: swing(b) + other.swing(b) * weight,
      }, turn + other.turn * weight, lift + other.lift * weight,
          tilt + other.tilt * weight);

  /// only is this pose with only [bones] taken from [other], [weight] of the
  /// way: a wave laid over the arm of a walk, and nothing else of it.
  CharacterPose only(
          CharacterPose other, Set<CharacterBone> bones, double weight) =>
      CharacterPose({
        for (var b in CharacterBone.values)
          b: bones.contains(b) ? this[b] + (other[b] - this[b]) * weight : this[b],
      }, {
        for (var b in CharacterBone.values)
          b: bones.contains(b)
              ? swing(b) + (other.swing(b) - swing(b)) * weight
              : swing(b),
      }, turn, lift, tilt);

  /// over is this pose with whatever [frame]'s keyframe pins in its place:
  /// the pose the character has at that frame.
  CharacterPose over(Keyframe frame) {
    var v = frame.values;
    if (v.isEmpty) return this;
    Map<CharacterBone, double>? a, s;
    for (var bone in CharacterBone.values) {
      if (v[boneChannel(bone)] case var x?) (a ??= {...angles})[bone] = x;
      if (v[swingChannel(bone)] case var x?) (s ??= {...swings})[bone] = x;
    }
    var t = v[turnChannel], l = v[liftChannel], k = v[tiltChannel];
    if (a == null && s == null && t == null && l == null && k == null) {
      return this;
    }
    return CharacterPose(
        a ?? angles, s ?? swings, t ?? turn, l ?? lift, k ?? tilt);
  }

  /// channels is every bone as keyframe channels, at rest ones included: a
  /// pose keyed is the whole pose, or a bone left out would hold whatever an
  /// earlier keyframe gave it.
  Map<String, double> get channels => {
        for (var bone in CharacterBone.values) ...{
          boneChannel(bone): this[bone],
          swingChannel(bone): swing(bone),
        },
        turnChannel: turn,
        liftChannel: lift,
        tiltChannel: tilt,
      };

  Map<String, dynamic> toJson() => {
        for (var e in angles.entries)
          if (e.value != 0) e.key.name: e.value,
        if (swings.values.any((v) => v != 0))
          "swing": {
            for (var e in swings.entries)
              if (e.value != 0) e.key.name: e.value,
          },
        if (turn != 0) "turn": turn,
        if (lift != 0) "lift": lift,
        if (tilt != 0) "tilt": tilt,
      };

  factory CharacterPose.fromJson(Object? json) {
    if (json is! Map) return rest;
    Map<CharacterBone, double> bones(Object? m) => {
          if (m is Map)
            for (var e in m.entries)
              if (CharacterBone.fromName("${e.key}") case var bone?
                  when e.value is num)
                bone: (e.value as num).toDouble(),
        };
    return CharacterPose(bones(json), bones(json["swing"]),
        jsonDouble(json["turn"], 0), jsonDouble(json["lift"], 0),
        jsonDouble(json["tilt"], 0).clamp(-85.0, 85.0));
  }
}

/// FaceControl is one thing a face can do, as a number: how far the brows
/// are up, how open the mouth is, which way the head is turned.
///
/// Numbers rather than drawn expressions, so that a feeling is a setting of
/// these (see expressionPresets), two feelings mix by mixing the numbers,
/// and each one is a keyframe channel of its own -- the face is animated the
/// way the bones are. See faceChannel.
enum FaceControl {
  lookX("Look across", -1, 1, 0),
  lookY("Look up", -1, 1, 0),
  eyesOpen("Eyes open", 0, 1.3, 1),
  squint("Squint", 0, 1, 0),
  browRaise("Brows up", -1, 1, 0),
  browSqueeze("Frown", 0, 1, 0),
  browWorry("Worry", 0, 1, 0),
  smile("Smile", -1, 1, 0),
  jaw("Mouth open", 0, 1, 0),
  wide("Wide or pucker", -1, 1, 0),

  /// turn is the head turned away from the reader, in degrees: towards the
  /// page's left as it goes up, round to the back at 180.
  turn("Head turn", -180, 180, 0),

  /// nod is the head tipped down (up when negative), in degrees.
  nod("Nod", -30, 30, 0);

  final String label;
  final double min;
  final double max;
  final double rest;
  const FaceControl(this.label, this.min, this.max, this.rest);

  static FaceControl? fromName(String? name) {
    for (var c in values) {
      if (c.name == name) return c;
    }
    return null;
  }
}

/// MouthShape is one of the mouths speech is drawn with: the six basic
/// shapes and three extra that hand-drawn animation has used since the
/// Hanna-Barbera studios, named by their usual letters. [rest] is no shape
/// at all -- the mouth the face's own controls make, smiling or frowning.
enum MouthShape {
  rest("X", "Rest"),
  closed("A", "M B P"),
  teeth("B", "K S T EE"),
  open("C", "EH AE"),
  wide("D", "AA I"),
  round("E", "AO ER"),
  pucker("F", "OO W"),
  lip("G", "F V"),
  tongue("H", "L");

  final String letter;
  final String sounds;
  const MouthShape(this.letter, this.sounds);

  static MouthShape fromIndex(num? i) {
    var n = i?.round() ?? 0;
    return n >= 0 && n < values.length ? values[n] : rest;
  }

  static MouthShape fromName(String? name) =>
      values.firstWhere((m) => m.name == name, orElse: () => rest);
}

/// faceChannelPrefix starts the name of every face keyframe channel.
const String faceChannelPrefix = "face.";

/// faceChannel is the keyframe channel [control] is pinned on.
String faceChannel(FaceControl control) => "$faceChannelPrefix${control.name}";

/// mouthChannel is the keyframe channel the mouth shape is pinned on, as
/// its index in MouthShape. Held rather than eased: there is no shape half
/// way between an M and an O, so a mouth changes on the frame it is keyed.
const String mouthChannel = "${faceChannelPrefix}mouth";

/// performanceChannel is whether [channel] is part of a character's
/// performance -- a bone or the face -- rather than of where it is.
bool performanceChannel(String channel) =>
    channel.startsWith(boneChannelPrefix) ||
    channel.startsWith(swingChannelPrefix) ||
    channel.startsWith("body.") ||
    channel.startsWith(faceChannelPrefix);

/// posingChannel is a performance channel other than the mouth. Lip sync
/// keys only the mouth, and a character whose mouth has been synced to a
/// voice-over has not been posed: how it stands is still its stance.
bool posingChannel(String channel) =>
    performanceChannel(channel) && channel != mouthChannel;

/// CharacterFace is a setting for each face control, and a mouth shape. A
/// control it does not name is at its rest.
class CharacterFace {
  final Map<FaceControl, double> controls;
  final MouthShape mouth;

  const CharacterFace([this.controls = const {}, this.mouth = MouthShape.rest]);

  static const CharacterFace rest = CharacterFace();

  double operator [](FaceControl c) => controls[c] ?? c.rest;

  CharacterFace withControl(FaceControl c, double v) =>
      CharacterFace({...controls, c: v.clamp(c.min, c.max).toDouble()}, mouth);

  CharacterFace withControls(Map<FaceControl, double> more) =>
      CharacterFace({...controls, ...more}, mouth);

  CharacterFace withMouth(MouthShape m) => CharacterFace(controls, m);

  /// feeling is this face with the expression of [other] -- everything but
  /// how the head is turned, which is where the character is facing rather
  /// than how it feels. Where the eyes look is part of a feeling: thinking
  /// looks up and away.
  CharacterFace feeling(CharacterFace other) => CharacterFace({
        ...controls,
        for (var c in FaceControl.values)
          if (!c.aims) c: other[c],
      }, mouth);

  /// mixed is this face [t] of the way to [other].
  CharacterFace mixed(CharacterFace other, double t) => CharacterFace({
        for (var c in FaceControl.values) c: this[c] + (other[c] - this[c]) * t,
      }, t < 0.5 ? mouth : other.mouth);

  /// over is this face with whatever [frame]'s keyframe pins in its place.
  /// The mouth is not read here: it is held, see CharacterElement.faceAtFrame.
  CharacterFace over(Keyframe frame) {
    if (frame.values.isEmpty) return this;
    Map<FaceControl, double>? out;
    for (var c in FaceControl.values) {
      var v = frame.values[faceChannel(c)];
      if (v == null) continue;
      (out ??= {...controls})[c] = v;
    }
    return out == null ? this : CharacterFace(out, mouth);
  }

  /// channels is every control as a keyframe channel, and the mouth.
  Map<String, double> get channels => {
        for (var c in FaceControl.values) faceChannel(c): this[c],
        mouthChannel: mouth.index.toDouble(),
      };

  Map<String, dynamic> toJson() => {
        for (var e in controls.entries)
          if (e.value != e.key.rest) e.key.name: e.value,
        if (mouth != MouthShape.rest) "mouth": mouth.name,
      };

  factory CharacterFace.fromJson(Object? json) {
    if (json is! Map) return rest;
    return CharacterFace({
      for (var e in json.entries)
        if (FaceControl.fromName("${e.key}") case var c? when e.value is num)
          c: (e.value as num).toDouble().clamp(c.min, c.max).toDouble(),
    }, MouthShape.fromName(json["mouth"] as String?));
  }
}

extension on FaceControl {
  /// aims is whether this control is which way the head points rather than
  /// what the face feels.
  bool get aims => this == FaceControl.turn || this == FaceControl.nod;
}

/// CharacterLife is the small movements a character makes on its own:
/// blinking, breathing and glancing about. Worked out from the frame and
/// the character's id, never from a random number, so the export blinks on
/// the same frames the stage did.
class CharacterLife {
  final bool blink;
  final bool breathe;
  final bool glance;

  const CharacterLife(
      {this.blink = true, this.breathe = true, this.glance = false});

  static const CharacterLife still =
      CharacterLife(blink: false, breathe: false, glance: false);

  bool get any => blink || breathe || glance;

  CharacterLife copyWith({bool? blink, bool? breathe, bool? glance}) =>
      CharacterLife(
          blink: blink ?? this.blink,
          breathe: breathe ?? this.breathe,
          glance: glance ?? this.glance);

  Map<String, dynamic> toJson() =>
      {"blink": blink, "breathe": breathe, "glance": glance};

  factory CharacterLife.fromJson(Object? json) {
    if (json is! Map) return const CharacterLife();
    const d = CharacterLife();
    return CharacterLife(
        blink: jsonBool(json["blink"], d.blink),
        breathe: jsonBool(json["breathe"], d.breathe),
        glance: jsonBool(json["glance"], d.glance));
  }
}

/// CharacterStyle is how a character's DNA is drawn.
enum CharacterStyle {
  /// featureCartoon is soft shapes, a big readable face and a coloured
  /// outline a shade darker than what it goes round.
  featureCartoon("Feature cartoon", "Soft shapes, readable faces, a shaded line"),
  anime("Anime", "Big bright eyes and a cel shadow"),
  manga("Manga ink", "Black ink and screentone, no colour"),
  chibi("Chibi", "A big head on a small body"),
  tvFlat("TV flat", "Flat colour and a thick even line"),
  rubberHose("Rubber hose", "1930s bendy limbs, gloves and pie eyes"),
  comic("Comic", "Bold ink with halftone shadows"),
  storybook("Storybook", "Soft washed colour and a pencil line"),
  clay("Clay", "Rounded and unlined, moving on twos"),
  paperCutout("Paper cut-out", "Flat pieces with a shadow behind"),
  pixel("Pixel", "Drawn small and scaled up crisply"),
  noir("Noir", "A silhouette with a rim of light");

  final String label;

  /// about is what it looks like, under its tile.
  final String about;
  const CharacterStyle(this.label, this.about);

  static CharacterStyle fromName(String? name) => values
      .firstWhere((s) => s.name == name, orElse: () => featureCartoon);

  /// onTwos is whether it moves on every second frame only, as stop-motion
  /// and much hand-drawn animation does.
  bool get onTwos => this == clay;

  /// frameOf is [frame] as this style moves: the even frame before it, for
  /// a style on twos.
  int frameOf(int frame) => onTwos ? frame - frame % 2 : frame;

  /// dnaOf is [dna] as this style draws it: a chibi is at most two and a
  /// half heads tall whatever its own proportions say.
  CharacterDna dnaOf(CharacterDna dna) => this == chibi && dna.headsTall > 2.6
      ? dna.copyWith(headsTall: 2.6, build: math.min(1.0, dna.build + 0.15))
      : dna;
}

enum HairStyle {
  short("Short"),
  long("Long"),
  bun("Bun"),
  curly("Curly"),
  bald("None");

  final String label;
  const HairStyle(this.label);

  static HairStyle fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => short);
}

/// Species is what kind of creature a character is: its ears, its muzzle,
/// its nose and whiskers. A person is one too.
enum Species {
  human("Person"),
  cat("Cat"),
  dog("Dog"),
  fox("Fox"),
  bear("Bear"),
  rabbit("Rabbit"),
  mouse("Mouse"),
  pig("Pig"),
  bird("Bird"),
  fish("Fish"),
  monster("Monster");

  final String label;
  const Species(this.label);

  static Species fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => human);

  bool get animal => this != human && this != monster;

  /// legless is whether it has no legs to stand on: a fish swims.
  bool get legless => this == fish;
}

enum TailKind {
  none("None"),
  long("Long"),
  bushy("Bushy"),
  curly("Curly"),
  stub("Stub"),
  dragon("Dragon");

  final String label;
  const TailKind(this.label);

  static TailKind fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => none);
}

enum WingKind {
  none("None"),
  feathered("Feathered"),
  bat("Bat");

  final String label;
  const WingKind(this.label);

  static WingKind fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => none);
}

enum HornKind {
  none("None"),
  small("Small"),
  ram("Ram"),
  antlers("Antlers");

  final String label;
  const HornKind(this.label);

  static HornKind fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => none);
}

/// CharacterDna is everything a character looks like, with no style in it.
class CharacterDna {
  /// headsTall is the character's height in head lengths: about two and a
  /// half for a chibi, five and a half for a cartoon, seven and a half for a
  /// real adult.
  final double headsTall;

  /// build is how broad the character is, from 0 (slight) to 1 (broad).
  final double build;

  final Color skin;
  final Color hair;
  final HairStyle hairStyle;
  final Color eyes;

  /// wardrobe is what is worn, from the skin outwards: the order is which
  /// is worn over which. See character_wardrobe.dart.
  final List<Garment> wardrobe;

  /// baseLayer is whether the base layer -- underwear, swimwear -- is
  /// drawn. On, taking off a character's clothes never leaves it bare.
  final bool baseLayer;

  final Species species;

  /// fourLegs stands the character on four legs: the body pitched forward,
  /// the arms its front legs, the head brought up to look ahead.
  final bool fourLegs;

  final TailKind tail;
  final WingKind wings;
  final HornKind horns;

  /// eyeCount is how many eyes: 1 for a cyclops, 2, or 3.
  final int eyeCount;

  final bool fangs;
  final bool spikes;

  /// fur2 is the lighter fur of a muzzle, a belly, the inside of an ear --
  /// and a monster's spikes and horns.
  final Color fur2;

  const CharacterDna({
    this.headsTall = 5.5,
    this.build = 0.4,
    this.skin = const Color(0xFFF2C7A5),
    this.hair = const Color(0xFF3B2A20),
    this.hairStyle = HairStyle.short,
    this.eyes = const Color(0xFF5A3B28),
    this.wardrobe = defaultWardrobe,
    this.baseLayer = true,
    this.species = Species.human,
    this.fourLegs = false,
    this.tail = TailKind.none,
    this.wings = WingKind.none,
    this.horns = HornKind.none,
    this.eyeCount = 2,
    this.fangs = false,
    this.spikes = false,
    this.fur2 = const Color(0xFFF6EBDD),
  });

  /// defaultWardrobe is a new character's clothes: a hoodie and trousers
  /// over the base layer, and trainers.
  static const List<Garment> defaultWardrobe = [
    ...baseLayer_,
    Garment(GarmentKind.trousers, color: Color(0xFF2F3E5C)),
    Garment(GarmentKind.hoodie, color: Color(0xFF5B9CFF)),
    Garment(GarmentKind.trainers, color: Color(0xFFF2F2F2)),
  ];

  static const double minHeads = 2;
  static const double maxHeads = 8;

  /// worn is what is drawn: the wardrobe, without the base layer when it
  /// is switched off.
  List<Garment> get worn => baseLayer
      ? wardrobe
      : [for (var g in wardrobe) if (g.kind.slot != GarmentSlot.base) g];

  CharacterDna copyWith({
    double? headsTall,
    double? build,
    Color? skin,
    Color? hair,
    HairStyle? hairStyle,
    Color? eyes,
    List<Garment>? wardrobe,
    bool? baseLayer,
    Species? species,
    bool? fourLegs,
    TailKind? tail,
    WingKind? wings,
    HornKind? horns,
    int? eyeCount,
    bool? fangs,
    bool? spikes,
    Color? fur2,
  }) =>
      CharacterDna(
        headsTall: (headsTall ?? this.headsTall).clamp(minHeads, maxHeads),
        build: (build ?? this.build).clamp(0.0, 1.0),
        skin: skin ?? this.skin,
        hair: hair ?? this.hair,
        hairStyle: hairStyle ?? this.hairStyle,
        eyes: eyes ?? this.eyes,
        wardrobe: wardrobe ?? this.wardrobe,
        baseLayer: baseLayer ?? this.baseLayer,
        species: species ?? this.species,
        fourLegs: fourLegs ?? this.fourLegs,
        tail: tail ?? this.tail,
        wings: wings ?? this.wings,
        horns: horns ?? this.horns,
        eyeCount: (eyeCount ?? this.eyeCount).clamp(1, 3),
        fangs: fangs ?? this.fangs,
        spikes: spikes ?? this.spikes,
        fur2: fur2 ?? this.fur2,
      );

  Map<String, dynamic> toJson() => {
        "heads": headsTall,
        "build": build,
        "skin": colorToJson(skin),
        "hair": colorToJson(hair),
        "hairStyle": hairStyle.name,
        "eyes": colorToJson(eyes),
        "wardrobe": [for (var g in wardrobe) g.toJson()],
        if (!baseLayer) "baseLayer": false,
        if (species != Species.human) "species": species.name,
        if (fourLegs) "fourLegs": true,
        if (tail != TailKind.none) "tail": tail.name,
        if (wings != WingKind.none) "wings": wings.name,
        if (horns != HornKind.none) "horns": horns.name,
        if (eyeCount != 2) "eyeCount": eyeCount,
        if (fangs) "fangs": true,
        if (spikes) "spikes": true,
        "fur2": colorToJson(fur2),
      };

  factory CharacterDna.fromJson(Map<String, dynamic> json) {
    const d = CharacterDna();
    return CharacterDna(
      headsTall: jsonDouble(json["heads"], d.headsTall)
          .clamp(minHeads, maxHeads),
      build: jsonDouble(json["build"], d.build).clamp(0.0, 1.0),
      skin: colorFromJson(json["skin"], d.skin),
      hair: colorFromJson(json["hair"], d.hair),
      hairStyle: HairStyle.fromName(json["hairStyle"] as String?),
      eyes: colorFromJson(json["eyes"], d.eyes),
      wardrobe: json["wardrobe"] is List
          ? [
              for (var g in json["wardrobe"] as List)
                if (Garment.fromJson(g) case var garment?) garment,
            ]
          : _olderClothes(json),
      baseLayer: jsonBool(json["baseLayer"], true),
      species: Species.fromName(json["species"] as String?),
      fourLegs: jsonBool(json["fourLegs"], false),
      tail: TailKind.fromName(json["tail"] as String?),
      wings: WingKind.fromName(json["wings"] as String?),
      horns: HornKind.fromName(json["horns"] as String?),
      eyeCount: jsonInt(json["eyeCount"], 2).clamp(1, 3),
      fangs: jsonBool(json["fangs"], false),
      spikes: jsonBool(json["spikes"], false),
      fur2: colorFromJson(json["fur2"], d.fur2),
    );
  }

  /// _olderClothes is the wardrobe of a character saved before it had one:
  /// a top, bottoms and shoes, each a kind and a colour.
  static List<Garment> _olderClothes(Map<String, dynamic> json) {
    var top = switch (json["top"]) {
      "tee" => GarmentKind.tee,
      "shirt" => GarmentKind.shirt,
      "dress" => GarmentKind.dress,
      _ => GarmentKind.hoodie,
    };
    var bottom = switch (json["bottom"]) {
      "shorts" => GarmentKind.shorts,
      "skirt" => GarmentKind.skirt,
      _ => GarmentKind.trousers,
    };
    return [
      ...baseLayer_,
      if (top != GarmentKind.dress)
        Garment(bottom,
            color: colorFromJson(json["bottomColor"], const Color(0xFF2F3E5C))),
      Garment(top,
          color: colorFromJson(json["topColor"], const Color(0xFF5B9CFF))),
      Garment(GarmentKind.trainers,
          color: colorFromJson(json["shoes"], const Color(0xFFF2F2F2))),
    ];
  }
}

/// CharacterShadow is the shadow a character casts on the ground it
/// stands on.
enum CharacterShadow {
  none("None"),
  soft("Soft"),
  hard("Hard");

  final String label;
  const CharacterShadow(this.label);

  static CharacterShadow fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => soft);
}

/// OnStage is where a character stands on a 3D stage: which stage, the spot
/// on its floor in metres, how tall it is, and which way it faces on it.
class OnStage {
  /// stage is the StageElement's id.
  final String stage;
  final double x;
  final double z;

  /// height is how tall the character stands, in metres.
  final double height;

  /// facing is which way round it stands on the floor, in degrees, before
  /// the camera is taken into account.
  final double facing;

  const OnStage(this.stage,
      {this.x = 0, this.z = 0, this.height = 1.7, this.facing = 0});

  OnStage copyWith(
          {double? x, double? z, double? height, double? facing}) =>
      OnStage(stage,
          x: x ?? this.x,
          z: z ?? this.z,
          height: (height ?? this.height).clamp(0.1, 30.0),
          facing: facing ?? this.facing);

  Map<String, dynamic> toJson() =>
      {"stage": stage, "x": x, "z": z, "height": height, "facing": facing};

  static OnStage? fromJson(Object? json) {
    if (json is! Map) return null;
    var id = jsonString(json["stage"], "");
    if (id.isEmpty) return null;
    return OnStage(id,
        x: jsonDouble(json["x"], 0),
        z: jsonDouble(json["z"], 0),
        height: jsonDouble(json["height"], 1.7).clamp(0.1, 30.0),
        facing: jsonDouble(json["facing"], 0));
  }
}

/// BodyKind is what a character's body is made of: drawn flat, as every
/// style draws it, or modelled in 3D.
enum BodyKind {
  drawn("Drawn"),

  /// mannequin is the body built in 3D from the character's own
  /// proportions and colours -- smooth, with no file behind it.
  mannequin("Mannequin"),

  /// model is a 3D character from a file: a .glb, .gltf or .vrm.
  model("Model");

  final String label;
  const BodyKind(this.label);

  static BodyKind fromName(String? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => drawn);
}

/// ModelShading is how a body in 3D is lit.
enum ModelShading {
  soft("Soft"),

  /// toon is lit in two flat bands, as cel animation is.
  toon("Toon"),

  /// flat is every face of the mesh one shade, as early 3D was.
  flat("Faceted");

  final String label;
  const ModelShading(this.label);

  static ModelShading fromName(String? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => soft);
}

/// CharacterBody is a character's body in 3D, when it has one.
class CharacterBody {
  final BodyKind kind;

  /// modelId is the stored model file -- see CanvasMedia and MediaKind.model
  /// -- and modelName what it was called when it was brought in.
  final String modelId;
  final String modelName;
  final ModelShading shading;

  /// outline draws a line round the figure, as ink round a cel.
  final bool outline;

  const CharacterBody({
    this.kind = BodyKind.drawn,
    this.modelId = "",
    this.modelName = "",
    this.shading = ModelShading.soft,
    this.outline = false,
  });

  bool get inThreeD => kind != BodyKind.drawn;

  CharacterBody copyWith({
    BodyKind? kind,
    String? modelId,
    String? modelName,
    ModelShading? shading,
    bool? outline,
  }) =>
      CharacterBody(
          kind: kind ?? this.kind,
          modelId: modelId ?? this.modelId,
          modelName: modelName ?? this.modelName,
          shading: shading ?? this.shading,
          outline: outline ?? this.outline);

  Map<String, dynamic> toJson() => {
        "kind": kind.name,
        if (modelId.isNotEmpty) "model": modelId,
        if (modelName.isNotEmpty) "modelName": modelName,
        if (shading != ModelShading.soft) "shading": shading.name,
        if (outline) "outline": true,
      };

  static CharacterBody fromJson(Object? json) {
    if (json is! Map) return const CharacterBody();
    return CharacterBody(
        kind: BodyKind.fromName(json["kind"] as String?),
        modelId: jsonString(json["model"], ""),
        modelName: jsonString(json["modelName"], ""),
        shading: ModelShading.fromName(json["shading"] as String?),
        outline: jsonBool(json["outline"], false));
  }

  @override
  bool operator ==(Object other) =>
      other is CharacterBody &&
      other.kind == kind &&
      other.modelId == modelId &&
      other.modelName == modelName &&
      other.shading == shading &&
      other.outline == outline;

  @override
  int get hashCode => Object.hash(kind, modelId, modelName, shading, outline);
}

class CharacterElement extends CanvasElement {
  final CharacterDna dna;
  final CharacterStyle style;

  /// pose is how the character stands when nothing on the timeline says
  /// otherwise. Bones keyed on the track take its place, frame by frame.
  final CharacterPose pose;

  /// face is how the face is set when nothing on the timeline says
  /// otherwise, as [pose] is for the bones.
  final CharacterFace face;

  final CharacterLife life;

  /// motions is the clips laid over the pose -- a walk, a wave -- in the
  /// order they were added. See withMotions.
  final List<MotionClip> motions;

  /// bareView shows the character without its clothes while it is being
  /// designed -- on the stage only. Every picture and video made from the
  /// canvas is dressed, whatever this says.
  final bool bareView;

  /// onStage is where it stands on a 3D stage, or null when it is drawn
  /// on the page like any other element.
  final OnStage? onStage;

  final CharacterShadow shadow;

  /// depth is how much nearer and bigger the character looks for being
  /// lower on the page, and further and smaller for being higher: nought
  /// is not at all. What makes a walk into a picture go into it. Not on a
  /// stage, where the camera does this.
  final double depth;

  final ElementAnimation animation;

  /// body is whether it is drawn or in 3D, and in 3D what from.
  final CharacterBody body;

  const CharacterElement(
    super.base, {
    this.dna = const CharacterDna(),
    this.style = CharacterStyle.featureCartoon,
    this.pose = restPose,
    this.face = CharacterFace.rest,
    this.life = const CharacterLife(),
    this.motions = const [],
    this.bareView = false,
    this.onStage,
    this.shadow = CharacterShadow.soft,
    this.depth = 0,
    this.animation = const ElementAnimation(),
    this.body = const CharacterBody(),
  });

  /// restPose is a new character's stance: arms a little away from the body
  /// and feet a little apart, which reads as standing rather than as a
  /// diagram of a person.
  static const CharacterPose restPose = CharacterPose({
    CharacterBone.upperArmL: 10,
    CharacterBone.upperArmR: -10,
    CharacterBone.foreArmL: -4,
    CharacterBone.foreArmR: 4,
    CharacterBone.thighL: 3,
    CharacterBone.thighR: -3,
  });

  @override
  ElementKind get kind => ElementKind.character;

  /// The model a modelled body is made from is a stored file, kept for as
  /// long as a character uses it.
  @override
  Set<String> get mediaIds =>
      body.modelId.isEmpty ? const {} : {body.modelId};

  /// poseAtFrame is how the character stands on [frame].
  CharacterPose poseAtFrame(int frame) => pose.over(poseAt(frame));

  /// faceAtFrame is how the face is set on [frame]: its controls eased
  /// between keyframes, and its mouth held from the last keyframe that
  /// named one.
  CharacterFace faceAtFrame(int frame) {
    var at = face.over(poseAt(frame));
    var keys = track?.keys;
    if (keys == null) return at;
    double? mouth;
    for (var k in keys) {
      if (k.frame > frame) break;
      mouth = k.values[mouthChannel] ?? mouth;
    }
    if (mouth == null) {
      // Before the first key that names a mouth, that key's mouth holds --
      // as every other channel does before its first keyframe.
      for (var k in keys) {
        if (k.values[mouthChannel] case var m?) {
          mouth = m;
          break;
        }
      }
    }
    return mouth == null ? at : at.withMouth(MouthShape.fromIndex(mouth));
  }

  /// performanceAt is how the character is on [frame] at [frameRate], as it
  /// is drawn: its pose and face, with its motion clips laid over them.
  (CharacterPose, CharacterFace) performanceAt(int frame, int frameRate) =>
      withMotions(poseAtFrame(frame), faceAtFrame(frame), motions, frame,
          frameRate);

  /// posedOnTimeline is whether any bone or any part of the face is keyed,
  /// which is what makes a change of pose or face a keyframe rather than a
  /// change of how the character stands.
  bool get posedOnTimeline =>
      track?.keys.any((k) => k.values.keys.any(posingChannel)) ?? false;

  /// mouthKeys is every mouth keyed on the track, in order.
  List<({int frame, MouthShape shape})> get mouthKeys => [
        for (var k in track?.keys ?? const <Keyframe>[])
          if (k.values[mouthChannel] case var m?)
            (frame: k.frame, shape: MouthShape.fromIndex(m)),
      ];

  /// withMouths is this character with its mouth keys from [from] up to
  /// [to] replaced by [mouths] -- the rest of its keyframes, and its mouths
  /// outside that stretch, as they were.
  CharacterElement withMouths(
      List<({int frame, MouthShape shape})> mouths,
      {int from = 0,
      int to = 1 << 30}) {
    var t = track ?? ElementTrack.empty;
    for (var k in t.keys) {
      if (k.frame < from || k.frame >= to) continue;
      if (!k.values.containsKey(mouthChannel)) continue;
      var without = k.withoutValue(mouthChannel);
      t = without.values.isEmpty && !without.posesElement && without.frame != 0
          ? t.withoutFrame(k.frame)
          : t.withKey(without);
    }
    for (var m in mouths) {
      var at = t.keyAt(m.frame) ?? t.restingAt(m.frame);
      t = t.withKey(at.withValue(mouthChannel, m.shape.index.toDouble()));
    }
    return (t.isEmpty ? withBase(clearTrack: true) : withBase(track: t))
        as CharacterElement;
  }

  @override
  CanvasElement rebase(ElementBase base) => CharacterElement(base,
      dna: dna,
      style: style,
      pose: pose,
      face: face,
      life: life,
      motions: motions,
      bareView: bareView,
      onStage: onStage,
      shadow: shadow,
      depth: depth,
      animation: animation,
      body: body);

  CharacterElement copyWith({
    CharacterDna? dna,
    CharacterStyle? style,
    CharacterPose? pose,
    CharacterFace? face,
    CharacterLife? life,
    List<MotionClip>? motions,
    bool? bareView,
    OnStage? onStage,
    bool offStage = false,
    CharacterShadow? shadow,
    double? depth,
    ElementAnimation? animation,
    CharacterBody? body,
  }) =>
      CharacterElement(base,
          dna: dna ?? this.dna,
          style: style ?? this.style,
          pose: pose ?? this.pose,
          face: face ?? this.face,
          life: life ?? this.life,
          motions: motions ?? this.motions,
          bareView: bareView ?? this.bareView,
          onStage: offStage ? null : (onStage ?? this.onStage),
          shadow: shadow ?? this.shadow,
          depth: (depth ?? this.depth).clamp(0.0, 2.0),
          animation: animation ?? this.animation,
          body: body ?? this.body);

  @override
  Map<String, dynamic> props() => {
        "dna": dna.toJson(),
        if (style != CharacterStyle.featureCartoon) "style": style.name,
        "pose": pose.toJson(),
        if (face.toJson().isNotEmpty) "face": face.toJson(),
        "life": life.toJson(),
        if (motions.isNotEmpty) "motions": [for (var m in motions) m.toJson()],
        if (bareView) "bareView": true,
        if (onStage != null) "onStage": onStage!.toJson(),
        if (shadow != CharacterShadow.soft) "shadow": shadow.name,
        if (depth != 0) "depth": depth,
        if (animation.any) "anim": animation.toJson(),
        if (body != const CharacterBody()) "body": body.toJson(),
      };

  factory CharacterElement.fromJson(Map<String, dynamic> json, ElementBase b) =>
      CharacterElement(b,
          dna: json["dna"] is Map<String, dynamic>
              ? CharacterDna.fromJson(json["dna"] as Map<String, dynamic>)
              : const CharacterDna(),
          style: CharacterStyle.fromName(json["style"] as String?),
          // Absent is a character saved before it had a stance of its own,
          // which never happens yet -- but an empty map is a character
          // deliberately stood straight, and the two must not be confused.
          pose: json.containsKey("pose")
              ? CharacterPose.fromJson(json["pose"])
              : restPose,
          face: CharacterFace.fromJson(json["face"]),
          life: CharacterLife.fromJson(json["life"]),
          bareView: jsonBool(json["bareView"], false),
          onStage: OnStage.fromJson(json["onStage"]),
          shadow: CharacterShadow.fromName(json["shadow"] as String?),
          depth: jsonDouble(json["depth"], 0).clamp(0.0, 2.0),
          motions: [
            if (json["motions"] case List raw)
              for (var m in raw)
                if (MotionClip.fromJson(m) case var clip?) clip,
          ],
          animation: jsonSpec(json["anim"], ElementAnimation.fromJson,
              const ElementAnimation()),
          body: CharacterBody.fromJson(json["body"]));
}
