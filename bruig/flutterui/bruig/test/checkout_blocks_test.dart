import 'package:bruig/components/feed/markdown_copy.dart';
import 'package:bruig/components/feed/markdown_panel.dart';
import 'package:bruig/components/feed/markdown_paynow.dart';
import 'package:bruig/components/feed/markdown_qr.dart';
import 'package:bruig/components/feed/markdown_paypick.dart';
import 'package:bruig/components/tooltips.dart';
import 'package:bruig/components/feed/markdown_steps.dart';
import 'package:bruig/components/feed/markdown_wallet.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/models/payments.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// checkout_blocks_test.dart covers the three blocks the shop's checkout
// added: the trail across the top of each step, the box that copies a payment
// address when pressed, and the one that says what the reader's own wallet
// can do.
//
// All three are markup a shop writes and this app draws, so what is worth
// checking is the seam between them: that the markers do not leak onto the
// page as text, that what a shop wrote is what a buyer can act on, and that
// each of them draws nothing rather than something wrong when the page did
// not say enough.

// tall is for the stacked layouts: the test surface is 600 points high, and
// a pay area with one half under the other is taller than that. It overflows
// the harness, not the app.
Widget _host(Widget child, {double width = 800, bool tall = false}) =>
    MultiProvider(
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
            child: tall
                ? SingleChildScrollView(
                    child: SizedBox(width: width, child: child))
                : SizedBox(width: width, child: child),
          ),
        ),
      ),
    );

Future<void> _pump(WidgetTester tester, String markdown,
    {double width = 800, bool tall = false}) async {
  await tester.pumpWidget(
      _host(MarkdownArea(markdown, false), width: width, tall: tall));
  await tester.pump();
}

const _trail = """
--steps[on=checkout]--
Checkout
[Cart](/cart) | [Checkout](/checkout) | [Review](/review) | Pay
--/steps--
""";

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group("the trail", () {
    test("reads the title and the steps off its two lines", () {
      var rule = StepsRule.parse(
          "on=review", "Review your order\nCart | Checkout | Review | Pay");
      expect(rule.title, "Review your order");
      expect([for (var s in rule.steps) s.label],
          ["Cart", "Checkout", "Review", "Pay"]);
      expect(rule.on, 2);
    });

    // A step written as a Markdown link is one you can go back to, and it
    // still reads as a line of words to a client that does not know the
    // block.
    test("reads a step written as a link", () {
      var rule = StepsRule.parse(
          "on=review", "Review\n[Cart](/cart) | Checkout | Review");
      expect(rule.steps.first.label, "Cart");
      expect(rule.steps.first.target, "/cart");
      expect(rule.steps[1].target, "");
    });

    // Matched on the words rather than on a number, so a page that adds or
    // drops a step cannot silently mark the wrong one.
    test("marks nothing when the step named is not in the trail", () {
      var rule = StepsRule.parse("on=delivery", "Checkout\nCart | Pay");
      expect(rule.on, -1);
    });

    test("is case-insensitive about which step it is on", () {
      var rule = StepsRule.parse("on=CART", "Shopping Cart\nCart | Pay");
      expect(rule.on, 0);
    });

    testWidgets("draws the title and every step", (tester) async {
      await _pump(tester, _trail);
      for (var word in ["Checkout", "Cart", "Review", "Pay"]) {
        expect(find.text(word), findsWidgets, reason: "$word is missing");
      }
    });

    testWidgets("does not show its own markers", (tester) async {
      await _pump(tester, _trail);
      expect(find.textContaining("--steps"), findsNothing);
      expect(find.textContaining("|"), findsNothing);
    });

    // The point of the block: they share a line. A heading with the trail
    // under it is what columns would have given, and is what this replaces.
    testWidgets("puts the trail beside the title when there is room",
        (tester) async {
      await _pump(tester, _trail, width: 800);
      var title = tester.getRect(find.text("Checkout").first);
      var last = tester.getRect(find.text("Pay"));
      expect(last.left, greaterThan(title.right),
          reason: "the trail should sit to the right of the title");
      expect((last.center.dy - title.center.dy).abs(), lessThan(12),
          reason: "the trail should sit on the title's line");
    });

    // Four words and three separators do not fit beside a heading in a
    // chat-width window, and squeezing them makes the trail taller than the
    // title it was meant to sit beside.
    testWidgets("drops the trail under the title in a narrow window",
        (tester) async {
      await _pump(tester, _trail, width: 360);
      var title = tester.getRect(find.text("Checkout").first);
      var last = tester.getRect(find.text("Pay"));
      expect(last.top, greaterThan(title.top));
    });
  });

  group("the copy box", () {
    const address = """
--copy[label=Payment address]--
DsExampleAddress0123456789
--/copy--
""";

    testWidgets("shows the label and what will be copied", (tester) async {
      await _pump(tester, address);
      expect(find.text("Payment address"), findsOneWidget);
      expect(find.text("DsExampleAddress0123456789"), findsOneWidget);
      expect(find.textContaining("--copy"), findsNothing);
    });

    // The whole box is the button, not an icon at the end of it: the thing
    // somebody reaches for is the address, because they are already pointing
    // at it.
    testWidgets("copies when the address itself is pressed", (tester) async {
      var copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        if (call.method == "Clipboard.setData") {
          copied.add(call.arguments["text"] as String);
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await _pump(tester, address);
      await tester.tap(find.text("DsExampleAddress0123456789"));
      await tester.pump();

      expect(copied, ["DsExampleAddress0123456789"]);
    });

    testWidgets("draws nothing when there is nothing to copy", (tester) async {
      await _pump(tester, "--copy[label=Address]--\n--/copy--\n");
      expect(find.byType(MarkdownCopy), findsOneWidget);
      expect(find.text("Address"), findsNothing);
    });
  });

  group("the wallet block", () {
    test("reads the amount and which halves to draw", () {
      var rule = WalletRule.parse("need=0.31000000, show=ln onchain");
      expect(rule.need, closeTo(0.31, 1e-9));
      expect(rule.showLN, isTrue);
      expect(rule.showOnChain, isTrue);
    });

    // A shop that takes one kind of payment must not report on the other: an
    // on-chain balance beside a Lightning-only shop reads as "you have
    // enough" to a buyer whose only route is a channel that is short.
    test("draws only the halves the shop takes", () {
      var ln = WalletRule.parse("need=1, show=ln");
      expect(ln.showLN, isTrue);
      expect(ln.showOnChain, isFalse);

      var chain = WalletRule.parse("need=1, show=onchain");
      expect(chain.showLN, isFalse);
      expect(chain.showOnChain, isTrue);
    });

    // Nought is not an amount to measure a balance against, and neither is a
    // shop with no exchange rate: both mean the page has nothing to judge.
    test("treats a missing or empty amount as nothing to judge", () {
      expect(WalletRule.parse("show=ln").need, isNull);
      expect(WalletRule.parse("need=, show=ln").need, isNull);
      expect(WalletRule.parse("need=0, show=ln").need, isNull);
    });

    // A wallet that will not answer is not a wallet that cannot pay. In a
    // test there is no golib to ask, so the block must come out empty rather
    // than saying something it does not know -- "we could not read your
    // balance" on a checkout page reads as a problem with the shop.
    testWidgets("says nothing when the wallet does not answer",
        (tester) async {
      await _pump(tester, "--wallet[need=0.31000000, show=ln onchain]--\n");
      await tester.pump();
      expect(find.byType(MarkdownWallet), findsOneWidget);
      expect(find.textContaining("Your wallet"), findsNothing);
      expect(find.textContaining("--wallet"), findsNothing);
    });
  });

  group("the payment cards", () {
    const cards = """
--paypick[action=/setCheckout, chosen=ln]--
--option[method=ln, icon=lightning, label=Lightning]--
Settles straight away.
--option[method=onchain, icon=onchain, label=On-chain]--
Settles after one confirmation.
--/paypick--
""";

    test("reads each option and the one already chosen", () {
      var rule = PayPickRule.parse("action=/setCheckout, chosen=onchain", """
--option[method=ln, icon=lightning, label=Lightning]--
Settles straight away.
--option[method=onchain, icon=onchain, label=On-chain]--
Settles after one confirmation.
""");
      expect(rule.action, "/setCheckout");
      expect(rule.chosen, "onchain");
      expect(rule.options.length, 2);
      expect(rule.options.first.label, "Lightning");
      expect(rule.options.first.help, "Settles straight away.");
      expect(rule.options.last.method, "onchain");
    });

    testWidgets("draws a title and an icon, and not the description",
        (tester) async {
      await _pump(tester, cards);
      expect(find.text("Lightning"), findsOneWidget);
      expect(find.text("On-chain"), findsOneWidget);
      expect(find.byIcon(Icons.bolt), findsOneWidget);
      // The words are behind the question mark, not printed under the title.
      expect(find.text("Settles straight away."), findsNothing);
      expect(find.byIcon(Icons.help_outline), findsNWidgets(2));
    });

    testWidgets("says which one is chosen", (tester) async {
      await _pump(tester, cards);
      expect(find.text("Chosen"), findsOneWidget);
      expect(find.text("Choose"), findsOneWidget);
    });

    // Everything that makes it read as a choice is a fact about the pair.
    testWidgets("draws both cards the same size", (tester) async {
      await _pump(tester, cards);
      var first = tester.getRect(find.byType(InkWell).first);
      var second = tester.getRect(find.byType(InkWell).last);
      expect(first.width, second.width);
      expect(first.height, second.height,
          reason: "a longer word on one card must not make the pair uneven");
    });

    testWidgets("keeps the pair together in the middle of a wide page",
        (tester) async {
      await _pump(tester, cards, width: 700);
      var block = tester.getRect(find.byType(MarkdownPayPick));
      var left = tester.getRect(find.byType(InkWell).first);
      var right = tester.getRect(find.byType(InkWell).last);
      expect(left.left - block.left, greaterThan(100),
          reason: "the cards should not stretch to the page edges");
      expect((block.center.dx - (left.left + right.right) / 2).abs(),
          lessThan(2),
          reason: "the pair should sit in the middle");
    });

    testWidgets("stacks them when there is no room to sit side by side",
        (tester) async {
      await _pump(tester, cards, width: 300);
      var first = tester.getRect(find.byType(InkWell).first);
      var second = tester.getRect(find.byType(InkWell).last);
      expect(second.top, greaterThan(first.top));
    });

    testWidgets("does not show its own markers", (tester) async {
      await _pump(tester, cards);
      expect(find.textContaining("--option"), findsNothing);
      expect(find.textContaining("--paypick"), findsNothing);
    });

    // A Stack sizes itself to its largest unpositioned child and lays it out
    // loosely, so the column came out as wide as its longest line and sat
    // against the left edge with everything centred inside that. Two cards
    // whose longest lines differ then had their marks in two different
    // places -- off-centre by however much the words differed.
    testWidgets("centres what is on a card against the card", (tester) async {
      await _pump(tester, cards);

      for (var (word, icon) in [
        ("Lightning", Icons.bolt),
        ("On-chain", Icons.link_rounded),
      ]) {
        var card = tester.getRect(find.ancestor(
            of: find.text(word), matching: find.byType(InkWell)));
        for (var part in [find.text(word), find.byIcon(icon)]) {
          expect((tester.getRect(part).center.dx - card.center.dx).abs(),
              lessThan(1),
              reason: "$word: something on the card is off its centre");
        }
      }
    });

    // Both cards are the same width, so the two marks must line up with each
    // other as well as with their own cards.
    testWidgets("puts both marks the same distance in", (tester) async {
      await _pump(tester, cards);
      var left = tester.getRect(find.ancestor(
          of: find.text("Lightning"), matching: find.byType(InkWell)));
      var right = tester.getRect(find.ancestor(
          of: find.text("On-chain"), matching: find.byType(InkWell)));
      var bolt = tester.getRect(find.byIcon(Icons.bolt));
      var link = tester.getRect(find.byIcon(Icons.link_rounded));

      expect((bolt.center.dx - left.center.dx).abs(), lessThan(1));
      expect((link.center.dx - right.center.dx).abs(), lessThan(1));
    });
  });

  group("the paying-with row", () {
    testWidgets("runs the full width with the mark on the right",
        (tester) async {
      await _pump(
          tester,
          "--paysummary[icon=lightning, label=Paying with, value=Lightning, "
          "link=/checkout, linklabel=Change]--\n",
          width: 600);
      expect(find.text("Paying with"), findsOneWidget);
      expect(find.text("Lightning"), findsOneWidget);
      expect(find.text("Change"), findsOneWidget);

      var row = tester.getRect(find.byType(MarkdownPaySummary));
      expect(row.width, 600);
      var label = tester.getRect(find.text("Paying with"));
      var mark = tester.getRect(find.byIcon(Icons.bolt));
      expect(mark.left, greaterThan(label.right));
    });
  });

  group("the pay-now button", () {
    test("reads the address and the amount", () {
      var rule = PayNowRule.parse("addr=DsAddr, amount=0.31000000");
      expect(rule.addr, "DsAddr");
      expect(rule.amount, closeTo(0.31, 1e-9));
      expect(rule.account, "default");
      expect(rule.draws, isTrue);
    });

    // This button never asks how much, so a page that does not say cannot
    // have one -- and neither can a page that names no address.
    test("draws nothing without both an address and an amount", () {
      expect(PayNowRule.parse("addr=DsAddr").draws, isFalse);
      expect(PayNowRule.parse("amount=0.31").draws, isFalse);
      expect(PayNowRule.parse("addr=DsAddr, amount=0").draws, isFalse);
    });

    testWidgets("says what it will send", (tester) async {
      await _pump(tester, "--paynow[addr=DsAddr, amount=0.31000000]--\n");
      expect(find.text("Pay with your Bison Relay wallet"), findsOneWidget);
      // The zeros nobody reads are dropped, and nothing is rounded away.
      expect(find.textContaining("0.31 DCR"), findsOneWidget);
      expect(find.textContaining("--paynow"), findsNothing);
    });
  });

  group("the on-chain pay area", () {
    const area = "--payways[addr=DsAddr, amount=0.31000000, dcr=0.3100 DCR]--\n";

    testWidgets("offers a square, an address and this app's own wallet",
        (tester) async {
      await _pump(tester, area, width: 800);
      expect(find.text("Pay with an external Decred wallet"), findsOneWidget);
      expect(find.text("DsAddr"), findsOneWidget);
      expect(find.text("Pay with your Bison Relay wallet"), findsOneWidget);
      expect(find.byType(MarkdownQr), findsOneWidget);
      expect(find.textContaining("--payways"), findsNothing);
    });

    // The square encodes the amount as well as the address: an order is paid
    // by sending exactly what it was quoted, and an address on its own leaves
    // that to be typed in by hand.
    test("encodes the address and the amount together", () {
      var rule = PayWaysRule(
          pay: PayNowRule.parse("addr=DsAddr, amount=0.31"), dcr: "0.3100 DCR");
      expect(rule.uri, "decred:DsAddr?amount=0.31000000");
    });

    // A choice whose halves are different sizes reads as one option and one
    // afterthought.
    testWidgets("draws both halves the same height", (tester) async {
      await _pump(tester, area, width: 800);
      var left = tester.getRect(find.byKey(payWaysExternal));
      var right = tester.getRect(find.byKey(payWaysInternal));
      expect(right.height, closeTo(left.height, 12),
          reason: "the button should be as tall as the area beside it");
      expect(right.left, greaterThan(left.left));
    });

    testWidgets("puts one under the other in a narrow window", (tester) async {
      await _pump(tester, area, width: 380, tall: true);
      var title = tester.getRect(find.text("Pay with an external Decred wallet"));
      var button = tester.getRect(find.text("Pay with your Bison Relay wallet"));
      expect(button.top, greaterThan(title.top));
      expect(find.byType(IntrinsicHeight), findsNothing);
    });
  });

  group("the checkout heading", () {
    const cards = """
--paypick[title=How would you like to pay?, action=/setCheckout, chosen=ln]--
--option[method=ln, icon=lightning, label=Lightning, note=Settles straight away]--
Settles straight away.
--option[method=onchain, icon=onchain, label=On-chain, note=About five minutes]--
Settles after one confirmation.
--/paypick--
""";

    test("reads the title and each option's note", () {
      var rule = PayPickRule.parse(
          "title=How would you like to pay?, chosen=ln",
          "--option[method=ln, label=Lightning, note=Instant]--\nWords.\n");
      expect(rule.title, "How would you like to pay?");
      expect(rule.options.single.note, "Instant");
    });

    // A question at one edge of the page over two cards in the middle of it
    // reads as two separate things.
    testWidgets("centres the question over the cards", (tester) async {
      await _pump(tester, cards, width: 700);
      var title = tester.getRect(find.text("How would you like to pay?"));
      var block = tester.getRect(find.byType(MarkdownPayPick));
      var left = tester.getRect(find.byType(InkWell).first);
      var right = tester.getRect(find.byType(InkWell).last);

      expect(block.width, 700, reason: "the block should fill the page");
      expect((title.center.dx - block.center.dx).abs(), lessThan(2));
      expect((title.center.dx - (left.left + right.right) / 2).abs(),
          lessThan(2),
          reason: "the question and the cards should share a centre");
    });

    // The choice is made on how long it takes, so that is on the card rather
    // than behind the question mark.
    testWidgets("says how long each way takes, on the card", (tester) async {
      await _pump(tester, cards);
      expect(find.text("Settles straight away"), findsOneWidget);
      expect(find.text("About five minutes"), findsOneWidget);
      // And the longer explanation is still not on the page.
      expect(find.text("Settles after one confirmation."), findsNothing);
    });

    // Hiding the app's own tooltips must leave these alone, and hiding these
    // must leave the app's labels alone -- which is the whole reason
    // hideHelpTooltips is a setting of its own.
    testWidgets("puts the description on the help-text setting",
        (tester) async {
      await _pump(tester, cards);
      var tip = tester.widget<HelpTooltip>(find.byType(HelpTooltip).first);
      expect(tip.message, "Settles straight away.");
      expect(tip.triggerMode, TooltipTriggerMode.tap);
    });
  });

  group("waiting for a confirmation", () {
    test("reads the order to move on to", () {
      var rule = PayNowRule.parse(
          "addr=DsAddr, amount=0.31000000, order=/order/00000001");
      expect(rule.order, "/order/00000001");
    });

    // Sent and confirmed are two states, not one. A button that says "Sent"
    // and then nothing stops talking exactly when the buyer starts wondering.
    testWidgets("says it is waiting once the coins have gone", (tester) async {
      await _pump(
          tester,
          "--paynow[addr=DsAddr, amount=0.31000000, order=/order/1]--\n",
          tall: true);

      // No golib in a test, so the send fails rather than sending -- which is
      // the other half of the promise: a failed send says so and stays
      // pressable.
      await tester.tap(find.text("Pay with your Bison Relay wallet"));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text("That did not go through"), findsOneWidget);
    });
  });

  group("a panel's ribbon", () {
    const sold = """
--panel[padding=12, border=1, color=outline, radius=8, badge=Sold out]--
A guitar
--/panel--
""";

    test("is read off the panel's own settings", () {
      var rule = PanelRule.parse("padding=12, badge=Sold out");
      expect(rule.badge, "Sold out");
      expect(PanelRule.parse("padding=12").badge, "");
    });

    testWidgets("draws the word over the panel", (tester) async {
      await _pump(tester, sold);
      expect(find.text("Sold out"), findsOneWidget);
      expect(find.text("A guitar"), findsOneWidget);
      expect(find.textContaining("badge="), findsNothing);
    });

    // A fact about the whole card, pinned to its corner -- not a line inside
    // it competing with the title.
    testWidgets("pins it to the top right", (tester) async {
      await _pump(tester, sold, width: 400);
      var panel = tester.getRect(find.byType(MarkdownPanel).first);
      var badge = tester.getRect(find.text("Sold out"));
      expect(badge.right, lessThanOrEqualTo(panel.right + 1));
      expect(panel.right - badge.right, lessThan(30));
      expect(badge.top - panel.top, lessThan(30));
    });

    // It must not push the card around: a shop front where the sold-out card
    // is a different height from the ones beside it looks broken rather than
    // out of stock.
    testWidgets("changes nothing about the panel's size", (tester) async {
      await _pump(tester, sold, width: 400);
      var withBadge = tester.getRect(find.byType(MarkdownPanel).first);

      await _pump(tester, sold.replaceFirst(", badge=Sold out", ""),
          width: 400);
      var without = tester.getRect(find.byType(MarkdownPanel).first);

      expect(withBadge.size, without.size);
    });
  });

  group("a title with a chip", () {
    const chipped = """
--steps[chip=2 left, chipink=quoteBar]--
A guitar
--/steps--
""";

    test("is read off the same block as the trail", () {
      var rule = StepsRule.parse("chip=2 left, chipink=quoteBar", "A guitar");
      expect(rule.title, "A guitar");
      expect(rule.chip, "2 left");
      expect(rule.steps, isEmpty);
      expect(rule.draws, isTrue);
    });

    testWidgets("draws the title and the chip", (tester) async {
      await _pump(tester, chipped);
      expect(find.text("A guitar"), findsOneWidget);
      expect(find.text("2 left"), findsOneWidget);
      expect(find.textContaining("--steps"), findsNothing);
      expect(find.textContaining("chip="), findsNothing);
    });

    testWidgets("puts it beside the title, on its line", (tester) async {
      await _pump(tester, chipped, width: 700);
      var title = tester.getRect(find.text("A guitar"));
      var chip = tester.getRect(find.text("2 left"));
      expect(chip.left, greaterThan(title.right));
      expect((chip.center.dy - title.center.dy).abs(), lessThan(12));
    });

    // Next to the title, not at the far edge. Pushed right it reads as a
    // second thing on the line rather than as a remark about the name it is
    // next to -- and on a wide page there is a lot of nothing in between for
    // it to be read across.
    testWidgets("leaves a little room and no more", (tester) async {
      await _pump(tester, chipped, width: 700);
      var title = tester.getRect(find.text("A guitar"));
      var box = tester.getRect(find.ancestor(
          of: find.text("2 left"), matching: find.byType(Container)));

      expect(box.left - title.right, greaterThan(4));
      expect(box.left - title.right, lessThan(24));
      expect(box.right, lessThan(400),
          reason: "the chip should follow the title, not the page's edge");
    });

    // Held to its own size, so the title takes the rest of the line: a box
    // stretched across the gap stops looking like a label.
    testWidgets("keeps the chip small", (tester) async {
      await _pump(tester, chipped, width: 700);
      var box = tester.getRect(find.ancestor(
          of: find.text("2 left"), matching: find.byType(Container)));
      expect(box.width, lessThan(120));
    });

    testWidgets("puts it under the title in a narrow window", (tester) async {
      await _pump(tester, chipped, width: 360);
      var title = tester.getRect(find.text("A guitar"));
      var chip = tester.getRect(find.text("2 left"));
      expect(chip.top, greaterThan(title.top));
      expect(chip.left, lessThan(80),
          reason: "folded, it reads from the left like everything else");
    });

    // The checkout trail is not a chip and must not become one.
    testWidgets("leaves the trail alone", (tester) async {
      await _pump(tester, _trail);
      expect(find.text("Cart"), findsOneWidget);
      expect(find.text("Pay"), findsOneWidget);
    });
  });

  group("a panel that fills the page", () {
    const short = """
--panel[padding=12, border=1, color=outline, radius=8]--
Ada
--/panel--
""";

    test("is off unless the page asks", () {
      expect(PanelRule.parse("padding=12").full, isFalse);
      expect(PanelRule.parse("padding=12, full=on").full, isTrue);
      expect(PanelRule.parse("padding=12, full=yes").full, isTrue);
      expect(PanelRule.parse("padding=12, full=off").full, isFalse);
    });

    // A block is laid out loosely by the column a page is built from, so a
    // panel is as wide as what is in it -- right for a card in a grid, and
    // wrong for a panel that is a section of a page.
    testWidgets("takes the whole width when it does", (tester) async {
      await _pump(tester, short, width: 600);
      var narrow = tester.getRect(find.byType(MarkdownPanel).first).width;

      await _pump(tester, short.replaceFirst("radius=8", "radius=8, full=on"),
          width: 600);
      var wide = tester.getRect(find.byType(MarkdownPanel).first).width;

      expect(narrow, lessThan(200), reason: "a short panel should shrink-wrap");
      expect(wide, 600);
    });
  });

  group("an address", () {
    // Markdown joins consecutive lines into a paragraph. Two trailing spaces
    // are its own hard break, which is what the shop writes between the
    // lines of an address.
    testWidgets("is drawn one thing per line", (tester) async {
      await _pump(
          tester, "Ada Lovelace  \n1 Long Road  \nCanterbury, Kent, CT1 1AA\n");

      var name = tester.getRect(find.textContaining("Ada Lovelace",
          findRichText: true));
      expect(name.height, greaterThan(40),
          reason: "three lines, not one paragraph run together");
    });
  });

  group("a panel's question mark", () {
    const asked = """
--panel[full=on, padding=12, border=1, color=outline, help=A phone number is for whoever delivers this, not for the seller.]--
Ada
--/panel--
""";

    // Every other value on a panel is a number or a word, so splitting on
    // commas was enough until one could carry prose -- and prose has commas
    // in it.
    test("keeps a sentence whole, commas and all", () {
      var rule = PanelRule.parse(
          "padding=12, help=A phone number is for the courier, not the seller., border=1");
      expect(rule.help, "A phone number is for the courier, not the seller.");
      expect(rule.padding, isNotNull);
      expect(rule.border, isNotNull);
    });

    testWidgets("keeps the words behind the mark", (tester) async {
      await _pump(tester, asked, width: 600);
      expect(find.byIcon(Icons.help_outline), findsOneWidget);
      expect(find.textContaining("phone number"), findsNothing);
      expect(find.textContaining("help="), findsNothing);
      expect(find.text("Ada"), findsOneWidget);
    });

    // On the app's own help-text setting, not the blanket tooltip one:
    // hiding the labels leaves these alone, and hiding these leaves the
    // labels alone.
    testWidgets("is one of the app's help icons", (tester) async {
      await _pump(tester, asked, width: 600);
      var tip = tester.widget<HelpTooltip>(find.byType(HelpTooltip));
      expect(tip.message,
          "A phone number is for whoever delivers this, not for the seller.");
      expect(tip.triggerMode, TooltipTriggerMode.tap);
    });

    testWidgets("pins it to the top right", (tester) async {
      await _pump(tester, asked, width: 600);
      var panel = tester.getRect(find.byType(MarkdownPanel).first);
      var mark = tester.getRect(find.byIcon(Icons.help_outline));
      expect(panel.right - mark.right, lessThan(30));
      expect(mark.top - panel.top, lessThan(30));
    });

    // A panel can carry both. The ribbon is the louder of the two and keeps
    // the corner.
    testWidgets("sits inside a ribbon when there is one", (tester) async {
      await _pump(tester, asked.replaceFirst("color=outline", "color=outline, badge=Sold out"),
          width: 600);
      var mark = tester.getRect(find.byIcon(Icons.help_outline));
      var badge = tester.getRect(find.text("Sold out"));
      expect(mark.right, lessThan(badge.left));
    });
  });

  group("stepping back", () {
    // The way back, in place of a row of links at the foot of the page
    // saying the same thing the trail already showed.
    testWidgets("makes the steps behind you pressable", (tester) async {
      await _pump(tester, _trail);
      var links = find.descendant(
          of: find.byType(MarkdownSteps), matching: find.byType(InkWell));
      expect(tester.widgetList(links).length, 1,
          reason: "only Cart is behind Checkout");
      expect(
          find.descendant(of: links, matching: find.text("Cart")), findsOneWidget);
    });

    // Going forward past a question you have not answered is what the
    // sequence exists to prevent, and a step you are already on is not
    // somewhere to go.
    testWidgets("leaves the current step and the ones ahead alone",
        (tester) async {
      await _pump(tester, _trail.replaceFirst("on=checkout", "on=cart"));
      expect(
          tester
              .widgetList(find.descendant(
                  of: find.byType(MarkdownSteps), matching: find.byType(InkWell)))
              .length,
          0,
          reason: "nothing is behind the first step");
    });

    testWidgets("never links a step that names nowhere", (tester) async {
      await _pump(tester, _trail.replaceFirst("on=checkout", "on=pay"));
      var links = find.descendant(
          of: find.byType(MarkdownSteps), matching: find.byType(InkWell));
      expect(tester.widgetList(links).length, 3,
          reason: "Cart, Checkout and Review are behind Pay; Pay itself is on");
    });
  });

  group("a warning border", () {
    // The markdown roles are about a document -- text, quotes, links, lines.
    // A warning is about the reader's own theme, which has a colour for it.
    test("is a word rather than a role", () {
      expect(PanelRule.parse("border=1, color=error").colorIsError, isTrue);
      expect(PanelRule.parse("border=1, color=ERROR").colorIsError, isTrue);
      expect(PanelRule.parse("border=1, color=accent").colorIsError, isFalse);
      expect(PanelRule.parse("border=1").colorIsError, isFalse);
    });

    testWidgets("draws the line in the theme's error colour", (tester) async {
      await _pump(
          tester,
          "--panel[full=on, padding=12, border=1, color=error]--\n"
          "The amount holds for another 25 minutes.\n--/panel--\n",
          width: 600);

      var theme = Provider.of<ThemeNotifier>(
          tester.element(find.byType(MarkdownPanel).first),
          listen: false);
      var box = tester.widgetList<DecoratedBox>(find.descendant(
          of: find.byType(MarkdownPanel),
          matching: find.byType(DecoratedBox)));
      var lines = [
        for (var b in box)
          if ((b.decoration as BoxDecoration).border != null)
            ((b.decoration as BoxDecoration).border as Border).top.color,
      ];
      expect(lines, contains(theme.colors.error));
    });
  });

  group("the pay area's question marks", () {
    const area = "--payways[addr=DsAddr, amount=0.31000000, dcr=0.3100 DCR, "
        "help=The shop watches for your payment, and marks the order when the "
        "network confirms it.]--\n";

    testWidgets("puts one on each half", (tester) async {
      await _pump(tester, area, width: 800);
      expect(find.byIcon(Icons.help_outline), findsNWidgets(2));
      expect(find.textContaining("watches for your payment"), findsNothing);
    });

    // The sentence has a comma in it, and attributes are separated by
    // commas: the whole of it has to survive the parse.
    testWidgets("carries the whole sentence", (tester) async {
      await _pump(tester, area, width: 800);
      var tip = tester.widget<HelpTooltip>(find.byType(HelpTooltip).first);
      expect(tip.message,
          "The shop watches for your payment, and marks the order when the "
          "network confirms it.");
      expect(tip.triggerMode, TooltipTriggerMode.tap);
    });
  });

  group("a panel that centres its writing", () {
    const card = """
--panel[full=on, padding=16, border=1, color=accent, radius=8, text=center]--
**Pay with your Bison Relay wallet**
--/panel--
""";

    // MarkdownBody sizes every block to its own content, so a paragraph is as
    // wide as its longest line and sits at the left -- and a textAlign of
    // centre inside a box exactly as wide as the words has nothing to centre
    // them in.
    testWidgets("actually centres it", (tester) async {
      await _pump(tester, card, width: 600);
      var panel = tester.getRect(find.byType(MarkdownPanel).first);
      var words = tester.getRect(find.textContaining(
          "Pay with your Bison Relay wallet",
          findRichText: true));

      expect(panel.width, 600, reason: "the panel should fill the page");
      expect((words.center.dx - panel.center.dx).abs(), lessThan(2));
    });

    // Where nobody asked, nothing changes: shrink-wrapping is right for a
    // caption under a picture and for a plate behind a price.
    testWidgets("leaves a panel that asked for nothing alone", (tester) async {
      await _pump(tester, card.replaceFirst(", text=center", ""), width: 600);
      var panel = tester.getRect(find.byType(MarkdownPanel).first);
      var words = tester.getRect(find.textContaining(
          "Pay with your Bison Relay wallet",
          findRichText: true));
      expect(words.center.dx, lessThan(panel.center.dx));
    });
  });
}
