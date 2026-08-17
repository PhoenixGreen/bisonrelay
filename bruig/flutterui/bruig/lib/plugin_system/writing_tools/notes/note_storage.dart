import 'dart:io';

import 'package:bruig/plugin_system/writing_tools/notes/note_target.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/post_storage.dart';
import 'package:path/path.dart' as path;

// note_storage.dart puts notes where the posts are.
//
// A note is a Markdown document in "<appDataDir>/my-posts/Bison Relay Notes",
// written through PostStorage like every other document in the library. That
// is the whole design and it is worth saying why, because the obvious
// alternative -- a notes database, or the JSON sidecar this feature started
// life as -- is easier to write and worse to live with.
//
// Notes are writing. Treating them as a separate kind of thing means a second
// format nothing else can read, a second place to back up, a second editor,
// and a note that can never become a post without being copied out by hand.
// Treating them as documents means they arrive in the library already: openable
// in the composer, spell-checked, searchable with grep, and readable in ten
// years by anything that reads text.
//
// What a note needs that a post does not is to be findable *by what it is
// about* -- "the note for this file", not "the note called this". That is one
// mapping, and it is kept in a hidden ".targets" file in the folder, the same
// shape and for the same reasons as the ".order" file next to it: one line per
// note, names rather than positions, and anything unrecognised ignored rather
// than treated as corruption. The listing is still the library; this is only
// an index into it, and it is rebuilt from the listing whenever it disagrees.

/// _indexFile maps notes to what they are about.
///
/// Hidden, so the listing already skips it and it needs no special case to
/// stay out of the library it describes. One "name\tkey" per line.
const _indexFile = ".targets";

/// NoteStorage reads and writes the notes folder.
class NoteStorage {
  /// folderPath is the notes folder, whether or not it exists yet.
  static Future<String> folderPath() async =>
      path.join(await PostStorage.libraryDir(), notesFolderName);

  /// ensureFolder makes the notes folder, so it appears in the sidebar before
  /// anybody has written anything into it.
  ///
  /// Called when notes are switched on rather than from PostStorage, so a
  /// user who turns the feature off never grows an empty folder.
  static Future<void> ensureFolder() async {
    try {
      await Directory(await folderPath()).create(recursive: true);
    } catch (_) {
      // A library that cannot be created is a problem the first write will
      // report properly. Failing here would only take the sidebar down.
    }
  }

  /// read returns the note for [target], or "" when there is not one yet.
  static Future<String> read(NoteTarget target) async {
    var name = await _existingNameFor(target);
    if (name == null) return "";
    return await PostStorage.read(notesFolderName, name) ?? "";
  }

  /// write saves the note for [target], creating it on the first keystroke
  /// and deleting it again when it is emptied.
  ///
  /// Deleting rather than leaving a blank document behind: the notes folder
  /// fills up on its own, without anybody choosing to file anything into it,
  /// so a note cleared out has to leave no row -- otherwise a week of
  /// glancing at pages leaves a list of empty documents to tidy up.
  static Future<bool> write(NoteTarget target, String text) async {
    try {
      var existing = await _existingNameFor(target);

      if (text.trim().isEmpty) {
        if (existing == null) return true;
        await PostStorage.delete(PostEntry(
            name: existing, folder: notesFolderName, isFolder: false));
        await _rewriteIndex();
        return true;
      }

      var name = existing ?? await _newNameFor(target);
      if (name == null) return false;
      var written = await PostStorage.write(notesFolderName, name, text);
      if (written == null) return false;
      if (existing == null) await _link(written, target.key);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// hasNote reports whether [target] has anything written about it, for a
  /// button that wants to say so without opening the note.
  static Future<bool> hasNote(NoteTarget target) async =>
      await _existingNameFor(target) != null;

  /// noteRenamed keeps a note attached to its page after it is renamed in the
  /// sidebar.
  ///
  /// Notes are ordinary documents, which means the library's own Rename
  /// applies to them, which means the index has to follow. Without this a
  /// renamed note would quietly detach: the page it belonged to would find
  /// nothing under the old name and start a second, empty one beside it.
  static Future<void> noteRenamed(String from, String to) async {
    var index = await _readIndex();
    var key = index.remove(from);
    if (key == null) return;
    index[to] = key;
    await _writeIndex(index);
  }

  // --- the index ---

  /// _existingNameFor is the note filed against [target], or null.
  ///
  /// Checked against the directory rather than trusted: a note deleted from
  /// the sidebar, or moved out of the folder to become an ordinary post,
  /// leaves an entry behind, and handing that name back would read an empty
  /// string out of a file that is not there and then write the note back into
  /// existence.
  static Future<String?> _existingNameFor(NoteTarget target) async {
    var index = await _readIndex();
    var live = await _liveNames();
    for (var entry in index.entries) {
      if (entry.value == target.key && live.contains(entry.key)) {
        return entry.key;
      }
    }
    return null;
  }

  /// _newNameFor picks a filename for a note that does not have one, from the
  /// target's own title, stepping past anything already taken.
  static Future<String?> _newNameFor(NoteTarget target) async {
    var base = PostStorage.sanitizeName(target.title);
    if (base == null) return null;

    var index = await _readIndex();
    var live = await _liveNames();
    bool taken(String n) => live.contains(n) || index.containsKey(n);

    if (!taken(base)) return base;
    // Two different things really can share a title -- two files of the same
    // name in different folders, two groups renamed to match. They are
    // different targets, so they get different notes.
    for (var n = 2; n < 1000; n++) {
      var candidate = "$base $n";
      if (!taken(candidate)) return candidate;
    }
    return "$base ${DateTime.now().millisecondsSinceEpoch}";
  }

  /// _liveNames is the notes actually in the folder right now.
  static Future<Set<String>> _liveNames() async {
    var entries = await PostStorage.list(notesFolderName);
    return {
      for (var entry in entries)
        if (!entry.isFolder) entry.name,
    };
  }

  static Future<Map<String, String>> _readIndex() async {
    try {
      var file = File(path.join(await folderPath(), _indexFile));
      if (!await file.exists()) return {};
      var out = <String, String>{};
      for (var line in await file.readAsLines()) {
        var cut = line.indexOf("\t");
        if (cut <= 0) continue;
        var name = line.substring(0, cut).trim();
        var key = line.substring(cut + 1).trim();
        if (name.isEmpty || key.isEmpty) continue;
        out[name] = key;
      }
      return out;
    } catch (_) {
      // An index that cannot be read is an index that has not been written
      // yet, as far as anything above here is concerned. The notes are still
      // on disk under their own names; what is lost is which page each one
      // belongs to, and the next note written rebuilds that one entry.
      return {};
    }
  }

  static Future<bool> _writeIndex(Map<String, String> index) async {
    try {
      var dir = await folderPath();
      await Directory(dir).create(recursive: true);
      await File(path.join(dir, _indexFile)).writeAsString(
          [for (var e in index.entries) "${e.key}\t${e.value}"].join("\n"));
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _link(String name, String key) async {
    var index = await _readIndex();
    // A key can only belong to one note, so anything else claiming it is
    // stale -- a note deleted and written again.
    index.removeWhere((_, k) => k == key);
    index[name] = key;
    await _writeIndex(index);
  }

  /// _rewriteIndex drops the entries whose documents have gone.
  static Future<void> _rewriteIndex() async {
    var index = await _readIndex();
    var live = await _liveNames();
    index.removeWhere((name, _) => !live.contains(name));
    await _writeIndex(index);
  }
}
