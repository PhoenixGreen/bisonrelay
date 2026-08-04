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
      curr[j] =
          [deletion, insertion, substitution].reduce((x, y) => x < y ? x : y);
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

/// A [SpellCheckService] driven entirely by capability-supplied data.
class _CapabilitySpellCheckService extends SpellCheckService {
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
