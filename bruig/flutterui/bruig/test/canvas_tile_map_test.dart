import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
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
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/tile_map_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/tile_painting.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_tile_map_test.dart is the Tile map element: tiles as Tiled and
// Godot turn them, its cells and layers kept, painted on with each tool --
// one undo a stroke -- drawn where they belong, and the tile sets found in
// a pack.

const _box = ElementBase(id: "m", x: 100, y: 50, width: 320, height: 160);
const _set = TileSource(sheet: "sheet", name: "Two", sheetW: 33, sheetH: 16, tileW: 16, tileH: 16, spacing: 1);

TileMapElement _map({List<TileLayer>? layers}) =>
    TileMapElement(_box, sources: const [_set], layers: layers ?? const [TileLayer(name: "Ground")], cell: 32);

/// _sheet is two 16-pixel tiles a pixel apart: the first red with a blue
/// pixel at its top left, the second green.
Future<ui.Image> _sheet() async {
  var p = SpritePixels.blank(33, 16);
  for (var y = 0; y < 16; y++) {
    for (var x = 0; x < 16; x++) {
      p.dab(x, y, const ui.Color(0xFFFF0000));
      p.dab(x + 17, y, const ui.Color(0xFF00FF00));
    }
  }
  p.dab(0, 0, const ui.Color(0xFF0000FF));
  return p.image();
}

void main() {
  group("tiles, cells and layers", () {
    test("a tile turned and flipped its eight ways, as Tiled's bits", () {
      var t = TileRef.of(3, 1234);
      expect((t.source, t.index, t.turned), (3, 1234, false));
      var seen = <int>{};
      var r = t;
      for (var k = 0; k < 4; k++) {
        seen.add(r.word);
        seen.add(r.flippedX().word);
        r = r.turnedRight();
      }
      expect(r, t, reason: "four quarter turns is round again");
      expect(seen.length, 8);
      expect(t.turnedRight().matrix, (0, -1, 1, 0), reason: "(x, y) to (-y, x)");
      expect(t.flippedX().flippedX(), t);
      expect(t.flippedX().plain, t);
      expect({for (var w in seen) TileRef(w).index}, {1234});
    });

    test("cells either side of nought, and a set's tiles found on its sheet", () {
      for (var (c, r) in [(0, 0), (-5, 7), (300, -32768), (32767, 2)]) {
        var k = cellKey(c, r);
        expect((colOf(k), rowOf(k)), (c, r));
      }
      expect((_set.columns, _set.rows, _set.count), (2, 1, 2));
      expect(_set.tileRect(1), const Rect.fromLTWH(17, 0, 16, 16));
      expect(_set.tileAt(const Offset(20, 5)), 1);
      expect(_set.tileAt(const Offset(16.5, 5)), isNull, reason: "the gap between");
    });

    test("kept and read back; a set taken out takes its tiles", () {
      var two = _set.copyWith(sheet: "other", name: "Other");
      var e = TileMapElement(_box,
          sources: [_set, two],
          layers: [
            TileLayer(name: "Ground", cells: {
              cellKey(0, 0): TileRef.of(0, 1).word,
              cellKey(-2, 3): TileRef.of(1, 0, flipX: true, swap: true).word,
            }),
            const TileLayer(name: "Top", visible: false, locked: true, opacity: 0.5, tint: Color(0xFF336699)),
          ],
          cell: 24,
          pixelArt: false);
      var back = CanvasDocument.fromJson(CanvasDocument(frames: 10).addElement(e).toJson()).elementById("m")
          as TileMapElement;
      expect(back.props(), e.props());
      expect(back.assetIds, {"sheet", "other"});
      var cut = e.withoutSource(0);
      expect(cut.sources.single.name, "Other");
      expect(cut.layers.first.cells, {cellKey(-2, 3): TileRef.of(0, 0, flipX: true, swap: true).word},
          reason: "the second set's tiles, its number one less");
      expect(newElement(ElementKind.tileMap, CanvasDocument(frames: 10)), isA<TileMapElement>());
    });

    test("a line touches each cell after the last; a fill stops at the window", () {
      expect(cellsAlong((0, 0), (3, 1)), [(0, 0), (1, 0), (2, 1), (3, 1)]);
      expect(cellsAlong((2, 2), (2, 2)), [(2, 2)]);
      var cells = {for (var c = 0; c < 5; c++) cellKey(c, 1): 7};
      expect(floodCells(cells, (0, 0), (0, 0, 4, 2)).length, 5, reason: "the empty row above, not the one below");
      expect(floodCells(cells, (2, 1), (0, 0, 4, 2)).length, 5);
      expect(floodCells(cells, (9, 9), (0, 0, 4, 2)), isEmpty);
    });
  });

  group("painted", () {
    (CanvasController, TilePaintSession) start({TileMapElement? map}) {
      var c = CanvasController(CanvasDocument(frames: 10).addElement(map ?? _map()));
      c.paintTiles("m");
      return (c, c.tilePaint!);
    }

    TileMapElement get(CanvasController c) => c.document.elementById("m") as TileMapElement;
    Offset at(int col, int row) => Offset(100 + col * 32 + 16, 50 + row * 32 + 16);

    test("each stroke one change, undone in one", () {
      var (c, s) = start();
      addTearDown(c.dispose);
      s.set(brush: TileRef.of(0, 1));
      s.strokeStart(at(0, 0));
      s.strokeTo(at(3, 0));
      expect(get(c).tileCount, 0, reason: "the map's own, until the pen lifts");
      expect(s.view(get(c)).working!.tileCount, 4);
      s.strokeEnd();
      expect(get(c).layers.first.cells.keys.map((k) => (colOf(k), rowOf(k))), [(0, 0), (1, 0), (2, 0), (3, 0)]);
      s.set(tool: TileTool.erase);
      s.strokeStart(at(1, 0));
      s.strokeEnd();
      expect(get(c).tileCount, 3);
      c.undo();
      expect(get(c).tileCount, 4);
      c.undo();
      expect(get(c).tileCount, 0);
    });

    test("a line and a box drawn again as the pen moves; a fill in the window", () {
      var (c, s) = start();
      addTearDown(c.dispose);
      s.set(tool: TileTool.rect);
      s.strokeStart(at(1, 1));
      s.strokeTo(at(5, 4));
      s.strokeTo(at(2, 2));
      s.strokeEnd();
      expect(get(c).tileCount, 4, reason: "only the box it ended as");
      s.set(tool: TileTool.line, brush: TileRef.of(0, 1));
      s.strokeStart(at(0, 0));
      s.strokeTo(at(9, 4));
      s.strokeTo(at(0, 4));
      s.strokeEnd();
      expect(get(c).layers.first.at(0, 2), TileRef.of(0, 1));
      expect(get(c).layers.first.at(9, 4), isNull);
      // A window of 10 by 5 cells: the rest, poured in.
      s.set(tool: TileTool.fill, brush: TileRef.of(0, 0));
      s.strokeStart(at(9, 0));
      s.strokeEnd();
      var cells = get(c).layers.first.cells;
      expect(cells.length, 50);
      expect(get(c).layers.first.at(0, 2), TileRef.of(0, 1), reason: "a different tile is a wall");
    });

    test("a tile picked up off the top layer showing; a locked layer is let be", () {
      var (c, s) = start(
          map: _map(layers: [
        TileLayer(name: "Ground", cells: {cellKey(2, 1): TileRef.of(0, 0).word}),
        TileLayer(name: "Top", cells: {cellKey(2, 1): TileRef.of(0, 1, flipY: true).word}, locked: true),
      ]));
      addTearDown(c.dispose);
      s.set(tool: TileTool.picker);
      s.strokeStart(at(2, 1));
      expect((s.brush, s.tool), (TileRef.of(0, 1, flipY: true), TileTool.paint));
      pickedTileLayer["m"] = 1;
      addTearDown(() => pickedTileLayer.remove("m"));
      s.strokeStart(at(5, 1));
      s.strokeEnd();
      expect(get(c).tileCount, 2, reason: "nothing laid on a locked layer");
      expect(c.canUndo, isFalse);
    });

    test("the tile to be laid shown under the pointer", () {
      var (c, s) = start();
      addTearDown(c.dispose);
      s.hoverAt(at(4, 2));
      expect(s.hover, (4, 2));
      expect(s.view(get(c)).ghost.single, (4, 2, s.brush));
      s.hoverAt(const Offset(0, 0));
      expect(s.hover, isNull);
    });
  });

  test("drawn in its cells, turned tiles turned, a hidden layer not", () async {
    var sheet = await _sheet();
    var e = _map(layers: [
      TileLayer(name: "A", cells: {
        cellKey(0, 0): TileRef.of(0, 0).word,
        cellKey(1, 0): TileRef.of(0, 0, flipX: true).word,
        cellKey(2, 0): TileRef.of(0, 0).turnedRight().word,
        cellKey(3, 1): TileRef.of(0, 1).word,
      }),
      TileLayer(name: "B", visible: false, cells: {cellKey(5, 0): TileRef.of(0, 1).word}),
    ]);
    var images = _Images({"sheet": sheet});
    var rec = ui.PictureRecorder();
    paintTileMap(ui.Canvas(rec), e.bounds, e, 0, images: images);
    var px = (await SpritePixels.of(await rec.endRecording().toImage(500, 300)))!;
    ui.Color at(double x, double y) => px.at((100 + x).round(), (50 + y).round());
    expect(at(1, 1), const ui.Color(0xFF0000FF), reason: "the blue corner, top left");
    expect(at(16, 16), const ui.Color(0xFFFF0000));
    expect(at(32 + 30, 1), const ui.Color(0xFF0000FF), reason: "flipped across: top right");
    expect(at(64 + 30, 1), const ui.Color(0xFF0000FF), reason: "turned right: top right");
    expect(at(96 + 16, 32 + 16), const ui.Color(0xFF00FF00));
    expect(at(160 + 16, 16).a, 0, reason: "a hidden layer is not drawn");
    expect(at(330, 16).a, 0, reason: "nothing outside its box");
  });

  test("a pack's tile sets: from Tiled's notes, Kenney's line of text, and folders", () async {
    var a = Archive();
    void add(String name, List<int> bytes) => a.addFile(ArchiveFile(name, bytes.length, bytes));
    var png = (await (await _sheet()).toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    add("Tilemap/set.tsx",
        '<tileset name="s" tilewidth="16" tileheight="16" spacing="1"><image source="../Sheets/a.png"/></tileset>'
            .codeUnits);
    add("Sheets/a.png", png);
    add("Sheets/a_packed.png", png);
    add("Other/info.txt", "The tiles are 8 x 8px and have a 2px margin between them.".codeUnits);
    add("Other/b.png", png);
    for (var i = 1; i <= 3; i++) {
      add("PNG/Tiles/grass$i.png", png);
    }
    var offers = tileSheetsIn(a);
    var byName = {for (var o in offers) o.name: o};
    expect((byName["A"]!.tileW, byName["A"]!.spacing), (16, 1));
    expect((byName["B"]!.tileW, byName["B"]!.spacing), (8, 2));
    expect(byName.keys.where((n) => n.startsWith("Tiles")), ["Tiles (3 tiles)"]);
    expect(byName["Tiles (3 tiles)"]!.files.length, 3);
    var (packed, tw, th) = await packTiles([await _sheet(), await _sheet(), await _sheet()], across: 2);
    expect((packed.width, packed.height, tw, th), (66, 32, 33, 16));
  });

  group("its settings", () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync("tile_map");
      CanvasStorage.rootOverride = root.path;
      CanvasLibrary.resetForTest();
    });
    tearDown(() {
      CanvasStorage.rootOverride = null;
      root.deleteSync(recursive: true);
      pickedTileLayer.clear();
      pickedTileSource.clear();
    });

    testWidgets("a tile picked from the palette paints; layers added and moved", (tester) async {
      SharedPreferences.setMockInitialValues({});
      var sheet = await tester.runAsync(_sheet);
      var c = CanvasController(CanvasDocument(frames: 10).addElement(_map()));
      addTearDown(c.dispose);
      c.images.hold("sheet", sheet!);
      c.selectOnly("m");
      tester.view.physicalSize = const ui.Size(420, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(home: Scaffold(body: SizedBox(width: 420, child: CanvasDesignPanel(controller: c)))),
      ));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 30)));
      await tester.pumpAndSettle();
      TileMapElement get() => c.document.elementById("m") as TileMapElement;
      // The second tile: 28 shown wide, the first at 0 and a gap.
      var sheetBox = tester.getTopLeft(find.byKey(const ValueKey("tilePaletteSheet")));
      await tester.tapAt(sheetBox + const Offset(28 * 17 / 16 + 6, 6));
      await tester.pumpAndSettle();
      expect(c.tilePaint?.brush, TileRef.of(0, 1), reason: "picked, and painting on");
      expect(find.byKey(const ValueKey("tileMapTools")), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey("tileMapTurn")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("tileMapTurn")));
      await tester.pump();
      expect(c.tilePaint!.brush, TileRef.of(0, 1).turnedRight());
      c.tilePaint!.strokeStart(const Offset(120, 60));
      c.tilePaint!.strokeEnd();
      expect(get().layers.single.at(0, 0), TileRef.of(0, 1).turnedRight());
      // A layer added above, then moved down under the ground.
      await tester.ensureVisible(find.byKey(const ValueKey("tileLayerAdd")));
      await tester.tap(find.byKey(const ValueKey("tileLayerAdd")));
      await tester.pumpAndSettle();
      expect(get().layers.map((l) => l.name), ["Ground", "Layer 2"]);
      await tester.tap(find.byKey(const ValueKey("tileLayerDown")));
      await tester.pumpAndSettle();
      expect(get().layers.map((l) => l.name), ["Layer 2", "Ground"]);
      expect(c.tilePaint!.layer, 0, reason: "the moved layer still the one painted");
      await tester.tap(find.byKey(const ValueKey("tileLayerShown-1")));
      await tester.pumpAndSettle();
      expect(get().layers[1].visible, isFalse);
      await tester.tap(find.byKey(const ValueKey("tileMapPaintOn")));
      await tester.pumpAndSettle();
      expect(c.tilePaint, isNull);
      expect(tester.takeException(), isNull);
    });
  });
}

class _Images implements CanvasImageSource {
  final Map<String, ui.Image> images;
  _Images(this.images);

  @override
  ui.Image? resolve(String id, BackgroundRemoval removal) => images[id];

  @override
  dynamic noSuchMethod(Invocation i) => null;
}
