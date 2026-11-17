import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/model/elements/tile_map_element.dart';
import 'package:bruig/plugin_system/canvas/render/tile_terrain.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/kenney_packs.dart';
import 'package:path/path.dart' as path;

// kenney_tiles.dart is the tile sets in a Kenney pack for the Tile map: his
// sheets sliced as his notes say (Tiled files, or text such as "16 x 16px,
// 1px margin"), sibling sheets alike, and tile folders laid on a sheet.

/// TileSheetOffer is a tile set in a pack: a sheet and its grid, or a
/// folder of single tiles to lay out on one.
class TileSheetOffer {
  final String name;

  /// file is the sheet's place in the pack, or files the single tiles'.
  final String file;
  final List<String> files;
  final int tileW, tileH, margin, spacing;

  const TileSheetOffer(this.name,
      {this.file = "", this.files = const [], this.tileW = 0, this.tileH = 0, this.margin = 0, this.spacing = 0});

  bool get packed => files.isNotEmpty;
}

String _attr(String tag, String name) =>
    RegExp('\\b$name="([^"]*)"').firstMatch(tag)?.group(1) ?? "";

/// TilesetNotes is a tileset as Tiled notes it: its picture's place and
/// grid.
typedef TilesetNotes = ({String image, int tileW, int tileH, int margin, int spacing});

/// readTilesets is the tilesets in [text] (a .tsx, or a .tmx containing
/// them), each with a picture of its own.
List<TilesetNotes> readTilesets(String text) => [
      for (var m in RegExp(r"<tileset\b[^>]*>\s*<image\b[^>]*>").allMatches(text))
        if (_tileset(m.group(0)!) case var t?) t,
    ];

TilesetNotes? _tileset(String t) {
  var image = RegExp(r"<image\b[^>]*>").firstMatch(t)!.group(0)!;
  var w = int.tryParse(_attr(t, "tilewidth")) ?? 0, h = int.tryParse(_attr(t, "tileheight")) ?? 0;
  var source = _attr(image, "source");
  if (w <= 0 || h <= 0 || source.isEmpty) return null;
  return (
    image: source,
    tileW: w,
    tileH: h,
    margin: int.tryParse(_attr(t, "margin")) ?? 0,
    spacing: int.tryParse(_attr(t, "spacing")) ?? 0
  );
}

/// tileSheetsIn is the tile sets in [archive]: noted sheets first, then
/// folders of single tiles, each [most] tiles at most.
List<TileSheetOffer> tileSheetsIn(Archive archive, {int most = 512}) {
  var names = [for (var f in archive.files) if (f.isFile && !f.name.contains("__MACOSX")) f.name];
  var has = names.toSet();
  String text(String name) {
    var f = archive.findFile(name);
    return f == null ? "" : utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  var sheets = <String, TileSheetOffer>{};
  // A tileset in Tiled's own notes, alone or in a map.
  for (var n in names.where((n) => n.endsWith(".tsx") || n.endsWith(".tmx"))) {
    for (var t in readTilesets(text(n))) {
      var file = path.normalize(path.join(path.dirname(n), t.image)).replaceAll("\\", "/");
      if (!has.contains(file) || sheets.containsKey(file)) continue;
      sheets[file] = TileSheetOffer(_pretty(path.basenameWithoutExtension(file)),
          file: file, tileW: t.tileW, tileH: t.tileH, margin: t.margin, spacing: t.spacing);
    }
  }
  // Kenney's notes, written three ways: "16 x 16px, 1px margin" (his margin
  // is the tile gap), "Tile size 16px × 16px, Space between tiles 1px", and
  // "Tile width: 16px, Margin: 0px, Spacing: 1px"; beside or above sheets.
  bool aSheet(String p) =>
      p.toLowerCase().endsWith(".png") && !RegExp(r"preview|sample", caseSensitive: false).hasMatch(path.basename(p));
  bool inSheetFolder(String p) =>
      RegExp(r"tilemap|tilesheet|tileset|spritesheet", caseSensitive: false).hasMatch(path.basename(path.dirname(p)));
  for (var n in names.where((n) => n.toLowerCase().endsWith(".txt"))) {
    var notes = readKenneyNotes(text(n));
    if (notes == null) continue;
    var beside = names.where((p) => path.dirname(p) == path.dirname(n) && aSheet(p)).toList();
    if (beside.isEmpty) beside = names.where((p) => aSheet(p) && inSheetFolder(p)).toList();
    for (var p in beside) {
      sheets.putIfAbsent(
          p,
          () => TileSheetOffer(_pretty(path.basenameWithoutExtension(p)),
              file: p,
              tileW: notes.tileW,
              tileH: notes.tileH,
              margin: notes.margin,
              spacing: p.toLowerCase().contains("packed") ? 0 : notes.spacing));
    }
  }
  // Other sheets in a folder of sheets are sliced as the pack's others
  // are: "packed" ones have no gaps.
  if (sheets.values.firstOrNull case var known?) {
    for (var p in names) {
      var folder = path.basename(path.dirname(p)).toLowerCase();
      if (!p.toLowerCase().endsWith(".png") || sheets.containsKey(p)) continue;
      if (!(folder.contains("tilesheet") || folder.contains("tileset") || folder.contains("tilemap"))) continue;
      sheets[p] = TileSheetOffer(_pretty(path.basenameWithoutExtension(p)),
          file: p,
          tileW: known.tileW,
          tileH: known.tileH,
          spacing: p.toLowerCase().contains("packed") ? 0 : known.spacing);
    }
  }
  // Folders of tiles, a picture each; a sheet already offered is not also
  // a tile of its folder.
  var folders = <String, List<String>>{};
  for (var g in spriteGroups(names)) {
    (folders[g.folder] ??= []).addAll(g.files.where((f) => !sheets.containsKey(f)));
  }
  // A folder's name, with its parent's where two share one.
  var called = {for (var f in folders.keys) f: f == "." ? "Pictures" : path.basename(f)};
  String nameOf(String f) {
    var n = called[f]!;
    if (called.values.where((x) => x == n).length < 2 || f == ".") return n;
    var parent = path.basename(path.dirname(f));
    return parent == "." ? n : "$parent $n";
  }

  return [
    ...sheets.values.toList()..sort((a, b) => a.name.compareTo(b.name)),
    for (var e in folders.entries)
      if (e.value.length > 1)
        TileSheetOffer("${_pretty(nameOf(e.key))} (${math.min(e.value.length, most)} tiles)",
            files: ([...e.value]..sort()).take(most).toList()),
  ];
}

/// readKenneyNotes reads tile size, margin and spacing from [text],
/// Kenney's notes on a sheet; null when it gives no size.
({int tileW, int tileH, int margin, int spacing})? readKenneyNotes(String text) {
  int? n(String pattern) => int.tryParse(
      RegExp(pattern, caseSensitive: false).firstMatch(text)?.groups([1]).firstOrNull ?? "");
  var w = n(r"tile\s*width\s*:\s*(\d+)"), h = n(r"tile\s*height\s*:\s*(\d+)");
  if (w == null || h == null) {
    // The size as one across the other, on a line saying size or else the
    // first: "16 x 16px", "16px × 16px".
    var across = RegExp(r"(\d+)\s*(?:px)?\s*[x×]\s*(\d+)", caseSensitive: false);
    var line = text.split("\n").where((l) => l.toLowerCase().contains("size") || l.toLowerCase().contains("tiles are"));
    var m = line.map(across.firstMatch).whereType<RegExpMatch>().firstOrNull ?? across.firstMatch(text);
    if (m == null) return null;
    (w, h) = (int.parse(m.group(1)!), int.parse(m.group(2)!));
  }
  var spacing = n(r"spacing\s*:\s*(\d+)") ?? n(r"space between tiles\D*(\d+)");
  var margin = n(r"margin\s*:\s*(\d+)") ?? n(r"(\d+)\s*px\s*margin");
  // Where no gap is named, his "margin" is the gap between tiles.
  if (spacing == null) return (tileW: w, tileH: h, margin: 0, spacing: margin ?? 0);
  return (tileW: w, tileH: h, margin: margin ?? 0, spacing: spacing);
}

String _pretty(String s) {
  var words = s.replaceAll(RegExp(r"[_-]+"), " ").trim();
  return words.isEmpty ? "Tiles" : words[0].toUpperCase() + words.substring(1);
}

/// tileSourceFrom is [offer] as a tile set: its sheet stored, or its tiles
/// laid on one and stored; null when unreadable.
Future<TileSource?> tileSourceFrom(TileSheetOffer offer, Archive archive) async {
  if (!offer.packed) {
    var entry = archive.findFile(offer.file);
    if (entry == null) return null;
    var bytes = Uint8List.fromList(entry.content as List<int>);
    var img = await groupFrame(archive, offer.file);
    if (img == null) return null;
    var id = await CanvasAssets.save(bytes);
    if (id == null) return null;
    await CanvasLibrary.addPicture(id, offer.name, bytes);
    var made = TileSource(
        sheet: id,
        name: offer.name,
        sheetW: img.width,
        sheetH: img.height,
        tileW: offer.tileW,
        tileH: offer.tileH,
        margin: offer.margin,
        spacing: offer.spacing);
    var rgba = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) return made;
    ui.Color pixel(int x, int y) {
      if (x < 0 || y < 0 || x >= img.width || y >= img.height) return const ui.Color(0x00000000);
      var i = (y * img.width + x) * 4;
      return ui.Color.fromARGB(rgba.getUint8(i + 3), rgba.getUint8(i), rgba.getUint8(i + 1), rgba.getUint8(i + 2));
    }

    return made.copyWith(terrains: kenneyTerrains(offer.file, made, pixel));
  }
  var tiles = <ui.Image>[];
  for (var f in offer.files) {
    if (await groupFrame(archive, f) case var img?) tiles.add(img);
  }
  if (tiles.isEmpty) return null;
  var (sheet, tw, th) = await packTiles(tiles);
  var png = await sheet.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) return null;
  var bytes = png.buffer.asUint8List();
  var id = await CanvasAssets.save(bytes);
  if (id == null) return null;
  await CanvasLibrary.addPicture(id, offer.name, bytes);
  return TileSource(sheet: id, name: offer.name, sheetW: sheet.width, sheetH: sheet.height, tileW: tw, tileH: th);
}

/// packTiles lays [tiles] on a sheet, [across] to a row, each centred on
/// the bottom of a cell as big as the biggest: the sheet and cell size.
Future<(ui.Image, int, int)> packTiles(List<ui.Image> tiles, {int across = 16}) async {
  var tw = tiles.map((i) => i.width).reduce(math.max), th = tiles.map((i) => i.height).reduce(math.max);
  var cols = math.min(tiles.length, across), rows = (tiles.length / cols).ceil();
  var rec = ui.PictureRecorder();
  var canvas = ui.Canvas(rec);
  for (var (k, img) in tiles.indexed) {
    canvas.drawImage(
        img, ui.Offset((k % cols) * tw + (tw - img.width) / 2, (k ~/ cols) * th + (th - img.height).toDouble()),
        ui.Paint());
  }
  return (await rec.endRecording().toImage(cols * tw, rows * th), tw, th);
}

/// kenneyTerrains is the terrain sets [file] (as [s]) comes with, tagged
/// from colours and chosen by eye: the roguelike sheet's pond is one; its
/// dirt and stone patches are laid by hand.
List<TerrainSet> kenneyTerrains(String file, TileSource s, ui.Color Function(int x, int y) pixel) {
  var name = path.basename(file).toLowerCase();
  if (name.startsWith("roguelikesheet") && s.tileW == 16 && s.columns == 57) {
    int at(int c, int r) => r * s.columns + c;
    var set = TerrainSet("Grass and water", terrains: [
      Terrain("Grass", const ui.Color(0xFF6DBE45), sample: at(5, 0)),
      Terrain("Water", const ui.Color(0xFF3FA7D6), sample: at(0, 0)),
    ]);
    return [
      tagByColour(
          set,
          s,
          [
            for (var r = 0; r < 3; r++)
              for (var c = 0; c < 5; c++) at(c, r),
            at(5, 0),
            at(5, 1),
          ],
          pixel),
    ];
  }
  return const [];
}
