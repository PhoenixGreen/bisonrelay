import 'dart:io';
import 'dart:typed_data';

import 'package:bruig/components/snackbars.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/theming_system/model/area_style.dart';
import 'package:bruig/theming_system/model/preset.dart';
import 'package:bruig/theming_system/model/theme_area.dart';
import 'package:bruig/theming_system/storage/theme_preset_storage.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

// theme_editor.dart is the entry point to the theming system's *editor* --
// the Settings > Appearance UI. It holds the whole-preset actions (new/save/
// delete/import/export/reset) and the top-level dropdowns, and is a barrel
// over editor/:
//
//   color_palette_section.dart   the "Color Palette" section.
//   areas_section.dart           the "Theme Areas" section, which dispatches
//                                to one editor/areas/<name>.dart per area.
//   area_editor_context.dart     the API those per-area files are handed.
//   editor_controls.dart         the shared slider/row/caption widgets.
//   palette_color_dropdown.dart  the palette-slot colour picker.
//   menus_section.dart           the "Menu" section.
//
// See theme_preset.dart for the model being edited and theme_manager.dart
// for the runtime that renders it.
export 'package:bruig/theming_system/editor/area_editor_context.dart';
export 'package:bruig/theming_system/editor/areas_section.dart';
export 'package:bruig/theming_system/editor/color_palette_section.dart';
export 'package:bruig/theming_system/editor/editor_controls.dart';
export 'package:bruig/theming_system/editor/menus_section.dart';
export 'package:bruig/theming_system/editor/palette_color_dropdown.dart';

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
  // Editing a theme that ships with the app forks it into one of the
  // reader's own, exactly as editing a built-in style guide does. A built-in
  // is the same on every device by definition -- that is what makes it worth
  // shipping -- so an "Ulysses" quietly edited here would mean something
  // different on this machine than on anyone else's, and there would be no
  // way back to the original short of reinstalling.
  if (existing != null && theme.isBuiltinPreset(existing.id)) {
    var fork = existing.copyWith(
        id: "preset-${DateTime.now().millisecondsSinceEpoch}",
        name: "${existing.name} (edited)");
    theme.previewPreset(fork);
    return fork;
  }
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

// setAreaStyleOn applies an edit to one area's style on the active custom
// preset, creating that preset first if the active theme is still a
// built-in (see ensureDraftPreset).
//
// The areas section reaches its own area through AreaEditorContext.setStyle,
// which comes here; this is for the parts of Appearance that edit an area
// without being one of its editors -- the Menu section, which sets the
// Navigation Bar's navRoutes beside the same items' order and names.
void setAreaStyleOn(ThemeNotifier theme, ThemeArea area,
    AreaStyle Function(AreaStyle) update) {
  var draft = ensureDraftPreset(theme);
  var current = draft.areas[area] ?? const AreaStyle();
  theme.previewPreset(
      draft.copyWith(areas: {...draft.areas, area: update(current)}));
}

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

// renamePreset asks for a new name for the active preset.
//
// A dialog rather than the inline field the dropdown used to swap itself
// for: rename now sits in the button row beside Save and Delete, matching
// the Markdown area's style-guide row, and a button that turned a *different*
// widget into a text box was hard to connect to the thing it had changed.
//
// Only the name. The id is what the theme is stored and selected under, so
// renaming leaves it alone -- this is the label, not the identity.
Future<void> renamePreset(BuildContext context, ThemeNotifier theme) async {
  var preset = theme.activePreset;
  if (preset == null) return;
  var controller = TextEditingController(text: preset.name);
  var name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text("Rename theme"),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: "Name"),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel")),
        TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text("Rename")),
      ],
    ),
  );
  if (name == null || name.trim().isEmpty) return;
  theme.previewPreset(preset.copyWith(name: name.trim()));
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
// resolution has a pre-existing bug unrelated to this feature.
//
// Renaming used to be a pencil in here that turned the dropdown into a text
// field; it is renamePreset() in the button row now, so this is only the
// picker.
class ThemeModeDropdown extends StatefulWidget {
  final ThemeNotifier theme;
  final MainMenuModel mainMenu;
  const ThemeModeDropdown(this.theme, this.mainMenu, {super.key});

  @override
  State<ThemeModeDropdown> createState() => _ThemeModeDropdownState();
}

class _ThemeModeDropdownState extends State<ThemeModeDropdown> {
  ThemeNotifier get theme => widget.theme;

  @override
  Widget build(BuildContext context) {
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

    // Capped rather than left to fill: this sits in a Wrap beside the New
    // Preset/import/export buttons, and a Wrap hands its children the whole
    // line, which isExpanded below would then take -- pushing every button
    // onto its own row. Inside the cap the dropdown still shrinks, so a
    // narrow window wraps the buttons instead of overflowing.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        // Flexible + isExpanded, and ellipsis on every label: a preset name is
        // arbitrary user text ("New Theme (unsaved)" already overflows a
        // narrow window), and a bare DropdownButton in a Row is handed
        // unbounded width, so it overflows rather than shrinking.
        Flexible(
          child: DropdownButton<String>(
            value: hasCurrent ? current : null,
            isExpanded: true,
            hint:
                Text(theme.presetDisplayName, overflow: TextOverflow.ellipsis),
            items: entries
                .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(
                          e.key == "dark"
                              ? "Default Theme"
                              : (theme
                                      .customPresets[
                                          e.key.replaceFirst("custom:", "")]
                                      ?.name ??
                                  e.value.descr),
                          overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (key) {
              if (key != null) switchToTheme(theme, widget.mainMenu, key);
            },
          ),
        ),
      ]),
    );
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
