import 'dart:io';

import 'package:bruig/theming_system/model/area_fill.dart';
import 'package:bruig/theming_system/model/area_options.dart';
import 'package:bruig/theming_system/model/area_style.dart';
import 'package:bruig/theming_system/runtime/theme_notifier.dart';
import 'package:bruig/theming_system/runtime/theme_tokens.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

// area_style_render.dart is the *rendering* half of AreaStyle: everything
// that turns one area's stored overrides (see area_style.dart) into paint --
// resolving its palette-bound colors against the live preset, building its
// two fills, and wrapping a widget in the resulting background and border.
//
// It's an extension rather than more methods on the class so the model layer
// stays free of any dependency on the runtime that renders it: area_style.
// dart knows nothing about ThemeNotifier, and this file is the one place
// the two meet.
extension AreaStyleRender on AreaStyle {
  // hasVisibleFrame is "this area has been given something to paint or some
  // space to take", which a render site checks before wrapping its content
  // at all: an area left alone still resolves to an opaque token-colored
  // box, so wrapping unconditionally would paint a background over regions
  // that never had one.
  bool get hasVisibleFrame =>
      mode != AreaBackgroundMode.token ||
      borderMode != AreaBackgroundMode.token ||
      !paddings.isZero ||
      !margins.isZero ||
      !borderRadii.isZero;

  // hasBorderWidth is "this style asks for a border on at least one side",
  // the per-side-aware replacement for the old `borderWidth > 0` checks.
  bool get hasBorderWidth => borderWidths.largest > 0;

  // borderSides builds a flat-color Border honoring each side's own width.
  // Note a zero-width side is BorderSide.none rather than a hairline, so
  // splitting a border and zeroing one side really does drop that edge.
  Border borderSides(Color color) {
    var w = borderWidths;
    BorderSide side(double width) =>
        width > 0 ? BorderSide(color: color, width: width) : BorderSide.none;
    return Border(
      left: side(w.left),
      top: side(w.top),
      right: side(w.right),
      bottom: side(w.bottom),
    );
  }

  // _liveColor prefers re-reading preset.palette[index] over the frozen
  // `raw` snapshot whenever index is set -- see solidColorIndex's doc.
  Color? _liveColor(ThemeNotifier theme, int? index, Color? raw) {
    if (index != null) {
      var palette = theme.activePalette;
      if (index < palette.length) return palette[index];
    }
    return raw;
  }

  // resolveBorderColor/resolveSolidColor are _liveColor's public form --
  // for the handful of render sites (navBar, the Sidebar's own
  // SecondarySideMenu) that build their decoration by hand instead of
  // going through toBoxDecoration/buildContainer, and for the theme
  // editor's own Color dropdown, which needs the live-resolved value (not
  // the frozen snapshot) to display the right slot selected.
  Color? resolveBorderColor(ThemeNotifier theme) =>
      _liveColor(theme, borderColorIndex, borderColor);
  Color? resolveSolidColor(ThemeNotifier theme) =>
      _liveColor(theme, solidColorIndex, solidColor);
  Color? resolveChatListAccentColor(ThemeNotifier theme) =>
      _liveColor(theme, chatListAccentColorIndex, chatListAccentColor);
  Color? resolveRtcActiveSessionColor(ThemeNotifier theme) =>
      _liveColor(theme, rtcActiveSessionColorIndex, rtcActiveSessionColor);
  Color? resolveRtcLiveColor(ThemeNotifier theme) =>
      _liveColor(theme, rtcLiveColorIndex, rtcLiveColor);
  Color? resolveRtcMutedColor(ThemeNotifier theme) =>
      _liveColor(theme, rtcMutedColorIndex, rtcMutedColor);
  Color? resolveRtcWarningColor(ThemeNotifier theme) =>
      _liveColor(theme, rtcWarningColorIndex, rtcWarningColor);
  Color? resolveChatListBackgroundColor(ThemeNotifier theme) =>
      _liveColor(theme, chatListBackgroundColorIndex, chatListBackgroundColor);
  Color? resolveChatListSelectedColor(ThemeNotifier theme) =>
      _liveColor(theme, chatListSelectedColorIndex, chatListSelectedColor);
  Color? resolveMessageAreaColor(ThemeNotifier theme) =>
      _liveColor(theme, messageAreaColorIndex, messageAreaColor);
  Color? resolveInputBackgroundColor(ThemeNotifier theme) =>
      _liveColor(theme, inputBackgroundColorIndex, inputBackgroundColor);
  Color? resolveInputBorderColor(ThemeNotifier theme) =>
      _liveColor(theme, inputBorderColorIndex, inputBorderColor);

  // _liveColors is _liveColor over a gradient's color list, pairing each
  // color with its own slot binding. `indexes` may be shorter than `raw`
  // (a gradient saved before those bindings existed, or one whose trailing
  // colors were custom-picked), in which case those fall back to the
  // stored color.
  List<Color> _liveColors(
          ThemeNotifier theme, List<Color> raw, List<int?> indexes) =>
      [
        for (var i = 0; i < raw.length; i++)
          _liveColor(theme, i < indexes.length ? indexes[i] : null, raw[i]) ??
              raw[i],
      ];
  // resolveGradientColors/resolveBorderGradientColors are the public form,
  // for the theme editor's own dropdowns.
  List<Color> resolveGradientColors(ThemeNotifier theme) =>
      _liveColors(theme, gradientColors, gradientColorIndexes);
  List<Color> resolveBorderGradientColors(ThemeNotifier theme) =>
      _liveColors(theme, borderGradientColors, borderGradientColorIndexes);

  // _backgroundFill/_borderFill resolve this style's two paint layers.
  AreaFill _backgroundFill(ThemeNotifier theme, SurfaceColor fallback,
          String? presetDir, Color? tokenColor) =>
      _resolveFill(mode, theme, fallback,
          tokenColor: tokenColor,
          solid: resolveSolidColor(theme),
          gradColors: _liveColors(theme, gradientColors, gradientColorIndexes),
          gradStops: gradientStops,
          gradBegin: gradientBegin,
          gradEnd: gradientEnd,
          imgPath: imagePath,
          imgFit: imageFit,
          preset: imagePreset,
          presetDir: presetDir);

  AreaFill _borderFill(
          ThemeNotifier theme, SurfaceColor fallback, String? presetDir) =>
      _resolveFill(borderMode, theme, fallback,
          gradColors: _liveColors(
              theme, borderGradientColors, borderGradientColorIndexes),
          gradStops: borderGradientStops,
          gradBegin: borderGradientBegin,
          gradEnd: borderGradientEnd,
          imgPath: borderImagePath,
          imgFit: borderImageFit,
          presetDir: presetDir);

  AreaFill _resolveFill(
    AreaBackgroundMode m,
    ThemeNotifier theme,
    SurfaceColor fallback, {
    Color? solid,
    List<Color> gradColors = const [],
    List<double>? gradStops,
    Alignment gradBegin = Alignment.topLeft,
    Alignment gradEnd = Alignment.bottomRight,
    String? imgPath,
    BoxFit imgFit = BoxFit.cover,
    // preset is only passed for the background layer -- borders have no
    // built-in image presets (and no image picker of their own).
    AreaImagePreset? preset,
    // tokenColor overrides what this fill's "Default" resolves to, for an
    // area whose default background is a palette slot of its own (Dual
    // Panel, Content Area) rather than a ColorScheme token.
    Color? tokenColor,
    String? presetDir,
  }) {
    switch (m) {
      case AreaBackgroundMode.token:
        // A non-default image preset paints *over* the area's normal color
        // rather than replacing it: the tiled patterns are translucent, so
        // the theme's own surface color still shows through behind them.
        return AreaFill(
            color: tokenColor ?? theme.surfaceColor(fallback),
            image: (preset != null && preset != AreaImagePreset.standard)
                ? areaImagePresetImage(preset)
                : null);
      case AreaBackgroundMode.none:
        return const AreaFill(color: Colors.transparent);
      case AreaBackgroundMode.solid:
        return AreaFill(color: solid ?? theme.surfaceColor(fallback));
      case AreaBackgroundMode.gradient:
        if (gradColors.length >= 2) {
          return AreaFill(
              gradient: LinearGradient(
                  begin: gradBegin,
                  end: gradEnd,
                  colors: gradColors,
                  stops: gradStops));
        }
        return AreaFill(color: theme.surfaceColor(fallback));
      case AreaBackgroundMode.image:
        // A user-picked image file wins over the built-in presets; with no
        // file picked, the chosen preset is the image (including "Default",
        // unlike token mode above where Default means "no image at all").
        if (imgPath != null && presetDir != null) {
          return AreaFill(
              image: DecorationImage(
                  image: FileImage(File(path.join(presetDir, imgPath))),
                  fit: imgFit));
        }
        return AreaFill(
            color: theme.surfaceColor(fallback),
            image: preset != null ? areaImagePresetImage(preset) : null);
    }
  }

  BorderRadius? get _radius {
    var r = borderRadii;
    return r.isZero ? null : r.radius;
  }

  // toBoxDecoration resolves this style's *background* (and, if the border
  // is a flat color, a matching BorderSide) into a single BoxDecoration.
  // This is the cheap path used by areas that are composed into an existing
  // widget's own decoration (app bar, side nav, sub-menu divider) rather
  // than wrapped in their own container -- it can't express a gradient or
  // image border (see buildContainer for that), but reproduces the area's
  // original appearance exactly when mode is token and there's no border.
  BoxDecoration toBoxDecoration(ThemeNotifier theme, SurfaceColor fallback,
      {String? presetDir, Color? tokenColor}) {
    var liveBorderColor = resolveBorderColor(theme);
    var bg = _backgroundFill(theme, fallback, presetDir, tokenColor);
    var border = (borderMode != AreaBackgroundMode.token &&
            liveBorderColor != null &&
            hasBorderWidth)
        ? borderSides(liveBorderColor)
        : null;
    return BoxDecoration(
      color: bg.color,
      gradient: bg.gradient,
      image: bg.image,
      border: border,
      // Flutter can't paint a border whose sides differ together with a
      // borderRadius (Border.paint throws outright), so a per-side border
      // loses the rounding on this flat path. buildContainer, which owns
      // its own widgets, keeps both by nesting instead -- see there.
      borderRadius: border == null || border.isUniform ? _radius : null,
    );
  }

  // buildContainer wraps `child` in this style's full background + border
  // (solid/gradient/image, matching modes independently) + padding/margin.
  // Two kinds of border can't be expressed as a single BoxDecoration -- a
  // gradient/image one (Border only supports flat per-side colors) and a
  // per-side one that also wants rounded corners (Border.paint refuses to
  // combine a non-uniform border with a borderRadius) -- so for both, this
  // nests two containers: an outer one painted with the border's fill,
  // inset by each side's own width, framing an inner one painted with the
  // background fill. That's the standard technique for non-solid borders in
  // Flutter, and it happens to express per-side widths exactly.
  Widget buildContainer(
    ThemeNotifier theme,
    SurfaceColor fallback, {
    required Widget child,
    String? presetDir,
    Color? tokenColor,
  }) {
    var bg = _backgroundFill(theme, fallback, presetDir, tokenColor);
    var widths = borderWidths;
    var hasBorder = borderMode != AreaBackgroundMode.token && hasBorderWidth;
    var inlineBorder =
        hasBorder && borderMode == AreaBackgroundMode.solid && widths.isUniform;

    // Any descendant ListTile needs a Material ancestor to paint its
    // background/ink splashes into. When this style paints a real
    // background/border below, the Containers built below would otherwise
    // be the nearest DecoratedBox sitting between the ListTile and whatever
    // Material happens to be further up the tree (e.g. Scaffold's), which
    // trips Flutter's "ListTile background may be invisible" assertion.
    // MaterialType.transparency paints nothing itself, so it just supplies
    // that ancestor without changing this area's appearance.
    var pad = paddings;
    Widget content = Container(
      padding: pad.isZero ? null : pad.insets,
      decoration: BoxDecoration(
        color: bg.color,
        gradient: bg.gradient,
        image: bg.image,
        borderRadius: _radius,
        // A uniform flat color border goes on this same box (matching
        // toBoxDecoration's cheaper path), no extra nesting needed.
        border: inlineBorder
            ? Border.all(
                color:
                    resolveBorderColor(theme) ?? theme.surfaceColor(fallback),
                width: widths.left)
            : null,
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );

    if (hasBorder && !inlineBorder) {
      // A solid border only lands here when its sides differ, in which case
      // there's no border *fill* to resolve -- just the flat color, painted
      // as the outer box's own background.
      var borderFill = borderMode == AreaBackgroundMode.solid
          ? AreaFill(
              color: resolveBorderColor(theme) ?? theme.surfaceColor(fallback))
          : _borderFill(theme, fallback, presetDir);
      content = Container(
        padding: widths.insets,
        decoration: BoxDecoration(
            color: borderFill.color,
            gradient: borderFill.gradient,
            image: borderFill.image,
            borderRadius: _radius),
        child: content,
      );
    }

    var mar = margins;
    if (!mar.isZero) {
      content = Container(margin: mar.insets, child: content);
    }
    return content;
  }

  // wrapBorderOnly wraps `child` in just this style's *border* -- for a
  // caller that paints its own background through some other fixed API
  // that only accepts a flat BoxDecoration (e.g. the third-party sidebarx
  // package's SidebarXTheme.decoration) and so can't itself embed a
  // gradient/image border, but can still wrap its whole widget with one via
  // this. A solid border is a no-op here (the caller's own decoration
  // already embeds it as a plain BorderSide, same as toBoxDecoration).
  Widget wrapBorderOnly(
    ThemeNotifier theme,
    SurfaceColor fallback, {
    required Widget child,
    String? presetDir,
  }) {
    if (borderMode == AreaBackgroundMode.token ||
        borderMode == AreaBackgroundMode.solid ||
        !hasBorderWidth) {
      return child;
    }
    var borderFill = _borderFill(theme, fallback, presetDir);
    return Container(
      padding: borderWidths.insets,
      decoration: BoxDecoration(
        color: borderFill.color,
        gradient: borderFill.gradient,
        image: borderFill.image,
        borderRadius: _radius,
      ),
      child: child,
    );
  }
}
