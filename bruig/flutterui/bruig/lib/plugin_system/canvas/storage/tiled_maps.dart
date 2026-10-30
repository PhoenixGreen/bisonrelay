import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/model/elements/tile_map_element.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/kenney_tiles.dart' show packTiles;
import 'package:path/path.dart' as path;

// tiled_maps.dart is a Tile map to and from Tiled's own files -- a map as
// .tmx or .tmj, its tilesets in it or beside it as .tsx or .tsj -- the
// format Godot, and most engines, take maps in. Read: its tilesets, each
// tile's animation and its wang sets (Tiled's terrains), its tile layers,
// and the tiles stood on its object layers. Written: the same, as .tmj,
// each set's sheet a picture beside it. A tile's three flips are the
// same three bits in both; a wang set's eight places are a tag's, in the
// same order.

/// TiledRead is a map read: its tile sets, its layers, how many cells
/// across and down, and anything it had that a Tile map has not.
typedef TiledRead = ({List<TileSource> sources, List<TileLayer> layers, int width, int height, List<String> left});

/// readTiledMap reads [text], a Tiled map -- .tmx, or .tmj when [json] --
/// with [file] finding what it names beside it: tilesets and pictures, by
/// their path from it. Its pictures are stored and put in the library.
Future<TiledRead?> readTiledMap(String text, {required bool json, required Future<Uint8List?> Function(String path) file}) async {
  var map = json ? _fromJson(text) : _fromXml(text);
  if (map == null) return null;
  var left = <String>[];
  var sources = <TileSource>[];
  // Each set's first gid, and its tiles' ids to their places on its sheet.
  var firsts = <(int, int, Map<int, int>?)>[];
  for (var ts in map.tilesets) {
    var set = ts;
    if (ts.source.isNotEmpty) {
      var bytes = await file(ts.source);
      var external = bytes == null
          ? null
          : (ts.source.toLowerCase().endsWith(".tsj") || ts.source.toLowerCase().endsWith(".json")
              ? _tilesetJson(jsonDecode(utf8.decode(bytes)), ts.firstGid)
              : _tilesetXml(_parseXml(utf8.decode(bytes, allowMalformed: true)), ts.firstGid));
      if (external == null) {
        left.add("the tileset ${ts.source}, not found");
        continue;
      }
      set = external.withDir(path.dirname(ts.source));
    }
    var made = await _source(set, file);
    if (made == null) {
      left.add("the tileset ${set.name}'s picture");
      continue;
    }
    sources.add(made.$1);
    firsts.add((set.firstGid, sources.length - 1, made.$2));
  }
  firsts.sort((a, b) => a.$1.compareTo(b.$1));
  TileRef? refOf(int gid) {
    var id = gid & 0x1FFFFFFF;
    if (id == 0) return null;
    (int, int, Map<int, int>?)? owner;
    for (var f in firsts) {
      if (f.$1 <= id) owner = f;
    }
    if (owner == null) return null;
    var local = id - owner.$1;
    var index = owner.$3 == null ? local : owner.$3![local];
    if (index == null) return null;
    return TileRef.of(owner.$2, index,
        flipX: gid & 0x80000000 != 0, flipY: gid & 0x40000000 != 0, swap: gid & 0x20000000 != 0);
  }

  var layers = <TileLayer>[];
  for (var l in map.layers) {
    if (l.objects != null) {
      var objects = <TileObject>[];
      for (var o in l.objects!) {
        var t = refOf(o.gid);
        if (t == null) continue;
        // Tiled stands a tile object on its bottom left; a thing here on
        // the middle of its bottom.
        objects.add(TileObject((o.x + o.w / 2) / map.tileW, o.y / map.tileH, TileStamp.one(t)));
      }
      if (l.objects!.length > objects.length) left.add("shapes and words on ${l.name}");
      layers.add(TileLayer(name: l.name, isObjects: true, objects: objects, visible: l.visible, opacity: l.opacity));
      continue;
    }
    var cells = <int, int>{};
    for (var (i, gid) in l.data.indexed) {
      if (refOf(gid) case var t?) cells[cellKey(l.x + i % l.width, l.y + i ~/ l.width)] = t.word;
    }
    layers.add(TileLayer(
        name: l.name, cells: cells, visible: l.visible, opacity: l.opacity, tint: l.tint, solid: l.solid));
  }
  return (sources: sources, layers: layers, width: map.width, height: map.height, left: left);
}

/// _source is [ts]'s picture stored and made a tile set: one sheet as it
/// is, or a set of single pictures laid out on one -- with its tiles' ids
/// to their places on it.
Future<(TileSource, Map<int, int>?)?> _source(_Tileset ts, Future<Uint8List?> Function(String) file) async {
  if (ts.image.isNotEmpty) {
    var bytes = await file(ts.image);
    if (bytes == null) return null;
    var img = await _decode(bytes);
    if (img == null) return null;
    var id = await CanvasAssets.save(bytes);
    if (id == null) return null;
    await CanvasLibrary.addPicture(id, ts.name, bytes);
    var s = TileSource(
        sheet: id,
        name: ts.name,
        sheetW: img.width,
        sheetH: img.height,
        tileW: ts.tileW,
        tileH: ts.tileH,
        margin: ts.margin,
        spacing: ts.spacing);
    return (s.copyWith(animations: ts.animations(null), terrains: ts.terrains(null)), null);
  }
  // A set of single pictures, each its own tile.
  var ids = ts.images.keys.toList()..sort();
  var pictures = <ui.Image>[];
  var at = <int, int>{};
  for (var i in ids) {
    var bytes = await file(ts.images[i]!);
    var img = bytes == null ? null : await _decode(bytes);
    if (img == null) continue;
    at[i] = pictures.length;
    pictures.add(img);
  }
  if (pictures.isEmpty) return null;
  var (sheet, tw, th) = await packTiles(pictures);
  var png = await sheet.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) return null;
  var bytes = png.buffer.asUint8List();
  var id = await CanvasAssets.save(bytes);
  if (id == null) return null;
  await CanvasLibrary.addPicture(id, ts.name, bytes);
  var s = TileSource(sheet: id, name: ts.name, sheetW: sheet.width, sheetH: sheet.height, tileW: tw, tileH: th);
  return (s.copyWith(animations: ts.animations(at), terrains: ts.terrains(at)), at);
}

Future<ui.Image?> _decode(Uint8List bytes) async {
  try {
    return (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;
  } catch (_) {
    return null;
  }
}

/// writeTiledMap is [e] as a Tiled .tmj, with the file each of its sets'
/// sheets is to be written to beside it -- named [names] -- in its order.
/// Its cells are counted from its top left painted, or from nought.
String writeTiledMap(TileMapElement e, List<String> names) {
  var first = e.sources.isEmpty ? null : e.sources.first;
  var tw = first?.tileW ?? 16, th = first?.tileH ?? 16;
  // Where the map starts, and how big it is: every cell, every thing.
  int c0 = 0, r0 = 0, c1 = 0, r1 = 0;
  var things = <(TileLayer, List<(double, double, TileRef)>)>[];
  for (var l in e.layers) {
    for (var k in l.cells.keys) {
      c0 = math.min(c0, colOf(k));
      r0 = math.min(r0, rowOf(k));
      c1 = math.max(c1, colOf(k));
      r1 = math.max(r1, rowOf(k));
    }
    if (l.isObjects) {
      // Each tile of a thing an object of its own, by its bottom left.
      var tiles = [
        for (var o in l.objects)
          for (var (dc, dr, t) in o.stamp.cells)
            (o.x - o.stamp.width / 2 + dc, o.y - (o.stamp.height - 1 - dr), t),
      ];
      for (var (x, y, _) in tiles) {
        c0 = math.min(c0, x.floor());
        r0 = math.min(r0, y.floor() - 1);
        c1 = math.max(c1, x.ceil());
        r1 = math.max(r1, y.ceil() - 1);
      }
      things.add((l, tiles));
    }
  }
  var w = c1 - c0 + 1, h = r1 - r0 + 1;
  var firsts = <int>[];
  var next = 1;
  for (var s in e.sources) {
    firsts.add(next);
    next += s.count;
  }
  int gid(TileRef t) =>
      (firsts[t.source] + t.index) | (t.flipX ? 0x80000000 : 0) | (t.flipY ? 0x40000000 : 0) | (t.swap ? 0x20000000 : 0);
  String hex(ui.Color c, {bool alpha = false}) {
    String two(double v) => (v * 255).round().toRadixString(16).padLeft(2, "0");
    return "#${alpha ? two(c.a) : ""}${two(c.r)}${two(c.g)}${two(c.b)}";
  }

  var objectId = 1;
  var layers = <Map<String, dynamic>>[];
  for (var (i, l) in e.layers.indexed) {
    var common = {
      "id": i + 1,
      "name": l.name,
      "opacity": l.opacity,
      "visible": l.visible,
      "x": 0,
      "y": 0,
      if (l.tint != null) "tintcolor": hex(l.tint!, alpha: true),
      // Ground in a game: the property a Tiled map's loaders look for.
      if (l.solid)
        "properties": [
          {"name": "solid", "type": "bool", "value": true}
        ],
    };
    if (l.isObjects) {
      var tiles = things.firstWhere((t) => identical(t.$1, l)).$2;
      layers.add({
        ...common,
        "type": "objectgroup",
        "draworder": "topdown",
        "objects": [
          for (var (x, y, t) in tiles)
            {
              "id": objectId++,
              "gid": gid(t),
              "x": (x - c0) * tw,
              "y": (y - r0) * th,
              "width": t.source < e.sources.length ? e.sources[t.source].tileW : tw,
              "height": t.source < e.sources.length ? e.sources[t.source].tileH : th,
              "rotation": 0,
              "visible": true,
            },
        ],
      });
      continue;
    }
    var data = List.filled(w * h, 0);
    for (var en in l.cells.entries) {
      var t = TileRef(en.value);
      if (t.source >= e.sources.length) continue;
      data[(rowOf(en.key) - r0) * w + colOf(en.key) - c0] = gid(t);
    }
    layers.add({...common, "type": "tilelayer", "width": w, "height": h, "data": data});
  }
  var tilesets = [
    for (var (i, s) in e.sources.indexed)
      {
        "firstgid": firsts[i],
        "name": s.name.isEmpty ? "Tiles ${i + 1}" : s.name,
        "image": names[i],
        "imagewidth": s.sheetW,
        "imageheight": s.sheetH,
        "tilewidth": s.tileW,
        "tileheight": s.tileH,
        "margin": s.margin,
        "spacing": s.spacing,
        "columns": s.columns,
        "tilecount": s.count,
        if (s.animations.isNotEmpty)
          "tiles": [
            for (var a in s.animations.entries)
              {
                "id": a.key,
                "animation": [
                  for (var f in a.value.frames) {"tileid": f, "duration": (1000 / a.value.fps).round()}
                ],
              },
          ],
        if (s.terrains.isNotEmpty)
          "wangsets": [
            for (var set in s.terrains)
              {
                "name": set.name,
                "type": switch (set.mode) {
                  TerrainMode.corners => "corner",
                  TerrainMode.sides => "edge",
                  TerrainMode.both => "mixed",
                },
                "tile": -1,
                "colors": [
                  for (var t in set.terrains)
                    {"name": t.name, "color": hex(t.color), "tile": t.sample ?? -1, "probability": 1},
                ],
                // Tiled's colours count from one, nothing nought.
                "wangtiles": [
                  for (var tag in set.tags.entries)
                    {
                      "tileid": tag.key,
                      "wangid": [for (var p = 1; p <= 8; p++) tag.value[p] + 1],
                    },
                ],
              },
          ],
      },
  ];
  return const JsonEncoder.withIndent(" ").convert({
    "type": "map",
    "version": "1.10",
    "tiledversion": "1.10.2",
    "orientation": "orthogonal",
    "renderorder": "right-down",
    "infinite": false,
    "width": w,
    "height": h,
    "tilewidth": tw,
    "tileheight": th,
    "nextlayerid": e.layers.length + 1,
    "nextobjectid": objectId,
    "layers": layers,
    "tilesets": tilesets,
  });
}

// What a map file says, read the same from either form.

class _Map {
  final int width, height, tileW, tileH;
  final List<_Tileset> tilesets;
  final List<_Layer> layers;
  _Map(this.width, this.height, this.tileW, this.tileH, this.tilesets, this.layers);
}

class _Tileset {
  final int firstGid;
  final String source, name, image;
  final int tileW, tileH, margin, spacing;

  /// images is a set of single pictures' own, by tile id.
  final Map<int, String> images;

  /// frames is each animated tile's frames: their ids and how long each.
  final Map<int, List<(int, int)>> frames;
  final List<_Wang> wangs;
  _Tileset(this.firstGid,
      {this.source = "",
      this.name = "",
      this.image = "",
      this.tileW = 16,
      this.tileH = 16,
      this.margin = 0,
      this.spacing = 0,
      this.images = const {},
      this.frames = const {},
      this.wangs = const []});

  /// withDir is it with the pictures it names counted from [dir] -- that of
  /// the tileset's own file -- not the map's.
  _Tileset withDir(String dir) => _Tileset(firstGid,
      name: name,
      image: image.isEmpty ? "" : path.normalize(path.join(dir, image)),
      tileW: tileW,
      tileH: tileH,
      margin: margin,
      spacing: spacing,
      images: {for (var e in images.entries) e.key: path.normalize(path.join(dir, e.value))},
      frames: frames,
      wangs: wangs);

  Map<int, TileAnimation> animations(Map<int, int>? at) => {
        for (var e in frames.entries)
          if (at == null || at.containsKey(e.key))
            (at?[e.key] ?? e.key): TileAnimation([for (var (id, _) in e.value) at?[id] ?? id],
                fps: (1000 / math.max(1, e.value.map((f) => f.$2).reduce((a, b) => a + b) / e.value.length))
                    .clamp(0.25, 60.0)),
      };

  List<TerrainSet> terrains(Map<int, int>? at) => [
        for (var w in wangs)
          TerrainSet(w.name,
              mode: w.mode,
              terrains: [
                for (var (name, colour, tile) in w.colours)
                  Terrain(name, colour, sample: tile < 0 ? null : (at?[tile] ?? tile)),
              ],
              tags: {
                for (var e in w.tiles.entries)
                  if (at == null || at.containsKey(e.key))
                    (at?[e.key] ?? e.key): () {
                      var ids = [for (var v in e.value) v - 1];
                      // Tiled has no middle: a tile's sides say what it is.
                      var sides = [for (var p in tagSides) ids[p - 1]].where((v) => v >= 0).toList();
                      var middle = w.mode == TerrainMode.corners || sides.isEmpty
                          ? -1
                          : sides.reduce((a, b) => sides.where((x) => x == a).length >= sides.where((x) => x == b).length ? a : b);
                      return [middle, ...ids];
                    }(),
              }),
      ];
}

class _Wang {
  final String name;
  final TerrainMode mode;
  final List<(String, ui.Color, int)> colours;
  final Map<int, List<int>> tiles;
  _Wang(this.name, this.mode, this.colours, this.tiles);
}

class _Layer {
  final String name;
  final int width, x, y;
  final List<int> data;
  final List<({int gid, double x, double y, double w, double h})>? objects;
  final bool visible;
  final double opacity;
  final ui.Color? tint;

  /// solid is whether it has a true "solid" or "collides" property: its
  /// tiles ground in a game.
  final bool solid;
  _Layer(this.name, this.width, this.data,
      {this.x = 0, this.y = 0, this.objects, this.visible = true, this.opacity = 1, this.tint, this.solid = false});
}

/// _solidNames are the layer properties that make a Tiled layer solid: its
/// own, and the one Phaser's and others' maps use.
const _solidNames = {"solid", "collides", "collision"};

TerrainMode _mode(String? type) => switch (type) {
      "edge" => TerrainMode.sides,
      "mixed" => TerrainMode.both,
      _ => TerrainMode.corners,
    };

ui.Color _colour(String? s, ui.Color or) {
  if (s == null || !s.startsWith("#")) return or;
  var h = s.substring(1);
  var v = int.tryParse(h, radix: 16);
  if (v == null) return or;
  return ui.Color(h.length == 6 ? 0xFF000000 | v : v);
}

/// _gids is a layer's data: written out, or in base64, packed or not.
List<int> _gids(Object? data, String? encoding, String? compression) {
  if (data is List) return [for (var v in data) v is num ? v.toInt() : 0];
  if (data is! String) return const [];
  if (encoding == "csv") {
    return [for (var v in data.split(",")) int.tryParse(v.trim()) ?? 0];
  }
  if (encoding != "base64") return const [];
  List<int> bytes = base64.decode(data.replaceAll(RegExp(r"\s"), ""));
  bytes = switch (compression) {
    "zlib" => const ZLibDecoder().decodeBytes(bytes),
    "gzip" => const GZipDecoder().decodeBytes(bytes),
    _ => bytes,
  };
  var b = ByteData.sublistView(Uint8List.fromList(bytes));
  return [for (var i = 0; i + 3 < b.lengthInBytes; i += 4) b.getUint32(i, Endian.little)];
}

_Map? _fromJson(String text) {
  Object? j;
  try {
    j = jsonDecode(text);
  } catch (_) {
    return null;
  }
  if (j is! Map) return null;
  int n(Object? v, int or) => v is num ? v.toInt() : or;
  var layers = <_Layer>[];
  void read(List raw) {
    for (var l in raw.whereType<Map>()) {
      switch (l["type"]) {
        case "tilelayer":
          layers.add(_Layer(l["name"] as String? ?? "Layer", n(l["width"], 1),
              _gids(l["data"], l["encoding"] as String? ?? "csv", l["compression"] as String?),
              x: n(l["x"], 0),
              y: n(l["y"], 0),
              visible: l["visible"] != false,
              opacity: (l["opacity"] as num?)?.toDouble() ?? 1,
              tint: l["tintcolor"] == null ? null : _colour(l["tintcolor"] as String, const ui.Color(0xFFFFFFFF)),
              solid: [
                if (l["properties"] case List props)
                  for (var p in props.whereType<Map>())
                    if (_solidNames.contains(p["name"]) && (p["value"] == true || p["value"] == "true")) p,
              ].isNotEmpty));
        case "objectgroup":
          layers.add(_Layer(l["name"] as String? ?? "Objects", 0, const [],
              objects: [
                for (var o in (l["objects"] as List? ?? const []).whereType<Map>())
                  (
                    gid: n(o["gid"], 0),
                    x: (o["x"] as num? ?? 0).toDouble(),
                    y: (o["y"] as num? ?? 0).toDouble(),
                    w: (o["width"] as num? ?? 0).toDouble(),
                    h: (o["height"] as num? ?? 0).toDouble()
                  ),
              ],
              visible: l["visible"] != false,
              opacity: (l["opacity"] as num?)?.toDouble() ?? 1));
        case "group":
          read(l["layers"] as List? ?? const []);
      }
    }
  }

  read(j["layers"] as List? ?? const []);
  var tilesets = [
    for (var t in (j["tilesets"] as List? ?? const []).whereType<Map>())
      t["source"] is String ? _Tileset(n(t["firstgid"], 1), source: t["source"] as String) : _tilesetJson(t, n(t["firstgid"], 1)),
  ];
  return _Map(n(j["width"], 1), n(j["height"], 1), n(j["tilewidth"], 16), n(j["tileheight"], 16), tilesets, layers);
}

_Tileset _tilesetJson(Object? t, int firstGid) {
  if (t is! Map) return _Tileset(firstGid);
  int n(Object? v, int or) => v is num ? v.toInt() : or;
  var images = <int, String>{};
  var frames = <int, List<(int, int)>>{};
  for (var tile in (t["tiles"] as List? ?? const []).whereType<Map>()) {
    var id = n(tile["id"], 0);
    if (tile["image"] is String) images[id] = tile["image"] as String;
    if (tile["animation"] case List a) {
      frames[id] = [for (var f in a.whereType<Map>()) (n(f["tileid"], 0), n(f["duration"], 100))];
    }
  }
  return _Tileset(firstGid,
      name: t["name"] as String? ?? "",
      image: t["image"] as String? ?? "",
      tileW: n(t["tilewidth"], 16),
      tileH: n(t["tileheight"], 16),
      margin: n(t["margin"], 0),
      spacing: n(t["spacing"], 0),
      images: images,
      frames: frames,
      wangs: [
        for (var w in (t["wangsets"] as List? ?? const []).whereType<Map>())
          _Wang(
              w["name"] as String? ?? "Terrains",
              _mode(w["type"] as String?),
              [
                for (var c in (w["colors"] as List? ?? const []).whereType<Map>())
                  (c["name"] as String? ?? "Terrain", _colour(c["color"] as String?, const ui.Color(0xFF888888)), n(c["tile"], -1)),
              ],
              {
                for (var wt in (w["wangtiles"] as List? ?? const []).whereType<Map>())
                  if (wt["wangid"] case List id when id.length == 8) n(wt["tileid"], 0): [for (var v in id) n(v, 0)],
              }),
      ]);
}

_Map? _fromXml(String text) {
  var root = _parseXml(text);
  if (root == null || root.name != "map") return null;
  int n(String? v, int or) => int.tryParse(v ?? "") ?? or;
  var layers = <_Layer>[];
  void read(_X parent) {
    for (var l in parent.kids) {
      switch (l.name) {
        case "layer":
          var data = l.kid("data");
          var gids = <int>[];
          if (data != null) {
            if (data.kids.any((k) => k.name == "chunk")) continue;
            gids = data.a["encoding"] == null
                ? [for (var t in data.kids.where((k) => k.name == "tile")) n(t.a["gid"], 0)]
                : _gids(data.text, data.a["encoding"], data.a["compression"]);
          }
          layers.add(_Layer(l.a["name"] ?? "Layer", n(l.a["width"], 1), gids,
              visible: l.a["visible"] != "0",
              opacity: double.tryParse(l.a["opacity"] ?? "") ?? 1,
              tint: l.a["tintcolor"] == null ? null : _colour(l.a["tintcolor"], const ui.Color(0xFFFFFFFF)),
              solid: [
                for (var p in l.kid("properties")?.kids ?? const <_X>[])
                  if (p.name == "property" && _solidNames.contains(p.a["name"]) && p.a["value"] == "true") p,
              ].isNotEmpty));
        case "objectgroup":
          layers.add(_Layer(l.a["name"] ?? "Objects", 0, const [],
              objects: [
                for (var o in l.kids.where((k) => k.name == "object"))
                  (
                    gid: n(o.a["gid"], 0),
                    x: double.tryParse(o.a["x"] ?? "") ?? 0,
                    y: double.tryParse(o.a["y"] ?? "") ?? 0,
                    w: double.tryParse(o.a["width"] ?? "") ?? 0,
                    h: double.tryParse(o.a["height"] ?? "") ?? 0
                  ),
              ],
              visible: l.a["visible"] != "0",
              opacity: double.tryParse(l.a["opacity"] ?? "") ?? 1));
        case "group":
          read(l);
      }
    }
  }

  read(root);
  var tilesets = [
    for (var t in root.kids.where((k) => k.name == "tileset"))
      t.a["source"] != null
          ? _Tileset(n(t.a["firstgid"], 1), source: t.a["source"]!)
          : _tilesetXml(t, n(t.a["firstgid"], 1)) ?? _Tileset(n(t.a["firstgid"], 1)),
  ];
  return _Map(n(root.a["width"], 1), n(root.a["height"], 1), n(root.a["tilewidth"], 16), n(root.a["tileheight"], 16),
      tilesets, layers);
}

_Tileset? _tilesetXml(_X? t, int firstGid) {
  if (t == null || t.name != "tileset") return null;
  int n(String? v, int or) => int.tryParse(v ?? "") ?? or;
  var images = <int, String>{};
  var frames = <int, List<(int, int)>>{};
  for (var tile in t.kids.where((k) => k.name == "tile")) {
    var id = n(tile.a["id"], 0);
    if (tile.kid("image")?.a["source"] case var src?) images[id] = src;
    if (tile.kid("animation") case var a?) {
      frames[id] = [
        for (var f in a.kids.where((k) => k.name == "frame")) (n(f.a["tileid"], 0), n(f.a["duration"], 100)),
      ];
    }
  }
  return _Tileset(firstGid,
      name: t.a["name"] ?? "",
      image: t.kid("image")?.a["source"] ?? "",
      tileW: n(t.a["tilewidth"], 16),
      tileH: n(t.a["tileheight"], 16),
      margin: n(t.a["margin"], 0),
      spacing: n(t.a["spacing"], 0),
      images: images,
      frames: frames,
      wangs: [
        for (var w in t.kid("wangsets")?.kids.where((k) => k.name == "wangset") ?? const <_X>[])
          _Wang(
              w.a["name"] ?? "Terrains",
              _mode(w.a["type"]),
              [
                for (var c in w.kids.where((k) => k.name == "wangcolor"))
                  (c.a["name"] ?? "Terrain", _colour(c.a["color"], const ui.Color(0xFF888888)), n(c.a["tile"], -1)),
              ],
              {
                for (var wt in w.kids.where((k) => k.name == "wangtile"))
                  if ((wt.a["wangid"] ?? "").split(",") case var id when id.length == 8)
                    n(wt.a["tileid"], 0): [for (var v in id) n(v.trim(), 0)],
              }),
      ]);
}

/// _X is an element of a Tiled XML file: its name, its attributes, what is
/// in it, and its words.
class _X {
  final String name;
  final Map<String, String> a;
  final List<_X> kids = [];
  String text = "";
  _X(this.name, this.a);

  _X? kid(String name) => kids.where((k) => k.name == name).firstOrNull;
}

/// _parseXml is [s] read as XML -- as plain as Tiled writes it -- or null.
_X? _parseXml(String s) {
  var tag = RegExp(r"<(/?)([A-Za-z_][\w.-]*)((?:\s+[\w:.-]+\s*=\s*(?:" "\"[^\"]*\"" r"|'[^']*'))*)\s*(/?)>");
  var attr = RegExp(r"([\w:.-]+)\s*=\s*(?:" "\"([^\"]*)\"" r"|'([^']*)')");
  String unescape(String v) => v
      .replaceAll("&lt;", "<")
      .replaceAll("&gt;", ">")
      .replaceAll("&quot;", '"')
      .replaceAll("&apos;", "'")
      .replaceAll("&amp;", "&");
  // Comments and the declaration are left out before the tags are read.
  s = s.replaceAll(RegExp(r"<!--.*?-->", dotAll: true), "").replaceAll(RegExp(r"<\?.*?\?>|<!DOCTYPE[^>]*>", dotAll: true), "");
  _X? root;
  var open = <_X>[];
  var at = 0;
  for (var m in tag.allMatches(s)) {
    if (open.isNotEmpty) open.last.text += s.substring(at, m.start);
    at = m.end;
    if (m.group(1) == "/") {
      if (open.isNotEmpty) open.removeLast();
      continue;
    }
    var x = _X(m.group(2)!, {
      for (var a in attr.allMatches(m.group(3) ?? "")) a.group(1)!: unescape(a.group(2) ?? a.group(3) ?? ""),
    });
    if (open.isEmpty) {
      root ??= x;
    } else {
      open.last.kids.add(x);
    }
    if (m.group(4) != "/") open.add(x);
  }
  return root;
}
