import 'package:bruig/plugin_system/writing_tools/engine/analysis.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';

// writing_analysis_test.dart covers the checks that count.
//
// They are the only checks in the app whose logic lives here rather than in a
// provider's regex, so they are the only ones a provider's own tests cannot
// reach. Everything below is about the counting being right and the
// thresholds being respected -- a check that fires on ordinary writing is
// worse than no check, because the reader learns to skip the whole page.

AnalysisCheck _check(
  String id, {
  int threshold = 0,
  String message = r"$1 / $2",
  List<String> values = const [],
  String severity = "suggestion",
}) =>
    AnalysisCheck(
        id, threshold, message, "Repetition", "why", severity, values);

List<WritingIssue> _run(String text, AnalysisCheck check) =>
    runAnalysisChecks(text, [check], isIgnoredCheck: (_) => false);

void main() {
  _unpairedBracketTests();
  group("repeated words", () {
    var check = _check("repeated-word-in-paragraph",
        threshold: 4, message: r'"$1" used $2 times');

    test("a word past the threshold is flagged at every use", () {
      var text = "The payment cleared. The payment failed. "
          "Another payment arrived, and the payment settled.";
      var issues = _run(text, check);

      expect(issues, hasLength(4),
          reason: "marking only the fourth use hides the three that made it "
              "a problem");
      expect(issues.first.message, '"payment" used 4 times');
      for (var issue in issues) {
        expect(text.substring(issue.range.start, issue.range.end), "payment");
      }
    });

    test("a word under the threshold is left alone", () {
      // Three uses is often just what the paragraph is about.
      expect(_run("payment payment payment", check), isEmpty);
    });

    // The count is per paragraph, not per message: the same word opening two
    // distant paragraphs is not a rut.
    test("the count does not cross a paragraph break", () {
      var text = "payment payment\n\npayment payment";
      expect(_run(text, check), isEmpty);
    });

    // Without this the page fills with "the", "and" and "that" and nothing
    // else can be found in it.
    test("function words are not counted", () {
      expect(_run("the and the and the and the and", check), isEmpty);
    });

    test("case does not split the count", () {
      expect(_run("Payment payment PAYMENT payment", check), hasLength(4));
    });
  });

  group("long sentences", () {
    var check =
        _check("long-sentence", threshold: 10, message: r"Long -- $2 words");

    test("a sentence past the threshold is flagged whole", () {
      var long = "${List.filled(12, "word").join(" ")}.";
      var issues = _run(long, check);
      expect(issues, hasLength(1));
      expect(issues.single.message, "Long -- 12 words");
      expect(issues.single.range.start, 0);
    });

    test("a short sentence is left alone", () {
      expect(_run("This is short.", check), isEmpty);
    });

    // A long message of short sentences is fine; the check is per sentence.
    test("sentences are measured one at a time", () {
      var text = List.filled(10, "Short and fine.").join(" ");
      expect(_run(text, check), isEmpty);
    });
  });

  group("repeated sentence openers", () {
    var check = _check("repeated-sentence-opener",
        threshold: 3, message: r'$2 sentences start with "$1"');

    test("a run of three is flagged at each opener", () {
      var text = "We shipped it. We tested it. We released it.";
      var issues = _run(text, check);
      expect(issues, hasLength(3));
      expect(issues.first.message, '3 sentences start with "We"');
      for (var issue in issues) {
        expect(text.substring(issue.range.start, issue.range.end), "We");
      }
    });

    test("a run of two is left alone", () {
      expect(
          _run("We shipped it. We tested it. Then it broke.", check), isEmpty);
    });

    // The run has to be consecutive: three sentences starting with "We"
    // spread through a message is not a rhythm problem.
    test("the run has to be unbroken", () {
      expect(
          _run("We went. They came. We saw. They left. We conquered.", check),
          isEmpty);
    });
  });

  group("spelling variants", () {
    var check = _check("spelling-variant-inconsistency",
        message: r'"$1" and "$2" are both used',
        values: ["colour|color", "organise|organize"]);

    test("both spellings are flagged when both appear", () {
      var text = "The colour is off, so change the color.";
      var issues = _run(text, check);
      expect(issues, hasLength(2));
      expect(issues.map((i) => i.text), containsAll(["colour", "color"]));
    });

    // Neither spelling is wrong, so neither is preferred: the check reports
    // that two were used, and each is offered the other.
    test("each is offered the other spelling", () {
      var issues = _run("colour and color", check);
      expect(
          issues.firstWhere((i) => i.text == "colour").suggestions, ["color"]);
      expect(
          issues.firstWhere((i) => i.text == "color").suggestions, ["colour"]);
    });

    test("one spelling used consistently is left alone", () {
      expect(_run("colour, colour and more colour", check), isEmpty);
      expect(_run("color, color and more color", check), isEmpty);
    });

    // Replacing "Colour" at the start of a sentence must not produce "color".
    test("the replacement keeps the capitalisation", () {
      var issues = _run("Colour matters. The color is off.", check);
      expect(
          issues.firstWhere((i) => i.text == "Colour").suggestions, ["Color"]);
    });

    // A pair listed but not used at all costs nothing.
    test("an unused pair is silent", () {
      expect(_run("The colour is off.", check), isEmpty);
    });
  });

  // A provider can ship a check before the app that runs it, so an unknown id
  // has to be ignored rather than reported.
  test("an unimplemented check is ignored", () {
    expect(_run("some text here", _check("some-future-check")), isEmpty);
  });

  test("a check turned off does not run", () {
    var check = _check("long-sentence", threshold: 3);
    expect(_run("one two three four", check), isNotEmpty);
    expect(
        runAnalysisChecks("one two three four", [check],
            isIgnoredCheck: (id) => id == analysisCheckId(check)),
        isEmpty);
  });

  // Severity decides the colour of the mark and which page it is listed on,
  // so it has to survive the trip through a declared check.
  test("severity carries through to the issue", () {
    var suggestion = _run(
        "one two three four five six", _check("long-sentence", threshold: 3));
    expect(suggestion.single.kind, WritingIssueKind.phrasing);

    var mistake = _run("one two three four five six",
        _check("long-sentence", threshold: 3, severity: ""));
    expect(mistake.single.kind, WritingIssueKind.grammar);
  });

  test("empty text is not analysed", () {
    expect(_run("   \n  ", _check("long-sentence", threshold: 1)), isEmpty);
  });
}

// Unpaired brackets: a counting check rather than a matching one, and the
// only one of them that is an error -- a bracket that is never closed is not
// a matter of taste, and the reader of the post sees it too.
void _unpairedBracketTests() {
  var check = AnalysisCheck("unpaired-brackets", 0, r'Unclosed "$1"',
      "Punctuation", "why", "", const []);

  List<WritingIssue> run(String text) =>
      runAnalysisChecks(text, [check], isIgnoredCheck: (_) => false);

  test("balanced text is left alone", () {
    for (var text in [
      "This (is fine) and so is [this].",
      "Nested (brackets [work] too).",
      'She said "hello" and left.',
      'Two "quoted" "things" here.',
      "No brackets at all.",
    ]) {
      expect(run(text), isEmpty, reason: text);
    }
  });

  test("an opener that is never closed is flagged where it opens", () {
    var text = "This (is not closed and neither is this.";
    var issue = run(text).single;
    expect(text.substring(issue.range.start, issue.range.end), "(");
    expect(issue.message, 'Unclosed "("');
  });

  test("a closer with nothing open is flagged", () {
    var issue = run("This is not opened).").single;
    expect(issue.text, ")");
  });

  // A count can say a message is unbalanced but not where, and in a long
  // post finding it is most of the work.
  test("the wrong closer is caught, not just an imbalance", () {
    var issues = run("Mismatched (like this].");
    expect(issues, isNotEmpty);
  });

  test("an odd number of quotes is flagged at the last one", () {
    var text = 'She said "hello and left.';
    var issue = run(text).single;
    expect(text.substring(issue.range.start, issue.range.end), '"');
  });

  // The apostrophe is the same character as a single quote, so counting it
  // would leave every message with a contraction in it unbalanced.
  test("apostrophes are not quotes", () {
    expect(run("I don't think it's a problem."), isEmpty);
  });

  // Code is full of brackets that balance in a language this knows nothing
  // about, and half of one pasted in on purpose is not a typo.
  group("things that are not mistakes", () {
    test("a fenced code block is skipped", () {
      expect(run("Here:\n```\nif (x {\n```\nand done."), isEmpty);
    });

    test("an inline code span is skipped", () {
      expect(run("Call `foo(` to see the error."), isEmpty);
    });

    // The single most annoying thing this could possibly do.
    test("emoticons are skipped", () {
      for (var text in [
        "Sounds good :)",
        "Oh no :(",
        "Really :-)",
        "Ha :D and =)",
        "Backwards (: too",
      ]) {
        expect(run(text), isEmpty, reason: text);
      }
    });

    // A real bracket beside an emoticon is still a real bracket.
    test("a genuine fault next to an emoticon is still caught", () {
      expect(run("This (is unclosed :) really"), isNotEmpty);
    });
  });
}
