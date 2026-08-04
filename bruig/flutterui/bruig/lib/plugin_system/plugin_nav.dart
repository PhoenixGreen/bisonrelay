import 'dart:async';

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
      if (p.manifest.screens.isEmpty) continue;
      stillEnabled.add(p.manifest.id);

      mainMenu.registerDynamicItem(MainMenuItem(
        p.manifest.navLabel,
        routeNameFor(p.manifest.id),
        (context) => PluginScreen(p.manifest.id, p.manifest.screens),
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

  // _navIcons is the fixed palette a manifest's navIcon may name. A plugin
  // ships no assets and no code the app draws with, so it picks from this
  // list rather than supplying an image -- an unrecognized name (from a
  // plugin built against a later version) falls back to a generic icon
  // rather than failing to register the plugin at all.
  static const Map<String, IconData> _navIcons = {
    "rss_feed": Icons.rss_feed,
    "article": Icons.article_outlined,
    "bookmark": Icons.bookmark_outline,
    "calendar": Icons.calendar_today_outlined,
    "chat": Icons.forum_outlined,
    "cloud": Icons.cloud_outlined,
    "code": Icons.code,
    "dashboard": Icons.dashboard_outlined,
    "explore": Icons.explore_outlined,
    "feed": Icons.dynamic_feed_outlined,
    "folder": Icons.folder_outlined,
    "music": Icons.music_note_outlined,
    "note": Icons.sticky_note_2_outlined,
    "photo": Icons.photo_outlined,
    "search": Icons.search,
    "star": Icons.star_outline,
    "store": Icons.storefront_outlined,
    "tag": Icons.local_offer_outlined,
    "video": Icons.ondemand_video_outlined,
    "wallet": Icons.account_balance_wallet_outlined,
  };

  IconData _iconFor(String name) => _navIcons[name] ?? Icons.extension_outlined;
}
