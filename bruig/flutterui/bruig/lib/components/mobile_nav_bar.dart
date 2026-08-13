import 'package:bruig/components/empty_widget.dart';
import 'package:bruig/components/indicator.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/feed.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/screens/chats.dart';
import 'package:bruig/screens/feed.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// mobile_nav_bar.dart is the narrow-screen bottom navigation -- the nav
// bar's counterpart on a phone. It's hand-built rather than a
// BottomNavigationBar because that widget divides its width evenly between
// a fixed set of items with no way to scroll: with the destination list now
// a theme setting (see the Mobile theme area), more items than fit has to
// mean "swipe sideways for the rest" rather than a row of squashed labels.
//
// Everything about a destination -- its order, its label, its icon -- comes
// from MainMenuModel, the same source the desktop nav bar reads, so a
// rename or a reorder in Settings > Appearance > Menu shows up in both.

// _minItemWidth is the narrowest an item is allowed to get before the bar
// starts scrolling instead of dividing further. Below this the longer
// labels ("Realtime Chat", "Address Book") ellipsize down to a couple of
// letters, which is worse than being off-screen and a swipe away. With the
// labels off there's nothing to ellipsize, so an item only needs room for
// its icon and more of them fit before it scrolls.
const double _minItemWidth = 84;
const double _minIconOnlyItemWidth = 56;

// _barHeight is roughly what BottomNavigationBar came out at with the icon
// and label sizes below, so the content area keeps the room it had. Without
// labels the bar gives that room back rather than padding the icons out to
// the same height.
const double _barHeight = 62;
const double _iconOnlyBarHeight = 48;
const double _iconSize = 32;

// mobileNavItems is the destination list the bar shows: the theme's chosen
// routes, in the menu's own order. Shared with OverviewScreen, which needs
// the same list to decide what counts as a top-level tab.
//
// The same routes the desktop nav bar carries, from the same setting -- see
// AreaStyle.navRoutes. [style] is the Navigation Bar area's, not Mobile's.
List<MainMenuItem> mobileNavItems(MainMenuModel mainMenu, AreaStyle style) =>
    navItemsFor(mainMenu, style.navRoutes);

class MobileNavBar extends StatelessWidget {
  final ClientModel client;
  final FeedModel feed;
  // onTap is handed the route name rather than an index: the item list is
  // built from a mutable, user-ordered menu, so an index means nothing
  // outside the frame it was computed in.
  final ValueChanged<String> onTap;
  const MobileNavBar(
      {super.key,
      required this.client,
      required this.feed,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Consumer2<ThemeNotifier, MainMenuModel>(
        builder: (context, theme, mainMenu, _) {
      var mobileStyle = theme.areaStyle(ThemeArea.mobile);
      var items = mobileNavItems(mainMenu, theme.areaStyle(ThemeArea.navBar));
      if (items.isEmpty) return const Empty();
      var showLabels = !mobileStyle.mobileNavHideLabels;

      // The same three palette slots the desktop nav bar resolves (see
      // sidebar.dart) -- this bar is that bar, on a phone, so a theme
      // shouldn't have to colour them separately.
      var unselectedColor =
          theme.activePreset?.navText ?? theme.colors.onSurfaceVariant;
      var selectedColor =
          theme.activePreset?.navSelected ?? theme.colors.primary;
      var background =
          theme.activePreset?.secondary ?? theme.colors.surfaceContainerLow;

      return Container(
        decoration: BoxDecoration(
            color: background,
            border: Border(
                top: BorderSide(color: theme.extraColors.sidebarDivider))),
        // The bar's background continues under the home indicator, but its
        // items stay above it -- what BottomNavigationBar did for itself,
        // and what this now has to do for itself.
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: showLabels ? _barHeight : _iconOnlyBarHeight,
            child: LayoutBuilder(builder: (context, constraints) {
              // Divided evenly while they all fit, then pinned at
              // _minItemWidth so the overflow scrolls rather than shrinking
              // further. Measuring here, instead of letting the Row size
              // itself, is what lets one widget do both.
              var minWidth = showLabels ? _minItemWidth : _minIconOnlyItemWidth;
              var itemWidth = constraints.maxWidth / items.length;
              if (itemWidth < minWidth) itemWidth = minWidth;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                // No overscroll bounce: with few enough items to fit there
                // is nothing to scroll to, and a bar that slides under the
                // thumb and springs back reads as a missed tap.
                physics: const ClampingScrollPhysics(),
                child: Row(children: [
                  for (var item in items)
                    SizedBox(
                      width: itemWidth,
                      child: _MobileNavItem(
                        item: item,
                        showLabel: showLabels,
                        selected: mainMenu.activeRoute == item.routeName,
                        selectedColor: selectedColor,
                        unselectedColor: unselectedColor,
                        showDot: (item.routeName == ChatsScreen.routeName &&
                                client.activeChats.hasUnreadMsgs) ||
                            (item.routeName == FeedScreen.routeName &&
                                feed.hasUnreadPostsComments),
                        onTap: () => onTap(item.routeName),
                      ),
                    ),
                ]),
              );
            }),
          ),
        ),
      );
    });
  }
}

class _MobileNavItem extends StatelessWidget {
  final MainMenuItem item;
  final bool showLabel;
  final bool selected;
  final Color selectedColor;
  final Color unselectedColor;
  final bool showDot;
  final VoidCallback onTap;
  const _MobileNavItem(
      {required this.item,
      required this.showLabel,
      required this.selected,
      required this.selectedColor,
      required this.unselectedColor,
      required this.showDot,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    var color = selected ? selectedColor : unselectedColor;
    // The Container above paints the background but isn't a Material, and
    // an InkWell with no Material ancestor draws no ripple at all.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Always the same Stack element regardless of unread state --
            // only the dot's visibility toggles. Branching between a Stack
            // and a bare Container here swaps the icon's element (an
            // SvgPicture for most entries) out and back in on every
            // unread-state change, which can trip flutter_svg's
            // didChangeDependencies() into calling setState()
            // synchronously mid-build on a cache hit.
            Stack(children: [
              // A SidebarSvgIcon is an unsized SvgPicture -- it takes
              // whatever room it's given, so without this box it grows to
              // fill the item and crowds out the label.
              SizedBox(
                width: _iconSize,
                height: _iconSize,
                child: IconTheme.merge(
                  data: IconThemeData(color: color, size: _iconSize - 6),
                  child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: item.icon ?? const Empty()),
                ),
              ),
              if (showDot)
                const Positioned(top: 1, right: 1, child: RedDotIndicator()),
            ]),
            if (showLabel) ...[
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: color,
                      fontSize: fontSize(TextSize.medium),
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
