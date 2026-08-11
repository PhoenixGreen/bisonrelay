import 'package:bruig/plugin_system/plugin_capability.dart';
import 'package:flutter/material.dart';

// plugin_settings.dart is how a capability gets settings onto Settings >
// Plugins without the settings page knowing what the capability is.
//
// The page needs to draw two things it cannot know about. A plugin's panel
// should carry whatever controls its capabilities imply -- a spellcheck
// provider's language picker belongs under the spellcheck provider, not in a
// list somewhere else. And some of those settings outlive every provider: a
// word added to a personal dictionary is a decision about the user's own app,
// and removing the plugin that prompted it must not put that decision out of
// reach.
//
// Written directly, both of those put a capability's UI inside the settings
// screen, and the screen named that capability -- which is the one thing the
// plugin system is built not to do. So the dependency is inverted: a feature
// module registers its section against the capability it belongs to, and the
// page asks only "is there a section for the capabilities this plugin
// declares".
//
// Registration happens once, at startup, from the feature's own entry point.
// A capability nobody registers a section for simply has none, which is the
// normal case.

/// PluginSettingsBuilder draws a capability's settings.
///
/// [inPluginPanel] is true inside an installed plugin's expanded panel and
/// false in the standalone position the page falls back to when nothing
/// provides the capability any more. A section uses it to drop its own heading
/// and rule in the panel, where the plugin's name is already above it.
typedef PluginSettingsBuilder = Widget Function(
    BuildContext context, bool inPluginPanel);

/// PluginSettingsRegistry holds the settings sections capabilities contribute.
///
/// Static rather than a provider, because it is read during the build of the
/// settings page and written once before any page exists. There is exactly one
/// app, and a section is a property of the build rather than of a session.
class PluginSettingsRegistry {
  PluginSettingsRegistry._();

  static final Map<PluginCapability, PluginSettingsBuilder> _sections = {};

  /// register attaches [builder] to [capability]. Registering the same
  /// capability twice replaces the first, which is what a hot reload does and
  /// is harmless.
  static void register(
          PluginCapability capability, PluginSettingsBuilder builder) =>
      _sections[capability] = builder;

  /// forCapabilities returns the sections belonging to the wire names a
  /// plugin's manifest declares, in the capability enum's own order so two
  /// plugins declaring the same pair draw them the same way round.
  static List<PluginSettingsBuilder> forCapabilities(
          Iterable<String> wireNames) =>
      [
        for (var capability in PluginCapability.values)
          if (wireNames.contains(capability.wireName) &&
              _sections[capability] != null)
            _sections[capability]!,
      ];

  /// orphaned returns the sections whose capability nothing installed
  /// provides. These are the settings that have to appear somewhere else on
  /// the page rather than vanish with the plugin that prompted them.
  static List<PluginSettingsBuilder> orphaned(Iterable<String> installed) => [
        for (var capability in PluginCapability.values)
          if (!installed.contains(capability.wireName) &&
              _sections[capability] != null)
            _sections[capability]!,
      ];
}
