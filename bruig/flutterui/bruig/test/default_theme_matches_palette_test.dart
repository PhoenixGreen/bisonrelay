import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// default_theme_matches_palette_test.dart pins the built-in "Default Theme"
// to the "Default" color palette.
//
// They are two hand-maintained copies of one design: appThemes["dark"] is
// what renders with no preset active, and ThemePreset.seedFromDark() is both
// the starting point for a custom preset and the palette card labelled
// "Default" (see color_palette_section.dart, which builds that card from
// this seed). Any role where they disagree is a color that visibly jumps the
// instant a user touches anything in Appearance -- which is how the divider
// tone drifted apart in the first place.

void main() {
  var seed = ThemePreset.seedFor(Brightness.dark);
  var theme = appThemes["dark"]!;
  var scheme = theme.data.colorScheme;

  test('the divider tone is the palette Outline swatch everywhere', () {
    // The three places a panel seam is read from, with and without a
    // preset -- see containers.dart and components/sidebar.dart.
    expect(theme.extraColors.sidebarDivider, seed.outline);
    expect(scheme.outlineVariant, seed.outline);
  });

  test('the button edge is the palette Button Border swatch', () {
    // The other outline role, deliberately a separate slot -- see
    // ThemePreset.toAppTheme().
    expect(scheme.outline, seed.buttonBorderColor);
    expect(theme.buttonStyles, isNotNull);
  });

  test('the surfaces and text tones match the palette', () {
    expect(scheme.surface, seed.primary);
    expect(scheme.tertiary, seed.tertiary);
    expect(scheme.onSurface, seed.onSurface);
    expect(scheme.onSurfaceVariant, seed.onSurfaceVariant);
    expect(scheme.primaryContainer, seed.accentContainer);
    expect(theme.extraColors.successOnSurface, seed.success);
    expect(scheme.error, seed.error);
  });

  test('the nav and sidebar fallbacks match the palette', () {
    // These roles are not in the ColorScheme -- with no preset active the
    // widgets fall back to a Material role instead (see sidebar.dart's
    // `activePreset?.navText ?? theme.colors.onSurfaceVariant` chains and
    // mobile_nav_bar.dart's copies of them). The fallback has to land on
    // the same color the palette names, or applying a preset shifts it.
    expect(scheme.onSurfaceVariant, seed.navText, reason: "nav text");
    expect(scheme.onSurfaceVariant, seed.sidebarText, reason: "sidebar text");
    expect(scheme.primary, seed.navSelected, reason: "nav selected");
    expect(scheme.primary, seed.sidebarAccent, reason: "sidebar accent");
    expect(scheme.surfaceContainerLow, seed.secondary,
        reason: "nav background");
    expect(scheme.surfaceContainerLowest, seed.sidebarBackground,
        reason: "sidebar background");
  });
}
