import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/plugin_system/writing_tools/ui/writing_settings.dart';

// writing_tools.dart is the single entry point to Bison Relay's writing tools:
// the spelling, grammar and phrasing marks in every composer, the thesaurus,
// and the post editor's review sidebar. App code outside this directory
// imports this file and nothing beneath it. Tests are the exception and reach
// straight into engine/, which is the point of engine/ being separable at all.
//
// It sits under lib/plugin_system/ because it is the app's half of a plugin
// that ships with Bison Relay -- see plugin_system.dart on what built in
// means. It is still its own module: it imports the plugin machinery, and
// the machinery imports nothing from here (see
// test/plugin_system_layering_test.dart, which fails if that reverses).
//
// The tools are the app's half of two plugin capabilities. A provider hands
// over a dictionary, a set of regex rules and a list of counting checks it
// wants run; nothing here is any provider's code, and with no provider enabled
// every composer behaves exactly as it would without the feature. The division
// is strict and it is the reason the plugin can be a sandboxed wasm module
// with no access to the app: the provider decides *what* is checked and this
// module owns *every mechanism* -- the regex engine, the edit-distance
// ranking, the counting, the painting and all of the UI.
//
// The one thing here that needs no provider at all is the document statistics.
// Counting words is not a judgement about English.
//
// Layout:
//
//   engine/            no Flutter beyond TextRange; testable on its own
//     writing_issue.dart  one flagged span, and the two text helpers
//     text_segments.dart  words, sentences and paragraphs, with offsets
//     suggester.dart      edit distance and the ranking of corrections
//     checker.dart        the rule engine the three sources meet in
//     analysis.dart       the registry the counting checks are named in
//     checks/             one file per family of counting check
//     stats.dart          word counts, reading time, reading ease
//     preferences.dart    what the user asked not to be told
//
//   spellcheck_capability.dart  keeps the checker fed; owns the fetch
//   thesaurus_capability.dart   answers one word at a time
//
//   ui/
//     writing_field.dart   the controller that paints the marks
//     writing_actions.dart what was clicked, and how to apply what was chosen
//     writing_popup.dart   the right-click popup explaining an issue
//     thesaurus_menu.dart  the "Look up" entry and the sheet it opens
//     writing_settings.dart the Settings > Plugins section
//     sidebar/             the post editor's four review pages
//
// The sidebar slot it occupies is not owned here: it is shared with the
// saved-post library, which is not a plugin at all. See
// models/composer_sidebar.dart.
export 'package:bruig/plugin_system/writing_tools/engine/preferences.dart';
export 'package:bruig/plugin_system/writing_tools/engine/stats.dart';
export 'package:bruig/plugin_system/writing_tools/engine/writing_issue.dart';
export 'package:bruig/plugin_system/writing_tools/spellcheck_capability.dart';
export 'package:bruig/plugin_system/writing_tools/thesaurus_capability.dart';
export 'package:bruig/plugin_system/writing_tools/ui/sidebar/writing_sidebar.dart';
export 'package:bruig/plugin_system/writing_tools/ui/thesaurus_menu.dart';
export 'package:bruig/plugin_system/writing_tools/ui/writing_actions.dart';
export 'package:bruig/plugin_system/writing_tools/ui/writing_field.dart';
export 'package:bruig/plugin_system/writing_tools/ui/writing_popup.dart';
export 'package:bruig/plugin_system/writing_tools/ui/writing_settings.dart';

/// registerWritingTools attaches this module to the plugin system.
///
/// Called once at startup, before the settings page can be reached. It is the
/// only line of the app that says the writing tools and the spellcheck-data
/// capability go together -- and it says it from this side of the boundary, so
/// the plugin system stays unaware that a dictionary is a thing anyone might
/// want settings for.
void registerWritingTools() {
  PluginSettingsRegistry.register(
    PluginCapability.spellcheckData,
    (context, inPluginPanel) =>
        WritingOverridesSection(inPluginPanel: inPluginPanel),
  );
}
