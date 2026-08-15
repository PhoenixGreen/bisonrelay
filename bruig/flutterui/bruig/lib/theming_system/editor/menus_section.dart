import 'package:bruig/components/text.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/screens/settings.dart';
import 'package:bruig/theming_system/storage/theme_preset_storage.dart';
import 'package:file_picker/file_picker.dart';
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
              leading: _IconButton(item: items[i], mainMenu: mainMenu),
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

/// _IconButton is the item's own icon, used as the control that changes it.
///
/// The icon is the button rather than sitting beside one: it is small, it is
/// already in the row, and what you press is exactly what you are about to
/// replace. An item with no icon at all (the Address Book's, before one is
/// chosen) still needs somewhere to press, so it shows an outline instead of
/// nothing.
class _IconButton extends StatelessWidget {
  final MainMenuItem item;
  final MainMenuModel mainMenu;
  const _IconButton({required this.item, required this.mainMenu});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: "Change icon",
        child: InkWell(
          onTap: () => _pickMenuIcon(context, mainMenu, item),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: SizedBox(
              width: 24,
              height: 24,
              child: item.icon ??
                  Icon(Icons.add_photo_alternate_outlined,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      );
}

/// _pickMenuIcon opens the icon chooser for one menu item.
///
/// Choosing writes straight through to the live menu (and so to the preview),
/// like renaming does -- it is not saved anywhere until the theme is, which
/// is what makes trying a few of them and settling on none of them free.
Future<void> _pickMenuIcon(
    BuildContext context, MainMenuModel mainMenu, MainMenuItem item) async {
  // listen: false -- this runs from a tap, not from a build, and the default
  // (listening) form asserts outright when called from an event handler.
  var theme = ThemeNotifier.of(context, listen: false);
  var choice = await showDialog<_IconChoice>(
    context: context,
    builder: (context) => _IconPickerDialog(item: item, mainMenu: mainMenu),
  );
  if (choice == null) return;

  switch (choice.kind) {
    case _IconChoiceKind.reset:
      mainMenu.setItemIcon(item.routeName, null);
    case _IconChoiceKind.bundled:
      mainMenu.setItemIcon(item.routeName, choice.assetPath);
    case _IconChoiceKind.file:
      var res = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        dialogTitle: "Pick menu icon",
        type: FileType.custom,
        allowedExtensions: const ["svg"],
      );
      var srcPath = res?.files.first.path;
      if (srcPath == null) return;
      // The file is copied into the preset's own directory, so the icon is
      // part of the theme and travels with an export -- the same treatment
      // area background images get. That needs a preset to copy *into*,
      // hence the draft, and its directory has to be published right away
      // or nothing can resolve the path until the preset happens to be
      // saved (see AreasSection.copyPickedImage, which says the same).
      var draft = ensureDraftPreset(theme);
      var relPath = await ThemePresetStorage.saveMenuIcon(
          draft.id, item.routeName, srcPath);
      var presetDir = await ThemePresetStorage.presetDir(draft.id);
      theme.previewPreset(draft.copyWith(sourceDir: presetDir));
      mainMenu.setItemIcon(item.routeName, relPath);
  }
}

enum _IconChoiceKind { bundled, file, reset }

class _IconChoice {
  final _IconChoiceKind kind;
  final String? assetPath;
  const _IconChoice(this.kind, [this.assetPath]);
}

class _IconPickerDialog extends StatelessWidget {
  final MainMenuItem item;
  final MainMenuModel mainMenu;
  const _IconPickerDialog({required this.item, required this.mainMenu});

  @override
  Widget build(BuildContext context) {
    var cs = Theme.of(context).colorScheme;
    var current = mainMenu.iconPathFor(item.routeName);
    return AlertDialog(
      title: Text("Icon for ${item.label}"),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var asset in bundledMenuIcons)
                _IconTile(
                  selected: current == asset,
                  onTap: () => Navigator.of(context)
                      .pop(_IconChoice(_IconChoiceKind.bundled, asset)),
                  child: MenuIcon(asset),
                ),
              // The user's own icon, when one is set, sits at the end of the
              // same row rather than in a section of its own -- it is one
              // more of the choices, and showing it is how you can tell
              // which one is currently picked.
              if (current != null && !MenuIcon.isAsset(current))
                _IconTile(
                  selected: true,
                  onTap: () => Navigator.of(context).pop(),
                  child: MenuIcon(current),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // A Wrap rather than a Row with a Spacer: the two buttons sit at
          // either end while they both fit and drop onto a second line when
          // they don't. A Row pins them to one line at their full width,
          // which overflowed as soon as the labels grew -- a larger font
          // scale is enough to do it.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context)
                    .pop(const _IconChoice(_IconChoiceKind.file)),
                icon: const Icon(Icons.folder_open),
                label: const Text("Choose SVG..."),
              ),
              // Disabled while the item still has its built-in icon: there is
              // nothing to undo, and an enabled button that does nothing reads
              // as broken.
              TextButton.icon(
                onPressed: current == null
                    ? null
                    : () => Navigator.of(context)
                        .pop(const _IconChoice(_IconChoiceKind.reset)),
                icon: const Icon(Icons.restart_alt),
                label: const Text("Default"),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Txt.S(
            "SVG only, and drawn in the navigation's own text color -- a "
            "multi-colored icon will come out one color.",
            color: TextColor.onSurfaceVariant,
          ),
          const SizedBox(height: 4),
          if (current != null && !MenuIcon.isAsset(current))
            Txt.S("Copied into this theme, so exporting it takes the icon too.",
                color: TextColor.onSurfaceVariant),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel")),
      ],
      backgroundColor: cs.surface,
    );
  }
}

class _IconTile extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  const _IconTile(
      {required this.selected, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    var cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 48,
        height: 48,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
              width: selected ? 2 : 1),
        ),
        child: child,
      ),
    );
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
