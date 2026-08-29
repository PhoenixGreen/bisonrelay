import 'package:bruig/components/feed/markdown_countdown.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/models/payments.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// countdown_test.dart covers the clock on a quoted price.
//
// A page is fetched once and nothing tells it the time, so "the amount holds
// for another 21 minutes" went on saying twenty-one for as long as anybody
// looked at it. The number is counted here, where there is a clock.

Widget _host(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<PaymentsModel>(create: (c) => PaymentsModel()),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<MarkdownAreaModel>(
            create: (c) => MarkdownAreaModel("/tmp")),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 600, child: child)),
        ),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group("how long is left", () {
    // Digits rather than words, and this is the whole of why the first
    // version looked broken: "another 21 minutes" is true and changes once a
    // minute, so somebody looking at it to see whether it is counting watches
    // nothing happen for up to sixty seconds.
    test("reads as a clock", () {
      expect(leftOnAClock(1260), "21:00");
      expect(leftOnAClock(1259), "20:59");
      expect(leftOnAClock(60), "1:00");
      expect(leftOnAClock(45), "0:45");
      expect(leftOnAClock(5), "0:05");
    });

    // Hours only when there are any: an amount held for a quarter of an hour
    // reading "0:14:32" is a clock pretending it might be needed for longer.
    test("keeps hours out of it until there are some", () {
      expect(leftOnAClock(3600), "1:00:00");
      expect(leftOnAClock(3661), "1:01:01");
      expect(leftOnAClock(3599), "59:59");
    });

    test("never counts below nothing", () {
      expect(leftOnAClock(0), "0:00");
      expect(leftOnAClock(-5), "0:00");
    });
  });

  group("the clock", () {
    test("reads what it was given", () {
      var rule = CountdownRule.parse(
          "seconds=1260, link=/reorder/00000001, label=Order it again");
      expect(rule.seconds, 1260);
      expect(rule.link, "/reorder/00000001");
      expect(rule.label, "Order it again");
      expect(rule.draws, isTrue);
    });

    test("never counts up from a negative", () {
      expect(CountdownRule.parse("seconds=-30").seconds, 0);
    });

    testWidgets("counts down without the page being fetched again",
        (tester) async {
      await tester.pumpWidget(_host(MarkdownArea(
          "--countdown[seconds=125, link=/reorder/1]--\n", false)));
      await tester.pump();
      expect(find.textContaining("2:05", findRichText: true), findsOneWidget);

      // One second later, without anything asking the shop -- which is the
      // point: a clock nobody can see move is a clock nobody believes.
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining("2:04", findRichText: true), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
      expect(find.textContaining("1:58", findRichText: true), findsOneWidget);
    });

    // At nought it stops being a warning and becomes what happened.
    testWidgets("says what happened when it runs out", (tester) async {
      await tester.pumpWidget(_host(MarkdownArea(
          "--countdown[seconds=2, link=/reorder/1, label=Order it again]--\n",
          false)));
      await tester.pump();
      expect(find.textContaining("holds for another", findRichText: true),
          findsOneWidget);
      expect(find.text("Order it again"), findsNothing);

      await tester.pump(const Duration(seconds: 3));
      expect(find.textContaining("has lapsed"), findsOneWidget);
      expect(find.textContaining("Nothing has been charged"), findsOneWidget);
      expect(find.text("Order it again"), findsOneWidget);
    });

    // A clock with nowhere to send anybody still tells the time.
    testWidgets("offers nothing to press when the page named nothing",
        (tester) async {
      await tester.pumpWidget(
          _host(MarkdownArea("--countdown[seconds=1]--\n", false)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining("has lapsed"), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets("does not show its own markers", (tester) async {
      await tester.pumpWidget(_host(
          MarkdownArea("--countdown[seconds=125, link=/reorder/1]--\n", false)));
      await tester.pump();
      expect(find.textContaining("--countdown"), findsNothing);
      expect(find.textContaining("seconds="), findsNothing);
    });
  });
}
