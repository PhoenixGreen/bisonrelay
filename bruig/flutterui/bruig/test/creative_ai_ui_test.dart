import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/sidebar_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/canvas_sidebar.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/sidebar_panels.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai.dart';
import 'package:bruig/plugin_system/creative_ai/ui/creative_ai_settings.dart';
import 'package:bruig/plugin_system/creative_ai/ui/writing_ai_panel.dart';
import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/plugin_system/writing_tools/ui/composer_sidebar_shell.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/canvas_app.dart';
import 'support/plugin_test_support.dart';

// creative_ai_ui_test.dart presses Creative AI's controls as a person would:
// the settings switches, the Canvas sidebar's icon, the Writing panel's icon,
// a suggestion's Accept, a quick edit with no Claude Code, and the
// right-click entries. Model tests alone once let dead controls ship.

class _Rig {
  final prefs = CreativeAiPreferences();
  final canvasPrefs = CanvasPreferences();
  final canvas = CanvasController(const CanvasDocument());
  final composer = ComposerSidebarController();
  final library = PostLibraryModel();
  late final CreativeAi ai = CreativeAi(
    prefs: prefs,
    canvas: () => canvas,
    canvasPrefs: () => canvasPrefs,
    composer: () => composer,
    library: () => library,
    serve: false,
    locateClaude: (_) async => null,
    // No disk in a widget test: the Styles panel says it could not read.
    stylesRoot: () async => throw "no disk here",
  );

  _Rig() {
    registerCreativeAi(prefs);
  }

  List<ChangeNotifierProvider> get providers => [
        ChangeNotifierProvider<CreativeAi>.value(value: ai),
        ChangeNotifierProvider<CreativeAiPreferences>.value(value: prefs),
        ChangeNotifierProvider<ComposerSidebarController>.value(
            value: composer),
        ChangeNotifierProvider<PostLibraryModel>.value(value: library),
      ];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets("the settings switches do what they say, at a large text size",
      (tester) async {
    var rig = _Rig();
    await pumpCanvasApp(
        tester,
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: ListView(children: const [CreativeAiSettingsSection()]),
        ),
        size: const Size(800, 2400),
        extra: rig.providers);
    expect(find.byKey(const ValueKey("creativeAiCanvas")), findsNothing);
    await tester.tap(find.byKey(const ValueKey("creativeAiEnabled")));
    await tester.pumpAndSettle();
    expect(rig.prefs.enabled, isTrue);
    // Claude Code looked for, and not found here: said so.
    expect(find.textContaining("was not found"), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey("creativeAiCanvas")));
    await tester.pumpAndSettle();
    expect(rig.prefs.canvas, isFalse);
    await tester.tap(find.byKey(const ValueKey("creativeAiApplyEdits")));
    await tester.pumpAndSettle();
    expect(rig.prefs.applyEdits, isTrue);

    var token = rig.prefs.token;
    await tester
        .ensureVisible(find.byKey(const ValueKey("creativeAiNewToken")));
    await tester.tap(find.byKey(const ValueKey("creativeAiNewToken")));
    await tester.pumpAndSettle();
    expect(rig.prefs.token, isNot(token));
    expect(tester.takeException(), isNull);
  });

  testWidgets("Canvas gets a Creative AI sidebar while it is on",
      (tester) async {
    var rig = _Rig();
    rig.prefs.enabled = true;
    rig.canvasPrefs.enabled = true;
    setTestScreen(tester, const Size(1200, 1000));
    var laid = ValueNotifier(const SidebarLayout(current: "design"));
    var bodies = SidebarPanelBodies(
      controller: rig.canvas,
      onOpen: (_, __) async {},
      onPublish: (_, __) {},
      onNew: (_, __) async {},
      onChoosePreset: (_, __) {},
    );
    await tester.pumpWidget(canvasApp(
        ValueListenableBuilder<SidebarLayout>(
            valueListenable: laid,
            builder: (context, l, _) => Row(children: [
                  SizedBox(
                      width: 320,
                      child: CanvasSidebar(
                          controller: rig.canvas,
                          layout: l,
                          onLayout: (next) => laid.value = next,
                          onHide: () {},
                          bodies: bodies,
                          onCustomise: () {})),
                  const Expanded(child: SizedBox()),
                ])),
        prefs: rig.canvasPrefs,
        extra: rig.providers));
    await tester.pump();

    var icon = find.byKey(const ValueKey("sidebarTab-creativeAi"));
    expect(icon, findsOneWidget);
    await tester.tap(icon);
    await tester.pumpAndSettle();
    expect(laid.value.current, "creativeAi");
    expect(find.text("ASK CLAUDE"), findsOneWidget);
    expect(find.byKey(const ValueKey("aiChatInput")), findsOneWidget);

    // Claude's changes offer Undo all, which puts the canvas back.
    rig.ai.beforeCanvasChange();
    rig.canvas.addElement(CanvasDocument.fromJson(const {
      "elements": [
        {"kind": "shape", "id": "s1"}
      ]
    }).elements.single);
    // Not settled: a selected element's panels keep a ticker going.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey("creativeAiUndoAll")));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(rig.canvas.document.elements, isEmpty);
    expect(find.byKey(const ValueKey("creativeAiUndoAll")), findsNothing);

    // Switched off for Canvas, its icon goes.
    rig.prefs.canvas = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey("sidebarTab-creativeAi")), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("Writing gets a Creative AI panel icon", (tester) async {
    var rig = _Rig();
    rig.prefs.enabled = true;
    await pumpCanvasApp(
        tester,
        SizedBox(
          width: 320,
          child: ComposerSidebarShell(
              controller: rig.composer,
              panels: ComposerPanel.values,
              child: const SizedBox()),
        ),
        extra: rig.providers);
    await tester.tap(find.byTooltip("Creative AI"));
    await tester.pumpAndSettle();
    expect(rig.composer.extra, writingAiPanelId);
    rig.prefs.writing = false;
    await tester.pumpAndSettle();
    expect(find.byTooltip("Creative AI"), findsNothing);
  });

  testWidgets("a suggestion is accepted or rejected from its card",
      (tester) async {
    var rig = _Rig();
    rig.prefs.enabled = true;
    var editor = TextEditingController(text: "The quick brown fox.");
    rig.composer.attach(editor);
    await pumpCanvasApp(
        tester,
        SizedBox(
            width: 360,
            height: 900,
            child: WritingAiPanel(composer: rig.composer)),
        extra: rig.providers);

    rig.ai.suggestions
        .offer(start: 10, end: 15, replacement: "red", source: "Improve");
    var newest = rig.ai.suggestions
        .offer(start: 4, end: 9, replacement: "slow", source: "Improve");
    await tester.pumpAndSettle();
    // The heading counts them; the newest is at the top.
    expect(find.text("2"), findsWidgets);
    expect(find.byKey(const ValueKey("aiAcceptAll")), findsOneWidget);
    await tester.ensureVisible(find.byKey(ValueKey("aiAccept-${newest.id}")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey("aiAccept-${newest.id}")));
    await tester.pumpAndSettle();
    expect(editor.text, "The slow brown fox.");
    await tester.ensureVisible(find.byKey(const ValueKey("aiReject-1")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("aiReject-1")));
    await tester.pumpAndSettle();
    expect(find.byType(SuggestionCard), findsNothing);
    expect(editor.text, "The slow brown fox.");

    // A quick edit with no Claude Code says what to do about it.
    editor.selection = const TextSelection(baseOffset: 0, extentOffset: 9);
    await tester.ensureVisible(find.byKey(const ValueKey("aiRewrite-improve")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("aiRewrite-improve")));
    await tester.pumpAndSettle();
    expect(find.textContaining("was not found"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("selected text offers Creative AI on its right-click menu",
      (tester) async {
    var rig = _Rig();
    rig.prefs.enabled = true;
    var preferences = WritingPreferences();
    var capability = SpellcheckCapability(
        fetch: (_) async => SpellcheckData(const ["the"], const [], const []),
        prefs: preferences);
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));
    var editor = WritingTextEditingController(text: "The quick brown fox.");
    rig.composer.attach(editor);
    var focus = FocusNode();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SpellcheckCapability>.value(value: capability),
        ChangeNotifierProvider<WritingPreferences>.value(value: preferences),
        Provider<ThesaurusCapability?>.value(value: null),
        ...rig.providers,
      ],
      child: MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: editor,
            focusNode: focus,
            contextMenuBuilder: (context, state) => writingContextMenu(
                context, state,
                fallbackItems: state.contextMenuButtonItems),
          ),
        ),
      ),
    ));
    focus.requestFocus();
    await tester.pump();
    var state = tester.state<EditableTextState>(find.byType(EditableText));
    editor.selection = const TextSelection(baseOffset: 4, extentOffset: 9);
    await tester.pump();
    state.showToolbar();
    await tester.pumpAndSettle();
    expect(find.text("Improve with Claude"), findsOneWidget);
    await tester.tap(find.text("Creative AI…"));
    await tester.pumpAndSettle();
    expect(rig.composer.extra, writingAiPanelId);

    // Switched off for Writing, the entries go.
    rig.prefs.writing = false;
    state.showToolbar();
    await tester.pumpAndSettle();
    expect(find.text("Improve with Claude"), findsNothing);
  });
}
