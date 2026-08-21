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

// markdown_header_test.dart covers the banner itself: its fields, the
// slots across it, and the room they are given.

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
      var e = parseBlock('''
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
      var e =
          parseBlock("--header--\nleft: hi\n--/header--", HeaderBlockSyntax());
      expect(e.attributes["height"], isNull);
    });

    test('a height is bounded to something that is still a banner', () {
      expect(
          parseBlock(
                  "--header[5000]--\nleft: a\n--/header--", HeaderBlockSyntax())
              .attributes["height"],
          "${HeaderBlockSyntax.maxHeight}");
      expect(
          parseBlock("--header[1]--\nleft: a\n--/header--", HeaderBlockSyntax())
              .attributes["height"],
          "40");
    });

    test('a field can be several lines, which is what a bar is', () {
      // "nav: --include[bar]--" is replaced with the whole of that fragment
      // before this is parsed, so a field that stopped at one line kept the
      // first line of a navigation bar and threw the links away.
      var e = parseBlock('''
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
      var e = parseBlock('''
--header--
nav: [Home](br://abc123/index.md)
[Notes](notes.md)
--/header--
''', HeaderBlockSyntax());

      expect(e.attributes["nav"], contains("br://abc123/index.md"));
      expect(e.attributes["nav"], contains("[Notes](notes.md)"));
    });

    test('a line before any field is not kept', () {
      var e = parseBlock(
          "--header--\nstray text\nleft: hi\n--/header--", HeaderBlockSyntax());
      expect(e.attributes["left"], "hi");
      expect(e.attributes.values, isNot(contains("stray text")));
    });

    test('an unterminated header still renders what was written', () {
      var e = parseBlock("--header--\nleft: hi", HeaderBlockSyntax());
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
        drawHost(child, width: width);

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

  group('the gap between slots', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<double> gapAt(WidgetTester tester, double width) async {
      await tester.pumpWidget(drawHost(MarkdownArea("""
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
      await tester.pumpWidget(drawHost(MarkdownArea("""
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
      var banner = tester.getRect(find
          .ancestor(of: find.text("Title"), matching: find.byType(ClipRRect))
          .first);
      var title = tester.getRect(find.text("Title"));
      var logo = tester.getRect(find.text("Logo"));

      expect(banner.right - title.right, lessThan(40),
          reason: "a right-hand slot should reach the banner's right edge");
      expect(title.left - logo.right, greaterThan(banner.width / 2),
          reason: "the slack belongs between them");
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
      await tester.pumpWidget(drawHost(MarkdownArea("""
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
