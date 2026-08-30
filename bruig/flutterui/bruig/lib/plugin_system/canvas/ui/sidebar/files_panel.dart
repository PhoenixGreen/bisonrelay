import 'package:bruig/components/text.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// files_panel.dart is the Files tab: the saved canvases, in their folders.
//
// It is a listing of a directory and nothing more -- no index, no database.
// What is on disk is what is shown, which is the same arrangement the post
// library uses and has the same payoff: a canvas copied in from elsewhere
// simply appears, and one deleted outside the app simply goes.
//
// One level of folders, so there is no breadcrumb and no move operation. The
// panel is either at the top, showing folders and loose documents, or inside
// one folder with a way back.

class CanvasFilesPanel extends StatefulWidget {
  final CanvasController controller;

  /// onOpen is called with a document read from disk. What to do about unsaved
  /// work in the editor is the screen's decision.
  final Future<void> Function(String folder, String name) onOpen;

  /// onPublish opens the publish sheet for a saved canvas without opening it
  /// in the editor first, which is what "send this one again" wants.
  final void Function(String folder, String name) onPublish;

  const CanvasFilesPanel({
    required this.controller,
    required this.onOpen,
    required this.onPublish,
    super.key,
  });

  @override
  State<CanvasFilesPanel> createState() => _CanvasFilesPanelState();
}

class _CanvasFilesPanelState extends State<CanvasFilesPanel> {
  CanvasController get controller => widget.controller;

  String _folder = "";
  List<CanvasEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onControllerChanged);
    _reload();
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// _onControllerChanged redraws the "open" and "unsaved" marks, which follow
  /// the editor rather than the disk.
  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    var entries = await CanvasStorage.list(_folder);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  /// _ask puts up a one-field dialog. Used for every name this panel needs,
  /// which is four of them, so it is worth having once.
  Future<String?> _ask(String title, String label, {String initial = ""}) async {
    var text = TextEditingController(text: initial);
    var result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: text,
          autofocus: true,
          maxLength: maxNameLength,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.of(context).pop(text.text),
              child: const Text("OK")),
        ],
      ),
    );
    text.dispose();
    return result;
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text("Cancel")),
            TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text("Delete")),
          ],
        ),
      ) ??
      false;

  Future<void> _saveAs() async {
    var snackbar = SnackBarModel.of(context);
    var wanted = await _ask("Save canvas as", "Name",
        initial: controller.name ?? controller.document.title);
    if (wanted == null) return;

    var clean = CanvasStorage.sanitizeName(wanted);
    if (clean == null) {
      snackbar.error("That name cannot be used for a file.");
      return;
    }
    if (await CanvasStorage.exists(_folder, clean)) {
      // Refused rather than overwritten. There is no undo for a saved canvas
      // replaced by another one, and "Save as" landing on an existing name is
      // far more often a slip than an intention.
      snackbar.error("There is already a canvas called $clean here.");
      return;
    }

    var ok = await controller.saveAs(_folder, clean);
    if (!mounted) return;
    ok
        ? snackbar.success("Saved $clean.")
        : snackbar.error("Unable to save $clean.");
    await _reload();
  }

  Future<void> _save() async {
    var snackbar = SnackBarModel.of(context);
    if (controller.name == null) {
      await _saveAs();
      return;
    }
    var ok = await controller.save();
    if (!mounted) return;
    ok
        ? snackbar.success("Saved ${controller.name}.")
        : snackbar.error("Unable to save ${controller.name}.");
    await _reload();
  }

  Future<void> _newFolder() async {
    var snackbar = SnackBarModel.of(context);
    var name = await _ask("New folder", "Folder name");
    if (name == null) return;
    var ok = await CanvasStorage.createFolder(name);
    if (!mounted) return;
    if (!ok) snackbar.error("That folder name cannot be used.");
    await _reload();
  }

  Future<void> _duplicate(CanvasEntry entry) async {
    var snackbar = SnackBarModel.of(context);
    var document = await CanvasStorage.load(entry.folder, entry.name);
    if (document == null) {
      if (mounted) snackbar.error("Unable to read ${entry.name}.");
      return;
    }
    var name = await CanvasStorage.uniqueName(entry.folder, "${entry.name} copy");
    await CanvasStorage.save(
        entry.folder, name, document.copyWith(title: name));
    await _reload();
  }

  Future<void> _rename(CanvasEntry entry) async {
    var snackbar = SnackBarModel.of(context);
    var wanted = await _ask("Rename", "Name", initial: entry.name);
    if (wanted == null) return;
    var clean = CanvasStorage.sanitizeName(wanted);
    if (clean == null || clean == entry.name) return;

    var ok = await CanvasStorage.rename(entry.folder, entry.name, clean);
    if (!mounted) return;
    if (!ok) {
      snackbar.error("Unable to rename — is there already a $clean here?");
      return;
    }
    // The editor is holding this document open under its old name, so it has
    // to be told, or the next Save writes a second file under the old one.
    if (controller.name == entry.name && controller.folder == entry.folder) {
      controller.name = clean;
    }
    await _reload();
  }

  Future<void> _delete(CanvasEntry entry) async {
    if (!await _confirm("Delete ${entry.name}?",
        "This cannot be undone. The canvas file will be removed from disk.")) {
      return;
    }
    await CanvasStorage.delete(entry.folder, entry.name);
    await _reload();
  }

  Future<void> _deleteFolder(CanvasEntry entry) async {
    var snackbar = SnackBarModel.of(context);
    var contents = await CanvasStorage.list(entry.name);
    if (!mounted) return;
    if (contents.isNotEmpty) {
      snackbar.error(
          "${entry.name} still holds ${contents.length} canvas"
          "${contents.length == 1 ? "" : "es"}. Empty it first.");
      return;
    }
    if (!await _confirm("Delete the folder ${entry.name}?",
        "The folder is empty and will be removed.")) {
      return;
    }
    await CanvasStorage.deleteFolder(entry.name);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _toolbar(theme),
      const Divider(height: 1),
      if (_folder.isNotEmpty)
        InkWell(
          onTap: () {
            setState(() {
              _folder = "";
              _loading = true;
            });
            _reload();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              const Icon(Icons.arrow_back, size: 15),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(_folder,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600))),
            ]),
          ),
        ),
      Expanded(
        child: _loading
            ? const Center(child: SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)))
            : _entries.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Txt.S(
                        "No saved canvases here yet. Save the one you are "
                        "working on, or start from a preset."),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _entries.length,
                    itemBuilder: (context, i) => _row(theme, _entries[i]),
                  ),
      ),
    ]);
  }

  Widget _toolbar(ThemeNotifier theme) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(
                controller.name ?? "Unsaved canvas",
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            if (controller.dirty)
              Tooltip(
                message: "There are changes that have not been saved",
                child: Icon(Icons.circle,
                    size: 8, color: theme.colors.tertiary),
              ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined, size: 15),
                label: const Text("Save", style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: "Save as a new canvas",
              child: IconButton(
                onPressed: _saveAs,
                icon: const Icon(Icons.save_as_outlined, size: 17),
                visualDensity: VisualDensity.compact,
              ),
            ),
            Tooltip(
              message: "New folder",
              child: IconButton(
                onPressed: _newFolder,
                icon: const Icon(Icons.create_new_folder_outlined, size: 17),
                visualDensity: VisualDensity.compact,
              ),
            ),
            Tooltip(
              message: "Refresh the list",
              child: IconButton(
                onPressed: _reload,
                icon: const Icon(Icons.refresh, size: 17),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ]),
        ]),
      );

  Widget _row(ThemeNotifier theme, CanvasEntry entry) {
    var open = !entry.isFolder &&
        controller.name == entry.name &&
        controller.folder == entry.folder;

    return InkWell(
      onTap: () async {
        if (entry.isFolder) {
          setState(() {
            _folder = entry.name;
            _loading = true;
          });
          await _reload();
        } else {
          await widget.onOpen(entry.folder, entry.name);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        color: open ? theme.colors.secondaryContainer : null,
        child: Row(children: [
          Icon(
            entry.isFolder ? Icons.folder_outlined : Icons.dashboard_outlined,
            size: 16,
            color: theme.colors.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)),
                if (!entry.isFolder && entry.modified != null)
                  Text(
                    DateFormat("d MMM y, HH:mm").format(entry.modified!),
                    style: TextStyle(
                        fontSize: 10, color: theme.colors.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: "More",
            icon: Icon(Icons.more_horiz,
                size: 16, color: theme.colors.onSurfaceVariant),
            padding: EdgeInsets.zero,
            itemBuilder: (context) => entry.isFolder
                ? const [
                    PopupMenuItem(value: "deleteFolder", child: Text("Delete")),
                  ]
                : const [
                    PopupMenuItem(value: "publish", child: Text("Publish…")),
                    PopupMenuItem(value: "duplicate", child: Text("Duplicate")),
                    PopupMenuItem(value: "rename", child: Text("Rename…")),
                    PopupMenuItem(value: "delete", child: Text("Delete")),
                  ],
            onSelected: (choice) {
              switch (choice) {
                case "publish":
                  widget.onPublish(entry.folder, entry.name);
                case "duplicate":
                  _duplicate(entry);
                case "rename":
                  _rename(entry);
                case "delete":
                  _delete(entry);
                case "deleteFolder":
                  _deleteFolder(entry);
              }
            },
          ),
        ]),
      ),
    );
  }
}
