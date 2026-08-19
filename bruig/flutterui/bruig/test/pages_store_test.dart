import 'package:golib_plugin/definitions.dart';
import 'package:flutter_test/flutter_test.dart';

// pages_store_test.dart covers the seller-side store models.
//
// The Store tab itself needs a PagesModel, whose construction reaches
// golib.dylib through ResourcesModel, so it is verified in the running app
// (see pages_browser_test.dart for the same limit and how the browser chrome
// works around it).

ManagedOrder _order(List<SSCartItem> items, {double ship = 0}) => ManagedOrder(
      1,
      "uid",
      "alice",
      SSCart(items, DateTime.now()),
      "placed",
      DateTime.now(),
      ship,
      0,
      "ln",
      const [],
    );

SSCartItem _item(double price, int qty) =>
    SSCartItem(SSProduct("t", "sku", "", const [], price, false), qty);

void main() {
  group('ManagedOrder', () {
    test('total counts quantity and adds shipping', () {
      var order = _order([_item(2.50, 3), _item(10, 1)], ship: 4.95);
      expect(order.total, closeTo(22.45, 0.0001));
    });

    test('an empty cart with no shipping owes nothing', () {
      expect(_order(const []).total, 0);
    });
  });

  group('ManagedProduct', () {
    test('copyWith keeps the file the product came from', () {
      var p = ManagedProduct(
          "Solo", "sku-1", "d", const ["music"], 0.99, false, false, "", "a.toml");
      var edited = p.copyWith(price: 1.99);

      expect(edited.file, "a.toml");
      expect(edited.sku, "sku-1");
      expect(edited.price, 1.99);
      // Untouched fields survive.
      expect(edited.tags, ["music"]);
    });

    test('a new product starts on sale, not hidden', () {
      // ManagedProduct.empty backs the "New product" form; starting hidden
      // would mean every product written had to be un-hidden afterwards.
      expect(ManagedProduct.empty().disabled, isFalse);
      expect(ManagedProduct.empty().sku, "");
    });
  });

  group('order statuses', () {
    test('are the ones the store accepts', () {
      // The seller picks from this list; simplestore.ValidOrderStatus
      // rejects anything else, so the two must agree.
      expect(ssOrderStatuses,
          ["placed", "paid", "shipped", "completed", "canceled"]);
    });
  });
}
