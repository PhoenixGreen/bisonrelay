import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_support.dart';

// writing_paragraph_scope_test.dart covers the checker reviewing one
// paragraph at a time and keeping the answers.
//
// The saving is the whole point -- a keystroke in a long post re-scans the
// paragraph it landed in rather than the post -- and so is the risk. Every
// finding is now made at an offset into a paragraph and reported at an offset
// into the document, so an error of arithmetic here does not lose a finding:
// it puts the underline, and the correction that follows it, on the wrong
// words entirely.
//
// So the property under test is always the same one. Whatever the checker
// says is wrong, the range it says it about must slice exactly that text out
// of the document it was handed.

const _dictionary = [
  "the",
  "payment",
  "cleared",
  "and",
  "we",
  "shipped",
  "it",
  "release",
  "went",
  "out",
  "on",
  "tuesday",
  "in",
  "order",
  "to",
  "keep",
  "going",
  "utilise",
  "use",
  "a",
  "of",
  "was",
  "fine",
  "line",
  "first",
  "second",
  "third",
  "paragraph",
  "here",
  "with",
  "words",
];

final _wordy = GrammarRule(
    r"\bin order to\b", 'Wordy -- try "to"', "to", "Style", "", "suggestion");
final _utilise = GrammarRule(
    r"\butilise\b", 'Wordy -- try "use"', "use", "Style", "", "suggestion");

Future<SpellcheckCapability> _configured() async {
  var capability = SpellcheckCapability(
    fetch: (_) async =>
        SpellcheckData(_dictionary, const [], [_wordy, _utilise], const []),
    prefs: WritingPreferences(),
  );
  await capability.update(FakePlugins({PluginCapability.spellcheckData}));
  return capability;
}

/// _mustPointAtItself is the property: a range that does not slice out its
/// own text is an underline in the wrong place.
void _mustPointAtItself(String text, List<WritingIssue> issues) {
  for (var issue in issues) {
    expect(text.substring(issue.range.start, issue.range.end), issue.text,
        reason: "an issue about \"${issue.text}\" points at "
            "\"${text.substring(issue.range.start, issue.range.end)}\"");
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test("findings past the first paragraph land where they belong", () async {
    var capability = await _configured();
    const text = "the payment cleared\n\n"
        "we shipped it in order to keep going\n\n"
        "the relese went out on tuesday";

    var issues = capability.review(text);
    _mustPointAtItself(text, issues);
    expect(issues.map((i) => i.text), contains("in order to"));
    expect(issues.map((i) => i.text), contains("relese"),
        reason: "the dictionary has to reach the last paragraph too");
  });

  // The cache is keyed by a paragraph's text, so editing one paragraph must
  // not disturb what was found in another -- but everything below it moves.
  test("editing one paragraph moves the findings below it", () async {
    var capability = await _configured();
    const tail = "\n\nwe shipped it in order to keep going";

    var before = capability.review("the payment cleared$tail");
    var after = capability.review("the payment cleared and it was fine$tail");

    _mustPointAtItself("the payment cleared and it was fine$tail", after);
    var wordyBefore = before.firstWhere((i) => i.text == "in order to");
    var wordyAfter = after.firstWhere((i) => i.text == "in order to");
    expect(wordyAfter.range.start, wordyBefore.range.start + 16,
        reason: "the paragraph it is in did not change, but its position did");
  });

  test("editing a paragraph updates what it says about it", () async {
    var capability = await _configured();
    const head = "the payment cleared\n\n";

    expect(capability.review("${head}we utilise it").map((i) => i.text),
        contains("utilise"));
    expect(capability.review("${head}we use it").map((i) => i.text),
        isNot(contains("utilise")),
        reason: "a paragraph that has been fixed must stop being reported");
  });

  // Two identical paragraphs share one cache entry, and each has to come back
  // at its own offset rather than twice at the first one's.
  test("the same paragraph twice is reported twice, in two places", () async {
    var capability = await _configured();
    const paragraph = "we shipped it in order to keep going";
    const text = "$paragraph\n\n$paragraph";

    var issues =
        capability.review(text).where((i) => i.text == "in order to").toList();
    expect(issues, hasLength(2));
    _mustPointAtItself(text, issues);
    expect(issues[0].range.start, isNot(issues[1].range.start));
  });

  // A correction is applied at the range, so a stale one would splice text
  // into the middle of some other word.
  test("a correction from a later paragraph lands on the right words",
      () async {
    var capability = await _configured();
    const text = "the payment cleared\n\nwe utilise it";
    var issue = capability.review(text).firstWhere((i) => i.text == "utilise");

    var fixed = text.replaceRange(
        issue.range.start, issue.range.end, issue.suggestions.single);
    expect(fixed, "the payment cleared\n\nwe use it");
  });
}
