import 'package:bruig/components/feed/markdown_blocks.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/theming_system/model/markdown_style.dart';
import 'package:bruig/models/payments.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Widget child, {double width = 900}) => MultiProvider(
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
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: width, child: child),
            ),
          ),
        ),
      ),
    );

void main() {
  const img = "--embed[type=image/png,data=AAAA]--";

  List<String> cells(String src) =>
      GridBlockSyntax.splitCells(src.trim().split("\n"));

  md.Element parse(String src) {
    var doc = md.Document(blockSyntaxes: [GridBlockSyntax()]);
    var nodes = doc.parseLines(src.trim().split("\n"));
    return (nodes.first as md.Element).children!.first as md.Element;
  }

  group('splitCells', () {
    test('each picture starts a cell and keeps the writing after it', () {
      expect(cells('''
$img
### One
first caption
$img
### Two
'''), [
        "$img\n### One\nfirst caption",
        "$img\n### Two",
      ]);
    });

    test('a leading picture does not emit an empty cell before itself', () {
      // The naive "flush on every picture" writes a blank first cell, which
      // renders as a gap the writer never asked for.
      expect(cells("$img\ncaption").length, 1);
    });

    test('writing before the first picture is a cell of its own', () {
      // Which is where a heading over the gallery goes.
      expect(cells('''
## Gallery
$img
one
'''), ["## Gallery", "$img\none"]);
    });

    test('a non-image embed does not start a cell', () {
      // A file attachment belongs in the caption it was written in, not in
      // a cell of its own.
      var pdf = "--embed[type=application/pdf,download=abc]--";
      expect(cells("$img\ncaption\n$pdf").length, 1);
    });

    test('a markdown image starts a cell too', () {
      expect(cells("![a](x.png)\none\n![b](y.png)\ntwo").length, 2);
    });

    test('blank lines between cells do not become cells', () {
      expect(cells("$img\none\n\n\n$img\ntwo").length, 2);
    });
  });

  group('GridBlockSyntax', () {
    test('a bare --grid-- leaves the width to the guide', () {
      // How many across is a decision about the page, not the writing, so a
      // writer who did not say gets whatever the reader's Markdown guide
      // says -- see GridRule.columns.
      var e = parse("--grid--\n$img\none\n$img\ntwo\n--/grid--");
      expect(e.tag, "grid");
      expect(e.attributes["columns"], isNull);
      expect(e.attributes["count"], "2");
      expect(e.attributes["cell0"], contains("one"));
    });

    test('--grid[n]-- sets the width, clamped to something usable', () {
      expect(
          parse("--grid[3]--\n$img\na\n--/grid--").attributes["columns"], "3");
      // Past four a cell in a chat-width window is a word wide.
      expect(
          parse("--grid[9]--\n$img\na\n--/grid--").attributes["columns"], "4");
      expect(
          parse("--grid[0]--\n$img\na\n--/grid--").attributes["columns"], "1");
    });

    test('--grid[1]-- is what Decred Pulse spells --grid2--', () {
      expect(
          parse("--grid[1]--\n$img\na\n--/grid--").attributes["columns"], "1");
    });

    test('--grid2-- itself is read, so imported pages lay out as written', () {
      var e = parse("--grid2--\n$img\none\n$img\ntwo\n--/grid2--");
      expect(e.attributes["columns"], "1");
      expect(e.attributes["count"], "2");
    });

    test('the closing marker does not have to match the opening one', () {
      // Forgiving on purpose: a mismatched pair is a typo, and losing the
      // gallery over it helps nobody.
      expect(parse("--grid2--\n$img\na\n--/grid--").attributes["count"], "1");
    });

    test('an unterminated grid still renders what was written', () {
      // Losing the writer's pictures because they forgot a closing marker
      // is worse than a gallery that runs to the end of the page.
      var e = parse("--grid--\n$img\none");
      expect(e.attributes["count"], "1");
    });

    test('an empty grid produces nothing rather than an empty box', () {
      expect(parse("--grid--\n--/grid--").attributes["count"], "0");
    });
  });

// The parse tests above prove the markers are read. These prove something is
// drawn from them -- a builder that is registered but never reached renders
// nothing, and the parse tests would not notice.

  group('drawn', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> pump(WidgetTester tester, String src,
        {double width = 900}) async {
      await tester.pumpWidget(_host(MarkdownArea(src, false), width: width));
      await tester.pump();
    }

    testWidgets('the captions reach the screen as markdown, not as text',
        (tester) async {
      await pump(tester, """
--grid--
$img
### First
$img
### Second
--/grid--
""");

      // Rendered by a MarkdownArea of its own per cell, so the heading is a
      // heading rather than a literal "### First".
      expect(find.text("First"), findsOneWidget);
      expect(find.text("Second"), findsOneWidget);
      expect(find.textContaining("###"), findsNothing);
      // And the markers themselves are consumed, not shown.
      expect(find.textContaining("--grid--"), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cells sit side by side across, and stacked at one across',
        (tester) async {
      await pump(
          tester, "--grid--\n$img\n### left\n$img\n### right\n--/grid--");
      var acrossLeft = tester.getTopLeft(find.text("left"));
      var acrossRight = tester.getTopLeft(find.text("right"));
      expect(acrossRight.dx, greaterThan(acrossLeft.dx));
      expect(acrossRight.dy, acrossLeft.dy);

      await pump(
          tester, "--grid[1]--\n$img\n### left\n$img\n### right\n--/grid--");
      var downLeft = tester.getTopLeft(find.text("left"));
      var downRight = tester.getTopLeft(find.text("right"));
      expect(downRight.dy, greaterThan(downLeft.dy));
      expect(downRight.dx, downLeft.dx);
    });

    testWidgets('a short last row keeps its cells at column width',
        (tester) async {
      // Three cells two across: the lone one on the second row must not
      // stretch to the full width, or the grid stops looking like one.
      await pump(
          tester, "--grid--\n$img\n### a\n$img\n### b\n$img\n### c\n--/grid--");
      var first = tester.getSize(find
          .ancestor(of: find.text("a"), matching: find.byType(MarkdownArea))
          .first);
      var last = tester.getSize(find
          .ancestor(of: find.text("c"), matching: find.byType(MarkdownArea))
          .first);
      expect(last.width, moreOrLessEquals(first.width, epsilon: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a narrow window does not overflow', (tester) async {
      await pump(tester,
          "--grid[4]--\n$img\n### a\n$img\n### b\n$img\n### c\n$img\n### d\n--/grid--",
          width: 320);
      expect(tester.takeException(), isNull);
    });
  });

  group('GridRule', () {
    test('survives a round trip through json', () {
      const r = GridRule(gap: 20, columns: 3, stackBelow: 250);
      expect(GridRule.fromJson(r.toJson()), r);
    });

    test('a guide written before galleries existed still loads', () {
      // Old presets have no "grid" key at all; they must open on the
      // defaults rather than failing to load.
      var guide = MarkdownStyleGuide.fromJson({"id": "x", "name": "X"});
      expect(guide.grid, const GridRule());
    });

    test('bounds keep a guide from setting something unusable', () {
      expect(const GridRule(columns: 99).boundedColumns, 4);
      expect(const GridRule(columns: 0).boundedColumns, 1);
      expect(const GridRule(gap: 1000).boundedGap, 96);
    });
  });
}
