import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_timeline_menus.dart opens the timeline play bar's menus for tests.
// The bar keeps only what is pressed while working: the options, tools and
// view live behind its settings button (playBarSettings), the length, rate, tempo and
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

/// openMore opens the play bar's settings, unless they are open already:
/// a switch pressed in them leaves them open, to be seen.
Future<void> openMore(WidgetTester tester, {bool settle = true}) async {
  if (find
      .byKey(const ValueKey("playBarSettingsPanel"))
      .evaluate()
      .isNotEmpty) {
    return;
  }
  var button = find.byKey(const ValueKey("playBarSettings"));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await settleMenu(tester, settle: settle);
}

/// tapTimelineItem opens the play bar's settings and presses the item [key]
/// in them, such as "snap-item" or "toolKnifeItem".
Future<void> tapTimelineItem(WidgetTester tester, String key,
    {bool settle = true}) async {
  await openMore(tester, settle: settle);
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.tap(find.byKey(ValueKey(key)));
  await settleMenu(tester, settle: settle);
  await closeMore(tester, settle: settle);
}

/// closeMore closes the play bar's settings if they are open, by a click
/// away from them, in the window's empty top corner: not by their button,
/// which the open panel can cover, nor Escape, which the timeline hears too
/// and puts the knife down with.
Future<void> closeMore(WidgetTester tester, {bool settle = true}) async {
  if (find.byKey(const ValueKey("playBarSettingsPanel")).evaluate().isEmpty) {
    return;
  }
  await tester.tapAt(const Offset(1, 1));
  await settleMenu(tester, settle: settle);
}

/// tapPlayAll presses the play bar's button for Play running every scene.
Future<void> tapPlayAll(WidgetTester tester) async {
  var button = find.byKey(const ValueKey("playAll"));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
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
