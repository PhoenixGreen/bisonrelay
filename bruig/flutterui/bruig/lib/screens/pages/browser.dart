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
  const PageBrowser(this.session, this.client, this.resources, {super.key});

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
      await widget.resources.fetchPage(
          page.uid, page.request.path, session.id, page.pageID, null, "");
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

    if (page == null) {
      return BrowserMessage(
        icon: session.timedOut ? Icons.schedule : Icons.hourglass_empty,
        title: session.timedOut ? "No answer yet" : "Requesting page…",
        detail: session.timedOut
            ? "The request is still queued and will be delivered whenever "
                "they reconnect. Nothing has come back so far."
            : "Waiting for the page to come back.",
      );
    }

    var path = page.request.path.join("/");
    var nick = pageOwnerName(
        page.uid, widget.client.publicID, widget.client.getNick(page.uid));
    var status = page.response.status;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageBrowserBar(
        session: session,
        nick: nick,
        path: path,
        loading: session.loading,
        onBack: () => session.goBack(),
        onForward: () => session.goForward(),
        onReload: reload,
        onHome: goHome,
      ),
      const Divider(height: 1),
      Expanded(
        child: status == 200
            ? ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Provider<PagesSource>(
                    key: pageKey,
                    create: (context) =>
                        PagesSource(page.uid, page.sessionID, page.pageID),
                    builder: (context, child) =>
                        MarkdownArea(markdownData, false),
                  ),
                ],
              )
            : PageStatusMessage(status: status, nick: nick, path: path),
      ),
    ]);
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
      ]),
    );
  }
}
