import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/tile_map_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/sprite_pixels.dart';
import 'package:bruig/plugin_system/canvas/render/tile_map_painter.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/kenney_tiles.dart';
import 'package:bruig/plugin_system/canvas/storage/tiled_maps.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/tile_map_settings.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_tile_scene_test.dart is a Tile map made a scene: layers lagging
// the camera, going on for ever and drifting, the light over it all, and
// the map to and from Tiled's own files -- and Kenney's notes on his sheets
// read the three ways he writes them.

const _box = ElementBase(id: "m", x: 0, y: 0, width: 160, height: 64);
const _set = TileSource(sheet: "sheet", sheetW: 33, sheetH: 16, tileW: 16, tileH: 16, spacing: 1);

/// _sheet is two tiles a pixel apart: red, then green.
Future<ui.Image> _sheet() async {
  var p = SpritePixels.blank(33, 16);
  for (var y = 0; y < 16; y++) {
    for (var x = 0; x < 16; x++) {
      p.dab(x, y, const ui.Color(0xFFFF0000));
      p.dab(x + 17, y, const ui.Color(0xFF00FF00));
    }
  }
  return p.image();
}

class _Images implements CanvasImageSource {
  final Map<String, ui.Image> images;
  _Images(this.images);

  @override
  ui.Image? resolve(String id, BackgroundRemoval removal) => images[id];

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

Future<SpritePixels> _draw(TileMapElement e, ui.Image sheet, {int frame = 0, int frames = 0}) async {
  var rec = ui.PictureRecorder();
  paintTileMap(ui.Canvas(rec), e.bounds, e, frame, frameRate: 10, frames: frames, images: _Images({"sheet": sheet}));
  return (await SpritePixels.of(await rec.endRecording().toImage(160, 64)))!;
}

void main() {
  test("kept and read back: how a layer moves, and the light", () {
    var e = TileMapElement(_box,
        sources: const [_set],
        layers: const [
          TileLayer(name: "Sky", parallax: 0.25, repeat: TileRepeat.across, drift: Offset(0.5, 0)),
        ],
        light: const Color(0xFF808080),
        lightTo: const Color(0xFF000040));
    var back = TileMapElement.fromJson(e.props(), _box);
    expect(back.props(), e.props());
    expect(back.lightAt(0), const Color(0xFF808080));
    expect(back.lightAt(1), const Color(0xFF000040));
    expect(e.copyWith(noLight: true).lightAt(0.5), isNull);
  });

  test("a layer that goes on for ever fills the box; one that drifts moves by itself", () async {
    var sheet = await _sheet();
    // One red cell, then one green, going on across: red, green, red...
    var e = TileMapElement(_box, sources: const [_set], cell: 16, layers: [
      TileLayer(repeat: TileRepeat.across, cells: {cellKey(0, 0): TileRef.of(0, 0).word, cellKey(1, 0): TileRef.of(0, 1).word}),
    ]);
    var px = await _draw(e, sheet);
    expect([for (var c = 0; c < 10; c++) px.at(c * 16 + 8, 8)],
        [for (var c = 0; c < 10; c++) c.isEven ? const ui.Color(0xFFFF0000) : const ui.Color(0xFF00FF00)]);
    expect(px.at(8, 24).a, 0, reason: "across only: nothing below");
    // Drifting a tile a second to the right: a second in, the first cell green.
    var drifting = e.withLayer(0, e.layers.single.copyWith(drift: const Offset(1, 0)));
    var later = await _draw(drifting, sheet, frame: 10);
    expect(later.at(8, 8), const ui.Color(0xFF00FF00));
    expect(later.at(24, 8), const ui.Color(0xFFFF0000));
  });

  test("a far layer lags the camera; the light is laid over the map alone", () async {
    var sheet = await _sheet();
    var e = TileMapElement(_box, sources: const [_set], cell: 16, layers: [
      TileLayer(parallax: 0, cells: {cellKey(2, 0): TileRef.of(0, 0).word}),
      TileLayer(cells: {cellKey(2, 1): TileRef.of(0, 1).word}),
    ]);
    tileCameraShift = const Offset(32, 0);
    addTearDown(() => tileCameraShift = null);
    var px = await _draw(e, sheet);
    expect(px.at(32 + 32 + 8, 8), const ui.Color(0xFFFF0000), reason: "the sky moved with the camera: still on screen");
    expect(px.at(32 + 8, 24), const ui.Color(0xFF00FF00), reason: "the ground did not");
    tileCameraShift = null;
    var lit = await _draw(e.copyWith(light: const Color(0xFF808080), lightTo: const Color(0xFF000000)), sheet, frames: 11);
    expect(lit.at(32 + 8, 8).r, closeTo(0.5, 0.02), reason: "red, at half light");
    expect(lit.at(100, 50).a, 0, reason: "nothing drawn, nothing lit");
    var dark = await _draw(e.copyWith(light: const Color(0xFF808080), lightTo: const Color(0xFF000000)), sheet,
        frame: 10, frames: 11);
    expect(dark.at(32 + 8, 8).r, closeTo(0, 0.02), reason: "by the end of the scene, night");
  });

  test("Kenney's notes read the three ways he writes them", () {
    expect(readKenneyNotes("The tiles are 16 x 16px and have a 1px margin between them."),
        (tileW: 16, tileH: 16, margin: 0, spacing: 1));
    expect(readKenneyNotes("Tile size • 16px × 16px\nSpace between tiles • 1px × 1px\nTotal tiles (horizontal) • 12 tiles"),
        (tileW: 16, tileH: 16, margin: 0, spacing: 1));
    expect(readKenneyNotes("  Tile width :\t32px\n  Tile height:\t24px\n\n  Margin:\t2px\n  Spacing:\t1px"),
        (tileW: 32, tileH: 24, margin: 2, spacing: 1));
    expect(readKenneyNotes("Created by Kenney"), isNull);
    // At the top of the pack, its sheets in a folder of their own.
    var a = Archive();
    void add(String name, String text) => a.addFile(ArchiveFile(name, text.length, utf8.encode(text)));
    add("Tilesheet.txt", "Tile size • 16px × 16px\nSpace between tiles • 1px × 1px");
    add("Tilemap/tilemap.png", "x");
    add("Tilemap/tilemap_packed.png", "x");
    add("Preview.png", "x");
    var offers = {for (var o in tileSheetsIn(a)) o.name: o};
    expect(offers.keys, ["Tilemap", "Tilemap packed"]);
    expect((offers["Tilemap"]!.spacing, offers["Tilemap packed"]!.spacing), (1, 0));
  });

  group("Tiled", () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync("tiled");
      CanvasStorage.rootOverride = root.path;
      CanvasLibrary.resetForTest();
    });
    tearDown(() {
      CanvasStorage.rootOverride = null;
      root.deleteSync(recursive: true);
    });

    Future<Uint8List> png() async => (await (await _sheet()).toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();

    test("written as .tmj and read back: cells, flips, things, tiles that play, terrains", () async {
      var bytes = await png();
      var e = TileMapElement(_box, sources: [
        _set.copyWith(
          name: "Two",
          animations: {0: const TileAnimation([0, 1], fps: 5)},
          terrains: [
            const TerrainSet("Ground", terrains: [Terrain("Grass", Color(0xFF00FF00), sample: 1)], tags: {
              0: [-1, -1, 0, -1, -1, -1, -1, -1, 0],
            }),
          ],
        ),
      ], layers: [
        TileLayer(name: "Ground", cells: {
          cellKey(-1, 0): TileRef.of(0, 1).word,
          cellKey(2, 3): TileRef.of(0, 0, flipX: true, swap: true).word,
        }),
        TileLayer(name: "Things", isObjects: true, objects: [TileObject(4.5, 2, TileStamp.one(TileRef.of(0, 1, flipY: true)))]),
      ]);
      var tmj = writeTiledMap(e, ["two.png"]);
      var j = jsonDecode(tmj) as Map;
      expect((j["width"], j["height"]), (6, 4), reason: "from column -1 to 4, row 0 to 3");
      expect((j["layers"] as List).first["data"][0], 2, reason: "tile 1 of the first set: gid 2");
      var read = (await readTiledMap(tmj, json: true, file: (p) async => p == "two.png" ? bytes : null))!;
      expect(read.left, isEmpty);
      var s = read.sources.single;
      expect((s.tileW, s.spacing, s.animations[0]!.fps), (16, 1, 5));
      expect(s.animations[0]!.frames, [0, 1]);
      expect(s.terrains.single.tags[0]!.sublist(1), [-1, 0, -1, -1, -1, -1, -1, 0]);
      expect(s.terrains.single.terrains.single.sample, 1);
      var ground = read.layers.first.cells;
      expect(ground[cellKey(0, 0)], TileRef.of(0, 1).word, reason: "moved one along: the map starts at nought");
      expect(ground[cellKey(3, 3)], TileRef.of(0, 0, flipX: true, swap: true).word);
      var thing = read.layers[1].objects.single;
      expect((thing.x, thing.y, thing.stamp.first), (5.5, 2.0, TileRef.of(0, 1, flipY: true)));
    });

    test("a .tmx read: written out, packed in base64, its tileset beside it, a set of single pictures", () async {
      var bytes = await png();
      var data = Uint8List(4 * 4);
      ByteData.sublistView(data)
        ..setUint32(0, 1, Endian.little)
        ..setUint32(4, 2 | 0x80000000, Endian.little)
        ..setUint32(12, 3, Endian.little);
      var packed = base64.encode(const ZLibEncoder().encode(data));
      var tmx = '''<?xml version="1.0" encoding="UTF-8"?>
<map version="1.10" orientation="orthogonal" width="2" height="2" tilewidth="16" tileheight="16">
 <!-- Kenney's maps have notes like this -->
 <tileset firstgid="1" source="tiles/two.tsx"/>
 <tileset firstgid="3" name="Props" tilewidth="16" tileheight="16" tilecount="1">
  <tile id="0"><image width="33" height="16" source="props/one.png"/></tile>
 </tileset>
 <layer id="1" name="Csv" width="2" height="2"><data encoding="csv">
0,1,
2,0
</data></layer>
 <layer id="2" name="Packed" width="2" height="2" opacity="0.5"><data encoding="base64" compression="zlib">
   $packed
  </data></layer>
 <objectgroup id="3" name="Things"><object id="1" gid="2" x="16" y="32" width="16" height="16"/><object id="2" x="0" y="0" width="5" height="5"/></objectgroup>
</map>''';
      var tsx = '<tileset name="Two" tilewidth="16" tileheight="16" spacing="1"><image source="two.png" width="33" height="16"/></tileset>';
      var read = (await readTiledMap(tmx, json: false, file: (p) async => switch (p) {
                "tiles/two.tsx" => Uint8List.fromList(utf8.encode(tsx)),
                "tiles/two.png" || "props/one.png" => bytes,
                _ => null,
              }))!;
      expect(read.sources.length, 2);
      expect(read.layers.map((l) => l.name), ["Csv", "Packed", "Things"]);
      expect(read.layers[0].cells, {cellKey(1, 0): TileRef.of(0, 0).word, cellKey(0, 1): TileRef.of(0, 1).word});
      expect(read.layers[1].cells, {
        cellKey(0, 0): TileRef.of(0, 0).word,
        cellKey(1, 0): TileRef.of(0, 1, flipX: true).word,
        cellKey(1, 1): TileRef.of(1, 0).word,
      });
      expect(read.layers[1].opacity, 0.5);
      expect(read.layers[2].objects.single.x, 1.5);
      expect(read.left, ["shapes and words on Things"]);
    });

    test("opened in place of a map: its sets and layers, its box the map's size, one undo", () {
      var c = CanvasController(CanvasDocument(frames: 10).addElement(TileMapElement(_box, sources: const [_set])));
      addTearDown(c.dispose);
      openTiledMap(c, "m", (
        sources: const [_set],
        layers: [TileLayer(name: "Read", cells: {cellKey(0, 0): 1})],
        width: 10,
        height: 5,
        left: const [],
      ));
      var m = c.document.elementById("m") as TileMapElement;
      expect(m.layers.single.name, "Read");
      expect((m.width, m.height, m.cell), (320, 160, 32), reason: "16-pixel tiles drawn twice their size");
      c.undo();
      expect((c.document.elementById("m") as TileMapElement).layers.single.name, "Ground");
    });
  });
}
