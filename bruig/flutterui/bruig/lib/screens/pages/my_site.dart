import 'package:bruig/components/buttons.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/config.dart';
import 'package:bruig/models/pages.dart';
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

  @override
  void initState() {
    super.initState();
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
      if (mounted) setState(() => documents = docs);
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
      await PageDocuments.publish(pages, page);
      await refreshDocuments();
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
      widget.resources.mostRecent = await widget.resources
          .fetchPage(widget.client.publicID, [page.file], 0, 0, null, "");
      widget.pages.browsing = true;
      widget.onOpenedOwnSite();
    } catch (exception) {
      snackbar.error("Unable to preview ${page.name}: $exception");
    }
  }

  /// previewDraft renders the document as it stands.
  ///
  /// Separate from Preview because they answer different questions: Preview
  /// is what a visitor gets, and a page that has never been published has no
  /// answer to that. This is what they would get if it were published now.
  void previewDraft(PageDocument page) async {
    var snackbar = SnackBarModel.of(context);
    try {
      var text = await PostStorage.read(pagesFolderName, page.name);
      if (text == null) {
        snackbar.error("${page.name} has nothing written in it yet.");
        return;
      }
      if (!mounted) return;
      await showDraftPreview(context, page.name, text);
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
        await PageDocuments.publish(pages, PageDocuments.forName(pages, "index"));
      } catch (exception) {
        if (mounted) {
          SnackBarModel.of(context).error("Unable to write front page: $exception");
        }
      }
    }
  }

  void chooseDir() async {
    var snackbar = SnackBarModel.of(context);
    var dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: "Directory to serve pages from");
    if (dir == null) return;
    var cfg = pages.hostConfig;
    try {
      await pages.setHost(cfg.copyWith(
          mode: cfg.hostsAnything
              ? cfg.mode
              : pagesHostModePages,
          pagesPath: dir));
    } catch (exception) {
      snackbar.error("Unable to change the pages directory: $exception");
    }
  }

  void viewOwnSite() async {
    var snackbar = SnackBarModel.of(context);
    try {
      var sess = await widget.resources
          .fetchPage(widget.client.publicID, ["index.md"], 0, 0, null, "");
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
  bool get hasWriting => hasWritingPage(
      Provider.of<MainMenuModel>(context, listen: false));

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
      await PostStorage.delete(PostEntry(
          name: page.name, folder: pagesFolderName, isFolder: false));
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
          return _PageEditor(
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
          onPublish: publishPage,
          onUnpublish: unpublishPage,
          onPreview: previewPage,
          onPreviewDraft: previewDraft,
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

  /// onPreviewDraft renders the document instead, which is the only way to
  /// look at a page that has never been published or has been written since.
  final void Function(PageDocument) onPreviewDraft;

  /// documents is every page of the site with where it stands -- see
  /// PageDocuments.list.
  final List<PageDocument> documents;
  const _SiteOverview({
    required this.pages,
    required this.documents,
    required this.onToggle,
    required this.onChooseDir,
    required this.onView,
    required this.onNew,
    required this.onEdit,
    required this.onDelete,
    required this.onPublish,
    required this.onUnpublish,
    required this.onPreview,
    required this.onPreviewDraft,
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
        ...documents.map((p) => _PageRow(
              page: p,
              onEdit: () => onEdit(p.name),
              onDelete: () => onDelete(p),
              onPublish: () => onPublish(p),
              onUnpublish: () => onUnpublish(p),
              onPreview: () => onPreview(p),
              onPreviewDraft: () => onPreviewDraft(p),
            )),
      if (cfg.hostsPages) ...[
        const SizedBox(height: 24),
        const _LinkHelp(),
      ],
    ]);
  }
}

class _PageRow extends StatelessWidget {
  final PageDocument page;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPublish;
  final VoidCallback onUnpublish;
  final VoidCallback onPreview;
  final VoidCallback onPreviewDraft;
  const _PageRow({
    required this.page,
    required this.onEdit,
    required this.onDelete,
    required this.onPublish,
    required this.onUnpublish,
    required this.onPreview,
    required this.onPreviewDraft,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);

    // A front page that is not published is worth saying plainly: it does
    // not take one page down, it makes the whole site answer "no front
    // page" to everyone who asks.
    // Deliberately not the state, which the chip beside the name already
    // says -- a row that said "Not published" twice was saying nothing
    // twice.
    var subtitle = page.isIndex
        ? (page.state.live
            ? "Front page — what visitors land on"
            : "Front page — nobody can reach the site without it")
        : null;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading:
          Icon(page.isIndex ? Icons.home_outlined : Icons.description_outlined),
      title: Row(children: [
        Flexible(child: Txt.M(page.name)),
        const SizedBox(width: 8),
        _StateChip(page.state, warn: page.isIndex && !page.state.live),
      ]),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle != null)
            Txt.S(subtitle,
                color: page.state.live
                    ? TextColor.onSurfaceVariant
                    : TextColor.onErrorContainer),
          // The link another page writes to reach this one. Shown because
          // it is not the page's name -- a page called "Test Page" is
          // linked as "test_page.md" -- so there is nowhere else to find
          // out what to type.
          _LinkChip(page.link, conflict: page.conflict),
        ],
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          icon: const Icon(Icons.drafts_outlined, size: 18),
          // Always available: it reads the document, which exists whatever
          // the site is serving.
          tooltip: "Preview ${page.name} as written",
          onPressed: onPreviewDraft,
        ),
        IconButton(
          icon: const Icon(Icons.visibility_outlined, size: 18),
          // Preview fetches the page from the site, which is the point:
          // it is what a visitor gets, not what the editor thinks. So a
          // page that is not published has nothing to show, and says so
          // rather than opening an empty browser.
          tooltip: page.state.live
              ? "Preview ${page.name}"
              : "Publish ${page.name} to preview it",
          onPressed: page.state.live ? onPreview : null,
        ),
        // Publish is offered whenever the served copy is not what the
        // document says -- which is both "never published" and "written
        // since", the two cases where a visitor is not reading this.
        if (page.state != PagePublishState.published)
          IconButton(
            icon: const Icon(Icons.publish_outlined, size: 18),
            tooltip: page.state == PagePublishState.draft
                ? "Publish ${page.name}"
                : "Publish update to ${page.name}",
            color: theme.colors.primary,
            onPressed: onPublish,
          ),
        if (page.state.live)
          IconButton(
            icon: const Icon(Icons.visibility_off_outlined, size: 18),
            tooltip: "Unpublish ${page.name}",
            onPressed: onUnpublish,
          ),
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 18),
          tooltip: "Edit ${page.name}",
          onPressed: onEdit,
        ),
        // No delete for the front page: a site with no front page cannot
        // be visited at all, so taking it down is Unpublish's job, where it
        // can be put back.
        if (!page.isIndex)
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: "Delete ${page.name}",
            onPressed: onDelete,
          ),
      ]),
      onTap: onEdit,
    );
  }
}

/// showDraftPreview renders a page as it stands, without publishing it.
///
/// Drawn by the same renderer a visitor's client uses, so what it shows is
/// what they would see -- but from the document rather than from the site,
/// which is the only way to look at a page that has never been published or
/// has been written since.
///
/// br:// links inside it are not followed: this is a look at one page, and
/// following a link would mean fetching, which is the other preview's job.
Future<void> showDraftPreview(
        BuildContext context, String name, String text) =>
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(children: [
                  const Icon(Icons.drafts_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Txt.L("Draft — $name")),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: "Close preview",
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ]),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: MarkdownArea(text, false),
                ),
              ),
            ],
          ),
        ),
      ),
    );

/// _LinkChip shows the link a page is reached by, and warns when two pages
/// want the same one.
class _LinkChip extends StatelessWidget {
  final String link;
  final bool conflict;
  const _LinkChip(this.link, {this.conflict = false});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: Text(link,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11,
                fontFamily: "monospace",
                color: theme.colors.onSurfaceVariant)),
      ),
      if (conflict) ...[
        const SizedBox(width: 6),
        Tooltip(
          message: "Another page publishes to this same link, and would "
              "replace this one",
          child: Icon(Icons.warning_amber_rounded,
              size: 13, color: theme.colors.error),
        ),
      ],
    ]);
  }
}

/// _StateChip says where a page stands. Deliberately drawn for every state
/// including the settled one: a row with no marking would read as "no
/// information" rather than "published and current".
class _StateChip extends StatelessWidget {
  final PagePublishState state;
  final bool warn;
  const _StateChip(this.state, {this.warn = false});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    Color color;
    if (warn) {
      color = theme.colors.error;
    } else {
      switch (state) {
        case PagePublishState.published:
          color = theme.extraColors.successOnSurface;
          break;
        case PagePublishState.edited:
          color = theme.colors.primary;
          break;
        case PagePublishState.draft:
          color = theme.colors.onSurfaceVariant;
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(state.label, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}

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

/// _PageEditor writes one markdown file. A name of "" is a new page.
class _PageEditor extends StatefulWidget {
  final PagesModel pages;
  final VoidCallback onDone;
  const _PageEditor(
      {super.key, required this.pages, required this.onDone});

  @override
  State<_PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends State<_PageEditor> {
  final nameCtrl = TextEditingController();
  final bodyCtrl = TextEditingController();
  bool saving = false;

  PageDraft get draft => widget.pages.pageDraft ?? const PageDraft(editing: "");
  bool get isNew => draft.isNew;

  @override
  void initState() {
    super.initState();
    // Whatever was typed before, which is there when coming back to a draft
    // left open. The boxes are the draft's, not the file's.
    nameCtrl.text = draft.name;
    bodyCtrl.text = draft.body;
    nameCtrl.addListener(remember);
    bodyCtrl.addListener(remember);
    if (!draft.loaded) load();
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    bodyCtrl.dispose();
    super.dispose();
  }

  /// remember hands what is in the boxes to the model, which outlives this
  /// screen. Deliberately not notifying -- see PagesModel's draft section.
  void remember() => widget.pages
      .updatePageDraft(draft.copyWith(name: nameCtrl.text, body: bodyCtrl.text));

  void load() async {
    var name = draft.editing;
    try {
      // The document is what is edited. A page that is only being served --
      // written before any of this existed -- is brought into the library
      // first, so there is always a document behind the editor.
      await PageDocuments.adopt(
          widget.pages, PageDocuments.forName(widget.pages, name));
      var content =
          await PostStorage.read(pagesFolderName, documentNameFor(name)) ?? "";
      if (!mounted) return;
      bodyCtrl.text = content;
    } catch (exception) {
      if (mounted) {
        SnackBarModel.of(context).error("Unable to read page: $exception");
      }
    }
    if (!mounted) return;
    // Marked loaded either way: a page that could not be read is not going
    // to read on the second attempt either, and retrying on every rebuild
    // would overwrite whatever was typed in the meantime.
    widget.pages.updatePageDraft(draft.copyWith(loaded: true));
    setState(() {});
  }

  /// save writes the document. It does not publish: what visitors are
  /// reading only changes when somebody says so.
  ///
  void save() async {
    var snackbar = SnackBarModel.of(context);
    var name = nameCtrl.text.trim();
    if (name.isEmpty) {
      snackbar.error("The page needs a name.");
      return;
    }
    var doc = documentNameFor(name);

    setState(() => saving = true);
    try {
      await PostStorage.write(pagesFolderName, doc, bodyCtrl.text);

      // Renaming through the name field leaves the old one behind, so drop
      // it -- both the document and anything published under it -- once the
      // new one is safely written.
      var wasPublished = false;
      if (!isNew && doc != documentNameFor(draft.editing)) {
        var old = PageDocuments.forName(widget.pages, draft.editing);
        wasPublished = old.state.live;
        if (wasPublished) {
          await PageDocuments.unpublish(widget.pages, old);
        }
        var entry = PostEntry(
            name: old.name, folder: pagesFolderName, isFolder: false);
        await PostStorage.delete(entry);
      }

      // A rename of something that was published republishes under the new
      // name, or renaming a live page would silently take it down.
      if (wasPublished) {
        await PageDocuments.publish(
            widget.pages, PageDocuments.forName(widget.pages, doc));
      }
      widget.onDone();
    } catch (exception) {
      snackbar.error("Unable to save page: $exception");
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!draft.loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 18),
            tooltip: "Back to pages",
            onPressed: widget.onDone,
          ),
          Expanded(child: Txt.L(isNew ? "New page" : draft.editing)),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            isDense: true,
            labelText: "File name",
            helperText: "index.md is the page visitors land on",
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TextField(
            controller: bodyCtrl,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              alignLabelWithHint: true,
              labelText: "Markdown",
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // One button. Saving keeps the writing; publishing is done from the
        // list this returns to, where the page's state is shown beside it --
        // so there is one place a page is published from rather than two
        // that have to agree.
        Row(children: [
          ElevatedButton(
            style: raisedButtonStyle(ThemeNotifier.of(context)),
            onPressed: saving ? null : () => save(),
            child: Text(saving ? "Saving…" : "Save"),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: widget.onDone, child: const Text("Cancel")),
        ]),
      ]),
    );
  }
}
