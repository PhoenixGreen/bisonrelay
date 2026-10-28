import 'dart:io';
import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/tile_map_element.dart';
import 'package:bruig/plugin_system/canvas/render/sprite_pixels.dart';
import 'package:bruig/plugin_system/canvas/render/tile_terrain.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/kenney_tiles.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/tile_map_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/tile_painting.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_tile_terrain_test.dart is terrains on a Tile map: tiles told apart
// by what is at their corners and sides, a terrain painted finding the
// tiles that match round it -- by corners, by sides, by both -- and tiles
// tagged from their colours.

const _src = TileSource(sheet: "sheet", sheetW: 64, sheetH: 64, tileW: 16, tileH: 16);

/// _byCorners is a set of sixteen tiles, each numbered by which of its
/// corners are water -- top left 1, top right 2, bottom right 4, bottom
/// left 8 -- the rest grass.
TerrainSet _byCorners({bool onNothing = false}) {
  var g = onNothing ? -1 : 0, w = onNothing ? 0 : 1;
  return TerrainSet("Ground", terrains: [
    if (!onNothing) const Terrain("Grass", Color(0xFF00FF00)),
    Terrain("Water", const Color(0xFF0000FF)),
  ], tags: {
    for (var m = onNothing ? 1 : 0; m < 16; m++)
      m: [
        -1, -1, //
        m & 2 != 0 ? w : g, -1, m & 4 != 0 ? w : g, -1, m & 8 != 0 ? w : g, -1, m & 1 != 0 ? w : g,
      ],
  });
}

int _maskAt(Map<int, int> cells, int c, int r) => TileRef(cells[cellKey(c, r)]!).index;

void main() {
  test("kept and read back; tagged a place at a time", () {
    var set = _byCorners();
    var back = TerrainSet.fromJson(set.toJson())!;
    expect(back.toJson(), set.toJson());
    expect(back.places, tagCorners);
    expect(back.copyWith(mode: TerrainMode.both).places.length, 9);
    var one = const TerrainSet("x").tagged(3, tagTop, 1);
    expect(one.tags[3]![tagTop], 1);
    expect(one.tagged(3, tagTop, -1).tags, isEmpty, reason: "every place nothing: untagged");
    var s = _src.copyWith(terrains: [set]);
    expect(TileSource.fromJson(s.toJson())!.terrains.single.tags.length, 16);
  });

  test("by corners: water painted into grass finds its own shore", () {
    var set = _byCorners();
    var cells = paintTerrain({}, source: 0, set: set, terrain: 0, at: [
      for (var r = 0; r < 5; r++)
        for (var c = 0; c < 5; c++) (c, r)
    ]);
    expect(cells.values.toSet(), {TileRef.of(0, 0).word}, reason: "grass all over");
    cells = paintTerrain(cells, source: 0, set: set, terrain: 1, at: [(2, 2)]);
    expect([
      for (var r = 1; r <= 3; r++) [for (var c = 1; c <= 3; c++) _maskAt(cells, c, r)]
    ], [
      [4, 12, 8],
      [6, 15, 9],
      [2, 3, 1],
    ]);
    expect(_maskAt(cells, 0, 0), 0, reason: "further off, still grass");
    // Another beside it: the two make one pond.
    cells = paintTerrain(cells, source: 0, set: set, terrain: 1, at: [(3, 2)]);
    expect([for (var c = 1; c <= 4; c++) _maskAt(cells, c, 1)], [4, 12, 12, 8]);
  });

  test("by corners on nothing: a patch's edges spread into the empty cells round it", () {
    var set = _byCorners(onNothing: true);
    var cells = paintTerrain({}, source: 0, set: set, terrain: 0, at: [(5, 5)]);
    expect(cells.length, 9);
    expect(_maskAt(cells, 5, 5), 15);
    expect(_maskAt(cells, 4, 4), 4);
    expect(cells.containsKey(cellKey(3, 3)), isFalse);
    // A tile of another set is let be.
    var other = {cellKey(6, 5): TileRef.of(1, 7).word};
    var round = paintTerrain(other, source: 0, set: set, terrain: 0, at: [(5, 5)]);
    expect(round[cellKey(6, 5)], TileRef.of(1, 7).word);
  });

  test("by sides: a path joins its neighbours", () {
    // Numbered by which sides join: top 1, right 2, bottom 4, left 8.
    var set = TerrainSet("Paths", mode: TerrainMode.sides, terrains: [const Terrain("Path", Color(0xFF996633))], tags: {
      for (var m = 0; m < 16; m++)
        m: [0, m & 1 != 0 ? 0 : -1, -1, m & 2 != 0 ? 0 : -1, -1, m & 4 != 0 ? 0 : -1, -1, m & 8 != 0 ? 0 : -1, -1],
    });
    var cells = paintTerrain({}, source: 0, set: set, terrain: 0, at: [(1, 1), (2, 1), (3, 1)]);
    expect([for (var c = 1; c <= 3; c++) _maskAt(cells, c, 1)], [2, 10, 8]);
    cells = paintTerrain(cells, source: 0, set: set, terrain: 0, at: [(2, 2)]);
    expect((_maskAt(cells, 2, 1), _maskAt(cells, 2, 2)), (14, 1));
    expect(cells.length, 4, reason: "the empty cells round a path stay empty");
  });

  test("by corners and sides: a corner joins only between two sides that do", () {
    // All 256 ways a middle can join its eight neighbours, numbered by bit:
    // top, top right, right ... top left, clockwise.
    var set = TerrainSet("Walls", mode: TerrainMode.both, terrains: [const Terrain("Wall", Color(0xFF777777))], tags: {
      for (var m = 0; m < 256; m++) m: [0, for (var b = 0; b < 8; b++) m & (1 << b) != 0 ? 0 : -1],
    });
    var cells = paintTerrain({}, source: 0, set: set, terrain: 0, at: [
      for (var r = 0; r < 3; r++)
        for (var c = 0; c < 3; c++) (c, r)
    ]);
    int bits(List<int> places) => places.fold(0, (m, p) => m | 1 << (p - 1));
    expect(_maskAt(cells, 1, 1), 255);
    expect(_maskAt(cells, 0, 0), bits([tagRight, tagBottomRight, tagBottom]));
    // A middle with a gap at its top right: the corner does not join.
    cells = paintTerrain({}, source: 0, set: set, terrain: 0, at: [(1, 1), (1, 0), (2, 1)]);
    var m = _maskAt(cells, 1, 1);
    expect(m & bits([tagTop, tagRight]), bits([tagTop, tagRight]));
    expect(m & bits([tagTopRight]), 0);
  });

  test("tagged from colours: each corner the terrain its few pixels look like, or nothing", () async {
    // Tile 0 all green, tile 1 all blue, tile 2 blue with a green top left
    // corner, tile 3 clear but for a blue bottom right corner.
    var p = SpritePixels.blank(64, 16);
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        p.dab(x, y, const ui.Color(0xFF20C020));
        p.dab(x + 16, y, const ui.Color(0xFF2020D0));
        p.dab(x + 32, y, x < 5 && y < 5 ? const ui.Color(0xFF30B030) : const ui.Color(0xFF3030C0));
        if (x > 10 && y > 10) p.dab(x + 48, y, const ui.Color(0xFF2020D0));
      }
    }
    var src = const TileSource(sheet: "s", sheetW: 64, sheetH: 16, tileW: 16, tileH: 16);
    var set = TerrainSet("Ground", terrains: [
      const Terrain("Grass", Color(0xFF00FF00), sample: 0),
      const Terrain("Water", Color(0xFF0000FF), sample: 1),
    ]);
    var tagged = tagByColour(set, src, [0, 1, 2, 3], p.at);
    List<int> corners(int t) => [for (var c in [tagTopLeft, tagTopRight, tagBottomRight, tagBottomLeft]) tagged.tags[t]![c]];
    expect(corners(0), [0, 0, 0, 0]);
    expect(corners(1), [1, 1, 1, 1]);
    expect(corners(2), [0, 1, 1, 1]);
    expect(corners(3), [-1, -1, 1, -1]);
  });

  test("painted with the session: a line of a terrain, one undo", () {
    var map = TileMapElement(const ElementBase(id: "m", x: 0, y: 0, width: 320, height: 320),
        sources: [_src.copyWith(terrains: [_byCorners()])], cell: 32);
    var c = CanvasController(CanvasDocument(frames: 10).addElement(map));
    addTearDown(c.dispose);
    c.paintTiles("m");
    var s = c.tilePaint!;
    s.set(terrain: (source: 0, set: 0, terrain: 0), tool: TileTool.rect);
    s.strokeStart(const Offset(5, 5));
    s.strokeTo(const Offset(300, 300));
    s.strokeEnd();
    s.set(terrain: (source: 0, set: 0, terrain: 1), tool: TileTool.line);
    s.strokeStart(const Offset(80, 150));
    s.strokeTo(const Offset(220, 150));
    s.strokeEnd();
    var cells = (c.document.elementById("m") as TileMapElement).layers.single.cells;
    // Water in columns 2 to 6: their corners all water, the shore either side.
    expect([for (var col = 1; col <= 7; col++) _maskAt(cells, col, 4)], [6, 15, 15, 15, 15, 15, 9]);
    c.undo();
    cells = (c.document.elementById("m") as TileMapElement).layers.single.cells;
    expect(cells.length, 100, reason: "nothing spread past the grass painted, with no edge into nothing to take");
    expect(cells.values.toSet(), {TileRef.of(0, 0).word});
    // A tile picked goes back to painting tiles.
    s.set(brush: TileRef.of(0, 3));
    expect(s.terrain, isNull);
  });

  group("its settings", () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync("tile_terrain");
      CanvasStorage.rootOverride = root.path;
      CanvasLibrary.resetForTest();
    });
    tearDown(() {
      CanvasStorage.rootOverride = null;
      root.deleteSync(recursive: true);
      pickedTileLayer.clear();
      pickedTileSource.clear();
      terrainUi.clear();
    });

    testWidgets("a set added, a terrain given its tile, a place tagged on the palette, painted", (tester) async {
      SharedPreferences.setMockInitialValues({});
      var sheet = await tester.runAsync(() => SpritePixels.blank(64, 64).image());
      var map = TileMapElement(const ElementBase(id: "m", x: 0, y: 0, width: 320, height: 320), sources: const [_src]);
      var c = CanvasController(CanvasDocument(frames: 10).addElement(map));
      addTearDown(c.dispose);
      c.images.hold("sheet", sheet!);
      c.selectOnly("m");
      c.paintTiles("m");
      c.tilePaint!.set(brush: TileRef.of(0, 5));
      tester.view.physicalSize = const ui.Size(420, 4000);
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
      TerrainSet set() => (c.document.elementById("m") as TileMapElement).sources.single.terrains.single;
      Future<void> tap(String key) async {
        await tester.ensureVisible(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
      }

      await tap("tileTerrainAddSet");
      await tap("tileTerrainAdd");
      expect(set().terrains.single.sample, 5, reason: "the tile picked, its own tile");
      await tap("tileTerrainTagging");
      // Tile 1's bottom right ninth, on a palette showing tiles 28 wide.
      await tester.ensureVisible(find.byKey(const ValueKey("tilePaletteSheet")));
      await tester.pumpAndSettle();
      var at = tester.getTopLeft(find.byKey(const ValueKey("tilePaletteSheet")));
      await tester.tapAt(at + const Offset(28 + 25, 25));
      await tester.pumpAndSettle();
      expect(set().tags[1]![tagBottomRight], 0);
      await tester.tapAt(at + const Offset(28 + 14, 14));
      await tester.pumpAndSettle();
      expect(set().tags[1]![tagCentre], -1, reason: "a set told apart by corners has no middle to tag");
      await tester.tapAt(at + const Offset(28 + 25, 25));
      await tester.pumpAndSettle();
      expect(set().tags, isEmpty, reason: "clicked again: nothing");
      expect(find.byKey(const ValueKey("tileMapPaintWith")), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // The roguelike preset was checked against Kenney's own sheet by eye; the
  // rule it is made by is tagByColour, above.
  test("Kenney's roguelike sheet comes with its grass and water; another with none", () {
    var rogue = const TileSource(sheet: "r", sheetW: 968, sheetH: 526, tileW: 16, tileH: 16, spacing: 1);
    ui.Color green(int x, int y) => const ui.Color(0xFF20C020);
    var sets = kenneyTerrains("Spritesheet/roguelikeSheet_transparent.png", rogue, green);
    expect(sets.single.name, "Grass and water");
    expect(sets.single.tags.length, 17, reason: "the pond's fifteen and two of grass");
    expect(kenneyTerrains("Tilesheet/colored.png", rogue, green), isEmpty);
  });
}
