import 'dart:convert';
import 'dart:io';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_client.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_sources.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/stock_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'canvas_audio_fake.dart';

// canvas_stock_panel_test.dart is the Stock section with a pretend network:
// the two gates in front of it, the key form, no request until somebody
// searches, a filter that searches again, and a result used -- fetched,
// stored, credited and put on the canvas.

/// A single transparent pixel, as a PNG: what every "download" delivers.
final _png = base64.decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==");

class FakeStock extends StockClient {
  final List<StockQuery> asked = [];
  int downloads = 0;

  @override
  Future<StockPage> search(StockQuery q,
      {required bool allowFetching, required bool proxied}) async {
    var refused =
        StockClient.refusal(allowFetching: allowFetching, proxied: proxied);
    if (refused != null) return StockPage.failed(refused);
    asked.add(q);
    return StockPage([
      StockItem(
        source: q.source,
        id: "1",
        title: "Red fox",
        author: "Ann",
        license: "Pixabay Content License",
        page: "https://pixabay.com/fox-1/",
        thumb: "https://cdn.pixabay.com/fox.jpg",
        media: "https://pixabay.com/fox.png",
        width: 1,
        height: 1,
      ),
    ]);
  }

  @override
  Future<bool> download(String url, File to,
      {required int maxBytes,
      required bool allowFetching,
      required bool proxied}) async {
    downloads++;
    await to.writeAsBytes(_png);
    return true;
  }

  @override
  ImageProvider thumbnail(String url) => MemoryImage(_png);
}

void main() {
  late Directory root;
  late FakeStock fake;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp("canvas_stock_panel");
    CanvasStorage.rootOverride = root.path;
    CanvasLibrary.resetForTest();
    fake = FakeStock();
    StockClient.instance = fake;
    proxiedForTest = false;
  });

  tearDown(() async {
    StockClient.instance = StockClient();
    proxiedForTest = null;
    CanvasStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> idle(WidgetTester tester, [int turns = 30]) async {
    for (var i = 0; i < turns; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 4)));
      await tester.pump();
    }
  }

  Future<(CanvasController, CanvasPreferences)> show(WidgetTester tester,
      {bool fetching = true, bool key = true}) async {
    if (key) {
      SharedPreferences.setMockInitialValues(
          {"canvasApiKey:pixabay.com": "abc"});
    }
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var c = CanvasController(const CanvasDocument(),
        audioEngine: FakeEngine(const {}));
    addTearDown(c.dispose);
    var prefs = CanvasPreferences();
    await idle(tester, 5);
    prefs.allowFetching = fetching;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>.value(value: prefs),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: SizedBox(width: 300, child: StockPanel(controller: c)))),
    ));
    await idle(tester);
    return (c, prefs);
  }

  testWidgets("with fetching off it says what switching it on means",
      (tester) async {
    var (_, prefs) = await show(tester, fetching: false);
    expect(find.byKey(const ValueKey("stockOff")), findsOneWidget);
    expect(find.byKey(const ValueKey("stockSearch")), findsNothing);
    await tester.tap(find.byKey(const ValueKey("stockAllowFetching")));
    await idle(tester);
    expect(prefs.allowFetching, isTrue);
    expect(find.byKey(const ValueKey("stockSearch")), findsOneWidget);
    expect(fake.asked, isEmpty, reason: "allowing is not searching");
  });

  testWidgets("behind a proxy there is nothing to search", (tester) async {
    proxiedForTest = true;
    await show(tester);
    expect(find.byKey(const ValueKey("stockProxied")), findsOneWidget);
    expect(find.byKey(const ValueKey("stockSearch")), findsNothing);
  });

  testWidgets("without a key, a key is asked for and kept on this machine",
      (tester) async {
    await show(tester, key: false);
    expect(find.byKey(const ValueKey("stockSearch")), findsNothing);
    await tester.enterText(find.byKey(const ValueKey("stockKey")), " k-123 ");
    await tester.tap(find.byKey(const ValueKey("stockSaveKey")));
    await idle(tester);
    var saved = await SharedPreferences.getInstance();
    expect(saved.getString("canvasApiKey:pixabay.com"), "k-123");
    expect(find.byKey(const ValueKey("stockSearch")), findsOneWidget);
  });

  testWidgets("nothing is asked until a search, and a filter asks again",
      (tester) async {
    await show(tester);
    expect(fake.asked, isEmpty, reason: "opening the panel connects nowhere");

    await tester.enterText(find.byKey(const ValueKey("stockSearch")), "fox");
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await idle(tester);
    expect(fake.asked.single.text, "fox");
    expect(
        find.byKey(const ValueKey("stock-pixabayPictures-1")), findsOneWidget);
    expect(find.text("Red fox"), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey("stockFilter-image_type")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Photos").last);
    await idle(tester);
    expect(fake.asked, hasLength(2));
    expect(fake.asked.last.value("image_type"), "photo");
    expect(fake.downloads, 0, reason: "results are previews");
  });

  testWidgets("a result clicked is fetched, credited and put on the canvas",
      (tester) async {
    var (c, _) = await show(tester);
    await tester.enterText(find.byKey(const ValueKey("stockSearch")), "fox");
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await idle(tester);

    await tester.tap(find.byKey(const ValueKey("stock-pixabayPictures-1")));
    for (var i = 0; i < 6; i++) {
      await idle(tester);
    }
    expect(fake.downloads, 1);
    var image = c.document.elements.single as ImageElement;
    expect(image.name, "Red fox");
    var asset = (await tester.runAsync(() => CanvasLibrary.list()))!.single;
    expect(asset.id, image.assetId);
    expect([asset.name, asset.author, asset.from, asset.origin],
        ["Red fox", "Ann", "Pixabay", "https://pixabay.com/fox-1/"]);
  });
}
