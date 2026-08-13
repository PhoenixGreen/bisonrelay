import 'dart:convert';

import 'package:bruig/storage_manager.dart';
import 'package:bruig/plugin_system/writing_tools/engine/writing_issue.dart';
import 'package:flutter/foundation.dart';

// preferences.dart holds what the user has told the writing tools to stop
// saying: words they do not want flagged, and checks they disagree with.
//
// It belongs to the app rather than to any provider. A plugin supplies a
// dictionary and a set of rules; which of those findings a particular person
// wants to see is their decision about their own app, and it must survive
// the plugin being disabled, updated or replaced. Storing it here also means
// a provider never learns what anyone chose to ignore.

// The storage keys, all under one "writing." prefix so they stay together and
// out of the way of the app's own settings.
const _dictionaryKey = "writing.personalDictionary";
const _disabledChecksKey = "writing.disabledChecks";
const _languageKey = "writing.language";

/// WritingPreferences is the user's own overrides on top of whatever the
/// enabled providers report.
///
/// Three separate things, because they have genuinely different lifetimes:
///
///   - [ignoreOnce] is for this session. "Leave that one alone for now" --
///     a name in one message, not a word to remember forever.
///   - [addToDictionary] is permanent, and is how a name or a piece of
///     jargon stops being flagged for good.
///   - [ignoreMatch] is for this session and applies to one phrase under one
///     rule. It exists because the assumption below turned out to be wrong.
///   - [disableCheck] is permanent and applies to a whole rule.
///
/// [disableCheck] was for a long time the only thing offered on a style
/// suggestion, on the reasoning that disagreeing with one instance of a rule
/// almost always means disagreeing with the rule. That is not true of the
/// style rules. "In order to" is padding in most sentences and exactly right
/// in a few, and someone who wants it here still wants to be told about it
/// in the next post -- which left them turning the rule off for good or
/// rewriting a sentence they were happy with.
class WritingPreferences extends ChangeNotifier {
  // Session only, deliberately not persisted: an "ignore once" that outlived
  // the app would be indistinguishable from the personal dictionary, and
  // there would be no way to tell which of the two had hidden a word.
  final Set<String> _ignoredThisSession = {};

  // Session only, for the same reason as the set above. Keyed by the rule
  // *and* the text it matched, not by either alone: keyed by rule it would
  // be disableCheck with a shorter memory, and keyed by text it would collide
  // with the spelling ignores -- "release" dismissed as a repetition would
  // also stop being spell-checked.
  final Set<String> _ignoredMatches = {};

  final Set<String> _dictionary = {};

  // Keyed by the rule's pattern rather than its message: the pattern is what
  // identifies a rule to the engine, and two rules can legitimately share a
  // message ("Missing apostrophe" covers a dozen contractions), where
  // disabling one must not silently disable the rest.
  //
  // The message is kept as the value purely so the settings page can say
  // which check was turned off. Deriving it from the live rules instead
  // would leave the list unreadable exactly when it matters most -- with the
  // provider disabled, which is when someone is most likely to be wondering
  // what they switched off.
  final Map<String, String> _disabledChecks = {};

  /// sidebarPage is which of the writing tools' four pages was last open,
  /// held as an index rather than as the enum itself.
  ///
  /// Here rather than in the sidebar's own State because that State goes
  /// with the screen: leaving the Feed and coming back reopened the panel on
  /// Spelling however long you had been reading the Document counts.
  ///
  /// An index because the enum lives in the sidebar, which imports this file
  /// -- naming the type here would make the pair circular for the sake of a
  /// number. The screen that reads it clamps, so a page removed from the enum
  /// lands on the first one rather than out of range. Not persisted: it is
  /// where you were, not a preference.
  int sidebarPage = 0;

  /// enabled is the whole feature's on/off switch for the current session --
  /// underlines and suggestions alike. Not persisted: it is a "let me write
  /// without being corrected for a minute" control, and one that stayed off
  /// across a restart would look like the feature had broken.
  bool _enabled = true;
  bool get enabled => _enabled;
  set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    notifyListeners();
  }

  /// language is which English (or other language) to check against, as a
  /// provider's own code -- "en-GB", "en-US".
  ///
  /// Persisted, unlike [enabled]: which English somebody writes is a fact
  /// about them, not a mood, and having it reset on restart would put every
  /// British spelling back under a red line.
  ///
  /// Empty means "whatever the provider defaults to", which is what a fresh
  /// install and a provider offering only one language both look like.
  String _language = "";
  String get language => _language;
  Future<void> setLanguage(String code) async {
    if (code == _language) return;
    _language = code;
    notifyListeners();
    await StorageManager.saveData(_languageKey, code);
  }

  /// personalDictionary and disabledChecks are exposed so the plugin
  /// settings page can show what has been hidden and take it back.
  Set<String> get personalDictionary => Set.unmodifiable(_dictionary);

  /// disabledChecks maps each turned-off rule's pattern to its description.
  Map<String, String> get disabledChecks => Map.unmodifiable(_disabledChecks);

  /// load reads the persisted sets. Failures are non-fatal: a corrupt or
  /// missing entry means no overrides, which is the same as a fresh install
  /// and strictly safer than refusing to check anything.
  Future<void> load() async {
    _dictionary.addAll(await _readSet(_dictionaryKey));
    _disabledChecks.addAll(await _readChecks());
    var stored = await StorageManager.readData(_languageKey);
    if (stored is String && stored.isNotEmpty) {
      _language = stored;
    }
    if (_dictionary.isNotEmpty ||
        _disabledChecks.isNotEmpty ||
        _language.isNotEmpty) {
      notifyListeners();
    }
  }

  /// _readChecks accepts both the current map form and the plain list an
  /// earlier build wrote, so upgrading does not silently switch every
  /// disabled check back on. A list entry has no description to recover.
  Future<Map<String, String>> _readChecks() async {
    try {
      var raw = await StorageManager.readData(_disabledChecksKey);
      if (raw is! String || raw.isEmpty) return {};
      var decoded = jsonDecode(raw);
      if (decoded is List) {
        return {for (var e in decoded) e.toString(): ""};
      }
      return (decoded as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v.toString()));
    } catch (exception) {
      debugPrint("Unable to read $_disabledChecksKey: $exception");
      return {};
    }
  }

  static Future<Set<String>> _readSet(String key) async {
    try {
      var raw = await StorageManager.readData(key);
      if (raw is! String || raw.isEmpty) return {};
      return (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (exception) {
      debugPrint("Unable to read $key: $exception");
      return {};
    }
  }

  Future<void> _writeSet(String key, Set<String> value) async {
    try {
      await StorageManager.saveData(key, jsonEncode(value.toList()));
    } catch (exception) {
      debugPrint("Unable to save $key: $exception");
    }
  }

  /// _key is how a word is stored and looked up: lower case, and with any
  /// typographic apostrophe folded to a plain one.
  ///
  /// The fold matters because the two forms are the same word. A field that
  /// substitutes U+2019 as you type would otherwise let "don't" be added to
  /// the dictionary and still be flagged, since the checker looks the word up
  /// in its plain form.
  static String _key(String word) => normalizeForMatching(word).toLowerCase();

  /// isIgnoredWord reports whether [word] should not be flagged, whether
  /// that was decided for this session or for good.
  bool isIgnoredWord(String word) {
    var key = _key(word);
    return _ignoredThisSession.contains(key) || _dictionary.contains(key);
  }

  bool isCheckDisabled(String pattern) => _disabledChecks.containsKey(pattern);

  /// _matchKey pairs a rule with the text it matched. The separator is a
  /// character neither part can contain, so no two pairs can collide by
  /// running into each other.
  static String _matchKey(String checkId, String text) =>
      "$checkId\u0000${_key(text)}";

  /// isIgnoredMatch reports whether this rule has been told to leave this
  /// particular phrase alone for the rest of the session.
  bool isIgnoredMatch(String? checkId, String text) =>
      checkId != null && _ignoredMatches.contains(_matchKey(checkId, text));

  /// ignoreMatch dismisses one phrase under one rule until the app restarts.
  ///
  /// The phrase rather than the one occurrence of it, and that is a real
  /// limitation rather than a shortcut. An occurrence is a pair of offsets
  /// into text that is still being typed, and every keystroke before it moves
  /// them -- so a dismissal pinned to a position would drift onto whatever
  /// happened to be there later. The phrase survives editing, and where a
  /// finding covers several occurrences at once (a word repeated four times
  /// in a paragraph) dismissing the phrase is what the reader means anyway.
  void ignoreMatch(String checkId, String text) {
    if (!_ignoredMatches.add(_matchKey(checkId, text))) return;
    notifyListeners();
  }

  void ignoreOnce(String word) {
    if (!_ignoredThisSession.add(_key(word))) return;
    notifyListeners();
  }

  Future<void> addToDictionary(String word) async {
    if (!_dictionary.add(_key(word))) return;
    notifyListeners();
    await _writeSet(_dictionaryKey, _dictionary);
  }

  Future<void> removeFromDictionary(String word) async {
    if (!_dictionary.remove(_key(word))) return;
    notifyListeners();
    await _writeSet(_dictionaryKey, _dictionary);
  }

  /// disableCheck turns a rule off. [description] is the rule's message, so
  /// the settings page can name it later.
  Future<void> disableCheck(String pattern, {String description = ""}) async {
    if (_disabledChecks.containsKey(pattern)) return;
    _disabledChecks[pattern] = description;
    notifyListeners();
    await _writeChecks();
  }

  Future<void> enableCheck(String pattern) async {
    if (_disabledChecks.remove(pattern) == null) return;
    notifyListeners();
    await _writeChecks();
  }

  Future<void> _writeChecks() async {
    try {
      await StorageManager.saveData(
          _disabledChecksKey, jsonEncode(_disabledChecks));
    } catch (exception) {
      debugPrint("Unable to save $_disabledChecksKey: $exception");
    }
  }
}
