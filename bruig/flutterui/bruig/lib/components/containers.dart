import 'package:bruig/components/empty_widget.dart';
import 'package:bruig/models/theme_preset.dart';
import 'package:bruig/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// BisonRelayLogo renders the app's logo preserving its true (non-square)
// aspect ratio. The source asset (assets/images/icon.png) is 102x157 --
// taller than it is wide -- so forcing it into a square SizedBox (as
// earlier code in overview.dart/sidebar.dart did) let the image center
// itself within that square by its own aspect ratio, leaving visible empty
// space on the left and right that a left/right Align couldn't close,
// since it only positioned the (mostly-empty) square box, not the glyph.
class BisonRelayLogo extends StatelessWidget {
  static const double aspectRatio = 102 / 157;

  // size is the taller (height) dimension; width is derived from it.
  final double size;
  const BisonRelayLogo({required this.size, super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * aspectRatio,
      height: size,
      child: Image.asset("assets/images/icon.png", fit: BoxFit.fill),
    );
  }
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
  final Widget? child;
  const ThemedArea(
      {required this.area,
      this.fallback = SurfaceColor.surface,
      this.child,
      super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
        builder: (context, theme, _) => theme.areaContainer(area, fallback,
            child: child ?? const Empty()));
  }
}

// Standard container that is painted with a material 3 color and changes
// all text rendered inside to (by default) use the corresponding onXXX color.
class Box extends StatelessWidget {
  final SurfaceColor color;
  final Widget? child;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final BorderRadiusGeometry? borderRadius;
  const Box(
      {this.color = SurfaceColor.surface,
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
    return Consumer<ThemeNotifier>(
        builder: (context, theme, _) => Container(
              margin: margin,
              padding: padding,
              constraints: constraints,
              color: borderRadius == null ? theme.surfaceColor(color) : null,
              decoration: borderRadius == null
                  ? null
                  : BoxDecoration(
                      borderRadius: borderRadius,
                      color: theme.surfaceColor(color)),
              width: width,
              height: height,
              child: DefaultTextStyle.merge(
                  style: theme.textStyleFor(context, null,
                      textColorForSurfaceColor[color] ?? TextColor.onSurface),
                  child: child ?? const Empty()),
            ));
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
    return Material(child: child);
  }
}

// Used on pages that have a secondary side menu when window has desktop size.
class SecondarySideMenu extends StatelessWidget {
  final Widget? child;
  final double? width;
  const SecondarySideMenu({this.child, this.width, super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(builder: (context, theme, _) {
      var areaStyle = theme.areaStyle(ThemeArea.subMenuTabBar);
      var effectiveWidth = areaStyle.width ?? width ?? 120;
      // width is already accounted for above regardless of this check, so
      // it's deliberately left out here -- but padding/margin must be
      // included alongside mode/borderMode, or setting either while mode
      // is still Default would silently be ignored by this shortcut.
      if (areaStyle.mode == AreaBackgroundMode.token &&
          areaStyle.borderMode == AreaBackgroundMode.token &&
          areaStyle.padding == 0 &&
          areaStyle.margin == 0) {
        // Unmodified: reproduce the original plain divider exactly.
        return Container(
          margin: const EdgeInsets.all(1),
          width: effectiveWidth,
          decoration: BoxDecoration(
              border: Border(
                  right: BorderSide(color: theme.extraColors.sidebarDivider))),
          child: child,
        );
      }
      // Customized: use the full background+border (solid/gradient/image)
      // treatment, not just a flat-color border.
      return SizedBox(
        width: effectiveWidth,
        child: theme.areaContainer(ThemeArea.subMenuTabBar, SurfaceColor.surface,
            child: child ?? const Empty()),
      );
    });
  }
}

class SecondarySideMenuList extends StatelessWidget {
  final double? width;
  final List<ListTile>? items;
  final ListView? list;
  final Widget? footer;
  const SecondarySideMenuList(
      {this.width, this.items, this.list, this.footer, super.key});

  Widget _child() {
    if (list != null) {
      return list!;
    }

    if (items != null) {
      return ListView(
          shrinkWrap: true,
          children: items!.map((e) => SecondarySideMenuItem(e)).toList());
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
                    Expanded(
                        child: ListTileTheme.merge(
                            tileColor: theme.colors.surfaceContainerLowest,
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
  final List<ListTile>? items;
  final ListView? list;
  final double? width;
  final Widget? footer;
  final Widget content;
  final bool isDetail;
  final Object? detailKey;
  const SecondarySideMenuLayout(
      {this.items,
      this.list,
      required this.content,
      this.width,
      this.footer,
      this.isDetail = false,
      this.detailKey,
      super.key});

  @override
  State<SecondarySideMenuLayout> createState() =>
      _SecondarySideMenuLayoutState();
}

class _SecondarySideMenuLayoutState extends State<SecondarySideMenuLayout> {
  bool _hovering = false;
  bool _manuallyCollapsed = false;
  // Lets the user reopen the submenu with the toggle handle even while
  // autoHideOnDetail would otherwise keep it hidden (e.g. to jump to a
  // different tab while composing a post or reading a chat). Reset once
  // the caller reports we're no longer in a detail view (or have moved to
  // a different one, per detailKey), so the next detail view starts
  // collapsed again.
  bool _forceShowInDetail = false;

  @override
  void didUpdateWidget(SecondarySideMenuLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDetail && !widget.isDetail) {
      _forceShowInDetail = false;
    } else if (widget.isDetail && oldWidget.detailKey != widget.detailKey) {
      _forceShowInDetail = false;
    }
  }

  Widget _menuList(double? width) => SecondarySideMenuList(
      width: width, items: widget.items, list: widget.list, footer: widget.footer);

  // Thin edge strip for hoverReveal's collapsed state: a divider line with
  // a pill-shaped chevron indicator, centered vertically -- styled like an
  // active-item highlight so it reads as part of the submenu rather than a
  // bare divider.
  Widget _hoverEdgeStrip(ThemeNotifier theme, {required bool showArrow}) {
    const width = 22.0;
    const pillHeight = 40.0;
    return Container(
      width: width,
      decoration: BoxDecoration(
        border:
            Border(right: BorderSide(color: theme.extraColors.sidebarDivider)),
      ),
      child: !showArrow
          ? null
          : Center(
              child: Container(
                width: width,
                height: pillHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colors.primary.withValues(alpha: 0.16),
                  borderRadius:
                      const BorderRadius.horizontal(right: Radius.circular(8)),
                ),
                child: Icon(Icons.chevron_right,
                    size: 22, color: theme.colors.primary),
              ),
            ),
    );
  }

  // Persistent handle for manualToggle and for reopening an
  // autoHideOnDetail submenu -- always shown/tappable, not tied to any
  // particular item, since the user is explicitly choosing to open/close it.
  Widget _toggleHandle(ThemeNotifier theme,
          {required bool collapsed, required VoidCallback onTap}) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: 16,
            decoration: BoxDecoration(
              border: Border(
                  right: BorderSide(color: theme.extraColors.sidebarDivider)),
            ),
            child: Icon(collapsed ? Icons.chevron_right : Icons.chevron_left,
                size: 16),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(builder: (context, theme, _) {
      var style = theme.areaStyle(ThemeArea.subMenuTabBar).subMenuStyle ??
          SubMenuStyle.alwaysVisible;

      if (style == SubMenuStyle.autoHideOnDetail && widget.isDetail) {
        if (_forceShowInDetail) {
          return Row(children: [
            _menuList(widget.width),
            _toggleHandle(theme,
                collapsed: false,
                onTap: () => setState(() => _forceShowInDetail = false)),
            Expanded(child: widget.content),
          ]);
        }
        return Row(children: [
          _toggleHandle(theme,
              collapsed: true,
              onTap: () => setState(() => _forceShowInDetail = true)),
          Expanded(child: widget.content),
        ]);
      }

      if (style == SubMenuStyle.hoverReveal) {
        var expandedWidth = widget.width ?? 130;
        // The panel is built once at its full width and slides in/out via
        // position, not width -- animating width instead would reflow the
        // text inside on every frame, reading as the labels "being typed
        // out" rather than a clean slide.
        return Stack(children: [
          Row(children: [
            const SizedBox(width: 22),
            Expanded(child: widget.content),
          ]),
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            width: 22,
            child: MouseRegion(
              onEnter: (_) => setState(() => _hovering = true),
              child: IgnorePointer(
                ignoring: _hovering,
                child: _hoverEdgeStrip(theme,
                    showArrow:
                        theme.areaStyle(ThemeArea.subMenuTabBar).showHoverArrow),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            top: 0,
            bottom: 0,
            left: _hovering ? 0 : -expandedWidth,
            width: expandedWidth,
            child: MouseRegion(
              onEnter: (_) => setState(() => _hovering = true),
              onExit: (_) => setState(() => _hovering = false),
              child: _menuList(expandedWidth),
            ),
          ),
        ]);
      }

      if (style == SubMenuStyle.manualToggle) {
        return Row(children: [
          if (!_manuallyCollapsed) _menuList(widget.width),
          _toggleHandle(theme,
              collapsed: _manuallyCollapsed,
              onTap: () =>
                  setState(() => _manuallyCollapsed = !_manuallyCollapsed)),
          Expanded(child: widget.content),
        ]);
      }

      // alwaysVisible (default).
      return Row(children: [
        _menuList(widget.width),
        Expanded(child: widget.content),
      ]);
    });
  }
}

