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

// kenney_tiles.dart is the tile sets to be had from one of Kenney's packs,
// for the Tile map element: his sheets of tiles, sliced as his notes beside
// them say -- a Tiled tileset or map, or a line of text, "16 x 16px, 1px
// margin" -- and the other sheets in their folders sliced the same; and
// his folders of tiles each a picture of its own, laid out on a sheet.

/// TileSheetOffer is a tile set a pack has: a sheet of it and its grid, or
/// a folder of single tiles to be laid out on one.
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

/// TilesetNotes is a tileset as Tiled notes it: its picture's place, from
/// the notes, and its grid.
typedef TilesetNotes = ({String image, int tileW, int tileH, int margin, int spacing});

/// readTilesets is the tilesets [text] notes -- a .tsx, or a map's .tmx
/// with them in it -- each with a picture of its own.
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

/// tileSheetsIn is the tile sets in [archive]: sheets with notes first,
/// then the folders of single tiles, each [most] tiles at most.
List<TileSheetOffer> tileSheetsIn(Archive archive, {int most = 512}) {
  var names = [for (var f in archive.files) if (f.isFile && !f.name.contains("__MACOSX")) f.name];
  var has = names.toSet();
  String text(String name) {
    var f = archive.findFile(name);
    return f == null ? "" : String.fromCharCodes(f.content as List<int>);
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
  // Kenney's line of text beside a sheet: "16 x 16px, 1px margin" -- his
  // margin is the gap between tiles.
  for (var n in names.where((n) => n.toLowerCase().endsWith(".txt"))) {
    var t = text(n);
    var size = RegExp(r"(\d+)\s*x\s*(\d+)\s*px", caseSensitive: false).firstMatch(t);
    if (size == null) continue;
    var gap = RegExp(r"(\d+)\s*px\s*margin|margin:\s*(\d+)", caseSensitive: false).firstMatch(t);
    var spacing = int.tryParse(gap?.group(1) ?? gap?.group(2) ?? "") ?? 0;
    for (var p in names.where((p) => path.dirname(p) == path.dirname(n) && p.toLowerCase().endsWith(".png"))) {
      sheets.putIfAbsent(
          p,
          () => TileSheetOffer(_pretty(path.basenameWithoutExtension(p)),
              file: p, tileW: int.parse(size.group(1)!), tileH: int.parse(size.group(2)!), spacing: spacing));
    }
  }
  // The other sheets in a folder of sheets, sliced as the pack's others
  // are: "packed" ones with no gaps.
  if (sheets.values.firstOrNull case var known?) {
    for (var p in names) {
      var folder = path.basename(path.dirname(p)).toLowerCase();
      if (!p.toLowerCase().endsWith(".png") || sheets.containsKey(p)) continue;
      if (!(folder.contains("tilesheet") || folder.contains("tileset"))) continue;
      sheets[p] = TileSheetOffer(_pretty(path.basenameWithoutExtension(p)),
          file: p,
          tileW: known.tileW,
          tileH: known.tileH,
          spacing: p.toLowerCase().contains("packed") ? 0 : known.spacing);
    }
  }
  // Folders of tiles, a picture each.
  var folders = <String, List<String>>{};
  for (var g in spriteGroups(names)) {
    (folders[g.folder] ??= []).addAll(g.files);
  }
  // A folder's name, and its parent's too where two have the same one.
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

String _pretty(String s) {
  var words = s.replaceAll(RegExp(r"[_-]+"), " ").trim();
  return words.isEmpty ? "Tiles" : words[0].toUpperCase() + words.substring(1);
}

/// tileSourceFrom is [offer] of [archive] made a tile set: its sheet
/// stored, or its tiles laid out on one -- each in a cell as big as the
/// biggest, standing on its bottom -- and stored; or null when it cannot
/// be read.
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

/// packTiles lays [tiles] out on a sheet, [across] to a row, each in a
/// cell as big as the biggest, on its bottom in the middle: the sheet, and
/// the cell's size.
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

/// kenneyTerrains is the terrain sets [file] -- one of Kenney's sheets, as
/// [s] -- comes with: those of its blocks that are drawn as terrains, each
/// tagged from its colours as anyone's would be. Checked by eye: his
/// roguelike sheet's pond, grass round water, is one; its dirt and stone
/// patches are shapes to lay by hand, and are not.
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
