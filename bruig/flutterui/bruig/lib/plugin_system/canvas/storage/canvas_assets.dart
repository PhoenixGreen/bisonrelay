import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

// canvas_assets.dart keeps the pictures a canvas refers to.
//
// A document holds asset ids, never bytes (see ImageElement). The bytes live
// once here, so a picture used many times is one copy and the document stays
// small, readable JSON. The same arrangement as the post library's embeds,
// but stored as raw bytes rather than base64, which is a third larger and
// buys a canvas nothing.

/// _dirName is the folder inside the library: Pictures, visible, so its
/// files can be found and used by hand.
const _dirName = canvasPicturesFolder;

/// _oldDirName is what the folder was called when it was hidden, used only to
/// find one left over and move it. See CanvasAssets._migrate.
const _oldDirName = ".assets";

/// _idPattern is what an id may look like: sixteen letters and digits, and
/// optionally a file extension (so the folder's files can be previewed and
/// opened). Old ids have no extension and still match, since saved documents
/// point at them.
///
/// Checked before an id is ever joined onto a path: an id from a saved
/// document is text from disk, and text from disk must not become an
/// arbitrary path.
final _idPattern = RegExp(r"^[a-zA-Z0-9]{16}(\.[a-z0-9]{1,5})?$");

/// sweepGrace is how new a stored file must be for a sweep to leave it,
/// though nothing names it yet: a bundle's pictures are stored before the
/// canvas that names them is saved, and another save's sweep can run between.
const Duration sweepGrace = Duration(minutes: 10);

/// _hashed is an id made from its content: a digest and an extension.
final _hashed = RegExp(r"^[a-f0-9]{16}\.[a-z0-9]{1,5}$");

/// idMatches is whether [id] starts with the digest of [bytes]: off the UI
/// isolate for anything big, which a video can be.
Future<bool> idMatches(String id, List<int> bytes) async {
  String digest(List<int> b) => sha256.convert(b).toString().substring(0, 16);
  var d = bytes.length > 4 * 1024 * 1024
      ? await compute(digest, bytes)
      : digest(bytes);
  return id.startsWith("$d.");
}

/// isMaskId is whether [id] is a subject mask rather than a picture. See
/// CanvasAssets.saveMask.
bool isMaskId(String id) => id.endsWith(".mask");

/// maxAssetBytes bounds one picture: generous, since photographs are
/// dropped in, but bounded, because the whole library is read when the
/// sidebar opens.
const int maxAssetBytes = 32 * 1024 * 1024;

/// CanvasAssets reads and writes the pictures.
class CanvasAssets {
  /// _migrate moves a store made while the folder was hidden. Careful,
  /// because every saved canvas points at these pictures by name:
  ///
  ///  - nothing to move, nothing happens;
  ///  - both present, nothing happens either: rather than merge and risk
  ///    overwriting a picture, both folders are left to be sorted out;
  ///  - the move itself is a rename, atomic within a directory.
  ///
  /// The names inside are untouched, so every document still resolves.
  static Future<void> _migrate(String library) async {
    try {
      var old = Directory(path.join(library, _oldDirName));
      if (!await old.exists()) return;
      var wanted = Directory(path.join(library, _dirName));
      if (await wanted.exists()) return;
      await old.rename(wanted.path);
    } catch (_) {
      // A store that cannot be moved is still a store: better left where it
      // is than Canvas refusing to open.
    }
  }

  /// _dir names the folder, creating it only when something is about to be
  /// written there. Reading and sweeping must not create it: they run in the
  /// background, possibly after the library above it has been removed.
  static Future<String> _dir({bool create = false}) async {
    var library = await CanvasStorage.libraryDir();
    await _migrate(library);
    var dir = path.join(library, _dirName);
    if (create) await Directory(dir).create(recursive: true);
    return dir;
  }

  static Future<String?> _pathFor(String id, {bool create = false}) async {
    if (!_idPattern.hasMatch(id)) return null;
    return path.join(await _dir(create: create), id);
  }

  /// save stores a picture and returns the id a document refers to it by, or
  /// null when it could not be stored.
  ///
  /// The id is the start of a hash of the bytes, so the same photograph
  /// dropped in twice, or into another canvas, finds the copy already there
  /// and the elements share one file. The extension comes from what the bytes
  /// are rather than the name they arrived under.
  static Future<String?> save(List<int> bytes) async {
    if (bytes.isEmpty || bytes.length > maxAssetBytes) return null;

    var id = "${sha256.convert(bytes).toString().substring(0, 16)}"
        "${_extensionOf(bytes)}";
    var file = await _pathFor(id, create: true);
    if (file == null) return null;

    try {
      var handle = File(file);
      // Already stored, by this canvas or another.
      if (await handle.exists()) return id;
      await writeWhole(file, bytes);
      return id;
    } catch (_) {
      return null;
    }
  }

  /// saveAs stores a picture under the id it already has, for a canvas
  /// arriving from somewhere else (see canvas_bundle.dart). [save] would
  /// nearly always work out the same name, but not for a canvas made before
  /// ids carried an extension, and every reference depends on it. The id is
  /// still checked against [_idPattern]: it really is text from somebody
  /// else's machine.
  static Future<bool> saveAs(String id, List<int> bytes) async {
    if (bytes.isEmpty || bytes.length > maxAssetBytes) return false;
    // An id that is a hash must be these bytes' hash, or a sender could put
    // their own picture under the name of one somebody else already uses.
    // Only the oldest ids, random names, cannot be checked.
    var file = await _pathFor(id, create: true);
    if (file == null) return false;
    try {
      var handle = File(file);
      // Already here (checked when it was stored): not hashed again, as a
      // canvas previewed twice would have every picture hashed twice.
      if (await handle.exists()) return true;
      if (_hashed.hasMatch(id) && !await idMatches(id, bytes)) return false;
      await writeWhole(file, bytes);
      return true;
    } catch (exception) {
      debugPrint("Unable to store the picture $id: $exception");
      return false;
    }
  }

  /// extensionForTest is [_extensionOf], which decides what a stored picture
  /// is called and is worth checking without writing files.
  @visibleForTesting
  static String extensionForTest(List<int> bytes) => _extensionOf(bytes);

  /// _extensionOf sniffs the format from the first few bytes rather than the
  /// file name it came in under (a ".jpg" that is really a PNG is common), so
  /// the operating system can open the file.
  static String _extensionOf(List<int> bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return ".png";
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return ".jpg";
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return ".gif";
    }
    if (bytes.length >= 12 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return ".webp";
    }
    // A vector, which has no magic number: it is XML, so look for the tag
    // near the top. The first few thousand bytes, since a drawing program's
    // file can open with a declaration, a doctype, a licence comment and
    // editor metadata before the tag.
    var head = String.fromCharCodes(bytes.take(4096)).toLowerCase();
    if (head.contains("<svg")) return ".svg";

    // Something else. Left without one rather than guessed at, since a wrong
    // extension is worse than none.
    return "";
  }

  /// saveFile copies a picture in from wherever the user picked it.
  static Future<String?> saveFile(String sourcePath) async {
    try {
      var source = File(sourcePath);
      var length = await source.length();
      if (length > maxAssetBytes) return null;
      return await save(await source.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  /// saveMask keeps a picture's subject mask (see ImageMask.subject) in the
  /// picture store, under its digest like any picture but with ".mask" for
  /// its kind, so the lists of pictures to choose from leave it out.
  static Future<String?> saveMask(List<int> bytes) async {
    if (bytes.isEmpty) return null;
    var id = "${sha256.convert(bytes).toString().substring(0, 16)}.mask";
    return await saveAs(id, bytes) ? id : null;
  }

  /// pathOf is where the picture [id] is on disk, or null where it is not.
  static Future<String?> pathOf(String id) async {
    var where = await _pathFor(id);
    if (where == null || !await File(where).exists()) return null;
    return where;
  }

  /// exists is whether a picture is still in the store, without reading it:
  /// the picture cache asks about every crest on every refresh, and a stat
  /// call answers it.
  static Future<bool> exists(String id) async {
    var file = await _pathFor(id);
    return file != null && await File(file).exists();
  }

  static Future<List<int>?> load(String id) async {
    var file = await _pathFor(id);
    if (file == null) return null;
    try {
      var f = File(file);
      if (!await f.exists()) return null;
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// stored is every picture in the store, most recently added first, so a
  /// picture can be used again.
  static Future<List<String>> stored() async {
    try {
      var dir = Directory(await _dir());
      var found = <(String, DateTime)>[];
      await for (var entry in dir.list(followLinks: false)) {
        if (entry is! File) continue;
        var id = path.basename(entry.path);
        if (!_idPattern.hasMatch(id)) continue;
        found.add((id, (await entry.stat()).modified));
      }
      found.sort((a, b) => b.$2.compareTo(a.$2));
      return [for (var entry in found) entry.$1];
    } catch (_) {
      // No folder yet, which means nothing stored.
      return const [];
    }
  }

  /// sweepUnused deletes every stored picture no saved canvas refers to.
  /// Called after a canvas is saved or deleted, the only moments the answer
  /// changes. Failing is not reported: a missed sweep costs some unseen bytes,
  /// and a successful save should not raise an error about tidying.
  static Future<int> sweepUnused() async {
    try {
      return await sweep(await CanvasStorage.liveAssetIds());
    } catch (_) {
      return 0;
    }
  }

  /// sweep deletes stored pictures that no saved document refers to.
  /// [liveIds] has to be every id in the whole library plus whatever is open
  /// in the editor, since one picture can be referred to from several
  /// canvases.
  static Future<int> sweep(Set<String> liveIds) async {
    var removed = 0;
    try {
      var dir = Directory(await _dir());
      await for (var entry in dir.list(followLinks: false)) {
        if (entry is! File) continue;
        var id = path.basename(entry.path);
        if (liveIds.contains(id)) continue;
        if (DateTime.now().difference(await entry.lastModified()) <
            sweepGrace) {
          continue;
        }
        try {
          await entry.delete();
          removed++;
        } catch (_) {
          // Being unable to delete one is not a reason to stop.
        }
      }
    } catch (_) {
      // No directory yet, which means nothing to sweep.
    }
    return removed;
  }
}
