import 'dart:io';
import 'dart:typed_data';

import 'package:bruig/components/snackbars.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/models/theme_preset.dart';
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
class PaletteSection extends StatefulWidget {
  const PaletteSection({super.key});

  @override
  State<PaletteSection> createState() => _PaletteSectionState();
}

class _PaletteSectionState extends State<PaletteSection> {
  PaletteSlot? expandedSlot;
  Color? draftColor;

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(builder: (context, theme, _) {
      var preset = displayPreset(theme);

      return Column(
        children: PaletteSlot.values.map((slot) {
          var isExpanded = expandedSlot == slot;
          var color = isExpanded ? (draftColor ?? preset.forSlot(slot)) : preset.forSlot(slot);

          return Column(children: [
            ListTile(
              title: Txt(paletteSlotLabel(slot)),
              trailing: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              onTap: () => setState(() {
                if (isExpanded) {
                  expandedSlot = null;
                  draftColor = null;
                } else {
                  expandedSlot = slot;
                  draftColor = preset.forSlot(slot);
                }
              }),
            ),
            if (isExpanded)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(children: [
                  ColorPicker(
                    pickerColor: draftColor ?? preset.forSlot(slot),
                    enableAlpha: false,
                    hexInputBar: true,
                    onColorChanged: (c) => setState(() => draftColor = c),
                  ),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(
                      onPressed: () => setState(() {
                        expandedSlot = null;
                        draftColor = null;
                      }),
                      child: const Text("Cancel"),
                    ),
                    TextButton(
                      onPressed: () {
                        var updated = ensureDraftPreset(theme)
                            .withSlot(slot, draftColor ?? preset.forSlot(slot));
                        setState(() {
                          expandedSlot = null;
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
        }).toList(),
      );
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
        if (hasWidth)
          _slider(
              "width",
              "Width",
              style.width ?? 120,
              40,
              400,
              (v) => _setStyle(theme, (s) => s.copyWith(width: v))),
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
