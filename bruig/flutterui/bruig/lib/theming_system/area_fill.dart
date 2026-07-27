import 'package:bruig/theming_system/area_options.dart';
import 'package:flutter/material.dart';

// area_fill.dart describes *how* an area's background or border is painted.
// Both layers support the same set of modes and share the same gradient
// vocabulary; see AreaStyle for the fields themselves.

// AreaBackgroundMode selects how a fill (background or border) is painted.
// token = "use the app's normal color scheme" (opaque, matches how the area
// looked before this feature existed). none is a distinct, explicit "no
// fill at all" (fully transparent) -- useful e.g. for a submenu/tab-bar
// area where a border/padding is wanted but no background color at all.
enum AreaBackgroundMode { token, none, solid, gradient, image }

// GradientDirection is a small set of named, dropdown-friendly gradient
// directions (rather than a free-form angle input, consistent with this
// app's "dropdowns not fiddly custom controls" settings UX).
enum GradientDirection {
  topLeftToBottomRight,
  topRightToBottomLeft,
  leftToRight,
  topToBottom,
}

const Map<GradientDirection, String> _gradientDirectionLabels = {
  GradientDirection.topLeftToBottomRight: "Top-left → Bottom-right",
  GradientDirection.topRightToBottomLeft: "Top-right → Bottom-left",
  GradientDirection.leftToRight: "Left → Right",
  GradientDirection.topToBottom: "Top → Bottom",
};

String gradientDirectionLabel(GradientDirection d) =>
    _gradientDirectionLabels[d]!;

const Map<GradientDirection, (Alignment, Alignment)>
    _gradientDirectionAlignments = {
  GradientDirection.topLeftToBottomRight:
      (Alignment.topLeft, Alignment.bottomRight),
  GradientDirection.topRightToBottomLeft:
      (Alignment.topRight, Alignment.bottomLeft),
  GradientDirection.leftToRight: (Alignment.centerLeft, Alignment.centerRight),
  GradientDirection.topToBottom: (Alignment.topCenter, Alignment.bottomCenter),
};

(Alignment, Alignment) gradientDirectionAlignments(GradientDirection d) =>
    _gradientDirectionAlignments[d]!;

// gradientDirectionFor maps a stored begin/end alignment pair back to the
// named direction that produced it, for the editor's dropdown.
GradientDirection gradientDirectionFor(Alignment begin, Alignment end) {
  for (var entry in _gradientDirectionAlignments.entries) {
    var (b, e) = entry.value;
    if (b == begin && e == end) return entry.key;
  }
  return GradientDirection.topLeftToBottomRight;
}

// _areaImagePresetAssets maps each built-in image preset to its asset. The
// pattern-*.png ones are small (128x128, under 1.5KB) seamless tiles.
const Map<AreaImagePreset, String> _areaImagePresetAssets = {
  AreaImagePreset.standard: "assets/images/loading-bg.png",
  AreaImagePreset.exitus1: "assets/images/login_bg.png",
  AreaImagePreset.grid: "assets/images/pattern-grid.png",
  AreaImagePreset.dots: "assets/images/pattern-dots.png",
  AreaImagePreset.diagonal: "assets/images/pattern-diagonal.png",
  AreaImagePreset.crosshatch: "assets/images/pattern-crosshatch.png",
  AreaImagePreset.waves: "assets/images/pattern-waves.png",
};

// areaImagePresetAsset is the raw asset path behind a preset -- for the
// theme editor's own thumbnail, which needs an ImageProvider rather than a
// laid-out DecorationImage.
String areaImagePresetAsset(AreaImagePreset p) => _areaImagePresetAssets[p]!;

// loginDefaultBackgroundImage is the standard preset's asset framed exactly
// the way the login screen has always painted it: anchored to the top-right
// at full height, over no background color at all. That framing only suits
// a full-screen area with the form floating over it -- see
// areaImagePresetImage for how the same asset is laid out everywhere else.
const DecorationImage loginDefaultBackgroundImage = DecorationImage(
  image: AssetImage("assets/images/loading-bg.png"),
  alignment: Alignment.topRight,
  fit: BoxFit.fitHeight,
);

// areaImagePresetImage is how a built-in preset actually paints as an area
// background. The two full-bleed photos cover the area, so they read as a
// background at any shape -- a wide header strip, the narrow nav column or
// a full-screen master background alike (fitting them to height instead,
// as the login screen frames its own default, leaves everything but a
// full-screen area showing a sliver of one edge). Every other preset is a
// small seamless tile, so it repeats at its natural size rather than being
// stretched to whatever the area happens to be.
DecorationImage areaImagePresetImage(AreaImagePreset p) => switch (p) {
      AreaImagePreset.standard || AreaImagePreset.exitus1 => DecorationImage(
          image: AssetImage(_areaImagePresetAssets[p]!),
          fit: BoxFit.cover,
        ),
      _ => DecorationImage(
          image: AssetImage(_areaImagePresetAssets[p]!),
          repeat: ImageRepeat.repeat,
        ),
    };

// AreaFill is the resolved paint for one "layer" (a background, or a border
// frame). At most one of color/gradient/image is set, except for a built-in
// image preset, which paints over the area's normal token color rather than
// replacing it -- the tiled patterns are semi-transparent by design.
class AreaFill {
  final Color? color;
  final Gradient? gradient;
  final DecorationImage? image;
  const AreaFill({this.color, this.gradient, this.image});
}
