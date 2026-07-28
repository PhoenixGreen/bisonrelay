// theme_preset.dart is the entry point to the theming system's *model*: the
// editable data behind a custom theme. It's a barrel over the pieces it's
// split into:
//
//   theme_area.dart     -- ThemeArea (which region of the app) + ContentAlign.
//   area_fill.dart      -- how a background/border layer is painted
//                          (AreaBackgroundMode, GradientDirection, AreaFill).
//   area_options.dart   -- the multiple-choice settings belonging to
//                          individual areas, grouped by area.
//   area_style.dart     -- AreaStyle, one area's complete set of overrides,
//                          plus the code that renders it.
//   color_palette.dart  -- PaletteSlot, the fixed color roles a theme carries.
//   preset.dart         -- ThemePreset, one whole named/exportable theme.
//   color_hex.dart      -- the shared #AARRGGBB codec.
//
// See theme_manager.dart for the runtime that renders a compiled theme, and
// theme_editor.dart for the Settings > Appearance UI that edits one.
export 'package:bruig/theming_system/area_fill.dart';
export 'package:bruig/theming_system/area_options.dart';
export 'package:bruig/theming_system/area_sides.dart';
export 'package:bruig/theming_system/area_style.dart';
export 'package:bruig/theming_system/bubble_shape.dart';
export 'package:bruig/theming_system/color_hex.dart';
export 'package:bruig/theming_system/color_palette.dart';
export 'package:bruig/theming_system/preset.dart';
export 'package:bruig/theming_system/theme_area.dart';
