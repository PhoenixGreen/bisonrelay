import 'package:bruig/theming_system/model/area_style.dart';
import 'package:bruig/theming_system/model/button_style.dart';
import 'package:bruig/theming_system/model/theme_area.dart';
import 'package:bruig/theming_system/runtime/theme_tokens.dart';
import 'package:flutter/material.dart';

// AppTheme is one fully-compiled, ready-to-render theme: Material's own
// ThemeData plus this app's extra colors/text styles and (for a custom
// ThemePreset) its per-area style overrides. The built-in dark/light themes
// are hand-written below; custom presets compile into the same shape via
// ThemePreset.toAppTheme().
class AppTheme {
  final String key;
  final String descr;
  final ThemeData data;
  final CustomColors extraColors;
  final CustomTextStyles extraTextStyles;

  // Decoration used to fade the background in StartupScreen components.
  final BoxDecoration? startupScreenBoxDecoration;

  // The five button roles, already compiled (see button_style.dart). Three
  // of them are also installed into `data`'s own button themes; Primary and
  // Danger have no ThemeData slot, so this is where components/buttons.dart
  // reads them from.
  final Map<ButtonRole, ButtonStyle> buttonStyles;

  // Per-area style overrides from a user-defined ThemePreset. Empty for the
  // built-in "dark"/"light"/"system" themes, meaning every area falls back to
  // its normal (pre-theming-feature) token-based rendering.
  final Map<ThemeArea, AreaStyle> areaStyles;

  // Directory a custom preset's areaStyles image paths are relative to. Null
  // for built-in themes (which never reference preset-relative images).
  final String? presetDir;

  AppTheme({
    required this.key,
    required this.descr,
    required this.data,
    required this.extraColors,
    required this.extraTextStyles,
    this.startupScreenBoxDecoration,
    this.buttonStyles = const {},
    this.areaStyles = const {},
    this.presetDir,
  });

  factory AppTheme.empty() => AppTheme(
      key: "",
      descr: "",
      data: ThemeData(),
      extraColors: const CustomColors(),
      extraTextStyles: const CustomTextStyles());
}

// _darkButtonColors/_lightButtonColors are the built-in themes' equivalent
// of a preset's Button Colors palette row. They're spelled out here (rather
// than read off the ColorScheme) because three of the seven -- the two extra
// fills and the second label color -- have no Material role behind them;
// they must match ThemePreset.seedFromDark/seedFromLight's own values, or
// the app would visibly recolor its buttons the moment any preset became
// active.
const _darkButtonColors = ButtonPaletteColors(
  primaryBackground: Color(0xFF454077),
  secondaryBackground: Color(0xFF93000A),
  thirdBackground: Color(0xFF474459),
  border: Color(0xFF928F99),
  hover: Color(0x1FC6BFFF),
  text1: Color(0xFFC6BFFF),
  text2: Color(0xFFE4DFFF),
);

const _lightButtonColors = ButtonPaletteColors(
  primaryBackground: Color(0xFFDDE1FF),
  secondaryBackground: Color(0xFFFFDAD6),
  thirdBackground: Color(0xFFDFE1F9),
  border: Color(0xFF767680),
  hover: Color(0x1F4F5B92),
  text1: Color(0xFF4F5B92),
  text2: Color(0xFF384379),
);

// _builtinButtonStyles compiles a built-in theme's buttons. There's no
// ThemePreset (and so no Buttons theme area) behind these, so every role
// takes its palette default.
Map<ButtonRole, ButtonStyle> _builtinButtonStyles(ButtonPaletteColors c) =>
    buildButtonStyles(overrides: const {}, palette: const [], colors: c);

final _darkButtonStyles = _builtinButtonStyles(_darkButtonColors);
final _lightButtonStyles = _builtinButtonStyles(_lightButtonColors);

// _startupGradient is the soft corner-to-corner fade painted behind the
// startup/login screen's own content.
BoxDecoration _startupGradient(Color base, List<double> alphas) =>
    BoxDecoration(
        gradient: LinearGradient(
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
      colors: [for (var a in alphas) base.withValues(alpha: a)],
      stops: const [0, 0.37, 1],
    ));

final appThemes = {
  "dark": AppTheme(
      key: "dark",
      descr: "Dark Theme",
      data: ThemeData.from(
        // Base Material3 color scheme based on seed
        useMaterial3: true,
        textTheme: interTextTheme,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF19172C),
          brightness: Brightness.dark,

          // Color scheme customizations. onSurfaceVariant was
          // Colors.grey[600], which is under 4.5:1 against this app's
          // chrome -- see ThemePreset.seedFromDark()'s note. Must match
          // that seed, or muted text shifts when a preset is applied.
          onSurfaceVariant: const Color(0xFF8C8C94),
          surface: const Color(0xFF19172C),
          surfaceContainerLow: const Color(0xFF17152A),
          surfaceContainerLowest: const Color(0xFF161429),
          // Matches ThemePreset.seedFromDark()'s tertiary exactly -- without
          // this, colorScheme.tertiary is left to Material's own tonal
          // derivation from the seed, which doesn't equal the "Default
          // Theme" palette card's tertiary swatch (nor, therefore, the
          // Settings group panels / Feed post cards that read
          // colorScheme.tertiary directly).
          tertiary: const Color(0xFF232030),
          // Matches ThemePreset.seedFromDark()'s accentContainer ("Button
          // Background Primary") exactly -- without this,
          // primaryContainer/secondary/secondaryContainer are each left to
          // their own independent tonal derivation from the seed, which
          // doesn't reliably land on the same color, so Material's default
          // Switch/snackbar could show yet another stray tint even on the
          // untouched, no-custom-preset app. These were pinned to
          // colorScheme.primary (0xFFC6BFFF, a near-white lavender) before
          // accentContainer became a button fill in its own right; at that
          // lightness nothing legible could sit on top of it.
          primaryContainer: const Color(0xFF454077),
          secondary: const Color(0xFF454077),
          secondaryContainer: const Color(0xFF454077),
        ),
      ).copyWith(
        // Bruig theme customizations.
        elevatedButtonTheme:
            ElevatedButtonThemeData(style: _darkButtonStyles[ButtonRole.plain]),
        textButtonTheme:
            TextButtonThemeData(style: _darkButtonStyles[ButtonRole.plain]),
        outlinedButtonTheme: OutlinedButtonThemeData(
            style: _darkButtonStyles[ButtonRole.outlined]),
        filledButtonTheme:
            FilledButtonThemeData(style: _darkButtonStyles[ButtonRole.tonal]),
        listTileTheme: ListTileThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
          selectedTileColor: Colors.grey[850],
          iconColor: const Color(0xFFe5e1e9), // onSurface
        ),

        hintColor: const Color(0xFF47464f), // onSurfaceVariant
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF19172C), // suface color.
          scrolledUnderElevation:
              0, // Disable the scroll shadow effect on appbar
        ),

        disabledColor: Colors.grey[850],
      ),
      // sidebarDivider/successOnSurface must equal ThemePreset
      // .seedFromDark()'s own outline/success -- see the note there.
      extraColors: const CustomColors(
        sidebarDivider: Color(0xFF47464F),
        successOnSurface: Color(0xFF5BC46B),
      ),
      buttonStyles: _darkButtonStyles,
      extraTextStyles: const CustomTextStyles(
        chatListGcIndicator: TextStyle(
          fontStyle: FontStyle.italic,
          color: Color(0xFF47464f), // onSurfaceVariant
        ),
      ),
      startupScreenBoxDecoration:
          _startupGradient(const Color(0xFF19172C), const [1, 0.85, 0.34])),
  "light": AppTheme(
      key: "light",
      descr: "Light Theme",
      data: ThemeData.from(
        // Base Material3 color scheme based on seed
        useMaterial3: true,
        textTheme: interBlackTextTheme,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE8E7F3),
          brightness: Brightness.light,

          // Color scheme customizations
          onSurfaceVariant: const Color(0xFF646468), // see the dark theme
          surface: const Color(0xFFE8E7F3),
          surfaceContainerLow: const Color(0xFFE6E5F2),
          surfaceContainerLowest: const Color(0xFFE2E1ED),
          // Matches ThemePreset.seedFromLight()'s tertiary -- see the dark
          // theme's comment above.
          tertiary: const Color(0xFFF5F4FA),
          // Matches this seed's own colorScheme.primary (0xFF4F5B92) -- see
          // the dark theme's primaryContainer/secondary/secondaryContainer
          // comment above.
          primaryContainer: const Color(0xFFDDE1FF),
          secondary: const Color(0xFFDDE1FF),
          secondaryContainer: const Color(0xFFDDE1FF),
        ),
      ).copyWith(
        // Bruig theme customizations.
        elevatedButtonTheme: ElevatedButtonThemeData(
            style: _lightButtonStyles[ButtonRole.plain]),
        textButtonTheme:
            TextButtonThemeData(style: _lightButtonStyles[ButtonRole.plain]),
        outlinedButtonTheme: OutlinedButtonThemeData(
            style: _lightButtonStyles[ButtonRole.outlined]),
        filledButtonTheme:
            FilledButtonThemeData(style: _lightButtonStyles[ButtonRole.tonal]),
        listTileTheme: ListTileThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
          selectedTileColor: Colors.grey[100],
          iconColor: const Color(0xFF45464F), // onSurface
        ),

        hintColor: const Color(0xFF45464F), // onSurfaceVariant
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFE8E7F3), // suface color.
          scrolledUnderElevation:
              0, // Disable the scroll shadow effect on appbar
        ),

        disabledColor: Colors.grey[850],
      ),
      extraColors: const CustomColors(
        // Matches ThemePreset.seedFromLight()'s outline/success/
        // sidebarAccent. sidebarDivider was Colors.white -- invisible on a
        // near-white page -- and the selected-item amber matched nothing
        // else in the light theme.
        sidebarDivider: Color(0xFFC6C5D0),
        successOnSurface: Color(0xFF166016),
        selectedItemOnSurfaceListView: Color(0xFF4F5B92),
      ),
      buttonStyles: _lightButtonStyles,
      extraTextStyles: const CustomTextStyles(
        chatListGcIndicator: TextStyle(
          fontStyle: FontStyle.italic,
          color: Color(0xFF45464F), // onSurfaceVariant
        ),
      ),
      startupScreenBoxDecoration:
          _startupGradient(const Color(0xFFE8E7F3), const [1, 0.95, 0.95])),
  "system": AppTheme(
    key: "system",
    descr: "Use System Default",
    data: ThemeData(),
    extraColors: const CustomColors(),
    extraTextStyles: const CustomTextStyles(),
  ),
};

const String defaultThemeName = "dark"; // This MUST exist in the map above.
