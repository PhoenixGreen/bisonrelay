import 'package:bruig/models/menus.dart';
import 'package:bruig/plugin_system/plugin_capability.dart';
import 'package:bruig/plugin_system/plugin_manager.dart';
import 'package:bruig/plugin_system/writing_tools/ui/writing_screen.dart';
import 'package:flutter/material.dart';

// writing_nav.dart puts the Writing section in the navigation while the
// Writing Tools plugin is enabled, and takes it out again when it is not.
//
// It is the same idea as PluginNavModel, and deliberately not the same code.
// That one builds a nav item out of a manifest, for a plugin whose screen is
// a widget tree the module sends over; this screen is the app's own Flutter
// code -- the app's half of the plugin, like every other file in this
// directory -- so there is nothing for the renderer to draw and no manifest
// to read it out of. What the two share is the mechanism underneath:
// MainMenuModel.registerDynamicItem, which is already how a destination that
// is not in the built-in list appears in the navigation, in the route
// dispatch, and in Settings > Appearance > Menu.

/// hasWritingPage is whether the Writing section currently exists.
///
/// Asked of the menu rather than of the plugin manager, so that the one
/// question a screen elsewhere in the app wants answered -- "is there a
/// Writing page to send somebody to?" -- is answered by whether there is one.
/// The Feed asks this to decide where its New Post link goes.
bool hasWritingPage(MainMenuModel mainMenu) =>
    mainMenu.menuForRoute(WritingScreen.routeName) != null;

/// WritingNavModel keeps the Writing destination in step with the plugin.
///
/// It holds no state anyone reads -- it exists for the side effect -- so
/// whatever provides it must do so eagerly (lazy: false).
class WritingNavModel extends ChangeNotifier {
  // Whether the item is *wanted*, so a repeat unregistration cannot happen.
  //
  // Only the removal is guarded. MainMenuModel tolerates a repeat
  // registration -- it updates in place and notifies nobody when nothing
  // render-relevant has changed -- but a repeat unregistration would clear
  // the active route out from under a reader standing on the page.
  //
  // This deliberately does not record whether the item is *present*, which is
  // what it used to do. Applying a theme's menu rebuilds the menu from the
  // built-in list, taking every dynamic item with it, and a model that
  // believed it had already registered had nothing to do -- so switching
  // themes took the Writing section away until the plugin was turned off and
  // on again. The menu is the only thing that knows what is in the menu.
  bool _wanted = false;

  /// update registers or unregisters the Writing nav item to match the
  /// current set of enabled plugins.
  ///
  /// Gated on the spellcheck-data capability rather than on a plugin id: the
  /// page is here to write with the writing tools, and if some other plugin
  /// provides them it earns the page just the same. This is the same
  /// question SpellcheckCapability.active answers, asked of the manager
  /// directly so that the nav does not have to wait on a dictionary being
  /// fetched before the destination appears.
  void update(PluginManagerModel plugins, MainMenuModel mainMenu) {
    var wanted = plugins.hasCapability(PluginCapability.spellcheckData);

    if (!wanted) {
      if (!_wanted) return;
      _wanted = false;
      mainMenu.unregisterDynamicItem(WritingScreen.routeName);
      return;
    }

    // Registered on every run while the plugin is on, rather than once when
    // it comes on. That is what makes the item reappear after a theme has
    // emptied the menu of dynamic items, and it costs nothing on the rebuilds
    // where nothing has changed: registerDynamicItem updates in place and
    // notifies only when something render-relevant actually differs, which is
    // also what stops this from notifying the menu it is listening to and
    // looping. The plugin nav next door has always worked this way.
    _wanted = true;
    mainMenu.registerDynamicItem(MainMenuItem(
      "Writing",
      WritingScreen.routeName,
      (context) => const WritingScreen(),
      (context) => const WritingScreenTitle(),
      const SidebarIcon(Icons.edit_note_outlined, false),
      <SubMenuInfo>[],
    ));
  }
}
