import 'package:bruig/components/text.dart';
import 'package:bruig/theming_system/editor/editor_controls.dart';
import 'package:bruig/theming_system/editor/palette_color_dropdown.dart';
import 'package:bruig/theming_system/runtime/theme_notifier.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';

// area_editor_context.dart is the API one theming_system/editor/areas/
// <name>.dart file is handed to build its area's own settings. Every area
// editor builds its controls only through the helpers here -- never a raw
// SwitchListTile/DropdownButton/Slider -- which is what keeps the settings
// consistent from one area to the next.

// AreaEditorContext is what a editor/areas/<name>.dart file is handed to
// build its own settings: the current preset/style plus the small set of
// controls the area editors are built from. Going through these helpers
// (rather than raw SwitchListTile/DropdownButton/Slider) is what keeps
// every area's settings looking and behaving the same.
class AreaEditorContext {
  final AreaEditorHost _host;

  final ThemeNotifier theme;
  final ThemePreset preset;
  final ThemeArea area;
  final AreaStyle style;

  const AreaEditorContext(this._host,
      {required this.theme,
      required this.preset,
      required this.area,
      required this.style});

  // setStyle applies an edit to this area's style. It always re-reads the
  // current style fresh (not a build()-scoped snapshot) before applying
  // `update` -- needed because a single user action can trigger two calls
  // in a row (e.g. picking a color both switches mode to Solid *and* sets
  // the color); if each call started from the same stale snapshot instead
  // of the just-updated one, the second call would silently discard the
  // first.
  void setStyle(AreaStyle Function(AreaStyle) update) =>
      _host.setAreaStyle(theme, update);

  // toggle is a labelled on/off switch.
  Widget toggle(String title,
          {String? subtitle,
          required bool value,
          required ValueChanged<bool> onChanged,
          bool compact = false}) =>
      SwitchListTile(
        contentPadding: compact ? EdgeInsets.zero : null,
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle) : null,
        value: value,
        onChanged: onChanged,
      );

  // choice is a labelled dropdown over a fixed set of options.
  Widget choice<T>(String label,
          {required T value,
          required List<T> options,
          required String Function(T) labelOf,
          required ValueChanged<T> onChanged}) =>
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          // The label gives way too, for the same reason the dropdown does
          // -- some of these run long ("Message bubble corners") and the
          // settings pane can be very narrow.
          Flexible(child: Txt("$label: ", overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          // Flexible + isExpanded, and ellipsis on the labels: several of
          // these options are long ("Default (Always visible)", "Auto-hide
          // when not needed"), and a bare DropdownButton in a Row is handed
          // unbounded width, so it overflows rather than shrinking once the
          // settings pane is narrow.
          Flexible(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              items: options
                  .map((o) => DropdownMenuItem(
                      value: o,
                      child: Text(labelOf(o), overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ]),
      );

  // colorPick is a labelled palette-color dropdown for an optional color,
  // where null means "use the built-in default".
  //
  // Callers pass the field's stored palette slot as `valueIndex` and record
  // the one handed back, so the color keeps following that slot when the
  // palette is edited later, and the dropdown shows the slot it's really
  // bound to rather than the first one that happens to hold the same color
  // -- see PaletteColorDropdown.valueIndex for why that distinction bites.
  Widget colorPick(String label,
          {required Color? value,
          required int? valueIndex,
          required void Function(Color? color, int? index) onChanged,
          String noneLabel = "Default"}) =>
      Row(children: [
        // Both sides give way: a long label ellipsizes rather than pushing
        // the dropdown off the edge, and the dropdown takes what's left
        // rather than its intrinsic width, which the longer palette slot
        // names ("Button Accent Background") overflow a narrow settings
        // column with.
        Flexible(child: Txt("$label: ", overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Expanded(
          child: PaletteColorDropdown(
            preset: preset,
            value: value,
            valueIndex: valueIndex,
            allowNone: true,
            noneLabel: noneLabel,
            isExpanded: true,
            onChanged: onChanged,
          ),
        ),
      ]);

  // colorCell is colorPick laid out as a caption over its dropdown, with
  // its explanation folded in underneath, for use inside `row`. The
  // side-by-side form colorPick uses doesn't survive three of them sharing
  // a line -- the label and the dropdown are each left too narrow to read.
  Widget colorCell(String label,
          {required Color? value,
          required int? valueIndex,
          required void Function(Color? color, int? index) onChanged,
          String noneLabel = "Default",
          String? note}) =>
      labelled(
        label,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PaletteColorDropdown(
            preset: preset,
            value: value,
            valueIndex: valueIndex,
            allowNone: true,
            noneLabel: noneLabel,
            isExpanded: true,
            onChanged: onChanged,
          ),
          if (note != null) ...[
            const SizedBox(height: 4),
            noteText(note),
          ],
        ]),
      );

  // row lays a set of cells out side by side in equal columns, wrapping --
  // and in the narrowest case stacking one per row -- once the settings
  // pane can't give each of them `minWidth`. It's the same layout the
  // shared background/border fill editors use, offered to the area editors
  // for settings that belong together on one line.
  Widget row(List<Widget> cells, {double minWidth = 150}) =>
      responsiveRow(cells, minWidth: minWidth);

  // slider is a drag-buffered slider: it only commits (and so only writes
  // to the preset) when the drag ends, not once per frame. `label` renders
  // the live value, so an area can spell out what its own zero/default
  // position means ("Width: Default", "Selected glow: Off", ...).
  //
  // Every slider carries a type-in box over the same value, so a setting
  // can be dragged roughly or entered exactly -- dragging alone can't
  // reliably land on a round number, and matching one area's value in
  // another is otherwise guesswork. Pass numberField: false for the rare
  // slider whose value isn't a number worth typing.
  Widget slider(String key, double value,
          {required String Function(double)? label,
          double min = 0,
          required double max,
          int? divisions,
          bool numberField = true,
          required ValueChanged<double> onCommit}) =>
      _host.areaSlider(
          key, value, label, min, max, divisions, numberField, onCommit);

  // spacing is a numeric setting that can be split into four -- per side,
  // or per corner for a radius. It's what the shared Border width/radius/
  // Padding/Margin controls are built from; an area's own settings use it
  // for anything with the same shape (a bubble's corners, a panel's inset).
  // See _spacingSetting for how the two states behave.
  List<Widget> spacing({
    required String key,
    required String name,
    required double max,
    required double single,
    required SideValues? sides,
    List<String> slotLabels = sideLabels,
    required ValueChanged<double> onSingle,
    required void Function(SideValues? Function(SideValues?, double))
        updateSides,
  }) =>
      _host.areaSpacing(this,
          key: key,
          name: name,
          max: max,
          single: single,
          sides: sides,
          slotLabels: slotLabels,
          onSingle: onSingle,
          updateSides: updateSides);

  // pickImage prompts for an image file, copies it into the preset's own
  // directory and hands back the path to store, or null if cancelled. SVG
  // is offered alongside the raster formats since some settings (the app
  // icon) render vectors too.
  Future<String?> pickImage(
          {required String suffix,
          required String dialogTitle,
          bool allowSvg = false}) =>
      _host.copyPickedImage(theme,
          suffix: suffix,
          dialogTitle: dialogTitle,
          extensions: [
            "bmp",
            "gif",
            "jpeg",
            "jpg",
            "png",
            "webp",
            if (allowSvg) "svg",
          ]);

  // imagePreview is the clickable thumbnail those settings are edited
  // through -- the box itself opens the picker.
  Widget imagePreview(String? relPath,
          {String? assetFallback, VoidCallback? onPick}) =>
      _host.areaImagePreview(relPath, preset.sourceDir,
          assetFallback: assetFallback, onPick: onPick);

  // note is the small explanatory caption shown under some controls.
  Widget note(String text) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: noteText(text),
      );
}

// AreaEditorHost is the part of the areas section an AreaEditorContext
// delegates back into -- applying an edit, and building the controls whose
// state or layout the section owns rather than the context. It's an
// interface so area_editor_context.dart doesn't have to know about
// AreasSection's private State class; _AreasSectionState is its only
// implementation.
abstract class AreaEditorHost {
  void setAreaStyle(ThemeNotifier theme, AreaStyle Function(AreaStyle) update);

  Widget areaSlider(
      String key,
      double value,
      String Function(double)? label,
      double min,
      double max,
      int? divisions,
      bool numberField,
      ValueChanged<double> onCommit);

  List<Widget> areaSpacing(
    AreaEditorContext ctx, {
    required String key,
    required String name,
    required double max,
    required double single,
    required SideValues? sides,
    required List<String> slotLabels,
    required ValueChanged<double> onSingle,
    required void Function(SideValues? Function(SideValues?, double))
        updateSides,
  });

  Future<String?> copyPickedImage(ThemeNotifier theme,
      {required String suffix,
      required String dialogTitle,
      List<String> extensions});

  Widget areaImagePreview(String? relPath, String? sourceDir,
      {AreaImagePreset? defaultPreset,
      String? assetFallback,
      VoidCallback? onPick});
}
