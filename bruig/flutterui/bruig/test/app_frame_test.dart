import 'package:bruig/components/app_frame.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

// app_frame_test.dart is what has to sit above every route.
//
// Both of these have been lost once. The repaint boundary went out with the
// in-app eyedropper -- it had been added so the app could capture its own
// frame, and it was also the thing keeping the app's content on a layer of
// its own, so without it every route change repainted the whole window and
// moving between menu items went from instant to visibly late.

const _marker = Key("framed");

/// _pump puts the frame up with the theme notifier AppTooltips reads its
/// setting from.
Future<void> _pump(WidgetTester tester, Widget? child) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
    create: (c) => ThemeNotifier(doLoad: false),
    child: MaterialApp(home: appFrame(child)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("the app's content is its own layer", (tester) async {
    await _pump(tester, const SizedBox(key: _marker));

    // Ours by name: Flutter puts up boundaries of its own, so asking
    // whether there is one above the child is answered yes either way.
    expect(
        find.ancestor(
            of: find.byKey(_marker), matching: find.byKey(appContentLayer)),
        findsOneWidget,
        reason: "nothing isolates the app's repaints from the window's");
    expect(tester.widget(find.byKey(appContentLayer)), isA<RepaintBoundary>());
  });

  testWidgets("and the tooltip settings reach all of it", (tester) async {
    await _pump(tester, const SizedBox(key: _marker));

    expect(
        find.ancestor(
            of: find.byKey(_marker), matching: find.byType(TooltipVisibility)),
        findsWidgets,
        reason: "the hover-text setting stops short of the app's own routes");
  });

  testWidgets("a frame with nothing in it still builds", (tester) async {
    // The builder is called before the navigator has anything in it.
    await _pump(tester, null);
    expect(find.text("no child"), findsOneWidget);
  });
}
