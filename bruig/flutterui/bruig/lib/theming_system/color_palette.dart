// color_palette.dart defines the fixed set of color *roles* a theme carries.
// ThemePreset (preset.dart) stores one Color per role; the Color Palette
// section of the theme editor (color_palette_section.dart) edits them, and a
// saved/built-in ColorPalette (palette_library.dart) can overwrite a subset
// of them in one click.

// PaletteSlot identifies one of the palette's colors. Deliberately fewer,
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
  // The header's own default background. Seeded to primary, which is what
  // the header drew before it had a slot of its own.
  headerBackground,
  // The Dual Panel and Content Area theme areas' own default backgrounds.
  // Seeded to the same value as primary, so out of the box a page looks
  // exactly as it did when it simply showed the master background through;
  // they exist so those two regions can be moved off it independently.
  dualBackground,
  contentBackground,
  tertiary,
  secondary,
  // The nav bar's selected item. Split from navAccent ("Button Accent
  // Background"), which it used to share -- one slot couldn't be tuned for
  // the nav bar without dragging every button's accent along with it.
  navSelected,
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
  // The other six colors of the "Button Colors" row. accentContainer above
  // is the seventh (Button Background Primary) -- it already was the button
  // fill before this row existed, so it keeps its slot rather than a new
  // one duplicating it. Button 1/4/5 take one of the three backgrounds;
  // every role can take the border, the hover tint, and one of the two
  // label colors. See button_style.dart for which role uses which.
  buttonBackgroundSecondary,
  buttonBackgroundThird,
  buttonBorderColor,
  buttonHover,
  buttonText1,
  buttonText2,
  navAccent,
  // Inputs get two colours: the border they sit at, and the one they take
  // when focused. Resting comes first so the pair reads left-to-right in
  // the palette grid the way the states themselves do.
  inputResting,
  inputSelected,
  // The fill inside an input. Transparent by default -- inputs have never
  // had a fill, and transparent is how that stays true while still being
  // a swatch you can set.
  inputBackground,
  sidebarAccent,
  error,
  success,
}

const Map<PaletteSlot, String> _paletteSlotLabels = {
  PaletteSlot.primary: "Master Background",
  PaletteSlot.headerBackground: "Header Background",
  PaletteSlot.dualBackground: "Dual Background",
  PaletteSlot.contentBackground: "Content Background",
  PaletteSlot.tertiary: "Secondary Background",
  PaletteSlot.secondary: "Navigation Background",
  PaletteSlot.navSelected: "Navigation Accent Color",
  PaletteSlot.sidebarBackground: "Sidebar Background",
  PaletteSlot.fourth: "Notifications Background",
  PaletteSlot.speechBackground: "Speech Background (Receive)",
  PaletteSlot.speechBackgroundSent: "Speech Background (Send)",
  PaletteSlot.outline: "Outline (Borders/Dividers)",
  PaletteSlot.onSurface: "Primary Text Color",
  PaletteSlot.onSurfaceVariant: "Secondary Text Color",
  PaletteSlot.navText: "Navigation Text Color",
  PaletteSlot.sidebarText: "Sidebar Text Color",
  PaletteSlot.accentContainer: "Button Background Primary",
  PaletteSlot.buttonBackgroundSecondary: "Button Background Secondary",
  PaletteSlot.buttonBackgroundThird: "Third Background Color",
  PaletteSlot.buttonBorderColor: "Button Border Color",
  PaletteSlot.buttonHover: "Background Hover",
  PaletteSlot.buttonText1: "Text Color 1",
  PaletteSlot.buttonText2: "Text Color 2",
  PaletteSlot.navAccent: "Toggle Background",
  PaletteSlot.inputResting: "Input Resting Color",
  PaletteSlot.inputSelected: "Input Color",
  PaletteSlot.inputBackground: "Input Background",
  PaletteSlot.sidebarAccent: "Sidebar Accent Color",
  PaletteSlot.error: "Error",
  PaletteSlot.success: "Success",
};

String paletteSlotLabel(PaletteSlot slot) => _paletteSlotLabels[slot]!;

// kMaxPaletteColors caps the *total* palette (the fixed PaletteSlot roles +
// ThemePreset.extraPaletteColors) a preset can carry; kMaxExtraPaletteColors
// is the remaining room for extras once the fixed roles are accounted for.
// Raised as fixed roles were added (Header/Input/Nav Accent take it to 23
// on their own, the Button Colors row to 30) -- at 22 the cap was already
// below the number of fixed slots, which left no room for a single extra
// colour, and at 32 the button row had cut the room for extras to two.
const int kMaxPaletteColors = 40;
final int kMaxExtraPaletteColors =
    kMaxPaletteColors - PaletteSlot.values.length;

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
  // The three button roles a palette has to decide for itself, appended at
  // the tail so palettes exported before they existed still load (colorAt's
  // length check falls back to the seed for them). They can't be derived
  // from navAccent the way they briefly were: a nav bar's selected item is
  // a UI element held to 3:1, while a button's label is text held to 4.5:1,
  // and several brand accents (Facebook blue, Google red, Reddit orange)
  // clear the first but not the second. Border and the tonal fill are
  // separate for the same reason in reverse -- both want a muted,
  // background-family tone, not the palette's loudest color.
  PaletteSlot.buttonText1,
  PaletteSlot.buttonBorderColor,
  PaletteSlot.buttonBackgroundThird,
];
