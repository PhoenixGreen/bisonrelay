import 'package:flutter/material.dart';

// ColorPalette is a small, named, standalone set of colors -- distinct from
// a full ThemePreset (which also carries area styles, menu customization,
// etc). Applying one overwrites the active preset's 5 "vivid" palette
// roles (see kVividPaletteSlots in theme_preset.dart: primary, secondary,
// tertiary, success, accent) with this palette's `colors`, in that order.
// error/surface/onSurface/onAccent/outline are deliberately left alone --
// those are functional/neutral roles that need to stay appropriate for the
// active preset's own light/dark brightness, not baked into a portable
// palette.
class ColorPalette {
  final String id;
  final String name;
  final List<Color> colors;
  // builtin palettes ship with the app and aren't user-deletable; they're
  // also never persisted to disk (see PaletteLibraryStorage).
  final bool builtin;
  const ColorPalette({
    required this.id,
    required this.name,
    required this.colors,
    this.builtin = false,
  });

  static String hexOf(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0')}';
  static Color colorFromHex(String s) =>
      Color(int.parse(s.replaceFirst('#', ''), radix: 16));

  Map<String, dynamic> toJson() =>
      {"id": id, "name": name, "colors": colors.map(hexOf).toList()};

  factory ColorPalette.fromJson(Map<String, dynamic> j) => ColorPalette(
        id: j["id"] as String,
        name: j["name"] as String,
        colors: (j["colors"] as List)
            .map((h) => colorFromHex(h as String))
            .toList(),
      );
}

// Each entry's 5 colors are ordered [primary, secondary, tertiary, success,
// accent] -- primary is used as ColorScheme.fromSeed's seed color when
// applied, so it's chosen as the palette's most saturated, mid-lightness
// hue (the one that seeds an attractive Material tonal palette), not just
// whichever color came first left-to-right in the reference swatches.
const List<ColorPalette> builtinPalettes = [
  ColorPalette(id: "builtin-meadow-green", name: "Meadow Green", builtin: true, colors: [
    Color(0xFF4A8FA8), // primary: mid blue-teal
    Color(0xFF5FAE8C), // secondary: teal-green
    Color(0xFF8FCB7E), // tertiary: green
    Color(0xFF2C5F82), // success: dark blue
    Color(0xFFD4E88A), // accent: pale yellow-green
  ]),
  ColorPalette(id: "builtin-fiery-palette", name: "Fiery Palette", builtin: true, colors: [
    Color(0xFFC86A28), // primary: burnt orange
    Color(0xFF8C1F28), // secondary: dark red
    Color(0xFFE8912D), // tertiary: orange
    Color(0xFF1F4E5F), // success: dark teal
    Color(0xFF4A1942), // accent: deep plum
  ]),
  ColorPalette(id: "builtin-ocean-sunset", name: "Ocean Sunset", builtin: true, colors: [
    Color(0xFF1F4E5C), // primary: teal
    Color(0xFFD4A055), // secondary: gold
    Color(0xFFA8482E), // tertiary: rust
    Color(0xFF8C2A2A), // success: dark red
    Color(0xFF0D1B2A), // accent: dark navy
  ]),
  ColorPalette(id: "builtin-summer-dream", name: "Summer Dream", builtin: true, colors: [
    Color(0xFF3E7C97), // primary: steel blue
    Color(0xFF4FA8AD), // secondary: teal
    Color(0xFFE07856), // tertiary: coral
    Color(0xFFF4C9A0), // success: peach
    Color(0xFFFBF3C9), // accent: cream
  ]),
  ColorPalette(id: "builtin-cool-waters", name: "Cool Waters", builtin: true, colors: [
    Color(0xFF3E8E90), // primary: teal
    Color(0xFF1F4E5C), // secondary: dark teal
    Color(0xFF6FC29A), // tertiary: green
    Color(0xFF97DDA0), // success: light green
    Color(0xFFCDF3CB), // accent: pale green
  ]),
  ColorPalette(id: "builtin-soft-sand", name: "Soft Sand", builtin: true, colors: [
    Color(0xFFB79E88), // primary: tan
    Color(0xFF8C7B68), // secondary: dark tan
    Color(0xFFD9CFC1), // tertiary: beige
    Color(0xFFC9C4BE), // success: gray
    Color(0xFFEDE6DD), // accent: cream
  ]),
  ColorPalette(id: "builtin-midnight-sky", name: "Midnight Sky", builtin: true, colors: [
    Color(0xFF1E5AA8), // primary: blue
    Color(0xFF123A75), // secondary: navy
    Color(0xFFF0B429), // tertiary: gold
    Color(0xFF0B1D42), // success: dark navy
    Color(0xFFF5D949), // accent: yellow
  ]),
  ColorPalette(id: "builtin-watermelon-sorbet", name: "Watermelon Sorbet", builtin: true, colors: [
    Color(0xFFE1587A), // primary: pink
    Color(0xFF4A8FA3), // secondary: blue
    Color(0xFF6FD9A8), // tertiary: mint
    Color(0xFF1B3B4B), // success: dark teal
    Color(0xFFF5CE85), // accent: peach
  ]),
  ColorPalette(id: "builtin-vibrant-color-fiesta", name: "Vibrant Color Fiesta", builtin: true, colors: [
    Color(0xFF4C7CF0), // primary: blue
    Color(0xFF8A3FE0), // secondary: purple
    Color(0xFFE0247E), // tertiary: pink
    Color(0xFFE8631E), // success: orange
    Color(0xFFF0A830), // accent: gold
  ]),
  ColorPalette(id: "builtin-dusty-rose", name: "Dusty Rose", builtin: true, colors: [
    Color(0xFFB5A3AC), // primary: mauve
    Color(0xFF7A6670), // secondary: dark mauve
    Color(0xFFC7CEE3), // tertiary: pale blue
    Color(0xFFE0D3D9), // success: pale pink
    Color(0xFFE8E3F0), // accent: lavender-white
  ]),
  ColorPalette(id: "builtin-autumn-sage", name: "Autumn Sage", builtin: true, colors: [
    Color(0xFFC87456), // primary: terracotta
    Color(0xFF8FB89A), // secondary: sage
    Color(0xFFE0C283), // tertiary: tan
    Color(0xFF2E2E4E), // success: dark navy
    Color(0xFFF0EEDD), // accent: cream
  ]),
  ColorPalette(id: "builtin-slate-night", name: "Slate Night", builtin: true, colors: [
    Color(0xFF3D5372), // primary: slate blue
    Color(0xFF16213A), // secondary: navy
    Color(0xFF7891A8), // tertiary: gray-blue
    Color(0xFF0A0E1A), // success: near-black
    Color(0xFFDCDEE0), // accent: light gray
  ]),
];
