import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:bruig/components/text.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_bundle.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:file_picker/file_picker.dart';
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
//
// It is laid out like the post library's sidebar next door, and deliberately:
// they are the same thing -- a list of the reader's own documents, with the
// things you can do to one on the row and the things that make new ones along
// the bottom. Two lists of files in one app that work differently is two
// things to learn for no reason.
//
// There is no Save button. A canvas that has been saved once saves itself --
// see CanvasController.scheduleAutosave -- and New canvas names its file
// immediately, so the ordinary path never needs one. The exception is a canvas
// started from a preset, which has no name and nowhere to go: for that, and
// only that, a Save chip appears beside the others.

class CanvasFilesPanel extends StatefulWidget {
  final CanvasController controller;

  /// onOpen is called with a document read from disk. What to do about unsaved
  /// work in the editor is the screen's decision.
  final Future<void> Function(String folder, String name) onOpen;

  /// onPublish opens the publish sheet for a saved canvas without opening it
  /// in the editor first, which is what "send this one again" wants.
  final void Function(String folder, String name) onPublish;

  /// onNew starts an empty canvas under a name that has already been checked.
  ///
  /// The screen's job rather than the panel's for the same reason opening one
  /// is: what to do about unsaved work in the editor is a question about the
  /// editor, and the panel does not own that.
  final Future<void> Function(String folder, String name) onNew;

  const CanvasFilesPanel({
    required this.controller,
    required this.onOpen,
    required this.onPublish,
    required this.onNew,
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
  Future<String?> _ask(String title, String label,
      {String initial = ""}) async {
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

  /// _saveAs files a canvas that has none.
  ///
  /// Reached only by the Save chip, which appears only for a canvas with no
  /// file behind it -- one started from a preset. Everything else has a name
  /// and saves itself.
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

  /// _import reads a canvas somebody sent and puts it in the library.
  ///
  /// Both forms of the file go through unpackCanvas -- the plain document and
  /// the bundle carrying its pictures -- so there is nothing here that has to
  /// know which arrived. The pictures are stored first: a canvas that appeared
  /// in the list and then failed to find its photographs would look like a
  /// broken canvas rather than like a failed import.
  Future<void> _import() async {
    var snackbar = SnackBarModel.of(context);
    var chosen = await FilePicker.platform.pickFiles(
      dialogTitle: "Open a canvas",
      // Not filtered to the extension: a canvas that has been through a chat,
      // a download folder or a mail client often arrives called something
      // else, and refusing to show it is worse than reading it and saying it
      // is not a canvas.
      withData: true,
    );
    var file = chosen?.files.firstOrNull;
    var bytes = file?.bytes;
    if (bytes == null) return;

    var bundle = await unpackCanvas(bytes);
    if (!mounted) return;
    if (bundle == null) {
      snackbar.error("That file is not a canvas.");
      return;
    }

    var stored = await storeBundlePictures(bundle);
    var wanted = CanvasStorage.sanitizeName(bundle.document.title) ??
        CanvasStorage.sanitizeName(file!.name.split(".").first) ??
        "Canvas";
    var name = await CanvasStorage.uniqueName(_folder, wanted);
    var ok = await CanvasStorage.save(
        _folder, name, bundle.document.copyWith(title: name));
    if (!mounted) return;

    if (!ok) {
      snackbar.error("Unable to save the canvas here.");
      return;
    }
    snackbar.success(stored == 0
        ? "Opened $name."
        : "Opened $name with $stored "
            "picture${stored == 1 ? "" : "s"}.");
    await _reload();
    await widget.onOpen(_folder, name);
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
    var name =
        await CanvasStorage.uniqueName(entry.folder, "${entry.name} copy");
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
    // The pictures that canvas was the last user of go with it.
    unawaited(CanvasAssets.sweepUnused());
    await _reload();
  }

  Future<void> _deleteFolder(CanvasEntry entry) async {
    var snackbar = SnackBarModel.of(context);
    var contents = await CanvasStorage.list(entry.name);
    if (!mounted) return;
    if (contents.isNotEmpty) {
      snackbar.error("${entry.name} still holds ${contents.length} canvas"
          "${contents.length == 1 ? "" : "es"}. Empty it first.");
      return;
    }
    if (!await _confirm("Delete the folder ${entry.name}?",
        "The folder is empty and will be removed.")) {
      return;
    }
    await CanvasStorage.deleteFolder(entry.name);
    unawaited(CanvasAssets.sweepUnused());
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
            ? const Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)))
            : _entries.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Txt.S(
                        "No saved canvases here yet. Save the one you are "
                        "working on, or start from a preset."),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _entries.length,
                    onReorderItem: _reorder,
                    // The drag is started by the row's own button, not by the
                    // row: a row is the thing you tap to open a canvas, and a
                    // hold that started anywhere on one would take the place
                    // of that tap for anybody who pauses before releasing.
                    buildDefaultDragHandles: false,
                    itemBuilder: (context, i) => _row(theme, _entries[i], i),
                  ),
      ),
      if (_reorderHint(theme) case var hint?) hint,
      _actions(theme),
    ]);
  }

  /// _actions is the bar along the bottom: the things that make something new.
  ///
  /// At the bottom rather than the top because that is where the post library
  /// keeps them, and because the list is the thing being read -- controls
  /// above it push what somebody came here for down the panel.
  Widget _actions(ThemeNotifier theme) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.colors.outlineVariant)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          _action(theme, Icons.add_box_outlined, "New canvas", _newCanvas),
          if (_folder.isEmpty)
            _action(theme, Icons.create_new_folder_outlined, "New folder",
                _newFolder),
          _action(theme, Icons.file_open_outlined, "Open a file", _import),
          // Only for a canvas that has nowhere to save itself to: one started
          // from a preset, or from nothing. Everything else is already saving
          // itself, and a button that says Save next to a canvas that has just
          // saved is a button that invites a press for no reason.
          if (controller.name == null && controller.dirty)
            _action(theme, Icons.save_outlined, "Save this canvas", _saveAs),
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

  /// _reorderHint says once, under the list, what a row cannot say for itself.
  ///
  /// Not a tooltip on the button it describes, and that is not a preference:
  /// a Tooltip inside a reorderable row is an overlay that gets re-attached
  /// mid-layout when the row moves, and the sidebar is replaced by a red error
  /// box. See _rowButton, and the post library's own note on the same crash.
  Widget? _reorderHint(ThemeNotifier theme) {
    if (_documents().length < 2) return null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Text(
        "Press and hold a row's ⋮ to move it",
        style: TextStyle(fontSize: 10, color: theme.colors.onSurfaceVariant),
      ),
    );
  }

  /// _documents is the entries that can be reordered.
  ///
  /// Folders are not among them. A folder's place in the listing is decided by
  /// the listing -- they come first, always -- so dragging one would be a
  /// gesture that appeared to work and then undid itself on the next read.
  List<CanvasEntry> _documents() => [
        for (var e in _entries)
          if (!e.isFolder) e
      ];

  /// _reorder writes the new order down. See CanvasStorage.saveOrder, which
  /// is what the listing reads back.
  Future<void> _reorder(int from, int to) async {
    var folders = _entries.length - _documents().length;
    // The indices arrive against the whole list, folders included, and a drop
    // above the folders is clamped to just below them rather than refused --
    // a drag that snaps back tells the reader nothing about why.
    from = math.max(0, from - folders);
    to = math.max(0, to - folders);

    var documents = _documents();
    if (from >= documents.length) return;
    var moved = documents.removeAt(from);
    documents.insert(math.min(to, documents.length), moved);

    setState(() => _entries = [
          ..._entries.where((e) => e.isFolder),
          ...documents,
        ]);
    await CanvasStorage.saveOrder(_folder, [for (var d in documents) d.name]);
  }

  /// _newCanvas starts an empty one and gives it a name straight away.
  ///
  /// Named immediately, which is the whole reason there is no Save button: a
  /// canvas with a file behind it saves itself from then on. Asking for the
  /// name first is also the moment to find out the name is taken, which is
  /// better than finding out after the work.
  Future<void> _newCanvas() async {
    var snackbar = SnackBarModel.of(context);
    var wanted = await _ask("New canvas", "Name");
    if (wanted == null) return;

    var clean = CanvasStorage.sanitizeName(wanted);
    if (clean == null) {
      snackbar.error("That name cannot be used for a file.");
      return;
    }
    if (await CanvasStorage.exists(_folder, clean)) {
      snackbar.error("There is already a canvas called $clean here.");
      return;
    }
    await widget.onNew(_folder, clean);
    await _reload();
  }

  Widget _row(ThemeNotifier theme, CanvasEntry entry, int index) {
    var open = !entry.isFolder &&
        controller.name == entry.name &&
        controller.folder == entry.folder;

    return InkWell(
      // A reorderable list needs a key on every child, and the row's own
      // identity is where it lives.
      key: ValueKey("${entry.folder}/${entry.name}"),
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
          _rowButton(theme, entry, index),
        ]),
      ),
    );
  }

  /// _rowButton is the one control at the end of a row: tap it for the menu,
  /// hold it to drag the row.
  ///
  /// There is deliberately no Tooltip on this button, and there must not be
  /// one. A Tooltip is an OverlayPortal: while it is showing it has a child
  /// parked in the Overlay's render tree. Reordering moves a row's element
  /// rather than rebuilding it, and reactivating an OverlayPortal that way
  /// re-attaches its overlay child mid-layout, which the framework refuses --
  /// the whole sidebar is replaced by a red error box. The tooltip and the
  /// gesture are the same hover, so they cannot both live here. What it would
  /// have said is said once under the list, by _reorderHint.
  ///
  /// A folder gets the menu but not the drag: folders are listed before
  /// documents whatever anybody does, so dragging one would appear to work
  /// and undo itself on the next read.
  Widget _rowButton(ThemeNotifier theme, CanvasEntry entry, int index) {
    var button = Builder(
      // A Builder so the menu is anchored to this button rather than to the
      // panel: the State's own context is the whole sidebar, and a menu
      // positioned off that opens at its corner.
      builder: (buttonContext) => Semantics(
        button: true,
        label: entry.isFolder ? "More" : "More — press and hold to move",
        child: GestureDetector(
          // Opaque, so the tap stops here rather than reaching the row's own
          // InkWell and opening the canvas under the menu.
          behavior: HitTestBehavior.opaque,
          onTap: () => _openRowMenu(buttonContext, entry),
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(Icons.more_vert,
                size: 16, color: theme.colors.onSurfaceVariant),
          ),
        ),
      ),
    );

    if (entry.isFolder) return button;
    return ReorderableDelayedDragStartListener(
      index: index,
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: button),
    );
  }

  /// _openRowMenu shows the row's menu under the button that was tapped.
  ///
  /// showMenu by hand rather than a PopupMenuButton, which wraps itself in a
  /// Tooltip -- see _rowButton on why nothing in one of these rows may own an
  /// overlay.
  Future<void> _openRowMenu(
      BuildContext buttonContext, CanvasEntry entry) async {
    var box = buttonContext.findRenderObject() as RenderBox?;
    var overlay =
        Overlay.of(buttonContext).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    var topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    var bottomRight =
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay);

    var choice = await showMenu<String>(
      context: buttonContext,
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        bottomRight.dy,
        overlay.size.width - bottomRight.dx,
        overlay.size.height - bottomRight.dy,
      ),
      items: entry.isFolder
          ? const [PopupMenuItem(value: "deleteFolder", child: Text("Delete"))]
          : const [
              PopupMenuItem(value: "publish", child: Text("Publish…")),
              PopupMenuItem(value: "duplicate", child: Text("Duplicate")),
              PopupMenuItem(value: "rename", child: Text("Rename…")),
              PopupMenuItem(value: "delete", child: Text("Delete")),
            ],
    );
    if (!mounted) return;
    switch (choice) {
      case "publish":
        widget.onPublish(entry.folder, entry.name);
      case "duplicate":
        await _duplicate(entry);
      case "rename":
        await _rename(entry);
      case "delete":
        await _delete(entry);
      case "deleteFolder":
        await _deleteFolder(entry);
    }
  }
}
