import 'package:bruig/writing_tools/engine/analysis.dart';
import 'package:bruig/writing_tools/engine/text_segments.dart';
import 'package:golib_plugin/definitions.dart';

// repetition.dart is the two checks about saying the same thing twice: one
// word used over and over inside a paragraph, and a run of sentences all
// opening the same way.
//
// Neither is an error and both are marked as suggestions by the providers
// that declare them. Repetition is often exactly right -- a paragraph about
// payments will say "payment" -- so the whole difficulty in both checks is
// the threshold at which it stops reading as the subject and starts reading
// as a rut. That number is the provider's to choose; the counting is here.

/// repeatedWordInParagraphId fires when one word is used the check's
/// threshold or more times in a single paragraph. `$1` is the word, `$2` the
/// count.
const repeatedWordInParagraphId = "repeated-word-in-paragraph";

/// repeatedSentenceOpenerId fires when that many consecutive sentences begin
/// with the same word. `$1` is the word, `$2` the run length.
const repeatedSentenceOpenerId = "repeated-sentence-opener";

/// repeatedWordCheckId names the one counting check whose finding can be
/// answered with a replacement, so the sidebar can offer alternatives beside
/// it. The word comes from here; the alternatives come from the thesaurus.
const repeatedWordCheckId = "analysis:$repeatedWordInParagraphId";

final Map<String, AnalysisRunner> repetitionChecks = {
  repeatedWordInParagraphId: _repeatedWords,
  repeatedSentenceOpenerId: _repeatedOpeners,
};

/// _functionWords are left out of the repetition count. They are the words a
/// sentence cannot be built without, and flagging "the" for appearing six
/// times would bury every real finding.
///
/// A fixed list rather than the provider's frequency ranking: the ranking
/// says which words are common in English, which is not the same question.
/// "Payment" is uncommon enough to rank low and is exactly the word a message
/// about payments should be allowed to repeat -- what matters here is whether
/// a word carries meaning, and function words are a closed class.
const _functionWords = {
  "a", "an", "the", "and", "or", "but", "if", "of", "to", "in", "on", "at",
  "by", "for", "with", "from", "as", "is", "are", "was", "were", "be", "been",
  "being", "am", "do", "does", "did", "have", "has", "had", "will", "would",
  "can", "could", "may", "might", "must", "shall", "should", "i", "you", "he",
  "she", "it", "we", "they", "me", "him", "her", "us", "them", "my", "your",
  "his", "its", "our", "their", "this", "that", "these", "those", "there",
  "here", "not", "no", "so", "than", "then", "when", "where", "which", "who",
  "what", "how", "why", "all", "any", "some", "one", "up", "out", "about",
  "into", "over", "just", "very", "too", "also", "more", "most", "such",
};

/// _repeatedWords flags every use of a word that appears too often within one
/// paragraph.
///
/// Every use, not just the ones past the threshold: the point is to show
/// where the repetition is so it can be broken up, and marking only the
/// fourth occurrence hides the three that made it a problem.
void _repeatedWords(AnalysisContext context, AnalysisCheck check) {
  var threshold = check.threshold > 0 ? check.threshold : 4;
  for (var paragraph in context.paragraphs) {
    var positions = <String, List<RegExpMatch>>{};
    for (var m in wordForChecking.allMatches(paragraph.text)) {
      var word = m.group(0)!.toLowerCase();
      // Short words are function words even when the list misses one, and a
      // repeated three-letter word reads as normal English rather than as a
      // rut.
      if (word.length < 4 || _functionWords.contains(word)) continue;
      (positions[word] ??= []).add(m);
    }
    for (var entry in positions.entries) {
      if (entry.value.length < threshold) continue;
      for (var m in entry.value) {
        context.report(
          check,
          paragraph.start + m.start,
          paragraph.start + m.end,
          subject: m.group(0)!,
          detail: "${entry.value.length}",
        );
      }
    }
  }
}

/// _repeatedOpeners flags a run of sentences that all begin with the same
/// word, marking the opening word of each.
void _repeatedOpeners(AnalysisContext context, AnalysisCheck check) {
  var threshold = check.threshold > 1 ? check.threshold : 3;
  var sentences = context.sentences;

  var runStart = 0;
  String? runWord;
  void flush(int end) {
    var length = end - runStart;
    if (runWord == null || length < threshold) return;
    for (var i = runStart; i < end; i++) {
      var opener = wordForChecking.firstMatch(sentences[i].text);
      if (opener == null) continue;
      context.report(
        check,
        sentences[i].start + opener.start,
        sentences[i].start + opener.end,
        subject: opener.group(0)!,
        detail: "$length",
      );
    }
  }

  for (var i = 0; i < sentences.length; i++) {
    var opener =
        wordForChecking.firstMatch(sentences[i].text)?.group(0)?.toLowerCase();
    if (opener != runWord) {
      flush(i);
      runStart = i;
      runWord = opener;
    }
  }
  flush(sentences.length);
}
