import 'dart:convert';

import 'package:bruig/storage_manager.dart';
import 'package:flutter/foundation.dart';

// writing_prefs.dart holds what the user has told the writing capabilities
// to stop saying: words they do not want flagged, and checks they disagree
// with.
//
// It belongs to the app rather than to any provider. A plugin supplies a
// dictionary and a set of rules; which of those findings a particular person
// wants to see is their decision about their own app, and it must survive
// the plugin being disabled, updated or replaced. Storing it here also means
// a provider never learns what anyone chose to ignore.

/// _storagePrefix keeps these keys together and out of the way of the app's
/// own settings.
const _dictionaryKey = "writing.personalDictionary";
const _disabledChecksKey = "writing.disabledChecks";

/// WritingPreferences is the user's own overrides on top of whatever the
/// enabled providers report.
///
/// Three separate things, because they have genuinely different lifetimes:
///
///   - [ignoreOnce] is for this session. "Leave that one alone for now" --
///     a name in one message, not a word to remember forever.
///   - [addToDictionary] is permanent, and is how a name or a piece of
///     jargon stops being flagged for good.
///   - [disableCheck] is permanent and applies to a whole rule, because
///     disagreeing with one instance of a style rule almost always means
///     disagreeing with the rule.
class WritingPreferences extends ChangeNotifier {
  // Session only, deliberately not persisted: an "ignore once" that outlived
  // the app would be indistinguishable from the personal dictionary, and
  // there would be no way to tell which of the two had hidden a word.
  final Set<String> _ignoredThisSession = {};

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
    if (_dictionary.isNotEmpty || _disabledChecks.isNotEmpty) {
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

  /// isIgnoredWord reports whether [word] should not be flagged, whether
  /// that was decided for this session or for good.
  bool isIgnoredWord(String word) {
    var key = word.toLowerCase();
    return _ignoredThisSession.contains(key) || _dictionary.contains(key);
  }

  bool isCheckDisabled(String pattern) => _disabledChecks.containsKey(pattern);

  void ignoreOnce(String word) {
    if (!_ignoredThisSession.add(word.toLowerCase())) return;
    notifyListeners();
  }

  Future<void> addToDictionary(String word) async {
    if (!_dictionary.add(word.toLowerCase())) return;
    notifyListeners();
    await _writeSet(_dictionaryKey, _dictionary);
  }

  Future<void> removeFromDictionary(String word) async {
    if (!_dictionary.remove(word.toLowerCase())) return;
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
