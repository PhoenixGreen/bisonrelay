import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// composer_rebuild_test.dart pins the behaviour behind a context menu that
// blinked as the pointer moved onto it, in the post editor only.
//
// The cause was not the menu. A TextEditingController notifies on selection
// changes as well as edits, and a right-click selects the word under the
// pointer; the post editor listened to the controller and, half a second
// later, rebuilt itself with a fresh post-size estimate -- tearing down the
// open menu in the process. The chat composer has no such listener, which is
// why only one of them blinked.
//
// This is about the shape of the listener rather than the editor's widgets,
// so it exercises that shape directly: a listener that acts on every
// notification, against one that first checks whether the text changed.

void main() {
  test("a selection change is not a text change", () {
    var controller = TextEditingController(text: "the payment cleared");

    var naiveCalls = 0;
    controller.addListener(() => naiveCalls++);

    var guardedCalls = 0;
    var lastText = controller.text;
    controller.addListener(() {
      if (controller.text == lastText) return;
      lastText = controller.text;
      guardedCalls++;
    });

    // What a right-click does: select the word under the pointer.
    controller.selection = const TextSelection(baseOffset: 4, extentOffset: 11);
    // And moving the caret afterwards.
    controller.selection = const TextSelection.collapsed(offset: 0);

    expect(naiveCalls, 2,
        reason: "the controller does notify for selection alone");
    expect(guardedCalls, 0,
        reason: "no edit happened, so nothing downstream should run");

    // A real edit must still get through.
    controller.text = "the payment has cleared";
    expect(guardedCalls, 1);

    controller.dispose();
  });
}
