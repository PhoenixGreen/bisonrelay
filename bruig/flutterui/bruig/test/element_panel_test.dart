import 'package:bruig/plugin_system/writing_tools/ui/sidebar/element_panel.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/element_specs.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// element_panel_test.dart covers the two steps down: a block, then what it
// can be told, then what that will take.

void main() {
  late TextEditingController editor;

  setUp(() => editor = TextEditingController());
  tearDown(() => editor.dispose());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
    ], child: MaterialApp(
        home: Scaffold(body: ElementPanel(editor: editor)))));
    await tester.pumpAndSettle();
  }

  testWidgets('a block lists what it can be told', (tester) async {
    await pump(tester);
    // Nothing is showing until one is picked: this is a sidebar column, and
    // five blocks' settings all at once is a list nobody can see.
    expect(find.text("Width"), findsNothing);

    await tester.tap(find.text("Page setup"));
    await tester.pumpAndSettle();

    for (var setting in pageSpec.settings) {
      expect(find.text(setting.label), findsOneWidget, reason: setting.key);
    }
  });

  testWidgets('each setting shows the answer it already gives',
      (tester) async {
    // A block told nothing is not a block doing nothing. The panel opens
    // describing what the writer would actually get.
    await pump(tester);
    await tester.tap(find.text("Page setup"));
    await tester.pumpAndSettle();

    expect(find.text("Full window"), findsOneWidget);
    expect(find.text("Normal"), findsWidgets);
  });

  testWidgets('a setting opens to its answers', (tester) async {
    await pump(tester);
    await tester.tap(find.text("Page setup"));
    await tester.pumpAndSettle();

    expect(find.text("Readable (800)"), findsNothing);
    await tester.tap(find.text("Width"));
    await tester.pumpAndSettle();
    expect(find.text("Readable (800)"), findsOneWidget);
  });

  testWidgets('choosing several writes one block, not several',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text("Page setup"));
    await tester.pumpAndSettle();

    await tester.tap(find.text("Width"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Readable (800)"));
    await tester.pumpAndSettle();

    await tester.tap(find.text("Background"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Raised"));
    await tester.pumpAndSettle();

    expect(editor.text, isEmpty, reason: "nothing is written until Insert");

    await tester.tap(find.text("Insert page setup"));
    await tester.pumpAndSettle();

    expect("--page--".allMatches(editor.text).length, 1);
    expect(editor.text, contains("width: 800"));
    expect(editor.text, contains("background: raised"));
    expect(editor.text, contains("--/page--"));
  });

  testWidgets('the note goes in with it, on a line of its own',
      (tester) async {
    // A comment, so a reader never sees it, and one line, so deleting it is
    // one thing to delete.
    await pump(tester);
    await tester.tap(find.text("Navigation bar"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Insert navigation bar"));
    await tester.pumpAndSettle();

    var lines = editor.text.trim().split("\n");
    expect(lines.first, startsWith("<!--"));
    expect(lines.first, endsWith("-->"));
    expect(lines.first.toLowerCase(), contains("delete this note"));
  });

  testWidgets('an answer picked, then changed, writes only the last',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text("Page setup"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Width"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Narrow (600)"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Wide (1000)"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Insert page setup"));
    await tester.pumpAndSettle();

    expect(editor.text, contains("width: 1000"));
    expect(editor.text, isNot(contains("600")));
  });
}
