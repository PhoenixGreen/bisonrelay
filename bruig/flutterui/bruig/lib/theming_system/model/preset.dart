import 'package:bruig/theming_system/model/area_style.dart';
import 'package:bruig/theming_system/model/button_style.dart';
import 'package:bruig/theming_system/model/color_contrast.dart';
import 'package:bruig/theming_system/model/color_hex.dart';
import 'package:bruig/theming_system/model/color_palette.dart';
import 'package:bruig/theming_system/model/preset_migrations.dart';
import 'package:bruig/theming_system/model/theme_area.dart';

// The one runtime dependency the model has, and only for the two seeds at
// the foot of this file: they read the built-in dark/light themes' real
// ColorScheme rather than re-guessing those values, so "Default Theme"
// can't drift from what the untouched app actually looks like.
import 'package:bruig/theming_system/runtime/app_theme.dart';
import 'package:flutter/material.dart';

// ThemePreset is one full, nameable, exportable custom theme: a palette (one
// color per PaletteSlot, plus any user-added extras) and a set of per-area
// style overrides. toAppTheme() compiles it into the same AppTheme shape the
// built-in dark/light themes use, so custom presets render through the
// pipeline the rest of the app already trusts.
class ThemePreset {
  final String id;
  final String name;
  final Brightness brightness;

  // ---------------------------------------------------------------------------
  // The palette -- one color per PaletteSlot, in the roles documented there.
  // ---------------------------------------------------------------------------
  final Color primary; // Main app background (and ColorScheme.fromSeed's
  // seed color). Also the Theme Areas section's select-menu popup
  // background.
  // The Dual Panel and Content Area areas' default backgrounds. Both are
  // seeded to primary's own value, so an untouched preset looks exactly as
  // it did when those regions simply let the master background show
  // through -- see PaletteSlot.dualBackground.
  final Color dualBackground;
  final Color contentBackground;
  final Color secondary; // Nav bar's background fill.
  final Color tertiary; // Shares the compiled ColorScheme's tertiary/
  // tertiaryContainer roles -- the RTC instant-call banner, voice-recorder
  // box, markdown blockquotes, Feed post card/post-detail background, the
  // Settings page's group panels (_SettingsGroupCard), and the Settings >
  // Audio microphone/output volume sliders' track background -- this
  // app's general-purpose "second background" tier.
  final Color fourth; // A 4th, more deeply nested background tier -- the
  // chat reply-preview box and the success/error snackbar ("popup
  // notification") background.
  final Color sidebarBackground; // Sidebar (subMenuTabBar) row/tile
  // background -- Settings/LN Management/Feed/etc.'s left nav list.
  final Color speechBackground; // Chat message bubble (received) background.
  final Color speechBackgroundSent; // Chat message bubble (sent/own)
  // background -- previously unthemed (always theme.colors.surfaceContainer,
  // a Primary-derived tone), so sent bubbles never actually followed any
  // preset color the way received bubbles did.
  final Color accentContainer; // Backs Material's primaryContainer/secondary/
  // secondaryContainer roles (default Switch track+thumb, FilledButton.tonal,
  // CancelButton's background, etc.) -- these were never
  // pinned to anything in toAppTheme's ColorScheme.fromSeed, so they were
  // left to Material's own tonal derivation from Primary's seed color, same
  // as the bug that made colorScheme.primary itself render as an unrelated,
  // oddly-tinted color (see navAccent's doc) -- except here nothing was
  // pinned at all, so it surfaced as a stray, uncontrollable pink showing up
  // across the app with no palette field to fix it from. CancelButton
  // now reads buttonBackgroundSecondary, the palette's own red button fill,
  // which is what Bison Relay has always drawn it as.
  //
  // The six slots below join it to make up the "Button Colors" row -- see
  // button_style.dart for which of the five button roles reads which.
  final Color buttonBackgroundSecondary; // The red fill: CancelButton
  // (Clear Post, Close Channel, Cancel).
  final Color buttonBackgroundThird; // The grey fill: FilledButton and
  // FilledButton.tonal (Create Post).
  final Color buttonBorderColor; // Every button's border, and so
  // colorScheme.outline -- which is what OutlinedButton's own default M3
  // border reads. Split out of navAccent, which used to drive it and the
  // nav bar together.
  final Color buttonHover; // The tint painted over a button's fill while
  // hovered/pressed. Deliberately translucent by default, so it reads as a
  // lift of whatever fill is underneath rather than replacing it.
  final Color buttonText1; // Label color for the two unfilled roles (Plain,
  // Outlined), where it sits against the page's own background.
  final Color buttonText2; // Label color for the three filled roles
  // (Primary, Tonal, Danger), where Text Color 1 would be reading against a
  // strong fill instead of the page.
  final Color onSurface; // General app text/icons -- NOT the nav bar or
  // sidebar, which have their own dedicated text/accent slots below.
  final Color onSurfaceVariant; // Muted/secondary text+icons -- toolbar
  // icon buttons, hint text, etc. Previously hardcoded (Colors.grey[600])
  // in toAppTheme with no palette field behind it at all, so it couldn't
  // be themed like onSurface can.
  final Color navText; // Nav bar's unselected-item text+icon color.
  final Color navAccent; // Nav bar's selected-item text+icon color.
  final Color headerBackground; // The header's own background, split from
  // primary so the top bar can be moved off the master background without
  // taking every other surface with it.
  final Color navSelected; // Nav bar's selected-item text+icon color.
  // Seeded from navAccent, which is what the nav bar read before this
  // slot existed.
  final Color inputResting; // Input boxes' border when not focused.
  // Seeded from inputSelected faded toward the background (see
  // restingBorderFrom), so the two read as one colour at two strengths with the
  // resting state always the quieter of the pair.
  final Color inputBackground; // Fill inside an input. Transparent unless
  // a theme sets it, which is what inputs have always looked like.
  final Color inputSelected; // Input boxes' focused border (see the Input
  // Areas theme area). Its own slot so inputs can be tuned without
  // dragging the nav bar's selected-item color along with them, which is
  // what they used to share.
  final Color sidebarText; // Sidebar's unselected-item text+icon color.
  final Color sidebarAccent; // Sidebar's selected-item text+icon color.
  final Color outline; // Borders/dividers that should blend into the
  // background (drives colorScheme.outlineVariant) -- panel dividers,
  // card/list-item borders, muted icon tints. Deliberately low-contrast.
  final Color error; // Genuine failure/danger states only -- validation
  // errors, exception messages, upload/parse failures, hanging up a live
  // call. Deliberately NOT used for the generic CancelButton (see
  // accentContainer's doc) or any other plain "step back"/dismiss action.
  final Color success;

  // extraPaletteColors are user-added swatches beyond the fixed roles
  // above -- free-form, no fixed semantic meaning, just additional options
  // offered wherever an area style needs a color picked (see `palette`
  // below and the theme editor's palette-color dropdowns). Capped at
  // kMaxExtraPaletteColors so the total palette never exceeds
  // kMaxPaletteColors.
  final List<Color> extraPaletteColors;

  final Map<ThemeArea, AreaStyle> areas;

  // Menu rename/reorder customization is saved as *part of this preset*
  // (rather than as a single global setting) so that switching themes
  // switches menu layout too, and "Reset to Default" (which switches to
  // the built-in default theme, unaffected by any custom preset) can't
  // accidentally erase what's saved in a *different*, still-selectable
  // preset. Null means "no customization" (always true for the built-in
  // dark/light themes). Keyed/ordered by routeName, same shape as
  // MainMenuModel.currentLabels()/currentOrder().
  final Map<String, String>? menuLabels;
  final List<String>? menuOrder;

  // Directory this preset was loaded from on disk (null for a preset that
  // only exists in memory, e.g. mid-edit before its first save). Area
  // background images are stored relative to this directory.
  final String? sourceDir;

  const ThemePreset({
    required this.id,
    this.name = "Default Theme",
    this.brightness = Brightness.dark,
    required this.primary,
    required this.dualBackground,
    required this.contentBackground,
    required this.secondary,
    required this.tertiary,
    required this.fourth,
    required this.sidebarBackground,
    required this.speechBackground,
    required this.speechBackgroundSent,
    required this.accentContainer,
    required this.buttonBackgroundSecondary,
    required this.buttonBackgroundThird,
    required this.buttonBorderColor,
    required this.buttonHover,
    required this.buttonText1,
    required this.buttonText2,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.navText,
    required this.navAccent,
    required this.headerBackground,
    required this.navSelected,
    required this.inputBackground,
    required this.inputResting,
    required this.inputSelected,
    required this.sidebarText,
    required this.sidebarAccent,
    required this.outline,
    required this.error,
    required this.success,
    this.extraPaletteColors = const [],
    this.areas = const {},
    this.menuLabels,
    this.menuOrder,
    this.sourceDir,
  });

  Color forSlot(PaletteSlot slot) => switch (slot) {
        PaletteSlot.primary => primary,
        PaletteSlot.dualBackground => dualBackground,
        PaletteSlot.contentBackground => contentBackground,
        PaletteSlot.secondary => secondary,
        PaletteSlot.tertiary => tertiary,
        PaletteSlot.fourth => fourth,
        PaletteSlot.sidebarBackground => sidebarBackground,
        PaletteSlot.speechBackground => speechBackground,
        PaletteSlot.speechBackgroundSent => speechBackgroundSent,
        PaletteSlot.accentContainer => accentContainer,
        PaletteSlot.buttonBackgroundSecondary => buttonBackgroundSecondary,
        PaletteSlot.buttonBackgroundThird => buttonBackgroundThird,
        PaletteSlot.buttonBorderColor => buttonBorderColor,
        PaletteSlot.buttonHover => buttonHover,
        PaletteSlot.buttonText1 => buttonText1,
        PaletteSlot.buttonText2 => buttonText2,
        PaletteSlot.onSurface => onSurface,
        PaletteSlot.onSurfaceVariant => onSurfaceVariant,
        PaletteSlot.navText => navText,
        PaletteSlot.navAccent => navAccent,
        PaletteSlot.headerBackground => headerBackground,
        PaletteSlot.navSelected => navSelected,
        PaletteSlot.inputBackground => inputBackground,
        PaletteSlot.inputResting => inputResting,
        PaletteSlot.inputSelected => inputSelected,
        PaletteSlot.sidebarText => sidebarText,
        PaletteSlot.sidebarAccent => sidebarAccent,
        PaletteSlot.outline => outline,
        PaletteSlot.error => error,
        PaletteSlot.success => success,
      };

  ThemePreset withSlot(PaletteSlot slot, Color c) => switch (slot) {
        PaletteSlot.primary => copyWith(primary: c),
        PaletteSlot.dualBackground => copyWith(dualBackground: c),
        PaletteSlot.contentBackground => copyWith(contentBackground: c),
        PaletteSlot.secondary => copyWith(secondary: c),
        PaletteSlot.tertiary => copyWith(tertiary: c),
        PaletteSlot.fourth => copyWith(fourth: c),
        PaletteSlot.sidebarBackground => copyWith(sidebarBackground: c),
        PaletteSlot.speechBackground => copyWith(speechBackground: c),
        PaletteSlot.speechBackgroundSent => copyWith(speechBackgroundSent: c),
        PaletteSlot.accentContainer => copyWith(accentContainer: c),
        PaletteSlot.buttonBackgroundSecondary =>
          copyWith(buttonBackgroundSecondary: c),
        PaletteSlot.buttonBackgroundThird => copyWith(buttonBackgroundThird: c),
        PaletteSlot.buttonBorderColor => copyWith(buttonBorderColor: c),
        PaletteSlot.buttonHover => copyWith(buttonHover: c),
        PaletteSlot.buttonText1 => copyWith(buttonText1: c),
        PaletteSlot.buttonText2 => copyWith(buttonText2: c),
        PaletteSlot.onSurface => copyWith(onSurface: c),
        PaletteSlot.onSurfaceVariant => copyWith(onSurfaceVariant: c),
        PaletteSlot.navText => copyWith(navText: c),
        PaletteSlot.navAccent => copyWith(navAccent: c),
        PaletteSlot.headerBackground => copyWith(headerBackground: c),
        PaletteSlot.navSelected => copyWith(navSelected: c),
        PaletteSlot.inputBackground => copyWith(inputBackground: c),
        PaletteSlot.inputResting => copyWith(inputResting: c),
        PaletteSlot.inputSelected => copyWith(inputSelected: c),
        PaletteSlot.sidebarText => copyWith(sidebarText: c),
        PaletteSlot.sidebarAccent => copyWith(sidebarAccent: c),
        PaletteSlot.outline => copyWith(outline: c),
        PaletteSlot.error => copyWith(error: c),
        PaletteSlot.success => copyWith(success: c),
      };

  // palette returns the fixed-role colors (in PaletteSlot order) plus any
  // extraPaletteColors -- this is the full set of colors offered wherever
  // an area style needs a color picked (see the theme editor's
  // palette-color dropdowns).
  List<Color> get palette =>
      [...PaletteSlot.values.map(forSlot), ...extraPaletteColors];

  // buttonPaletteColors is this preset's seven button colors bundled for
  // buildButtonStyles -- see button_style.dart.
  ButtonPaletteColors get buttonPaletteColors => ButtonPaletteColors(
        primaryBackground: accentContainer,
        secondaryBackground: buttonBackgroundSecondary,
        thirdBackground: buttonBackgroundThird,
        border: buttonBorderColor,
        hover: buttonHover,
        text1: buttonText1,
        text2: buttonText2,
      );

  ThemePreset copyWith({
    String? id,
    String? name,
    Brightness? brightness,
    Color? primary,
    Color? dualBackground,
    Color? contentBackground,
    Color? secondary,
    Color? tertiary,
    Color? fourth,
    Color? sidebarBackground,
    Color? speechBackground,
    Color? speechBackgroundSent,
    Color? accentContainer,
    Color? buttonBackgroundSecondary,
    Color? buttonBackgroundThird,
    Color? buttonBorderColor,
    Color? buttonHover,
    Color? buttonText1,
    Color? buttonText2,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? navText,
    Color? navAccent,
    Color? headerBackground,
    Color? navSelected,
    Color? inputBackground,
    Color? inputResting,
    Color? inputSelected,
    Color? sidebarText,
    Color? sidebarAccent,
    Color? outline,
    Color? error,
    Color? success,
    List<Color>? extraPaletteColors,
    Map<ThemeArea, AreaStyle>? areas,
    Map<String, String>? menuLabels,
    List<String>? menuOrder,
    String? sourceDir,
  }) =>
      ThemePreset(
        id: id ?? this.id,
        name: name ?? this.name,
        brightness: brightness ?? this.brightness,
        primary: primary ?? this.primary,
        dualBackground: dualBackground ?? this.dualBackground,
        contentBackground: contentBackground ?? this.contentBackground,
        secondary: secondary ?? this.secondary,
        tertiary: tertiary ?? this.tertiary,
        fourth: fourth ?? this.fourth,
        sidebarBackground: sidebarBackground ?? this.sidebarBackground,
        speechBackground: speechBackground ?? this.speechBackground,
        speechBackgroundSent: speechBackgroundSent ?? this.speechBackgroundSent,
        accentContainer: accentContainer ?? this.accentContainer,
        buttonBackgroundSecondary:
            buttonBackgroundSecondary ?? this.buttonBackgroundSecondary,
        buttonBackgroundThird:
            buttonBackgroundThird ?? this.buttonBackgroundThird,
        buttonBorderColor: buttonBorderColor ?? this.buttonBorderColor,
        buttonHover: buttonHover ?? this.buttonHover,
        buttonText1: buttonText1 ?? this.buttonText1,
        buttonText2: buttonText2 ?? this.buttonText2,
        onSurface: onSurface ?? this.onSurface,
        onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
        navText: navText ?? this.navText,
        navAccent: navAccent ?? this.navAccent,
        headerBackground: headerBackground ?? this.headerBackground,
        navSelected: navSelected ?? this.navSelected,
        inputBackground: inputBackground ?? this.inputBackground,
        inputResting: inputResting ?? this.inputResting,
        inputSelected: inputSelected ?? this.inputSelected,
        sidebarText: sidebarText ?? this.sidebarText,
        sidebarAccent: sidebarAccent ?? this.sidebarAccent,
        outline: outline ?? this.outline,
        error: error ?? this.error,
        success: success ?? this.success,
        extraPaletteColors: extraPaletteColors ?? this.extraPaletteColors,
        areas: areas ?? this.areas,
        menuLabels: menuLabels ?? this.menuLabels,
        menuOrder: menuOrder ?? this.menuOrder,
        sourceDir: sourceDir ?? this.sourceDir,
      );

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "brightness": brightness.name,
        // paletteVersion marks which PaletteSlot layout a preset's stored
        // color *indexes* were written against -- 2 after the reorder and
        // buttonBorder removal, 3 after Dual/Content Background were
        // inserted below primary, 4 after Input Selected was inserted after
        // navAccent, 5 after Input Resting joined it, 6 after Navigation
        // Accent was split out of navAccent, 7 after Header Background was
        // split out of primary, 8 after Input Background was added, 9 after
        // the six remaining Button Colors were inserted after Button
        // Background Primary. The palette map itself is keyed by slot
        // *name*, so it's unaffected by any of them; only AreaStyle's index
        // fields (raw positions into the flat `palette` list) need this to
        // know whether they still need remapping on load.
        "paletteVersion": 9,
        "palette": {
          for (var slot in PaletteSlot.values)
            slot.name: colorToHex(forSlot(slot)),
        },
        if (extraPaletteColors.isNotEmpty)
          "extraPaletteColors": extraPaletteColors.map(colorToHex).toList(),
        "areas": areas.map((k, v) => MapEntry(k.name, v.toJson())),
        if (menuLabels != null) "menuLabels": menuLabels,
        if (menuOrder != null) "menuOrder": menuOrder,
      };

  factory ThemePreset.fromJson(Map<String, dynamic> j) {
    var p = j["palette"] as Map<String, dynamic>;
    var preset = seedFor(
      j["brightness"] == "light" ? Brightness.light : Brightness.dark,
    ).copyWith(id: j["id"], name: j["name"] ?? "Default Theme");
    for (var slot in PaletteSlot.values) {
      var hex = p[slot.name];
      if (hex != null) preset = preset.withSlot(slot, colorFromHex(hex));
    }
    // Presets written before inputSelected existed have no value for it,
    // and every input in the app used to draw in navAccent -- so seed it
    // from that preset's own navAccent rather than the built-in seed's,
    // which would visibly recolour every text box on load.
    // The header drew the master background before it had a slot.
    if (p[PaletteSlot.headerBackground.name] == null) {
      preset = preset.withSlot(PaletteSlot.headerBackground, preset.primary);
    }
    // The nav bar read navAccent before this slot existed, so a preset
    // without one keeps looking exactly as it did.
    if (p[PaletteSlot.navSelected.name] == null) {
      preset = preset.withSlot(PaletteSlot.navSelected, preset.navAccent);
    }
    if (p[PaletteSlot.inputSelected.name] == null) {
      preset = preset.withSlot(PaletteSlot.inputSelected, preset.navAccent);
    }
    // Resting starts as a faded Input Color, for every palette: the two
    // then read as one colour at two strengths, which is a sane starting
    // point whatever the theme, and it's a swatch like any other from
    // there. Faded toward this preset's own background rather than
    // darkened -- see restingBorderFrom.
    if (p[PaletteSlot.inputResting.name] == null) {
      preset = preset.withSlot(PaletteSlot.inputResting,
          restingBorderFrom(preset.inputSelected, preset.primary));
    }
    // Every button drew its border and its accent label from navAccent
    // before the Button Colors row existed, so a preset without them keeps
    // looking exactly as it did rather than jumping to the built-in seed's
    // own accent. The three fills and the second label color have no
    // earlier equivalent to inherit and keep the seed's values.
    if (p[PaletteSlot.buttonBorderColor.name] == null) {
      preset = preset.withSlot(PaletteSlot.buttonBorderColor, preset.navAccent);
    }
    if (p[PaletteSlot.buttonText1.name] == null) {
      preset = preset.withSlot(PaletteSlot.buttonText1, preset.navAccent);
    }
    if (p[PaletteSlot.buttonHover.name] == null) {
      preset = preset.withSlot(
          PaletteSlot.buttonHover, preset.navAccent.withValues(alpha: 0.12));
    }
    var rawAreas = j["areas"] as Map<String, dynamic>? ?? {};
    var paletteVersion = (j["paletteVersion"] as num?)?.toInt() ?? 1;
    if (paletteVersion != 9) {
      rawAreas = rawAreas.map((k, v) {
        var area = Map<String, dynamic>.from(v as Map<String, dynamic>);
        // Every field holding a raw position into the flat palette list.
        for (var key in [
          "solidColorIndex",
          "borderColorIndex",
          "sidebarDividerColorIndex",
          "chatListAccentColorIndex",
          "chatListBackgroundColorIndex",
          "chatListSelectedColorIndex",
          "messageAreaColorIndex",
          "inputBackgroundColorIndex",
          "inputBorderColorIndex",
        ]) {
          if (area[key] != null) {
            area[key] = migrateLegacyColorIndex(
                (area[key] as num).toInt(), paletteVersion);
          }
        }
        for (var key in [
          "gradientColorIndexes",
          "borderGradientColorIndexes"
        ]) {
          if (area[key] is List) {
            area[key] = (area[key] as List)
                .map((e) => e == null
                    ? null
                    : migrateLegacyColorIndex(
                        (e as num).toInt(), paletteVersion))
                .toList();
          }
        }
        return MapEntry(k, area);
      });
    }
    return preset.copyWith(
      extraPaletteColors: j["extraPaletteColors"] != null
          ? (j["extraPaletteColors"] as List)
              .map((h) => colorFromHex(h as String))
              .toList()
          : const [],
      // Skip any area key that no longer matches a known ThemeArea (e.g.
      // saved by a future/older version of the app) instead of throwing.
      areas: migrateAreas({
        for (var e in rawAreas.entries)
          if (ThemeArea.values.where((a) => a.name == e.key).firstOrNull
              case var area?)
            area: AreaStyle.fromJson(e.value as Map<String, dynamic>)
      }),
      menuLabels: j["menuLabels"] != null
          ? (j["menuLabels"] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, v as String))
          : null,
      menuOrder: j["menuOrder"] != null
          ? (j["menuOrder"] as List).cast<String>()
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Seeds
  // ---------------------------------------------------------------------------

  // seedFor returns the starting-point preset for a base brightness -- not a
  // separate installable preset, just what the palette editor pre-fills with
  // (and what a freshly-created "New Theme" starts from).
  static ThemePreset seedFor(Brightness brightness) =>
      brightness == Brightness.dark ? seedFromDark() : seedFromLight();

  // secondary/sidebarBackground/navText/navAccent/sidebarText/sidebarAccent
  // are read straight off appThemes' real ColorScheme rather than
  // independently-guessed hex literals, so the "Default Theme" card can
  // never silently drift from what the untouched, no-custom-preset app
  // actually looks like (this previously caused the seed's navAccent to be
  // amber/orange while the real default nav accent is ColorScheme.primary,
  // a lavender-purple/indigo).
  //
  // navText/sidebarText and navAccent/sidebarAccent are intentionally set
  // to the *same* source value (onSurfaceVariant / primary) because that's
  // what the real fallback rendering does when no preset is active (see
  // sidebar.dart's navUnselectedIconColor/navSelectedIconColor and
  // containers.dart's sidebarText/sidebarAccent fallbacks) -- Nav and
  // Sidebar are only meant to visibly diverge on sidebarBackground
  // (surfaceContainerLowest vs secondary's surfaceContainerLow), not on
  // text/accent, unless the user explicitly customizes one of them.
  static ThemePreset seedFromDark() {
    var scheme = appThemes["dark"]!.data.colorScheme;
    return ThemePreset(
      id: "custom",
      name: "Default Theme",
      brightness: Brightness.dark,
      primary: const Color(0xFF19172C),
      // Same as primary: a page shows the master background through until
      // one of these is deliberately moved off it.
      dualBackground: const Color(0xFF19172C),
      contentBackground: const Color(0xFF19172C),
      secondary: scheme.surfaceContainerLow,
      tertiary: const Color(0xFF232030),
      // A genuinely raised surface. This was 0xFF1C1930, which sits at a
      // 1.03:1 contrast against primary -- i.e. indistinguishable from the
      // page behind it, so the reply-preview box and every "Theme saved"
      // toast rendered as an invisible rectangle. 2.45:1 is the same step
      // the built-in library palettes were retuned to.
      fourth: const Color(0xFF56518A),
      sidebarBackground: scheme.surfaceContainerLowest,
      speechBackground: const Color(0xFF232030),
      // Was an exact-looking duplicate of the old `fourth` (0xFF1C1930),
      // 1.03:1 against primary -- own/sent bubbles had no visible edge at
      // all. A purple-tinted step up keeps them subordinate to the message
      // text while actually reading as a bubble.
      speechBackgroundSent: const Color(0xFF322D4E),
      // The five button colors below are Bison Relay master's own, read off
      // the ColorScheme its dark theme actually compiles to: master leaves
      // primaryContainer/secondaryContainer/errorContainer/outline to
      // Material's derivation from the 0xFF19172C seed, and those are the
      // exact values its buttons draw with (see components/buttons.dart on
      // master -- raisedButtonStyle reads primaryContainer, CancelButton
      // errorContainer). Hard-coded rather than read off `scheme` because
      // this app pins several of those roles itself now, so `scheme` no
      // longer reports what master would have shown.
      accentContainer: const Color(0xFF454077), // master primaryContainer
      buttonBackgroundSecondary: const Color(0xFF93000A), // errorContainer
      buttonBackgroundThird: const Color(0xFF474459), // secondaryContainer
      buttonBorderColor: const Color(0xFF928F99), // master outline
      buttonHover: scheme.primary.withValues(alpha: 0.12),
      buttonText1: scheme.primary, // master's TextButton/OutlinedButton fg
      buttonText2: const Color(0xFFE4DFFF), // master onPrimaryContainer
      onSurface: const Color(0xFFE5E1E9),
      // Master uses Colors.grey[600] (0xFF757575) here, and every muted
      // label in the app inherits it -- unselected nav items, sidebar rows,
      // hint text. Against the darkest chrome that lands at 3.7-4.3:1,
      // under the 4.5:1 floor for text, and because applyColorPalette
      // resets this role from the seed it dragged all eleven library
      // palettes under with it. Lifted just far enough to clear 4.5:1
      // against the lightest nav/sidebar background any of them use.
      onSurfaceVariant: const Color(0xFF8C8C94),
      navText: const Color(0xFF8C8C94),
      navAccent: scheme.primary,
      inputSelected: scheme.primary,
      inputResting: restingBorderFrom(scheme.primary, const Color(0xFF19172C)),
      inputBackground: Colors.transparent,
      navSelected: scheme.primary,
      headerBackground: const Color(0xFF19172C),
      sidebarText: const Color(0xFF8C8C94),
      sidebarAccent: scheme.primary,
      // The seam between panels: a line darker than the backgrounds it
      // separates, rather than a lighter one drawn on top of them. This is
      // what the "Default" palette card shows for Outline (the card is
      // built from this seed -- see color_palette_section.dart) and it must
      // stay equal to appThemes["dark"]'s extraColors.sidebarDivider and
      // colorScheme.outlineVariant, the values used when NO preset is
      // active: once any preset is, activePreset?.outline takes precedence
      // (see containers.dart's border color chains), so a mismatch shows up
      // as every border in the app shifting the moment a preset is applied.
      //
      // Deliberately very low contrast against the surfaces either side
      // (~1.1:1). An earlier pass raised this from Colors.black to master's
      // outlineVariant 0xFF47464F on the grounds that a divider should be
      // *visible*; in this app's chrome that reads as a pale rule drawn
      // over the panels rather than as the gap between them.
      outline: const Color(0xFF0D0D0D),
      // Master's dark-theme colorScheme.error. This was 0xFFBA1A1A --
      // M3's *light*-theme error, used unchanged on a near-black
      // background at 2.7:1. `error` is read directly as foreground here
      // (error messages, the hang-up-call icon); errorContainer is still
      // derived separately for surfaces, so this only has to be legible as
      // text, which the light value never was.
      error: const Color(0xFFFFB4AB),
      // 0xFF2D882D managed only 3.89:1 as foreground on this background.
      success: const Color(0xFF5BC46B),
    );
  }

  static ThemePreset seedFromLight() {
    var scheme = appThemes["light"]!.data.colorScheme;
    return ThemePreset(
      id: "custom",
      name: "Default Theme",
      brightness: Brightness.light,
      primary: const Color(0xFFE8E7F3),
      dualBackground: const Color(0xFFE8E7F3),
      contentBackground: const Color(0xFFE8E7F3),
      secondary: scheme.surfaceContainerLow,
      tertiary: const Color(0xFFF5F4FA),
      // Raised, not another near-white tier: 0xFFEDEBF5 was 1.04:1 against
      // primary, so toasts and the reply-preview box had no visible edge --
      // the same bug the dark seed's `fourth` had.
      fourth: const Color(0xFFAFB5D4),
      sidebarBackground: scheme.surfaceContainerLowest,
      speechBackground: const Color(0xFFF5F4FA),
      // Was a duplicate of the old `fourth`, 1.04:1 against primary.
      speechBackgroundSent: const Color(0xFFD0D6EE),
      // Master's light-theme container roles, same reasoning as the dark
      // seed above. All three are pale here, which is why buttonText2 goes
      // dark rather than near-white.
      accentContainer: const Color(0xFFDDE1FF), // master primaryContainer
      buttonBackgroundSecondary: const Color(0xFFFFDAD6), // errorContainer
      buttonBackgroundThird: const Color(0xFFDFE1F9), // secondaryContainer
      buttonBorderColor: const Color(0xFF767680), // master outline
      buttonHover: scheme.primary.withValues(alpha: 0.12),
      buttonText1: scheme.primary,
      buttonText2: const Color(0xFF384379), // master onPrimaryContainer
      onSurface: const Color(0xFF1B1B21),
      // Master's Colors.grey[600] is only 3.76:1 on this background --
      // see the dark seed's note. Darkened to clear 4.5:1.
      onSurfaceVariant: const Color(0xFF646468),
      navText: const Color(0xFF646468),
      navAccent: scheme.primary,
      inputSelected: scheme.primary,
      inputResting: restingBorderFrom(scheme.primary, const Color(0xFFE8E7F3)),
      inputBackground: Colors.transparent,
      navSelected: scheme.primary,
      headerBackground: const Color(0xFFE8E7F3),
      sidebarText: const Color(0xFF646468),
      sidebarAccent: scheme.primary,
      // Master's outlineVariant. Was Colors.white -- invisible on a
      // near-white page, the light-theme twin of the dark seed's black.
      outline: const Color(0xFFC6C5D0),
      error: const Color(0xFFBA1A1A), // master light-theme error
      // 0xFF2D882D was 3.67:1 on this background.
      success: const Color(0xFF166016),
    );
  }
}
