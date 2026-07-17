import 'package:flutter/material.dart';

// ColorPalette is a small, named, standalone set of colors -- distinct from
// a full ThemePreset (which also carries area styles, menu customization,
// etc). Applying one overwrites the active preset's 7 "vivid" palette
// roles (see kVividPaletteSlots in theme_preset.dart: primary, secondary,
// tertiary, sidebarBackground, speechBackground, navAccent, sidebarAccent)
// with this palette's `colors`, in that order. fourth/onSurface/navText/
// sidebarText/outline/error/success are deliberately left alone -- those
// are functional/neutral roles that need to stay appropriate for the
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

// Each entry's 7 colors are ordered [primary, secondary, tertiary,
// sidebarBackground, speechBackground, navAccent, sidebarAccent], applied
// *exactly as stored* (see theme_editor.dart's _applyPalette) -- no
// brightness-aware re-derivation, no hue rotation.
// Each entry is a self-contained, already-tuned look: pick the colors as
// they should actually render, not as a "hue hint" for a formula to
// reinterpret. Two entries can legitimately reuse the same swatch across
// multiple slots (e.g. a deliberately flat, uniform dark theme) -- that's
// the author's choice, not something to compensate for algorithmically.
//
// Curated to exactly 10, each modeled on a real, recognizable app's actual
// brand palette (rather than an arbitrary named hue) so every entry reads
// as a deliberate, professional design instead of a generic color-wheel
// pick -- users can save/build their own beyond these via the theme
// editor's "Save current palette".
const List<ColorPalette> builtinPalettes = [
  // Exact values tuned live in the theme editor and exported (see
  // Dark_Palette_T2.json in the conversation this was pulled from), not run
  // through any re-derivation. Kept first in this list (right after the
  // synthetic "Default Theme" card prepended in theme_editor.dart) since
  // it's the primary dark option.
  ColorPalette(id: "builtin-dark-theme", name: "Dark Theme", builtin: true, colors: [
    Color(0xFF000000), // primary
    Color(0xFF000000), // secondary (nav bg)
    Color(0xFF262A32), // tertiary
    Color(0xFF0B0C0C), // sidebar bg
    Color(0xFF2F303B), // speech bg
    Color(0xFF1D9BF0), // navAccent
    Color(0xFFFFFFFF), // sidebarAccent
  ]),
  // X (Twitter)'s "Lights out" dark theme -- exact values tuned live in the
  // theme editor and exported (see preset.json in the conversation this was
  // pulled from), not run through any re-derivation. Primary/secondary/
  // sidebar background are deliberately identical, matching X's genuinely
  // flat black chrome; X blue and white carry the accents.
  ColorPalette(id: "builtin-x-dark", name: "X (Twitter) Dark", builtin: true, colors: [
    Color(0xFF121417), // primary
    Color(0xFF121417), // secondary (nav bg) -- same as primary, deliberately flat
    Color(0xFF262A32), // tertiary
    Color(0xFF121417), // sidebar bg -- same as primary, deliberately flat
    Color(0xFF2F303B), // speech bg
    Color(0xFF1D9BF0), // navAccent: X blue
    Color(0xFFFFFFFF), // sidebarAccent: white (X's icon/text color)
  ]),
  // VS Code's default Dark+ theme: near-neutral blue-grey panels (editor/
  // sidebar/activity bar/status bar are each a subtly different grey) with
  // its signature status-bar blue as the accent.
  ColorPalette(id: "builtin-vscode-dark", name: "VS Code", builtin: true, colors: [
    Color(0xFF1E1F22), // primary hue: editor background, faint blue-grey
    Color(0xFF2A2D31), // secondary (nav bg) hue: activity bar
    Color(0xFF33363B), // tertiary hue
    Color(0xFF232529), // sidebar bg hue: explorer panel
    Color(0xFF2C2F33), // speech bg hue
    Color(0xFF007ACC), // navAccent: VS Code status-bar blue
    Color(0xFF3794FF), // sidebarAccent: VS Code active-item blue
  ]),
  // Facebook: a genuine tonal ramp of brand blue -- Secondary deliberately
  // darker/deeper than the rest so the nav rail reads as clearly recessed,
  // Speech deliberately lighter so the chat area reads as clearly raised.
  ColorPalette(id: "builtin-facebook", name: "Facebook", builtin: true, colors: [
    Color(0xFF1E5FBF), // primary hue
    Color(0xFF0B2D5C), // secondary (nav bg) hue: deep FB blue
    Color(0xFF5B9BF2), // tertiary hue: light FB blue
    Color(0xFF1650A3), // sidebar bg hue
    Color(0xFF7FB3FF), // speech bg hue: brightest FB blue
    Color(0xFF1877F2), // navAccent: Facebook blue
    Color(0xFF42A5F5), // sidebarAccent: light Facebook blue
  ]),
  // Snapchat: near-black panels (a tight cluster, like its real all-black
  // chrome) with just a faint gold-yellow undertone, so the unmistakable
  // pure yellow accent is what actually carries the brand.
  ColorPalette(id: "builtin-snapchat", name: "Snapchat", builtin: true, colors: [
    Color(0xFF24200A), // primary hue
    Color(0xFF2F2B0E), // secondary (nav bg) hue
    Color(0xFF433D14), // tertiary hue
    Color(0xFF393411), // sidebar bg hue
    Color(0xFF3D3712), // speech bg hue
    Color(0xFFFFFC00), // navAccent: Snapchat yellow
    Color(0xFFFFD500), // sidebarAccent: deeper gold-yellow
  ]),
  // Instagram: a magenta/pink tonal ramp (the gradient's darkest stop) with
  // its orange accent providing the complementary pop from the other end
  // of the real gradient.
  ColorPalette(id: "builtin-instagram", name: "Instagram", builtin: true, colors: [
    Color(0xFFA6306B), // primary hue
    Color(0xFF571938), // secondary (nav bg) hue
    Color(0xFFD3699E), // tertiary hue
    Color(0xFF962C61), // sidebar bg hue
    Color(0xFFDD88B2), // speech bg hue
    Color(0xFFE1306C), // navAccent: Instagram pink
    Color(0xFFF77737), // sidebarAccent: Instagram orange
  ]),
  // WhatsApp: a green tonal ramp with its real two-tone brand accent --
  // bright action green paired with the darker teal-green used in its own
  // header/nav chrome.
  ColorPalette(id: "builtin-whatsapp", name: "WhatsApp", builtin: true, colors: [
    Color(0xFF3B9B6E), // primary hue
    Color(0xFF1F513A), // secondary (nav bg) hue
    Color(0xFF72CAA1), // tertiary hue
    Color(0xFF358D64), // sidebar bg hue
    Color(0xFF90D5B5), // speech bg hue
    Color(0xFF25D366), // navAccent: WhatsApp green
    Color(0xFF128C7E), // sidebarAccent: WhatsApp teal
  ]),
  // Reddit: a burnt-orange tonal ramp with the real upvote-orange and
  // comment-blue accent pairing from Reddit's own UI.
  ColorPalette(id: "builtin-reddit", name: "Reddit", builtin: true, colors: [
    Color(0xFF9B583B), // primary hue
    Color(0xFF512E1F), // secondary (nav bg) hue
    Color(0xFFCA8D72), // tertiary hue
    Color(0xFF8D4F35), // sidebar bg hue
    Color(0xFFD5A590), // speech bg hue
    Color(0xFFFF4500), // navAccent: Reddit orangered
    Color(0xFF0079D3), // sidebarAccent: Reddit blue
  ]),
  // Matrix/Element: a teal-green tonal ramp with Element's link blue as the
  // secondary accent.
  ColorPalette(id: "builtin-matrix", name: "Matrix", builtin: true, colors: [
    Color(0xFF3B9B83), // primary hue
    Color(0xFF1F5145), // secondary (nav bg) hue
    Color(0xFF72CAB4), // tertiary hue
    Color(0xFF358D77), // sidebar bg hue
    Color(0xFF90D5C4), // speech bg hue
    Color(0xFF0DBD8B), // navAccent: Matrix/Element green
    Color(0xFF368BD6), // sidebarAccent: Element blue
  ]),
  // Gmail: a red tonal ramp with Google's own red/blue duo -- red for the
  // compose/primary action, blue for links and selected states.
  ColorPalette(id: "builtin-gmail", name: "Gmail", builtin: true, colors: [
    Color(0xFF9B433B), // primary hue
    Color(0xFF51231F), // secondary (nav bg) hue
    Color(0xFFCA7A72), // tertiary hue
    Color(0xFF8D3D35), // sidebar bg hue
    Color(0xFFD59690), // speech bg hue
    Color(0xFFEA4335), // navAccent: Google red
    Color(0xFF4285F4), // sidebarAccent: Google blue
  ]),
  // YouTube: near-black panels (a tight cluster, like its real dark-mode
  // chrome) with just a faint red undertone, pure brand red for the accent.
  ColorPalette(id: "builtin-youtube", name: "YouTube", builtin: true, colors: [
    Color(0xFF220B0C), // primary hue
    Color(0xFF2E0F10), // secondary (nav bg) hue
    Color(0xFF411617), // tertiary hue
    Color(0xFF371214), // sidebar bg hue
    Color(0xFF3B1415), // speech bg hue
    Color(0xFFFF0000), // navAccent: YouTube red
    Color(0xFFFF4444), // sidebarAccent: lighter YouTube red
  ]),
];
