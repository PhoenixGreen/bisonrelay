import 'dart:io';

import 'package:bruig/components/text.dart';
import 'package:bruig/theming_system/area_fill.dart';
import 'package:bruig/theming_system/area_options.dart';
import 'package:bruig/theming_system/area_sides.dart';
import 'package:bruig/theming_system/area_style.dart';
import 'package:bruig/theming_system/color_palette.dart';
import 'package:bruig/theming_system/palette_color_dropdown.dart';
import 'package:bruig/theming_system/preset.dart';
import 'package:bruig/theming_system/theme_area.dart';
import 'package:bruig/theming_system/theme_editor.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset_storage.dart';
import 'package:bruig/theming_system/theming_area_buttons.dart';
import 'package:bruig/theming_system/theming_area_chat.dart';
import 'package:bruig/theming_system/theming_area_feed.dart';
import 'package:bruig/theming_system/theming_area_header.dart';
import 'package:bruig/theming_system/theming_area_filemanager.dart';
import 'package:bruig/theming_system/theming_area_inputs.dart';
import 'package:bruig/theming_system/theming_area_master.dart';
import 'package:bruig/theming_system/theming_area_mobile.dart';
import 'package:bruig/theming_system/theming_area_navbar.dart';
import 'package:bruig/theming_system/theming_area_realtimechat.dart';
import 'package:bruig/theming_system/theming_area_settings_pages.dart';
import 'package:bruig/theming_system/theming_area_sidebar.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

// theming_areas_section.dart is the "Theme Areas" section of Settings >
// Appearance. It owns the parts every area shares -- the area picker, the
// background/border fill editors, and the spacing sliders -- then hands off
// to that area's own theming_area_<name>.dart file for its specific
// settings, via the AreaEditorContext handed to it.

// _editableAreas is every ThemeArea whose rendering has been wired to
// consult per-area styling (see ThemedArea usages across overview.dart,
// sidebar.dart, startupscreen.dart, containers.dart and the MainMenuItem
// area tags in models/menus.dart), in the order the picker lists them.
const List<ThemeArea> _editableAreas = [
  ThemeArea.masterBackground,
  ThemeArea.header,
  ThemeArea.loginScreen,
  ThemeArea.navBar,
  ThemeArea.dualPanel,
  ThemeArea.subMenuTabBar,
  ThemeArea.contentArea,
  ThemeArea.inputAreas,
  ThemeArea.buttons,
  ThemeArea.chat,
  ThemeArea.feed,
  ThemeArea.realtimeChat,
  ThemeArea.manageContent,
  ThemeArea.settingsPages,
  ThemeArea.mobile,
];

// _framedAreas are the areas that carry a background, border and spacing of
// their own -- the regions of the app's chrome. Everything below them in the
// picker is a *page*, and pages are all framed by Dual Panel now: one entry
// styling the sidebar and content of every page as a single region, instead
// of nine pages each with an identical-looking copy of the same four
// settings that only ever applied to one of them.
//
// That's also why LN Management and Pages are no longer listed at all: the
// frame was the only thing they had. Manage Content is back as "File
// Manager", but for settings of its own rather than a frame.
const Set<ThemeArea> _framedAreas = {
  ThemeArea.masterBackground,
  ThemeArea.header,
  ThemeArea.loginScreen,
  ThemeArea.navBar,
  ThemeArea.dualPanel,
  ThemeArea.subMenuTabBar,
  ThemeArea.contentArea,
};

// _imageAreas is the subset of areas offering a background image at all --
// the four big, mostly-empty surfaces where a full-bleed photo or a tiled
// pattern actually reads as a background. Everywhere else (chat, feed,
// panels, list screens) an image behind dense content just fights it, so
// those areas get color/gradient backgrounds only.
//
// Borders never offer an image, in any area.
const Set<ThemeArea> _imageAreas = {
  ThemeArea.masterBackground,
  ThemeArea.header,
  ThemeArea.loginScreen,
  ThemeArea.navBar,
};

// AreaEditorContext is what a theming_area_<name>.dart file is handed to
// build its own settings: the current preset/style plus the small set of
// controls the area editors are built from. Going through these helpers
// (rather than raw SwitchListTile/DropdownButton/Slider) is what keeps
// every area's settings looking and behaving the same.
class AreaEditorContext {
  final _AreasSectionState _host;

  final ThemeNotifier theme;
  final ThemePreset preset;
  final ThemeArea area;
  final AreaStyle style;

  const AreaEditorContext._(this._host,
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
      _host._setStyle(theme, update);

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
      _labelled(
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
            _noteText(note),
          ],
        ]),
      );

  // row lays a set of cells out side by side in equal columns, wrapping --
  // and in the narrowest case stacking one per row -- once the settings
  // pane can't give each of them `minWidth`. It's the same layout the
  // shared background/border fill editors use, offered to the area editors
  // for settings that belong together on one line.
  Widget row(List<Widget> cells, {double minWidth = 150}) =>
      _responsiveRow(cells, minWidth: minWidth);

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
      _host._slider(
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
      _host._spacingSetting(this,
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
      _host._copyPickedImage(theme,
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
      _host._imagePreview(relPath, preset.sourceDir,
          assetFallback: assetFallback, onPick: onPick);

  // note is the small explanatory caption shown under some controls.
  Widget note(String text) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: _noteText(text),
      );
}

// _noteText is the caption itself, without the indent `note` adds -- a cell
// inside a row is already indented by the column it sits in.
Widget _noteText(String text) => Text(text,
    style: const TextStyle(fontSize: 12, color: Color(0xFF9AA3A0)));

// _areaEditor returns the settings specific to one area, or nothing for the
// areas whose only settings are the shared background/border/spacing ones
// (Login Screen, Dual Panel, Content Area).
List<Widget> _areaEditor(AreaEditorContext ctx) => switch (ctx.area) {
      ThemeArea.masterBackground => masterAreaEditor(ctx),
      ThemeArea.header => headerAreaEditor(ctx),
      ThemeArea.navBar => navBarAreaEditor(ctx),
      ThemeArea.subMenuTabBar => sidebarAreaEditor(ctx),
      ThemeArea.chat => chatAreaEditor(ctx),
      ThemeArea.feed => feedAreaEditor(ctx),
      ThemeArea.realtimeChat => realtimeChatAreaEditor(ctx),
      ThemeArea.inputAreas => inputAreasAreaEditor(ctx),
      ThemeArea.buttons => buttonsAreaEditor(ctx),
      ThemeArea.manageContent => fileManagerAreaEditor(ctx),
      ThemeArea.settingsPages => settingsPagesAreaEditor(ctx),
      ThemeArea.mobile => mobileAreaEditor(ctx),
      _ => const [],
    };

// AreasSection is an embeddable (non-routed) editor for per-area styling,
// sourcing every color from the active palette via dropdowns (see
// PaletteColorDropdown) rather than a color-picker popup.
class AreasSection extends StatefulWidget {
  final ThemeArea? initialArea;
  final ValueChanged<ThemeArea>? onAreaChanged;
  const AreasSection({this.initialArea, this.onAreaChanged, super.key});

  @override
  State<AreasSection> createState() => _AreasSectionState();
}

class _AreasSectionState extends State<AreasSection> {
  late ThemeArea selected = widget.initialArea ?? _editableAreas.first;

  void _setStyle(ThemeNotifier theme, AreaStyle Function(AreaStyle) update) {
    var draft = ensureDraftPreset(theme);
    var current = draft.areas[selected] ?? const AreaStyle();
    theme.previewPreset(
        draft.copyWith(areas: {...draft.areas, selected: update(current)}));
  }

  // _slider keys each _ValueSlider by area *and* setting, so switching areas
  // gives the new area's value a fresh widget state rather than one still
  // holding the previous area's half-typed text.
  Widget _slider(
          String key,
          double value,
          String Function(double)? label,
          double min,
          double max,
          int? divisions,
          bool numberField,
          ValueChanged<double> onCommit) =>
      _ValueSlider(
        key: ValueKey("$selected/$key"),
        label: label,
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        numberField: numberField,
        onCommit: onCommit,
      );

  // _copyPickedImage puts a chosen file in the preset's own directory and
  // returns its path relative to that, or null if the user cancelled.
  // Shared by every area setting that holds an image.
  Future<String?> _copyPickedImage(ThemeNotifier theme,
      {required String suffix,
      required String dialogTitle,
      List<String> extensions = const [
        "bmp",
        "gif",
        "jpeg",
        "jpg",
        "png",
        "webp"
      ]}) async {
    var res = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    var srcPath = res?.files.first.path;
    if (srcPath == null) return null;

    var draft = ensureDraftPreset(theme);
    var relPath = await ThemePresetStorage.saveAreaImage(
        draft.id, selected, srcPath,
        suffix: suffix);
    // saveAreaImage copies the file to disk immediately (even for an
    // unsaved draft), so sourceDir must be set right away too -- otherwise
    // nothing can resolve the path until the preset happens to get saved.
    var presetDir = await ThemePresetStorage.presetDir(draft.id);
    theme.previewPreset(draft.copyWith(sourceDir: presetDir));
    return relPath;
  }

  Future<void> _pickImage(ThemeNotifier theme) async {
    var relPath = await _copyPickedImage(theme,
        suffix: "bg", dialogTitle: "Pick background image");
    if (relPath == null) return;

    var draft = ensureDraftPreset(theme);
    var current = draft.areas[selected] ?? const AreaStyle();
    var style =
        current.copyWith(mode: AreaBackgroundMode.image, imagePath: relPath);
    theme.previewPreset(
        draft.copyWith(areas: {...draft.areas, selected: style}));
  }

  // _imagePreview shows the user's own picked image if one is set;
  // otherwise the built-in image preset that would be painted instead, so
  // users can see what's currently active before deciding to replace it.
  // Uses BoxFit.contain (not cover) deliberately -- the full-bleed presets
  // are screen-sized (e.g. 1024x768), and cover would crop a tiny, often
  // near-blank corner of a sparse image into the thumbnail instead of
  // showing the whole thing shrunk down.
  // The box itself is the control -- clicking it opens the file picker, so
  // there's no separate "Pick image..." button beside it.
  Widget _imagePreview(String? relPath, String? sourceDir,
      {AreaImagePreset? defaultPreset,
      String? assetFallback,
      VoidCallback? onPick}) {
    const size = 64.0;
    ImageProvider? image;
    if (relPath != null && sourceDir != null) {
      image = FileImage(File(path.join(sourceDir, relPath)));
    } else if (defaultPreset != null) {
      image = AssetImage(areaImagePresetAsset(defaultPreset));
    } else if (assetFallback != null) {
      image = AssetImage(assetFallback);
    }

    var radius = BorderRadius.circular(4);
    return Tooltip(
      message: relPath != null ? "Change image..." : "Pick image...",
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onPick,
          borderRadius: radius,
          child: Ink(
            width: size,
            height: size,
            decoration: BoxDecoration(
              // A neutral mid-grey backdrop (not just the surrounding page
              // background) so a sparse/mostly-dark or mostly-transparent
              // image still reads as "there's an image here" at this small
              // a size, instead of blending into a dark theme's own
              // background.
              color: image != null ? Colors.grey.shade700 : null,
              border: Border.all(color: Colors.grey),
              borderRadius: radius,
              image: image != null
                  ? DecorationImage(image: image, fit: BoxFit.contain)
                  : null,
            ),
            child: image == null
                ? const Icon(Icons.add_photo_alternate_outlined,
                    color: Colors.grey)
                : null,
          ),
        ),
      ),
    );
  }

  // _fillEditor builds the mode dropdown + conditional color/gradient-
  // direction/image controls shared by both the background and the border
  // fill -- they support the same modes, just against different AreaStyle
  // fields (except Image, which only the background has).
  //
  // Mode, Color and Image sit side by side across one row (wrapping when
  // the settings pane is too narrow for that), rather than the colour and
  // image being nested under a mode selection: picking any of them is just
  // a different way to fill the same area. Picking a color switches to
  // Solid, picking an image switches to Image, and picking the Color
  // dropdown's own first entry (labelled with this fill's `tokenLabel`)
  // switches back to where it started.
  Widget _fillEditor({
    required ThemePreset preset,
    required String? sourceDir,
    required String label,
    required String tokenLabel,
    required AreaBackgroundMode mode,
    required ValueChanged<AreaBackgroundMode> onModeChanged,
    required Color? solidColor,
    // The palette slot each color was picked from, when it came from one.
    // Passing these (rather than letting the dropdown search the palette
    // for a matching color) is what makes it show the slot the fill is
    // really bound to -- see PaletteColorDropdown.valueIndex.
    required int? solidColorIndex,
    required void Function(Color? color, int? index) onSolidChanged,
    required List<Color> gradientColors,
    required List<int?> gradientColorIndexes,
    required void Function(int index, Color? c, int? colorIndex)
        onGradientColorChanged,
    required Alignment gradientBegin,
    required Alignment gradientEnd,
    required ValueChanged<GradientDirection> onDirectionChanged,
    // allowImage is false for every border, and for the background of every
    // area outside _imageAreas.
    bool allowImage = false,
    String? imagePath,
    AreaImagePreset imagePreset = AreaImagePreset.standard,
    VoidCallback? onPickImage,
    VoidCallback? onRemoveImage,
    // imagePresetCell is the built-in-image picker, passed in as a ready
    // cell so it lines up in this same row (Image, Color and the preset all
    // describe the one fill) rather than sitting under it. Only shown
    // alongside the image controls -- see _imagePresetEditor for the
    // separate case where it appears on its own instead.
    Widget? imagePresetCell,
    // Only meaningful for the background fill -- the border already has an
    // equivalent "no border at all" via its own token/tokenLabel ("None"),
    // so a separate none entry there would just be a confusing duplicate.
    bool supportsNone = false,
    // tokenShownAs replaces this dropdown's "default" entry with whichever
    // real mode that default actually amounts to -- Solid for an area whose
    // untouched background is a color palette slot, Image for one painting
    // a built-in image (the login screen). The dropdown then always names
    // what's in use, rather than hiding it behind an opaque "Default";
    // going back is still one click, via the Color dropdown's own "Default"
    // entry below. Null (borders) keeps the distinct token entry, since
    // "no border" isn't any of the other modes.
    AreaBackgroundMode? tokenShownAs,
  }) {
    var shownMode = mode == AreaBackgroundMode.token && tokenShownAs != null
        ? tokenShownAs
        : mode;
    // The Image entry stays listed for a style that's already on it even
    // when this fill no longer offers images (an older preset with a border
    // image, say): DropdownButton asserts if `value` matches no item. It
    // disappears for good once the user picks anything else.
    var offerImageMode = allowImage || shownMode == AreaBackgroundMode.image;
    // The image controls themselves only belong to a fill that's actually
    // showing an image, in a fill that offers images at all. Offering them
    // beside a Solid one implied a Solid fill could have an image too, when
    // picking one just switches the mode -- which the Image entry in the
    // dropdown already does, plainly. (A border, or an older preset from
    // before this area lost its image picker, can still *be* on image mode;
    // it just gets no dead controls for it, only the dropdown entry above
    // to switch back out.)
    var showImage = allowImage && shownMode == AreaBackgroundMode.image;
    // Color describes every fill except a gradient, which has its own pair
    // of colors below, and None, which has nothing to set.
    var showColor = mode == AreaBackgroundMode.token ||
        mode == AreaBackgroundMode.solid ||
        mode == AreaBackgroundMode.image;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _responsiveRow(
          // A little narrower than the default: these are all dropdowns,
          // which ellipsize their longest entries rather than becoming
          // unusable, and fitting the widest case (four of them, for a
          // gradient or an image) on one line matters more here.
          minWidth: 140,
          [
            _labelled(
              label,
              DropdownButton<AreaBackgroundMode>(
                value: shownMode,
                isExpanded: true,
                items: [
                  if (tokenShownAs == null)
                    DropdownMenuItem(
                        value: AreaBackgroundMode.token,
                        child: Text(tokenLabel)),
                  if (supportsNone)
                    const DropdownMenuItem(
                        value: AreaBackgroundMode.none, child: Text("None")),
                  const DropdownMenuItem(
                      value: AreaBackgroundMode.gradient,
                      child: Text("Gradient")),
                  // Solid isn't usually picked from here directly (the Color
                  // control beside it is the way in), but it must still be a
                  // valid item -- it's what most areas' default background
                  // shows as, and DropdownButton asserts if `value` matches no
                  // item.
                  const DropdownMenuItem(
                      value: AreaBackgroundMode.solid, child: Text("Solid")),
                  if (offerImageMode)
                    const DropdownMenuItem(
                        value: AreaBackgroundMode.image, child: Text("Image")),
                ],
                onChanged: (m) {
                  // Re-picking what's already shown is a no-op -- notably when
                  // that's the folded-in token mode, where acting on it would
                  // quietly convert an area's live palette-backed default into
                  // a frozen Solid/Image of its own.
                  if (m == null || m == shownMode) return;
                  onModeChanged(m);
                },
              ),
            ),
            if (showColor)
              _labelled(
                "Color",
                PaletteColorDropdown(
                  preset: preset,
                  value: mode == AreaBackgroundMode.solid ? solidColor : null,
                  valueIndex:
                      mode == AreaBackgroundMode.solid ? solidColorIndex : null,
                  isExpanded: true,
                  // Always offered, so a picked color is always undoable: this
                  // entry ("Default" for a background, "None" for a border) is
                  // the only way back to the area's untouched fill, since the
                  // mode dropdown beside it no longer lists it separately.
                  allowNone: true,
                  noneLabel: tokenLabel,
                  onChanged: (c, i) {
                    if (c == null) {
                      onModeChanged(AreaBackgroundMode.token);
                      return;
                    }
                    onModeChanged(AreaBackgroundMode.solid);
                    onSolidChanged(c, i);
                  },
                ),
              ),
            if (showImage)
              _labelled(
                "Image",
                Row(children: [
                  _imagePreview(
                    mode == AreaBackgroundMode.image ? imagePath : null,
                    sourceDir,
                    // With no file of the user's own picked, the thumbnail
                    // shows whichever built-in preset is actually being
                    // painted.
                    defaultPreset: imagePreset,
                    onPick: () {
                      onModeChanged(AreaBackgroundMode.image);
                      onPickImage?.call();
                    },
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
              ),
            if (showImage && imagePresetCell != null) imagePresetCell,
            // The gradient's own two colors and direction join the same row
            // rather than stacking below it -- they're this mode's equivalent
            // of the single Color dropdown the other modes show there.
            if (mode == AreaBackgroundMode.gradient) ...[
              for (var i = 0; i < 2; i++)
                _labelled(
                  "Color ${i + 1}",
                  PaletteColorDropdown(
                    preset: preset,
                    value: gradientColors.length > i ? gradientColors[i] : null,
                    valueIndex: gradientColorIndexes.length > i
                        ? gradientColorIndexes[i]
                        : null,
                    isExpanded: true,
                    onChanged: (c, ci) => onGradientColorChanged(i, c, ci),
                  ),
                ),
              _labelled(
                "Direction",
                DropdownButton<GradientDirection>(
                  value: gradientDirectionFor(gradientBegin, gradientEnd),
                  isExpanded: true,
                  items: GradientDirection.values
                      .map((d) => DropdownMenuItem(
                          value: d,
                          child: Text(gradientDirectionLabel(d),
                              // The longest labels in any of these dropdowns;
                              // in a narrow column they ellipsize rather than
                              // overflowing the button.
                              overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (d) {
                    if (d != null) onDirectionChanged(d);
                  },
                ),
              ),
            ],
          ]),
    ]);
  }

  // _spacingSetting builds one of the four spacing settings every area has
  // (border width, border radius, padding, margin): a single slider
  // covering all four sides, or -- once split with the button beside its
  // name -- one slider per side laid out across the width.
  //
  // Splitting seeds all four sides from the single value; collapsing drops
  // them and goes back to that same single value, which is left untouched
  // while split. Zero means "use this area's built-in default" throughout,
  // split or not, which is why the name reads "...: Default" there rather
  // than the setting genuinely being zero.
  List<Widget> _spacingSetting(
    AreaEditorContext ctx, {
    required String key,
    required String name,
    required double max,
    required double single,
    required SideValues? sides,
    required List<String> slotLabels,
    required ValueChanged<double> onSingle,
    // updateSides is handed a transform rather than a finished value, so
    // that editing one side re-reads the other three from the *current*
    // style instead of this build's snapshot of them -- see setStyle.
    required void Function(SideValues? Function(SideValues?, double))
        updateSides,
  }) {
    var split = sides != null;
    var isDefault = split ? sides.isZero : single <= 0;
    return [
      Row(children: [
        Expanded(child: Text(isDefault ? "$name: Default" : name)),
        TextButton.icon(
          onPressed: () => updateSides(
              (cur, one) => cur == null ? SideValues.all(one) : null),
          icon: Icon(split ? Icons.call_merge : Icons.call_split, size: 16),
          label: Text(split ? "One value" : "Per side"),
          style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact),
        ),
      ]),
      if (!split)
        ctx.slider(key, single,
            label: null, max: max, numberField: true, onCommit: onSingle)
      else
        _responsiveRow(
          [
            for (var i = 0; i < 4; i++)
              ctx.slider("$key.$i", sides[i],
                  label: (_) => slotLabels[i],
                  max: max,
                  numberField: true,
                  onCommit: (v) => updateSides((cur, one) =>
                      (cur ?? SideValues.all(one)).withValue(i, v))),
          ],
          // Wide enough for a usable slider plus its number box; below
          // that the four stack instead of all becoming unusable.
          minWidth: 190,
        ),
      // Keeps consecutive settings from reading as one block, which
      // matters most when several are split into four at once.
      const SizedBox(height: 8),
    ];
  }

  // _backgroundTokenShownAs is the real background mode an area's untouched
  // "default" amounts to, and so what the Background dropdown names while
  // the style is still on token -- see _fillEditor's tokenShownAs. Every
  // area's default background is its palette color, except the login
  // screen's, which has always been a built-in image.
  AreaBackgroundMode _backgroundTokenShownAs(ThemeArea area) =>
      area == ThemeArea.loginScreen
          ? AreaBackgroundMode.image
          : AreaBackgroundMode.solid;

  // _imagePresetCell is the built-in-image picker, as a cell for the
  // background fill's own row -- it's part of choosing that background, so
  // it belongs beside the Image control rather than under it. Null for an
  // area with no images, or one whose background isn't showing one.
  Widget? _imagePresetCell(AreaEditorContext ctx) {
    var shownMode = ctx.style.mode == AreaBackgroundMode.token
        ? _backgroundTokenShownAs(ctx.area)
        : ctx.style.mode;
    if (!_imageAreas.contains(ctx.area) ||
        shownMode != AreaBackgroundMode.image) {
      return null;
    }
    return _labelled("Image preset", _imagePresetDropdown(ctx));
  }

  Widget _imagePresetDropdown(AreaEditorContext ctx) =>
      DropdownButton<AreaImagePreset>(
        value: ctx.style.imagePreset,
        isExpanded: true,
        items: AreaImagePreset.values
            .map((p) => DropdownMenuItem(
                value: p,
                child: Text(areaImagePresetLabel(p),
                    overflow: TextOverflow.ellipsis)))
            .toList(),
        onChanged: (p) {
          if (p != null) ctx.setStyle((s) => s.copyWith(imagePreset: p));
        },
      );

  // _imagePresetEditor covers what the fill's own row can't: the note for
  // when a picked image file is overriding the preset, and the one case
  // where the preset needs its own line -- a non-default preset layered
  // over an otherwise default background, where the fill row shows Solid
  // and so has no image controls to sit beside. Leaving that reachable is
  // what keeps such a preset undoable rather than stranded.
  List<Widget> _imagePresetEditor(AreaEditorContext ctx) {
    if (!_imageAreas.contains(ctx.area)) return const [];
    var mode = ctx.style.mode;
    var stranded = mode == AreaBackgroundMode.token &&
        _backgroundTokenShownAs(ctx.area) != AreaBackgroundMode.image &&
        ctx.style.imagePreset != AreaImagePreset.standard;
    return [
      if (stranded) ...[
        const SizedBox(height: 12),
        ctx.choice<AreaImagePreset>(
          "Image preset",
          value: ctx.style.imagePreset,
          options: AreaImagePreset.values,
          labelOf: areaImagePresetLabel,
          onChanged: (p) => ctx.setStyle((s) => s.copyWith(imagePreset: p)),
        ),
      ],
      if (mode == AreaBackgroundMode.image && ctx.style.imagePath != null)
        ctx.note("A picked image file is in use -- remove it to go back to "
            "the image preset."),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(builder: (context, theme, _) {
      var preset = displayPreset(theme);
      var style = preset.areas[selected] ?? const AreaStyle();
      var ctx = AreaEditorContext._(this,
          theme: theme, preset: preset, area: selected, style: style);

      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DropdownButton<ThemeArea>(
          value: selected,
          isExpanded: true,
          items: _editableAreas
              .map((a) =>
                  DropdownMenuItem(value: a, child: Text(themeAreaLabel(a))))
              .toList(),
          onChanged: (a) => setState(() {
            if (a != null) {
              selected = a;
              widget.onAreaChanged?.call(a);
            }
          }),
        ),
        // One gap under the area picker for every area, whether what
        // follows is the frame block or the area's own first setting --
        // some of those start with a control carrying no padding of its
        // own, which used to leave them sitting flush against the picker.
        const SizedBox(height: 20),
        // The background/border/spacing block, for the areas that have a
        // frame of their own. A page doesn't: Dual Panel frames every
        // page's sidebar and content together (see _framedAreas).
        if (_framedAreas.contains(selected)) ...[
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
                next = next.copyWith(
                    solidColor: preset.primary,
                    solidColorIndex: PaletteSlot.primary.index);
              }
              if (m == AreaBackgroundMode.gradient &&
                  next.gradientColors.length < 2) {
                next = next.copyWith(gradientColors: [
                  preset.primary,
                  preset.secondary
                ], gradientColorIndexes: [
                  PaletteSlot.primary.index,
                  PaletteSlot.secondary.index
                ]);
              }
              return next;
            }),
            solidColor: style.resolveSolidColor(theme),
            solidColorIndex: style.solidColorIndex,
            onSolidChanged: (c, i) => _setStyle(
                theme,
                (s) => s.copyWith(
                    solidColor: c,
                    solidColorIndex: i,
                    clearSolidColorIndex: i == null)),
            gradientColors: style.resolveGradientColors(theme),
            gradientColorIndexes: style.gradientColorIndexes,
            onGradientColorChanged: (i, c, ci) => _setStyle(theme, (s) {
              var (colors, indexes) = _withGradientColor(
                  s.gradientColors, s.gradientColorIndexes, i, c, ci,
                  fallback: preset.primary,
                  fallbackIndex: PaletteSlot.primary.index);
              return s.copyWith(
                  gradientColors: colors, gradientColorIndexes: indexes);
            }),
            gradientBegin: style.gradientBegin,
            gradientEnd: style.gradientEnd,
            onDirectionChanged: (d) => _setStyle(theme, (s) {
              var (b, e) = gradientDirectionAlignments(d);
              return s.copyWith(gradientBegin: b, gradientEnd: e);
            }),
            allowImage: _imageAreas.contains(selected),
            imagePath: style.imagePath,
            imagePreset: style.imagePreset,
            imagePresetCell: _imagePresetCell(ctx),
            onPickImage: () => _pickImage(theme),
            onRemoveImage: () => _setStyle(
                theme,
                (s) => s.copyWith(
                    mode: AreaBackgroundMode.token, clearImagePath: true)),
            supportsNone: true,
            tokenShownAs: _backgroundTokenShownAs(selected),
          ),
          ..._imagePresetEditor(ctx),
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
                next = next.copyWith(
                    borderColor: preset.outline,
                    borderColorIndex: PaletteSlot.outline.index);
              }
              if (m == AreaBackgroundMode.gradient &&
                  next.borderGradientColors.length < 2) {
                next = next.copyWith(borderGradientColors: [
                  preset.outline,
                  preset.primary
                ], borderGradientColorIndexes: [
                  PaletteSlot.outline.index,
                  PaletteSlot.primary.index
                ]);
              }
              if (m != AreaBackgroundMode.token && next.borderWidth <= 0) {
                next = next.copyWith(borderWidth: 2);
              }
              return next;
            }),
            solidColor: style.resolveBorderColor(theme),
            solidColorIndex: style.borderColorIndex,
            onSolidChanged: (c, i) => _setStyle(
                theme,
                (s) => s.copyWith(
                    borderColor: c,
                    borderColorIndex: i,
                    clearBorderColorIndex: i == null)),
            gradientColors: style.resolveBorderGradientColors(theme),
            gradientColorIndexes: style.borderGradientColorIndexes,
            onGradientColorChanged: (i, c, ci) => _setStyle(theme, (s) {
              var (colors, indexes) = _withGradientColor(s.borderGradientColors,
                  s.borderGradientColorIndexes, i, c, ci,
                  fallback: preset.outline,
                  fallbackIndex: PaletteSlot.outline.index);
              return s.copyWith(
                  borderGradientColors: colors,
                  borderGradientColorIndexes: indexes);
            }),
            gradientBegin: style.borderGradientBegin,
            gradientEnd: style.borderGradientEnd,
            onDirectionChanged: (d) => _setStyle(theme, (s) {
              var (b, e) = gradientDirectionAlignments(d);
              return s.copyWith(borderGradientBegin: b, borderGradientEnd: e);
            }),
            // No allowImage/onPickImage: borders are never image-filled.
            imagePath: style.borderImagePath,
          ),
          const SizedBox(height: 8),
          ..._spacingSetting(ctx,
              key: "borderWidth",
              name: "Border width",
              max: 10,
              single: style.borderWidth,
              sides: style.borderWidthSides,
              slotLabels: sideLabels,
              onSingle: (v) => ctx.setStyle((s) => s.copyWith(borderWidth: v)),
              updateSides: (f) => ctx.setStyle((s) {
                    var next = f(s.borderWidthSides, s.borderWidth);
                    return s.copyWith(
                        borderWidthSides: next,
                        clearBorderWidthSides: next == null);
                  })),
          ..._spacingSetting(ctx,
              key: "borderRadius",
              name: "Border radius",
              max: 48,
              single: style.borderRadius,
              sides: style.borderRadiusSides,
              // Radius is the one of the four measured at the corners rather
              // than along the edges.
              slotLabels: cornerLabels,
              onSingle: (v) => ctx.setStyle((s) => s.copyWith(borderRadius: v)),
              updateSides: (f) => ctx.setStyle((s) {
                    var next = f(s.borderRadiusSides, s.borderRadius);
                    return s.copyWith(
                        borderRadiusSides: next,
                        clearBorderRadiusSides: next == null);
                  })),
          // Header padding maps to titleSpacing (the gap either side of the
          // title) rather than a container inset, so it gets a larger range
          // appropriate for that.
          //
          // The nav bar has neither: the sidebarx package lays that bar out
          // from its own metrics and ignores anything handed to it here, so
          // both sliders are left out rather than left dead.
          if (selected != ThemeArea.navBar) ...[
            ..._spacingSetting(ctx,
                key: "padding",
                name: "Padding",
                max: selected == ThemeArea.header ? 100 : 48,
                single: style.padding,
                sides: style.paddingSides,
                slotLabels: sideLabels,
                onSingle: (v) => ctx.setStyle((s) => s.copyWith(padding: v)),
                updateSides: (f) => ctx.setStyle((s) {
                      var next = f(s.paddingSides, s.padding);
                      return s.copyWith(
                          paddingSides: next, clearPaddingSides: next == null);
                    })),
            ..._spacingSetting(ctx,
                key: "margin",
                name: "Margin",
                max: 48,
                single: style.margin,
                sides: style.marginSides,
                slotLabels: sideLabels,
                onSingle: (v) => ctx.setStyle((s) => s.copyWith(margin: v)),
                updateSides: (f) => ctx.setStyle((s) {
                      var next = f(s.marginSides, s.margin);
                      return s.copyWith(
                          marginSides: next, clearMarginSides: next == null);
                    })),
          ],
        ],
        ..._areaEditor(ctx),
      ]);
    });
  }
}

// _ValueSlider is one numeric setting: a slider, and optionally a type-in
// box over the same value, so it can be dragged roughly or set exactly.
//
// Neither control writes on every change. The slider commits when the drag
// ends, not once per frame, and the box when it's submitted or loses focus,
// not per keystroke -- each commit rewrites the draft preset and rebuilds
// the whole app's theme through it, which is far too much work to do per
// frame or per character.
class _ValueSlider extends StatefulWidget {
  // label renders the live value above the slider; null leaves it off, for
  // a caller that has already labelled this value itself.
  final String Function(double)? label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final bool numberField;
  final ValueChanged<double> onCommit;

  const _ValueSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.numberField,
    required this.onCommit,
    super.key,
  });

  @override
  State<_ValueSlider> createState() => _ValueSliderState();
}

class _ValueSliderState extends State<_ValueSlider> {
  // _dragging holds the in-flight value while the slider's thumb is down,
  // so the label and box track the drag before it's committed.
  double? _dragging;
  late final TextEditingController _ctrl =
      TextEditingController(text: _format(widget.value));
  late final FocusNode _focus = FocusNode()..addListener(_focusChanged);

  double get _shown => _dragging ?? widget.value;

  static String _format(double v) => v.toStringAsFixed(1);

  @override
  void didUpdateWidget(covariant _ValueSlider old) {
    super.didUpdateWidget(old);
    // Mirror an outside change (the slider, or a reset elsewhere) into the
    // box -- but never while it's focused, which would rewrite what the
    // user is in the middle of typing.
    if (!_focus.hasFocus && widget.value != old.value) {
      _ctrl.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (!_focus.hasFocus) _commitText();
  }

  void _commitText() {
    // Anything unparseable, negative or past this setting's range snaps
    // back to what's actually set, rather than quietly applying something
    // else or leaving the box disagreeing with the slider beside it.
    var parsed = double.tryParse(_ctrl.text.trim());
    var v = parsed == null
        ? widget.value
        : parsed.clamp(widget.min, widget.max).toDouble();
    if (_ctrl.text != _format(v)) _ctrl.text = _format(v);
    if (v != widget.value) widget.onCommit(v);
  }

  @override
  Widget build(BuildContext context) {
    var slider = Slider(
      value: _shown.clamp(widget.min, widget.max),
      min: widget.min,
      max: widget.max,
      divisions: widget.divisions,
      onChanged: (v) => setState(() {
        _dragging = v;
        if (!_focus.hasFocus) _ctrl.text = _format(v);
      }),
      onChangeEnd: (v) {
        setState(() => _dragging = null);
        // Commit exactly what the box shows. A continuous slider otherwise
        // lands on values with more precision than the box displays, and
        // the box would then "change" the setting to its own rounded
        // reading the next time it merely lost focus.
        widget.onCommit(double.parse(_format(v)));
      },
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.label != null) Text(widget.label!(_shown)),
      Row(children: [
        Expanded(child: slider),
        if (widget.numberField)
          SizedBox(
            width: 58,
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              textAlign: TextAlign.center,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _commitText(),
            ),
          ),
      ]),
    ]);
  }
}

// _responsiveRow lays `cells` out side by side in equal columns, wrapping
// onto further rows -- and in the narrowest case one per row -- as soon as
// the available width can't give every cell at least `minWidth`. Equal
// widths (rather than each cell taking what it needs) are what keeps the
// controls lined up in columns across a wrap.
Widget _responsiveRow(List<Widget> cells, {double minWidth = 150}) {
  if (cells.isEmpty) return const SizedBox.shrink();
  const gap = 16.0;
  return LayoutBuilder(builder: (context, constraints) {
    var perRow = ((constraints.maxWidth + gap) / (minWidth + gap))
        .floor()
        .clamp(1, cells.length);
    var width = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
    return Wrap(
      spacing: gap,
      runSpacing: 12,
      children: [
        for (var cell in cells) SizedBox(width: width, child: cell),
      ],
    );
  });
}

// _withGradientColor sets one of a gradient's two colors, returning the
// color list and the matching list of palette slots it was picked from
// (null for a custom color). The two are kept the same length and updated
// together so an index can never end up describing a different color than
// the one it was stored for -- the failure that makes a bound color follow
// the wrong palette slot.
(List<Color>, List<int?>) _withGradientColor(
  List<Color> colors,
  List<int?> indexes,
  int at,
  Color? color,
  int? colorIndex, {
  required Color fallback,
  required int fallbackIndex,
}) {
  var nextColors = List<Color>.from(colors);
  var nextIndexes = List<int?>.from(indexes);
  // A gradient always has two colors; older data (or a style switched into
  // gradient mode without both seeded) may have fewer.
  while (nextColors.length < 2) {
    nextColors.add(fallback);
  }
  while (nextIndexes.length < nextColors.length) {
    nextIndexes.add(fallbackIndex);
  }
  nextColors[at] = color ?? fallback;
  nextIndexes[at] = color == null ? fallbackIndex : colorIndex;
  return (nextColors, nextIndexes);
}

// _labelled is one cell of a _responsiveRow: a caption over its control.
Widget _labelled(String label, Widget control) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Txt(label),
      const SizedBox(height: 4),
      control,
    ]);
