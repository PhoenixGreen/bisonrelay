import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';

import 'plugin_test_support.dart';

// thesaurus_test.dart covers the app's side of the thesaurus capability:
// which selections are worth asking a provider about, and that the answer is
// only asked for once.

ThesaurusEntry _happy() => ThesaurusEntry("happy", [
      ThesaurusSense("adj", ["glad", "cheerful"], ["unhappy"]),
    ]);

void main() {
  test("no provider means no lookup at all", () async {
    var asked = <String>[];
    var capability = ThesaurusCapability(
      FakePlugins({}),
      fetch: (w) async {
        asked.add(w);
        return _happy();
      },
    );
    expect(capability.available, isFalse);
    expect(await capability.lookUp("happy"), isNull);
    expect(asked, isEmpty, reason: "the provider was woken for nothing");
  });

  test("a word is looked up and returned", () async {
    var capability = ThesaurusCapability(
      FakePlugins({PluginCapability.thesaurus}),
      fetch: (w) async => _happy(),
    );
    var entry = await capability.lookUp("happy");
    expect(entry, isNotNull);
    expect(entry!.senses.single.synonyms, contains("glad"));
    expect(entry.senses.single.antonyms, contains("unhappy"));
  });

  // Re-opening the menu on the same word is the common case, and the answer
  // cannot change while a provider stays enabled.
  test("a repeated lookup does not ask again", () async {
    var calls = 0;
    var capability = ThesaurusCapability(
      FakePlugins({PluginCapability.thesaurus}),
      fetch: (w) async {
        calls++;
        return _happy();
      },
    );
    await capability.lookUp("happy");
    await capability.lookUp("Happy");
    await capability.lookUp("  happy  ");
    expect(calls, 1);
  });

  // A miss is cached too: a name or a typo is exactly what gets selected
  // repeatedly while someone fiddles with a sentence.
  test("a miss is remembered", () async {
    var calls = 0;
    var capability = ThesaurusCapability(
      FakePlugins({PluginCapability.thesaurus}),
      fetch: (w) async {
        calls++;
        return null;
      },
    );
    expect(await capability.lookUp("zzznotaword"), isNull);
    expect(await capability.lookUp("zzznotaword"), isNull);
    expect(calls, 1);
  });

  test("a failing provider yields nothing rather than throwing", () async {
    var capability = ThesaurusCapability(
      FakePlugins({PluginCapability.thesaurus}),
      fetch: (w) async => throw "provider is not loaded",
    );
    expect(await capability.lookUp("happy"), isNull);
  });

  group("normalizeWord", () {
    test("trims the punctuation a selection drags along", () {
      // Double-clicking a word routinely takes the comma or quote with it.
      for (var raw in ["happy", " happy ", "happy,", '"happy"', "(happy)"]) {
        expect(ThesaurusCapability.normalizeWord(raw), "happy",
            reason: "for input ${raw.trim()}");
      }
    });

    test("lowercases, since the thesaurus is keyed that way", () {
      expect(ThesaurusCapability.normalizeWord("Happy"), "happy");
    });

    test("keeps internal apostrophes and hyphens", () {
      expect(ThesaurusCapability.normalizeWord("well-chosen"), "well-chosen");
      expect(ThesaurusCapability.normalizeWord("don't"), "don't");
    });

    test("rejects what no thesaurus can answer", () {
      // A phrase, a number, and pure punctuation: asking about any of these
      // wakes the plugin to no purpose.
      for (var raw in ["two words", "", "   ", "123", "!!!", "3.5"]) {
        expect(ThesaurusCapability.normalizeWord(raw), isNull,
            reason: "for input '$raw'");
      }
    });
  });
}
