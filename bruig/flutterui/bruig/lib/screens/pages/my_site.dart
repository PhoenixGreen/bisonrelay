import 'package:bruig/components/buttons.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/config.dart';
import 'package:bruig/models/pages.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    pages.loadHost();
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
        await pages.savePage("index.md", starterIndex);
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

  void newPage() => pages.startPageDraft("");

  void deletePage(String name) async {
    var snackbar = SnackBarModel.of(context);
    try {
      await pages.deletePage(name);
    } catch (exception) {
      snackbar.error("Unable to delete $name: $exception");
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
          onToggle: toggleHosting,
          onChooseDir: chooseDir,
          onView: viewOwnSite,
          onNew: newPage,
          onEdit: pages.startPageDraft,
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
  final void Function(String) onDelete;
  const _SiteOverview({
    required this.pages,
    required this.onToggle,
    required this.onChooseDir,
    required this.onView,
    required this.onNew,
    required this.onEdit,
    required this.onDelete,
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
      else if (pages.localPages.isEmpty)
        const Txt.S("No pages yet.", color: TextColor.onSurfaceVariant)
      else
        ...pages.localPages.map((p) => _PageRow(
              page: p,
              onEdit: () => onEdit(p.name),
              onDelete: () => onDelete(p.name),
            )),
      if (cfg.hostsPages) ...[
        const SizedBox(height: 24),
        const _LinkHelp(),
      ],
    ]);
  }
}

class _PageRow extends StatelessWidget {
  final LocalPage page;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _PageRow(
      {required this.page, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(page.isIndex ? Icons.home_outlined : Icons.description_outlined),
      title: Txt.M(page.name),
      subtitle: Txt.S(
          page.isIndex
              ? "Front page — what visitors land on"
              : "${page.size} bytes",
          color: TextColor.onSurfaceVariant),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 18),
          tooltip: "Edit ${page.name}",
          onPressed: onEdit,
        ),
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
      var content = await widget.pages.readPage(name);
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

  void save() async {
    var snackbar = SnackBarModel.of(context);
    var name = nameCtrl.text.trim();
    if (name.isEmpty) {
      snackbar.error("The page needs a name.");
      return;
    }
    if (!name.endsWith(".md")) name = "$name.md";

    setState(() => saving = true);
    try {
      await widget.pages.savePage(name, bodyCtrl.text);
      // Renaming through the name field leaves the old file behind, so drop
      // it once the new one is safely written.
      if (!isNew && name != draft.editing) {
        await widget.pages.deletePage(draft.editing);
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
        Row(children: [
          ElevatedButton(
            style: raisedButtonStyle(ThemeNotifier.of(context)),
            onPressed: saving ? null : save,
            child: Text(saving ? "Saving…" : "Save"),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: widget.onDone, child: const Text("Cancel")),
        ]),
      ]),
    );
  }
}
