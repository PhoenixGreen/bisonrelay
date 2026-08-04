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
//   screens/plugin_screen.dart          renders a plugin-described screen
//   screens/plugin_settings_screen.dart Settings > Plugins
//
// The Go counterpart is client/pluginmgr (install state and manifests),
// client/pluginmgr/wasmhost (the sandboxed runtime) and
// client/pluginmgr/capabilities (the host side of each capability).
export 'package:bruig/plugin_system/capabilities/link_card.dart';
export 'package:bruig/plugin_system/capabilities/markdown_extensions.dart';
export 'package:bruig/plugin_system/capabilities/spellcheck.dart';
export 'package:bruig/plugin_system/plugin_capability.dart';
export 'package:bruig/plugin_system/plugin_manager.dart';
export 'package:bruig/plugin_system/plugin_nav.dart';
export 'package:bruig/plugin_system/screens/plugin_screen.dart';
export 'package:bruig/plugin_system/screens/plugin_settings_screen.dart';
