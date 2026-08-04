import 'dart:io';

import 'package:flutter/material.dart';

// theme_tokens.dart holds the app's *vocabulary* for theming: the named
// color/size tokens widgets ask for (TextSize/TextColor/SurfaceColor), the
// extra non-Material colors and text styles an AppTheme carries, and the
// base Inter text themes. Nothing here resolves a token to an actual color
// -- that's ThemeNotifier's job (see theme_notifier.dart).

enum TextSize {
  small, // label.medium (12pt).
  system, // Default text size when no size is specified.
  medium, // body.medium / label.large. (14 pt).
  large, // body.large / title.medium (16 pt).
  huge, // title.large (22 pt).
}

// fontSize returns the font size to use given the text size token. When null is
// passed to size, a null font size ("default" size) is returned.
double? fontSize(TextSize? size) {
  switch (size) {
    case TextSize.small:
      return 12;
    case TextSize.system:
      return null;
    case TextSize.medium:
      return 14;
    case TextSize.large:
      return 16;
    case TextSize.huge:
      return 22;
    case null:
      return null;
  }
}

enum TextColor {
  onPrimary,
  onSecondary,
  onTertiary,
  onError,

  onPrimaryContainer,
  onSecondaryContainer,
  onTertiaryContainer,
  onErrorContainer,

  onSurface, // Default text color.
  onSurfaceVariant,

  onInverseSurface,
  inversePrimary, // Used as text when the surface is inverseSurface.

  onPrimaryFixed,
  onPrimaryFixedVariant,
  onSecondaryFixed,
  onSecondaryFixedVariant,
  onTertiaryFixed,
  onTertiaryFixedVariant,

  error, // Used when only the text is displayed as error.
  successOnSurface, // Used for displaying a successful message on top of a surface
}

// SurfaceColor are colors used on surfaces/containers/background.
enum SurfaceColor {
  // Main component action colors.
  primary,
  secondary,
  tertiary,
  error,

  // Main container background colors.
  primaryContainer,
  secondaryContainer,
  tertiaryContainer,
  errorContainer,

  // Secondary surface background colors.
  surface, // Default background color.
  surfaceContainerLowest,
  surfaceContainerLow,
  surfaceContainer,
  surfaceContainerHigh,
  surfaceContainerHighest,

  // Surface variants.
  surfaceBright,
  surfaceDim,

  // Inverse colors.
  inverseSurface,
  inversePrimary,

  // These are rarely used.
  primaryFixed,
  primaryFixedDim,
  secondaryFixed,
  secondaryFixedDim,
  tertiaryFixed,
  tertiaryFixedDim,
}

// CustomColors are the handful of app-specific colors that have no
// equivalent role in Material's ColorScheme.
class CustomColors {
  final Color sidebarDivider;
  final Color successOnSurface;
  final Color selectedItemOnSurfaceListView;

  const CustomColors({
    this.sidebarDivider = Colors.black,
    this.successOnSurface = const Color(0xFF2D882D),
    this.selectedItemOnSurfaceListView = Colors.amber,
  });
}

class CustomTextStyles {
  // Used on the small "gc" indicator on the list of chats.
  final TextStyle chatListGcIndicator;

  // Used on the nick initial on CircleAvatar (when the avatar color is
  // light or dark).
  final TextStyle lightAvatarInitial;
  final TextStyle darkAvatarInitial;
  final TextStyle lightAvatarInitialLarge;
  final TextStyle darkAvatarInitialLarge;

  final TextStyle monospaced;

  const CustomTextStyles({
    this.chatListGcIndicator = const TextStyle(),
    this.lightAvatarInitial =
        const TextStyle(fontSize: 16, color: Color(0xFF0E0D0D)),
    this.darkAvatarInitial =
        const TextStyle(fontSize: 16, color: Color(0xC0FCFCFC)),
    this.lightAvatarInitialLarge =
        const TextStyle(fontSize: 50, color: Color(0xFF0E0D0D)),
    this.darkAvatarInitialLarge =
        const TextStyle(fontSize: 50, color: Color(0xC0FCFCFC)),
    this.monospaced = const TextStyle(fontFamily: "RobotoMono"),
  });
}

// textColorForSurfaceColor maps a background color token to its
// corresponding text color ("on" color).
const Map<SurfaceColor, TextColor> textColorForSurfaceColor = {
  SurfaceColor.primary: TextColor.onPrimary,
  SurfaceColor.secondary: TextColor.onSecondary,
  SurfaceColor.tertiary: TextColor.onTertiary,
  SurfaceColor.error: TextColor.onError,
  SurfaceColor.primaryContainer: TextColor.onPrimaryContainer,
  SurfaceColor.secondaryContainer: TextColor.onSecondaryContainer,
  SurfaceColor.tertiaryContainer: TextColor.onTertiaryContainer,
  SurfaceColor.errorContainer: TextColor.onErrorContainer,
  SurfaceColor.surface: TextColor.onSurface,
  SurfaceColor.surfaceContainerLowest: TextColor.onSurface,
  SurfaceColor.surfaceContainerLow: TextColor.onSurface,
  SurfaceColor.surfaceContainer: TextColor.onSurface,
  SurfaceColor.surfaceContainerHigh: TextColor.onSurface,
  SurfaceColor.surfaceContainerHighest: TextColor.onSurface,
  SurfaceColor.surfaceBright: TextColor.onSurface,
  SurfaceColor.surfaceDim: TextColor.onSurface,
  SurfaceColor.inverseSurface: TextColor.onInverseSurface,
  SurfaceColor.inversePrimary: TextColor.onSurface,
  SurfaceColor.primaryFixed: TextColor.onPrimaryFixed,
  SurfaceColor.primaryFixedDim: TextColor.onPrimaryFixed,
  SurfaceColor.secondaryFixed: TextColor.onSecondaryFixed,
  SurfaceColor.secondaryFixedDim: TextColor.onSecondaryFixed,
  SurfaceColor.tertiaryFixed: TextColor.onTertiaryFixed,
  SurfaceColor.tertiaryFixedDim: TextColor.onTertiaryFixed,
};

class AppFontSize {
  final String descr;
  final double scale;

  AppFontSize({required this.descr, required this.scale});
}

// Available global text rescaling factors.
final Map<String, AppFontSize> appFontSizes = {
  "system":
      AppFontSize(descr: "System default", scale: -1), // OS-level scaling.
  "xsmall": AppFontSize(descr: "Extra Small", scale: 0.65),
  "small": AppFontSize(descr: "Small", scale: 0.85),
  "medium": AppFontSize(descr: "Medium", scale: 1.15),
  "large": AppFontSize(descr: "Large", scale: 1.25),
  "xlarge": AppFontSize(descr: "Extra Large", scale: 1.5),
};

String appFontSizeKeyForScale(double scale) {
  var key = "system";
  appFontSizes.forEach((k, v) {
    if (v.scale == scale) {
      key = k;
    }
  });
  return key;
}

class AppImageSize {
  final String descr;

  AppImageSize({required this.descr});
}

// Available chat image display sizes.
final Map<String, AppImageSize> appImageSizes = {
  "default": AppImageSize(descr: "Default"),
  "half": AppImageSize(descr: "Half width"),
  "full": AppImageSize(descr: "Full width"),
};

const String defaultChatImageSize = "default";

String emojifont = Platform.isWindows ? "notoemoji_win" : "notoemoji_unix";

// _interTheme builds the full Inter TextTheme with a single flat text color.
// Both variants below previously spelled out all 15 styles by hand (30
// near-identical TextStyle literals); the only real difference between them
// is the color, and within the black variant, display/headlineLarge/
// headlineMedium used black54 while everything else used black87.
TextTheme _interTheme(Color color, {Color? mutedColor}) {
  TextStyle style(String label, Color c) => TextStyle(
      debugLabel: 'inter$label',
      fontFamily: 'Inter',
      decoration: TextDecoration.none,
      color: c,
      fontFamilyFallback: [emojifont]);
  var muted = mutedColor ?? color;
  return TextTheme(
    displayLarge: style('displayLarge', muted),
    displayMedium: style('displayMedium', muted),
    displaySmall: style('displaySmall', muted),
    headlineLarge: style('headlineLarge', muted),
    headlineMedium: style('headlineMedium', muted),
    headlineSmall: style('headlineSmall', color),
    titleLarge: style('titleLarge', color),
    titleMedium: style('titleMedium', color),
    titleSmall: style('titleSmall', color),
    bodyLarge: style('bodyLarge', color),
    bodyMedium: style('bodyMedium', color),
    bodySmall: style('bodySmall', color),
    labelLarge: style('labelLarge', color),
    labelMedium: style('labelMedium', color),
    labelSmall: style('labelSmall', color),
  );
}

final TextTheme interTextTheme = _interTheme(Colors.white70);
final TextTheme interBlackTextTheme =
    _interTheme(Colors.black87, mutedColor: Colors.black54);
