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
    // Also leaves the browser, without closing the page -- see
    // PagesModel.tab.
    pages.tab = index;
    Timer(const Duration(milliseconds: 1),
        () async => menu.activePageTab = index);
  }

  // Opening a site switches to the browser rather than staying on the list
  // that launched it: the page is the thing that was asked for. The callers
  // set PagesModel.browsing; this is only to rebuild.
  void showBrowser() => setState(() {});

  /// sessionLabel names an open page: whose it is, and which of theirs.
  String sessionLabel(PagesSession sess) {
    var uid = sess.currentPage?.uid ?? sess.pendingUid;
    return openPageLabel(
      pageOwnerName(uid, widget.client.publicID, widget.client.getNick(uid)),
      sess.currentPage?.request.path ?? sess.pendingPath,
    );
  }

  void openSession(PagesSession sess) {
    resources.mostRecent = sess;
    pages.browsing = true;
  }

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

  Widget activeTab(int tab, Widget visitArea) {
    switch (tab) {
      case pagesTabMySite:
        return MySiteTab(pages, widget.client, resources, showBrowser);
      case pagesTabStore:
        return StoreTab(pages);
      default:
        return visitArea;
    }
  }

  /// closeSession shuts a page and decides what to show instead.
  ///
  /// With pages left, ResourcesModel has already moved to a neighbour.
  /// With none, there is nothing to browse: the area falls back to the
  /// contact list, which is where a page is started from.
  void closeSession(PagesSession sess) {
    resources.closeSession(sess.id);
    if (resources.mostRecent == null) {
      pages
        ..browsing = false
        ..tab = pagesTabVisit;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ModalRoute.of(context)!.settings.arguments != null) {
      final args = ModalRoute.of(context)!.settings.arguments as PageTabs;
      pages.tab = args.tabIndex;
    }

    // The width the layout below will see, which is what decides whether a
    // sidebar can be a column at all -- not the width of the browser bar,
    // which sits inside the narrower content area.
    return LayoutBuilder(builder: (context, constraints) {
      return Consumer2<PagesModel, ResourcesModel>(
        builder: (context, pagesModel, resources, _) {
          var session = resources.mostRecent;
          var browsing = pagesModel.browsing && session != null;
          var tab = pagesModel.tab.clamp(0, pagesTabLabels.length - 1);

          var open = resources.sessions;
          var items = pagesBarItems(onItemChanged, tab);

          // A page opening for the first time takes the sidebar aside, so
          // the reading measure is the page's -- see sidebarOpen.
          if (!identical(session, _openSession)) {
            _openSession = session;
            sidebarOpen = false;
          }

          // Below the collapse width -- or under the collapsed submenu
          // style -- the sidebar is the drawer's whatever this screen sets,
          // and only the main navigation's re-tap opens it. The toggle
          // would set a flag nothing reads, so it is not offered rather
          // than offered and dead.
          var inDrawer = sidebarIsInDrawer(context, constraints.maxWidth);

          // The Visit area is the browser: the contact list is what shows
          // with nothing open, and it stays reachable through the strip's
          // new-tab button once something is -- which is what a browser's
          // new-tab page is. Keeping them in one place is what lets the
          // sidebar go back to three plain destinations.
          Widget visitArea = browsing
              ? PageBrowser(
                  session,
                  widget.client,
                  resources,
                  sidebarOpen: sidebarOpen,
                  onToggleSidebar: inDrawer ? null : toggleSidebar,
                )
              : VisitTab(widget.client, pages, resources, showBrowser);

          if (open.isNotEmpty) {
            visitArea = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageTabStrip(
                  tabs: [
                    for (var sess in open)
                      PageTab(
                        label: sessionLabel(sess),
                        current: browsing && identical(sess, session),
                        onOpen: () => openSession(sess),
                        onClose: () => closeSession(sess),
                      ),
                  ],
                  newTabSelected: !browsing,
                  onNewTab: () => pages.browsing = false,
                ),
                const Divider(height: 1),
                Expanded(child: visitArea),
              ],
            );
          }

          var content = activeTab(tab, visitArea);

          return SecondarySideMenuLayout(
            storageKey: "pages",
            items: items,
            sidebarRevision:
                Object.hash(tab, items.length, sidebarOpen, browsing),
            isDetail: ModalRoute.of(context)!.settings.arguments != null,
            // Deliberately the same path a narrow window takes rather than
            // simply not drawing it: that registers the sidebar with
            // CollapsedSidebarModel, so re-tapping Pages in the main
            // navigation still slides it in.
            collapseSidebar: browsing && !sidebarOpen,
            content: content,
          );
        },
      );
    });
  }
}
