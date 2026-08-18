import 'package:flutter/material.dart';

// writing_issue.dart is what every part of the writing tools passes around:
// one flagged span, and the two text helpers that anything producing one
// needs.
//
// It sits at the bottom of the module and imports nothing from it, which is
// what lets the checker, the counting checks, the field and the three UIs all
// speak the same language without any of them depending on each other.

/// _typographicApostrophes are the characters a text field may put in place
/// of a typed apostrophe. macOS substitutes U+2019 as you type unless smart
/// quotes are switched off, so this is the common case rather than the
/// exotic one.
const _typographicApostrophes = ["’", "ʼ", "‘"];

/// normalizeForMatching replaces typographic apostrophes with the plain one,
/// so a contraction is matched however the field spelled it.
///
/// Reported: "I've" was flagged as a misspelling. Written with U+2019 the
/// word regex splits it into "I" and "ve", and "ve" is in no dictionary.
/// Every contraction rule a provider ships was affected the same way and more
/// quietly -- `\bdon't\b` simply never fired on real typing.
///
/// Length is preserved exactly, and that is the point: all of these are
/// single UTF-16 code units, as is the apostrophe, so every offset into the
/// normalized text is an offset into the original. The ranges this produces
/// can be handed straight back to the field, and the text the user sees is
/// never rewritten.
String normalizeForMatching(String text) {
  var out = text;
  for (var mark in _typographicApostrophes) {
    if (out.contains(mark)) out = out.replaceAll(mark, "'");
  }
  assert(out.length == text.length,
      "normalizing must not move any offset in the text");
  return out;
}

/// matchCase gives [replacement] the capitalisation of [original], so
/// replacing "Colour" at the start of a sentence does not produce "color",
/// and correcting "Dont" does not produce "don't".
///
/// One-way on purpose: it can add a capital and never take one away. The
/// rules whose whole point is to add one -- a weekday, a language, the first
/// word of a sentence -- match lowercase text and suggest the capitalised
/// form, and a two-way version would undo exactly the fix they exist for.
String matchCase(String original, String replacement) {
  if (original.isEmpty || replacement.isEmpty) return replacement;
  if (original[0] == original[0].toUpperCase() &&
      original[0] != original[0].toLowerCase()) {
    return replacement[0].toUpperCase() + replacement.substring(1);
  }
  return replacement;
}

/// WritingIssueKind separates what a provider flags by how sure it is, which
/// decides how the text is marked and which page the issue is listed on.
///
/// [spelling] and [grammar] are mistakes: text that is wrong whatever the
/// writer meant. An unknown word is a fact about the dictionary, and the
/// grammar rules are held to a standard of never firing on correct writing.
/// Both get the red underline.
///
/// [phrasing] is an opinion -- wordiness, a cliche, the passive voice, a word
/// used four times in a paragraph. These are often right and sometimes wrong,
/// and marking them like a misspelling would put the same alarming red under
/// prose that is perfectly good, which is how people learn to ignore every
/// underline including the ones that matter. They get their own colour.
///
/// [check] is a question rather than either. The text is real English and is
/// probably what was meant; it belongs to a pair people get wrong, and the
/// rules cannot tell from the sentence which one this is. "It would brake the
/// system" is the case: nothing about it is ungrammatical, and "brake" is
/// spelled correctly, so neither of the kinds above can carry it -- an error
/// rule would have to fire on "he started to brake" too, and a phrasing rule
/// would be claiming the writing could be better when the claim is that it
/// might be wrong.
///
/// The distinction earns its keep at the two ends. The error rules hold to
/// never firing on correct writing, and that standard is exactly what kept
/// most confusable pairs out of the plugin entirely -- as checks they can be
/// written at all. And a check is the only kind where "this usage is correct"
/// is a sensible answer, which is the button it gets and the others do not.
enum WritingIssueKind {
  spelling,
  grammar,
  phrasing,
  check;

  /// isMistake groups the two kinds a writer should fix from the two they
  /// should merely consider.
  bool get isMistake =>
      this == WritingIssueKind.spelling || this == WritingIssueKind.grammar;

  /// isCheck is the one kind that can be answered with "that is correct" --
  /// see [check]. Asked as a question of its own rather than by comparing
  /// against the enum at each call site, since every one of those comparisons
  /// is really asking this.
  bool get isCheck => this == WritingIssueKind.check;

  /// fromSeverity reads a provider's severity string. Anything a provider
  /// does not explicitly call a suggestion or a check is a mistake, so a
  /// provider that never heard of severity keeps the behaviour it had.
  static WritingIssueKind fromSeverity(String severity) => switch (severity) {
        "suggestion" => phrasing,
        "check" => check,
        _ => grammar,
      };
}

/// WritingIssue is one flagged span, with enough context to list it away
/// from the text it came from.
///
/// Flutter's own SuggestionSpan carries a range and replacements and nothing
/// else, which is all an inline underline needs. A panel listing every
/// problem in a message has to say what each one *is*, so this exists
/// alongside it, built from the same data.
class WritingIssue {
  final TextRange range;

  /// The offending text itself, so a list can show it without re-slicing.
  final String text;

  /// What is wrong: a provider's rule message, or a plain note for a word
  /// the dictionary doesn't have.
  final String message;

  final List<String> suggestions;
  final WritingIssueKind kind;

  /// checkId identifies the rule that produced a style issue, so it can be
  /// turned off. Null for a spelling issue, which comes from the dictionary
  /// and has no rule behind it.
  final String? checkId;

  /// A heading grouping the issue -- "Capitalization", "Spelling". Empty when
  /// the provider sent none, in which case the UI shows [message] alone.
  final String category;

  /// A sentence saying what is wrong and why, for a reader who does not
  /// already know the rule. [message] names the problem in the few words a
  /// menu row allows; this is what the popup can afford to spell out. Empty
  /// when the provider sent none.
  final String explanation;

  /// The rule's message as its provider wrote it, before the matched text
  /// was substituted into it.
  ///
  /// [message] describes this occurrence and is what the reader sees.
  /// This describes the rule, and is what names it where a rule is being
  /// switched off -- a list of disabled checks wants "Should be \"$1
  /// effect\"", which covers every determiner, not "Should be \"an
  /// effect\"", which is the one that happened to be on screen.
  ///
  /// Falls back to [message] for an issue with no rule behind it.
  final String ruleMessage;

  const WritingIssue({
    required this.range,
    required this.text,
    required this.message,
    required this.suggestions,
    required this.kind,
    this.checkId,
    this.category = "",
    this.explanation = "",
    String? ruleMessage,
  }) : ruleMessage = ruleMessage ?? message;

  /// title is what to head the issue with: the category if the provider gave
  /// one, and the message otherwise, so a rule with no category still gets a
  /// heading rather than an empty line.
  String get title => category.isNotEmpty ? category : message;
}

/// orderedForPainting sorts issues by position and drops any that overlaps
/// one already kept.
///
/// Both properties are load-bearing rather than tidiness. Flutter takes the
/// spans built from these as sorted and disjoint: it binary-searches them to
/// find the word under the cursor, and walks them in order to build the
/// styled text the underline is drawn into. Handing it an unordered or
/// overlapping list makes it find the wrong span -- so a correction splices
/// at some other word's offsets -- and corrupts the span tree, which shows up
/// as text jumping around while merely editing.
///
/// Rules are matched one at a time and words separately, so the natural order
/// of production is by rule and then by word, never by position.
///
/// Overlaps are resolved by preferring the spelling issue, except where a
/// style rule covers exactly the same characters, in which case the style
/// rule wins.
///
/// The exception is the important half, and an earlier version had only the
/// rule and not the exception. For "alot" and "i" a style rule matched the
/// identical span, and preferring spelling threw its answer away: the rule
/// knows the fix is "a lot" or "I", where a spelling suggestion is only ever
/// the nearest dictionary words -- for "alot", "allot" and "aloft".
///
/// Everywhere else spelling wins, and it has to win in both directions. A
/// repeated-word rule *contains* the misspellings inside it, and its fix
/// would merely duplicate the typo. A sentence-capital rule is *contained* by
/// the first word, one character wide, and would otherwise hide a misspelling
/// of that word behind a note about its capital.
List<WritingIssue> orderedForPainting(List<WritingIssue> issues) {
  // A style rule is preferred only when it lines up exactly with something
  // the dictionary also flagged.
  var spellingRanges = {
    for (var i in issues)
      if (i.kind == WritingIssueKind.spelling)
        "${i.range.start}:${i.range.end}",
  };
  int rank(WritingIssue i) {
    if (i.kind == WritingIssueKind.spelling) return 1;
    return spellingRanges.contains("${i.range.start}:${i.range.end}") ? 0 : 2;
  }

  issues.sort((a, b) {
    var byStart = a.range.start.compareTo(b.range.start);
    if (byStart != 0) return byStart;
    var byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    return a.range.end.compareTo(b.range.end);
  });

  var kept = <WritingIssue>[];
  var lastEnd = -1;
  for (var issue in issues) {
    if (issue.range.start < lastEnd) continue;
    kept.add(issue);
    lastEnd = issue.range.end;
  }
  return kept;
}
