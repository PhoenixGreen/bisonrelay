import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';

import 'plugin_test_support.dart';

// spellcheck_suggestions_test.dart covers the checker's two jobs -- flagging
// unknown words with useful corrections, and running the provider's grammar
// rules -- and in particular that making the dictionary lookup fast did not
// make it wrong.

// _dictionary is deliberately full of near-misses for the typos below, so a
// lookup that narrowed the candidate set too aggressively would visibly lose
// one rather than merely reorder them.
const _dictionary = [
  "receive",
  "relieve",
  "believe",
  "recede",
  "receipt",
  "separate",
  "desperate",
  "federate",
  "operate",
  "definitely",
  "delicately",
  "occurred",
  "occur",
  "accused",
  "weird",
  "wield",
  "wired",
  "the",
  "then",
  "they",
  "them",
  "there",
  "address",
  "adders",
  "payment",
  "payments",
  "channel",
  "channels",
  "invoice",
  "decred",
  "bisonrelay",
];

Future<SpellCheckConfiguration> _configFor(SpellcheckData data) async {
  var capability = SpellcheckCapability(fetch: () async => data);
  await capability.update(FakePlugins({PluginCapability.spellcheckData}));
  return capability.configuration!;
}

Future<List<SuggestionSpan>> _check(
    SpellCheckConfiguration config, String text) async {
  var spans = await config.spellCheckService!
      .fetchSpellCheckSuggestions(const Locale("en", "US"), text);
  return spans ?? [];
}

void main() {
  var plain = SpellcheckData(_dictionary, []);

  test("a known word is not flagged", () async {
    var spans = await _check(await _configFor(plain), "the payment");
    expect(spans, isEmpty);
  });

  test("an unknown word is flagged with near corrections", () async {
    var spans = await _check(await _configFor(plain), "recieve");
    expect(spans, hasLength(1));
    expect(spans.first.suggestions, contains("receive"));
  });

  // The reason this file exists. The lookup narrows candidates by length and
  // by letter set before measuring edit distance; both filters must be
  // necessary conditions only, or a correction silently disappears. An
  // earlier version used the wrong letter-set bound and lost "believe" for
  // "recieve" -- a two-edit correction it should always offer.
  test("narrowing the candidates loses no correction", () async {
    var config = await _configFor(plain);
    // Every dictionary word within two edits, found by brute force.
    int distance(String a, String b) {
      var prev = List<int>.generate(b.length + 1, (i) => i);
      var curr = List<int>.filled(b.length + 1, 0);
      for (var i = 1; i <= a.length; i++) {
        curr[0] = i;
        for (var j = 1; j <= b.length; j++) {
          var cost = a[i - 1] == b[j - 1] ? 0 : 1;
          curr[j] = [prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost]
              .reduce((x, y) => x < y ? x : y);
        }
        var t = prev;
        prev = curr;
        curr = t;
      }
      return prev[b.length];
    }

    for (var typo in ["recieve", "seperate", "occured", "wierd", "adress"]) {
      // What an exhaustive scan of the dictionary would rank, nearest first.
      var scored = _dictionary
          .map((w) => MapEntry(w, distance(typo, w)))
          .where((e) => e.value <= 2)
          .toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      var wantDistances = scored.take(3).map((e) => e.value).toList();

      var spans = await _check(config, typo);
      var got = spans.single.suggestions;

      // Comparing the *distances* rather than the words is deliberate:
      // several dictionary words are often equally close, so which of them
      // is shown is an arbitrary tie-break, but how close they are is not.
      // A candidate filter that drops a nearer word shows up here as a
      // larger distance, which is exactly the failure being guarded against.
      var gotDistances = got.map((w) => distance(typo, w)).toList();
      expect(gotDistances, wantDistances,
          reason: "$typo: offered $got at distances $gotDistances, but the "
              "nearest in the dictionary are "
              "${scored.take(3).map((e) => e.key).toList()} at "
              "$wantDistances");
    }
  });

  test("suggestions are ordered nearest first", () async {
    var spans = await _check(await _configFor(plain), "occured");
    // "occurred" is one edit away; "occur" is two.
    expect(spans.single.suggestions.first, "occurred");
  });

  test("the provider's own vocabulary is accepted", () async {
    var spans = await _check(await _configFor(plain), "decred bisonrelay");
    expect(spans, isEmpty);
  });

  group("grammar rules", () {
    // These run in Dart's regex engine, which is the only place the
    // backreference rules can be exercised at all -- Go's RE2 cannot compile
    // them, so the plugin's own tests skip them.
    Future<SpellCheckConfiguration> withRules(List<GrammarRule> rules) =>
        _configFor(SpellcheckData(_dictionary, rules));

    test("a repeated word is caught and the duplicate dropped", () async {
      var config = await withRules([
        GrammarRule(r"\b(\w+)([ \t]+)\1\b", "Repeated word", r"$1"),
      ]);
      var spans = await _check(config, "the the payment");
      expect(spans, isNotEmpty);
      expect(spans.first.suggestions, contains("the"));
    });

    test("repeated punctuation is caught", () async {
      var config = await withRules([
        GrammarRule(r"([,;:])\1+", "Repeated punctuation", r"$1"),
      ]);
      var spans = await _check(config, "wait,, then go");
      expect(spans, isNotEmpty);
      expect(spans.first.suggestions, contains(","));
    });

    test("a rule with no suggestion still flags the text", () async {
      var config = await withRules([
        GrammarRule(r"[!?]{3,}", "Excessive punctuation", ""),
      ]);
      var spans = await _check(config, "really!!!");
      expect(spans, isNotEmpty);
      expect(spans.first.suggestions, isEmpty);
    });

    // A provider is third-party code; one bad pattern must cost only itself.
    test("an uncompilable rule is skipped, not fatal", () async {
      var config = await withRules([
        GrammarRule("([unclosed", "Broken", ""),
        GrammarRule(r"[ ]{2,}", "Multiple spaces", " "),
      ]);
      var spans = await _check(config, "hello  world");
      expect(spans, isNotEmpty);
      expect(spans.first.suggestions, contains(" "));
    });
  });
}
