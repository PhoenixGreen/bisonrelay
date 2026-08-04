import 'dart:math' as math;

import 'package:flutter/material.dart';

// color_contrast.dart is the theming system's WCAG contrast maths: the one
// place relative luminance and contrast ratio are computed, shared by the
// palette seeds, the palette editor and test/palette_contrast_test.dart
// (which asserts a legible ratio for every text/background pair every
// shipped palette produces).

double _linear(double channel) => channel <= 0.04045
    ? channel / 12.92
    : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

// relativeLuminance is WCAG 2.x relative luminance, 0 (black) to 1 (white).
double relativeLuminance(Color c) =>
    0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b);

// contrastRatio is the WCAG contrast ratio between two colors, 1:1
// (identical) to 21:1 (black on white). Text needs 4.5, a UI element 3.
double contrastRatio(Color a, Color b) {
  var la = relativeLuminance(a), lb = relativeLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

// restingBorderFrom derives an input's unfocused border from its focused one
// by fading it *toward the background it sits on*, which is what "more
// muted" actually means -- darkening only reads as muting on a dark theme.
//
// The target is 40% of the focused border's own contrast, rather than a
// fixed blend, so the pair keeps the same relationship whatever colors a
// theme uses.
Color restingBorderFrom(Color selected, Color background) {
  var target = contrastRatio(selected, background) * 0.4;
  for (var i = 0; i <= 100; i++) {
    var c = Color.lerp(background, selected, i / 100)!;
    if (contrastRatio(c, background) >= target) return c;
  }
  return selected;
}
