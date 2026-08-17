import 'package:bruig/models/menus.dart';
import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:flutter_test/flutter_test.dart';

import 'plugin_test_support.dart';

// writing_section_test.dart covers the Writing destination: that it exists
// exactly while the writing tools do, that it is offered in the menu settings
// like any other destination, and that nothing is left pointing at it once it
// is gone.
//
// Worth pinning because none of it is visible from the writing tools
// themselves. The page is registered from a provider whose value nobody
// reads, so a mistake here does not fail anywhere -- the destination simply
// never appears, or never leaves.

const _route = WritingScreen.routeName;

MainMenuModel _menu() => MainMenuModel();

WritingNavModel _navFor(MainMenuModel menu, {required bool enabled}) {
  var nav = WritingNavModel();
  nav.update(
      FakePlugins(enabled ? {PluginCapability.spellcheckData} : {}), menu);
  return nav;
}

void main() {
  // MainMenuModel defers its notifications to the end of a frame, which needs
  // a binding even where no widget is built.
  TestWidgetsFlutterBinding.ensureInitialized();

  group("the Writing destination", () {
    test("is absent until a plugin provides the writing tools", () {
      var menu = _menu();
      _navFor(menu, enabled: false);

      expect(menu.menuForRoute(_route), isNull);
      expect(hasWritingPage(menu), isFalse,
          reason: "somebody who has never enabled the plugin has never had "
              "the page, and the Feed's New Post link is theirs");
    });

    test("appears when one does", () {
      var menu = _menu();
      _navFor(menu, enabled: true);

      var item = menu.menuForRoute(_route);
      expect(item, isNotNull);
      expect(item!.label, "Writing");
      expect(item.hiddenFromSideBar, isFalse);
      expect(hasWritingPage(menu), isTrue);
    });

    // The gate is the capability, not a plugin id: the page is here to write
    // with the writing tools, and another plugin providing them earns it too.
    test("is gated on the capability rather than on one plugin", () {
      var menu = _menu();
      var nav = WritingNavModel();

      nav.update(FakePlugins({PluginCapability.linkCard}), menu);
      expect(hasWritingPage(menu), isFalse,
          reason: "a plugin that draws link cards is not a writing tool");

      nav.update(FakePlugins({PluginCapability.spellcheckData}), menu);
      expect(hasWritingPage(menu), isTrue);
    });

    test("goes again when the plugin is disabled", () {
      var menu = _menu();
      var nav = WritingNavModel();

      nav.update(FakePlugins({PluginCapability.spellcheckData}), menu);
      expect(hasWritingPage(menu), isTrue);

      nav.update(FakePlugins({}), menu);
      expect(menu.menuForRoute(_route), isNull);
      expect(hasWritingPage(menu), isFalse);
    });

    // Reported: switching between two themes took the Writing section out of
    // the navigation, and only turning the plugin off and on again brought it
    // back.
    //
    // Applying a theme's menu customization rebuilds the menu from the
    // built-in list, which by definition holds no dynamic item -- so the
    // Writing entry goes with it. The plugin has not changed, so a model that
    // remembers having registered the item has nothing to do and does
    // nothing, and the section stays gone until the plugin set actually
    // moves. The neighbouring plugin nav survives the same wipe because it
    // registers unconditionally every time it runs.
    test("survives a theme's menu being applied", () {
      var menu = _menu();
      var nav = WritingNavModel();
      var plugins = FakePlugins({PluginCapability.spellcheckData});

      nav.update(plugins, menu);
      expect(hasWritingPage(menu), isTrue);

      // What switching to another theme does to the menu.
      menu.applyThemeMenu({"/feed": "Posts"}, null);
      expect(hasWritingPage(menu), isFalse,
          reason: "the wipe itself is not the bug -- not coming back is");

      // The rebuild that applying a theme triggers, since the model is wired
      // to the menu as well as to the plugins.
      nav.update(plugins, menu);
      expect(hasWritingPage(menu), isTrue,
          reason: "the plugin is still on, so the page still belongs there");
    });

    test("comes back after a theme wipe without the plugin moving", () {
      var menu = _menu();
      var nav = WritingNavModel();
      var plugins = FakePlugins({PluginCapability.spellcheckData});

      nav.update(plugins, menu);
      for (var i = 0; i < 3; i++) {
        menu.applyThemeMenu(null, null);
        nav.update(plugins, menu);
        expect(hasWritingPage(menu), isTrue, reason: "after theme $i");
      }
    });

    // Reported against the plugin nav this one is modelled on: update() runs
    // on every rebuild of the provider tree it is wired into, not only when
    // a plugin is switched on or off. An unregister on one of those rebuilds
    // would clear the active route out from under somebody standing on the
    // page.
    test("a rebuild that changes nothing changes nothing", () {
      var menu = _menu();
      var nav = WritingNavModel();
      var plugins = FakePlugins({PluginCapability.spellcheckData});

      nav.update(plugins, menu);
      menu.activeRoute = _route;

      for (var i = 0; i < 5; i++) {
        nav.update(plugins, menu);
      }

      expect(hasWritingPage(menu), isTrue);
      expect(menu.activeMenu.routeName, _route,
          reason: "a repeat registration threw the reader off the page");
    });

    // Standing on the page when the plugin goes: there is no page any more,
    // so nothing may still be pointing at it.
    test("disabling it clears the active route", () {
      var menu = _menu();
      var nav = WritingNavModel();

      nav.update(FakePlugins({PluginCapability.spellcheckData}), menu);
      menu.activeRoute = _route;
      expect(menu.activeMenu.routeName, _route);

      nav.update(FakePlugins({}), menu);
      expect(menu.activeMenu.routeName, isNot(_route));
    });
  });

  group("the navigation", () {
    // Settings > Appearance > Menu builds its rows from MainMenuModel.menus,
    // so being registered is what puts it there -- and being absent from
    // defaultHiddenNavRoutes is what has it switched on to begin with.
    test("carries Writing by default once it exists", () {
      var menu = _menu();
      _navFor(menu, enabled: true);

      expect(navItemsFor(menu, null).map((e) => e.routeName), contains(_route),
          reason: "enabling the plugin should put the page in front of "
              "somebody, not leave it to be found in the theme editor");
      expect(menu.menus.where((e) => !e.hiddenFromSideBar).map((e) => e.label),
          contains("Writing"),
          reason: "the menu editor lists exactly these");
    });

    // It is a destination like any other once it is there: renameable, and
    // the rename reaches the page heading (see MainMenuModel.headerLabel).
    test("lets the Writing item be renamed like any other", () {
      var menu = _menu();
      _navFor(menu, enabled: true);

      menu.renameItem(_route, "Drafts");
      expect(menu.menuForRoute(_route)!.label, "Drafts");
      expect(hasWritingPage(menu), isTrue,
          reason: "the redirect keys on the route, not on the name");
    });

    // A theme that names its routes explicitly predates this destination and
    // cannot list it, exactly as it cannot list an RSS plugin's.
    test("a theme's own route list decides for itself", () {
      var menu = _menu();
      _navFor(menu, enabled: true);

      expect(navRouteShown(_route, const []), isFalse);
      expect(navRouteShown(_route, const [_route]), isTrue);
    });
  });

  // The Feed menu icon was a fourth panel back when this sidebar lived inside
  // the Feed and choosing it meant leaving the composer. The Writing page is
  // its own destination, so the way out of it is the navigation.
  group("the composer sidebar", () {
    test("offers no way back to a screen it is no longer inside", () {
      expect(ComposerPanel.values.map((p) => p.label),
          isNot(contains("Feed menu")));
      expect(ComposerPanel.values, hasLength(3));
    });
  });
}
