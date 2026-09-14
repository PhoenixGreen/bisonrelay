import 'dart:io';

import 'package:bruig/plugin_system/canvas/model/data_presets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_row_names.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_row_names_test.dart is the list of things a source has.
//
// The built-in list could not be right: every identifier written out by hand
// is a chance to be wrong, and wrong here is invisible until somebody types a
// name and the refresh comes back without it. CoinGecko files Firo under
// "zcoin" and XRP under "ripple". So the list is asked for and kept, and what
// is pinned here is that asking wins over guessing.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp("canvas_names_test");
    CanvasStorage.rootOverride = root.path;
    CanvasRowNames.forget();
  });

  tearDown(() async {
    CanvasStorage.rootOverride = null;
    CanvasRowNames.forget();
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// _list is what CoinGecko's own list of coins looks like.
  Future<dynamic> list(String url) async => [
        {"id": "decred", "symbol": "dcr", "name": "Decred"},
        {"id": "ripple", "symbol": "xrp", "name": "XRP"},
        {"id": "zcoin", "symbol": "firo", "name": "Firo"},
        {"id": "digibyte", "symbol": "dgb", "name": "DigiByte"},
        // The same name twice, which a source of thousands has plenty of.
        {"id": "firo-imposter", "symbol": "fake", "name": "Firo"},
        // And entries with nothing usable in them.
        {"id": "", "name": "Nameless"},
        {"name": "No identifier"},
      ];

  group("asking the source", () {
    test("replaces the guesses with what it files things under", () async {
      // Before: the built-in list, which has Firo wrong-ish and is short.
      expect(CanvasRowNames.idFor(coinGeckoMarkets, "Firo"), isNotEmpty);

      var found = await CanvasRowNames.fetch(coinGeckoMarkets, list);
      expect(found, 4, reason: "the usable ones, each name once");

      expect(CanvasRowNames.idFor(coinGeckoMarkets, "Firo"), "zcoin");
      expect(CanvasRowNames.idFor(coinGeckoMarkets, "XRP"), "ripple");
      expect(CanvasRowNames.idFor(coinGeckoMarkets, "DigiByte"), "digibyte");
    });

    test("and the first of a name wins", () async {
      // A source of thousands has several coins called the same thing, and
      // the real one comes before its imitators.
      await CanvasRowNames.fetch(coinGeckoMarkets, list);
      expect(CanvasRowNames.idFor(coinGeckoMarkets, "Firo"), "zcoin");
    });

    test("anything it has never heard of is taken as typed", () async {
      await CanvasRowNames.fetch(coinGeckoMarkets, list);
      expect(CanvasRowNames.idFor(coinGeckoMarkets, "Some New Coin"),
          "some-new-coin");
    });

    test("the names are what a cell offers", () async {
      expect(CanvasRowNames.suggestionsFor(coinGeckoMarkets),
          coinGeckoMarkets.rowNames,
          reason: "the built-in list until it has been asked");

      await CanvasRowNames.fetch(coinGeckoMarkets, list);
      expect(CanvasRowNames.suggestionsFor(coinGeckoMarkets),
          containsAll(["Decred", "XRP", "Firo", "DigiByte"]));
    });

    test("it is kept for next time", () async {
      await CanvasRowNames.fetch(coinGeckoMarkets, list);
      CanvasRowNames.forget();
      expect(CanvasRowNames.known(coinGeckoMarkets.id), isNull);

      await CanvasRowNames.load(coinGeckoMarkets.id);
      expect(CanvasRowNames.idFor(coinGeckoMarkets, "Firo"), "zcoin");
    });

    test("and a request that answers with nothing changes nothing", () async {
      expect(await CanvasRowNames.fetch(coinGeckoMarkets, (_) async => null),
          isNull);
      expect(await CanvasRowNames.fetch(coinGeckoMarkets, (_) async => []),
          isNull);
      expect(CanvasRowNames.known(coinGeckoMarkets.id), isNull,
          reason: "the guesses are still better than nothing");
    });

    test("a source with no list to ask for is not asked", () async {
      expect(footballData.namesAddress, isEmpty);
      expect(await CanvasRowNames.fetch(footballData, list), isNull);
    });
  });
}
