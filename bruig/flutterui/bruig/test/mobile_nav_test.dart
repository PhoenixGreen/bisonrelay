import 'package:bruig/components/mobile_nav_bar.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/screens/chats.dart';
import 'package:bruig/screens/feed.dart';
import 'package:bruig/screens/realtimechat/rtclist.dart';
import 'package:bruig/screens/settings.dart';
import 'package:bruig/screens/viewpage_screen.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter_test/flutter_test.dart';

// mobile_nav_test.dart covers the Mobile theme area's destination list: what
// the narrow-screen bottom bar carries, and where its order comes from.

List<String> routesOf(MainMenuModel menu, AreaStyle style) =>
    mobileNavItems(menu, style).map((e) => e.routeName).toList();

void main() {
  test('an untouched theme carries the four default destinations', () {
    var routes = routesOf(MainMenuModel(), const AreaStyle());
    expect(routes, [
      ChatsScreen.routeName,
      FeedScreen.routeName,
      ViewPageScreen.routeName,
      SettingsScreen.routeName,
    ]);
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
    var style = AreaStyle(mobileNavRoutes: [
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

  test('an off-by-default destination can be switched on', () {
    var style = AreaStyle(mobileNavRoutes: [
      ChatsScreen.routeName,
      RealtimeChatScreen.routeName,
    ]);
    expect(routesOf(MainMenuModel(), style),
        [ChatsScreen.routeName, RealtimeChatScreen.routeName]);
  });

  test('an empty list is a real setting, not "use the defaults"', () {
    const style = AreaStyle(mobileNavRoutes: []);
    expect(routesOf(MainMenuModel(), style), isEmpty);
    // ...and has to survive the round trip through a saved preset, which
    // omits every field still at its default.
    var loaded = AreaStyle.fromJson(style.toJson());
    expect(loaded.mobileNavRoutes, isEmpty);
    expect(routesOf(MainMenuModel(), loaded), isEmpty);
  });

  test('a route the menu no longer has is simply skipped', () {
    var style = AreaStyle(
        mobileNavRoutes: [ChatsScreen.routeName, "/plugins/long-gone"]);
    expect(routesOf(MainMenuModel(), style), [ChatsScreen.routeName]);
  });

  test('the mobile settings round-trip through JSON', () {
    var style = AreaStyle(
        mobileNavRoutes: [ChatsScreen.routeName, SettingsScreen.routeName],
        mobileTapOpensSidebar: true,
        mobileNavHideLabels: true,
        mobileSidebarAvatarCloses: true,
        mobileAvatarOpensProfile: true,
        mobileHideBackButton: true,
        mobileHideSelfAvatar: true,
        mobileAvatarSecondTapCloses: true);
    var loaded = AreaStyle.fromJson(style.toJson());
    expect(loaded.mobileNavRoutes,
        [ChatsScreen.routeName, SettingsScreen.routeName]);
    expect(loaded.mobileTapOpensSidebar, isTrue);
    expect(loaded.mobileNavHideLabels, isTrue);
    expect(loaded.mobileSidebarAvatarCloses, isTrue);
    expect(loaded.mobileAvatarOpensProfile, isTrue);
    expect(loaded.mobileHideBackButton, isTrue);
    expect(loaded.mobileHideSelfAvatar, isTrue);
    expect(loaded.mobileAvatarSecondTapCloses, isTrue);

    // An untouched area writes none of them, and reads back as "use the
    // defaults" rather than as an empty list.
    var untouched = AreaStyle.fromJson(const AreaStyle().toJson());
    expect(untouched.mobileNavRoutes, isNull);
    expect(untouched.mobileTapOpensSidebar, isFalse);
    expect(untouched.mobileNavHideLabels, isFalse);
    expect(untouched.mobileSidebarAvatarCloses, isFalse);
    expect(untouched.mobileAvatarOpensProfile, isFalse);
    expect(untouched.mobileHideBackButton, isFalse);
    expect(untouched.mobileHideSelfAvatar, isFalse);
    expect(untouched.mobileAvatarSecondTapCloses, isFalse);
  });
}
