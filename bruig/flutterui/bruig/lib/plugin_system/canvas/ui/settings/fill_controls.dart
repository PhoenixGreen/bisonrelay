import 'package:flutter/material.dart';

import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/presets/background_looks.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/procedural_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/recent_pictures.dart';

// fill_controls.dart is the controls of a fill that is a picture or a
// pattern: the same set for letters, a box behind them and a shape.

/// fillBits are one fill kind's controls: picture buttons, or a pattern's
/// style and colours. For letters, boxes and shapes.
List<Widget> fillBits(
  BuildContext context,
  TextFill fill,
  ValueChanged<TextFill> onChanged,
  VoidCallback begin,
  VoidCallback commit, {
  /// keyPrefix names the controls, as a panel can carry two sets: the
  /// letters' paint and their box's.
  String keyPrefix = "text",
}) {
  var f = _FillEdit(fill, onChanged, begin, commit, keyPrefix);
  return [
    if (fill.kind == TextFillKind.image) ..._pictureBits(context, f),
    if (fill.kind == TextFillKind.pattern) ..._patternBits(context, f),
    if (fill.on) ..._framingBits(f),
    if (fill.kind == TextFillKind.pattern) ..._patternMore(f),
    if (fill.on && fill.locked)
      const CanvasHint(
          "Locked, the picture travels with the words while they arrive, so "
          "the same bit of it shows through the same letter from the first "
          "frame to the last. Unlocked it stays pinned to the box and the "
          "words sweep across it. It follows a whole-paragraph arrival; "
          "letter by letter there is no single movement to follow."),
  ];
}

/// _FillEdit is the fill the controls show and how they change it:
/// [onChanged] for each step of a drag, [now] for a change made in one go.
class _FillEdit {
  final TextFill fill;
  final ValueChanged<TextFill> onChanged;
  final VoidCallback begin;
  final VoidCallback commit;

  /// prefix starts every control's key: see fillBits.
  final String prefix;
  const _FillEdit(
      this.fill, this.onChanged, this.begin, this.commit, this.prefix);

  void now(TextFill next) {
    begin();
    onChanged(next);
    commit();
  }
}

/// _pictureBits choose the picture, then, once there is one, how it is
/// tiled and looks.
List<Widget> _pictureBits(BuildContext context, _FillEdit f) {
  var fill = f.fill;
  return [
    CanvasIconButton(
      key: ValueKey("${f.prefix}FillPicture"),
      icon: fill.assetId.isEmpty
          ? Icons.add_photo_alternate
          : Icons.image_outlined,
      tooltip: fill.assetId.isEmpty
          ? "Choose a picture to show through the letters"
          : "Replace this picture",
      onPressed: () async {
        var id = await pickCanvasImage(context);
        if (id != null) f.now(fill.copyWith(assetId: id));
      },
    ),
    CanvasIconButton(
      key: ValueKey("${f.prefix}FillLibrary"),
      icon: Icons.photo_library_outlined,
      tooltip: "Use a picture you have already added",
      onPressed: () async {
        var id = await showRecentPictures(context);
        if (id != null) f.now(fill.copyWith(assetId: id));
      },
    ),
    if (fill.assetId.isNotEmpty) ...[
      CanvasToggle(
        label: "Tile",
        value: fill.tile,
        onChanged: (v) => f.now(fill.copyWith(tile: v)),
      ),
      // A picture element's Look (filter, overlay), same names and order;
      // then the two sliders a picture keeps beside Fit.
      CanvasDropdown<ImageFilterPreset>(
        key: ValueKey("${f.prefix}FillLook"),
        label: "Filter",
        value: fill.filter,
        width: 106,
        options: [for (var p in ImageFilterPreset.values) (p, p.label)],
        onChanged: (v) => f.now(fill.copyWith(filter: v)),
      ),
      CanvasDropdown<OverlayBlend>(
        key: ValueKey("${f.prefix}FillBlend"),
        label: "Overlay",
        value: fill.blend,
        width: 106,
        options: [for (var b in OverlayBlend.values) (b, b.label)],
        onChanged: (v) => f.now(fill.copyWith(blend: v)),
      ),
      if (fill.blend != OverlayBlend.none)
        CanvasColorButton(
          key: ValueKey("${f.prefix}FillOverlay"),
          label: "Colour",
          color: fill.overlay,
          // And two colours to fade between, as every swatch has: how a
          // photograph fades into a ground.
          gradient: fill.overlayFade,
          onChanged: (c) => f.now(fill.copyWith(overlay: c)),
          onGradientChanged: (g) => f.now(g == null
              ? fill.copyWith(flatOverlay: true)
              : fill.copyWith(overlayFade: g)),
        ),
      CanvasNumberField(
        key: ValueKey("${f.prefix}FillSaturation"),
        label: "Saturation",
        value: fill.saturation,
        min: 0,
        max: 3,
        decimals: 2,
        width: 62,
        onChanged: (v) => f.onChanged(fill.copyWith(saturation: v)),
        onCommit: f.commit,
      ),
      CanvasNumberField(
        key: ValueKey("${f.prefix}FillBrightness"),
        label: "Brightness",
        value: fill.brightness,
        min: 0,
        max: 3,
        decimals: 2,
        width: 62,
        onChanged: (v) => f.onChanged(fill.copyWith(brightness: v)),
        onCommit: f.commit,
      ),
    ],
  ];
}

/// _patternBits are the three choices a background starts from (style,
/// look, colours), since a pattern in a word is the same pattern; then its
/// colours, how much of it, its size and turn, and another like it.
List<Widget> _patternBits(BuildContext context, _FillEdit f) {
  var fill = f.fill;
  var pattern = fill.pattern;
  void patterned(ProceduralSpec p) => f.now(fill.copyWith(pattern: p));
  return [
    patternStyleDropdown(
      key: ValueKey("${f.prefix}FillPattern"),
      width: 138,
      label: "Pattern",
      spec: pattern,
      onChanged: patterned,
    ),
    patternLookDropdown(
      key: ValueKey("${f.prefix}FillPatternLook"),
      width: 138,
      spec: pattern,
      onChanged: patterned,
    ),
    patternPaletteDropdown(
      context,
      key: ValueKey("${f.prefix}FillPalette"),
      width: 138,
      spec: pattern,
      onChanged: patterned,
    ),
    const CanvasLineBreak(),
    // The same colour as a generated background's Base, so the pattern
    // behind a word can fade as a canvas's does.
    CanvasColorButton(
      label: "Behind",
      color: pattern.background,
      gradient: pattern.gradient,
      onChanged: (c) => patterned(pattern.copyWith(background: c)),
      onGradientChanged: (g) => patterned(g == null
          ? pattern.copyWith(flatBackground: true)
          : pattern.copyWith(gradient: g)),
    ),
    CanvasColorButton(
      label: "Ink",
      color: pattern.foreground,
      onChanged: (c) => patterned(pattern.copyWith(foreground: c)),
    ),
    CanvasColorButton(
      label: "Second",
      color: pattern.accent,
      onChanged: (c) => patterned(pattern.copyWith(accent: c)),
    ),
    CanvasNumberField(
      label: "How much",
      value: pattern.density,
      min: 0,
      max: 1,
      decimals: 2,
      width: 58,
      onChanged: (v) =>
          f.onChanged(fill.copyWith(pattern: pattern.copyWith(density: v))),
      onCommit: f.commit,
    ),
    CanvasNumberField(
      label: "Size",
      value: pattern.scale,
      min: 0.005,
      max: 0.4,
      decimals: 3,
      width: 62,
      onChanged: (v) =>
          f.onChanged(fill.copyWith(pattern: pattern.copyWith(scale: v))),
      onCommit: f.commit,
    ),
    CanvasNumberField(
      label: "Turn",
      value: pattern.rotation,
      min: -180,
      max: 180,
      decimals: 0,
      width: 58,
      onChanged: (v) =>
          f.onChanged(fill.copyWith(pattern: pattern.copyWith(rotation: v))),
      onCommit: f.commit,
    ),
    CanvasIconButton(
      key: ValueKey("${f.prefix}FillSeed"),
      icon: Icons.casino_outlined,
      tooltip: "Another one like it",
      onPressed: () => patterned(pattern.copyWith(seed: pattern.seed + 1)),
    ),
    // Back to the style's own settings, keeping the style.
    CanvasIconButton(
      key: ValueKey("${f.prefix}FillReset"),
      icon: Icons.restart_alt,
      tooltip: "Put this pattern back to how it started",
      onPressed: () => patterned(switch (looksFor(pattern.style).firstOrNull) {
        var first? => withLook(pattern, first),
        null => ProceduralSpec(style: pattern.style),
      }),
    ),
  ];
}

/// _framingBits are how much of a chosen fill lands and where it sits, for
/// both kinds: knocked back, it is a ground, not competing with the words.
/// A colour has its own alpha.
List<Widget> _framingBits(_FillEdit f) {
  var fill = f.fill;
  return [
    CanvasNumberField(
      key: ValueKey("${f.prefix}FillOpacity"),
      label: "Opacity",
      value: fill.opacity,
      min: 0,
      max: 1,
      decimals: 2,
      width: 58,
      onChanged: (v) => f.onChanged(fill.copyWith(opacity: v)),
      onCommit: f.commit,
    ),
    CanvasNumberField(
      label: "Zoom",
      value: fill.zoom,
      min: 0.05,
      max: 20,
      decimals: 2,
      width: 58,
      onChanged: (v) => f.onChanged(fill.copyWith(zoom: v)),
      onCommit: f.commit,
    ),
    // Slid inside its frame, as a share of it: a face put in the middle of
    // a Layout cell, a flame moved to the word it should rise from.
    CanvasNumberField(
      key: ValueKey("${f.prefix}FillPanX"),
      label: "Across",
      value: fill.panX * 100,
      min: -200,
      max: 200,
      decimals: 0,
      suffix: "%",
      width: 58,
      onChanged: (v) => f.onChanged(fill.copyWith(panX: v / 100)),
      onCommit: f.commit,
    ),
    CanvasNumberField(
      key: ValueKey("${f.prefix}FillPanY"),
      label: "Down",
      value: fill.panY * 100,
      min: -200,
      max: 200,
      decimals: 0,
      suffix: "%",
      width: 58,
      onChanged: (v) => f.onChanged(fill.copyWith(panY: v / 100)),
      onCommit: f.commit,
    ),
    if (fill.panX != 0 || fill.panY != 0)
      CanvasIconButton(
        key: ValueKey("${f.prefix}FillPanReset"),
        icon: Icons.filter_center_focus,
        tooltip: "Back to the middle",
        onPressed: () => f.now(fill.copyWith(panX: 0, panY: 0)),
      ),
    CanvasToggle(
      key: ValueKey("${f.prefix}FillLocked"),
      label: "Lock to the words",
      value: fill.locked,
      onChanged: (v) => f.now(fill.copyWith(locked: v)),
    ),
    const CanvasHint(
        "Whatever is chosen is drawn across the whole line and then cut to "
        "the shape of the letters — so a flame or a splatter runs through "
        "the words rather than restarting inside each one. Zoom sizes it "
        "against them: 1 fits it across the words, 2 shows a quarter of it "
        "at twice the size. Across and Down slide it inside its frame."),
  ];
}

/// _patternMore is the rest of the pattern style's settings and effects,
/// behind a heading: a background's controls less those on the row above.
List<Widget> _patternMore(_FillEdit f) => [
      const CanvasLineBreak(),
      CanvasFill(
        child: SizedBox(
          width: 200,
          child: CanvasExpander(
            key: ValueKey("${f.prefix}FillPatternMore"),
            label: "Pattern settings",
            remember: "${f.prefix}.patternMore",
            children: [
              ProceduralSettings(
                fill: true,
                spec: f.fill.pattern,
                onChanged: (p) => f.onChanged(f.fill.copyWith(pattern: p)),
                onBegin: f.begin,
                onCommit: f.commit,
              ),
            ],
          ),
        ),
      ),
    ];
