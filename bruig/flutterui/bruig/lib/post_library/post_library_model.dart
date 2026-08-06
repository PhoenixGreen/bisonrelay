import 'dart:async';

import 'package:bruig/post_library/post_storage.dart';
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
  }

  Future<void> refresh() async {
    _loading = true;
    _notify();
    _entries = await PostStorage.list(_folder);
    _loading = false;
    _notify();
  }

  /// openFolderNamed goes into a folder, or back to the top with "".
  Future<void> openFolderNamed(String folder) async {
    _folder = folder;
    await refresh();
  }

  // --- the open document ---

  /// startDocument creates a new document and makes it the open one, so
  /// everything typed from now on lands in it.
  ///
  /// Written immediately, empty, rather than on the first keystroke: a
  /// document that exists only in memory until you type is one that a
  /// crash loses and that the list cannot show.
  Future<bool> startDocument(String name, {String content = ""}) async {
    var written = await _guard(() => PostStorage.write(_folder, name, content));
    if (written == null) return false;
    _openName = written;
    _openFolder = _folder;
    await refresh();
    return true;
  }

  /// saveCurrentAs files whatever the editor holds under a new name, and
  /// leaves it open so further edits keep going there.
  Future<bool> saveCurrentAs(String name) =>
      startDocument(name, content: _editor?.text ?? "");

  /// open loads a document into the editor.
  ///
  /// [replace] false inserts it at the cursor instead, which is the whole
  /// reason the caller is asked: opening a saved note while halfway through
  /// a post should be able to mean either thing, and guessing wrong throws
  /// away work.
  ///
  /// Inserting deliberately does *not* make the document the open one --
  /// the editor now holds a mixture, and autosaving that back over the file
  /// it came from would destroy it.
  Future<bool> open(PostEntry entry, {bool replace = true}) async {
    var content = await PostStorage.read(entry.folder, entry.name);
    if (content == null) {
      _error = "Could not read \"${entry.name}\".";
      _notify();
      return false;
    }
    var editor = _editor;
    if (editor == null) return false;

    if (replace) {
      editor.value = TextEditingValue(
        text: content,
        selection: TextSelection.collapsed(offset: content.length),
      );
      _openName = entry.name;
      _openFolder = entry.folder;
    } else {
      var at = editor.selection.isValid
          ? editor.selection.start
          : editor.text.length;
      var text = editor.text.replaceRange(at, editor.selection.end, content);
      editor.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: at + content.length),
      );
      // The editor is now a mixture of this document and what was already
      // there, and belongs to neither file.
      _openName = null;
    }
    _error = null;
    _notify();
    return true;
  }

  /// closeDocument stops autosaving without touching what is on disk or in
  /// the editor.
  void closeDocument() {
    _debounce?.cancel();
    _openName = null;
    _notify();
  }

  void _onEdited() {
    if (_openName == null) return;
    _debounce?.cancel();
    _debounce = Timer(autosaveDelay, _save);
  }

  /// flush writes any pending edit now, for a caller about to go away.
  Future<void> flush() async {
    if (_debounce?.isActive != true) return;
    _debounce?.cancel();
    await _save();
  }

  Future<void> _save() async {
    var name = _openName;
    var editor = _editor;
    if (name == null || editor == null) return;

    _saving = true;
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
    await refresh();
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
    if (deletedOpen || deletedOpenFolder) closeDocument();
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
