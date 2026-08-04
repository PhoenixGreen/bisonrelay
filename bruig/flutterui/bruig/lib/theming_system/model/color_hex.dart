import 'package:flutter/material.dart';

// colorToHex/colorFromHex are the theming system's single #AARRGGBB codec,
// used by every model that persists a color (AreaStyle, ThemePreset,
// ColorPalette). Each of those used to carry its own private, byte-identical
// copy of this pair.
String colorToHex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0')}';

Color colorFromHex(String s) =>
    Color(int.parse(s.replaceFirst('#', ''), radix: 16));
