import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_client.dart';
import 'package:path/path.dart' as path;

// kenney_packs.dart is Kenney's free sprite packs, for the Sprite element: a
// chosen few of the hundreds he has made -- figures, animals, effects,
// items and tiles -- each fetched from where he put it on OpenGameArt the
// first time it is wanted, and kept. Every one is CC0: free for anything,
// no credit asked. A pack's pictures are found in it and grouped -- a run
// of numbered frames is an animation, the rest of a folder its frames --
// and a group is made into a sprite sheet of its own.

/// KenneyKind is what a pack is mostly of.
enum KenneyKind {
  figures("Figures"),
  effects("Effects"),
  items("Items"),
  tiles("Tiles");

  final String label;
  const KenneyKind(this.label);
}

/// KenneyPack is one of Kenney's packs: its name, what it is of, and
/// where it is.
class KenneyPack {
  final String slug;
  final String title;
  final KenneyKind kind;

  /// zip is the pack as Kenney put it on OpenGameArt, and page its page
  /// there.
  final String zip;
  String get page => "https://opengameart.org/content/$slug";

  const KenneyPack(this.slug, this.title, this.kind, this.zip);
}

const _oga = "https://opengameart.org/sites/default/files";

/// kenneyPacks is the packs offered: each checked to be Kenney's own, on
/// OpenGameArt, under CC0.
const List<KenneyPack> kenneyPacks = [
  KenneyPack("platformer-art-deluxe", "Platformer deluxe", KenneyKind.figures,
      "$_oga/platformerGraphicsDeluxe_Updated.zip"),
  KenneyPack("platformer-art-more-animations-and-enemies", "More animations and enemies",
      KenneyKind.figures, "$_oga/moreEnemiesAnimations.zip"),
  KenneyPack("platformer-pack-redux-360-assets", "Platformer redux", KenneyKind.figures,
      "$_oga/Platformer%20Pack%20Redux%20%28360%20assets%29.zip"),
  KenneyPack("simplified-platformer-pack", "Simplified platformer", KenneyKind.figures,
      "$_oga/kenney_simplifiedPlatformer.zip"),
  KenneyPack("platformer-art-pixel-redux", "Pixel platformer", KenneyKind.figures,
      "$_oga/Platformer%20Art%20Pixel%20Redux.zip"),
  KenneyPack("animal-pack-redux", "Animals", KenneyKind.figures, "$_oga/kenney_animalPackRedux.zip"),
  KenneyPack("robot-pack", "Robots", KenneyKind.figures, "$_oga/Robot%20pack.zip"),
  KenneyPack("roguelike-character-pack", "Roguelike characters", KenneyKind.figures,
      "$_oga/Roguelike%20Characters%20pack.zip"),
  KenneyPack("modular-character-pack", "Modular characters", KenneyKind.figures,
      "$_oga/Kenney_characterPack_1.zip"),
  KenneyPack("particle-pack-80-sprites", "Particles", KenneyKind.effects, "$_oga/kenney_particlePack.zip"),
  KenneyPack("emotes-pack", "Emotes", KenneyKind.effects, "$_oga/kenney_emotesPack.zip"),
  KenneyPack("generic-items", "Items", KenneyKind.items, "$_oga/kenney_genericItems_updatedCross.zip"),
  KenneyPack("game-icons", "Game icons", KenneyKind.items, "$_oga/Kenney_gameIcons.zip"),
  KenneyPack("alien-ufo-pack", "Aliens and UFOs", KenneyKind.items, "$_oga/Alien%20UFO%20pack.zip"),
  KenneyPack("racing-pack", "Racing", KenneyKind.items, "$_oga/racing-pack.zip"),
  KenneyPack("pirate-pack-190", "Pirates", KenneyKind.items, "$_oga/kenney_piratepack.zip"),
  KenneyPack("jumper-pack", "Jumper", KenneyKind.tiles, "$_oga/JumperPack_Kenney.zip"),
  KenneyPack("1-bit-pack", "1-bit", KenneyKind.tiles, "$_oga/1bitpack_kenney_1.1.zip"),
  KenneyPack("roguelikerpg-pack-1700-tiles", "Roguelike RPG", KenneyKind.tiles, "$_oga/Roguelike%20pack.zip"),
  KenneyPack("roguelike-indoor-pack", "Roguelike indoors", KenneyKind.tiles, "$_oga/Roguelike%20Indoor%20pack.zip"),
  KenneyPack("roguelike-modern-city-pack", "Roguelike city", KenneyKind.tiles,
      "$_oga/Roguelike%20Modern%20City%20pack.zip"),
  KenneyPack("tiny-town", "Tiny town", KenneyKind.tiles, "$_oga/kenney_tiny-town.zip"),
  KenneyPack("tiny-dungeon", "Tiny dungeon", KenneyKind.tiles, "$_oga/kenney_tinydungeon.zip"),
  KenneyPack("rpg-urban-pack", "RPG urban", KenneyKind.tiles, "$_oga/kenney_RPGurbanPack.zip"),
  KenneyPack("topdown-shooter", "Top-down shooter", KenneyKind.tiles, "$_oga/topdown-shooter.zip"),
  KenneyPack("tower-defense-top-down", "Tower defence", KenneyKind.tiles,
      "$_oga/Tower%20Defense%20%28top-down%29.zip"),
  KenneyPack("abstract-platformer", "Abstract platformer", KenneyKind.tiles,
      "$_oga/Abstract%20Platformer%20%28370%20assets%29.zip"),
  KenneyPack("sokoban-100-tiles", "Sokoban", KenneyKind.tiles, "$_oga/kenney_sokobanPack.zip"),
];

/// kenneyMaxBytes is the most a pack is fetched to.
const int kenneyMaxBytes = 64 << 20;

/// kenneyFile is where [pack] is kept once fetched: beside the library,
/// dotted so the library's listing passes it by.
Future<File> kenneyFile(KenneyPack pack) async =>
    File(path.join(await CanvasStorage.libraryDir(), ".stock", "kenney", "${pack.slug}.zip"));

/// kenneyFetch is [pack], fetched if it is not kept already -- or null when
/// it cannot be: fetching not allowed, through a proxy, or failed.
Future<File?> kenneyFetch(KenneyPack pack, {required bool allowFetching, required bool proxied}) async {
  var file = await kenneyFile(pack);
  if (await file.exists()) return file;
  await file.parent.create(recursive: true);
  var ok = await StockClient.instance
      .download(pack.zip, file, maxBytes: kenneyMaxBytes, allowFetching: allowFetching, proxied: proxied);
  return ok ? file : null;
}

/// SpriteGroup is pictures of a pack that make one sprite: a run of
/// numbered frames -- a walk, a flicker -- or the rest of a folder.
class SpriteGroup {
  final String name;
  final String folder;

  /// files are its pictures' places in the pack, in the order they play.
  final List<String> files;

  /// sequence is whether it is a numbered run: an animation, not a set.
  final bool sequence;
  const SpriteGroup(this.name, this.folder, this.files, this.sequence);
}

/// _skipped is what a pack's pictures are not taken from: its previews,
/// its own sheets -- the frames are taken one by one -- and its drawings.
final RegExp _skipped =
    RegExp(r"(^|/)(__MACOSX|vector|spritesheets?|sheets?|preview|sample|unity)(/|$)|preview|sample|sheet",
        caseSensitive: false);

/// spriteGroups is the sprites to be had from a pack's [names] -- the
/// files in it: numbered runs first, then folders, by name.
List<SpriteGroup> spriteGroups(Iterable<String> names) {
  var number = RegExp(r"^(.*?)[ _-]?(\d+)$");
  var runs = <String, List<(int, String)>>{};
  var loose = <String, List<String>>{};
  for (var n in names) {
    if (!n.toLowerCase().endsWith(".png") || _skipped.hasMatch(n)) continue;
    var folder = path.dirname(n);
    var base = path.basenameWithoutExtension(n);
    var m = number.firstMatch(base);
    if (m != null && m.group(1)!.isNotEmpty) {
      (runs["$folder|${m.group(1)}"] ??= []).add((int.parse(m.group(2)!), n));
    } else {
      (loose[folder] ??= []).add(n);
    }
  }
  var out = <SpriteGroup>[];
  // A run of one is not a run: it goes with the rest of its folder.
  for (var e in runs.entries) {
    var (folder, prefix) = (e.key.split("|").first, e.key.split("|").last);
    var files = [...e.value]..sort((a, b) => a.$1.compareTo(b.$1));
    if (files.length < 2) {
      (loose[folder] ??= []).add(files.single.$2);
      continue;
    }
    out.add(SpriteGroup(_pretty(prefix), folder, [for (var (_, f) in files) f], true));
  }
  out.sort((a, b) => a.name.compareTo(b.name));
  var sets = [
    for (var e in loose.entries)
      SpriteGroup(_pretty(e.key == "." ? "Pictures" : path.basename(e.key)), e.key,
          [...e.value]..sort(), false),
  ]..sort((a, b) => a.name.compareTo(b.name));
  return [...out, ...sets];
}

String _pretty(String s) {
  var words = s.replaceAll(RegExp(r"[_-]+"), " ").trim();
  return words.isEmpty ? "Sprite" : words[0].toUpperCase() + words.substring(1);
}

/// kenneyGroups reads the pack in [zip]: its groups, and the files it has.
Future<(List<SpriteGroup>, Archive)> kenneyGroups(File zip) async {
  var archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
  return (spriteGroups([for (var f in archive.files) if (f.isFile) f.name]), archive);
}

/// groupFrame is picture [file] of [archive], read.
Future<ui.Image?> groupFrame(Archive archive, String file) async {
  var entry = archive.files.where((f) => f.isFile && f.name == file).firstOrNull;
  if (entry == null) return null;
  try {
    var codec = await ui.instantiateImageCodec(Uint8List.fromList(entry.content as List<int>));
    return (await codec.getNextFrame()).image;
  } catch (_) {
    return null;
  }
}

/// spriteFromGroup is [e] made of [group] of [archive]: its pictures laid
/// out on a sheet of their own -- each in a cell as big as the biggest,
/// standing on its bottom -- stored, and played as one animation: a run in
/// order, a set one frame after another.
Future<SpriteElement?> spriteFromGroup(SpriteElement e, SpriteGroup group, Archive archive,
    {int most = 64}) async {
  var frames = <ui.Image>[];
  for (var f in group.files.take(most)) {
    if (await groupFrame(archive, f) case var img?) frames.add(img);
  }
  if (frames.isEmpty) return null;
  var cw = frames.map((i) => i.width).reduce(math.max);
  var ch = frames.map((i) => i.height).reduce(math.max);
  var cols = math.min(frames.length, math.max(1, (2048 / cw).floor()).clamp(1, 12));
  var rows = (frames.length / cols).ceil();
  var rec = ui.PictureRecorder();
  var canvas = ui.Canvas(rec);
  for (var (k, img) in frames.indexed) {
    var x = (k % cols) * cw + (cw - img.width) / 2;
    var y = (k ~/ cols) * ch + (ch - img.height).toDouble();
    canvas.drawImage(img, ui.Offset(x, y), ui.Paint());
  }
  var sheet = await rec.endRecording().toImage(cols * cw, rows * ch);
  var png = await sheet.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) return null;
  var bytes = png.buffer.asUint8List();
  var id = await CanvasAssets.save(bytes);
  if (id == null) return null;
  await CanvasLibrary.addPicture(id, group.name, bytes);
  var count = frames.length;
  return e.copyWith(
    sheet: id,
    sheetName: group.name,
    sheetW: cols * cw,
    sheetH: rows * ch,
    columns: cols,
    rows: rows,
    margin: 0,
    spacing: 0,
    rects: const [],
    actions: [
      SpriteAction(group.sequence ? group.name : "Frames",
          frames: {SpriteFacing.front: [for (var i = 0; i < count; i++) i]},
          fps: group.sequence ? 10 : 2),
    ],
    action: group.sequence ? group.name : "Frames",
    cues: const [],
    // Kenney's pixel packs are drawn small: kept square. The rest smooth.
    pixelArt: cw <= 32 && ch <= 32,
    // Drawn white on black, to be laid on as light: it glows.
    glow: await _onBlack(frames.first),
  );
}

/// _onBlack is whether [img] is drawn on black, not on nothing: its corners
/// solid and dark -- a particle, to be laid on as light.
Future<bool> _onBlack(ui.Image img) async {
  var data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return false;
  var w = img.width, h = img.height;
  for (var (x, y) in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]) {
    var i = (y * w + x) * 4;
    var a = data.getUint8(i + 3);
    var bright = data.getUint8(i) + data.getUint8(i + 1) + data.getUint8(i + 2);
    if (a < 250 || bright > 30) return false;
  }
  return true;
}
