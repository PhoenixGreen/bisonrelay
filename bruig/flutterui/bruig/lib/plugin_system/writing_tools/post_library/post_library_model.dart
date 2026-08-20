import 'dart:async';

import 'package:bruig/plugin_system/writing_tools/notes/note_storage.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/embed_store.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/post_storage.dart';
import 'package:flutter/material.dart';

// post_library_model.dart holds what the sidebar is showing and keeps the
// open document on disk.
//
// The library itself is the directory listing -- there is no index to keep
// in step with it -- so this holds only the position in it: which folder is
// open, which document is loaded, and the debounce timer.

/// autosaveDelay is how long typing has to stop before the open document is
/// written.
///
/// Long enough that a sentence is one write rather than thirty, short enough
/// that closing the laptop mid-thought does not lose it. Every write is the
/// whole file, which at the size of a post is nothing.
const autosaveDelay = Duration(milliseconds: 800);

/// maxAutosaveInterval is the longest the open document can go unwritten
/// while it is being edited.
///
/// A debounce alone is not autosave: somebody typing steadily never stops
/// for long enough to trigger one, so the longer they write the more they
/// stand to lose. This puts a ceiling on it regardless of how continuously
/// the keys are moving.
const maxAutosaveInterval = Duration(seconds: 3);

/// PostLibraryModel is the saved-post library as the sidebar sees it.
class PostLibraryModel extends ChangeNotifier {
  /// folder is the folder being browsed, or "" for the top level.
  String get folder => _folder;
  String _folder = "";

  /// entries is what is in [folder] right now.
  List<PostEntry> get entries => _entries;
  List<PostEntry> _entries = const [];

  bool get loading => _loading;
  bool _loading = false;

  /// openName is the document being edited, or null when the editor holds
  /// something that is not from the library -- a fresh post, or one opened
  /// and then replaced.
  String? get openName => _openName;
  String? _openName;

  /// openFolder is where [openName] lives, which is not necessarily the
  /// folder currently being browsed.
  String get openFolder => _openFolder;
  String _openFolder = "";

  /// saving is true while a write is in flight, so the sidebar can say so
  /// rather than leaving the user wondering.
  bool get saving => _saving;
  bool _saving = false;

  /// error is the last failure, for the sidebar to show. Cleared by the next
  /// successful operation.
  String? get error => _error;
  String? _error;

  TextEditingController? _editor;
  Timer? _debounce;
  DateTime? _dirtySince;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _editor?.removeListener(_onEdited);
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// watch points the model at the composer whose text is being saved.
  ///
  /// The editor can be swapped underneath this -- a rebuild of the screen
  /// hands over a new controller -- so the listener moves with it. Nothing
  /// is written until a document is actually open.
  void watch(TextEditingController? editor) {
    if (identical(editor, _editor)) return;
    _editor?.removeListener(_onEdited);
    _editor = editor;
    _editor?.addListener(_onEdited);
    // Somebody asked for a document while there was nowhere to put it --
    // see requestOpen.
    if (_editor != null && _pendingOpen != null) {
      var wanted = _pendingOpen!;
      _pendingOpen = null;
      open(wanted);
    }
  }

  PostEntry? _pendingOpen;

  /// requestOpen opens a document, or arranges to as soon as there is an
  /// editor to open it into.
  ///
  /// The waiting is the point. Asking is done from elsewhere in the app --
  /// My Site's New and Edit buttons -- which then navigates to the Writing
  /// page, so at the moment of asking there is no composer yet and [open]
  /// would have nothing to write into and quietly do nothing.
  Future<void> requestOpen(String folder, String name) async {
    var entry = PostEntry(name: name, folder: folder, isFolder: false);
    if (_editor == null) {
      _pendingOpen = entry;
      // The sidebar should be showing the folder it came from when it
      // arrives, not wherever it was left last.
      _folder = folder;
      return;
    }
    await open(entry);
    await openFolderNamed(folder);
  }

  Future<void> refresh() async {
    _loading = true;
    _notify();
    _entries = await PostStorage.list(_folder);
    _loading = false;
    _notify();
    unawaited(_sweepEmbedsOnce());
  }

  /// _sweptEmbeds keeps the sweep to once per run of the app.
  bool _sweptEmbeds = false;

  /// _sweepEmbedsOnce deletes stored pictures that no draft refers to any
  /// more -- the ones left behind when a draft holding a picture is deleted.
  ///
  /// Once per run, and after the listing rather than before it, because it
  /// reads every document in the library to find out which pictures are
  /// still spoken for. That is cheap for text files and not something to do
  /// on every visit to the sidebar.
  ///
  /// Every document, not only the open folder: one picture can be referred
  /// to from more than one draft -- a post duplicated, or text pasted
  /// between two of them -- and deleting it while a second draft still
  /// points at it would break that draft to tidy up after the first.
  ///
  /// [alsoLive] is anything referred to from outside the library, which
  /// means the post currently in the composer. It has not necessarily been
  /// saved anywhere yet.
  Future<void> _sweepEmbedsOnce() async {
    if (_sweptEmbeds) return;
    _sweptEmbeds = true;
    try {
      var live = Set<String>.from(alsoLive?.call() ?? const <String>{});
      // Every folder, reserved ones included: a picture in a page, a
      // fragment or a note is as spoken for as one in a post.
      for (var folder in ["", ...await PostStorage.allFolderNames()]) {
        for (var entry in await PostStorage.list(folder)) {
          if (entry.isFolder) continue;
          var content = await PostStorage.read(entry.folder, entry.name);
          if (content != null) live.addAll(EmbedStore.idsIn(content));
        }
      }
      await EmbedStore.sweep(live);
    } catch (_) {
      // Tidying up is never worth failing over. The cost of not doing it is
      // some disk space; the cost of getting it wrong would be a picture.
    }
  }

  /// alsoLive reports embed ids in use outside the library, so the sweep
  /// does not delete a picture the composer is still holding.
  Set<String> Function()? alsoLive;

  /// openFolderNamed goes into a folder, or back to the top with "".
  Future<void> openFolderNamed(String folder) async {
    _folder = folder;
    await refresh();
  }

  // --- the open document ---

  /// newDocument creates a document and makes it the open one, so
  /// everything typed from now on lands in it.
  ///
  /// It takes the editor's text when nothing is open and starts blank when
  /// something is, and neither of those loses anything: with a document open
  /// the text is already in it, and with none open the text belongs to
  /// nowhere else and would be discarded by the next thing loaded.
  ///
  /// Written immediately rather than on the first keystroke: a document that
  /// exists only in memory until you type is one that a crash loses and that
  /// the list cannot show.
  Future<bool> newDocument(String name) async {
    await flush();
    var adopting = _openName == null;
    var content = adopting ? (_editor?.text ?? "") : "";

    var written = await _guard(() => PostStorage.write(_folder, name, content));
    if (written == null) return false;

    _openName = written;
    _openFolder = _folder;
    if (!adopting) _setEditorText("");
    await refresh();
    return true;
  }

  /// adoptsEditorText reports what [newDocument] would do with what is on
  /// screen, so the dialog can say which before it is agreed to.
  bool get adoptsEditorText => _openName == null;

  /// open loads a document into the editor, saving whatever was open first.
  ///
  /// Switching is the whole interaction: the editor shows one document at a
  /// time, moving between them writes the one being left, and nothing new is
  /// created by the move. An earlier version asked whether to replace the
  /// editor or insert at the cursor, which meant a document could end up
  /// holding a mixture that belonged to no file -- and the next save then
  /// wrote it out under a new name, quietly multiplying documents every time
  /// somebody moved between them.
  Future<bool> open(PostEntry entry) async {
    await flush();
    await fileLooseText();

    var content = await PostStorage.read(entry.folder, entry.name);
    if (content == null) {
      _error = "Could not read \"${entry.name}\".";
      _notify();
      return false;
    }
    if (_editor == null) return false;

    _setEditorText(content);
    _openName = entry.name;
    _openFolder = entry.folder;
    _dirtySince = null;
    _error = null;
    _notify();
    return true;
  }

  /// fileLooseText saves editor text that belongs to no document.
  ///
  /// Opening a document replaces the editor, and without this the post
  /// somebody had started writing -- which is not in the library and not in
  /// any file -- would go with it. It is filed under a name taken from its
  /// own first line, beside everything else, rather than being lost or
  /// silently held somewhere the user cannot see.
  ///
  /// The result deliberately does not become the open document: the caller
  /// is on its way to opening something else.
  Future<String?> fileLooseText() async {
    if (_openName != null) return null;
    var text = _editor?.text ?? "";
    if (text.trim().isEmpty) return null;

    var name = await _availableName(PostStorage.suggestName(text));
    var written = await _guard(() => PostStorage.write(_folder, name, text));
    if (written != null) await refresh();
    return written;
  }

  /// _availableName finds a name near [wanted] that is not taken, so filing
  /// loose text cannot land on top of a document somebody wrote.
  Future<String> _availableName(String wanted) async {
    if (!await PostStorage.exists(_folder, wanted)) return wanted;
    for (var n = 2; n < 1000; n++) {
      var candidate = "$wanted $n";
      if (!await PostStorage.exists(_folder, candidate)) return candidate;
    }
    return "$wanted ${DateTime.now().millisecondsSinceEpoch}";
  }

  /// renameOpen renames the document currently being edited, or files the
  /// editor's text under [name] when nothing is open yet.
  ///
  /// This is what the title on the composer does. Naming an unfiled post is
  /// how it becomes a document, which means the title box is also the way
  /// into the library for somebody who never opens the sidebar.
  Future<bool> renameOpen(String name) async {
    var safe = PostStorage.sanitizeName(name);
    if (safe == null || safe == _openName) return false;

    if (_openName == null) return newDocument(safe);

    await flush();
    var entry =
        PostEntry(name: _openName!, folder: _openFolder, isFolder: false);
    return rename(entry, safe);
  }

  /// move puts a document in another folder, following it if it is the one
  /// open so autosave keeps writing where the user can see it.
  Future<bool> move(PostEntry entry, String toFolder) async {
    await flush();
    var moved = await _guard(() => PostStorage.move(entry, toFolder));
    if (moved != true) {
      _error = "Could not move \"${entry.name}\" -- is that name taken there?";
      _notify();
      return false;
    }
    if (entry.name == _openName && entry.folder == _openFolder) {
      _openFolder = toFolder;
    }
    await refresh();
    return true;
  }

  /// _setEditorText replaces what is on screen, leaving the caret at the end
  /// where somebody continuing to write expects it.
  void _setEditorText(String text) {
    _editor?.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// closeDocument stops autosaving without touching what is on disk or in
  /// the editor.
  void closeDocument() {
    _debounce?.cancel();
    _dirtySince = null;
    _openName = null;
    _notify();
  }

  void _onEdited() {
    if (_openName == null) return;

    // The ceiling, checked before the debounce is renewed: renewing it is
    // exactly what a steady typist does forever.
    var since = _dirtySince;
    if (since == null) {
      _dirtySince = DateTime.now();
    } else if (DateTime.now().difference(since) >= maxAutosaveInterval) {
      _debounce?.cancel();
      _save();
      return;
    }

    _debounce?.cancel();
    _debounce = Timer(autosaveDelay, _save);
  }

  /// flush writes any pending edit now, for a caller about to go away or
  /// about to load something else over the top.
  Future<void> flush() async {
    if (_debounce?.isActive != true && _dirtySince == null) return;
    _debounce?.cancel();
    await _save();
  }

  Future<void> _save() async {
    var name = _openName;
    var editor = _editor;
    if (name == null || editor == null) return;

    _saving = true;
    _dirtySince = null;
    _notify();
    await _guard(() => PostStorage.write(_openFolder, name, editor.text));
    _saving = false;
    // Only the browsed folder is on screen; refreshing another one would
    // replace the list the user is looking at.
    if (_openFolder == _folder) {
      _entries = await PostStorage.list(_folder);
    }
    _notify();
  }

  // --- library operations ---

  Future<bool> createFolder(String name) async {
    var made = await _guard(() => PostStorage.createFolder(name));
    if (made == null) return false;
    await refresh();
    return true;
  }

  Future<bool> rename(PostEntry entry, String newName) async {
    var renamed = await _guard(() => PostStorage.rename(entry, newName));
    if (renamed == null) {
      _error = "Could not rename to \"$newName\" -- is that name taken?";
      _notify();
      return false;
    }
    // The open document following its own rename, so autosave keeps writing
    // to the file the user is looking at rather than recreating the old one.
    if (!entry.isFolder &&
        entry.name == _openName &&
        entry.folder == _openFolder) {
      _openName = renamed;
    }
    // A note is an ordinary document, so this Rename applies to it -- and the
    // index that says which page each note belongs to has to follow, or the
    // renamed note detaches and that page starts an empty second one beside
    // it. See NoteStorage.noteRenamed.
    if (!entry.isFolder && entry.folder == notesFolderName) {
      await NoteStorage.noteRenamed(entry.name, renamed);
    }
    await refresh();
    return true;
  }

  /// reorder moves the entry at [from] to [to], as a drag ends.
  ///
  /// The indices are into [entries] as it is shown, [to] being where the row
  /// ends up -- ReorderableListView's onReorderItem has already accounted for
  /// the row leaving its old place, which its older onReorder did not.
  ///
  /// A document cannot be dropped among the folders or the other way about:
  /// the two are separate runs and stay that way, so a drag that ends past
  /// the boundary lands against it instead of crossing it.
  Future<bool> reorder(int from, int to) async {
    if (from < 0 || from >= _entries.length) return false;

    var moving = _entries[from];
    // The notes folder is pinned to the bottom by the listing itself and is
    // not among the rows that can move. Its own row offers no drag handle;
    // this is the guard for everything else, so a folder dragged to the end
    // lands above it rather than past it.
    if (moving.isNotesFolder) return false;
    var first = _entries.indexWhere((e) => e.isFolder == moving.isFolder);
    var last = _entries.lastIndexWhere(
        (e) => e.isFolder == moving.isFolder && !e.isNotesFolder);
    to = to.clamp(first, last);
    if (to == from) return false;

    var next = [..._entries];
    next.insert(to, next.removeAt(from));

    // Written as one list for the folder, documents then folders, which is
    // the order the listing puts them back in.
    var order = [
      for (var e in next)
        if (!e.isFolder) e.name,
      for (var e in next)
        if (e.isFolder) e.name,
    ];

    // Shown before it is saved. A drag that snaps back while the disk write
    // finishes reads as the drag having failed.
    _entries = next;
    _notify();

    if (!await PostStorage.writeOrder(_folder, order)) {
      _error = "Could not save the order of this folder";
      await refresh();
      return false;
    }
    return true;
  }

  Future<void> delete(PostEntry entry) async {
    await PostStorage.delete(entry);
    // Deleting what is open stops the autosave, which would otherwise write
    // the file straight back a second later.
    var deletedOpen = !entry.isFolder &&
        entry.name == _openName &&
        entry.folder == _openFolder;
    var deletedOpenFolder = entry.isFolder && entry.name == _openFolder;
    if (deletedOpen || deletedOpenFolder) {
      closeDocument();
      // ...and the writing goes with it.
      //
      // Stopping the autosave is not enough on its own. closeDocument leaves
      // the text on screen belonging to no document, which is exactly the
      // state fileLooseText exists to rescue -- so opening anything else
      // filed it under a name taken from its own first heading, which is the
      // name it had just been deleted under, and the document reappeared in
      // the folder it had just been removed from.
      //
      // Clearing it here rather than teaching fileLooseText to recognise
      // deleted text: text that has been explicitly deleted is not unsaved
      // writing, and a flag saying "do not rescue this" would still be
      // sitting there over whatever the user typed next.
      _setEditorText("");
    }
    await refresh();
  }

  /// _guard runs a storage call and turns a failure into something the
  /// sidebar can show, rather than an unhandled exception from a disk that
  /// is full or a directory that is read-only.
  Future<T?> _guard<T>(Future<T?> Function() op) async {
    try {
      var result = await op();
      if (result != null) _error = null;
      return result;
    } catch (exception) {
      _error = "$exception";
      _notify();
      return null;
    }
  }
}
