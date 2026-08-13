import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/plugin_system/writing_tools/engine/writing_issue.dart';
import 'package:flutter/foundation.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';

// thesaurus_capability.dart is the app's side of the thesaurus capability.
// Unlike spellcheck, which is handed its whole dataset once, this one asks a
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
  ///
  /// The word is sent as typed. This used to try a series of guessed base
  /// forms as well -- stripping "-ing", "-ies", "-ed" and so on -- because a
  /// thesaurus is keyed by the forms its source recorded, and "happier" is
  /// not one of them. That belongs on the provider's side of the line and is
  /// now done there, with the source's own irregular-word lists rather than
  /// suffix guesses: "went" reaches "go" and "children" reaches "child",
  /// which no amount of guessing here would have managed.
  ///
  /// Removing it also stopped a miss costing six round trips into the wasm
  /// sandbox. A name or a typo now costs one.
  ///
  /// The answer reports which form it is for, in [ThesaurusEntry.word], and
  /// that need not be the word asked about.
  Future<ThesaurusEntry?> lookUp(String word) async {
    var key = normalizeWord(word);
    if (key == null || !available) return null;
    if (_cache.containsKey(key)) return _cache[key];

    ThesaurusEntry? entry;
    try {
      entry = await _fetch(key);
    } catch (exception) {
      debugPrint("Thesaurus lookup failed for \"$key\": $exception");
      entry = null;
    }
    _cache[key] = entry;
    return entry;
  }

  /// maxLookupWords is how long a selection may be and still be a lookup.
  ///
  /// Three. The datasets carry phrases of up to three words -- "take off",
  /// "put up with" -- and a selection longer than that is a sentence
  /// somebody highlighted, not a thing to look up. Offering the entry for
  /// one would mean a menu item that is never useful appearing over every
  /// drag of the cursor.
  static const maxLookupWords = 3;

  /// normalizeWord reduces a selection to the lowercase word or phrase a
  /// thesaurus can be asked about, or null if it isn't one. Surrounding
  /// punctuation and whitespace are trimmed, since a double-click selection
  /// often carries them.
  ///
  /// A phrase is allowed because the data has them. It used to reject
  /// anything containing a space, which meant the two constructions somebody
  /// learning English most wants explained -- a phrasal verb and an idiom --
  /// were the two it could not be asked about, while 64,246 entries covering
  /// them sat unused in the source data.
  static String? normalizeWord(String raw) {
    // Folded first, so a contraction typed with the apostrophe a text field
    // substituted reaches the provider in the form its data is keyed by.
    var trimmed = normalizeForMatching(raw).trim().toLowerCase();
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
    if (word.isEmpty) return null;
    // Runs of whitespace collapse to one space: a selection dragged across a
    // line break carries the newline with it, and the data is keyed by
    // single spaces.
    var words = word.split(RegExp(r"\s+")).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty || words.length > maxLookupWords) return null;
    return words.join(" ");
  }
}
