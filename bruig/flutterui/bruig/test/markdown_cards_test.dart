import 'package:bruig/components/md_elements.dart';
import 'package:bruig/models/payments.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// markdown_cards_test.dart covers callouts and cards, which are one thing
// with a different amount filled in: a title, some text, an icon and a
// button, any of which may be left out.
//
// The syntax is fielded rather than markdown-inside-the-card, because a
// card's parts are named things. That also decides how it degrades: a reader
// whose app does not know it sees labelled lines in the order they were
// written, which is still the card, just not drawn.

const _callout = """
--card--
icon: info
title: A callout
text: What it says.
--/card--
""";

Widget _host(Widget child, {double width = 900}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<PaymentsModel>(create: (c) => PaymentsModel()),
        ChangeNotifierProvider<MarkdownAreaModel>(
            create: (c) => MarkdownAreaModel("/tmp")),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: width, child: child),
            ),
          ),
        ),
      ),
    );

Future<void> _pump(WidgetTester tester, String markdown,
    {double width = 900, MarkdownStyleGuide? guide}) async {
  await tester.pumpWidget(
      _host(MarkdownArea(markdown, false, guide: guide), width: width));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group("a callout", () {
    testWidgets("shows its title, text and icon", (tester) async {
      await _pump(tester, _callout);
      expect(find.text("A callout"), findsOneWidget);
      expect(find.text("What it says."), findsOneWidget);
      expect(find.byIcon(MarkdownCardIcon.info.icon), findsOneWidget);
    });

    testWidgets("the field markers are not shown", (tester) async {
      await _pump(tester, _callout);
      expect(find.textContaining("--card"), findsNothing);
      expect(find.textContaining("title:"), findsNothing);
    });

    // Every field is optional: a callout with only text is a card with one
    // field, not a broken one.
    testWidgets("a field left out is simply absent", (tester) async {
      await _pump(tester, "--card--\ntext: Only this.\n--/card--");
      expect(find.text("Only this."), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // A name this app has not heard of draws no icon rather than a guess at
    // one -- the vocabulary is closed for the same reason every other choice
    // in a guide is.
    testWidgets("an unknown icon draws none", (tester) async {
      await _pump(tester, "--card--\nicon: rocket\ntitle: T\n--/card--");
      expect(find.text("T"), findsOneWidget);
      expect(find.byType(Icon), findsNothing);
    });

    // A description is a paragraph and wraps in the source like one.
    testWidgets("a wrapped field is joined back up", (tester) async {
      await _pump(tester,
          "--card--\ntext: The first part\n  and the second part.\n--/card--");
      expect(find.text("The first part and the second part."), findsOneWidget);
    });

    testWidgets("a button with a link is live, one without is not",
        (tester) async {
      await _pump(
          tester,
          "--card--\ntitle: T\nbutton: Go\nlink: https://decred.org\n"
          "--/card--\n\n--card--\ntitle: U\nbutton: Nowhere\n--/card--");
      var live = tester.widget<ElevatedButton>(find.ancestor(
          of: find.text("Go"), matching: find.byType(ElevatedButton)));
      var dead = tester.widget<ElevatedButton>(find.ancestor(
          of: find.text("Nowhere"), matching: find.byType(ElevatedButton)));
      expect(live.onPressed, isNotNull);
      expect(dead.onPressed, isNull,
          reason: "a button with nowhere to go is not a button");
    });
  });

  group("a grid of cards", () {
    testWidgets("two across share the width", (tester) async {
      await _pump(
          tester,
          "--cards[2]--\n--card--\ntitle: One\n--/card--\n"
          "--card--\ntitle: Two\n--/card--\n--/cards--");
      var one = tester.getRect(find.text("One"));
      var two = tester.getRect(find.text("Two"));
      expect(two.left, greaterThan(one.left));
      expect(two.top, closeTo(one.top, 1), reason: "side by side, not stacked");
    });

    testWidgets("a third card starts a second row", (tester) async {
      await _pump(
          tester,
          "--cards[2]--\n--card--\ntitle: One\n--/card--\n"
          "--card--\ntitle: Two\n--/card--\n"
          "--card--\ntitle: Three\n--/card--\n--/cards--");
      expect(tester.getRect(find.text("Three")).top,
          greaterThan(tester.getRect(find.text("One")).top));
    });

    // Two across and three down. Past that a card in a post-width column is
    // narrower than the words in it.
    testWidgets("past six cards the rest are dropped", (tester) async {
      var cards = [
        for (var i = 0; i < 9; i++) "--card--\ntitle: Card $i\n--/card--"
      ].join("\n");
      await _pump(tester, "--cards[2]--\n$cards\n--/cards--");
      expect(find.text("Card 5"), findsOneWidget);
      expect(find.text("Card 6"), findsNothing);
    });

    test("the limits are two across and three down", () {
      expect(CardsBlockSyntax.maxColumns, 2);
      expect(CardsBlockSyntax.maxRows, 3);
      expect(CardsBlockSyntax.maxCards, 6);
    });

    testWidgets("more columns than allowed is clamped, not refused",
        (tester) async {
      await _pump(
          tester,
          "--cards[5]--\n--card--\ntitle: One\n--/card--\n"
          "--card--\ntitle: Two\n--/card--\n--/cards--");
      expect(tester.getRect(find.text("Two")).top,
          closeTo(tester.getRect(find.text("One")).top, 1));
    });
  });

  group("the guide draws the box", () {
    Future<BoxDecoration?> boxOf(WidgetTester tester, CardRule rule) async {
      var guide = builtInGuideFor(defaultGuideId)!.copyWith(cards: rule);
      await _pump(tester, _callout, guide: guide);
      for (var c in tester.widgetList<Container>(find.byType(Container))) {
        var d = c.decoration;
        if (d is BoxDecoration && d.borderRadius != null) return d;
      }
      return null;
    }

    testWidgets("the background, border and corners are the guide's",
        (tester) async {
      var box = await boxOf(
          tester,
          const CardRule(
            background: MarkdownInk.literal(Color(0xFF223344)),
            borderWidth: 2,
            borderInk: MarkdownInk.literal(Color(0xFF667788)),
            radius: 20,
          ));
      expect(box?.color, const Color(0xFF223344));
      expect(box?.borderRadius, BorderRadius.circular(20));
      expect((box?.border as Border?)?.top.width, 2);
    });

    testWidgets("the icon takes its size and colour from the guide",
        (tester) async {
      var guide = builtInGuideFor(defaultGuideId)!.copyWith(
          cards: const CardRule(
              iconSize: 40, iconInk: MarkdownInk.literal(Color(0xFFFF0000))));
      await _pump(tester, _callout, guide: guide);
      var icon = tester.widget<Icon>(find.byIcon(MarkdownCardIcon.info.icon));
      expect(icon.size, 40);
      expect(icon.color, const Color(0xFFFF0000));
    });

    test("every card setting survives being saved", () {
      var cards = const CardRule(
        gap: 24,
        padding: 20,
        background: MarkdownInk.of(MarkdownRole.raised),
        borderWidth: 3,
        radius: 8,
        iconSize: 44,
        iconBackground: MarkdownInk.of(MarkdownRole.accent),
      );
      var guide =
          const MarkdownStyleGuide(id: "x", name: "X").copyWith(cards: cards);
      expect(MarkdownStyleGuide.fromJson(guide.toJson()).cards, cards);
    });
  });
}
