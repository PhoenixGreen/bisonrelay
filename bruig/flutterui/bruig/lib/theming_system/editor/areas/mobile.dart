import 'package:bruig/theming_system/theme_editor.dart';
import 'package:flutter/material.dart';

// mobile.dart is the "Mobile" area's own settings: how the narrow-screen
// bottom navigation is drawn, and how tapping it behaves.
//
// *Which* destinations it carries is not here. It is one setting with the
// desktop nav bar now (AreaStyle.navRoutes), set in Settings > Appearance >
// Menu beside the same items' order and names -- the two bars are one
// navigation at two sizes, and a destination present in one but not the
// other is one the user has to remember the width of the window to find.
List<Widget> mobileAreaEditor(AreaEditorContext ctx) => [
      ctx.note("Which destinations this bar carries is set in Settings > "
          "Appearance > Menu, along with the desktop navigation bar's. Too "
          "many to fit scroll sideways."),
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
