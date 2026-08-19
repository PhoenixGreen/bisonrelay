import 'dart:async';

import 'package:bruig/components/containers.dart';
import 'package:bruig/components/pages_bar.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/models/pages.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/screens/overview.dart';
import 'package:bruig/screens/pages/browser.dart';
import 'package:bruig/screens/pages/my_site.dart';
import 'package:bruig/screens/pages/store.dart';
import 'package:bruig/screens/pages/visit.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ViewPagesScreenTitle extends StatelessWidget {
  const ViewPagesScreenTitle({super.key});

  @override
  Widget build(BuildContext context) {
    // Deliberately read from the menu rather than PagesModel: the heading
    // is built without a running client, and PagesModel needs one.
    return Consumer<MainMenuModel>(builder: (context, menu, _) {
      var name = menu.headerLabel(ViewPageScreen.routeName) ?? "Pages";
      var idx = menu.activePageTab.clamp(0, pagesTabLabels.length - 1);
      return Txt.L("$name / ${pagesTabLabels[idx]}");
    });
  }
}

class ViewPageScreen extends StatefulWidget {
  static String routeName = "/pages";
  final ResourcesModel resources;
  final ClientModel client;
  const ViewPageScreen(this.resources, this.client, {super.key});

  @override
  State<ViewPageScreen> createState() => _ViewPageScreenState();
}

class _ViewPageScreenState extends State<ViewPageScreen> {
  ResourcesModel get resources => widget.resources;

  PagesModel get pages => Provider.of<PagesModel>(context, listen: false);
  MainMenuModel get menu => Provider.of<MainMenuModel>(context, listen: false);

  void onItemChanged(int index) {
    pages.tab = index;
    Timer(const Duration(milliseconds: 1),
        () async => menu.activePageTab = index);
  }

  // Opening a site switches to the browser rather than staying on the list
  // that launched it: the page is the thing that was asked for.
  void showBrowser() => setState(() {});

  // Whether the tab sidebar is showing while a page is open.
  //
  // A page starts with it hidden: the tabs are how you got here, and the
  // page wants the width -- pages are written to a reading measure, and on a
  // narrow window the sidebar takes a third of it. The toggle in the browser
  // bar brings it back, and _openSession is what makes "starts hidden" mean
  // per page rather than once ever, so closing a page and opening another
  // does not inherit the last one's choice.
  bool sidebarOpen = false;
  PagesSession? _openSession;

  void toggleSidebar() => setState(() => sidebarOpen = !sidebarOpen);

  Widget activeTab(int tab) {
    switch (tab) {
      case pagesTabMySite:
        return MySiteTab(pages, widget.client, resources, showBrowser);
      case pagesTabStore:
        return StoreTab(pages);
      default:
        return VisitTab(widget.client, pages, resources, showBrowser);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ModalRoute.of(context)!.settings.arguments != null) {
      final args = ModalRoute.of(context)!.settings.arguments as PageTabs;
      pages.tab = args.tabIndex;
    }

    return Consumer2<PagesModel, ResourcesModel>(
      builder: (context, pagesModel, resources, _) {
        var session = resources.mostRecent;
        var items = pagesBarItems(onItemChanged, pagesModel.tab);
        var tab = pagesModel.tab.clamp(0, items.length - 1);

        // A session that is open takes the content area: the tabs are how
        // you get to a page, and the page is what you came for. Closing it
        // hands the area back to whichever tab is selected.
        if (!identical(session, _openSession)) {
          _openSession = session;
          sidebarOpen = false;
        }

        Widget content;
        if (session != null) {
          content = PageBrowser(
            session,
            widget.client,
            resources,
            sidebarOpen: sidebarOpen,
            onToggleSidebar: toggleSidebar,
            onClose: () => resources.mostRecent = null,
          );
        } else {
          content = activeTab(tab);
        }

        return SecondarySideMenuLayout(
          storageKey: "pages",
          items: items,
          sidebarRevision: Object.hash(tab, items.length, sidebarOpen),
          isDetail: ModalRoute.of(context)!.settings.arguments != null,
          // Deliberately the same path a narrow window takes rather than
          // simply not drawing it: that registers the sidebar with
          // CollapsedSidebarModel, so re-tapping Pages in the main
          // navigation still slides it in.
          collapseSidebar: session != null && !sidebarOpen,
          content: content,
        );
      },
    );
  }
}
