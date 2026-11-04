import 'package:bruig/models/menus.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_screen.dart';
import 'package:flutter/material.dart';

// canvas_nav.dart puts the Canvas section in the navigation while the feature
// is on, through MainMenuModel's dynamic items as the Writing section does:
// route dispatch, both nav bars and Settings > Appearance > Menu all build off
// MainMenuModel.menus.

/// CanvasNavModel keeps the Canvas destination in step with the preference.
///
/// Nothing reads it; it exists for the side effect, so it must be provided
/// eagerly (lazy: false).
class CanvasNavModel extends ChangeNotifier {
  /// _wanted guards only the removal: a repeat registration is harmless, but
  /// a repeat unregistration would clear the active route from under a reader
  /// standing on the page.
  bool _wanted = false;

  /// update registers or unregisters the nav item to match the preference.
  ///
  /// It registers on every run while the feature is on, not only when it
  /// comes on: applying a theme rebuilds the menu from the built-in list and
  /// drops every dynamic item.
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
