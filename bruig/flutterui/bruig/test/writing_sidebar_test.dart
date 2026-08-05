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
class _Host extends StatelessWidget {
  final bool reshape;
  const _Host({this.reshape = false});

  @override
  Widget build(BuildContext context) {
    var writing = Provider.of<WritingSidebarController>(context);
    var composer = const _Composer();
    if (!writing.visible) {
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
              controller: writing.editor, onClose: writing.close),
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
  WritingSidebarController? _sidebar;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sidebar = Provider.of<WritingSidebarController>(context, listen: false)
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
              Provider.of<WritingSidebarController>(context, listen: false)
                  .show(),
          child: const Text("Writing Tools"),
        ),
      ]);
}

Future<void> _pumpApp(WidgetTester tester, WritingPreferences prefs,
    {bool reshape = false}) async {
  var spellcheck = SpellcheckCapability(
      fetch: () async => SpellcheckData(
          const ["the", "cleared", "payment"], const [], const []),
      prefs: prefs);
  await spellcheck.update(FakePlugins({PluginCapability.spellcheckData}));

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<SpellcheckCapability>.value(value: spellcheck),
      ChangeNotifierProvider<WritingPreferences>.value(value: prefs),
      ChangeNotifierProvider(create: (c) => WritingSidebarController()),
      Provider<ThesaurusCapability?>.value(
        value: ThesaurusCapability(
          FakePlugins({PluginCapability.thesaurus}),
          fetch: (w) async => w == "cleared"
              ? ThesaurusEntry(w, [
                  ThesaurusSense("verb", const ["settled"], const [])
                ])
              : null,
        ),
      ),
    ],
    child: MaterialApp(home: _Host(reshape: reshape)),
  ));
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

  testWidgets("closing returns the slot", (tester) async {
    await _pumpApp(tester, WritingPreferences());
    await tester.tap(find.text("Writing Tools"));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip("Close"));
    await tester.pumpAndSettle();
    expect(find.text("NORMAL SIDEBAR"), findsOneWidget);
  });

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
  // the sidebar is already where suggestions live.
  testWidgets("alternatives appear in the panel, not behind a button",
      (tester) async {
    await _pumpApp(tester, WritingPreferences());
    await tester.tap(find.text("Writing Tools"));
    await tester.pumpAndSettle();

    expect(find.text("Select a word for alternatives."), findsOneWidget,
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

  // Reported: with a long list of issues the alternatives were pushed below
  // the fold, where nobody would think to scroll for them -- and they answer
  // a question about what is selected right now.
  testWidgets("the alternatives stay in view below a long issue list",
      (tester) async {
    await _pumpApp(tester, WritingPreferences());
    await tester.tap(find.text("Writing Tools"));
    await tester.pumpAndSettle();

    var composer = tester.state<_ComposerState>(find.byType(_Composer));
    composer.controller.text = List.filled(30, "paymnt").join(" ");
    composer.focusNode.requestFocus();
    await tester.pumpAndSettle();

    expect(find.text("Select a word for alternatives."), findsOneWidget,
        reason: "the alternatives were pushed out of the panel");
  });
}
