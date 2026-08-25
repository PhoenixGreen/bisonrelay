import 'package:bruig/models/pages.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/models/store.dart';
import 'package:bruig/screens/pages/store/store_front_fields.dart';
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
  _Store(super.pages);

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
    expect(find.text("Crop from"), findsNothing,
        reason: "nothing to crop until every picture is one shape");

    await tester.tap(find.text("Draw every picture at the same shape"));
    await tester.pumpAndSettle();

    expect(shop.saved.fixedImage, isTrue);
    expect(find.text("Crop from"), findsOneWidget);
    expect(find.text("Shape"), findsOneWidget);
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
    expect(find.text("Where the writing sits on it"), findsNothing);

    await tester.tap(find.text("Above the writing").last);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Behind the whole card").last);
    await tester.pumpAndSettle();

    expect(shop.saved.imagePosition, "full");
    expect(find.text("Where the writing sits on it"), findsOneWidget);
  });

  testWidgets('the plate behind the writing brings its own settings',
      (tester) async {
    var shop = await pump(tester);
    expect(find.text("Plate colour"), findsNothing);

    await tester.tap(find.text("A plate behind the writing"));
    await tester.pumpAndSettle();

    expect(shop.saved.textBackground, isTrue);
    for (var field in ["Plate colour", "Padding", "Margin", "Corner radius"]) {
      expect(find.text(field), findsOneWidget, reason: "$field is missing");
    }
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
