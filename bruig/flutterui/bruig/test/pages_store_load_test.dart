import 'dart:async';

import 'package:bruig/models/pages.dart';
import 'package:bruig/models/store.dart';
import 'package:bruig/models/resources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:shared_preferences/shared_preferences.dart';

// pages_store_load_test.dart covers the order the Store section loads in.
//
// The catalogue is read when the section is built, which is as Pages opens
// rather than when the section is first looked at -- every section stays
// built so a half-written product survives the trip. That made a race
// certain rather than occasional: the store asked whether it was hosting a
// store before the answer had arrived, was told no, and emptied its own
// catalogue. On restart the products were simply gone, and came back only
// once something else refilled the list.

class _FakePages extends PagesModel {
  _FakePages() : super(ResourcesModel(runStream: false));

  final hostArrived = Completer<PagesHostStatus>();

  static final storeConfig = PagesHostConfig(
      pagesHostModeStore, "", "/store", "ln", "", 0, "");

  @override
  Future<PagesHostStatus> fetchHost() => hostArrived.future;
}

/// _FakeStore is the shop half. The catalogue and the order book moved to
/// StoreModel, and the race this file is about did not: the shop still asks
/// hosting whether there is one before it reads anything.
class _FakeStore extends StoreModel {
  // listen: false -- there is no golib here to hear an order from.
  _FakeStore(PagesModel pages) : super(pages, listen: false);

  int productFetches = 0;

  @override
  Future<List<ManagedProduct>> fetchProducts() async {
    productFetches++;
    return [
      ManagedProduct("A thing", "SKU1", "", const [], 1, false, false, "",
          "products.toml")
    ];
  }

  @override
  Future<List<ManagedOrder>> fetchOrders() async => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the catalogue waits for the hosting config rather than emptying', () async {
    var m = _FakePages();
    var shop = _FakeStore(m);

    // The Store section is built before the config has arrived.
    var loading = shop.loadStore();
    await Future<void>.delayed(Duration.zero);
    expect(shop.productFetches, 0, reason: "nothing to ask for yet");

    m.hostArrived.complete(PagesHostStatus(
        _FakePages.storeConfig, true, "", "/store", const []));
    await loading;

    expect(shop.products, hasLength(1));
    expect(shop.products.first.sku, "SKU1");
  });

  test('a client hosting no store still ends up with an empty catalogue',
      () async {
    var m = _FakePages();
    var shop = _FakeStore(m);
    var loading = shop.loadStore();
    m.hostArrived.complete(
        PagesHostStatus(PagesHostConfig.off(), true, "", "", const []));
    await loading;

    expect(shop.products, isEmpty);
    expect(shop.productFetches, 0);
    expect(shop.storeError, isNull, reason: "not hosting is not an error");
  });

  test('the hosting config is read once, however many things want it',
      () async {
    var m = _FakePages();
    var shop = _FakeStore(m);
    var a = shop.loadStore(), b = shop.loadStore();
    var ready = m.hostReady;
    m.hostArrived.complete(PagesHostStatus(
        _FakePages.storeConfig, true, "", "/store", const []));
    await Future.wait([a, b, ready]);

    // hostArrived is a single Completer: a second call to fetchHost would
    // have thrown on completing it twice.
    expect(m.hostConfig.hostsStore, isTrue);
  });
}
