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
  final double rise;
  final double head;
  final String? mouth;
  const ModularPose({
    this.armL = 0,
    this.armR = 0,
    this.legL = 0,
    this.legR = 0,
    this.rise = 0,
    this.head = 0,
    this.mouth,
  });
}

/// ModularAnimation is one thing the puppet does: its frames' poses, how
/// fast they play, and whether over and over.
class ModularAnimation {
  final String name;
  final List<ModularPose> frames;
  final double fps;
  final bool loop;
  const ModularAnimation(this.name, this.frames, {this.fps = 8, this.loop = true});
}

List<ModularPose> _cycle(int n, ModularPose Function(double phase) at) =>
    [for (var k = 0; k < n; k++) at(2 * math.pi * k / n)];

/// modularAnimations is what the builder can make: each a run of poses.
final List<ModularAnimation> modularAnimations = [
  ModularAnimation("Idle", _cycle(4, (p) => ModularPose(rise: 3 * math.sin(p), armL: 2 * math.sin(p), armR: 2 * math.sin(p))), fps: 4),
  ModularAnimation(
      "Walk",
      _cycle(8, (p) => ModularPose(
          legL: 16 * math.sin(p),
          legR: -16 * math.sin(p),
          armL: -14 * math.sin(p),
          armR: 14 * math.sin(p),
          rise: 5 * math.cos(2 * p).abs())),
      fps: 8),
  ModularAnimation(
      "Run",
      _cycle(8, (p) => ModularPose(
          legL: 32 * math.sin(p),
          legR: -32 * math.sin(p),
          armL: -30 * math.sin(p),
          armR: 30 * math.sin(p),
          rise: 12 * math.cos(2 * p).abs(),
          head: 3)),
      fps: 12),
  ModularAnimation(
      "Jump",
      const [
        ModularPose(rise: -14, legL: 8, legR: 8, armL: -10, armR: -10),
        ModularPose(rise: 30, legL: -6, legR: -6, armL: 70, armR: 70, mouth: "oh"),
        ModularPose(rise: 60, legL: -10, legR: -10, armL: 110, armR: 110, mouth: "oh"),
        ModularPose(rise: 30, legL: -4, legR: -4, armL: 80, armR: 80),
        ModularPose(rise: -10, legL: 8, legR: 8, armL: 0, armR: 0),
      ],
      fps: 8,
      loop: false),
  ModularAnimation(
      "Wave",
      _cycle(6, (p) => ModularPose(armR: 130 + 18 * math.sin(p), armL: 2, head: 3 * math.sin(p))),
      fps: 8),
  ModularAnimation(
      "Cheer",
      _cycle(4, (p) => ModularPose(armL: 135 + 10 * math.sin(p), armR: 135 + 10 * math.sin(p), rise: 6 * math.sin(p).abs(), mouth: "oh")),
      fps: 6),
];

// Where each piece joins the next, in its own picture's pixels: the arm at
// its shoulder end and its wrist, the leg at its hip and its ankle -- as
// drawn for the page's right; the left the same, mirrored.
const ui.Offset _shoulderIn = ui.Offset(14, 40);
const ui.Offset _wristIn = ui.Offset(156, 116);
const ui.Offset _hipIn = ui.Offset(33, 8);
const ui.Offset _ankleIn = ui.Offset(62, 156);

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
  // From the waist: the body's middle, a leg and a shoe's height up.
  canvas.translate(0, -(164 + 26) - pose.rise);
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
      {bool flip = false}) {
    var d = point - pivot;
    if (mirror) d = ui.Offset(-d.dx, d.dy);
    if (flip) d = ui.Offset(d.dx, -d.dy);
    var r = degrees * math.pi / 180;
    return place + ui.Offset(d.dx * math.cos(r) - d.dy * math.sin(r), d.dx * math.sin(r) + d.dy * math.cos(r));
  }

  var skin = look.skin;
  // Legs, the trouser legs over them, and shoes at their ends. Turned
  // outwards is a leg swung out from the hip: the right's angle as it is,
  // the left's mirrored.
  for (var (mirror, angle, hip) in [(true, -pose.legL, const ui.Offset(-34, 18)), (false, pose.legR, const ui.Offset(34, 18))]) {
    piece(at(parts.skinPart(skin, "leg")), _hipIn, hip, angle, mirror: mirror);
    if (look.legs != "none") {
      var legImg = at(parts.legs[look.pantsColour]?[look.legs]);
      piece(legImg, _hipIn + const ui.Offset(6, 0), hip, angle, mirror: mirror);
    }
    var ankle = carried(_hipIn, _ankleIn, hip, angle, mirror);
    centred(at(parts.shoes[look.shoeColour]?[look.shoe]), ankle + ui.Offset(mirror ? -14 : 14, 8),
        degrees: angle * 0.4, mirror: mirror);
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
const ui.Size modularCell = ui.Size(500, 760);

/// modularSheet draws [look] through [animations] -- a row each, a frame
/// to a cell [cellHeight] pixels tall, each standing on its cell's floor --
/// and is the sheet, and how many cells across and down.
Future<(ui.Image, int, int)> modularSheet(
    ModularParts parts, ModularLook look, List<ModularAnimation> animations, int cellHeight) async {
  var mouths = {for (var a in animations) for (var f in a.frames) if (f.mouth != null) f.mouth!};
  var pieces = await modularPieces(parts, look, mouths: mouths);
  var scale = cellHeight / modularCell.height;
  var cw = (modularCell.width * scale).ceil(), ch = cellHeight;
  var cols = animations.map((a) => a.frames.length).reduce(math.max);
  var rec = ui.PictureRecorder();
  var canvas = ui.Canvas(rec);
  for (var (row, a) in animations.indexed) {
    for (var (k, pose) in a.frames.indexed) {
      canvas.save();
      canvas.clipRect(ui.Rect.fromLTWH(k * cw.toDouble(), row * ch.toDouble(), cw.toDouble(), ch.toDouble()));
      paintModular(canvas, pieces, parts, look, pose, ui.Offset(k * cw + cw / 2, (row + 1) * ch - ch * 0.02), scale);
      canvas.restore();
    }
  }
  return (await rec.endRecording().toImage(cols * cw, animations.length * ch), cols, animations.length);
}
