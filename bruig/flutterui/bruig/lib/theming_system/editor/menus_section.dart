import 'package:bruig/models/menus.dart';
import 'package:bruig/screens/settings.dart';
import 'package:bruig/theming_system/theme_editor.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// MenuSection is an embeddable (non-routed) editor for sidebar menu items:
// inline-editable labels, Up/Down reordering buttons, and a switch for
// whether the navigation carries the item at all. The first two are backed
// by MainMenuModel.renameItem/reorderItems, the third by the theme's
// AreaStyle.navRoutes.
//
// All three in one place because they are three facts about the same list.
// The switches used to live in the Mobile theme area and to govern only the
// phone's bottom bar, which left the desktop nav bar with no way to drop a
// destination at all -- and put "which items" a page away from "what order
// and what name", for the same items.
//
// Reordering is deliberately not drag-based -- explicit buttons are
// unambiguous and don't depend on a platform-specific drag gesture to
// register correctly.
class MenuSection extends StatefulWidget {
  const MenuSection({super.key});

  @override
  State<MenuSection> createState() => _MenuSectionState();
}

class _MenuSectionState extends State<MenuSection> {
  final Map<String, TextEditingController> _controllers = {};

  TextEditingController _controllerFor(MainMenuItem item) {
    var existing = _controllers[item.routeName];
    if (existing != null) {
      if (existing.text != item.label) existing.text = item.label;
      return existing;
    }
    var ctrl = TextEditingController(text: item.label);
    _controllers[item.routeName] = ctrl;
    return ctrl;
  }

  @override
  void dispose() {
    for (var c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _move(
      MainMenuModel mainMenu, List<MainMenuItem> items, int index, int delta) {
    var newIndex = index + delta;
    if (newIndex < 0 || newIndex >= items.length) return;
    var reordered = List<MainMenuItem>.from(items);
    var item = reordered.removeAt(index);
    reordered.insert(newIndex, item);
    mainMenu.reorderItems(reordered.map((e) => e.routeName).toList());
  }

  /// _setShown switches one destination on or off in the navigation.
  ///
  /// The list is written back in menu order, not tap order, so it reads the
  /// way the bars do, and always in full rather than as a difference from
  /// the default -- an absent route is how "off" is expressed, so a list
  /// that only recorded changes could not express it.
  ///
  /// The first such edit turns the default set into an explicit list, which
  /// is why every other item is resolved through navRouteShown rather than
  /// assumed on: the two the default leaves out would otherwise come back
  /// the moment any unrelated switch was touched.
  void _setShown(ThemeNotifier theme, List<MainMenuItem> items,
      List<String>? current, MainMenuItem item, bool on) {
    var next = [
      for (var e in items)
        if (e.routeName == item.routeName
            ? on
            : navRouteShown(e.routeName, current))
          e.routeName,
      // A route that's on but isn't in the menu right now belongs to a
      // plugin that's currently disabled. Keeping it means re-enabling the
      // plugin restores its slot, rather than this edit having quietly
      // dropped it.
      if (current != null)
        ...current.where((r) => !items.any((e) => e.routeName == r)),
    ];
    setAreaStyleOn(theme, ThemeArea.navBar, (s) => s.copyWith(navRoutes: next));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<MainMenuModel, ThemeNotifier>(
        builder: (context, mainMenu, theme, _) {
      var items = mainMenu.menus.where((e) => !e.hiddenFromSideBar).toList();
      // Null means the default set, which is not the same as all of them --
      // see defaultHiddenNavRoutes.
      var shown = theme.areaStyle(ThemeArea.navBar).navRoutes;

      return Column(
        children: [
          for (var i = 0; i < items.length; i++)
            ListTile(
              leading: items[i].icon,
              title: TextField(
                controller: _controllerFor(items[i]),
                decoration: const InputDecoration(border: InputBorder.none),
                onChanged: (v) => mainMenu.renameItem(items[i].routeName, v),
              ),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: i > 0 ? () => _move(mainMenu, items, i, -1) : null,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: i < items.length - 1
                      ? () => _move(mainMenu, items, i, 1)
                      : null,
                ),
                // Settings cannot be switched off. It is the way back to this
                // screen: with it gone from both bars there is no route to
                // the switch that would put it back, and the app would have
                // to be reinstalled to undo one tap.
                _ShownSwitch(
                  value: navRouteShown(items[i].routeName, shown),
                  onChanged: items[i].routeName == SettingsScreen.routeName
                      ? null
                      : (on) => _setShown(theme, items, shown, items[i], on),
                ),
              ]),
            ),
        ],
      );
    });
  }
}

/// _ShownSwitch is the per-item visibility switch, with the reason a
/// disabled one cannot be moved attached to it.
class _ShownSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const _ShownSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: onChanged == null
            ? "Settings always stays in the navigation -- it is the way back "
                "to this screen"
            : value
                ? "Shown in the navigation bar and the mobile bar"
                : "Hidden from both",
        child: Switch(value: value, onChanged: onChanged),
      );
}
