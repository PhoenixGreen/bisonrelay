import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_tool_hint.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// The pill over the canvas while a drawing is edited: the tool in hand, and
// the way back to the points tool or out of the drawing.

void main() {
  testWidgets("the tool in hand, then Points, then Done", (tester) async {
    var c = CanvasController(const CanvasDocument().addElement(VectorElement(
        const ElementBase(id: "v", width: 100, height: 100),
        viewBox: const Rect.fromLTWH(0, 0, 100, 100),
        shapes: const [])));
    addTearDown(c.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
      create: (c) => ThemeNotifier(doLoad: false),
      child: MaterialApp(
          home: Scaffold(body: Center(child: VectorToolHint(controller: c)))),
    ));
    expect(find.byKey(const ValueKey("vectorToolHint")), findsNothing,
        reason: "nothing being edited");

    c.selectOnly("v");
    c.editVector("v");
    c.vectorTool = VectorTool.pen;
    await tester.pumpAndSettle();
    expect(find.text("Pen"), findsOneWidget);
    expect(find.text(vectorToolLine(VectorTool.pen)), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("vectorToolPoints")));
    await tester.pumpAndSettle();
    expect(c.vectorTool, VectorTool.select);
    expect(find.byKey(const ValueKey("vectorToolPoints")), findsNothing,
        reason: "already the points tool");
    expect(find.text("Done · Esc"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("vectorToolDone")));
    await tester.pumpAndSettle();
    expect(c.vectorEditing, isNull);
    expect(find.byKey(const ValueKey("vectorToolHint")), findsNothing);
  });
}
