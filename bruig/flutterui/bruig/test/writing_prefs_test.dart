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
      fetch: () async => SpellcheckData(_dictionary, const [], _rules),
      prefs: prefs);
  await capability.update(FakePlugins({PluginCapability.spellcheckData}));
  return capability;
}

void main() {
  _fieldKeyTests();
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
        fetch: () async => SpellcheckData(const [
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
    expect(capability.configuration, isNotNull);

    prefs.enabled = false;
    expect(capability.review(text), isEmpty);
    expect(capability.configuration, isNull,
        reason: "the inline underlines must go too, not just the panel");

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

// Reported: the on/off switch did nothing. EditableText reads
// spellCheckConfiguration once, in initState, and didUpdateWidget never
// looks at it again -- so a live field goes on checking with the
// configuration it was born with, whatever it is handed later. The only way
// the change lands is for the field to be rebuilt, which is what fieldKey is
// for.
void _fieldKeyTests() {
  test("the field key changes when checking is switched off", () async {
    var prefs = WritingPreferences();
    var capability = SpellcheckCapability(
        fetch: () async => SpellcheckData(const ["the"], const [], const []),
        prefs: prefs);
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));

    var whileOn = capability.fieldKey;
    prefs.enabled = false;
    expect(capability.fieldKey, isNot(whileOn),
        reason: "the field would otherwise keep checking after the switch");

    prefs.enabled = true;
    expect(capability.fieldKey, whileOn,
        reason: "switching back should restore the original field");
  });

  // The other half: an override must NOT rebuild the field, since that drops
  // focus and selection mid-sentence. Those clear their underline by
  // refreshing the results in place instead.
  test("adding a word to the dictionary leaves the field alone", () async {
    var prefs = WritingPreferences();
    var capability = SpellcheckCapability(
        fetch: () async => SpellcheckData(const ["the"], const [], const []),
        prefs: prefs);
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));

    var before = capability.fieldKey;
    await prefs.addToDictionary("dcrdex");
    prefs.ignoreOnce("bisonrelay");
    expect(capability.fieldKey, before);
  });
}
