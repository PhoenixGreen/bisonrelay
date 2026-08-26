import 'package:bruig/models/pages.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/models/store.dart';
import 'package:bruig/screens/pages/store/store_front_fields.dart';
import 'package:bruig/theming_system/editor/editor_controls.dart';
import 'package:bruig/theming_system/model/markdown_style.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// store_front_settings_test.dart is about the controls being wired to
// something.
//
// A model test would pass with every one of these switches drawn and
// connected to nothing: the model is right, and the settings it holds are the
// ones the store reads. What has to be true as well is that a seller who
// turns a switch on has changed their shop -- which is a thing only a test
// that presses it can say.

class _Pages extends PagesModel {
  _Pages() : super(ResourcesModel(runStream: false));

  @override
  PagesHostConfig get hostConfig =>
      PagesHostConfig(pagesHostModeStore, "", "/store", "ln", "", 0, "");

  @override
  Future<void> loadHost() async {}
}

/// _Store is a shop with no golib behind it: what is saved is kept here, and
/// the corrections the store would make are not made.
class _Store extends StoreModel {
  _Store(super.pages, {this.template = _shipped});

  /// template is the shop's front page. The shipped one by default: a shop
  /// whose front page is up to date is the case every other test here is
  /// about.
  final String template;

  @override
  String get indexTemplate => template;

  StoreIndexLayout saved = const StoreIndexLayout();
  int saves = 0;

  @override
  StoreIndexLayout get indexLayout => saved;

  @override
  Future<void> setIndexLayout(StoreIndexLayout layout) async {
    saved = layout;
    saves++;
    notifyListeners();
  }

  @override
  Future<void> loadStore() async {}
}

/// drag moves the slider named [name] to [value] and waits for the save.
///
/// By its label rather than its position: these come and go as settings are
/// switched on, and finding one by index is how a test ends up driving a
/// different control from the one it names.
/// drag moves the slider labelled [label] to [value] and waits for the save.
///
/// Found by the key the cell carries rather than by where it sits: these come
/// and go as settings are switched on, and finding one by position is how a
/// test ends up driving a different control from the one it names.
///
/// Driven through the slider's own callbacks rather than by dragging across
/// it. A drag has to land on a pixel, and what is being tested is that moving
/// this control saves this setting -- not Flutter's hit testing.
Future<void> drag(WidgetTester tester, String name, int value) async {
  var slider = find.descendant(
      of: find.byKey(ValueKey("store-front/$name")),
      matching: find.byType(Slider));
  expect(slider, findsOneWidget, reason: "no slider named $name");

  var widget = tester.widget<Slider>(slider);
  widget.onChanged!(value.toDouble());
  // The theme editor's slider commits when the drag ends, not once per
  // frame: each commit writes the shop's settings file.
  widget.onChangeEnd!(value.toDouble());
  await tester.pumpAndSettle();
}

/// _shipped is enough of the shipped front page to be recognised as one.
const _shipped = "{{ storePage }}\n{{ storeGrid }}\n{{ productCard . }}\n";

void main() {
  group('the colours a plate may take', () {
    // A palette holds a slot per job rather than a colour per slot, so the
    // same colour sits in several of them: three are seeded to the master
    // background in a fresh theme. Two entries offering the same colour is
    // not a choice anybody can make, and a dropdown asserts outright that its
    // value matches exactly one of its items -- so the second slot holding
    // the colour the shop had chosen took the settings page down with it.
    test('a colour held by two palette slots is offered once', () {
      var repeated = const Color(0xff262626);
      var choices = colorChoices(
          [repeated, repeated, const Color(0xff884400)], "#262626");

      var values = choices.map((c) => c.value).toList();
      expect(values.toSet().length, values.length,
          reason: "a dropdown with two items of one value asserts");
      expect(values.where((v) => v == "#262626").length, 1);
    });

    test('the roles come first and are all there', () {
      var choices = colorChoices(const [], "raised");
      expect(choices.length, MarkdownRole.values.length);
      expect(choices.first.role, MarkdownRole.text);
      expect(choices.any((c) => c.value == "raised"), isTrue);
    });

    test('a colour the shop holds that is not offered is added', () {
      // Written into the file by hand, or picked from a palette this client
      // no longer has. Offered as itself rather than silently becoming
      // another colour -- and still only once.
      var choices = colorChoices(const [Color(0xff884400)], "#123456");
      expect(choices.first.value, "#123456");
      expect(choices.where((c) => c.value == "#123456").length, 1);
    });

    test('a colour the shop holds that is already offered is not added twice',
        () {
      var choices = colorChoices(const [Color(0xff884400)], "#884400");
      expect(choices.where((c) => c.value == "#884400").length, 1);
    });
  });

  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_Store> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var shop = _Store(_Pages());
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<StoreModel>.value(value: shop),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: Consumer<StoreModel>(
                        builder: (context, store, _) =>
                            StoreFrontFields(store: store)))))));
    await tester.pumpAndSettle();
    return shop;
  }

  testWidgets('turning one shape on saves it and offers the shape',
      (tester) async {
    var shop = await pump(tester);
    expect(find.text("Crop from: "), findsNothing,
        reason: "nothing to crop until every picture is one shape");

    await tester.tap(find.text("Draw every picture at the same shape"));
    await tester.pumpAndSettle();

    expect(shop.saved.fixedImage, isTrue);
    expect(find.text("Crop from: "), findsOneWidget);
    expect(find.text("Shape: "), findsOneWidget);
  });

  testWidgets('the crop is chosen from a list rather than typed',
      (tester) async {
    var shop = await pump(tester);
    await tester.tap(find.text("Draw every picture at the same shape"));
    await tester.pumpAndSettle();

    // The dropdown is opened by its current answer, which is what a seller
    // sees and presses.
    await tester.tap(find.text("Centre").last);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Top left").last);
    await tester.pumpAndSettle();

    expect(shop.saved.crop, "topleft");
  });

  testWidgets('the writing can be placed only on a card it is on',
      (tester) async {
    // Where the writing sits is a question about a card whose picture is
    // behind all of it. On the other two the picture and the writing are
    // stacked, and where the writing is is which of them.
    var shop = await pump(tester);
    expect(find.text("Where the writing sits on it: "), findsNothing);

    await tester.tap(find.text("Above the writing").last);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Behind the whole card").last);
    await tester.pumpAndSettle();

    expect(shop.saved.imagePosition, "full");
    expect(find.text("Where the writing sits on it: "), findsOneWidget);
  });

  testWidgets('the plate behind the writing brings its own settings',
      (tester) async {
    var shop = await pump(tester);
    expect(find.text("Plate colour"), findsNothing);

    await tester.tap(find.text("Draw a plate behind the writing"));
    await tester.pumpAndSettle();

    expect(shop.saved.textBackground, isTrue);
    for (var field in ["Plate colour: ", "Padding", "Corner radius"]) {
      expect(find.text(field), findsOneWidget, reason: "$field is missing");
    }
  });

  testWidgets('a border round the card brings its own settings',
      (tester) async {
    var shop = await pump(tester);
    expect(find.text("Border width"), findsNothing);

    await tester.tap(find.text("Draw a border round each product"));
    await tester.pumpAndSettle();

    expect(shop.saved.cardBorder, isTrue);
    for (var field in [
      "Border width",
      "Border colour: ",
      "Padding",
      "Margin"
    ]) {
      expect(find.text(field), findsWidgets, reason: "$field is missing");
    }
  });

  testWidgets('the corners are one number until they are four', (tester) async {
    // A seller who wants all four the same should not have to type the same
    // number four times, and one who wants a picture rounded at the top and
    // square at the bottom cannot say that with one number at all.
    var shop = await pump(tester);
    expect(find.text("Picture corners"), findsOneWidget);
    expect(find.text("Top left"), findsNothing);

    await drag(tester, "corners", 12);

    expect(shop.saved.imageCornerTopLeft, 12);
    expect(shop.saved.imageCornerBottomRight, 12,
        reason: "one number sets all four");

    await tester.tap(find.text("Set the picture's corners one by one"));
    await tester.pumpAndSettle();
    expect(find.text("Top left"), findsOneWidget);

    // Each corner on its own, and each one keeping what the last set. This
    // is what the text boxes could not do: they saved on losing focus,
    // Flutter delivers that to every box on the page, and a box that had
    // just appeared in another box's position was handed its text.
    await drag(tester, "corner-tr", 20);
    await drag(tester, "corner-br", 4);

    expect(shop.saved.imageCornerTopLeft, 12);
    expect(shop.saved.imageCornerTopRight, 20);
    expect(shop.saved.imageCornerBottomRight, 4);
    expect(shop.saved.imageCornerBottomLeft, 12,
        reason: "a corner nobody touched was changed by one that was");
  });

  testWidgets('the three-row card offers what its button says', (tester) async {
    var shop = await pump(tester);
    expect(
        find.widgetWithText(TextField, "What the button says"), findsNothing);

    await tester.tap(find.text("Title and price").last);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Title, description, price and a button").last);
    await tester.pumpAndSettle();

    expect(shop.saved.textLayout, "rows");
    expect(
        find.widgetWithText(TextField, "What the button says"), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, "What the button says"), "Add to cart");
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(shop.saved.buttonLabel, "Add to cart");
  });

  testWidgets('flush is offered wherever there is a picture to sit against',
      (tester) async {
    // It was offered only for a picture behind the whole card. A plate under
    // a picture touches its bottom edge just as much.
    var shop = await pump(tester);
    await tester.tap(find.text("Draw a plate behind the writing"));
    await tester.pumpAndSettle();
    expect(find.text("Sit it flush with the picture's edge"), findsOneWidget);

    await tester.tap(find.text("Above the writing").last);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Below the writing").last);
    await tester.pumpAndSettle();

    expect(shop.saved.imagePosition, "bottom");
    expect(find.text("Sit it flush with the picture's edge"), findsOneWidget);
  });

  testWidgets('which side the writing sits on is asked of both cards',
      (tester) async {
    // Both: the three-row card places its own rows, but which side those
    // rows sit on is as much a question there as on the plain one.
    var shop = await pump(tester);
    expect(find.text("Which side the writing sits on: "), findsOneWidget);

    await tester.tap(find.text("Title and price").last);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Title, description, price and a button").last);
    await tester.pumpAndSettle();

    expect(shop.saved.textLayout, "rows");
    expect(find.text("Which side the writing sits on: "), findsOneWidget);
  });

  testWidgets('the three-row card brings the button\'s own settings',
      (tester) async {
    var shop = await pump(tester);
    expect(find.text("The button"), findsNothing);

    await tester.tap(find.text("Title and price").last);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Title, description, price and a button").last);
    await tester.pumpAndSettle();

    expect(find.text("The button"), findsOneWidget);
    expect(find.text("Button colour: "), findsOneWidget);
    expect(find.text("Above the price"), findsOneWidget);

    await drag(tester, "meta-gap", 14);
    expect(shop.saved.metaGap, 14);

    await drag(tester, "button-radius", 20);
    expect(shop.saved.buttonRadius, 20,
        reason: "the button's corners were not the ones that moved");
  });

  testWidgets('turning flush off gives the plate somewhere to stand off to',
      (tester) async {
    // A shop whose margin is nought saw nothing happen: the setting saved,
    // and both states drew the same card.
    var shop = await pump(tester);
    await tester.tap(find.text("Draw a plate behind the writing"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Above the writing").last);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Behind the whole card").last);
    await tester.pumpAndSettle();

    expect(shop.saved.textMargin, 0);

    await tester.tap(find.text("Sit it flush with the picture's edge"));
    await tester.pumpAndSettle();
    expect(shop.saved.textFlush, isTrue);
    expect(find.text("Gap from the picture"), findsNothing,
        reason: "a plate sitting flush has no gap to set");

    await tester.tap(find.text("Sit it flush with the picture's edge"));
    await tester.pumpAndSettle();
    expect(shop.saved.textFlush, isFalse);
    expect(shop.saved.textMargin, greaterThan(0),
        reason: "off means standing off, and nought is not standing off");
    expect(find.text("Gap from the picture"), findsOneWidget);
  });

  testWidgets('the grid is set from the shop rather than the reader',
      (tester) async {
    // How far apart a gallery of photographs should be is the reader's own
    // guide. How far apart a row of cards should be is the shop's, and on a
    // phone it is the difference between three across and two.
    var shop = await pump(tester);
    expect(find.text("The grid"), findsOneWidget);

    await drag(tester, "grid-gap", 12);
    await drag(tester, "grid-margin", 8);
    expect(shop.saved.gridGap, 12);
    expect(shop.saved.gridMargin, 8);
  });

  testWidgets('the two row gaps are one control until they are two',
      (tester) async {
    var shop = await pump(tester);
    await tester.tap(find.text("Title and price").last);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Title, description, price and a button").last);
    await tester.pumpAndSettle();

    // Apart to begin with, because the defaults differ: the description sits
    // closer under the title than the price row does under it.
    expect(find.text("Above the description"), findsOneWidget);
    await drag(tester, "meta-gap", 16);
    expect(shop.saved.metaGap, 16);
    expect(shop.saved.rowGap, isNot(16), reason: "one gap moved the other");

    await tester.tap(find.text("Set the space above each row separately"));
    await tester.pumpAndSettle();
    expect(find.text("Space between rows"), findsOneWidget);
    expect(shop.saved.metaGap, shop.saved.rowGap,
        reason: "brought back together, one number must draw one gap");

    await drag(tester, "row-gap", 10);
    expect(shop.saved.rowGap, 10);
    expect(shop.saved.metaGap, 10);
  });

  testWidgets('a product name can be held to one line', (tester) async {
    var shop = await pump(tester);
    await tester.tap(find.text("Title and price").last);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Title, description, price and a button").last);
    await tester.pumpAndSettle();

    expect(shop.indexLayout.titleOneLine, isFalse);
    await tester.tap(find.text("Keep a product's name to one line"));
    await tester.pumpAndSettle();
    expect(shop.saved.titleOneLine, isTrue);
  });

  testWidgets('the plate\'s padding is one number until it is four',
      (tester) async {
    var shop = await pump(tester);
    await tester.tap(find.text("Draw a plate behind the writing"));
    await tester.pumpAndSettle();

    expect(find.text("Padding"), findsOneWidget);
    expect(find.text("Top"), findsNothing);

    await drag(tester, "plate-padding", 12);
    expect(shop.saved.textPadding, 12);

    await tester.tap(find.text("Set the plate's padding side by side"));
    await tester.pumpAndSettle();

    // Each side starts where it already was, so nothing moves at the moment
    // the controls change.
    expect(shop.saved.textPaddingTop, 12);
    expect(shop.saved.textPaddingBottom, 12);

    await drag(tester, "plate-padding-bottom", 24);
    expect(shop.saved.textPaddingBottom, 24);
    expect(shop.saved.textPaddingTop, 12, reason: "one side moved another");

    // And back: the sides give up their own answers, or one slider would be
    // showing and four would be drawn.
    await tester.tap(find.text("Set the plate's padding side by side"));
    await tester.pumpAndSettle();
    expect(shop.saved.textPaddingBottom, lessThan(0));
    expect(shop.saved.textPadding, 12);
  });

  testWidgets('the card\'s padding can be set side by side too',
      (tester) async {
    // The same control, asked twice: the plate's padding and the card's are
    // the same question.
    var shop = await pump(tester);
    await tester.tap(find.text("Draw a border round each product"));
    await tester.pumpAndSettle();

    await drag(tester, "card-padding", 10);
    expect(shop.saved.cardPadding, 10);

    await tester.tap(find.text("Set the card's padding side by side"));
    await tester.pumpAndSettle();
    expect(shop.saved.cardPaddingTop, 10);

    await drag(tester, "card-padding-bottom", 20);
    expect(shop.saved.cardPaddingBottom, 20);
    expect(shop.saved.cardPaddingTop, 10);
  });

  testWidgets('every length on the page can be shown at once', (tester) async {
    // The plate, the border and the button each have a corner radius and a
    // padding. Keyed by their label, two of them under one key in one tree
    // is an outright assertion rather than a muddle -- and every one of
    // these settings is meant to be usable at the same time.
    var shop = await pump(tester);

    await tester.tap(find.text("Draw a plate behind the writing"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Draw a border round each product"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Title and price").last);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Title, description, price and a button").last);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Set the picture's corners one by one"));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // And each one still moves the setting it names.
    await drag(tester, "plate-radius", 12);
    await drag(tester, "border-radius", 20);
    await drag(tester, "button-radius", 4);
    expect(shop.saved.textRadius, 12);
    expect(shop.saved.cardBorderRadius, 20);
    expect(shop.saved.buttonRadius, 4);
  });

  testWidgets('a front page too old for a setting says so', (tester) async {
    // A shop's templates are the seller's own from the day the shop is made,
    // so a front page written before a setting existed goes on drawing what
    // it always drew: the setting saves, shows what it saved, and changes
    // nothing on the page. Told apart from a broken setting only by being
    // said out loud -- it was reported as a broken setting three times.
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var shop = _Store(_Pages(), template: "--grid[3]--\n{{ productCard . }}\n");
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<StoreModel>.value(value: shop),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: Consumer<StoreModel>(
                        builder: (context, store, _) =>
                            StoreFrontFields(store: store)))))));
    await tester.pumpAndSettle();

    // Named by what the seller would look for, not by the call.
    expect(find.textContaining("the space between products"), findsOneWidget);
    expect(find.textContaining("Restore default pages"), findsOneWidget);
    // And it does not cry wolf about the settings that do reach it.
    expect(find.textContaining("what one product looks like"), findsNothing);
  });

  testWidgets('a front page that is up to date says nothing', (tester) async {
    await pump(tester);
    expect(find.textContaining("Restore default pages"), findsNothing);
  });

  testWidgets('the DCR estimate can be taken off the shop front',
      (tester) async {
    var shop = await pump(tester);
    expect(shop.indexLayout.showDCR, isTrue);

    await tester.tap(find.text("Show the DCR estimate on the shop front"));
    await tester.pumpAndSettle();

    expect(shop.saved.showDCR, isFalse);
    expect(shop.saves, 1);
  });
}
