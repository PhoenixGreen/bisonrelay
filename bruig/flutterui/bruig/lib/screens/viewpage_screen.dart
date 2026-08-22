import 'dart:async';

import 'package:bruig/components/containers.dart';
import 'package:bruig/components/empty_widget.dart';
import 'package:bruig/components/pages_bar.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/models/pages.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/screens/overview.dart';
import 'package:bruig/screens/pages/browser.dart';
import 'package:bruig/screens/pages/my_site.dart';
import 'package:bruig/screens/pages/sections.dart';
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

  String sessionNick(PagesSession? sess) {
    if (sess == null) return "";
    var uid = sess.currentPage?.uid ?? sess.pendingUid;
    return pageOwnerName(
        uid, widget.client.publicID, widget.client.getNick(uid));
  }

  String sessionPath(PagesSession? sess) =>
      (sess?.currentPage?.request.path ?? sess?.pendingPath ?? const [])
          .join("/");

  /// reload asks for the page again, and goHome for the front page of
  /// whoever is being read.
  ///
  /// Here rather than in PageBrowser because the bar that calls them is
  /// here: it is drawn above every section, not only above a page.
  void reload() async {
    var sess = resources.mostRecent;
    var page = sess?.currentPage;
    if (sess == null || page == null) return;
    var snackbar = SnackBarModel.of(context);
    try {
      // reload: true, or this would find the page it is meant to replace
      // sitting in the history and show that instead.
      await resources.fetchPage(
          page.uid, page.request.path, sess.id, page.pageID, null, "",
          reload: true);
    } catch (exception) {
      snackbar.error("Unable to reload page: $exception");
    }
  }

  void goHome() async {
    var sess = resources.mostRecent;
    var page = sess?.currentPage;
    if (sess == null || page == null) return;
    var snackbar = SnackBarModel.of(context);
    try {
      await resources
          .fetchPage(page.uid, ["index.md"], sess.id, page.pageID, null, "");
    } catch (exception) {
      snackbar.error("Unable to open front page: $exception");
    }
  }

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

  // The sidebar's visibility is PagesModel's -- the reader's setting for
  // the whole section, kept wherever they put it. See PagesModel.sidebarOpen
  // for why it is not reset when a page opens.
  void toggleSidebar() => pages.sidebarOpen = !pages.sidebarOpen;



  /// openTabs is what is open, in the order the strip shows it: the sections
  /// first, then the pages.
  ///
  /// One list, because a tab is a tab. A section and a page are different
  /// things behind the strip -- one is a view of this client, the other a
  /// fetched document -- and that difference used to reach the reader:
  /// closing a section dropped the whole area back to Visit while its
  /// neighbours sat there untouched, and closing a page did not.
  List<Object> get openTabs => [
        for (var i in const [pagesTabMySite, pagesTabStore])
          if (pages.openSections.contains(i)) i,
        ...resources.sessions,
      ];

  /// closeTab shuts one and moves to whatever is still open.
  ///
  /// Closing a tab that is not the one being looked at moves nothing: what
  /// is on screen is still open, and jumping away from it because something
  /// else was shut is the behaviour this replaced.
  void closeTab(Object tab) {
    var was = openTabs;
    var at = was.indexOf(tab);
    if (at == -1) return;

    var current = tab is int
        ? (!pages.browsing && pages.tab == tab)
        : (pages.browsing && identical(resources.mostRecent, tab));

    if (tab is int) {
      pages.closeSection(tab);
    } else {
      resources.closeSession((tab as PagesSession).id);
    }
    if (!current) return;

    var next = nextTabAfterClosing(was, at);
    if (next == null) {
      pages
        ..browsing = false
        ..tab = pagesTabVisit;
      return;
    }
    if (next is int) {
      onItemChanged(next);
    } else {
      openSession(next as PagesSession);
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
          var sidebarOpen = pagesModel.sidebarOpen;

          // Below the collapse width -- or under the collapsed submenu
          // style -- the sidebar is the drawer's whatever this screen sets,
          // and only the main navigation's re-tap opens it. The toggle
          // would set a flag nothing reads, so it is not offered rather
          // than offered and dead.
          var inDrawer = sidebarIsInDrawer(context, constraints.maxWidth);

          // The chrome -- tab strip and browser bar -- sits above every
          // section, not only above a page. Two reasons, and the second is
          // the one that matters: an open page stays reachable from
          // wherever you are, and the sidebar toggle is somewhere you can
          // always find it. It lives in this bar, so a bar that appeared
          // only while reading a page would leave the sidebar shut with no
          // way to open it again.
          // Every section stays built while another is looked at, so a
          // half-written page or product survives the trip -- see
          // PagesSections.
          var body = PagesSections(
            index: browsing ? PagesSections.browserIndex : tab,
            visit: VisitTab(widget.client, pages, resources, showBrowser),
            mySite: MySiteTab(pages, widget.client, resources, showBrowser),
            store: StoreTab(pages),
            browser: session == null
                ? const Empty()
                : PageBrowser(session, widget.client, resources),
          );

          // Sections open as tabs too, beside the pages -- so what is open
          // is visible, and moving between a page and the store is one
          // click rather than a trip through the sidebar. Kept in the tab
          // order rather than the order they were opened, so they do not
          // swap places under the pointer.
          var sectionTabs = [
            for (var i in const [pagesTabMySite, pagesTabStore])
              if (pagesModel.openSections.contains(i))
                PageTab(
                  label: pagesTabLabels[i],
                  icon: sectionIcon(i),
                  current: !browsing && tab == i,
                  onOpen: () => onItemChanged(i),
                  onClose: () => closeTab(i),
                ),
          ];

          var tabs = [
            ...sectionTabs,
            for (var sess in open)
              PageTab(
                label: sessionLabel(sess),
                current: browsing && identical(sess, session),
                onOpen: () => openSession(sess),
                onClose: () => closeTab(sess),
              ),
          ];

          var content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (tabs.isNotEmpty) ...[
                PageTabStrip(tabs: tabs),
                const Divider(height: 1),
              ],
              PageBrowserBar(
                session: browsing ? session : null,
                sectionLabel: pagesTabLabels[tab],
                nick: browsing ? sessionNick(session) : "",
                path: browsing ? sessionPath(session) : "",
                loading: browsing && session.loading,
                sidebarOpen: sidebarOpen,
                onToggleSidebar: inDrawer ? null : toggleSidebar,
                // The sidebar is the usual way to these two, and it can be
                // shut -- so the bar carries them as well, or hiding the
                // sidebar would put them out of reach entirely.
                section: browsing ? -1 : tab,
                onSection: (i) => onItemChanged(i),
                onBack: () => session?.goBack(),
                onForward: () => session?.goForward(),
                onReload: reload,
                onHome: goHome,
              ),
              const Divider(height: 1),
              Expanded(child: body),
            ],
          );

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
            // One setting, honoured on every section: see
            // PagesModel.sidebarOpen.
            collapseSidebar: !sidebarOpen,
            content: content,
          );
        },
      );
    });
  }
}
