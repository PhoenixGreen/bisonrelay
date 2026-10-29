import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// studio_colors.dart is the palette the sound side of Canvas is drawn in: the
// mixer, the effects, the timeline's channels and the instruments.
//
// Two ways to get it. Studio is a look of its own, dark and lit like a desk,
// and where everyone starts. Follow my theme asks the app's theme for every
// role instead, so a light theme gets a light mixer. Either way any one role
// can be changed by hand, in Settings > Plugins > Canvas -- which is where
// these live rather than among the app's theme areas, because the theming
// system is its own submission and Canvas is stacked on it, not part of it.
//
// Only what a state means is a colour of its own here -- on, solo, armed,
// the meter's three bands, a device's screen. Everything else is a surface or
// a text level, asked for by role.

/// StudioRole is one colour of the studio palette.
enum StudioRole {
  panel("Panel", "Behind the strips and devices"),
  strip("Strip", "Each channel, each device"),
  raised("Raised", "Headers, unlit buttons"),
  inset("Inset", "Boxes, meter slots"),
  edge("Edge", "Outlines"),
  text("Text", "Names and values"),
  muted("Muted text", "Labels"),
  on("On", "Switched on, sends, the fader's line"),
  solo("Solo", "Solo"),
  arm("Arm", "Armed to record"),
  meterLow("Meter", "A meter's safe band"),
  meterMid("Meter, hot", "Near the top"),
  meterHigh("Meter, clip", "Over the top"),
  display("Display", "EQ, compressor and reverb screens"),
  displayLine("Display line", "The curve on a screen");

  final String label;
  final String use;
  const StudioRole(this.label, this.use);
}

/// StudioLook is where the palette comes from.
enum StudioLook {
  studio("Studio"),
  theme("Follow my theme");

  final String label;
  const StudioLook(this.label);

  static StudioLook fromName(String? name) =>
      values.firstWhere((l) => l.name == name, orElse: () => studio);
}

class StudioColors {
  final Map<StudioRole, Color> _colors;
  const StudioColors._(this._colors);

  Color operator [](StudioRole role) => _colors[role]!;

  Color get panel => this[StudioRole.panel];
  Color get strip => this[StudioRole.strip];
  Color get raised => this[StudioRole.raised];
  Color get inset => this[StudioRole.inset];
  Color get edge => this[StudioRole.edge];
  Color get text => this[StudioRole.text];
  Color get muted => this[StudioRole.muted];
  Color get on => this[StudioRole.on];
  Color get solo => this[StudioRole.solo];
  Color get arm => this[StudioRole.arm];
  Color get meterLow => this[StudioRole.meterLow];
  Color get meterMid => this[StudioRole.meterMid];
  Color get meterHigh => this[StudioRole.meterHigh];
  Color get display => this[StudioRole.display];
  Color get displayLine => this[StudioRole.displayLine];

  /// onOn, onSolo and onArm are what is written on a lit button: dark on a
  /// light lamp, light on a dark one.
  Color get onOn => _ink(on);
  Color get onSolo => _ink(solo);
  Color get onArm => _ink(arm);

  /// unlit is a lamp that is off: the colour, much dimmed into the strip.
  Color unlit(Color lamp) => Color.lerp(strip, lamp, 0.22)!;

  static Color _ink(Color c) =>
      c.computeLuminance() > 0.4 ? const Color(0xFF15120A) : Colors.white;

  /// studio is the built-in look.
  static const StudioColors studio = StudioColors._({
    StudioRole.panel: Color(0xFF17181C),
    StudioRole.strip: Color(0xFF222429),
    StudioRole.raised: Color(0xFF2E3036),
    StudioRole.inset: Color(0xFF16171B),
    StudioRole.edge: Color(0xFF3A3D44),
    StudioRole.text: Color(0xFFE6E7EA),
    StudioRole.muted: Color(0xFFA3A9B3),
    StudioRole.on: Color(0xFFF2B33D),
    StudioRole.solo: Color(0xFF5AA9FF),
    StudioRole.arm: Color(0xFFFF5A5A),
    StudioRole.meterLow: Color(0xFF3CCF7A),
    StudioRole.meterMid: Color(0xFFF2B33D),
    StudioRole.meterHigh: Color(0xFFFF5A5A),
    StudioRole.display: Color(0xFF0F1A2E),
    StudioRole.displayLine: Color(0xFF5FD0FF),
  });

  /// fromScheme is the palette asked of the app's theme. Tertiary is not
  /// used: in this app it is a panel's fill, not an accent, and anything
  /// drawn in it vanishes into the panel behind.
  factory StudioColors.fromScheme(ColorScheme c) => StudioColors._({
        StudioRole.panel: c.surface,
        StudioRole.strip: c.surfaceContainer,
        StudioRole.raised: c.surfaceContainerHigh,
        StudioRole.inset: c.surfaceContainerLowest,
        StudioRole.edge: c.outlineVariant,
        StudioRole.text: c.onSurface,
        StudioRole.muted: c.onSurfaceVariant,
        StudioRole.on: c.primary,
        StudioRole.solo: c.secondary,
        StudioRole.arm: c.error,
        StudioRole.meterLow: studio.meterLow,
        StudioRole.meterMid: studio.meterMid,
        StudioRole.meterHigh: studio.meterHigh,
        StudioRole.display: c.brightness == Brightness.dark
            ? studio.display
            : Color.lerp(c.surfaceContainerLowest, c.primary, 0.08)!,
        StudioRole.displayLine: c.brightness == Brightness.dark
            ? studio.displayLine
            : c.primary,
      });

  /// resolve is the palette for [look] with [overrides] laid over it.
  static StudioColors resolve(StudioLook look, Map<StudioRole, Color> overrides,
      ColorScheme scheme) {
    var base = look == StudioLook.studio ? studio : StudioColors.fromScheme(scheme);
    if (overrides.isEmpty) return base;
    return StudioColors._({...base._colors, ...overrides});
  }

  /// scheme is this palette as a ColorScheme over [base], for the pieces
  /// of the mixer drawn from a scheme's roles -- surface, outline, primary.
  ColorScheme scheme(ColorScheme base) => base.copyWith(
        brightness: panel.computeLuminance() < 0.4
            ? Brightness.dark
            : Brightness.light,
        surface: panel,
        surfaceContainerLowest: inset,
        surfaceContainerLow: panel,
        surfaceContainer: strip,
        surfaceContainerHigh: raised,
        surfaceContainerHighest: raised,
        outline: edge,
        outlineVariant: edge,
        onSurface: text,
        onSurfaceVariant: muted,
        primary: on,
        onPrimary: onOn,
        secondary: solo,
        onSecondary: onSolo,
        error: arm,
        onError: onArm,
      );

  /// of is the palette in force where [context] is: the reader's choice,
  /// against the app's theme, changes followed.
  static StudioColors of(BuildContext context) {
    var prefs = Provider.of<CanvasPreferences?>(context);
    var scheme = Theme.of(context).colorScheme;
    if (prefs == null) return studio;
    return resolve(prefs.studioLook, prefs.studioOverrides, scheme);
  }
}

/// MixerLook is what the mixer's pieces are drawn in: the studio palette,
/// and the same as a scheme for the pieces that ask by role.
class MixerLook {
  final ColorScheme colors;
  final StudioColors studio;
  const MixerLook(this.colors, this.studio);

  static MixerLook of(BuildContext context) {
    var studio = StudioColors.of(context);
    return MixerLook(studio.scheme(Theme.of(context).colorScheme), studio);
  }
}
