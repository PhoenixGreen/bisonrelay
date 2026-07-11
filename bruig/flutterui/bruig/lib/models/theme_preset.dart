import 'dart:io';

import 'package:bruig/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

// ThemeArea identifies a distinct visual region of the app that can carry its
// own background/border override, independent of the global color scheme.
enum ThemeArea {
  masterBackground,
  loginScreen,
  header,
  navBar,
  subMenuTabBar,
  chat,
  feed,
  realtimeChat,
  lnManagement,
  pages,
  manageContent,
  stats,
  logs,
}

String themeAreaLabel(ThemeArea area) {
  switch (area) {
    case ThemeArea.masterBackground:
      return "Master Background";
    case ThemeArea.loginScreen:
      return "Login Screen";
    case ThemeArea.header:
      return "Header";
    case ThemeArea.navBar:
      return "Navigation Bar";
    case ThemeArea.subMenuTabBar:
      return "Submenu / Tab Bar";
    case ThemeArea.chat:
      return "Chat";
    case ThemeArea.feed:
      return "Feed";
    case ThemeArea.realtimeChat:
      return "Realtime Chat";
    case ThemeArea.lnManagement:
      return "LN Management";
    case ThemeArea.pages:
      return "Pages";
    case ThemeArea.manageContent:
      return "Manage Content";
    case ThemeArea.stats:
      return "Stats";
    case ThemeArea.logs:
      return "Logs";
  }
}

// ContentAlign controls where an area's primary content sits (currently
// only wired for the header's title). hidden removes the content entirely.
enum ContentAlign { start, center, end, hidden }

// HeaderPosition controls where (or whether) the header renders:
// - top: today's behavior, a full-width bar above everything (sidebar
//   included).
// - content: a bar the same width as just the content area (to the right
//   of the primary nav sidebar), with the logo/about-button and "new post"
//   button removed since they belong to the global app chrome, not a
//   per-content-area bar.
// - none: no header at all; the content area extends to fill that space.
enum HeaderPosition { top, content, none }

String headerPositionLabel(HeaderPosition p) {
  switch (p) {
    case HeaderPosition.top:
      return "Default (Top)";
    case HeaderPosition.content:
      return "Content";
    case HeaderPosition.none:
      return "None";
  }
}

String contentAlignLabel(ContentAlign a) {
  switch (a) {
    case ContentAlign.start:
      return "Left";
    case ContentAlign.center:
      return "Center";
    case ContentAlign.end:
      return "Right";
    case ContentAlign.hidden:
      return "Remove";
  }
}

// SubMenuStyle controls how a page's submenu (its sub-navigation tabs, e.g.
// Settings' Account/Appearance/Notifications/... list) shows or hides
// itself; only meaningful for subMenuTabBar, and only wired up for the
// "tab-style" submenus with a small fixed set of destinations (Settings, LN
// Management, Feed, the plugin screen switcher) -- not the dynamic,
// potentially-long lists (chat list, RTC sessions, page-view sessions).
// - alwaysVisible: today's behavior, a persistent column beside the content.
// - hoverReveal: collapses to a thin edge strip and expands to full width
//   while the mouse hovers over it.
// - autoHideOnDetail: hidden entirely while viewing content that doesn't
//   need sub-navigation (e.g. an individual post, a specific chat), and
//   shown otherwise.
// - manualToggle: a persistent collapse/expand handle next to the content,
//   like the primary nav sidebar's own collapse button.
enum SubMenuStyle { alwaysVisible, hoverReveal, autoHideOnDetail, manualToggle }

String subMenuStyleLabel(SubMenuStyle s) {
  switch (s) {
    case SubMenuStyle.alwaysVisible:
      return "Default (Always visible)";
    case SubMenuStyle.hoverReveal:
      return "Reveal on hover";
    case SubMenuStyle.autoHideOnDetail:
      return "Auto-hide when not needed";
    case SubMenuStyle.manualToggle:
      return "Manual show/hide";
  }
}

// AreaBackgroundMode selects how a fill (background or border) is painted.
// token = "use the app's normal color scheme" (opaque, matches how the area
// looked before this feature existed). none is a distinct, explicit "no
// fill at all" (fully transparent) -- useful e.g. for a submenu/tab-bar
// area where a border/padding is wanted but no background color at all.
enum AreaBackgroundMode { token, none, solid, gradient, image }

// GradientDirection is a small set of named, dropdown-friendly gradient
// directions (rather than a free-form angle input, consistent with this
// app's "dropdowns not fiddly custom controls" settings UX).
enum GradientDirection {
  topLeftToBottomRight,
  topRightToBottomLeft,
  leftToRight,
  topToBottom,
}

String gradientDirectionLabel(GradientDirection d) {
  switch (d) {
    case GradientDirection.topLeftToBottomRight:
      return "Top-left → Bottom-right";
    case GradientDirection.topRightToBottomLeft:
      return "Top-right → Bottom-left";
    case GradientDirection.leftToRight:
      return "Left → Right";
    case GradientDirection.topToBottom:
      return "Top → Bottom";
  }
}

(Alignment, Alignment) gradientDirectionAlignments(GradientDirection d) {
  switch (d) {
    case GradientDirection.topLeftToBottomRight:
      return (Alignment.topLeft, Alignment.bottomRight);
    case GradientDirection.topRightToBottomLeft:
      return (Alignment.topRight, Alignment.bottomLeft);
    case GradientDirection.leftToRight:
      return (Alignment.centerLeft, Alignment.centerRight);
    case GradientDirection.topToBottom:
      return (Alignment.topCenter, Alignment.bottomCenter);
  }
}

GradientDirection gradientDirectionFor(Alignment begin, Alignment end) {
  for (var d in GradientDirection.values) {
    var (b, e) = gradientDirectionAlignments(d);
    if (b == begin && e == end) return d;
  }
  return GradientDirection.topLeftToBottomRight;
}

// _Fill is the resolved paint for one "layer" (a background, or a border
// frame) -- at most one of color/gradient/image is set.
class _Fill {
  final Color? color;
  final Gradient? gradient;
  final DecorationImage? image;
  const _Fill({this.color, this.gradient, this.image});
}

// AreaStyle is the set of visual overrides a user can apply to a single
// ThemeArea. mode == token (the default) means "use the app's normal color
// scheme", producing an identical appearance to what the area rendered
// before this feature existed. The border supports the same four modes as
// the background (default/solid/gradient/image), plus independent padding
// (inset between the border and the content) and margin (outer spacing).
class AreaStyle {
  final AreaBackgroundMode mode;
  final SurfaceColor? tokenOverride;
  final Color? solidColor;
  final List<Color> gradientColors;
  final List<double>? gradientStops;
  final Alignment gradientBegin;
  final Alignment gradientEnd;
  final String? imagePath; // Relative path within the preset's directory.
  final BoxFit imageFit;

  final AreaBackgroundMode borderMode;
  final Color? borderColor;
  final List<Color> borderGradientColors;
  final List<double>? borderGradientStops;
  final Alignment borderGradientBegin;
  final Alignment borderGradientEnd;
  final String? borderImagePath;
  final BoxFit borderImageFit;
  final double borderWidth;
  final double borderRadius;

  final double padding;
  final double margin;

  // width overrides the area's own layout width -- only meaningful for
  // subMenuTabBar (the one area with a fixed, configurable panel width);
  // null means "use that area's built-in default". Deliberately not
  // exposed for navBar -- the sidebarx package's collapse/extend toggle
  // assumes specific width values for its own animation.
  final double? width;

  // height overrides the area's own layout height -- only meaningful for
  // header (the app bar's height); null means "use the default toolbar
  // height".
  final double? height;

  // contentAlign controls where the area's primary content (currently only
  // wired for the header's title) sits within the area; null means "use
  // that area's default alignment".
  final ContentAlign? contentAlign;

  // logoSize overrides the app-icon logo size; meaningful for header (its
  // own logo, independent of the header's height) and navBar (see
  // showLogo below). Null means the built-in default (40 for header, 32
  // for navBar).
  final double? logoSize;

  // headerPosition controls where/whether the header renders at all; only
  // meaningful for header. Null means HeaderPosition.top (today's
  // behavior).
  final HeaderPosition? headerPosition;

  // showLogo displays the Bison Relay logo at the top of the nav bar; only
  // meaningful for navBar. Intended for when the header is set to
  // HeaderPosition.content or .none, since the header's own logo
  // disappears in both of those (the header only spans the content area,
  // or doesn't render at all), but it's an independent toggle either way.
  final bool showLogo;

  // logoAlign positions the nav bar logo (showLogo above) horizontally;
  // only meaningful for navBar, and only start/center/end are used there
  // (hidden doesn't apply -- showLogo already covers visibility). Null
  // means center.
  final ContentAlign? logoAlign;

  // subMenuStyle controls how a page's submenu shows/hides itself; only
  // meaningful for subMenuTabBar. Null means SubMenuStyle.alwaysVisible
  // (today's behavior).
  final SubMenuStyle? subMenuStyle;

  // showHoverArrow toggles the small chevron indicator shown on the
  // collapsed edge strip when subMenuStyle is hoverReveal; only meaningful
  // for subMenuTabBar. True (shown) is the default/unmodified state.
  final bool showHoverArrow;

  // isUnmodified is true only when nothing about this style differs from
  // the area's original, pre-theming-feature appearance. A few render call
  // sites (SecondarySideMenu, the header, the login screen) have a cheaper
  // "reproduce the exact original widget" path for the common unmodified
  // case rather than always paying for the general buildContainer/
  // areaContainer machinery -- they must check *every* field here, not
  // just mode/borderMode, or a padding/margin/width/height/contentAlign
  // change with mode left at its default silently gets ignored by that
  // shortcut.
  bool get isUnmodified =>
      mode == AreaBackgroundMode.token &&
      borderMode == AreaBackgroundMode.token &&
      padding == 0 &&
      margin == 0 &&
      width == null &&
      height == null &&
      contentAlign == null &&
      logoSize == null &&
      headerPosition == null &&
      showLogo == false &&
      logoAlign == null &&
      subMenuStyle == null &&
      showHoverArrow == true;

  const AreaStyle({
    this.mode = AreaBackgroundMode.token,
    this.tokenOverride,
    this.solidColor,
    this.gradientColors = const [],
    this.gradientStops,
    this.gradientBegin = Alignment.topLeft,
    this.gradientEnd = Alignment.bottomRight,
    this.imagePath,
    this.imageFit = BoxFit.cover,
    this.borderMode = AreaBackgroundMode.token,
    this.borderColor,
    this.borderGradientColors = const [],
    this.borderGradientStops,
    this.borderGradientBegin = Alignment.topLeft,
    this.borderGradientEnd = Alignment.bottomRight,
    this.borderImagePath,
    this.borderImageFit = BoxFit.cover,
    this.borderWidth = 0,
    this.borderRadius = 0,
    this.padding = 0,
    this.margin = 0,
    this.width,
    this.height,
    this.contentAlign,
    this.logoSize,
    this.headerPosition,
    this.showLogo = false,
    this.logoAlign,
    this.subMenuStyle,
    this.showHoverArrow = true,
  });

  AreaStyle copyWith({
    AreaBackgroundMode? mode,
    SurfaceColor? tokenOverride,
    Color? solidColor,
    List<Color>? gradientColors,
    List<double>? gradientStops,
    Alignment? gradientBegin,
    Alignment? gradientEnd,
    String? imagePath,
    bool clearImagePath = false,
    BoxFit? imageFit,
    AreaBackgroundMode? borderMode,
    Color? borderColor,
    List<Color>? borderGradientColors,
    List<double>? borderGradientStops,
    Alignment? borderGradientBegin,
    Alignment? borderGradientEnd,
    String? borderImagePath,
    bool clearBorderImagePath = false,
    BoxFit? borderImageFit,
    double? borderWidth,
    double? borderRadius,
    double? padding,
    double? margin,
    double? width,
    bool clearWidth = false,
    double? height,
    bool clearHeight = false,
    ContentAlign? contentAlign,
    double? logoSize,
    HeaderPosition? headerPosition,
    bool? showLogo,
    ContentAlign? logoAlign,
    SubMenuStyle? subMenuStyle,
    bool? showHoverArrow,
  }) =>
      AreaStyle(
        mode: mode ?? this.mode,
        tokenOverride: tokenOverride ?? this.tokenOverride,
        solidColor: solidColor ?? this.solidColor,
        gradientColors: gradientColors ?? this.gradientColors,
        gradientStops: gradientStops ?? this.gradientStops,
        gradientBegin: gradientBegin ?? this.gradientBegin,
        gradientEnd: gradientEnd ?? this.gradientEnd,
        imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
        imageFit: imageFit ?? this.imageFit,
        borderMode: borderMode ?? this.borderMode,
        borderColor: borderColor ?? this.borderColor,
        borderGradientColors: borderGradientColors ?? this.borderGradientColors,
        borderGradientStops: borderGradientStops ?? this.borderGradientStops,
        borderGradientBegin: borderGradientBegin ?? this.borderGradientBegin,
        borderGradientEnd: borderGradientEnd ?? this.borderGradientEnd,
        borderImagePath: clearBorderImagePath
            ? null
            : (borderImagePath ?? this.borderImagePath),
        borderImageFit: borderImageFit ?? this.borderImageFit,
        borderWidth: borderWidth ?? this.borderWidth,
        borderRadius: borderRadius ?? this.borderRadius,
        padding: padding ?? this.padding,
        margin: margin ?? this.margin,
        width: clearWidth ? null : (width ?? this.width),
        height: clearHeight ? null : (height ?? this.height),
        contentAlign: contentAlign ?? this.contentAlign,
        logoSize: logoSize ?? this.logoSize,
        headerPosition: headerPosition ?? this.headerPosition,
        showLogo: showLogo ?? this.showLogo,
        logoAlign: logoAlign ?? this.logoAlign,
        subMenuStyle: subMenuStyle ?? this.subMenuStyle,
        showHoverArrow: showHoverArrow ?? this.showHoverArrow,
      );

  static String _colorToHex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0')}';
  static Color _colorFromHex(String s) =>
      Color(int.parse(s.replaceFirst('#', ''), radix: 16));
  static List<double> _alignToJson(Alignment a) => [a.x, a.y];
  static Alignment _alignFromJson(dynamic j, Alignment fallback) => j != null
      ? Alignment((j[0] as num).toDouble(), (j[1] as num).toDouble())
      : fallback;

  Map<String, dynamic> toJson() => {
        "mode": mode.name,
        if (tokenOverride != null) "tokenOverride": tokenOverride!.name,
        if (solidColor != null) "solidColor": _colorToHex(solidColor!),
        if (gradientColors.isNotEmpty)
          "gradientColors": gradientColors.map(_colorToHex).toList(),
        if (gradientStops != null) "gradientStops": gradientStops,
        "gradientBegin": _alignToJson(gradientBegin),
        "gradientEnd": _alignToJson(gradientEnd),
        if (imagePath != null) "imagePath": imagePath,
        "imageFit": imageFit.name,
        "borderMode": borderMode.name,
        if (borderColor != null) "borderColor": _colorToHex(borderColor!),
        if (borderGradientColors.isNotEmpty)
          "borderGradientColors": borderGradientColors.map(_colorToHex).toList(),
        if (borderGradientStops != null)
          "borderGradientStops": borderGradientStops,
        "borderGradientBegin": _alignToJson(borderGradientBegin),
        "borderGradientEnd": _alignToJson(borderGradientEnd),
        if (borderImagePath != null) "borderImagePath": borderImagePath,
        "borderImageFit": borderImageFit.name,
        "borderWidth": borderWidth,
        "borderRadius": borderRadius,
        "padding": padding,
        "margin": margin,
        if (width != null) "width": width,
        if (height != null) "height": height,
        if (contentAlign != null) "contentAlign": contentAlign!.name,
        if (logoSize != null) "logoSize": logoSize,
        if (headerPosition != null) "headerPosition": headerPosition!.name,
        if (showLogo) "showLogo": showLogo,
        if (logoAlign != null) "logoAlign": logoAlign!.name,
        if (subMenuStyle != null) "subMenuStyle": subMenuStyle!.name,
        if (!showHoverArrow) "showHoverArrow": showHoverArrow,
      };

  factory AreaStyle.fromJson(Map<String, dynamic> j) => AreaStyle(
        mode: AreaBackgroundMode.values.firstWhere((e) => e.name == j["mode"],
            orElse: () => AreaBackgroundMode.token),
        tokenOverride: j["tokenOverride"] != null
            ? SurfaceColor.values.firstWhere((e) => e.name == j["tokenOverride"])
            : null,
        solidColor:
            j["solidColor"] != null ? _colorFromHex(j["solidColor"]) : null,
        gradientColors: j["gradientColors"] != null
            ? (j["gradientColors"] as List)
                .map((e) => _colorFromHex(e as String))
                .toList()
            : const [],
        gradientStops: j["gradientStops"] != null
            ? (j["gradientStops"] as List)
                .map((e) => (e as num).toDouble())
                .toList()
            : null,
        gradientBegin: _alignFromJson(j["gradientBegin"], Alignment.topLeft),
        gradientEnd: _alignFromJson(j["gradientEnd"], Alignment.bottomRight),
        imagePath: j["imagePath"],
        imageFit: BoxFit.values.firstWhere((e) => e.name == j["imageFit"],
            orElse: () => BoxFit.cover),
        borderMode: AreaBackgroundMode.values.firstWhere(
            (e) => e.name == j["borderMode"],
            orElse: () => AreaBackgroundMode.token),
        borderColor:
            j["borderColor"] != null ? _colorFromHex(j["borderColor"]) : null,
        borderGradientColors: j["borderGradientColors"] != null
            ? (j["borderGradientColors"] as List)
                .map((e) => _colorFromHex(e as String))
                .toList()
            : const [],
        borderGradientStops: j["borderGradientStops"] != null
            ? (j["borderGradientStops"] as List)
                .map((e) => (e as num).toDouble())
                .toList()
            : null,
        borderGradientBegin:
            _alignFromJson(j["borderGradientBegin"], Alignment.topLeft),
        borderGradientEnd:
            _alignFromJson(j["borderGradientEnd"], Alignment.bottomRight),
        borderImagePath: j["borderImagePath"],
        borderImageFit: BoxFit.values
            .firstWhere((e) => e.name == j["borderImageFit"],
                orElse: () => BoxFit.cover),
        borderWidth: (j["borderWidth"] as num?)?.toDouble() ?? 0,
        borderRadius: (j["borderRadius"] as num?)?.toDouble() ?? 0,
        padding: (j["padding"] as num?)?.toDouble() ?? 0,
        margin: (j["margin"] as num?)?.toDouble() ?? 0,
        width: (j["width"] as num?)?.toDouble(),
        height: (j["height"] as num?)?.toDouble(),
        contentAlign: j["contentAlign"] != null
            ? ContentAlign.values.firstWhere((e) => e.name == j["contentAlign"])
            : null,
        logoSize: (j["logoSize"] as num?)?.toDouble(),
        headerPosition: j["headerPosition"] != null
            ? HeaderPosition.values
                .firstWhere((e) => e.name == j["headerPosition"])
            : null,
        showLogo: j["showLogo"] as bool? ?? false,
        logoAlign: j["logoAlign"] != null
            ? ContentAlign.values.firstWhere((e) => e.name == j["logoAlign"])
            : null,
        subMenuStyle: j["subMenuStyle"] != null
            ? SubMenuStyle.values.firstWhere((e) => e.name == j["subMenuStyle"])
            : null,
        showHoverArrow: j["showHoverArrow"] as bool? ?? true,
      );

  _Fill _resolveFill(
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
    String? presetDir,
  }) {
    switch (m) {
      case AreaBackgroundMode.token:
        return _Fill(color: theme.surfaceColor(tokenOverride ?? fallback));
      case AreaBackgroundMode.none:
        return const _Fill(color: Colors.transparent);
      case AreaBackgroundMode.solid:
        return _Fill(color: solid ?? theme.surfaceColor(fallback));
      case AreaBackgroundMode.gradient:
        if (gradColors.length >= 2) {
          return _Fill(
              gradient: LinearGradient(
                  begin: gradBegin,
                  end: gradEnd,
                  colors: gradColors,
                  stops: gradStops));
        }
        return _Fill(color: theme.surfaceColor(tokenOverride ?? fallback));
      case AreaBackgroundMode.image:
        if (imgPath != null && presetDir != null) {
          return _Fill(
              image: DecorationImage(
                  image: FileImage(File(path.join(presetDir, imgPath))),
                  fit: imgFit));
        }
        return _Fill(color: theme.surfaceColor(tokenOverride ?? fallback));
    }
  }

  // toBoxDecoration resolves this style's *background* (and, if the border
  // is a flat color, a matching BorderSide) into a single BoxDecoration.
  // This is the cheap path used by areas that are composed into an existing
  // widget's own decoration (app bar, side nav, sub-menu divider) rather
  // than wrapped in their own container -- it can't express a gradient or
  // image border (see buildContainer for that), but reproduces the area's
  // original appearance exactly when mode is token and there's no border.
  BoxDecoration toBoxDecoration(ThemeNotifier theme, SurfaceColor fallback,
      {String? presetDir}) {
    var bg = _resolveFill(mode, theme, fallback,
        solid: solidColor,
        gradColors: gradientColors,
        gradStops: gradientStops,
        gradBegin: gradientBegin,
        gradEnd: gradientEnd,
        imgPath: imagePath,
        imgFit: imageFit,
        presetDir: presetDir);
    return BoxDecoration(
      color: bg.color,
      gradient: bg.gradient,
      image: bg.image,
      border: (borderMode != AreaBackgroundMode.token &&
              borderColor != null &&
              borderWidth > 0)
          ? Border.all(color: borderColor!, width: borderWidth)
          : null,
      borderRadius:
          borderRadius > 0 ? BorderRadius.circular(borderRadius) : null,
    );
  }

  // buildContainer wraps `child` in this style's full background + border
  // (solid/gradient/image, matching modes independently) + padding/margin.
  // A gradient or image border can't be expressed as a single BoxDecoration
  // (Border only supports flat per-side colors), so when the border isn't
  // a flat color, this nests two containers: an outer one painted with the
  // border's fill, inset by borderWidth, framing an inner one painted with
  // the background fill -- the standard technique for non-solid borders in
  // Flutter.
  Widget buildContainer(
    ThemeNotifier theme,
    SurfaceColor fallback, {
    required Widget child,
    String? presetDir,
  }) {
    var bg = _resolveFill(mode, theme, fallback,
        solid: solidColor,
        gradColors: gradientColors,
        gradStops: gradientStops,
        gradBegin: gradientBegin,
        gradEnd: gradientEnd,
        imgPath: imagePath,
        imgFit: imageFit,
        presetDir: presetDir);
    var radius = borderRadius > 0 ? BorderRadius.circular(borderRadius) : null;

    Widget content = Container(
      padding: padding > 0 ? EdgeInsets.all(padding) : null,
      decoration: BoxDecoration(
          color: bg.color,
          gradient: bg.gradient,
          image: bg.image,
          borderRadius: radius),
      child: child,
    );

    if (borderMode != AreaBackgroundMode.token && borderWidth > 0) {
      if (borderMode == AreaBackgroundMode.solid) {
        // Flat color: a plain Border on the same box is enough (matches
        // toBoxDecoration's cheaper path), no extra nesting needed.
        content = Container(
          padding: padding > 0 ? EdgeInsets.all(padding) : null,
          decoration: BoxDecoration(
            color: bg.color,
            gradient: bg.gradient,
            image: bg.image,
            borderRadius: radius,
            border: Border.all(
                color: borderColor ?? theme.surfaceColor(fallback),
                width: borderWidth),
          ),
          child: child,
        );
      } else {
        var borderFill = _resolveFill(borderMode, theme, fallback,
            gradColors: borderGradientColors,
            gradStops: borderGradientStops,
            gradBegin: borderGradientBegin,
            gradEnd: borderGradientEnd,
            imgPath: borderImagePath,
            imgFit: borderImageFit,
            presetDir: presetDir);
        content = Container(
          padding: EdgeInsets.all(borderWidth),
          decoration: BoxDecoration(
              color: borderFill.color,
              gradient: borderFill.gradient,
              image: borderFill.image,
              borderRadius: radius),
          child: content,
        );
      }
    }

    if (margin > 0) {
      content = Container(margin: EdgeInsets.all(margin), child: content);
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
        borderWidth <= 0) {
      return child;
    }
    var borderFill = _resolveFill(borderMode, theme, fallback,
        gradColors: borderGradientColors,
        gradStops: borderGradientStops,
        gradBegin: borderGradientBegin,
        gradEnd: borderGradientEnd,
        imgPath: borderImagePath,
        imgFit: borderImageFit,
        presetDir: presetDir);
    return Container(
      padding: EdgeInsets.all(borderWidth),
      decoration: BoxDecoration(
        color: borderFill.color,
        gradient: borderFill.gradient,
        image: borderFill.image,
        borderRadius: borderRadius > 0 ? BorderRadius.circular(borderRadius) : null,
      ),
      child: child,
    );
  }
}

// PaletteSlot identifies one of the 10 palette colors. Deliberately fewer,
// more distinct roles than Material3's ColorScheme (which has 4 near-
// identical onPrimary/onSecondary/onTertiary/onError slots in practice) --
// every slot here has a clearly different purpose so there's minimal visual
// overlap between them.
enum PaletteSlot {
  primary,
  secondary,
  tertiary,
  error,
  surface,
  onSurface,
  onAccent,
  outline,
  success,
  accent,
}

// kMaxPaletteColors caps the *total* palette (10 fixed roles +
// extraPaletteColors) a preset can carry; kMaxExtraPaletteColors is the
// remaining room for extras once the 10 fixed roles are accounted for.
const int kMaxPaletteColors = 20;
// 20 - 10 fixed PaletteSlot roles.
const int kMaxExtraPaletteColors = kMaxPaletteColors - 10;

// kVividPaletteSlots are the 5 roles a ColorPalette library entry (see
// palette_library.dart) actually carries and overwrites when applied --
// error/surface/onSurface/onAccent/outline are functional/neutral roles
// that must stay dark-vs-light-theme-appropriate, so a library palette
// deliberately leaves them alone rather than clobbering them with
// (possibly brightness-mismatched, e.g. a white surface in a dark theme)
// baked-in values.
const List<PaletteSlot> kVividPaletteSlots = [
  PaletteSlot.primary,
  PaletteSlot.secondary,
  PaletteSlot.tertiary,
  PaletteSlot.success,
  PaletteSlot.accent,
];

String paletteSlotLabel(PaletteSlot slot) {
  switch (slot) {
    case PaletteSlot.primary:
      return "Primary";
    case PaletteSlot.secondary:
      return "Secondary";
    case PaletteSlot.tertiary:
      return "Tertiary";
    case PaletteSlot.error:
      return "Error";
    case PaletteSlot.surface:
      return "Surface (Background)";
    case PaletteSlot.onSurface:
      return "On Surface (Text)";
    case PaletteSlot.onAccent:
      return "On Accent (Text on Color)";
    case PaletteSlot.outline:
      return "Outline (Borders)";
    case PaletteSlot.success:
      return "Success";
    case PaletteSlot.accent:
      return "Accent (Custom)";
  }
}

// ThemePreset is one full, nameable, exportable custom theme: a 10-color
// palette plus a set of per-area style overrides.
class ThemePreset {
  final String id;
  final String name;
  final Brightness brightness;

  // The 10-color palette (see PaletteSlot for the rationale behind these
  // specific roles). "accent" carries no fixed ColorScheme role -- it's a
  // free extra swatch available for area styling.
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color error;
  final Color surface;
  final Color onSurface;
  final Color onAccent;
  final Color outline;
  final Color success;
  final Color accent;

  // extraPaletteColors are user-added swatches beyond the 10 fixed roles
  // above -- free-form, no fixed semantic meaning, just additional options
  // offered wherever an area style needs a color picked (see `palette`
  // below and theme_editor.dart's palette-color dropdowns). Capped at
  // kMaxExtraPaletteColors (see below) so the total palette never exceeds
  // kMaxPaletteColors.
  final List<Color> extraPaletteColors;

  final Map<ThemeArea, AreaStyle> areas;

  // Menu rename/reorder customization is saved as *part of this preset*
  // (rather than as a single global setting) so that switching themes
  // switches menu layout too, and "Reset to Default" (which switches to
  // the built-in default theme, unaffected by any custom preset) can't
  // accidentally erase what's saved in a *different*, still-selectable
  // preset. Null means "no customization" (always true for the built-in
  // dark/light themes). Keyed/ordered by routeName, same shape as
  // MainMenuModel.currentLabels()/currentOrder().
  final Map<String, String>? menuLabels;
  final List<String>? menuOrder;

  // Directory this preset was loaded from on disk (null for a preset that
  // only exists in memory, e.g. mid-edit before its first save). Area
  // background images are stored relative to this directory.
  final String? sourceDir;

  const ThemePreset({
    required this.id,
    this.name = "Default Theme",
    this.brightness = Brightness.dark,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.error,
    required this.surface,
    required this.onSurface,
    required this.onAccent,
    required this.outline,
    required this.success,
    required this.accent,
    this.extraPaletteColors = const [],
    this.areas = const {},
    this.menuLabels,
    this.menuOrder,
    this.sourceDir,
  });

  Color forSlot(PaletteSlot slot) {
    switch (slot) {
      case PaletteSlot.primary:
        return primary;
      case PaletteSlot.secondary:
        return secondary;
      case PaletteSlot.tertiary:
        return tertiary;
      case PaletteSlot.error:
        return error;
      case PaletteSlot.surface:
        return surface;
      case PaletteSlot.onSurface:
        return onSurface;
      case PaletteSlot.onAccent:
        return onAccent;
      case PaletteSlot.outline:
        return outline;
      case PaletteSlot.success:
        return success;
      case PaletteSlot.accent:
        return accent;
    }
  }

  ThemePreset withSlot(PaletteSlot slot, Color color) {
    switch (slot) {
      case PaletteSlot.primary:
        return copyWith(primary: color);
      case PaletteSlot.secondary:
        return copyWith(secondary: color);
      case PaletteSlot.tertiary:
        return copyWith(tertiary: color);
      case PaletteSlot.error:
        return copyWith(error: color);
      case PaletteSlot.surface:
        return copyWith(surface: color);
      case PaletteSlot.onSurface:
        return copyWith(onSurface: color);
      case PaletteSlot.onAccent:
        return copyWith(onAccent: color);
      case PaletteSlot.outline:
        return copyWith(outline: color);
      case PaletteSlot.success:
        return copyWith(success: color);
      case PaletteSlot.accent:
        return copyWith(accent: color);
    }
  }

  // palette returns the 10 fixed-role colors (in PaletteSlot order) plus
  // any extraPaletteColors -- this is the full set of colors offered
  // wherever an area style needs a color picked (see theme_editor.dart's
  // palette-color dropdowns).
  List<Color> get palette =>
      [...PaletteSlot.values.map(forSlot), ...extraPaletteColors];

  ThemePreset copyWith({
    String? id,
    String? name,
    Brightness? brightness,
    Color? primary,
    Color? secondary,
    Color? tertiary,
    Color? error,
    Color? surface,
    Color? onSurface,
    Color? onAccent,
    Color? outline,
    Color? success,
    Color? accent,
    List<Color>? extraPaletteColors,
    Map<ThemeArea, AreaStyle>? areas,
    Map<String, String>? menuLabels,
    List<String>? menuOrder,
    String? sourceDir,
  }) =>
      ThemePreset(
        id: id ?? this.id,
        name: name ?? this.name,
        brightness: brightness ?? this.brightness,
        primary: primary ?? this.primary,
        secondary: secondary ?? this.secondary,
        tertiary: tertiary ?? this.tertiary,
        error: error ?? this.error,
        surface: surface ?? this.surface,
        onSurface: onSurface ?? this.onSurface,
        onAccent: onAccent ?? this.onAccent,
        outline: outline ?? this.outline,
        success: success ?? this.success,
        accent: accent ?? this.accent,
        extraPaletteColors: extraPaletteColors ?? this.extraPaletteColors,
        areas: areas ?? this.areas,
        menuLabels: menuLabels ?? this.menuLabels,
        menuOrder: menuOrder ?? this.menuOrder,
        sourceDir: sourceDir ?? this.sourceDir,
      );

  // toAppTheme compiles this preset into an AppTheme using exactly the same
  // ColorScheme.fromSeed()+copyWith() formula the built-in "dark"/"light"
  // themes are hand-written with (see appThemes below), so custom presets
  // render through the same pipeline the rest of the app already trusts.
  static Color _darken(Color c, double amount) {
    var hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
  }

  // toAppTheme deliberately does NOT force primary/secondary/tertiary/error
  // (or their "on" counterparts) into ColorScheme.fromSeed the way an
  // earlier version of this method did -- those roles drive the foreground
  // of many standard Material widgets (e.g. OutlinedButton's text/icon
  // color defaults to colorScheme.primary), and forcing them to the user's
  // raw palette swatch (which can easily equal or nearly equal `surface`,
  // as the seed defaults below do) produces illegible text-on-background.
  // Only `seedColor` (== primary, exactly as the original hand-built
  // "dark"/"light" AppThemes below only ever passed a single seed) and the
  // background-ish `surface`/its container tones are passed explicitly;
  // Material safely derives properly-contrasting primary/secondary/
  // tertiary/error/onX tones from the seed, exactly like "dark"/"light" do.
  // This also keeps an unedited draft preset (see seedFromDark/Light)
  // visually near-identical to the built-in theme it was cloned from,
  // since it's produced by the same formula with the same seed value.
  AppTheme toAppTheme() {
    var textTheme =
        brightness == Brightness.dark ? interTextTheme : interBlackTextTheme;
    var data = ThemeData.from(
      useMaterial3: true,
      textTheme: textTheme,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: brightness,
        onSurfaceVariant: Colors.grey[600],
        surface: surface,
        surfaceContainerLow: _darken(surface, 0.012),
        surfaceContainerLowest: _darken(surface, 0.022),
      ),
    ).copyWith(
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        selectedTileColor: brightness == Brightness.dark
            ? Colors.grey[850]
            : Colors.grey[100],
        iconColor: onSurface,
      ),
      hintColor: onSurface.withValues(alpha: 0.6),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        scrolledUnderElevation: 0,
      ),
      disabledColor: Colors.grey[850],
    );

    return AppTheme(
      key: "custom:$id",
      descr: name,
      data: data,
      extraColors: CustomColors(successOnSurface: success),
      extraTextStyles: CustomTextStyles(
        chatListGcIndicator: TextStyle(
          fontStyle: FontStyle.italic,
          color: onSurface.withValues(alpha: 0.6),
        ),
      ),
      areaStyles: areas,
      presetDir: sourceDir,
    );
  }

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0')}';
  static Color _fromHex(String s) =>
      Color(int.parse(s.replaceFirst('#', ''), radix: 16));

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "brightness": brightness.name,
        "palette": {
          for (var slot in PaletteSlot.values)
            slot.name: _hex(forSlot(slot)),
        },
        if (extraPaletteColors.isNotEmpty)
          "extraPaletteColors": extraPaletteColors.map(_hex).toList(),
        "areas": areas.map((k, v) => MapEntry(k.name, v.toJson())),
        if (menuLabels != null) "menuLabels": menuLabels,
        if (menuOrder != null) "menuOrder": menuOrder,
      };

  factory ThemePreset.fromJson(Map<String, dynamic> j) {
    var p = j["palette"] as Map<String, dynamic>;
    var preset = seedFromDark().copyWith(
      id: j["id"],
      name: j["name"] ?? "Default Theme",
      brightness:
          j["brightness"] == "light" ? Brightness.light : Brightness.dark,
    );
    for (var slot in PaletteSlot.values) {
      var hex = p[slot.name];
      if (hex != null) preset = preset.withSlot(slot, _fromHex(hex));
    }
    return preset.copyWith(
      extraPaletteColors: j["extraPaletteColors"] != null
          ? (j["extraPaletteColors"] as List)
              .map((h) => _fromHex(h as String))
              .toList()
          : const [],
      // Skip any area key that no longer matches a known ThemeArea (e.g.
      // saved by a future/older version of the app) instead of throwing.
      areas: Map.fromEntries((j["areas"] as Map<String, dynamic>? ?? {})
          .entries
          .where((e) => ThemeArea.values.any((a) => a.name == e.key))
          .map((e) => MapEntry(
              ThemeArea.values.firstWhere((a) => a.name == e.key),
              AreaStyle.fromJson(e.value as Map<String, dynamic>)))),
      menuLabels: j["menuLabels"] != null
          ? (j["menuLabels"] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, v as String))
          : null,
      menuOrder: j["menuOrder"] != null
          ? (j["menuOrder"] as List).cast<String>()
          : null,
    );
  }

  // Seed palettes to pre-fill the palette editor from - not separate
  // installable presets, just starting points.
  static ThemePreset seedFromDark() => const ThemePreset(
        id: "custom",
        name: "Default Theme",
        brightness: Brightness.dark,
        primary: Color(0xFF19172C),
        secondary: Color(0xFF47464F),
        tertiary: Color(0xFF6F5573),
        error: Color(0xFFBA1A1A),
        surface: Color(0xFF19172C),
        onSurface: Color(0xFFE5E1E9),
        onAccent: Color(0xFFFFFFFF),
        outline: Color(0xFF47464F),
        success: Color(0xFF2D882D),
        accent: Color(0xFFFFC107),
      );

  static ThemePreset seedFromLight() => const ThemePreset(
        id: "custom",
        name: "Default Theme",
        brightness: Brightness.light,
        primary: Color(0xFFE8E7F3),
        secondary: Color(0xFF45464F),
        tertiary: Color(0xFF6F5573),
        error: Color(0xFFBA1A1A),
        surface: Color(0xFFE8E7F3),
        onSurface: Color(0xFF1B1B1F),
        onAccent: Color(0xFFFFFFFF),
        outline: Color(0xFF45464F),
        success: Color(0xFF2D882D),
        accent: Color(0xFFFF6F00),
      );
}
