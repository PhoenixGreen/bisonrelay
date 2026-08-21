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

    test('no size given leaves it to the row', () {
      // A row is a fixed height and everything in it is set to that, so a
      // title comes out level with the logo beside it without either being
      // told about the other.
      expect(HeaderTextStyle.parse({}).size, isNull);
      expect(HeaderTextStyle.parse({"titlesize": "40"}).size, 40);
    });

    test('a picture can fill the letters, as colours can', () {
      var st = HeaderTextStyle.parse(
          {"titleimage": "--embed[type=image/png,data=AAAA]--"});
      expect(st.image, isNotNull);
      expect(st.plain, isFalse);
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
--header--
titlecase: upper
titleweight: bold
titlegradient: #ff0000,#0000ff
titlebackground: #00000040
titleborder: 2
titlebordercolor: #ffffff
--row[80,center]--
## My site
--/row--
--/header--
""", false)));
      await tester.pump();

      // How large a title is set is the row's height, not how many hashes
      // were typed -- two of them in a banner would otherwise be small.
      expect(find.text("MY SITE"), findsOneWidget);
      expect(find.textContaining("##"), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });


  group('a title too long for its row', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<Rect> titleIn(WidgetTester tester, String words,
        {double width = 1000}) async {
      await tester.pumpWidget(drawHost(MarkdownArea("""
--header--
--row[60,left]--
# $words
--/row--
--/header--
""", false), width: width));
      await tester.pump();
      return tester.getRect(find.text(words));
    }

    testWidgets('keeps its height, and loses width instead', (tester) async {
      // The whole point of fixing a row's height: shrinking the letters
      // would change how tall the writing looks and undo it. Squeezing them
      // keeps the cap height and loses only the width.
      var roomy = await titleIn(tester, "Short");
      var cramped = await titleIn(
          tester, "A very much longer title than will ever fit across here",
          width: 300);

      expect(cramped.height, moreOrLessEquals(roomy.height, epsilon: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a short one is not stretched to fill the row', (tester) async {
      var narrow = await titleIn(tester, "Hi", width: 400);
      var wide = await titleIn(tester, "Hi", width: 1200);
      expect(wide.width, moreOrLessEquals(narrow.width, epsilon: 1));
    });
  });
}
