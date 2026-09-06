import 'package:bruig/models/purchases.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';

// purchases_test.dart covers working out what somebody has bought from what
// they were sent.
//
// A shop sets the order, the SKU and the title on the file it sends, and the
// receiving client keeps them beside it. So nothing is recorded separately,
// and nothing can drift out of step with what actually arrived.

FileMetadata sent({
  required String sku,
  String title = "A guide",
  String hash = "h1",
  String filename = "guide.md",
}) =>
    FileMetadata(
        1,
        0,
        10,
        "",
        filename,
        "",
        hash,
        const [],
        "",
        {
          purchaseOrderAttr: "7",
          purchaseSKUAttr: sku,
          purchaseTitleAttr: title,
        });

FileMetadata plainFile({String hash = "z"}) =>
    FileMetadata(1, 0, 10, "", "holiday.jpg", "", hash, const [], "", null);

void main() {
  group('telling a purchase from a file', () {
    test('a file a shop sent is one', () {
      expect(isPurchase(sent(sku: "g1")), isTrue);
    });

    test('a file somebody just sent is not', () {
      expect(isPurchase(plainFile()), isFalse);
      expect(isPurchase(null), isFalse);
    });
  });

  group('gathering what was bought', () {
    test('ordinary files are left out of it', () {
      var got = purchasesOf([
        (seller: "alice", metadata: plainFile()),
        (seller: "alice", metadata: sent(sku: "g1")),
      ]);
      expect(got, hasLength(1));
      expect(got.first.sku, "g1");
    });

    test('a product is one thing however many times it was sent', () {
      // Three sendings of one product is one thing somebody bought, not
      // three, and that difference is why this is shown apart from the
      // downloads at all.
      var got = purchasesOf([
        (seller: "alice", metadata: sent(sku: "g1", hash: "h1")),
        (seller: "alice", metadata: sent(sku: "g1", hash: "h2")),
        (seller: "alice", metadata: sent(sku: "g1", hash: "h3")),
      ]);
      expect(got, hasLength(1));
      expect(got.first.copies, hasLength(3));
    });

    test('the same file arriving twice is not an update', () {
      // A shop that sends the same file again sends the same hash. Calling
      // that an update tells somebody to go and read what they have read.
      var got = purchasesOf([
        (seller: "alice", metadata: sent(sku: "g1", hash: "h1")),
        (seller: "alice", metadata: sent(sku: "g1", hash: "h1")),
      ]);
      expect(got.first.hasUpdate, isFalse);
      expect(got.first.copies, hasLength(1));
    });

    test('a new version of the same product is', () {
      var got = purchasesOf([
        (seller: "alice", metadata: sent(sku: "g1", hash: "h1")),
        (seller: "alice", metadata: sent(sku: "g1", hash: "h2")),
      ]);
      expect(got.first.hasUpdate, isTrue);
      expect(got.first.latest.hash, "h2");
    });

    test('two shops using one SKU are two products', () {
      // Nothing stops them, and folding one seller's product into
      // another's would show somebody a thing they never bought.
      var got = purchasesOf([
        (seller: "alice", metadata: sent(sku: "g1", title: "Alice's guide")),
        (seller: "bob", metadata: sent(sku: "g1", title: "Bob's guide")),
      ]);
      expect(got, hasLength(2));
      expect(got.map((p) => p.seller).toSet(), {"alice", "bob"});
    });

    test('a product with no title falls back to the file name', () {
      var noTitle = FileMetadata(1, 0, 10, "", "manual.pdf", "", "h", const [],
          "", {purchaseSKUAttr: "g1"});
      expect(purchasesOf([(seller: "a", metadata: noTitle)]).first.title,
          "manual.pdf");
    });

    test('nothing bought is nothing shown', () {
      expect(purchasesOf(const []), isEmpty);
      expect(purchasesOf([(seller: "a", metadata: plainFile())]), isEmpty);
    });
  });
}
