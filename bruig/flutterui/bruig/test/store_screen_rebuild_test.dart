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
  // listen: false -- there is no golib here to hear an order from.
  _Store(PagesModel pages) : super(pages, listen: false);

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

    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
    ], child: MaterialApp(
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
}
