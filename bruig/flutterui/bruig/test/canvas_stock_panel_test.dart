import 'dart:async';
import 'dart:convert';
import 'support/canvas_app.dart';
import 'dart:io';

import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_client.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_library.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_sources.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/character_browser.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/stock_import.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/stock_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/canvas_audio_fake.dart';
import 'canvas_video_element_test.dart' show FakeFrames;

// canvas_stock_panel_test.dart is the Stock section with a pretend network:
// the two gates in front of it, the key form, no request until somebody
// searches, a filter that searches again, and a result used -- fetched,
// stored, credited and put on the canvas.

/// A single transparent pixel, as a PNG: what a "download" delivers unless a
/// test sets FakeStock.delivers.
final _png = base64.decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==");

class FakeStock extends StockClient {
  final List<StockQuery> asked = [];
  int downloads = 0;

  /// pages, when set, are the pictures' pages in turn, each a list of ids.
  List<List<String>>? pages;

  @override
  Future<StockPage> search(StockQuery q,
      {required bool allowFetching, required bool proxied}) async {
    var refused =
        StockClient.refusal(allowFetching: allowFetching, proxied: proxied);
    if (refused != null) return StockPage.failed(refused);
    asked.add(q);
    await held?.future;
    if (q.source == StockSource.pixabayVideos) {
      return StockPage([
        StockItem(
          source: q.source,
          id: "9",
          title: "Waves",
          author: "Bo",
          thumb: "https://cdn.pixabay.com/waves.jpg",
          media: "https://cdn.pixabay.com/waves-medium.mp4",
          preview: "https://cdn.pixabay.com/waves-tiny.mp4",
          width: 640,
          height: 360,
          length: 60,
        ),
      ]);
    }
    var pages = this.pages;
    if (pages != null) {
      var n = asked.where((a) => a.source == q.source).length - 1;
      return StockPage([
        for (var id in pages[n])
          StockItem(
            source: q.source,
            id: id,
            title: "Picture $id",
            thumb: "https://cdn.pixabay.com/$id.jpg",
            media: "https://pixabay.com/$id.png",
            width: 1,
            height: 1,
          ),
      ], more: n + 1 < pages.length);
    }
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

  /// held, when set, keeps each search's answer back until it completes:
  /// a slow network.
  Completer<void>? held;

  /// delivers is the file every download writes.
  List<int> delivers = _png;

  @override
  Future<bool> download(String url, File to,
      {required int maxBytes,
      required bool allowFetching,
      required bool proxied}) async {
    downloads++;
    await to.writeAsBytes(delivers);
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

  /// show puts the panel up on [library]. With [load], its preferences are
  /// first read from what the test stored.
  Future<(CanvasController, CanvasPreferences)> show(WidgetTester tester,
      {bool fetching = true,
      bool key = true,
      StockLibrary? library,
      bool load = false}) async {
    if (key) {
      SharedPreferences.setMockInitialValues(
          {"canvasApiKey:pixabay.com": "abc"});
    }
    setTestScreen(tester, const Size(1200, 900));
    var c = CanvasController(const CanvasDocument(),
        audioEngine: FakeEngine(const {}));
    addTearDown(c.dispose);
    var prefs = CanvasPreferences();
    if (load) await tester.runAsync(prefs.load);
    await idle(tester, 5);
    prefs.allowFetching = fetching;
    if (library != null) prefs.stockLibrary = library;
    await tester.pumpWidget(canvasApp(
        SizedBox(width: 300, child: StockPanel(controller: c)),
        prefs: prefs));
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

  // The two gates stood in front of everything, so the characters drawn
  // here, which ask nothing of the network, could not be reached while
  // fetching was off, as it is to begin with.
  for (var (gate, proxied) in [("fetching off", false), ("a proxy", true)]) {
    testWidgets("with $gate, a library that fetches nothing still opens",
        (tester) async {
      proxiedForTest = proxied;
      await show(tester,
          fetching: proxied,
          key: false,
          library: const StockBrowserLibrary(StockBrowser.characters));
      expect(find.byKey(const ValueKey("stockOff")), findsNothing);
      expect(find.byKey(const ValueKey("stockProxied")), findsNothing);
      expect(find.byType(CharacterBrowser), findsOneWidget);
    });
  }

  // The library was read from storage after the panel was first built, so
  // it showed nothing until then, and then the library saved.
  testWidgets("the first frame is already on the library chosen last",
      (tester) async {
    var c = CanvasController(const CanvasDocument(),
        audioEngine: FakeEngine(const {}));
    addTearDown(c.dispose);
    var prefs = CanvasPreferences();
    const characters = StockBrowserLibrary(StockBrowser.characters);
    prefs.stockLibrary = characters;
    await tester.pumpWidget(canvasApp(
        SizedBox(width: 300, child: StockPanel(controller: c)),
        prefs: prefs));
    expect(
        tester
            .widget<CanvasDropdown<StockLibrary>>(
                find.byKey(const ValueKey("stockSource")))
            .value,
        characters);
    expect(find.byType(CharacterBrowser), findsOneWidget);
  });

  testWidgets(
      "with fetching off, another library can be chosen from the gate's "
      "own page", (tester) async {
    await show(tester, fetching: false);
    expect(find.byKey(const ValueKey("stockOff")), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("stockSource")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Drawn characters").last);
    await idle(tester);
    expect(find.byType(CharacterBrowser), findsOneWidget);
    expect(fake.asked, isEmpty);
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

  // The key's two buttons and the licence button share the Library row; the
  // licence choice lives behind its button rather than among the filters.
  testWidgets("the licence is a button beside the key's", (tester) async {
    SharedPreferences.setMockInitialValues({
      "canvasApiKey:api.thenounproject.com": "k",
      "canvasApiKey:api.thenounproject.com#secret": "s",
    });
    var (_, prefs) = await show(tester,
        key: false, library: const StockSourceLibrary(StockSource.nounProject));
    var library = tester.getRect(find.byKey(const ValueKey("stockSource")));
    for (var k in ["stockChangeKey", "stockForgetKey", "stockLicence"]) {
      var r = tester.getRect(find.byKey(ValueKey(k)));
      expect(r.center.dy, closeTo(library.bottom - 18, 18),
          reason: "$k is on the Library row");
    }
    expect(find.textContaining("Using your"), findsNothing);
    expect(find.byKey(const ValueKey("stockFilter-limit_to_public_domain")),
        findsNothing,
        reason: "not among the filters");
    expect(find.byKey(const ValueKey("stockLicencePanel")), findsNothing);

    await tester.tap(find.byKey(const ValueKey("stockLicence")));
    await idle(tester);
    expect(find.byKey(const ValueKey("stockLicencePanel")), findsOneWidget);
    await tester.tap(
        find.byKey(const ValueKey("stockLicence-limit_to_public_domain-0")));
    await idle(tester);
    expect(prefs.stockFilters[StockSource.nounProject],
        {"limit_to_public_domain": "0"});
    var saved = await SharedPreferences.getInstance();
    expect(saved.getString("canvasStockFilters"),
        contains('"limit_to_public_domain":"0"'));
  });

  // The licence filters were known by a list of their names, and two
  // libraries spell theirs "licence": theirs showed among the filters, and
  // the licence button's panel had no choice in it.
  for (var source in ["wikimedia", "iconify"]) {
    testWidgets(
        "$source's licence choice is behind the licence button, whatever "
        "it calls it", (tester) async {
      await show(tester,
          key: false,
          library: StockSourceLibrary(StockSource.values.byName(source)));
      expect(find.byKey(const ValueKey("stockFilter-licence")), findsNothing,
          reason: "not among the filters");
      await tester.tap(find.byKey(const ValueKey("stockLicence")));
      await idle(tester);
      expect(find.byKey(const ValueKey("stockLicence-licence-free")),
          findsOneWidget,
          reason: "behind the licence button");
    });
  }

  // Saved filters under a library this build does not know were read as
  // Pixabay's pictures', and the last one read won: Pixabay's own were lost.
  testWidgets("filters saved for an unknown library leave Pixabay's alone",
      (tester) async {
    SharedPreferences.setMockInitialValues({
      "canvasApiKey:pixabay.com": "abc",
      "canvasStockFilters": jsonEncode({
        "pixabayPictures": {"image_type": "photo"},
        "gone": {"image_type": "vector"},
      }),
    });
    await show(tester, key: false, load: true);
    await tester.enterText(find.byKey(const ValueKey("stockSearch")), "fox");
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await idle(tester);
    expect(fake.asked.single.source, StockSource.pixabayPictures);
    expect(fake.asked.single.filters["image_type"], "photo");
  });

  testWidgets(
      "an answer still on its way when the library changes is not shown "
      "as the new library's", (tester) async {
    // Changing library cleared the results but not the search they were
    // for, so an answer arriving afterwards filled the new library's list:
    // Pixabay's pictures showed under Pexels once its key was given.
    await show(tester);
    fake.held = Completer();
    await tester.enterText(find.byKey(const ValueKey("stockSearch")), "fox");
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await idle(tester, 5);
    expect(fake.asked, hasLength(1));

    await tester.tap(find.byKey(const ValueKey("stockSource")));
    // Not settled: the search's spinner turns until its answer comes.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text("Pexels photos").last);
    await idle(tester);
    expect(find.byKey(const ValueKey("stockKey")), findsOneWidget,
        reason: "Pexels needs a key, and none is given");

    fake.held!.complete();
    await idle(tester);
    await tester.enterText(find.byKey(const ValueKey("stockKey")), "p-1");
    await tester.tap(find.byKey(const ValueKey("stockSaveKey")));
    await idle(tester);
    expect(find.byKey(const ValueKey("stockSearch")), findsOneWidget);
    expect(find.byKey(const ValueKey("stock-pixabayPictures-1")), findsNothing,
        reason: "Pixabay's answer, for the library left");
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: "not waiting for the answer it set aside");
  });

  testWidgets("a next page repeating a result does not show it twice",
      (tester) async {
    // Ken's log: Pixabay's second page repeated a picture from the first,
    // and two tiles with one key threw.
    fake.pages = [
      ["1", "2", "3"],
      ["3", "4"],
    ];
    await show(tester);
    await tester.enterText(find.byKey(const ValueKey("stockSearch")), "fox");
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await idle(tester);
    await tester.tap(find.byKey(const ValueKey("stockMore")));
    await idle(tester);

    expect(tester.takeException(), isNull);
    for (var id in ["1", "2", "3", "4"]) {
      expect(find.byKey(ValueKey("stock-pixabayPictures-$id")), findsOneWidget,
          reason: "picture $id once");
    }
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
    // Until it is on the canvas, however long a loaded machine takes.
    for (var i = 0; i < 100 && c.document.elements.isEmpty; i++) {
      await idle(tester, 5);
    }
    await idle(tester);
    expect(fake.downloads, 1);
    var image = c.document.elements.single as ImageElement;
    expect(image.name, "Red fox");
    var asset = (await tester.runAsync(() => CanvasLibrary.list()))!.single;
    expect(asset.id, image.assetId);
    expect([asset.name, asset.author, asset.from, asset.origin],
        ["Red fox", "Ann", "Pixabay", "https://pixabay.com/fox-1/"]);
  });

  // An icon library's drawing arrives unseen, so it is held to the rule a
  // script's drawing is: nothing in it that runs, embeds a page or reaches
  // outside itself.
  test("a stock drawing with a script is refused; a plain one is kept",
      () async {
    StockItem icon(String id) => StockItem(
        source: StockSource.iconify,
        id: id,
        title: "Icon $id",
        media: "https://api.iconify.design/x/$id.svg");
    Future<StockImport> fetch(String svg) {
      fake.delivers = utf8.encode(svg);
      return importStockItem(icon(svg.length.toString()),
          allowFetching: true, proxied: false);
    }

    var scripted = await fetch('<svg xmlns="http://www.w3.org/2000/svg">'
        '<script>alert(1)</script><rect width="4" height="4"/></svg>');
    expect(scripted.asset, isNull);
    expect(scripted.problem,
        contains("has a script, an embedded page or a link to an outside"));
    expect(await CanvasLibrary.list(), isEmpty);

    var plain = await fetch('<svg xmlns="http://www.w3.org/2000/svg" '
        'viewBox="0 0 4 4"><rect width="4" height="4"/></svg>');
    expect(plain.problem, isNull);
    expect(plain.asset?.kind, AssetKind.vector);
    expect((await CanvasLibrary.list()).single.id, plain.asset?.id);
  });

  // A video is watched in its tile before it is chosen: a small copy fetched
  // when play is pressed, and nothing added anywhere.
  testWidgets("a video result plays in its tile before it is used",
      (tester) async {
    // A minute long: a loaded machine can take a second or more over the
    // steps below, and a one-second video had finished by the time it was
    // looked for.
    var frames = StockPanel.videoFrames;
    StockPanel.videoFrames = FakeFrames(60);
    addTearDown(() => StockPanel.videoFrames = frames);
    var (c, _) = await show(tester,
        library: const StockSourceLibrary(StockSource.pixabayVideos));
    await tester.enterText(find.byKey(const ValueKey("stockSearch")), "sea");
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await idle(tester);

    await tester.tap(find.byKey(const ValueKey("stockWatch-pixabayVideos-9")));
    // Until it shows, within reason: the copy is written to a real file, and
    // a loaded machine takes longer over that than a quiet one.
    var watching = find.byKey(const ValueKey("stockWatching-pixabayVideos-9"));
    for (var i = 0; i < 40 && watching.evaluate().isEmpty; i++) {
      await idle(tester, 5);
    }
    expect(fake.downloads, 1, reason: "the small copy, to watch");
    expect(find.byKey(const ValueKey("stockWatching-pixabayVideos-9")),
        findsOneWidget);
    expect(c.document.elements, isEmpty, reason: "watched, not used");

    await tester.tap(find.byKey(const ValueKey("stockWatch-pixabayVideos-9")));
    await idle(tester, 5);
    expect(find.byKey(const ValueKey("stockWatching-pixabayVideos-9")),
        findsNothing,
        reason: "stopped");
  });
}
