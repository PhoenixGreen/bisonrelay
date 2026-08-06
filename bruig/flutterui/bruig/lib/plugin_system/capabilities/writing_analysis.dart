import 'package:bruig/plugin_system/capabilities/spellcheck.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';

// writing_analysis.dart runs the checks a regular expression cannot express,
// because they have to count.
//
// "This word appears four times in this paragraph" is not a property of any
// stretch of text on its own -- it is a property of the paragraph around it,
// and a pattern has no way to look there. The same goes for a sentence's
// length, a run of sentences opening the same way, and two spellings of one
// word being mixed.
//
// A provider does not supply the logic for these, because there is no pattern
// to supply. It names one of the checks implemented below and gives the
// threshold, the wording and the explanation; the mechanics live here, as
// they already do for the regex engine and the edit-distance ranking a
// provider also relies on without owning.
//
// A check id nothing here implements is ignored rather than reported, so a
// provider can ship a check ahead of the app that runs it.

/// _sentenceEnd splits text into sentences: a full stop, question mark or
/// exclamation followed by whitespace, or a line break.
///
/// Approximate on purpose. It splits "e.g." and "Mr. Smith" in the wrong
/// place, and getting that right needs an abbreviation list that would then
/// be wrong about some other abbreviation. The checks built on it only ever
/// count, so a wrongly split sentence costs a slightly wrong number rather
/// than a wrongly placed underline.
final _sentenceEnd = RegExp(r"(?<=[.!?])\s+|\n+");

/// _word matches a word for counting: letters and apostrophes, so "don't" is
/// one word rather than two.
final _word = RegExp(r"[A-Za-z][A-Za-z']*");

/// _paragraphBreak is a blank line, which is what separates paragraphs in the
/// plain text these composers hold.
final _paragraphBreak = RegExp(r"\n\s*\n");

/// runAnalysisChecks applies every check [checks] names that this app knows
/// how to run, over the whole of [text].
///
/// [dictionaryWords] is consulted by the repetition check to leave function
/// words alone; a repeated "the" is not a stylistic problem.
List<WritingIssue> runAnalysisChecks(
  String text,
  List<AnalysisCheck> checks, {
  required bool Function(String) isIgnoredCheck,
}) {
  if (text.trim().isEmpty) return const [];
  var issues = <WritingIssue>[];
  for (var check in checks) {
    if (isIgnoredCheck(analysisCheckId(check))) continue;
    switch (check.id) {
      case "repeated-word-in-paragraph":
        _repeatedWords(text, check, issues);
      case "long-sentence":
        _longSentences(text, check, issues);
      case "repeated-sentence-opener":
        _repeatedOpeners(text, check, issues);
      case "spelling-variant-inconsistency":
        _spellingVariants(text, check, issues);
      default:
        // A check this app does not implement. Deliberately silent: it is how
        // a provider ships a check before the app that runs it.
        break;
    }
  }
  return issues;
}

/// analysisCheckId is how one of these is identified when the user turns it
/// off. It has to be distinguishable from a grammar rule's pattern, which is
/// what that same preference set otherwise holds.
String analysisCheckId(AnalysisCheck check) => "analysis:${check.id}";

/// _issue builds one result, expanding the check's message.
///
/// `$1` is what the check is about -- the repeated word, the spelling that
/// clashes -- and `$2` is whatever second thing the check counts or names: a
/// number for the counting checks, the other spelling for the variant one.
/// Both are passed as strings so one substitution serves all four.
WritingIssue _issue(
  AnalysisCheck check,
  int start,
  int end,
  String text, {
  String subject = "",
  String detail = "",
  List<String> suggestions = const [],
}) {
  String expand(String s) =>
      s.replaceAll(r"$1", subject).replaceAll(r"$2", detail);
  return WritingIssue(
    range: TextRange(start: start, end: end),
    text: text.substring(start, end),
    message: expand(check.message),
    suggestions: suggestions,
    kind: check.severity == "suggestion"
        ? WritingIssueKind.phrasing
        : WritingIssueKind.grammar,
    checkId: analysisCheckId(check),
    category: check.category,
    explanation: expand(check.explanation),
  );
}

/// _commonWords are left out of the repetition count. They are the words a
/// sentence cannot be built without, and flagging "the" for appearing six
/// times would bury every real finding.
///
/// A fixed list rather than the provider's frequency ranking: the ranking
/// says which words are common in English, which is not the same question.
/// "Payment" is uncommon enough to rank low and is exactly the word a message
/// about payments should be allowed to repeat -- what matters here is whether
/// a word carries meaning, and function words are a closed class.
const _functionWords = {
  "a",
  "an",
  "the",
  "and",
  "or",
  "but",
  "if",
  "of",
  "to",
  "in",
  "on",
  "at",
  "by",
  "for",
  "with",
  "from",
  "as",
  "is",
  "are",
  "was",
  "were",
  "be",
  "been",
  "being",
  "am",
  "do",
  "does",
  "did",
  "have",
  "has",
  "had",
  "will",
  "would",
  "can",
  "could",
  "may",
  "might",
  "must",
  "shall",
  "should",
  "i",
  "you",
  "he",
  "she",
  "it",
  "we",
  "they",
  "me",
  "him",
  "her",
  "us",
  "them",
  "my",
  "your",
  "his",
  "its",
  "our",
  "their",
  "this",
  "that",
  "these",
  "those",
  "there",
  "here",
  "not",
  "no",
  "so",
  "than",
  "then",
  "when",
  "where",
  "which",
  "who",
  "what",
  "how",
  "why",
  "all",
  "any",
  "some",
  "one",
  "up",
  "out",
  "about",
  "into",
  "over",
  "just",
  "very",
  "too",
  "also",
  "more",
  "most",
  "such",
};

/// _repeatedWords flags every use of a word that appears too often within one
/// paragraph.
///
/// Every use, not just the ones past the threshold: the point is to show
/// where the repetition is so it can be broken up, and marking only the
/// fourth occurrence hides the three that made it a problem.
void _repeatedWords(String text, AnalysisCheck check, List<WritingIssue> out) {
  var threshold = check.threshold > 0 ? check.threshold : 4;
  for (var paragraph in _paragraphs(text)) {
    var positions = <String, List<RegExpMatch>>{};
    for (var m in _word.allMatches(paragraph.text)) {
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
        out.add(_issue(
          check,
          paragraph.start + m.start,
          paragraph.start + m.end,
          text,
          subject: m.group(0)!,
          detail: "${entry.value.length}",
        ));
      }
    }
  }
}

/// _longSentences flags a sentence past the threshold, underlining the whole
/// of it.
void _longSentences(String text, AnalysisCheck check, List<WritingIssue> out) {
  var threshold = check.threshold > 0 ? check.threshold : 30;
  for (var sentence in _sentences(text)) {
    var words = _word.allMatches(sentence.text).length;
    if (words < threshold) continue;
    out.add(
        _issue(check, sentence.start, sentence.end, text, detail: "$words"));
  }
}

/// _repeatedOpeners flags a run of sentences that all begin with the same
/// word, marking the opening word of each.
void _repeatedOpeners(
    String text, AnalysisCheck check, List<WritingIssue> out) {
  var threshold = check.threshold > 1 ? check.threshold : 3;
  var sentences = _sentences(text);

  var runStart = 0;
  String? runWord;
  void flush(int end) {
    var length = end - runStart;
    if (runWord == null || length < threshold) return;
    for (var i = runStart; i < end; i++) {
      var opener = _word.firstMatch(sentences[i].text);
      if (opener == null) continue;
      out.add(_issue(
        check,
        sentences[i].start + opener.start,
        sentences[i].start + opener.end,
        text,
        subject: opener.group(0)!,
        detail: "$length",
      ));
    }
  }

  for (var i = 0; i < sentences.length; i++) {
    var opener = _word.firstMatch(sentences[i].text)?.group(0)?.toLowerCase();
    if (opener != runWord) {
      flush(i);
      runStart = i;
      runWord = opener;
    }
  }
  flush(sentences.length);
}

/// _spellingVariants flags both spellings when a message uses two spellings
/// of one word.
///
/// Neither is wrong, so neither is preferred: every occurrence of both is
/// marked, and the message names the other one so it is clear what the clash
/// is. Choosing a side would mean choosing between British and American
/// English on the writer's behalf.
void _spellingVariants(
    String text, AnalysisCheck check, List<WritingIssue> out) {
  var lower = text.toLowerCase();
  for (var pair in check.values) {
    var parts = pair.split("|");
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) continue;
    // A cheap reject before building a pattern for each of the forty pairs on
    // every keystroke.
    if (!lower.contains(parts[0]) || !lower.contains(parts[1])) continue;

    var first = _occurrences(text, parts[0]);
    var second = _occurrences(text, parts[1]);
    if (first.isEmpty || second.isEmpty) continue;
    for (var (match, other) in [
      ...first.map((m) => (m, parts[1])),
      ...second.map((m) => (m, parts[0])),
    ]) {
      var found = match.group(0)!;
      out.add(_issue(
        check,
        match.start,
        match.end,
        text,
        subject: found,
        detail: other,
        // Offered as a correction even though nothing here is wrong: taking
        // it is how you settle on one spelling, and it is the only action
        // there is to take.
        suggestions: [_matchCase(found, other)],
      ));
    }
  }
}

/// _matchCase gives [replacement] the capitalisation of [original], so
/// replacing "Colour" at the start of a sentence does not produce "color".
String _matchCase(String original, String replacement) {
  if (original.isEmpty || replacement.isEmpty) return replacement;
  if (original[0] == original[0].toUpperCase() &&
      original[0] != original[0].toLowerCase()) {
    return replacement[0].toUpperCase() + replacement.substring(1);
  }
  return replacement;
}

/// _occurrences finds whole-word appearances of [word], case-insensitively.
List<RegExpMatch> _occurrences(String text, String word) =>
    RegExp("\\b${RegExp.escape(word)}\\b", caseSensitive: false)
        .allMatches(text)
        .toList();

/// _Segment is a stretch of the original text together with where it started,
/// so an issue found inside it can be reported at the right offset.
class _Segment {
  final String text;
  final int start;
  int get end => start + text.length;
  const _Segment(this.text, this.start);
}

List<_Segment> _paragraphs(String text) => _split(text, _paragraphBreak);

List<_Segment> _sentences(String text) => _split(text, _sentenceEnd);

/// _split cuts text on [separator], keeping each piece's offset and dropping
/// the empty ones.
List<_Segment> _split(String text, RegExp separator) {
  var out = <_Segment>[];
  var at = 0;
  for (var m in separator.allMatches(text)) {
    var piece = text.substring(at, m.start);
    if (piece.trim().isNotEmpty) out.add(_Segment(piece, at));
    at = m.end;
  }
  var last = text.substring(at);
  if (last.trim().isNotEmpty) out.add(_Segment(last, at));
  return out;
}
