import 'dart:async';

import 'package:bruig/components/containers.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/screens/manage_content/manage_content.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bruig/models/downloads.dart';
import 'package:bruig/screens/manage_content/downloads.dart';
import 'package:bruig/components/manage_bar.dart';
import 'package:bruig/screens/overview.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/models/uistate.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/screens/manage_content/purchases.dart';

class ManageContentScreenTitle extends StatelessWidget {
  const ManageContentScreenTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<MainMenuModel, ThemeNotifier>(
        builder: (context, menu, theme, child) {
      var idx = manageContentScreenSub
          .indexWhere((e) => e.pageTab == menu.activePageTab);
      var name =
          menu.headerLabel(ManageContentScreen.routeName) ?? "Manage Content";

      return Txt.L("$name / ${manageContentScreenSub[idx].label}");
    });
  }
}

class ManageContentScreen extends StatefulWidget {
  static const routeName = '/manageContent';
  final MainMenuModel menu;
  const ManageContentScreen(this.menu, {super.key});

  @override
  State<ManageContentScreen> createState() => _ManageContentScreenState();
}

class _ManageContentScreenState extends State<ManageContentScreen> {
  // Which tab is open, and the file the Downloads tab has in its preview,
  // both held on ManageContentNavModel rather than here.
  //
  // Out there for two reasons at once. This screen is rebuilt from scratch
  // every time it is navigated to, so anything kept here is lost by stepping
  // over to Chat and back. And opening a preview takes the sidebar aside
  // (see SecondarySideMenuLayout.collapseSidebar), which rebuilds the tab's
  // own State -- so the preview could not live down there either.
  ManageContentNavModel get nav =>
      ClientModel.of(context, listen: false).ui.manageContentNav;

  Widget activeTab(int tabIndex, String? previewing) {
    switch (tabIndex) {
      case 0:
        return const ManageContent(0);
      case 1:
        return const ManageContent(1);
      case 2:
        return Consumer2<DownloadsModel, ClientModel>(
            builder: (context, downloads, client, child) => DownloadsScreen(
                downloads, client,
                previewing: previewing, onPreviewing: nav.open));
      case 3:
        return Consumer2<DownloadsModel, ClientModel>(
            builder: (context, downloads, client, child) => PurchasesScreen(
                downloads, client,
                nav: nav, previewing: previewing, onPreviewing: nav.open));
    }
    return Text("Active is $tabIndex");
  }

  void onItemChanged(int index) {
    // Switching tabs takes the preview with it, so the sidebar comes back.
    nav
      ..open(null)
      ..tab = index;
    Timer(const Duration(milliseconds: 1),
        () async => widget.menu.activePageTab = index);
  }

  @override
  Widget build(BuildContext context) {
    // Explicit navigation still wins: arriving with arguments (from a link
    // or a notification) opens the tab those name, rather than the one that
    // happened to be open last.
    if (ModalRoute.of(context)!.settings.arguments != null) {
      final args = ModalRoute.of(context)!.settings.arguments as PageTabs;
      nav.tab = args.tabIndex;
    }

    // Deliberately not short-circuited to a bare activeTab() on a small
    // screen: below SecondarySideMenuLayout's collapse width it already
    // renders content-only, but it also hands its item list to
    // CollapsedSidebarModel on the way -- which is what gives the mobile
    // navigation's re-tap gesture (see the Mobile theme area) something to
    // slide in, and what the mobile header's three-dot menu used to be the
    // only route to.
    return ListenableBuilder(
      listenable: nav,
      builder: (context, _) {
        var previewing = nav.tab == 2 ? nav.path : null;
        return SecondarySideMenuLayout(
          storageKey: "manageContent",
          items: manageContentBarItems(onItemChanged, nav.tab),
          isDetail: ModalRoute.of(context)!.settings.arguments != null,
          collapseSidebar: previewing != null,
          content: activeTab(nav.tab, previewing),
        );
      },
    );
  }
}
