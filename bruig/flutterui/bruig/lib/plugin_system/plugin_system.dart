// plugin_system.dart is the single entry point to Bison Relay's plugin
// support. Everything outside lib/plugin_system/ imports this file and nothing
// beneath it.
//
// A plugin is a manifest plus a sandboxed WebAssembly module. It comes from
// one of two places, and that is the only difference between them:
//
//   Built in    ships inside the client and is present without being
//               installed. It cannot be removed, only disabled, and nothing
//               imported may take its id. Two ship: Writing Tools and Pretty
//               Links, because the app's own features are written against
//               the services they provide -- a composer expects somebody to
//               answer "spellcheck-data", and a user who had to find a file
//               before the app worked as described would call that a broken
//               install. See client/pluginmgr/builtin.
//
//   Imported    a file the reader chose, installed through Settings >
//               Plugins. RSS is one: a screen you may or may not want.
//
// Being built in buys presence, not privilege. Both kinds run in the same
// wasm sandbox, reach the network through the same Tor-proxied client, and
// are validated by the same manifest checks. Nothing in this directory
// branches on which kind it is handling except the settings page, which
// groups them and withholds Remove from the built-ins.
//
// A plugin contributes to the app in exactly two ways, and no other:
//
//   1. A capability (see plugin_capability.dart): a headless service that
//      feeds somewhere the app already draws -- link previews, spellcheck
//      data. The app is written against the capability, never against a
//      plugin; whether one is installed is only ever asked as
//      PluginManagerModel.hasCapability.
//
//      A provider supplies content, never logic. It writes the regexes but
//      never runs them; it names the counting checks but never implements
//      them; it ranks words but does not do the ranking. Whatever consumes a
//      capability is a mechanism waiting for data, which is what lets a plugin
//      be a sandboxed wasm module with no access to the app at all.
//
//   2. A screen (see plugin_nav.dart, screens/plugin_screen.dart): a nav item
//      whose UI the plugin describes declaratively as JSON, which
//      screens/plugin_screen.dart renders. The plugin draws nothing itself.
//
// Consequently no plugin's name appears anywhere in the app outside the
// Settings > Plugins list, which is the one place plugins are shown as
// plugins. Uninstalling one leaves nothing dangling.
//
// What is NOT here is any capability's implementation. This directory owns
// installation, the vocabulary of capabilities, the nav items and the settings
// page -- the machinery that is the same whatever a plugin does. What a
// capability's data is then *used for* is a feature of the app, and lives with
// the rest of that feature:
//
//   writing_tools/    the spellcheck-data and thesaurus capabilities
//   link_previews/    the link-card capability
//
// Those two sit inside this directory because they are the app's side of the
// two built-in plugins, and a reader looking for "what ships with Bison
// Relay" should find all of it in one place. They are still separate
// modules, not part of the machinery.
//
// The split is not cosmetic, and the rule that keeps it is one line: those
// two directories import this one, and this one imports neither. So the
// files listed below can be read start to finish without knowing what a wavy
// underline or a preview card is, and a third capability is added without
// touching any of them except the enum in plugin_capability.dart. An import
// pointing the other way undoes the whole arrangement, and nothing but
// noticing prevents it.
//
// Contents:
//
//   plugin_capability.dart              the capabilities a plugin may offer
//   plugin_manager.dart                 which plugins are installed/enabled
//   plugin_nav.dart                     screen-bearing plugins as nav items
//   plugin_settings.dart                where a capability's settings attach
//   plugin_slots.dart                   the surfaces a plugin may contribute to
//   plugin_icons.dart                   the icon names a plugin may use
//   screens/widget_renderer.dart        the declarative widget tree, drawn
//   screens/plugin_screen.dart          renders a plugin-described screen
//   screens/plugin_settings_screen.dart Settings > Plugins
//
// The Go counterpart is client/pluginmgr (install state and manifests),
// client/pluginmgr/wasmhost (the sandboxed runtime) and
// client/pluginmgr/capabilities (the host side of each capability).
export 'package:bruig/plugin_system/plugin_capability.dart';
export 'package:bruig/plugin_system/plugin_manager.dart';
export 'package:bruig/plugin_system/plugin_nav.dart';
export 'package:bruig/plugin_system/plugin_settings.dart';
export 'package:bruig/plugin_system/plugin_slots.dart';
export 'package:bruig/plugin_system/screens/plugin_screen.dart';
export 'package:bruig/plugin_system/screens/plugin_settings_screen.dart';
