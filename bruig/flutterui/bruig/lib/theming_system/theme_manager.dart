// theme_manager.dart is the entry point to the theming system's *runtime*
// (as opposed to its models and its editor UI): everything a widget needs to
// read the active theme. It's a barrel over three files:
//
//   theme_tokens.dart   -- the named tokens widgets ask for (TextSize,
//                          TextColor, SurfaceColor) plus CustomColors/
//                          CustomTextStyles, font/image size options, and
//                          the base Inter text themes.
//   app_theme.dart      -- AppTheme (one compiled theme) and appThemes (the
//                          registry, holding the built-in dark/light/system
//                          entries plus any registered custom presets).
//   theme_notifier.dart -- ThemeNotifier, which owns the active theme,
//                          resolves tokens to colors, and manages custom
//                          ThemePresets.
//
// See theme_preset.dart for the editable model behind a custom theme, and
// theme_editor.dart for the Settings > Appearance UI that edits it.
export 'package:bruig/theming_system/app_theme.dart';
export 'package:bruig/theming_system/theme_notifier.dart';
export 'package:bruig/theming_system/theme_tokens.dart';
