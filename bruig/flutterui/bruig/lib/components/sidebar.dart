import 'package:bruig/components/app_notifications.dart';
import 'package:bruig/components/containers.dart';
import 'package:bruig/components/empty_widget.dart';
import 'package:bruig/components/indicator.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/feed.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/models/notifications.dart';
import 'package:bruig/models/theme_preset.dart';
import 'package:bruig/screens/chats.dart';
import 'package:bruig/screens/feed.dart';
import 'package:bruig/theme_manager.dart';

import 'package:flutter/material.dart';
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

    if (currentPath == route) {
      return;
    }

    widget.navKey.currentState!.pushReplacementNamed(route);
  }

  void menuUpdated() {
    setState(() {
      ctrl.selectIndex(mainMenu.activeIndex);
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
          theme.activePreset?.navAccent ?? theme.colors.primary;
      var navBackground =
          theme.activePreset?.secondary ?? theme.colors.surfaceContainerLow;
      // A border (any mode) makes Container reserve extra inset for it on
      // top of the existing padding, shrinking the content area -- the
      // collapsed sidebar's icon layout already has ~zero slack at its
      // hardcoded width, so any border at all overflows it by a couple of
      // pixels unless the outer width grows to compensate. The parent Row
      // (sidebar + Expanded(Navigator) in overview.dart) absorbs this fine
      // since the Navigator side just gets very slightly narrower.
      var borderInset = navStyle.borderMode != AreaBackgroundMode.token &&
              navStyle.borderWidth > 0
          ? navStyle.borderWidth * 2
          : 0.0;
      // SidebarXTheme.decoration (below) can only be a flat BoxDecoration,
      // so it can't itself express a gradient/image border (only the
      // background supports those directly here) -- wrapBorderOnly adds
      // that border around the whole widget instead when needed.
      return navStyle.wrapBorderOnly(theme, SurfaceColor.surfaceContainerLow,
          presetDir: theme.fullTheme.presetDir,
          child: SidebarX(
            theme: SidebarXTheme(
              margin: const EdgeInsets.all(1),
              padding: const EdgeInsets.all(2),
              width: 70 + borderInset,
              decoration: theme.areaStyle(ThemeArea.navBar).mode ==
                      AreaBackgroundMode.token
                  ? BoxDecoration(
                      // No borderRadius here: a Border with only one side
                      // set (the other 3 default to BorderSide.none, a
                      // different color/width) can never satisfy Flutter's
                      // "uniform border" requirement for combining with a
                      // borderRadius -- Border.paint asserts on this
                      // combination unconditionally, regardless of which
                      // colors are actually used.
                      color: navBackground,
                      border: Border(
                          right: BorderSide(
                              color: theme.extraColors.sidebarDivider)),
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
            footerDivider:
                Divider(height: 2, color: theme.extraColors.sidebarDivider),
            footerBuilder: (context, extended) => Container(
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
            controller: ctrl,
            items: mainMenu.menus
                .where((m) => m.hiddenFromSideBar == false)
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
