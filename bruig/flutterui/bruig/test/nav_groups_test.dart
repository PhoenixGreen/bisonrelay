import 'package:bruig/components/feed/markdown_nav.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/models/payments.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/model/markdown_style.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// nav_groups_test.dart covers a bar divided in two: what the site wrote at
// one end, and what a shop added at the other.
//
// The three things that division is for -- a count over a link, an icon
// standing in for its words, and the second group folding into a menu when
// there is no room for it -- are each a thing a bar could not say before.

Widget wrap(Widget child, {Size size = const Size(1200, 800)}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (_) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<PaymentsModel>(create: (_) => PaymentsModel()),
        ChangeNotifierProvider<SnackBarModel>(create: (_) => SnackBarModel()),
        ChangeNotifierProvider<ResourcesModel>(
            create: (_) => ResourcesModel(runStream: false)),
        ChangeNotifierProvider<MarkdownAreaModel>(
            create: (_) => MarkdownAreaModel("")),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

const bar = "--nav[pills]--\n"
    "[Home](index.md)\n"
    "[About](about.md)\n"
    "--right--\n"
    "[Shop](/store)\n"
    "[Cart](/cart)[badge=2]\n"
    "[Orders](/orders)\n"
    "--/nav--\n";

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('what one link said about itself', () {
    test('a link with nothing after it is the link', () {
      var got = NavEntry.parse("[Home](index.md)")!;
      expect(got.label, "Home");
      expect(got.target, "index.md");
      expect(got.badge, isNull);
      expect(got.icon, isNull);
      expect(got.labelled, isTrue);
    });

    test('the settings it may carry', () {
      var got = NavEntry.parse("[Cart](/cart)[badge=2, icon=cart, label=off]")!;
      expect(got.badge, 2);
      expect(got.icon, MarkdownCardIcon.cart);
      expect(got.labelled, isFalse);
    });

    test('nought is nothing waiting', () {
      // A cart holding nothing should not wear a nought.
      expect(NavEntry.parse("[Cart](/cart)[badge=0]")!.badge, isNull);
    });

    test('a line that is not a link is not one', () {
      expect(NavEntry.parse("just words"), isNull);
      expect(NavEntry.parse("--right--"), isNull);
    });
  });

  group('drawn', () {
    testWidgets('the second group sits at the other end', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(MarkdownArea(bar, false)));
      await tester.pump();

      var about = tester.getRect(find.text("About"));
      var shop = tester.getRect(find.text("Shop"));
      expect(shop.left, greaterThan(about.right + 100),
          reason: "the shop's links are not at the far end");
      // And the marker itself is not drawn as the words it is made of.
      expect(find.textContaining("--right--"), findsNothing);
    });

    testWidgets('the bar\'s own background runs behind both groups',
        (tester) async {
      // What a divided bar lost by being built somewhere else: the strip
      // behind the links, its height and its margin are all put on after
      // the links are laid out, and a bar that returned early skipped every
      // one of them. On screen the strip ended where the first group did,
      // which reads as the links having lost their background.
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(MarkdownArea(
          bar.replaceFirst("--nav[pills]--",
              "--nav[pills, background=#102030, width=full]--"),
          false)));
      await tester.pump();

      var strip = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.color == const Color(0xff102030));
      expect(strip.length, 1, reason: "the bar has no background of its own");

      var box = tester.getRect(find.byWidget(strip.first));
      var orders = tester.getRect(find.text("Orders"));
      expect(box.right, greaterThanOrEqualTo(orders.right),
          reason: "the strip stops before the second group");
      expect(
          box.left, lessThanOrEqualTo(tester.getRect(find.text("Home")).left));
    });

    testWidgets('what is in the cart is drawn over it', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(MarkdownArea(bar, false)));
      await tester.pump();

      expect(find.text("2"), findsOneWidget);
      var cart = tester.getRect(find.text("Cart"));
      var badge = tester.getRect(find.text("2"));
      expect(badge.center.dx, greaterThan(cart.center.dx));
      expect(badge.center.dy, lessThan(cart.center.dy));
    });

    testWidgets('an icon stands in for the words, which become its name',
        (tester) async {
      await tester.pumpWidget(wrap(MarkdownArea(
          "--nav[pills]--\n[Cart](/cart)[icon=cart, label=off]\n--/nav--\n",
          false)));
      await tester.pump();

      expect(find.byIcon(Icons.shopping_cart_outlined), findsOneWidget);
      expect(find.text("Cart"), findsNothing);
      expect(find.byType(Tooltip), findsOneWidget);
    });

    testWidgets('the added group folds before the site\'s own is squeezed',
        (tester) async {
      // Which group gives way. The second used to take its natural width and
      // the first whatever was left, so on a middling window the site's own
      // links were squeezed to empty boxes while the shop's icons sat there
      // at full size. The group added to a bar is the group that folds.
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Wide enough for the site's links and nothing like enough for both.
      await tester.pumpWidget(wrap(SizedBox(
          width: 800,
          child: MarkdownArea(
              "--nav[pills]--\n"
              "[Documentation](docs.md)\n"
              "[Contributing](contributing.md)\n"
              "[Downloads](downloads.md)\n"
              "--right--\n"
              "[Shop](/store)[icon=shop, label=off]\n"
              "[Cart](/cart)[icon=cart, label=off, badge=1]\n"
              "[Orders](/orders)[icon=orders, label=off]\n"
              "--/nav--\n",
              false))));
      await tester.pump();

      for (var word in ["Documentation", "Contributing", "Downloads"]) {
        expect(find.text(word), findsOneWidget, reason: "$word went");
        var box = tester.getRect(find.text(word));
        expect(box.width, greaterThan(20),
            reason: "$word was squeezed to nothing");
      }
    });

    testWidgets('narrower still, the site\'s own links fold as well',
        (tester) async {
      // A bar cannot always answer by wrapping. This one is usually written
      // into a row of a banner, and a row has a height -- wrapped inside
      // one, the second line is cut off, which is a bar showing whichever
      // links happened to land on the first line and no way to reach the
      // rest. A menu holds all of them at any width.
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(SizedBox(
          width: 300,
          child: MarkdownArea(
              "--nav[pills]--\n"
              "[Documentation](docs.md)\n"
              "[Contributing](contributing.md)\n"
              "[Downloads](downloads.md)\n"
              "--right--\n"
              "[Shop](/store)[icon=shop, label=off]\n"
              "[Cart](/cart)[icon=cart, label=off, badge=1]\n"
              "--/nav--\n",
              false))));
      await tester.pump();

      expect(find.byIcon(Icons.menu), findsOneWidget);
      expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
      expect(find.text("Documentation"), findsNothing);
      expect(tester.takeException(), isNull);

      // Everything is still reachable, which is the point of folding rather
      // than letting a row cut them off.
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.text("Documentation"), findsOneWidget);
      expect(find.text("Downloads"), findsOneWidget);
    });

    testWidgets('a folded group is drawn in the bar\'s own ink',
        (tester) async {
      // The same links, the same bar: folding must not change their colour.
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(SizedBox(
          width: 360,
          child: MarkdownArea(
              "--nav[pills]--\n[Home](index.md)\n--right--\n"
              "[Shop](/store)[icon=shop, label=off]\n"
              "[Cart](/cart)[icon=cart, label=off]\n--/nav--\n",
              false))));
      await tester.pump();

      var folded = tester.widget<Icon>(find.byIcon(Icons.storefront_outlined));
      var word = tester.widget<Text>(find.text("Home"));
      expect(folded.color, word.style!.color);
    });

    testWidgets('the second group can be sized and moved in from the edge',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(MarkdownArea(
          "--nav[pills]--\n[Home](index.md)\n--right[size=28, inset=24]--\n"
          "[Shop](/store)[icon=shop, label=off]\n--/nav--\n",
          false)));
      await tester.pump();

      expect(
          tester.widget<Icon>(find.byIcon(Icons.storefront_outlined)).size, 28);

      var icon = tester.getRect(find.byIcon(Icons.storefront_outlined));
      var bar = tester.getRect(find.byType(MarkdownArea).first);
      expect(bar.right - icon.right, greaterThan(20),
          reason: "the last icon is pressed against the end of the bar");
    });

    testWidgets('a link can be marked as the page being read', (tester) async {
      // A shop is a dozen paths -- the front, a product, the cart -- and only
      // one of them is what the site's link says. So the shop says.
      await tester.pumpWidget(wrap(MarkdownArea(
          "--nav[pills]--\n[Store](store)[active=on]\n[Home](index.md)\n"
          "--/nav--\n",
          false)));
      await tester.pump();

      expect(tester.widget<Text>(find.text("Store")).style!.fontWeight,
          FontWeight.bold);
      expect(tester.widget<Text>(find.text("Home")).style!.fontWeight,
          FontWeight.normal);
    });

    testWidgets('the folded group wears its own icon, badge and all',
        (tester) async {
      // Three dots say only that there is a menu. The shop's own storefront
      // says which menu it is -- and the count has to be inside the bar
      // rather than hung off the end of it, where it was cut in half.
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(SizedBox(
          width: 360,
          child: MarkdownArea(
              "--nav[pills]--\n[Home](index.md)\n--right--\n"
              "[Shop](/store)[icon=shop, label=off]\n"
              "[Cart](/cart)[icon=cart, label=off, badge=3]\n"
              "--/nav--\n",
              false))));
      await tester.pump();

      expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsNothing);

      // The count is drawn, and inside the bar rather than over its edge.
      var badge = tester.getRect(find.text("3"));
      var bar = tester.getRect(find.byType(MarkdownArea).first);
      expect(badge.right, lessThanOrEqualTo(bar.right),
          reason: "the count is hanging off the end of the bar");
    });

    testWidgets('a link can ask for no box round it', (tester) async {
      await tester.pumpWidget(wrap(MarkdownArea(
          "--nav[pills]--\n[Home](index.md)\n--right--\n"
          "[Cart](/cart)[icon=cart, label=off, plain=on]\n--/nav--\n",
          false)));
      await tester.pump();

      // The site's link keeps its pill; the shop's has none.
      var pills = find.ancestor(
          of: find.text("Home"), matching: find.byType(Container));
      expect(pills, findsOneWidget);
      expect(
          find.ancestor(
              of: find.byIcon(Icons.shopping_cart_outlined),
              matching: find.byType(Container)),
          findsNothing);
    });

    testWidgets('the second group can sit closer together', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      Future<double> spacingWith(String marker) async {
        await tester.pumpWidget(wrap(MarkdownArea(
            "--nav[pills, gap=20]--\n[Home](index.md)\n$marker\n"
            "[Shop](/store)[icon=shop, label=off]\n"
            "[Orders](/orders)[icon=orders, label=off]\n--/nav--\n",
            false)));
        await tester.pump();
        var shop = tester.getRect(find.byIcon(Icons.storefront_outlined));
        var orders = tester.getRect(find.byIcon(Icons.receipt_long_outlined));
        return orders.left - shop.right;
      }

      var theirs = await spacingWith("--right--");
      var tight = await spacingWith("--right[gap=2]--");
      expect(tight, lessThan(theirs));
    });

    testWidgets('an ordinary bar folds too, with no shop in it',
        (tester) async {
      // The fold lived on the divided path, so it happened on a shop's pages
      // and nowhere else: the same bar, on the site's own pages, still
      // wrapped and was still cut off by the row it sits in.
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const plain = "--nav[pills]--\n"
          "[Documentation](docs.md)\n"
          "[Contributing](contributing.md)\n"
          "[Downloads](downloads.md)\n"
          "--/nav--\n";

      await tester.pumpWidget(
          wrap(SizedBox(width: 240, child: MarkdownArea(plain, false))));
      await tester.pump();

      expect(find.byIcon(Icons.menu), findsOneWidget);
      expect(find.text("Documentation"), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.text("Downloads"), findsOneWidget);
    });

    testWidgets('a bar is the same height folded as it is drawn out',
        (tester) async {
      // The banner it sits in has a height, and a bar that grew a second row
      // -- or shrank to a bare icon -- changed it with the window.
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const plain = "--nav[pills]--\n"
          "[Documentation](docs.md)\n"
          "[Contributing](contributing.md)\n"
          "[Downloads](downloads.md)\n"
          "--/nav--\n";

      Future<double> heightAt(double width) async {
        await tester.pumpWidget(
            wrap(SizedBox(width: width, child: MarkdownArea(plain, false))));
        await tester.pump();
        return tester.getRect(find.byType(MarkdownArea).first).height;
      }

      var wide = await heightAt(900);
      var narrow = await heightAt(240);
      expect(narrow, closeTo(wide, 6));
    });

    testWidgets('a divided bar keeps its height and its right edge as it folds',
        (tester) async {
      // Both of these move the banner the bar is written into, and both were
      // wrong for the same reason: the count hung off the corner of the
      // folded icon needed room, and room at the end of a row is what there
      // is least of. Given it above, the bar grew when it folded; given it at
      // the side, the icon sat further in than the links it replaced.
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const withCart = "--nav[pills]--\n"
          "[Home](index.md)\n[About](about.md)\n"
          "--right--\n"
          "[Shop](/store)[icon=shop, label=off]\n"
          "[Orders](/orders)[icon=orders, label=off]\n"
          "[Cart](/cart)[icon=cart, label=off, badge=1]\n"
          "--/nav--\n";

      Future<(double, double)> at(double width) async {
        await tester.pumpWidget(
            wrap(SizedBox(width: width, child: MarkdownArea(withCart, false))));
        await tester.pump();
        var bar = tester.getRect(find.byType(MarkdownArea).first);
        var last = tester.getRect(find.byIcon(
            find.byIcon(Icons.shopping_cart_outlined).evaluate().isEmpty
                ? Icons.storefront_outlined
                : Icons.shopping_cart_outlined));
        return (bar.height, bar.right - last.right);
      }

      var (openHeight, openEdge) = await at(1100);
      var (foldedHeight, foldedEdge) = await at(450);

      expect(foldedHeight, openHeight,
          reason: "the bar changed height when it folded");
      expect(foldedEdge, closeTo(openEdge, 2),
          reason: "the folded group sits further in than the links it "
              "replaced");
    });

    testWidgets('a bar in a banner folds rather than being cut through',
        (tester) async {
      // A banner drawn in a narrow window scales its rows down, deliberately,
      // so a logo and a title keep their proportions. A block in one of those
      // rows is drawn at its own size and clipped to the row -- also
      // deliberate, since shrinking a bar of links would set its writing at a
      // different size from everything else in the banner.
      //
      // Together those two leave a bar drawing itself full size into a row
      // half its height: what is left is a strip through the middle of some
      // words. Neither side is wrong on its own, and neither can see the
      // other, so the banner tells the cell how much room it has.
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const banner = "--header--\n"
          "\n"
          "--row[44,center,flush]--\n"
          "--nav[pills, align=left]--\n"
          "[Home](index.md)\n[About](about.md)\n[Store](store)\n"
          "--/nav--\n"
          "--/row--\n"
          "\n"
          "--/header--\n";

      // Set large enough that the scaled row cannot hold the words. What
      // decides is the writing against the room, measured -- not a multiple
      // of the font size, which read high and folded bars that had room to
      // spare, and a bar that is always a menu is no better than one that is
      // always cut.
      Future<bool> foldedAt(double width) async {
        await tester.pumpWidget(wrap(SizedBox(
            width: width,
            child: DefaultTextStyle(
                style: const TextStyle(fontSize: 30),
                child: MarkdownArea(banner, false)))));
        await tester.pump();
        return find.byIcon(Icons.menu).evaluate().isNotEmpty;
      }

      expect(await foldedAt(1000), isFalse,
          reason: "a banner at full size has room for its links");
      expect(await foldedAt(420), isTrue,
          reason: "a banner scaled down has a row too short for them");

      // And what folded is still reachable.
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.text("About"), findsOneWidget);
    });

    testWidgets('both folded menus keep the same room at their own edge',
        (tester) async {
      // One of them was taking the bar's own padding and the other a
      // fallback, so a fully folded bar sat four pixels further in on one
      // side than the other -- which on a bar that is two icons and a gap is
      // most of what there is to look at.
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(SizedBox(
          width: 300,
          child: MarkdownArea(
              "--nav[pills]--\n"
              "[Home](index.md)\n[About](about.md)\n[Store](store)\n"
              "--right--\n"
              "[Shop](/store)[icon=shop, label=off]\n"
              "[Cart](/cart)[icon=cart, label=off, badge=1]\n"
              "--/nav--\n",
              false))));
      await tester.pump();

      var bar = tester.getRect(find.byType(MarkdownArea).first);
      var burger = tester.getRect(find.byIcon(Icons.menu));
      var shop = tester.getRect(find.byIcon(Icons.storefront_outlined));

      expect(burger.left - bar.left, closeTo(bar.right - shop.right, 0.5));
    });

    testWidgets('narrow enough, the second group folds into a menu',
        (tester) async {
      // A row of six links on a phone is not a bar, it is three rows of two
      // -- and the group that can be given up is the shop's, not the site's.
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          wrap(SizedBox(width: 380, child: MarkdownArea(bar, false))));
      await tester.pump();

      expect(find.text("Home"), findsOneWidget,
          reason: "the site's own links stay");
      expect(find.text("Shop"), findsNothing);
      // No icons on these links, so the menu falls back to three dots.
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);

      // What is waiting behind the menu is still visible while it is shut.
      expect(find.text("2"), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      expect(find.text("Shop"), findsOneWidget);
      expect(find.text("Orders"), findsOneWidget);
    });
  });
}
