import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_timeline_menus.dart opens the timeline play bar's menus for tests.
// The bar keeps only what is pressed while working: the options, tools and
// view live behind its ⋯ button (timelineMore), the length, rate, tempo and
// loop behind the readout's arrow (timingMenu), and a marker's settings
// behind the flag (markerMenu).

/// settleMenu lets a menu open or close. With [settle], pumpAndSettle;
/// without, a few frames, for a test whose timeline never settles.
Future<void> settleMenu(WidgetTester tester, {bool settle = true}) async {
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

/// openMore opens the play bar's ⋯ menu.
Future<void> openMore(WidgetTester tester, {bool settle = true}) async {
  var button = find.byKey(const ValueKey("timelineMore"));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await settleMenu(tester, settle: settle);
}

/// tapTimelineItem opens the ⋯ menu and presses the item [key] in it, such
/// as "playAll-item", "snap-item" or "toolKnifeItem". The menu closes.
Future<void> tapTimelineItem(WidgetTester tester, String key,
    {bool settle = true}) async {
  await openMore(tester, settle: settle);
  await tester.tap(find.byKey(ValueKey(key)));
  await settleMenu(tester, settle: settle);
}

/// openTiming opens the menu behind the playhead's readout: the length,
/// frame rate, tempo, metre, quantise and the loop's FROM/FOR.
Future<void> openTiming(WidgetTester tester, {bool settle = true}) async {
  if (find.byKey(const ValueKey("loopFrom")).evaluate().isNotEmpty) return;
  var button = find.byKey(const ValueKey("timingMenu"));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await settleMenu(tester, settle: settle);
}

/// closeTiming shuts the timing menu, if it is open, by pressing its button
/// again.
Future<void> closeTiming(WidgetTester tester, {bool settle = true}) async {
  if (find.byKey(const ValueKey("loopFrom")).evaluate().isEmpty) return;
  await tester.tap(find.byKey(const ValueKey("timingMenu")));
  await settleMenu(tester, settle: settle);
}

/// openMarker opens the menu behind the bar's flag: a marker under the
/// playhead, and what it does -- or the buttons to add one.
Future<void> openMarker(WidgetTester tester, {bool settle = true}) async {
  var button = find.byKey(const ValueKey("markerMenu"));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await settleMenu(tester, settle: settle);
}

/// closeMenus shuts whatever menu is open, as Escape does.
Future<void> closeMenus(WidgetTester tester, {bool settle = true}) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await settleMenu(tester, settle: settle);
}
