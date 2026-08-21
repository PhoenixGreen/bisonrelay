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
}
