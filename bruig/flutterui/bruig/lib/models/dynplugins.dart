import 'dart:async';

import 'package:bruig/components/dynplugin_screen.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/menus.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';

/// DynPluginsModel keeps MainMenuModel's nav items in sync with the set of
/// enabled dynamic-wasm plugins (see client/pluginmgr/wasmhost on the Go
/// side): each contributes exactly one MainMenuItem, built generically from
/// its manifest (navLabel/navIcon/screens). There is no RSS-specific (or
/// any other plugin-specific) code here or in DynPluginScreen -- adding a
/// second dynamic-wasm plugin needs zero changes to either.
class DynPluginsModel extends ChangeNotifier {
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

  DynPluginsModel() {
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

  /// update is called (via a ChangeNotifierProxyProvider2) whenever
  /// PluginsModel's plugin list changes, registering/unregistering
  /// MainMenuModel nav items to match the current set of enabled
  /// dynamic-wasm plugins.
  void update(List<PluginInfo> plugins, MainMenuModel mainMenu) {
    var stillEnabled = <String>{};

    for (var p in plugins) {
      if (p.manifest.rendererKind != "dynamic-wasm" || !p.enabled) continue;
      if (p.manifest.screens.isEmpty) continue;
      stillEnabled.add(p.manifest.id);

      mainMenu.registerDynamicItem(MainMenuItem(
        p.manifest.navLabel,
        routeNameFor(p.manifest.id),
        (context) => DynPluginScreen(p.manifest.id, p.manifest.screens),
        (context) => Txt.L(p.manifest.navLabel),
        SidebarIcon(_iconFor(p.manifest.navIcon), false),
        <SubMenuInfo>[],
      ));
    }

    for (var id in _registered.difference(stillEnabled)) {
      mainMenu.unregisterDynamicItem(routeNameFor(id));
    }
    _registered
      ..clear()
      ..addAll(stillEnabled);
  }

  // _iconFor maps a manifest-declared icon name to a built-in IconData,
  // falling back to a generic icon for anything unrecognized -- plugin
  // manifests can't ship arbitrary assets/code, only pick from this fixed
  // set, consistent with the rest of the dynamic-wasm plugin design.
  IconData _iconFor(String name) {
    switch (name) {
      case "rss_feed":
        return Icons.rss_feed;
      default:
        return Icons.extension_outlined;
    }
  }
}
