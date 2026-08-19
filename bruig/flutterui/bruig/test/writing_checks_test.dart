import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/composer_edits.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/issue_list_page.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_support.dart';

// writing_checks_test.dart covers the third severity: a rule that asks rather
// than tells.
//
// The case it exists for is "It would brake the system", which every other
// tier has to leave alone. An error rule cannot catch it without also
// catching "he had to brake"; a style suggestion would be claiming the
// phrasing could be better when the claim is that the word may be wrong. A
// check says neither, offers the other spelling, and takes "Correct Usage"
// for an answer -- and it is that answer, permanent and per-phrase, that
// makes a rule allowed to be wrong tolerable to the writer who was right.

const _dictionary = ["it", "would", "brake", "break", "the", "system", "hard"];

/// _brake is the pilot rule as the plugin ships it, cut down to the one
/// position under test.
final _brake = GrammarRule(
  r"\b([wW]ould|[cC]ould|[tT]o)\s+brake\b",
  "Did you mean \"\$1 break\"?",
  r"$1 break",
  "Possible confusion",
  "A \"brake\" stops a vehicle. To \"break\" something is to damage it.",
  "check",
);

Future<(SpellcheckCapability, WritingPreferences)> _configured(
    {WritingPreferences? preferences}) async {
  var prefs = preferences ?? WritingPreferences();
  var capability = SpellcheckCapability(
      fetch: (_) async =>
          SpellcheckData(_dictionary, const [], [_brake], const []),
      prefs: prefs);
  await capability.update(FakePlugins({PluginCapability.spellcheckData}));
  return (capability, prefs);
}

/// _greeting is the vocative check as the plugin ships it: two right answers,
/// offered in the order the rule names them.
final _greeting = GrammarRule(
  r"(^|[.!?]\s|\n)(Hi|Hello)\s+([A-Z][a-z]{2,})\s+([a-z]+)",
  "Comma after the name?",
  r"$1$2 $3, $4",
  "Punctuation",
  "The name you are addressing is separated from what you go on to say.",
  "check",
  const [],
  [r"$1$2, $3, $4"],
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // A question with two right answers has to be allowed to say so. Picking
  // one of them for the reader is wrong half the time while looking certain.
  test("a rule can offer more than one answer", () async {
    var prefs = WritingPreferences();
    var capability = SpellcheckCapability(
        fetch: (_) async => SpellcheckData(
            const ["hi", "sarah", "thanks", "for", "the", "notes"],
            const [],
            [_greeting],
            const []),
        prefs: prefs);
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));

    var issue = capability.review("Hi Sarah thanks for the notes").single;
    expect(issue.suggestions, ["Hi Sarah, thanks", "Hi, Sarah, thanks"],
        reason: "the rule's own answer leads, and its alternative follows");

    // Both have to be applicable, not merely listed.
    var fixed = "Hi Sarah thanks for the notes".replaceRange(
        issue.range.start, issue.range.end, issue.suggestions.last);
    expect(fixed, "Hi, Sarah, thanks for the notes");
  });

  test("a check is neither a mistake nor a phrasing opinion", () async {
    var (capability, _) = await _configured();

    var issue = capability.review("It would brake the system").single;
    expect(issue.kind, WritingIssueKind.check);
    expect(issue.kind.isMistake, isFalse,
        reason: "a check must not be listed among the things that are wrong");
    expect(issue.kind.isCheck, isTrue);
    expect(issue.suggestions, ["would break"],
        reason: "the other reading is the whole content of the question");
  });

  // The tier's own colour. Sharing the suggestion's blue was the smaller
  // change and the wrong one: blue says the writing could read better, amber
  // says it may be the wrong word.
  test("a check is marked differently from both of the others", () {
    Color colorOf(WritingIssueKind kind) =>
        SpellcheckCapability.styleFor(kind).decorationColor!;

    expect(colorOf(WritingIssueKind.check),
        isNot(colorOf(WritingIssueKind.phrasing)));
    expect(colorOf(WritingIssueKind.check),
        isNot(colorOf(WritingIssueKind.grammar)));
  });

  test("Correct Usage answers the question for good", () async {
    var (capability, prefs) = await _configured();
    const text = "It would brake the system";
    var issue = capability.review(text).single;

    await prefs.acceptUsage(issue.checkId!, issue.text);
    expect(capability.review(text), isEmpty);

    // The point of persisting it: a reader who confirmed the word once is
    // not asked again next week, which is the only thing that makes a rule
    // allowed to be wrong worth shipping.
    var restarted = WritingPreferences();
    await restarted.load();
    var (afterRestart, _) = await _configured(preferences: restarted);
    expect(afterRestart.review(text), isEmpty,
        reason: "an accepted usage that forgets is an ignore-once");
  });

  // The phrase, not the word. Somebody who confirms one sentence has not
  // confirmed every sentence they will ever write with that word in it.
  test("accepting one wording leaves the others asked about", () async {
    var (capability, prefs) = await _configured();
    var issue = capability.review("It would brake the system").single;
    await prefs.acceptUsage(issue.checkId!, issue.text);

    expect(capability.review("It could brake the system"), isNotEmpty);
    expect(prefs.isCheckDisabled(_brake.pattern), isFalse,
        reason: "accepting a wording is not turning the check off");
  });

  test("an accepted wording can be taken back", () async {
    var (capability, prefs) = await _configured();
    const text = "It would brake the system";
    var issue = capability.review(text).single;
    await prefs.acceptUsage(issue.checkId!, issue.text);

    var key = prefs.acceptedUsages.single;
    expect(WritingPreferences.describeUsage(key).$2, "would brake");
    await prefs.unacceptUsage(key);
    expect(capability.review(text), isNotEmpty,
        reason: "a permanent dismissal with no way back is how the tools "
            "quietly stop working");
  });

  // The button itself, rather than the model behind it. Two dead controls
  // once shipped behind passing model tests -- see the sidebar's own tests.
  testWidgets("the row offers Correct Usage and it clears the issue",
      (tester) async {
    var (capability, prefs) = await _configured();
    var controller = TextEditingController(text: "It would brake the system");
    addTearDown(controller.dispose);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<WritingPreferences>.value(value: prefs),
        Provider<ThesaurusCapability?>.value(value: null),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer<WritingPreferences>(
            builder: (context, prefs, _) => IssueListPage(
              issues: capability.review(controller.text),
              edits: ComposerEdits(controller),
              empty: "Nothing to suggest for this post.",
            ),
          ),
        ),
      ),
    ));

    expect(find.text("would brake"), findsOneWidget);
    expect(find.text("Correct Usage"), findsOneWidget);
    expect(find.text("Ignore once"), findsNothing,
        reason: "a session ignore and a permanent accept are the same click "
            "to anyone reading the row");

    await tester.tap(find.text("Correct Usage"));
    await tester.pumpAndSettle();

    expect(find.text("Correct Usage"), findsNothing);
    expect(find.text("Nothing to suggest for this post."), findsOneWidget);
  });
}
