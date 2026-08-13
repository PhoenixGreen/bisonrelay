import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_support.dart';

// writing_popup_test.dart covers what a right-click on a flagged word
// actually offers. The gap it was originally written for: the composer showed
// the wavy underline but no corrections, because Flutter only surfaces those
// through a toolbar builder that was never set -- so the underline pointed at
// a problem the menu could not fix.
//
// It now also covers the reason the menu became a popup: a bare list of
// replacement words says what to change and never why, which is no use to the
// person likeliest to right-click.

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

/// _MenuHost is a composer wired the way the real ones are, so what the tests
/// open is the same widget the app opens.
class _MenuHost extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  const _MenuHost({required this.controller, required this.focusNode});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: TextField(
          controller: controller,
          focusNode: focusNode,
          contextMenuBuilder: (context, editableTextState) =>
              writingContextMenu(context, editableTextState, fallbackItems: [
            ContextMenuButtonItem(
                onPressed: () {}, type: ContextMenuButtonType.paste),
          ]),
        ),
      );
}

/// _open builds a composer, puts the caret inside the flagged text and opens
/// the menu, leaving whatever it produced on screen to be asserted against.
Future<EditableTextState> _open(
  WidgetTester tester,
  String text,
  int caretOffset, {
  bool thesaurus = false,
  List<GrammarRule> rules = const [],
  WritingPreferences? prefs,
  // selectTo mimics a desktop right-click, which selects the word under the
  // pointer rather than merely placing a caret. That difference is what made
  // a flagged letter unclickable while the punctuation beside it worked, so
  // it has to be expressible here.
  int? selectTo,
}) async {
  var preferences = prefs ?? WritingPreferences();
  var capability = SpellcheckCapability(
      fetch: (_) async => SpellcheckData(_dictionary, const [], rules),
      prefs: preferences);
  await capability.update(FakePlugins({PluginCapability.spellcheckData}));

  var controller = WritingTextEditingController(text: text);
  var focusNode = FocusNode();

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<SpellcheckCapability>.value(value: capability),
      ChangeNotifierProvider<WritingPreferences>.value(value: preferences),
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
      home: _MenuHost(controller: controller, focusNode: focusNode),
    ),
  ));

  focusNode.requestFocus();
  await tester.pump();

  // Place the caret and open the menu. Nothing has to be handed to the field
  // first: it reads the capability itself.
  var state = tester.state<EditableTextState>(find.byType(EditableText));
  controller.selection = selectTo == null
      ? TextSelection.collapsed(offset: caretOffset)
      : TextSelection(baseOffset: caretOffset, extentOffset: selectTo);
  await tester.pump();

  state.showToolbar();
  await tester.pumpAndSettle();
  return state;
}

/// capability reaches the one the field is painting from.
SpellcheckCapability capability(EditableTextState state) =>
    state.context.read<SpellcheckCapability>();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  _multipleIssueTests();
  _unsuggestableIssueTest();

  // The original regression. "thh" is flagged, and the corrections the
  // service already computed for the underline must reach the popup.
  testWidgets("a misspelled word offers its corrections", (tester) async {
    await _open(tester, "thh", 1);
    expect(find.text("the"), findsOneWidget,
        reason: "the popup offered nothing for a flagged word");
  });

  // The point of the popup over a list of words: someone who does not know
  // the rule cannot act on "Should be it's" alone.
  testWidgets("an issue is explained, not just named", (tester) async {
    await _open(tester, "the payment", 5, rules: [
      GrammarRule(r"\bpayment\b", "Wordy", "fee", "Style",
          "This phrase says in several words what one would say as clearly."),
    ]);

    expect(find.text("Style"), findsOneWidget,
        reason: "the category should head the popup");
    expect(find.text("Wordy"), findsOneWidget,
        reason: "the short message belongs under the heading");
    expect(find.textContaining("says in several words"), findsOneWidget,
        reason: "the explanation is the reason the popup exists");
    expect(find.text("fee"), findsOneWidget);
  });

  // A provider that sends no category or explanation is still valid; the
  // popup falls back to the message rather than showing an empty heading.
  testWidgets("a rule with no category still gets a heading", (tester) async {
    await _open(tester, "the payment", 5, rules: [
      GrammarRule(r"\bpayment\b", "Wordy", "fee"),
    ]);
    expect(find.text("Wordy"), findsOneWidget,
        reason: "the message should stand in for the missing category");
  });

  // Replacing the menu must not cost the composer what its menu did before.
  testWidgets("the composer's own entries survive", (tester) async {
    await _open(tester, "thh", 1);
    expect(find.text("Paste"), findsOneWidget,
        reason: "the popup swallowed the composer's own menu");
  });

  testWidgets("choosing a correction rewrites the word", (tester) async {
    var state = await _open(tester, "thh", 1);
    await tester.tap(find.text("the"));
    await tester.pumpAndSettle();
    expect(state.textEditingValue.text, "the");
  });

  // Reported from the chat composer: choosing Ignore or Add to dictionary
  // left the red underline exactly where it was. Flutter re-runs spell check
  // only when the text changes, so an override -- which changes the answer
  // without touching a character -- left the old result on screen until the
  // next keystroke.
  testWidgets("an override clears the underline at once", (tester) async {
    var prefs = WritingPreferences();
    var state = await _open(tester, "paymnt", 3, prefs: prefs);
    expect(capability(state).review("paymnt"), isNotEmpty,
        reason: "the word should start out flagged");

    await tester.tap(find.text("Ignore once"));
    await tester.pumpAndSettle();

    expect(prefs.isIgnoredWord("paymnt"), isTrue);
    expect(capability(state).review("paymnt"), isEmpty,
        reason: "the mark outlived the word being ignored");
  });

  testWidgets("a style issue can be switched off from the popup",
      (tester) async {
    var prefs = WritingPreferences();
    var state = await _open(tester, "the payment", 5, prefs: prefs, rules: [
      GrammarRule(r"\bpayment\b", "Wordy", "fee"),
    ]);

    await tester.tap(find.text("Turn off this check"));
    await tester.pumpAndSettle();

    expect(prefs.isCheckDisabled(r"\bpayment\b"), isTrue);
    expect(capability(state).review("the payment"), isEmpty);
  });

  // The second half of an old report: asking a thesaurus about a misspelling
  // can only ever return nothing, so it must not be offered.
  testWidgets("a misspelled word is not offered a lookup", (tester) async {
    await _open(tester, "thh", 1, thesaurus: true);
    expect(find.text("Look up"), findsNothing);
  });

  testWidgets("a correctly spelled word gets the ordinary menu",
      (tester) async {
    await _open(tester, "payment", 0, thesaurus: true, selectTo: 7);
    expect(find.text("Look up"), findsOneWidget,
        reason: "a word that is spelled fine is one to look up, not correct");
    expect(find.text("Paste"), findsOneWidget);
  });

  // Reported: right-clicking the uncapitalised letter offered nothing, while
  // right-clicking the full stop at the end of the previous sentence worked.
  // Two causes, both fixed: the rule's span used to begin at that full stop,
  // and the lookup tested a single cursor offset when a right-click hands it
  // a whole selected word.
  group("a flagged letter mid-text", () {
    var capitalRule = [
      GrammarRule(
          r"(?<=^|[.!?]\s)([a-z])",
          "Sentence should start with a "
              "capital",
          r"$U1",
          "Capitalization",
          "A sentence begins with a capital letter."),
    ];

    testWidgets("is clickable on the letter itself", (tester) async {
      // "the payment. it cleared" -- right-click on "it" selects [13,15].
      await _open(tester, "the payment. it cleared", 13,
          rules: capitalRule, selectTo: 15);
      expect(find.text("I"), findsOneWidget,
          reason: "clicking the flagged letter offered nothing");
    });

    testWidgets("is clickable with a plain caret too", (tester) async {
      await _open(tester, "the payment. it cleared", 13, rules: capitalRule);
      expect(find.text("I"), findsOneWidget);
    });

    testWidgets("flags only the letter, not the punctuation before it",
        (tester) async {
      var capability = SpellcheckCapability(
          fetch: (_) async =>
              SpellcheckData(_dictionary, const [], capitalRule));
      await capability.update(FakePlugins({PluginCapability.spellcheckData}));
      const text = "the payment. it cleared";
      var issue = capability.review(text).firstWhere((i) => i.range.start > 0);
      expect(text.substring(issue.range.start, issue.range.end), "i",
          reason: "the underline should sit on the letter alone");
    });
  });
}

// Reported: a word with two problems surfaced them one at a time, each
// appearing only once the last was fixed, so the menu looked as though it had
// missed something. The inline underlines have to be disjoint, which is why
// review() drops overlaps -- but a popup opened on one word wants all of them.
void _multipleIssueTests() {
  test("every issue on a word reaches the popup", () async {
    var prefs = WritingPreferences();
    var capability = SpellcheckCapability(
      fetch: (_) async => SpellcheckData(const [
        "cant"
      ], const [], [
        GrammarRule(r"\bcant\b", "Missing apostrophe", "can't"),
        GrammarRule(r"\bcant\b", "Informal", "cannot"),
      ]),
      prefs: prefs,
    );
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));

    // The underline shows one, because it must.
    expect(capability.review("cant"), hasLength(1));

    // The popup sees both.
    var both = capability.issuesAt("cant", 0, 4);
    expect(both, hasLength(2));
    expect(both.map((i) => i.suggestions.single),
        containsAll(["can't", "cannot"]));
  });

  test("issuesAt only returns what the range touches", () async {
    var capability = SpellcheckCapability(
      fetch: (_) async => SpellcheckData(const [
        "the"
      ], const [], [
        GrammarRule(r"[ ]{2,}", "Multiple spaces", " "),
      ]),
      prefs: WritingPreferences(),
    );
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));

    const text = "the  the";
    expect(capability.issuesAt(text, 3, 5), isNotEmpty,
        reason: "the doubled space sits at 3..5");
    expect(capability.issuesAt(text, 0, 3), isEmpty,
        reason: "the first word is fine");
  });

  // The contract the popup reads its heading and body from. A provider that
  // sends neither still produces a usable issue, which is what lets an older
  // plugin keep working.
  test("a rule's category and explanation reach the issue", () async {
    var capability = SpellcheckCapability(
      fetch: (_) async => SpellcheckData(const [
        "cant"
      ], const [], [
        GrammarRule(
            r"\bcant\b",
            "Missing apostrophe",
            "can't",
            "Punctuation",
            "This is a contraction and the apostrophe stands in for the "
                "dropped letters."),
        GrammarRule(r"\bcant\b", "Informal", "cannot"),
      ]),
      prefs: WritingPreferences(),
    );
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));

    var issues = capability.issuesAt("cant", 0, 4);
    var explained = issues.firstWhere((i) => i.message == "Missing apostrophe");
    expect(explained.category, "Punctuation");
    expect(explained.title, "Punctuation");
    expect(explained.explanation, contains("stands in for"));

    var bare = issues.firstWhere((i) => i.message == "Informal");
    expect(bare.category, isEmpty);
    expect(bare.explanation, isEmpty);
    expect(bare.title, "Informal",
        reason: "a rule with no category falls back to its message");
  });

  // A misspelling has no rule behind it, so its heading and explanation are
  // the checker's own -- and must still be there.
  test("a misspelling explains itself too", () async {
    var capability = SpellcheckCapability(
      fetch: (_) async => SpellcheckData(const ["the"], const [], const []),
      prefs: WritingPreferences(),
    );
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));

    var issue = capability.review("paymnt").single;
    expect(issue.title, "Spelling");
    expect(issue.explanation, isNotEmpty);
  });
}

// A rule that flags without proposing a fix -- because there is no single
// right one -- has an explanation to give, and that is exactly the case a
// menu of replacement words could not serve at all.
void _unsuggestableIssueTest() {
  testWidgets("an issue with no correction still explains itself",
      (tester) async {
    await _open(tester, "the payment", 5, rules: [
      GrammarRule(
          r"\bpayment\b",
          "Wordy",
          "",
          "Style",
          "There is no single rewrite for this; it is flagged to draw the "
              "eye."),
    ]);

    expect(find.text("Style"), findsOneWidget,
        reason: "a flagged span with nothing to offer opened no popup");
    expect(find.textContaining("no single rewrite"), findsOneWidget);
  });
}
