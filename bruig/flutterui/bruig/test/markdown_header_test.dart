import 'package:bruig/components/feed/markdown_header.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/models/payments.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bruig/theming_system/model/markdown_style.dart';
import 'package:markdown/markdown.dart' as md;

// markdown_header_test.dart covers a site's furniture: the banner at the top
// of a page and the bar of links usually in it.
//
// Both are fielded, so what is tested here is how the fields are read and
// how the slots across a header are shared out -- which is the part with a
// rule in it rather than a layout.

md.Element _parse(String src, md.BlockSyntax syntax) {
  var doc = md.Document(blockSyntaxes: [syntax]);
  var nodes = doc.parseLines(src.trim().split("\n"));
  return (nodes.first as md.Element).children!.first as md.Element;
}

Widget _drawHost(Widget child, {double width = 900}) => MultiProvider(
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
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );

void main() {
  group('headerSpans', () {
    test('a slot grows into the empty ones after it', () {
      // Logo left, title middle: the title takes the right-hand space too,
      // because there is nothing to its right to keep it out of.
      expect(headerSpans({"left": "logo", "middle": "title"}), [1, 2, 0]);
    });

    test('two at the ends leave the middle open between them', () {
      // Which is the shape somebody writing exactly those two means.
      expect(headerSpans({"left": "logo", "right": "title"}), [1, 0, 1]);
    });

    test('one on its own takes the whole width, wherever it sits', () {
      expect(headerSpans({"middle": "title"}), [0, 3, 0]);
      expect(headerSpans({"left": "logo"}), [3, 0, 0]);
      expect(headerSpans({"right": "title"}), [0, 0, 3]);
    });

    test('the last named slot absorbs what is left at the end', () {
      expect(headerSpans({"middle": "a", "right": "b"}), [0, 1, 1]);
    });

    test('all three take one each', () {
      expect(
          headerSpans({"left": "a", "middle": "b", "right": "c"}), [1, 1, 1]);
    });

    test('an empty value is not a slot', () {
      expect(headerSpans({"left": "a", "middle": ""}), [3, 0, 0]);
    });

    test('the spans always add up to the width', () {
      for (var f in [
        {"left": "a"},
        {"left": "a", "middle": "b"},
        {"left": "a", "right": "c"},
        {"middle": "b", "right": "c"},
        {"left": "a", "middle": "b", "right": "c"},
      ]) {
        var spans = headerSpans(f);
        // Empty columns between named slots are drawn as a flexible gap of
        // one, so the total is the width either way.
        var gaps = spans
            .sublist(0, spans.lastIndexOf(spans.lastWhere((s) => s > 0)))
            .where((s) => s == 0)
            .length;
        expect(spans.reduce((a, b) => a + b) + gaps, headerSlots.length,
            reason: "$f gave $spans");
      }
    });

    test('none at all is no slots', () {
      expect(headerSpans({}), [0, 0, 0]);
    });
  });

  group('HeaderBlockSyntax', () {
    test('reads its fields and its height', () {
      var e = _parse('''
--header[300]--
background: --embed[type=image/png,data=AAAA]--
left: ![](logo)
right: # My Site
description: What it is for.
nav: --include[navigation]--
navat: top
--/header--
''', HeaderBlockSyntax());

      expect(e.tag, "header");
      expect(e.attributes["height"], "300");
      expect(e.attributes["right"], "# My Site");
      expect(e.attributes["navat"], "top");
      expect(e.attributes["description"], "What it is for.");
    });

    test('without a height the reader\'s theme decides', () {
      var e = _parse("--header--\nleft: hi\n--/header--", HeaderBlockSyntax());
      expect(e.attributes["height"], isNull);
    });

    test('a height is bounded to something that is still a banner', () {
      expect(
          _parse("--header[5000]--\nleft: a\n--/header--", HeaderBlockSyntax())
              .attributes["height"],
          "${HeaderBlockSyntax.maxHeight}");
      expect(
          _parse("--header[1]--\nleft: a\n--/header--", HeaderBlockSyntax())
              .attributes["height"],
          "40");
    });

    test('a field can be several lines, which is what a bar is', () {
      // "nav: --include[bar]--" is replaced with the whole of that fragment
      // before this is parsed, so a field that stopped at one line kept the
      // first line of a navigation bar and threw the links away.
      var e = _parse('''
--header--
nav: --nav[pills]--
[Home](index.md)
[About](about.md)
--/nav--
right: # My site
--/header--
''', HeaderBlockSyntax());

      expect(e.attributes["nav"], contains("[Home](index.md)"));
      expect(e.attributes["nav"], contains("[About](about.md)"));
      expect(e.attributes["nav"], contains("--/nav--"));
      // And the field after it is still its own.
      expect(e.attributes["right"], "# My site");
    });

    test('a colon in a value does not start a new field', () {
      // Which is most lines of a bar: "[Home](br://...)" has one.
      var e = _parse('''
--header--
nav: [Home](br://abc123/index.md)
[Notes](notes.md)
--/header--
''', HeaderBlockSyntax());

      expect(e.attributes["nav"], contains("br://abc123/index.md"));
      expect(e.attributes["nav"], contains("[Notes](notes.md)"));
    });

    test('a line before any field is not kept', () {
      var e = _parse(
          "--header--\nstray text\nleft: hi\n--/header--", HeaderBlockSyntax());
      expect(e.attributes["left"], "hi");
      expect(e.attributes.values, isNot(contains("stray text")));
    });

    test('an unterminated header still renders what was written', () {
      var e = _parse("--header--\nleft: hi", HeaderBlockSyntax());
      expect(e.attributes["left"], "hi");
    });
  });

  group('embedImage', () {
    test('takes the picture and its kind out of an inline embed', () {
      var got = embedImage("--embed[type=image/png,data=AAAA]--");
      expect(got, isNotNull);
      expect(got!.bytes.length, 3);
      // The kind matters: a vector needs a different decoder, and guessing
      // from the bytes is guessing at something the writer already knew.
      expect(got.mime, "image/png");
    });

    test('a vector keeps its kind so it can be drawn as one', () {
      var got = embedImage("--embed[type=image/svg+xml,data=AAAA]--");
      expect(got!.mime, "image/svg+xml");
      expect(isSvgMime(got.mime), isTrue);
    });

    test('anything that is not an inline image is simply not drawn', () {
      expect(embedImage(null), isNull);
      expect(embedImage("photo.png"), isNull);
      expect(embedImage("--embed[type=application/pdf,data=AAAA]--"), isNull);
      expect(embedImage("--embed[type=image/png]--"), isNull);
      // A reference the document still carries while it is being written,
      // rather than the picture itself.
      expect(
          embedImage("--embed[type=image/png,data=[content abcdefghijkl]]--"),
          isNull);
    });
  });

  group('isSvgMime', () {
    test('recognises what a vector is declared as', () {
      expect(isSvgMime("image/svg+xml"), isTrue);
      expect(isSvgMime("IMAGE/SVG+XML"), isTrue);
      expect(isSvgMime("image/svg"), isTrue);
    });

    test('and nothing else', () {
      expect(isSvgMime("image/png"), isFalse);
      expect(isSvgMime("image/webp"), isFalse);
      expect(isSvgMime(""), isFalse);
    });
  });

  group('NavBlockSyntax', () {
    test('one link a line, in order', () {
      var e = _parse('''
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
        var e =
            _parse("--nav[${s.name}]--\n[a](a.md)\n--/nav--", NavBlockSyntax());
        expect(e.attributes["style"], s.name);
      }
    });

    test('an unknown shape falls back rather than failing', () {
      var e = _parse("--nav[sparkly]--\n[a](a.md)\n--/nav--", NavBlockSyntax());
      expect(e.attributes["style"], "plain");
    });

    test('blank lines are not links', () {
      var e = _parse(
          "--nav--\n[a](a.md)\n\n\n[b](b.md)\n--/nav--", NavBlockSyntax());
      expect(e.attributes["count"], "2");
    });

    test('a bar stops being navigation past a point', () {
      var many = List.generate(40, (i) => "[$i]($i.md)").join("\n");
      var e = _parse("--nav--\n$many\n--/nav--", NavBlockSyntax());
      expect(int.parse(e.attributes["count"]!), NavBlockSyntax.maxLinks);
    });
  });

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

  group('where a slot sits in itself', () {
    test('a middle beside a logo hugs the logo', () {
      // Centring it in the space it grew into would put the title further
      // from the logo than writing it on the right would have.
      expect(headerSlotAlignment({"left": "logo", "middle": "title"}, 1),
          Alignment.centerLeft);
    });

    test('a middle with nothing to its left is centred', () {
      expect(headerSlotAlignment({"middle": "title"}, 1), Alignment.center);
    });

    test('the ends sit at their ends', () {
      expect(headerSlotAlignment({"left": "a"}, 0), Alignment.centerLeft);
      expect(headerSlotAlignment({"right": "c"}, 2), Alignment.centerRight);
      // Even alone, so "right" means right.
      expect(headerSlotAlignment({"right": "c"}, 2), Alignment.centerRight);
    });

    test('the three slots give three distances from the logo', () {
      // Which is what makes having three worth it: next to it, centred,
      // and against the far edge.
      var withLogo = {"left": "logo", "middle": "m", "right": "r"};
      expect(headerSlotAlignment(withLogo, 1), Alignment.centerLeft);
      expect(headerSlotAlignment(withLogo, 2), Alignment.centerRight);
      expect(headerSlotAlignment({"middle": "m"}, 1), Alignment.center);
    });
  });

  group('drawn', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Widget host(Widget child, {double width = 900}) =>
        _drawHost(child, width: width);

    // Note on what these can and cannot catch: a picture does not decode in
    // a widget test, so an embed lays out as nothing and a banner holding
    // only a logo cannot overflow here however wrong the layout is. Text
    // does lay out, which is what the narrow case below leans on -- checked
    // against the version that shipped the overflow, where it fails.

    testWidgets('the banner is the height it was asked for', (tester) async {
      await tester.pumpWidget(host(MarkdownArea("""
--header[150]--
right: # My site
--/header--
""", false)));
      await tester.pump();

      // Found through the slot's text, since the header widget is private.
      var box = tester.getSize(find
          .ancestor(of: find.text("My site"), matching: find.byType(ClipRRect))
          .first);
      expect(box.height, 150);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a narrow window does not overflow either', (tester) async {
      await tester.pumpWidget(host(MarkdownArea("""
--header[120]--
left: # A logo would go here
middle: # A rather long site name that has to wrap
right: [Contact](contact.md)
--/header--
""", false), width: 320));
      await tester.pump();

      expect(tester.takeException(), isNull);
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
      await tester.pumpWidget(_drawHost(MarkdownArea("""
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

  group('the gap between slots', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<double> gapAt(WidgetTester tester, double width) async {
      await tester.pumpWidget(_drawHost(MarkdownArea("""
--header[200]--
left: # Logo
middle: # Title
--/header--
""", false), width: width));
      await tester.pump();
      return tester.getRect(find.text("Title")).left -
          tester.getRect(find.text("Logo")).right;
    }

    testWidgets('stays the same however wide the window', (tester) async {
      // Sharing the width out proportionally made this grow with the
      // window, and a logo and title written to sit together drifted apart
      // on a wide one.
      var narrow = await gapAt(tester, 500);
      var wide = await gapAt(tester, 1200);
      expect(wide, moreOrLessEquals(narrow, epsilon: 1));
    });

    testWidgets('a right-hand slot still goes to the right edge',
        (tester) async {
      await tester.pumpWidget(_drawHost(MarkdownArea("""
--header[200]--
left: # Logo
right: # Title
--/header--
""", false), width: 1000));
      await tester.pump();

      // The title belongs against the far edge, with the slack between the
      // two rather than to the right of the title. Measured against the
      // banner rather than the window: the markdown area has gutters of its
      // own, so the banner is narrower than the page and an absolute figure
      // here would be measuring those.
      var banner = tester.getRect(
          find.ancestor(of: find.text("Title"), matching: find.byType(ClipRRect))
              .first);
      var title = tester.getRect(find.text("Title"));
      var logo = tester.getRect(find.text("Logo"));

      expect(banner.right - title.right, lessThan(40),
          reason: "a right-hand slot should reach the banner's right edge");
      expect(title.left - logo.right, greaterThan(banner.width / 2),
          reason: "the slack belongs between them");
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
      await tester.pumpWidget(_drawHost(MarkdownArea("""
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

  group('how tall a logo is', () {
    test('a number is the height, bounded', () {
      expect(headerLogoHeight({"logosize": "64"}), 64);
      expect(headerLogoHeight({"logosize": "9999"}), 600);
      expect(headerLogoHeight({"logosize": "1"}), 8);
    });

    test('nothing said fills the banner, as it always did', () {
      expect(headerLogoHeight({}), isNull);
      expect(headerLogoHeight({"logosize": ""}), isNull);
      expect(headerLogoHeight({"logosize": "fill"}), isNull);
    });

    test('something it cannot read fills too, rather than vanishing', () {
      expect(headerLogoHeight({"logosize": "big"}), isNull);
    });

    test('it is a field, so it does not read as a slot', () {
      // A line the header does not know becomes part of the value above it
      // -- a logosize that was not a field would be swallowed by whatever
      // slot preceded it.
      expect(headerFields, contains("logosize"));
    });
  });

  group('a sized logo is drawn', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('at the height it was given', (tester) async {
      // The picture cannot decode in a test, so this checks the box it is
      // put in rather than the picture -- which is the part being decided
      // here anyway.
      await tester.pumpWidget(_drawHost(MarkdownArea("""
--header[200]--
left: --embed[type=image/png,data=AAAA]--
right: # My site
logosize: 48
--/header--
""", false)));
      await tester.pump();

      var boxes = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .where((b) => b.height == 48);
      expect(boxes, isNotEmpty,
          reason: "the logo should be boxed to the height it was given");
      expect(tester.takeException(), isNull);
    });
  });
}
