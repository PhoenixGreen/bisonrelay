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
          : _openDocument(library, entry),
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
            case "delete":
              if (await _confirmDelete(entry)) await library.delete(entry);
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: "rename", child: Text("Rename")),
          PopupMenuItem(value: "delete", child: Text("Delete")),
        ],
      );

  Widget _actions(ThemeNotifier theme, PostLibraryModel library) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.colors.outlineVariant)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          _action(theme, Icons.note_add_outlined, "Save this post",
              () => _saveCurrent(library)),
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

  Future<void> _saveCurrent(PostLibraryModel library) async {
    var name = await _askName(
      title: library.folder.isEmpty
          ? "Save post"
          : "Save post in ${library.folder}",
      initial: PostStorage.suggestName(widget.controller?.text ?? ""),
    );
    if (name == null) return;
    if (await PostStorage.exists(library.folder, name) &&
        !await _confirmOverwrite(name)) {
      return;
    }
    await library.saveCurrentAs(name);
  }

  Future<void> _newFolder(PostLibraryModel library) async {
    var name = await _askName(title: "New folder", initial: "");
    if (name != null) await library.createFolder(name);
  }

  /// _openDocument asks what to do with the text already in the editor, and
  /// only asks when there is some -- a prompt whose answer is always the
  /// same is a prompt that teaches people to dismiss prompts.
  Future<void> _openDocument(PostLibraryModel library, PostEntry entry) async {
    var current = widget.controller?.text ?? "";
    if (current.trim().isEmpty) {
      await library.open(entry);
      return;
    }
    if (!mounted) return;

    var replace = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Open \"${entry.name}\""),
        content: const Text(
            "There is already something in the editor. Replacing it will "
            "discard what is there."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Insert at cursor")),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Replace")),
        ],
      ),
    );
    if (replace == null) return;
    await library.open(entry, replace: replace);
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
      {required String title, required String initial}) async {
    var controller = TextEditingController(text: initial);
    var result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: StatefulBuilder(
          builder: (context, setInner) {
            var safe = PostStorage.sanitizeName(controller.text);
            return Column(mainAxisSize: MainAxisSize.min, children: [
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
