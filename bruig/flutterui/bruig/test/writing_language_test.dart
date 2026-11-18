import 'dart:convert';
import 'dart:io';

import 'package:bruig/plugin_system/writing_tools/engine/checker.dart';
import 'package:bruig/plugin_system/writing_tools/engine/language/lexicon.dart';
import 'package:bruig/plugin_system/writing_tools/engine/language/token_rules.dart';
import 'package:bruig/plugin_system/writing_tools/engine/language/tokens.dart';
import 'package:bruig/plugin_system/writing_tools/engine/suggester.dart';
import 'package:flutter_test/flutter_test.dart' hide Tags;
import 'package:golib_plugin/definitions.dart';

// writing_language_test.dart covers the part of the checker that reads a
// sentence as words: the lexicon, the tokenizer, and the patterns over them.
//
// With a lexicon written out here, so it runs without the plugin's data and
// says what each piece does on its own. Whether the shipped rules work on the
// shipped data is writing_rule_examples_test.dart's question.

/// Enough of a lexicon to say something about a few sentences, in the
/// provider's format and sorted as the provider sorts it.
const _lexiconLines = [
  "'re\tVBP:100:be",
  "'s\tPOS:55 VBZ:45:be",
  "a\tDT:100",
  "apple\tNN:100\tNNS=apples",
  "apples\tNNS:100:apple",
  "be\tVB:100\tVBP=are VBZ=is VBD=was VBN=been VBG=being",
  "child\tNN:100\tNNS=children",
  "children\tNNS:100:child",
  "didn't\tVBD:100:do",
  "dog\tNN:99 VB:1\tNNS=dogs",
  "go\tVB:98 NN:2\tVBZ=goes VBD=went VBN=gone VBG=going",
  "goes\tVBZ:100:go",
  "gone\tVBN:100:go",
  "he\tPRP:100",
  "home\tNN:60 RB:40",
  "hour\tNN:100",
  "i\tPRP:100",
  "is\tVBZ:100:be",
  "london\tNNP:100",
  "run\tVB:60 NN:25 VBN:15\tVBZ=runs VBD=ran VBG=running",
  "she\tPRP:100",
  "the\tDT:100",
  "they\tPRP:100",
  "to\tTO:62 IN:38",
  "user\tNN:100",
  "went\tVBD:100:go",
  "works\tNNS:55:work VBZ:45:work",
];

final _lexicon =
    Lexicon("# a comment the reader skips\n${_lexiconLines.join("\n")}\n");

List<Sentence> _read(String text) => Tokenizer(_lexicon).sentences(text);

List<String> _matches(String pattern, String text,
    [Map<String, Set<String>> classes = const {}]) {
  var compiled = TokenPattern.compile(pattern, classes);
  return [
    for (var s in _read(text))
      for (var m in compiled.allMatches(s.tokens))
        text.substring(m.start, m.end),
  ];
}

void main() {
  group("lexicon", () {
    test("finds a word, its readings and its base", () {
      var went = _lexicon.lookup("went")!;
      expect(went.readings.single.lemma, "go");
      expect(went.all, 1 << Tags.vbd);
      expect(_lexicon.lookup("wnet"), isNull);
      // First and last lines, where a search that is off by one misses.
      expect(_lexicon.lookup("'re"), isNotNull);
      expect(_lexicon.lookup("works"), isNotNull);
    });

    test("gives the form a base word takes", () {
      expect(_lexicon.inflect("go", Tags.vbd), "went");
      expect(_lexicon.inflect("go", Tags.vbz), "goes");
      expect(_lexicon.inflect("child", Tags.nns), "children");
      // Spelled like the base, so not listed apart from it.
      expect(_lexicon.inflect("run", Tags.vbn), "run");
      // "Are" is the only present form that is not the base.
      expect(_lexicon.inflect("be", Tags.vbp), "are");
      expect(_lexicon.inflect("go", Tags.vbp), "go");
      expect(_lexicon.inflect("apple", Tags.vbd), isNull,
          reason: "a noun has no past, and an answer with a hole in it is "
              "worse than none");
    });

    test("a rare reading is possible and not likely", () {
      var dog = _lexicon.lookup("dog")!;
      expect(dog.all & (1 << Tags.vb), isNot(0));
      expect(dog.likely & (1 << Tags.vb), 0);
    });
  });

  group("tokenizer", () {
    test("cuts sentences where they end, and not at an abbreviation", () {
      expect(_read("He went home. She went home.").length, 2);
      expect(_read("Dr. Smith went home.").length, 1);
      expect(_read("The U.S. claims otherwise.").length, 1);
      expect(_read("He went to main.dart and home.").length, 1);
      expect(_read("\"Really?\" she went.").length, 1,
          reason: "the quotation ended; the sentence did not");
      expect(_read("He went... home.").length, 1);
      expect(_read("first line\nsecond line").length, 2);
    });

    test("reads a contraction as the two words it is", () {
      var tokens = _read("They're home.").single.tokens;
      expect(tokens.map((t) => t.lower), ["they", "'re", "home", "."]);
      expect(tokens[1].start, 4);
      expect(tokens[1].end, 7);
      // One the lexicon lists whole stays whole.
      expect(_read("He didn't go.").single.tokens[1].lower, "didn't");
      // A typographic apostrophe is the same apostrophe.
      expect(_read("They’re home.").single.tokens[1].lower, "'re");
    });

    test("leaves what is not prose alone", () {
      var tokens =
          _read("He went to https://example.com/a?b=c home").single.tokens;
      expect(tokens[3].kind, TokenKind.other);
      expect(tokens[3].text, "https://example.com/a?b=c");
    });

    test("chooses a reading from what is around the word", () {
      var transitions = "DT NNS 2.0\nDT VBZ -4.0\nPRP VBZ 2.0\nPRP NNS -2.0";
      var tagger = Tokenizer(_lexicon, transitions);
      var afterThe = tagger.sentences("The works").single.tokens[1];
      var afterHe = tagger.sentences("He works").single.tokens[1];
      expect(Tags.names[afterThe.tag], "NNS");
      expect(Tags.names[afterHe.tag], "VBZ");
    });

    test("knows where a sentence and a clause start", () {
      var tokens = _read("- he went, she went").single.tokens;
      var he = tokens[1], she = tokens[4];
      expect(he.first, isTrue);
      expect(he.opening, isFalse,
          reason: "a list item need not be capitalised");
      expect(she.clauseStart, isTrue);
      expect(tokens[2].clauseStart, isFalse);
    });
  });

  group("patterns", () {
    test("match words, tags, base forms and classes", () {
      expect(_matches("he|she <VBD>", "She went home."), ["She went"]);
      expect(_matches("[go]", "He goes. They went. She is gone."),
          ["goes", "went", "gone"]);
      expect(
          _matches("{who} went", "They went.", {
            "who": {"they"}
          }),
          ["They went"]);
      expect(_matches("<~VBZ>", "The works"), ["works"]);
      expect(_matches("<=NN>", "The dog works"), ["dog"],
          reason: "\"works\" is a noun barely half the time");
      expect(
          _matches(r"/[a-z]+/&<=NNP>", "He went to london. He went to London."),
          ["london"]);
    });

    test("underline only what the brackets hold", () {
      expect(_matches("he ( went ) home", "He went home."), ["went"]);
    });

    test("optional and repeated elements", () {
      expect(_matches("he <RB>? went", "He went."), ["He went"]);
      expect(_matches("the _{0,2} home", "The dog went home."),
          ["The dog went home"]);
    });

    test("anchors and looking ahead", () {
      expect(_matches("^ he", "He went. Then he went."), ["He"]);
      expect(_matches("( went ) =>home", "He went home. She went."), ["went"]);
      expect(_matches("( went ) !>home", "He went home. She went."), ["went"]);
      expect(_matches("( went ) !>home", "She went.").length, 1,
          reason: "nothing after it is not \"home\" after it");
    });

    test("say what is wrong with a pattern that is", () {
      expect(() => TokenPattern.compile("<NOPE>"), throwsFormatException);
      expect(() => TokenPattern.compile("{missing}"), throwsFormatException);
      expect(() => TokenPattern.compile("<VB"), throwsFormatException);
    });

    test("a rule is skipped for a sentence with none of its words", () {
      var pattern = TokenPattern.compile("he|she <VBD>");
      expect(pattern.required, {"he", "she"});
      expect(pattern.couldMatch({"they", "went"}), isFalse);
      expect(pattern.couldMatch({"she", "went"}), isTrue);
      // A tag pins nothing down, and a rule of tags alone is always tried.
      expect(TokenPattern.compile("<DT> <NN>").required, isNull);
    });

    test("fill in a replacement from what matched", () {
      var text = "He didn't went home.";
      var sentence = _read(text).single;
      var match = TokenPattern.compile("didn't ( <VBD> )")
          .allMatches(sentence.tokens)
          .single;
      expect(match.expand(r"$1 $2:VB", text, _lexicon), "didn't go");
      expect(match.expand(r"$2:VBG", text, _lexicon), "going");
      expect(match.expand(r"$2:NNS", text, _lexicon), isNull,
          reason: "\"went\" has no plural");
    });

    test("choose a or an by sound", () {
      expect(takesAn("apple"), isTrue);
      expect(takesAn("hour"), isTrue);
      expect(takesAn("user"), isFalse);
      expect(takesAn("university"), isFalse);
      expect(takesAn("unimportant"), isTrue);
      expect(takesAn("dog"), isFalse);
    });
  });

  group("in the checker", () {
    SpellcheckData data(List<TokenRule> rules) => SpellcheckData(
          const ["he", "she", "didn't", "went", "go", "home", "goes"],
          const [],
          const [],
          const [],
          "",
          const [],
          GrammarData(
            lexicon: base64
                .encode(gzip.encode(utf8.encode(_lexiconLines.join("\n")))),
            rules: rules,
          ),
        );

    final didntWent = TokenRule(
        "didnt-past",
        "didn't ( <VBD> )",
        r'Should be "$1 $2:VB"',
        const [r"$2:VB"],
        "Grammar",
        "After \"didn't\" the verb is plain.");

    test("a rule over words marks the word and offers the right form", () {
      var checker = WritingChecker()..updateData(data([didntWent]));
      var issue = checker.review("He didn't went home.").single;
      expect(issue.text, "went");
      expect(issue.message, 'Should be "didn\'t go"');
      expect(issue.suggestions, ["go"]);
      expect(issue.checkId, "token:didnt-past");
      expect(issue.kind.isMistake, isTrue);
      expect(checker.review("He didn't go home."), isEmpty);
    });

    test("a rule this engine cannot read is skipped, not fatal", () {
      var broken = TokenRule("broken", "<NOPE>", "never");
      var checker = WritingChecker()..updateData(data([broken, didntWent]));
      expect(checker.review("He didn't went home.").single.checkId,
          "token:didnt-past");
    });

    test("a provider that sends no grammar still checks spelling", () {
      var checker = WritingChecker()
        ..updateData(SpellcheckData(const ["he", "went"], const [], const []));
      expect(checker.review("He wnet").single.text, "wnet");
    });
  });

  group("corrections", () {
    test("are ranked by the slip and by how common the word is", () {
      var suggester = Suggester()
        ..index({
          "the",
          "tea",
          "ten",
          "tech",
          "what",
          "wait",
          "really",
          "real",
          "rely",
          "thank",
          "you"
        }, [
          "the",
          "what",
          "you",
          "really",
          "real",
          "thank",
          "wait",
          "ten",
          "tea",
          "tech",
          "rely"
        ]);
      expect(suggester.suggest("teh").first, "the",
          reason: "two letters the wrong way round, and the commonest word");
      expect(suggester.suggest("waht").first, "what");
      expect(suggester.suggest("realy").first, "really",
          reason: "a doubled letter left single");
      expect(suggester.suggest("thankyou").first, "thank you");
    });
  });
}
