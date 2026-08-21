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

    Future<Rect> titleIn(WidgetTester tester, String words) async {
      // One width throughout: a banner scales with the room it has, so
      // measuring two widths would be measuring that instead of this.
      await tester.pumpWidget(drawHost(MarkdownArea("""
--header--
--row[60,left]--
# $words
--/row--
--/header--
""", false), width: 900));
      await tester.pump();
      return tester.getRect(find.text(words));
    }

    testWidgets('keeps its height, and loses width instead', (tester) async {
      // The whole point of fixing a row's height: shrinking the letters
      // would change how tall the writing looks and undo it. Squeezing them
      // keeps the cap height and loses only the width.
      var short = await titleIn(tester, "Short");
      var long = await titleIn(tester,
          "A very much longer title than will ever fit across this banner");

      expect(long.height, moreOrLessEquals(short.height, epsilon: 2));
      expect(long.width, greaterThan(short.width));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a short one is not stretched to fill the row', (tester) async {
      var once = await titleIn(tester, "Hi");
      var again = await titleIn(tester, "Hi");
      expect(again.width, moreOrLessEquals(once.width, epsilon: 1));
    });
  });

  group('an outline round the letters', () {
    test('reads a width and a colour, bounded', () {
      var st = HeaderTextStyle.parse({
        "titleoutline": "3",
        "titleoutlinecolor": "#ffffff",
      });
      expect(st.outline, 3);
      expect(st.outlineColor, const Color(0xffffffff));
      expect(HeaderTextStyle.parse({"titleoutline": "99"}).outline, 12);
    });

    test('and takes a gradient, as the fill does', () {
      var st = HeaderTextStyle.parse({"titleoutlinegradient": "#f00,#00f"});
      expect(st.outlineGradient, hasLength(2));
      // One colour is a colour, not a gradient -- the same rule the fill
      // follows, so the two read alike.
      var one = HeaderTextStyle.parse({"titleoutlinegradient": "#f00"});
      expect(one.outlineGradient, isEmpty);
      expect(one.outlineColor, const Color(0xffff0000));
    });

    test('is distinct from the box round the whole title', () {
      // titleborder draws a box; titleoutline draws round the letters.
      var st = HeaderTextStyle.parse(
          {"titleoutline": "2", "titleborder": "4"});
      expect(st.outline, 2);
      expect(st.borderWidth, 4);
    });

    test('counts as something said about the title', () {
      expect(HeaderTextStyle.parse({"titleoutline": "2"}).plain, isFalse);
    });
  });

  group('an outlined title is drawn', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('as the words twice, stroke under fill', (tester) async {
      // A stroke sits half inside the letter, so painting it over the fill
      // would eat into it. Underneath, only the outer half shows.
      await tester.pumpWidget(drawHost(MarkdownArea("""
--header--
titleoutline: 2
titleoutlinecolor: #ffffff
--row[60,left]--
# My site
--/row--
--/header--
""", false)));
      await tester.pump();

      expect(find.text("My site"), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('and once when there is no outline', (tester) async {
      await tester.pumpWidget(drawHost(MarkdownArea("""
--header--
--row[60,left]--
# My site
--/row--
--/header--
""", false)));
      await tester.pump();
      expect(find.text("My site"), findsOneWidget);
    });
  });
}
