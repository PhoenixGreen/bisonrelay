import 'dart:io';
import 'dart:math' as math;

import 'package:bruig/components/empty_widget.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:bruig/storage_manager.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

// BisonRelayLogo renders the app's icon at a given size, wherever the app
// draws it -- the header, the nav bar, the About button.
//
// Unmodified it's the built-in asset, kept at its true (non-square) aspect
// ratio: assets/images/icon.png is 102x157 -- taller than it is wide -- so
// forcing it into a square SizedBox (as earlier code in overview.dart/
// sidebar.dart did) let the image center itself within that square by its
// own aspect ratio, leaving visible empty space on the left and right that
// a left/right Align couldn't close, since it only positioned the
// (mostly-empty) square box, not the glyph.
//
// A user-supplied icon (AreaStyle.logoPath on the header area, applied
// app-wide) can be any shape, so it gets a square box of the requested size
// and is fitted inside it -- there's no aspect ratio to build the box from
// without decoding the image first, and contain within a known box keeps
// every call site's layout predictable while never distorting the picture.
class BisonRelayLogo extends StatelessWidget {
  static const double aspectRatio = 102 / 157;
  static const String assetPath = "assets/images/icon.png";

  // size is the taller (height) dimension; width is derived from it.
  final double size;
  const BisonRelayLogo({required this.size, super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(builder: (context, theme, _) {
      var custom = customAppIcon(theme, size);
      if (custom != null) return custom;
      return SizedBox(
        width: size * aspectRatio,
        height: size,
        child: Image.asset(assetPath, fit: BoxFit.fill),
      );
    });
  }
}

// customAppIcon is the user's own app icon at `size`, or null when they
// haven't set one. Separate from BisonRelayLogo for the call sites that
// draw the icon themselves rather than through it (the About button).
//
// SVG is resolved through flutter_svg, which the app already uses for its
// menu icons; anything else goes through Image.file.
Widget? customAppIcon(ThemeNotifier theme, double size) {
  var logoPath = theme.areaStyle(ThemeArea.header).logoPath;
  var dir = theme.fullTheme.presetDir;
  if (logoPath == null || dir == null) return null;
  var file = File(p.join(dir, logoPath));
  return SizedBox(
    width: size,
    height: size,
    child: logoPath.toLowerCase().endsWith(".svg")
        ? SvgPicture.file(file, fit: BoxFit.contain)
        : Image.file(file,
            fit: BoxFit.contain,
            // A path that no longer resolves (the preset's directory moved
            // or was cleaned up) shouldn't leave a broken-image box in the
            // app's chrome.
            errorBuilder: (context, error, stack) =>
                Image.asset(BisonRelayLogo.assetPath, fit: BoxFit.contain)),
  );
}

// ThemedArea wraps a whole visual region (e.g. the master background, the
// header, a whole content page) with a per-area style override -- border,
// gradient/solid fill, background image -- coming from the active
// ThemePreset, if any. With no override configured for the area, it renders
// identically to a plain Container filled with the given SurfaceColor token
// (i.e. exactly how the area rendered before this feature existed).
class ThemedArea extends StatelessWidget {
  final ThemeArea area;
  final SurfaceColor fallback;
  // tokenColor is what this area's "Default" background paints, for the
  // areas whose default is a palette slot of their own rather than a
  // ColorScheme token. Null keeps the token.
  final Color? tokenColor;
  final Widget? child;
  const ThemedArea(
      {required this.area,
      this.fallback = SurfaceColor.surface,
      this.tokenColor,
      this.child,
      super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
        builder: (context, theme, _) => theme.areaContainer(area, fallback,
            tokenColor: tokenColor, child: child ?? const Empty()));
  }
}

// Standard container that is painted with a material 3 color and changes
// all text rendered inside to (by default) use the corresponding onXXX color.
class Box extends StatelessWidget {
  final SurfaceColor color;
  // overrideColor paints over `color`'s resolved ColorScheme token with a
  // specific raw Color instead -- for palette fields (e.g. "News
  // background") that aren't part of the compiled ColorScheme at all, so
  // there's no SurfaceColor token to point `color` at. `color`'s own
  // token is still used to pick the auto-contrasting text color below,
  // since overrideColor has no equivalent "on this color" role to read.
  final Color? overrideColor;
  final Widget? child;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final BorderRadiusGeometry? borderRadius;
  const Box(
      {this.color = SurfaceColor.surface,
      this.overrideColor,
      this.child,
      this.padding,
      this.constraints,
      this.margin,
      this.width,
      this.height,
      this.borderRadius,
      super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(builder: (context, theme, _) {
      var resolvedColor = overrideColor ?? theme.surfaceColor(color);
      return Container(
        margin: margin,
        padding: padding,
        constraints: constraints,
        color: borderRadius == null ? resolvedColor : null,
        decoration: borderRadius == null
            ? null
            : BoxDecoration(borderRadius: borderRadius, color: resolvedColor),
        width: width,
        height: height,
        child: DefaultTextStyle.merge(
            style: theme.textStyleFor(context, null,
                textColorForSurfaceColor[color] ?? TextColor.onSurface),
            child: child ?? const Empty()),
      );
    });
  }
}

// SecondarySideMenuItem is an individual item (ListTile or similar) of a
// SecondarySideMenu. This is needed to fix
// https://github.com/flutter/flutter/issues/59511.
class SecondarySideMenuItem extends StatelessWidget {
  final Widget child;
  const SecondarySideMenuItem(this.child, {super.key});

  @override
  Widget build(BuildContext context) {
    // type: MaterialType.transparency is required here -- Material's
    // default type (canvas) paints an opaque fill using canvasColor when
    // no explicit color is given, and canvasColor is pinned to Primary in
    // ThemePreset.toAppTheme(). That silently painted every single row
    // Primary-colored, hiding the Sidebar background underneath it
    // entirely -- only the empty space past the last row (never wrapped in
    // a Material at all) ever showed the real Sidebar background, which is
    // exactly the "rows are one color, empty space below is another" split
    // that kept getting reported. This Material's only job is to give each
    // row's InkWell something to paint ink splashes into, so it should be
    // as invisible as the same fix already applied to
    // SecondarySideMenuList's own wrapping Material.
    return Material(type: MaterialType.transparency, child: child);
  }
}

// SidebarNavItem describes one fixed-list nav row (Settings' Account/
// Appearance/..., LN Management's Overview/Accounts/..., etc.) in a
// screen-agnostic way, so SecondarySideMenuList/Layout can render every such
// sidebar identically -- including the optional icon+pill-highlight look
// (see AreaStyle.sidebarIconRows) -- from one shared implementation instead
// of each screen (or, previously, just Settings) rolling its own row widget.
class SidebarNavItem {
  final IconData? icon;
  final String label;
  final Widget? trailing;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  const SidebarNavItem({
    this.icon,
    required this.label,
    this.trailing,
    this.selected = false,
    this.enabled = true,
    required this.onTap,
  });
}

// _SidebarNavRow renders a single SidebarNavItem, in either of the Sidebar
// area's two looks:
// - plain (AreaStyle.sidebarIconRows == false, the default/unmodified
//   look): today's ListTile.
// - icon-row (sidebarIconRows == true): a pill-highlight row with a leading
//   icon, generalized from a Settings-only nav that used to implement this
//   look itself, behind its own toggle, for that one screen.
// Both modes share the same text+icon color resolution -- Sidebar text/
// accent are top-level palette slots now (not per-area overrides), since
// there's only ever one sidebar per theme.
class _SidebarNavRow extends StatelessWidget {
  final SidebarNavItem item;
  const _SidebarNavRow(this.item);

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(builder: (context, theme, _) {
      var style = theme.areaStyle(ThemeArea.subMenuTabBar);
      // theme.textStyleFor(..., null) only carries a fontSize (color is left
      // null/inherited) -- copyWith below only overrides color when we pass
      // a non-null one, so the default (unmodified) look is untouched.
      var baseStyle = theme.textStyleFor(context, TextSize.small, null) ??
          const TextStyle();

      var preset = theme.activePreset;
      var color = item.selected
          ? (preset?.sidebarAccent ?? theme.colors.primary)
          : (preset?.sidebarText ?? theme.colors.onSurfaceVariant);

      var showIcon = style.sidebarShowIcons && item.icon != null;
      var radius = BorderRadius.circular(style.sidebarCornerRadius);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Material(
          // A translucent tint of the same sidebarAccent used for the
          // icon/text above -- previously this read
          // theme.colors.surfaceContainerHighest, a Material tone derived
          // from Primary via ColorScheme.fromSeed, so this (far more
          // visually prominent) highlight pill silently followed Primary
          // edits while the actual Sidebar Accent color field only ever
          // affected the much less noticeable icon/text tint inside it.
          color: item.selected
              ? color.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: item.enabled ? item.onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                if (showIcon) ...[
                  Icon(item.icon, size: 19, color: color),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(item.label,
                      // A nav label is a name, not prose: too little room
                      // should shorten it, never wrap it onto a second line
                      // -- which Flutter does by breaking mid-word when a
                      // single word doesn't fit ("Overvie/w"). sidebarWidth
                      // keeps there being room in the first place; this
                      // makes the degradation graceful if a caller or a
                      // large font scale still runs out.
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: baseStyle.copyWith(
                        fontWeight:
                            item.selected ? FontWeight.w600 : FontWeight.w500,
                        color: color,
                      )),
                ),
                if (item.trailing != null) item.trailing!,
              ]),
            ),
          ),
        ),
      );
    });
  }
}

// sidebarWidth is how wide any of the app's sidebars actually renders: what
// was asked for, never below a floor that keeps a row from collapsing into
// unreadability. The default is only reached by a sidebar whose width can
// be neither measured nor declared.
const double _sidebarDefaultWidth = 200;
const double _sidebarMinWidth = 120;

double sidebarWidth(double? requested) =>
    math.max(requested ?? _sidebarDefaultWidth, _sidebarMinWidth);

// measuredSidebarWidth is the width a fixed-item sidebar's own labels need:
// the widest of them at its boldest (selected) weight, plus everything the
// row puts around it.
//
// Sizing to this beats any fixed number, because the right number differs
// per screen and per setting: the hardcoded 130-200px these screens each
// declared were both too narrow for some (labels wrapping mid-word --
// "Overvie/w" -- once Show icons was turned on) and too wide for others (a
// column of short names with dead space beside them). It also follows the
// font scale and the icon toggle for free, since both feed into what's
// measured here.
//
// Only fixed-item sidebars can be measured. A dynamic `list:` one -- the
// chat list, RTC sessions, page-view sessions -- has no labels to measure
// at this level, so those keep the width their screen declares.
double measuredSidebarWidth(
    BuildContext context, ThemeNotifier theme, List<SidebarNavItem> items) {
  var areaStyle = theme.areaStyle(ThemeArea.subMenuTabBar);
  var base =
      theme.textStyleFor(context, TextSize.small, null) ?? const TextStyle();
  var labelStyle = base.copyWith(fontWeight: FontWeight.w600);
  var scaler = MediaQuery.textScalerOf(context);

  var widest = 0.0;
  var hasTrailing = false;
  var hasIcons = false;
  for (var item in items) {
    hasTrailing = hasTrailing || item.trailing != null;
    hasIcons = hasIcons || item.icon != null;
    var painter = TextPainter(
      text: TextSpan(text: item.label, style: labelStyle),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    widest = math.max(widest, painter.width);
  }

  // Everything a row puts either side of its label: _SidebarNavRow's outer
  // 8 and inner 14 horizontal padding, the leading icon and its gap when
  // icons are on, an allowance for a trailing badge, the container's own
  // 1px margin and its divider, and a few px of slack so text never sits
  // flush against the edge.
  var chrome = (8 + 14) * 2 +
      (areaStyle.sidebarShowIcons && hasIcons ? 19 + 12 : 0) +
      (hasTrailing ? 28 : 0) +
      3 +
      6;
  return widest + chrome;
}

// sidebarEdgeColor/sidebarEdgeWidth resolve the sidebar's right edge the
// same way SecondarySideMenu paints it -- the area's own Border once one is
// set, otherwise the built-in divider -- so every edge any sidebar draws
// matches, not just the always-visible one's.
Color sidebarEdgeColor(ThemeNotifier theme) {
  var style = theme.areaStyle(ThemeArea.subMenuTabBar);
  if (style.borderMode != AreaBackgroundMode.token) {
    var c = style.resolveBorderColor(theme);
    if (c != null) return c;
    // A gradient border has no single color; these callers (drag handles
    // and the like) need one, so take the color the gradient starts from
    // rather than dropping back to the built-in divider, which would leave
    // the handle a visibly different color from the edge beside it.
    var grad = style.resolveBorderGradientColors(theme);
    if (grad.isNotEmpty) return grad.first;
  }
  return theme.activePreset?.outline ?? theme.extraColors.sidebarDivider;
}

double sidebarEdgeWidth(ThemeNotifier theme) {
  var style = theme.areaStyle(ThemeArea.subMenuTabBar);
  var right = style.borderWidths.right;
  return style.borderMode != AreaBackgroundMode.token && right > 0 ? right : 1;
}

/// contentAreaOverlay wraps whatever any screen is about to draw as its
/// content area -- the region beside a sidebar, not the whole page.
///
/// One hook rather than a line in every screen, because the content area is
/// already the one thing every layout in the app agrees on: SecondarySideMenu-
/// Layout puts its content through [contentAreaFrame], and the two screens
/// that lay their own sidebar out (the feed, the writing page) call it
/// themselves. Anything wrapped here therefore lands inside the region the
/// reader thinks of as "the page", on every screen, without this file or those
/// screens knowing what was wrapped.
///
/// Inverted deliberately: the notes button and panel are the only user of it
/// today (see plugin_system/writing_tools/notes), and a component this generic
/// must not import a feature. The feature registers itself at startup, exactly
/// as a capability registers its settings section -- see
/// plugin_system/plugin_settings.dart, which makes the same trade for the same
/// reason.
///
/// A wrapper must tolerate being applied more than once on one screen: the
/// feed nests content areas. Handling that is the wrapper's business, not this
/// hook's.
Widget Function(Widget content)? contentAreaOverlay;

// contentAreaFrame wraps a screen's content in the Content Area's own
// styling -- what puts space or a border between a sidebar and the content
// beside it, and what draws a border around, say, the chat area. Screens
// that lay their own sidebar out (the feed's panel) call this themselves;
// SecondarySideMenuLayout does it for everything else.
//
// Only wrapped once that area has actually been given something: an
// untouched area still resolves to an opaque token-colored box, which would
// paint over content that never had a background of its own.
Widget contentAreaFrame(ThemeNotifier theme, Widget content) {
  // Anything a feature wants drawn over every content area, in every screen,
  // goes on before the styling gate below -- so it appears whether or not the
  // area has been given a background of its own. See [contentAreaOverlay].
  content = contentAreaOverlay?.call(content) ?? content;

  // Its Background "Default" is the palette's Content Background, seeded to
  // the same value as Master Background so this paints what showed through
  // before it existed. The built-in themes have no palette to read, so they
  // keep the old behavior of only wrapping once something is set.
  var token = theme.activePreset?.contentBackground;
  if (token == null &&
      !theme.areaStyle(ThemeArea.contentArea).hasVisibleFrame) {
    return content;
  }
  return ThemedArea(
      area: ThemeArea.contentArea, tokenColor: token, child: content);
}

// contentAreaBackgroundColor is the colour the Content Area actually paints
// -- what a screen sitting inside that frame should match when it needs to
// paint a background of its own. The area's own Background setting first,
// since that's what the user last chose; the palette's Content Background
// otherwise. A gradient or image background has no single colour to match,
// so those fall back to the palette slot rather than guessing an end stop.
Color? contentAreaBackgroundColor(ThemeNotifier theme) {
  var style = theme.areaStyle(ThemeArea.contentArea);
  if (style.mode == AreaBackgroundMode.solid) {
    return style.resolveSolidColor(theme) ??
        theme.activePreset?.contentBackground;
  }
  return theme.activePreset?.contentBackground;
}

// dualPanelFrame wraps a whole page -- its sidebar and its content, as one
// region -- in the Dual Panel area's styling, so a border on it goes round
// the outside of both. Same gate as contentAreaFrame: an untouched area
// still resolves to an opaque token-colored box, which would paint over
// every page in the app.
Widget dualPanelFrame(ThemeNotifier theme, Widget page) {
  // Same as contentAreaFrame: "Default" is the palette's Dual Background.
  var token = theme.activePreset?.dualBackground;
  if (token == null && !theme.areaStyle(ThemeArea.dualPanel).hasVisibleFrame) {
    return page;
  }
  return ThemedArea(area: ThemeArea.dualPanel, tokenColor: token, child: page);
}

// sidebarBackgroundColor is the fill every sidebar in the app shares -- the
// "Sidebar Background" palette slot, read live so it follows palette edits.
Color sidebarBackgroundColor(ThemeNotifier theme) =>
    theme.activePreset?.sidebarBackground ?? theme.colors.surface;

// Used on pages that have a secondary side menu when window has desktop size.
class SecondarySideMenu extends StatelessWidget {
  final Widget? child;
  final double? width;
  // fillWidth takes whatever width the parent gives instead of setting one.
  // For a screen that sizes its own sidebar (the feed's drag-resizable
  // panel) but still wants the background, border and spacing every other
  // sidebar gets from here.
  final bool fillWidth;
  const SecondarySideMenu(
      {this.child, this.width, this.fillWidth = false, super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(builder: (context, theme, _) {
      var areaStyle = theme.areaStyle(ThemeArea.subMenuTabBar);
      var effectiveWidth = fillWidth ? null : sidebarWidth(width);
      // The Sidebar's *Default* background is the "Sidebar background"
      // color palette slot, read live, so it can never silently diverge
      // from what the palette editor shows (a stored solidColor snapshot
      // wouldn't update when the palette color is edited later). Any other
      // Background mode resolves through AreaStyle like every other area.
      var bg = areaStyle.toBoxDecoration(theme, SurfaceColor.surface,
          presetDir: theme.fullTheme.presetDir);
      var background = areaStyle.mode == AreaBackgroundMode.token
          ? sidebarBackgroundColor(theme)
          : bg.color;
      // The right edge, by one rule in both branches below so that merely
      // adding padding or a margin can't make the divider disappear: the
      // area's own Border once one is set, otherwise the built-in divider.
      // Setting a Border color is therefore also the only route to *no*
      // divider -- split Border width per side and leave the right at 0.
      //
      // The built-in divider's "Default" looks the same as explicitly
      // picking Outline (Borders/Dividers) from the palette; extraColors
      // .sidebarDivider is an unrelated hardcoded fallback (black for every
      // custom preset), not the preset's own outline swatch, so it's only
      // reached by the built-in themes, which have no preset to read and so
      // keep their original divider color.
      //
      // A gradient or image border is not a BorderSide and cannot go in a
      // BoxDecoration at all, so it is painted by wrapBorderOnly below --
      // an outer box carrying the fill, inset by the border widths -- the
      // same way the nav bar draws one. Before that, picking Border >
      // Gradient here resolved to no flat color, so the sidebar fell
      // through to its built-in divider and the setting appeared to do
      // nothing.
      var liveBorderColor = areaStyle.resolveBorderColor(theme);
      var gradientBorder = areaStyle.borderMode != AreaBackgroundMode.token &&
          areaStyle.borderMode != AreaBackgroundMode.solid &&
          areaStyle.hasBorderWidth;
      var hasOwnBorder = areaStyle.borderMode == AreaBackgroundMode.solid &&
          liveBorderColor != null &&
          areaStyle.hasBorderWidth;
      var border = gradientBorder
          ? null
          : hasOwnBorder
              ? areaStyle.borderSides(liveBorderColor)
              : Border(
                  right: BorderSide(
                      color: theme.activePreset?.outline ??
                          theme.extraColors.sidebarDivider));
      // Flutter refuses to paint a non-uniform border with a borderRadius,
      // and a lone right-hand divider never is uniform (see AreaStyle
      // .toBoxDecoration, which drops the radius on the same grounds).
      // (A gradient border leaves `border` null and is painted outside this
      // box, so the rounding is kept.)
      var borderRadius =
          border == null || border.isUniform ? bg.borderRadius : null;

      var spaced = !areaStyle.paddings.isZero || !areaStyle.margins.isZero;
      if (!hasOwnBorder && !gradientBorder && !spaced) {
        // Unmodified: reproduce the original plain divider exactly.
        return Container(
          margin: const EdgeInsets.all(1),
          width: effectiveWidth,
          decoration: BoxDecoration(
            color: background,
            gradient: bg.gradient,
            image: bg.image,
            border: border,
          ),
          child: child,
        );
      }
      // Customized border/padding/margin: same background fill and right
      // edge as above, with the area's own spacing on top.
      Widget body = Container(
        padding: areaStyle.paddings.insets,
        decoration: BoxDecoration(
          color: background,
          gradient: bg.gradient,
          image: bg.image,
          border: border,
          borderRadius: borderRadius,
        ),
        child: child,
      );
      if (gradientBorder) {
        body = areaStyle.wrapBorderOnly(theme, SurfaceColor.surface,
            presetDir: theme.fullTheme.presetDir, child: body);
      }
      return SizedBox(
        width: effectiveWidth,
        // The margin goes outside the border, not between it and the fill,
        // so a gradient border stays on the sidebar's own edge.
        child: Container(margin: areaStyle.margins.insets, child: body),
      );
    });
  }
}

class SecondarySideMenuList extends StatelessWidget {
  final double? width;
  final List<SidebarNavItem>? items;
  final Widget? list;
  final Widget? header;
  final Widget? footer;
  const SecondarySideMenuList(
      {this.width, this.items, this.list, this.header, this.footer, super.key});

  Widget _child() {
    if (list != null) {
      return list!;
    }

    if (items != null) {
      return ListView(
          shrinkWrap: true,
          children: items!
              .map((e) => SecondarySideMenuItem(_SidebarNavRow(e)))
              .toList());
    }

    return const Empty();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
        builder: (context, theme, _) => SecondarySideMenu(
              width: width,
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ...(header != null ? [header!] : []),
                    Expanded(
                        child: ListTileTheme.merge(
                            tileColor: theme.activePreset?.sidebarBackground ??
                                theme.colors.surfaceContainerLowest,
                            // tileColor: Colors.amber,
                            // ListTile.tileColor needs a nearby Material
                            // ancestor to paint into and to render ink
                            // splashes. `items:` callers already get one per
                            // row via SecondarySideMenuItem, but a caller
                            // passing `list:` (a raw ListView of its own
                            // ListTiles) doesn't -- and when this area's
                            // style is customized, SecondarySideMenu wraps
                            // everything in a colored areaContainer further
                            // out, which then hides the tile's background/
                            // splashes. MaterialType.transparency paints
                            // nothing itself, so it just provides that
                            // ancestor without changing appearance.
                            child: Material(
                                type: MaterialType.transparency,
                                child: _child()))),
                    ...(footer != null ? [footer!] : []),
                  ]),
            ));
  }
}

// SecondarySideMenuLayout combines a page's submenu (its sub-navigation
// tabs, e.g. Settings' Account/Appearance/Notifications/... list, or a
// dynamic list like Chat's contacts) with its main content, hiding/
// revealing the submenu per SubMenuStyle (see theme_preset.dart). Exactly
// one of `items`/`list` must be given, matching SecondarySideMenuList's own
// dual API.
//
// isDetail lets a caller flag "the content right now doesn't need
// sub-navigation" (e.g. Feed showing a single post, LN Management routed
// to a specific tab via arguments) -- only consulted when the active style
// is autoHideOnDetail. detailKey identifies *which* detail is being shown
// (e.g. the open chat's id, or the post being read) -- when it changes
// while isDetail stays true (switching straight from one detail view to
// another, e.g. clicking a different chat), any manual reopen of the
// submenu resets, so the new detail view starts collapsed again too.
class SecondarySideMenuLayout extends StatefulWidget {
  final List<SidebarNavItem>? items;
  final Widget? list;
  final double? width;
  final Widget? header;
  final Widget? footer;
  final Widget content;
  final bool isDetail;
  final Object? detailKey;

  /// collapseSidebar hands the sidebar to the drawer even on a wide window,
  /// for a screen whose content wants the room for a while -- the file
  /// preview, which is something being read or watched rather than a list
  /// being scanned.
  ///
  /// Deliberately the same path a narrow window takes rather than simply
  /// not drawing it: that registers the sidebar with CollapsedSidebarModel,
  /// so re-tapping the destination in the main navigation still slides it
  /// in. A sidebar that is merely hidden is one the reader cannot get back.
  final bool collapseSidebar;

  /// sidebarRevision is whatever this screen's sidebar would look different
  /// for, so the collapsed drawer knows to redraw it. Only needed by a
  /// sidebar whose contents change while it is open -- see
  /// CollapsedSidebarModel.register.
  final Object? sidebarRevision;
  // storageKey identifies this screen's sidebar for width persistence when
  // AreaStyle.subMenuStyle is SubMenuStyle.resizable -- since subMenuTabBar
  // is one shared style for every sidebar in the app, each screen must
  // remember its own dragged width independently (e.g. Settings' sidebar
  // shouldn't jump to whatever width the chat list was last dragged to).
  final String storageKey;
  const SecondarySideMenuLayout(
      {this.items,
      this.list,
      required this.content,
      required this.storageKey,
      this.width,
      this.header,
      this.footer,
      this.isDetail = false,
      this.detailKey,
      this.sidebarRevision,
      this.collapseSidebar = false,
      super.key});

  @override
  State<SecondarySideMenuLayout> createState() =>
      _SecondarySideMenuLayoutState();
}

// _sidebarWidthCache holds the last-known resizable width for each
// storageKey for the lifetime of the app process. A screen's
// SecondarySideMenuLayout State gets torn down and recreated on every
// navigation away and back (each screen is a fresh Navigator route), so
// relying solely on an async StorageManager read in initState races: by the
// time the read resolves the State may already be gone (or the user may
// already be looking at the default width). Reading this synchronous cache
// first means a revisited screen shows its last dragged width immediately,
// with StorageManager only needed to seed it once per app run and to
// survive an app restart.
final Map<String, double> _sidebarWidthCache = {};

class _SecondarySideMenuLayoutState extends State<SecondarySideMenuLayout> {
  // Below this width the sidebar becomes an overlay drawer instead of a
  // column. See _compactLayout.
  static const _collapseBelowWidth = kSidebarCollapseWidth;

  // Drag-resized width for SubMenuStyle.resizable, persisted per screen (see
  // storageKey doc above). Null until loaded/dragged, meaning "use the
  // caller's declared default width".
  double? _resizableWidth;
  static const _resizableMinWidth = 180.0;
  static const _resizableMaxWidth = 560.0;

  String get _widthStorageKey => "sidebarWidth_${widget.storageKey}";

  @override
  void dispose() {
    // This screen's sidebar goes with this screen. Screens that never
    // register one have nothing to clear it, so leaving it would put this
    // sidebar in the drawer over whatever the user opened next.
    //
    // Scoped to this registration: on a navigation the new screen registers
    // before the old one is disposed, and an unscoped clear here would wipe
    // the sidebar that had just arrived.
    _client?.ui.collapsedSidebar.unregister(owner: this);
    super.dispose();
  }

  // Captured while mounted, since dispose cannot reach the provider tree.
  ClientModel? _client;

  @override
  void initState() {
    super.initState();
    final cached = _sidebarWidthCache[widget.storageKey];
    if (cached != null) {
      _resizableWidth = cached;
    } else {
      _loadResizableWidth();
    }
  }

  Future<void> _loadResizableWidth() async {
    final v = await StorageManager.readData(_widthStorageKey);
    if (v is num) {
      _sidebarWidthCache[widget.storageKey] = v.toDouble();
      if (mounted) {
        setState(() => _resizableWidth = v.toDouble());
      }
    }
  }

  void _setResizableWidth(double w) {
    _sidebarWidthCache[widget.storageKey] = w;
    setState(() => _resizableWidth = w);
  }

  void _saveResizableWidth() {
    final w = _resizableWidth;
    if (w != null) {
      StorageManager.saveData(_widthStorageKey, w);
    }
  }

  Widget _menuList(double? width, {bool closeOnTap = false}) =>
      SecondarySideMenuList(
          width: width,
          // In the overlay drawer, picking a destination should also put the
          // drawer away -- leaving it covering the very content you just
          // asked for is the classic mobile-nav annoyance. Only possible for
          // a fixed item list; a dynamic `list:` owns its own taps.
          items: closeOnTap && widget.items != null
              ? [
                  for (var item in widget.items!)
                    SidebarNavItem(
                      icon: item.icon,
                      label: item.label,
                      trailing: item.trailing,
                      selected: item.selected,
                      enabled: item.enabled,
                      onTap: () {
                        item.onTap();
                        ClientModel.of(context, listen: false)
                            .ui
                            .collapsedSidebar
                            .close();
                      },
                    )
                ]
              : widget.items,
          list: widget.list,
          header: widget.header,
          footer: widget.footer);

  // _compactLayout is the narrow-window form: the sidebar stops taking a
  // column of its own and is handed to CollapsedSidebarModel, which the
  // main navigation opens on a re-tap and OverviewScreen paints over the
  // top of everything -- the main nav included. Below ~900px a
  // fixed sidebar leaves too little room for content, which is why the
  // feed's own panel already dropped itself there.
  Widget _compactLayout(ClientModel client, double panelWidth) {
    client.ui.collapsedSidebar.register(
        (context) => _menuList(panelWidth, closeOnTap: true), panelWidth,
        revision: widget.sidebarRevision, owner: this);
    return contentAreaFrame(ThemeNotifier.of(context), widget.content);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return Consumer<ThemeNotifier>(builder: (context, theme, _) {
        var style = theme.areaStyle(ThemeArea.subMenuTabBar).subMenuStyle ??
            SubMenuStyle.alwaysVisible;
        // A fixed-item sidebar sizes to its own labels; only a dynamic list,
        // which has none to measure, falls back to the width its screen
        // declared. See measuredSidebarWidth.
        var menuWidth = widget.items != null
            ? measuredSidebarWidth(context, theme, widget.items!)
            : widget.width;

        // The drawer, either because it was asked for or because a window
        // this narrow has no usable room for a sidebar column whichever
        // visibility is set.
        var client = ClientModel.of(context, listen: false);
        _client = client;
        if (style == SubMenuStyle.collapsed ||
            constraints.maxWidth < _collapseBelowWidth) {
          return _compactLayout(client, kCollapsedSidebarWidth);
        }

        // An explicit collapse -- the content asking for the room, rather
        // than the window being too narrow to give it -- keeps whichever
        // layout this style already had and empties the sidebar's slot,
        // instead of dropping to the content-only shape above.
        //
        // The shape has to hold still because this one happens mid-session
        // at the reader's request: changing it rebuilds the content's State
        // from scratch, which is what lost the file preview that had just
        // been opened and would reset the list's search and sort besides.
        // (Reaching for a GlobalKey to carry the element across the reshape
        // instead is worse than the problem: reparenting one inside this
        // LayoutBuilder mutates a render object during layout, and the
        // framework asserts outright.)
        //
        // The sidebar is still handed to the drawer, so re-tapping the
        // destination in the main navigation slides it back in.
        if (widget.collapseSidebar) {
          client.ui.collapsedSidebar.register(
              (context) => _menuList(kCollapsedSidebarWidth, closeOnTap: true),
              kCollapsedSidebarWidth,
              revision: widget.sidebarRevision,
              owner: this);
        } else {
          // Wide again: hand the drawer back, so re-tapping this page in the
          // main nav can't open a sidebar that's already on screen.
          client.ui.collapsedSidebar.unregister();
        }

        // The sidebar's slot, kept in the layout even when empty so the
        // content beside it stays at the same position in the tree.
        Widget sidebarSlot(double? width) => widget.collapseSidebar
            ? const SizedBox.shrink()
            : _menuList(width);

        if (style == SubMenuStyle.resizable) {
          var defaultWidth = sidebarWidth(menuWidth);
          var currentWidth = (_resizableWidth ?? defaultWidth)
              .clamp(_resizableMinWidth, _resizableMaxWidth);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sidebarSlot(currentWidth),
              if (widget.collapseSidebar)
                const SizedBox.shrink()
              else
                MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: (d) => _setResizableWidth(
                      (currentWidth + d.delta.dx)
                          .clamp(_resizableMinWidth, _resizableMaxWidth)),
                  onHorizontalDragEnd: (_) => _saveResizableWidth(),
                  onDoubleTap: () {
                    _setResizableWidth(defaultWidth);
                    _saveResizableWidth();
                  },
                  child: SizedBox(
                    width: 8,
                    child: Center(
                      child: SizedBox(
                        width: sidebarEdgeWidth(theme),
                        child: ColoredBox(color: sidebarEdgeColor(theme)),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(child: contentAreaFrame(theme, widget.content)),
            ],
          );
        }

        // alwaysVisible (default).
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          sidebarSlot(menuWidth),
          Expanded(child: contentAreaFrame(theme, widget.content)),
        ]);
      });
    });
  }
}

// kSidebarCollapseWidth is the window width below which a sidebar column
// leaves too little room for content and is handed to the drawer instead.
const double kSidebarCollapseWidth = 900;

/// sidebarIsInDrawer reports whether a sidebar in this space is the drawer's
/// rather than a column of its own -- because the window is too narrow for
/// one, or because the theme asks for the collapsed style.
///
/// Public so a screen can tell whether its own show/hide control would do
/// anything. When the sidebar is the drawer's, only the main navigation's
/// re-tap opens it, and a screen-level toggle is inert: it sets a flag that
/// SecondarySideMenuLayout never reaches, because both conditions below are
/// checked before it looks at collapseSidebar at all.
///
/// Deliberately here beside the layout that acts on it, rather than
/// recomputed by each caller: two copies of this rule would drift, and the
/// symptom of drift is a control that silently does nothing.
bool sidebarIsInDrawer(BuildContext context, double availableWidth) {
  var style = ThemeNotifier.of(context, listen: false)
          .areaStyle(ThemeArea.subMenuTabBar)
          .subMenuStyle ??
      SubMenuStyle.alwaysVisible;
  return style == SubMenuStyle.collapsed ||
      availableWidth < kSidebarCollapseWidth;
}

// kCollapsedSidebarWidth is how wide the narrow-window drawer is, for every
// sidebar. Deliberately one figure rather than each screen's own width: as a
// drawer it's an overlay on a small screen, where what matters is being
// comfortably readable, not matching the column it replaced.
const double kCollapsedSidebarWidth = 325;

// kSidebarResizeMin/Max bound every drag-resizable sidebar in the app.
const double kSidebarResizeMin = 180;
const double kSidebarResizeMax = 560;

// ResizableSidebar remembers a drag-resized width for one screen's sidebar
// and hands back the grab strip to put between it and the content.
//
// SecondarySideMenuLayout has this built in for SubMenuStyle.resizable, but
// a screen that lays its own sidebar out -- the feed's side panel, which
// centers a fixed-width panel and column rather than docking left -- can't
// use that layout without losing its own. The builder form lets it keep
// its layout and still honor the same setting, off the same per-screen
// width store, so a width dragged here survives navigation the same way.
class ResizableSidebar extends StatefulWidget {
  final String storageKey;
  final double defaultWidth;
  final Widget Function(BuildContext context, double width, Widget handle)
      builder;
  const ResizableSidebar({
    required this.storageKey,
    required this.defaultWidth,
    required this.builder,
    super.key,
  });

  @override
  State<ResizableSidebar> createState() => _ResizableSidebarState();
}

class _ResizableSidebarState extends State<ResizableSidebar> {
  double? _width;

  String get _storeKey => "sidebarWidth_${widget.storageKey}";

  @override
  void initState() {
    super.initState();
    // Same two-step as SecondarySideMenuLayout: the synchronous cache first
    // so a revisited screen shows its width immediately, with the async read
    // only needed to seed it once per app run.
    final cached = _sidebarWidthCache[widget.storageKey];
    if (cached != null) {
      _width = cached;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final v = await StorageManager.readData(_storeKey);
    if (v is num) {
      _sidebarWidthCache[widget.storageKey] = v.toDouble();
      if (mounted) setState(() => _width = v.toDouble());
    }
  }

  void _set(double w) {
    _sidebarWidthCache[widget.storageKey] = w;
    setState(() => _width = w);
  }

  void _save() {
    final w = _width;
    if (w != null) StorageManager.saveData(_storeKey, w);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(builder: (context, theme, _) {
      var width = (_width ?? widget.defaultWidth)
          .clamp(kSidebarResizeMin, kSidebarResizeMax);
      var handle = MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: (d) => _set(
              (width + d.delta.dx).clamp(kSidebarResizeMin, kSidebarResizeMax)),
          onHorizontalDragEnd: (_) => _save(),
          onDoubleTap: () {
            _set(widget.defaultWidth);
            _save();
          },
          child: SizedBox(
            width: 8,
            child: Center(
              child: SizedBox(
                width: sidebarEdgeWidth(theme),
                child: ColoredBox(color: sidebarEdgeColor(theme)),
              ),
            ),
          ),
        ),
      );
      return widget.builder(context, width, handle);
    });
  }
}

/// CollapsedSidebarScope marks the subtree that is the collapsed drawer.
///
/// A sidebar looks the same in both places but is not in the same situation:
/// in the drawer it is an overlay with a scrim, put away by tapping off it,
/// so a control of its own for hiding it is one route too many to the same
/// place -- and points the wrong way besides.
class CollapsedSidebarScope extends InheritedWidget {
  const CollapsedSidebarScope({required super.child, super.key});

  /// of reports whether [context] is inside the drawer.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CollapsedSidebarScope>() !=
      null;

  @override
  bool updateShouldNotify(CollapsedSidebarScope oldWidget) => false;
}
