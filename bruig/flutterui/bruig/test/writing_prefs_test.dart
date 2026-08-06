import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_support.dart';

// writing_prefs_test.dart covers the overrides: what the user has told the
// writing tools to stop reporting, and the session switch that silences the
// lot.

const _dictionary = ["the", "payment", "cleared"];
final _rules = [
  GrammarRule(r"[ ]{2,}", "Multiple spaces", " "),
  GrammarRule(r"[!?]{3,}", "Excessive punctuation", "!"),
];

Future<SpellcheckCapability> _capability(WritingPreferences prefs) async {
  var capability = SpellcheckCapability(
      fetch: (_) async => SpellcheckData(_dictionary, const [], _rules),
      prefs: prefs);
  await capability.update(FakePlugins({PluginCapability.spellcheckData}));
  return capability;
}

void main() {
  _descriptionTests();
  // StorageManager is backed by shared_preferences, which needs a fake store
  // in a test binding.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test("an ignored word stops being flagged", () async {
    var prefs = WritingPreferences();
    var capability = await _capability(prefs);

    expect(capability.review("dcrdex is fast"), isNotEmpty);
    prefs.ignoreOnce("dcrdex");
    expect(capability.review("dcrdex is fast").where((i) => i.text == "dcrdex"),
        isEmpty);
  });

  test("ignoring is case-insensitive, as the dictionary is", () async {
    var prefs = WritingPreferences();
    var capability = await _capability(prefs);
    prefs.ignoreOnce("DcrDex");
    expect(
        capability.review("dcrdex").where((i) => i.text == "dcrdex"), isEmpty);
  });

  // The distinction between the two menu entries: one outlives the session
  // and one does not. Without it there would be no way to tell which of them
  // had hidden a word, nor to take back the wrong one.
  test("only the dictionary survives a restart", () async {
    var prefs = WritingPreferences();
    prefs.ignoreOnce("oncelyword");
    await prefs.addToDictionary("keptword");

    var reloaded = WritingPreferences();
    await reloaded.load();
    expect(reloaded.isIgnoredWord("keptword"), isTrue);
    expect(reloaded.isIgnoredWord("oncelyword"), isFalse,
        reason: '"ignore once" must not outlive the session');
  });

  test("a word can be taken back out of the dictionary", () async {
    var prefs = WritingPreferences();
    await prefs.addToDictionary("mistake");
    expect(prefs.isIgnoredWord("mistake"), isTrue);
    await prefs.removeFromDictionary("mistake");
    expect(prefs.isIgnoredWord("mistake"), isFalse);

    var reloaded = WritingPreferences();
    await reloaded.load();
    expect(reloaded.isIgnoredWord("mistake"), isFalse,
        reason: "removing it must persist too");
  });

  test("a disabled check stops firing, and can be turned back on", () async {
    var prefs = WritingPreferences();
    var capability = await _capability(prefs);
    const text = "the  payment";

    var issue = capability.review(text).single;
    expect(issue.message, "Multiple spaces");
    expect(issue.checkId, isNotNull,
        reason: "a style issue must say which rule produced it");

    await prefs.disableCheck(issue.checkId!);
    expect(capability.review(text), isEmpty);

    await prefs.enableCheck(issue.checkId!);
    expect(capability.review(text), isNotEmpty);
  });

  // Rules are identified by pattern rather than message because a message is
  // shared: "Missing apostrophe" covers a dozen contractions, and turning one
  // off must not silently take the rest with it.
  test("disabling one check leaves its namesakes alone", () async {
    var prefs = WritingPreferences();
    // Both spellings are in the dictionary -- "cant" and "wont" are real
    // words -- so the only thing that can flag them is the style rule under
    // test, and a leftover spelling issue cannot be mistaken for one.
    var capability = SpellcheckCapability(
        fetch: (_) async => SpellcheckData(const [
              "cant",
              "wont"
            ], const [], [
              GrammarRule(r"\bcant\b", "Missing apostrophe", "can't"),
              GrammarRule(r"\bwont\b", "Missing apostrophe", "won't"),
            ]),
        prefs: prefs);
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));

    await prefs.disableCheck(r"\bcant\b");
    var issues = capability.review("cant wont");
    expect(issues.where((i) => i.text == "cant"), isEmpty);
    expect(issues.where((i) => i.text == "wont"), isNotEmpty,
        reason: "the other rule shares a message, not an identity");
  });

  test("the session switch silences everything", () async {
    var prefs = WritingPreferences();
    var capability = await _capability(prefs);
    const text = "the  paymnt";

    expect(capability.review(text), isNotEmpty);

    prefs.enabled = false;
    // review() is what the field paints from, so this is the inline marks
    // going as well as the panel emptying.
    expect(capability.review(text), isEmpty);

    prefs.enabled = true;
    expect(capability.review(text), isNotEmpty);
  });

  test("changing an override re-checks immediately", () async {
    var prefs = WritingPreferences();
    var capability = await _capability(prefs);
    var notified = 0;
    capability.addListener(() => notified++);

    prefs.ignoreOnce("something");
    expect(notified, greaterThan(0),
        reason: "an ignored word should leave the text at once, "
            "not at the next keystroke");
  });
}

// Reported: the disabled-checks list in Settings read "check 1, check 2".
// A rule is identified by its pattern, which is no use to a reader, so the
// message is stored alongside it -- and every place that turns a rule off has
// to pass it, not just the one that was fixed at the time.
void _descriptionTests() {
  test("turning a check off records what it was", () async {
    var prefs = WritingPreferences();
    await prefs.disableCheck(r"\balot\b",
        description: "\"a lot\" is two words");
    expect(prefs.disabledChecks[r"\balot\b"], "\"a lot\" is two words");
  });
}
