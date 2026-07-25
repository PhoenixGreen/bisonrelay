import 'package:flutter/material.dart';

// ColorPalette is a small, named, standalone set of colors -- distinct from
// a full ThemePreset (which also carries area styles, menu customization,
// etc). Applying one (see theme_editor.dart's _applyPalette) overwrites the
// active preset's 12 "vivid" palette roles (see kVividPaletteSlots in
// theme_preset.dart: primary, secondary, tertiary, sidebarBackground,
// speechBackground, speechBackgroundSent, navAccent, sidebarAccent,
// accentContainer, error, outline, buttonBorder) with this palette's
// `colors`, in that order. It also resets every other functional/neutral
// role (fourth/onSurface/onSurfaceVariant/navText/sidebarText/success) and
// the overall brightness to this palette's own `brightness` seed, so the
// result is always a fully internally-consistent look regardless of
// whatever preset was active beforehand.
class ColorPalette {
  final String id;
  final String name;
  final List<Color> colors;
  // builtin palettes ship with the app and aren't user-deletable; they're
  // also never persisted to disk (see PaletteLibraryStorage).
  final bool builtin;
  // The brightness this palette's 12 colors were designed against --
  // applying it (see theme_editor.dart's _applyPalette) also resets the
  // preset's neutral/functional roles (text, success, etc.) to this
  // brightness's own seed values, not just the 12 vivid slots. Without
  // this,
  // applying a near-black palette while the light base theme was active left
  // dark text colors untouched underneath it (or vice versa), so the same
  // palette rendered completely differently -- sometimes unreadably --
  // depending on which base theme happened to be active beforehand.
  // Defaults to dark since every built-in palette except "Light" targets a
  // dark chrome.
  final Brightness brightness;
  const ColorPalette({
    required this.id,
    required this.name,
    required this.colors,
    this.builtin = false,
    this.brightness = Brightness.dark,
  });

  static String hexOf(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0')}';
  static Color colorFromHex(String s) =>
      Color(int.parse(s.replaceFirst('#', ''), radix: 16));

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "colors": colors.map(hexOf).toList(),
        "brightness": brightness == Brightness.light ? "light" : "dark",
      };

  factory ColorPalette.fromJson(Map<String, dynamic> j) => ColorPalette(
        id: j["id"] as String,
        name: j["name"] as String,
        colors: (j["colors"] as List)
            .map((h) => colorFromHex(h as String))
            .toList(),
        // Absent for palettes saved/exported before this field existed --
        // they were only ever produced from a dark-base draft, so dark is
        // the correct fallback.
        brightness:
            j["brightness"] == "light" ? Brightness.light : Brightness.dark,
      );
}

// Each entry's 12 colors are ordered [primary, secondary, tertiary,
// sidebarBackground, speechBackground, speechBackgroundSent, navAccent,
// sidebarAccent, accentContainer, error, outline, buttonBorder], applied
// *exactly as stored* (see theme_editor.dart's _applyPalette) -- no
// brightness-aware re-derivation, no hue rotation.
// speechBackground is the "received" chat bubble; speechBackgroundSent is
// the "sent"/own bubble -- kept as its own deliberately-chosen color (e.g.
// WhatsApp's real outgoing-message teal) rather than reusing speechBackground
// or falling back to the seed's generic value, so sent/received bubbles
// read as visibly distinct per palette, matching each app's real chat UI.
// accentContainer ("Accent (Buttons/Toggles)", drives Switch/tonal-button
// backgrounds, and -- since CancelButton no longer misuses `error` for its
// background, see theme_preset.dart's doc -- the "Cancel" button too) is a
// muted, readable-with-light-text tone pulled from each palette's own
// accent hue rather than the Default/Light seed's pale lavender, which
// clashed badly as a "Buttons/Toggles" color on e.g. a WhatsApp-green or
// Reddit-orange palette. error is kept a conventional, consistent "danger"
// red across every palette (not brand-tinted -- a semantic color should
// stay predictable): a bright coral-red (#FF6B6B) rather than a dark one,
// since `error` is read directly as foreground text/icon color on this
// app's own near-black backgrounds (error messages, the hang-up-call
// button's icon) -- a dark red reads at a poor ~2.5:1 contrast there, even
// though it looks fine as a *container background* with light text on
// top. errorContainer is no longer forced to equal `error` (see
// theme_preset.dart's toAppTheme), so this single field only has to be
// legible as foreground text/icons now, not also serve as a background.
// outline (plain dividers/panel borders) is tuned to sit roughly halfway
// between each palette's own primary and tertiary tones, so it reads as a
// deliberate, barely-there blend specific to that palette's background
// family rather than one generic grey that happens to clash with some
// (e.g. WhatsApp's teal-black vs Snapchat's amber-black). buttonBorder
// (outlined-button/focused-input borders, which need to actually stand
// out) reuses each palette's own navAccent -- high-contrast against the
// near-black background and ties the button chrome back to the palette's
// brand color, the same relationship the Default/Light seed uses.
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
    Color(0xFF2F303B), // speech bg (received)
    Color(0xFF17324A), // speech bg sent: blue-tinted, echoes navAccent
    Color(0xFF1D9BF0), // navAccent
    Color(0xFFFFFFFF), // sidebarAccent
    Color(0xFF1B4A66), // accentContainer: muted blue container, echoes navAccent
    Color(0xFFFF6B6B), // error
    Color(0xFF1A1C20), // outline: subtle, between primary and tertiary
    Color(0xFF1D9BF0), // buttonBorder: echoes navAccent
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
    Color(0xFF2F303B), // speech bg (received)
    Color(0xFF15202B), // speech bg sent: X's real navy DM bubble
    Color(0xFF1D9BF0), // navAccent: X blue
    Color(0xFFFFFFFF), // sidebarAccent: white (X's icon/text color)
    Color(0xFF16405C), // accentContainer: muted blue container, echoes navAccent
    Color(0xFFFF6B6B), // error
    Color(0xFF1D2024), // outline: subtle, between primary and tertiary
    Color(0xFF1D9BF0), // buttonBorder: echoes navAccent
  ]),
  // VS Code's default Dark+ theme: near-neutral blue-grey panels (editor/
  // sidebar/activity bar/status bar are each a subtly different grey) with
  // its signature status-bar blue as the accent.
  ColorPalette(id: "builtin-vscode-dark", name: "VS Code", builtin: true, colors: [
    Color(0xFF1E1F22), // primary hue: editor background, faint blue-grey
    Color(0xFF2A2D31), // secondary (nav bg) hue: activity bar
    Color(0xFF33363B), // tertiary hue
    Color(0xFF232529), // sidebar bg hue: explorer panel
    Color(0xFF2C2F33), // speech bg hue (received)
    Color(0xFF264F78), // speech bg sent: VS Code's real selection-highlight blue
    Color(0xFF007ACC), // navAccent: VS Code status-bar blue
    Color(0xFF3794FF), // sidebarAccent: VS Code active-item blue
    Color(0xFF1F4E73), // accentContainer: muted blue container, echoes navAccent
    Color(0xFFFF6B6B), // error
    Color(0xFF282A2E), // outline: subtle, between primary and tertiary
    Color(0xFF007ACC), // buttonBorder: echoes navAccent
  ]),
  // Facebook: matches its real dark-mode chrome -- near-black neutral
  // panels (background/nav rail/sidebar all a tight blue-grey cluster, the
  // way Facebook's own #18191A/#242526 chrome reads) with the brand blue
  // reserved for accents, not painted across the whole background.
  ColorPalette(id: "builtin-facebook", name: "Facebook", builtin: true, colors: [
    Color(0xFF18191B), // primary: FB's real dark-mode background
    Color(0xFF0E0F10), // secondary (nav bg): recessed rail
    Color(0xFF2A2C30), // tertiary: elevated panel/card
    Color(0xFF141518), // sidebar bg
    Color(0xFF242526), // speech bg (received): FB's real raised-panel color
    Color(0xFF1B5FCC), // speech bg sent: Messenger's real outgoing blue bubble
    Color(0xFF1877F2), // navAccent: Facebook blue
    Color(0xFF4599FF), // sidebarAccent: FB's dark-mode link blue
    Color(0xFF1B4A8A), // accentContainer: muted blue container, echoes navAccent
    Color(0xFFFF6B6B), // error
    Color(0xFF212226), // outline: subtle, between primary and tertiary
    Color(0xFF1877F2), // buttonBorder: echoes navAccent
  ]),
  // Snapchat: near-black panels with a faint warm amber-black undertone
  // (echoing its yellow brand even in the neutral chrome) so the
  // unmistakable pure yellow accent is what actually carries the brand.
  ColorPalette(id: "builtin-snapchat", name: "Snapchat", builtin: true, colors: [
    Color(0xFF15130E), // primary
    Color(0xFF0C0B08), // secondary (nav bg)
    Color(0xFF2B2619), // tertiary
    Color(0xFF1A170F), // sidebar bg
    Color(0xFF231F14), // speech bg (received)
    Color(0xFF3D3212), // speech bg sent: deeper amber-gold, echoes navAccent
    Color(0xFFFFFC00), // navAccent: Snapchat yellow
    Color(0xFFFFD500), // sidebarAccent: deeper gold-yellow
    Color(0xFF5C4C0E), // accentContainer: muted gold-olive container
    Color(0xFFFF6B6B), // error
    Color(0xFF201C13), // outline: subtle, between primary and tertiary
    Color(0xFFFFFC00), // buttonBorder: echoes navAccent
  ]),
  // Instagram: near-black panels with a faint cool plum-black undertone
  // (echoing the magenta end of its gradient even in the neutral chrome --
  // and keeping it visually distinct from Snapchat's warm-black neutral
  // cluster) with the brand pink/orange duo from its gradient carrying the
  // accents.
  ColorPalette(id: "builtin-instagram", name: "Instagram", builtin: true, colors: [
    Color(0xFF161114), // primary
    Color(0xFF0D0A0C), // secondary (nav bg)
    Color(0xFF2B2227), // tertiary
    Color(0xFF1B161A), // sidebar bg
    Color(0xFF231C21), // speech bg (received)
    Color(0xFF3A1830), // speech bg sent: deep magenta-plum, echoes navAccent
    Color(0xFFC13584), // navAccent: Instagram pink
    Color(0xFFF77737), // sidebarAccent: Instagram orange
    Color(0xFF7A2E5C), // accentContainer: muted magenta container
    Color(0xFFFF6B6B), // error
    Color(0xFF1F191C), // outline: subtle, between primary and tertiary
    Color(0xFFC13584), // buttonBorder: echoes navAccent
  ]),
  // WhatsApp: matches its real dark-mode chrome -- deep teal-black panels
  // (background/sidebar/panel all pulled from WhatsApp's actual
  // #0B141A/#111B21/#202C33 chrome) with the brand green/teal duo as
  // accents.
  ColorPalette(id: "builtin-whatsapp", name: "WhatsApp", builtin: true, colors: [
    Color(0xFF0B141A), // primary: WhatsApp's real dark-mode background
    Color(0xFF080F13), // secondary (nav bg)
    Color(0xFF202C33), // tertiary: WhatsApp's real panel/hover color
    Color(0xFF111B21), // sidebar bg: WhatsApp's real chat-list bg
    Color(0xFF202C33), // speech bg (received): WhatsApp's real bubble color
    Color(0xFF005C4B), // speech bg sent: WhatsApp's real outgoing-bubble teal
    Color(0xFF25D366), // navAccent: WhatsApp green
    Color(0xFF00A884), // sidebarAccent: WhatsApp teal
    Color(0xFF1D5C4A), // accentContainer: muted teal-green container
    Color(0xFFFF6B6B), // error
    Color(0xFF162026), // outline: subtle, between primary and tertiary
    Color(0xFF25D366), // buttonBorder: echoes navAccent
  ]),
  // Reddit: matches its real dark-mode chrome -- near-black neutral panels
  // (Reddit's own #030303/#1A1A1B/#272729 chrome) with the real
  // upvote-orange and comment-blue accent pairing.
  ColorPalette(id: "builtin-reddit", name: "Reddit", builtin: true, colors: [
    Color(0xFF1A1A1B), // primary: Reddit's real dark-mode background
    Color(0xFF0B0B0C), // secondary (nav bg)
    Color(0xFF272729), // tertiary: Reddit's real panel color
    Color(0xFF161617), // sidebar bg
    Color(0xFF1E1E20), // speech bg (received)
    Color(0xFF3D2013), // speech bg sent: deep upvote-orange tint
    Color(0xFFFF4500), // navAccent: Reddit orangered
    Color(0xFF0079D3), // sidebarAccent: Reddit blue
    Color(0xFF1B4A73), // accentContainer: muted blue container (Reddit's comment blue)
    Color(0xFFFF6B6B), // error
    Color(0xFF212122), // outline: subtle, between primary and tertiary
    Color(0xFFFF4500), // buttonBorder: echoes navAccent
  ]),
  // Matrix/Element: matches its real dark-mode chrome -- neutral blue-grey
  // panels (Element's own #15191E/#21262C chrome) with its green/blue
  // accent pairing.
  ColorPalette(id: "builtin-matrix", name: "Matrix", builtin: true, colors: [
    Color(0xFF15191E), // primary: Element's real dark-mode background
    Color(0xFF0E1114), // secondary (nav bg)
    Color(0xFF21262C), // tertiary: Element's real panel color
    Color(0xFF181C20), // sidebar bg
    Color(0xFF23282E), // speech bg (received)
    Color(0xFF13342C), // speech bg sent: Element's real own-message green tint
    Color(0xFF0DBD8B), // navAccent: Matrix/Element green
    Color(0xFF368BD6), // sidebarAccent: Element blue
    Color(0xFF155C48), // accentContainer: muted green container, echoes navAccent
    Color(0xFFFF6B6B), // error
    Color(0xFF1B1F24), // outline: subtle, between primary and tertiary
    Color(0xFF0DBD8B), // buttonBorder: echoes navAccent
  ]),
  // Gmail: matches its real dark-mode chrome -- neutral grey panels
  // (Google's own #202124/#292A2D chrome) with Google's red/blue duo as
  // accents -- a lighter, dark-mode-friendly blue rather than the fully
  // saturated light-mode one, since it needs to hold contrast on dark
  // panels.
  ColorPalette(id: "builtin-gmail", name: "Gmail", builtin: true, colors: [
    Color(0xFF202124), // primary: Gmail's real dark-mode background
    Color(0xFF131417), // secondary (nav bg)
    Color(0xFF2C2D30), // tertiary: Gmail's real panel color
    Color(0xFF191A1D), // sidebar bg
    Color(0xFF292A2D), // speech bg (received)
    Color(0xFF16324F), // speech bg sent: Google-blue tint, echoes sidebarAccent
    Color(0xFFEA4335), // navAccent: Google red
    Color(0xFF8AB4F8), // sidebarAccent: Google's dark-mode blue
    Color(0xFF15416B), // accentContainer: muted blue container, echoes sidebarAccent
    Color(0xFFFF6B6B), // error
    Color(0xFF262729), // outline: subtle, between primary and tertiary
    Color(0xFFEA4335), // buttonBorder: echoes navAccent
  ]),
  // YouTube: matches its real dark-mode chrome -- near-black neutral panels
  // (YouTube's own #0F0F0F/#212121 chrome) with pure brand red for the
  // accent.
  ColorPalette(id: "builtin-youtube", name: "YouTube", builtin: true, colors: [
    Color(0xFF0F0F0F), // primary: YouTube's real dark-mode background
    Color(0xFF0A0A0A), // secondary (nav bg)
    Color(0xFF272727), // tertiary: YouTube's real panel color
    Color(0xFF181818), // sidebar bg
    Color(0xFF212121), // speech bg (received)
    Color(0xFF3D1013), // speech bg sent: deep brand-red tint
    Color(0xFFFF0000), // navAccent: YouTube red
    Color(0xFFFF4444), // sidebarAccent: lighter YouTube red
    Color(0xFF7A1F1F), // accentContainer: muted red container, echoes navAccent
    Color(0xFFFF6B6B), // error
    Color(0xFF1B1B1B), // outline: subtle, between primary and tertiary
    Color(0xFFFF0000), // buttonBorder: echoes navAccent
  ]),
];
