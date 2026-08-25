import 'package:bruig/screens/pages/my_site/site_tabs.dart';
import 'package:bruig/screens/pages/store/store_tabs.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// section_tabs_test.dart covers the two tab rows: the shop's and the site's.
//
// They exist because each section was one long page holding three or four
// different jobs, and reaching the third meant scrolling past the other two.
// The count on a tab is the part worth testing: it is what lets somebody
// look at the catalogue and still see that a buyer is waiting.

Widget host(Widget child) => MultiProvider(providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
    ], child: MaterialApp(home: Scaffold(body: child)));

void main() {
  group("the shop's tabs", () {
    testWidgets('offer every job the shop has', (tester) async {
      await tester.pumpWidget(
          host(StoreTabs(current: StoreTabKind.products, onChanged: (_) {})));
      await tester.pumpAndSettle();

      for (var kind in StoreTabKind.values) {
        expect(find.text(kind.label), findsOneWidget, reason: kind.name);
      }
    });

    testWidgets('say how many orders are waiting on an answer', (tester) async {
      await tester.pumpWidget(host(StoreTabs(
          current: StoreTabKind.products, onChanged: (_) {}, needsAnswer: 3)));
      await tester.pumpAndSettle();
      expect(find.text("3"), findsOneWidget);
    });

    testWidgets('say nothing when nobody is waiting', (tester) async {
      // A nought beside Orders is a thing to read and dismiss every time.
      await tester.pumpWidget(
          host(StoreTabs(current: StoreTabKind.products, onChanged: (_) {})));
      await tester.pumpAndSettle();
      expect(find.text("0"), findsNothing);
    });

    testWidgets('move to the one that was pressed', (tester) async {
      StoreTabKind? went;
      await tester.pumpWidget(host(StoreTabs(
          current: StoreTabKind.products, onChanged: (k) => went = k)));
      await tester.pumpAndSettle();

      // Named through the enum: the label is the thing under test elsewhere,
      // and a tap test should not fail again the next time it is reworded.
      await tester.tap(find.text(StoreTabKind.templates.label));
      expect(went, StoreTabKind.templates);
    });
  });

  group("the site's tabs", () {
    testWidgets('offer pages, fragments and pictures', (tester) async {
      await tester.pumpWidget(
          host(SiteTabs(current: SiteTabKind.pages, onChanged: (_) {})));
      await tester.pumpAndSettle();

      for (var kind in SiteTabKind.values) {
        expect(find.text(kind.label), findsOneWidget, reason: kind.name);
      }
    });

    testWidgets('say how many pages a visitor is behind on', (tester) async {
      await tester.pumpWidget(host(SiteTabs(
          current: SiteTabKind.pictures, onChanged: (_) {}, unpublished: 2)));
      await tester.pumpAndSettle();
      expect(find.text("2"), findsOneWidget);
    });

    testWidgets('move to the one that was pressed', (tester) async {
      SiteTabKind? went;
      await tester.pumpWidget(host(
          SiteTabs(current: SiteTabKind.pages, onChanged: (k) => went = k)));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Fragments"));
      expect(went, SiteTabKind.fragments);
    });
  });
}
