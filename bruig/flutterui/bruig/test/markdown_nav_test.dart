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

  group('where the bar sits', () {
    test('reads both words, in either order', () {
      expect(NavPlacement.parse("bottom middle"),
          const NavPlacement(atTop: false, across: Alignment.center));
      expect(NavPlacement.parse("middle bottom"),
          const NavPlacement(atTop: false, across: Alignment.center));
      expect(NavPlacement.parse("top right"),
          const NavPlacement(atTop: true, across: Alignment.centerRight));
    });

    test('either word may be left out', () {
      // "top" on its own was the whole of this field before, and still
      // means what it did.
      expect(NavPlacement.parse("top").atTop, isTrue);
      expect(NavPlacement.parse("top").across, Alignment.centerLeft);
      expect(NavPlacement.parse("middle").atTop, isFalse);
      expect(NavPlacement.parse("middle").across, Alignment.center);
    });

    test('nothing at all is the bottom left', () {
      expect(NavPlacement.parse(null),
          const NavPlacement(atTop: false, across: Alignment.centerLeft));
      expect(NavPlacement.parse(""), NavPlacement.parse(null));
    });

    test('spelt either way', () {
      expect(NavPlacement.parse("center"), NavPlacement.parse("centre"));
      expect(
          NavPlacement.parse("TOP MIDDLE"), NavPlacement.parse("top middle"));
    });

    test('a word it does not know is ignored, not fatal', () {
      expect(NavPlacement.parse("top sideways").atTop, isTrue);
    });
  });

  group('the bar is drawn where it was put', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<Rect> barRect(WidgetTester tester, String navat) async {
      await tester.pumpWidget(drawHost(MarkdownArea("""
--header[200]--
left: # Logo
nav: [Home](index.md)
navat: $navat
--/header--
""", false)));
      await tester.pump();
      return tester.getRect(find.text("Home"));
    }

    testWidgets('top puts it above the slots, bottom below', (tester) async {
      var logo = () => tester.getRect(find.text("Logo"));

      var top = await barRect(tester, "top");
      expect(top.top, lessThan(logo().top),
          reason: "asked for the top and drawn below the logo");

      var bottom = await barRect(tester, "bottom");
      expect(bottom.top, greaterThan(logo().top));
    });

    testWidgets('and across where it was asked for', (tester) async {
      var left = await barRect(tester, "bottom left");
      var middle = await barRect(tester, "bottom middle");
      var right = await barRect(tester, "bottom right");

      expect(middle.left, greaterThan(left.left));
      expect(right.left, greaterThan(middle.left));
      expect(tester.takeException(), isNull);
    });
  });
}
