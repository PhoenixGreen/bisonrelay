import 'package:bruig/components/app_notifications.dart';
import 'package:bruig/components/containers.dart';
import 'package:bruig/components/empty_widget.dart';
import 'package:bruig/components/indicator.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/exchange_rate.dart';
import 'package:bruig/models/feed.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/models/notifications.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:bruig/screens/chats.dart';
import 'package:bruig/screens/feed.dart';
import 'package:bruig/theming_system/theme_manager.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sidebarx/sidebarx.dart';
import 'package:window_manager/window_manager.dart';

class Sidebar extends StatefulWidget {
  final ClientModel client;
  final MainMenuModel mainMenu;
  final AppNotifications ntfns;
  final GlobalKey<NavigatorState> navKey;
  final FeedModel feed;

  const Sidebar(this.client, this.mainMenu, this.ntfns, this.navKey, this.feed,
      {super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> with WindowListener {
  ClientModel get client => widget.client;
  MainMenuModel get mainMenu => widget.mainMenu;
  SidebarXController ctrl =
      SidebarXController(selectedIndex: 0, extended: true);
  FeedModel get feed => widget.feed;
  bool hasUnreadMsgs = false;
  double prevWindowSize = -1;

  void feedUpdated() async {
    setState(() {});
  }

  void connStateChanged() async {
    // Needed because the list of menus changes depending on the connstate.
    setState(() {});
  }

  void switchScreen(String route) {
    // Do not change screen if already there.
    String currentPath = "";
    widget.navKey.currentState?.popUntil((route) {
      currentPath = route.settings.name ?? "";
      return true;
    });

    var collapsed = client.ui.collapsedSidebar;
    if (currentPath == route) {
      // Already on this destination, so there's nothing to navigate to --
      // re-tapping it opens that page's own sidebar instead, when the
      // window is narrow enough that it's collapsed into the drawer. This
      // is the only way the drawer opens: re-tapping the destination you're
      // already on is where you'd reach for that page's own list anyway.
      // It toggles, so a third tap puts it away.
      if (collapsed.available) collapsed.toggle();
      return;
    }

    // Actually going somewhere else: don't leave the drawer sitting open
    // over the new page. The destination registers its own sidebar, so
    // leaving it open would swap the contents out from under the user.
    collapsed.close();
    widget.navKey.currentState!.pushReplacementNamed(route);
  }

  void menuUpdated() {
    setState(() {
      // Which row of *this bar* to light up, found by route.
      //
      // Not mainMenu.activeIndex: that is a position in the full menu,
      // which carries entries this bar never draws -- the two hidden
      // route-only items, and now any destination the theme has switched
      // off (see AreaStyle.navRoutes). The hidden two sit at the end, so
      // the two lists agreed by accident for as long as they were the only
      // difference; switching off a destination in the middle put every row
      // below it one out, and the bar highlighted the item under the one
      // that had been tapped. Tapping again appeared to fix it because
      // switchScreen short-circuits when the route is unchanged, so this
      // never ran a second time and SidebarX's own (correct) selection
      // stood.
      var routes = ThemeNotifier.of(context, listen: false)
          .areaStyle(ThemeArea.navBar)
          .navRoutes;
      var index = navItemsFor(mainMenu, routes)
          .indexWhere((e) => e.routeName == mainMenu.activeRoute);
      // A route this bar doesn't carry -- the Address Book reached from the
      // chat list's footer, say. Nothing to light up, so the previous row
      // is left as it is rather than moving the highlight somewhere wrong.
      if (index >= 0) ctrl.selectIndex(index);
    });
  }

  void hasUnreadMsgsChanged() {
    setState(() {
      hasUnreadMsgs = client.hasUnreadChats.val;
    });
  }

  @override
  void onWindowResize() {
    var size = MediaQuery.sizeOf(context);
    if (prevWindowSize < 0) {
      prevWindowSize = size.width;
      return;
    }

    // Check current screen size.  If over 1000px and NOT extended, then extend
    // If NOT over 1000px and extended, then collapse sidebar.
    var newSize = size.width;

    if (newSize < prevWindowSize && newSize < 1000 && ctrl.extended == true) {
      ctrl.setExtended(false);
    } else if (newSize > prevWindowSize &&
        newSize > 1000 &&
        ctrl.extended == false) {
      ctrl.setExtended(true);
    }

    prevWindowSize = size.width;
  }

  @override
  void initState() {
    super.initState();
    feed.addListener(feedUpdated);
    client.connState.addListener(connStateChanged);
    mainMenu.addListener(menuUpdated);
    client.hasUnreadChats.addListener(hasUnreadMsgsChanged);
    windowManager.addListener(this);
  }

  @override
  void didUpdateWidget(Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      oldWidget.feed.removeListener(feedUpdated);
      oldWidget.client.connState.removeListener(connStateChanged);
      oldWidget.mainMenu.removeListener(menuUpdated);
      oldWidget.client.hasUnreadChats.removeListener(hasUnreadMsgsChanged);
      feed.addListener(feedUpdated);
      client.connState.addListener(connStateChanged);
      mainMenu.addListener(menuUpdated);
      client.hasUnreadChats.addListener(hasUnreadMsgsChanged);
    }
  }

  @override
  void dispose() {
    feed.removeListener(feedUpdated);
    client.connState.removeListener(connStateChanged);
    mainMenu.removeListener(menuUpdated);
    client.hasUnreadChats.removeListener(hasUnreadMsgsChanged);
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ClientModel, ThemeNotifier>(
        builder: (context, client, theme, child) {
      var navStyle = theme.areaStyle(ThemeArea.navBar);
      // Computed once and reused both for SidebarXTheme's iconTheme/
      // selectedIconTheme (which only take effect for the package's own
      // default icon rendering, unused here) and for the iconBuilder below
      // (used instead, since it's the only way to also show the unread
      // dot) -- iconBuilder bypasses SidebarXTheme's icon theming entirely,
      // so this app has to apply the selected/unselected color itself.
      // Nav text/accent colors are top-level palette slots now (not
      // per-area overrides), since there's only ever one nav bar per theme.
      var navUnselectedIconColor =
          theme.activePreset?.navText ?? theme.colors.onSurfaceVariant;
      var navSelectedIconColor =
          theme.activePreset?.navSelected ?? theme.colors.primary;
      var navBackground =
          theme.activePreset?.secondary ?? theme.colors.surfaceContainerLow;
      // A border (any mode) makes Container reserve extra inset for it on
      // top of the existing padding, shrinking the content area -- the
      // collapsed sidebar's icon layout already has ~zero slack at its
      // hardcoded width, so any border at all overflows it by a couple of
      // pixels unless the outer width grows to compensate. The parent Row
      // (sidebar + Expanded(Navigator) in overview.dart) absorbs this fine
      // since the Navigator side just gets very slightly narrower.
      var liveBorderColor = navStyle.resolveBorderColor(theme);
      var hasCustomBorder = navStyle.borderMode != AreaBackgroundMode.token &&
          liveBorderColor != null &&
          navStyle.hasBorderWidth;
      var navBorder = navStyle.borderWidths;
      var borderInset =
          hasCustomBorder ? navBorder.left + navBorder.right : 0.0;
      // SidebarXTheme.decoration (below) can only be a flat BoxDecoration,
      // so it can't itself express a gradient/image border (only the
      // background supports those directly here) -- wrapBorderOnly adds
      // that border around the whole widget instead when needed.
      return navStyle.wrapBorderOnly(theme, SurfaceColor.surfaceContainerLow,
          presetDir: theme.fullTheme.presetDir,
          child: SidebarX(
            theme: SidebarXTheme(
              // Fixed, not themed: the Padding/Margin settings are hidden
              // for this area (see theming_areas_section.dart). Routing them
              // to SidebarXTheme's own fields was tried and doesn't move
              // anything -- the package lays this bar out from its own
              // metrics -- so they'd have been two dead sliders.
              margin: const EdgeInsets.all(1),
              padding: const EdgeInsets.all(2),
              width: 70 + borderInset,
              // Background and border are independently checked here --
              // previously the custom Border settings (color/width/radius)
              // were only ever read when Background was ALSO switched away
              // from Default, forcing a background change just to get a
              // border to show at all. navBackground (not a generic
              // SurfaceColor fallback) is used whenever Background itself
              // is still Default, so it stays live-bound to the preset's
              // own Secondary color regardless of whether a custom border
              // is set.
              decoration: navStyle.mode == AreaBackgroundMode.token
                  ? BoxDecoration(
                      color: navBackground,
                      // A non-default image preset paints over that
                      // Secondary background rather than replacing it (the
                      // tiled patterns are translucent), matching what
                      // AreaStyle does for every other area's Default
                      // background.
                      image: navStyle.imagePreset != AreaImagePreset.standard
                          ? areaImagePresetImage(navStyle.imagePreset)
                          : null,
                      border: hasCustomBorder
                          ? navStyle.borderSides(liveBorderColor)
                          : Border(
                              right: BorderSide(
                                  color: theme.extraColors.sidebarDivider)),
                      // No borderRadius unless the border is uniform on all
                      // four sides -- neither the plain right-edge divider
                      // fallback nor a deliberately per-side border can
                      // satisfy Flutter's "uniform border" requirement for
                      // combining with a borderRadius, and Border.paint
                      // asserts on that combination unconditionally.
                      borderRadius: hasCustomBorder && navBorder.isUniform
                          ? navStyle.borderRadii.radius
                          : null,
                    )
                  : theme.areaDecoration(
                      ThemeArea.navBar, SurfaceColor.surfaceContainerLow),
              hoverTextStyle: theme
                  .textStyleFor(context, null, TextColor.onSurfaceVariant)
                  ?.copyWith(color: navUnselectedIconColor),
              textStyle: theme
                  .textStyleFor(context, null, TextColor.onSurfaceVariant)
                  ?.copyWith(color: navUnselectedIconColor),
              // Shares the same accent (and fallback chain) as
              // selectedIconTheme below -- "Nav accent color" is one slot
              // driving both the label and the icon, not just the icon.
              selectedTextStyle: theme
                  .textStyleFor(context, null, TextColor.onSurface)
                  ?.copyWith(color: navSelectedIconColor),
              itemPadding:
                  const EdgeInsets.only(top: 7, bottom: 6, left: 12, right: 12),
              itemMargin:
                  const EdgeInsets.only(top: 5, bottom: 0, left: 5, right: 5),
              selectedItemMargin:
                  const EdgeInsets.only(top: 5, bottom: 0, left: 5, right: 5),
              selectedItemPadding:
                  const EdgeInsets.only(top: 7, bottom: 6, left: 12, right: 12),
              selectedItemTextPadding: const EdgeInsets.only(left: 7),
              itemTextPadding: const EdgeInsets.only(left: 7),
              itemDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
              ),
              selectedItemDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                // A translucent tint of the same navAccent used for the
                // selected icon/text above -- previously this read
                // theme.surfaceColor(SurfaceColor.surfaceContainerHighest),
                // a Material tone derived from Primary via
                // ColorScheme.fromSeed, so this highlight pill silently
                // followed Primary edits instead of the Nav accent color
                // field.
                color: navSelectedIconColor.withValues(alpha: 0.18),
              ),
              iconTheme: IconThemeData(color: navUnselectedIconColor, size: 21),
              selectedIconTheme:
                  IconThemeData(color: navSelectedIconColor, size: 21),
            ),
            extendedTheme: SidebarXTheme(width: 200 + borderInset),
            // Intended for when the header is set to HeaderPosition.content or
            // .none, since the header's own logo disappears in both of those.
            headerBuilder: navStyle.showLogo
                ? (context, extended) => Padding(
                      // Left/right match the menu items' own left inset below
                      // (SidebarXTheme.padding(2) + itemMargin.left(5) +
                      // itemPadding.left(12) = 19), so a left/right-aligned
                      // logo lines up with the icon column instead of sitting
                      // flush against the sidebar's outer edge.
                      padding: const EdgeInsets.only(
                          top: 10, bottom: 10, left: 19, right: 19),
                      child: Align(
                        alignment: switch (navStyle.logoAlign) {
                          ContentAlign.start => Alignment.centerLeft,
                          ContentAlign.end => Alignment.centerRight,
                          ContentAlign.center ||
                          ContentAlign.hidden ||
                          null =>
                            Alignment.center,
                        },
                        child: BisonRelayLogo(size: navStyle.logoSize ?? 32),
                      ),
                    )
                : null,
            // Rendered by footerBuilder below rather than here, so the
            // prices can sit *above* the line that separates off the bottom
            // section (relay counter, notifications, collapse arrow) --
            // SidebarX always places this divider before the footer.
            footerDivider: const SizedBox.shrink(),
            footerBuilder: (context, extended) =>
                Column(mainAxisSize: MainAxisSize.min, children: [
              if (navStyle.showDcrPrice || navStyle.showBtcPrice)
                _PriceRows(
                    style: navStyle,
                    extended: extended == true,
                    textColor: navUnselectedIconColor),
              Divider(height: 2, color: theme.extraColors.sidebarDivider),
              Container(
                  margin: const EdgeInsets.all(5),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (client.countRelays)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                            extended == true
                                ? "Relay Counter: ${client.msgsSent}"
                                : "${client.msgsSent}",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: theme.colors.onSurfaceVariant,
                                fontSize: 12)),
                      ),
                    NotificationsDrawerHeader(widget.ntfns),
                  ])),
            ]),
            controller: ctrl,
            // The theme's chosen destinations, not every one the app has --
            // the same list the phone's bottom bar carries, from the same
            // setting (Settings > Appearance > Menu).
            items: navItemsFor(mainMenu, navStyle.navRoutes)
                .map((e) => SidebarXItem(
                      label: e.label,
                      // Always the same Stack/icon element regardless of
                      // unread state -- only the dot's visibility toggles.
                      // Branching between a Stack and a bare Container here
                      // swaps the icon's element (an SvgPicture for most
                      // menu entries) out and back in on every unread-state
                      // change, which can trip flutter_svg's
                      // didChangeDependencies() into calling setState()
                      // synchronously mid-build on a cache hit ("setState()
                      // or markNeedsBuild() called during build").
                      // A custom iconBuilder bypasses SidebarXTheme's own
                      // iconTheme/selectedIconTheme entirely (the package
                      // only applies those when rendering item.icon itself,
                      // via its built-in _Icon widget) -- so the
                      // selected/unselected color has to be applied here,
                      // via IconTheme.merge, for it to have any effect at
                      // all on e.icon (a SidebarSvgIcon).
                      iconBuilder: (selected, hovered) => IconTheme.merge(
                        data: IconThemeData(
                            color: selected
                                ? navSelectedIconColor
                                : navUnselectedIconColor),
                        child: Stack(children: [
                          Container(
                              padding: const EdgeInsets.all(3),
                              child: e.icon ?? const Empty()),
                          if ((e.routeName == ChatsScreen.routeName &&
                                  hasUnreadMsgs) ||
                              (e.routeName == FeedScreen.routeName &&
                                  feed.hasUnreadPostsComments))
                            const Positioned(
                                top: 1, right: 1, child: RedDotIndicator()),
                        ]),
                      ),
                      onTap: () => switchScreen(e.routeName),
                    ))
                .toList(),
          ));
    });
  }
}

// _PriceRows is the DCR/BTC price footer of the nav bar (see
// AreaStyle.showDcrPrice): a coin disc with a small arrow badge showing
// which way the price last moved, and the price itself while the bar is
// extended. Collapsed, the badge is the whole signal, so it stays.
class _PriceRows extends StatelessWidget {
  final AreaStyle style;
  final bool extended;
  final Color textColor;
  const _PriceRows(
      {required this.style, required this.extended, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Consumer<ExchangeRateModel>(builder: (context, rates, _) {
      // Nothing to show until the client's tracker has a price: a row
      // reading "$0.00" would be worse than no row.
      if (!rates.hasRates) return const Empty();
      var size = style.priceIconSize ?? 26;
      return Column(mainAxisSize: MainAxisSize.min, children: [
        if (style.showDcrPrice)
          _row("assets/images/coin-dcr.png", rates.dcrPrice, rates.dcrDirection,
              size, style.dcrPricePaddings),
        if (style.showBtcPrice)
          _row("assets/images/coin-btc.png", rates.btcPrice, rates.btcDirection,
              size, style.btcPricePaddings),
      ]);
    });
  }

  // The coin marks are the official logos, shipped as assets and left in
  // their own brand colours -- recolouring a coin's disc per palette would
  // make it a worse identifier, which is the only job it has here. Clipped
  // to a circle so the two read as a matched pair regardless of how each
  // source file is cropped.
  Widget _row(String asset, double price, int direction, double size,
      SideValues inset) {
    var disc = SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        ClipOval(
            child: Image.asset(asset,
                width: size, height: size, fit: BoxFit.cover)),
        // The direction badge, overlapping the disc's lower-right. Absent
        // rather than neutral when there's no previous price to compare
        // against -- a flat arrow would claim the price held steady when
        // the truth is we haven't seen it move yet.
        if (direction != 0)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: size * 0.5,
              height: size * 0.5,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF101010),
              ),
              child: Icon(direction > 0 ? Icons.north_east : Icons.south_east,
                  size: size * 0.36,
                  color: direction > 0
                      ? const Color(0xFF2ECC71)
                      : const Color(0xFFFF5C5C)),
            ),
          ),
      ]),
    );

    // Grouped, and no cents once the price is into the thousands: at BTC's
    // magnitude the pennies are noise and the two decimals are what pushes
    // the label into an ellipsis on a narrow bar.
    var label = Text(
        price >= 1000
            ? NumberFormat.currency(symbol: "\$", decimalDigits: 0)
                .format(price)
            : NumberFormat.currency(symbol: "\$", decimalDigits: 2)
                .format(price),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w500, color: textColor));

    // The themed inset is added to the base gap rather than replacing it,
    // so the rows still have breathing room at the default of 0. Collapsed,
    // only the bottom survives: it's the one side that still does something
    // useful there (the gap below each row), whereas a left/right/top value
    // would push the icon off the column's centre or clip it against the
    // row above (see AreaStyle.dcrPricePadding).
    var padding =
        extended ? inset.insets : EdgeInsets.only(bottom: inset.insets.bottom);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3) + padding,
      child: extended
          ? Row(children: [
              const SizedBox(width: 4),
              disc,
              const SizedBox(width: 10),
              Expanded(child: label),
            ])
          : Center(child: disc),
    );
  }
}
