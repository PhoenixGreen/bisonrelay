// link_previews.dart is the app's side of the link-card capability: the
// preview card a bare URL turns into, the players a provider may ask for
// beside it, and the markdown extension that puts the two on the page.
//
// It is a feature module rather than part of lib/plugin_system/. The plugin
// system owns installation, capabilities and the settings page; what any one
// capability *does* with the data it receives is the feature's business, and
// keeping the two apart is what lets the plugin system be read without
// knowing what a link card is.
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
export 'package:bruig/link_previews/link_card.dart';
export 'package:bruig/link_previews/markdown_extension.dart';
export 'package:bruig/link_previews/youtube_player.dart';
