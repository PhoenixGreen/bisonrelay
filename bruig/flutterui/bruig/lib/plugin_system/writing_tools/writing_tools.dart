import 'package:bruig/components/containers.dart';
import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/plugin_system/writing_tools/notes/notes_settings.dart';
import 'package:bruig/plugin_system/writing_tools/notes/ui/notes_host.dart';
import 'package:bruig/plugin_system/writing_tools/ui/writing_settings.dart';
import 'package:flutter/material.dart';

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
//   composer_sidebar.dart  which panel has the slot beside the editor
//   writing_nav.dart       the Writing destination, while the plugin is on
//
//   post_library/      the saved posts: folders and documents on disk
//   notes/             the note for whatever page you are on
//
//   ui/
//     writing_field.dart   the controller that paints the marks
//     writing_actions.dart what was clicked, and how to apply what was chosen
//     writing_popup.dart   the right-click popup explaining an issue
//     thesaurus_menu.dart  the "Look up" entry and the sheet it opens
//     writing_settings.dart the Settings > Plugins section
//     writing_screen.dart  the Writing section itself
//     composer.dart        the post editor on it
//     add_embed_dialog.dart  putting a picture into a post
//     composer_sidebar_shell.dart  the panel icons above the sidebar
//     sidebar/             the review pages, and Formatting & Content
//
// The Writing section, its editor and its whole sidebar live here rather than
// under screens/feed/ because they exist only while this plugin is enabled.
// The Feed keeps a plain composer of its own for everybody else, and the two
// share no code: this one is free to assume a sidebar beside it, a document
// on disk behind it, and marks under its words.
//
// The one thing in here that is not a writing tool is the post library. It
// is no plugin's -- documents on disk are the user's -- but it is a panel of
// this sidebar and reachable from nowhere else, so it travels with the page
// that shows it.
//
// Notes are here for the same reason and one more. They are documents in that
// same library, written in the same Markdown, and they are the writing you do
// while reading rather than the writing you do to publish -- which is a
// writing tool if anything is. See notes/notes.dart.
export 'package:bruig/plugin_system/writing_tools/composer_sidebar.dart';
export 'package:bruig/plugin_system/writing_tools/notes/notes.dart';
export 'package:bruig/plugin_system/writing_tools/engine/preferences.dart';
export 'package:bruig/plugin_system/writing_tools/engine/stats.dart';
export 'package:bruig/plugin_system/writing_tools/engine/writing_issue.dart';
export 'package:bruig/plugin_system/writing_tools/post_library/post_library.dart';
export 'package:bruig/plugin_system/writing_tools/spellcheck_capability.dart';
export 'package:bruig/plugin_system/writing_tools/thesaurus_capability.dart';
export 'package:bruig/plugin_system/writing_tools/writing_nav.dart';
export 'package:bruig/plugin_system/writing_tools/ui/sidebar/writing_sidebar.dart';
export 'package:bruig/plugin_system/writing_tools/ui/thesaurus_menu.dart';
export 'package:bruig/plugin_system/writing_tools/ui/writing_actions.dart';
export 'package:bruig/plugin_system/writing_tools/ui/writing_field.dart';
export 'package:bruig/plugin_system/writing_tools/ui/writing_popup.dart';
export 'package:bruig/plugin_system/writing_tools/ui/writing_screen.dart';
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
    (context, inPluginPanel) => _WritingToolsSettings(inPluginPanel),
  );

  // Notes are drawn over every screen's content area -- the region beside a
  // page's own sidebar. Registered here rather than written into a layout,
  // for the same reason the settings section above is: components/containers
  // is the most generic file in the app and must not import a feature. See
  // contentAreaOverlay.
  contentAreaOverlay = (content) => NotesHost(child: content);
}

/// _WritingToolsSettings is everything this module puts on Settings > Plugins.
///
/// The registry holds one section per capability, and these two belong to the
/// same one: notes exist because the writing tools do, and both are undone
/// from the same panel. Composing them here rather than widening the registry
/// keeps that a fact about this module instead of a rule the plugin system has
/// to know.
///
/// Notes first because they are a feature to turn on and off, which is what
/// somebody opening this panel is usually looking for. The overrides below are
/// a list of past decisions to undo, and are absent entirely until there are
/// some.
class _WritingToolsSettings extends StatelessWidget {
  final bool inPluginPanel;
  const _WritingToolsSettings(this.inPluginPanel);

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const NotesSettingsSection(),
        WritingOverridesSection(inPluginPanel: inPluginPanel),
      ]);
}
