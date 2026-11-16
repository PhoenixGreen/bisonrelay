import 'package:bruig/plugin_system/canvas/ui/canvas_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_name_dialog_test.dart is the dialog the Files panel and the Code
// Studio ask a name with (Ken, 2026-11-16: "A TextEditingController was
// used after being disposed", from files_panel.dart). The field's
// controller was disposed as soon as the answer came back, while the dialog
// was still animating away and building its field; it belongs to the
// dialog now, and goes when the dialog does.

void main() {
  for (var how in ["OK", "Enter", "Cancel"]) {
    testWidgets("a name given by $how, and the dialog gone cleanly",
        (tester) async {
      String? answer = "unset";
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () async => answer = await askForName(
                            context,
                            title: "New canvas",
                            label: "Name",
                            initial: "Draft",
                            fieldKey: const ValueKey("nameField")),
                        child: const Text("Ask")),
                  ))));
      await tester.tap(find.text("Ask"));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey("nameField")), "League");
      switch (how) {
        case "OK":
          await tester.tap(find.text("OK"));
        case "Enter":
          await tester.testTextInput.receiveAction(TextInputAction.done);
        default:
          await tester.tap(find.text("Cancel"));
      }
      // Through the dialog's going, frame by frame: where the disposed
      // controller was used.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(answer, how == "Cancel" ? isNull : "League");
      expect(find.byKey(const ValueKey("nameField")), findsNothing);
    });
  }
}
