import 'package:bruig/plugin_system/plugin_capability.dart';
import 'package:bruig/plugin_system/plugin_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';

// thesaurus.dart is the app's side of the thesaurus capability. Unlike
// spellcheck, which is handed its whole dataset once, this one asks a
// question at a time: a thesaurus is far too large to push across, so the
// provider keeps it and answers lookups.

/// ThesaurusCapability answers word lookups from whichever plugin currently
/// provides them, or reports that nothing does.
///
/// It is a plain model rather than a ChangeNotifier: nothing watches it, and
/// a lookup is a one-off request answered into a menu. Whether the capability
/// exists at all is read from [PluginManagerModel] at the moment of asking,
/// so enabling or removing a provider takes effect immediately without this
/// having to track it.
class ThesaurusCapability {
  final PluginManagerModel _plugins;

  // _fetch is injectable so this class can be tested without a running
  // client; it is Golib.lookupSynonyms everywhere but in tests.
  final Future<ThesaurusEntry?> Function(String word) _fetch;

  ThesaurusCapability(this._plugins,
      {Future<ThesaurusEntry?> Function(String word)? fetch})
      : _fetch = fetch ?? Golib.lookupSynonyms;

  /// _cache holds recent lookups. Someone comparing options tends to reopen
  /// the same menu several times, and the answer cannot change while a
  /// provider stays enabled.
  final Map<String, ThesaurusEntry?> _cache = {};

  /// available reports whether any enabled plugin provides a thesaurus, so a
  /// caller can leave its control out entirely rather than offering one that
  /// always comes back empty.
  bool get available => _plugins.hasCapability(PluginCapability.thesaurus);

  /// lookUp returns what a provider knows about [word], or null when none is
  /// enabled, none covers the word, or the lookup fails -- cases a caller
  /// treats identically, by offering nothing.
  ///
  /// [word] is matched as a single lowercase token. Anything else (a phrase,
  /// a number, punctuation) is rejected here rather than sent onward: no
  /// thesaurus keyed on words can answer it, and asking wakes the plugin for
  /// nothing.
  Future<ThesaurusEntry?> lookUp(String word) async {
    var key = normalizeWord(word);
    if (key == null || !available) return null;
    if (_cache.containsKey(key)) return _cache[key];

    ThesaurusEntry? entry;
    for (var candidate in [key, ..._baseForms(key)]) {
      try {
        entry = await _fetch(candidate);
      } catch (exception) {
        debugPrint("Thesaurus lookup failed for \"$candidate\": $exception");
        entry = null;
      }
      if (entry != null) break;
    }
    _cache[key] = entry;
    return entry;
  }

  /// _baseForms are reductions to try when a word itself is not in the
  /// thesaurus, in decreasing order of confidence.
  ///
  /// A thesaurus is keyed by the forms its source happened to record, and
  /// those are not the forms people type: "happy" is there and "happier" is
  /// not. Without this, asking about a perfectly ordinary word returns
  /// nothing and looks broken.
  ///
  /// Each is only accepted if the provider actually has it, so a wrong guess
  /// costs a lookup and nothing else. They are tried in order and the first
  /// hit wins, which is why the more specific endings come first.
  static Iterable<String> _baseForms(String word) sync* {
    // Contractions: "wouldn't" -> "would". Rarely helps, since auxiliaries
    // have few synonyms, but it costs one cached miss to find out.
    if (word.endsWith("n't") && word.length > 4) {
      yield word.substring(0, word.length - 3);
    }
    if (word.endsWith("'s") && word.length > 3) {
      yield word.substring(0, word.length - 2);
    }
    // -ier/-iest/-ies all come from a -y stem: happier, happiest, worries.
    for (var suffix in ["iest", "ier", "ies"]) {
      if (word.endsWith(suffix) && word.length > suffix.length + 1) {
        yield "${word.substring(0, word.length - suffix.length)}y";
      }
    }
    for (var suffix in ["ing", "est", "ed", "es", "er", "s"]) {
      if (word.endsWith(suffix) && word.length > suffix.length + 2) {
        yield word.substring(0, word.length - suffix.length);
      }
    }
  }

  /// normalizeWord reduces a selection to the single lowercase word a
  /// thesaurus can be asked about, or null if it isn't one. Surrounding
  /// punctuation and whitespace are trimmed, since a double-click selection
  /// often carries them.
  static String? normalizeWord(String raw) {
    var trimmed = raw.trim().toLowerCase();
    // Strip anything that isn't a letter from both ends, leaving internal
    // apostrophes and hyphens ("don't", "well-chosen") alone.
    var start = 0, end = trimmed.length;
    bool isLetter(int c) => (c >= 97 && c <= 122);
    while (start < end && !isLetter(trimmed.codeUnitAt(start))) {
      start++;
    }
    while (end > start && !isLetter(trimmed.codeUnitAt(end - 1))) {
      end--;
    }
    var word = trimmed.substring(start, end);
    if (word.isEmpty || word.contains(RegExp(r"\s"))) return null;
    return word;
  }
}
