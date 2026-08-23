import 'package:bruig/components/feed/markdown_nav.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/models/payments.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/model/markdown_style.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'header_harness.dart';

// markdown_nav_test.dart covers a bar of links: what it reads, and where
// in a banner it ends up.

void main() {
  group('what a page says about one bar', () {
    // The theme decides how bars look, and that is where it belongs: a
    // reader who has set their Markdown theme should see every page in it.
    // But where a bar sits and how far it is from what is above it is the
    // page's business. So what is written wins for that bar, and what is
    // left out falls through to the theme.
    /// barIn is the bar's own Wrap, not the paragraph's.
    ///
    /// The renderer puts every block in a paragraph and a paragraph draws
    /// its contents in a Wrap of its own, so the first Wrap on the page
    /// belongs to the paragraph and answers nothing about the bar.
    Finder navBar() => find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == "_MarkdownNav");

    Future<Wrap> barIn(WidgetTester tester, String src) async {
      await tester.pumpWidget(drawHost(MarkdownArea(src, false)));
      await tester.pumpAndSettle();
      return tester.widget<Wrap>(
          find.descendant(of: navBar(), matching: find.byType(Wrap)).first);
    }

    testWidgets('align runs the links that way', (tester) async {
      var left = await barIn(tester,
          "--nav[pills, align=left]--\n[Home](index.md)\n--/nav--");
      expect(left.alignment, WrapAlignment.start);

      var middle = await barIn(tester,
          "--nav[pills, align=center]--\n[Home](index.md)\n--/nav--");
      expect(middle.alignment, WrapAlignment.center);

      var right = await barIn(tester,
          "--nav[pills, align=right]--\n[Home](index.md)\n--/nav--");
      expect(right.alignment, WrapAlignment.end);
    });

    testWidgets('middle is not the only answer any more', (tester) async {
      // Running the background the whole way across used to centre the
      // links with it, so a bar asked for as a strip along an edge could
      // not also be a strip that starts at the left.
      var bar = await barIn(tester,
          "--nav[pills, width=full, align=left]--\n[Home](index.md)\n--/nav--");
      expect(bar.alignment, WrapAlignment.start);
    });

    testWidgets('gap is the space between links', (tester) async {
      var tight =
          await barIn(tester, "--nav[gap=4]--\n[Home](index.md)\n--/nav--");
      var wide =
          await barIn(tester, "--nav[gap=30]--\n[Home](index.md)\n--/nav--");
      expect(tight.spacing, 4);
      expect(wide.spacing, 30);
      expect(wide.spacing, greaterThan(tight.spacing));
    });

    testWidgets('a bar that says nothing is the bar it always was',
        (tester) async {
      // The whole bargain: settings left out fall through to the theme, so
      // every page written before any of this could be said is unchanged.
      var plain = await barIn(tester, "--nav--\n[Home](index.md)\n--/nav--");
      var styled =
          await barIn(tester, "--nav[pills]--\n[Home](index.md)\n--/nav--");
      expect(plain.spacing, styled.spacing);
      expect(plain.alignment, styled.alignment);
    });

    testWidgets('margin moves the bar rather than growing it',
        (tester) async {
      // Outside the background: padding would grow the strip instead of
      // keeping it away from what is above.
      //
      // Measured from the bar's own top to what it draws, not from the page
      // to the bar. The margin is applied inside the widget, so the widget
      // sits where it always did and only its contents move -- the same
      // thing that made a banner's margin impossible to catch.
      Future<double> insetOf(String src) async {
        await tester.pumpWidget(drawHost(MarkdownArea(src, false)));
        await tester.pumpAndSettle();
        var drawn =
            find.descendant(of: navBar(), matching: find.byType(Wrap)).first;
        return tester.getTopLeft(drawn).dy - tester.getTopLeft(navBar()).dy;
      }

      var without = await insetOf("--nav--\n[Home](index.md)\n--/nav--");
      var withMargin =
          await insetOf("--nav[margin=20]--\n[Home](index.md)\n--/nav--");
      expect(withMargin - without, 20);
    });
  });

  group('NavBlockSyntax', () {
    test('one link a line, in order', () {
      var e = parseBlock('''
--nav--
[Home](index.md)
[About](about.md)
--/nav--
''', NavBlockSyntax());

      expect(e.attributes["count"], "2");
      expect(e.attributes["l0"], "[Home](index.md)");
      expect(e.attributes["l1"], "[About](about.md)");
      expect(e.attributes["style"], "plain");
    });

    test('the writer picks the shape', () {
      for (var s in NavStyle.values) {
        var e = parseBlock(
            "--nav[${s.name}]--\n[a](a.md)\n--/nav--", NavBlockSyntax());
        expect(e.attributes["style"], s.name);
      }
    });

    test('an unknown shape falls back rather than failing', () {
      var e =
          parseBlock("--nav[sparkly]--\n[a](a.md)\n--/nav--", NavBlockSyntax());
      expect(e.attributes["style"], "plain");
    });

    test('blank lines are not links', () {
      var e = parseBlock(
          "--nav--\n[a](a.md)\n\n\n[b](b.md)\n--/nav--", NavBlockSyntax());
      expect(e.attributes["count"], "2");
    });

    test('a bar stops being navigation past a point', () {
      var many = List.generate(40, (i) => "[$i]($i.md)").join("\n");
      var e = parseBlock("--nav--\n$many\n--/nav--", NavBlockSyntax());
      expect(int.parse(e.attributes["count"]!), NavBlockSyntax.maxLinks);
    });
  });



  group('a bar in a banner', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('is a row like any other, placed the way a row is',
        (tester) async {
      // What used to be a "nav" field with a "navat" beside it. A bar has
      // nothing special about it now: it is a fragment in a row, and where
      // it sits is the row's business.
      await tester.pumpWidget(drawHost(MarkdownArea("""
--header--
--row[60,left]--
# Site
--/row--
--row[40,center]--
--nav[pills]--
[Home](index.md)
--/nav--
--/row--
--/header--
""", false), width: 1000));
      await tester.pump();

      var site = tester.getRect(find.text("Site"));
      var home = tester.getRect(find.text("Home"));

      // The second row is under the first, and centred across it.
      expect(home.top, greaterThan(site.top));
      var banner = tester.getRect(find
          .ancestor(of: find.text("Home"), matching: find.byType(ClipRRect))
          .first);
      expect(home.center.dx, moreOrLessEquals(banner.center.dx, epsilon: 4));
      expect(tester.takeException(), isNull);
    });
  });

  group('a link in a bar', () {
    test('is split into its label and where it goes', () {
      var got = navLink("[Home](index.md)");
      expect(got!.label, "Home");
      expect(got.target, "index.md");
    });

    test('handles a br:// address, which has a colon in it', () {
      expect(navLink("[Theirs](br://abc123/index.md)")!.target,
          "br://abc123/index.md");
    });

    test('anything that is not a link is left alone', () {
      // Shown as written rather than dropped, so a typo is visible instead
      // of silently costing an entry.
      expect(navLink("Home"), isNull);
      expect(navLink("[Home]"), isNull);
      expect(navLink(""), isNull);
    });
  });

  group('the rules survive being saved', () {
    test('a bar round-trips, colours and all', () {
      const r = NavRule(
        gap: 20,
        padding: 10,
        ink: MarkdownInk.of(MarkdownRole.accent),
        hover: MarkdownInk.of(MarkdownRole.link),
        active: MarkdownInk.of(MarkdownRole.quote),
        background: MarkdownInk.of(MarkdownRole.raised),
        fullWidth: false,
      );
      expect(NavRule.fromJson(r.toJson()), r);
    });

    test('a guide written before any of them still loads', () {
      var guide = MarkdownStyleGuide.fromJson({"id": "x", "name": "X"});
      // Inherit, so a bar looks like the rest of the writing and the
      // setting reads "Theme default" rather than a colour nobody chose.
      expect(guide.nav.ink.isInherit, isTrue);
      expect(guide.nav.hover.isInherit, isTrue);
      expect(guide.nav.active.isInherit, isTrue);
      expect(guide.nav.background.isInherit, isTrue);
    });
  });

  group('the page being read', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<TextStyle> styleOf(WidgetTester tester, String label,
        {String? here}) async {
      Widget bar = MarkdownArea("""
--nav--
[Home](index.md)
[About](about.md)
--/nav--
""", false);
      if (here != null) bar = NavCurrentPage(path: here, child: bar);
      await tester.pumpWidget(drawHost(bar));
      await tester.pump();
      return tester.widget<Text>(find.text(label)).style!;
    }

    testWidgets('is marked, and the others are not', (tester) async {
      var home = await styleOf(tester, "Home", here: "index.md");
      var about = await styleOf(tester, "About", here: "index.md");
      expect(home.fontWeight, FontWeight.bold);
      expect(about.fontWeight, FontWeight.normal);
    });

    testWidgets('is matched however the page was reached', (tester) async {
      // A bar written as "[Home](index.md)" is the same link whether the
      // page was opened by that name or by a whole br:// address, and a
      // writer should not have to write it twice.
      var home = await styleOf(tester, "Home", here: "br://abc123/index.md");
      expect(home.fontWeight, FontWeight.bold);
    });

    testWidgets('nothing is marked outside a page', (tester) async {
      // A bar in a post has no page being read, and marks nothing.
      var home = await styleOf(tester, "Home");
      expect(home.fontWeight, FontWeight.normal);
      expect(tester.takeException(), isNull);
    });
  });
}
