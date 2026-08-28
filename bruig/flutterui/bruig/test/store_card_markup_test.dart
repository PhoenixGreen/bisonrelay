import 'package:bruig/components/feed/markdown_blocks.dart';
import 'package:bruig/components/feed/markdown_button.dart';
import 'package:bruig/components/feed/markdown_listing.dart';
import 'package:bruig/components/feed/markdown_qr.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:bruig/components/feed/markdown_panel.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/components/pages/forms.dart' as pf;
import 'dart:typed_data';

import 'package:bruig/models/pages.dart';
import 'package:bruig/models/payments.dart';
import 'package:bruig/theming_system/model/button_style.dart';
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

/// _Pages hands back bytes for any picture, so a panel drawing one has
/// something to draw. What is in them does not matter: nothing here looks at
/// the picture, only at the box it is given.
class _Pages extends PagesModel {
  _Pages() : super(ResourcesModel(runStream: false));

  @override
  Uint8List? localAssetBytes(String path) => Uint8List.fromList([1, 2, 3, 4]);
}

Widget wrap(Widget child) => MultiProvider(providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (_) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<PaymentsModel>(create: (_) => PaymentsModel()),
      ChangeNotifierProvider<SnackBarModel>(create: (_) => SnackBarModel()),
      ChangeNotifierProvider<ResourcesModel>(
          create: (_) => ResourcesModel(runStream: false)),
      ChangeNotifierProvider<PagesModel>(create: (_) => _Pages()),
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

    test('a fill and a border both take a role or a colour', () {
      // A role follows the reader's theme, which is why a page should name
      // one -- a line nobody in a dark theme can see is not a line. But the
      // fill and the border of a shop's own cards are what that shop is
      // coloured with, and a setting that cannot carry the colour somebody
      // chose is a setting they cannot use.
      expect(PanelRule.parse("fill=#101820").fill?.literal, isNotNull);
      expect(PanelRule.parse("color=#101820").color?.literal, isNotNull);
      expect(PanelRule.parse("fill=raised").fill?.role, MarkdownRole.raised);
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

    testWidgets('with no shape given, the picture is the width of the panel',
        (tester) async {
      // What made two of the four corners look broken. A picture left at its
      // own width sits at one end of a card that is stretched to its share
      // of the row, so the corners at the other end were cutting empty
      // space -- the setting saved, the markup was right, and half of it
      // did nothing anybody could see.
      await tester.pumpWidget(wrap(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MarkdownPanel(
            rule: PanelRule.parse("image=assets/g.png, radius=0 24 24 0"),
            child: const SizedBox.shrink(),
          ),
        ],
      )));
      await tester.pump();

      var picture = tester.widget<Image>(find.byType(Image));
      expect(picture.width, double.infinity);
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

  group('a grid the page can space itself', () {
    testWidgets('the gap between cells is the page\'s to set', (tester) async {
      // How far apart a gallery of photographs should be is a decision about
      // reading, and the reader's guide makes it. How far apart a row of
      // cards should be is a decision about the page they are on.
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(MarkdownArea(
          "--grid[2, gap=40]--\n--cell--\nOne\n--cell--\nTwo\n--/grid--\n",
          false)));
      await tester.pump();

      var one = tester.getRect(find.textContaining("One", findRichText: true));
      var two = tester.getRect(find.textContaining("Two", findRichText: true));
      expect(two.left - one.right, greaterThan(30),
          reason: "the gap the page asked for did not reach the grid");
    });

    test('a bare count still means what it always did', () {
      // Every gallery written before the settings existed says --grid[3]--.
      var doc = md.Document(blockSyntaxes: [GridBlockSyntax()]);
      var nodes = doc.parse("--grid[3]--\n![](a.png)\n--/grid--");
      var grid = (nodes.first as md.Element).children!.first as md.Element;
      expect(grid.attributes["columns"], "3");
      expect(grid.attributes["gap"], isNull);
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

  group('a listing: three rows and the thing to press', () {
    const rows = "--listing--\n"
        "title: First product\n"
        "link: product/1209391282\n"
        "summary: A longish product description. Features: - One - Two\n"
        "meta: \$659.99 · ≈ 26.3996 DCR\n"
        "button: Buy Now\n"
        "style: primary\n"
        "align: left\n"
        "--/listing--\n";

    test('the fields it was written with', () {
      var got = ListingRule.of(const {
        "title": "A guitar",
        "link": "product/gtr",
        "summary": "A lovely guitar",
        "meta": "\$20.00",
        "button": "Buy Now",
        "style": "primary",
        "align": "center",
      });
      expect(got.title, "A guitar");
      expect(got.summary, "A lovely guitar");
      expect(got.meta, "\$20.00");
      expect(got.role, ButtonRole.primary);
      expect(got.align, CrossAxisAlignment.center);
      expect(got.lines, 1);
    });

    testWidgets('the description is one line however narrow the card is',
        (tester) async {
      // The reason this is a block of its own. A paragraph wraps to whatever
      // width it is given, so on a card a third of a page wide the
      // description ran to four lines and pushed the price out of sight.
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          wrap(SizedBox(width: 200, child: MarkdownArea(rows, false))));
      await tester.pump();

      var summary = tester.widget<Text>(
          find.text("A longish product description. Features: - One - Two"));
      expect(summary.maxLines, 1);
      expect(summary.overflow, TextOverflow.ellipsis);
    });

    testWidgets('the price and the button stay on one row', (tester) async {
      // They were a run of columns, which stacks below a width the reader's
      // guide sets -- so on a card three across they stacked every time, and
      // the divider a run of columns draws put a rule between them.
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          wrap(SizedBox(width: 220, child: MarkdownArea(rows, false))));
      await tester.pump();

      var price = tester.getRect(find.textContaining("659.99"));
      var button =
          tester.getRect(find.widgetWithText(ElevatedButton, "Buy Now"));
      expect(price.center.dy, closeTo(button.center.dy, 12),
          reason: "the price and the button are not on one line");
      expect(price.left, lessThan(button.left),
          reason: "the price is not to the left of the button");
    });

    testWidgets('the title is set the way a link is set', (tester) async {
      // The plain card's title is written as Markdown and goes through the
      // reader's guide. This one does not, so colouring it by hand made
      // switching between the two layouts change the colour of the title --
      // the same thing, drawn twice, two ways.
      await tester.pumpWidget(wrap(MarkdownArea(rows, false)));
      await tester.pump();

      var context = tester.element(find.byType(MarkdownListing));
      // listen: false -- reading a model outside a build is what this is,
      // and Provider asserts on the listening form there.
      var theme = Provider.of<ThemeNotifier>(context, listen: false);
      var body = Theme.of(context).textTheme.bodyMedium;
      var title = tester.widget<Text>(find.text("First product"));

      expect(title.style!.color, theme.markdownLinkStyle(body).color);
    });

    testWidgets('the two gaps can differ', (tester) async {
      // They are different joins: the description belongs to the title above
      // it, while the price row is the end of the card.
      await tester.pumpWidget(wrap(MarkdownArea(
          rows.replaceFirst(
              "align: left\n", "align: left\ngap: 2\nmetagap: 16\n"),
          false)));
      await tester.pump();

      var heights = tester
          .widgetList<SizedBox>(find.descendant(
              of: find.byType(MarkdownListing),
              matching: find.byType(SizedBox)))
          .map((b) => b.height)
          .toList();
      expect(heights, containsAll([2.0, 16.0]));
    });

    testWidgets('a title can be held to one line', (tester) async {
      await tester.pumpWidget(wrap(MarkdownArea(
          rows.replaceFirst("align: left\n", "align: left\ntitlelines: 1\n"),
          false)));
      await tester.pump();

      var title = tester.widget<Text>(find.text("First product"));
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
    });

    testWidgets('a title wraps unless it is told not to', (tester) async {
      // Losing the end of a name is worse than a card an extra line tall,
      // unless the seller says otherwise.
      await tester.pumpWidget(wrap(MarkdownArea(rows, false)));
      await tester.pump();

      expect(tester.widget<Text>(find.text("First product")).maxLines, isNull);
    });

    testWidgets('the rows keep the gap they were given', (tester) async {
      await tester.pumpWidget(wrap(MarkdownArea(
          rows.replaceFirst("align: left\n", "align: left\ngap: 20\n"),
          false)));
      await tester.pump();

      var gaps = tester
          .widgetList<SizedBox>(find.descendant(
              of: find.byType(MarkdownListing),
              matching: find.byType(SizedBox)))
          .where((b) => b.height == 20);
      expect(gaps.length, 2,
          reason: "the gap goes between every row, not only the first two");
    });

    testWidgets('the button takes the colour and shape it was given',
        (tester) async {
      await tester.pumpWidget(wrap(MarkdownArea(
          "$rows".replaceFirst("style: primary\n",
              "style: primary\ncolor: #ffffffff\nradius: 20\npadding: 4\n"),
          false)));
      await tester.pump();

      var button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      var states = <WidgetState>{};
      expect(button.style!.backgroundColor!.resolve(states),
          const Color(0xffffffff));
      // A label that can be read on it: the roles carry a label colour that
      // suits their own fill, and a written colour carries none.
      expect(button.style!.foregroundColor!.resolve(states), Colors.black);

      var shape =
          button.style!.shape!.resolve(states) as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(20));
    });

    testWidgets('the title is larger than the writing under it',
        (tester) async {
      await tester.pumpWidget(wrap(MarkdownArea(rows, false)));
      await tester.pump();

      var title = tester.widget<Text>(find.text("First product"));
      var summary = tester.widget<Text>(
          find.text("A longish product description. Features: - One - Two"));
      expect(title.style!.fontSize!, greaterThan(summary.style!.fontSize!));
      expect(title.style!.fontWeight, FontWeight.bold);
    });
  });

  group('two blocks with nothing between them', () {
    testWidgets('a panel can close the gap between what is inside it',
        (tester) async {
      // The one piece of spacing a block cannot state for itself: a margin of
      // nought on two neighbours still leaves the renderer's own spacing, so
      // a plate told to sit flush against the picture above it sat a fixed
      // gap away however firmly it asked not to.
      Future<double> gapWith(String attrs) async {
        await tester.pumpWidget(wrap(MarkdownArea(
            "--panel[$attrs]--\n"
            "--panel[fill=raised]--\nOne\n--/panel--\n"
            "--panel[fill=raised]--\nTwo\n--/panel--\n"
            "--/panel--\n",
            false)));
        await tester.pump();
        var one =
            tester.getRect(find.textContaining("One", findRichText: true));
        var two =
            tester.getRect(find.textContaining("Two", findRichText: true));
        return two.top - one.bottom;
      }

      var flush = await gapWith("gap=0");
      var apart = await gapWith("gap=20");
      expect(apart - flush, closeTo(20, 1));
    });
  });

  group('an order as the store writes it', () {
    testWidgets('a line of an order draws its picture beside it',
        (tester) async {
      // A thumbnail on a row of a list -- an order line, a product in a
      // basket -- where the picture is what somebody recognises the row by
      // and the rows still have to line up.
      await tester.pumpWidget(wrap(MarkdownArea(
          "--listing--\n"
          "title: A guitar\n"
          "summary: 2 × \$20.00\n"
          "meta: \$40.00\n"
          "image: shopassets/g.jpg\n"
          "--/listing--\n",
          false)));
      await tester.pump();

      expect(find.text("A guitar"), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);

      var picture = tester.getRect(find.byType(Image));
      var title = tester.getRect(find.text("A guitar"));
      expect(picture.right, lessThanOrEqualTo(title.left),
          reason: "the picture is not beside the writing");
    });

    testWidgets('a line with no picture is just the writing', (tester) async {
      await tester.pumpWidget(wrap(MarkdownArea(
          "--listing--\ntitle: A drum\nmeta: \$5.00\n--/listing--\n", false)));
      await tester.pump();

      expect(find.byType(Image), findsNothing);
      expect(find.text("A drum"), findsOneWidget);
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

    // The fullest card the settings can ask for, pasted out of the Go side
    // exactly as productCard emits it: a border round the whole thing, a
    // picture filling it with its top corners rounded, a plate flush with
    // the foot of the picture, and three rows on the plate ending in a
    // button. Four panels deep with a run of columns inside them, which is
    // the arrangement most likely to hit a depth guard or a layout that
    // cannot measure itself.
    const dressed = "--grid[3]--\n"
        "--cell--\n"
        "--panel[border=1, color=outline, radius=8, padding=10, margin=0]--\n"
        "--panel[image=shopassets/g.jpg, ratio=400x400, crop=center, "
        "radius=8 8 0 0, link=product/gtr, align=bottom, justify=stretch, "
        "padding=0]--\n"
        "--panel[fill=raised, padding=10, margin=0, radius=8, text=center]--\n"
        "**[A guitar](product/gtr)**\n"
        "\n"
        "A lovely guitar with a spruce top.\n"
        "\n"
        "--columns[2]--\n"
        "\$20.00\n"
        "--col--\n"
        "--button[label=Buy Now, link=product/gtr, style=primary, align=right]--\n"
        "--/columns--\n"
        "--/panel--\n"
        "--/panel--\n"
        "--/panel--\n"
        "--/grid--\n";

    testWidgets('the fullest card the settings can ask for draws',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(MarkdownArea(dressed, false)));
      await tester.pump();

      expect(find.textContaining("A guitar", findRichText: true), findsWidgets);
      expect(find.textContaining("spruce top", findRichText: true),
          findsOneWidget);
      expect(
          find.textContaining("\$20.00", findRichText: true), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, "Buy Now"), findsOneWidget);
      expect(find.byType(MarkdownPanel), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

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

  group('a link drawn as a button', () {
    test('what it was written with', () {
      var got = ButtonRule.parse(
          "label=Buy Now, link=product/gtr, style=primary, align=right");
      expect(got.label, "Buy Now");
      expect(got.link, "product/gtr");
      expect(got.role, ButtonRole.primary);
      expect(got.align, Alignment.centerRight);
      expect(got.draws, isTrue);
    });

    test('a button with nothing to press is not drawn', () {
      // Going somewhere is the whole of what it does, so one with no link is
      // not a button; one with no label is nothing anybody can read.
      expect(ButtonRule.parse("label=Buy Now").draws, isFalse);
      expect(ButtonRule.parse("link=product/gtr").draws, isFalse);
    });

    testWidgets('it is pressed rather than read', (tester) async {
      await tester.pumpWidget(wrap(MarkdownArea(
          "--button[label=Buy Now, link=product/gtr, style=primary]--",
          false)));
      await tester.pump();

      expect(find.widgetWithText(ElevatedButton, "Buy Now"), findsOneWidget);
    });
  });

  group('a square somebody points a phone at', () {
    testWidgets('it carries exactly what it was given', (tester) async {
      // It draws a square and does not know what an address looks like: a
      // block that rewrote what it was handed would be a block that pays
      // somebody else.
      await tester.pumpWidget(wrap(MarkdownArea(
          "--qr[size=120]--\ndecred:DsAddr?amount=1.60000000\n--/qr--\n",
          false)));
      await tester.pump();

      // Read off the block rather than the code: qr_flutter keeps its data
      // private, and what is being pinned here is that the block passes on
      // what it was handed.
      var qr = tester.widget<MarkdownQr>(find.byType(MarkdownQr));
      expect(qr.data, "decred:DsAddr?amount=1.60000000");
      expect(qr.rule.size, 120);
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets('it is drawn on white whatever the theme', (tester) async {
      // A camera looks for dark on light. One drawn in a dark theme's own
      // colours is a square a phone will not read, and nothing on screen
      // would say why.
      await tester.pumpWidget(
          wrap(MarkdownArea("--qr--\ndecred:DsAddr\n--/qr--\n", false)));
      await tester.pump();

      var box = tester.widget<Container>(find.ancestor(
          of: find.byType(QrImageView), matching: find.byType(Container)));
      expect((box.decoration as BoxDecoration).color, Colors.white);
    });

    test('a size nothing can be drawn at is not taken', () {
      expect(QrRule.parse("size=10000").size, 180);
      expect(QrRule.parse("size=200").size, 200);
      expect(QrRule.parse("align=center").align, Alignment.center);
    });
  });

  group('a form that asks somebody to choose', () {
    testWidgets('a select offers its labels and carries its values',
        (tester) async {
      // The label is what the reader chooses between and the value is what
      // the page receives, because those are rarely the same: a shop asking
      // how somebody wants to pay wants "ln" and the buyer is choosing
      // "Lightning".
      var form = pf.FormElement([
        pf.FormField("action", value: "/placeOrder"),
        pf.FormField("select",
            name: "method",
            label: "How would you like to pay?",
            options: "ln|Lightning, onchain|On-chain"),
        pf.FormField("submit", label: "Place Order"),
      ]);
      await tester.pumpWidget(wrap(pf.CustomForm(form)));
      await tester.pumpAndSettle();

      // The first is the answer until somebody picks another: a field that
      // is null until it is touched behaves differently for somebody who
      // agreed with the default.
      var method = form.fields.firstWhere((f) => f.name == "method");
      expect(method.value, "ln");
      expect(find.text("Lightning"), findsOneWidget);

      await tester.tap(find.text("Lightning").last);
      await tester.pumpAndSettle();
      await tester.tap(find.text("On-chain").last);
      await tester.pumpAndSettle();

      expect(method.value, "onchain");
    });

    test('the choices are read the way they are written', () {
      var field = pf.FormField("select",
          options: "ln|Lightning — settles now, onchain|On-chain");
      expect(field.choices.length, 2);
      expect(field.choices.first.value, "ln");
      expect(field.choices.first.label, "Lightning — settles now");
      // A choice with no label of its own is its own label.
      expect(pf.FormField("select", options: "one, two").choices.last.label,
          "two");
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
