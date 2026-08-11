import 'dart:convert';
import 'dart:math' as math;

import 'package:bruig/components/md_elements.dart';
import 'package:bruig/models/payments.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'png_fixture.dart';

// markdown_columns_test.dart covers columns: a block syntax Bison Relay adds,
// because Markdown has none of its own in any dialect worth following.
//
// The shape of it is the app's existing one -- --columns-- / --col-- /
// --/columns--, matching --form-- next door. What matters below is that each
// column is markdown in its own right, that the columns divide the width
// between them, and that they stop being columns when there is no width to
// divide.

/// _body is the style a run is measured in. The test framework draws every
/// glyph at a fixed size, so these numbers are stable but are not the ones a
/// real font gives -- what the tests below check is one block against
/// another, not either against a figure from the page.
const _body = TextStyle(fontSize: 14);

const _twoColumns = """
--columns--
# Left heading
Left text.
--col--
Right text.
--/columns--
""";

Widget _host(Widget child, {double width = 800}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<PaymentsModel>(create: (c) => PaymentsModel()),
        ChangeNotifierProvider<MarkdownAreaModel>(
            create: (c) => MarkdownAreaModel("/tmp")),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );

Future<void> _pump(WidgetTester tester, String markdown,
    {double width = 800}) async {
  await tester.pumpWidget(_host(MarkdownArea(markdown, false), width: width));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group("the syntax", () {
    test("splits on the separator and drops the markers", () {
      var doc = ColumnsBlockSyntax();
      expect(doc.pattern.hasMatch("--columns--"), isTrue);
      expect(doc.pattern.hasMatch("  --columns--  "), isTrue);
      expect(doc.pattern.hasMatch("--columns-- and more"), isFalse,
          reason: "a marker is a line of its own, not a run of text");
    });

    // A run left open is every run for as long as it is being written, so it
    // has to render rather than swallow the rest of the post silently.
    testWidgets("an unclosed run still draws its columns", (tester) async {
      await _pump(tester, "--columns--\nLeft.\n--col--\nRight.");
      expect(find.text("Left."), findsOneWidget);
      expect(find.text("Right."), findsOneWidget);
    });

    testWidgets("the markers themselves are not shown", (tester) async {
      await _pump(tester, _twoColumns);
      expect(find.textContaining("--col"), findsNothing);
    });
  });

  group("a column holds markdown, not text", () {
    testWidgets("a heading inside one is a heading", (tester) async {
      await _pump(tester, _twoColumns);
      var heading = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((r) => r.text)
          .whereType<TextSpan>()
          .expand((s) => s.children ?? const <InlineSpan>[])
          .whereType<TextSpan>()
          .firstWhere((s) => s.text == "Left heading");
      expect(heading.style?.fontSize, greaterThan(14),
          reason: "it is set as a heading, not as the text around it");
    });
  });

  group("the width is divided between them", () {
    // The columns themselves, not the words in them: a line of text sizes to
    // its own length whatever column it sits in. Index 0 is the post; the
    // rest are one MarkdownArea per column.
    double columnWidth(WidgetTester tester, int index) =>
        tester.getSize(find.byType(MarkdownArea).at(index + 1)).width;

    testWidgets("two columns each take about half", (tester) async {
      await _pump(tester, "--columns--\nLeft.\n--col--\nRight.");
      // 800 less the 16 point gap, halved.
      expect(columnWidth(tester, 0), closeTo(392, 1));
      expect(columnWidth(tester, 1), closeTo(392, 1));
    });

    testWidgets("three columns each take about a third", (tester) async {
      await _pump(tester, "--columns--\nOne.\n--col--\nTwo.\n--col--\nThree.");
      // 800 less two gaps, in thirds.
      expect(columnWidth(tester, 0), closeTo(256, 1));
      expect(columnWidth(tester, 2), closeTo(256, 1));
    });

    // The whole reason the stacking width exists: the same post is read in a
    // window a third of somebody else's, and three columns of nine
    // characters each is not a layout.
    testWidgets("they stack when there is no width to divide", (tester) async {
      await _pump(tester, "--columns--\nLeft.\n--col--\nRight.", width: 300);
      var left = tester.getRect(find.text("Left."));
      var right = tester.getRect(find.text("Right."));
      expect(right.top, greaterThanOrEqualTo(left.bottom),
          reason: "one above the other, not side by side");
    });

    testWidgets("a single column is drawn as a plain block", (tester) async {
      await _pump(tester, "--columns--\nOnly one.\n--/columns--");
      expect(find.text("Only one."), findsOneWidget);
    });
  });

  // The run's box: the space inside it, the space around it, and the line
  // round the outside. Round the run rather than round each column -- a
  // border on every column is a row of boxes with a channel down the middle
  // of every gap, which is not what a set of columns looks like.
  group("the run's box", () {
    /// _boxed pumps a two-column run under a guide carrying [columns].
    Future<void> boxed(WidgetTester tester, ColumnRule columns) async {
      var guide = builtInGuideFor(defaultGuideId)!.copyWith(columns: columns);
      await tester.pumpWidget(_host(MarkdownArea(
          "--columns--\nLeft.\n--col--\nRight.\n--/columns--", false,
          guide: guide)));
      await tester.pump();
    }

    /// decorationOf is the box drawn round the first column.
    BoxDecoration? decorationOf(WidgetTester tester) {
      for (var c in tester.widgetList<Container>(find.byType(Container))) {
        var d = c.decoration;
        if (d is BoxDecoration &&
            (d.border != null || d.borderRadius != null)) {
          return d;
        }
      }
      return null;
    }

    testWidgets("nothing set draws no box at all", (tester) async {
      await boxed(tester, const ColumnRule());
      expect(decorationOf(tester), isNull,
          reason: "a column with no box stays the plain block it was");
    });

    testWidgets("a border is drawn round the run", (tester) async {
      await boxed(tester, const ColumnRule(borderWidth: 3));
      // Border, not BoxBorder: only the concrete one has sides to read.
      var border = decorationOf(tester)?.border as Border?;
      expect(border, isNotNull);
      expect(border!.top.width, 3);
      expect(border.left.width, 3);
    });

    // The thing that was wrong: a border on each column put two lines and a
    // gap where one line belongs.
    testWidgets("there is one box, not one per column", (tester) async {
      await boxed(tester, const ColumnRule(borderWidth: 3));
      var boxes = tester.widgetList<Container>(find.byType(Container)).where(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration! as BoxDecoration).border != null);
      expect(boxes.length, 1,
          reason: "two columns, one frame round the pair of them");
    });

    testWidgets("the corners are rounded", (tester) async {
      await boxed(tester, const ColumnRule(borderWidth: 1, radius: 12));
      expect(decorationOf(tester)?.borderRadius, BorderRadius.circular(12));
    });

    // Each side on its own, which is the whole point of splitting them.
    testWidgets("a side can be set on its own", (tester) async {
      await boxed(
          tester,
          ColumnRule(
              borderWidth: 1, borderWidthSides: SideValues([4, 0, 0, 0])));
      var border = decorationOf(tester)!.border! as Border;
      expect(border.left.width, 4);
      expect(border.top.width, 0);
      expect(border.right.width, 0);
    });

    // Flutter refuses to paint a border whose sides differ together with
    // rounded corners, so the rounding is what gives way -- stated in the
    // editor rather than left to be discovered.
    testWidgets("a split border squares the corners off", (tester) async {
      await boxed(
          tester,
          ColumnRule(
              radius: 12,
              borderWidth: 1,
              borderWidthSides: SideValues([4, 1, 1, 1])));
      expect(decorationOf(tester)?.borderRadius, isNull);
      expect(tester.takeException(), isNull);
    });

    // The divider is its own line down the middle of each gap, and its own
    // setting: a rule between columns usually reads better at a different
    // weight from the frame, and most of the time there is no frame at all.
    testWidgets("no divider is drawn when its width is zero", (tester) async {
      await boxed(tester, const ColumnRule(borderWidth: 1));
      expect(
          find.byType(CustomPaint).evaluate().where((e) {
            var w = e.widget as CustomPaint;
            return w.painter.runtimeType.toString().contains("ColumnDividers");
          }),
          isEmpty);
    });

    testWidgets("a divider is painted down each gap", (tester) async {
      await boxed(tester, const ColumnRule(dividerWidth: 2, gap: 24));
      var painters = find.byType(CustomPaint).evaluate().where((e) {
        var w = e.widget as CustomPaint;
        return w.painter.runtimeType.toString().contains("ColumnDividers");
      });
      expect(painters, isNotEmpty);
    });

    // A divider needs no border, and a border needs no divider.
    testWidgets("a divider works with no border at all", (tester) async {
      await boxed(tester, const ColumnRule(dividerWidth: 2));
      expect(decorationOf(tester), isNull);
      expect(tester.takeException(), isNull);
    });

    // Stacked, the same line does the same job the other way round.
    testWidgets("stacked, the divider lies across the gap", (tester) async {
      var guide = builtInGuideFor(defaultGuideId)!
          .copyWith(columns: const ColumnRule(dividerWidth: 2, gap: 20));
      await tester.pumpWidget(_host(
          MarkdownArea(
              "--columns--\nLeft.\n--col--\nRight.\n--/columns--", false,
              guide: guide),
          width: 300));
      await tester.pump();
      expect(
          tester
              .widgetList<Container>(find.byType(Container))
              .any((c) => c.constraints?.maxHeight == 2),
          isTrue,
          reason: "a line across, where the vertical one would have been");
    });

    testWidgets("padding and margin reach the container", (tester) async {
      await boxed(tester, const ColumnRule(padding: 10, margin: 6));
      var container = tester
          .widgetList<Container>(find.byType(Container))
          .firstWhere((c) => c.padding == const EdgeInsets.all(10));
      expect(container.margin, const EdgeInsets.all(6));
    });

    testWidgets("a per-side padding is used as given", (tester) async {
      await boxed(tester,
          ColumnRule(padding: 4, paddingSides: SideValues([1, 2, 3, 4])));
      expect(
          tester.widgetList<Container>(find.byType(Container)).any((c) =>
              c.padding ==
              const EdgeInsets.only(left: 1, top: 2, right: 3, bottom: 4)),
          isTrue);
    });
  });

  group("the box survives being saved", () {
    test("every setting round-trips", () {
      var columns = ColumnRule(
        gap: 20,
        stackBelow: 300,
        padding: 8,
        paddingSides: SideValues([1, 2, 3, 4]),
        margin: 5,
        marginSides: SideValues([5, 6, 7, 8]),
        borderWidth: 2,
        borderWidthSides: SideValues([2, 0, 2, 0]),
        borderInk: const MarkdownInk.of(MarkdownRole.accent),
        radius: 10,
        radiusSides: SideValues([10, 0, 10, 0]),
      );
      var guide = const MarkdownStyleGuide(id: "x", name: "X")
          .copyWith(columns: columns);
      var back = MarkdownStyleGuide.fromJson(guide.toJson()).columns;
      expect(back, columns);
      expect(back.borderInk.role, MarkdownRole.accent);
    });

    // The defaults write nothing they do not have to, so a guide that never
    // touched a column is stored as small as it was before these existed.
    test("the defaults stay out of the file", () {
      var json = const ColumnRule().toJson();
      expect(json.containsKey("padding"), isFalse);
      expect(json.containsKey("borderWidth"), isFalse);
      expect(json.containsKey("radiusSides"), isFalse);
    });
  });

  // Auto-flow: --columns[2]-- divides one run of writing between two columns
  // rather than expecting it to be split by hand.
  //
  // Balanced by block and in the order it was written. Order is the part that
  // matters most: when the window is too narrow the columns stack, and
  // stacked they have to read back as the post that was typed.
  group("flowing content between columns", () {
    String para(int n, int size) => n.toString() * size;

    test("equal blocks divide evenly", () {
      var blocks = [for (var i = 0; i < 4; i++) para(i, 100)];
      var out = flowColumns(blocks.join("\n\n"), 2);
      expect(out.length, 2);
      expect(out[0].split("\n\n").length, 2);
      expect(out[1].split("\n\n").length, 2);
    });

    test("uneven blocks are balanced by how much they hold", () {
      // One long block and four short ones: the long one is a column by
      // itself rather than the count being split down the middle.
      var out = flowColumns(
          [para(0, 400), para(1, 40), para(2, 40), para(3, 40), para(4, 40)]
              .join("\n\n"),
          2);
      expect(out[0].split("\n\n").length, 1);
      expect(out[1].split("\n\n").length, 4);
    });

    // The one that cannot be got wrong: read left to right, the columns are
    // the post in the order it was written.
    test("nothing is lost or reordered", () {
      var blocks = [for (var i = 0; i < 9; i++) "block $i"];
      for (var count = 2; count <= 4; count++) {
        var out = flowColumns(blocks.join("\n\n"), count);
        expect(out.length, count);
        expect(
            out.join("\n\n").split("\n\n").where((b) => b.isNotEmpty), blocks,
            reason: "$count columns");
      }
    });

    // A break can fall between two paragraphs but never through the middle
    // of a fenced block, however many blank lines are inside it.
    test("a fenced block is kept whole", () {
      var markdown =
          "before\n\n```\none\n\ntwo\n```\n\nafter\n\nmore\n\nand more";
      var out = flowColumns(markdown, 2);
      var fenced = out.firstWhere((c) => c.contains("```"));
      expect("```".allMatches(fenced).length, 2,
          reason: "both fences in the same column, or it is not a block");
    });

    // An embed carries its picture as base64: tens of thousands of
    // characters, none of them on the page. Weighed by its length it would
    // take a column to itself and push everything else into the next one.
    test("a picture is weighed as a block, not as its bytes", () {
      // Weighed by its length the embed is 40,000 characters and takes a
      // column to itself, pushing all four paragraphs into the other one.
      // Weighed as the block it draws as, it shares its column.
      var embed = "--embed[type=image/png,data=${"A" * 40000}]--";
      var out = flowColumns(
          [embed, para(1, 300), para(2, 300), para(3, 300), para(4, 300)]
              .join("\n\n"),
          2);
      expect(out[0].contains("--embed["), isTrue);
      expect(out[0].split("\n\n").length, 2,
          reason: "the picture and a paragraph, not the picture alone");
      expect(out[1].split("\n\n").length, 3);
    });

    test("fewer blocks than columns leaves the empty ones empty", () {
      var out = flowColumns("only one block", 3);
      expect(out.length, 3);
      expect(out[0], "only one block");
      expect(out[1], isEmpty);
    });

    test("one column is the whole run", () {
      expect(flowColumns("a\n\nb", 1), ["a\n\nb"]);
    });

    // Reported: it flowed if paragraph breaks were put in and did not if
    // they were not. A run written as one paragraph has no break to fall
    // between, so it sat entirely in the first column with the rest empty.
    group("a run written as one paragraph", () {
      var oneParagraph = List.generate(
              12, (i) => "This is sentence number $i and it runs on a while.")
          .join(" ");

      test("is split rather than left in the first column", () {
        var out = flowColumns(oneParagraph, 2);
        expect(out[0], isNotEmpty);
        expect(out[1], isNotEmpty, reason: "the second column is not empty");
      });

      test("is split near the middle", () {
        var out = flowColumns(oneParagraph, 2);
        expect(out[0].length, closeTo(out[1].length, oneParagraph.length / 4));
      });

      // The head finishes one column and the tail starts the next, each a
      // paragraph in its own right -- so the two read as prose carrying on
      // rather than as a paragraph with a hole in it.
      test("each piece is one paragraph, not several", () {
        var out = flowColumns(oneParagraph, 2);
        expect(out[0].contains("\n\n"), isFalse);
        expect(out[1].contains("\n\n"), isFalse);
      });

      test("the break falls at a sentence", () {
        var out = flowColumns(oneParagraph, 2);
        expect(out[0].trimRight(), endsWith("."));
        expect(out[1], startsWith("This is sentence number"));
      });

      test("nothing is lost", () {
        var out = flowColumns(oneParagraph, 3);
        expect(out.join(" ").split(RegExp(r"\s+")).join(" "),
            oneParagraph.split(RegExp(r"\s+")).join(" "));
      });

      // A sentence is the smallest piece there is: below that a column
      // would end mid-thought.
      test("a single sentence is never cut", () {
        var out = flowColumns("One sentence with no full stop inside it", 2);
        expect(out[0], "One sentence with no full stop inside it");
        expect(out[1], isEmpty);
      });
    });

    // Reported: a subtitle in a run broke the flow, and so did a picture
    // with text under it.
    //
    // Both were the same thing. A blank line used to be the only boundary,
    // so a heading written straight above its paragraph -- which is how
    // anyone writes one -- was one indivisible lump with everything under
    // it, and a column cannot be balanced against a lump.
    group("blocks are cut finely enough to balance", () {
      test("a heading is its own block", () {
        var out = flowColumns(
            "## Title\nFirst paragraph here, of a reasonable length.\n\n"
            "${"b" * 200}\n\n${"c" * 200}",
            2);
        expect(out[1], isNotEmpty);
        expect(out[0], startsWith("## Title"));
      });

      // A heading left at the foot of a column announces the next one.
      test("a heading is not left at the foot of a column", () {
        var out = flowColumns(
            "${"a" * 300}\n\n## Title\n\n${"b" * 300}\n\n${"c" * 300}", 2);
        expect(out[0].trimRight(), isNot(endsWith("## Title")));
        expect(out.any((c) => c.contains("## Title")), isTrue);
      });

      test("a picture with text under it is two blocks", () {
        var picture = "--embed[type=image/png,data=AAAA]--";
        var out = flowColumns(
            "$picture\nText directly under the picture.\n\n${"b" * 400}", 2,
            weigh: (b) => b.contains("--embed[") ? 400 : b.length.toDouble());
        expect(out[0], contains("--embed["));
        expect(out.join(" "), contains("Text directly under the picture."));
        expect(out[1], isNotEmpty);
      });

      test("a rule is its own block", () {
        var out = flowColumns("${"a" * 200}\n---\n${"b" * 200}", 2);
        expect(out.length, 2);
        expect(out[1], isNotEmpty);
      });
    });

    // Reported with the markdown that produced it: a picture on one line and
    // one long paragraph on the next, in a two column run, drew the picture
    // alone on the left and every word of the post on the right.
    //
    // Two separate rules had to be got past. The picture fits a column, so
    // "is this block oversized" said no about the paragraph beside it; and
    // with one block left and one column still to fill, the rule that keeps
    // a column from being empty stopped before the cut was ever considered
    // -- while the block it was saving was the only writing there was.
    group("a picture with one long paragraph beside it", () {
      // As long as the paragraph in the report, which is the size at which
      // the picture stops being a fair share of the column on its own.
      var prose = List.generate(
          24,
          (i) => "Ordinary body text sits here, sentence $i of it, and "
              "it runs on for a while yet.").join(" ");
      // 16:9, which is the shape a photograph usually arrives in.
      var picture =
          "--embed[type=image/png,data=${base64Encode(pngOf(1600, 900))}]--";

      List<String> flow(double width) => flowColumns("$picture\n$prose", 2,
          weigh: columnWeigher(width: width, body: _body, gap: 8));

      test("the paragraph carries on under the picture", () {
        for (var width in [300.0, 440.0, 600.0]) {
          var out = flow(width);
          expect(out[0], contains("--embed["), reason: "at $width");
          expect(out[0].replaceAll(RegExp(r'--embed\[.*?\]--'), "").trim(),
              isNotEmpty,
              reason: "at $width the picture is not alone in its column");
        }
      });

      test("the two columns come out near enough the same", () {
        var weigh = columnWeigher(width: 440, body: _body, gap: 8);
        var out = flow(440);
        var left = weigh(out[0]);
        var right = weigh(out[1]);
        expect(left, closeTo(right, math.max(left, right) * 0.35));
      });

      // The whole of the reported run: a heading, a picture, a long
      // paragraph and a short one. The heading and the picture are both
      // fixed heights the estimate gets right, so any error in the text
      // estimate landed entirely on the other column -- which is what left
      // the left column ending half way down the page.
      test("a heading, a picture and two paragraphs come out even", () {
        var second = "This is the problem with being wrong! A guide sets its "
            "line height and the space between paragraphs, and this is the "
            "second paragraph so that gap is visible rather than described.";
        for (var width in [300.0, 435.0, 600.0]) {
          var weigh = columnWeigher(width: width, body: _body, gap: 8);
          var out = flowColumns("## Title Area\n$picture\n$prose\n\n$second", 2,
              weigh: weigh);

          // Each column weighed as the blocks it holds, which is how the
          // flow weighed them -- measuring a whole column in one go reads
          // its opening heading as the style of everything under it.
          double weighColumn(String column) => column
              .split("\n\n")
              .where((b) => b.trim().isNotEmpty)
              .fold<double>(0, (a, b) => a + weigh(b));

          var left = weighColumn(out[0]);
          var right = weighColumn(out[1]);
          expect(out[0], contains("## Title Area"), reason: "at $width");
          expect(left, closeTo(right, math.max(left, right) * 0.25),
              reason: "at $width the two columns are within a quarter");
        }
      });

      // A picture too tall to share its column keeps it, which is the right
      // answer rather than a failure: there is nothing to put beside it.
      test("a picture as tall as a column keeps it to itself", () {
        var tall =
            "--embed[type=image/png,data=${base64Encode(pngOf(400, 600))}]--";
        var out = flowColumns("$tall\n$prose", 2,
            weigh: columnWeigher(width: 440, body: _body, gap: 8));
        expect(out[0], contains("--embed["));
        expect(out[1], contains("Ordinary body text"));
      });
    });

    // Reported as a regression: splitting was being reached for first, so a
    // run written with paragraph breaks had its paragraphs cut in half when
    // it had perfectly good boundaries of its own.
    group("paragraph breaks are respected where there are any", () {
      test("paragraphs are not cut when they need not be", () {
        var out = flowColumns(
            [for (var i = 0; i < 6; i++) "Paragraph $i. ${"x" * 100}"]
                .join("\n\n"),
            2);
        for (var column in out) {
          expect("Paragraph".allMatches(column).length,
              column.split("\n\n").length,
              reason: "one whole paragraph per block, none of them halves");
        }
      });

      test("a run of paragraphs still divides evenly", () {
        var out = flowColumns(
            [for (var i = 0; i < 6; i++) "x" * 100].join("\n\n"), 2);
        expect(out[0].split("\n\n").length, 3);
        expect(out[1].split("\n\n").length, 3);
      });
    });

    // Only prose is split. A list cut in half is two lists, and a table cut
    // in half is not a table at all.
    test("a list is never split", () {
      var list = "- one\n- two\n- three\n- four";
      var out = flowColumns("$list\n\nshort", 2);
      expect(out.any((c) => c.contains(list)), isTrue);
    });

    test("a fenced block is never split", () {
      var out = flowColumns(
          "```\nline one. line two. line three.\n```\n\nshort after", 2);
      expect(out.any((c) => c.contains("line one. line two. line three.")),
          isTrue);
    });
  });

  // Reported alongside it: a column with a picture at the top came out half
  // empty. Weighed by characters an embed counted for a fixed number of them
  // whatever its proportions, so a tall photograph and a thin banner filled
  // the same amount of column.
  group("weighing a block by how tall it will be drawn", () {
    var weigh = columnWeigher(width: 400, body: _body, gap: 8);
    String embed(int w, int h) =>
        "--embed[type=image/png,data=${base64Encode(pngOf(w, h))}]--";

    test("a tall picture weighs more than a wide one", () {
      expect(weigh(embed(200, 400)), greaterThan(weigh(embed(400, 100))));
    });

    test("a picture is weighed as the space it will take", () {
      // Square, across a 400 wide column: 400 tall, plus the block gap and
      // the space the guide leaves above and below a picture.
      expect(weigh(embed(200, 200)), closeTo(424, 8));
    });

    // A picture set to half the column is half as wide and so half as tall.
    // Weighed as though it filled the column it counted for nearly twice
    // the space it takes.
    test("a picture narrower than its column weighs less", () {
      var narrow = columnWeigher(
          width: 400,
          body: _body,
          gap: 8,
          image: const ImageRule(widthPercent: 50));
      expect(narrow(embed(200, 200)), lessThan(weigh(embed(200, 200)) / 1.5));
    });

    test("a wider column makes a picture taller, not shorter", () {
      var wide = columnWeigher(width: 800, body: _body, gap: 8);
      expect(wide(embed(200, 200)), greaterThan(weigh(embed(200, 200))));
    });

    test("more text weighs more", () {
      expect(weigh("a" * 400), greaterThan(weigh("a" * 100)));
    });

    // A wider column fits more on a line, so the same words are shorter.
    test("a wider column makes text shorter", () {
      var wide = columnWeigher(width: 800, body: _body, gap: 8);
      expect(wide("a" * 400), lessThan(weigh("a" * 400)));
    });

    test("a heading weighs more than the same words as body text", () {
      expect(weigh("# A heading here"), greaterThan(weigh("A heading here")));
    });

    // The one that was wrong on the page. Weighed flat, a picture counted
    // for the same as about 600 characters however large it was drawn, so a
    // column holding a big one and a line of text was called the equal of a
    // column holding a wall of prose -- and came out half empty.
    test("a large picture outweighs a wall of prose", () {
      // Portrait, across a 400 wide column: 800 tall, against 600
      // characters of body text at a fraction of that.
      expect(weigh(embed(400, 800)), greaterThan(weigh("a" * 600) * 2));
    });

    // Two pictures of different shapes used to weigh exactly the same.
    test("shape is what tells two pictures apart", () {
      expect(weigh(embed(400, 800)) - weigh(embed(400, 100)), greaterThan(600));
    });
  });

  group("flowing, end to end", () {
    testWidgets("a count with no separators is flowed", (tester) async {
      await _pump(tester,
          "--columns[2]--\n${"one " * 40}\n\n${"two " * 40}\n--/columns--");
      // Two columns' worth of MarkdownArea beneath the post's own.
      expect(find.byType(MarkdownArea).evaluate().length, 3);
    });

    // A separator is a decision the writer already made, so it wins -- and
    // it is how a break is forced in a run that would otherwise be balanced.
    /// _contentOf is the markdown one column was given.
    ///
    /// Read off the widget rather than measured on the page: an embedded
    /// picture has no size until its bytes have been decoded, which happens
    /// after layout, so measuring a column that holds one measures the text
    /// beside it and nothing else.
    String contentOf(WidgetTester tester, int column) => tester
        .widget<MarkdownArea>(find.byType(MarkdownArea).at(column + 1))
        .text;

    // Reported: one long paragraph with no blank lines in it landed entirely
    // in the first column, leaving the second empty.
    testWidgets("one long paragraph fills both columns", (tester) async {
      var prose = List.generate(
              20, (i) => "This is sentence number $i and it runs on a while.")
          .join(" ");
      await _pump(tester, "--columns[2]--\n$prose\n--/columns--");

      var left = contentOf(tester, 0);
      var right = contentOf(tester, 1);
      expect(right, isNotEmpty, reason: "the second column has writing in it");
      expect(left.length, closeTo(right.length, prose.length / 4));
      expect(left.trimRight(), endsWith("."),
          reason: "the break falls at a sentence");
    });

    // Reported alongside it: a picture in a column threw the balance out,
    // because it was weighed as a fixed number of characters rather than as
    // the space it was going to take.
    testWidgets("a picture is balanced against the prose beside it",
        (tester) async {
      // Room for what it draws: the test surface is 600 tall by default and
      // a picture with ten paragraphs beside it is more than that, which is
      // a complaint about the surface rather than about the balance.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var picture =
          "--embed[type=image/png,data=${base64Encode(pngOf(400, 300))}]--";
      var prose = [
        for (var i = 0; i < 10; i++)
          "Paragraph number $i, with enough words in it to wrap onto a "
              "second line of the column it lands in."
      ].join("\n\n");
      await _pump(tester, "--columns[2]--\n$picture\n\n$prose\n--/columns--");

      var left = contentOf(tester, 0);
      var right = contentOf(tester, 1);
      expect(left, contains("--embed["));
      expect(left, contains("Paragraph number"),
          reason: "the picture shares its column instead of filling it");
      // The picture is 4:3 across a 392 wide column, so about 294 tall --
      // roughly six of these paragraphs. The rest go beside it.
      expect("Paragraph number".allMatches(right).length, greaterThan(5));
    });

    testWidgets("separators win over the count", (tester) async {
      await _pump(
          tester, "--columns[3]--\nLeft.\n--col--\nRight.\n--/columns--");
      expect(find.byType(MarkdownArea).evaluate().length, 3,
          reason: "two columns, as written, not the three asked for");
    });
  });

  // A post arrives from somebody else, and each column is rendered by a
  // MarkdownArea that reads columns too -- so nesting is a way to build a
  // widget tree as deep as the post is long. Past the cap the markers are
  // shown as the text they are.
  group("nesting is bounded", () {
    testWidgets("a deeply nested run does not recurse forever", (tester) async {
      // Room for whatever it draws, so a layout complaint about the test's
      // own 800x600 surface cannot be mistaken for the thing being measured.
      tester.view.physicalSize = const Size(2400, 24000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var markdown = "innermost";
      for (var i = 0; i < 40; i++) {
        markdown = "--columns--\n$markdown\n--col--\nb\n--/columns--";
      }
      await _pump(tester, markdown, width: 2000);
      expect(tester.takeException(), isNull,
          reason: "forty deep is a post somebody else wrote, not a crash");
    });

    // Past the cap the markers are shown as the text they are, which is how
    // the descent is known to have stopped rather than merely been survived.
    testWidgets("past the cap the markup is shown as text", (tester) async {
      var markdown = "innermost";
      for (var i = 0; i < 6; i++) {
        markdown = "--columns--\n$markdown\n--col--\nb\n--/columns--";
      }
      await _pump(tester, markdown, width: 2000);
      expect(find.textContaining("--columns--"), findsWidgets);
    });
  });
}
