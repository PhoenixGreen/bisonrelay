import 'package:bruig/components/caret_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// caret_keys_test.dart is Up and Down in text fields Flutter's own fail in:
// centred text (a single line at any width, several lines at a width the
// text engine cannot hold exactly). Flutter asserts and the caret stays put;
// with caretKeyActions over the app, the caret moves as it should.

void main() {
  /// show puts one field of [text] on a [width] screen, the caret at the
  /// start, under caretKeyActions as the app has them.
  Future<TextEditingController> show(WidgetTester tester, String text,
      {required double width,
      TextAlign align = TextAlign.center,
      int? maxLines}) async {
    var controller = TextEditingController(text: text);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        actions: {...WidgetsApp.defaultActions, ...caretKeyActions},
        home: Scaffold(
            body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                    width: width,
                    child: TextField(
                        controller: controller,
                        autofocus: true,
                        maxLines: maxLines,
                        textAlign: align))))));
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();
    return controller;
  }

  Future<int> press(WidgetTester tester, LogicalKeyboardKey key,
      TextEditingController controller) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
    expect(tester.takeException(), isNull);
    return controller.selection.extentOffset;
  }

  testWidgets("a centred line: Down to its end, Up to its start",
      (tester) async {
    var c = await show(tester, "One line", width: 400, maxLines: 1);
    expect(await press(tester, LogicalKeyboardKey.arrowDown, c), 8);
    expect(await press(tester, LogicalKeyboardKey.arrowUp, c), 0);
  });

  testWidgets("centred lines at an inexact width: a line at a time",
      (tester) async {
    var c = await show(tester, "One line\nTwo\nThree line\nFour", width: 561.6);
    var at = [
      for (var i = 0; i < 4; i++)
        await press(tester, LogicalKeyboardKey.arrowDown, c),
    ];
    var lineOf = [
      for (var o in at) "\n".allMatches(c.text.substring(0, o)).length
    ];
    expect(lineOf, [1, 2, 3, 3],
        reason: "down each line, and stays on the last");
    expect(at.last, c.text.length, reason: "the last Down goes to the end");
    expect(await press(tester, LogicalKeyboardKey.arrowUp, c),
        lessThan(c.text.length));
  });

  testWidgets("left-aligned lines move as Flutter's own do", (tester) async {
    var c = await show(tester, "One line\nTwo\nThree line\nFour",
        width: 561.6, align: TextAlign.left);
    expect(await press(tester, LogicalKeyboardKey.arrowDown, c), 9,
        reason: "the start of the second line, under the caret");
    expect(await press(tester, LogicalKeyboardKey.arrowDown, c), 13);
  });

  testWidgets("with Shift, Down extends the selection", (tester) async {
    var c = await show(tester, "One line", width: 400, maxLines: 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect((c.selection.baseOffset, c.selection.extentOffset), (0, 8));
  });
}
