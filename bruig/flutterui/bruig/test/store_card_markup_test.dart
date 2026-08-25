import 'package:bruig/components/feed/markdown_blocks.dart';
import 'package:bruig/components/feed/markdown_panel.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/components/pages/forms.dart' as pf;
import 'package:bruig/models/payments.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/model/markdown_style.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// store_card_markup_test.dart covers the page markup a shop front is written
// as: a panel with a picture behind it, a grid divided where the writer said,
// and a form whose button says how much weight it carries.
//
// None of it is about selling. A card is a box with a picture behind it and a
// link on the whole of it, which is what a banner, a link card and a gallery
// tile are too -- so the store writes markup any page may write, and this
// covers the markup rather than the shop.

Widget wrap(Widget child) => MultiProvider(providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (_) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<PaymentsModel>(create: (_) => PaymentsModel()),
      ChangeNotifierProvider<SnackBarModel>(create: (_) => SnackBarModel()),
      ChangeNotifierProvider<ResourcesModel>(
          create: (_) => ResourcesModel(runStream: false)),
      ChangeNotifierProvider<MarkdownAreaModel>(
          create: (_) => MarkdownAreaModel("")),
    ], child: MaterialApp(home: Scaffold(body: child)));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('a panel with a picture behind it', () {
    test('the settings a card is written with', () {
      var got = PanelRule.parse("image=shopassets/guitar.jpg, ratio=600x400, "
          "crop=topleft, link=product/gtr, align=bottom, fill=raised");
      expect(got.image, "shopassets/guitar.jpg");
      expect(got.ratio, closeTo(1.5, 0.001));
      expect(got.crop, Alignment.topLeft);
      expect(got.link, "product/gtr");
      expect(got.align, Alignment.bottomCenter);
      expect(got.fill?.role, MarkdownRole.raised);
    });

    test('a fill may be a colour, unlike a border', () {
      // A border names a role and never a colour, because a line nobody in a
      // dark theme can see is not a line. A fill is what a seller colours
      // their own shop front with, so it takes either -- and the role is
      // still the better answer, because it follows the reader's theme.
      expect(PanelRule.parse("fill=#101820").fill?.literal, isNotNull);
      expect(PanelRule.parse("color=#101820").color, isNull);
    });

    test('a shape may be given either way round', () {
      expect(PanelRule.parse("ratio=400x400").ratio, 1);
      expect(PanelRule.parse("ratio=1.5").ratio, 1.5);
    });

    test('a shape nothing can be drawn at is not taken', () {
      // A panel a hundred times wider than it is tall is a hairline, from a
      // number somebody typed into a settings field.
      expect(PanelRule.parse("ratio=1000x1").ratio, 8);
      expect(PanelRule.parse("ratio=1x1000").ratio, 1 / 8);
      expect(PanelRule.parse("ratio=0x400").ratio, isNull);
      expect(PanelRule.parse("ratio=wide").ratio, isNull);
    });

    test('a background is one of this site\'s own files, never a URL', () {
      // What is drawn behind a panel is fetched from whoever served the
      // page. A background that could name a URL would be every page able to
      // ask its reader's client to fetch from anywhere.
      expect(PanelRule.parse("image=https://example.com/x.png").image, isNull);
      expect(
          PanelRule.parse("image=shopassets/x.png").image, "shopassets/x.png");
    });

    testWidgets('a shape asked for is the shape it is drawn at',
        (tester) async {
      await tester.pumpWidget(wrap(const MarkdownPanel(
        rule: PanelRule(ratio: 1.5, image: "shopassets/guitar.jpg"),
        child: SizedBox.shrink(),
      )));
      await tester.pump();

      var box = tester.widget<AspectRatio>(find.byType(AspectRatio));
      expect(box.aspectRatio, 1.5);
    });

    testWidgets('a panel with nothing asked for is left as it was',
        (tester) async {
      // The plain block a panel was before any of this: no stack, no clip,
      // nothing measured.
      await tester.pumpWidget(
          wrap(const MarkdownPanel(rule: PanelRule(), child: Text("plain"))));
      await tester.pump();
      expect(find.byType(AspectRatio), findsNothing);
      expect(
          find.descendant(
              of: find.byType(MarkdownPanel), matching: find.byType(Stack)),
          findsNothing);
    });

    testWidgets('the whole panel is the link', (tester) async {
      // Somebody looking at a shop front and tapping the picture of the
      // thing they want has said what they want. Before this that tap did
      // nothing: only the title underneath was a link.
      await tester.pumpWidget(wrap(const MarkdownPanel(
        rule: PanelRule(link: "product/gtr", ratio: 1),
        child: SizedBox.shrink(),
      )));
      await tester.pump();

      var tap = tester.widget<GestureDetector>(find.descendant(
          of: find.byType(MarkdownPanel),
          matching: find.byType(GestureDetector)));
      expect(tap.onTap, isNotNull);
      expect(tap.behavior, HitTestBehavior.opaque,
          reason: "a card whose margins ignore taps is a card that ignores "
              "half the taps aimed at it");
    });
  });

  group('a grid divided where the writer said', () {
    test('--cell-- opens a cell whatever is in it', () {
      var cells = GridBlockSyntax.splitCells([
        "--cell--",
        "**[A guitar](product/gtr)**",
        "--panel[image=shopassets/guitar.jpg]--",
        "--/panel--",
        "--cell--",
        "**[A drum](product/drm)**",
      ]);
      expect(cells.length, 2);
      expect(cells.first, contains("A guitar"));
      expect(cells.last, contains("A drum"));
    });

    test('a marker is consumed rather than drawn', () {
      var cells = GridBlockSyntax.splitCells(["--cell--", "one"]);
      expect(cells, ["one"]);
    });

    test('the markers win where there are any', () {
      // A card with a picture in the middle of it would otherwise be divided
      // in half by the picture -- and a writer who has said where the cells
      // are has already answered the question that guess was for.
      var cells = GridBlockSyntax.splitCells([
        "--cell--",
        "![](a.png)",
        "some writing",
        "![](b.png)",
      ]);
      expect(cells.length, 1);
    });

    test('a gallery with no markers still divides at its pictures', () {
      var cells = GridBlockSyntax.splitCells([
        "![](a.png)",
        "A caption",
        "![](b.png)",
        "Another",
      ]);
      expect(cells.length, 2);
    });
  });

  group('a shop front as the store writes it', () {
    // The markup below is what simplestore's productCard emits, pasted as it
    // comes out. The two are covered separately -- Go for what is written,
    // this for what is drawn -- and this is where they are checked to be the
    // same language.
    const front = "--grid[3]--\n"
        "--cell--\n"
        "--panel[image=shopassets/guitar.jpg, ratio=400x400, crop=center, "
        "link=product/gtr]--\n"
        "--/panel--\n"
        "**[A guitar](product/gtr)**\n"
        "\$20.00\n"
        "\n"
        "--cell--\n"
        "--panel[image=shopassets/placeholder.png, ratio=400x400, crop=center, "
        "link=product/drm]--\n"
        "--/panel--\n"
        "**[A drum](product/drm)**\n"
        "\$30.00\n"
        "\n"
        "--/grid--\n";

    testWidgets('every product is one card, and every card is a link',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(MarkdownArea(front, false)));
      await tester.pump();

      expect(find.byType(MarkdownPanel), findsNWidgets(2));
      // Rich text: the title is a link inside a paragraph rather than a
      // Text of its own.
      expect(
          find.textContaining("A guitar", findRichText: true), findsOneWidget);
      expect(find.textContaining("A drum", findRichText: true), findsOneWidget);

      // The writing of one card must not have joined the card before it,
      // which is what happens to a grid that divides itself at pictures when
      // a card puts its picture somewhere else.
      expect(find.byType(AspectRatio), findsNWidgets(2));
    });
  });

  group('what a form\'s button carries', () {
    md.Element? parseForm(String text) {
      var doc = md.Document(blockSyntaxes: [pf.FormBlockSyntax()]);
      var nodes = doc.parse(text);
      for (var node in nodes) {
        if (node is md.Element && node.children != null) {
          for (var child in node.children!) {
            if (child is pf.FormElement) return child;
          }
        }
      }
      return null;
    }

    test('a form may say which side its button sits on', () {
      var form = parseForm('--form[align=right]--\n'
          'type="action" value="/clearCart"\n'
          'type="submit" label="Clear Cart"\n'
          '--/form--') as pf.FormElement?;
      expect(form, isNotNull);
      expect(form!.align, "right");
    });

    test('a form with no settings is still a form', () {
      var form = parseForm('--form--\n'
          'type="submit" label="Update"\n'
          '--/form--') as pf.FormElement?;
      expect(form, isNotNull);
      expect(form!.align, "");
    });

    test('a submit carries what it is drawn as and what it asks', () {
      var form = parseForm('--form--\n'
          'type="action" value="/placeOrder"\n'
          'type="submit" label="Place Order" style="primary" '
          'confirm="Place this order for \$20.00?"\n'
          '--/form--') as pf.FormElement?;
      var submit = form!.fields.firstWhere((f) => f.type == "submit");
      expect(submit.style, "primary");
      expect(submit.confirm, "Place this order for \$20.00?");
    });

    testWidgets('a submit that asks does nothing until it is answered',
        (tester) async {
      var form = pf.FormElement([
        pf.FormField("action", value: "/clearCart"),
        pf.FormField("submit",
            label: "Clear Cart",
            style: "danger",
            confirm: "Take everything out of your cart?"),
      ]);
      await tester.pumpWidget(wrap(pf.CustomForm(form)));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Clear Cart"));
      await tester.pumpAndSettle();

      expect(find.text("Take everything out of your cart?"), findsOneWidget);
      expect(find.text("Cancel"), findsOneWidget);

      await tester.tap(find.text("Cancel"));
      await tester.pumpAndSettle();
      expect(find.text("Take everything out of your cart?"), findsNothing);
    });

    testWidgets('a submit with no question just does it', (tester) async {
      // A dialog in front of every form is a page nobody can use: adding
      // something to a cart and changing a quantity are not acts anybody
      // needs warning about.
      var form = pf.FormElement([
        pf.FormField("action", value: "/setCartQty"),
        pf.FormField("submit", label: "Update"),
      ]);
      await tester.pumpWidget(wrap(pf.CustomForm(form)));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Update"));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
