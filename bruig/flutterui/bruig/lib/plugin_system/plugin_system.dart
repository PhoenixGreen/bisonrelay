// plugin_system.dart is the single entry point to Bison Relay's plugin
// support. Everything outside lib/plugin_system/ imports this file and
// nothing beneath it.
//
// A plugin is an external artifact -- a manifest plus a sandboxed WebAssembly
// module, built and shipped independently of this repository. It contributes
// to the app in exactly two ways, and no other:
//
//   1. A capability (see plugin_capability.dart): a headless service that
//      feeds somewhere the app already draws -- link previews, spellcheck
//      data. The app is written against the capability, never against a
//      plugin; whether one is installed is only ever asked as
//      PluginManagerModel.hasCapability.
//
//      A provider supplies content, never logic. It writes the regexes but
//      never runs them; it names the counting checks but never implements
//      them; it ranks words but does not do the ranking. Everything under
//      capabilities/ is a mechanism waiting for data, which is what lets a
//      plugin be a sandboxed wasm module with no access to the app at all.
//
//   2. A screen (see plugin_nav.dart, screens/plugin_screen.dart): a nav
//      item whose UI the plugin describes declaratively as JSON, which
//      screens/plugin_screen.dart renders. The plugin draws nothing itself.
//
// Consequently no plugin's name appears anywhere in the app outside the
// Settings > Plugins list, which is the one place plugins are shown as
// plugins. Uninstalling one leaves nothing dangling.
//
// Contents:
//
//   plugin_capability.dart              the capabilities a plugin may offer
//   plugin_manager.dart                 which plugins are installed/enabled
//   plugin_nav.dart                     screen-bearing plugins as nav items
//   capabilities/link_card.dart         the link-card capability's UI
//   capabilities/youtube_player.dart    a player a link-card provider may ask for
//   capabilities/markdown_extensions.dart  capabilities meeting the markdown pipeline
//   capabilities/spellcheck.dart        the spellcheck-data capability
//   capabilities/writing_analysis.dart  the checks that count rather than match
//   capabilities/writing_stats.dart     word counts and reading time
//   capabilities/writing_field.dart     the controller that paints the marks
//   capabilities/spellcheck_actions.dart what a chosen correction does to a field
//   capabilities/writing_popup.dart     the right-click popup explaining an issue
//   capabilities/writing_prefs.dart     what the user asked not to be told
//   capabilities/thesaurus.dart         the thesaurus capability
//   capabilities/thesaurus_menu.dart    its composer UI
//   capabilities/writing_sidebar.dart   the post editor's four review pages
//   screens/plugin_screen.dart          renders a plugin-described screen
//   screens/plugin_settings_screen.dart Settings > Plugins
//
// The Go counterpart is client/pluginmgr (install state and manifests),
// client/pluginmgr/wasmhost (the sandboxed runtime) and
// client/pluginmgr/capabilities (the host side of each capability).
export 'package:bruig/plugin_system/capabilities/link_card.dart';
export 'package:bruig/plugin_system/capabilities/markdown_extensions.dart';
export 'package:bruig/plugin_system/capabilities/spellcheck.dart';
export 'package:bruig/plugin_system/capabilities/writing_analysis.dart';
export 'package:bruig/plugin_system/capabilities/writing_stats.dart';
export 'package:bruig/plugin_system/capabilities/writing_field.dart';
export 'package:bruig/plugin_system/capabilities/spellcheck_actions.dart';
export 'package:bruig/plugin_system/capabilities/writing_popup.dart';
export 'package:bruig/plugin_system/capabilities/writing_prefs.dart';
export 'package:bruig/plugin_system/capabilities/thesaurus.dart';
export 'package:bruig/plugin_system/capabilities/thesaurus_menu.dart';
export 'package:bruig/plugin_system/capabilities/writing_sidebar.dart';
export 'package:bruig/plugin_system/plugin_capability.dart';
export 'package:bruig/plugin_system/plugin_manager.dart';
export 'package:bruig/plugin_system/plugin_nav.dart';
export 'package:bruig/plugin_system/screens/plugin_screen.dart';
export 'package:bruig/plugin_system/screens/plugin_settings_screen.dart';
