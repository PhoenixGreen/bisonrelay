import 'package:bruig/components/composer_sidebar_shell.dart';
import 'package:bruig/components/feed/formatting_sidebar.dart';
import 'package:bruig/models/composer_sidebar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// composer_sidebar_test.dart covers the nav that replaced the buttons under
// the editor, and the formatting panel one of its icons opens.

Future<void> _pump(WidgetTester tester, ComposerSidebarController controller,
    {List<ComposerPanel>? panels}) async {
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<ComposerSidebarController>.value(
          value: controller),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => controller.minimized
              ? Row(children: [
                  ComposerSidebarRestoreButton(controller: controller),
                  const Expanded(child: Text("EDITOR")),
                ])
              : Row(children: [
                  SizedBox(
                    width: 260,
                    child: ComposerSidebarShell(
                      controller: controller,
                      panels: panels ?? ComposerPanel.values,
                      child: Text("PANEL: ${controller.panel.name}"),
                    ),
                  ),
                  const Expanded(child: Text("EDITOR")),
                ]),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  _titleDecorationTests();
  group("the panel nav", () {
    testWidgets("starts on the screen's own menu", (tester) async {
      var controller = ComposerSidebarController();
      await _pump(tester, controller);
      expect(find.text("PANEL: none"), findsOneWidget);
    });

    testWidgets("an icon switches panels", (tester) async {
      var controller = ComposerSidebarController();
      await _pump(tester, controller);

      await tester.tap(find.byIcon(ComposerPanel.posts.icon));
      await tester.pumpAndSettle();
      expect(find.text("PANEL: posts"), findsOneWidget);

      await tester.tap(find.byIcon(ComposerPanel.formatting.icon));
      await tester.pumpAndSettle();
      expect(find.text("PANEL: formatting"), findsOneWidget);
    });

    // A panel whose feature is unavailable is left out rather than shown
    // disabled: there is nothing the user could do about it from here.
    testWidgets("a panel can be left out", (tester) async {
      var controller = ComposerSidebarController();
      await _pump(tester, controller, panels: [
        ComposerPanel.none,
        ComposerPanel.posts,
      ]);
      expect(find.byIcon(ComposerPanel.writing.icon), findsNothing);
      expect(find.byIcon(ComposerPanel.posts.icon), findsOneWidget);
    });
  });

  group("minimizing", () {
    testWidgets("hides the sidebar and leaves a way back", (tester) async {
      var controller = ComposerSidebarController();
      await _pump(tester, controller);

      await tester.tap(find.byTooltip("Hide the sidebar"));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerSidebarShell), findsNothing);
      expect(find.text("EDITOR"), findsOneWidget);
      expect(find.byTooltip("Show the sidebar"), findsOneWidget,
          reason: "a hidden sidebar with no way back is a trap");

      await tester.tap(find.byTooltip("Show the sidebar"));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerSidebarShell), findsOneWidget);
    });

    // Somebody who minimized while reading their library did not ask to be
    // returned to the feed menu.
    testWidgets("comes back to the panel that was showing", (tester) async {
      var controller = ComposerSidebarController();
      await _pump(tester, controller);

      await tester.tap(find.byIcon(ComposerPanel.posts.icon));
      await tester.pumpAndSettle();
      controller.toggleMinimized();
      await tester.pumpAndSettle();
      controller.toggleMinimized();
      await tester.pumpAndSettle();

      expect(find.text("PANEL: posts"), findsOneWidget);
    });

    test("asking for a panel un-minimizes", () {
      var controller = ComposerSidebarController()..toggleMinimized();
      expect(controller.visible, isFalse);

      controller.show(ComposerPanel.writing);
      expect(controller.visible, isTrue);
      expect(controller.panel, ComposerPanel.writing);
    });
  });

  // Every entry in the formatting panel goes through one routine, so these
  // cover its shapes rather than each button.
  group("formatting", () {
    late TextEditingController editor;
    late ComposerSidebarController controller;

    Future<void> pumpPanel(WidgetTester tester) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
        ],
        child: MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 300,
                  child: FormattingSidebar(controller: controller))),
        ),
      ));
      await tester.pumpAndSettle();
    }

    setUp(() {
      editor = TextEditingController();
      controller = ComposerSidebarController()..attach(editor);
    });
    tearDown(() {
      editor.dispose();
      controller.dispose();
    });

    testWidgets("wrapping keeps the selection so it stays highlighted",
        (tester) async {
      editor.value = const TextEditingValue(
        text: "make this bold",
        selection: TextSelection(baseOffset: 10, extentOffset: 14),
      );
      await pumpPanel(tester);

      await tester.tap(find.byIcon(Icons.format_bold));
      await tester.pumpAndSettle();

      expect(editor.text, "make this **bold**");
      expect(editor.selection.textInside(editor.text), "bold");
    });

    // With nothing selected the placeholder goes in selected, so the next
    // keystroke replaces it rather than landing beside it.
    testWidgets("an empty selection leaves the placeholder selected",
        (tester) async {
      await pumpPanel(tester);
      await tester.tap(find.byIcon(Icons.link));
      await tester.pumpAndSettle();

      expect(editor.text, "[text](https://)");
      expect(editor.selection.textInside(editor.text), "text");
    });

    testWidgets("a line prefix applies to every selected line", (tester) async {
      editor.value = const TextEditingValue(
        text: "one\ntwo\nthree",
        selection: TextSelection(baseOffset: 0, extentOffset: 13),
      );
      await pumpPanel(tester);

      await tester.tap(find.byIcon(Icons.format_list_bulleted));
      await tester.pumpAndSettle();
      expect(editor.text, "- one\n- two\n- three");
    });

    // Pressing the same button twice is not a way to write "## ## ".
    testWidgets("a line prefix is not doubled", (tester) async {
      editor.value = const TextEditingValue(
        text: "> quoted",
        selection: TextSelection.collapsed(offset: 3),
      );
      await pumpPanel(tester);

      await tester.tap(find.byIcon(Icons.format_quote));
      await tester.pumpAndSettle();
      expect(editor.text, "> quoted");
    });

    // A table dropped into the middle of a paragraph is not a table.
    testWidgets("a block is separated from what surrounds it", (tester) async {
      editor.value = const TextEditingValue(
        text: "some text",
        selection: TextSelection.collapsed(offset: 9),
      );
      await pumpPanel(tester);

      await tester.tap(find.byIcon(Icons.horizontal_rule));
      await tester.pumpAndSettle();
      expect(editor.text, "some text\n\n---");
    });

    testWidgets("a block does not pile up blank lines", (tester) async {
      editor.value = const TextEditingValue(
        text: "some text\n\n",
        selection: TextSelection.collapsed(offset: 11),
      );
      await pumpPanel(tester);

      await tester.tap(find.byIcon(Icons.horizontal_rule));
      await tester.pumpAndSettle();
      expect(editor.text, "some text\n\n---");
    });

    // The panel is built before a composer attaches, and again for the frame
    // or two while one is being rebuilt.
    testWidgets("no composer means the buttons are simply disabled",
        (tester) async {
      controller = ComposerSidebarController();
      await pumpPanel(tester);
      expect(
          tester
              .widget<OutlinedButton>(find.ancestor(
                  of: find.byIcon(Icons.format_bold),
                  matching: find.byType(OutlinedButton)))
              .onPressed,
          isNull);
    });
  });
}

// Reported: the post title looked like an input, with a border at rest and
// an underline on focus, on a page whose job is to get out of the way of the
// writing.
//
// Worth a test rather than an eyeball, because the cause was not in the
// widget: the app's InputDecorationTheme sets enabledBorder and
// focusedBorder, and those win over the `border` the field cleared. Anything
// added to that theme later would come back the same way.
void _titleDecorationTests() {
  testWidgets("a heading-styled field shows no border, focused or not",
      (tester) async {
    var controller = TextEditingController();
    var focus = FocusNode();

    await tester.pumpWidget(MaterialApp(
      // The same shape as the app's theme: borders declared per state
      // rather than on `border`.
      theme: ThemeData(
        inputDecorationTheme: const InputDecorationTheme(
          enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFFFFF00))),
          focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFFFFF00), width: 2)),
        ),
      ),
      home: Scaffold(
        body: TextField(
          controller: controller,
          focusNode: focus,
          decoration: const InputDecoration(
            hintText: "Untitled post",
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            filled: false,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    ));

    InputDecorator decorator() =>
        tester.widget<InputDecorator>(find.byType(InputDecorator));

    var resting = decorator().decoration;
    expect(resting.border, InputBorder.none);
    expect(resting.enabledBorder, InputBorder.none);
    expect(resting.focusedBorder, InputBorder.none);

    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(decorator().isFocused, isTrue,
        reason: "the field has to actually be focused for this to mean "
            "anything");
    expect(decorator().decoration.focusedBorder, InputBorder.none,
        reason: "the underline came back on focus");

    controller.dispose();
    focus.dispose();
  });
}
