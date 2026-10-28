import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/kenney_packs.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_client.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/stock_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_kenney_test.dart is Kenney's free sprite packs: what is found in a
// pack, a sprite made of it, a pack fetched once and kept, and the packs in
// the Stock sidebar. Nothing here goes to the network.

/// _png is a picture [w] by [h], [colour] all over, as a .png's bytes.
Future<Uint8List> _png(int w, int h, ui.Color colour) async {
  var rec = ui.PictureRecorder();
  ui.Canvas(rec).drawColor(colour, ui.BlendMode.src);
  var img = await rec.endRecording().toImage(w, h);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

Future<Archive> _pack() async {
  var a = Archive();
  void add(String name, Uint8List b) => a.addFile(ArchiveFile(name, b.length, b));
  add("Player/walk/p1_walk01.png", await _png(20, 30, const ui.Color(0xFF3366FF)));
  add("Player/walk/p1_walk02.png", await _png(24, 28, const ui.Color(0xFF3366FF)));
  add("Player/walk/p1_walk03.png", await _png(22, 30, const ui.Color(0xFF3366FF)));
  add("Items/coin.png", await _png(16, 16, const ui.Color(0xFFFFCC00)));
  add("Items/gem.png", await _png(16, 16, const ui.Color(0xFF00CC88)));
  add("Particles/flame_01.png", await _png(16, 16, const ui.Color(0xFF000000)));
  add("Particles/flame_02.png", await _png(16, 16, const ui.Color(0xFF000000)));
  add("preview.png", await _png(8, 8, const ui.Color(0xFF000000)));
  add("Spritesheet/sheet.png", await _png(8, 8, const ui.Color(0xFF000000)));
  return a;
}

class _FakeStock extends StockClient {
  int downloads = 0;
  final List<int> zip;
  _FakeStock(this.zip);

  @override
  Future<bool> download(String url, File to,
      {required int maxBytes, required bool allowFetching, required bool proxied}) async {
    if (!allowFetching || proxied) return false;
    downloads++;
    await to.writeAsBytes(zip);
    return true;
  }
}

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync("canvas_kenney");
    CanvasStorage.rootOverride = root.path;
    CanvasLibrary.resetForTest();
  });
  tearDown(() {
    CanvasStorage.rootOverride = null;
    root.deleteSync(recursive: true);
  });

  test("every pack offered is Kenney's own, on OpenGameArt", () {
    expect(kenneyPacks, isNotEmpty);
    for (var p in kenneyPacks) {
      expect(p.zip, startsWith("https://opengameart.org/sites/default/files/"), reason: p.slug);
      expect(p.zip, endsWith(".zip"), reason: p.slug);
    }
    expect({for (var p in kenneyPacks) p.slug}.length, kenneyPacks.length);
    expect({for (var p in kenneyPacks) p.kind}, containsAll(KenneyKind.values));
  });

  test("a pack's sprites: numbered runs, then each folder's set; previews and sheets passed by", () {
    var groups = spriteGroups([
      "Player/walk/p1_walk01.png", "Player/walk/p1_walk03.png", "Player/walk/p1_walk02.png",
      "Items/coin.png", "Items/gem.png", "Items/key_1.png",
      "preview.png", "Spritesheet/sheet.png", "Vector/coin.svg", "Items/readme.txt",
    ]);
    expect(groups.map((g) => (g.name, g.sequence, g.files.length)),
        [("P1 walk", true, 3), ("Items", false, 3)]);
    expect(groups.first.files, [
      "Player/walk/p1_walk01.png",
      "Player/walk/p1_walk02.png",
      "Player/walk/p1_walk03.png",
    ], reason: "in the order they play");
    expect(groups.last.files, contains("Items/key_1.png"), reason: "a run of one is a picture of a set");
  });

  test("a sprite made of a run: a sheet of even cells, played as one animation", () async {
    var a = await _pack();
    var groups = spriteGroups([for (var f in a.files) f.name]);
    var walk = groups.firstWhere((g) => g.name == "P1 walk");
    var s = (await spriteFromGroup(const SpriteElement(ElementBase(id: "s")), walk, a))!;
    expect((s.columns, s.rows, s.frameCount), (3, 1, 3));
    expect(s.cellSize, const ui.Size(24, 30), reason: "as big as the biggest frame");
    expect(s.actions.single.name, "P1 walk");
    expect(s.actions.single.frames[SpriteFacing.front], [0, 1, 2]);
    expect(s.pixelArt, isTrue, reason: "drawn small");
    expect(s.glow, isFalse);
    expect(s.assetIds, {s.sheet});
    // Drawn white on black: laid on as light.
    var flame = groups.firstWhere((g) => g.name == "Flame");
    expect((await spriteFromGroup(const SpriteElement(ElementBase(id: "f")), flame, a))!.glow, isTrue);
  });

  test("a pack is fetched once, then kept; not at all with fetching off", () async {
    var zip = ZipEncoder().encode(await _pack());
    var fake = _FakeStock(zip);
    StockClient.instance = fake;
    addTearDown(() => StockClient.instance = StockClient());
    var pack = kenneyPacks.first;
    expect(await kenneyFetch(pack, allowFetching: false, proxied: false), isNull);
    var file = await kenneyFetch(pack, allowFetching: true, proxied: false);
    expect(file, isNotNull);
    expect(await kenneyFetch(pack, allowFetching: true, proxied: false), isNotNull);
    expect(fake.downloads, 1, reason: "kept");
    var (groups, _) = await kenneyGroups(file!);
    expect(groups.map((g) => g.name), containsAll(["P1 walk", "Flame", "Items"]));
  });

  testWidgets("Kenney's sprites in the Stock sidebar, chosen and kept", (tester) async {
    SharedPreferences.setMockInitialValues({});
    proxiedForTest = false;
    addTearDown(() => proxiedForTest = null);
    var prefs = CanvasPreferences();
    prefs.allowFetching = true;
    var c = CanvasController(CanvasDocument(frames: 24));
    addTearDown(c.dispose);
    tester.view.physicalSize = const ui.Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>.value(value: prefs),
      ],
      child: MaterialApp(home: Scaffold(body: SizedBox(width: 300, child: StockPanel(controller: c)))),
    ));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    var library = tester.widget<CanvasDropdown<String>>(find.byKey(const ValueKey("stockSource")));
    expect(library.options.map((o) => o.$1), contains("kenney"));
    library.onChanged("kenney");
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("kenneyPack")), findsOneWidget);
    expect(find.byKey(const ValueKey("stockSearch")), findsNothing, reason: "no search, no key");
    var packs = tester.widget<CanvasDropdown<String>>(find.byKey(const ValueKey("kenneyPack")));
    expect(packs.options.where((o) => o.$1.isNotEmpty).length, kenneyPacks.length);
    expect(tester.takeException(), isNull);
  });
}
