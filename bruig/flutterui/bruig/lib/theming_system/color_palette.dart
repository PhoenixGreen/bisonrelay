// color_palette.dart defines the fixed set of color *roles* a theme carries.
// ThemePreset (preset.dart) stores one Color per role; the Color Palette
// section of the theme editor (color_palette_section.dart) edits them, and a
// saved/built-in ColorPalette (palette_library.dart) can overwrite a subset
// of them in one click.

// PaletteSlot identifies one of the 17 palette colors. Deliberately fewer,
// more distinct roles than Material3's ColorScheme (which has 4 near-
// identical onPrimary/onSecondary/onTertiary/onError slots in practice) --
// every slot here has a clearly different purpose so there's minimal visual
// overlap between them. Grouped by tier (backgrounds, then text, then
// accents, then semantic) so the palette editor and dropdowns read as a
// coherent list rather than an arbitrary historical order. `buttonBorder`
// used to be its own slot here; it's been removed and merged into
// `navAccent` (see ThemePreset.toAppTheme) since every built-in palette
// already set it to an exact duplicate of navAccent's own value.
enum PaletteSlot {
  primary,
  tertiary,
  secondary,
  sidebarBackground,
  fourth,
  speechBackground,
  speechBackgroundSent,
  outline,
  onSurface,
  onSurfaceVariant,
  navText,
  sidebarText,
  accentContainer,
  navAccent,
  sidebarAccent,
  error,
  success,
}

const Map<PaletteSlot, String> _paletteSlotLabels = {
  PaletteSlot.primary: "Primary Background",
  PaletteSlot.tertiary: "Secondary Background",
  PaletteSlot.secondary: "Navigation Background",
  PaletteSlot.sidebarBackground: "Sidebar Background",
  PaletteSlot.fourth: "Notifications Background",
  PaletteSlot.speechBackground: "Speech Background (Receive)",
  PaletteSlot.speechBackgroundSent: "Speech Background (Send)",
  PaletteSlot.outline: "Outline (Borders/Dividers)",
  PaletteSlot.onSurface: "Primary Text Color",
  PaletteSlot.onSurfaceVariant: "Secondary Text Color",
  PaletteSlot.navText: "Navigation Text Color",
  PaletteSlot.sidebarText: "Sidebar Text Color",
  PaletteSlot.accentContainer: "Button Background",
  PaletteSlot.navAccent: "Button Accent Background",
  PaletteSlot.sidebarAccent: "Sidebar Accent Color",
  PaletteSlot.error: "Error",
  PaletteSlot.success: "Success",
};

String paletteSlotLabel(PaletteSlot slot) => _paletteSlotLabels[slot]!;

// kMaxPaletteColors caps the *total* palette (the fixed PaletteSlot roles +
// ThemePreset.extraPaletteColors) a preset can carry; kMaxExtraPaletteColors
// is the remaining room for extras once the fixed roles are accounted for.
const int kMaxPaletteColors = 20;
final int kMaxExtraPaletteColors = kMaxPaletteColors - PaletteSlot.values.length;

// kVividPaletteSlots are the 12 roles a ColorPalette library entry (see
// palette_library.dart) actually carries and overwrites when applied --
// 6 background-tier hues (used exactly as stored -- see
// color_palette_section.dart's applyColorPalette) plus 6 real accent/semantic
// colors. Each background tier gets its own hue input (rather than all
// deriving from `primary`) so a palette's sidebar/chat areas can each have a
// distinct character instead of looking like minor tints of the same
// background. Tertiary also drives the Feed post card/post-detail background
// and the Settings page's group panels (see post_content.dart/feed_posts.dart/
// settings.dart's _SettingsGroupCard) -- previously a separate `newsBackground`
// slot duplicated this role for feed cards only, leaving Settings on an
// unrelated color; merged into Tertiary so every "second background" tier
// in the app reads as the same deliberate color. speechBackgroundSent (the
// "sent"/own chat bubble) is included alongside speechBackground (the
// "received" bubble) so the two can read as deliberately distinct colors
// per palette -- e.g. WhatsApp's real outgoing-bubble teal -- instead of
// speechBackgroundSent silently falling back to the Default/Light seed's
// own value (identical across every other palette) the way it used to.
// accentContainer (drives Switch/tonal-button backgrounds) is included for
// the same reason -- it used to always fall back to the Default/Light
// seed's own pale lavender, which reads as a random, brand-mismatched
// "Buttons/Toggles" color on e.g. WhatsApp-green or Reddit-orange palettes.
// error is included too so each palette can use a dark-mode-appropriate
// red tuned for its own background instead of a single flat value that was
// occasionally too dark/muddy against certain panel tones -- it's still
// deliberately kept a similar, conventional "danger" red across every
// palette (not brand-tinted) since a semantic color like error should stay
// visually predictable regardless of theme. outline is included so each
// palette can tune its own divider color to blend into that palette's
// specific background tone -- a single flat grey doesn't blend equally
// well with, say, WhatsApp's teal-black vs Snapchat's amber-black.
// onSurface/navText/sidebarText/success are functional/neutral roles that
// must stay dark-vs-light-theme-appropriate, so a library palette
// deliberately leaves them alone (they're reset from palette.brightness's
// own seed instead) rather than clobbering them with (possibly
// brightness-mismatched) baked-in values. fourth (the reply-preview box and
// success/error toast background) IS included, appended at the tail -- it
// used to always fall back to the Default/Light seed's own flat purple-blue
// regardless of which palette was active, so e.g. applying WhatsApp's
// teal-black or Snapchat's warm amber-black look still showed an unrelated
// purple notification box; each built-in palette now tunes its own
// third-background-tier tone to match.
const List<PaletteSlot> kVividPaletteSlots = [
  PaletteSlot.primary,
  PaletteSlot.secondary,
  PaletteSlot.tertiary,
  PaletteSlot.sidebarBackground,
  PaletteSlot.speechBackground,
  PaletteSlot.speechBackgroundSent,
  PaletteSlot.navAccent,
  PaletteSlot.sidebarAccent,
  PaletteSlot.accentContainer,
  PaletteSlot.error,
  PaletteSlot.outline,
  PaletteSlot.fourth,
];
