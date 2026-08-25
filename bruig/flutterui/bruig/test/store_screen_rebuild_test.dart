import 'dart:async';
import 'package:bruig/models/pages.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/models/store.dart';
import 'package:bruig/screens/pages/store.dart';
import 'package:bruig/screens/pages/store/store_orders.dart';
import 'package:bruig/screens/pages/store/product_editor.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bruig/screens/pages/store/store_tabs.dart';
import 'package:bruig/screens/pages/store/shop_frame_fields.dart';

// store_screen_rebuild_test.dart is about the screen noticing.
//
// Splitting PagesModel in two moved the catalogue, the orders and the
// product being written onto StoreModel, and left this screen listening to
// hosting alone. Everything still worked; nothing was drawn. Pressing Edit
// changed the shop and not the page, and the editor turned up only once
// something else happened to rebuild it.
//
// Every model test still passed, because the models were right. This is the
// test that was missing: not what the model holds, but whether the screen is
// told.

class _Pages extends PagesModel {
  _Pages() : super(ResourcesModel(runStream: false));

  @override
  PagesHostConfig get hostConfig =>
      PagesHostConfig(pagesHostModeStore, "", "/store", "ln", "", 0, "");

  @override
  Future<void> loadHost() async {}
}

class _Store extends StoreModel {
  _Store(super.pages);

  @override
  Future<void> loadStore() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the screen follows the shop, not only the hosting',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var pages = _Pages();
    var shop = _Store(pages);

    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
    ], child: MaterialApp(home: Scaffold(body: StoreTab(pages, shop, "me")))));
    await tester.pumpAndSettle();

    expect(find.byType(ProductEditor), findsNothing);

    // What pressing Edit does. The screen has to notice on its own.
    shop.startProductDraft(ManagedProduct.empty());
    await tester.pumpAndSettle();

    expect(find.byType(ProductEditor), findsOneWidget,
        reason: "the shop changed and the screen did not redraw");
  });

  testWidgets('an order placed with your own shop cannot be delivered',
      (tester) async {
    // Everything else about such an order works, so it is a good way to try
    // the shop. Sending is between two clients and your own identity is not
    // a remote user -- so the button is offered greyed, with the reason,
    // rather than left to fail with "user not found": a sentence about
    // somebody who is standing right there.
    var pages = _Pages();
    var shop = _Store(pages);

    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: OrderThread(
          order: ManagedOrder(1, "me", "", SSCart(const [], DateTime.now()),
              "placed", DateTime.now(), 0, 0, "ln", const []),
          onReply: (_) async {},
          onSendGoods: () async {},
          isOwn: true,
        )))));
    await tester.pumpAndSettle();

    expect(
        tester
            .widget<OutlinedButton>(find
                .ancestor(
                    of: find.text("Send the files now"),
                    matching: find.byType(OutlinedButton))
                .first)
            .onPressed,
        isNull);
    expect(find.textContaining("second client"), findsOneWidget);
  });

  test('a shop told about an order reads its book again', () async {
    // The stream from golib takes one listener and keeps it, even after a
    // cancel, and ClientModel has been that listener since before the shop
    // had a seller's screen. Taking it here threw on the second listen and
    // brought the whole Pages area down -- so the shop is told by whoever
    // already holds it, and this is that wiring.
    var orders = StreamController<SSPlacedOrder>.broadcast();
    addTearDown(orders.close);

    var loads = 0;
    var shop = _CountingStore(_Pages(), orders.stream, () => loads++);
    expect(loads, 0);

    orders.add(
        SSPlacedOrder(SSOrder(1, "uid", SSCart(const [], DateTime.now())), ""));
    await Future<void>.delayed(Duration.zero);
    expect(loads, 1, reason: "the order book was not read again");

    shop.dispose();
    orders.add(
        SSPlacedOrder(SSOrder(2, "uid", SSCart(const [], DateTime.now())), ""));
    await Future<void>.delayed(Duration.zero);
    expect(loads, 1, reason: "a disposed shop is still listening");
  });

  testWidgets('the shop keeps a half-written product across a tab change',
      (tester) async {
    // The tabs are a view of one screen rather than four screens. Opening
    // Orders to answer somebody must not throw away a product that is half
    // typed -- which is what four screens would have done.
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var pages = _Pages();
    var shop = _Store(pages);

    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
    ], child: MaterialApp(home: Scaffold(body: StoreTab(pages, shop, "me")))));
    await tester.pumpAndSettle();

    shop.startProductDraft(ManagedProduct.empty());
    await tester.pumpAndSettle();
    expect(find.byType(ProductEditor), findsOneWidget);

    // The editor stands in front of the tabs, so what is being written is
    // not something a tab can navigate away from by accident.
    expect(find.text("Orders"), findsNothing);
  });

  _mainSetupTab();

  testWidgets('the shop is drawn with its tabs', (tester) async {
    // Checked by pumping the screen, not by the analyser: the tabs were
    // written, the parameters were wired, everything compiled, and the
    // switch that draws them never reached the file -- so the shop went on
    // being one long page and nothing said otherwise.
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var pages = _Pages();
    var shop = _Store(pages);

    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
    ], child: MaterialApp(home: Scaffold(body: StoreTab(pages, shop, "me")))));
    await tester.pumpAndSettle();

    expect(find.byType(StoreTabs), findsOneWidget,
        reason: "the shop is still one long page");
    for (var kind in StoreTabKind.values) {
      expect(find.text(kind.label), findsWidgets, reason: kind.name);
    }
  });
}

void _mainSetupTab() {
  testWidgets('naming the shop is a tab of the shop', (tester) async {
    // These two fields used to sit on the site's hosting screen, under the
    // page list, because the fragments they name are the site's. A seller
    // looking for what their shop is called looked at the shop, so that is
    // where they are now -- and this pumps the tab rather than trusting the
    // switch to have been wired.
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var pages = _Pages();
    var shop = _Store(pages);

    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
    ], child: MaterialApp(home: Scaffold(body: StoreTab(pages, shop, "me")))));
    await tester.pumpAndSettle();

    expect(find.text("What the shop is called"), findsNothing,
        reason: "setup is a tab, not something on every tab");

    await tester.tap(find.text(StoreTabKind.setup.label));
    await tester.pumpAndSettle();

    expect(find.byType(ShopFrameFields), findsOneWidget);
    expect(find.text("What the shop is called"), findsOneWidget);
    expect(find.text("The shop's frame"), findsOneWidget);
  });

  test('the tab a seller visits once is named for setup', () {
    // The templates tab said "Pages", which is the site's word for the
    // things a visitor reads. In the shop they are the templates it renders
    // through, and two tabs called Pages in one app is one too many.
    expect(StoreTabKind.templates.label, "Templates");
    expect(StoreTabKind.setup.label, "Store setup");
  });
}

class _CountingStore extends StoreModel {
  final void Function() onLoad;
  _CountingStore(PagesModel pages, Stream<SSPlacedOrder> orders, this.onLoad)
      : super(pages, ordersPlaced: orders);

  @override
  Future<void> loadStore() async => onLoad();
}
