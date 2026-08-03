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
import 'package:bruig/theming_system/theme_manager.dart';

class ManageContentScreenTitle extends StatelessWidget {
  const ManageContentScreenTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<MainMenuModel, ThemeNotifier>(
        builder: (context, menu, theme, child) {
      var idx = manageContentScreenSub
          .indexWhere((e) => e.pageTab == menu.activePageTab);

      return Txt.L("Manage Content / ${manageContentScreenSub[idx].label}");
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
  int tabIndex = 0;

  Widget activeTab() {
    switch (tabIndex) {
      case 0:
        return const ManageContent(0);
      case 1:
        return const ManageContent(1);
      case 2:
        return Consumer2<DownloadsModel, ClientModel>(
            builder: (context, downloads, client, child) =>
                DownloadsScreen(downloads, client));
    }
    return Text("Active is $tabIndex");
  }

  void onItemChanged(int index) {
    setState(() => tabIndex = index);
    Timer(const Duration(milliseconds: 1),
        () async => widget.menu.activePageTab = index);
  }

  @override
  Widget build(BuildContext context) {
    if (ModalRoute.of(context)!.settings.arguments != null) {
      final args = ModalRoute.of(context)!.settings.arguments as PageTabs;
      tabIndex = args.tabIndex;
    }

    // Deliberately not short-circuited to a bare activeTab() on a small
    // screen: below SecondarySideMenuLayout's collapse width it already
    // renders content-only, but it also hands its item list to
    // CollapsedSidebarModel on the way -- which is what gives the mobile
    // navigation's re-tap gesture (see the Mobile theme area) something to
    // slide in, and what the mobile header's three-dot menu used to be the
    // only route to.
    return SecondarySideMenuLayout(
      storageKey: "manageContent",
      items: manageContentBarItems(onItemChanged, tabIndex),
      isDetail: ModalRoute.of(context)!.settings.arguments != null,
      content: activeTab(),
    );
  }
}
