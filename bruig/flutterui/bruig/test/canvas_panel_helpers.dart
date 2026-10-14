import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_panel_helpers.dart opens the parts of a sectioned settings panel a
// test needs -- each only if it is shut, since a section opened in one test
// stays open for the rest of the file (see controls.dart's section memory).

/// openSection opens the section remembered as [remember] -- "image.picture.
/// mask", say -- if it is shut.
Future<void> openSection(WidgetTester tester, String remember) async {
  if (find.byKey(ValueKey("sectionBody-$remember")).evaluate().isNotEmpty) {
    return;
  }
  var head = find.byKey(ValueKey("section-$remember"));
  await tester.ensureVisible(head);
  await tester.tap(head);
  await tester.pumpAndSettle();
}

/// openLayerList opens a picture's layers from the strip into the list.
Future<void> openLayerList(WidgetTester tester) async {
  if (find.byKey(const ValueKey("imageLayersRows")).evaluate().isNotEmpty) {
    return;
  }
  var head = find.byKey(const ValueKey("imageLayersOpen"));
  await tester.ensureVisible(head);
  await tester.tap(head);
  await tester.pumpAndSettle();
}

/// addLayer presses the Add tile [key] -- "imageAddFill", say -- opening the
/// Add tiles first.
Future<void> addLayer(WidgetTester tester, String key) async {
  if (find.byKey(const ValueKey("imageAddTiles")).evaluate().isEmpty) {
    var add = find.byKey(const ValueKey("imageLayersAdd"));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
  }
  var tile = find.byKey(ValueKey(key));
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

/// typeNumber types [text] into the stepper [key] -- "elementX", say -- the
/// way a person does: a double-click on the number, the digits, Return.
Future<void> typeNumber(WidgetTester tester, String key, String text) async {
  var number = find.byKey(ValueKey("$key-number"));
  await tester.ensureVisible(number);
  await tester.pumpAndSettle();
  await tester.tap(number);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(number);
  await tester.pumpAndSettle();
  await tester.enterText(
      find.descendant(
          of: find.byKey(ValueKey(key)), matching: find.byType(EditableText)),
      text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}
