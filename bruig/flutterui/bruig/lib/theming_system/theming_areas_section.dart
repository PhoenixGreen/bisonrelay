import 'dart:io';

import 'package:bruig/components/text.dart';
import 'package:bruig/theming_system/area_fill.dart';
import 'package:bruig/theming_system/area_style.dart';
import 'package:bruig/theming_system/color_palette.dart';
import 'package:bruig/theming_system/palette_color_dropdown.dart';
import 'package:bruig/theming_system/preset.dart';
import 'package:bruig/theming_system/theme_area.dart';
import 'package:bruig/theming_system/theme_editor.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset_storage.dart';
import 'package:bruig/theming_system/theming_area_chat.dart';
import 'package:bruig/theming_system/theming_area_feed.dart';
import 'package:bruig/theming_system/theming_area_header.dart';
import 'package:bruig/theming_system/theming_area_login.dart';
import 'package:bruig/theming_system/theming_area_master.dart';
import 'package:bruig/theming_system/theming_area_navbar.dart';
import 'package:bruig/theming_system/theming_area_realtimechat.dart';
import 'package:bruig/theming_system/theming_area_sidebar.dart';
import 'package:bruig/theming_system/theming_area_stats.dart';
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
          Txt("$label: "),
          const SizedBox(width: 8),
          DropdownButton<T>(
            value: value,
            items: options
                .map((o) => DropdownMenuItem(value: o, child: Text(labelOf(o))))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ]),
      );

  // colorPick is a labelled palette-color dropdown for an optional color,
  // where null means "use the built-in default".
  Widget colorPick(String label,
          {required Color? value,
          required ValueChanged<Color?> onChanged,
          String noneLabel = "Default"}) =>
      Row(children: [
        Txt("$label: "),
        const SizedBox(width: 8),
        PaletteColorDropdown(
          preset: preset,
          value: value,
          allowNone: true,
          noneLabel: noneLabel,
          onChanged: (c, _) => onChanged(c),
        ),
      ]);

  // slider is a drag-buffered slider: it only commits (and so only writes
  // to the preset) when the drag ends, not once per frame. `label` renders
  // the live value, so an area can spell out what its own zero/default
  // position means ("Width: Default", "Selected glow: Off", ...).
  Widget slider(String key, double value,
          {required String Function(double) label,
          double min = 0,
          required double max,
          int? divisions,
          required ValueChanged<double> onCommit}) =>
      _host._slider(key, value, label, min, max, divisions, onCommit);

  // note is the small explanatory caption shown under some controls.
  Widget note(String text) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(text,
            style: const TextStyle(fontSize: 12, color: Color(0xFF9AA3A0))),
      );
}

// _areaEditor returns the settings specific to one area, or nothing for the
// areas whose only settings are the shared background/border/spacing ones
// (LN Management, Pages, Manage Content, Logs).
List<Widget> _areaEditor(AreaEditorContext ctx) => switch (ctx.area) {
      ThemeArea.masterBackground => masterAreaEditor(ctx),
      ThemeArea.header => headerAreaEditor(ctx),
      ThemeArea.navBar => navBarAreaEditor(ctx),
      ThemeArea.subMenuTabBar => sidebarAreaEditor(ctx),
      ThemeArea.chat => chatAreaEditor(ctx),
      ThemeArea.feed => feedAreaEditor(ctx),
      ThemeArea.realtimeChat => realtimeChatAreaEditor(ctx),
      ThemeArea.stats => statsAreaEditor(ctx),
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
  // _dragValues holds the in-flight value of any slider currently being
  // dragged, keyed by that slider's own key -- see _slider.
  final Map<String, double> _dragValues = {};

  void _setStyle(ThemeNotifier theme, AreaStyle Function(AreaStyle) update) {
    var draft = ensureDraftPreset(theme);
    var current = draft.areas[selected] ?? const AreaStyle();
    theme.previewPreset(
        draft.copyWith(areas: {...draft.areas, selected: update(current)}));
  }

  Widget _slider(String key, double value, String Function(double) label,
      double min, double max, int? divisions, ValueChanged<double> onCommit) {
    var shown = _dragValues[key] ?? value;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label(shown)),
      Slider(
        value: shown,
        min: min,
        max: max,
        divisions: divisions,
        onChanged: (v) => setState(() => _dragValues[key] = v),
        onChangeEnd: (v) {
          setState(() => _dragValues.remove(key));
          onCommit(v);
        },
      ),
    ]);
  }

  Future<void> _pickImage(ThemeNotifier theme, {required bool forBorder}) async {
    var res = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      dialogTitle: "Pick ${forBorder ? 'border' : 'background'} image",
      type: FileType.custom,
      allowedExtensions: ["bmp", "gif", "jpeg", "jpg", "png", "webp"],
    );
    var srcPath = res?.files.first.path;
    if (srcPath == null) return;

    var draft = ensureDraftPreset(theme);
    var relPath = await ThemePresetStorage.saveAreaImage(
        draft.id, selected, srcPath,
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
        : current.copyWith(mode: AreaBackgroundMode.image, imagePath: relPath);
    theme.previewPreset(draft.copyWith(
        sourceDir: presetDir, areas: {...draft.areas, selected: style}));
  }

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
    required void Function(Color? color, int? index) onSolidChanged,
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
                      value:
                          mode == AreaBackgroundMode.solid ? solidColor : null,
                      allowNone:
                          allowSolidNone || mode != AreaBackgroundMode.solid,
                      onChanged: (c, i) {
                        onModeChanged(AreaBackgroundMode.solid);
                        onSolidChanged(c, i);
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
                          defaultAssetPath: mode == AreaBackgroundMode.token
                              ? defaultAssetPath
                              : null),
                      const SizedBox(width: 8),
                      Flexible(
                        child: OutlinedButton(
                          onPressed: () {
                            onModeChanged(AreaBackgroundMode.image);
                            onPickImage();
                          },
                          child: Text(mode == AreaBackgroundMode.image &&
                                  imagePath != null
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
        for (var i = 0; i < 2; i++)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Txt("Color ${i + 1}: "),
              const SizedBox(width: 8),
              PaletteColorDropdown(
                preset: preset,
                value: gradientColors.length > i ? gradientColors[i] : null,
                onChanged: (c, _) => onGradientColorChanged(i, c),
              ),
            ]),
          ),
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
            _dragValues.clear();
          }),
        ),
        // Sidebar's background is deliberately not user-overridable here --
        // it always reads the "Sidebar background" color palette slot
        // directly (see SecondarySideMenu in containers.dart), so editing
        // it lives in the Color Palette section, not a per-area fill mode
        // that could silently diverge from it.
        if (selected != ThemeArea.subMenuTabBar) ...[
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
                next = next.copyWith(
                    solidColor: preset.primary,
                    solidColorIndex: PaletteSlot.primary.index);
              }
              if (m == AreaBackgroundMode.gradient &&
                  next.gradientColors.length < 2) {
                next = next.copyWith(
                    gradientColors: [preset.primary, preset.secondary]);
              }
              return next;
            }),
            solidColor: style.resolveSolidColor(theme),
            onSolidChanged: (c, i) => _setStyle(
                theme,
                (s) => s.copyWith(
                    solidColor: c,
                    solidColorIndex: i,
                    clearSolidColorIndex: i == null)),
            allowSolidNone: false,
            gradientColors: style.gradientColors,
            onGradientColorChanged: (i, c) => _setStyle(theme, (s) {
              var colors = List<Color>.from(s.gradientColors);
              while (colors.length < 2) {
                colors.add(preset.primary);
              }
              colors[i] = c ?? preset.primary;
              return s.copyWith(gradientColors: colors);
            }),
            gradientBegin: style.gradientBegin,
            gradientEnd: style.gradientEnd,
            onDirectionChanged: (d) => _setStyle(theme, (s) {
              var (b, e) = gradientDirectionAlignments(d);
              return s.copyWith(gradientBegin: b, gradientEnd: e);
            }),
            imagePath: style.imagePath,
            onPickImage: () => _pickImage(theme, forBorder: false),
            onRemoveImage: () => _setStyle(
                theme,
                (s) => s.copyWith(
                    mode: AreaBackgroundMode.token, clearImagePath: true)),
            defaultAssetPath: selected == ThemeArea.loginScreen
                ? "assets/images/loading-bg.png"
                : null,
            supportsNone: true,
          ),
        ],
        ...loginAreaBackgroundEditor(ctx),
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
              next = next.copyWith(
                  borderGradientColors: [preset.outline, preset.primary]);
            }
            if (m != AreaBackgroundMode.token && next.borderWidth <= 0) {
              next = next.copyWith(borderWidth: 2);
            }
            return next;
          }),
          solidColor: style.resolveBorderColor(theme),
          onSolidChanged: (c, i) => _setStyle(
              theme,
              (s) => s.copyWith(
                  borderColor: c,
                  borderColorIndex: i,
                  clearBorderColorIndex: i == null)),
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
          onPickImage: () => _pickImage(theme, forBorder: true),
          onRemoveImage: () => _setStyle(
              theme,
              (s) => s.copyWith(
                  borderMode: AreaBackgroundMode.token,
                  clearBorderImagePath: true)),
        ),
        const SizedBox(height: 8),
        ctx.slider("borderWidth", style.borderWidth,
            label: (v) => "Border width: ${v.toStringAsFixed(1)}",
            max: 10,
            onCommit: (v) => ctx.setStyle((s) => s.copyWith(borderWidth: v))),
        ctx.slider("borderRadius", style.borderRadius,
            label: (v) => "Border radius: ${v.toStringAsFixed(1)}",
            max: 48,
            onCommit: (v) => ctx.setStyle((s) => s.copyWith(borderRadius: v))),
        // Padding and margin have no visible effect on navBar -- it's
        // composed by the third-party sidebarx package's own fixed layout,
        // which doesn't consult either field -- so both are hidden there as
        // dead controls. For header, padding maps to titleSpacing (the gap
        // around the title), so it's kept, just with a larger range
        // appropriate for that.
        if (selected != ThemeArea.navBar) ...[
          ctx.slider("padding", style.padding,
              label: (v) => "Padding: ${v.toStringAsFixed(1)}",
              max: selected == ThemeArea.header ? 100 : 48,
              onCommit: (v) => ctx.setStyle((s) => s.copyWith(padding: v))),
          ctx.slider("margin", style.margin,
              label: (v) => "Margin: ${v.toStringAsFixed(1)}",
              max: 48,
              onCommit: (v) => ctx.setStyle((s) => s.copyWith(margin: v))),
        ],
        // Width is only wired for the Sidebar. navBar's width is
        // deliberately not user-configurable -- the sidebarx package's
        // collapse/extend toggle button assumes specific width values for
        // its own animation, and overriding them broke it.
        if (selected == ThemeArea.subMenuTabBar)
          ctx.slider("width", style.width ?? 0,
              // 0 means "use this area's built-in default width" rather
              // than an actual zero-width panel, so "reset to default"
              // stays reachable from the slider itself.
              label: (v) =>
                  v <= 0 ? "Width: Default" : "Width: ${v.toStringAsFixed(1)}",
              max: 400,
              onCommit: (v) => ctx.setStyle((s) =>
                  v <= 0 ? s.copyWith(clearWidth: true) : s.copyWith(width: v))),
        ..._areaEditor(ctx),
      ]);
    });
  }
}
