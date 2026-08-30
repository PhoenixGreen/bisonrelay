import 'package:bruig/models/menus.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_screen.dart';
import 'package:flutter/material.dart';

// canvas_nav.dart puts the Canvas section in the navigation while the feature
// is turned on, and takes it out again when it is not.
//
// The same mechanism the Writing section uses -- MainMenuModel's dynamic items
// -- and for the same reason: registering is all that is needed, because the
// route dispatch, both nav bars and Settings > Appearance > Menu all build off
// MainMenuModel.menus. What differs is only what it is gated on. See
// canvas_preferences.dart on why this one is a preference rather than a plugin
// capability.

/// hasCanvasPage is whether the Canvas section currently exists.
///
/// Asked of the menu rather than of the preference, so the one question
/// another screen wants answered -- "is there a Canvas page to send somebody
/// to?" -- is answered by whether there is one.
bool hasCanvasPage(MainMenuModel mainMenu) =>
    mainMenu.menuForRoute(CanvasScreen.routeName) != null;

/// CanvasNavModel keeps the Canvas destination in step with the preference.
///
/// It holds no state anyone reads -- it exists for the side effect -- so
/// whatever provides it must do so eagerly (lazy: false).
class CanvasNavModel extends ChangeNotifier {
  /// _wanted guards only the removal.
  ///
  /// MainMenuModel tolerates a repeat registration -- it updates in place and
  /// notifies nobody when nothing render-relevant has changed -- but a repeat
  /// unregistration would clear the active route out from under a reader
  /// standing on the page.
  bool _wanted = false;

  /// update registers or unregisters the nav item to match the preference.
  ///
  /// Registered on every run while the feature is on, rather than once when it
  /// comes on. That is what makes the item reappear after applying a theme,
  /// which rebuilds the menu from the built-in list and takes every dynamic
  /// item with it. It costs nothing on the runs where nothing has changed.
  void update(CanvasPreferences prefs, MainMenuModel mainMenu) {
    if (!prefs.enabled) {
      if (!_wanted) return;
      _wanted = false;
      mainMenu.unregisterDynamicItem(CanvasScreen.routeName);
      return;
    }

    _wanted = true;
    mainMenu.registerDynamicItem(MainMenuItem(
      "Canvas",
      CanvasScreen.routeName,
      (context) => const CanvasScreen(),
      (context) => const CanvasScreenTitle(),
      const SidebarIcon(Icons.draw_outlined, false),
      <SubMenuInfo>[],
    ));
  }
}
