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
void applyColorPalette(ThemeNotifier theme, ColorPalette palette) =>
    theme.previewPreset(paletteApplied(ensureDraftPreset(theme), palette));

// paletteApplied is applyColorPalette's mapping on its own, with no
// ThemeNotifier involved -- which is what makes the result of applying any
// palette checkable in a test (see test/palette_contrast_test.dart, which
// runs every built-in palette through it and asserts the contrast of every
// text/background pair it produces).
ThemePreset paletteApplied(ThemePreset draft, ColorPalette palette) {
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
  return draft.copyWith(
    brightness: palette.brightness,
    primary: colorAt(0, base.primary),
    // Follow primary rather than being left at the previous theme's value:
    // a library palette carries no entry for these two (its stored colors
    // are positional, so appending would break every palette saved before
    // now), and leaving them behind would strand two regions on a
    // background from a palette that's no longer applied.
    headerBackground: colorAt(0, base.primary),
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
    // A library palette stores one accent (its brand colour), and its
    // positional format can't be extended without breaking every palette
    // saved before now -- so the nav takes that same accent on apply, and
    // is a separate swatch to tune afterwards.
    navSelected: colorAt(legacySevenColor ? 5 : 6, base.navAccent),
    sidebarAccent: colorAt(legacySevenColor ? 6 : 7, base.sidebarAccent),
    // Inputs follow the palette's own accent, the same way the nav bar's
    // selected item does. They were left out of this list entirely, and
    // because a library palette carries no entry for them they simply kept
    // whatever the draft already had -- which for a fresh draft is the
    // seed's lavender, so every text box in the app stayed purple no
    // matter which palette was applied.
    inputSelected: colorAt(legacySevenColor ? 5 : 6, base.navAccent),
    inputResting: ThemePreset.restingBorderFrom(
        colorAt(legacySevenColor ? 5 : 6, base.navAccent),
        colorAt(0, base.primary)),
    // Inputs have never carried a fill; reset rather than left behind, so
    // applying a palette always lands on the same result.
    inputBackground: base.inputBackground,
    accentContainer: colorAt(8, base.accentContainer),
    error: colorAt(9, base.error),
    outline: colorAt(10, base.outline),
    fourth: colorAt(11, base.fourth),
    // The button label, border and tonal fill are the palette's own (tail
    // slots 12-14; a palette exported before they existed falls back to the
    // seed). Hover follows the label, since it's that color at 12% over
    // whatever fill is underneath. The danger fill and the filled-button
    // label stay on the seed deliberately: a red that means "destructive"
    // and a near-white that has to stay legible on every fill are both
    // semantic, and should read the same whichever palette is applied.
    buttonText1: colorAt(12, base.buttonText1),
    buttonBorderColor: colorAt(13, base.buttonBorderColor),
    buttonBackgroundThird: colorAt(14, base.buttonBackgroundThird),
    buttonHover: colorAt(12, base.buttonText1).withValues(alpha: 0.12),
    buttonBackgroundSecondary: base.buttonBackgroundSecondary,
    buttonText2: base.buttonText2,
    // Neutral/functional roles always come from the brightness seed.
    onSurface: base.onSurface,
    onSurfaceVariant: base.onSurfaceVariant,
    navText: base.navText,
    sidebarText: base.sidebarText,
    success: base.success,
  );
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

  // Some slots are two states of one colour rather than two colours, and
  // read better as one row with a swatch each than as two rows whose names
  // have to explain the relationship. The companion is drawn to the left
  // (resting first, then selected -- the order the states happen in) and
  // gets no row of its own.
  // Keyed by the slot that keeps the row (drawn rightmost), valued by the
  // ones that join it, in the order they're drawn -- leftmost first. The
  // row appears wherever the key's slot already sat in the list, and the
  // companions get no row of their own.
  static const Map<PaletteSlot, List<PaletteSlot>> _pairedWith = {
    PaletteSlot.primary: [
      PaletteSlot.tertiary,
      PaletteSlot.contentBackground,
      PaletteSlot.dualBackground,
      PaletteSlot.headerBackground,
    ],
    PaletteSlot.inputBackground: [
      PaletteSlot.inputResting,
      PaletteSlot.inputSelected,
    ],
    PaletteSlot.speechBackgroundSent: [PaletteSlot.speechBackground],
    // The seven button colors, drawn right to left in the order they were
    // specified: the fill Button 1 uses keeps the row (it's the slot that
    // already existed), then the other two fills, the border, the hover
    // tint and the two label colors run leftwards from it.
    PaletteSlot.accentContainer: [
      PaletteSlot.buttonText2,
      PaletteSlot.buttonText1,
      PaletteSlot.buttonHover,
      PaletteSlot.buttonBorderColor,
      PaletteSlot.buttonBackgroundThird,
      PaletteSlot.buttonBackgroundSecondary,
    ],
    PaletteSlot.sidebarBackground: [
      PaletteSlot.sidebarText,
      PaletteSlot.sidebarAccent,
    ],
    PaletteSlot.secondary: [PaletteSlot.navText, PaletteSlot.navSelected],
    PaletteSlot.onSurface: [PaletteSlot.onSurfaceVariant],
    PaletteSlot.success: [PaletteSlot.error],
  };

  // A paired row keeps its owner's label unless the pair is really one
  // idea with two halves, in which case it gets a name covering both.
  static const Map<PaletteSlot, String> _pairedLabels = {
    PaletteSlot.primary: "Primary Backgrounds",
    PaletteSlot.onSurface: "Primary Text Colors",
    PaletteSlot.secondary: "Navigation Colors",
    PaletteSlot.sidebarBackground: "Sidebar Colors",
    PaletteSlot.speechBackgroundSent: "Speech Backgrounds",
    PaletteSlot.inputBackground: "Input Colors",
    PaletteSlot.accentContainer: "Button Colors",
    PaletteSlot.success: "Error and Success",
  };

  // _leadingRows are the rows shown first, in this order, regardless of
  // where their slots sit in PaletteSlot. Row order is presentation only,
  // so it lives here rather than in the enum -- area styles bind colours
  // by their index into that enum, and reordering it to suit the editor
  // would renumber every one of those bindings.
  static const List<PaletteSlot> _leadingRows = [
    PaletteSlot.primary,
    PaletteSlot.onSurface,
  ];

  // _rowOrder is every palette entry that gets a row, in display order:
  // the leading ones, then everything else as the enum has it, then the
  // user's extra colours.
  List<int> _rowOrder(int paletteLength) {
    var companions = _pairedWith.values.expand((g) => g).toSet();
    var slots = [
      ..._leadingRows,
      ...PaletteSlot.values
          .where((s) => !_leadingRows.contains(s) && !companions.contains(s)),
    ];
    return [
      ...slots.map((s) => s.index),
      for (var i = PaletteSlot.values.length; i < paletteLength; i++) i,
    ];
  }

  // _slotRow is one palette entry: its label, its swatch (or swatches --
  // see _pairedWith), and, when expanded, the inline picker editing
  // whichever swatch was tapped.
  Widget _slotRow(ThemeNotifier theme, List<Color> fullPalette, int i) {
    var isSlot = i < PaletteSlot.values.length;
    var slot = isSlot ? PaletteSlot.values[i] : null;

    // A companion is drawn inside its owner's row, so it has none here.
    if (slot != null &&
        _pairedWith.values.any((group) => group.contains(slot))) {
      return const SizedBox.shrink();
    }

    var companions = (slot != null ? _pairedWith[slot] : null) ?? const [];

    var label = isSlot
        ? (slot != null ? _pairedLabels[slot] : null) ??
            paletteSlotLabel(PaletteSlot.values[i])
        : "Extra color ${i - PaletteSlot.values.length + 1}";
    // Either swatch of a paired row opens the picker under that same row,
    // so what's being edited may be this slot or its companion.
    var editing = expandedIndex == i
        ? i
        : (companions.any((c) => c.index == expandedIndex)
            ? expandedIndex
            : null);
    var isExpanded = editing != null;

    void commit() {
      var target = editing ?? i;
      var draft = ensureDraftPreset(theme);
      var chosen = draftColor ?? fullPalette[target];
      ThemePreset updated;
      if (target < PaletteSlot.values.length) {
        updated = draft.withSlot(PaletteSlot.values[target], chosen);
      } else {
        var colors = List<Color>.from(draft.extraPaletteColors);
        colors[target - PaletteSlot.values.length] = chosen;
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

    Widget swatch(int index, {String? tooltip}) {
      var live = expandedIndex == index && draftColor != null
          ? draftColor!
          : fullPalette[index];
      Widget box = InkWell(
        onTap: () => expandedIndex == index
            ? _collapse()
            : setState(() {
                expandedIndex = index;
                draftColor = fullPalette[index];
              }),
        child: colorSwatchBox(live, size: 28, radius: 4),
      );
      return tooltip == null ? box : Tooltip(message: tooltip, child: box);
    }

    return Column(children: [
      ListTile(
        title: Txt(label),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          // Each swatch names itself on hover: two bare squares on a row
          // don't say which is which, and the row label can only name one
          // of them.
          for (var c in companions) ...[
            swatch(c.index, tooltip: paletteSlotLabel(c)),
            const SizedBox(width: 8),
          ],
          swatch(i,
              tooltip: companions.isNotEmpty && slot != null
                  ? paletteSlotLabel(slot)
                  : null),
          if (!isSlot)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: "Remove color",
              onPressed: removeExtra,
            ),
        ]),
        // The row itself edits the row's own colour; the swatches are what
        // reach a companion.
        onTap: () => expandedIndex == i
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
              pickerColor: draftColor ?? fullPalette[editing],
              // Lets a palette color blend into whatever it's painted over
              // (e.g. a semi-transparent divider or overlay) instead of
              // always being fully opaque.
              enableAlpha: true,
              displayThumbColor: true,
              hexInputBar: true,
              onColorChanged: (c) => setState(() => draftColor = c),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton(
                icon: const Icon(Icons.colorize),
                tooltip: "Pick color from app (eyedropper)",
                onPressed: () async {
                  var picked = await pickColorFromApp(context);
                  if (picked != null) setState(() => draftColor = picked);
                },
              ),
              Row(children: [
                TextButton(onPressed: _collapse, child: const Text("Cancel")),
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
        ..._rowOrder(fullPalette.length)
            .map((i) => _slotRow(theme, fullPalette, i)),
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
