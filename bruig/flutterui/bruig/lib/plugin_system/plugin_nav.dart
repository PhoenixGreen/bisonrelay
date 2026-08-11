import 'dart:async';

import 'package:bruig/plugin_system/plugin_icons.dart';
import 'package:bruig/plugin_system/plugin_slots.dart';
import 'package:bruig/plugin_system/screens/plugin_screen.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/menus.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';

/// PluginNavModel keeps MainMenuModel's nav items in sync with the set of
/// enabled plugins that contribute screens. Each such plugin gets exactly
/// one MainMenuItem, built entirely from its manifest (navLabel, navIcon,
/// screens), so a second, tenth or hundredth screen-bearing plugin needs no
/// change here or in PluginScreen.
class PluginNavModel extends ChangeNotifier {
  final Set<String> _registered = {};

  // Golib.dynPluginScreenUpdated() is a single-subscription stream (like
  // every other NtfStreams entry) -- it may only be listened to once for
  // the app's whole lifetime. DynPluginsModel is that one long-lived
  // listener; it re-broadcasts onto pluginScreenUpdated, which
  // DynPluginScreen (recreated every time its nav item is visited) can
  // safely listen to any number of times.
  final StreamController<String> _pluginScreenUpdated =
      StreamController<String>.broadcast();
  Stream<String> get pluginScreenUpdated => _pluginScreenUpdated.stream;
  late final StreamSubscription<String> _updateSub;

  PluginNavModel() {
    _updateSub =
        Golib.dynPluginScreenUpdated().listen(_pluginScreenUpdated.add);
  }

  @override
  void dispose() {
    _updateSub.cancel();
    _pluginScreenUpdated.close();
    super.dispose();
  }

  static String routeNameFor(String pluginId) => "/dynplugin/$pluginId";

  /// update registers and unregisters MainMenuModel nav items to match the
  /// current set of enabled screen-bearing plugins. Called whenever the
  /// plugin list changes.
  void update(List<PluginInfo> plugins, MainMenuModel mainMenu) {
    var stillEnabled = <String>{};

    for (var p in plugins) {
      if (p.manifest.rendererKind != "dynamic-wasm" || !p.enabled) continue;
      // The nav slot, like every other -- a plugin that contributes no nav
      // item simply has none, whether because it is headless or because it
      // appears only in a settings page or a composer toolbar.
      for (var nav in p.manifest.contributionsTo(PluginSlots.nav)) {
        stillEnabled.add(p.manifest.id);

        // A nav contribution with no sub-pages is a one-page plugin, and its
        // own id is that page. Only the nav slot carries sub-pages at all,
        // which is why the side menu lives with the screen rather than here.
        var screens = nav.screens.isNotEmpty
            ? nav.screens
            : [ScreenDef(nav.id, nav.label)];

        mainMenu.registerDynamicItem(MainMenuItem(
          nav.label,
          routeNameFor(p.manifest.id),
          (context) => PluginScreen(p.manifest.id, screens),
          (context) => Txt.L(nav.label),
          SidebarIcon(pluginIcon(nav.icon), false),
          <SubMenuInfo>[],
        ));
        // One nav item per plugin: the route name is keyed on the plugin id,
        // so a second contribution would overwrite the first rather than
        // appear beside it. A plugin wanting two tabs wants two plugins.
        break;
      }
    }

    for (var id in _registered.difference(stillEnabled)) {
      mainMenu.unregisterDynamicItem(routeNameFor(id));
    }
    _registered
      ..clear()
      ..addAll(stillEnabled);
  }
}
