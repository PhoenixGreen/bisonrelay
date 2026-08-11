import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/writing_tools/writing_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_support.dart';

// writing_ignore_test.dart covers dismissing one phrase under one rule.
//
// Reported: a style suggestion offered only "Turn off this check", which is
// permanent and applies everywhere. "In order to" is padding in most
// sentences and exactly right in a few, so the only ways out were losing the
// rule for good or rewriting a sentence you were happy with.

const _dictionary = [
  "the",
  "release",
  "payment",
  "cleared",
  "in",
  "order",
  "to",
  "ship",
  "and",
  "we",
  "did",
  "it",
  "again",
];

Future<(SpellcheckCapability, WritingPreferences)> _configured({
  List<GrammarRule> rules = const [],
  List<AnalysisCheck> checks = const [],
}) async {
  var prefs = WritingPreferences();
  var capability = SpellcheckCapability(
      fetch: (_) async => SpellcheckData(_dictionary, const [], rules, checks),
      prefs: prefs);
  await capability.update(FakePlugins({PluginCapability.spellcheckData}));
  return (capability, prefs);
}

final _wordy = GrammarRule(
    r"\bin order to\b", 'Wordy -- try "to"', "to", "Style", "", "suggestion");

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test("a dismissed phrase stops being flagged", () async {
    var (capability, prefs) = await _configured(rules: [_wordy]);
    const text = "we did it in order to ship";
    var issue = capability.review(text).single;
    expect(issue.text, "in order to");

    prefs.ignoreMatch(issue.checkId!, issue.text);
    expect(capability.review(text), isEmpty);
  });

  // The whole point: the rule is still on, so the next post is still checked.
  test("the rule keeps working on other text", () async {
    var (capability, prefs) = await _configured(rules: [
      _wordy,
      GrammarRule(r"\bthe payment\b", "Wordy", "it", "Style", "", "suggestion"),
    ]);
    prefs.ignoreMatch(r"\bin order to\b", "in order to");

    expect(capability.review("in order to ship"), isEmpty);
    expect(capability.review("the payment cleared"), isNotEmpty,
        reason: "dismissing one phrase must not quieten a different rule");
    expect(prefs.isCheckDisabled(r"\bin order to\b"), isFalse,
        reason: "dismissing a phrase is not turning the check off");
  });

  // Keyed by rule and text together. Keyed by text alone this would also
  // silence the spelling of the same word.
  test("dismissing a phrase does not affect the speller", () async {
    var repeated = AnalysisCheck("repeated-word-in-paragraph", 2,
        r'"$1" used $2 times', "Repetition", "why", "suggestion", const []);
    var (capability, prefs) = await _configured(checks: [repeated]);
    const text = "the reliese and the reliese again";

    var issues = capability.review(text);
    expect(
        issues.where((i) => i.kind == WritingIssueKind.spelling), isNotEmpty);
    var repetition = issues
        .firstWhere((i) => i.checkId == "analysis:repeated-word-in-paragraph");

    prefs.ignoreMatch(repetition.checkId!, repetition.text);
    var after = capability.review(text);
    expect(after.where((i) => i.checkId != null), isEmpty);
    expect(after.where((i) => i.kind == WritingIssueKind.spelling), isNotEmpty,
        reason: "the misspelling is a separate finding and stays");
  });

  // A counting check reports every occurrence of one problem, so dismissing
  // it has to dismiss the finding rather than one of its marks.
  test("dismissing a counting check clears all of its marks", () async {
    var repeated = AnalysisCheck("repeated-word-in-paragraph", 3,
        r'"$1" used $2 times', "Repetition", "why", "suggestion", const []);
    var (capability, prefs) = await _configured(checks: [repeated]);
    const text = "the release, the release and the release";

    var issues = capability.review(text);
    expect(issues, hasLength(3));
    prefs.ignoreMatch(issues.first.checkId!, issues.first.text);
    expect(capability.review(text), isEmpty);
  });

  // Spelling has its own two ways out and no checkId at all, so the new
  // filter has to leave it alone.
  test("a misspelling is untouched by phrase dismissal", () async {
    var (capability, prefs) = await _configured();
    expect(capability.review("reliese").single.checkId, isNull);
    prefs.ignoreMatch("", "reliese");
    expect(capability.review("reliese"), isNotEmpty);
  });

  test("dismissal does not survive a restart", () async {
    var (_, prefs) = await _configured(rules: [_wordy]);
    prefs.ignoreMatch(r"\bin order to\b", "in order to");
    expect(prefs.isIgnoredMatch(r"\bin order to\b", "in order to"), isTrue);

    var (capability, fresh) = await _configured(rules: [_wordy]);
    expect(fresh.isIgnoredMatch(r"\bin order to\b", "in order to"), isFalse);
    expect(capability.review("in order to ship"), isNotEmpty,
        reason: "unlike the dictionary and disabled checks, this is for the "
            "session only");
  });
}
