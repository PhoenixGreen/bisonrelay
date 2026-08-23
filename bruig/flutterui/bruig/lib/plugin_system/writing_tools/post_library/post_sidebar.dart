import 'package:bruig/plugin_system/writing_tools/post_library/post_library_model.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/page_documents.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/post_storage.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

// post_sidebar.dart is the saved-post library in the composer's sidebar
// slot: folders and documents, one level deep, listed the way the directory
// on disk lists them.

/// PostSidebar browses `<appDataDir>/my-posts` and loads what is in it into
/// the composer beside it.
/// _isFrontPage is whether an entry is the site's front page.
///
/// Only inside the Pages folder: an ordinary document called "index" kept
/// somewhere else is just a document.
bool _isFrontPage(PostEntry entry) =>
    !entry.isFolder &&
    entry.folder == pagesFolderName &&
    pageSlug(entry.name) == "index";

/// reservedFolderIcon is the icon for one of the app's own folders.
IconData reservedFolderIcon(String name) {
  switch (name) {
    case pagesFolderName:
      return Icons.web_outlined;
    case storeFolderName:
      return Icons.storefront_outlined;
    default:
      return Icons.sticky_note_2_outlined;
  }
}

class PostSidebar extends StatefulWidget {
  /// The composer whose text is being saved, or null for the frame or two
  /// while one is being rebuilt -- see ComposerSidebarController.visible.
  final TextEditingController? controller;

  const PostSidebar({
    required this.controller,
    super.key,
  });

  @override
  State<PostSidebar> createState() => _PostSidebarState();
}

class _PostSidebarState extends State<PostSidebar> {
  PostLibraryModel get _library => context.read<PostLibraryModel>();

  @override
  void initState() {
    super.initState();
    // After the frame, because both of these notify and the model is being
    // read during this one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _library
        ..watch(widget.controller)
        ..refresh();
    });
  }

  @override
  void didUpdateWidget(covariant PostSidebar old) {
    super.didUpdateWidget(old);
    // The composer can be swapped underneath this, and the model has to
    // follow it or autosave would keep writing the old one's text.
    if (!identical(old.controller, widget.controller)) {
      _library.watch(widget.controller);
    }
  }

  @override
  Widget build(BuildContext context) {
    var library = context.watch<PostLibraryModel>();
    var theme = ThemeNotifier.of(context);

    var header = _header(theme, library);
    var hint = _reorderHint(theme, library);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (header != null) header,
      Expanded(child: _list(theme, library)),
      if (hint != null) hint,
      if (library.error case var message?) _error(theme, message),
      _actions(theme, library),
    ]);
  }

  /// _header is the folder you are in, and nothing when you are not in one.
  ///
  /// At the top level there is no title: the nav icon above already says
  /// which panel this is, and a line reading "My Posts" under an icon
  /// meaning "My Posts" is a line of a narrow column spent twice on the same
  /// word. Inside a folder the name is the only thing saying where you are,
  /// so it stays, with the way back beside it.
  ///
  /// Note what is NOT here: the saving indicator. It used to be, and at the
  /// top level -- where there is otherwise no header at all -- that meant
  /// every autosave inserted a row into the Column and removed it again a
  /// moment later, shoving the whole list down and back on a timer while
  /// somebody typed. The indicator moved to _actions, which is always drawn,
  /// so a save changes no layout at all. Anything added here in future has to
  /// keep that property: this widget's presence must depend only on which
  /// folder is open.
  Widget? _header(ThemeNotifier theme, PostLibraryModel library) {
    if (library.folder.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, size: 18),
          tooltip: "Back to My Posts",
          visualDensity: VisualDensity.compact,
          onPressed: () => library.openFolderNamed(""),
        ),
        Expanded(
          child: Text(
            folderLabel(library.folder),
            style: const TextStyle(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }

  Widget _list(ThemeNotifier theme, PostLibraryModel library) {
    if (library.loading && library.entries.isEmpty) {
      return const Center(
        child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (library.entries.isEmpty) {
      return _note(
          theme,
          library.folder.isEmpty
              ? "Nothing saved yet. Name this post above, or start a new "
                  "document below."
              : "This folder is empty.");
    }
    // Reorderable rather than a plain list, with a handle of its own: the
    // rows are tapped to open a document, so a drag that starts anywhere on
    // one would have to be told apart from a tap by how long it was held.
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      buildDefaultDragHandles: false,
      itemCount: library.entries.length,
      itemBuilder: (context, i) {
        var entry = library.entries[i];
        return _row(theme, library, entry, i,
            key: ValueKey("${entry.isFolder}:${entry.folder}/${entry.name}"));
      },
      onReorderItem: (from, to) => library.reorder(from, to),
      // The row lifted out of the list, without the list's own shadow --
      // this sidebar is already a panel and a second raised surface inside
      // it reads as a dialog opening.
      proxyDecorator: (child, index, animation) => Material(
        color: theme.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        child: child,
      ),
    );
  }

  Widget _row(
      ThemeNotifier theme, PostLibraryModel library, PostEntry entry, int index,
      {required Key key}) {
    var isOpen = !entry.isFolder &&
        entry.name == library.openName &&
        entry.folder == library.openFolder;

    return InkWell(
      key: key,
      onTap: () => entry.isFolder
          ? library.openFolderNamed(entry.name)
          : library.open(entry),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 7, 4, 7),
        child: Row(children: [
          Icon(
            // The reserved folders each get an icon of their own: they
            // behave differently from the folders around them -- they fill
            // themselves, and cannot be renamed or deleted -- and a row that
            // is not quite like its neighbours should not look exactly like
            // them. Different from each other too, since what is in one is
            // not what is in the next.
            entry.isReservedFolder
                ? reservedFolderIcon(entry.name)
                : entry.isFolder
                    ? Icons.folder_outlined
                    : Icons.description_outlined,
            size: 16,
            color:
                isOpen ? theme.colors.primary : theme.colors.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.isFolder ? folderLabel(entry.name) : entry.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isOpen ? FontWeight.w600 : FontWeight.normal,
                    color: isOpen ? theme.colors.primary : null,
                  ),
                ),
                if (!entry.isFolder)
                  Text(
                    _subtitle(entry, isOpen),
                    style: TextStyle(
                        fontSize: 10, color: theme.colors.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          _rowButton(theme, library, entry, index),
        ]),
      ),
    );
  }

  String _subtitle(PostEntry entry, bool isOpen) {
    var parts = <String>[];
    if (isOpen) parts.add("open");
    if (entry.size != null) parts.add(_size(entry.size!));
    if (entry.modified != null) parts.add(_when(entry.modified!));
    return parts.join(" · ");
  }

  String _size(int bytes) {
    if (bytes < 1024) return "$bytes B";
    return "${(bytes / 1024).toStringAsFixed(1)} KB";
  }

  /// _when is deliberately coarse. To the minute today, to the day this
  /// year, and with the year only when it is not this one -- what a reader
  /// wants from this column is "recent or not", and a full timestamp on
  /// every row is noise they have to read past.
  String _when(DateTime at) {
    var now = DateTime.now();
    var sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    if (sameDay) return DateFormat.Hm().format(at);
    if (at.year == now.year) return DateFormat.MMMd().format(at);
    return DateFormat.yMMMd().format(at);
  }

  /// _rowButton is the one control at the end of a row: tap it for the
  /// menu, hold it to drag the row.
  ///
  /// One button rather than the two this used to be -- a drag handle and a
  /// "more" button beside it. Two controls in a column this narrow left the
  /// name of the document about a dozen characters wide, and they are the
  /// same thing to a reader: the things you can do to this row. Holding to
  /// move is the gesture a phone already uses for reordering anything.
  ///
  /// A handle rather than the whole row, still. A row is the thing you tap
  /// to open a document, so a hold that started anywhere on one would take
  /// the place of that tap for anybody who pauses before releasing.
  ///
  /// There is deliberately no Tooltip on this button, and there must not be
  /// one. A Tooltip is an OverlayPortal: while it is showing it has a child
  /// parked in the Overlay's render tree, rooted somewhere else entirely.
  /// Reordering moves a row's element rather than rebuilding it -- every row
  /// carries a GlobalKey of ReorderableListView's own -- and reactivating an
  /// OverlayPortal that way re-attaches its overlay child in the middle of a
  /// layout pass, which the framework refuses:
  ///
  ///   A _RenderLayoutBuilder was mutated in _RenderLayoutBuilder.performLayout
  ///
  /// and the whole sidebar is replaced by a red error box. Reported after
  /// dragging a document to the bottom of a folder, and only reproducible
  /// with a real pointer: the tooltip has to be *showing* for the portal to
  /// have anything to re-attach, and it is showing because the pointer is
  /// resting on this button -- which is exactly where it has to rest to
  /// press and hold. The gesture and the tooltip were the same hover.
  ///
  /// Timing around it does not work either: rows slide under a stationary
  /// pointer while the drag is live, so a tooltip dismissed when the drag
  /// starts is re-armed by the next row to pass beneath. Nothing inside a
  /// reorderable row may own an overlay.
  ///
  /// What the tooltip said -- that holding this moves the row -- was never a
  /// fact about one row anyway. It is said once, under the list, by
  /// _reorderHint.
  Widget _rowButton(ThemeNotifier theme, PostLibraryModel library,
      PostEntry entry, int index) {
    // The notes folder has neither of the two things this button is for. It
    // cannot be renamed or deleted, so the menu would open empty, and it is
    // pinned to the bottom of the list, so there is nowhere to drag it to.
    // The space it would take is kept, so its row lines up with the others.
    if (entry.isReservedFolder) return const SizedBox(width: 28, height: 28);

    return ReorderableDelayedDragStartListener(
      index: index,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        // A Builder so the menu can be anchored to this button rather
        // than to the sidebar: the State's own context is the whole
        // panel, and a menu positioned off that opens at its corner.
        child: Builder(
          builder: (buttonContext) => Semantics(
            button: true,
            label: "More -- press and hold to move",
            child: GestureDetector(
              // Opaque so the tap stops here rather than reaching the
              // row's own InkWell, which would open the document under
              // the menu.
              behavior: HitTestBehavior.opaque,
              onTap: () => _openRowMenu(buttonContext, library, entry),
              child: SizedBox(
                width: 28,
                height: 28,
                child: Icon(Icons.more_vert,
                    size: 16, color: theme.colors.onSurfaceVariant),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// _reorderHint is where the row tooltips went: one line, under the list,
  /// saying the thing they each said separately.
  ///
  /// Only with something to reorder. On a single document it would be
  /// explaining a gesture that cannot change anything.
  Widget? _reorderHint(ThemeNotifier theme, PostLibraryModel library) {
    if (library.entries.length < 2) return null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Text(
        "Press and hold a row's ⋮ to move it",
        style: TextStyle(fontSize: 10, color: theme.colors.onSurfaceVariant),
      ),
    );
  }

  /// _openRowMenu shows the row's menu under the button that was tapped.
  ///
  /// showMenu by hand rather than a PopupMenuButton, because that widget
  /// wraps itself in a Tooltip whose long press would compete with the drag
  /// this button now also starts.
  Future<void> _openRowMenu(BuildContext buttonContext,
      PostLibraryModel library, PostEntry entry) async {
    var button = buttonContext.findRenderObject() as RenderBox?;
    var overlay =
        Overlay.of(buttonContext).context.findRenderObject() as RenderBox?;
    if (button == null || overlay == null) return;
    var topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
    var bottomRight = button.localToGlobal(button.size.bottomRight(Offset.zero),
        ancestor: overlay);
    var choice = await showMenu<String>(
      context: buttonContext,
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        bottomRight.dy,
        overlay.size.width - bottomRight.dx,
        overlay.size.height - bottomRight.dy,
      ),
      items: [
        // A reserved folder is offered neither: the app files into it by
        // name from elsewhere, so a rename or a delete would strand
        // everything in it and the next write would recreate the folder
        // anyway. Storage refuses both regardless (see PostStorage); this is
        // only so the menu does not offer what will not happen.
        //
        // The front page is offered neither either. It is the page every
        // visitor lands on, named "index" because that is the name they ask
        // for -- renaming it does not rename the front page, it takes the
        // site's entrance away and leaves an ordinary page behind.
        if (!entry.isReservedFolder && !_isFrontPage(entry))
          const PopupMenuItem(value: "rename", child: Text("Rename")),
        // A folder has nowhere to go: the library is one level deep.
        // Neither has anything belonging to the site -- the folder is what
        // makes a document what it is. A page is a page because it is in
        // Pages; a fragment is one because it is in Fragments, and that is
        // where --include[name]-- looks for it. Moving either out is not
        // filing, it is unmaking it.
        //
        // isSiteFolder rather than naming Pages here, because naming one of
        // the two is the mistake that has already been made once: the
        // publish menu asked about the Pages folder alone and left every
        // fragment offering Create Post.
        if (!entry.isFolder && !isSiteFolder(entry.folder))
          const PopupMenuItem(value: "move", child: Text("Move to...")),
        if (!entry.isReservedFolder && !_isFrontPage(entry))
          const PopupMenuItem(value: "delete", child: Text("Delete")),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case "rename":
        var name = await _askName(
            title: "Rename ${entry.isFolder ? "folder" : "document"}",
            initial: entry.name);
        if (name != null) await library.rename(entry, name);
      case "move":
        await _moveDocument(library, entry);
      case "delete":
        if (await _confirmDelete(entry)) await library.delete(entry);
    }
  }

  Widget _actions(ThemeNotifier theme, PostLibraryModel library) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.colors.outlineVariant)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Row(children: [
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              _action(theme, Icons.note_add_outlined, "New document",
                  () => _newDocument(library)),
              if (library.folder.isEmpty)
                _action(theme, Icons.create_new_folder_outlined, "New folder",
                    () => _newFolder(library)),
            ]),
          ),
          // Shown while a write is in flight rather than after it: the point
          // is to answer "did that save", and an indicator that only appears
          // once the answer is yes never gets seen.
          //
          // It lives in this row, which is always drawn, rather than in the
          // header, which at the top level is not -- see _header. The box is
          // reserved either way so that the indicator appearing does not
          // shuffle the chips beside it.
          SizedBox(
            width: 20,
            height: 12,
            child: library.saving
                ? Center(
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: theme.colors.onSurfaceVariant),
                    ),
                  )
                : null,
          ),
        ]),
      );

  Widget _action(ThemeNotifier theme, IconData icon, String label,
          VoidCallback onTap) =>
      ActionChip(
        visualDensity: VisualDensity.compact,
        avatar: Icon(icon, size: 15, color: theme.colors.onSurfaceVariant),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        onPressed: onTap,
      );

  Widget _note(ThemeNotifier theme, String text) => Padding(
        padding: const EdgeInsets.all(14),
        child: Text(text,
            style:
                TextStyle(fontSize: 11, color: theme.colors.onSurfaceVariant)),
      );

  Widget _error(ThemeNotifier theme, String message) => Container(
        width: double.infinity,
        color: theme.colors.errorContainer,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Text(message,
            style:
                TextStyle(fontSize: 11, color: theme.colors.onErrorContainer)),
      );

  // --- the dialogs ---

  /// _newDocument names a document and starts it.
  ///
  /// The dialog says which of the two things it is about to do, because
  /// which one depends on state the user cannot see: with nothing open it
  /// takes what is in the editor, and with a document open it starts blank
  /// because that text is already saved in the document it belongs to.
  Future<void> _newDocument(PostLibraryModel library) async {
    var adopting = library.adoptsEditorText;
    var text = widget.controller?.text ?? "";
    var name = await _askName(
      title: library.folder.isEmpty
          ? "New document"
          : "New document in ${library.folder}",
      initial: adopting ? PostStorage.suggestName(text) : "Untitled",
      note: adopting && text.trim().isNotEmpty
          ? "Starts from what is in the editor."
          : "Starts blank. The editor is saved to the open document first.",
    );
    if (name == null) return;
    if (await PostStorage.exists(library.folder, name) &&
        !await _confirmOverwrite(name)) {
      return;
    }
    await library.newDocument(name);
  }

  /// _moveDocument asks which folder to move a document into.
  Future<void> _moveDocument(PostLibraryModel library, PostEntry entry) async {
    var folders = await PostStorage.folderNames();
    if (!mounted) return;

    var destinations = ["", ...folders]..removeWhere((f) => f == entry.folder);
    if (destinations.isEmpty) {
      // Nowhere to go: one folder exists and the document is already in it.
      return;
    }

    var choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(
            "Move \"${entry.isFolder ? folderLabel(entry.name) : entry.name}\" to"),
        children: [
          for (var folder in destinations)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, folder),
              child: Row(children: [
                Icon(
                    folder.isEmpty
                        ? Icons.inbox_outlined
                        : Icons.folder_outlined,
                    size: 16),
                const SizedBox(width: 8),
                Text(folder.isEmpty ? "My Posts" : folderLabel(folder)),
              ]),
            ),
        ],
      ),
    );
    if (choice != null) await library.move(entry, choice);
  }

  Future<void> _newFolder(PostLibraryModel library) async {
    var name = await _askName(title: "New folder", initial: "");
    if (name != null) await library.createFolder(name);
  }

  Future<bool> _confirmOverwrite(String name) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("Replace \"$name\"?"),
          content:
              const Text("A document with that name is already saved here."),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel")),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Replace")),
          ],
        ),
      ) ??
      false;

  Future<bool> _confirmDelete(PostEntry entry) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
              "Delete \"${entry.isFolder ? folderLabel(entry.name) : entry.name}\"?"),
          content: Text(entry.isFolder
              ? "The folder and everything in it will be deleted."
              : "The file will be deleted."),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel")),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Delete")),
          ],
        ),
      ) ??
      false;

  /// _askName collects a folder or document name, showing what it will
  /// actually be saved as.
  ///
  /// Shown live because the sanitizing is not obvious: a name with a slash
  /// or a colon in it comes back changed, and finding that out only after
  /// the file appears under a different name is worse than being told.
  Future<String?> _askName(
      {required String title, required String initial, String? note}) async {
    var controller = TextEditingController(text: initial);
    var result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: StatefulBuilder(
          builder: (context, setInner) {
            var safe = PostStorage.sanitizeName(controller.text);
            return Column(mainAxisSize: MainAxisSize.min, children: [
              if (note != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(note, style: const TextStyle(fontSize: 11)),
                  ),
                ),
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: maxNameLength,
                decoration: const InputDecoration(labelText: "Name"),
                onChanged: (_) => setInner(() {}),
                onSubmitted: (_) =>
                    safe == null ? null : Navigator.pop(context, safe),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  safe == null
                      ? "Enter a name."
                      : "Saved as $safe${title.startsWith("New folder") ? "" : ".md"}",
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ]);
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          FilledButton(
            onPressed: () {
              var safe = PostStorage.sanitizeName(controller.text);
              if (safe != null) Navigator.pop(context, safe);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}
