import 'package:bruig/components/feed/markdown_title.dart';
import 'package:bruig/components/feed/markdown_header.dart';
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

// markdown_title_test.dart covers how a banner's words are set -- the half
// of a header whose look belongs to whoever wrote the site.

void main() {
  group('the rules survive being saved', () {
    test('a header round-trips', () {
      const r =
          HeaderRule(height: 300, padding: 24, radius: 12, gap: 16, scrim: 0.5);
      expect(HeaderRule.fromJson(r.toJson()), r);
    });

    test('a bar round-trips', () {
      const r = NavRule(gap: 20, padding: 10, radius: 99, borderWidth: 2);
      expect(NavRule.fromJson(r.toJson()), r);
    });

    test('a guide written before either existed still loads', () {
      var guide = MarkdownStyleGuide.fromJson({"id": "x", "name": "X"});
      expect(guide.header, const HeaderRule());
      expect(guide.nav, const NavRule());
    });

    test('bounds keep a guide from setting something unusable', () {
      expect(const HeaderRule(height: 5000).boundedHeight, 600);
      expect(const HeaderRule(height: 1).boundedHeight, 40);
      expect(const NavRule(radius: 999).boundedRadius, 32);
    });
  });

  group('how a title is set', () {
    test('reads the fields, and bounds what it reads', () {
      var st = HeaderTextStyle.parse({
        "titlesize": "48",
        "titleweight": "bold",
        "titleitalic": "yes",
        "titlecase": "upper",
        "titletracking": "3",
        "titlebackground": "#00000080",
        "titleborder": "2",
        "titlebordercolor": "#fff",
      });
      expect(st.size, 48);
      expect(st.bold, isTrue);
      expect(st.italic, isTrue);
      expect(st.tracking, 3);
      expect(st.borderWidth, 2);
      expect(st.background?.a, closeTo(0.5, 0.01),
          reason: "#rrggbbaa, so a background can be see-through");
      expect(st.border, const Color(0xffffffff));
    });

    test('"fill" makes a title as tall as the room it has', () {
      // Which is what makes it sit level with a logo and scale with it.
      var st = HeaderTextStyle.parse({"titlesize": "fill"});
      expect(st.fill, isTrue);
      expect(st.size, isNull);
    });

    test('case changes the words, not how they are drawn', () {
      // So what is copied out of the page is what was written.
      expect(HeaderTextStyle.parse({"titlecase": "upper"}).apply("My site"),
          "MY SITE");
      expect(HeaderTextStyle.parse({"titlecase": "lower"}).apply("My Site"),
          "my site");
      expect(HeaderTextStyle.parse({}).apply("My Site"), "My Site");
    });

    test('a gradient needs two colours; one is just a colour', () {
      expect(HeaderTextStyle.parse({"titlegradient": "#f00,#00f"}).gradient,
          hasLength(2));
      var one = HeaderTextStyle.parse({"titlegradient": "#f00"});
      expect(one.gradient, isEmpty);
      expect(one.color, const Color(0xffff0000));
    });

    test('a colour it cannot read leaves what it would have replaced', () {
      var st = HeaderTextStyle.parse({"titlecolor": "reddish"});
      expect(st.color, isNull);
    });

    test('nothing said means nothing done', () {
      expect(HeaderTextStyle.parse({}).plain, isTrue);
      expect(HeaderTextStyle.parse({"titlecase": "upper"}).plain, isFalse);
    });

    test('sizes and spacing are bounded', () {
      expect(HeaderTextStyle.parse({"titlesize": "9999"}).size, 200);
      expect(HeaderTextStyle.parse({"titletracking": "500"}).tracking, 40);
      expect(HeaderTextStyle.parse({"titleborder": "99"}).borderWidth, 16);
    });
  });

  group('a styled title is drawn', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('with the case applied and the heading marks dropped',
        (tester) async {
      await tester.pumpWidget(drawHost(MarkdownArea("""
--header[200]--
middle: ## My site
titlecase: upper
titlesize: 40
titleweight: bold
titlegradient: #ff0000,#0000ff
titlebackground: #00000040
titleborder: 2
titlebordercolor: #ffffff
--/header--
""", false)));
      await tester.pump();

      // How large a title is set is titlesize, not how many hashes were
      // typed -- two of them in a banner would otherwise be small.
      expect(find.text("MY SITE"), findsOneWidget);
      expect(find.textContaining("##"), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('a title told to fill', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<Rect> titleRect(WidgetTester tester, String extra) async {
      await tester.pumpWidget(drawHost(MarkdownArea("""
--header[200]--
left: # Logo
right: # Title
$extra
--/header--
""", false)));
      await tester.pump();
      return tester.getRect(find.text("Title"));
    }

    testWidgets('is taller than one left alone', (tester) async {
      // A FittedBox only scales a child down into a box larger than it, and
      // a slot's constraints are loose -- so "fill" used to size itself to
      // the words and do nothing at all.
      var plain = await titleRect(tester, "");
      var filled = await titleRect(tester, "titlesize: fill");
      expect(filled.height, greaterThan(plain.height));
    });

    testWidgets('matches the logo when the logo has a height', (tester) async {
      var filled = await titleRect(tester, "logosize: 80\ntitlesize: fill");
      // The point of the pair: set both and they come out level.
      expect(filled.height, moreOrLessEquals(80, epsilon: 2));
    });

    testWidgets('takes the row when the logo has none', (tester) async {
      var filled = await titleRect(tester, "titlesize: fill");
      // The banner is 200 less its padding, which is what a logo without a
      // height of its own also takes.
      expect(filled.height, greaterThan(100));
      expect(tester.takeException(), isNull);
    });
  });
}
