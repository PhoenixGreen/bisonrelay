import 'dart:io';
import 'dart:typed_data';

import 'package:bruig/components/snackbars.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/models/palette_library.dart';
import 'package:bruig/models/theme_preset.dart';
import 'package:bruig/palette_library_storage.dart';
import 'package:bruig/theme_manager.dart';
import 'package:bruig/theme_preset_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

// ensureDraftPreset returns the active custom preset, creating (seeding from
// the current base brightness) and activating one first if the active
// theme is still a built-in. Only call this from an actual edit action (not
// from build()) -- merely viewing the Appearance page must not silently
// switch the user off "Default Theme".
ThemePreset ensureDraftPreset(ThemeNotifier theme) {
  var existing = theme.activePreset;
  if (existing != null) return existing;

  var seed = theme.brightness == Brightness.dark
      ? ThemePreset.seedFromDark()
      : ThemePreset.seedFromLight();
  var withId = seed.copyWith(
      id: "preset-${DateTime.now().millisecondsSinceEpoch}",
      name: "New Theme");
  theme.previewPreset(withId);
  return withId;
}

// displayPreset returns the preset whose values should currently be shown in
// the editors: the active custom preset if there is one, otherwise a
// read-only preview of the current base theme's seed colors (nothing is
// registered/activated by just looking at it).
ThemePreset displayPreset(ThemeNotifier theme) =>
    theme.activePreset ??
    (theme.brightness == Brightness.dark
        ? ThemePreset.seedFromDark()
        : ThemePreset.seedFromLight());

// PaletteColorDropdown lets the user pick one of the active palette's 10
// colors (plus, optionally, "None") for a single field -- no popup dialog,
// just a standard dropdown menu.
class PaletteColorDropdown extends StatelessWidget {
  final ThemePreset preset;
  final Color? value;
  final ValueChanged<Color?> onChanged;
  final bool allowNone;
  const PaletteColorDropdown(
      {required this.preset,
      required this.value,
      required this.onChanged,
      this.allowNone = false,
      super.key});

  Widget _swatch(Color color) => Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(3),
        ),
      );

  @override
  Widget build(BuildContext context) {
    var palette = preset.palette;
    var matchIdx = value == null
        ? -1
        : palette.indexWhere((c) => c.toARGB32() == value!.toARGB32());
    // -1 is only a valid dropdown value when a "None" item is present (i.e.
    // allowNone). Otherwise (e.g. value is an off-palette color, or null on
    // a field that's supposed to always carry a real color) fall back to
    // the first palette entry rather than passing an unmatched value to
    // DropdownButton, which asserts on that.
    if (matchIdx < 0 && !allowNone) matchIdx = 0;

    return DropdownButton<int>(
      value: matchIdx,
      items: [
        if (allowNone)
          const DropdownMenuItem(value: -1, child: Text("None")),
        for (var i = 0; i < PaletteSlot.values.length; i++)
          DropdownMenuItem(
            value: i,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _swatch(palette[i]),
              const SizedBox(width: 8),
              Text(paletteSlotLabel(PaletteSlot.values[i])),
            ]),
          ),
      ],
      onChanged: (i) {
        if (i == null || i < 0) {
          onChanged(null);
        } else {
          onChanged(palette[i]);
        }
      },
    );
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
  Widget build(BuildContext context) {
    return DropdownButton<String>(
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
}

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

// createNewPreset creates a fresh custom preset (seeded from the current
// base brightness) and previews it live -- it isn't written to disk (and
// won't show up in the "load preset" list) until the user presses Save.
void createNewPreset(ThemeNotifier theme) {
  var seed = theme.brightness == Brightness.dark
      ? ThemePreset.seedFromDark()
      : ThemePreset.seedFromLight();
  var withId = seed.copyWith(
      id: "preset-${DateTime.now().millisecondsSinceEpoch}",
      name: "New Theme");
  theme.previewPreset(withId);
}

Future<void> importPresetFile(
    BuildContext context, ThemeNotifier theme, MainMenuModel mainMenu) async {
  var res = await FilePicker.platform.pickFiles(
    allowMultiple: false,
    dialogTitle: "Import theme preset",
    type: FileType.custom,
    allowedExtensions: ["zip"],
  );
  if (res == null) return;
  var path = res.files.first.path;
  if (path == null) return;

  if (!context.mounted) return;
  try {
    var bytes = await File(path).readAsBytes();
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

// resetToDefaultTheme reverts both the color theme and the menu
// rename/reorder customization back to their defaults -- a full "start
// over," not just the color theme in isolation.
void resetToDefaultTheme(ThemeNotifier theme, MainMenuModel mainMenu) {
  theme.switchTheme("dark");
  mainMenu.resetToDefault();
}

// PaletteSection is an embeddable (non-routed) editor for the active
// preset's 10-color palette. Tapping a color expands an inline picker in
// place -- no modal popups -- committed via a "Done" button so a single
// disk write happens per edit instead of one per drag frame.
// PaletteSwatchStrip renders a row of colors as a thin horizontal bar --
// used both for the collapsed-section preview (see PaletteExpansionTile)
// and for each palette-library card's thumbnail.
class PaletteSwatchStrip extends StatelessWidget {
  final List<Color> colors;
  final double height;
  const PaletteSwatchStrip({required this.colors, this.height = 14, super.key});

  @override
  Widget build(BuildContext context) {
    if (colors.isEmpty) return SizedBox(height: height);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: height,
        child: Row(
            children: colors.map((c) => Expanded(child: Container(color: c))).toList()),
      ),
    );
  }
}

// PaletteExpansionTile wraps PaletteSection with a collapsed-state preview
// (a horizontal strip of the active preset's current palette) so the
// active palette is visible at a glance without expanding the section.
class PaletteExpansionTile extends StatefulWidget {
  const PaletteExpansionTile({super.key});

  @override
  State<PaletteExpansionTile> createState() => _PaletteExpansionTileState();
}

class _PaletteExpansionTileState extends State<PaletteExpansionTile> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(builder: (context, theme, _) {
      var preset = displayPreset(theme);
      return ExpansionTile(
        title: const Txt.S("Color Palette"),
        subtitle: !expanded
            ? Padding(
                padding: const EdgeInsets.only(top: 6, right: 16),
                child: PaletteSwatchStrip(colors: preset.palette),
              )
            : null,
        initiallyExpanded: false,
        onExpansionChanged: (v) => setState(() => expanded = v),
        children: const [PaletteSection()],
      );
    });
  }
}

class PaletteSection extends StatefulWidget {
  const PaletteSection({super.key});

  @override
  State<PaletteSection> createState() => _PaletteSectionState();
}

class _PaletteSectionState extends State<PaletteSection> {
  int? expandedIndex; // index into displayPreset(theme).palette
  Color? draftColor;
  List<ColorPalette> userPalettes = [];

  @override
  void initState() {
    super.initState();
    _loadUserPalettes();
  }

  void _loadUserPalettes() async {
    var palettes = await PaletteLibraryStorage.listPalettes();
    if (mounted) setState(() => userPalettes = palettes);
  }

  Future<String?> _promptForName(String title, String hint) {
    var ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.of(context).pop(ctrl.text),
              child: const Text("Save")),
        ],
      ),
    );
  }

  Future<void> _saveCurrentAsPalette(ThemeNotifier theme) async {
    var preset = displayPreset(theme);
    var name = await _promptForName("Save Palette", "Palette name");
    if (name == null || name.trim().isEmpty) return;
    var palette = ColorPalette(
      id: "palette-${DateTime.now().millisecondsSinceEpoch}",
      name: name.trim(),
      colors: kVividPaletteSlots.map(preset.forSlot).toList(),
    );
    await PaletteLibraryStorage.savePalette(palette);
    if (!mounted) return;
    setState(() => userPalettes = [...userPalettes, palette]);
  }

  // _paletteSurfaceFor derives a background neutral tinted with the
  // palette's own primary hue, but kept dark-or-light-appropriate for the
  // active preset's brightness -- masterBackground/navBar/subMenuTabBar
  // (and everything else left at their default "token" styling) all read
  // this surface color (and its derived container tones), so without this
  // the whole rest of the app never visibly reacted to picking a palette.
  Color _paletteSurfaceFor(Color primary, Brightness brightness) {
    var hsl = HSLColor.fromColor(primary);
    var lightness = brightness == Brightness.dark ? 0.09 : 0.97;
    var saturation = (hsl.saturation * (brightness == Brightness.dark ? 0.35 : 0.25))
        .clamp(0.0, 1.0);
    return hsl.withSaturation(saturation).withLightness(lightness).toColor();
  }

  Color _paletteOnSurfaceFor(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xFFE6E1E5)
      : const Color(0xFF1A1A1A);

  Color _paletteOutlineFor(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xFF938F99)
      : const Color(0xFF79747E);

  // Text-on-accent should stay legible regardless of how light/dark the
  // palette's own accent color happens to be.
  Color _paletteOnAccentFor(Color accent) =>
      HSLColor.fromColor(accent).lightness > 0.55
          ? const Color(0xFF1A1A1A)
          : Colors.white;

  void _applyPalette(ThemeNotifier theme, ColorPalette palette) {
    var draft = ensureDraftPreset(theme);
    var updated = draft;
    for (var i = 0; i < kVividPaletteSlots.length && i < palette.colors.length; i++) {
      updated = updated.withSlot(kVividPaletteSlots[i], palette.colors[i]);
    }
    var primary = palette.colors.isNotEmpty ? palette.colors[0] : draft.primary;
    var accent = palette.colors.length > 4 ? palette.colors[4] : primary;
    updated = updated.copyWith(
      surface: _paletteSurfaceFor(primary, draft.brightness),
      onSurface: _paletteOnSurfaceFor(draft.brightness),
      outline: _paletteOutlineFor(draft.brightness),
      onAccent: _paletteOnAccentFor(accent),
    );
    theme.previewPreset(updated);
  }

  Future<void> _exportPalette(ColorPalette palette) async {
    var destPath = await FilePicker.platform.saveFile(
      dialogTitle: "Export color palette",
      fileName: "${palette.name.replaceAll(' ', '_')}.json",
      type: FileType.custom,
      allowedExtensions: ["json"],
    );
    if (destPath == null) return;
    var bytes = await PaletteLibraryStorage.exportPalette(palette);
    await File(destPath).writeAsBytes(bytes);
    if (mounted) showSuccessSnackbar(context, "Exported palette to $destPath");
  }

  Future<void> _importPalette() async {
    var res = await FilePicker.platform.pickFiles(
      dialogTitle: "Import color palette",
      type: FileType.custom,
      allowedExtensions: ["json"],
    );
    if (res == null) return;
    var filePath = res.files.first.path;
    if (filePath == null) return;
    try {
      var bytes = await File(filePath).readAsBytes();
      var palette = await PaletteLibraryStorage.importPalette(bytes);
      if (!mounted) return;
      setState(() => userPalettes = [...userPalettes, palette]);
      showSuccessSnackbar(context, "Imported palette \"${palette.name}\"");
    } catch (exception) {
      if (mounted) {
        showErrorSnackbar(context, "Unable to import palette: $exception");
      }
    }
  }

  Future<void> _deletePalette(ColorPalette palette) async {
    await PaletteLibraryStorage.deletePalette(palette.id);
    if (!mounted) return;
    setState(() =>
        userPalettes = userPalettes.where((p) => p.id != palette.id).toList());
  }

  Widget _paletteCard(ThemeNotifier theme, ColorPalette palette) {
    return InkWell(
      onTap: () => _applyPalette(theme, palette),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 150,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(6)),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PaletteSwatchStrip(colors: palette.colors, height: 28),
              const SizedBox(height: 6),
              SizedBox(
                height: 22,
                child: Row(children: [
                  Expanded(
                      child: Txt.S(palette.name,
                          overflow: TextOverflow.ellipsis)),
                  SizedBox(
                    height: 22,
                    width: 22,
                    child: PopupMenuButton<String>(
                      iconSize: 16,
                      padding: EdgeInsets.zero,
                      onSelected: (v) {
                        if (v == "export") _exportPalette(palette);
                        if (v == "delete") _deletePalette(palette);
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                            value: "export", child: Text("Export")),
                        if (!palette.builtin)
                          const PopupMenuItem(
                              value: "delete", child: Text("Delete")),
                      ],
                    ),
                  ),
                ]),
              ),
            ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(builder: (context, theme, _) {
      var preset = displayPreset(theme);
      var fullPalette = preset.palette;
      var seed = theme.brightness == Brightness.dark
          ? ThemePreset.seedFromDark()
          : ThemePreset.seedFromLight();
      var defaultPalette = ColorPalette(
        id: "default",
        name: "Default Theme",
        builtin: true,
        colors: kVividPaletteSlots.map(seed.forSlot).toList(),
      );
      var allPalettes = [defaultPalette, ...builtinPalettes, ...userPalettes];
      var canAddMore =
          preset.extraPaletteColors.length < kMaxExtraPaletteColors;

      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Expanded(
              child: SizedBox(
                height: 92,
                child: ListView(
                    scrollDirection: Axis.horizontal,
                    children:
                        allPalettes.map((p) => _paletteCard(theme, p)).toList()),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
                onPressed: () => _saveCurrentAsPalette(theme),
                icon: const Icon(Icons.save_outlined),
                tooltip: "Save current palette"),
            IconButton(
                onPressed: _importPalette,
                icon: const Icon(Icons.file_upload_outlined),
                tooltip: "Import palette"),
          ]),
        ),
        const Divider(),
        ...List.generate(fullPalette.length, (i) {
          var isSlot = i < PaletteSlot.values.length;
          var label = isSlot
              ? paletteSlotLabel(PaletteSlot.values[i])
              : "Extra color ${i - PaletteSlot.values.length + 1}";
          var isExpanded = expandedIndex == i;
          var color = isExpanded ? (draftColor ?? fullPalette[i]) : fullPalette[i];

          return Column(children: [
            ListTile(
              title: Txt(label),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                if (!isSlot)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: "Remove color",
                    onPressed: () {
                      var extraIdx = i - PaletteSlot.values.length;
                      var draft = ensureDraftPreset(theme);
                      var updatedExtras =
                          List<Color>.from(draft.extraPaletteColors)
                            ..removeAt(extraIdx);
                      setState(() {
                        if (expandedIndex == i) {
                          expandedIndex = null;
                          draftColor = null;
                        }
                      });
                      theme.previewPreset(
                          draft.copyWith(extraPaletteColors: updatedExtras));
                    },
                  ),
              ]),
              onTap: () => setState(() {
                if (isExpanded) {
                  expandedIndex = null;
                  draftColor = null;
                } else {
                  expandedIndex = i;
                  draftColor = fullPalette[i];
                }
              }),
            ),
            if (isExpanded)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(children: [
                  ColorPicker(
                    pickerColor: draftColor ?? fullPalette[i],
                    enableAlpha: false,
                    hexInputBar: true,
                    onColorChanged: (c) => setState(() => draftColor = c),
                  ),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(
                      onPressed: () => setState(() {
                        expandedIndex = null;
                        draftColor = null;
                      }),
                      child: const Text("Cancel"),
                    ),
                    TextButton(
                      onPressed: () {
                        var draft = ensureDraftPreset(theme);
                        var chosen = draftColor ?? fullPalette[i];
                        ThemePreset updated;
                        if (isSlot) {
                          updated =
                              draft.withSlot(PaletteSlot.values[i], chosen);
                        } else {
                          var extraIdx = i - PaletteSlot.values.length;
                          var colors =
                              List<Color>.from(draft.extraPaletteColors);
                          colors[extraIdx] = chosen;
                          updated = draft.copyWith(extraPaletteColors: colors);
                        }
                        setState(() {
                          expandedIndex = null;
                          draftColor = null;
                        });
                        theme.previewPreset(updated);
                      },
                      child: const Text("Done"),
                    ),
                  ]),
                ]),
              ),
          ]);
        }),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: OutlinedButton.icon(
            onPressed: canAddMore
                ? () {
                    var draft = ensureDraftPreset(theme);
                    theme.previewPreset(draft.copyWith(extraPaletteColors: [
                      ...draft.extraPaletteColors,
                      Colors.grey,
                    ]));
                  }
                : null,
            icon: const Icon(Icons.add),
            label: Text(canAddMore
                ? "Add Color"
                : "Maximum of $kMaxPaletteColors colors reached"),
          ),
        ),
      ]);
    });
  }
}

// _editableAreas are every ThemeArea whose rendering has been wired to
// consult per-area styling (see ThemedArea usages across overview.dart,
// sidebar.dart, startupscreen.dart, containers.dart and the MainMenuItem
// area tags in models/menus.dart).
const List<ThemeArea> _editableAreas = [
  ThemeArea.masterBackground,
  ThemeArea.header,
  ThemeArea.loginScreen,
  ThemeArea.navBar,
  ThemeArea.subMenuTabBar,
  ThemeArea.chat,
  ThemeArea.feed,
  ThemeArea.realtimeChat,
  ThemeArea.lnManagement,
  ThemeArea.pages,
  ThemeArea.manageContent,
  ThemeArea.stats,
  ThemeArea.logs,
];

// AreasSection is an embeddable (non-routed) editor for per-area background/
// border styling, sourcing every color from the active palette via
// dropdowns (see PaletteColorDropdown) rather than a color-picker popup.
class AreasSection extends StatefulWidget {
  const AreasSection({super.key});

  @override
  State<AreasSection> createState() => _AreasSectionState();
}

class _AreasSectionState extends State<AreasSection> {
  ThemeArea selected = _editableAreas.first;
  final Map<String, double> _dragValues = {};

  Future<void> _pickImage(ThemeNotifier theme, ThemePreset preset,
      {required bool forBorder}) async {
    var res = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      dialogTitle: "Pick ${forBorder ? 'border' : 'background'} image",
      type: FileType.custom,
      allowedExtensions: ["bmp", "gif", "jpeg", "jpg", "png", "webp"],
    );
    if (res == null) return;
    var path = res.files.first.path;
    if (path == null) return;

    var draft = ensureDraftPreset(theme);
    var relPath = await ThemePresetStorage.saveAreaImage(
        draft.id, selected, path,
        suffix: forBorder ? "border" : "bg");
    // saveAreaImage copies the file to disk immediately (even for an
    // unsaved draft), so sourceDir must be set right away too -- otherwise
    // the preview (and eventual rendering) can't resolve imagePath until
    // the preset happens to get saved/reloaded.
    var presetDir = await ThemePresetStorage.presetDir(draft.id);
    var current = draft.areas[selected] ?? const AreaStyle();
    var style = forBorder
        ? current.copyWith(
            borderMode: AreaBackgroundMode.image, borderImagePath: relPath)
        : current.copyWith(
            mode: AreaBackgroundMode.image, imagePath: relPath);
    theme.previewPreset(draft.copyWith(
        sourceDir: presetDir, areas: {...draft.areas, selected: style}));
  }

  // _imagePreview shows a thumbnail of the currently selected image (or a
  // _imagePreview shows the user's own picked image if one is set;
  // otherwise, for areas with a built-in default image (currently just the
  // login screen's pattern), shows that as a reference so users can see
  // what's currently active before deciding to replace it; otherwise a
  // plain placeholder. Uses BoxFit.contain (not cover) deliberately -- the
  // source images here are full-screen-sized (e.g. 1024x768), and cover
  // would crop a tiny, often near-blank corner of a sparse pattern into the
  // thumbnail instead of showing the whole image shrunk down.
  Widget _imagePreview(String? relPath, String? sourceDir,
      {String? defaultAssetPath}) {
    const size = 64.0;
    ImageProvider? image;
    if (relPath != null && sourceDir != null) {
      image = FileImage(File(path.join(sourceDir, relPath)));
    } else if (defaultAssetPath != null) {
      image = AssetImage(defaultAssetPath);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // A neutral mid-grey backdrop (not just the surrounding page
        // background) so a sparse/mostly-dark or mostly-transparent image
        // still reads as "there's an image here" at this small a size,
        // instead of blending into a dark theme's own background.
        color: image != null ? Colors.grey.shade700 : null,
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(4),
        image: image != null
            ? DecorationImage(image: image, fit: BoxFit.contain)
            : null,
      ),
      child: image == null
          ? const Icon(Icons.image_outlined, color: Colors.grey)
          : null,
    );
  }

  // _setStyle always re-reads the current style fresh (via ensureDraftPreset,
  // not a build()-scoped closure variable) before applying `update` --
  // needed because a single user action can trigger two calls in a row
  // (e.g. picking a color both switches mode to Solid *and* sets the
  // color); if each call started from the same stale outer `style` snapshot
  // instead of the just-updated one, the second call would silently
  // discard the first.
  void _setStyle(ThemeNotifier theme, AreaStyle Function(AreaStyle) update) {
    var draft = ensureDraftPreset(theme);
    var current = draft.areas[selected] ?? const AreaStyle();
    var next = update(current);
    theme.previewPreset(
        draft.copyWith(areas: {...draft.areas, selected: next}));
  }

  // _slider is a drag-buffered Slider (only commits to previewPreset -- and
  // so only writes to the preset -- when the drag ends, not per-frame).
  Widget _slider(String key, String label, double value, double min,
      double max, ValueChanged<double> onCommit) {
    var shown = _dragValues[key] ?? value;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("$label: ${shown.toStringAsFixed(1)}"),
      Slider(
        value: shown,
        min: min,
        max: max,
        onChanged: (v) => setState(() => _dragValues[key] = v),
        onChangeEnd: (v) {
          setState(() => _dragValues.remove(key));
          onCommit(v);
        },
      ),
    ]);
  }

  // _widthSlider is a Width control where the minimum (0) means "use this
  // area's built-in default width" (AreaStyle.width left null) rather than
  // an actual zero-width panel -- dragging above 0 sets an explicit
  // override in pixels. This keeps "reset to default" reachable directly
  // from the slider instead of requiring a separate reset affordance.
  Widget _widthSlider(ThemeNotifier theme, AreaStyle style) {
    const key = "width";
    var shown = _dragValues[key] ?? style.width ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(shown <= 0 ? "Width: Default" : "Width: ${shown.toStringAsFixed(1)}"),
      Slider(
        value: shown,
        min: 0,
        max: 400,
        onChanged: (v) => setState(() => _dragValues[key] = v),
        onChangeEnd: (v) {
          setState(() => _dragValues.remove(key));
          if (v <= 0) {
            _setStyle(theme, (s) => s.copyWith(clearWidth: true));
          } else {
            _setStyle(theme, (s) => s.copyWith(width: v));
          }
        },
      ),
    ]);
  }

  // _glowSlider controls the intensity of the selected-row glow in the chat
  // list (AreaStyle.chatListGlowIntensity). 0 turns the glow off entirely;
  // 1.0 (the default when unset) matches the original design; above 1
  // exaggerates it.
  Widget _glowSlider(ThemeNotifier theme, AreaStyle style) {
    const key = "chatListGlowIntensity";
    var shown = _dragValues[key] ?? style.chatListGlowIntensity ?? 1.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(shown <= 0.05
          ? "Selected glow: Off"
          : "Selected glow: ${shown.toStringAsFixed(1)}"),
      Slider(
        value: shown,
        min: 0,
        max: 2,
        onChanged: (v) => setState(() => _dragValues[key] = v),
        onChangeEnd: (v) {
          setState(() => _dragValues.remove(key));
          _setStyle(theme, (s) => s.copyWith(chatListGlowIntensity: v));
        },
      ),
    ]);
  }

  // _expandPaddingSlider controls the space around the whole conversation
  // viewport (top, sides, and before the input bar) when
  // AreaStyle.expandMessageWidth is on (AreaStyle.expandMessagePadding); 0
  // (the default when unset) fills the panel edge-to-edge.
  Widget _expandPaddingSlider(ThemeNotifier theme, AreaStyle style) {
    const key = "expandMessagePadding";
    var shown = _dragValues[key] ?? style.expandMessagePadding ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("Panel padding: ${shown.toStringAsFixed(1)}"),
      Slider(
        value: shown,
        min: 0,
        max: 48,
        onChanged: (v) => setState(() => _dragValues[key] = v),
        onChangeEnd: (v) {
          setState(() => _dragValues.remove(key));
          _setStyle(theme, (s) => s.copyWith(expandMessagePadding: v));
        },
      ),
    ]);
  }

  // _fillEditor builds the mode dropdown + conditional color/gradient-
  // direction/image controls shared by both the background and the border
  // fill -- they support the same four modes, just against different
  // AreaStyle fields. Color and Image are shown side by side (not nested
  // under separate mode selections) since picking either one is just a
  // different way to fill the same area -- picking a color switches to
  // Solid, picking an image switches to Image.
  Widget _fillEditor({
    required ThemePreset preset,
    required String? sourceDir,
    required String label,
    required String tokenLabel,
    required AreaBackgroundMode mode,
    required ValueChanged<AreaBackgroundMode> onModeChanged,
    required Color? solidColor,
    required ValueChanged<Color?> onSolidChanged,
    required List<Color> gradientColors,
    required void Function(int index, Color? c) onGradientColorChanged,
    required Alignment gradientBegin,
    required Alignment gradientEnd,
    required ValueChanged<GradientDirection> onDirectionChanged,
    required bool allowSolidNone,
    required String? imagePath,
    required VoidCallback onPickImage,
    VoidCallback? onRemoveImage,
    String? defaultAssetPath,
    // Only meaningful for the background fill -- the border already has an
    // equivalent "no border at all" via its own token/tokenLabel ("None"),
    // so a separate none entry there would just be a confusing duplicate.
    bool supportsNone = false,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Txt("$label: "),
        const SizedBox(width: 8),
        DropdownButton<AreaBackgroundMode>(
          value: mode,
          items: [
            DropdownMenuItem(
                value: AreaBackgroundMode.token, child: Text(tokenLabel)),
            if (supportsNone)
              const DropdownMenuItem(
                  value: AreaBackgroundMode.none, child: Text("None")),
            const DropdownMenuItem(
                value: AreaBackgroundMode.gradient, child: Text("Gradient")),
            // Solid/Image aren't meant to be picked from here directly
            // (use the Color/Image controls below instead), but they must
            // still be valid items -- the style's mode can already be one
            // of these (existing data, or set via those controls), and
            // DropdownButton asserts if `value` doesn't match any item.
            const DropdownMenuItem(
                value: AreaBackgroundMode.solid, child: Text("Solid")),
            const DropdownMenuItem(
                value: AreaBackgroundMode.image, child: Text("Image")),
          ],
          onChanged: (m) {
            if (m != null) onModeChanged(m);
          },
        ),
      ]),
      if (mode == AreaBackgroundMode.token ||
          mode == AreaBackgroundMode.solid ||
          mode == AreaBackgroundMode.image)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Txt("Color"),
                    const SizedBox(height: 4),
                    PaletteColorDropdown(
                      preset: preset,
                      value: mode == AreaBackgroundMode.solid ? solidColor : null,
                      allowNone: allowSolidNone || mode != AreaBackgroundMode.solid,
                      onChanged: (c) {
                        onModeChanged(AreaBackgroundMode.solid);
                        onSolidChanged(c);
                      },
                    ),
                  ]),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Txt("Image"),
                    const SizedBox(height: 4),
                    Row(children: [
                      _imagePreview(
                          mode == AreaBackgroundMode.image ? imagePath : null,
                          sourceDir,
                          defaultAssetPath:
                              mode == AreaBackgroundMode.token
                                  ? defaultAssetPath
                                  : null),
                      const SizedBox(width: 8),
                      Flexible(
                        child: OutlinedButton(
                          onPressed: () {
                            onModeChanged(AreaBackgroundMode.image);
                            onPickImage();
                          },
                          child: Text(
                              mode == AreaBackgroundMode.image && imagePath != null
                                  ? "Change..."
                                  : "Pick image..."),
                        ),
                      ),
                      if (mode == AreaBackgroundMode.image &&
                          imagePath != null &&
                          onRemoveImage != null)
                        IconButton(
                          onPressed: onRemoveImage,
                          icon: const Icon(Icons.close),
                          tooltip: "Remove image",
                        ),
                    ]),
                  ]),
            ),
          ]),
        ),
      if (mode == AreaBackgroundMode.gradient) ...[
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            const Txt("Color 1: "),
            const SizedBox(width: 8),
            PaletteColorDropdown(
              preset: preset,
              value: gradientColors.isNotEmpty ? gradientColors[0] : null,
              onChanged: (c) => onGradientColorChanged(0, c),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          const Txt("Color 2: "),
          const SizedBox(width: 8),
          PaletteColorDropdown(
            preset: preset,
            value: gradientColors.length > 1 ? gradientColors[1] : null,
            onChanged: (c) => onGradientColorChanged(1, c),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const Txt("Direction: "),
          const SizedBox(width: 8),
          DropdownButton<GradientDirection>(
            value: gradientDirectionFor(gradientBegin, gradientEnd),
            items: GradientDirection.values
                .map((d) => DropdownMenuItem(
                    value: d, child: Text(gradientDirectionLabel(d))))
                .toList(),
            onChanged: (d) {
              if (d != null) onDirectionChanged(d);
            },
          ),
        ]),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(builder: (context, theme, _) {
      var preset = displayPreset(theme);
      var style = preset.areas[selected] ?? const AreaStyle();
      // navBar's width is deliberately not user-configurable here -- the
      // sidebarx package's collapse/extend toggle button assumes specific
      // width values for its own animation, and overriding them broke it.
      var hasWidth = selected == ThemeArea.subMenuTabBar;

      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DropdownButton<ThemeArea>(
          value: selected,
          isExpanded: true,
          items: _editableAreas
              .map((a) => DropdownMenuItem(
                  value: a, child: Text(themeAreaLabel(a))))
              .toList(),
          onChanged: (a) => setState(() {
            if (a != null) selected = a;
            _dragValues.clear();
          }),
        ),
        const SizedBox(height: 12),
        _fillEditor(
          preset: preset,
          sourceDir: preset.sourceDir,
          label: "Background",
          tokenLabel: "Default",
          mode: style.mode,
          onModeChanged: (m) => _setStyle(theme, (s) {
            var next = s.copyWith(mode: m);
            // Seed a real color immediately when switching into a mode
            // that requires one, so the color dropdown(s) always have a
            // valid palette-backed value to show.
            if (m == AreaBackgroundMode.solid && next.solidColor == null) {
              next = next.copyWith(solidColor: preset.surface);
            }
            if (m == AreaBackgroundMode.gradient &&
                next.gradientColors.length < 2) {
              next = next.copyWith(
                  gradientColors: [preset.surface, preset.primary]);
            }
            return next;
          }),
          solidColor: style.solidColor,
          onSolidChanged: (c) =>
              _setStyle(theme, (s) => s.copyWith(solidColor: c)),
          allowSolidNone: false,
          gradientColors: style.gradientColors,
          onGradientColorChanged: (i, c) => _setStyle(theme, (s) {
            var colors = List<Color>.from(s.gradientColors);
            while (colors.length < 2) {
              colors.add(preset.surface);
            }
            colors[i] = c ?? preset.surface;
            return s.copyWith(gradientColors: colors);
          }),
          gradientBegin: style.gradientBegin,
          gradientEnd: style.gradientEnd,
          onDirectionChanged: (d) => _setStyle(theme, (s) {
            var (b, e) = gradientDirectionAlignments(d);
            return s.copyWith(gradientBegin: b, gradientEnd: e);
          }),
          imagePath: style.imagePath,
          onPickImage: () => _pickImage(theme, preset, forBorder: false),
          onRemoveImage: () => _setStyle(
              theme,
              (s) => s.copyWith(
                  mode: AreaBackgroundMode.token, clearImagePath: true)),
          defaultAssetPath: selected == ThemeArea.loginScreen
              ? "assets/images/loading-bg.png"
              : null,
          supportsNone: true,
        ),
        const Divider(height: 32),
        _fillEditor(
          preset: preset,
          sourceDir: preset.sourceDir,
          label: "Border",
          tokenLabel: "None",
          mode: style.borderMode,
          onModeChanged: (m) => _setStyle(theme, (s) {
            var next = s.copyWith(borderMode: m);
            if (m == AreaBackgroundMode.solid && next.borderColor == null) {
              next = next.copyWith(borderColor: preset.outline);
            }
            if (m == AreaBackgroundMode.gradient &&
                next.borderGradientColors.length < 2) {
              next = next.copyWith(
                  borderGradientColors: [preset.outline, preset.primary]);
            }
            if (m != AreaBackgroundMode.token && next.borderWidth <= 0) {
              next = next.copyWith(borderWidth: 2);
            }
            return next;
          }),
          solidColor: style.borderColor,
          onSolidChanged: (c) =>
              _setStyle(theme, (s) => s.copyWith(borderColor: c)),
          allowSolidNone: true,
          gradientColors: style.borderGradientColors,
          onGradientColorChanged: (i, c) => _setStyle(theme, (s) {
            var colors = List<Color>.from(s.borderGradientColors);
            while (colors.length < 2) {
              colors.add(preset.outline);
            }
            colors[i] = c ?? preset.outline;
            return s.copyWith(borderGradientColors: colors);
          }),
          gradientBegin: style.borderGradientBegin,
          gradientEnd: style.borderGradientEnd,
          onDirectionChanged: (d) => _setStyle(theme, (s) {
            var (b, e) = gradientDirectionAlignments(d);
            return s.copyWith(borderGradientBegin: b, borderGradientEnd: e);
          }),
          imagePath: style.borderImagePath,
          onPickImage: () => _pickImage(theme, preset, forBorder: true),
          onRemoveImage: () => _setStyle(
              theme,
              (s) => s.copyWith(
                  borderMode: AreaBackgroundMode.token,
                  clearBorderImagePath: true)),
        ),
        const SizedBox(height: 8),
        _slider("borderWidth", "Border width", style.borderWidth, 0, 10,
            (v) => _setStyle(theme, (s) => s.copyWith(borderWidth: v))),
        _slider("borderRadius", "Border radius", style.borderRadius, 0, 48,
            (v) => _setStyle(theme, (s) => s.copyWith(borderRadius: v))),
        // Padding has no visible effect on navBar -- it's composed by the
        // third-party sidebarx package's own fixed layout, which doesn't
        // consult this field at all -- so it's hidden there as a dead
        // control. For header, padding now maps to titleSpacing (the gap
        // around the title), so it's kept, just with a smaller range
        // appropriate for that.
        if (selected != ThemeArea.navBar)
          _slider(
              "padding",
              "Padding",
              style.padding,
              0,
              selected == ThemeArea.header ? 100 : 48,
              (v) => _setStyle(theme, (s) => s.copyWith(padding: v))),
        // Margin has no effect on navBar for the same reason (sidebarx's
        // own hardcoded margin), but does work for header (insets the
        // themed background within the app bar).
        if (selected != ThemeArea.navBar)
          _slider("margin", "Margin", style.margin, 0, 48,
              (v) => _setStyle(theme, (s) => s.copyWith(margin: v))),
        if (hasWidth) _widthSlider(theme, style),
        if (selected == ThemeArea.subMenuTabBar) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Txt("Visibility: "),
            const SizedBox(width: 8),
            DropdownButton<SubMenuStyle>(
              value: style.subMenuStyle ?? SubMenuStyle.alwaysVisible,
              items: SubMenuStyle.values
                  .map((s) => DropdownMenuItem(
                      value: s, child: Text(subMenuStyleLabel(s))))
                  .toList(),
              onChanged: (s) {
                if (s != null) {
                  _setStyle(theme, (st) => st.copyWith(subMenuStyle: s));
                }
              },
            ),
          ]),
          if ((style.subMenuStyle ?? SubMenuStyle.alwaysVisible) ==
              SubMenuStyle.hoverReveal)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Show hover arrow"),
              value: style.showHoverArrow,
              onChanged: (v) =>
                  _setStyle(theme, (s) => s.copyWith(showHoverArrow: v)),
            ),
        ],
        if (selected == ThemeArea.navBar) ...[
          SwitchListTile(
            title: const Text("Show logo"),
            subtitle: const Text(
                "Displays the Bison Relay logo at the top of the nav bar -- "
                "useful when the header is set to Content or None"),
            value: style.showLogo,
            onChanged: (v) =>
                _setStyle(theme, (s) => s.copyWith(showLogo: v)),
          ),
          if (style.showLogo) ...[
            _slider("logoSize", "Logo size", style.logoSize ?? 32, 16, 80,
                (v) => _setStyle(theme, (s) => s.copyWith(logoSize: v))),
            const SizedBox(height: 8),
            Row(children: [
              const Txt("Logo position: "),
              const SizedBox(width: 8),
              DropdownButton<ContentAlign>(
                value: style.logoAlign ?? ContentAlign.center,
                items: const [ContentAlign.start, ContentAlign.center, ContentAlign.end]
                    .map((a) => DropdownMenuItem(
                        value: a, child: Text(contentAlignLabel(a))))
                    .toList(),
                onChanged: (a) {
                  if (a != null) {
                    _setStyle(theme, (s) => s.copyWith(logoAlign: a));
                  }
                },
              ),
            ]),
          ],
        ],
        if (selected == ThemeArea.chat) ...[
          SwitchListTile(
            title: const Text("Reply & pin messages"),
            subtitle: const Text(
                "Adds Reply and Pin to the message context menu, with a "
                "reply chip and pinned-message bar in the conversation"),
            value: style.enableMessageActions,
            onChanged: (v) =>
                _setStyle(theme, (s) => s.copyWith(enableMessageActions: v)),
          ),
          SwitchListTile(
            title: const Text("Show last message & timestamp"),
            subtitle: const Text(
                "Shows a last-message preview and relative timestamp on "
                "each contact/GC row"),
            value: style.showChatListLastMessage,
            onChanged: (v) => _setStyle(
                theme, (s) => s.copyWith(showChatListLastMessage: v)),
          ),
          SwitchListTile(
            title: const Text("Chat list design"),
            subtitle: const Text(
                "Rounded, glowing rows with a highlighted selected chat, "
                "instead of the plain list"),
            value: style.chatListDesignEnabled,
            onChanged: (v) => _setStyle(
                theme, (s) => s.copyWith(chatListDesignEnabled: v)),
          ),
          if (style.chatListDesignEnabled) ...[
            _slider(
                "chatListCornerRadius",
                "Row corner radius",
                style.chatListCornerRadius ?? 14,
                0,
                28,
                (v) => _setStyle(
                    theme, (s) => s.copyWith(chatListCornerRadius: v))),
            Row(children: [
              const Txt("Accent color: "),
              const SizedBox(width: 8),
              PaletteColorDropdown(
                preset: preset,
                value: style.chatListAccentColor,
                allowNone: true,
                onChanged: (c) => _setStyle(
                    theme,
                    (s) => c == null
                        ? s.copyWith(clearChatListAccentColor: true)
                        : s.copyWith(chatListAccentColor: c)),
              ),
            ]),
            _glowSlider(theme, style),
            SwitchListTile(
              title: const Text("Row top highlight"),
              subtitle: const Text(
                  "Top-left ambient glow and lit hairline on unselected "
                  "rows, instead of a flat background"),
              value: style.chatListTopHighlight,
              onChanged: (v) => _setStyle(
                  theme, (s) => s.copyWith(chatListTopHighlight: v)),
            ),
          ],
          SwitchListTile(
            title: const Text("Monochrome avatars"),
            subtitle: const Text(
                "Uses a graphite-gray fallback avatar instead of a "
                "colorful hashed hue (real avatar images are unaffected)"),
            value: style.monochromeAvatars,
            onChanged: (v) =>
                _setStyle(theme, (s) => s.copyWith(monochromeAvatars: v)),
          ),
          SwitchListTile(
            title: const Text("Chat backdrop glow"),
            subtitle:
                const Text("Adds a subtle gradient wash behind messages"),
            value: style.chatBackdropWash,
            onChanged: (v) =>
                _setStyle(theme, (s) => s.copyWith(chatBackdropWash: v)),
          ),
          SwitchListTile(
            title: const Text("In-chat search"),
            subtitle: const Text(
                "Adds a search button to the chat title bar for "
                "searching loaded messages"),
            value: style.enableChatSearch,
            onChanged: (v) =>
                _setStyle(theme, (s) => s.copyWith(enableChatSearch: v)),
          ),
          SwitchListTile(
            title: const Text("Resizable chat list"),
            subtitle: const Text(
                "Makes the chat list pane drag-resizable and adds a "
                "persistent search/start-chat bar above it"),
            value: style.resizableChatList,
            onChanged: (v) =>
                _setStyle(theme, (s) => s.copyWith(resizableChatList: v)),
          ),
          SwitchListTile(
            title: const Text("Formatting toolbar"),
            subtitle: const Text(
                "Adds a Bold/Italic/Code/Strikethrough/Link toolbar to "
                "the message composer"),
            value: style.formattingToolbar,
            onChanged: (v) =>
                _setStyle(theme, (s) => s.copyWith(formattingToolbar: v)),
          ),
          SwitchListTile(
            title: const Text("Composer polish"),
            subtitle: const Text(
                "Inline tip button on 1:1 chats, a glowing send button, "
                "and a per-contact message hint"),
            value: style.composerPolish,
            onChanged: (v) =>
                _setStyle(theme, (s) => s.copyWith(composerPolish: v)),
          ),
          SwitchListTile(
            title: const Text("Square message bubbles"),
            value: style.squareBubbles,
            onChanged: (v) =>
                _setStyle(theme, (s) => s.copyWith(squareBubbles: v)),
          ),
          const SizedBox(height: 8),
          Row(children: [
            const Txt("Message layout: "),
            const SizedBox(width: 8),
            DropdownButton<MessageLayoutMode>(
              value: style.messageLayoutMode ?? MessageLayoutMode.standard,
              items: MessageLayoutMode.values
                  .map((m) => DropdownMenuItem(
                      value: m, child: Text(messageLayoutModeLabel(m))))
                  .toList(),
              onChanged: (m) {
                if (m == null) return;
                _setStyle(
                    theme,
                    (s) => m == MessageLayoutMode.standard
                        ? s.copyWith(clearMessageLayoutMode: true)
                        : s.copyWith(messageLayoutMode: m));
              },
            ),
          ]),
          if ((style.messageLayoutMode ?? MessageLayoutMode.standard) !=
              MessageLayoutMode.standard)
            SwitchListTile(
              title: const Text("Expand to fill panel"),
              subtitle: const Text(
                  "Uses the full conversation panel width instead of "
                  "margining the message list in"),
              value: style.expandMessageWidth,
              onChanged: (v) => _setStyle(
                  theme, (s) => s.copyWith(expandMessageWidth: v)),
            ),
          if (style.expandMessageWidth) _expandPaddingSlider(theme, style),
        ],
        if (selected == ThemeArea.realtimeChat) ...[
          SwitchListTile(
            title: const Text("Auto-unmute on join"),
            subtitle: const Text(
                "Automatically unmutes (with a snackbar notice) when "
                "joining a live session"),
            value: style.autoUnmuteOnJoin,
            onChanged: (v) =>
                _setStyle(theme, (s) => s.copyWith(autoUnmuteOnJoin: v)),
          ),
          SwitchListTile(
            title: const Text("Enhanced call status indicators"),
            subtitle: const Text(
                "Pulsing mic-live indicator, clearer mute/unmute button "
                "states, and a warning chip while in a live session"),
            value: style.enhancedCallIndicators,
            onChanged: (v) => _setStyle(
                theme, (s) => s.copyWith(enhancedCallIndicators: v)),
          ),
        ],
        if (selected == ThemeArea.feed) ...[
          SwitchListTile(
            title: const Text("Feed card redesign"),
            subtitle: const Text(
                "X-style borderless post cards, live comment count, a "
                "height-clamped body with \"Show more\", and a centered "
                "post-detail view"),
            value: style.feedCardRedesign,
            onChanged: (v) =>
                _setStyle(theme, (s) => s.copyWith(feedCardRedesign: v)),
          ),
          SwitchListTile(
            title: const Text("Post actions: relay, tip, quote"),
            subtitle: const Text(
                "Relay-to-subscribers, tip-the-author, and quote-post "
                "icons on each card, with nested quote-post rendering "
                "(requires Feed card redesign)"),
            value: style.feedCardActions,
            onChanged: (v) =>
                _setStyle(theme, (s) => s.copyWith(feedCardActions: v)),
          ),
          SwitchListTile(
            title: const Text("Bookmarks"),
            subtitle: const Text(
                "Per-post bookmark toggle and a Bookmarks section in the "
                "feed side panel (requires Feed side panel for the list)"),
            value: style.feedBookmarks,
            onChanged: (v) =>
                _setStyle(theme, (s) => s.copyWith(feedBookmarks: v)),
          ),
          SwitchListTile(
            title: const Text("Hide posts"),
            subtitle: const Text(
                "Per-post hide/unhide and a Hidden section in the feed "
                "side panel (requires Feed side panel for the list)"),
            value: style.feedHidePosts,
            onChanged: (v) =>
                _setStyle(theme, (s) => s.copyWith(feedHidePosts: v)),
          ),
          SwitchListTile(
            title: const Text("Feed side panel"),
            subtitle: const Text(
                "Search, sort, and an unread-only filter in a nav rail, "
                "replacing the plain tab bar on the main feed tab"),
            value: style.feedSidePanel,
            onChanged: (v) =>
                _setStyle(theme, (s) => s.copyWith(feedSidePanel: v)),
          ),
          SwitchListTile(
            title: const Text("Inline composer"),
            subtitle: const Text(
                "A pinned \"What's happening?\" composer at the top of "
                "the feed"),
            value: style.feedInlineComposer,
            onChanged: (v) =>
                _setStyle(theme, (s) => s.copyWith(feedInlineComposer: v)),
          ),
          SwitchListTile(
            title: const Text("Composer formatting toolbar"),
            subtitle: const Text(
                "Bold/Italic/Code/Strikethrough/Link toolbar in the "
                "inline composer (requires Inline composer)"),
            value: style.feedComposerFormatting,
            onChanged: (v) => _setStyle(
                theme, (s) => s.copyWith(feedComposerFormatting: v)),
          ),
          SwitchListTile(
            title: const Text("Composer image/file attach"),
            subtitle: const Text(
                "Attach an image or file from the inline composer "
                "(requires Inline composer)"),
            value: style.feedComposerAttach,
            onChanged: (v) =>
                _setStyle(theme, (s) => s.copyWith(feedComposerAttach: v)),
          ),
          SwitchListTile(
            title: const Text("Drafts"),
            subtitle: const Text(
                "Save/reuse/delete post drafts (requires Inline composer "
                "and Feed side panel)"),
            value: style.feedDrafts,
            onChanged: (v) =>
                _setStyle(theme, (s) => s.copyWith(feedDrafts: v)),
          ),
          SwitchListTile(
            title: const Text("Hide sidebar when reading a post"),
            subtitle: const Text(
                "Drops the feed sidebar while viewing a single post, for "
                "a more focused reading experience (requires Feed side "
                "panel)"),
            value: style.feedHideSidebarOnPost,
            onChanged: (v) => _setStyle(
                theme, (s) => s.copyWith(feedHideSidebarOnPost: v)),
          ),
        ],
        if (selected == ThemeArea.header) ...[
          Row(children: [
            const Txt("Position: "),
            const SizedBox(width: 8),
            DropdownButton<HeaderPosition>(
              value: style.headerPosition ?? HeaderPosition.top,
              items: HeaderPosition.values
                  .map((p) => DropdownMenuItem(
                      value: p, child: Text(headerPositionLabel(p))))
                  .toList(),
              onChanged: (p) {
                if (p != null) {
                  _setStyle(theme, (s) => s.copyWith(headerPosition: p));
                }
              },
            ),
          ]),
          const SizedBox(height: 8),
          _slider("logoSize", "Logo size", style.logoSize ?? 40, 16, 80,
              (v) => _setStyle(theme, (s) => s.copyWith(logoSize: v))),
          _slider("height", "Height", style.height ?? 56, 40, 120,
              (v) => _setStyle(theme, (s) => s.copyWith(height: v))),
          const SizedBox(height: 8),
          Row(children: [
            const Txt("Text align: "),
            const SizedBox(width: 8),
            DropdownButton<ContentAlign>(
              value: style.contentAlign ?? ContentAlign.center,
              items: ContentAlign.values
                  .map((a) => DropdownMenuItem(
                      value: a, child: Text(contentAlignLabel(a))))
                  .toList(),
              onChanged: (a) {
                if (a != null) {
                  _setStyle(theme, (s) => s.copyWith(contentAlign: a));
                }
              },
            ),
          ]),
        ],
      ]);
    });
  }
}
