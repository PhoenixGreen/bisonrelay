import 'package:bruig/components/feed/markdown_panel.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/models/payments.dart';
import 'package:bruig/theming_system/model/markdown_style.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// markdown_panel_test.dart covers --panel--, a box drawn round a piece of a
// page.
//
// Not --section--: a page's reply regions are written --section id=x -- ...
// --/section--, and every --/section-- is stripped before a page is drawn.
// A box sharing that closing line would have it taken away from underneath.

Widget wrap(String md) => MultiProvider(providers: [
      ChangeNotifierProvider<ThemeNotifier>(create: (_) => ThemeNotifier()),
      ChangeNotifierProvider<PaymentsModel>(create: (_) => PaymentsModel()),
      ChangeNotifierProvider<MarkdownAreaModel>(
          create: (_) => MarkdownAreaModel("")),
    ], child: MaterialApp(
        home: Scaffold(
            body: Align(
                alignment: Alignment.topLeft, child: MarkdownArea(md, false)))));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('what a panel asked for', () {
    test('a bare panel asks for nothing', () {
      expect(PanelRule.parse(null), PanelRule.none);
      expect(PanelRule.parse(""), PanelRule.none);
    });

    test('the settings it states', () {
      var got = PanelRule.parse(
          "padding=16, margin=8, border=2, style=dashed, color=accent, "
          "radius=8");
      expect(got.padding, const EdgeInsets.all(16));
      expect(got.margin, const EdgeInsets.all(8));
      expect(got.border, const EdgeInsets.all(2));
      expect(got.stroke, PanelStroke.dashed);
      expect(got.color?.role, MarkdownRole.accent);
      expect(got.radius, BorderRadius.circular(8));
    });

    test('a border can be one side only', () {
      // A rule across the top of a block and a card outlined all round are
      // the same thing asked for differently. Having to write two blocks to
      // get one line is how a table ends up used as a border.
      expect(PanelRule.parse("border=1 0 0 0").border,
          const EdgeInsets.only(top: 1));
    });

    test('padding and border are written the same way', () {
      // Two ways of writing the same thing in one block is two things to
      // remember.
      expect(PanelRule.parse("border=1 2").border,
          const EdgeInsets.symmetric(vertical: 1, horizontal: 2));
      expect(PanelRule.parse("padding=1 2").padding,
          const EdgeInsets.symmetric(vertical: 1, horizontal: 2));
    });

    test('a colour may be a role or a colour, and a role is the better one',
        () {
      // A role follows the reader's theme, which is the bargain the page
      // background makes and the reason a line should name one: #000000 is a
      // line nobody in a dark theme can see. A written colour is carried all
      // the same -- somebody putting a border round their own shop's cards
      // has a particular colour in mind, and refusing it only meant the
      // border went unused.
      expect(PanelRule.parse("color=outline").color?.role, MarkdownRole.outline);
      expect(PanelRule.parse("color=#ff0000").color?.literal, isNotNull);
      expect(PanelRule.parse("color=puce").color, isNull);
    });

    test('corners can be given one by one', () {
      // A picture at the top of a card is rounded at the top and square
      // where the writing meets it. One number for all four cannot draw
      // that, and a card built out of two boxes to get it has a seam.
      expect(PanelRule.parse("radius=8 8 0 0").radius,
          const BorderRadius.only(
              topLeft: Radius.circular(8), topRight: Radius.circular(8)));
      expect(PanelRule.parse("radius=8").radius, BorderRadius.circular(8));
    });

    test('a panel says how wide its content is and which way it reads', () {
      var got = PanelRule.parse("justify=right, text=center");
      expect(got.justify, PanelJustify.right);
      expect(got.text, WrapAlignment.center);
      expect(PanelRule.parse("").justify, PanelJustify.stretch,
          reason: "a block of a page has always been the full width of it");
      expect(PanelRule.parse("").text, isNull);
    });

    test('a stroke it does not know is a solid line', () {
      expect(PanelRule.parse("style=squiggly").stroke, PanelStroke.solid);
      expect(PanelRule.parse("style=none").stroke, PanelStroke.none);
    });

    test('one bad setting does not spoil the panel', () {
      var got = PanelRule.parse("padding=16, radius=round");
      expect(got.padding, const EdgeInsets.all(16));
      expect(got.radius, isNull);
    });

    test('a setting it does not know is ignored, not guessed at', () {
      expect(PanelRule.parse("colour=outline").color, isNull);
    });

    test('nought is an answer', () {
      expect(PanelRule.parse("padding=0").padding, EdgeInsets.zero);
      expect(PanelRule.parse("radius=0").radius, BorderRadius.zero);
    });
  });

  group('a border on one side only', () {
    test('is what four numbers mean, clockwise from the top', () {
      // border=0 0 0 5 is a rule down the left, written the way padding is.
      expect(PanelRule.parse("border=0 0 0 5").border,
          const EdgeInsets.only(left: 5));
      expect(PanelRule.parse("border=5 0 0 0").border,
          const EdgeInsets.only(top: 5));
    });

    testWidgets('draws, dashed as well as solid', (tester) async {
      // Dashed borders read a thickness to draw at. Reading one number for
      // all four sides, a panel asking for a rule down its left asked for a
      // line 0 thick and got nothing -- which looked like dashed borders
      // being broken rather than like this.
      for (var style in ["solid", "dashed", "dotted"]) {
        await tester.pumpWidget(wrap(
            "--panel[border=0 0 0 5, style=$style]--\nInside\n--/panel--"));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: style);
        expect(find.textContaining("Inside", findRichText: true), findsWidgets,
            reason: style);
      }
    });
  });

  group('drawing one', () {
    testWidgets('the content inside it is rendered', (tester) async {
      await tester.pumpWidget(wrap("--panel[padding=8]--\n# Inside\n--/panel--"));
      await tester.pumpAndSettle();
      expect(find.textContaining("Inside", findRichText: true), findsWidgets);
    });

    testWidgets('the block lines are not left as writing', (tester) async {
      await tester.pumpWidget(wrap("--panel[padding=8]--\nInside\n--/panel--"));
      await tester.pumpAndSettle();
      var shown = find
          .byType(RichText)
          .evaluate()
          .map((e) => (e.widget as RichText).text.toPlainText())
          .join(" ");
      expect(shown, contains("Inside"));
      expect(shown, isNot(contains("--panel")));
      expect(shown, isNot(contains("padding")));
    });

    testWidgets('a panel can hold a panel', (tester) async {
      // The closing line has to be matched to the one that opened it. Matched
      // to the first one seen, the outer panel ends at the inner panel's
      // close and the rest of it spills onto the page.
      await tester.pumpWidget(wrap("--panel[padding=8]--\n"
          "--panel[padding=4]--\nDeep\n--/panel--\n"
          "Shallow\n--/panel--"));
      await tester.pumpAndSettle();
      var shown = find
          .byType(RichText)
          .evaluate()
          .map((e) => (e.widget as RichText).text.toPlainText())
          .join(" ");
      expect(shown, contains("Deep"));
      expect(shown, contains("Shallow"));
      expect(shown, isNot(contains("--/panel--")));
    });

    testWidgets('a panel with no settings still draws its content',
        (tester) async {
      await tester.pumpWidget(wrap("--panel--\nPlain\n--/panel--"));
      await tester.pumpAndSettle();
      expect(find.textContaining("Plain", findRichText: true), findsWidgets);
    });
  });
}
