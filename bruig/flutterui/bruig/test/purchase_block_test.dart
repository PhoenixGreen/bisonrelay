import 'package:bruig/components/feed/markdown_purchase.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/models/payments.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// purchase_block_test.dart covers the row an order page draws for a file it
// bought.
//
// The hard part is which copy of which product a row is about, and it is
// decided in arrivedFor. A shop sends the same product again when it changes,
// a buyer can order the same product twice, and two shops are free to use the
// same SKU -- so a row that matched loosely would offer somebody the wrong
// file with the right name on it.

/// _fake stands in for a received file's metadata: arrivedFor reads the two
/// attributes and the filename, and nothing else.
class _Meta {
  final Map<String, dynamic>? attributes;
  final String filename;
  const _Meta(this.attributes, this.filename);
}

List<({String diskPath, dynamic metadata})> _received(
        List<(String path, String? order, String? sku, String name)> rows) =>
    [
      for (var r in rows)
        (
          diskPath: r.$1,
          metadata: _Meta({
            if (r.$2 != null) "simplestore.order": r.$2,
            if (r.$3 != null) "simplestore.sku": r.$3,
          }, r.$4)
        ),
    ];

Widget _host(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<PaymentsModel>(create: (c) => PaymentsModel()),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<MarkdownAreaModel>(
            create: (c) => MarkdownAreaModel("/tmp")),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 700, child: child)),
        ),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group("the markup", () {
    test("reads the order, the sku and the title", () {
      var rule =
          PurchaseRule.parse("order=00000001, sku=g1, title=A guide to it");
      expect(rule.order, "00000001");
      expect(rule.sku, "g1");
      expect(rule.title, "A guide to it");
      expect(rule.draws, isTrue);
    });

    // Without a SKU there is nothing to match a file against, so there is
    // nothing this row could honestly say.
    test("draws nothing without a sku", () {
      expect(PurchaseRule.parse("order=1, title=A guide").draws, isFalse);
    });
  });

  group("finding what arrived", () {
    const rule = PurchaseRule(order: "00000001", sku: "g1", title: "A guide");

    test("finds nothing before anything has been sent", () {
      expect(arrivedFor(const [], rule), isNull);
    });

    test("ignores files from other products", () {
      var got = arrivedFor(
          _received([("/tmp/other.md", "00000001", "g2", "other.md")]), rule);
      expect(got, isNull);
    });

    // Files that arrived but were never written are not files anybody can
    // open, and offering to read one is offering a button that does nothing.
    test("ignores a file that is not on disk", () {
      var got =
          arrivedFor(_received([("", "00000001", "g1", "guide.md")]), rule);
      expect(got, isNull);
    });

    test("finds the copy sent for this order", () {
      var got = arrivedFor(
          _received([
            ("/tmp/old.md", "00000007", "g1", "old.md"),
            ("/tmp/this.md", "00000001", "g1", "guide.md"),
          ]),
          rule);
      expect(got?.path, "/tmp/this.md");
      expect(got?.filename, "guide.md");
    });

    // A copy of the same product from an earlier order is still the thing
    // that was bought: better to offer it than to tell somebody who has the
    // file that nothing has arrived.
    test("falls back to another copy of the same product", () {
      var got = arrivedFor(
          _received([("/tmp/old.md", "00000007", "g1", "old.md")]), rule);
      expect(got?.path, "/tmp/old.md");
    });
  });

  group("the row", () {
    // A page rendered somewhere with no downloads behind it -- a preview, a
    // test -- says nothing rather than bringing the page down.
    testWidgets("draws nothing without a downloads model", (tester) async {
      await tester.pumpWidget(_host(MarkdownArea(
          "--purchase[order=00000001, sku=g1, title=A guide]--\n", false)));
      await tester.pump();
      expect(find.byType(MarkdownPurchase), findsOneWidget);
      expect(find.textContaining("--purchase"), findsNothing);
      expect(find.textContaining("A guide"), findsNothing);
    });
  });
}
