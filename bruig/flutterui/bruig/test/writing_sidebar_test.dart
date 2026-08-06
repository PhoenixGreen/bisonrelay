import 'package:bruig/models/composer_sidebar.dart';
import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_support.dart';

// writing_sidebar_test.dart mounts the arrangement the post editor and the
// feed screen really use -- a composer that offers its text, a host that
// owns the sidebar slot -- because the two are wired through a controller
// rather than a parent/child relationship, and nothing about reading either
// file on its own shows whether they meet.

/// _Host stands in for the feed screen: it decides what goes in the slot.
///
/// [reshape] mimics what the real screen does, and what made this fail:
/// opening the sidebar changes the layout enough that the composer beneath
/// it lands at a different depth, so its State is torn down and rebuilt --
/// which used to withdraw the composer and close the sidebar in the same
/// frame it opened.
class _Host extends StatefulWidget {
  final bool reshape;

  /// composing mirrors the Feed screen's tab check: the tools belong to the
  /// composer, so a screen showing something else must not hand the slot
  /// over even when the controller is still open.
  final bool composing;
  const _Host({this.reshape = false, this.composing = true});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  // The page lives with the host, as it does on the real screen -- see
  // WritingSidebar.page.
  WritingSidebarPage _page = WritingSidebarPage.mistakes;

  bool get reshape => widget.reshape;
  bool get composing => widget.composing;

  @override
  Widget build(BuildContext context) {
    var writing = Provider.of<ComposerSidebarController>(context);
    var composer = const _Composer();
    // Mirrors the Feed: the slot is the composer's while composing, and
    // which panel is in it is the controller's business. ComposerPanel.none
    // is the screen's own menu rather than an empty slot.
    var showsPanel =
        composing && writing.visible && writing.panel == ComposerPanel.writing;

    // Hiding the sidebar while composing means nothing beside the editor.
    // Falling through to the branch below would put the screen's own sidebar
    // back, which is what the Feed used to do -- so the icon looked like it
    // had merely closed the panel it was on.
    if (composing && writing.minimized) {
      return Scaffold(body: composer);
    }

    if (!showsPanel) {
      return Scaffold(
        body: reshape
            ? composer
            : Row(children: [
                const SizedBox(width: 220, child: Text("NORMAL SIDEBAR")),
                Expanded(child: composer),
              ]),
      );
    }
    return Scaffold(
      body: Row(children: [
        SizedBox(
          width: 220,
          child: WritingSidebar(
            controller: writing.editor,
            page: _page,
            onPageChanged: (page) => setState(() => _page = page),
          ),
        ),
        Expanded(child: composer),
      ]),
    );
  }
}

/// _Composer stands in for the post editor: it offers its controller and has
/// the button that opens the tools.
class _Composer extends StatefulWidget {
  const _Composer();

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final controller = TextEditingController(text: "the paymnt cleared");
  final focusNode = FocusNode();
  ComposerSidebarController? _sidebar;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sidebar = Provider.of<ComposerSidebarController>(context, listen: false)
        ..attach(controller);
    });
  }

  @override
  void dispose() {
    _sidebar?.detach(controller);
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
            child: TextField(
                controller: controller, focusNode: focusNode, maxLines: null)),
        OutlinedButton(
          onPressed: () =>
              Provider.of<ComposerSidebarController>(context, listen: false)
                  .show(ComposerPanel.writing),
          child: const Text("Writing Tools"),
        ),
      ]);
}

Future<void> _pumpApp(WidgetTester tester, WritingPreferences prefs,
    {bool reshape = false, bool composing = true}) async {
  var spellcheck = SpellcheckCapability(
      fetch: (_) async => SpellcheckData(const [
            "the",
            "cleared",
            "payment",
            "utilise"
          ], const [], [
            GrammarRule(r"\butilise\b", "Wordy -- try \"use\"", "use", "Style",
                "\"Utilise\" is usually just \"use\".", "suggestion"),
          ]),
      prefs: prefs);
  await spellcheck.update(FakePlugins({PluginCapability.spellcheckData}));

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<SpellcheckCapability>.value(value: spellcheck),
      ChangeNotifierProvider<WritingPreferences>.value(value: prefs),
      ChangeNotifierProvider(create: (c) => ComposerSidebarController()),
      Provider<ThesaurusCapability?>.value(
        value: ThesaurusCapability(
          FakePlugins({PluginCapability.thesaurus}),
          fetch: (w) async => w == "cleared"
              ? ThesaurusEntry(
                  w,
                  [
                    ThesaurusSense("verb", const ["settled"], const [])
                  ],
                  [ThesaurusDefinition("verb", "freed from any question")],
                )
              : null,
        ),
      ),
    ],
    child: MaterialApp(home: _Host(reshape: reshape, composing: composing)),
  ));
  await tester.pumpAndSettle();
}

/// _open switches the sidebar to [page] the way a reader would.
Future<void> _open(WidgetTester tester, WritingSidebarPage page) async {
  await tester.tap(find.byIcon(page.icon));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets("the button opens the sidebar", (tester) async {
    await _pumpApp(tester, WritingPreferences());

    expect(find.text("NORMAL SIDEBAR"), findsOneWidget,
        reason: "the slot starts as whatever the screen normally shows");

    await tester.tap(find.text("Writing Tools"));
    await tester.pumpAndSettle();

    expect(find.text("NORMAL SIDEBAR"), findsNothing,
        reason: "the button did not hand the slot over");
    expect(find.textContaining("Writing"), findsWidgets);
    // The composer's one misspelling should be listed.
    expect(find.text("paymnt"), findsOneWidget);
  });

  // Reported: hiding the sidebar made the writing tools disappear and left
  // the default sidebar in their place.
  //
  // Like the "not composing" test below, this covers the contract rather
  // than the Feed's own copy of the decision -- it cannot catch that screen
  // asking the wrong question, only that there is a right one to ask.
  testWidgets("hiding the sidebar leaves nothing beside the editor",
      (tester) async {
    await _pumpApp(tester, WritingPreferences());
    var controller = tester
        .state<_ComposerState>(find.byType(_Composer))
        .context
        .read<ComposerSidebarController>();

    controller.show(ComposerPanel.writing);
    await tester.pumpAndSettle();
    expect(find.byType(WritingSidebar), findsOneWidget);

    controller.toggleMinimized();
    await tester.pumpAndSettle();

    expect(find.byType(WritingSidebar), findsNothing);
    expect(find.text("NORMAL SIDEBAR"), findsNothing,
        reason: "hiding the sidebar put the screen's own one back");
    expect(find.byType(_Composer), findsOneWidget);
  });

  // The close button is gone: the nav above the panel is what moves between
  // them now, and a panel that could close itself left the slot showing the
  // Feed menu with no way to tell why. Switching is covered in
  // composer_sidebar_test.dart.

  testWidgets("ignoring a word from the sidebar drops it", (tester) async {
    var prefs = WritingPreferences();
    await _pumpApp(tester, prefs);
    await tester.tap(find.text("Writing Tools"));
    await tester.pumpAndSettle();

    expect(find.text("paymnt"), findsOneWidget);
    await tester.tap(find.text("Ignore"));
    await tester.pumpAndSettle();

    expect(find.text("paymnt"), findsNothing,
        reason: "an ignored word should leave the list at once");
    expect(prefs.isIgnoredWord("paymnt"), isTrue);
  });

  testWidgets("the switch silences the list", (tester) async {
    var prefs = WritingPreferences();
    await _pumpApp(tester, prefs);
    await tester.tap(find.text("Writing Tools"));
    await tester.pumpAndSettle();

    expect(find.text("paymnt"), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text("paymnt"), findsNothing);
    expect(prefs.enabled, isFalse);
  });

  // The reported failure: the button appeared to do nothing. Opening the
  // sidebar reshapes the layout, which rebuilds the composer's State, which
  // withdrew the composer -- and detach used to close the sidebar, undoing
  // the open in the same frame.
  testWidgets("the sidebar survives the composer being rebuilt",
      (tester) async {
    await _pumpApp(tester, WritingPreferences(), reshape: true);

    await tester.tap(find.text("Writing Tools"));
    await tester.pumpAndSettle();

    expect(find.byType(WritingSidebar), findsOneWidget,
        reason: "the sidebar closed itself as it opened");
  });

  // Reported: the alternatives sat behind a button that opened a sheet, when
  // the sidebar is already where suggestions live. They are now a page of it,
  // driven by the selection rather than by a search box.
  testWidgets("the thesaurus page answers for the selected word",
      (tester) async {
    await _pumpApp(tester, WritingPreferences());
    await tester.tap(find.text("Writing Tools"));
    await tester.pumpAndSettle();
    await _open(tester, WritingSidebarPage.thesaurus);

    expect(
        find.text(
            "Select a word to see what it means and what else could be said."),
        findsOneWidget,
        reason: "with nothing selected there is nothing to look up");

    // Select "cleared" -- offsets 11..18 of "the paymnt cleared". The field
    // has to hold focus first: an unfocused one does not keep a selection,
    // and neither does anyone selecting a word for real.
    var composer = tester.state<_ComposerState>(find.byType(_Composer));
    composer.focusNode.requestFocus();
    await tester.pumpAndSettle();
    composer.controller.selection =
        const TextSelection(baseOffset: 11, extentOffset: 18);
    await tester.pumpAndSettle();

    expect(find.text("settled"), findsOneWidget,
        reason: "the synonym should be listed without another click");
    // A word's meaning belongs beside its alternatives: choosing between
    // replacements is guesswork without knowing which sense was meant.
    expect(find.textContaining("freed from any question"), findsOneWidget,
        reason: "the definition should be shown alongside the alternatives");
  });

  test("a word with no entry says so rather than staying blank", () {
    // Covered at the capability level; see thesaurus_test.dart.
  });

  // Reported: switching checking off hid the button that opens the sidebar,
  // and the switch that turns it back on lives inside that sidebar -- so
  // there was no way back.
  testWidgets("the way back in survives checking being switched off",
      (tester) async {
    var prefs = WritingPreferences();
    await _pumpApp(tester, prefs);

    prefs.enabled = false;
    await tester.pumpAndSettle();

    expect(find.text("Writing Tools"), findsOneWidget,
        reason: "the only route back to the switch cannot depend on it");

    await tester.tap(find.text("Writing Tools"));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsOneWidget,
        reason: "and the switch has to be reachable once inside");

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(prefs.enabled, isTrue);
  });

  // Reported, back when everything shared one column: with a long list of
  // issues the alternatives were pushed below the fold, where nobody would
  // think to scroll for them. Its own page is the durable answer -- no amount
  // of anything on another page can push it anywhere.
  testWidgets("a long issue list cannot bury another page", (tester) async {
    await _pumpApp(tester, WritingPreferences());
    await tester.tap(find.text("Writing Tools"));
    await tester.pumpAndSettle();

    var composer = tester.state<_ComposerState>(find.byType(_Composer));
    composer.controller.text = List.filled(30, "paymnt").join(" ");
    composer.focusNode.requestFocus();
    await tester.pumpAndSettle();

    await _open(tester, WritingSidebarPage.thesaurus);
    expect(
        find.text(
            "Select a word to see what it means and what else could be said."),
        findsOneWidget);
  });

  group("the pages", () {
    // Mistakes and suggestions are separated so the list of things actually
    // wrong stays short enough to work through.
    testWidgets("mistakes and phrasing are listed apart", (tester) async {
      await _pumpApp(tester, WritingPreferences());
      await tester.tap(find.text("Writing Tools"));
      await tester.pumpAndSettle();

      var composer = tester.state<_ComposerState>(find.byType(_Composer));
      composer.controller.text = "the paymnt utilise";
      await tester.pumpAndSettle();

      expect(find.text("paymnt"), findsOneWidget,
          reason: "the misspelling belongs on the mistakes page");
      expect(find.text("utilise"), findsNothing,
          reason: "a suggestion must not pad the list of real errors");

      await _open(tester, WritingSidebarPage.phrasing);
      expect(find.text("utilise"), findsOneWidget);
      expect(find.text("paymnt"), findsNothing);
    });

    testWidgets("the document page counts the text", (tester) async {
      await _pumpApp(tester, WritingPreferences());
      await tester.tap(find.text("Writing Tools"));
      await tester.pumpAndSettle();
      await _open(tester, WritingSidebarPage.document);

      // "the paymnt cleared"
      expect(find.text("Words"), findsOneWidget);
      expect(find.text("3"), findsWidgets);
      expect(find.text("18"), findsWidgets, reason: "18 characters");
    });

    // Counting words needs no dictionary and no rules, so this page is the
    // one thing here that still works with the feature switched off.
    testWidgets("the document page survives the switch", (tester) async {
      var prefs = WritingPreferences();
      await _pumpApp(tester, prefs);
      await tester.tap(find.text("Writing Tools"));
      await tester.pumpAndSettle();

      prefs.enabled = false;
      await tester.pumpAndSettle();
      await _open(tester, WritingSidebarPage.document);

      expect(find.text("Words"), findsOneWidget,
          reason: "the counts do not depend on the checker being on");
    });

    testWidgets("the nav shows how much is on each page", (tester) async {
      await _pumpApp(tester, WritingPreferences());
      await tester.tap(find.text("Writing Tools"));
      await tester.pumpAndSettle();

      expect(find.byTooltip("Spelling & grammar (1)"), findsOneWidget,
          reason: "a page with nothing on it should say so before it is "
              "opened, not after");
      expect(find.byTooltip("Phrasing"), findsOneWidget,
          reason: "an empty page carries no count");
    });
  });

  // Reported: the tools appeared in the sidebar slot on every Feed tab, not
  // just while composing. The controller stays open across tabs on purpose
  // -- coming back to the editor should find the tools as they were left --
  // so it is the host that has to decide, from the screen it is showing.
  //
  // This covers the contract between the two. It cannot catch the screen
  // asking the wrong question, which is what went wrong: the Feed screen had
  // three separate conditions and one was left ungated. That is now one
  // value the three derive from, so they cannot disagree.
  testWidgets("a screen that is not composing keeps its own sidebar",
      (tester) async {
    await _pumpApp(tester, WritingPreferences(), composing: false);

    // Opened while the editor was on screen, then navigated away from.
    var controller = tester
        .state<_ComposerState>(find.byType(_Composer))
        .context
        .read<ComposerSidebarController>();
    controller.show(ComposerPanel.writing);
    await tester.pumpAndSettle();

    expect(find.byType(WritingSidebar), findsNothing,
        reason: "the tools took a slot on a screen with nothing to review");
    expect(find.text("NORMAL SIDEBAR"), findsOneWidget);
    expect(controller.visible, isTrue,
        reason: "returning to the editor should find them as they were left");
  });
}
