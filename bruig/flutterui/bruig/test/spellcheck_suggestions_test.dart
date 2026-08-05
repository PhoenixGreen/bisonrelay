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
  var plain = SpellcheckData(_dictionary, const [], []);

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
    // Every dictionary word within two edits, found by brute force. This is
    // the oracle the indexed lookup is checked against, so it has to score
    // the same way -- Damerau, counting an adjacent transposition as one
    // typo. Left as plain Levenshtein it disagrees about exactly the words
    // this is meant to protect: "recieve" is one transposition from
    // "receive" and two substitutions from it.
    int distance(String a, String b) {
      var prevPrev = List<int>.filled(b.length + 1, 0);
      var prev = List<int>.generate(b.length + 1, (i) => i);
      var curr = List<int>.filled(b.length + 1, 0);
      for (var i = 1; i <= a.length; i++) {
        curr[0] = i;
        for (var j = 1; j <= b.length; j++) {
          var cost = a[i - 1] == b[j - 1] ? 0 : 1;
          var v = [prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost]
              .reduce((x, y) => x < y ? x : y);
          if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
            var t = prevPrev[j - 2] + 1;
            if (t < v) v = t;
          }
          curr[j] = v;
        }
        var t = prevPrev;
        prevPrev = prev;
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
      var wantDistances = scored.take(5).map((e) => e.value).toList();

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
              "${scored.take(5).map((e) => e.key).toList()} at "
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

  _reviewTests();
  _spanOrderTests();
  _rankingTests();
  _fixPreferenceTests();
  _lookaroundRuleTests();

  group("grammar rules", () {
    // These run in Dart's regex engine, which is the only place the
    // backreference rules can be exercised at all -- Go's RE2 cannot compile
    // them, so the plugin's own tests skip them.
    Future<SpellCheckConfiguration> withRules(List<GrammarRule> rules) =>
        _configFor(SpellcheckData(_dictionary, const [], rules));

    test("a repeated word is caught and the duplicate dropped", () async {
      var config = await withRules([
        GrammarRule(r"\b(\w+)([ \t]+)\1\b", "Repeated word", r"$1"),
      ]);
      const text = "the the payment";
      var spans = await _check(config, text);
      var span = spans.firstWhere(
          (s) => text.substring(s.range.start, s.range.end) == "the the");
      expect(span.suggestions, contains("the"));
    });

    test("repeated punctuation is caught", () async {
      var config = await withRules([
        GrammarRule(r"([,;:])\1+", "Repeated punctuation", r"$1"),
      ]);
      const text = "wait,, then go";
      var spans = await _check(config, text);
      // Located by what it covers rather than by position: spans are ordered
      // by where they sit in the text, so the words around this one -- which
      // the test dictionary does not contain -- come first.
      var span = spans.firstWhere(
          (s) => text.substring(s.range.start, s.range.end) == ",,");
      expect(span.suggestions, contains(","));
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
      const text = "hello  world";
      var spans = await _check(config, text);
      var span = spans.firstWhere(
          (s) => text.substring(s.range.start, s.range.end) == "  ");
      expect(span.suggestions, contains(" "),
          reason: "the good rule must still fire alongside the broken one");
    });
  });
}

// The review() API backs the post editor's panel, which needs to say what
// each problem *is* -- something Flutter's own SuggestionSpan cannot carry.
void _reviewTests() {
  var rules = [
    GrammarRule(r"[ ]{2,}", "Multiple spaces", " "),
    GrammarRule(r"[!?]{3,}", "Excessive punctuation", ""),
  ];

  test("review separates spelling from style, in reading order", () async {
    var capability = SpellcheckCapability(
        fetch: () async => SpellcheckData(_dictionary, const [], rules));
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));

    var issues = capability.review("the  payment recieve");
    expect(issues, hasLength(2));

    // Ordered by position: the doubled space precedes the misspelling.
    expect(issues[0].kind, WritingIssueKind.style);
    expect(issues[0].message, "Multiple spaces");
    expect(issues[1].kind, WritingIssueKind.spelling);
    expect(issues[1].text, "recieve");
    expect(issues[1].suggestions, contains("receive"));
  });

  test("a style rule with no fix still carries its message", () async {
    var capability = SpellcheckCapability(
        fetch: () async => SpellcheckData(_dictionary, const [], rules));
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));

    var issues = capability.review("payment!!!");
    expect(issues.single.message, "Excessive punctuation");
    expect(issues.single.suggestions, isEmpty);
  });

  test("no provider means nothing to review", () async {
    var capability = SpellcheckCapability(fetch: () async => throw "unused");
    await capability.update(FakePlugins({}));
    expect(capability.review("recieve  this"), isEmpty);
  });

  // The ranges drive in-place replacement in the panel, so they have to
  // address exactly the text they claim to.
  test("an issue's range addresses its own text", () async {
    var capability = SpellcheckCapability(
        fetch: () async => SpellcheckData(_dictionary, const [], rules));
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));

    const text = "the  payment recieve";
    for (var issue in capability.review(text)) {
      expect(text.substring(issue.range.start, issue.range.end), issue.text);
    }
  });
}

// Flutter treats the spans returned by fetchSpellCheckSuggestions as sorted
// and disjoint: it binary-searches them for the word under the cursor, and
// walks them in order to build the styled text the underline draws into.
// Handing it an unordered or overlapping list makes it find the wrong span --
// so applying a correction rewrites some other word -- and corrupts the span
// tree, which showed up as text jumping around while merely editing.
//
// Rules are matched one at a time and words separately, so the natural order
// of production is by rule and then by word, and never by position. These
// pin the ordering that has to be imposed on top.
void _spanOrderTests() {
  var rules = [
    GrammarRule(r"[ ]{2,}", "Multiple spaces", " "),
    GrammarRule(r"[ \t]+([,.!?;:])", "Space before punctuation", r"$1"),
    GrammarRule(r"\b(\w+)([ \t]+)\1\b", "Repeated word", r"$1"),
  ];

  Future<List<SuggestionSpan>> spansFor(String text) async {
    var capability = SpellcheckCapability(
        fetch: () async => SpellcheckData(_dictionary, const [], rules));
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));
    var spans = await capability.configuration!.spellCheckService!
        .fetchSpellCheckSuggestions(const Locale("en", "US"), text);
    return spans ?? [];
  }

  test("spans are sorted by position", () async {
    // A style issue late in the text and a misspelling early in it: emitted
    // rules-first, that is exactly backwards.
    var spans = await spansFor("recieve the payment  now ,");
    var starts = spans.map((s) => s.range.start).toList();
    var sorted = [...starts]..sort();
    expect(starts, sorted, reason: "spans came back out of order: $starts");
  });

  test("spans never overlap", () async {
    // "teh teh" is both a repeated word and two misspellings, so the naive
    // result covers the same characters three times over.
    var spans = await spansFor("teh teh payment");
    for (var i = 1; i < spans.length; i++) {
      expect(spans[i].range.start, greaterThanOrEqualTo(spans[i - 1].range.end),
          reason: "span $i overlaps its predecessor: "
              "${spans.map((s) => '${s.range.start}-${s.range.end}').toList()}");
    }
  });

  test("a misspelling wins over a style rule covering it", () async {
    var spans = await spansFor("teh teh payment");
    // The first span should be the misspelled word alone, offering a real
    // correction -- not the repeated-word rule, whose fix would just
    // duplicate the typo.
    expect(spans.first.range.end, 3);
    expect(spans.first.suggestions, contains("the"));
  });

  // The symptom as reported: correcting one issue rewrote different text.
  // With ordered, disjoint spans every range addresses exactly its own word.
  test("every span addresses the text it describes", () async {
    const text = "recieve the payment  now , teh teh";
    var spans = await spansFor(text);
    expect(spans, isNotEmpty);
    for (var span in spans) {
      expect(span.range.start, lessThan(span.range.end));
      expect(span.range.end, lessThanOrEqualTo(text.length));
    }
    // And the first one really is the misspelling at offset 0.
    expect(text.substring(spans.first.range.start, spans.first.range.end),
        "recieve");
  });
}

// These are the cases that were reported as broken, kept as cases rather
// than as an abstract property because each failed for its own reason.
void _rankingTests() {
  // A dictionary with the real competitors in it: every word here is within
  // two edits of one of the typos below, so ranking is the only thing that
  // can put the right one first.
  const words = [
    "the",
    "there",
    "they",
    "them",
    "then",
    "thy",
    "tech",
    "meh",
    "teach",
    "received",
    "receive",
    "relieved",
    "relieve",
    "believed",
    "reviewed",
    "deceived",
    "receiver",
    "weird",
    "wield",
  ];
  // Ordered as the provider ranks them: commonest first.
  const common = [
    "the",
    "there",
    "they",
    "them",
    "then",
    "received",
    "receive",
    "believed",
    "weird"
  ];

  Future<List<String>> suggestionsFor(String typo) async {
    var capability = SpellcheckCapability(
        fetch: () async => SpellcheckData(words, common, const []));
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));
    var spans = await capability.configuration!.spellCheckService!
        .fetchSpellCheckSuggestions(const Locale("en", "US"), typo);
    return spans!.single.suggestions;
  }

  // Reported: "recieved" did not offer "received". It was found, at distance
  // 2 under plain Levenshtein, and buried under the crowd of other words
  // two edits away. As a transposition it is one edit, and it is the more
  // common word, so it now leads.
  test("a transposed word is corrected first", () async {
    expect((await suggestionsFor("recieved")).first, "received");
    expect((await suggestionsFor("recieve")).first, "receive");
  });

  // Reported: "teh" did not offer "the". Six words sit one edit away, and
  // with distance alone deciding, which surfaced was arbitrary.
  test("the commonest of the equally near words wins", () async {
    expect((await suggestionsFor("teh")).first, "the");
  });

  test("a wrong letter is still corrected", () async {
    expect((await suggestionsFor("wierd")).first, "weird");
  });

  // Without a ranked list -- an older provider, or one for another language
  // -- ranking degrades to distance alone rather than breaking.
  test("an unranked provider still returns the nearest words", () async {
    var capability = SpellcheckCapability(
        fetch: () async => SpellcheckData(words, const [], const []));
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));
    var spans = await capability.configuration!.spellCheckService!
        .fetchSpellCheckSuggestions(const Locale("en", "US"), "recieved");
    expect(spans!.single.suggestions, contains("received"));
  });
}

// Four reported failures, all about which fix reaches the user rather than
// whether one was found. Kept as named cases because each had its own cause.
void _fixPreferenceTests() {
  // "alot" and "i" are not dictionary words, so each produces a spelling
  // issue covering exactly the same characters as the style rule for it.
  const words = ["a", "lot", "allot", "aloft", "the", "payment"];
  var rules = [
    GrammarRule(r"\balot\b", '"a lot" is two words', "a lot"),
    GrammarRule(r"\bi\b", '"I" is capitalised', "I"),
    GrammarRule(r"([!?])\1{2,}", "Excessive punctuation", r"$1"),
    GrammarRule(r"(^|[.!?]\s+)([a-z])", "Sentence should start with a capital",
        r"$1$U2"),
    GrammarRule(r"\b(\w+)([ \t]+)\1\b", "Repeated word", r"$1"),
  ];

  Future<List<WritingIssue>> reviewOf(String text) async {
    var capability = SpellcheckCapability(
        fetch: () async => SpellcheckData(words, const [], rules));
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));
    return capability.review(text);
  }

  // Reported: the "a lot" fix disappeared. A spelling issue covered the same
  // span and was being preferred, so the offer became "allot"/"aloft" --
  // the nearest dictionary words, and not what anyone meant.
  test("a style rule beats a spelling issue on the same span", () async {
    var issues = await reviewOf("thanks alot");
    var issue = issues.firstWhere((i) => i.text == "alot");
    expect(issue.kind, WritingIssueKind.style);
    expect(issue.suggestions, contains("a lot"));
  });

  test('"i" is offered "I"', () async {
    var issues = await reviewOf("payment i sent");
    var issue = issues.firstWhere((i) => i.text == "i");
    expect(issue.suggestions, contains("I"));
  });

  // The other half of the preference, which must not regress: a wide style
  // span still loses to the narrower spelling issues inside it, since the
  // repeated-word fix would only duplicate the typo.
  test("a wide style rule loses to the misspellings inside it", () async {
    var issues = await reviewOf("teh teh");
    expect(issues.map((i) => i.text), everyElement(isNot("teh teh")));
    expect(issues.where((i) => i.text == "teh"), hasLength(2));
  });

  // Reported: no way to correct "!!!". The rule flagged it and offered
  // nothing, on the grounds that there was no single right fix -- but there
  // is: whichever mark was actually used.
  test("excessive punctuation can be corrected", () async {
    var issues = await reviewOf("really!!!");
    var issue = issues.firstWhere((i) => i.message == "Excessive punctuation");
    expect(issue.suggestions, contains("!"));
    expect(
        (await reviewOf("really???"))
            .firstWhere((i) => i.message == "Excessive punctuation")
            .suggestions,
        contains("?"));
  });

  // Reported: no capitalisation check. The fix needs the letter that was
  // typed upper-cased, which a literal template cannot express -- hence $U.
  test("a sentence start is offered its capital", () async {
    var issues = await reviewOf("the payment. it cleared");
    var issue = issues.firstWhere((i) =>
        i.message == "Sentence should start with a capital" &&
        i.text.contains("i"));
    expect(issue.suggestions.single, ". I");
  });

  test(r"$U leaves the rest of a group alone", () async {
    var issues = await reviewOf("payment. the rest");
    var issue = issues.firstWhere((i) =>
        i.message == "Sentence should start with a capital" &&
        // The rule fires at the very start too, so take the one
        // after the full stop.
        i.range.start > 0);
    // Only the captured letter is raised, not the whole match.
    expect(issue.suggestions.single, ". T");
  });
}

// Six of the plugin's rules use backreferences or lookarounds, which Go's
// RE2 cannot compile -- so the plugin's own tests skip them and this is the
// only place they are ever executed. The patterns below mirror the plugin's
// verbatim; they are duplicated rather than imported because the plugin is a
// separate Go module with no Dart to import.
void _lookaroundRuleTests() {
  const tlds = "com|org|net|edu|gov|mil|int|io|dev|app|xyz|info|biz|tv|"
      "ai|gg|rs|sh|ly|cc|onion|uk|de|fr|ru|au|ca|us|jp|cn|nz|za|eu|ch|nl|se|"
      "tech|site|online|store|blog|news|wiki|link|page|pro|me|co|gl|fm";
  var missingSpace = GrammarRule(
      "(?<=\\w\\w|[)\\]\"'])([.!?])"
          "(?!(?:$tlds)\\b|[\\w-]*\\.(?:$tlds)\\b)([A-Za-z])",
      "Missing space after punctuation",
      r"$1 $U2");
  var pronounI = GrammarRule(r"(?<!\.)\bi\b(?!\.)", '"I" is capitalised', "I");

  // Only the rule's own findings: the corpus below is full of words no test
  // dictionary contains, and their spelling issues say nothing about whether
  // the rule under test fired.
  Future<List<WritingIssue>> reviewWith(List<GrammarRule> rules, String text,
      {List<String> words = const ["the"]}) async {
    var capability = SpellcheckCapability(
        fetch: () async => SpellcheckData(words, const [], rules));
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));
    return capability
        .review(text)
        .where((i) => i.kind == WritingIssueKind.style)
        .toList();
  }

  // Reported: a run-together sentence whose next word was also lower case
  // was flagged by nothing. It fell between two rules, each assuming the
  // other's condition -- one wanted a capital after the stop, the other a
  // space before the letter.
  test("a run-together sentence is flagged and fixed in one go", () async {
    var issues = await reviewWith([missingSpace], "(if you are free).what's");
    var issue = issues
        .firstWhere((i) => i.message == "Missing space after punctuation");
    expect(issue.suggestions.single, ". W",
        reason: "the fix should insert the space and capitalise together");
  });

  test("it fires whatever the case of the next letter", () async {
    for (var text in ["Stop.Now", "done.next thing", "Dr.Smith"]) {
      expect(await reviewWith([missingSpace], text), isNotEmpty,
          reason: 'nothing flagged in "$text"');
    }
  });

  // The guards. A dot inside a web address or an initialism is not a
  // sentence boundary, and flagging one is worse than missing a real error.
  test("it leaves addresses and initialisms alone", () async {
    for (var text in [
      "Have a look at example.com when you get a chance.",
      "see docs.rs for details",
      "check news.ycombinator.com",
      "at my.shop.co.uk today",
      "e.g. this one",
      "i.e. that one",
      "U.S.A. today",
      "It cost 3.5 DCR.",
      "Fine. Next question, then.",
    ]) {
      expect(await reviewWith([missingSpace], text), isEmpty,
          reason: 'wrongly flagged "$text"');
    }
  });

  // Reported from a two-paragraph post: the first word of the second
  // paragraph was not flagged. The lookbehind sees exactly the characters
  // immediately before the letter, which between paragraphs is the second of
  // two newlines -- not a full stop and a space.
  test("a paragraph start is treated as a sentence start", () async {
    var capital = GrammarRule(r"(?<=^|[.!?]\s|\n)([a-z])",
        "Sentence should start with a capital", r"$U1");
    const text = "the deadline entirely.\n\nthat's the plan";
    var issues = await reviewWith([capital], text,
        words: const ["the", "deadline", "entirely", "that's", "plan"]);
    expect(issues.where((i) => i.range.start > 0), isNotEmpty,
        reason: "the second paragraph's first letter was not flagged");
    expect(issues.last.suggestions.single, "T");
  });

  test('the "I" rule skips initialisms', () async {
    // A dictionary carrying the words used, so a spelling issue does not
    // legitimately outrank the rule under test -- as it would for "i'm"
    // against a dictionary that has never heard of it.
    const words = ["i", "i'm", "think", "so", "going", "this", "one", "that"];
    expect(
        await reviewWith([pronounI], "e.g. this one, i.e. that one",
            words: words),
        isEmpty,
        reason: 'the "i" of "i.e." is not the pronoun');
    expect(
        await reviewWith([pronounI], "i think so", words: words), isNotEmpty);
    expect(await reviewWith([pronounI], "i'm going", words: words), isNotEmpty);
  });
}
