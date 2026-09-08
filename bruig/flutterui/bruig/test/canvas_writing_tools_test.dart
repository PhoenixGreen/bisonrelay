import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_text_editor.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_writing_tools_test.dart is the writing tools reaching the canvas.
//
// A headline on a canvas is text somebody wrote, and it gets the same
// spelling, grammar and phrasing marks as a post does -- with the same
// provider, the same dictionary and the same right-click menu. What makes
// that cheap is that the tools are a TextEditingController: it composes its
// own styled text and reads the capability from the context it is painted
// in, so a field that swaps its controller gets everything and a field that
// does not is untouched.

void main() {
  /// editor is a canvas text editor, with or without the tools provided.
  Future<void> pump(WidgetTester tester,
      {SpellcheckCapability? capability}) async {
    var element = TextElement(
      const ElementBase(id: "t", x: 0, y: 0, width: 300, height: 120),
      text: "Teh canvas",
    );

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        Provider<SpellcheckCapability?>.value(value: capability),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            CanvasTextEditor(
              element: element,
              rect: const Rect.fromLTWH(0, 0, 300, 120),
              scale: 1,
              onChanged: (_) {},
              onDone: () {},
            ),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets("the editor's controller is the writing tools' own",
      (tester) async {
    // Which is the whole mechanism: the marks, the suggestions and the
    // thesaurus all hang off it, and it needs no capability to be built.
    await pump(tester);
    var field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller, isA<WritingTextEditingController>());
  });

  testWidgets("and its menu is the writing tools' menu", (tester) async {
    await pump(tester);
    var field = tester.widget<TextField>(find.byType(TextField));
    expect(field.contextMenuBuilder, isNotNull,
        reason: "without one there is nowhere for a correction, a word to "
            "add to the dictionary, or a synonym to be offered");
  });

  testWidgets("with no provider it is the editor it always was",
      (tester) async {
    // Nothing here names a provider and nothing here switches anything on:
    // with none enabled the controller behaves exactly like a plain one.
    await pump(tester);
    await tester.enterText(find.byType(TextField), "Teh canvas");
    await tester.pumpAndSettle();
    expect(find.text("Teh canvas"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // What is deliberately not tested here: whether the checker finds a
  // particular misspelling. That is the writing tools' own test and their own
  // dictionary; building a live capability needs a plugin manager and the
  // preferences store, and a canvas test that stood one up would be testing
  // the tools through a keyhole. What the canvas owes is the controller and
  // the menu, which is what is checked above.
}
