import 'package:bruig/plugin_system/capabilities/writing_analysis.dart';
import 'package:bruig/plugin_system/capabilities/writing_prefs.dart';
import 'package:bruig/plugin_system/plugin_capability.dart';
import 'package:bruig/plugin_system/plugin_manager.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';

// spellcheck.dart is the app's side of the spellcheck-data capability: it
// takes whatever words, grammar rules and analysis checks the enabled
// providers supply, and answers "what is wrong with this text". It contains
// no dictionary and no writing rules of its own -- with no provider enabled,
// review() returns nothing and the composers show no marks at all.
//
// Flutter's own SpellCheckService is deliberately not used. It carries one
// style for every flagged span, which cannot express the difference between a
// mistake and a suggestion, and it re-runs only when the text changes, which
// is the wrong trigger for a word being added to the dictionary. The painting
// is done instead by WritingTextEditingController -- see writing_field.dart.

/// Matches a single "word" for dictionary lookup purposes: runs of letters
/// and apostrophes (so contractions like "don't" are one token).
final _wordRegExp = RegExp(r"[A-Za-z']+");

/// _typographicApostrophes are the characters a text field may put in place
/// of a typed apostrophe. macOS substitutes U+2019 as you type unless smart
/// quotes are switched off, so this is the common case rather than the
/// exotic one.
const _typographicApostrophes = ["\u2019", "\u02BC", "\u2018"];

/// normalizeForMatching replaces typographic apostrophes with the plain one,
/// so a contraction is matched however the field spelled it.
///
/// Reported: "I've" was flagged as a misspelling. Written with U+2019 the
/// word regex above splits it into "I" and "ve", and "ve" is in no
/// dictionary. Every contraction rule a provider ships was affected the same
/// way and more quietly -- `\bdon't\b` simply never fired on real typing.
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

/// Expands a grammar rule's replacement template against [match]:
///
///   `$1`, `$2`   the capture group, as matched.
///   `$U1`, `$U2` the capture group with its first letter upper-cased.
///
/// The `$U` form exists for the rules whose whole point is a change of case
/// -- capitalising the start of a sentence -- which a literal template
/// cannot express, since the letter to capitalise is whatever was typed.
/// Spelled `$U1` rather than a backslash escape because these templates
/// arrive as JSON, where a backslash is already the string escape.
String _expandTemplate(String template, RegExpMatch match) {
  return template.replaceAllMapped(RegExp(r'\$(U?)(\d+)'), (m) {
    var idx = int.tryParse(m.group(2)!);
    if (idx == null || idx > match.groupCount) return m.group(0)!;
    var value = match.group(idx) ?? '';
    if (m.group(1) != 'U' || value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  });
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

/// Damerau-Levenshtein (edit) distance between two strings, abandoned as soon
/// as the whole working row exceeds [max] -- a generic string algorithm with
/// no language-specific knowledge, used to rank dictionary suggestions.
///
/// Damerau rather than plain Levenshtein because it counts a transposition
/// of adjacent characters as one typo rather than two, and transposition is
/// the commonest typing error there is -- "recieve", "teh", "thier". Scored
/// as two edits, the intended word sinks below every word that is merely one
/// substitution away, and never reaches the handful of corrections shown.
///
/// The bound matters: this runs over thousands of candidates per misspelled
/// word, and almost all of them are nowhere near. Returning `max + 1` for
/// those instead of finishing the matrix is most of why a full dictionary is
/// affordable at all.
int _editDistance(String a, String b, int max) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  // Three rows, not two: a transposition looks back two rows and two columns.
  var prevPrev = List<int>.filled(b.length + 1, 0);
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    var rowBest = i;
    for (var j = 1; j <= b.length; j++) {
      var cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = prev[j] + 1;
      if (curr[j - 1] + 1 < v) v = curr[j - 1] + 1;
      if (prev[j - 1] + cost < v) v = prev[j - 1] + cost;
      if (i > 1 &&
          j > 1 &&
          a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
        var transposed = prevPrev[j - 2] + 1;
        if (transposed < v) v = transposed;
      }
      curr[j] = v;
      if (v < rowBest) rowBest = v;
    }
    // Every later row is at least this row's minimum, so once that exceeds
    // the budget the final distance cannot come back under it.
    if (rowBest > max) return max + 1;
    var tmp = prevPrev;
    prevPrev = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length];
}

/// _touchesDigit reports whether [match] has a digit against either end.
bool _touchesDigit(String text, RegExpMatch match) {
  bool isDigit(int at) {
    if (at < 0 || at >= text.length) return false;
    var c = text.codeUnitAt(at);
    return c >= 0x30 && c <= 0x39;
  }

  return isDigit(match.start - 1) || isDigit(match.end);
}

/// _letterMask is a 26-bit set of which letters appear in [w], used to reject
/// candidates before paying for the distance matrix. A single edit changes
/// the letter *set* by at most two elements (a substitution removes one and
/// adds another), so more than `2 * maxDistance` differing letters proves the
/// words are too far apart. It is a necessary condition only -- a candidate
/// that passes still has to be measured -- so the filter can never lose a
/// suggestion, only save work.
int _letterMask(String w) {
  var mask = 0;
  for (var i = 0; i < w.length; i++) {
    var c = w.codeUnitAt(i) - 97; // 'a'
    if (c >= 0 && c < 26) mask |= 1 << c;
  }
  return mask;
}

int _bitCount(int x) {
  var n = 0;
  while (x != 0) {
    x &= x - 1;
    n++;
  }
  return n;
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
enum WritingIssueKind {
  spelling,
  grammar,
  phrasing;

  /// isMistake groups the two kinds a writer should fix from the one they
  /// should merely consider.
  bool get isMistake => this != WritingIssueKind.phrasing;
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

/// _compileAll turns a provider's antipattern sources into matchers, keeping
/// whichever compile.
List<RegExp> _compileAll(List<String> sources) {
  var out = <RegExp>[];
  for (var source in sources) {
    try {
      out.add(RegExp(source));
    } catch (_) {
      // An exception this engine cannot read. The rule still runs, which is
      // the safer of the two failures.
    }
  }
  return out;
}

/// _Candidate is one possible correction, with the two numbers it is ordered
/// by: how far it is from what was typed, and how common a word it is.
class _Candidate {
  final String word;
  final int distance;
  final int commonRank;
  const _Candidate(this.word, this.distance, this.commonRank);
}

class _CompiledRule {
  final RegExp pattern;
  final String message;
  final String suggest;
  // source is the pattern as the provider wrote it, which is how a rule is
  // identified when the user turns it off -- see WritingPreferences.
  final String source;
  final String category;
  final String explanation;
  final WritingIssueKind kind;

  /// antipatterns suppress this rule where they match over it. Compiled
  /// alongside the pattern, and an uncompilable one is dropped rather than
  /// taking the rule with it -- losing an exception makes a rule noisier,
  /// which is recoverable; losing the rule makes it silent, which is not
  /// obvious to anybody.
  final List<RegExp> antipatterns;

  _CompiledRule(this.pattern, this.message, this.suggest, this.source,
      this.category, this.explanation, this.kind, this.antipatterns);
}

/// _Checker is the whole checking engine, driven entirely by
/// capability-supplied data.
class _Checker {
  Set<String> _words = {};
  List<_CompiledRule> _rules = [];
  List<AnalysisCheck> _analysis = [];

  // _byLength indexes the dictionary by word length, and _masks caches each
  // word's letter set. Together they cut the candidates a misspelling is
  // measured against from the whole dictionary to a few hundred. Built once
  // per data load, which is rare; a real dictionary is ~120k words and takes
  // roughly 20ms.
  final Map<int, List<String>> _byLength = {};
  final Map<String, int> _masks = {};

  // _commonRank maps a word to its position in the provider's most-common
  // list; absent means "not common". It is what breaks the ties edit distance
  // leaves behind -- see _suggest.
  final Map<String, int> _commonRank = {};

  // _suggestionCache memoizes by word. Every keystroke re-checks the whole
  // composer, so without it the same handful of misspellings is rescored on
  // each one; with it, only a newly typed word costs anything.
  final Map<String, List<String>> _suggestionCache = {};

  /// prefs is what the user has chosen not to be told about. Null until the
  /// capability supplies it, which it does before any text is checked.
  WritingPreferences? prefs;

  bool get hasData => _words.isNotEmpty || _rules.isNotEmpty;

  void updateData(SpellcheckData data) {
    _words = data.words.map((w) => w.toLowerCase()).toSet();

    _byLength.clear();
    _masks.clear();
    _commonRank.clear();
    _suggestionCache.clear();
    for (var i = 0; i < data.commonWords.length; i++) {
      // First occurrence wins: merged lists from several providers are
      // concatenated, so an earlier provider's ranking takes precedence.
      _commonRank.putIfAbsent(data.commonWords[i].toLowerCase(), () => i);
    }
    for (var w in _words) {
      (_byLength[w.length] ??= []).add(w);
      _masks[w] = _letterMask(w);
    }
    _rules = data.grammarRules
        .map((r) {
          try {
            return _CompiledRule(
                RegExp(r.pattern),
                r.message,
                r.suggest,
                r.pattern,
                r.category,
                r.explanation,
                // Anything a provider does not explicitly call a suggestion
                // is a mistake, so a provider that never heard of severity
                // keeps the behaviour it had.
                r.severity == "suggestion"
                    ? WritingIssueKind.phrasing
                    : WritingIssueKind.grammar,
                _compileAll(r.antipatterns));
          } catch (_) {
            // A plugin-supplied pattern Dart's regex engine can't compile;
            // skip just that rule rather than failing the whole plugin.
            return null;
          }
        })
        .whereType<_CompiledRule>()
        .toList();
    _analysis = data.analysisChecks;
  }

  /// review returns every problem in [text], ordered by position so a list
  /// reads in the same order as the message.
  ///
  /// Mistakes and suggestions are de-overlapped separately and then merged,
  /// rather than competing with each other. They have to be disjoint within
  /// each group, because each group is painted as one run of decorations --
  /// but a suggestion and a mistake are painted differently and may overlap
  /// freely. Making them compete would have been actively wrong: a
  /// long-sentence suggestion covers a whole sentence and would have
  /// swallowed every misspelling inside it.
  List<WritingIssue> review(String text) {
    var raw = _reviewRaw(text);
    var merged = [
      ..._ordered(raw.where((i) => i.kind.isMistake).toList()),
      ..._ordered(raw.where((i) => !i.kind.isMistake).toList()),
    ];
    merged.sort((a, b) => a.range.start.compareTo(b.range.start));
    return merged;
  }

  /// _reviewRaw finds everything, in no particular order.
  List<WritingIssue> _reviewRaw(String original) {
    if (!hasData) return const [];
    // Matched against the normalized text and reported against the original.
    // The two are the same length, so the ranges are interchangeable -- see
    // normalizeForMatching.
    var text = normalizeForMatching(original);
    var issues = <WritingIssue>[];

    for (var rule in _rules) {
      if (prefs?.isCheckDisabled(rule.source) ?? false) continue;
      try {
        // Where this rule is not to fire, computed once for the whole text
        // rather than per match.
        var exceptions = <TextRange>[
          for (var antipattern in rule.antipatterns)
            for (var m in antipattern.allMatches(text))
              TextRange(start: m.start, end: m.end),
        ];

        for (var m in rule.pattern.allMatches(text)) {
          // Contained, not merely overlapping. An exception describes a
          // longer reading that the match is part of -- "my self" inside
          // "my self-esteem" -- so a pattern that happens to clip the edge
          // of one is not that reading and should still be flagged.
          if (exceptions.any((e) => e.start <= m.start && e.end >= m.end)) {
            continue;
          }
          issues.add(WritingIssue(
            range: TextRange(start: m.start, end: m.end),
            // Sliced from the original, not from what was matched: this is
            // what gets spliced back into the field and what a correction is
            // checked against, so it has to be the characters actually there.
            text: original.substring(m.start, m.end),
            // Expanded, like the replacement beside it. A message reading
            // `Should be "$1 effect"` is a template that was never filled
            // in, and it was shown to the reader exactly like that.
            message: _expandTemplate(rule.message, m),
            // Case carried across from what was matched. The rules key on a
            // literal word -- "dont", "alot", "your welcome" -- and each
            // accepts either case in its first letter, because the mistake
            // is commonest at the start of a sentence, which is precisely
            // where the fix must not hand back a lowercase word.
            suggestions: rule.suggest.isEmpty
                ? const []
                : [
                    matchCase(original.substring(m.start, m.end),
                        _expandTemplate(rule.suggest, m))
                  ],
            kind: rule.kind,
            checkId: rule.source,
            // The message as the provider wrote it. Turning a rule off
            // names it in Settings, and the rule is the whole pattern
            // rather than the one phrase that happened to trip it --
            // "Should be \"$1 effect\"" covers a, an, the, this and five
            // more, and listing it as "Should be \"an effect\"" would
            // describe a rule narrower than the one being switched off.
            ruleMessage: rule.message,
            category: rule.category,
            explanation: _expandTemplate(rule.explanation, m),
          ));
        }
      } catch (_) {
        // A provider-supplied pattern that throws at match time; skip just
        // that rule, as the inline path does.
      }
    }

    // Given the original: these checks count and compare rather than match
    // contractions, and their results are spliced back into the field.
    issues.addAll(runAnalysisChecks(original, _analysis,
        isIgnoredCheck: (id) => prefs?.isCheckDisabled(id) ?? false));

    for (var m in _wordRegExp.allMatches(text)) {
      // A run of letters welded to a digit is not a word the dictionary can
      // rule on: the "th" in "12th", the "st" in "1st", the "v" in "v1.2.3",
      // the "MP" in "MP3". Each of those was flagged, and the ordinal
      // suffixes especially, because the wordlist drops two-letter entries
      // that are not common words -- which is what lets "th" be offered
      // "the" when it stands alone.
      if (_touchesDigit(text, m)) continue;

      var word = m.group(0)!;
      if (_words.contains(word.toLowerCase())) continue;
      if (prefs?.isIgnoredWord(word) ?? false) continue;
      issues.add(WritingIssue(
        range: TextRange(start: m.start, end: m.end),
        text: original.substring(m.start, m.end),
        message: "Not in dictionary",
        suggestions: _suggest(word.toLowerCase()),
        kind: WritingIssueKind.spelling,
        category: "Spelling",
        explanation: "This word is not in the dictionary. It may be a typo, "
            "or a name or term the dictionary does not cover -- in which "
            "case you can add it.",
      ));
    }

    // Dismissed phrases are dropped here rather than inside each producer
    // above, because the grammar rules and the counting checks arrive by
    // completely different routes and this is the one point they have both
    // already passed. Spelling issues carry no checkId and are unaffected --
    // those have their own two ways out.
    var dismissed = prefs;
    if (dismissed != null) {
      issues.removeWhere((i) => dismissed.isIgnoredMatch(i.checkId, i.text));
    }

    issues.sort((a, b) => a.range.start.compareTo(b.range.start));
    return issues;
  }

  /// issuesAt is everything wrong with the text between [start] and [end],
  /// overlaps included.
  ///
  /// review() deliberately drops overlapping issues, because the inline
  /// underlines have to be disjoint. A menu opened on one word wants the
  /// opposite: if a word is both misspelled and caught by a style rule, or
  /// by two style rules, all of them should be on offer at once rather than
  /// appearing one at a time as each is fixed.
  List<WritingIssue> issuesAt(String text, int start, int end) => [
        for (var issue in _reviewRaw(text))
          if (issue.range.start < end && issue.range.end > start) issue,
      ];

  /// _ordered sorts issues by position and drops any that overlaps one
  /// already kept.
  ///
  /// Both properties are load-bearing rather than tidiness. Flutter takes the
  /// spans built from these as sorted and disjoint: it binary-searches them
  /// to find the word under the cursor, and walks them in order to build the
  /// styled text the underline is drawn into. Handing it an unordered or
  /// overlapping list makes it find the wrong span -- so a correction splices
  /// at some other word's offsets -- and corrupts the span tree, which shows
  /// up as text jumping around while merely editing.
  ///
  /// Rules are matched one at a time and words separately, so the natural
  /// order of production is by rule and then by word, never by position.
  ///
  /// Overlaps are resolved by preferring the spelling issue, except where a
  /// style rule covers exactly the same characters, in which case the style
  /// rule wins.
  ///
  /// The exception is the important half, and an earlier version had only
  /// the rule and not the exception. For "alot" and "i" a style rule matched
  /// the identical span, and preferring spelling threw its answer away: the
  /// rule knows the fix is "a lot" or "I", where a spelling suggestion is
  /// only ever the nearest dictionary words -- for "alot", "allot" and
  /// "aloft".
  ///
  /// Everywhere else spelling wins, and it has to win in both directions.
  /// A repeated-word rule *contains* the misspellings inside it, and its fix
  /// would merely duplicate the typo. A sentence-capital rule is *contained*
  /// by the first word, one character wide, and would otherwise hide a
  /// misspelling of that word behind a note about its capital.
  static List<WritingIssue> _ordered(List<WritingIssue> issues) {
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

  /// _suggest ranks the dictionary words within [maxDistance] edits of
  /// [word]: nearest first, and among equally near ones, commonest first.
  ///
  /// The second half matters as much as the first. A short typo is one edit
  /// from a dozen words -- "teh" reaches "the", "tech", "meh", "th" and "te"
  /// alike -- and with distance alone deciding, which of them surfaces is
  /// arbitrary, so the intended word is as likely to be missing as not.
  /// Ordering ties by how common a word is puts the one somebody plausibly
  /// meant at the top. Words the provider ranked at all come before words it
  /// didn't.
  ///
  /// Only the candidate *set* is narrowed, never the scoring: every word the
  /// index offers is still measured exactly, so this returns what comparing
  /// against the entire dictionary would, just without doing it.
  List<String> _suggest(String word,
      {int maxSuggestions = 5, int maxDistance = 2}) {
    var cached = _suggestionCache[word];
    if (cached != null) return cached;

    var wordMask = _letterMask(word);
    var maskLimit = 2 * maxDistance;
    // Rank beyond any real one, for words the provider left unranked.
    var unranked = _commonRank.length + 1;
    var scored = <_Candidate>[];

    for (var len = word.length - maxDistance;
        len <= word.length + maxDistance;
        len++) {
      for (var candidate in _byLength[len] ?? const <String>[]) {
        if (_bitCount(wordMask ^ _masks[candidate]!) > maskLimit) continue;
        var d = _editDistance(word, candidate, maxDistance);
        if (d <= maxDistance) {
          scored.add(
              _Candidate(candidate, d, _commonRank[candidate] ?? unranked));
        }
      }
    }

    scored.sort((a, b) {
      var byDistance = a.distance.compareTo(b.distance);
      if (byDistance != 0) return byDistance;
      return a.commonRank.compareTo(b.commonRank);
    });
    var out = scored.take(maxSuggestions).map((c) => c.word).toList();
    _suggestionCache[word] = out;
    return out;
  }
}

/// SpellcheckCapability tracks whether any plugin currently provides
/// spellcheck data and, when one does, keeps the checker fed with it.
///
/// A composer does not read this directly. It gives its TextField a
/// [WritingTextEditingController], which asks this what is wrong with the
/// text as it paints -- see writing_field.dart. With no provider enabled the
/// answer is always nothing, and the field looks exactly as it would without
/// the feature.
class SpellcheckCapability extends ChangeNotifier {
  final _Checker _checker = _Checker();

  // _fetch is injectable so this class can be tested without a running
  // client; it is Golib.getSpellcheckData everywhere but in tests.
  final Future<SpellcheckData> Function(String language) _fetch;

  /// preferences is the user's own overrides -- ignored words, disabled
  /// checks, and the session on/off switch. Owned here so every consumer of
  /// the capability sees the same set.
  final WritingPreferences preferences;

  SpellcheckCapability(
      {Future<SpellcheckData> Function(String language)? fetch,
      WritingPreferences? prefs})
      : _fetch = fetch ?? Golib.getSpellcheckData,
        preferences = prefs ?? WritingPreferences() {
    _checker.prefs = preferences;
    // Re-checking is what makes an ignored word disappear from the text
    // immediately rather than at the next keystroke.
    preferences.addListener(_onPreferencesChanged);
  }

  @override
  void dispose() {
    preferences.removeListener(_onPreferencesChanged);
    super.dispose();
  }

  bool _active = false;
  bool get active => _active;

  /// _onPreferencesChanged re-reads the dictionary when the language
  /// changes, and otherwise just re-checks the text.
  ///
  /// The whole word list changes with the language -- "colour" is in one and
  /// "color" in the other -- so this is a fetch and not a filter.
  void _onPreferencesChanged() {
    _invalidate();
    var plugins = _plugins;
    if (plugins != null && preferences.language != _loadedFor) {
      update(plugins);
    }
  }

  // The last review, kept because the field asks for it on every repaint --
  // every keystroke, and every movement of the caret. Recomputing a long post
  // each time a cursor moves is work for nothing.
  //
  // Keyed on the text alone, and thrown away whenever anything else that
  // could change the answer does: new data, or a change to the preferences.
  String? _reviewedText;
  List<WritingIssue>? _reviewed;

  void _invalidate() {
    _reviewedText = null;
    _reviewed = null;
    notifyListeners();
  }

  /// languages is every language the enabled providers can check against,
  /// for a UI offering the choice. Empty until data has been loaded, and
  /// empty from a provider that serves only one.
  List<SpellcheckLanguage> get languages => _languages;
  List<SpellcheckLanguage> _languages = const [];

  /// activeLanguage is the language actually loaded, which is not always the
  /// one asked for: a provider without it answers in what it has.
  String get activeLanguage => _activeLanguage;
  String _activeLanguage = "";

  // The language the loaded data was fetched for, so a preference change is
  // noticed even though nothing else about the plugin set has moved.
  String? _loadedFor;
  PluginManagerModel? _plugins;

  /// styleFor is how a flagged span is marked in the text.
  ///
  /// Red for a mistake and blue for a suggestion, which is the distinction
  /// the whole severity contract exists to draw. A wordiness rule marked like
  /// a misspelling would put an alarming red wave under prose that is
  /// perfectly good, and the reader who learns to ignore that mark ignores it
  /// over the misspellings too.
  static TextStyle styleFor(WritingIssueKind kind) => TextStyle(
        decoration: TextDecoration.underline,
        decorationColor: kind.isMistake ? Colors.red : const Color(0xFF3B82F6),
        decorationStyle: TextDecorationStyle.wavy,
        // Thick enough to survive being selected. The underline is not
        // removed by a selection, but the selection highlight is painted
        // across the same pixels, and a hairline wave washes out under it to
        // the point of looking as though the flag had gone.
        decorationThickness: 2,
      );

  /// review lists every problem a provider finds in [text] -- see
  /// WritingIssue. Empty when no provider is enabled, which is also what a
  /// clean message returns, so a caller need not distinguish them.
  List<WritingIssue> review(String text) {
    if (!_active || !preferences.enabled) return const [];
    if (_reviewedText == text) return _reviewed!;
    var issues = _checker.review(text);
    _reviewedText = text;
    _reviewed = issues;
    return issues;
  }

  /// issuesAt is everything wrong with one stretch of text -- see the
  /// checker's own note on why this differs from review().
  List<WritingIssue> issuesAt(String text, int start, int end) =>
      _active && preferences.enabled
          ? _checker.issuesAt(text, start, end)
          : const [];

  /// update re-reads the merged data whenever the set of enabled plugins
  /// changes. The fetch lives here rather than in PluginManagerModel so the
  /// manager never has to know this capability exists -- it only reports
  /// which capabilities are present.
  Future<void> update(PluginManagerModel plugins) async {
    // Kept so a language change can re-fetch without the plugin set having
    // moved; update() is otherwise only called when it has.
    _plugins = plugins;
    var active = plugins.hasCapability(PluginCapability.spellcheckData);

    // Flip `active` BEFORE awaiting the data, never after. This runs from a
    // ChangeNotifierProxyProvider's update, i.e. part-way through the build
    // of the composer that is about to read `configuration` -- so anything
    // set after an await lands too late for that build, and the composer
    // hands its TextField a null configuration (Flutter's "spell check
    // off") for the rest of its life. Only the word list can arrive late;
    // whether the feature exists at all cannot.
    if (active != _active) {
      _active = active;
      notifyListeners();
    }
    if (!active) return;

    var language = preferences.language;
    try {
      var data = await _fetch(language);
      _loadedFor = language;
      _activeLanguage = data.language;
      if (data.languages.isNotEmpty) _languages = data.languages;
      _checker.updateData(data);
      _reviewedText = null;
      _reviewed = null;
      // The words landing is a second, later change: a composer built in
      // the meantime is showing an active-but-empty checker and needs to
      // re-run it now there is something to check against.
      notifyListeners();
    } catch (exception) {
      // A provider still loading; keep whatever data we already had rather
      // than dropping spell check entirely mid-session.
      debugPrint("Unable to load spellcheck data: $exception");
    }
  }
}
