import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';

import 'plugin_test_support.dart';

// spellcheck_menu_test.dart covers what a right-click on a flagged word
// actually offers. The gap it was written for: the composer showed the wavy
// underline but no corrections, because Flutter only surfaces those through
// a toolbar builder that was never set -- so the underline pointed at a
// problem the menu could not fix.

const _dictionary = [
  "the",
  "three",
  "there",
  "they",
  "payment",
  "happy",
  "it",
  "cleared"
];

/// _menuFor builds a composer wired the way the real ones are, puts the
/// caret inside [word], and returns the labels its context menu offers.
Future<List<String>> _menuFor(
  WidgetTester tester,
  String text,
  int caretOffset, {
  bool thesaurus = false,
  List<GrammarRule> rules = const [],
  // selectWord mimics a desktop right-click, which selects the word under
  // the pointer rather than merely placing a caret. That difference is what
  // made a flagged letter unclickable while the punctuation beside it
  // worked, so it has to be expressible here.
  int? selectTo,
}) async {
  var capability = SpellcheckCapability(
      fetch: () async => SpellcheckData(_dictionary, const [], rules));
  await capability.update(FakePlugins({PluginCapability.spellcheckData}));

  var labels = <String>[];
  var controller = TextEditingController(text: text);
  var focusNode = FocusNode();

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SpellcheckCapability>.value(value: capability),
      Provider<ThesaurusCapability?>.value(
        value: thesaurus
            ? ThesaurusCapability(
                FakePlugins({PluginCapability.thesaurus}),
                fetch: (w) async => ThesaurusEntry(w, [
                  ThesaurusSense("adj", ["glad"], [])
                ]),
              )
            : null,
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: TextField(
          controller: controller,
          focusNode: focusNode,
          spellCheckConfiguration: capability.configuration,
          contextMenuBuilder: (context, editableTextState) {
            labels = [
              ...spellingContextMenuItems(context, editableTextState),
              ...thesaurusContextMenuItems(context, editableTextState),
            ].map((item) => item.label ?? "<${item.type.name}>").toList();
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  ));

  focusNode.requestFocus();
  await tester.pump();

  // Drive the spell check the way the framework does, then place the caret
  // and open the menu.
  var state = tester.state<EditableTextState>(find.byType(EditableText));
  var spans = await capability.configuration!.spellCheckService!
      .fetchSpellCheckSuggestions(const Locale("en", "US"), text);
  state.spellCheckResults = SpellCheckResults(text, spans ?? []);
  controller.selection = selectTo == null
      ? TextSelection.collapsed(offset: caretOffset)
      : TextSelection(baseOffset: caretOffset, extentOffset: selectTo);
  await tester.pump();

  state.showToolbar();
  await tester.pump();
  return labels;
}

void main() {
  // Reported from the chat composer: choosing Ignore or Add to dictionary
  // left the red underline exactly where it was. Flutter re-runs spell check
  // only when the text changes, so an override -- which changes the answer
  // without touching a character -- left the old result on screen until the
  // next keystroke.
  testWidgets("an override clears the underline at once", (tester) async {
    var prefs = WritingPreferences();
    var capability = SpellcheckCapability(
        fetch: () async => SpellcheckData(_dictionary, const [], const []),
        prefs: prefs);
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));

    late EditableTextState editableState;
    var menuItems = <ContextMenuButtonItem>[];
    var controller = TextEditingController(text: "paymnt");
    var focusNode = FocusNode();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SpellcheckCapability>.value(value: capability),
        ChangeNotifierProvider<WritingPreferences>.value(value: prefs),
        Provider<ThesaurusCapability?>.value(value: null),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: controller,
            focusNode: focusNode,
            spellCheckConfiguration: capability.configuration,
            contextMenuBuilder: (context, state) {
              editableState = state;
              menuItems = spellingContextMenuItems(context, state);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    ));

    focusNode.requestFocus();
    await tester.pump();

    var state = tester.state<EditableTextState>(find.byType(EditableText));
    var spans = await capability.configuration!.spellCheckService!
        .fetchSpellCheckSuggestions(const Locale("en", "US"), "paymnt");
    state.spellCheckResults = SpellCheckResults("paymnt", spans ?? []);
    controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();
    expect(state.spellCheckResults!.suggestionSpans, isNotEmpty,
        reason: "the word should start out flagged");

    state.showToolbar();
    await tester.pump();
    editableState = state;

    // Press the real menu entry rather than calling the model directly: the
    // refresh is part of what choosing it does.
    var ignore = menuItems.firstWhere((i) => i.label == "Ignore once");
    ignore.onPressed!();
    await tester.pump();

    expect(capability.review("paymnt"), isEmpty,
        reason: "the checker itself should no longer flag it");
    expect(editableState.spellCheckResults!.suggestionSpans, isEmpty,
        reason: "the underline outlived the word being ignored");
  });

  // The regression. "thh" is flagged, and the corrections the service
  // already computed for the underline must reach the menu.
  testWidgets("a misspelled word offers its corrections", (tester) async {
    var labels = await _menuFor(tester, "thh", 1);
    expect(labels, isNotEmpty,
        reason: "the menu offered nothing for a flagged word");
    expect(labels, contains("the"));
    expect(labels.length, lessThanOrEqualTo(maxCorrections),
        reason: "the menu should not list every near miss");
  });

  testWidgets("corrections come first", (tester) async {
    var labels = await _menuFor(tester, "thh", 1, thesaurus: true);
    expect(labels.first, isNot("Synonyms"),
        reason: "corrections are why the menu was opened on a flagged word");
  });

  // The second half of the reported problem: asking a thesaurus about a
  // misspelling can only ever return nothing, so it must not be offered.
  testWidgets("a misspelled word is not offered synonyms", (tester) async {
    var labels = await _menuFor(tester, "thh", 1, thesaurus: true);
    expect(labels, isNot(contains("Synonyms")));
  });

  // Reported: right-clicking the uncapitalised letter offered nothing, while
  // right-clicking the full stop at the end of the previous sentence worked.
  // Two causes, both fixed here: the rule's span used to begin at that full
  // stop, and the lookup tested a single cursor offset when a right-click
  // hands it a whole selected word.
  group("a flagged letter mid-text", () {
    var capitalRule = [
      GrammarRule(r"(?<=^|[.!?]\s)([a-z])",
          "Sentence should start with a capital", r"$U1"),
    ];

    testWidgets("is clickable on the letter itself", (tester) async {
      // "the payment. it cleared" -- right-click on "it" selects [13,15].
      var labels = await _menuFor(tester, "the payment. it cleared", 13,
          rules: capitalRule, selectTo: 15);
      expect(labels, contains("I"),
          reason: "clicking the flagged letter offered nothing");
    });

    testWidgets("is clickable with a plain caret too", (tester) async {
      var labels = await _menuFor(tester, "the payment. it cleared", 13,
          rules: capitalRule);
      expect(labels, contains("I"));
    });

    testWidgets("flags only the letter, not the punctuation before it",
        (tester) async {
      var capability = SpellcheckCapability(
          fetch: () async =>
              SpellcheckData(_dictionary, const [], capitalRule));
      await capability.update(FakePlugins({PluginCapability.spellcheckData}));
      const text = "the payment. it cleared";
      var issue = capability.review(text).firstWhere((i) => i.range.start > 0);
      expect(text.substring(issue.range.start, issue.range.end), "i",
          reason: "the underline should sit on the letter alone");
    });
  });

  testWidgets("a correctly spelled word offers no corrections", (tester) async {
    var labels = await _menuFor(tester, "payment", 3);
    expect(labels.where((l) => _dictionary.contains(l)), isEmpty,
        reason: "a word that is spelled fine has nothing to correct");
  });
}
