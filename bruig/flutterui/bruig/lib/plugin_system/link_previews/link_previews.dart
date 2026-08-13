// link_previews.dart is the app's side of the link-card capability: the
// preview card a bare URL turns into, the players a provider may ask for
// beside it, and the markdown extension that puts the two on the page.
//
// It sits under lib/plugin_system/ because it is the app's half of a plugin
// that ships with Bison Relay -- see plugin_system.dart on what built in
// means -- but it is its own module, not part of the machinery. The plugin
// system owns installation, capabilities and the settings page; what any one
// capability *does* with the data it receives is the feature's business, and
// keeping the two apart is what lets the plugin system be read without
// knowing what a link card is. The dependency runs one way, this module on
// the machinery, and test/plugin_system_layering_test.dart fails if that
// ever reverses.
//
// Nothing here names a plugin. A provider claims a URL and returns metadata
// for it; whether one is installed is only ever asked as
// PluginManagerModel.hasCapability(PluginCapability.linkCard), which is the
// single line markdown_extension.dart is built around. With no provider
// enabled the extension is not registered and a bare URL renders exactly as
// it did before.
//
// Contents:
//
//   link_card.dart          the preview card itself
//   youtube_player.dart     a player a provider may name in its metadata
//   markdown_extension.dart where the capability meets the markdown pipeline
export 'package:bruig/plugin_system/link_previews/link_card.dart';
export 'package:bruig/plugin_system/link_previews/markdown_extension.dart';
export 'package:bruig/plugin_system/link_previews/youtube_player.dart';
