import 'package:bruig/models/menus.dart';
import 'package:bruig/theming_system/theme_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// mobile.dart is the "Mobile" area's own settings: what the
// narrow-screen bottom navigation carries, and how tapping it behaves.
//
// The destination list is built from MainMenuModel rather than a hardcoded
// list of its own, so it picks up the menu's order, its labels and its
// icons -- including a rename or a reorder made in Settings > Appearance >
// Menu, and including a nav item a dynamic-wasm plugin registered. Every
// destination the app has is listed; which of them start switched on is
// defaultMobileNavRoutes.
List<Widget> mobileAreaEditor(AreaEditorContext ctx) => [
      const Text("Navigation items"),
      ctx.note("Their order and names come from Settings > Appearance > "
          "Menu. Too many to fit scroll sideways."),
      _MobileNavItems(ctx),
      const SizedBox(height: 12),
      ctx.toggle("Show item names",
          subtitle: "Off leaves the icons alone, and fits more of them "
              "before the bar scrolls",
          value: !ctx.style.mobileNavHideLabels,
          onChanged: (v) =>
              ctx.setStyle((s) => s.copyWith(mobileNavHideLabels: !v))),
      ctx.toggle("Show your avatar",
          subtitle: "In the header's top-left corner. It stands aside on "
              "its own wherever the title already carries an avatar",
          value: !ctx.style.mobileHideSelfAvatar,
          onChanged: (v) =>
              ctx.setStyle((s) => s.copyWith(mobileHideSelfAvatar: !v))),
      ctx.toggle("Header avatar opens your account",
          subtitle: "Goes to Settings > Account, your own avatar, name and "
              "identity, instead of the top of Settings",
          value: ctx.style.mobileAvatarOpensProfile,
          onChanged: (v) =>
              ctx.setStyle((s) => s.copyWith(mobileAvatarOpensProfile: v))),
      ctx.toggle("Header avatar tap again to close",
          subtitle: "A second tap closes the right sidebar, or leaves the "
              "Account page for wherever you tapped it from",
          value: ctx.style.mobileAvatarSecondTapCloses,
          onChanged: (v) =>
              ctx.setStyle((s) => s.copyWith(mobileAvatarSecondTapCloses: v))),
      ctx.toggle("Show back button",
          subtitle: "Off leaves your avatar in the header's corner at all "
              "times; \"Tap again to go back\" covers the same ground",
          value: !ctx.style.mobileHideBackButton,
          onChanged: (v) =>
              ctx.setStyle((s) => s.copyWith(mobileHideBackButton: !v))),
      ctx.toggle("Sidebar avatar closes the sidebar",
          subtitle: "The right sidebar's avatar dismisses it, instead of "
              "opening a menu of the entries already listed below it",
          value: ctx.style.mobileSidebarAvatarCloses,
          onChanged: (v) =>
              ctx.setStyle((s) => s.copyWith(mobileSidebarAvatarCloses: v))),
      ctx.toggle("Tap again to go back",
          subtitle: "Re-tapping the page you're on slides that page's "
              "sidebar in from the left (on Chat, returns to the chat "
              "list), and drops the three-dot menu from the header",
          value: ctx.style.mobileTapOpensSidebar,
          onChanged: (v) =>
              ctx.setStyle((s) => s.copyWith(mobileTapOpensSidebar: v))),
    ];

class _MobileNavItems extends StatelessWidget {
  final AreaEditorContext ctx;
  const _MobileNavItems(this.ctx);

  @override
  Widget build(BuildContext context) {
    return Consumer<MainMenuModel>(builder: (context, mainMenu, _) {
      var enabled = ctx.style.mobileNavRoutes ?? defaultMobileNavRoutes;
      var items = mainMenu.menus.where((e) => !e.hiddenFromSideBar).toList();
      return Column(children: [
        for (var item in items)
          ctx.toggle(item.label,
              compact: true,
              value: enabled.contains(item.routeName), onChanged: (on) {
            // Written back in menu order, not tap order, so the saved
            // list reads the way the bar does. It's stored in full
            // (never as a diff from the default) so that switching a
            // default item off survives a reload -- an absent route is
            // how "off" is expressed.
            var next = [
              for (var e in items)
                if (e.routeName == item.routeName
                    ? on
                    : enabled.contains(e.routeName))
                  e.routeName,
              // A route that's on but isn't in the menu right now
              // belongs to a plugin that's currently disabled. Keeping
              // it means re-enabling the plugin restores its slot,
              // rather than this edit having quietly dropped it.
              ...enabled.where((r) => !items.any((e) => e.routeName == r)),
            ];
            ctx.setStyle((s) => s.copyWith(mobileNavRoutes: next));
          }),
      ]);
    });
  }
}
