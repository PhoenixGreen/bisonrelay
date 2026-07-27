import 'package:bruig/theming_system/area_style.dart';
import 'package:bruig/theming_system/theme_area.dart';
import 'package:bruig/theming_system/theme_tokens.dart';
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

// _startupGradient is the soft corner-to-corner fade painted behind the
// startup/login screen's own content.
BoxDecoration _startupGradient(Color base, List<double> alphas) => BoxDecoration(
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

          // Color scheme customizations
          onSurfaceVariant: Colors.grey[600],
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
          // Matches this seed's own colorScheme.primary (0xFFC6BFFF, the
          // tonal-derived value navAccent/accentContainer both read via
          // ThemePreset.seedFromDark()) -- without this,
          // primaryContainer/secondary/secondaryContainer are each left to
          // their own independent tonal derivation from the seed, which
          // doesn't reliably land on the same color, so Material's default
          // Switch/FilledButton.tonal/snackbar could show yet another
          // stray tint even on the untouched, no-custom-preset app.
          primaryContainer: const Color(0xFFC6BFFF),
          secondary: const Color(0xFFC6BFFF),
          secondaryContainer: const Color(0xFFC6BFFF),
        ),
      ).copyWith(
        // Bruig theme customizations.
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
      extraColors: const CustomColors(),
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
          onSurfaceVariant: Colors.grey[600],
          surface: const Color(0xFFE8E7F3),
          surfaceContainerLow: const Color(0xFFE6E5F2),
          surfaceContainerLowest: const Color(0xFFE2E1ED),
          // Matches ThemePreset.seedFromLight()'s tertiary -- see the dark
          // theme's comment above.
          tertiary: const Color(0xFFF5F4FA),
          // Matches this seed's own colorScheme.primary (0xFF4F5B92) -- see
          // the dark theme's primaryContainer/secondary/secondaryContainer
          // comment above.
          primaryContainer: const Color(0xFF4F5B92),
          secondary: const Color(0xFF4F5B92),
          secondaryContainer: const Color(0xFF4F5B92),
        ),
      ).copyWith(
        // Bruig theme customizations.
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
        sidebarDivider: Colors.white,
        selectedItemOnSurfaceListView: Color(0xFFFF6F00),
      ),
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
