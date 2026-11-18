import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bruig/plugin_system/writing_tools/engine/language/lexicon.dart';
import 'package:bruig/plugin_system/writing_tools/engine/language/token_rules.dart';
import 'package:bruig/plugin_system/writing_tools/engine/language/tokens.dart';
import 'package:bruig/plugin_system/writing_tools/engine/language/usage.dart';
import 'package:bruig/plugin_system/writing_tools/engine/writing_issue.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';

// grammar.dart is the part of the checker that reads a sentence as a
// sentence: words, what each one is, and how such words are used.
//
// Three kinds of finding come out of it, all driven by the provider's data:
//
//   - its rules over words (token_rules.dart) -- agreement, verb forms,
//     articles, and whatever else it has written;
//   - a word that the words around it make unlikely, where one it is often
//     confused with would be likely -- "a reel problem";
//   - two common words side by side that English all but never puts
//     together -- "the of", "is went".
//
// The last two are declared by the provider as analysis checks, like the
// counting checks, and for the same reason: it says how sure to be and what
// to say, and the mechanism is here.

/// The ids of the checks this file runs. Declared by the provider among its
/// analysis checks; an id it does not declare is not run.
const confusedWordCheck = "confused-word";
const confusedWordCertainCheck = "confused-word-certain";
const unusualPairCheck = "unusual-word-pair";

class _Rule {
  final TokenRule rule;
  final TokenPattern pattern;
  final List<TokenPattern> except;
  final WritingIssueKind kind;
  _Rule(this.rule, this.pattern, this.except)
      : kind = WritingIssueKind.fromSeverity(rule.severity);

  String get checkId => "token:${rule.id}";
}

final int _anywhere = UsageModel.context("u", const []);

/// _Gap is the place a word sits in, as the five contexts the provider
/// counted: both neighbours, the two words before and the two after, and
/// the one before and the one after.
class _Gap {
  final int both, twoBefore, twoAfter, before, after;
  _Gap(String l2, String l1, String r1, String r2)
      : both = UsageModel.context("M", [l1, r1]),
        twoBefore = UsageModel.context("A", [l2, l1]),
        twoAfter = UsageModel.context("B", [r1, r2]),
        before = UsageModel.context("l", [l1]),
        after = UsageModel.context("r", [r1]);
}

/// LanguageEngine holds one provider's grammar and applies it to text.
class LanguageEngine {
  final Lexicon lexicon;
  final Tokenizer tokenizer;
  final UsageModel usage;
  final List<_Rule> _rules;
  final Map<String, AnalysisCheck> _checks;

  LanguageEngine._(
      this.lexicon, this.tokenizer, this.usage, this._rules, this._checks);

  /// Builds the engine from what the provider sent, or returns null where it
  /// sent no grammar. A table that will not read is left out rather than
  /// failing the rest: the dictionary and the older rules do not depend on
  /// any of this and must not be lost to it.
  static LanguageEngine? from(SpellcheckData data) {
    var grammar = data.grammar;
    if (grammar == null || grammar.lexicon.isEmpty) return null;

    var lexiconText = "";
    try {
      lexiconText = utf8.decode(_inflate(grammar.lexicon));
    } catch (_) {
      return null;
    }
    var lexicon = Lexicon(lexiconText);
    if (lexicon.isEmpty) return null;

    var usage = UsageModel.empty;
    try {
      usage = UsageModel.parse(
        ngrams: _inflate(grammar.ngrams),
        confusionSets: grammar.confusionSets,
        pairWords: grammar.pairWords,
        pairBits: _inflate(grammar.pairBits),
      );
    } catch (_) {
      // No counts: the rules still run, and the two checks that need the
      // counts find nothing.
    }

    var classes = <String, Set<String>>{
      for (var e in grammar.classes.entries) e.key: e.value.toSet(),
    };
    var rules = <_Rule>[];
    for (var rule in grammar.rules) {
      try {
        rules.add(_Rule(
          rule,
          TokenPattern.compile(rule.pattern, classes),
          [for (var e in rule.except) TokenPattern.compile(e, classes)],
        ));
      } on FormatException {
        // A pattern this engine cannot read. Skipped, as an unreadable
        // regular expression is.
      }
    }
    return LanguageEngine._(
      lexicon,
      Tokenizer(lexicon, grammar.transitions),
      usage,
      rules,
      {for (var c in data.analysisChecks) c.id: c},
    );
  }

  /// What [word], which the dictionary does not have, should have been if it
  /// is a regular ending put on a word that does not take one: "buyed" for
  /// "bought", "childs" for "children", "gooder" for "better". Empty for a
  /// word that is not that.
  List<String> regularised(String word) {
    var out = <String>[];
    void offer(String? form) {
      if (form != null && form != word && !out.contains(form)) out.add(form);
    }

    Iterable<String> stems(String ending) sync* {
      if (!word.endsWith(ending) || word.length - ending.length < 2) return;
      var stem = word.substring(0, word.length - ending.length);
      yield stem;
      yield "${stem}e";
      // "runned": the consonant was doubled for the ending.
      if (stem.length >= 3 && stem[stem.length - 1] == stem[stem.length - 2]) {
        yield stem.substring(0, stem.length - 1);
      }
    }

    for (var stem in stems("ed")) {
      offer(lexicon.inflect(stem, Tags.vbd));
      offer(lexicon.inflect(stem, Tags.vbn));
    }
    for (var ending in const ["s", "es"]) {
      for (var stem in stems(ending)) {
        var entry = lexicon.lookup(stem);
        if (entry == null || entry.all & (1 << Tags.nn) == 0) continue;
        // Its real plural, or -- for a noun that has none -- itself:
        // "informations" is "information".
        offer(entry.forms[Tags.nns] ?? stem);
      }
    }
    for (var stem in stems("er")) {
      offer(lexicon.inflect(stem, Tags.id("JJR")));
    }
    for (var stem in stems("est")) {
      offer(lexicon.inflect(stem, Tags.id("JJS")));
    }
    return out;
  }

  static Uint8List _inflate(String base64Gzip) {
    if (base64Gzip.isEmpty) return Uint8List(0);
    return Uint8List.fromList(gzip.decode(base64.decode(base64Gzip)));
  }

  /// The patterns that would not compile, for the tests: a rule that is
  /// skipped is indistinguishable from a rule nobody wrote.
  static List<String> uncompilable(GrammarData grammar) {
    var classes = <String, Set<String>>{
      for (var e in grammar.classes.entries) e.key: e.value.toSet(),
    };
    var bad = <String>[];
    for (var rule in grammar.rules) {
      for (var pattern in [rule.pattern, ...rule.except]) {
        try {
          TokenPattern.compile(pattern, classes);
        } on FormatException catch (e) {
          bad.add("${rule.id}: ${e.message}");
        }
      }
    }
    return bad;
  }

  /// Everything this finds in [text], which is read for matching, reported
  /// against [original], which is what is on screen. The two are the same
  /// length -- see normalizeForMatching.
  List<WritingIssue> review(
      String text, String original, bool Function(String checkId) disabled) {
    var issues = <WritingIssue>[];
    for (var sentence in tokenizer.sentences(text)) {
      var before = issues.length;
      _applyRules(sentence, original, disabled, issues);
      // What a rule has already explained is not asked about again.
      var explained = [
        for (var i = before; i < issues.length; i++) issues[i].range,
      ];
      bool covered(int start, int end) =>
          explained.any((r) => r.start < end && r.end > start);
      var units = unitsOf(sentence);
      _confusedWords(sentence, units, original, disabled, covered, issues);
      _unusualPairs(sentence, units, original, disabled, covered, issues);
    }
    return issues;
  }

  void _applyRules(Sentence sentence, String original,
      bool Function(String) disabled, List<WritingIssue> issues) {
    var tokens = sentence.tokens;
    var words = <String>{for (var t in tokens) t.lower};
    for (var rule in _rules) {
      if (!rule.pattern.couldMatch(words)) continue;
      if (disabled(rule.checkId)) continue;
      var matches = rule.pattern.allMatches(tokens);
      if (matches.isEmpty) continue;
      var exceptions = [
        for (var e in rule.except) ...e.allMatches(tokens),
      ];
      for (var m in matches) {
        if (exceptions.any((e) => e.from <= m.from && e.to >= m.to)) continue;
        var message = m.expand(rule.rule.message, original, lexicon);
        // A message that cannot be filled in names nothing, and the rule
        // has no finding to make without it.
        if (message == null) continue;
        var found = original.substring(m.start, m.end);
        var answers = <String>[];
        for (var template in rule.rule.suggest) {
          var answer = m.expand(template, original, lexicon);
          if (answer == null || answer == found) continue;
          answer = matchCase(found, answer);
          if (!answers.contains(answer)) answers.add(answer);
        }
        // Every answer on offer needed a form the lexicon does not have.
        if (rule.rule.suggest.isNotEmpty && answers.isEmpty) continue;
        // The provider's rules are in order of which says it best, and two
        // marks on the same words are one too many.
        if (issues
            .any((i) => i.range.start == m.start && i.range.end == m.end)) {
          continue;
        }
        issues.add(WritingIssue(
          range: TextRange(start: m.start, end: m.end),
          text: found,
          message: message,
          suggestions: answers,
          kind: rule.kind,
          checkId: rule.checkId,
          ruleMessage: rule.rule.message,
          category: rule.rule.category,
          explanation: m.expand(rule.rule.explanation, original, lexicon) ??
              rule.rule.explanation,
        ));
      }
    }
  }

  /// Whether the sentence ends with a mark that ends sentences.
  static bool _finished(List<Token> tokens) {
    for (var i = tokens.length - 1; i >= 0; i--) {
      var t = tokens[i];
      if (t.kind != TokenKind.punctuation) return false;
      if (t.isTagged(1 << Tags.stop)) return true;
    }
    return false;
  }

  static String _at(List<Unit> units, int i) =>
      i < 0 ? "<s>" : (i >= units.length ? "</s>" : units[i].text);

  /// How many times likelier [rival] is than [typed] in the gap [around]
  /// describes, and whether that is beyond doubt.
  ///
  /// The provider keeps a context only where one word is found there far
  /// more than the other, allowing for how much commoner one of them is
  /// everywhere. So a count for the rival is already a finding, and what is
  /// weighed here is how many such findings there are and whether the word
  /// as typed has any standing of its own.
  (double, bool) _odds(String typed, String rival, _Gap around) {
    const smooth = 0.5;
    double seen(int context, String word) => usage.countIn(context, word);

    // Both neighbours at once is the whole question, where it was counted.
    var mid = seen(around.both, rival);
    var midTyped = seen(around.both, typed);
    if (mid > 0 || midTyped > 0) {
      return ((mid + smooth) / (midTyped + smooth), midTyped == 0 && mid >= 12);
    }

    // Otherwise each side on its own: the two words before, or failing that
    // the one; the two after, or the one.
    (double, double)? side(int wide, int narrow) {
      var a = seen(wide, rival), b = seen(wide, typed);
      if (a > 0 || b > 0) return (a, b);
      a = seen(narrow, rival);
      b = seen(narrow, typed);
      if (a > 0 || b > 0) return (a, b);
      return null;
    }

    var left = side(around.twoBefore, around.before);
    var right = side(around.twoAfter, around.after);
    if (left == null && right == null) return (0, false);
    var prior =
        (seen(_anywhere, rival) + smooth) / (seen(_anywhere, typed) + smooth);

    // A side is one of three things. Nothing kept: it tells the two words
    // apart no better than chance, and counts for neither. The typed word
    // kept and the rival not: this is the typed word's place, and the rival
    // has no claim. Or the rival kept, and the ratio is how strong its claim
    // is.
    double ratio((double, double)? side) {
      if (side == null) return prior;
      var (forRival, forTyped) = side;
      return forRival == 0 ? 0 : (forRival + smooth) / (forTyped + smooth);
    }

    var leftRatio = ratio(left), rightRatio = ratio(right);
    if (leftRatio == 0 || rightRatio == 0) return (0, false);
    // A word found with both its neighbours is at home, whatever else would
    // also fit: "giving you access" is not "giving your access" because
    // "your access" is the commoner pair.
    if (left != null && right != null && left.$2 >= 3 && right.$2 >= 3) {
      return (0, false);
    }
    var certain = left != null &&
        right != null &&
        left.$2 == 0 &&
        right.$2 == 0 &&
        left.$1 >= 12 &&
        right.$1 >= 12;
    return (leftRatio * rightRatio / prior, certain);
  }

  void _confusedWords(
      Sentence sentence,
      List<Unit> units,
      String original,
      bool Function(String) disabled,
      bool Function(int, int) covered,
      List<WritingIssue> issues) {
    if (!usage.hasContexts) return;
    var ask = _checks[confusedWordCheck];
    var tell = _checks[confusedWordCertainCheck];
    if (ask != null && disabled("analysis:${ask.id}")) ask = null;
    if (tell != null && disabled("analysis:${tell.id}")) tell = null;
    if (ask == null && tell == null) return;

    var tokens = sentence.tokens;
    for (var i = 0; i < units.length; i++) {
      var unit = units[i];
      var rivals = usage.rivals[unit.text];
      if (rivals == null) continue;
      var token = tokens[unit.firstToken];
      // A name is not a misspelling of the word it looks like.
      if (token.properLooking || token.allCaps) continue;
      var start = token.start, end = tokens[unit.lastToken].end;
      if (covered(start, end)) continue;

      var l1 = _at(units, i - 1), l2 = _at(units, i - 2);
      var r1 = _at(units, i + 1), r2 = _at(units, i + 2);
      // Nothing can be told from a word alone.
      if (l1 == "<s>" && r1 == "</s>") continue;
      // Nor from the last word of a sentence that has not been finished:
      // what comes after it is half of the evidence, and it has not been
      // typed yet. "It is to" is on its way to "to blame" as often as it is
      // a slip for "too".
      if (r1 == "</s>" && !_finished(tokens)) continue;

      var gap = _Gap(l2, l1, r1, r2);
      String? best;
      var bestOdds = 0.0;
      var bestAgreed = false;
      for (var rival in rivals) {
        var (odds, agreed) = _odds(unit.text, rival, gap);
        if (odds > bestOdds) {
          best = rival;
          bestOdds = odds;
          bestAgreed = agreed;
        }
      }
      if (best == null) continue;

      AnalysisCheck? check;
      if (tell != null && bestAgreed && bestOdds >= tell.threshold) {
        check = tell;
      } else if (ask != null && bestOdds >= ask.threshold) {
        check = ask;
      }
      if (check == null) continue;

      var found = original.substring(start, end);
      String fill(String s) =>
          s.replaceAll(r"$1", found).replaceAll(r"$2", best!);
      issues.add(WritingIssue(
        range: TextRange(start: start, end: end),
        text: found,
        message: fill(check.message),
        suggestions: [matchCase(found, best)],
        kind: WritingIssueKind.fromSeverity(check.severity),
        checkId: "analysis:${check.id}",
        ruleMessage: check.message,
        category: check.category,
        explanation: fill(check.explanation),
      ));
    }
  }

  void _unusualPairs(
      Sentence sentence,
      List<Unit> units,
      String original,
      bool Function(String) disabled,
      bool Function(int, int) covered,
      List<WritingIssue> issues) {
    if (!usage.hasPairs) return;
    var check = _checks[unusualPairCheck];
    if (check == null || disabled("analysis:${check.id}")) return;
    var tokens = sentence.tokens;

    for (var i = 0; i + 1 < units.length; i++) {
      var a = units[i], b = units[i + 1];
      if (a.text == b.text) continue; // The repeated-word rule's business.
      if (!usage.neverTogether(a.text, b.text)) continue;
      var first = tokens[a.firstToken], second = tokens[b.firstToken];
      if (!first.isWord || !second.isWord) continue;
      if (first.properLooking || second.properLooking) continue;
      if (first.allCaps || second.allCaps) continue;
      // Side by side in the counts' sense may still have a quote or a
      // bracket between them, and then the two are not a pairing at all.
      if (b.firstToken != a.lastToken + 1) continue;
      var start = first.start, end = tokens[b.lastToken].end;
      if (covered(start, end)) continue;
      var found = original.substring(start, end);
      issues.add(WritingIssue(
        range: TextRange(start: start, end: end),
        text: found,
        message: check.message.replaceAll(r"$1", found),
        suggestions: const [],
        kind: WritingIssueKind.fromSeverity(check.severity),
        checkId: "analysis:${check.id}",
        ruleMessage: check.message,
        category: check.category,
        explanation: check.explanation.replaceAll(r"$1", found),
      ));
    }
  }
}
