import 'package:bruig/components/md_elements.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// pageOwnerName is who a page belongs to, in the reader's terms.
///
/// Takes the ids rather than the client so it can be tested: constructing a
/// ClientModel loads golib.dylib.
///
/// Falls back to the public id only for someone with no chat -- and never for
/// the reader's own site, which has no chat at all and would otherwise be
/// labelled with a bare hex id on the one page they look at most. "Your site"
/// rather than "My site" so that it still reads as a sentence in the status
/// messages below: "Your site is hosting, but has nothing at ...".
String pageOwnerName(String uid, String ownID, String nick) {
  if (uid == ownID) return "Your site";
  return nick.isNotEmpty ? nick : uid;
}

/// noAnswerDetail explains an unanswered request without guessing which of
/// the two reasons it was.
///
/// Both are common and neither can be told from the other here. A client from
/// before the not-hosting reply existed drops a request it cannot serve
/// rather than answering it, so no site and no connection look identical from
/// this end -- and saying only "still queued" reads as though the page is
/// about to arrive when usually it never will.
String noAnswerDetail(String who) =>
    "Either $who is not online, or they host nothing and are running a "
    "version that does not say so. The request stays queued either way, and "
    "the page will appear if it arrives.";

/// PageBrowser shows one pages session, with the chrome a reader expects of
/// something that follows links: where they are, how to get back, and what
/// happened when a page does not arrive.
class PageBrowser extends StatefulWidget {
  final PagesSession session;
  final ClientModel client;
  final ResourcesModel resources;
  final bool sidebarOpen;

  /// onToggleSidebar is null where the sidebar is the drawer's rather than a
  /// column of this screen's -- see sidebarIsInDrawer. The control is then
  /// left out rather than shown dead: it is the main navigation's re-tap
  /// that opens the drawer, and a button that cannot is only confusing.
  final VoidCallback? onToggleSidebar;
  final VoidCallback onClose;

  /// tabs are every open page. One page draws no strip and keeps the close
  /// button in the address bar; two or more draw the strip, which carries a
  /// close of its own per tab and so takes the bar's place.
  final List<PageTab> tabs;
  const PageBrowser(
    this.session,
    this.client,
    this.resources, {
    required this.sidebarOpen,
    required this.onToggleSidebar,
    required this.onClose,
    this.tabs = const [],
    super.key,
  });

  @override
  State<PageBrowser> createState() => _PageBrowserState();
}

class _PageBrowserState extends State<PageBrowser> {
  PagesSession get session => widget.session;
  String markdownData = "";
  Key pageKey = UniqueKey();

  void updateSession() {
    var newMdData = session.pageData();
    setState(() {
      if (newMdData != markdownData) {
        markdownData = newMdData;

        // Bump pageKey so that the Provider<PagesSource> is recreated with
        // the new page. This is needed so that navigating pages across
        // different UIDs work.
        pageKey = UniqueKey();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    updateSession();
    session.addListener(updateSession);
  }

  @override
  void didUpdateWidget(PageBrowser oldWidget) {
    oldWidget.session.removeListener(updateSession);
    super.didUpdateWidget(oldWidget);
    session.addListener(updateSession);
    updateSession();
  }

  @override
  void dispose() {
    session.removeListener(updateSession);
    super.dispose();
  }

  void reload() async {
    var page = session.currentPage;
    if (page == null) return;
    var snackbar = SnackBarModel.of(context);
    try {
      // reload: true, or this would find the page it is meant to replace
      // sitting in the history and show that instead.
      await widget.resources.fetchPage(
          page.uid, page.request.path, session.id, page.pageID, null, "",
          reload: true);
    } catch (exception) {
      snackbar.error("Unable to reload page: $exception");
    }
  }

  void goHome() async {
    var page = session.currentPage;
    if (page == null) return;
    var snackbar = SnackBarModel.of(context);
    try {
      await widget.resources
          .fetchPage(page.uid, ["index.md"], session.id, page.pageID, null, "");
    } catch (exception) {
      snackbar.error("Unable to open front page: $exception");
    }
  }

  @override
  Widget build(BuildContext context) {
    var page = session.currentPage;

    // Where the bar points. Before anything has come back there is no page
    // to read it off, so it falls back to what was asked for -- which is
    // also what lets the wait name the contact.
    var uid = page?.uid ?? session.pendingUid;
    var path = (page?.request.path ?? session.pendingPath).join("/");
    var nick = pageOwnerName(
        uid, widget.client.publicID, widget.client.getNick(uid));

    Widget body;
    if (page == null) {
      body = BrowserMessage(
        icon: session.timedOut ? Icons.schedule : Icons.hourglass_empty,
        title: session.timedOut ? "No answer" : "Requesting page…",
        detail: session.timedOut
            ? noAnswerDetail(nick)
            : "Waiting for $nick.",
      );
    } else if (page.response.status == 200) {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Provider<PagesSource>(
            key: pageKey,
            create: (context) =>
                PagesSource(page.uid, page.sessionID, page.pageID),
            builder: (context, child) => MarkdownArea(markdownData, false),
          ),
        ],
      );
    } else {
      body = PageStatusMessage(
          status: page.response.status, nick: nick, path: path);
    }

    var stripped = widget.tabs.length > 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (stripped) ...[
        PageTabStrip(tabs: widget.tabs),
        const Divider(height: 1),
      ],
      PageBrowserBar(
        session: session,
        nick: nick,
        path: path,
        loading: session.loading,
        sidebarOpen: widget.sidebarOpen,
        onToggleSidebar: widget.onToggleSidebar,
        // Null once the strip is drawn: every tab there carries its own
        // close, and two ways to shut the same page is one too many.
        onClose: stripped ? null : widget.onClose,
        onBack: () => session.goBack(),
        onForward: () => session.goForward(),
        onReload: reload,
        onHome: goHome,
      ),
      const Divider(height: 1),
      Expanded(child: body),
    ]);
  }
}

/// PageTab is one open page, for the strip above the address bar.
class PageTab {
  final String label;
  final bool current;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  const PageTab({
    required this.label,
    required this.current,
    required this.onOpen,
    required this.onClose,
  });
}

/// PageTabStrip is the row of open pages above the address bar.
///
/// Only drawn once there are two. A strip of one is a label for the thing
/// already filling the screen, and the address bar underneath already says
/// whose page it is -- so a single page keeps the plain close button in the
/// bar instead, and gains no chrome for having been opened.
class PageTabStrip extends StatelessWidget {
  final List<PageTab> tabs;
  const PageTabStrip({super.key, required this.tabs});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Container(
      height: 34,
      color: theme.colors.surfaceContainerHighest.withValues(alpha: 0.4),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        itemBuilder: (context, i) => _Tab(tabs[i]),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final PageTab tab;
  const _Tab(this.tab);

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var selected = tab.current;
    return InkWell(
      onTap: tab.onOpen,
      child: Container(
        // Bounded so a long page name cannot push the other tabs off, and
        // floored so a short one is still big enough to aim at.
        constraints: const BoxConstraints(minWidth: 96, maxWidth: 200),
        padding: const EdgeInsets.only(left: 10, right: 4),
        decoration: BoxDecoration(
          color: selected
              ? theme.colors.surface
              : theme.colors.surfaceContainerHighest.withValues(alpha: 0.4),
          border: Border(
            right: BorderSide(color: theme.colors.outlineVariant, width: 1),
            // The current tab is marked along the top rather than by colour
            // alone, so which page is open survives a theme whose two
            // surfaces are close together.
            top: BorderSide(
              color: selected ? theme.colors.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Txt.S(
              tab.label,
              overflow: TextOverflow.ellipsis,
              color: selected ? TextColor.onSurface : TextColor.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            icon: const Icon(Icons.close, size: 13),
            tooltip: "Close ${tab.label}",
            onPressed: tab.onClose,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
          ),
        ]),
      ),
    );
  }
}

/// PageStatusMessage explains a non-ok reply in the reader's terms. The numbers
/// come from the page protocol -- see SiteStatus, which maps the same set.
class PageStatusMessage extends StatelessWidget {
  final int status;
  final String nick;
  final String path;
  const PageStatusMessage(
      {super.key,
      required this.status,
      required this.nick,
      required this.path});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 404:
        return BrowserMessage(
          icon: Icons.search_off,
          title: "No such page",
          detail: "$nick is hosting, but has nothing at \"$path\".",
        );
      case 501:
        return BrowserMessage(
          icon: Icons.web_asset_off,
          title: "No site",
          detail: "$nick is not hosting any pages.",
        );
      case 400:
        return BrowserMessage(
          icon: Icons.error_outline,
          title: "Bad request",
          detail: "$nick could not make sense of the request for \"$path\".",
        );
      default:
        return BrowserMessage(
          icon: Icons.error_outline,
          title: "Status $status",
          detail: "$nick answered the request for \"$path\" with status "
              "$status.",
        );
    }
  }
}

class BrowserMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  const BrowserMessage(
      {super.key,
      required this.icon,
      required this.title,
      required this.detail});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 40, color: theme.colors.onSurfaceVariant),
          const SizedBox(height: 12),
          Txt.L(title),
          const SizedBox(height: 6),
          Txt.S(detail,
              color: TextColor.onSurfaceVariant, textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

class PageBrowserBar extends StatelessWidget {
  final PagesSession session;
  final String nick;
  final String path;
  final bool loading;
  final bool sidebarOpen;
  final VoidCallback? onToggleSidebar;

  /// onClose is null when the tab strip is showing, which closes pages
  /// itself.
  final VoidCallback? onClose;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onReload;
  final VoidCallback onHome;
  const PageBrowserBar({
    super.key,
    required this.session,
    required this.nick,
    required this.path,
    required this.loading,
    required this.sidebarOpen,
    required this.onToggleSidebar,
    required this.onClose,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    required this.onHome,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(children: [
        if (onToggleSidebar != null)
          IconButton(
            icon: Icon(sidebarOpen ? Icons.menu_open : Icons.menu, size: 18),
            tooltip: sidebarOpen ? "Hide sidebar" : "Show sidebar",
            onPressed: onToggleSidebar,
          ),
        IconButton(
          icon: const Icon(Icons.arrow_back, size: 18),
          tooltip: "Back",
          onPressed: session.canGoBack ? onBack : null,
        ),
        IconButton(
          icon: const Icon(Icons.arrow_forward, size: 18),
          tooltip: "Forward",
          onPressed: session.canGoForward ? onForward : null,
        ),
        IconButton(
          icon: const Icon(Icons.home_outlined, size: 18),
          tooltip: "Front page",
          onPressed: onHome,
        ),
        IconButton(
          icon: const Icon(Icons.refresh, size: 18),
          tooltip: "Reload",
          onPressed: loading ? null : onReload,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              Flexible(
                child: Txt.S("$nick / $path", overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
        ),
        if (onClose != null)
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: "Close page",
            onPressed: onClose,
          ),
      ]),
    );
  }
}
