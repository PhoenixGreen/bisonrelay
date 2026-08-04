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

/// Expands `$1`, `$2`, etc. in [template] with [match]'s capture groups, for
/// a grammar rule's suggested replacement.
String _expandTemplate(String template, RegExpMatch match) {
  return template.replaceAllMapped(RegExp(r'\$(\d+)'), (m) {
    var idx = int.tryParse(m.group(1)!);
    if (idx == null || idx > match.groupCount) return m.group(0)!;
    return match.group(idx) ?? '';
  });
}

/// Levenshtein (edit) distance between two strings, abandoned as soon as the
/// whole working row exceeds [max] -- a generic string algorithm with no
/// language-specific knowledge, used to rank dictionary suggestions.
///
/// The bound matters: this runs over thousands of candidates per misspelled
/// word, and almost all of them are nowhere near. Returning `max + 1` for
/// those instead of finishing the matrix is most of why a full dictionary is
/// affordable at all.
int _editDistance(String a, String b, int max) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

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
      curr[j] = v;
      if (v < rowBest) rowBest = v;
    }
    // Every later row is at least this row's minimum, so once that exceeds
    // the budget the final distance cannot come back under it.
    if (rowBest > max) return max + 1;
    var tmp = prev;
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

  // _suggestionCache memoizes by word. Every keystroke re-checks the whole
  // composer, so without it the same handful of misspellings is rescored on
  // each one; with it, only a newly typed word costs anything.
  final Map<String, List<String>> _suggestionCache = {};

  bool get hasData => _words.isNotEmpty || _rules.isNotEmpty;

  void updateData(SpellcheckData data) {
    _words = data.words.map((w) => w.toLowerCase()).toSet();

    _byLength.clear();
    _masks.clear();
    _suggestionCache.clear();
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
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
      Locale locale, String text) async {
    if (!hasData) return [];

    var spans = <SuggestionSpan>[];

    for (var rule in _rules) {
      try {
        for (var m in rule.pattern.allMatches(text)) {
          var suggestions = rule.suggest.isEmpty
              ? <String>[]
              : [_expandTemplate(rule.suggest, m)];
          spans.add(SuggestionSpan(
              TextRange(start: m.start, end: m.end), suggestions));
        }
      } catch (_) {
        // A plugin-supplied pattern that throws at match time (e.g. an
        // engine-specific construct); skip just that rule.
      }
    }

    for (var m in _wordRegExp.allMatches(text)) {
      var word = m.group(0)!;
      var lower = word.toLowerCase();
      if (_words.contains(lower)) continue;
      spans.add(SuggestionSpan(
          TextRange(start: m.start, end: m.end), _suggest(lower)));
    }

    return spans;
  }

  /// _suggest ranks the dictionary words within [maxDistance] edits of
  /// [word], nearest first.
  ///
  /// Only the candidate *set* is narrowed, never the scoring: every word the
  /// index offers is still measured exactly, so this returns what comparing
  /// against the entire dictionary would, just without doing it.
  List<String> _suggest(String word,
      {int maxSuggestions = 3, int maxDistance = 2}) {
    var cached = _suggestionCache[word];
    if (cached != null) return cached;

    var wordMask = _letterMask(word);
    var maskLimit = 2 * maxDistance;
    var scored = <MapEntry<String, int>>[];

    for (var len = word.length - maxDistance;
        len <= word.length + maxDistance;
        len++) {
      for (var candidate in _byLength[len] ?? const <String>[]) {
        if (_bitCount(wordMask ^ _masks[candidate]!) > maskLimit) continue;
        var d = _editDistance(word, candidate, maxDistance);
        if (d <= maxDistance) scored.add(MapEntry(candidate, d));
      }
    }

    scored.sort((a, b) => a.value.compareTo(b.value));
    var out = scored.take(maxSuggestions).map((e) => e.key).toList();
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
