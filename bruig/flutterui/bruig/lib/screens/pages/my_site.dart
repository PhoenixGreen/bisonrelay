import 'package:bruig/components/buttons.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/config.dart';
import 'package:bruig/models/pages.dart';
import 'package:bruig/screens/pages/page_editor.dart';
import 'package:bruig/screens/pages/site_rows.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:golib_plugin/definitions.dart';

/// starterIndex is what a brand new site says before its owner writes
/// anything. It is deliberately a real page rather than an empty file: the
/// first thing an author does is read their own front page, and an empty one
/// looks like a fault.
const starterIndex = """
# Welcome

This is my Bison Relay site. Anyone I have a connection with can read it,
served straight from my client -- there is no server in the middle, and no
copy of it anywhere else.

Nothing here is public: it is only readable by people I am already connected
to, and only while I am online.
""";

/// MySiteTab is the hosting half of the Pages section: whether this client
/// serves anything, and the markdown behind it.
class MySiteTab extends StatefulWidget {
  final PagesModel pages;
  final ClientModel client;
  final ResourcesModel resources;
  final VoidCallback onOpenedOwnSite;
  const MySiteTab(this.pages, this.client, this.resources, this.onOpenedOwnSite,
      {super.key});

  @override
  State<MySiteTab> createState() => _MySiteTabState();
}

class _MySiteTabState extends State<MySiteTab> {
  PagesModel get pages => widget.pages;

  /// documents is every page of the site with where it stands. Derived from
  /// the library and the served directory, so it is recomputed rather than
  /// stored -- there is nothing here that is not already on disk.
  List<PageDocument> documents = const [];

  /// fragments are the shared pieces the pages include -- see
  /// PageDocuments and doc/pages.md. Listed apart from the pages because
  /// they are not pages: a visitor never lands on one, and it has no link
  /// of its own worth showing.
  List<PageDocument> fragments = const [];

  @override
  void initState() {
    super.initState();
    pages.ownUid = widget.client.publicID;
    pages.loadHost().then((_) => refreshDocuments());
    pages.addListener(refreshDocuments);
  }

  @override
  void dispose() {
    pages.removeListener(refreshDocuments);
    super.dispose();
  }

  bool _refreshing = false;

  /// refreshDocuments rereads the list. Guarded because it is hung off the
  /// model's own notifications and publishing notifies -- without this a
  /// publish would start a reread that finished, notified, and started
  /// another.
  Future<void> refreshDocuments() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      var docs = await PageDocuments.list(pages);
      var frags = await PageDocuments.list(pages, folder: partialsFolderName);
      if (mounted) {
        setState(() {
          documents = docs;
          fragments = frags;
        });
      }
    } catch (exception) {
      if (mounted) {
        SnackBarModel.of(context).error("Unable to list pages: $exception");
      }
    } finally {
      _refreshing = false;
    }
  }

  void publishPage(PageDocument page) async {
    var snackbar = SnackBarModel.of(context);
    try {
      // A page only being served, with no document behind it, has to be
      // brought into the library before it can be published from one.
      await PageDocuments.adopt(pages, page);
      var missing = await PageDocuments.publish(pages, page);
      await refreshDocuments();
      if (missing > 0) {
        snackbar.error("${page.name} was published with $missing picture"
            "${missing == 1 ? "" : "s"} missing.");
      }
    } catch (exception) {
      snackbar.error("Unable to publish ${page.name}: $exception");
    }
  }

  /// previewPage opens one page of the reader's own site in the browser.
  ///
  /// The same fetch a visitor makes, against the served copy, so what it
  /// shows is what they would get rather than what the editor holds.
  void previewPage(PageDocument page) async {
    var snackbar = SnackBarModel.of(context);
    try {
      widget.resources.mostRecent = await widget.resources.fetchPage(
          widget.client.publicID, [page.file], 0, 0, null, "",
          reload: true);
      widget.pages.browsing = true;
      widget.onOpenedOwnSite();
    } catch (exception) {
      snackbar.error("Unable to preview ${page.name}: $exception");
    }
  }

  void unpublishPage(PageDocument page) async {
    var snackbar = SnackBarModel.of(context);
    try {
      // Adopted first, or unpublishing a page that was only ever served
      // would be a delete: there would be nothing left to publish again.
      await PageDocuments.adopt(pages, page);
      await PageDocuments.unpublish(pages, page);
      await refreshDocuments();
    } catch (exception) {
      snackbar.error("Unable to unpublish ${page.name}: $exception");
    }
  }

  Future<void> _apply(PagesHostConfig cfg) async {
    var snackbar = SnackBarModel.of(context);
    try {
      await pages.setHost(cfg);
    } catch (exception) {
      snackbar.error("Unable to change hosting: $exception");
    }
  }

  void toggleHosting(bool on) async {
    var cfg = pages.hostConfig;
    if (!on) {
      await _apply(cfg.copyWith(mode: pagesHostModeOff));
      return;
    }

    var path = cfg.pagesPath.isNotEmpty
        ? cfg.pagesPath
        : (pages.host?.defaultPath ?? "");
    if (path.isEmpty) {
      SnackBarModel.of(context).error("No directory to keep the site in.");
      return;
    }

    await _apply(cfg.copyWith(
      mode: cfg.hostsStore ? pagesHostModeBoth : pagesHostModePages,
      pagesPath: path,
    ));

    // A site with no front page cannot be visited, so write one the first
    // time hosting is switched on.
    if (mounted && pages.localPages.isEmpty) {
      try {
        await PostStorage.write(pagesFolderName, "index", starterIndex);
        await PageDocuments.publish(
            pages, PageDocuments.forName(pages, "index"));
      } catch (exception) {
        if (mounted) {
          SnackBarModel.of(context)
              .error("Unable to write front page: $exception");
        }
      }
    }
  }

  void chooseDir() async {
    var snackbar = SnackBarModel.of(context);
    var dir = await FilePicker.platform
        .getDirectoryPath(dialogTitle: "Directory to serve pages from");
    if (dir == null) return;
    var cfg = pages.hostConfig;
    try {
      await pages.setHost(cfg.copyWith(
          mode: cfg.hostsAnything ? cfg.mode : pagesHostModePages,
          pagesPath: dir));
    } catch (exception) {
      snackbar.error("Unable to change the pages directory: $exception");
    }
  }

  void viewOwnSite() async {
    var snackbar = SnackBarModel.of(context);
    try {
      var sess = await widget.resources.fetchPage(
          widget.client.publicID, ["index.md"], 0, 0, null, "",
          reload: true);
      widget.resources.mostRecent = sess;
      widget.pages.browsing = true;
      widget.onOpenedOwnSite();
    } catch (exception) {
      snackbar.error("Unable to open own site: $exception");
    }
  }

  /// writingPage is the Writing section, when the writing tools are on.
  ///
  /// New and Edit go there when it exists: a page is writing, and the
  /// Writing page is the app's place for writing -- with the formatting
  /// panel, the checks and the library beside it. The editor below is what
  /// is left for everybody else, and is why it still exists.
  ///
  /// The same redirect the Feed's New Post link makes, for the same reason.
  bool get hasWriting =>
      hasWritingPage(Provider.of<MainMenuModel>(context, listen: false));

  /// openInWriting makes sure there is a document, hands it to the library
  /// and goes there.
  Future<void> openInWriting(String name, {bool creating = false}) async {
    var snackbar = SnackBarModel.of(context);
    var library = Provider.of<PostLibraryModel>(context, listen: false);
    var navigator = Navigator.of(context);
    var doc = documentNameFor(name);
    try {
      if (creating) {
        // A name is needed before there is a document, and an empty one
        // cannot be filed. Named for what it is until it is renamed.
        doc = await _freeName();
        await PostStorage.write(pagesFolderName, doc, "");
      } else {
        await PageDocuments.adopt(pages, PageDocuments.forName(pages, name));
      }
      await library.requestOpen(pagesFolderName, doc);
      navigator.pushReplacementNamed(WritingScreen.routeName);
    } catch (exception) {
      snackbar.error("Unable to open $doc for writing: $exception");
    }
  }

  /// _freeName picks a name no page is using yet.
  Future<String> _freeName() async {
    var taken = {
      for (var d in documents) d.name.toLowerCase(),
    };
    if (!taken.contains("new page")) return "New page";
    for (var i = 2;; i++) {
      if (!taken.contains("new page $i".toLowerCase())) return "New page $i";
    }
  }

  void newPage() {
    if (hasWriting) {
      openInWriting("", creating: true);
      return;
    }
    pages.startPageDraft("");
  }

  /// newFragment makes a shared piece and opens it. Only offered with the
  /// writing tools on: the fallback editor below writes pages, and a second
  /// one for fragments would be the same editor twice.
  void newFragment() async {
    var snackbar = SnackBarModel.of(context);
    var library = Provider.of<PostLibraryModel>(context, listen: false);
    var navigator = Navigator.of(context);
    try {
      var taken = {for (var f in fragments) f.name.toLowerCase()};
      var name = "navigation";
      for (var i = 2; taken.contains(name); i++) {
        name = "fragment $i";
      }
      await PostStorage.write(partialsFolderName, name, "");
      await library.requestOpen(partialsFolderName, name);
      navigator.pushReplacementNamed(WritingScreen.routeName);
    } catch (exception) {
      snackbar.error("Unable to make a fragment: $exception");
    }
  }

  void editFragment(String name) async {
    if (!hasWriting) return;
    var library = Provider.of<PostLibraryModel>(context, listen: false);
    var navigator = Navigator.of(context);
    await PageDocuments.adopt(
        pages, PageDocuments.forName(pages, name, folder: partialsFolderName));
    await library.requestOpen(partialsFolderName, name);
    navigator.pushReplacementNamed(WritingScreen.routeName);
  }

  void deleteFragment(PageDocument f) async {
    var snackbar = SnackBarModel.of(context);
    try {
      await pages.deletePage(f.file);
      await PostStorage.delete(
          PostEntry(name: f.name, folder: partialsFolderName, isFolder: false));
      await refreshDocuments();
    } catch (exception) {
      snackbar.error("Unable to delete ${f.name}: $exception");
    }
  }

  void editPage(String name) {
    if (hasWriting) {
      openInWriting(name);
      return;
    }
    pages.startPageDraft(pageFileNameFor(name));
  }

  /// deletePage removes the page for good: the document and anything
  /// published under it.
  ///
  /// Both, deliberately. Deleting only the document would leave the page
  /// still being served with nothing behind it, and deleting only the served
  /// copy is what Unpublish is for.
  void deletePage(PageDocument page) async {
    var snackbar = SnackBarModel.of(context);
    try {
      // The file it is actually served as, not the one its name would
      // suggest -- a page published before the slug rule is served under a
      // name the document cannot reproduce.
      await pages.deletePage(page.file);
      await PostStorage.delete(
          PostEntry(name: page.name, folder: pagesFolderName, isFolder: false));
      await refreshDocuments();
    } catch (exception) {
      snackbar.error("Unable to delete ${page.name}: $exception");
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: pages,
      builder: (context, _) {
        var draft = pages.pageDraft;
        if (draft != null) {
          return PageEditor(
            // Keyed on which page is being written, so switching from one
            // to another builds a fresh editor rather than reusing the
            // first one's boxes.
            key: ValueKey("page-draft-${draft.editing}"),
            pages: pages,
            onDone: pages.endPageDraft,
          );
        }
        return _SiteOverview(
          pages: pages,
          documents: documents,
          fragments: fragments,
          onNewFragment: hasWriting ? newFragment : null,
          onEditFragment: editFragment,
          onDeleteFragment: deleteFragment,
          onPublish: publishPage,
          onUnpublish: unpublishPage,
          onPreview: previewPage,
          onToggle: toggleHosting,
          onChooseDir: chooseDir,
          onView: viewOwnSite,
          onNew: newPage,
          onEdit: editPage,
          onDelete: deletePage,
        );
      },
    );
  }
}

class _SiteOverview extends StatelessWidget {
  final PagesModel pages;
  final void Function(bool) onToggle;
  final VoidCallback onChooseDir;
  final VoidCallback onView;
  final VoidCallback onNew;
  final void Function(String) onEdit;
  final void Function(PageDocument) onDelete;
  final void Function(PageDocument) onPublish;
  final void Function(PageDocument) onUnpublish;

  /// onPreview fetches the page from the site: what a visitor would get.
  final void Function(PageDocument) onPreview;

  /// documents is every page of the site with where it stands -- see
  /// PageDocuments.list.
  final List<PageDocument> documents;

  /// fragments are the shared pieces those pages include.
  final List<PageDocument> fragments;

  /// onNewFragment is null without the writing tools: making one opens the
  /// Writing page, and there is nowhere else to write it.
  final VoidCallback? onNewFragment;
  final void Function(String) onEditFragment;
  final void Function(PageDocument) onDeleteFragment;
  const _SiteOverview({
    required this.pages,
    required this.documents,
    required this.fragments,
    required this.onNewFragment,
    required this.onEditFragment,
    required this.onDeleteFragment,
    required this.onToggle,
    required this.onChooseDir,
    required this.onView,
    required this.onNew,
    required this.onEdit,
    required this.onDelete,
    required this.onPublish,
    required this.onUnpublish,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    var cfg = pages.hostConfig;

    if (!pages.hostEditable) {
      return _ManagedElsewhere(mode: cfg.mode);
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      const Txt.L("My Site"),
      const SizedBox(height: 4),
      const Txt.S(
          "Your site is served from this client, to people you are already "
          "connected to, while you are online. Nothing is uploaded anywhere.",
          color: TextColor.onSurfaceVariant),
      const SizedBox(height: 16),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Txt.M("Host a site"),
        subtitle: Txt.S(
            cfg.hostsPages
                ? "Serving from ${displayPath(cfg.pagesPath)}"
                : "Not serving anything",
            color: TextColor.onSurfaceVariant),
        value: cfg.hostsPages,
        onChanged: pages.loadingHost ? null : onToggle,
      ),
      if (pages.hostError != null) ...[
        const SizedBox(height: 8),
        Txt.S(pages.hostError!, color: TextColor.onErrorContainer),
      ],
      const SizedBox(height: 8),
      Row(children: [
        OutlinedButton.icon(
          onPressed: onChooseDir,
          icon: const Icon(Icons.folder_open, size: 16),
          label: const Text("Change folder"),
        ),
        const SizedBox(width: 8),
        if (cfg.hostsPages)
          OutlinedButton.icon(
            onPressed: onView,
            icon: const Icon(Icons.visibility_outlined, size: 16),
            label: const Text("View my site"),
          ),
      ]),
      const SizedBox(height: 24),
      Row(children: [
        const Expanded(child: Txt.L("Pages")),
        if (cfg.hostsPages)
          ElevatedButton.icon(
            style: raisedButtonStyle(ThemeNotifier.of(context)),
            onPressed: onNew,
            icon: const Icon(Icons.add, size: 16),
            label: const Text("New page"),
          ),
      ]),
      const SizedBox(height: 8),
      if (!cfg.hostsPages)
        const Txt.S("Switch hosting on to write pages.",
            color: TextColor.onSurfaceVariant)
      else if (documents.isEmpty)
        const Txt.S("No pages yet.", color: TextColor.onSurfaceVariant)
      else
        ...documents.map((p) => SiteRow(
              item: p,
              onEdit: () => onEdit(p.name),
              onDelete: () => onDelete(p),
              onPublish: () => onPublish(p),
              onUnpublish: () => onUnpublish(p),
              onPreview: () => onPreview(p),
            )),
      if (cfg.hostsPages) ...[
        const SizedBox(height: 24),
        const FragmentsHelp(),
        Row(children: [
          const Expanded(child: Txt.L("Shared fragments")),
          if (onNewFragment != null)
            OutlinedButton.icon(
              onPressed: onNewFragment,
              icon: const Icon(Icons.add, size: 16),
              label: const Text("New fragment"),
            ),
        ]),
        const SizedBox(height: 8),
        if (fragments.isEmpty)
          const Txt.S("None yet.", color: TextColor.onSurfaceVariant)
        else
          ...fragments.map((f) => SiteRow(
                item: f,
                onEdit: () => onEditFragment(f.name),
                onDelete: () => onDeleteFragment(f),
                onPublish: () => onPublish(f),
                onUnpublish: () => onUnpublish(f),
              )),
        const SizedBox(height: 24),
        const _LinkHelp(),
      ],
    ]);
  }
}

/// _SiteRow is one thing the site is made of: a page, or a fragment its
/// pages share.
///

/// _FragmentRow is one shared fragment.
///
/// Deliberately plainer than a page's row: a fragment has no front-page
/// warning, and no preview -- a visitor never opens one, so there is nothing
/// to look at on its own.

/// _ManagedElsewhere is shown when hosting is pointed at an http upstream or
/// handed to a client over the RPC interface. The app is not the thing
/// serving in those modes, so there is nothing here to change.
class _ManagedElsewhere extends StatelessWidget {
  final String mode;
  const _ManagedElsewhere({required this.mode});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Txt.L("My Site"),
        const SizedBox(height: 8),
        Txt.M("Hosting is set to \"$mode\" in the config file."),
        const SizedBox(height: 6),
        const Txt.S(
            "Pages are being served by something outside this app, so they "
            "cannot be edited here. Change the [resources] upstream line in "
            "brclient.conf to host from the app instead.",
            color: TextColor.onSurfaceVariant),
      ]),
    );
  }
}

class _LinkHelp extends StatelessWidget {
  const _LinkHelp();

  @override
  Widget build(BuildContext context) {
    return const ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Txt.M("Writing pages"),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Txt.S("Pages are markdown. index.md is the front page."),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Txt.S(
              "Link to another of your pages with a plain path: [About](about.md)"),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Txt.S(
              "Link to someone else's site with br://<their id>/index.md — a "
              "reader following it fetches that page from them."),
        ),
      ],
    );
  }
}
