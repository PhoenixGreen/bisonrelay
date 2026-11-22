import 'dart:io';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_dialogs.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:bruig/components/text.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_bundle.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

// files_panel.dart is the Files tab: the saved canvases, in their folders,
// one level deep. A plain listing of a directory, no index, as the post
// library is, and laid out like it: a canvas copied in appears, one deleted
// outside the app goes. No permanent Save button: a saved canvas saves
// itself (CanvasController.scheduleAutosave) and New canvas names its file
// at once; only a canvas with no file (one from a preset) gets a Save chip.

class CanvasFilesPanel extends StatefulWidget {
  final CanvasController controller;

  /// onOpen is called with a document read from disk; what to do about
  /// unsaved work in the editor is the screen's decision.
  final Future<void> Function(String folder, String name) onOpen;

  /// onPublish opens the publish sheet for a saved canvas without opening it.
  final void Function(String folder, String name) onPublish;

  /// onNew starts an empty canvas under a name already checked, left to the
  /// screen, which owns the question of unsaved work.
  final Future<void> Function(String folder, String name) onNew;

  /// showing is whether this tab is on display. Kept alive while hidden
  /// (Offstage in canvas_screen.dart), it rereads the directory on return.
  final bool showing;

  const CanvasFilesPanel({
    required this.controller,
    required this.onOpen,
    required this.onPublish,
    required this.onNew,
    this.showing = true,
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
    // Back in the folder last worked in.
    _folder =
        Provider.of<CanvasPreferences>(context, listen: false).filesFolder;
    _reload();
  }

  @override
  void didUpdateWidget(CanvasFilesPanel old) {
    super.didUpdateWidget(old);
    if (widget.showing && !old.showing) _reload();
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// _onControllerChanged redraws the "open" and "unsaved" marks, which
  /// follow the editor rather than the disk, only when they change: the
  /// editor notifies at every frame of play and every step of a drag, and
  /// this panel is built even while another tab shows.
  void _onControllerChanged() {
    // Not whether it is saved: that flips with every autosave while knobs
    // turn or things are dragged, and rebuilt the whole list each time.
    // The Save button watches it on its own (see _actions).
    var now = (controller.folder, controller.name);
    if (now == _marks) return;
    _marks = now;
    if (mounted) setState(() {});
  }

  (String?, String?)? _marks;

  Future<void> _reload() async {
    var entries = await CanvasStorage.list(_folder);
    // The folder may have been renamed or deleted since (from another window,
    // say). An empty listing alone does not prove it, so ask the top level.
    if (_folder.isNotEmpty && entries.isEmpty) {
      var top = await CanvasStorage.list("");
      if (!top.any((e) => e.isFolder && e.name == _folder)) {
        _folder = "";
        entries = top;
        if (mounted) _rememberFolder();
      }
    }
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  /// _rememberFolder keeps where the reader is, for the next time.
  void _rememberFolder() =>
      Provider.of<CanvasPreferences>(context, listen: false).filesFolder =
          _folder;

  /// _ask puts up a one-field dialog, for every name this panel asks for.
  Future<String?> _ask(String title, String label, {String initial = ""}) =>
      askForName(context,
          title: title,
          label: label,
          initial: initial,
          maxLength: maxNameLength);

  Future<bool> _confirm(String title, String message) =>
      askToConfirm(context, title: title, message: message, confirm: "Delete");

  /// _freeName is [wanted] as a file name, or null with the reason said: a
  /// taken name is refused, as a replaced canvas cannot be undone.
  Future<String?> _freeName(String wanted, SnackBarModel snackbar) async {
    var clean = CanvasStorage.sanitizeName(wanted);
    if (clean == null) {
      snackbar.error("That name cannot be used for a file.");
      return null;
    }
    if (await CanvasStorage.exists(_folder, clean)) {
      snackbar.error("There is already a canvas called $clean here.");
      return null;
    }
    return clean;
  }

  /// _saveNow writes this canvas out now, rather than at the autosave (three
  /// seconds of quiet, and on leaving: CanvasScreen._confirmDiscard).
  Future<void> _saveNow() async {
    var snackbar = SnackBarModel.of(context);
    var name = controller.name;
    if (name == null) return _saveAs();
    var ok = await controller.save();
    if (!mounted) return;
    ok ? snackbar.success("Saved $name.") : snackbar.error("Unable to save.");
  }

  /// _saveAs files a canvas with no file behind it, from the Save chip.
  Future<void> _saveAs() async {
    var snackbar = SnackBarModel.of(context);
    var wanted = await _ask("Save canvas as", "Name",
        initial: controller.name ?? controller.document.title);
    if (wanted == null) return;

    var clean = await _freeName(wanted, snackbar);
    if (clean == null) return;

    var ok = await controller.saveAs(_folder, clean);
    if (!mounted) return;
    ok
        ? snackbar.success("Saved $clean.")
        : snackbar.error("Unable to save $clean.");
    await _reload();
  }

  /// _import reads a canvas somebody sent into the library. Both forms
  /// (plain document and bundle) go through unpackCanvas. The pictures are
  /// stored first, so a canvas never appears without its photographs.
  Future<void> _import() async {
    var snackbar = SnackBarModel.of(context);
    var chosen = await FilePicker.platform.pickFiles(
      dialogTitle: "Open a canvas",
      // Not filtered to the extension: a canvas that has been through a
      // chat or a mail client often arrives renamed.
    );
    var file = chosen?.files.firstOrNull;
    var at = file?.path;
    if (at == null) return;

    // Read and taken apart off the UI isolate, size checked first, as a
    // canvas from a chat is: a big or crafted file must not freeze the app.
    var bundle = await unpackCanvasFile(File(at));
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
    // Directly under the one it is a copy of.
    await CanvasStorage.keepPlace(entry.folder,
        was: CanvasStorage.orderKeyFor(entry), now: name, after: true);
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
    // The editor holds this document open under its old name; tell it, or
    // the next save writes a second file under the old one.
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
    var gone = await CanvasStorage.delete(entry.folder, entry.name);
    // The editor may hold this canvas open: it keeps the work, but as a
    // canvas never saved, or the next save writes the file back.
    if (gone &&
        controller.name == entry.name &&
        controller.folder == entry.folder) {
      controller.detachFromFile();
    }
    // What only that canvas used goes with it; assets stay in the library.
    unawaited(CanvasLibrary.tidy(open: controller.document.storedIds));
    await _reload();
  }

  /// _move asks which folder a canvas should go to, and puts it there: a
  /// dialog rather than a drag onto a folder row, since there are only a
  /// handful of destinations and a row is easy to miss.
  Future<void> _move(CanvasEntry entry) async {
    var snackbar = SnackBarModel.of(context);
    var folders = await CanvasStorage.folderNames();
    if (!mounted) return;

    var destinations = ["", ...folders]..remove(entry.folder);
    if (destinations.isEmpty) {
      snackbar.error("There is nowhere else to put it yet — make a folder "
          "first.");
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
                // The library itself, outside every folder: "Top level",
                // not the section's name, which reads as another folder.
                Icon(
                    folder.isEmpty
                        ? Icons.home_outlined
                        : Icons.folder_outlined,
                    size: 16),
                const SizedBox(width: 8),
                Text(folder.isEmpty ? "Top level" : folder),
              ]),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    var ok = await CanvasStorage.move(entry.folder, entry.name, choice);
    if (!mounted) return;
    if (!ok) {
      snackbar.error("Unable to move ${entry.name} — is there already one "
          "called that there?");
      return;
    }
    // The editor may hold this canvas open: move its idea of where the
    // canvas lives too, or the next write goes back to the old folder.
    if (controller.name == entry.name && controller.folder == entry.folder) {
      controller.folder = choice;
    }
    await _reload();
  }

  /// _renameFolder renames a folder and everything in it.
  Future<void> _renameFolder(CanvasEntry entry) async {
    var snackbar = SnackBarModel.of(context);
    var wanted = await _ask("Rename folder", "Name", initial: entry.name);
    if (wanted == null || wanted == entry.name) return;

    var ok = await CanvasStorage.renameFolder(entry.name, wanted);
    if (!mounted) return;
    if (!ok) {
      snackbar.error("Unable to rename — is there already a $wanted?");
      return;
    }
    // As in _move: the editor's open canvas may be in this folder.
    if (controller.folder == entry.name) {
      controller.folder = CanvasStorage.sanitizeName(wanted) ?? entry.name;
    }
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
    unawaited(CanvasLibrary.tidy(open: controller.document.storedIds));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_folder.isNotEmpty)
        Material(
          // Its own Material inside the list: the sidebar's would let the
          // highlight spill over other sections and stay put on scroll.
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () {
              setState(() {
                _folder = "";
                _loading = true;
              });
              _rememberFolder();
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
                    // The drag starts from the row's own button: a hold
                    // anywhere would take the tap that opens the canvas.
                    buildDefaultDragHandles: false,
                    itemBuilder: (context, i) => _row(theme, _entries[i], i),
                  ),
      ),
      if (_reorderHint(theme) case var hint?) hint,
      _actions(theme),
    ]);
  }

  /// _actions is the bar along the bottom: the things that make something
  /// new, below the list as in the post library.
  Widget _actions(ThemeNotifier theme) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.colors.outlineVariant)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          // A canvas with no file behind it gets Save as its worded button.
          if (controller.name == null)
            _action(theme, Icons.save_outlined, "Save canvas", _saveAs)
          else
            _action(theme, Icons.add_box_outlined, "New canvas", _newCanvas),
          // Icons only, for the least used. Save stays though a saved canvas
          // writes itself out: the autosave is invisible, and a button that
          // says the work is on disk is still worth having.
          if (controller.name != null)
            CanvasWatch<bool>(
                listenable: controller,
                select: () => controller.dirty,
                builder: (context, dirty) => _iconAction(
                    theme,
                    Icons.save_outlined,
                    dirty ? "Save now" : "Saved",
                    _saveNow)),
          if (_folder.isEmpty)
            _iconAction(theme, Icons.create_new_folder_outlined, "New folder",
                _newFolder),
          _iconAction(theme, Icons.file_open_outlined,
              "Open a canvas from a file", _import),
        ]),
      );

  /// _iconAction is a chip with no words, for an action its icon says. A
  /// Tooltip is safe here, outside the reorderable rows (see _rowButton).
  Widget _iconAction(ThemeNotifier theme, IconData icon, String tooltip,
          VoidCallback onTap) =>
      Tooltip(
        message: tooltip,
        child: ActionChip(
          visualDensity: VisualDensity.compact,
          labelPadding: EdgeInsets.zero,
          label: Icon(icon, size: 16, color: theme.colors.onSurfaceVariant),
          onPressed: onTap,
        ),
      );

  Widget _action(ThemeNotifier theme, IconData icon, String label,
          VoidCallback onTap) =>
      ActionChip(
        visualDensity: VisualDensity.compact,
        avatar: Icon(icon, size: 15, color: theme.colors.onSurfaceVariant),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        onPressed: onTap,
      );

  /// _reorderHint says once, under the list, that rows can be held and
  /// moved: a tooltip inside a reorderable row is not possible.
  Widget? _reorderHint(ThemeNotifier theme) {
    if (_entries.length < 2) return null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Text(
        "Press and hold a row's ⋮ to move it",
        style: TextStyle(fontSize: 10, color: theme.colors.onSurfaceVariant),
      ),
    );
  }

  /// _reorder writes the new order down (CanvasStorage.saveOrder, which the
  /// listing reads back). The order file marks folders, so a folder and a
  /// canvas of the same name cannot swap places.
  Future<void> _reorder(int from, int to) async {
    if (from < 0 || from >= _entries.length) return;
    var entries = [..._entries];
    var moved = entries.removeAt(from);
    entries.insert(math.min(to, entries.length), moved);

    setState(() => _entries = entries);
    await CanvasStorage.saveOrder(_folder, entries);
  }

  /// _newCanvas starts the empty preset (the Presets panel's "Empty canvas") and
  /// names it at once: a canvas with a file saves itself from then on, and a
  /// taken name is found before the work rather than after.
  Future<void> _newCanvas() async {
    var snackbar = SnackBarModel.of(context);
    var wanted = await _ask("New canvas", "Name");
    if (wanted == null) return;

    var clean = await _freeName(wanted, snackbar);
    if (clean == null) return;
    await widget.onNew(_folder, clean);
    await _reload();
  }

  Widget _row(ThemeNotifier theme, CanvasEntry entry, int index) {
    var open = !entry.isFolder &&
        controller.name == entry.name &&
        controller.folder == entry.folder;

    return Material(
      key: ValueKey("${entry.folder}/${entry.name}"),
      // Its own Material: see build.
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () async {
          if (entry.isFolder) {
            setState(() {
              _folder = entry.name;
              _loading = true;
            });
            _rememberFolder();
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
      ),
    );
  }

  /// _rowButton is the one control at a row's end: tap for the menu, hold
  /// to drag the row. It must have no Tooltip: a Tooltip is an
  /// OverlayPortal, and reordering moves a row's element, re-attaching the
  /// overlay child mid-layout, which the framework refuses.
  Widget _rowButton(ThemeNotifier theme, CanvasEntry entry, int index) {
    var button = Builder(
      // A Builder, so the menu anchors here, not to the whole sidebar.
      builder: (buttonContext) => Semantics(
        button: true,
        label: "More — press and hold to move",
        child: GestureDetector(
          // Opaque, so the tap stops here rather than reaching the row's
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

    return ReorderableDelayedDragStartListener(
      index: index,
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: button),
    );
  }

  /// _saveAsPreset keeps a saved canvas in the Presets panel, read from
  /// the file, so it is the saved version even while another is open.
  Future<void> _saveAsPreset(CanvasEntry entry) async {
    var snackbar = SnackBarModel.of(context);
    var name = await askForPresetName(context, "Save this canvas as a preset",
        initial: entry.name);
    if (name == null || name.trim().isEmpty) return;
    var document = await CanvasStorage.load(entry.folder, entry.name);
    if (document == null) {
      snackbar.error("Unable to read ${entry.name}.");
      return;
    }
    var saved = await SavedPresetStore.canvases.save(name, document.toJson());
    if (saved == null) {
      snackbar.error("Unable to save the preset.");
      return;
    }
    snackbar.success("Saved ${saved.name} to Presets › Canvas.");
  }

  /// _openRowMenu shows the row's menu under its button, by hand, since a
  /// PopupMenuButton wraps itself in a Tooltip (see _rowButton).
  Future<void> _openRowMenu(
      BuildContext buttonContext, CanvasEntry entry) async {
    var box = buttonContext.findRenderObject() as RenderBox?;
    var overlay =
        Overlay.of(buttonContext).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    var topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    var bottomRight =
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay);

    var choice = await showMenu<_RowAction>(
      context: buttonContext,
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        bottomRight.dy,
        overlay.size.width - bottomRight.dx,
        overlay.size.height - bottomRight.dy,
      ),
      items: entry.isFolder
          ? const [
              PopupMenuItem(
                  value: _RowAction.renameFolder, child: Text("Rename…")),
              PopupMenuItem(
                  value: _RowAction.deleteFolder, child: Text("Delete")),
            ]
          : const [
              PopupMenuItem(value: _RowAction.publish, child: Text("Publish…")),
              // A copy of the file now: later edits leave the preset be.
              PopupMenuItem(
                  value: _RowAction.preset,
                  child: Text("Save canvas as preset")),
              PopupMenuItem(
                  value: _RowAction.duplicate, child: Text("Duplicate")),
              PopupMenuItem(value: _RowAction.rename, child: Text("Rename…")),
              PopupMenuItem(value: _RowAction.move, child: Text("Move to…")),
              PopupMenuItem(value: _RowAction.delete, child: Text("Delete")),
            ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _RowAction.publish:
        widget.onPublish(entry.folder, entry.name);
      case _RowAction.preset:
        await _saveAsPreset(entry);
      case _RowAction.duplicate:
        await _duplicate(entry);
      case _RowAction.rename:
        await _rename(entry);
      case _RowAction.move:
        await _move(entry);
      case _RowAction.delete:
        await _delete(entry);
      case _RowAction.renameFolder:
        await _renameFolder(entry);
      case _RowAction.deleteFolder:
        await _deleteFolder(entry);
    }
  }
}

/// _RowAction is a choice on a row's menu: the first six a canvas's, the
/// last two a folder's.
enum _RowAction {
  publish,
  preset,
  duplicate,
  rename,
  move,
  delete,
  renameFolder,
  deleteFolder,
}
