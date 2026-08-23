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

  group('a group of settings', () {
    testWidgets('opens to its settings rather than listing them all',
        (tester) async {
      // A banner has eighteen settings. Eighteen rows is a list nobody
      // reads, so they are five things to open.
      await pump(tester);
      await tester.tap(find.text("Header"));
      await tester.pumpAndSettle();

      expect(find.text("Title fill"), findsOneWidget);
      expect(find.text("Title outline"), findsOneWidget);
      expect(find.text("Row 1"), findsOneWidget);
      expect(find.text("Row 2"), findsOneWidget);
      // Inside the group, not on the face of the panel.
      expect(find.text("Tracking"), findsNothing);
    });

    testWidgets('shows its settings side by side when opened',
        (tester) async {
      await pump(tester);
      await tester.tap(find.text("Header"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Row 1"));
      await tester.pumpAndSettle();

      // findsWidgets, not one: "Row height" is also what the Title size
      // setting says when it is left alone, and both are on screen.
      for (var label in ["Height", "Layout", "Flush", "Group"]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text("Split"), findsOneWidget);
    });

    testWidgets('a row setting reaches the row it is written in',
        (tester) async {
      await pump(tester);
      await tester.tap(find.text("Header"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Row 1"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Tall (200)"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Yes").first);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Insert header"));
      await tester.pumpAndSettle();

      expect(editor.text, contains("--row["));
      expect(editor.text, contains("200"));
      expect(editor.text, isNot(contains("height:")));
    });
  });

  group('an exclusive group', () {
    testWidgets('asks which one before offering its answers', (tester) async {
      await pump(tester);
      await tester.tap(find.text("Header"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Title fill"));
      await tester.pumpAndSettle();

      // The three alternatives, and nothing chosen.
      for (var label in ["Colour", "Gradient", "Picture"]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
    });

    testWidgets('picking one clears the others', (tester) async {
      // A title is filled with a colour, or a gradient, or a picture.
      // Two of them set is a banner asked two things, and only one can win
      // -- so the panel must not be able to write both.
      await pump(tester);
      await tester.tap(find.text("Header"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Title fill"));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Colour"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Gradient"));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Insert header"));
      await tester.pumpAndSettle();

      expect(editor.text, contains("titlegradient:"));
      expect(editor.text, isNot(contains("titlecolor:")));
    });

    testWidgets('None clears all of them', (tester) async {
      await pump(tester);
      await tester.tap(find.text("Header"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Title fill"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Picture"));
      await tester.pumpAndSettle();
      // The group's own None, which is the first chip in the chooser --
      // not one of the several Nones the settings below it also offer.
      await tester.tap(find.descendant(
          of: find.ancestor(
              of: find.text("Gradient"), matching: find.byType(Wrap)).first,
          matching: find.text("None")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Insert header"));
      await tester.pumpAndSettle();

      expect(editor.text, isNot(contains("titleimage:")));
      expect(editor.text, isNot(contains("titlegradient:")));
    });
  });

  group('a colour', () {
    test('is written the way a banner reads one', () {
      expect(hexOf(const Color(0xffffffff)), "#ffffff");
      expect(hexOf(const Color(0xff000000)), "#000000");
      // Alpha kept only when there is some to keep: #00000080 is the
      // see-through panel a banner wants behind its writing.
      expect(hexOf(const Color(0x80000000)), "#00000080");
    });

    test('is read back from what was written', () {
      expect(parseHexColour("#ffffff"), const Color(0xffffffff));
      expect(parseHexColour("#fff"), const Color(0xffffffff));
      expect(parseHexColour("#00000080"), const Color(0x80000000));
    });

    test('round trips', () {
      for (var c in [
        const Color(0xffff0000),
        const Color(0x8012ab34),
        const Color(0xff123456),
      ]) {
        expect(parseHexColour(hexOf(c)), c);
      }
    });

    test('anything that is not one is nothing', () {
      // What the banner itself does with it: an unreadable colour leaves
      // that setting unset rather than the banner broken.
      for (var raw in ["", "red", "ffffff", "#ggg", "#12345"]) {
        expect(parseHexColour(raw), isNull, reason: raw);
      }
    });
  });

  group('picking a gradient', () {
    testWidgets('shows both colours and what they make', (tester) async {
      // A gradient is the two colours against each other -- neither is
      // right or wrong on its own -- so picking them in turn meant judging
      // the second against a memory of the first.
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      String? got;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                        onPressed: () async => got = await pickGradient(
                            context,
                            const Color(0xffff0000),
                            const Color(0xff0000ff)),
                        child: const Text("open"),
                      )))));
      await tester.tap(find.text("open"));
      await tester.pumpAndSettle();

      expect(find.text("First"), findsOneWidget);
      expect(find.text("Second"), findsOneWidget);

      // The gradient itself is on screen, drawn from both colours.
      var painted = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => (c.decoration as BoxDecoration?)?.gradient != null);
      expect(painted, isNotEmpty);
      expect(
          ((painted.first.decoration as BoxDecoration).gradient
                  as LinearGradient)
              .colors,
          [const Color(0xffff0000), const Color(0xff0000ff)]);

      await tester.tap(find.text("Use this"));
      await tester.pumpAndSettle();
      expect(got, "#ff0000,#0000ff");
    });

    testWidgets('cancelling changes nothing', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      String? got = "untouched";
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                        onPressed: () async => got = await pickGradient(
                            context,
                            const Color(0xffff0000),
                            const Color(0xff0000ff)),
                        child: const Text("open"),
                      )))));
      await tester.tap(find.text("open"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Cancel"));
      await tester.pumpAndSettle();
      expect(got, isNull);
    });
  });
}
