import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:flutter_test/flutter_test.dart';

// writing_stats_test.dart covers the Document page's arithmetic.
//
// Counting is the one part of the writing tools with a right answer, so it is
// the one part worth testing exhaustively. The reading-ease score is the
// exception: it rests on a syllable estimate that cannot be exactly right,
// and the tests below check the band it lands in rather than the number.

void main() {
  test("an empty message counts nothing", () {
    var stats = WritingStats.of("");
    expect(stats.words, 0);
    expect(stats.characters, 0);
    expect(stats.sentences, 0);
    expect(stats.paragraphs, 0);
    expect(stats.lines, 0);
    expect(stats.readingEase, isNull);
  });

  test("characters are counted with and without spaces", () {
    var stats = WritingStats.of("the payment cleared");
    expect(stats.characters, 19);
    expect(stats.charactersNoSpaces, 17);
  });

  group("words", () {
    test("a contraction is one word", () {
      expect(WritingStats.of("don't stop").words, 2);
    });

    test("a number is a word", () {
      expect(WritingStats.of("it cost 3 DCR").words, 4);
    });

    test("punctuation is not a word", () {
      expect(WritingStats.of("yes -- really!").words, 2);
    });
  });

  group("sentences", () {
    test("each terminator ends one", () {
      expect(WritingStats.of("One. Two! Three?").sentences, 3);
    });

    test("a trailing sentence without a full stop still counts", () {
      expect(WritingStats.of("One. And then this").sentences, 2);
    });

    test("a line break ends a sentence", () {
      expect(WritingStats.of("A heading\nSome text.").sentences, 2);
    });
  });

  group("paragraphs and lines", () {
    test("a blank line separates paragraphs", () {
      expect(WritingStats.of("First para.\n\nSecond para.").paragraphs, 2);
    });

    test("a single line break does not", () {
      expect(WritingStats.of("First line.\nSecond line.").paragraphs, 1);
    });

    // How text wraps depends on the width of the field it is in, which is not
    // a property of the text, so this counts breaks rather than visual rows.
    test("lines are line breaks, not wrapped rows", () {
      expect(WritingStats.of("one\ntwo\nthree").lines, 3);
      expect(WritingStats.of("no breaks at all").lines, 1);
    });
  });

  test("pages are fractional", () {
    var stats = WritingStats.of(List.filled(250, "word").join(" "));
    expect(stats.pages, closeTo(0.5, 0.01),
        reason: "rounding half a page up to one overstates a short message");
  });

  group("reading time", () {
    test("a short message is under a minute", () {
      var stats = WritingStats.of(List.filled(50, "word").join(" "));
      expect(stats.readingTime.inSeconds, 15);
    });

    test("a long one is measured in minutes", () {
      var stats = WritingStats.of(List.filled(600, "word").join(" "));
      expect(stats.readingTime.inMinutes, 3);
    });
  });

  group("reading ease", () {
    // Short text produces a number that looks authoritative and means
    // nothing, so it produces no number at all.
    test("text too short to score has no score", () {
      expect(WritingStats.of("This is a short note.").readingEase, isNull);
    });

    test("plain writing scores as easy", () {
      var text = "The cat sat on the mat. The dog ran to the park. "
          "We went for a walk. It was a good day. The sun was out.";
      var stats = WritingStats.of(text);
      expect(stats.readingEase, greaterThan(70));
      expect(stats.readingEaseLabel, anyOf("Easy", "Very easy"));
    });

    test("dense writing scores lower than plain writing", () {
      var plain = WritingStats.of(
          "The cat sat on the mat. The dog ran to the park. We went for a "
          "walk. It was a good day. The sun was out today.");
      var dense = WritingStats.of(
          "The implementation demonstrates considerable architectural "
          "sophistication, incorporating numerous interdependent "
          "abstractions whose collective behaviour necessitates "
          "comprehensive documentation for subsequent maintenance "
          "activities undertaken by unfamiliar practitioners.");
      expect(dense.readingEase, lessThan(plain.readingEase!),
          reason: "the score has to move in the right direction even if the "
              "absolute number rests on an estimate");
    });

    test("the score is bounded", () {
      var stats = WritingStats.of(List.filled(40, "a").join(" "));
      expect(stats.readingEase, inInclusiveRange(0, 100));
    });
  });

  group("syllable estimation", () {
    test("the ordinary cases", () {
      expect(estimateSyllables("cat"), 1);
      expect(estimateSyllables("payment"), 2);
      expect(estimateSyllables("relay"), 2);
      expect(estimateSyllables("dictionary"), 4);
    });

    test("a silent trailing e is not counted", () {
      expect(estimateSyllables("make"), 1);
      expect(estimateSyllables("time"), 1);
    });

    test("but -le is", () {
      expect(estimateSyllables("table"), 2);
      expect(estimateSyllables("little"), 2);
    });

    test("-ed only counts after t or d", () {
      expect(estimateSyllables("walked"), 1);
      expect(estimateSyllables("wanted"), 2);
      expect(estimateSyllables("landed"), 2);
    });

    // Every written word is said, so nothing may come back as zero -- a zero
    // would drag the reading-ease score for the whole message.
    test("no word estimates to zero", () {
      for (var word in ["a", "I", "rhythm", "cwm", "hmm", "1st"]) {
        expect(estimateSyllables(word), greaterThan(0), reason: word);
      }
    });
  });
}
