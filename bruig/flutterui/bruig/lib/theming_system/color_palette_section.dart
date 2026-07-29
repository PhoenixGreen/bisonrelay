import 'dart:io';

import 'package:bruig/components/eyedropper.dart';
import 'package:bruig/components/snackbars.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/theming_system/color_palette.dart';
import 'package:bruig/theming_system/palette_color_dropdown.dart';
import 'package:bruig/theming_system/palette_library.dart';
import 'package:bruig/theming_system/palette_library_storage.dart';
import 'package:bruig/theming_system/preset.dart';
import 'package:bruig/theming_system/theme_editor.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';

// color_palette_section.dart is the "Color Palette" section of Settings >
// Appearance: the palette-library strip (apply/save/import/export a whole
// ColorPalette) above an inline editor for each individual PaletteSlot.

// applyColorPalette applies a ColorPalette's 12 stored vivid colors exactly
// as stored -- no hue rotation, no re-deriving them. Each built-in/saved
// palette is a self-contained, already-tuned look (e.g. "X (Twitter) Dark"
// was tuned live in the editor and exported), so recomputing its colors
// through a generic formula only fights whatever the palette's author
// actually intended.
//
// The neutral/functional roles (onSurface/onSurfaceVariant/navText/
// sidebarText/success) and the overall brightness, however, ARE reset -- to
// palette.brightness's own seed -- rather than left at whatever the draft
// preset already had. Every built-in palette's colors are tuned against one
// specific brightness (nearly always dark; only "Light" targets light), so
// leaving old neutrals in place made the exact same palette render
// completely differently -- sometimes unreadably, e.g. dark text surviving
// under a freshly-applied near-black background -- depending on whether the
// dark or light base theme happened to be active before the palette was
// clicked. Resetting them from palette.brightness's seed makes applying any
// given palette produce the same, internally-consistent result regardless of
// prior state.
void applyColorPalette(ThemeNotifier theme, ColorPalette palette) {
  var draft = ensureDraftPreset(theme);
  var base = ThemePreset.seedFor(palette.brightness);
  Color colorAt(int i, Color fallback) =>
      i < palette.colors.length ? palette.colors[i] : fallback;
  // Palettes saved/exported before speechBackgroundSent became a stored
  // vivid slot only have 7 colors, ending in [..., navAccent,
  // sidebarAccent] -- read the accents from their old positions for
  // those instead of misreading a leftover sidebarAccent as navAccent.
  // accentContainer/error/outline/fourth are newer still (appended at
  // the tail, in that order), so any palette shorter than their index
  // naturally falls back to the seed's own value for them via colorAt's
  // length check -- no extra legacy-length branching needed for those.
  // (buttonBorder, once between outline and fourth in this tail sequence,
  // was removed and merged into navAccent -- see color_palette.dart.)
  var legacySevenColor = palette.colors.length == 7;
  theme.previewPreset(draft.copyWith(
    brightness: palette.brightness,
    primary: colorAt(0, base.primary),
    // Follow primary rather than being left at the previous theme's value:
    // a library palette carries no entry for these two (its stored colors
    // are positional, so appending would break every palette saved before
    // now), and leaving them behind would strand two regions on a
    // background from a palette that's no longer applied.
    dualBackground: colorAt(0, base.primary),
    contentBackground: colorAt(0, base.primary),
    secondary: colorAt(1, base.secondary),
    tertiary: colorAt(2, base.tertiary),
    sidebarBackground: colorAt(3, base.sidebarBackground),
    speechBackground: colorAt(4, base.speechBackground),
    speechBackgroundSent: legacySevenColor
        ? base.speechBackgroundSent
        : colorAt(5, base.speechBackgroundSent),
    navAccent: colorAt(legacySevenColor ? 5 : 6, base.navAccent),
    sidebarAccent: colorAt(legacySevenColor ? 6 : 7, base.sidebarAccent),
    accentContainer: colorAt(8, base.accentContainer),
    error: colorAt(9, base.error),
    outline: colorAt(10, base.outline),
    fourth: colorAt(11, base.fourth),
    // Neutral/functional roles always come from the brightness seed.
    onSurface: base.onSurface,
    onSurfaceVariant: base.onSurfaceVariant,
    navText: base.navText,
    sidebarText: base.sidebarText,
    success: base.success,
  ));
}

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
            children: colors
                .map((c) => Expanded(child: Container(color: c)))
                .toList()),
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
  @override
  Widget build(BuildContext context) {
    var settingsNav = ClientModel.of(context, listen: false).ui.settingsNav;
    return Consumer<ThemeNotifier>(builder: (context, theme, _) {
      var preset = displayPreset(theme);
      return ExpansionTile(
        title: const Txt.S("Color Palette"),
        subtitle: !settingsNav.paletteExpanded
            ? Padding(
                padding: const EdgeInsets.only(top: 6, right: 16),
                child: PaletteSwatchStrip(colors: preset.palette),
              )
            : null,
        initiallyExpanded: settingsNav.paletteExpanded,
        onExpansionChanged: (v) =>
            setState(() => settingsNav.paletteExpanded = v),
        children: const [PaletteSection()],
      );
    });
  }
}

// PaletteSection is an embeddable (non-routed) editor for the active
// preset's palette. Tapping a color expands an inline picker in place -- no
// modal popups -- committed via a "Done" button so a single disk write
// happens per edit instead of one per drag frame.
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

  void _collapse() => setState(() {
        expandedIndex = null;
        draftColor = null;
      });

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
      brightness: preset.brightness,
    );
    await PaletteLibraryStorage.savePalette(palette);
    if (!mounted) return;
    setState(() => userPalettes = [...userPalettes, palette]);
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
    var filePath = res?.files.first.path;
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
      onTap: () => applyColorPalette(theme, palette),
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
                      child:
                          Txt.S(palette.name, overflow: TextOverflow.ellipsis)),
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

  // _slotRow is one palette entry: its label, its current swatch, and (when
  // expanded) the inline picker that edits it.
  Widget _slotRow(ThemeNotifier theme, List<Color> fullPalette, int i) {
    var isSlot = i < PaletteSlot.values.length;
    var label = isSlot
        ? paletteSlotLabel(PaletteSlot.values[i])
        : "Extra color ${i - PaletteSlot.values.length + 1}";
    var isExpanded = expandedIndex == i;
    var color = isExpanded ? (draftColor ?? fullPalette[i]) : fullPalette[i];

    void commit() {
      var draft = ensureDraftPreset(theme);
      var chosen = draftColor ?? fullPalette[i];
      ThemePreset updated;
      if (isSlot) {
        updated = draft.withSlot(PaletteSlot.values[i], chosen);
      } else {
        var colors = List<Color>.from(draft.extraPaletteColors);
        colors[i - PaletteSlot.values.length] = chosen;
        updated = draft.copyWith(extraPaletteColors: colors);
      }
      _collapse();
      theme.previewPreset(updated);
    }

    void removeExtra() {
      var draft = ensureDraftPreset(theme);
      var updatedExtras = List<Color>.from(draft.extraPaletteColors)
        ..removeAt(i - PaletteSlot.values.length);
      if (isExpanded) _collapse();
      // Area styles bind a color by its index into the whole palette (the
      // fixed slots then the extras -- see ThemePreset.palette), so dropping
      // an extra shifts every later one down a place. Without remapping,
      // each area bound past this point silently starts following its
      // neighbour's color instead, and one bound to the removed color keeps
      // whatever it last resolved to.
      theme.previewPreset(draft.copyWith(
        extraPaletteColors: updatedExtras,
        areas: {
          for (var e in draft.areas.entries)
            e.key: e.value.remapPaletteIndexes(i),
        },
      ));
    }

    return Column(children: [
      ListTile(
        title: Txt(label),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          colorSwatchBox(color, size: 28, radius: 4),
          if (!isSlot)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: "Remove color",
              onPressed: removeExtra,
            ),
        ]),
        onTap: () => isExpanded
            ? _collapse()
            : setState(() {
                expandedIndex = i;
                draftColor = fullPalette[i];
              }),
      ),
      if (isExpanded)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            ColorPicker(
              pickerColor: draftColor ?? fullPalette[i],
              // Lets a palette color blend into whatever it's painted over
              // (e.g. a semi-transparent divider or overlay) instead of
              // always being fully opaque.
              enableAlpha: true,
              displayThumbColor: true,
              hexInputBar: true,
              onColorChanged: (c) => setState(() => draftColor = c),
            ),
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.colorize),
                    tooltip: "Pick color from app (eyedropper)",
                    onPressed: () async {
                      var picked = await pickColorFromApp(context);
                      if (picked != null) setState(() => draftColor = picked);
                    },
                  ),
                  Row(children: [
                    TextButton(
                        onPressed: _collapse, child: const Text("Cancel")),
                    TextButton(onPressed: commit, child: const Text("Done")),
                  ]),
                ]),
          ]),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(builder: (context, theme, _) {
      var preset = displayPreset(theme);
      var fullPalette = preset.palette;
      // The Default/Light cards are always built from their own fixed seed,
      // never from theme.brightness/the currently active preset -- they must
      // reproduce the same look every time regardless of which base theme
      // (or palette) happens to be active when they're shown.
      var allPalettes = [
        for (var b in [Brightness.dark, Brightness.light])
          ColorPalette(
            id: b == Brightness.dark ? "default" : "light",
            name: b == Brightness.dark ? "Default" : "Light",
            builtin: true,
            brightness: b,
            colors:
                kVividPaletteSlots.map(ThemePreset.seedFor(b).forSlot).toList(),
          ),
        ...builtinPalettes,
        ...userPalettes,
      ];
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
                    children: allPalettes
                        .map((p) => _paletteCard(theme, p))
                        .toList()),
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
        ...List.generate(
            fullPalette.length, (i) => _slotRow(theme, fullPalette, i)),
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
