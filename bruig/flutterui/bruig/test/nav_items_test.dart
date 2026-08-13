import 'package:bruig/components/mobile_nav_bar.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/screens/address_book_screen.dart';
import 'package:bruig/screens/chats.dart';
import 'package:bruig/screens/feed.dart';
import 'package:bruig/screens/realtimechat/rtclist.dart';
import 'package:bruig/screens/settings.dart';
import 'package:bruig/screens/viewpage_screen.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter_test/flutter_test.dart';

// nav_items_test.dart covers the navigation's destination list: which
// destinations the bars carry, and where their order comes from.
//
// One list for both bars (AreaStyle.navRoutes), so these assert through
// navItemsFor and through mobileNavItems, which is that same list as the
// phone's bottom bar reads it.

List<String> routesOf(MainMenuModel menu, AreaStyle style) =>
    navItemsFor(menu, style.navRoutes).map((e) => e.routeName).toList();

void main() {
  _navBarIndexTests();

  test('an untouched theme carries every destination but the hidden ones',
      () {
    var menu = MainMenuModel();
    var routes = routesOf(menu, const AreaStyle());
    expect(
        routes,
        menu.menus
            .where((e) =>
                !e.hiddenFromSideBar &&
                !defaultHiddenNavRoutes.contains(e.routeName))
            .map((e) => e.routeName));
    expect(routes, contains(ChatsScreen.routeName));
    expect(routes, contains(SettingsScreen.routeName));
    // Including the ones the mobile bar used to leave out by default.
    expect(routes, contains(RealtimeChatScreen.routeName));
    // ...and not the two the default leaves out.
    expect(routes, isNot(contains(AddressBookScreen.routeName)));
    expect(defaultHiddenNavRoutes, contains("/dynplugin/rss"));
  });

  test('a hidden-by-default destination can be switched on', () {
    var style = AreaStyle(navRoutes: [
      ChatsScreen.routeName,
      AddressBookScreen.routeName,
    ]);
    expect(routesOf(MainMenuModel(), style), [
      ChatsScreen.routeName,
      AddressBookScreen.routeName,
      SettingsScreen.routeName,
    ]);
  });

  test('both bars read the same list', () {
    var menu = MainMenuModel();
    var style = AreaStyle(navRoutes: [
      ChatsScreen.routeName,
      SettingsScreen.routeName,
    ]);
    expect(mobileNavItems(menu, style).map((e) => e.routeName),
        routesOf(menu, style));
  });

  test('the order comes from the menu, not from the saved list', () {
    var menu = MainMenuModel();
    menu.reorderItems([
      SettingsScreen.routeName,
      ChatsScreen.routeName,
      FeedScreen.routeName,
      ViewPageScreen.routeName,
    ]);
    // The saved list is deliberately in a different order to the menu's --
    // it says which destinations, never in what sequence.
    var style = AreaStyle(navRoutes: [
      ViewPageScreen.routeName,
      SettingsScreen.routeName,
      ChatsScreen.routeName,
    ]);
    expect(routesOf(menu, style), [
      SettingsScreen.routeName,
      ChatsScreen.routeName,
      ViewPageScreen.routeName,
    ]);
  });

  test('an empty list is a real setting, not "use the defaults"', () {
    const style = AreaStyle(navRoutes: []);
    // Settings survives it -- it is the way back to the switches.
    expect(routesOf(MainMenuModel(), style), [SettingsScreen.routeName]);
    // ...and it has to survive the round trip through a saved preset, which
    // omits every field still at its default.
    var loaded = AreaStyle.fromJson(style.toJson());
    expect(loaded.navRoutes, isEmpty);
    expect(routesOf(MainMenuModel(), loaded), [SettingsScreen.routeName]);
  });

  test('Settings is carried even when a preset leaves it out', () {
    // The editor won't write such a list, but an imported or hand-edited
    // preset can arrive with one, and it would otherwise be unrecoverable.
    var style = AreaStyle(navRoutes: [ChatsScreen.routeName]);
    expect(routesOf(MainMenuModel(), style),
        [ChatsScreen.routeName, SettingsScreen.routeName]);
  });

  test('a route the menu no longer has is simply skipped', () {
    var style = AreaStyle(navRoutes: [
      ChatsScreen.routeName,
      "/plugins/long-gone",
      SettingsScreen.routeName,
    ]);
    expect(routesOf(MainMenuModel(), style),
        [ChatsScreen.routeName, SettingsScreen.routeName]);
  });

  test('navRoutes round-trips through JSON', () {
    var style = AreaStyle(
        navRoutes: [ChatsScreen.routeName, SettingsScreen.routeName]);
    var loaded = AreaStyle.fromJson(style.toJson());
    expect(loaded.navRoutes, [ChatsScreen.routeName, SettingsScreen.routeName]);

    // An untouched area writes nothing, and reads back as "every
    // destination" rather than as an empty list.
    expect(AreaStyle.fromJson(const AreaStyle().toJson()).navRoutes, isNull);
  });

  test('the mobile settings round-trip through JSON', () {
    var style = const AreaStyle(
        mobileTapOpensSidebar: true,
        mobileNavHideLabels: true,
        mobileSidebarAvatarCloses: true,
        mobileAvatarOpensProfile: true,
        mobileHideBackButton: true,
        mobileHideSelfAvatar: true,
        mobileAvatarSecondTapCloses: true);
    var loaded = AreaStyle.fromJson(style.toJson());
    expect(loaded.mobileTapOpensSidebar, isTrue);
    expect(loaded.mobileNavHideLabels, isTrue);
    expect(loaded.mobileSidebarAvatarCloses, isTrue);
    expect(loaded.mobileAvatarOpensProfile, isTrue);
    expect(loaded.mobileHideBackButton, isTrue);
    expect(loaded.mobileHideSelfAvatar, isTrue);
    expect(loaded.mobileAvatarSecondTapCloses, isTrue);

    var untouched = AreaStyle.fromJson(const AreaStyle().toJson());
    expect(untouched.mobileTapOpensSidebar, isFalse);
    expect(untouched.mobileNavHideLabels, isFalse);
    expect(untouched.mobileSidebarAvatarCloses, isFalse);
    expect(untouched.mobileAvatarOpensProfile, isFalse);
    expect(untouched.mobileHideBackButton, isFalse);
    expect(untouched.mobileHideSelfAvatar, isFalse);
    expect(untouched.mobileAvatarSecondTapCloses, isFalse);
  });

  test('the chat list footer defaults on and round-trips', () {
    expect(const AreaStyle().chatSidebarFooter, isTrue);
    var off = AreaStyle.fromJson(
        const AreaStyle(chatSidebarFooter: false).toJson());
    expect(off.chatSidebarFooter, isFalse);
    expect(AreaStyle.fromJson(const AreaStyle().toJson()).chatSidebarFooter,
        isTrue);
  });
}

// The nav bar highlights a row by its position in the bar, and the menu
// model reports the active item's position in the *full* menu. Those are
// two different numbers as soon as anything is filtered out of the middle
// -- see components/sidebar.dart's menuUpdated, which must map by route
// rather than reuse MainMenuModel.activeIndex.
void _navBarIndexTests() {
  int barIndexOf(MainMenuModel menu, List<String>? routes, String route) =>
      navItemsFor(menu, routes).indexWhere((e) => e.routeName == route);

  test('activeIndex is not the row the nav bar draws', () {
    var menu = MainMenuModel();
    // The default hides Address Book, which sits in the middle of the menu.
    menu.activeRoute = FeedScreen.routeName;
    var bar = barIndexOf(menu, null, FeedScreen.routeName);
    expect(menu.activeIndex, isNot(bar),
        reason: "if these agree this test no longer guards anything");
    // The bug: using activeIndex would light up the row *below* Feed.
    var items = navItemsFor(menu, null);
    expect(items[menu.activeIndex].routeName, isNot(FeedScreen.routeName));
    expect(items[bar].routeName, FeedScreen.routeName);
  });

  test('every visible destination maps to its own row', () {
    var menu = MainMenuModel();
    for (var routes in <List<String>?>[
      null,
      [ChatsScreen.routeName, SettingsScreen.routeName],
    ]) {
      for (var item in navItemsFor(menu, routes)) {
        menu.activeRoute = item.routeName;
        var bar = barIndexOf(menu, routes, item.routeName);
        expect(navItemsFor(menu, routes)[bar].routeName, item.routeName);
      }
    }
  });

  test('a route the bar does not carry reports no row', () {
    var menu = MainMenuModel();
    // Reachable from the chat list footer while hidden from the nav.
    expect(barIndexOf(menu, null, AddressBookScreen.routeName), -1);
  });
}
