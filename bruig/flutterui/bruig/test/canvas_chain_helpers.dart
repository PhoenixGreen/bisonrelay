import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

// canvas_chain_helpers.dart helps tests reach what a device card keeps
// behind its ⋯: moving it along the chain, and taking it out.

/// revealInMenu opens the ⋯ of the device card that holds [key] -- each in
/// turn until one does -- so it can be found and pressed. Nothing is done
/// where [key] is on screen already.
Future<void> revealInMenu(WidgetTester tester, String key) async {
  if (find.byKey(ValueKey(key)).evaluate().isNotEmpty) return;
  var mores = find.byWidgetPredicate((w) =>
      w.key is ValueKey<String> &&
      (w.key as ValueKey<String>).value.startsWith("deviceMore-"));
  for (var element in mores.evaluate().toList()) {
    var more = find.byKey(element.widget.key!);
    await tester.ensureVisible(more);
    await tester.pump();
    await tester.tap(more);
    await tester.pump();
    if (find.byKey(ValueKey(key)).evaluate().isNotEmpty) return;
    // Not this one's: shut it again.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
  }
}

/// openAdd opens the chain's "+" that [slot] finds -- the slot keyed
/// addDeviceOpen, addMidiOpen, addMoveOpen or addLookOpen -- so what it
/// adds can be picked.
Future<void> openAdd(WidgetTester tester, Finder slot) async {
  await tester.ensureVisible(slot);
  await tester.pump();
  await tester.tap(slot);
  await tester.pump(const Duration(milliseconds: 200));
}
