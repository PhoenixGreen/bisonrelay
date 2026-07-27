import 'dart:io';
import 'dart:typed_data';

import 'package:bruig/components/snackbars.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/theming_system/preset.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

// theme_editor.dart is the entry point to the theming system's *editor* --
// the Settings > Appearance UI. It holds the whole-preset actions (new/save/
// delete/import/export/reset) and the top-level dropdowns, and re-exports the
// sections the settings page embeds:
//
//   color_palette_section.dart  -- the "Color Palette" section.
//   theming_areas_section.dart  -- the "Theme Areas" section, which dispatches
//                                  to one theming_area_<name>.dart per area.
//   menus.dart                  -- the "Menu" section.
//
// See theme_preset.dart for the model being edited and theme_manager.dart for
// the runtime that renders it.
export 'package:bruig/theming_system/color_palette_section.dart';
export 'package:bruig/theming_system/menus.dart';
export 'package:bruig/theming_system/theming_areas_section.dart';

// newDraftPreset builds a fresh, unsaved custom preset seeded from the
// current base brightness.
ThemePreset _newDraftPreset(ThemeNotifier theme) =>
    ThemePreset.seedFor(theme.brightness).copyWith(
        id: "preset-${DateTime.now().millisecondsSinceEpoch}",
        name: "New Theme");

// ensureDraftPreset returns the active custom preset, creating (seeding from
// the current base brightness) and activating one first if the active
// theme is still a built-in. Only call this from an actual edit action (not
// from build()) -- merely viewing the Appearance page must not silently
// switch the user off "Default Theme".
ThemePreset ensureDraftPreset(ThemeNotifier theme) {
  var existing = theme.activePreset;
  if (existing != null) return existing;

  var draft = _newDraftPreset(theme);
  theme.previewPreset(draft);
  return draft;
}

// displayPreset returns the preset whose values should currently be shown in
// the editors: the active custom preset if there is one, otherwise a
// read-only preview of the current base theme's seed colors (nothing is
// registered/activated by just looking at it).
ThemePreset displayPreset(ThemeNotifier theme) =>
    theme.activePreset ?? ThemePreset.seedFor(theme.brightness);

// createNewPreset creates a fresh custom preset and previews it live -- it
// isn't written to disk (and won't show up in the "load preset" list) until
// the user presses Save.
void createNewPreset(ThemeNotifier theme) =>
    theme.previewPreset(_newDraftPreset(theme));

// switchToTheme switches the active color theme *and* applies that theme's
// own saved menu customization (or none, for a built-in) -- every place
// that changes which theme is active must go through this (not
// theme.switchTheme directly) so a theme's menu layout travels with it.
void switchToTheme(ThemeNotifier theme, MainMenuModel mainMenu, String key) {
  theme.switchTheme(key);
  var id = key.startsWith("custom:") ? key.substring("custom:".length) : null;
  var preset = id != null ? theme.customPresets[id] : null;
  mainMenu.applyThemeMenu(preset?.menuLabels, preset?.menuOrder);
}

// resetToDefaultTheme reverts both the color theme and the menu
// rename/reorder customization back to their defaults -- a full "start
// over," not just the color theme in isolation.
void resetToDefaultTheme(ThemeNotifier theme, MainMenuModel mainMenu) {
  theme.switchTheme("dark");
  mainMenu.resetToDefault();
}

Future<void> savePreset(
    BuildContext context, ThemeNotifier theme, MainMenuModel mainMenu) async {
  if (theme.activePreset == null) {
    showErrorSnackbar(
        context, "Nothing to save yet -- change a color or area first.");
    return;
  }
  await theme.saveActivePreset(
      menuLabels: mainMenu.currentLabels(), menuOrder: mainMenu.currentOrder());
  if (context.mounted) showSuccessSnackbar(context, "Theme saved");
}

Future<void> deletePreset(BuildContext context, ThemeNotifier theme) async {
  if (theme.activePreset == null) return;
  await theme.deleteActivePreset();
  if (context.mounted) showSuccessSnackbar(context, "Theme deleted");
}

Future<void> importPresetFile(
    BuildContext context, ThemeNotifier theme, MainMenuModel mainMenu) async {
  var res = await FilePicker.platform.pickFiles(
    allowMultiple: false,
    dialogTitle: "Import theme preset",
    type: FileType.custom,
    allowedExtensions: ["zip"],
  );
  var srcPath = res?.files.first.path;
  if (srcPath == null) return;

  if (!context.mounted) return;
  try {
    var bytes = await File(srcPath).readAsBytes();
    var preset = await ThemePresetStorage.importPresetZip(bytes);
    theme.registerCustomPreset(preset, markSaved: true);
    theme.switchTheme("custom:${preset.id}");
    mainMenu.applyThemeMenu(preset.menuLabels, preset.menuOrder);
    if (context.mounted) {
      showSuccessSnackbar(context, "Imported theme \"${preset.name}\"");
    }
  } catch (exception) {
    if (context.mounted) {
      showErrorSnackbar(context, "Unable to import preset: $exception");
    }
  }
}

Future<void> exportPresetFile(BuildContext context, ThemeNotifier theme) async {
  var preset = theme.activePreset;
  if (preset == null) {
    showErrorSnackbar(
        context, "Only custom presets can be exported. Edit a color first.");
    return;
  }

  var destPath = await FilePicker.platform.saveFile(
    dialogTitle: "Export theme preset",
    fileName: "${preset.id}.zip",
    type: FileType.custom,
    allowedExtensions: ["zip"],
  );
  if (destPath == null) return;

  if (!context.mounted) return;
  try {
    Uint8List bytes = await ThemePresetStorage.exportPresetZip(preset.id);
    await File(destPath).writeAsBytes(bytes);
    if (context.mounted) {
      showSuccessSnackbar(context, "Exported theme to $destPath");
    }
  } catch (exception) {
    if (context.mounted) {
      showErrorSnackbar(context, "Unable to export preset: $exception");
    }
  }
}

// ThemeModeDropdown picks the active theme: built-in dark/light or any
// registered custom preset. "system" is intentionally hidden -- its
// resolution has a pre-existing bug unrelated to this feature. When the
// active theme is an editable custom preset, a small pencil toggles the
// dropdown into an inline rename field in the same slot, rather than having
// a separate always-visible name field taking up its own row.
class ThemeModeDropdown extends StatefulWidget {
  final ThemeNotifier theme;
  final MainMenuModel mainMenu;
  const ThemeModeDropdown(this.theme, this.mainMenu, {super.key});

  @override
  State<ThemeModeDropdown> createState() => _ThemeModeDropdownState();
}

class _ThemeModeDropdownState extends State<ThemeModeDropdown> {
  bool _renaming = false;
  final _ctrl = TextEditingController();

  ThemeNotifier get theme => widget.theme;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _startRename(ThemePreset preset) {
    _ctrl.text = preset.name;
    setState(() => _renaming = true);
  }

  void _commitRename(ThemePreset preset) {
    theme.previewPreset(preset.copyWith(name: _ctrl.text));
    setState(() => _renaming = false);
  }

  @override
  Widget build(BuildContext context) {
    var preset = theme.activePreset;

    if (_renaming && preset != null) {
      return SizedBox(
        width: 220,
        child: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: "Preset name"),
          onSubmitted: (_) => _commitRename(preset),
          onTapOutside: (_) => _commitRename(preset),
        ),
      );
    }

    // Only list saved presets -- an in-progress (unsaved) edit shouldn't
    // show up as a selectable "preset" until the user presses Save.
    var entries = appThemes.entries
        .where((e) =>
            e.key == "dark" ||
            e.key == "light" ||
            (e.key.startsWith("custom:") &&
                theme.isPresetSaved(e.key.substring("custom:".length))))
        .toList();
    var current = theme.getThemeMode();
    var hasCurrent = entries.any((e) => e.key == current);

    return Row(mainAxisSize: MainAxisSize.min, children: [
      DropdownButton<String>(
        value: hasCurrent ? current : null,
        hint: Text(theme.presetDisplayName),
        items: entries
            .map((e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(e.key == "dark"
                      ? "Default Theme"
                      : (theme.customPresets[e.key.replaceFirst("custom:", "")]
                              ?.name ??
                          e.value.descr)),
                ))
            .toList(),
        onChanged: (key) {
          if (key != null) switchToTheme(theme, widget.mainMenu, key);
        },
      ),
      if (preset != null)
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 18),
          tooltip: "Rename",
          onPressed: () => _startRename(preset),
        ),
    ]);
  }
}

// FontSizeDropdown picks the global text-scale factor.
class FontSizeDropdown extends StatelessWidget {
  final ThemeNotifier theme;
  const FontSizeDropdown(this.theme, {super.key});

  @override
  Widget build(BuildContext context) => DropdownButton<String>(
        value: appFontSizeKeyForScale(theme.fontScale),
        items: appFontSizes.entries
            .map((e) =>
                DropdownMenuItem(value: e.key, child: Text(e.value.descr)))
            .toList(),
        onChanged: (key) {
          if (key != null) theme.setFontSize(appFontSizes[key]?.scale ?? 1);
        },
      );
}

// ImageSizeDropdown picks how large chat images are displayed.
class ImageSizeDropdown extends StatelessWidget {
  final ThemeNotifier theme;
  const ImageSizeDropdown(this.theme, {super.key});

  @override
  Widget build(BuildContext context) => DropdownButton<String>(
        value: theme.chatImageSize,
        items: appImageSizes.entries
            .map((e) =>
                DropdownMenuItem(value: e.key, child: Text(e.value.descr)))
            .toList(),
        onChanged: (key) {
          if (key != null) theme.setChatImageSize(key);
        },
      );
}
