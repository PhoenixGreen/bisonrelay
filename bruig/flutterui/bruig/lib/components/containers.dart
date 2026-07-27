import 'package:bruig/components/empty_widget.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:bruig/storage_manager.dart';
import 'package:bruig/theming_system/theme_manager.dart';
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
    return Consumer<ThemeNotifier>(
        builder: (context, theme, _) {
          var resolvedColor = overrideColor ?? theme.surfaceColor(color);
          return Container(
              margin: margin,
              padding: padding,
              constraints: constraints,
              color: borderRadius == null ? resolvedColor : null,
              decoration: borderRadius == null
                  ? null
                  : BoxDecoration(
                      borderRadius: borderRadius, color: resolvedColor),
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
      var baseStyle =
          theme.textStyleFor(context, TextSize.small, null) ?? const TextStyle();

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
          color: item.selected ? color.withValues(alpha: 0.18) : Colors.transparent,
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
      // The Sidebar's *Default* background is the "Sidebar background"
      // color palette slot, read live, so it can never silently diverge
      // from what the palette editor shows (a stored solidColor snapshot
      // wouldn't update when the palette color is edited later). Any other
      // Background mode resolves through AreaStyle like every other area,
      // just with a flat-color-only border (no gradient/image border
      // support here, matching what the "unmodified" case already only
      // ever supported).
      var bg = areaStyle.toBoxDecoration(theme, SurfaceColor.surface,
          presetDir: theme.fullTheme.presetDir);
      var background = areaStyle.mode == AreaBackgroundMode.token
          ? (theme.activePreset?.sidebarBackground ?? theme.colors.surface)
          : bg.color;
      var liveBorderColor = areaStyle.resolveBorderColor(theme);
      var hasCustomBorder = areaStyle.borderMode != AreaBackgroundMode.token &&
              liveBorderColor != null &&
              areaStyle.hasBorderWidth ||
          !areaStyle.paddings.isZero ||
          !areaStyle.margins.isZero;
      if (!hasCustomBorder) {
        // Unmodified: reproduce the original plain divider exactly.
        return Container(
          margin: const EdgeInsets.all(1),
          width: effectiveWidth,
          decoration: BoxDecoration(
            color: background,
            gradient: bg.gradient,
            image: bg.image,
            border: areaStyle.sidebarShowRightDivider
                ? Border(
                    right: BorderSide(
                        // "Default" should look the same as explicitly
                        // picking Outline (Borders) from the palette --
                        // extraColors.sidebarDivider is an unrelated,
                        // hardcoded fallback (black for every custom
                        // preset), not the preset's own outline swatch.
                        // Built-in (non-custom) themes have no preset to
                        // read, so they keep their original divider color.
                        color: areaStyle.resolveSidebarDividerColor(theme) ??
                            theme.activePreset?.outline ??
                            theme.extraColors.sidebarDivider,
                        width: areaStyle.sidebarDividerWidth))
                : null,
          ),
          child: child,
        );
      }
      // Customized border/padding/margin: same background fill as above,
      // just with the area's own border/spacing treatment on top.
      return SizedBox(
        width: effectiveWidth,
        child: Container(
          margin: areaStyle.margins.insets,
          padding: areaStyle.paddings.insets,
          decoration: BoxDecoration(
            color: background,
            gradient: bg.gradient,
            image: bg.image,
            // bg (from toBoxDecoration) already resolved the per-side
            // border and, with it, whether the radius can survive alongside
            // one -- reuse both rather than re-deriving them here.
            border: (areaStyle.borderMode != AreaBackgroundMode.token &&
                    liveBorderColor != null &&
                    areaStyle.hasBorderWidth)
                ? areaStyle.borderSides(liveBorderColor)
                : null,
            borderRadius: bg.borderRadius,
          ),
          child: child,
        ),
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
          children:
              items!.map((e) => SecondarySideMenuItem(_SidebarNavRow(e))).toList());
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
  bool _hovering = false;
  bool _manuallyCollapsed = false;
  // Lets the user reopen the submenu with the toggle handle even while
  // autoHideOnDetail would otherwise keep it hidden (e.g. to jump to a
  // different tab while composing a post or reading a chat). Reset once
  // the caller reports we're no longer in a detail view (or have moved to
  // a different one, per detailKey), so the next detail view starts
  // collapsed again.
  bool _forceShowInDetail = false;

  // Drag-resized width for SubMenuStyle.resizable, persisted per screen (see
  // storageKey doc above). Null until loaded/dragged, meaning "use the
  // caller's declared default width".
  double? _resizableWidth;
  static const _resizableMinWidth = 180.0;
  static const _resizableMaxWidth = 560.0;

  String get _widthStorageKey => "sidebarWidth_${widget.storageKey}";

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
      width: width,
      items: widget.items,
      list: widget.list,
      header: widget.header,
      footer: widget.footer);

  // Thin edge strip for hoverReveal's collapsed state: a divider line with
  // a pill-shaped chevron indicator, centered vertically -- styled like an
  // active-item highlight so it reads as part of the submenu rather than a
  // bare divider.
  //
  // _dividerColor/_dividerWidth resolve the same way as SecondarySideMenu's
  // own plain-divider path above -- sidebarDividerColor, when set, should
  // apply to every divider the sidebar draws, not just the always-visible
  // one.
  Color _dividerColor(ThemeNotifier theme) =>
      theme
          .areaStyle(ThemeArea.subMenuTabBar)
          .resolveSidebarDividerColor(theme) ??
      theme.activePreset?.outline ??
      theme.extraColors.sidebarDivider;
  double _dividerWidth(ThemeNotifier theme) =>
      theme.areaStyle(ThemeArea.subMenuTabBar).sidebarDividerWidth;

  Widget _hoverEdgeStrip(ThemeNotifier theme, {required bool showArrow}) {
    const width = 22.0;
    const pillHeight = 40.0;
    return Container(
      width: width,
      decoration: BoxDecoration(
        border: Border(
            right: BorderSide(
                color: _dividerColor(theme), width: _dividerWidth(theme))),
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
                  right: BorderSide(
                      color: _dividerColor(theme),
                      width: _dividerWidth(theme))),
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
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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

      if (style == SubMenuStyle.resizable) {
        var defaultWidth = widget.width ?? 130;
        var currentWidth =
            (_resizableWidth ?? defaultWidth).clamp(_resizableMinWidth, _resizableMaxWidth);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _menuList(currentWidth),
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
                      width: _dividerWidth(theme),
                      child: ColoredBox(color: _dividerColor(theme)),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: widget.content),
          ],
        );
      }

      if (style == SubMenuStyle.manualToggle) {
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!_manuallyCollapsed) _menuList(widget.width),
          _toggleHandle(theme,
              collapsed: _manuallyCollapsed,
              onTap: () =>
                  setState(() => _manuallyCollapsed = !_manuallyCollapsed)),
          Expanded(child: widget.content),
        ]);
      }

      // alwaysVisible (default).
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _menuList(widget.width),
        Expanded(child: widget.content),
      ]);
    });
  }
}

