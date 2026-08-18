import 'package:bruig/plugin_system/writing_tools/engine/analysis.dart';
import 'package:bruig/plugin_system/writing_tools/engine/preferences.dart';
import 'package:bruig/plugin_system/writing_tools/engine/suggester.dart';
import 'package:bruig/plugin_system/writing_tools/engine/writing_issue.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';

// checker.dart is the whole checking engine, driven entirely by
// capability-supplied data. It contains no dictionary and no writing rules of
// its own -- with no provider enabled, review() returns nothing and the
// composers show no marks at all.
//
// The three sources of a finding meet here and nowhere else: the provider's
// regex rules, the counting checks under checks/, and the dictionary. Each
// arrives by a completely different route, and this is the one point they have
// all passed -- which is why the user's own dismissals are applied here rather
// than inside each producer.
//
// Nothing in this file touches Flutter beyond TextRange. It is a pure function
// from text to findings, which is what makes it testable without a widget
// tree; SpellcheckCapability wraps it in the plumbing that has to know about
// the running client.

/// _wordRegExp matches a single "word" for dictionary lookup purposes: runs of
/// letters and apostrophes, so contractions like "don't" are one token.
final _wordRegExp = RegExp(r"[A-Za-z']+");

/// _touchesDigit reports whether [match] has a digit against either end.
bool _touchesDigit(String text, RegExpMatch match) {
  bool isDigit(int at) {
    if (at < 0 || at >= text.length) return false;
    var c = text.codeUnitAt(at);
    return c >= 0x30 && c <= 0x39;
  }

  return isDigit(match.start - 1) || isDigit(match.end);
}

/// _expandTemplate expands a grammar rule's replacement template against
/// [match]:
///
///   `$1`, `$2`   the capture group, as matched.
///   `$U1`, `$U2` the capture group with its first letter upper-cased.
///
/// The `$U` form exists for the rules whose whole point is a change of case
/// -- capitalising the start of a sentence -- which a literal template cannot
/// express, since the letter to capitalise is whatever was typed. Spelled `$U1`
/// rather than a backslash escape because these templates arrive as JSON, where
/// a backslash is already the string escape.
String _expandTemplate(String template, RegExpMatch match) {
  return template.replaceAllMapped(RegExp(r'\$(U?)(\d+)'), (m) {
    var idx = int.tryParse(m.group(2)!);
    if (idx == null || idx > match.groupCount) return m.group(0)!;
    var value = match.group(idx) ?? '';
    if (m.group(1) != 'U' || value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  });
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

/// _CompiledRule is one provider rule, ready to match.
class _CompiledRule {
  final RegExp pattern;
  final String message;
  final String suggest;

  /// source is the pattern as the provider wrote it, which is how a rule is
  /// identified when the user turns it off -- see WritingPreferences.
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

  const _CompiledRule({
    required this.pattern,
    required this.message,
    required this.suggest,
    required this.source,
    required this.category,
    required this.explanation,
    required this.kind,
    required this.antipatterns,
  });

  /// compile returns null for a pattern Dart's regex engine cannot read, so
  /// one bad rule is skipped rather than failing the whole provider.
  static _CompiledRule? compile(GrammarRule rule) {
    try {
      return _CompiledRule(
        pattern: RegExp(rule.pattern),
        message: rule.message,
        suggest: rule.suggest,
        source: rule.pattern,
        category: rule.category,
        explanation: rule.explanation,
        kind: WritingIssueKind.fromSeverity(rule.severity),
        antipatterns: _compileAll(rule.antipatterns),
      );
    } catch (_) {
      return null;
    }
  }
}

/// WritingChecker answers "what is wrong with this text" from whatever words,
/// grammar rules and analysis checks the enabled providers have supplied.
class WritingChecker {
  Set<String> _words = {};
  List<_CompiledRule> _rules = [];
  List<AnalysisCheck> _analysis = [];
  final Suggester _suggester = Suggester();

  /// prefs is what the user has chosen not to be told about. Null until the
  /// capability supplies it, which it does before any text is checked.
  WritingPreferences? prefs;

  bool get hasData => _words.isNotEmpty || _rules.isNotEmpty;

  void updateData(SpellcheckData data) {
    _words = data.words.map((w) => w.toLowerCase()).toSet();
    _suggester.index(_words, data.commonWords);
    _rules = data.grammarRules
        .map(_CompiledRule.compile)
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
  /// long-sentence suggestion covers a whole sentence and would have swallowed
  /// every misspelling inside it.
  List<WritingIssue> review(String text) {
    var raw = _reviewRaw(text);
    var merged = [
      ...orderedForPainting(raw.where((i) => i.kind.isMistake).toList()),
      ...orderedForPainting(raw.where((i) => !i.kind.isMistake).toList()),
    ];
    merged.sort((a, b) => a.range.start.compareTo(b.range.start));
    return merged;
  }

  /// issuesAt is everything wrong with the text between [start] and [end],
  /// overlaps included.
  ///
  /// review() deliberately drops overlapping issues, because the inline
  /// underlines have to be disjoint. A menu opened on one word wants the
  /// opposite: if a word is both misspelled and caught by a style rule, or by
  /// two style rules, all of them should be on offer at once rather than
  /// appearing one at a time as each is fixed.
  List<WritingIssue> issuesAt(String text, int start, int end) => [
        for (var issue in _reviewRaw(text))
          if (issue.range.start < end && issue.range.end > start) issue,
      ];

  /// _reviewRaw finds everything, in no particular order.
  List<WritingIssue> _reviewRaw(String original) {
    if (!hasData) return const [];
    // Matched against the normalized text and reported against the original.
    // The two are the same length, so the ranges are interchangeable -- see
    // normalizeForMatching.
    var text = normalizeForMatching(original);
    var issues = <WritingIssue>[];

    for (var rule in _rules) {
      _applyRule(rule, text, original, issues);
    }

    // Given the original: these checks count and compare rather than match
    // contractions, and their results are spliced back into the field.
    issues.addAll(runAnalysisChecks(original, _analysis,
        isIgnoredCheck: (id) => prefs?.isCheckDisabled(id) ?? false));

    _checkSpelling(text, original, issues);

    // Dismissed phrases are dropped here rather than inside each producer
    // above, because the grammar rules and the counting checks arrive by
    // completely different routes and this is the one point they have both
    // already passed. Spelling issues carry no checkId and are unaffected --
    // those have their own two ways out.
    //
    // Accepted usages are dropped in the same pass. Those are permanent and
    // come from a check's "Correct Usage", where an ignore is for the session
    // -- but both are the same question at this point, which is whether the
    // user has already answered this rule about this phrase.
    var dismissed = prefs;
    if (dismissed != null) {
      issues.removeWhere((i) =>
          dismissed.isIgnoredMatch(i.checkId, i.text) ||
          dismissed.isAcceptedUsage(i.checkId, i.text));
    }

    issues.sort((a, b) => a.range.start.compareTo(b.range.start));
    return issues;
  }

  /// _applyRule runs one provider rule over the whole text.
  void _applyRule(_CompiledRule rule, String text, String original,
      List<WritingIssue> issues) {
    if (prefs?.isCheckDisabled(rule.source) ?? false) return;
    try {
      // Where this rule is not to fire, computed once for the whole text
      // rather than per match.
      var exceptions = <TextRange>[
        for (var antipattern in rule.antipatterns)
          for (var m in antipattern.allMatches(text))
            TextRange(start: m.start, end: m.end),
      ];

      for (var m in rule.pattern.allMatches(text)) {
        // Contained, not merely overlapping. An exception describes a longer
        // reading that the match is part of -- "my self" inside "my
        // self-esteem" -- so a pattern that happens to clip the edge of one is
        // not that reading and should still be flagged.
        if (exceptions.any((e) => e.start <= m.start && e.end >= m.end)) {
          continue;
        }
        // Sliced from the original, not from what was matched: this is what
        // gets spliced back into the field and what a correction is checked
        // against, so it has to be the characters actually there.
        var found = original.substring(m.start, m.end);
        issues.add(WritingIssue(
          range: TextRange(start: m.start, end: m.end),
          text: found,
          // Expanded, like the replacement beside it. A message reading
          // `Should be "$1 effect"` is a template that was never filled in,
          // and it was shown to the reader exactly like that.
          message: _expandTemplate(rule.message, m),
          // Case carried across from what was matched. The rules key on a
          // literal word -- "dont", "alot", "your welcome" -- and each accepts
          // either case in its first letter, because the mistake is commonest
          // at the start of a sentence, which is precisely where the fix must
          // not hand back a lowercase word.
          suggestions: rule.suggest.isEmpty
              ? const []
              : [matchCase(found, _expandTemplate(rule.suggest, m))],
          kind: rule.kind,
          checkId: rule.source,
          // The message as the provider wrote it. Turning a rule off names it
          // in Settings, and the rule is the whole pattern rather than the one
          // phrase that happened to trip it -- "Should be \"$1 effect\""
          // covers a, an, the, this and five more, and listing it as "Should
          // be \"an effect\"" would describe a rule narrower than the one
          // being switched off.
          ruleMessage: rule.message,
          category: rule.category,
          explanation: _expandTemplate(rule.explanation, m),
        ));
      }
    } catch (_) {
      // A provider-supplied pattern that throws at match time; skip just that
      // rule, as compiling does.
    }
  }

  /// _checkSpelling flags every word the dictionary does not have.
  void _checkSpelling(
      String text, String original, List<WritingIssue> issues) {
    for (var m in _wordRegExp.allMatches(text)) {
      // A run of letters welded to a digit is not a word the dictionary can
      // rule on: the "th" in "12th", the "st" in "1st", the "v" in "v1.2.3",
      // the "MP" in "MP3". Each of those was flagged, and the ordinal suffixes
      // especially, because the wordlist drops two-letter entries that are not
      // common words -- which is what lets "th" be offered "the" when it
      // stands alone.
      if (_touchesDigit(text, m)) continue;

      var word = m.group(0)!;
      if (_words.contains(word.toLowerCase())) continue;
      if (prefs?.isIgnoredWord(word) ?? false) continue;
      var found = original.substring(m.start, m.end);
      issues.add(WritingIssue(
        range: TextRange(start: m.start, end: m.end),
        text: found,
        message: "Not in dictionary",
        // Case carried across, as it is for the rule corrections. The wordlist
        // is lowercased when it is built, so every suggestion comes back
        // lowercase whatever was typed -- which meant correcting a misspelling
        // that opened a sentence quietly removed its capital.
        suggestions: [
          for (var suggestion in _suggester.suggest(word.toLowerCase()))
            matchCase(found, suggestion)
        ],
        kind: WritingIssueKind.spelling,
        category: "Spelling",
        explanation: "This word is not in the dictionary. It may be a typo, "
            "or a name or term the dictionary does not cover -- in which "
            "case you can add it.",
      ));
    }
  }
}
