import 'package:bruig/components/feed/markdown_header.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/theming_system/model/markdown_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'header_harness.dart';

// markdown_header_test.dart covers the banner: its rows, how each divides,
// and the height they are held to.
//
// A banner is at most two rows of at most two cells. Everything past that is
// refused rather than half-drawn, because a shape nobody can check is a shape
// that breaks at a width its author never saw.

List<HeaderRow> rowsOf(String src) =>
    headerRowsOf(parseBlock(src, HeaderBlockSyntax()).attributes);

void main() {
  group('a banner keeps no room of its own', () {
    // The gap is what separates the rows inside a banner -- that is what it
    // says it is, and what it does at the rows. It was also used as an outer
    // margin, which gave the banner a second one nothing documented. Nothing
    // showed until a page took a background, at which point it read as a
    // band above the banner that no padding or margin on the page could
    // reach, because it was inside the page and outside the banner.
    Finder banner() => find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == "_MarkdownHeader");

    testWidgets('what is drawn starts where the banner does', (tester) async {
      // The banner's own top, not the page's: the second margin was inside
      // the banner widget, so the widget sat where it always had and only
      // what it drew moved down.
      await tester.pumpWidget(drawHost(MarkdownArea(
          "--header--\n--row[96]--\n# Site\n--/row--\n--/header--", false)));
      await tester.pumpAndSettle();

      var drawn =
          find.descendant(of: banner(), matching: find.byType(SizedBox)).first;
      expect(tester.getTopLeft(drawn).dy, tester.getTopLeft(banner()).dy);
    });

    testWidgets('and takes no room below it either', (tester) async {
      // What separates a banner from what follows is what separates any two
      // blocks, and the renderer puts that between them already. A margin of
      // its own on top of that is the banner counted twice.
      await tester.pumpWidget(drawHost(MarkdownArea(
          "--header--\n--row[96]--\n# Site\n--/row--\n--/header--\n\nBody",
          false)));
      await tester.pumpAndSettle();

      var bannerBottom = tester.getBottomLeft(banner()).dy;
      var bodyTop = tester
          .getTopLeft(find.textContaining("Body", findRichText: true).first)
          .dy;
      // One block's worth, not two.
      expect(bodyTop - bannerBottom, lessThanOrEqualTo(12.0));
    });
  });

  group('rows', () {
    test('a row carries its height and how it divides', () {
      var rows = rowsOf('''
--header--
--row[96,split]--
left: ![](logo)
right: # My Site
--/row--
--/header--
''');
      expect(rows, hasLength(1));
      expect(rows.first.height, 96);
      expect(rows.first.mode, HeaderRowMode.split);
      expect(rows.first.cells, ["![](logo)", "# My Site"]);
    });

    test('a row that names neither gets a default', () {
      var rows = rowsOf("--header--\n--row--\n# Hi\n--/row--\n--/header--");
      expect(rows.first.height, HeaderRow.defaultHeight);
      expect(rows.first.mode, HeaderRowMode.left);
    });

    test('the two words work in either order', () {
      expect(
          rowsOf("--header--\n--row[center,40]--\nx\n--/row--\n--/header--")
              .first
              .mode,
          HeaderRowMode.center);
      expect(
          rowsOf("--header--\n--row[center,40]--\nx\n--/row--\n--/header--")
              .first
              .height,
          40);
    });

    test('centre is spelt either way', () {
      expect(HeaderRowMode.parse("centre"), HeaderRowMode.center);
      expect(HeaderRowMode.parse("center"), HeaderRowMode.center);
      // Anything it does not know sits at the left rather than failing.
      expect(HeaderRowMode.parse("sideways"), HeaderRowMode.left);
    });

    test('a height is bounded to something still a banner', () {
      expect(
          rowsOf("--header--\n--row[9999]--\nx\n--/row--\n--/header--")
              .first
              .height,
          HeaderRow.maxHeight);
      expect(
          rowsOf("--header--\n--row[1]--\nx\n--/row--\n--/header--")
              .first
              .height,
          16);
    });

    test('two rows are kept and a third is not', () {
      var src = StringBuffer("--header--\n");
      for (var i = 0; i < 5; i++) {
        src.write("--row[40]--\nrow $i\n--/row--\n");
      }
      src.write("--/header--");
      var rows = rowsOf(src.toString());
      expect(rows, hasLength(maxHeaderRows));
      // The first two, not the last: a writer reads down the page.
      expect(rows.first.cells.first, "row 0");
    });
  });

  group('cells', () {
    test('a row with no named cell holds one thing', () {
      // Which is what a bar of links in a row looks like -- a fragment, and
      // nothing special about it.
      var rows = rowsOf('''
--header--
--row[44,center]--
--include[navigation]--
--/row--
--/header--
''');
      expect(rows.first.cells, ["--include[navigation]--"]);
    });

    test('a cell can be several lines, which is what a fragment becomes', () {
      var rows = rowsOf('''
--header--
--row[44,split]--
left: --nav[pills]--
[Home](index.md)
--/nav--
right: # Title
--/row--
--/header--
''');
      expect(rows.first.cells.first, contains("[Home](index.md)"));
      expect(rows.first.cells.first, contains("--/nav--"));
      expect(rows.first.cells.last, "# Title");
    });

    test('a colon in a cell does not start a new one', () {
      // Which is most lines of a bar: "[Home](br://...)" has one.
      var rows = rowsOf('''
--header--
--row--
left: [Home](br://abc/index.md)
[More](more.md)
--/row--
--/header--
''');
      expect(rows.first.cells.first, contains("br://abc/index.md"));
      expect(rows.first.cells.first, contains("[More](more.md)"));
    });

    test('an empty row is no cells rather than one empty one', () {
      expect(
          rowsOf("--header--\n--row[40]--\n--/row--\n--/header--").first.cells,
          isEmpty);
    });
  });

  group('two cells together', () {
    test('any mode but split takes two, side by side', () {
      // A logo and the title beside it, which is the commonest thing a
      // banner holds and the one shape split cannot make.
      var rows = rowsOf('''
--header--
--row[96,left]--
left: ![](logo)
right: # My site
--/row--
--/header--
''');
      expect(rows.first.mode, HeaderRowMode.left);
      expect(rows.first.cells, hasLength(2));
    });

    test('and both are kept, rather than one being dropped', () {
      for (var mode in ["left", "center", "right"]) {
        var rows = rowsOf("--header--\n--row[60,$mode]--\nleft: A\nright: B\n"
            "--/row--\n--/header--");
        expect(rows.first.cells, ["A", "B"], reason: mode);
      }
    });
  });

  group('the banner itself', () {
    test('keeps its own fields apart from its rows', () {
      var e = parseBlock('''
--header--
background: --embed[type=image/png,data=AAAA]--
--row[80,split]--
left: # A
right: # B
--/row--
--/header--
''', HeaderBlockSyntax());
      expect(e.attributes["background"], contains("data=AAAA"));
      expect(headerRowsOf(e.attributes), hasLength(1));
    });

    test('an unterminated header still renders what was written', () {
      var rows = rowsOf("--header--\n--row[40]--\nkept\n--/row--");
      expect(rows.first.cells.first, "kept");
    });
  });

  group('embedImage', () {
    test('takes the picture and its kind out of an inline embed', () {
      var got = embedImage("--embed[type=image/png,data=AAAA]--");
      expect(got!.bytes.length, 3);
      // The kind matters: a vector needs a different decoder, and guessing
      // from the bytes is guessing at something the writer already knew.
      expect(got.mime, "image/png");
    });

    test('anything that is not an inline image is not drawn', () {
      expect(embedImage(null), isNull);
      expect(embedImage("photo.png"), isNull);
      expect(embedImage("--embed[type=application/pdf,data=AAAA]--"), isNull);
      // A reference the document still carries while it is being written.
      expect(
          embedImage("--embed[type=image/png,data=[content abcdefghijkl]]--"),
          isNull);
    });
  });

  group('isSvgMime', () {
    test('recognises what a vector is declared as, and nothing else', () {
      expect(isSvgMime("image/svg+xml"), isTrue);
      expect(isSvgMime("IMAGE/SVG+XML"), isTrue);
      expect(isSvgMime("image/png"), isFalse);
    });
  });

  group('the rules survive being saved', () {
    test('a header round-trips', () {
      const r =
          HeaderRule(height: 300, padding: 24, radius: 12, gap: 16, scrim: 0.5);
      expect(HeaderRule.fromJson(r.toJson()), r);
    });

    test('a guide written before headers existed still loads', () {
      var guide = MarkdownStyleGuide.fromJson({"id": "x", "name": "X"});
      expect(guide.header, const HeaderRule());
    });
  });

  group('drawn', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('a banner is as tall as its rows', (tester) async {
      await tester.pumpWidget(drawHost(MarkdownArea('''
--header--
--row[80,split]--
left: # Logo
right: # Title
--/row--
--row[40,center]--
[Home](index.md)
--/row--
--/header--
''', false)));
      await tester.pump();

      var banner = tester.getRect(find
          .ancestor(of: find.text("Logo"), matching: find.byType(ClipRRect))
          .first);
      // The rows, plus the padding above and below them.
      const padding = 20.0;
      expect(
          banner.height, moreOrLessEquals(80 + 40 + padding * 2, epsilon: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a split row puts its cells at opposite edges', (tester) async {
      await tester.pumpWidget(drawHost(MarkdownArea('''
--header--
--row[80,split]--
left: # Logo
right: # Title
--/row--
--/header--
''', false), width: 1000));
      await tester.pump();

      var banner = tester.getRect(find
          .ancestor(of: find.text("Logo"), matching: find.byType(ClipRRect))
          .first);
      var logo = tester.getRect(find.text("Logo"));
      var title = tester.getRect(find.text("Title"));

      expect(logo.left - banner.left, lessThan(40));
      expect(banner.right - title.right, lessThan(40));
    });

    testWidgets('a centred row centres its one cell', (tester) async {
      await tester.pumpWidget(drawHost(MarkdownArea('''
--header--
--row[60,center]--
# Middle
--/row--
--/header--
''', false), width: 1000));
      await tester.pump();

      var banner = tester.getRect(find
          .ancestor(of: find.text("Middle"), matching: find.byType(ClipRRect))
          .first);
      var text = tester.getRect(find.text("Middle"));
      expect(text.center.dx, moreOrLessEquals(banner.center.dx, epsilon: 2));
    });

    testWidgets('the row height is what sets the writing', (tester) async {
      Future<double> heightOf(int row) async {
        await tester.pumpWidget(drawHost(MarkdownArea('''
--header--
--row[$row,left]--
# Title
--/row--
--/header--
''', false)));
        await tester.pump();
        return tester.getRect(find.text("Title")).height;
      }

      // Taller row, taller writing -- without either being told about the
      // other, which is what makes a title sit level with a logo.
      expect(await heightOf(100), greaterThan(await heightOf(40)));
    });

    testWidgets('a narrow window does not overflow', (tester) async {
      await tester.pumpWidget(drawHost(MarkdownArea('''
--header--
--row[60,split]--
left: # A rather long name on the left
right: # And another on the right
--/row--
--/header--
''', false), width: 320));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('two cells drawn together', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<double> gapAt(WidgetTester tester, double width) async {
      await tester.pumpWidget(drawHost(MarkdownArea("""
--header--
--row[60,left]--
left: # Logo
right: # Title
--/row--
--/header--
""", false), width: width));
      await tester.pump();
      return tester.getRect(find.text("Title")).left -
          tester.getRect(find.text("Logo")).right;
    }

    testWidgets('sit together rather than sharing out the width',
        (tester) async {
      // Sharing the width out is what made a logo and its title drift apart
      // on a wide window. Measured as a share of the banner rather than in
      // pixels, since a banner scales with the room it has -- an absolute
      // figure would be measuring that instead.
      Future<double> shareAt(double width) async {
        await tester.pumpWidget(drawHost(MarkdownArea("""
--header--
--row[60,left]--
left: # Logo
right: # Title
--/row--
--/header--
""", false), width: width));
        await tester.pump();
        var banner = tester.getRect(find
            .ancestor(of: find.text("Logo"), matching: find.byType(ClipRRect))
            .first);
        var gap = tester.getRect(find.text("Title")).left -
            tester.getRect(find.text("Logo")).right;
        return gap / banner.width;
      }

      // A small share of the banner at either width -- not the half that
      // splitting it would give.
      expect(await shareAt(1200), lessThan(0.15));
      expect(await shareAt(600), lessThan(0.15));
    });

    testWidgets('and split still pushes them to the edges', (tester) async {
      await tester.pumpWidget(drawHost(MarkdownArea("""
--header--
--row[60,split]--
left: # Logo
right: # Title
--/row--
--/header--
""", false), width: 1000));
      await tester.pump();

      // Measured against the banner rather than the window: the markdown
      // area has gutters of its own, so an absolute figure here would be
      // measuring those.
      var banner = tester.getRect(find
          .ancestor(of: find.text("Logo"), matching: find.byType(ClipRRect))
          .first);
      var gap = tester.getRect(find.text("Title")).left -
          tester.getRect(find.text("Logo")).right;
      // A third of the banner rather than a half: the writing is set to the
      // row's height, so at 60px the two words are wide themselves and the
      // slack between them is what is left over.
      expect(gap, greaterThan(banner.width / 3));
    });
  });

  group('room for the second cell', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('a title beside a logo gets what the logo leaves',
        (tester) async {
      // Holding the second cell to a share of the row meant condensing and
      // then cutting writing while most of the banner stood empty beside
      // it. It takes what the first leaves now.
      //
      // Compared against split, where a cell is held to half on purpose,
      // rather than against a figure: the widths a test font reports are
      // its own, and what matters here is that one shape gives more room
      // than the other.
      const title = "A title that wants a good deal more than half the room";

      Future<double> widthIn(String mode) async {
        await tester.pumpWidget(drawHost(MarkdownArea("""
--header--
--row[30,$mode]--
left: # Logo
right: # $title
--/row--
--/header--
""", false), width: 1200));
        await tester.pump();
        return tester.getRect(find.text(title)).width;
      }

      expect(await widthIn("left"), greaterThan(await widthIn("split")));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a wide first cell still leaves the second half',
        (tester) async {
      await tester.pumpWidget(drawHost(MarkdownArea("""
--header--
--row[60,left]--
left: # A very long first cell that would take the whole row given the chance
right: # Second
--/row--
--/header--
""", false), width: 800));
      await tester.pump();

      var banner = tester.getRect(find
          .ancestor(of: find.text("Second"), matching: find.byType(ClipRRect))
          .first);
      var first = tester.getRect(find.textContaining("A very long first"));
      expect(first.width, lessThanOrEqualTo(banner.width / 2 + 2));
      expect(tester.takeException(), isNull);
    });
  });

  group('a banner in a smaller window', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<({double banner, double logo})> at(
        WidgetTester tester, double width) async {
      await tester.pumpWidget(drawHost(MarkdownArea("""
--header--
--row[120,left]--
left: # Logo
right: # Title
--/row--
--/header--
""", false), width: width));
      await tester.pump();
      return (
        banner: tester
            .getRect(find
                .ancestor(
                    of: find.text("Logo"), matching: find.byType(ClipRRect))
                .first)
            .height,
        logo: tester.getRect(find.text("Logo")).height,
      );
    }

    testWidgets('scales as a whole, keeping its proportions', (tester) async {
      var wide = await at(tester, 900);
      var narrow = await at(tester, 400);

      // Shorter overall, and the writing shorter with it -- which is the
      // point. Left alone the rows kept their written height whatever room
      // there was, and the title absorbed the whole difference by
      // condensing until it was cut.
      expect(narrow.banner, lessThan(wide.banner));
      expect(narrow.logo, lessThan(wide.logo));

      // The same shape at both: the writing is the same share of the
      // banner, which is what "disproportionate on a small screen" was.
      expect(narrow.logo / narrow.banner,
          moreOrLessEquals(wide.logo / wide.banner, epsilon: 0.02));
    });

    testWidgets('never larger than it was written', (tester) async {
      // Only ever down. A banner on a wide screen is the size it was
      // written, not a bigger one.
      var wide = await at(tester, 2000);
      var atFull = await at(tester, 900);
      expect(wide.banner, moreOrLessEquals(atFull.banner, epsilon: 1));
    });

    testWidgets('stops shrinking before it stops being legible',
        (tester) async {
      var tiny = await at(tester, 120);
      var wide = await at(tester, 900);
      // HeaderRule.smallestScale is half by default.
      expect(tiny.banner / wide.banner, greaterThanOrEqualTo(0.49));
      expect(tester.takeException(), isNull);
    });
  });

  group('a flush row', () {
    test('is read from the marker, alongside the rest', () {
      var rows = rowsOf(
          "--header--\n--row[44,center,flush]--\nx\n--/row--\n--/header--");
      expect(rows.first.flush, isTrue);
      expect(rows.first.height, 44);
      expect(rows.first.mode, HeaderRowMode.center);
    });

    test('an ordinary row is not flush', () {
      expect(
          rowsOf("--header--\n--row[44]--\nx\n--/row--\n--/header--")
              .first
              .flush,
          isFalse);
    });

    testWidgets('sits hard against the edge it is at', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(drawHost(MarkdownArea("""
--header--
--row[40,center,flush]--
# Strip
--/row--
--row[80,left]--
# Body
--/row--
--/header--
""", false)));
      await tester.pump();

      var banner = tester.getRect(find
          .ancestor(of: find.text("Strip"), matching: find.byType(ClipRRect))
          .first);
      var strip = tester.getRect(find.text("Strip"));
      var body = tester.getRect(find.text("Body"));

      // Nothing above the strip; the row below keeps its inset.
      expect(strip.top - banner.top, lessThan(banner.height / 4));
      expect(body.left - banner.left, greaterThan(4));
      expect(tester.takeException(), isNull);
    });
  });

  group('where a banner puts its spaces', () {
    HeaderRow row({bool flush = false}) => HeaderRow(
        height: 40, mode: HeaderRowMode.left, cells: const ["x"], flush: flush);

    test('two ordinary rows are inset from the edges and stacked', () {
      // Before, between, after.
      expect(headerRowSpaces([row(), row()]), [true, false, true]);
    });

    test('a strip at the bottom keeps the row above its own space', () {
      // Which is the fault this fixes: the writing sat crowded against the
      // strip because the flush row took the space between them with it.
      expect(headerRowSpaces([row(), row(flush: true)]), [true, true, false]);
    });

    test('and a strip at the top does the same', () {
      expect(headerRowSpaces([row(flush: true), row()]), [false, true, true]);
    });

    test('a strip at both ends leaves the middle row its room', () {
      expect(headerRowSpaces([row(flush: true), row(), row(flush: true)]),
          [false, true, true, false]);
    });

    test('two strips together have nothing between them', () {
      expect(headerRowSpaces([row(flush: true), row(flush: true)]),
          [false, false, false]);
    });

    test('one row on its own', () {
      expect(headerRowSpaces([row()]), [true, true]);
      expect(headerRowSpaces([row(flush: true)]), [false, false]);
    });
  });

  group('a strip drawn at an edge', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('leaves the row above as much room below as above',
        (tester) async {
      await tester.pumpWidget(drawHost(MarkdownArea("""
--header--
--row[80,left]--
# Body
--/row--
--row[40,center,flush]--
# Strip
--/row--
--/header--
""", false)));
      await tester.pump();

      var banner = tester.getRect(find
          .ancestor(of: find.text("Body"), matching: find.byType(ClipRRect))
          .first);
      var body = tester.getRect(find.text("Body"));
      var strip = tester.getRect(find.text("Strip"));

      // The strip is against the bottom, and the writing above it is not
      // crowded against the strip.
      expect(banner.bottom - strip.bottom, lessThan(banner.height / 4));
      expect(strip.top - body.bottom, greaterThan(4));
      expect(tester.takeException(), isNull);
    });
  });

  group('room for the second cell, whichever way the row runs', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<double> widthIn(WidgetTester tester, String mode) async {
      const title = "A title that wants a good deal more than half the room";
      await tester.pumpWidget(drawHost(MarkdownArea("""
--header--
--row[30,$mode]--
left: # Logo
right: # $title
--/row--
--/header--
""", false), width: 1200));
      await tester.pump();
      return tester.getRect(find.text(title)).width;
    }

    testWidgets('centre and right get what left gets', (tester) async {
      // Holding each cell to half meant a title in a centred row was
      // cropped while the room it needed sat empty beside it. A row's
      // alignment says where its writing sits, not how much of the banner
      // it may use.
      var left = await widthIn(tester, "left");
      expect(
          await widthIn(tester, "center"), moreOrLessEquals(left, epsilon: 1));
      expect(
          await widthIn(tester, "right"), moreOrLessEquals(left, epsilon: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('and the alignment still says where it sits', (tester) async {
      Future<Rect> rectIn(String mode) async {
        await tester.pumpWidget(drawHost(MarkdownArea("""
--header--
--row[30,$mode]--
left: # Logo
right: # Short
--/row--
--/header--
""", false), width: 1200));
        await tester.pump();
        return tester.getRect(find.text("Short"));
      }

      var l = await rectIn("left");
      var c = await rectIn("center");
      var r = await rectIn("right");
      expect(c.left, greaterThan(l.left));
      expect(r.left, greaterThan(c.left));
    });
  });

  group('a grouped pair', () {
    test('is read from the marker, alongside the rest', () {
      var rows = rowsOf("--header--\n--row[96,center,group]--\n"
          "left: A\nright: B\n--/row--\n--/header--");
      expect(rows.first.group, isTrue);
      expect(rows.first.mode, HeaderRowMode.center);
      expect(rows.first.height, 96);
    });

    test('an ordinary row is not grouped', () {
      expect(
          rowsOf("--header--\n--row[96,center]--\nx\n--/row--\n--/header--")
              .first
              .group,
          isFalse);
    });

    test('reads alongside flush, in either order', () {
      var rows = rowsOf("--header--\n--row[40,group,flush,center]--\n"
          "left: A\nright: B\n--/row--\n--/header--");
      expect(rows.first.group, isTrue);
      expect(rows.first.flush, isTrue);
      expect(rows.first.mode, HeaderRowMode.center);
    });

    group('drawn', () {
      setUp(() => SharedPreferences.setMockInitialValues({}));

      Future<({Rect logo, Rect title, Rect banner})> pairIn(
          WidgetTester tester, String args) async {
        await tester.pumpWidget(drawHost(MarkdownArea("""
--header--
--row[$args]--
left: # Logo
right: # Title
--/row--
--/header--
""", false), width: 1200));
        await tester.pump();
        return (
          logo: tester.getRect(find.text("Logo")),
          title: tester.getRect(find.text("Title")),
          banner: tester.getRect(find
              .ancestor(of: find.text("Logo"), matching: find.byType(ClipRRect))
              .first),
        );
      }

      testWidgets('sits together in the middle', (tester) async {
        var g = await pairIn(tester, "60,center,group");

        // The pair straddles the middle, rather than the logo staying at
        // the left with the title beside it.
        var pairMiddle = (g.logo.left + g.title.right) / 2;
        expect(pairMiddle, moreOrLessEquals(g.banner.center.dx, epsilon: 8));
        expect(tester.takeException(), isNull);
      });

      testWidgets('and ungrouped still leaves the logo at the left',
          (tester) async {
        var plain = await pairIn(tester, "60,center");
        expect(plain.logo.left - plain.banner.left, lessThan(40));
      });

      testWidgets('goes where the mode says', (tester) async {
        var left = await pairIn(tester, "60,left,group");
        var right = await pairIn(tester, "60,right,group");
        expect(left.logo.left, lessThan(right.logo.left));
        expect(right.banner.right - right.title.right, lessThan(40));
      });
    });
  });
}
