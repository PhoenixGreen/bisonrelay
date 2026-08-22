import 'package:bruig/components/feed/markdown_page.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/models/payments.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// page_setup_test.dart covers what a page says about itself: how wide it is,
// what it sits on, and how much room it keeps around itself.
//
// Stated in the page rather than in a panel beside it, because the page bytes
// are the only thing that reaches a reader. See markdown_page.dart.

void main() {
  group('reading what a page asked for', () {
    test('a page that says nothing asks for nothing', () {
      expect(PageSetup.parse("# Just a page"), PageSetup.none);
      expect(PageSetup.parse("# Just a page").saysAnything, isFalse);
    });

    test('the settings it states', () {
      var got = PageSetup.parse(
          "--page--\nwidth: 800\nbackground: raised\npadding: 24\n--/page--");
      expect(got.width, 800);
      expect(got.background, PageBackground.raised);
      expect(got.padding, const EdgeInsets.all(24));
    });

    test('a unit is allowed, because people write one', () {
      // "800" and "800px" mean the same thing to anyone typing them, and a
      // page that went full width because of a "px" would be a puzzle.
      expect(PageSetup.parse("--page--\nwidth: 800px\n--/page--").width, 800);
    });

    test('a width it cannot have is brought back to one it can', () {
      expect(PageSetup.parse("--page--\nwidth: 40000\n--/page--").width,
          maxPageWidth);
    });

    test('a width of nothing is no width at all', () {
      // Rather than a page one pixel wide.
      expect(PageSetup.parse("--page--\nwidth: 0\n--/page--").width, isNull);
      expect(PageSetup.parse("--page--\nwidth: wide\n--/page--").width, isNull);
    });

    test('a background it does not recognise is none, not a guess', () {
      expect(PageSetup.parse("--page--\nbackground: #ff0000\n--/page--")
          .background, PageBackground.none);
    });

    test('a setting it does not know is left alone', () {
      // A typo shows up as itself rather than silently doing nothing
      // somewhere else.
      expect(PageSetup.parse("--page--\nwdith: 800\n--/page--"),
          PageSetup.none);
    });

    test('nothing outside the block is read as part of it', () {
      var got = PageSetup.parse(
          "width: 200\n--page--\nwidth: 800\n--/page--\nwidth: 400");
      expect(got.width, 800);
    });

    test('the first block wins', () {
      // A page with two is an author changing their mind in writing. The one
      // at the top is the one anybody would look at.
      var got = PageSetup.parse(
          "--page--\nwidth: 800\n--/page--\n--page--\nwidth: 400\n--/page--");
      expect(got.width, 800);
    });
  });

  group('room around a page', () {
    EdgeInsets? space(String value) =>
        PageSetup.parse("--page--\npadding: $value\n--/page--").padding;

    test('one number is every side', () {
      expect(space("24"), const EdgeInsets.all(24));
    });

    test('two is down-and-up, then across', () {
      expect(space("12 24"),
          const EdgeInsets.symmetric(vertical: 12, horizontal: 24));
    });

    test('four is each side from the top, going clockwise', () {
      expect(space("1 2 3 4"), const EdgeInsets.fromLTRB(4, 1, 2, 3));
    });

    test('commas are allowed, because people write them', () {
      expect(space("12, 24"),
          const EdgeInsets.symmetric(vertical: 12, horizontal: 24));
    });

    test('one bad number spoils the set rather than half-applying', () {
      // Half a margin is worse than none: it is a page that looks wrong in
      // one direction only, which is the hardest kind to work out.
      expect(space("12 wide"), isNull);
    });
  });

  group('the block itself', () {
    testWidgets('is not left on the page as writing', (tester) async {
      // It is also the first line of the page, which is where it belongs and
      // which is the case that used to throw.
      // It says something about the page, not about the place it sits. Left
      // unconsumed it renders as itself, and the reader sees "--page--" and
      // "width: 800" at the top of every page.
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(MultiProvider(providers: [
        ChangeNotifierProvider<ThemeNotifier>(create: (_) => ThemeNotifier()),
        ChangeNotifierProvider<PaymentsModel>(create: (_) => PaymentsModel()),
        ChangeNotifierProvider<MarkdownAreaModel>(
            create: (_) => MarkdownAreaModel("")),
      ], child: MaterialApp(
          home: Scaffold(
              body: MarkdownArea(
                  "--page--\nwidth: 800\nbackground: raised\n--/page--\n"
                  "# Title",
                  false)))));
      await tester.pumpAndSettle();

      var shown = find
          .byType(RichText)
          .evaluate()
          .map((e) => (e.widget as RichText).text.toPlainText())
          .join(" ");
      expect(shown, contains("Title"));
      expect(shown, isNot(contains("--page--")));
      expect(shown, isNot(contains("width")));
      expect(shown, isNot(contains("background")));
    });
  });

  group('what the reader allows', () {
    const asked = PageSetup(width: 800);

    double? widthOf(PageSetup setup, double? cap) =>
        PageFrame(setup: setup, cap: cap, child: const SizedBox()).width;

    test('a page gets what it asked for when there is no cap', () {
      expect(widthOf(asked, null), 800);
    });

    test('a cap narrower than the page wins', () {
      expect(widthOf(asked, 600), 600);
    });

    test('a cap wider than the page does not widen it', () {
      // A ceiling, not a measurement. A reader who caps at 1200 has not
      // asked for every narrow page to be stretched to 1200.
      expect(widthOf(asked, 1200), 800);
    });

    test('a cap applies to a page that asked for nothing', () {
      expect(widthOf(PageSetup.none, 900), 900);
    });
  });
}
