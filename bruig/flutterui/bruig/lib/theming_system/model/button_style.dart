import 'package:bruig/theming_system/model/area_sides.dart';
import 'package:bruig/theming_system/model/color_hex.dart';
import 'package:flutter/material.dart';

// button_style.dart is the "Buttons" theme area's own model: which kinds of
// button the app actually has (ButtonRole), the overrides one of them can
// carry (ButtonAreaStyle), and the code that compiles a role + the palette's
// button colors into the ButtonStyle the widgets render through
// (buildButtonStyles).
//
// The five roles are the five visually distinct buttons Bison Relay ships --
// they were already there, just spread across Material's own button widgets
// and this app's own wrappers with no single place to tune them.

// ButtonRole is one of the app's five button appearances. The names are
// deliberately about what a button *looks like*, not where it's used: the
// same role turns up on the login screen, in the feed and in LN management.
enum ButtonRole {
  // Filled with the palette's Button Background Primary. The login screen's
  // Unlock Wallet / Create Wallet actions -- see raisedButtonStyle.
  primary,
  // No fill and no border, just a hover background. Every plain
  // ElevatedButton and TextButton: Network Config, Export Logs, Settings,
  // Open Outbound Channel, Open/Remove, Create.
  plain,
  // No fill, but a border. Every OutlinedButton: Read More, Add Comment,
  // Add Embed, Generate Address, Send On-Chain, Rescan Wallet, Accept.
  outlined,
  // Filled with the palette's Third Background Color. FilledButton and
  // FilledButton.tonal -- Create Post.
  tonal,
  // Filled with the palette's Button Background Secondary (the red one).
  // CancelButton: Clear Post, Close Channel, Cancel.
  danger,
}

const Map<ButtonRole, String> _buttonRoleLabels = {
  ButtonRole.primary: "Button 1 - Primary",
  ButtonRole.plain: "Button 2 - Plain",
  ButtonRole.outlined: "Button 3 - Outlined",
  ButtonRole.tonal: "Button 4 - Tonal",
  ButtonRole.danger: "Button 5 - Danger",
};

String buttonRoleLabel(ButtonRole r) => _buttonRoleLabels[r]!;

// buttonRoleExamples names real buttons of each kind, so it's clear which
// one is being edited without hunting through the app for it.
const Map<ButtonRole, String> buttonRoleExamples = {
  ButtonRole.primary: "Unlock Wallet, Create Wallet.",
  ButtonRole.plain: "Network Config, Export Logs, Settings, Open Outbound "
      "Channel, Open, Remove.",
  ButtonRole.outlined: "Read More, Add Comment, Add Embed, Generate Address, "
      "Send On-Chain, Rescan Wallet, Accept.",
  ButtonRole.tonal: "Create Post.",
  ButtonRole.danger: "Clear Post, Close Channel, Cancel.",
};

// ButtonAreaStyle is one role's overrides. Every field is null/zero by
// default, meaning "leave this role exactly as the palette already renders
// it" -- an untouched preset produces the same ButtonStyle it did before the
// Buttons area existed.
//
// The color fields follow the same frozen-color-plus-live-slot pattern the
// rest of AreaStyle uses: `*Index`, when set, is a position into the active
// preset's palette that the color was picked from, and resolution always
// prefers re-reading that slot over the frozen snapshot (see
// AreaStyle.solidColorIndex).
@immutable
class ButtonAreaStyle {
  final Color? background;
  final int? backgroundIndex;
  // hover is painted over the background while the pointer is on the button
  // (and while it's pressed), so a translucent color reads as a tint of
  // whatever fill is underneath rather than replacing it.
  final Color? hover;
  final int? hoverIndex;
  final Color? border;
  final int? borderIndex;
  final double borderWidth;
  // Zero means this role keeps its built-in shape, which for every button
  // in the app is a stadium (a pill whose corners are half its height) --
  // not square corners. Any value set here replaces that outright, so the
  // way to square a button off is a radius of near-zero rather than zero.
  final double borderRadius;
  final SideValues? borderRadiusSides;
  final double padding;
  final SideValues? paddingSides;
  final double margin;
  final SideValues? marginSides;

  const ButtonAreaStyle({
    this.background,
    this.backgroundIndex,
    this.hover,
    this.hoverIndex,
    this.border,
    this.borderIndex,
    this.borderWidth = 0,
    this.borderRadius = 0,
    this.borderRadiusSides,
    this.padding = 0,
    this.paddingSides,
    this.margin = 0,
    this.marginSides,
  });

  // isEmpty is what lets an untouched role skip the override path entirely
  // -- see buildButtonStyles.
  bool get isEmpty =>
      background == null &&
      hover == null &&
      border == null &&
      borderWidth == 0 &&
      borderRadius == 0 &&
      borderRadiusSides == null &&
      padding == 0 &&
      paddingSides == null &&
      margin == 0 &&
      marginSides == null;

  // paddings/margins are the split-into-four form when the user has split
  // the setting, and the single value applied all round otherwise. Null
  // means the setting is untouched, so the button keeps its built-in inset.
  EdgeInsets? get paddings =>
      paddingSides?.insets ?? (padding > 0 ? EdgeInsets.all(padding) : null);
  EdgeInsets? get margins =>
      marginSides?.insets ?? (margin > 0 ? EdgeInsets.all(margin) : null);

  // radii is the same for the corner-measured setting: null leaves the
  // button on its own stadium shape rather than squaring it off.
  BorderRadius? get radii =>
      borderRadiusSides?.radius ??
      (borderRadius > 0 ? BorderRadius.circular(borderRadius) : null);

  ButtonAreaStyle copyWith({
    Color? background,
    int? backgroundIndex,
    bool clearBackground = false,
    bool clearBackgroundIndex = false,
    Color? hover,
    int? hoverIndex,
    bool clearHover = false,
    bool clearHoverIndex = false,
    Color? border,
    int? borderIndex,
    bool clearBorder = false,
    bool clearBorderIndex = false,
    double? borderWidth,
    double? borderRadius,
    SideValues? borderRadiusSides,
    bool clearBorderRadiusSides = false,
    double? padding,
    SideValues? paddingSides,
    bool clearPaddingSides = false,
    double? margin,
    SideValues? marginSides,
    bool clearMarginSides = false,
  }) =>
      ButtonAreaStyle(
        background: clearBackground ? null : (background ?? this.background),
        backgroundIndex: clearBackgroundIndex
            ? null
            : (backgroundIndex ?? this.backgroundIndex),
        hover: clearHover ? null : (hover ?? this.hover),
        hoverIndex: clearHoverIndex ? null : (hoverIndex ?? this.hoverIndex),
        border: clearBorder ? null : (border ?? this.border),
        borderIndex:
            clearBorderIndex ? null : (borderIndex ?? this.borderIndex),
        borderWidth: borderWidth ?? this.borderWidth,
        borderRadius: borderRadius ?? this.borderRadius,
        borderRadiusSides: clearBorderRadiusSides
            ? null
            : (borderRadiusSides ?? this.borderRadiusSides),
        padding: padding ?? this.padding,
        paddingSides:
            clearPaddingSides ? null : (paddingSides ?? this.paddingSides),
        margin: margin ?? this.margin,
        marginSides:
            clearMarginSides ? null : (marginSides ?? this.marginSides),
      );

  // remapPaletteIndexes mirrors AreaStyle.remapPaletteIndexes for this
  // role's three color bindings -- see there for why removing a palette
  // entry has to shift them.
  ButtonAreaStyle remapPaletteIndexes(int removed) {
    int? remap(int? i) => i == null || i < removed
        ? i
        : i == removed
            ? null
            : i - 1;
    return copyWith(
      backgroundIndex: remap(backgroundIndex),
      clearBackgroundIndex: remap(backgroundIndex) == null,
      hoverIndex: remap(hoverIndex),
      clearHoverIndex: remap(hoverIndex) == null,
      borderIndex: remap(borderIndex),
      clearBorderIndex: remap(borderIndex) == null,
    );
  }

  Map<String, dynamic> toJson() => {
        if (background != null) "background": colorToHex(background!),
        if (backgroundIndex != null) "backgroundIndex": backgroundIndex,
        if (hover != null) "hover": colorToHex(hover!),
        if (hoverIndex != null) "hoverIndex": hoverIndex,
        if (border != null) "border": colorToHex(border!),
        if (borderIndex != null) "borderIndex": borderIndex,
        if (borderWidth != 0) "borderWidth": borderWidth,
        if (borderRadius != 0) "borderRadius": borderRadius,
        if (borderRadiusSides != null)
          "borderRadiusSides": borderRadiusSides!.toJson(),
        if (padding != 0) "padding": padding,
        if (paddingSides != null) "paddingSides": paddingSides!.toJson(),
        if (margin != 0) "margin": margin,
        if (marginSides != null) "marginSides": marginSides!.toJson(),
      };

  factory ButtonAreaStyle.fromJson(Map<String, dynamic> j) {
    Color? color(String k) =>
        j[k] != null ? colorFromHex(j[k] as String) : null;
    double number(String k) => (j[k] as num?)?.toDouble() ?? 0;
    return ButtonAreaStyle(
      background: color("background"),
      backgroundIndex: (j["backgroundIndex"] as num?)?.toInt(),
      hover: color("hover"),
      hoverIndex: (j["hoverIndex"] as num?)?.toInt(),
      border: color("border"),
      borderIndex: (j["borderIndex"] as num?)?.toInt(),
      borderWidth: number("borderWidth"),
      borderRadius: number("borderRadius"),
      borderRadiusSides: SideValues.fromJson(j["borderRadiusSides"]),
      padding: number("padding"),
      paddingSides: SideValues.fromJson(j["paddingSides"]),
      margin: number("margin"),
      marginSides: SideValues.fromJson(j["marginSides"]),
    );
  }

  // resolve* prefer re-reading the bound palette slot over the frozen
  // snapshot, so editing that color later moves the button with it.
  Color? resolveBackground(List<Color> palette) =>
      _live(palette, backgroundIndex, background);
  Color? resolveHover(List<Color> palette) => _live(palette, hoverIndex, hover);
  Color? resolveBorder(List<Color> palette) =>
      _live(palette, borderIndex, border);

  static Color? _live(List<Color> palette, int? index, Color? raw) =>
      index != null && index < palette.length ? palette[index] : raw;
}

// ButtonPaletteColors are the palette's seven button colors, already
// resolved -- the defaults every role falls back to when the Buttons area
// leaves it alone. Bundled into one value so the built-in dark/light themes
// (which have no ThemePreset behind them) and a custom preset can both hand
// buildButtonStyles the same thing.
@immutable
class ButtonPaletteColors {
  final Color primaryBackground; // Button Background Primary.
  final Color secondaryBackground; // Button Background Secondary (red).
  final Color thirdBackground; // Third Background Color (grey).
  final Color border; // Button Border Color.
  final Color hover; // Background Hover.
  // text1 is the palette's Text Color 1 -- the accent-colored label the
  // unfilled roles (Plain, Outlined) use, where it sits on the page's own
  // background. text2 is Text Color 2, the near-white label the filled
  // roles (Primary, Tonal, Danger) use, where the accent color would be
  // reading against a strong fill instead.
  final Color text1;
  final Color text2;

  const ButtonPaletteColors({
    required this.primaryBackground,
    required this.secondaryBackground,
    required this.thirdBackground,
    required this.border,
    required this.hover,
    required this.text1,
    required this.text2,
  });
}

// _roleDefaults is each role's untouched appearance, in terms of the palette
// colors above: its fill, its label, and whether it carries a border.
//
// The two unfilled roles are explicitly transparent rather than left unset.
// Leaving the fill null lets each widget keep its own Material default,
// which is transparent for TextButton and OutlinedButton but a solid
// surfaceContainerLow for ElevatedButton -- and every plain ElevatedButton
// in the app (Export Logs, Settings, Open Outbound Channel, Create, Done,
// Import Plugin) then drew a dark pill that this role is specified not to
// have. They're all the same button; they now all render as one.
({Color fill, Color label, bool bordered}) _roleDefaults(
        ButtonRole role, ButtonPaletteColors c) =>
    switch (role) {
      ButtonRole.primary => (
          fill: c.primaryBackground,
          label: c.text2,
          bordered: false
        ),
      ButtonRole.plain => (
          fill: Colors.transparent,
          label: c.text1,
          bordered: false
        ),
      ButtonRole.outlined => (
          fill: Colors.transparent,
          label: c.text1,
          bordered: true
        ),
      ButtonRole.tonal => (
          fill: c.thirdBackground,
          label: c.text2,
          bordered: false
        ),
      ButtonRole.danger => (
          fill: c.secondaryBackground,
          label: c.text2,
          bordered: false
        ),
    };

// buildButtonStyles compiles every role into the ButtonStyle its widgets
// render through. The result is stored on the compiled AppTheme, so both the
// ThemeData button themes (Plain/Outlined/Tonal) and this app's own button
// widgets (Primary via raisedButtonStyle, Danger via CancelButton) read the
// same compiled values.
Map<ButtonRole, ButtonStyle> buildButtonStyles({
  required Map<ButtonRole, ButtonAreaStyle> overrides,
  required List<Color> palette,
  required ButtonPaletteColors colors,
}) =>
    {
      for (var role in ButtonRole.values)
        role: _buildRoleStyle(
            role, overrides[role] ?? const ButtonAreaStyle(), palette, colors),
    };

ButtonStyle _buildRoleStyle(ButtonRole role, ButtonAreaStyle s,
    List<Color> palette, ButtonPaletteColors c) {
  var d = _roleDefaults(role, c);
  var fill = s.resolveBackground(palette) ?? d.fill;
  var hover = s.resolveHover(palette) ?? c.hover;
  var border = s.resolveBorder(palette) ?? (d.bordered ? c.border : null);
  // A role that draws a border gets Material's own 1px unless the user has
  // asked for a specific width; one that doesn't only grows a border once a
  // width is actually set.
  var borderWidth = s.borderWidth > 0
      ? s.borderWidth
      : (border != null && (d.bordered || s.border != null) ? 1.0 : 0.0);
  var padding = s.paddings;
  var margin = s.margins;
  // Null radii leaves the widget on its own shape, which is a stadium for
  // every Material button type this app uses -- so an untouched role is
  // still the pill it always was.
  var radii = s.radii;
  var shape = radii == null
      ? const StadiumBorder()
      : RoundedRectangleBorder(borderRadius: radii);

  var overlay = WidgetStateProperty.resolveWith<Color?>(
      (states) => _hovered(states) ? hover : null);

  // Pinning a color for every state at once is what would otherwise make a
  // disabled button look live -- Material's own defaults fade the label to
  // 38% and the fill to 12%, and a flat WidgetStatePropertyAll replaces
  // that wholesale. The same two fades are reapplied here, against the
  // palette's own colors rather than Material's onSurface, so a disabled
  // button still reads as the theme's button.
  var label = WidgetStateProperty.resolveWith<Color?>((states) =>
      states.contains(WidgetState.disabled)
          ? d.label.withValues(alpha: 0.38)
          : d.label);
  var background = WidgetStateProperty.resolveWith<Color?>((states) =>
      states.contains(WidgetState.disabled)
          ? fill.withValues(alpha: fill.a * 0.12)
          : fill);
  var side = borderWidth > 0 && border != null
      ? WidgetStateProperty.resolveWith<BorderSide?>((states) => BorderSide(
          color: states.contains(WidgetState.disabled)
              ? border.withValues(alpha: 0.12)
              : border,
          width: borderWidth))
      : null;

  // Every button in Bison Relay's design is a flat pill, so the Material
  // elevation ElevatedButton would otherwise carry (a shadow under the
  // fill, plus a surface tint over it) is turned off for all five roles
  // rather than left to differ between the widget types sharing a role.
  const flat = (
    elevation: WidgetStatePropertyAll(0.0),
    shadow: WidgetStatePropertyAll(Colors.transparent),
  );

  if (margin == null) {
    return ButtonStyle(
      backgroundColor: background,
      foregroundColor: label,
      iconColor: label,
      overlayColor: overlay,
      side: side,
      elevation: flat.elevation,
      shadowColor: flat.shadow,
      surfaceTintColor: flat.shadow,
      // Left unset when no radius was picked, so the widget keeps its own
      // shape -- and so raisedButtonStyle's wider login-screen pill still
      // shows through the merge (see components/buttons.dart).
      shape: radii == null ? null : WidgetStatePropertyAll(shape),
      padding: padding != null ? WidgetStatePropertyAll(padding) : null,
    );
  }

  // With a margin set, the button's own Material can no longer paint the
  // fill or the border: the Material is the *outer* box, so anything it
  // paints reaches the edge of the margin too. Instead it's made fully
  // transparent and the visible pill is drawn by backgroundBuilder, which
  // wraps the button's content (and its padding) inside that Material --
  // inset by the margin. See ButtonStyleButton.build for the nesting.
  //
  // The ink overlay goes with it, for the same reason: it's painted on the
  // Material below, which would light up the margin as well. Hover is drawn
  // into the pill below instead, from the same states.
  return ButtonStyle(
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    foregroundColor: label,
    iconColor: label,
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: flat.shadow,
    surfaceTintColor: flat.shadow,
    elevation: flat.elevation,
    side: const WidgetStatePropertyAll(BorderSide.none),
    padding: padding != null ? WidgetStatePropertyAll(padding) : null,
    backgroundBuilder: (context, states, child) {
      var painted = background.resolve(states)!;
      if (_hovered(states)) {
        // alphaBlend, not a straight swap: Background Hover is meant to be
        // a translucent tint over whatever fill is underneath, exactly as
        // Material's own overlay is. Over an unfilled role's transparent
        // fill that leaves the hover color itself, which is what the two
        // background-less roles have to show a hover with.
        painted = Color.alphaBlend(hover, painted);
      }
      return Container(
        margin: margin,
        decoration: ShapeDecoration(
          color: painted,
          shape: shape.copyWith(side: side?.resolve(states)),
        ),
        child: child,
      );
    },
  );
}

bool _hovered(Set<WidgetState> states) =>
    states.contains(WidgetState.hovered) ||
    states.contains(WidgetState.pressed) ||
    states.contains(WidgetState.focused);
