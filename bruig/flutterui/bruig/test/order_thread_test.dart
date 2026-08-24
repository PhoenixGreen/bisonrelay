import 'package:bruig/screens/pages/store/store_orders.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';

// order_thread_test.dart covers the seller's half of an order's messages.
//
// Both ends of this were built when the shop was: a buyer can write on an
// order, and the store records a reply. There was nowhere in the app to read
// one or write one back, so a buyer asking when something ships got silence
// and the seller never knew they had asked.

ManagedOrder orderWith(List<SSOrderComment> comments) => ManagedOrder(
      7,
      "uid",
      "Some Buyer",
      SSCart(const [], DateTime.now()),
      "placed",
      DateTime.now(),
      0,
      0,
      "ln",
      comments,
    );

SSOrderComment from(String who, String text) =>
    SSOrderComment(DateTime.now(), who == "seller", text);

void main() {
  Future<void> pump(WidgetTester tester, ManagedOrder order,
      Future<void> Function(String) onReply,
      {Future<void> Function()? onSendGoods}) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
    ], child: MaterialApp(
        home: Scaffold(
            body: OrderThread(
                order: order,
                onReply: onReply,
                onSendGoods: onSendGoods ?? () async {})))));
    await tester.pumpAndSettle();
  }

  testWidgets('an order with nothing said says so', (tester) async {
    await pump(tester, orderWith(const []), (_) async {});
    expect(find.textContaining("Nothing has been said"), findsOneWidget);
  });

  testWidgets('both sides of the conversation are shown', (tester) async {
    await pump(
        tester,
        orderWith([
          from("buyer", "When does this ship?"),
          from("seller", "Tomorrow."),
        ]),
        (_) async {});

    expect(find.text("When does this ship?"), findsOneWidget);
    expect(find.text("Tomorrow."), findsOneWidget);
    // Told apart by who said them, not only by where they sit: a seller
    // reading their own words back as the buyer's would answer the wrong
    // question.
    expect(find.textContaining("Some Buyer"), findsOneWidget);
    expect(find.textContaining("You"), findsWidgets);
  });

  testWidgets('a reply is sent, and the box is cleared', (tester) async {
    String? sent;
    await pump(tester, orderWith(const []), (text) async => sent = text);

    await tester.enterText(find.byType(TextField), "It ships tomorrow");
    await tester.tap(find.text("Send"));
    await tester.pumpAndSettle();

    expect(sent, "It ships tomorrow");
    expect(find.text("It ships tomorrow"), findsNothing);
  });

  testWidgets('a reply that fails keeps what was typed', (tester) async {
    // A box emptied on a failure is a reply somebody has to type again with
    // nothing to copy from.
    await pump(tester, orderWith(const []),
        (_) async => throw "the other end is offline");

    await tester.enterText(find.byType(TextField), "It ships tomorrow");
    await tester.tap(find.text("Send"));
    await tester.pumpAndSettle();

    expect(find.text("It ships tomorrow"), findsOneWidget);
  });

  testWidgets('an empty reply is not sent', (tester) async {
    var sent = 0;
    await pump(tester, orderWith(const []), (_) async => sent++);

    await tester.enterText(find.byType(TextField), "   ");
    await tester.tap(find.text("Send"));
    await tester.pumpAndSettle();

    expect(sent, 0);
  });

  testWidgets('the seller can send the files again', (tester) async {
    // The files go out when payment lands, so this is for when a buyer says
    // nothing arrived -- and it is the only way to try the whole path
    // without a payment, since paying yourself is not a thing Lightning
    // will do.
    var sent = 0;
    await pump(tester, orderWith(const []), (_) async {},
        onSendGoods: () async => sent++);

    await tester.tap(find.text("Send the files now"));
    await tester.pumpAndSettle();
    expect(sent, 1);
  });

  testWidgets('sending files does not tie up the reply box', (tester) async {
    // Two different things to be doing. Sharing one busy flag greyed out
    // the reply while a file went out.
    var replied = 0;
    await pump(tester, orderWith(const []), (_) async => replied++,
        onSendGoods: () async => throw "the other end is offline");

    await tester.tap(find.text("Send the files now"));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), "It is on its way");
    await tester.tap(find.text("Send"));
    await tester.pumpAndSettle();
    expect(replied, 1, reason: "the reply box was tied up by the file send");
  });
}
