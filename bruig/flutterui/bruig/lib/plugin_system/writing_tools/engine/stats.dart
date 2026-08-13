import 'package:bruig/plugin_system/writing_tools/engine/text_segments.dart';

// stats.dart counts what is there rather than what is wrong with it.
//
// Nothing here needs a plugin. Counting words is not a judgement about
// English and takes no dictionary, no rules and no data -- so unlike every
// other page of the writing sidebar, this one works with no provider enabled
// at all. It lives in the writing tools because that is where the sidebar
// showing it lives, not because it depends on one.
//
// The segmentation is the shared one, so "sentence" means here exactly what
// it means to the check that flags a long one. It did not always: this file
// carried its own copies of the same three regexes, with a comment pointing
// at the other definition instead of using it.

final _vowelGroup = RegExp(r"[aeiouy]+");

/// wordsPerMinute is a middling adult reading speed for ordinary prose. Real
/// speeds run from 150 to 300 depending on the reader and the material, so
/// the figure this produces is an indication and not a measurement.
const int wordsPerMinute = 200;

/// wordsPerPage is a single-spaced page in a typical 12pt font. A
/// double-spaced manuscript page is about half this, which is why the figure
/// is stated rather than assumed.
const int wordsPerPage = 500;

/// WritingStats is everything the Document page shows, computed in one pass
/// over the text so the page can be rebuilt on every keystroke.
class WritingStats {
  final int characters;
  final int charactersNoSpaces;
  final int words;
  final int sentences;
  final int paragraphs;
  final int lines;

  /// syllables is an estimate, and only exists to feed [readingEase].
  final int syllables;

  const WritingStats({
    required this.characters,
    required this.charactersNoSpaces,
    required this.words,
    required this.sentences,
    required this.paragraphs,
    required this.lines,
    required this.syllables,
  });

  static const empty = WritingStats(
    characters: 0,
    charactersNoSpaces: 0,
    words: 0,
    sentences: 0,
    paragraphs: 0,
    lines: 0,
    syllables: 0,
  );

  /// of counts [text] in a single pass per measure.
  factory WritingStats.of(String text) {
    if (text.isEmpty) return empty;

    var wordMatches = wordForCounting.allMatches(text).toList();
    var syllables = 0;
    for (var m in wordMatches) {
      syllables += estimateSyllables(m.group(0)!);
    }

    return WritingStats(
      characters: text.length,
      charactersNoSpaces: text.replaceAll(RegExp(r"\s"), "").length,
      words: wordMatches.length,
      sentences: countSegments(text, sentenceEnd),
      paragraphs: countSegments(text, paragraphBreak),
      // A line break count, not a count of the lines as wrapped on screen:
      // how text wraps depends on the width of the field it is in, which is
      // not a property of the text.
      lines: text.trim().isEmpty ? 0 : "\n".allMatches(text).length + 1,
      syllables: syllables,
    );
  }

  /// pages is fractional on purpose. A message is almost never a whole number
  /// of pages, and rounding a half page up to one overstates it badly at the
  /// lengths anything here is likely to be.
  double get pages => words / wordsPerPage;

  /// readingTime is how long [words] takes to read at [wordsPerMinute].
  Duration get readingTime =>
      Duration(seconds: (words / wordsPerMinute * 60).round());

  /// readingEase is the Flesch reading-ease score: roughly 0 to 100, higher
  /// being easier. 60-70 is plain English; below 30 is heavy going.
  ///
  /// Null for text too short to score. The formula divides by the sentence
  /// and word counts, and on a three-word message it produces a number that
  /// looks authoritative and means nothing.
  ///
  /// The syllable count it rests on is an estimate -- see [estimateSyllables]
  /// -- so this is a rough band rather than a figure to quote.
  double? get readingEase {
    if (words < 20 || sentences == 0) return null;
    var score =
        206.835 - 1.015 * (words / sentences) - 84.6 * (syllables / words);
    return score.clamp(0, 100);
  }

  /// readingEaseLabel puts [readingEase] into words, which is the only form
  /// most readers can use it in.
  String? get readingEaseLabel {
    var score = readingEase;
    if (score == null) return null;
    if (score >= 80) return "Very easy";
    if (score >= 60) return "Easy";
    if (score >= 50) return "Fairly easy";
    if (score >= 30) return "Difficult";
    return "Very difficult";
  }

}

/// estimateSyllables counts vowel groups in [word], with the adjustments that
/// make the count roughly right for English.
///
/// An estimate, and unavoidably so: syllable counts depend on pronunciation,
/// which spelling does not determine ("read" is one syllable either way,
/// "lived" is one and "hatred" is two). A real count needs a pronunciation
/// dictionary, which would be several megabytes to improve one figure on one
/// page by a few percent.
///
/// The rules below are the usual ones: count groups of vowels, drop a silent
/// trailing "e", and never return zero, since every written word is said.
int estimateSyllables(String word) {
  var w = word.toLowerCase().replaceAll(RegExp(r"[^a-z]"), "");
  if (w.isEmpty) return 0;
  if (w.length <= 3) return 1;

  // A trailing "e" is usually silent ("make", "time"), except after "l"
  // where it forms its own syllable ("little", "table").
  if (w.endsWith("e") && !w.endsWith("le")) {
    w = w.substring(0, w.length - 1);
  }
  // "-ed" is a syllable only after t or d ("wanted", "landed"); elsewhere it
  // is not ("walked", "lived").
  if (w.endsWith("ed") && w.length > 3) {
    var before = w[w.length - 3];
    if (before != "t" && before != "d") {
      w = w.substring(0, w.length - 2);
    }
  }

  var count = _vowelGroup.allMatches(w).length;
  return count < 1 ? 1 : count;
}
