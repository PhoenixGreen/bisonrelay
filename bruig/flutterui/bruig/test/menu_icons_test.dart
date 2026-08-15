import 'package:bruig/models/menus.dart';
import 'package:bruig/screens/feed.dart';
import 'package:bruig/screens/ln_management.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter_test/flutter_test.dart';

// menu_icons_test.dart covers the two things Settings > Appearance > Menu
// changes about an item beyond its position: which icon it shows, and the
// heading its page shows once it has been renamed.

const _chat = "/chat";

void main() {
  test('an untouched item keeps its built-in icon and records nothing', () {
    var menu = MainMenuModel();
    expect(menu.iconPathFor(_chat), isNull);
    // Nothing to snapshot into a preset either -- only changed icons are
    // written down, so the built-in ones stay free to change later.
    expect(menu.currentIcons(), isEmpty);
  });

  test('choosing an icon changes the item and is snapshotted', () {
    var menu = MainMenuModel();
    var before = menu.menus.firstWhere((e) => e.routeName == _chat).icon;

    menu.setItemIcon(_chat, "assets/icons/icons-menu-stats.svg");

    expect(menu.iconPathFor(_chat), "assets/icons/icons-menu-stats.svg");
    expect(menu.currentIcons(), {_chat: "assets/icons/icons-menu-stats.svg"});
    var after = menu.menus.firstWhere((e) => e.routeName == _chat).icon;
    expect(after, isA<MenuIcon>());
    expect(after, isNot(same(before)));
  });

  test('resetting puts the built-in icon back', () {
    var menu = MainMenuModel();
    var original = menu.menus.firstWhere((e) => e.routeName == _chat).icon;

    menu.setItemIcon(_chat, "assets/icons/icons-menu-stats.svg");
    menu.setItemIcon(_chat, null);

    expect(menu.iconPathFor(_chat), isNull);
    expect(menu.currentIcons(), isEmpty);
    expect(menu.menus.firstWhere((e) => e.routeName == _chat).icon,
        same(original));
  });

  test('changing an icon leaves the label and the order alone', () {
    var menu = MainMenuModel();
    menu.renameItem(_chat, "Messages");
    var order = menu.currentOrder();

    menu.setItemIcon(_chat, "assets/icons/icons-menu-stats.svg");

    expect(
        menu.menus.firstWhere((e) => e.routeName == _chat).label, "Messages");
    expect(menu.currentOrder(), order);
  });

  test('a theme carries its icons, and switching away drops them', () {
    var menu = MainMenuModel();
    menu.applyThemeMenu(
        null, null, {_chat: "assets/icons/icons-menu-news.svg"});
    expect(menu.iconPathFor(_chat), "assets/icons/icons-menu-news.svg");

    // Switching to a theme with no menu customization of its own.
    menu.applyThemeMenu(null, null, null);
    expect(menu.iconPathFor(_chat), isNull);
  });

  test('icons round-trip through a preset', () {
    var preset = ThemePreset.seedFromDark().copyWith(
        menuIcons: {_chat: "images/menuicon_chat.svg"},
        menuLabels: {_chat: "Messages"});
    var back = ThemePreset.fromJson(preset.toJson());
    expect(back.menuIcons, {_chat: "images/menuicon_chat.svg"});

    // A preset that has never had an icon changed writes no key at all, so
    // an older preset loads as "no customization" rather than as "every
    // icon blank".
    var plain = ThemePreset.seedFromDark();
    expect(plain.toJson().containsKey("menuIcons"), isFalse);
    expect(ThemePreset.fromJson(plain.toJson()).menuIcons, isNull);
  });

  test('a bundled icon is told apart from one the user supplied', () {
    expect(MenuIcon.isAsset("assets/icons/icons-menu-chat.svg"), isTrue);
    expect(MenuIcon.isAsset("images/menuicon_chat.svg"), isFalse);
  });

  group('headerLabel', () {
    test('is null while an item still has its built-in name', () {
      var menu = MainMenuModel();
      // Null, not "Feed": each page keeps the heading it composes for
      // itself, which is not always the menu label (LN Management's page is
      // headed "LN").
      expect(menu.headerLabel(FeedScreen.routeName), isNull);
      expect(menu.headerLabel(LNScreen.routeName), isNull);
    });

    test('is the new name once the item is renamed', () {
      var menu = MainMenuModel();
      menu.renameItem(FeedScreen.routeName, "Posts");
      expect(menu.headerLabel(FeedScreen.routeName), "Posts");
    });

    test('follows a rename that arrived from a preset', () {
      var menu = MainMenuModel();
      menu.applyThemeMenu({FeedScreen.routeName: "Posts"}, null);
      expect(menu.headerLabel(FeedScreen.routeName), "Posts");
    });

    test('a saved preset does not turn every label into an override', () {
      var menu = MainMenuModel();
      // Saving a theme snapshots *every* label, untouched ones included
      // (see currentLabels). Re-applying that must not read as though all
      // of them had been renamed.
      menu.applyThemeMenu(menu.currentLabels(), menu.currentOrder());
      expect(menu.headerLabel(FeedScreen.routeName), isNull);
      expect(menu.headerLabel(LNScreen.routeName), isNull);
    });

    test('is null for a route the menu does not carry', () {
      expect(MainMenuModel().headerLabel("/nope"), isNull);
    });
  });
}
