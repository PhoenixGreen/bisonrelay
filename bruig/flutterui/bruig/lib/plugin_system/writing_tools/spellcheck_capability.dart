import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/plugin_system/writing_tools/engine/checker.dart';
import 'package:bruig/plugin_system/writing_tools/engine/preferences.dart';
import 'package:bruig/plugin_system/writing_tools/engine/writing_issue.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';

// spellcheck_capability.dart is the app's side of the spellcheck-data
// capability: it takes whatever words, grammar rules and analysis checks the
// enabled providers supply and keeps a WritingChecker fed with them.
//
// It is the boundary between the running client and the engine. Everything
// that has to know a plugin exists -- whether one is enabled, which language
// it was asked for, what happens when a fetch fails -- is here; everything
// that only has to know English is in engine/, and can be tested without any
// of this.
//
// Flutter's own SpellCheckService is deliberately not used. It carries one
// style for every flagged span, which cannot express the difference between a
// mistake and a suggestion, and it re-runs only when the text changes, which
// is the wrong trigger for a word being added to the dictionary. The painting
// is done instead by WritingTextEditingController -- see ui/writing_field.dart.

/// SpellcheckCapability tracks whether any plugin currently provides
/// spellcheck data and, when one does, keeps the checker fed with it.
///
/// A composer does not read this directly. It gives its TextField a
/// [WritingTextEditingController], which asks this what is wrong with the text
/// as it paints. With no provider enabled the answer is always nothing, and
/// the field looks exactly as it would without the feature.
class SpellcheckCapability extends ChangeNotifier {
  final WritingChecker _checker = WritingChecker();

  // _fetch is injectable so this class can be tested without a running
  // client; it is Golib.getSpellcheckData everywhere but in tests.
  final Future<SpellcheckData> Function(String language) _fetch;

  /// preferences is the user's own overrides -- ignored words, disabled
  /// checks, and the session on/off switch. Owned here so every consumer of
  /// the capability sees the same set.
  final WritingPreferences preferences;

  SpellcheckCapability(
      {Future<SpellcheckData> Function(String language)? fetch,
      WritingPreferences? prefs})
      : _fetch = fetch ?? Golib.getSpellcheckData,
        preferences = prefs ?? WritingPreferences() {
    _checker.prefs = preferences;
    // Re-checking is what makes an ignored word disappear from the text
    // immediately rather than at the next keystroke.
    preferences.addListener(_onPreferencesChanged);
  }

  @override
  void dispose() {
    preferences.removeListener(_onPreferencesChanged);
    super.dispose();
  }

  bool _active = false;
  bool get active => _active;

  /// _onPreferencesChanged re-reads the dictionary when the language changes,
  /// and otherwise just re-checks the text.
  ///
  /// The whole word list changes with the language -- "colour" is in one and
  /// "color" in the other -- so this is a fetch and not a filter.
  void _onPreferencesChanged() {
    _invalidate();
    var plugins = _plugins;
    if (plugins != null && preferences.language != _loadedFor) {
      update(plugins);
    }
  }

  // The last review, kept because the field asks for it on every repaint --
  // every keystroke, and every movement of the caret. Recomputing a long post
  // each time a cursor moves is work for nothing.
  //
  // Keyed on the text alone, and thrown away whenever anything else that could
  // change the answer does: new data, or a change to the preferences.
  String? _reviewedText;
  List<WritingIssue>? _reviewed;

  void _invalidate() {
    _reviewedText = null;
    _reviewed = null;
    notifyListeners();
  }

  /// languages is every language the enabled providers can check against, for
  /// a UI offering the choice. Empty until data has been loaded, and empty
  /// from a provider that serves only one.
  List<SpellcheckLanguage> get languages => _languages;
  List<SpellcheckLanguage> _languages = const [];

  /// activeLanguage is the language actually loaded, which is not always the
  /// one asked for: a provider without it answers in what it has.
  String get activeLanguage => _activeLanguage;
  String _activeLanguage = "";

  // The language the loaded data was fetched for, so a preference change is
  // noticed even though nothing else about the plugin set has moved.
  String? _loadedFor;
  PluginManagerModel? _plugins;

  /// styleFor is how a flagged span is marked in the text.
  ///
  /// Red for a mistake and blue for a suggestion, which is the distinction the
  /// whole severity contract exists to draw. A wordiness rule marked like a
  /// misspelling would put an alarming red wave under prose that is perfectly
  /// good, and the reader who learns to ignore that mark ignores it over the
  /// misspellings too.
  static TextStyle styleFor(WritingIssueKind kind) => TextStyle(
        decoration: TextDecoration.underline,
        decorationColor: kind.isMistake ? Colors.red : const Color(0xFF3B82F6),
        decorationStyle: TextDecorationStyle.wavy,
        // Thick enough to survive being selected. The underline is not removed
        // by a selection, but the selection highlight is painted across the
        // same pixels, and a hairline wave washes out under it to the point of
        // looking as though the flag had gone.
        decorationThickness: 2,
      );

  /// review lists every problem a provider finds in [text] -- see
  /// WritingIssue. Empty when no provider is enabled, which is also what a
  /// clean message returns, so a caller need not distinguish them.
  List<WritingIssue> review(String text) {
    if (!_active || !preferences.enabled) return const [];
    if (_reviewedText == text) return _reviewed!;
    var issues = _checker.review(text);
    _reviewedText = text;
    _reviewed = issues;
    return issues;
  }

  /// issuesAt is everything wrong with one stretch of text -- see the
  /// checker's own note on why this differs from review().
  List<WritingIssue> issuesAt(String text, int start, int end) =>
      _active && preferences.enabled
          ? _checker.issuesAt(text, start, end)
          : const [];

  /// update re-reads the merged data whenever the set of enabled plugins
  /// changes. The fetch lives here rather than in PluginManagerModel so the
  /// manager never has to know this capability exists -- it only reports which
  /// capabilities are present.
  Future<void> update(PluginManagerModel plugins) async {
    // Kept so a language change can re-fetch without the plugin set having
    // moved; update() is otherwise only called when it has.
    _plugins = plugins;
    var active = plugins.hasCapability(PluginCapability.spellcheckData);

    // Flip `active` BEFORE awaiting the data, never after. This runs from a
    // ChangeNotifierProxyProvider's update, i.e. part-way through the build of
    // the composer that is about to read it -- so anything set after an await
    // lands too late for that build, and the composer spends the rest of its
    // life believing the feature is off. Only the word list can arrive late;
    // whether the feature exists at all cannot.
    if (active != _active) {
      _active = active;
      notifyListeners();
    }
    if (!active) return;

    var language = preferences.language;
    try {
      var data = await _fetch(language);
      _loadedFor = language;
      _activeLanguage = data.language;
      if (data.languages.isNotEmpty) _languages = data.languages;
      _checker.updateData(data);
      _reviewedText = null;
      _reviewed = null;
      // The words landing is a second, later change: a composer built in the
      // meantime is showing an active-but-empty checker and needs to re-run it
      // now there is something to check against.
      notifyListeners();
    } catch (exception) {
      // A provider still loading; keep whatever data we already had rather
      // than dropping spell check entirely mid-session.
      debugPrint("Unable to load spellcheck data: $exception");
    }
  }
}
