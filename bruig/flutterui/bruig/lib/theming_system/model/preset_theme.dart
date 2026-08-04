import 'package:bruig/theming_system/model/area_style.dart';
import 'package:bruig/theming_system/model/button_style.dart';
import 'package:bruig/theming_system/model/preset.dart';
import 'package:bruig/theming_system/model/theme_area.dart';
import 'package:bruig/theming_system/runtime/app_theme.dart';
import 'package:bruig/theming_system/runtime/theme_tokens.dart';
import 'package:flutter/material.dart';

// preset_theme.dart compiles a ThemePreset into an AppTheme -- the step
// between the editable model (preset.dart) and the runtime that renders it
// (runtime/app_theme.dart). It's an extension rather than a method on
// ThemePreset so the model itself carries no dependency on the compiled
// theme.
extension ThemePresetTheme on ThemePreset {
  Color _darken(Color c, double amount) {
    var hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  // toAppTheme compiles this preset into an AppTheme using exactly the same
  // ColorScheme.fromSeed()+copyWith() formula the built-in "dark"/"light"
  // themes are hand-written with (see appThemes), so custom presets render
  // through the same pipeline the rest of the app already trusts.
  //
  // It deliberately does NOT force secondary (or most Material-derived
  // roles) into ColorScheme.fromSeed -- those roles drive the foreground of
  // many standard Material widgets, and forcing them to the user's raw
  // palette swatch can produce illegible text-on-background. `primary` (the
  // seed), `tertiary`, `error`, and `onSurface` are safe to pass through
  // directly since ColorScheme.fromSeed independently derives a full,
  // properly-contrasting tonal ramp (onTertiary/tertiaryContainer/onError/
  // errorContainer/etc.) from each -- the same way `surface` already was.
  // `onSurface` in particular is what "On surface text" actually needs to
  // drive general app text/icon color (most Text/Icon widgets read
  // colorScheme.onSurface when given no explicit color) -- without passing
  // it here, editing that palette slot had no visible effect anywhere.
  AppTheme toAppTheme() {
    // interTextTheme/interBlackTextTheme hardcode Colors.white70/black54 on
    // every style -- reused as-is, a plain Text widget with no explicit
    // color (i.e. most of them; only this app's own Txt component with an
    // explicit TextColor reads colorScheme.onSurface directly) would never
    // reflect a custom preset's "On surface text" pick at all, regardless
    // of the colorScheme.onSurface override below. .apply() recolors every
    // style to the preset's own onSurface instead.
    var textTheme =
        (brightness == Brightness.dark ? interTextTheme : interBlackTextTheme)
            .apply(displayColor: onSurface, bodyColor: onSurface);
    // The five button roles, compiled once here so the ThemeData button
    // themes below and this app's own button widgets (raisedButtonStyle,
    // CancelButton -- see components/buttons.dart) all render from the same
    // resolved values instead of each re-deriving them.
    var buttons = buildButtonStyles(
      overrides: (areas[ThemeArea.buttons] ?? const AreaStyle()).buttonStyles,
      palette: palette,
      colors: buttonPaletteColors,
    );

    var data = ThemeData.from(
      useMaterial3: true,
      textTheme: textTheme,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: brightness,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        // colorScheme.outline is what OutlinedButton's own default M3
        // border reads (plus a few of this app's own custom button
        // styles) -- pinned to `buttonBorderColor`, since a clickable
        // button's edge needs to stand out against the background, unlike
        // a plain divider. It used to be pinned to navAccent, which meant
        // the nav bar's accent and every button's border were one color
        // that couldn't be tuned apart; buttonBorderColor seeds from
        // navAccent so nothing moves until it's deliberately changed.
        outline: buttonBorderColor,
        // colorScheme.outlineVariant is the separate, subtler Material
        // role that this app's own panel/card/divider borders read
        // (Settings' left-nav panel border, Manage Content's card border,
        // the emoji picker's category icons, the About page border, the
        // feed post-detail divider) -- pinned to `outline`, the
        // blend-with-background field. Previously neither role was pinned
        // at all, so every one of these borders (buttons included) showed
        // Material's auto-derived tonal color regardless of what the user
        // picked; now the two palette fields cleanly map to the two roles
        // instead of colliding on one.
        outlineVariant: outline,
        surface: primary,
        surfaceContainerLow: _darken(primary, 0.012),
        surfaceContainerLowest: _darken(primary, 0.022),
        // Continues the same explicit elevation ladder as
        // surfaceContainerLow/Lowest above, rather than leaving these 3
        // tiers to Material's own tonal derivation -- otherwise any
        // unthemed Card/Container that reads one of these (several plain
        // settings panels do) shows the same unpredictable seed-derived
        // tint described above instead of a shade of the actual chosen
        // Primary color.
        surfaceContainer: _darken(primary, 0.006),
        surfaceContainerHigh: _darken(primary, 0.0),
        surfaceContainerHighest: _darken(primary, -0.01),
        tertiary: tertiary,
        // Only `error` (not errorContainer/onErrorContainer) is pinned --
        // same reasoning as tertiary/surface above: ColorScheme.fromSeed
        // independently derives a properly-contrasting errorContainer/
        // onErrorContainer pair from this seed. Previously errorContainer
        // was force-pinned to the exact same flat value as `error` (with
        // onErrorContainer force-pinned to onSurface) because CancelButton
        // read errorContainer for its background -- collapsing Material's
        // normal two-tier tonal system (a brighter `error` for text/icons
        // directly on the background vs. a darker `errorContainer` for
        // surfaces with light text on top) into one flat color that
        // couldn't satisfy both contrast needs at once. Now that
        // CancelButton no longer uses errorContainer (see accentContainer's
        // doc), only genuine error-surface call sites (snackbar error
        // background, failed-upload/unsupported-GC-version event cards)
        // read it, so letting Material derive it properly is strictly
        // better than a hand-pinned flat value.
        error: error,
        // Without this, ColorScheme.fromSeed computes its own tonal
        // derivation of "primary" from the seed rather than using the
        // literal color -- every other unthemed Material widget that falls
        // back to colorScheme.primary (default OutlinedButton/TextButton
        // foreground, container backgrounds, etc.) then shows that
        // computed tone instead of anything the user actually picked. That
        // tone is also unpredictable at the extremes: a fully desaturated
        // seed (e.g. pure black "Primary") has no well-defined hue, and
        // Material's algorithm can resolve it to an unrelated, oddly-tinted
        // color (seen here as a washed-out pink). navAccent is what this
        // app treats as its actual "accent" role, so pinning
        // colorScheme.primary to it keeps every unthemed widget visually
        // consistent with the app's own accent instead of a hidden,
        // seed-derived one.
        primary: navAccent,
        // onPrimary had the exact same never-pinned problem -- Material's
        // default Switch uses it for the ON-state thumb color (track is
        // colorScheme.primary, already pinned above), so it showed the
        // same kind of stray, unpredictable tint (a dark maroon) with no
        // palette field to control it from.
        onPrimary: onSurface,
        // primaryContainer/secondary/secondaryContainer had the exact same
        // problem as primary above, just never pinned at all -- Material's
        // default Switch (track+thumb) and FilledButton.tonal both read
        // one of these, and showed the same stray, unpredictable
        // seed-derived tint (see accentContainer's doc) with no palette
        // field to control it from.
        primaryContainer: accentContainer,
        secondary: accentContainer,
        secondaryContainer: accentContainer,
        onPrimaryContainer: onSurface,
        onSecondary: onSurface,
        onSecondaryContainer: onSurface,
      ),
    ).copyWith(
      // DropdownButton's popup menu (e.g. the Theme Areas section's select)
      // falls back to canvasColor when no explicit dropdownColor is set
      // (true everywhere in this app) -- this connects it to "Primary"
      // without needing to touch every DropdownButton call site.
      canvasColor: primary,
      // The three roles Material's own widgets render: Plain covers both
      // the plain ElevatedButton and TextButton (they look identical --
      // no fill, no border, just a hover), Outlined every OutlinedButton,
      // and Tonal both FilledButton variants. The other two roles belong
      // to this app's own widgets and are read off AppTheme.buttonStyles
      // instead, since there's no ThemeData slot for them.
      elevatedButtonTheme:
          ElevatedButtonThemeData(style: buttons[ButtonRole.plain]),
      textButtonTheme: TextButtonThemeData(style: buttons[ButtonRole.plain]),
      outlinedButtonTheme:
          OutlinedButtonThemeData(style: buttons[ButtonRole.outlined]),
      filledButtonTheme:
          FilledButtonThemeData(style: buttons[ButtonRole.tonal]),
      // Inputs read colorScheme.primary for their focused border, which is
      // pinned to navAccent above -- so every text field in the app took
      // the nav bar's selected-item colour whether that suited it or not.
      // inputSelected is its own slot precisely so it doesn't have to.
      inputDecorationTheme: InputDecorationTheme(
        focusColor: inputSelected,
        // The plain underline inputs (Cost, Description, the settings
        // fields) get the same two states as the outlined ones: resting
        // colour at rest, Input Color on focus.
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: inputResting),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: inputSelected, width: 2),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        selectedTileColor:
            brightness == Brightness.dark ? Colors.grey[850] : Colors.grey[100],
        iconColor: onSurface,
      ),
      hintColor: onSurface.withValues(alpha: 0.6),
      appBarTheme: AppBarTheme(
        backgroundColor: headerBackground,
        scrolledUnderElevation: 0,
      ),
      disabledColor: Colors.grey[850],
    );

    return AppTheme(
      key: "custom:$id",
      descr: name,
      data: data,
      extraColors: CustomColors(
        successOnSurface: success,
        sidebarDivider: outline,
        selectedItemOnSurfaceListView: sidebarAccent,
      ),
      extraTextStyles: CustomTextStyles(
        chatListGcIndicator: TextStyle(
          fontStyle: FontStyle.italic,
          color: onSurface.withValues(alpha: 0.6),
        ),
      ),
      buttonStyles: buttons,
      areaStyles: areas,
      presetDir: sourceDir,
    );
  }
}
