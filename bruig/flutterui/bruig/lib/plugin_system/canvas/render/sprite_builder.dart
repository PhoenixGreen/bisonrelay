import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';

// sprite_builder.dart is a figure built from Kenney's modular character
// pack -- a head, a body, arms, legs, a face, hair and clothes, each a piece
// of its own in any of its colours -- put together as a cut-out puppet is:
// each piece laid on a skeleton, the left side the right side mirrored, and
// the arms and legs turned about the shoulder and the hip. Posed through an
// animation's frames -- standing, walking, running, jumping, waving -- it is
// drawn into a sprite sheet. See the Sprite element's builder.

/// ModularParts is the pack's pieces, found by their names: every choice
/// there is of each, and the pieces read as they are wanted.
class ModularParts {
  final Archive archive;
  ModularParts(this.archive) {
    _index();
  }

  /// The choices, each a name and the piece -- or pieces -- it stands for.
  final List<int> skins = [];
  final Map<String, Map<String, String>> hair = {};
  final Map<String, Map<int, String>> shirts = {};
  final Map<String, Map<String, String>> sleeves = {};
  final Map<String, Map<int, String>> pants = {};
  final Map<String, Map<String, String>> legs = {};
  final Map<String, Map<int, String>> shoes = {};
  final Map<String, String> eyes = {};
  final Map<String, String> brows = {};
  final Map<int, Map<int, String>> noses = {};
  final Map<String, String> mouths = {};
  final Set<String> _files = {};

  void _index() {
    var skin = RegExp(r"^PNG/Skin/Tint (\d+)/tint\d+_head\.png$");
    var hairRe = RegExp(r"^PNG/Hair/([^/]+)/[a-z0-9]+?((?:Man|Woman)\d+)\.png$", caseSensitive: false);
    // Named either way round -- "blueShirt1", "shirtYellow1" -- as the pack
    // has them.
    var shirt = RegExp(r"^PNG/Shirts/([^/]+)/\w*?shirt[a-z]*?(\d+)\.png$", caseSensitive: false);
    var sleeve = RegExp(r"^PNG/Shirts/([^/]+)/\w*?arm\w*?_(long|short|shorter)\.png$", caseSensitive: false);
    var pantsTop = RegExp(r"^PNG/Pants/([^/]+)/pants[A-Za-z]*\d*?(\d)\.png$");
    var pantsLeg =
        RegExp(r"^PNG/Pants/([^/]+)/\w*?(?:pants|leg)\w*?_(long|short|shorter)\.png$", caseSensitive: false);
    var shoe = RegExp(r"^PNG/Shoes/([^/]+)/\w*?shoe(\d+)\.png$", caseSensitive: false);
    var eye = RegExp(r"^PNG/Face/Eyes/eye(\w+?)_(large|small)\.png$");
    var brow = RegExp(r"^PNG/Face/Eyebrows/(\w+?)Brow(\d)\.png$");
    var nose = RegExp(r"^PNG/Face/Nose/Tint (\d+)/tint\d+Nose(\d)\.png$");
    var mouth = RegExp(r"^PNG/Face/Mouth/mouth_(\w+)\.png$");
    for (var f in archive.files) {
      if (!f.isFile) continue;
      var n = f.name;
      _files.add(n);
      RegExpMatch? m;
      if ((m = skin.firstMatch(n)) != null) {
        skins.add(int.parse(m!.group(1)!));
      } else if ((m = hairRe.firstMatch(n)) != null) {
        (hair[m!.group(1)!] ??= {})[m.group(2)!] = n;
      } else if ((m = sleeve.firstMatch(n)) != null) {
        (sleeves[m!.group(1)!] ??= {})[m.group(2)!] = n;
      } else if ((m = shirt.firstMatch(n)) != null) {
        (shirts[m!.group(1)!] ??= {})[int.parse(m.group(2)!)] = n;
      } else if ((m = pantsLeg.firstMatch(n)) != null) {
        (legs[m!.group(1)!] ??= {})[m.group(2)!] = n;
      } else if ((m = pantsTop.firstMatch(n)) != null) {
        (pants[m!.group(1)!] ??= {})[int.parse(m.group(2)!)] = n;
      } else if ((m = shoe.firstMatch(n)) != null) {
        (shoes[m!.group(1)!] ??= {})[int.parse(m.group(2)!)] = n;
      } else if ((m = eye.firstMatch(n)) != null) {
        eyes["${m!.group(1)} ${m.group(2)}"] = n;
      } else if ((m = brow.firstMatch(n)) != null) {
        brows["${m!.group(1)} ${m.group(2)}"] = n;
      } else if ((m = nose.firstMatch(n)) != null) {
        (noses[int.parse(m!.group(1)!)] ??= {})[int.parse(m.group(2)!)] = n;
      } else if ((m = mouth.firstMatch(n)) != null) {
        mouths[m!.group(1)!] = n;
      }
    }
    skins.sort();
  }

  /// isModular is whether it has the pieces a figure is built of.
  bool get isModular => skins.isNotEmpty && shirts.isNotEmpty && pants.isNotEmpty;

  String skinPart(int tint, String part) => "PNG/Skin/Tint $tint/tint${tint}_$part.png";

  final Map<String, ui.Image?> _read = {};

  /// image is piece [file], read once.
  Future<ui.Image?> image(String? file) async {
    if (file == null || !_files.contains(file)) return null;
    if (_read.containsKey(file)) return _read[file];
    var entry = archive.files.firstWhere((f) => f.name == file);
    try {
      var codec = await ui.instantiateImageCodec(Uint8List.fromList(entry.content as List<int>));
      return _read[file] = (await codec.getNextFrame()).image;
    } catch (_) {
      return _read[file] = null;
    }
  }

  /// first is the first choice of [options], by name.
  static String firstOf(Iterable<String> options) => (options.toList()..sort()).first;

  /// standard is a figure of the first of everything.
  ModularLook standard() => ModularLook(
        skin: skins.first,
        hairColour: hair.containsKey("Black") ? "Black" : firstOf(hair.keys),
        hair: "Man1",
        eyes: eyes.containsKey("Black large") ? "Black large" : firstOf(eyes.keys),
        brows: brows.containsKey("black 1") ? "black 1" : firstOf(brows.keys),
        nose: 1,
        mouth: mouths.containsKey("happy") ? "happy" : firstOf(mouths.keys),
        shirtColour: shirts.containsKey("Blue") ? "Blue" : firstOf(shirts.keys),
        shirt: 1,
        sleeves: "short",
        pantsColour: pants.containsKey("Blue 1") ? "Blue 1" : firstOf(pants.keys),
        pants: 1,
        legs: "long",
        shoeColour: shoes.containsKey("Brown 1") ? "Brown 1" : firstOf(shoes.keys),
        shoe: 1,
      );
}

/// ModularLook is a figure's choice of each piece.
class ModularLook {
  final int skin;
  final String hairColour, hair;
  final String eyes, brows;
  final int nose;
  final String mouth;
  final String shirtColour;
  final int shirt;

  /// sleeves and legs are how long: "long", "short", "shorter" -- or
  /// "none", the arm or the leg bare.
  final String sleeves;
  final String pantsColour;
  final int pants;
  final String legs;
  final String shoeColour;
  final int shoe;

  const ModularLook({
    required this.skin,
    required this.hairColour,
    required this.hair,
    required this.eyes,
    required this.brows,
    required this.nose,
    required this.mouth,
    required this.shirtColour,
    required this.shirt,
    required this.sleeves,
    required this.pantsColour,
    required this.pants,
    required this.legs,
    required this.shoeColour,
    required this.shoe,
  });

  ModularLook copyWith({
    int? skin,
    String? hairColour,
    String? hair,
    String? eyes,
    String? brows,
    int? nose,
    String? mouth,
    String? shirtColour,
    int? shirt,
    String? sleeves,
    String? pantsColour,
    int? pants,
    String? legs,
    String? shoeColour,
    int? shoe,
  }) =>
      ModularLook(
        skin: skin ?? this.skin,
        hairColour: hairColour ?? this.hairColour,
        hair: hair ?? this.hair,
        eyes: eyes ?? this.eyes,
        brows: brows ?? this.brows,
        nose: nose ?? this.nose,
        mouth: mouth ?? this.mouth,
        shirtColour: shirtColour ?? this.shirtColour,
        shirt: shirt ?? this.shirt,
        sleeves: sleeves ?? this.sleeves,
        pantsColour: pantsColour ?? this.pantsColour,
        pants: pants ?? this.pants,
        legs: legs ?? this.legs,
        shoeColour: shoeColour ?? this.shoeColour,
        shoe: shoe ?? this.shoe,
      );

  Map<String, dynamic> toJson() => {
        "skin": skin,
        "hairColour": hairColour,
        "hair": hair,
        "eyes": eyes,
        "brows": brows,
        "nose": nose,
        "mouth": mouth,
        "shirtColour": shirtColour,
        "shirt": shirt,
        "sleeves": sleeves,
        "pantsColour": pantsColour,
        "pants": pants,
        "legs": legs,
        "shoeColour": shoeColour,
        "shoe": shoe,
      };

  static ModularLook? fromJson(Object? json) {
    if (json is! Map) return null;
    try {
      return ModularLook(
        skin: (json["skin"] as num).toInt(),
        hairColour: json["hairColour"] as String,
        hair: json["hair"] as String,
        eyes: json["eyes"] as String,
        brows: json["brows"] as String,
        nose: (json["nose"] as num).toInt(),
        mouth: json["mouth"] as String,
        shirtColour: json["shirtColour"] as String,
        shirt: (json["shirt"] as num).toInt(),
        sleeves: json["sleeves"] as String,
        pantsColour: json["pantsColour"] as String,
        pants: (json["pants"] as num).toInt(),
        legs: json["legs"] as String,
        shoeColour: json["shoeColour"] as String,
        shoe: (json["shoe"] as num).toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// ModularPose is the puppet posed: each arm and leg turned from hanging
/// -- outwards is more, in degrees -- the body risen or sunk, and the head
/// tipped.
class ModularPose {
  final double armL, armR, legL, legR;

  /// kneeL and kneeR are how much of a leg's length shows: 1 straight, less
  /// a knee bent towards the viewer -- sitting, crouching, a foot lifted.
  /// The longer leg is what the figure stands on.
  final double kneeL, kneeR;
  final double rise;
  final double head;

  /// lean is the whole figure tipped about its feet, degrees, to the page's
  /// right.
  final double lean;
  final String? mouth;
  const ModularPose({
    this.armL = 0,
    this.armR = 0,
    this.legL = 0,
    this.legR = 0,
    this.kneeL = 1,
    this.kneeR = 1,
    this.rise = 0,
    this.head = 0,
    this.lean = 0,
    this.mouth,
  });

  /// lerp is [a] a way [t] towards [b]; the mouth the nearer one's.
  static ModularPose lerp(ModularPose a, ModularPose b, double t) {
    double l(double x, double y) => x + (y - x) * t;
    return ModularPose(
      armL: l(a.armL, b.armL),
      armR: l(a.armR, b.armR),
      legL: l(a.legL, b.legL),
      legR: l(a.legR, b.legR),
      kneeL: l(a.kneeL, b.kneeL),
      kneeR: l(a.kneeR, b.kneeR),
      rise: l(a.rise, b.rise),
      head: l(a.head, b.head),
      lean: l(a.lean, b.lean),
      mouth: t < 0.5 ? a.mouth : b.mouth,
    );
  }

  /// scaled is the pose [motion] times as far from standing still: a
  /// smaller swing, or a bigger one. An arm stops short of straight up.
  ModularPose scaled(double motion) {
    if (motion == 1) return this;
    double knee(double k) => (1 + (k - 1) * motion).clamp(0.25, 1.0);
    return ModularPose(
      armL: (armL * motion).clamp(-40.0, 175.0),
      armR: (armR * motion).clamp(-40.0, 175.0),
      legL: legL * motion,
      legR: legR * motion,
      kneeL: knee(kneeL),
      kneeR: knee(kneeR),
      rise: rise * motion,
      head: head * motion,
      lean: lean * motion,
      mouth: mouth,
    );
  }
}

/// ModularAnimation is one thing the puppet does: a cycle, played round and
/// round, or a run of key poses from first to last -- how many frames it is
/// drawn in, how fast they play, and whether over and over.
class ModularAnimation {
  final String name;
  final int count;
  final double fps;
  final bool loop;
  final ModularPose Function(double phase)? _cycle;
  final List<ModularPose> _keys;

  /// cycle is an animation that comes back round to where it started: its
  /// pose at each [phase], 0 to 2π.
  ModularAnimation.cycle(this.name, this.count, ModularPose Function(double phase) at,
      {this.fps = 8, this.loop = true})
      : _cycle = at,
        _keys = const [];

  /// keyed is one that goes from its first pose to its last, through the
  /// rest: drawn in as many frames as it has keys, or between them.
  ModularAnimation.keyed(this.name, List<ModularPose> keys, {this.fps = 8, this.loop = false})
      : count = keys.length,
        _cycle = null,
        _keys = keys;

  /// frames is its poses, drawn in [count] frames, [motion] times as big.
  List<ModularPose> framesOf({int? count, double motion = 1}) {
    var n = math.max(count ?? this.count, _cycle == null ? 2 : 1);
    if (_cycle case var at?) {
      return [for (var k = 0; k < n; k++) at(2 * math.pi * k / n).scaled(motion)];
    }
    if (n == _keys.length) return [for (var p in _keys) p.scaled(motion)];
    return [
      for (var k = 0; k < n; k++)
        () {
          var t = k * (_keys.length - 1) / (n - 1);
          var i = math.min(t.floor(), _keys.length - 2);
          return ModularPose.lerp(_keys[i], _keys[i + 1], t - i).scaled(motion);
        }(),
    ];
  }

  List<ModularPose> get frames => framesOf();
}

/// ModularTuning is how an animation is drawn and played, changed from how
/// it comes: in how many frames, how fast, and how big its motion.
class ModularTuning {
  final int? frames;
  final double? fps;
  final double motion;
  const ModularTuning({this.frames, this.fps, this.motion = 1});

  ModularTuning copyWith({int? frames, double? fps, double? motion}) =>
      ModularTuning(frames: frames ?? this.frames, fps: fps ?? this.fps, motion: motion ?? this.motion);

  Map<String, dynamic> toJson() => {
        if (frames != null) "frames": frames,
        if (fps != null) "fps": fps,
        if (motion != 1) "motion": motion,
      };

  static ModularTuning fromJson(dynamic j) => j is Map
      ? ModularTuning(
          frames: (j["frames"] as num?)?.toInt(),
          fps: (j["fps"] as num?)?.toDouble(),
          motion: (j["motion"] as num?)?.toDouble() ?? 1)
      : const ModularTuning();
}

/// _talking is the mouths a figure talks through, in turn.
const List<String> _talking = ["straight", "oh", "happy", "teethUpper", "oh", "glad"];

String _mouthAt(double phase, List<String> mouths) =>
    mouths[(phase / (2 * math.pi) * mouths.length).round() % mouths.length];

/// modularAnimations is what the builder can make.
final List<ModularAnimation> modularAnimations = [
  ModularAnimation.cycle(
      "Idle", 4, (p) => ModularPose(rise: 3 * math.sin(p), armL: 2 * math.sin(p), armR: 2 * math.sin(p)),
      fps: 4),
  ModularAnimation.cycle(
      "Walk",
      8,
      (p) => ModularPose(
          legL: 16 * math.sin(p),
          legR: -16 * math.sin(p),
          armL: -14 * math.sin(p),
          armR: 14 * math.sin(p),
          rise: 5 * math.cos(2 * p).abs())),
  ModularAnimation.cycle(
      "Run",
      8,
      (p) => ModularPose(
          legL: 32 * math.sin(p),
          legR: -32 * math.sin(p),
          armL: -30 * math.sin(p),
          armR: 30 * math.sin(p),
          rise: 12 * math.cos(2 * p).abs(),
          head: 3),
      fps: 12),
  ModularAnimation.keyed("Jump", const [
    ModularPose(rise: -14, legL: 8, legR: 8, armL: -10, armR: -10, kneeL: 0.85, kneeR: 0.85),
    ModularPose(rise: 30, legL: -6, legR: -6, armL: 70, armR: 70, mouth: "oh"),
    ModularPose(rise: 60, legL: -10, legR: -10, armL: 110, armR: 110, mouth: "oh"),
    ModularPose(rise: 30, legL: -4, legR: -4, armL: 80, armR: 80),
    ModularPose(rise: -10, legL: 8, legR: 8, armL: 0, armR: 0, kneeL: 0.85, kneeR: 0.85),
  ]),
  ModularAnimation.cycle(
      "Wave", 6, (p) => ModularPose(armR: 130 + 18 * math.sin(p), armL: 2, head: 3 * math.sin(p))),
  ModularAnimation.cycle(
      "Cheer",
      4,
      (p) => ModularPose(
          armL: 135 + 10 * math.sin(p), armR: 135 + 10 * math.sin(p), rise: 6 * math.sin(p).abs(), mouth: "oh"),
      fps: 6),
  // Talking: the mouth through its shapes, the head nodding, a hand
  // making the point.
  ModularAnimation.cycle(
      "Talk",
      6,
      (p) => ModularPose(
          mouth: _mouthAt(p, _talking), head: 3 * math.sin(p), armR: 18 + 10 * math.sin(2 * p), armL: 3),
      fps: 8),
  ModularAnimation.cycle(
      "Sit",
      4,
      (p) => ModularPose(
          kneeL: 0.3, kneeR: 0.3, legL: 8, legR: 8, armL: -20, armR: -20, rise: 2 * math.sin(p)),
      fps: 3),
  ModularAnimation.cycle(
      "Crouch",
      4,
      (p) => ModularPose(
          kneeL: 0.45, kneeR: 0.45, legL: 14, legR: 14, armL: 10, armR: 10, rise: 2 * math.sin(p), head: 2),
      fps: 4),
  // Up a ladder, seen from in front: a hand up and the other foot, then
  // the other two.
  ModularAnimation.cycle(
      "Climb",
      4,
      (p) => ModularPose(
          armL: 125 + 30 * math.sin(p),
          armR: 125 - 30 * math.sin(p),
          kneeL: 0.8 - 0.2 * math.sin(p),
          kneeR: 0.8 + 0.2 * math.sin(p),
          legL: 6,
          legR: 6),
      fps: 6),
  // Falling through the air, arms and legs flailing.
  ModularAnimation.cycle(
      "Fall",
      4,
      (p) => ModularPose(
          rise: 40,
          armL: 120 + 25 * math.sin(p),
          armR: 120 - 25 * math.sin(p),
          legL: 14 + 8 * math.sin(p),
          legR: 14 - 8 * math.sin(p),
          kneeL: 0.9,
          kneeR: 0.9,
          mouth: "oh"),
      fps: 10),
  // A swing: the fist drawn back low, then up and out.
  ModularAnimation.keyed("Punch", const [
    ModularPose(armR: -30, armL: 10, lean: -3, kneeL: 0.85, kneeR: 0.85, legL: 10, legR: 10),
    ModularPose(armR: 60, armL: -10, lean: 5, kneeL: 0.85, kneeR: 0.85, legL: 10, legR: 10, mouth: "teethUpper"),
    ModularPose(armR: 60, armL: -10, lean: 5, kneeL: 0.85, kneeR: 0.85, legL: 10, legR: 10, mouth: "teethUpper"),
    ModularPose(armR: 0, armL: 0, kneeL: 0.9, kneeR: 0.9, legL: 6, legR: 6),
  ], fps: 10),
  ModularAnimation.keyed("Kick", const [
    ModularPose(armL: 25, armR: 25, legR: 6),
    ModularPose(armL: 50, armR: 40, legR: 55, lean: -6, mouth: "teethUpper"),
    ModularPose(armL: 50, armR: 40, legR: 55, lean: -6, mouth: "teethUpper"),
    ModularPose(armL: 25, armR: 25, legR: 6),
  ], fps: 10),
  ModularAnimation.keyed("Hurt", const [
    ModularPose(lean: -6, head: -8, armL: 40, armR: 40, rise: 4, mouth: "sad"),
    ModularPose(lean: -5, head: -5, armL: 25, armR: 25, mouth: "sad"),
    ModularPose(mouth: "straight"),
  ], fps: 8),
];

// Where each piece joins the next, in its own picture's pixels: the arm at
// its shoulder end and its wrist, the leg at its hip and its ankle -- as
// drawn for the page's right; the left the same, mirrored.
const ui.Offset _shoulderIn = ui.Offset(14, 40);
const ui.Offset _wristIn = ui.Offset(156, 116);
const ui.Offset _hipIn = ui.Offset(33, 8);
const ui.Offset _ankleIn = ui.Offset(62, 156);
const ui.Offset _kneeIn = ui.Offset(48, 82);

/// modularHeight is how tall a standing figure is, in the pack's pixels,
/// hair to shoes, and modularWidth how wide, arms out.
const double modularHeight = 640;
const double modularWidth = 470;

/// paintModular draws the figure [look] in [pose] with its feet on [floor]
/// -- the middle of its bottom -- [scale] times the pack's own size, from
/// [parts]' pieces, read already: see [modularPieces].
void paintModular(ui.Canvas canvas, Map<String, ui.Image?> pieces, ModularParts parts, ModularLook look,
    ModularPose pose, ui.Offset floor, double scale) {
  ui.Image? at(String? file) => file == null ? null : pieces[file];
  canvas.save();
  canvas.translate(floor.dx, floor.dy);
  canvas.scale(scale);
  if (pose.lean != 0) canvas.rotate(pose.lean * math.pi / 180);
  // From the waist: the body's middle, the longer leg and a shoe's height
  // up -- the shorter one's foot off the floor.
  canvas.translate(0, -(164 - (_kneeIn.dy - _hipIn.dy) * (1 - math.max(pose.kneeL, pose.kneeR)) + 26) - pose.rise);
  var paint = ui.Paint()..filterQuality = ui.FilterQuality.medium;

  void piece(ui.Image? img, ui.Offset pivot, ui.Offset place, double degrees,
      {bool mirror = false, bool flip = false}) {
    if (img == null) return;
    canvas.save();
    canvas.translate(place.dx, place.dy);
    if (degrees != 0) canvas.rotate(degrees * math.pi / 180);
    if (mirror || flip) canvas.scale(mirror ? -1 : 1, flip ? -1 : 1);
    canvas.drawImage(img, -pivot, paint);
    canvas.restore();
  }

  void centred(ui.Image? img, ui.Offset centre, {double degrees = 0, bool mirror = false}) {
    if (img == null) return;
    piece(img, ui.Offset(img.width / 2, img.height / 2), centre, degrees, mirror: mirror);
  }

  // Where a point of a piece turned [degrees] about [place] -- mirrored or
  // not -- ends up.
  ui.Offset carried(ui.Offset pivot, ui.Offset point, ui.Offset place, double degrees, bool mirror,
      {bool flip = false, double length = 1}) {
    var d = point - pivot;
    d = ui.Offset(d.dx, d.dy * length);
    if (mirror) d = ui.Offset(-d.dx, d.dy);
    if (flip) d = ui.Offset(d.dx, -d.dy);
    var r = degrees * math.pi / 180;
    return place + ui.Offset(d.dx * math.cos(r) - d.dy * math.sin(r), d.dx * math.sin(r) + d.dy * math.cos(r));
  }

  var skin = look.skin;
  // Legs, the trouser legs over them, and shoes at their ends. Turned
  // outwards is a leg swung out from the hip: the right's angle as it is,
  // the left's mirrored.
  // A leg is drawn in two: the thigh from the hip, shortened as much as the
  // knee is bent towards the viewer, and the shin from the knee -- hanging
  // straighter the more it is bent, as a sitting figure's do. A shortened
  // thigh is its knee end only, not the whole of it squashed: squashed, the
  // trousers' edge at the hip smears.
  void limb(ui.Image? img, ui.Offset pivot, ui.Offset hip, double angle, double shin, double knee, bool mirror) {
    if (img == null) return;
    var w = img.width.toDouble(), h = img.height.toDouble();
    var split = math.min(_kneeIn.dy, h);
    var kneeIn = ui.Offset(pivot.dx + _kneeIn.dx - _hipIn.dx, split);
    canvas.save();
    canvas.translate(hip.dx, hip.dy);
    canvas.rotate(angle * math.pi / 180);
    // Seen end on, a bent thigh is the knee coming forward: wider.
    canvas.scale((mirror ? -1 : 1) * (1 + (1 - knee) * 0.25), 1);
    // A little past the knee, so no seam shows there.
    var top = math.min(split + 3, h);
    var from = (split - pivot.dy) * (1 - knee);
    canvas.drawImageRect(img, ui.Rect.fromLTRB(0, from, w, top),
        ui.Rect.fromLTRB(-pivot.dx, -pivot.dy, w - pivot.dx, top - from - pivot.dy), paint);
    canvas.restore();
    if (split >= h) return;
    var at = carried(pivot, kneeIn, hip, angle, mirror, length: knee);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(shin * math.pi / 180);
    if (mirror) canvas.scale(-1, 1);
    canvas.drawImageRect(img, ui.Rect.fromLTWH(0, split, w, h - split),
        ui.Rect.fromLTWH(-kneeIn.dx, 0, w, h - split), paint);
    canvas.restore();
  }

  for (var (mirror, angle, hip, knee) in [
    (true, -pose.legL, const ui.Offset(-34, 18), pose.kneeL),
    (false, pose.legR, const ui.Offset(34, 18), pose.kneeR),
  ]) {
    var shin = angle * ((knee - 0.4) / 0.6).clamp(0.0, 1.0);
    limb(at(parts.skinPart(skin, "leg")), _hipIn, hip, angle, shin, knee, mirror);
    if (look.legs != "none") {
      limb(at(parts.legs[look.pantsColour]?[look.legs]), _hipIn + const ui.Offset(6, 0), hip, angle, shin, knee, mirror);
    }
    var kneeAt = carried(_hipIn, _kneeIn, hip, angle, mirror, length: knee);
    var ankle = carried(_kneeIn, _ankleIn, kneeAt, shin, mirror);
    centred(at(parts.shoes[look.shoeColour]?[look.shoe]), ankle + ui.Offset(mirror ? -14 : 14, 8),
        degrees: shin * 0.4, mirror: mirror);
  }
  // The body: neck, shirt, the waist of the trousers.
  centred(at(parts.skinPart(skin, "neck")), const ui.Offset(0, -168));
  centred(at(parts.shirts[look.shirtColour]?[look.shirt]), const ui.Offset(0, -86));
  centred(at(parts.pants[look.pantsColour]?[look.pants]), const ui.Offset(0, 8));
  // The head, the face on it, the hair over it.
  canvas.save();
  canvas.translate(0, -180);
  if (pose.head != 0) canvas.rotate(pose.head * math.pi / 180);
  const head = ui.Offset(0, -78);
  centred(at(parts.skinPart(skin, "head")), head);
  for (var side in [-1.0, 1.0]) {
    centred(at(parts.eyes[look.eyes]), head + ui.Offset(side * 32, 8));
    centred(at(parts.brows[look.brows]), head + ui.Offset(side * 32, -20), mirror: side < 0);
  }
  centred(at(parts.noses[skin]?[look.nose]), head + const ui.Offset(0, 30));
  centred(at(parts.mouths[pose.mouth ?? look.mouth] ?? parts.mouths[look.mouth]), head + const ui.Offset(0, 54));
  var hairImg = at(parts.hair[look.hairColour]?[look.hair]);
  if (hairImg != null) {
    piece(hairImg, ui.Offset(hairImg.width / 2, 0), head + const ui.Offset(0, -98), 0);
  }
  canvas.restore();
  // Arms over the body, sleeves over the arms, hands at their ends. Out
  // from hanging is more: the right's as it is, the left's mirrored.
  for (var (mirror, angle, shoulder) in [(true, pose.armL, const ui.Offset(-60, -150)), (false, pose.armR, const ui.Offset(60, -150))]) {
    // Raised past level, the arm bows the other way -- the elbow out, as
    // an arm held up does -- not across the face: the piece turned over.
    // The left turns the other way round from the right.
    var up = angle >= 90;
    var side = mirror ? -1.0 : 1.0;
    var turn = -side * (up ? angle - 90 : angle);
    var arm = at(parts.skinPart(skin, "arm"));
    if (arm == null) continue;
    ui.Offset over(ui.Offset p, ui.Image img) => up ? ui.Offset(p.dx, _shoulderIn.dy * 2 - p.dy) : p;
    piece(arm, _shoulderIn, shoulder, turn, mirror: mirror, flip: up);
    if (look.sleeves != "none") {
      piece(at(parts.sleeves[look.shirtColour]?[look.sleeves]), _shoulderIn, shoulder, turn,
          mirror: mirror, flip: up);
    }
    var wrist = carried(_shoulderIn, over(_wristIn, arm), shoulder, turn, mirror);
    centred(at(parts.skinPart(skin, "hand")), wrist, degrees: turn, mirror: mirror);
  }
  canvas.restore();
}

/// modularPieces is every piece [look] is drawn with, read from [parts].
Future<Map<String, ui.Image?>> modularPieces(ModularParts parts, ModularLook look, {Iterable<String> mouths = const []}) async {
  var files = <String?>[
    for (var p in ["leg", "neck", "head", "arm", "hand"]) parts.skinPart(look.skin, p),
    parts.legs[look.pantsColour]?[look.legs],
    parts.shoes[look.shoeColour]?[look.shoe],
    parts.shirts[look.shirtColour]?[look.shirt],
    parts.sleeves[look.shirtColour]?[look.sleeves],
    parts.pants[look.pantsColour]?[look.pants],
    parts.eyes[look.eyes],
    parts.brows[look.brows],
    parts.noses[look.skin]?[look.nose],
    parts.mouths[look.mouth],
    for (var m in mouths) parts.mouths[m],
    parts.hair[look.hairColour]?[look.hair],
  ];
  return {
    for (var f in files)
      if (f != null) f: await parts.image(f),
  };
}

/// modularCell is how much room a frame of a built figure has, in the
/// pack's pixels: enough for a jump, and arms held up.
const ui.Size modularCell = ui.Size(560, 760);

/// modularSheet draws [look] through [animations] -- a row each, a frame
/// to a cell [cellHeight] pixels tall, each standing on its cell's floor --
/// and is the sheet, and how many cells across and down.
/// Each is drawn as [tuning] has it, by name: in so many frames, its
/// motion so big.
Future<(ui.Image, int, int)> modularSheet(
    ModularParts parts, ModularLook look, List<ModularAnimation> animations, int cellHeight,
    {Map<String, ModularTuning> tuning = const {}}) async {
  var drawn = [
    for (var a in animations)
      a.framesOf(count: tuning[a.name]?.frames, motion: tuning[a.name]?.motion ?? 1),
  ];
  var mouths = {for (var frames in drawn) for (var f in frames) if (f.mouth != null) f.mouth!};
  var pieces = await modularPieces(parts, look, mouths: mouths);
  var scale = cellHeight / modularCell.height;
  var cw = (modularCell.width * scale).ceil(), ch = cellHeight;
  var cols = drawn.map((f) => f.length).reduce(math.max);
  var rec = ui.PictureRecorder();
  var canvas = ui.Canvas(rec);
  for (var (row, frames) in drawn.indexed) {
    for (var (k, pose) in frames.indexed) {
      canvas.save();
      canvas.clipRect(ui.Rect.fromLTWH(k * cw.toDouble(), row * ch.toDouble(), cw.toDouble(), ch.toDouble()));
      paintModular(canvas, pieces, parts, look, pose, ui.Offset(k * cw + cw / 2, (row + 1) * ch - ch * 0.02), scale);
      canvas.restore();
    }
  }
  return (await rec.endRecording().toImage(cols * cw, animations.length * ch), cols, animations.length);
}
