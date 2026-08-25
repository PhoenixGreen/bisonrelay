import 'package:bruig/models/pages.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/models/store.dart';
import 'package:bruig/screens/pages/store/shop_frame_fields.dart';
import 'package:bruig/screens/pages/store/store_front_fields.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// store_setup_tap_test.dart is about a control on a page with a text box on
// it still being a control.
//
// The Store setup tab holds both: the shop's name and the fragments it wears,
// which are text boxes, and what a card on the shop front looks like, which
// is switches and dropdowns. The text boxes save on onTapOutside -- and that
// fires on pointer *down*, before the tap on whatever was actually pressed
// has finished.
//
// Saving means setHost, which stops the shop and stands a new one up and
// rebuilds this screen. So every tap on a switch rebuilt the subtree under
// the finger that was pressing it, the pointer came up on a widget that no
// longer existed, and the switch did not move. Nothing on screen said why,
// and the setting it would have saved looked broken rather than untouched.

class _Pages extends PagesModel {
  _Pages() : super(ResourcesModel(runStream: false));

  /// hosts is how many times the shop was stopped and started.
  int hosts = 0;

  @override
  PagesHostConfig get hostConfig =>
      PagesHostConfig(pagesHostModeStore, "", "/store", "ln", "", 0, "");

  @override
  Future<void> loadHost() async {}

  @override
  Future<void> setHost(PagesHostConfig cfg) async {
    hosts++;
    // Asynchronously, the way the real one is: it goes to golib, which stops
    // the shop and stands a new one up, and the screen is rebuilt when that
    // comes back. The delay is what puts the rebuild between the finger
    // going down and coming up again.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    notifyListeners();
  }
}

class _Store extends StoreModel {
  _Store(super.pages);

  StoreIndexLayout saved = const StoreIndexLayout();

  @override
  StoreIndexLayout get indexLayout => saved;

  @override
  Future<void> setIndexLayout(StoreIndexLayout layout) async {
    saved = layout;
    notifyListeners();
  }

  @override
  Future<void> loadStore() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a switch beside the shop-name boxes still switches',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var pages = _Pages();
    var shop = _Store(pages);

    // The setup tab as the screen builds it: both halves, and the whole thing
    // rebuilt whenever either model says something changed.
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
    ], child: MaterialApp(
        home: Scaffold(
            body: ListenableBuilder(
      listenable: Listenable.merge([pages, shop]),
      builder: (context, _) => SingleChildScrollView(
        child: Column(children: [
          ShopFrameFields(pages: pages),
          StoreFrontFields(store: shop),
        ]),
      ),
    )))));
    await tester.pumpAndSettle();

    // Put the cursor in one of the text boxes, which is what a seller does
    // first: this tab is where the shop is named.
    await tester.tap(find.widgetWithText(TextField, "Shop name"));
    await tester.pumpAndSettle();

    // Pressed and held for a moment, which is what tapping is. A tap that
    // is down and up inside one frame never meets the rebuild.
    var at = tester.getCenter(find.text("Show the DCR estimate on the shop front"));
    var finger = await tester.startGesture(at);
    await tester.pump(const Duration(milliseconds: 120));
    await finger.up();
    await tester.pumpAndSettle();

    expect(shop.saved.showDCR, isFalse,
        reason: "the tap went to a widget that was rebuilt out from under it");
    expect(pages.hosts, 0,
        reason: "nothing in the shop's name changed, so the shop must not "
            "have been stopped and restarted");
  });

  testWidgets('the shop is restarted when its name really does change',
      (tester) async {
    // The other half of the guard: saving only on a change must not mean
    // never saving.
    var pages = _Pages();

    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
    ], child: MaterialApp(home: Scaffold(body: ShopFrameFields(pages: pages)))));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, "Shop name"), "Leeds Records");
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(pages.hosts, 1);
  });
}
