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
/// one word rather than two. The typographic apostrophes are included
/// because a field that substitutes them would otherwise split every
/// contraction in the message.
final _word = RegExp("[A-Za-z][A-Za-z'\u2019\u02BC\u2018]*");

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
  DateTime? now,
}) {
  now ??= DateTime.now();
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
      case "unpaired-brackets":
        _unpairedBrackets(text, check, issues);
      case "date-weekday-mismatch":
        _weekdayAgreement(text, check, issues, now, wantYear: true);
      case "date-weekday-mismatch-this-year":
        _weekdayAgreement(text, check, issues, now, wantYear: false);
      case "impossible-date":
        _impossibleDates(text, check, issues, now);
      case "apostrophe-inconsistency":
        _apostropheConsistency(text, check, issues);
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

/// repeatedWordCheckId names the one counting check whose finding can be
/// answered with a replacement, so the sidebar can offer alternatives beside
/// it. The word comes from here; the alternatives come from the thesaurus.
const repeatedWordCheckId = "analysis:repeated-word-in-paragraph";

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
        suggestions: [matchCase(found, other)],
      ));
    }
  }
}

/// _pairs are the marks that come in twos. The apostrophe is deliberately
/// absent: it is the same character as a single quote, and "don't" would
/// leave every message unbalanced.
const _pairs = {"(": ")", "[": "]", "{": "}"};

/// _skipped are the stretches of a message where an unmatched bracket is
/// somebody's content rather than their mistake.
///
/// Code is the obvious one -- a fenced block or an inline span is full of
/// brackets that balance in a language this knows nothing about, and half of
/// one pasted in on purpose is still not a typo the writer wants told about.
/// Emoticons are the other: ":)" is a closing bracket with nothing open, and
/// flagging it would be the single most annoying thing this plugin does.
final _skipped = RegExp(
  r"```[\s\S]*?```" // a fenced code block
  r"|`[^`\n]*`" // an inline code span
  r"|[:;=8][-~^]?[)(\]\[dDpPoO]" // :) :-( :] :D
  r"|[)(\]\[][-~^]?[:;=8]", // (: ]:
);

/// _unpairedBrackets flags a bracket that is never closed, a closer with
/// nothing open, and an odd number of double quotes.
///
/// A stack rather than a count, so "(]" is caught and so is the *position*
/// of the offender -- a count can say a message is unbalanced but not where,
/// which in a long post is most of the work.
void _unpairedBrackets(
    String text, AnalysisCheck check, List<WritingIssue> out) {
  var masked = _maskSkipped(text);

  var open = <({String mark, int at})>[];
  var quotes = <int>[];
  for (var i = 0; i < masked.length; i++) {
    var c = masked[i];
    if (_pairs.containsKey(c)) {
      open.add((mark: c, at: i));
      continue;
    }
    if (c == '"') {
      quotes.add(i);
      continue;
    }
    if (!_pairs.containsValue(c)) continue;

    // A closer with nothing open, or one that does not match what is.
    if (open.isEmpty || _pairs[open.last.mark] != c) {
      out.add(_issue(check, i, i + 1, text, subject: c));
      continue;
    }
    open.removeLast();
  }

  for (var unclosed in open) {
    out.add(_issue(check, unclosed.at, unclosed.at + 1, text,
        subject: unclosed.mark));
  }
  // Quotes have no direction, so the only thing that can be said is that
  // there is an odd number of them -- and the last is the one to point at,
  // since everything before it paired up.
  if (quotes.length.isOdd) {
    out.add(_issue(check, quotes.last, quotes.last + 1, text, subject: '"'));
  }
}

/// _maskSkipped replaces code spans and emoticons with spaces, keeping the
/// text the same length so every offset still points where it did.
String _maskSkipped(String text) {
  var masked = text.split("");
  for (var m in _skipped.allMatches(text)) {
    for (var i = m.start; i < m.end; i++) {
      masked[i] = " ";
    }
  }
  return masked.join();
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

// --- Dates -------------------------------------------------------------
//
// The only checks here that do arithmetic rather than counting, and the only
// ones certain about something a careful reader would still miss: nobody
// proofreads a date against a calendar. "We ship Monday, 10 August" is a
// sentence you can read twenty times without noticing the 10th is a Tuesday.
//
// The month and weekday names are the trap. "May", "March" and "August" are
// ordinary words, so a pattern looking for a month alone would fire on "we
// march on" constantly. Every pattern below therefore requires a month
// beside a day number, and the two weekday checks require a weekday beside
// both -- which is a shape that ordinary prose does not accidentally form.

const _monthNumbers = {
  "january": 1,
  "jan": 1,
  "february": 2,
  "feb": 2,
  "march": 3,
  "mar": 3,
  "april": 4,
  "apr": 4,
  "may": 5,
  "june": 6,
  "jun": 6,
  "july": 7,
  "jul": 7,
  "august": 8,
  "aug": 8,
  "september": 9,
  "sept": 9,
  "sep": 9,
  "october": 10,
  "oct": 10,
  "november": 11,
  "nov": 11,
  "december": 12,
  "dec": 12,
};

const _weekdayNumbers = {
  "monday": 1,
  "mon": 1,
  "tuesday": 2,
  "tues": 2,
  "tue": 2,
  "wednesday": 3,
  "weds": 3,
  "wed": 3,
  "thursday": 4,
  "thurs": 4,
  "thur": 4,
  "thu": 4,
  "friday": 5,
  "fri": 5,
  "saturday": 6,
  "sat": 6,
  "sunday": 7,
  "sun": 7,
};

/// _weekdayNames is indexed by DateTime.weekday, which counts Monday as 1.
const _weekdayNames = [
  "",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday",
];

/// _alternation joins names longest-first, so "september" is preferred to
/// "sep" and "tuesday" to "tue". A regex alternation takes the first branch
/// that matches rather than the longest, so the order is the whole of what
/// makes the abbreviations safe to include.
String _alternation(Iterable<String> names) {
  var sorted = names.toList()..sort((a, b) => b.length.compareTo(a.length));
  return sorted.join("|");
}

final _months = _alternation(_monthNumbers.keys);
final _weekdays = _alternation(_weekdayNumbers.keys);

/// _dayNumber is a day with an optional ordinal ending, refusing to match
/// part of a longer number: without the lookahead, "August 100" reads as the
/// 10th.
const _dayNumber = r"(\d{1,2})(?:st|nd|rd|th)?(?!\d)";

/// _optionalYear is four digits after a comma or a space.
const _optionalYear = r"(?:[,\s]+(\d{4})(?!\d))?";

/// The weekday separator allows a full stop so "Mon. 10 Aug." is read.
const _sep = r"[.,\s]+";

/// Weekday given: "Monday, 10 August 2026" and "Monday the 10th of August".
/// Groups: 1 weekday, 2 day, 3 month, 4 year.
final _weekdayDayFirst = RegExp(
    "\\b($_weekdays)\\b$_sep(?:the\\s+)?$_dayNumber\\s+(?:of\\s+)?($_months)\\b$_optionalYear",
    caseSensitive: false);

/// "Monday, August 10, 2026". Groups: 1 weekday, 2 month, 3 day, 4 year.
final _weekdayMonthFirst = RegExp(
    "\\b($_weekdays)\\b$_sep($_months)\\s+$_dayNumber$_optionalYear",
    caseSensitive: false);

/// The same two without a weekday, for the impossible-date check, which has
/// no use for one. Keeping them separate means the flagged range is the date
/// itself rather than the weekday in front of it.
/// Groups: 1 day, 2 month, 3 year.
final _bareDayFirst = RegExp(
    "\\b$_dayNumber\\s+(?:of\\s+)?($_months)\\b$_optionalYear",
    caseSensitive: false);

/// Groups: 1 month, 2 day, 3 year.
final _bareMonthFirst =
    RegExp("\\b($_months)\\s+$_dayNumber$_optionalYear", caseSensitive: false);

/// _nearestYear picks the year a date with no year written most likely means:
/// the one that puts it closest to today.
///
/// The current year is the obvious guess and it is wrong twice a year. Someone
/// writing "Monday, 4 January" in late December means the January a week away,
/// not the one eleven months behind them, and checking the weekday against the
/// wrong year produces a confident correction that is itself wrong. The same
/// happens in reverse in early January for a date in December.
///
/// Returns null when the day does not exist in any candidate year, which is
/// the impossible-date check's business rather than this one's.
int? _nearestYear(int month, int day, DateTime now) {
  int? best;
  Duration? closest;
  for (var year in [now.year - 1, now.year, now.year + 1]) {
    if (day < 1 || day > _daysInMonth(month, year)) continue;
    var gap = DateTime(year, month, day).difference(now).abs();
    if (closest == null || gap < closest) {
      closest = gap;
      best = year;
    }
  }
  return best;
}

bool _isLeapYear(int y) => y % 4 == 0 && (y % 100 != 0 || y % 400 == 0);

int _daysInMonth(int month, int year) {
  const lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (month == 2 && _isLeapYear(year)) return 29;
  return lengths[month - 1];
}

/// _weekdayAgreement flags a weekday that is not the one that date fell on.
///
/// [wantYear] splits the two declared checks. With the year written out the
/// answer is certain and the check is an error; without it the current year
/// is assumed, "Monday 10 August" may be a date in some other year, and the
/// check is a suggestion. Each match belongs to exactly one of the two, so
/// running both produces one finding rather than two.
void _weekdayAgreement(
  String text,
  AnalysisCheck check,
  List<WritingIssue> out,
  DateTime now, {
  required bool wantYear,
}) {
  void consider(
      RegExpMatch m, String? weekday, int? day, int? month, String? yearText) {
    if (weekday == null || day == null || month == null) return;
    if ((yearText != null) != wantYear) return;
    var year =
        yearText == null ? _nearestYear(month, day, now) : int.parse(yearText);
    if (year == null) return;
    // A date that does not exist has no weekday to disagree with, and
    // saying so is the impossible-date check's job rather than this one's.
    // Only reachable with a year written out; _nearestYear has already
    // rejected the rest.
    if (day < 1 || day > _daysInMonth(month, year)) return;

    var actual = DateTime(year, month, day).weekday;
    var written = _weekdayNumbers[weekday.toLowerCase()];
    if (written == null || written == actual) return;

    // The weekday sits at the start of the match, which is what lets its
    // range be taken without per-group offsets -- something Dart's Match
    // does not expose.
    out.add(_issue(check, m.start, m.start + weekday.length, text,
        subject: weekday,
        detail: _weekdayNames[actual],
        // The date is assumed to be the part that was looked up and the
        // weekday the part typed from memory, so the weekday is what gets
        // corrected. Stated in the explanation, because the other way round
        // is just as possible and only the writer knows.
        //
        // Capitalised whatever case was typed, unlike every other
        // correction in this file: a weekday is a proper noun, so "tuesday"
        // wants "Monday" and not "monday". Running it through matchCase
        // would be a no-op -- it only ever adds a capital -- and would read
        // as though the case were being carried over.
        suggestions: [_weekdayNames[actual]]));
  }

  for (var m in _weekdayDayFirst.allMatches(text)) {
    consider(m, m.group(1), int.tryParse(m.group(2) ?? ""),
        _monthNumbers[m.group(3)?.toLowerCase()], m.group(4));
  }
  for (var m in _weekdayMonthFirst.allMatches(text)) {
    consider(m, m.group(1), int.tryParse(m.group(3) ?? ""),
        _monthNumbers[m.group(2)?.toLowerCase()], m.group(4));
  }
}

/// _impossibleDates flags a day number the month never has.
void _impossibleDates(
    String text, AnalysisCheck check, List<WritingIssue> out, DateTime now) {
  var seen = <int>{};
  void consider(RegExpMatch m, int? day, int? month, String? yearText) {
    if (day == null || month == null) return;
    // 29 February is a real date every fourth year, so without a year
    // written out there is nothing to object to. 30 and 31 February are
    // wrong whatever the year, and still caught.
    if (yearText == null && month == 2 && day == 29) return;
    var year = yearText == null ? now.year : int.parse(yearText);
    var days = _daysInMonth(month, year);
    if (day >= 1 && day <= days) return;
    // The two patterns overlap on some text; the same slip is one finding.
    if (!seen.add(m.start)) return;
    out.add(_issue(check, m.start, m.end, text,
        subject: text.substring(m.start, m.end), detail: "$days"));
  }

  for (var m in _bareDayFirst.allMatches(text)) {
    consider(m, int.tryParse(m.group(1) ?? ""),
        _monthNumbers[m.group(2)?.toLowerCase()], m.group(3));
  }
  for (var m in _bareMonthFirst.allMatches(text)) {
    consider(m, int.tryParse(m.group(2) ?? ""),
        _monthNumbers[m.group(1)?.toLowerCase()], m.group(3));
  }
}

// --- Apostrophes -------------------------------------------------------

/// _wordApostrophe matches an apostrophe with a letter on both sides.
///
/// Word-internal only, and that restriction is the whole rule. A straight
/// quote around a quotation is not an apostrophe, and counting those would
/// report every message that quotes something as inconsistent.
final _wordApostrophe = RegExp("(?<=[A-Za-z])(['’])(?=[A-Za-z])");

/// _apostropheConsistency flags the minority apostrophe when a message uses
/// both the straight one and the curly one inside words.
///
/// Neither is wrong, which is why this is a suggestion. Both together is
/// what text pasted from two places looks like.
void _apostropheConsistency(
    String text, AnalysisCheck check, List<WritingIssue> out) {
  var straight = <int>[], curly = <int>[];
  for (var m in _wordApostrophe.allMatches(text)) {
    (m.group(1) == "'" ? straight : curly).add(m.start);
  }
  if (straight.isEmpty || curly.isEmpty) return;

  // On a tie the curly one is the odd one out: a field that substitutes
  // apostrophes produces those, so it is the one that arrived from
  // somewhere else.
  var curlyLoses = curly.length <= straight.length;
  var odd = curlyLoses ? curly : straight;
  var wanted = curlyLoses ? "'" : "’";
  for (var at in odd) {
    out.add(_issue(check, at, at + 1, text,
        subject: text[at], detail: wanted, suggestions: [wanted]));
  }
}
