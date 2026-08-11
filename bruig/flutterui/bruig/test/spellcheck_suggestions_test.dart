import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/writing_tools/writing_tools.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

Future<SpellcheckCapability> _configFor(SpellcheckData data) async {
  var capability = SpellcheckCapability(fetch: (_) async => data);
  await capability.update(FakePlugins({PluginCapability.spellcheckData}));
  return capability;
}

/// _check is what the field paints from, expressed as the spans these tests
/// were written against. review() is now the single source: the old
/// SpellCheckService wrapper around it is gone.
Future<List<SuggestionSpan>> _check(
    SpellcheckCapability config, String text) async {
  return [
    for (var issue in config.review(text))
      SuggestionSpan(issue.range, issue.suggestions),
  ];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
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
  _confusionRuleTests();
  _newLookaheadRuleTests();
  _apostropheTests();
  _compoundAndPunctuationTests();
  _antipatternTests();
  _digitAdjacentTests();
  _messageTemplateTests();

  group("grammar rules", () {
    // These run in Dart's regex engine, which is the only place the
    // backreference rules can be exercised at all -- Go's RE2 cannot compile
    // them, so the plugin's own tests skip them.
    Future<SpellcheckCapability> withRules(List<GrammarRule> rules) =>
        _configFor(SpellcheckData(_dictionary, const [], rules));

    // Reported: "Youre are the one." was corrected to "you're are the one."
    // The wordlist is lowercased when it is built, so every dictionary
    // suggestion arrives lowercase -- and the rule corrections had been
    // taught to carry the case across while the spelling ones had not.
    test("a capitalised misspelling gets a capitalised correction", () async {
      var config = await _configFor(SpellcheckData(
          const ["you're", "your", "youth"], const [], const []));
      const text = "Youre the one";
      var spans = await _check(config, text);
      var span = spans.firstWhere(
          (s) => text.substring(s.range.start, s.range.end) == "Youre");
      expect(span.suggestions, isNotEmpty);
      for (var suggestion in span.suggestions) {
        expect(suggestion[0], suggestion[0].toUpperCase(),
            reason: "correcting a word that opens a sentence must not "
                "quietly remove its capital");
      }
      expect(span.suggestions, contains("You're"));
    });

    test("a lowercase misspelling is corrected in lowercase", () async {
      var config = await _configFor(SpellcheckData(
          const ["you're", "your", "youth"], const [], const []));
      const text = "i think youre right";
      var spans = await _check(config, text);
      var span = spans.firstWhere(
          (s) => text.substring(s.range.start, s.range.end) == "youre");
      expect(span.suggestions, contains("you're"));
    });

    // The literal-word rules -- "dont", "alot", "your welcome" -- accept
    // either case in their first letter, because the start of a sentence is
    // exactly where these are typed. That made the fix wrong in a new way:
    // "Dont" was corrected to "don't", mid-capital-letter.
    group("a correction keeps the capital it replaced", () {
      test("a capitalised mistake gets a capitalised fix", () async {
        var config = await withRules([
          GrammarRule(r"\b[Dd]ont\b", "Should be \"don't\"", "don't"),
        ]);
        const text = "Dont worry";
        var spans = await _check(config, text);
        var span = spans.firstWhere(
            (s) => text.substring(s.range.start, s.range.end) == "Dont");
        expect(span.suggestions, ["Don't"]);
      });

      test("a lowercase mistake is left lowercase", () async {
        var config = await withRules([
          GrammarRule(r"\b[Dd]ont\b", "Should be \"don't\"", "don't"),
        ]);
        const text = "we dont know";
        var spans = await _check(config, text);
        var span = spans.firstWhere(
            (s) => text.substring(s.range.start, s.range.end) == "dont");
        expect(span.suggestions, ["don't"]);
      });

      // The rules that exist to *add* a capital match lowercase text and
      // suggest the capitalised form. Carrying case across must not undo
      // them, which is why it only ever adds a capital.
      test("a capitalisation fix is not undone", () async {
        var config = await withRules([
          GrammarRule(r"\b(monday|tuesday)\b", "Should be \"\$U1\"", r"$U1"),
        ]);
        const text = "see you on monday";
        var spans = await _check(config, text);
        var span = spans.firstWhere(
            (s) => text.substring(s.range.start, s.range.end) == "monday");
        expect(span.suggestions, ["Monday"]);
      });
    });

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
        fetch: (_) async => SpellcheckData(_dictionary, const [], rules));
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));

    var issues = capability.review("the  payment recieve");
    expect(issues, hasLength(2));

    // Ordered by position: the doubled space precedes the misspelling.
    expect(issues[0].kind, WritingIssueKind.grammar);
    expect(issues[0].message, "Multiple spaces");
    expect(issues[1].kind, WritingIssueKind.spelling);
    expect(issues[1].text, "recieve");
    expect(issues[1].suggestions, contains("receive"));
  });

  test("a style rule with no fix still carries its message", () async {
    var capability = SpellcheckCapability(
        fetch: (_) async => SpellcheckData(_dictionary, const [], rules));
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));

    var issues = capability.review("payment!!!");
    expect(issues.single.message, "Excessive punctuation");
    expect(issues.single.suggestions, isEmpty);
  });

  test("no provider means nothing to review", () async {
    var capability = SpellcheckCapability(fetch: (_) async => throw "unused");
    await capability.update(FakePlugins({}));
    expect(capability.review("recieve  this"), isEmpty);
  });

  // The ranges drive in-place replacement in the panel, so they have to
  // address exactly the text they claim to.
  test("an issue's range addresses its own text", () async {
    var capability = SpellcheckCapability(
        fetch: (_) async => SpellcheckData(_dictionary, const [], rules));
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
        fetch: (_) async => SpellcheckData(_dictionary, const [], rules));
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));
    return [
      for (var issue in capability.review(text))
        SuggestionSpan(issue.range, issue.suggestions),
    ];
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
        fetch: (_) async => SpellcheckData(words, common, const []));
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));
    return capability.review(typo).single.suggestions;
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
        fetch: (_) async => SpellcheckData(words, const [], const []));
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));
    expect(
        capability.review("recieved").single.suggestions, contains("received"));
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
        fetch: (_) async => SpellcheckData(words, const [], rules));
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));
    return capability.review(text);
  }

  // Reported: the "a lot" fix disappeared. A spelling issue covered the same
  // span and was being preferred, so the offer became "allot"/"aloft" --
  // the nearest dictionary words, and not what anyone meant.
  test("a style rule beats a spelling issue on the same span", () async {
    var issues = await reviewOf("thanks alot");
    var issue = issues.firstWhere((i) => i.text == "alot");
    expect(issue.kind, WritingIssueKind.grammar);
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
        fetch: (_) async => SpellcheckData(words, const [], rules));
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));
    return capability
        .review(text)
        .where((i) => i.kind == WritingIssueKind.grammar)
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

// The plugin's its/it's and capitalisation rules use lookarounds, so RE2
// cannot compile them and only the app ever runs them.
void _confusionRuleTests() {
  var capital = GrammarRule(r"(?<=^|[.!?]\s|\n)([a-z])([a-z0-9']*)",
      "Sentence should start with a capital", r"$U1$2");
  var itsVerb = GrammarRule(
      r"\b([Ii])ts\s+(a|an|the|not|been|my|your|our|his|her|their|"
          r"raining|snowing|too|going\s+to)\b",
      r"""Should be "$1t's $2""",
      r"$1t's $2");
  var itsOwn = GrammarRule(
      r"\b([Ii])t's\s+(own|owner)\b", r"""Should be "$1ts $2""", r"$1ts $2");

  // The dictionary has to carry the words these sentences use. Without
  // them each word is also a spelling issue, and a spelling issue correctly
  // outranks a style rule covering the same text -- so the rule under test
  // would be filtered out for a reason that is not a bug.
  const words = [
    "its",
    "it's",
    "going",
    "to",
    "rain",
    "a",
    "shame",
    "the",
    "channel",
    "lost",
    "funding",
    "balance",
    "is",
    "low",
    "owner",
    "has",
    "more",
    "meaning",
    "clear",
    "own",
    "fault",
    "that's",
    "plan",
  ];

  Future<List<WritingIssue>> styleOf(
      List<GrammarRule> rules, String text) async {
    var capability = SpellcheckCapability(
        fetch: (_) async => SpellcheckData(words, const [], rules));
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));
    return capability
        .review(text)
        .where((i) => i.kind == WritingIssueKind.grammar)
        .toList();
  }

  // Reported: the fix for "that's" was offered as "That", which reads as a
  // proposal to drop the "'s" rather than to capitalise the word.
  test("a capital fix keeps the rest of the word", () async {
    var issues = await styleOf([capital], "that's the plan");
    expect(issues.first.text, "that's");
    expect(issues.first.suggestions.single, "That's");
  });

  // Reported: "Its raining outside" was not flagged. The rule was written
  // with a literal "its" and Dart's regexes are case-sensitive, so the one
  // position it goes wrong most -- the start of a sentence -- was the one
  // position it could never match.
  test("its is corrected whatever its case", () async {
    expect((await styleOf([itsVerb], "Its raining outside")).single.suggestions,
        contains("It's raining"),
        reason: "a capitalised Its must be caught, and stay capitalised");
    expect((await styleOf([itsVerb], "its going to rain")).single.suggestions,
        contains("it's going to"));
  });

  test("its is left alone wherever a possessive can stand", () async {
    // Adjectives and verb-nouns are the trap. Every one of these reads
    // correctly, and a list that included adjectives flagged them all.
    for (var ok in [
      "the channel lost its funding",
      "its true value is hard to judge",
      "its cold storage keeps the keys offline",
      "its best feature is the relay",
      "its going rate is higher",
      "its freezing point",
      "its only purpose",
      "its owner has more",
    ]) {
      expect(await styleOf([itsVerb], ok), isEmpty, reason: 'flagged "$ok"');
    }
  });

  test("it's is corrected before a noun it cannot own", () async {
    expect((await styleOf([itsOwn], "it's own fault")).single.suggestions,
        contains("its own"));
    expect((await styleOf([itsOwn], "It's own fault")).single.suggestions,
        contains("Its own"));
    expect(await styleOf([itsOwn], "it's going to rain"), isEmpty);
  });
}

// Reported: "I've" was flagged as a misspelling, and no contraction rule ever
// fired on real typing. macOS substitutes U+2019 for a typed apostrophe
// unless smart quotes are off, and the word regex splits "I’ve" into "I"
// and "ve" -- so the dictionary never saw the word, and a provider's
// `\bdon't\b` never saw its own text.
void _apostropheTests() {
  const words = [
    "i've",
    "don't",
    "the",
    "payment",
    "cleared",
    "i",
    "it's",
    "here",
    "fault",
    "own"
  ];

  Future<SpellcheckCapability> checker({List<GrammarRule> rules = const []}) =>
      _configFor(SpellcheckData(words, const [], rules));

  group("typographic apostrophes", () {
    test("a contraction is not flagged", () async {
      var capability = await checker();
      expect(capability.review("I’ve cleared the payment"), isEmpty,
          reason: "the curly apostrophe split the word in two");
      // The modifier letter and the left quote get used the same way.
      expect(capability.review("Iʼve cleared the payment"), isEmpty);
      expect(capability.review("don‘t"), isEmpty);
    });

    test("a provider's contraction rule still fires", () async {
      var capability = await checker(rules: [
        GrammarRule(r"\bit's\s+own\b", "Should be \"its own\"", "its own"),
      ]);
      var issues = capability.review("it’s own fault");
      expect(issues, isNotEmpty,
          reason: "every rule with an apostrophe in it was dead");
      expect(issues.first.suggestions, ["its own"]);
    });

    // The offsets are into the text the field actually holds, and the flagged
    // text is what is there -- not the folded form. A correction is checked
    // against it before being spliced in, so a folded copy would silently
    // stop every correction from applying.
    test("the flagged text comes from the original", () async {
      var capability = await checker();
      const text = "the paymnt’s here";
      var issue = capability.review(text).single;
      expect(text.substring(issue.range.start, issue.range.end), issue.text);
      expect(issue.text, contains("’"));
    });

    test("folding cannot move an offset", () {
      const text = "I’ve donʼt it‘s";
      expect(normalizeForMatching(text).length, text.length);
      expect(normalizeForMatching(text), "I've don't it's");
    });
  });

  // A word added to the dictionary with one apostrophe has to stay added when
  // the checker looks it up with the other.
  test("an added contraction stays added whichever apostrophe was typed",
      () async {
    var prefs = WritingPreferences();
    await prefs.addToDictionary("O’Brien");
    expect(prefs.isIgnoredWord("o'brien"), isTrue);
    expect(prefs.isIgnoredWord("O’Brien"), isTrue);
  });
}

// The two rules Go's RE2 cannot compile, so the plugin's own corpus never
// sees them run. Both use lookahead.
void _newLookaheadRuleTests() {
  // A dictionary carrying every word used below: an unknown word is also a
  // spelling issue, and a spelling issue correctly outranks a style rule
  // covering the same span, so the rule under test would vanish for a reason
  // that is not a bug.
  const words = [
    "send",
    "it",
    "to",
    "me",
    "him",
    "her",
    "us",
    "them",
    "too",
    "review",
    "the",
    "bank",
    "operates",
    "in",
    "on",
    "principal",
    "principle",
    "cities",
    "only",
    "i",
    "agree",
    "with",
    "this",
    "amounts",
    "interest",
    "charged",
    "over",
    "is",
  ];

  Future<List<WritingIssue>> review(
      String text, List<GrammarRule> rules) async {
    var capability = SpellcheckCapability(
        fetch: (_) async => SpellcheckData(words, const [], rules));
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));
    return capability.review(text);
  }

  group("\"me to\" at the end of a sentence", () {
    var rule = GrammarRule(r"\b(me|him|her|us|them)\s+to(?=[.!?]|$)",
        r'Should be "$1 too"', r"$1 too");

    test("is caught before a full stop", () async {
      var issues = await review("send it to me to.", [rule]);
      expect(issues.expand((i) => i.suggestions), contains("me too"));
    });

    test("is caught at the very end of the text", () async {
      expect(await review("send it to me to", [rule]), isNotEmpty);
    });

    // The lookahead is the whole rule: "to" followed by a word is the
    // preposition and always correct.
    test("leaves a real preposition alone", () async {
      expect(await review("send it to me to review", [rule]), isEmpty);
    });
  });

  group("\"in principal\" at the end of a clause", () {
    var rule = GrammarRule(r"\b(in|on)\s+principal(?=[.,;:!?]|$)",
        r'Should be "$1 principle"', r"$1 principle");

    test("is caught before punctuation", () async {
      var issues = await review("i agree in principal.", [rule]);
      expect(issues.expand((i) => i.suggestions), contains("in principle"));
    });

    // "Principal" is also an adjective, which is why the rule cannot simply
    // match the two words wherever they appear.
    test("leaves the adjective alone", () async {
      expect(await review("the bank operates in principal cities only", [rule]),
          isEmpty);
      expect(await review("interest is charged on principal amounts", [rule]),
          isEmpty);
    });
  });
}

// The compound and punctuation rules that need lookaround, which Go's RE2
// cannot compile -- so the plugin's own corpus never sees them run and this
// is the only place they are exercised at all.
//
// Each pair below is the mistake and the reading that keeps the two words
// apart. The second is what the lookahead is for, and without it every one
// of these rules would be flagging correct writing.
void _compoundAndPunctuationTests() {
  /// review returns only what the rules under test found.
  ///
  /// Spelling is filtered out rather than suppressed with a bigger word
  /// list. A test dictionary can never carry every word a sentence uses, and
  /// an unknown word does not merely add noise: review() drops a style issue
  /// that overlaps a spelling one, so the rule being tested disappears for a
  /// reason that has nothing to do with the rule.
  ///
  /// issuesAt over the whole text for the same reason -- it reports
  /// everything that overlaps rather than choosing one per span.
  Future<List<WritingIssue>> review(
      String text, List<GrammarRule> rules) async {
    var capability = SpellcheckCapability(
        fetch: (_) async => SpellcheckData(const [], const [], rules));
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));
    return capability
        .issuesAt(text, 0, text.length)
        .where((issue) => issue.kind != WritingIssueKind.spelling)
        .toList();
  }

  group("words written as two", () {
    var selfRule = GrammarRule(
        r"\b([Mm])y\s+self\b(?!-)", r'Should be "$1yself"', r"$1yself");

    test("is caught", () async {
      var issues = await review("i did it my self", [selfRule]);
      expect(issues.expand((i) => i.suggestions), contains("myself"));
    });

    // The lookahead is the whole rule: "self" starting a hyphenated word is
    // not a split compound.
    test("leaves a hyphenated word alone", () async {
      expect(await review("my self-esteem took a knock", [selfRule]), isEmpty);
    });

    // An adjective between the two is a different construction, and the
    // pattern never sees it because the words are no longer adjacent.
    test("leaves an adjective between them alone", () async {
      expect(await review("i like my true self better", [selfRule]), isEmpty);
    });

    var withoutRule = GrammarRule(r"\b([Ww])ith\s+out\b(?!\s+of\b)",
        r'Should be "$1ithout"', r"$1ithout");

    test("with out is caught, with out of is not", () async {
      expect(await review("we did it with out", [withoutRule]), isNotEmpty);
      expect(await review("it came with out of date firmware", [withoutRule]),
          isEmpty);
    });

    var becauseRule = GrammarRule(r"\b([Bb])e\s+cause\b(?!\s+(for|of)\b)",
        r'Should be "$1ecause"', r"$1ecause");

    test("be cause is caught, be cause for is not", () async {
      expect(
          await review("i did it be cause we can", [becauseRule]), isNotEmpty);
      expect(await review("that would be cause for concern", [becauseRule]),
          isEmpty);
    });
  });

  group("punctuation", () {
    var doubledStop =
        GrammarRule(r"(?<![.\d])\.\.(?!\.)", "Doubled full stop", ".");

    test("two full stops are caught", () async {
      expect(await review("that is all.. we go", [doubledStop]), isNotEmpty);
    });

    // Three is an ellipsis and belongs to the writer.
    test("an ellipsis is left alone", () async {
      expect(
          await review("wait for it... there it is", [doubledStop]), isEmpty);
    });

    test("a version number is left alone", () async {
      expect(
          await review("the file is at v1.2.3 here", [doubledStop]), isEmpty);
    });

    var adverbComma = GrammarRule(
        r"(?<=^|[.!?]\s|\n)(Therefore|Meanwhile|Finally)\s+(?=[A-Za-z])",
        r'Missing comma after "$1"',
        r"$1, ");

    test("a conjunctive adverb opening a sentence wants a comma", () async {
      var issues = await review("Therefore we go", [adverbComma]);
      expect(issues.expand((i) => i.suggestions), contains("Therefore, "));
    });

    // Only at the start of a sentence: mid-sentence it is doing a different
    // job and takes no comma.
    test("mid-sentence it is left alone", () async {
      expect(await review("we can therefore go", [adverbComma]), isEmpty);
    });

    var yesNoComma = GrammarRule(
        r"(?<=^|[.!?]\s|\n)(Yes|No)\s+([Ii]|[Ww]e|[Yy]ou|[Hh]e|[Ss]he|[Ii]t|[Tt]hey)\b",
        r'Missing comma after "$1"',
        r"$1, $2");

    test("an answering yes or no wants a comma", () async {
      expect(await review("No i do not", [yesNoComma]), isNotEmpty);
    });

    // The reason the rule names what may follow: cutting "No one" in half
    // would be worse than the comma it was trying to add.
    test("\"No one\" is not an answering no", () async {
      expect(
          await review("No one knows the answer yet", [yesNoComma]), isEmpty);
      expect(await review("No longer a problem", [yesNoComma]), isEmpty);
    });
  });
}

// Antipatterns: a provider says where a rule is *not* to fire, instead of
// gluing a negative lookahead onto the end of the pattern.
void _antipatternTests() {
  Future<List<WritingIssue>> review(
      String text, List<GrammarRule> rules) async {
    var capability = SpellcheckCapability(
        fetch: (_) async => SpellcheckData(const [], const [], rules));
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));
    return capability
        .issuesAt(text, 0, text.length)
        .where((issue) => issue.kind != WritingIssueKind.spelling)
        .toList();
  }

  var guarded = GrammarRule(r"\b([Mm])y\s+self\b", r'Should be "$1yself"',
      r"$1yself", "Grammar", "why", "", [r"[Mm]y\s+self-"]);

  test("the rule still fires where the exception does not apply", () async {
    expect(await review("i did it my self", [guarded]), isNotEmpty);
  });

  test("an exception takes the match away", () async {
    expect(await review("my self-esteem took a knock", [guarded]), isEmpty);
  });

  // Contained, not merely overlapping. An exception describes a longer
  // reading the match is part of, so a pattern that happens to clip the edge
  // of one is not that reading and is still a mistake.
  test("an exception has to cover the match, not touch it", () async {
    var rule = GrammarRule(
        r"\bfoo\b", "Foo", "bar", "Grammar", "why", "", [r"baz\s+foo"]);
    expect(await review("baz foo", [rule]), isEmpty);
    expect(await review("qux foo", [rule]), isNotEmpty);
  });

  // Losing an exception makes a rule noisier, which somebody notices and
  // reports. Losing the rule makes it silent, which nobody notices at all.
  test("an exception that will not compile does not disable the rule",
      () async {
    var rule = GrammarRule(
        r"\bfoo\b", "Foo", "bar", "Grammar", "why", "", [r"(unclosed"]);
    expect(await review("a foo here", [rule]), isNotEmpty);
  });

  test("several exceptions all apply", () async {
    var rule = GrammarRule(
        r"\b([Ww])ith\s+out\b",
        r'Should be "$1ithout"',
        r"$1ithout",
        "Grammar",
        "why",
        "",
        [r"[Ww]ith\s+out\s+of\b", r"[Ww]ith\s+out-"]);
    expect(await review("we did it with out", [rule]), isNotEmpty);
    expect(await review("with out of date info", [rule]), isEmpty);
    expect(await review("with out-of-date info", [rule]), isEmpty);
  });
}

// Reported: "12th" was flagged. The word pattern pulls letter runs out of
// the text, so "12th" hands the dictionary "th" -- which is deliberately not
// in it, because that is what lets a bare "th" be offered "the".
void _digitAdjacentTests() {
  Future<List<WritingIssue>> review(String text) async {
    var capability = SpellcheckCapability(
        fetch: (_) async => SpellcheckData(
            const ["the", "on", "at", "meet"], const [], const []));
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));
    return capability.review(text);
  }

  test("an ordinal suffix is not a word", () async {
    for (var text in [
      "the 12th",
      "the 1st",
      "the 2nd",
      "the 3rd",
      "the 21st"
    ]) {
      expect(await review(text), isEmpty, reason: text);
    }
  });

  test("letters welded to a number are left alone", () async {
    for (var text in ["v1.2.3", "MP3", "3D", "COVID19", "H2O"]) {
      expect(await review(text), isEmpty, reason: text);
    }
  });

  // The exclusion is about being adjacent to a digit, not about being short.
  // A bare "th" is still a typo, and still gets "the".
  test("a bare short word is still flagged", () async {
    var issues = await review("th");
    expect(issues, hasLength(1));
    expect(issues.single.suggestions, contains("the"));
  });
}

// Reported: a rule's message showed as `Should be "$1 effect"` -- the
// template, with nothing filled in. Only the replacement was ever expanded,
// so 61 of the plugin's rules were showing their own source to the reader.
void _messageTemplateTests() {
  Future<WritingIssue> only(String text, GrammarRule rule) async {
    var capability = SpellcheckCapability(
        fetch: (_) async => SpellcheckData(const [], const [], [rule]));
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));
    return capability
        .issuesAt(text, 0, text.length)
        .firstWhere((i) => i.kind != WritingIssueKind.spelling);
  }

  test("the matched text is put into the message", () async {
    var rule = GrammarRule(
        r"\b(a|an|the)\s+affect\b", r'Should be "$1 effect"', r"$1 effect");
    var issue = await only("it had the affect of", rule);
    expect(issue.message, 'Should be "the effect"');
    expect(issue.suggestions.single, "the effect");
  });

  test("and into the explanation", () async {
    var rule = GrammarRule(r"\b(\w+)\s+affect\b", "Wrong word", r"$1 effect",
        "Confused words", r'"$1 affect" is not a phrase.');
    var issue = await only("it had the affect of", rule);
    expect(issue.explanation, '"the affect" is not a phrase.');
  });

  // Turning a rule off names it in Settings, and the rule is the whole
  // pattern rather than the phrase that happened to trip it.
  test("the rule keeps its own wording for being switched off", () async {
    var rule = GrammarRule(
        r"\b(a|an|the)\s+affect\b", r'Should be "$1 effect"', r"$1 effect");
    var issue = await only("it had the affect of", rule);
    expect(issue.ruleMessage, r'Should be "$1 effect"',
        reason: "a disabled-checks list saying \"the effect\" would describe "
            "a rule narrower than the one switched off");
  });

  // A misspelling has no rule behind it, so the two are the same thing.
  test("an issue with no rule reports the same either way", () async {
    var capability = SpellcheckCapability(
        fetch: (_) async => SpellcheckData(const ["the"], const [], const []));
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));
    var issue = capability.review("paymnt").single;
    expect(issue.ruleMessage, issue.message);
  });
}
