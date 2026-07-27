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

// AreaFill is the resolved paint for one "layer" (a background, or a border
// frame) -- at most one of color/gradient/image is set.
class AreaFill {
  final Color? color;
  final Gradient? gradient;
  final DecorationImage? image;
  const AreaFill({this.color, this.gradient, this.image});
}
