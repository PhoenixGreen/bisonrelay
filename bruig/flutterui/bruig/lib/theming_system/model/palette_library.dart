import 'package:bruig/theming_system/model/color_hex.dart';
import 'package:flutter/material.dart';

// ColorPalette is a small, named, standalone set of colors -- distinct from
// a full ThemePreset (which also carries area styles, menu customization,
// etc). Applying one (see color_palette_section.dart's applyColorPalette)
// overwrites the active preset's 12 "vivid" palette roles (see
// kVividPaletteSlots in color_palette.dart: primary, secondary, tertiary,
// sidebarBackground,
// speechBackground, speechBackgroundSent, navAccent, sidebarAccent,
// accentContainer, error, outline, fourth) with this palette's `colors`,
// in that order. It also resets every other functional/neutral
// role (onSurface/onSurfaceVariant/navText/sidebarText/success) and
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
  // applying it (see color_palette_section.dart's applyColorPalette) also resets the
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

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "colors": colors.map(colorToHex).toList(),
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
// sidebarAccent, accentContainer, error, outline, fourth], applied
// *exactly as stored* (see color_palette_section.dart's applyColorPalette) -- no
// brightness-aware re-derivation, no hue rotation.
// speechBackground is the "received" chat bubble; speechBackgroundSent is
// the "sent"/own bubble -- kept as its own deliberately-chosen color (e.g.
// WhatsApp's real outgoing-message teal) rather than reusing speechBackground
// or falling back to the seed's generic value, so sent/received bubbles
// read as visibly distinct per palette, matching each app's real chat UI.
// accentContainer ("Accent (Buttons/Toggles)", drives Switch/tonal-button
// backgrounds, and -- since CancelButton no longer misuses `error` for its
// background, see preset.dart's doc -- the "Cancel" button too) is a
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
// preset.dart's toAppTheme), so this single field only has to be
// legible as foreground text/icons now, not also serve as a background.
// outline (plain dividers/panel borders) is tuned to sit roughly halfway
// between each palette's own primary and tertiary tones, so it reads as a
// deliberate, barely-there blend specific to that palette's background
// family rather than one generic grey that happens to clash with some
// (e.g. WhatsApp's teal-black vs Snapchat's amber-black). Outlined-button/
// focused-input borders (formerly a separate `buttonBorder` slot) now read
// navAccent directly -- high-contrast against the near-black background
// and ties the button chrome back to the palette's brand color, the same
// relationship the Default/Light seed uses; every entry below already set
// buttonBorder to an exact duplicate of its own navAccent, so removing it
// as a distinct slot changes nothing about how any of these render.
// fourth (the reply-preview box and success/error toast background --
// "Notifications Background") is included as a 12th, tail-appended slot
// so each palette can tune its own notification-surface tone instead of
// every palette showing the same flat purple-blue notification box
// regardless of its own hue family. Deliberately picked as a clear,
// noticeably-lighter step up from that palette's own primary/tertiary
// tones (a first attempt picked something roughly midway between the two
// and it read as barely distinguishable from Primary -- a toast needs to
// look raised, not like one more subtle background tier), tinted toward
// each palette's own brand hue rather than a neutral grey.
// Each entry is a self-contained, already-tuned look: pick the colors as
// they should actually render, not as a "hue hint" for a formula to
// reinterpret. Two entries can legitimately reuse the same swatch across
// multiple slots (e.g. a deliberately flat, uniform dark theme) -- that's
// the author's choice, not something to compensate for algorithmically.
//
// Curated, and deliberately short. Each entry is modeled on something real
// -- an app's actual dark mode, or a club's two colors -- rather than an
// arbitrary named hue, so every one reads as a design instead of a
// color-wheel pick. Users can save and build their own beyond these via
// the theme editor's "Save current palette".
//
// This was eleven, one per recognizable brand. Eight of them (X, VS Code,
// Facebook, Snapchat, Instagram, WhatsApp, Reddit, YouTube) were dropped:
// as a set they were near-black chrome plus one brand accent over and
// over, so most of the list looked the same in use and picking between
// them wasn't a real choice. What's left is five that differ from each
// other -- flat black, navy and gold, neutral grey, green, and warm grey.
//
// Removing a palette is safe: applying one copies its colors into the
// preset, so nothing stores a palette id. A user who had applied one keeps
// exactly the theme they had; they just can't pick it from the strip again.
const List<ColorPalette> builtinPalettes = [
  // Exact values tuned live in the theme editor and exported (see
  // Dark_Palette_T2.json in the conversation this was pulled from), not run
  // through any re-derivation. Kept first in this list (right after the
  // synthetic "Default Theme" card prepended in theme_editor.dart) since
  // it's the primary dark option.
  ColorPalette(id: "builtin-dark-theme", name: "Dark", builtin: true, colors: [
    Color(0xFF000000), // primary
    Color(0xFF000000), // secondary (nav bg)
    Color(0xFF262A32), // tertiary
    Color(0xFF0B0C0C), // sidebar bg
    Color(0xFF2F303B), // speech bg (received)
    Color(0xFF17324A), // speech bg sent: blue-tinted, echoes navAccent
    Color(0xFF1D9BF0), // navAccent
    Color(0xFFFFFFFF), // sidebarAccent
    Color(
        0xFF1B4A66), // accentContainer: muted blue container, echoes navAccent
    Color(0xFFFF6B6B), // error
    Color(0xFF1A1C20), // outline: subtle, between primary and tertiary
    Color(0xFF42516D), // fourth: notifications/toast surface -- deliberately
    // a clear step up in lightness (not just a subtle third background
    // tier) so a "Theme saved"-style toast or the chat reply-preview box
    // actually reads as a raised surface instead of blending into Primary.
    // Button label / border / tonal fill (tail slots 12-14): X-blue label, muted blue border, slate tonal fill.
    Color(0xFF1D9BF0), // buttonText1
    Color(0xFF5A83A0), // buttonBorderColor
    Color(0xFF4C6372), // buttonBackgroundThird
    // The input pair (tail slots 15-16): the accent-derived values this
    // palette already rendered, written out so appending the slots
    // changed nothing about how it looks.
    Color(0xFF115A8B), // inputResting
    Color(0xFF1D9BF0), // inputSelected
  ]), // Leeds United: the club's navy and gold, built as a theme in the editor
  // and exported before being brought in here (leeds-united-v3.json). Navy
  // #1D428A and gold #FFCD00 are the club's own two colors; the background
  // tiers are that navy taken down toward black so the gold has somewhere
  // quiet to sit. Gold carries the accents and white the sidebar, which is
  // the shirt.
  ColorPalette(
      id: "builtin-leeds-united",
      name: "Leeds United",
      builtin: true,
      colors: [
        Color(0xFF0F1A30), // primary: deep navy-black
        Color(0xFF0A1322), // secondary (nav bg): darker still
        Color(0xFF1C2B49), // tertiary: the lifted navy panel
        Color(0xFF101B33), // sidebar bg
        Color(0xFF1E2E4E), // speech bg (received)
        Color(0xFF1D428A), // speech bg sent: the club navy itself
        Color(0xFFFFCD00), // navAccent: club gold
        Color(0xFFFFFFFF), // sidebarAccent: the shirt
        Color(0xFF2C4E8F), // accentContainer: navy container, echoes navAccent
        Color(0xFFFF6B6B), // error
        Color(0xFF1A2540), // outline: subtle, between primary and tertiary
        Color(0xFF3E5687), // fourth: notifications/toast surface -- a clear
        // step up in lightness so it reads as raised, not just another navy tier
        // Button label / border / tonal fill (tail slots 12-14): gold label, with
        // the border and fill desaturated toward the navy so they stay chrome
        // rather than two more gold elements competing with the accent.
        Color(0xFFFFCD00), // buttonText1
        Color(0xFF9B8D53), // buttonBorderColor
        Color(0xFF6C602E), // buttonBackgroundThird
        // The input pair (tail slots 15-16): the accent-derived values this
        // palette already rendered, written out so appending the slots
        // changed nothing about how it looks.
        Color(0xFF9D8414), // inputResting
        Color(0xFFFFCD00), // inputSelected
      ]),
  // Ulysses: the writing app's dark mode -- flat, near-neutral greys with no
  // hue in the chrome at all, and two accents that never appear together.
  // The point of the design is that nothing competes with the text, so the
  // tiers sit close together and the only saturated colors in the palette
  // are the two accents.
  //
  // The blue is the app's chrome accent -- the selected folder, the nav's
  // own selected item, the toggles. The warm brown/tan pair is the other:
  // Ulysses sets an annotated line as tan text on a brown ground, and it is
  // the only warmth anywhere in that design, which is what makes it read as
  // a mark on the page rather than as part of the furniture. Here that pair
  // is the input box and the sidebar's selected item, so the two accents
  // stay on separate parts of the app and never sit side by side.
  //
  // Tuned in the editor and exported ("Ulysses Take 2"), then copied in
  // exactly -- not re-derived, and not re-tuned toward the contrast floors.
  // See the notes on speech bg sent and inputResting for the two places
  // that needed a word.
  ColorPalette(id: "builtin-ulysses", name: "Ulysses", builtin: true, colors: [
    Color(0xFF1E1E1E), // primary: the editor sheet
    Color(0xFF161616), // secondary (nav bg): the darkest column
    Color(0xFF262626), // tertiary: the raised card in the note list
    Color(0xFF1A1A1A), // sidebar bg: between the two
    Color(0xFF262626), // speech bg (received): the same tone as the card
    Color(0xFF0E0E0E), // speech bg sent: below the sheet rather than above
    // it, which is the one place this design puts a surface *under* the
    // page. Authored as 0xFF161616, which measured 1.085:1 against the
    // sheet -- under the 1.15 a bubble needs to have any visible edge at
    // all -- so it is taken down to the nearest tone that clears it, 1.158:1
    Color(0xFF0A84FF), // navAccent: the blue on the selected folder
    Color(0xFFC08A5B), // sidebarAccent: the tan. The chrome accent is the
    // blue above; the sidebar taking the warm one is what keeps the
    // design's two colors on separate furniture
    Color(0xFF17456F), // accentContainer: the muted blue container
    Color(0xFFFF6B6B), // error
    Color(0xFF2B2B2B), // outline: just above the card tone, so a divider
    // reads as the edge of a panel rather than as a line drawn on one
    Color(0xFF4A4A4A), // fourth: notifications/toast surface -- neutral, and
    // a clear step up in lightness so it reads as raised
    // Button label / border / tonal fill (tail slots 12-14): the tan as the
    // label, and neutral greys for the border and fill. Tinting those as
    // well would put an accent on every button edge in the app, which is the
    // opposite of what this design does.
    Color(0xFFC08A5B), // buttonText1: the tan, 5.58:1 on the sheet
    Color(0xFF7A7A7A), // buttonBorderColor
    Color(0xFF3F3F3F), // buttonBackgroundThird
    // The input pair (tail slots 15-16): warm, while the chrome stays blue.
    // This is why those two slots are storable at all -- derived from
    // navAccent they would both come out blue.
    Color(0xFF3B2F26), // inputResting: 1.29:1 against the sheet, which is
    // below the 1.6 a *derived* resting border is held to. Authored, seen
    // rendered, and kept: the design wants the box to be felt rather than
    // read, and the focused state below carries the visible state
    Color(0xFFC08A5B), // inputSelected: the tan, focused
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
    Color(
        0xFF155C48), // accentContainer: muted green container, echoes navAccent
    Color(0xFFFF6B6B), // error
    Color(0xFF1B1F24), // outline: subtle, between primary and tertiary
    Color(0xFF475D76), // fourth: notifications/toast surface -- a clear
    // step up in lightness so it reads as raised, not just another
    // near-black background tier
    // Button label / border / tonal fill (tail slots 12-14): Element green, muted green border and fill.
    Color(0xFF0DBD8B), // buttonText1
    Color(0xFF559885), // buttonBorderColor
    Color(0xFF44675D), // buttonBackgroundThird
    // The input pair (tail slots 15-16): the accent-derived values this
    // palette already rendered, written out so appending the slots
    // changed nothing about how it looks.
    Color(0xFF117058), // inputResting
    Color(0xFF0DBD8B), // inputSelected
  ]), // Gmail: matches its real dark-mode chrome -- neutral grey panels
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
    Color(
        0xFF15416B), // accentContainer: muted blue container, echoes sidebarAccent
    Color(0xFFFF6B6B), // error
    Color(0xFF262729), // outline: subtle, between primary and tertiary
    Color(0xFF5B6171), // fourth: notifications/toast surface -- a clear
    // step up in lightness so it reads as raised, not just another
    // near-black background tier
    // Button label / border / tonal fill (tail slots 12-14): Google's own dark-mode blue, which is what Google uses for
    // text buttons -- the #EA4335 brand red is only 4.10:1 as text here.
    Color(0xFF8AB4F8), // buttonText1
    Color(0xFFB98682), // buttonBorderColor
    Color(0xFF7D5653), // buttonBackgroundThird
    // The input pair (tail slots 15-16): the accent-derived values this
    // palette already rendered, written out so appending the slots
    // changed nothing about how it looks.
    Color(0xFF712F2B), // inputResting
    Color(0xFFEA4335), // inputSelected
  ]),
];
