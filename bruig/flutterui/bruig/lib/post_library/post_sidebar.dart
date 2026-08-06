import 'package:bruig/post_library/post_library_model.dart';
import 'package:bruig/post_library/post_storage.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

// post_sidebar.dart is the saved-post library in the composer's sidebar
// slot: folders and documents, one level deep, listed the way the directory
// on disk lists them.

/// PostSidebar browses `<appDataDir>/my-posts` and loads what is in it into
/// the composer beside it.
class PostSidebar extends StatefulWidget {
  /// The composer whose text is being saved, or null for the frame or two
  /// while one is being rebuilt -- see ComposerSidebarController.visible.
  final TextEditingController? controller;

  /// onClose returns the slot to whatever the screen normally shows there.
  final VoidCallback onClose;

  const PostSidebar({
    required this.controller,
    required this.onClose,
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

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header(theme, library),
      const Divider(height: 1),
      Expanded(child: _list(theme, library)),
      if (library.error case var message?) _error(theme, message),
      _actions(theme, library),
    ]);
  }

  Widget _header(ThemeNotifier theme, PostLibraryModel library) {
    var inFolder = library.folder.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
      child: Row(children: [
        if (inFolder)
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 18),
            tooltip: "Back to My Posts",
            onPressed: () => library.openFolderNamed(""),
          )
        else
          const SizedBox(width: 8),
        Expanded(
          child: Text(
            inFolder ? library.folder : "My Posts",
            style: const TextStyle(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Shown while a write is in flight rather than after it: the point
        // is to answer "did that save", and an indicator that only appears
        // once the answer is yes never gets seen.
        if (library.saving)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: theme.colors.onSurfaceVariant),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          tooltip: "Close",
          onPressed: widget.onClose,
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
              ? "Nothing saved yet. Save this post, or make a folder to file "
                  "it in."
              : "This folder is empty.");
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        for (var entry in library.entries) _row(theme, library, entry),
      ],
    );
  }

  Widget _row(ThemeNotifier theme, PostLibraryModel library, PostEntry entry) {
    var isOpen = !entry.isFolder &&
        entry.name == library.openName &&
        entry.folder == library.openFolder;

    return InkWell(
      onTap: () => entry.isFolder
          ? library.openFolderNamed(entry.name)
          : library.open(entry),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 7, 4, 7),
        child: Row(children: [
          Icon(
            entry.isFolder ? Icons.folder_outlined : Icons.description_outlined,
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
                  entry.name,
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
          _rowMenu(library, entry),
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

  Widget _rowMenu(PostLibraryModel library, PostEntry entry) =>
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 16),
        tooltip: "More",
        padding: EdgeInsets.zero,
        onSelected: (choice) async {
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
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: "rename", child: Text("Rename")),
          // A folder has nowhere to go: the library is one level deep.
          if (!entry.isFolder)
            const PopupMenuItem(value: "move", child: Text("Move to...")),
          const PopupMenuItem(value: "delete", child: Text("Delete")),
        ],
      );

  Widget _actions(ThemeNotifier theme, PostLibraryModel library) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.colors.outlineVariant)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          _action(theme, Icons.note_add_outlined, "New document",
              () => _newDocument(library)),
          if (library.folder.isEmpty)
            _action(theme, Icons.create_new_folder_outlined, "New folder",
                () => _newFolder(library)),
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
        title: Text("Move \"${entry.name}\" to"),
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
                Text(folder.isEmpty ? "My Posts" : folder),
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
          title: Text("Delete \"${entry.name}\"?"),
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
