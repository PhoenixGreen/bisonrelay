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
      expect(got.color, MarkdownRole.accent);
      expect(got.radius, 8);
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

    test('a colour is a role, never a colour', () {
      // The same bargain the page background makes: a panel cannot know
      // whether its reader is in a dark theme, so a line it names #000000
      // is a line nobody in one can see.
      expect(PanelRule.parse("color=#ff0000").color, isNull);
      expect(PanelRule.parse("color=outline").color, MarkdownRole.outline);
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
      expect(PanelRule.parse("radius=0").radius, 0);
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
