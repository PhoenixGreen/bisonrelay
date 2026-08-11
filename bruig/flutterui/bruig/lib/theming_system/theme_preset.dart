// theme_preset.dart is the entry point to the theming system's *model* --
// the editable data behind a custom theme -- and a barrel over model/:
//
//   theme_area.dart        ThemeArea (which region of the app) + ContentAlign.
//   area_fill.dart         how a background/border layer is painted
//                          (AreaBackgroundMode, GradientDirection, AreaFill).
//   area_options.dart      the multiple-choice settings belonging to
//                          individual areas, grouped by area.
//   area_sides.dart        SideValues, a spacing setting split per side.
//   area_style.dart        AreaStyle, one area's complete set of overrides.
//   area_style_render.dart AreaStyle's rendering half -- resolving its colors
//                          and painting its background/border.
//   bubble_shape.dart      a chat bubble's corner settings as a ShapeBorder.
//   button_style.dart      the Buttons area's model: ButtonRole (which of the
//                          app's five buttons) and the overrides one carries,
//                          plus the code compiling them into a ButtonStyle.
//   color_contrast.dart    WCAG luminance/contrast maths.
//   color_hex.dart         the shared #AARRGGBB codec.
//   color_palette.dart     PaletteSlot, the fixed color roles a theme carries.
//   palette_library.dart   ColorPalette + the built-in palettes.
//   preset.dart            ThemePreset, one whole named/exportable theme.
//   preset_migrations.dart carrying presets written by an older build forward.
//   preset_theme.dart      compiling a ThemePreset into an AppTheme.
//
// See theme_manager.dart for the runtime that renders a compiled theme, and
// theme_editor.dart for the Settings > Appearance UI that edits one.
export 'package:bruig/theming_system/model/area_fill.dart';
export 'package:bruig/theming_system/model/area_options.dart';
export 'package:bruig/theming_system/model/area_sides.dart';
export 'package:bruig/theming_system/model/area_style.dart';
export 'package:bruig/theming_system/model/area_style_render.dart';
export 'package:bruig/theming_system/model/bubble_shape.dart';
export 'package:bruig/theming_system/model/button_style.dart';
export 'package:bruig/theming_system/model/color_contrast.dart';
export 'package:bruig/theming_system/model/color_hex.dart';
export 'package:bruig/theming_system/model/color_palette.dart';
export 'package:bruig/theming_system/model/markdown_guides.dart';
export 'package:bruig/theming_system/model/markdown_style.dart';
export 'package:bruig/theming_system/model/markdown_style_render.dart';
export 'package:bruig/theming_system/model/palette_library.dart';
export 'package:bruig/theming_system/model/preset.dart';
export 'package:bruig/theming_system/model/preset_migrations.dart';
export 'package:bruig/theming_system/model/preset_theme.dart';
export 'package:bruig/theming_system/model/theme_area.dart';
