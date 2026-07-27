import 'package:bruig/models/menus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// MenuSection is an embeddable (non-routed) editor for sidebar menu items:
// inline-editable labels and Up/Down reordering buttons, backed by
// MainMenuModel.renameItem/reorderItems. Deliberately not drag-based --
// explicit buttons are unambiguous and don't depend on a platform-specific
// drag gesture to register correctly.
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

  void _move(MainMenuModel mainMenu, List<MainMenuItem> items, int index,
      int delta) {
    var newIndex = index + delta;
    if (newIndex < 0 || newIndex >= items.length) return;
    var reordered = List<MainMenuItem>.from(items);
    var item = reordered.removeAt(index);
    reordered.insert(newIndex, item);
    mainMenu.reorderItems(reordered.map((e) => e.routeName).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MainMenuModel>(builder: (context, mainMenu, _) {
      var items = mainMenu.menus.where((e) => !e.hiddenFromSideBar).toList();

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
                  onPressed:
                      i > 0 ? () => _move(mainMenu, items, i, -1) : null,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: i < items.length - 1
                      ? () => _move(mainMenu, items, i, 1)
                      : null,
                ),
              ]),
            ),
        ],
      );
    });
  }
}
