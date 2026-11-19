import 'package:bruig/models/menus.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/canvas_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// canvas_nav.dart puts the Canvas section in the navigation while the feature
// is on, through MainMenuModel's dynamic items, which route dispatch, both
// nav bars and Settings > Appearance > Menu all build off.

/// canvasMenuDrawing and canvasMenuKey are the two halves of Canvas's own
/// mark: a C drawn as an open path with its dimension lines, and the keyframe
/// the path ends in. Two files because a menu icon is tinted whole, and the
/// keyframe is the one part that keeps its own colour.
const canvasMenuDrawing = "assets/icons/icons-menu-canvas.svg";
const canvasMenuKey = "assets/icons/icons-menu-canvas-key.svg";

/// canvasKeyColor is the keyframe's orange, Bison Relay's own. It is the
/// mark's colour, not a theme's, so it is the same under every theme.
const canvasKeyColor = Color(0xFFFF7A1F);

/// CanvasMenuIcon is the Canvas entry's icon: the drawing in the colour the
/// menu gives an item, selected or not, and the keyframe over it in orange.
class CanvasMenuIcon extends StatelessWidget {
  const CanvasMenuIcon({super.key});

  @override
  Widget build(BuildContext context) {
    // The ambient IconTheme is how both nav bars say an item is selected.
    var color = IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurfaceVariant;
    // passthrough: the phone's bar gives the icon a fixed box to fill, the
    // sidebar leaves it at its own 24, and both pictures must do the same.
    return Stack(fit: StackFit.passthrough, children: [
      SvgPicture.asset(canvasMenuDrawing,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn)),
      SvgPicture.asset(canvasMenuKey,
          colorFilter: const ColorFilter.mode(canvasKeyColor, BlendMode.srcIn)),
    ]);
  }
}

/// CanvasNavModel keeps the Canvas destination in step with the preference.
/// Nothing reads it, so it must be provided eagerly (lazy: false).
class CanvasNavModel extends ChangeNotifier {
  /// _wanted guards only the removal: a repeat unregistration would clear
  /// the active route from under a reader standing on the page.
  bool _wanted = false;

  /// update registers or unregisters the nav item to match the preference.
  /// It registers on every run while the feature is on: applying a theme
  /// rebuilds the menu from the built-in list and drops every dynamic item.
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
      const CanvasMenuIcon(),
      <SubMenuInfo>[],
    ));
  }
}
