import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:golib_plugin/definitions.dart';

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

/// Levenshtein (edit) distance between two strings -- a generic string
/// algorithm with no language-specific knowledge, used to rank dictionary
/// suggestions for a misspelled word.
int _editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    for (var j = 1; j <= b.length; j++) {
      var cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var deletion = prev[j] + 1;
      var insertion = curr[j - 1] + 1;
      var substitution = prev[j - 1] + cost;
      curr[j] = [deletion, insertion, substitution].reduce((x, y) => x < y ? x : y);
    }
    var tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length];
}

class _CompiledRule {
  final RegExp pattern;
  final String message;
  final String suggest;
  _CompiledRule(this.pattern, this.message, this.suggest);
}

/// A [SpellCheckService] driven entirely by whatever a spellcheck-capability
/// plugin supplies (see [PluginsModel.spellcheckActive]/[SpellcheckData]).
/// Contains no hardcoded words or writing rules of its own: delete the
/// plugin, and this service has nothing left to check text against.
class PluginSpellCheckService extends SpellCheckService {
  Set<String> _words = {};
  List<_CompiledRule> _rules = [];

  bool get hasData => _words.isNotEmpty || _rules.isNotEmpty;

  void updateData(SpellcheckData data) {
    _words = data.words.map((w) => w.toLowerCase()).toSet();
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
          var suggestions =
              rule.suggest.isEmpty ? <String>[] : [_expandTemplate(rule.suggest, m)];
          spans.add(SuggestionSpan(TextRange(start: m.start, end: m.end), suggestions));
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

  List<String> _suggest(String word,
      {int maxSuggestions = 3, int maxDistance = 2}) {
    var scored = <MapEntry<String, int>>[];
    for (var candidate in _words) {
      if ((candidate.length - word.length).abs() > maxDistance) continue;
      var d = _editDistance(word, candidate);
      if (d <= maxDistance) scored.add(MapEntry(candidate, d));
    }
    scored.sort((a, b) => a.value.compareTo(b.value));
    return scored.take(maxSuggestions).map((e) => e.key).toList();
  }
}

/// Reactively wires [PluginSpellCheckService] to whichever spellcheck
/// plugin is currently enabled (see main.dart's ChangeNotifierProxyProvider
/// on PluginsModel), so composer widgets can just watch [configuration]
/// without knowing anything about plugins themselves.
class SpellCheckModel extends ChangeNotifier {
  final PluginSpellCheckService _service = PluginSpellCheckService();
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

  void update(bool active, SpellcheckData data) {
    if (active) _service.updateData(data);
    if (active == _active) return;
    _active = active;
    notifyListeners();
  }
}
