import 'package:bruig/plugin_system/plugin_capability.dart';
import 'package:bruig/plugin_system/plugin_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';

// spellcheck.dart is the app's side of the spellcheck-data capability: it
// takes whatever words and grammar rules the enabled providers supply and
// drives Flutter's own SpellCheckService with them. It contains no
// dictionary and no writing rules of its own -- with no provider enabled,
// there is nothing to check text against and the composers get no
// configuration at all.

/// Matches a single "word" for dictionary lookup purposes: runs of letters
/// and apostrophes (so contractions like "don't" are one token).
final _wordRegExp = RegExp(r"[A-Za-z']+");

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

/// WritingIssueKind separates the two things a provider flags, because they
/// warrant different confidence: an unknown word is a fact about the
/// dictionary, whereas a style rule is a judgement that may be wrong.
enum WritingIssueKind { spelling, style }

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

  const WritingIssue({
    required this.range,
    required this.text,
    required this.message,
    required this.suggestions,
    required this.kind,
  });
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
  _CompiledRule(this.pattern, this.message, this.suggest);
}

/// A [SpellCheckService] driven entirely by capability-supplied data.
class _CapabilitySpellCheckService extends SpellCheckService {
  Set<String> _words = {};
  List<_CompiledRule> _rules = [];

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
            return _CompiledRule(RegExp(r.pattern), r.message, r.suggest);
          } catch (_) {
            // A plugin-supplied pattern Dart's regex engine can't compile;
            // skip just that rule rather than failing the whole plugin.
            return null;
          }
        })
        .whereType<_CompiledRule>()
        .toList();
  }

  @override
  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
      Locale locale, String text) async {
    if (!hasData) return [];
    return [
      for (var issue in review(text))
        SuggestionSpan(issue.range, issue.suggestions),
    ];
  }

  /// review returns every problem in [text], for a caller listing them
  /// rather than underlining them in place. Ordered by position, so the list
  /// reads in the same order as the message.
  List<WritingIssue> review(String text) {
    if (!hasData) return const [];
    var issues = <WritingIssue>[];

    for (var rule in _rules) {
      try {
        for (var m in rule.pattern.allMatches(text)) {
          issues.add(WritingIssue(
            range: TextRange(start: m.start, end: m.end),
            text: m.group(0) ?? "",
            message: rule.message,
            suggestions: rule.suggest.isEmpty
                ? const []
                : [_expandTemplate(rule.suggest, m)],
            kind: WritingIssueKind.style,
          ));
        }
      } catch (_) {
        // A provider-supplied pattern that throws at match time; skip just
        // that rule, as the inline path does.
      }
    }

    for (var m in _wordRegExp.allMatches(text)) {
      var word = m.group(0)!;
      if (_words.contains(word.toLowerCase())) continue;
      issues.add(WritingIssue(
        range: TextRange(start: m.start, end: m.end),
        text: word,
        message: "Not in dictionary",
        suggestions: _suggest(word.toLowerCase()),
        kind: WritingIssueKind.spelling,
      ));
    }

    return _ordered(issues);
  }

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
/// spellcheck data and, when one does, keeps the service fed with it. A
/// composer widget watches [configuration] and hands it straight to its
/// TextField; null means "no provider", which is exactly Flutter's own
/// "spell check off".
class SpellcheckCapability extends ChangeNotifier {
  final _CapabilitySpellCheckService _service = _CapabilitySpellCheckService();

  // _fetch is injectable so this class can be tested without a running
  // client; it is Golib.getSpellcheckData everywhere but in tests.
  final Future<SpellcheckData> Function() _fetch;

  SpellcheckCapability({Future<SpellcheckData> Function()? fetch})
      : _fetch = fetch ?? Golib.getSpellcheckData;

  bool _active = false;
  bool get active => _active;

  SpellCheckConfiguration? get configuration => _active
      ? SpellCheckConfiguration(
          spellCheckService: _service,
          misspelledTextStyle: const TextStyle(
            decoration: TextDecoration.underline,
            decorationColor: Colors.red,
            decorationStyle: TextDecorationStyle.wavy,
          ),
        )
      : null;

  /// review lists every problem a provider finds in [text] -- see
  /// WritingIssue. Empty when no provider is enabled, which is also what a
  /// clean message returns, so a caller need not distinguish them.
  List<WritingIssue> review(String text) =>
      _active ? _service.review(text) : const [];

  /// update re-reads the merged data whenever the set of enabled plugins
  /// changes. The fetch lives here rather than in PluginManagerModel so the
  /// manager never has to know this capability exists -- it only reports
  /// which capabilities are present.
  Future<void> update(PluginManagerModel plugins) async {
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

    try {
      _service.updateData(await _fetch());
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
