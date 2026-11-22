import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

// canvas_assets.dart keeps the pictures a canvas refers to. A document holds
// asset ids, never bytes (see ImageElement): the bytes live once here, so a
// picture used many times is one copy and the document stays small JSON.
// Stored raw, not base64, which is a third larger and buys nothing.

/// _dirName is the library's Pictures folder, visible, so its files can be
/// found and used by hand.
const _dirName = canvasPicturesFolder;

/// _idPattern is what an id may look like: the start of a hash of the
/// bytes, and a file extension where the format was recognised (so the
/// files can be previewed and opened). Checked before an id is ever joined
/// onto a path: an id from a saved document is text from disk, and must not
/// become an arbitrary path.
final _idPattern = RegExp(r"^[a-f0-9]{16}(\.[a-z0-9]{1,5})?$");

/// sweepGrace is how new a stored file must be for a sweep to leave it
/// though nothing names it: a bundle's pictures are stored before the
/// canvas naming them is saved, and another save's sweep can run between.
const Duration sweepGrace = Duration(minutes: 10);

/// idMatches is whether [id] is the digest of [bytes], with or without an
/// extension; off the UI isolate for anything big, as a video can be.
Future<bool> idMatches(String id, List<int> bytes) async {
  String digest(List<int> b) => sha256.convert(b).toString().substring(0, 16);
  var d = bytes.length > 4 * 1024 * 1024
      ? await compute(digest, bytes)
      : digest(bytes);
  return id == d || id.startsWith("$d.");
}

/// isMaskId is whether [id] is a subject mask (CanvasAssets.saveMask).
bool isMaskId(String id) => id.endsWith(".mask");

/// looksLikeSvg is whether [bytes] hold an SVG drawing, judged by what they
/// hold and never by the name they arrived under. A drawing has no magic
/// number: it is XML, so the tag is looked for in the first 4 KB, past any
/// declaration, doctype, licence comment and editor metadata an export puts
/// before it. Here, beneath both the stores and the renderer, so everything
/// that asks the question gets the same answer.
bool looksLikeSvg(List<int> bytes) =>
    String.fromCharCodes(bytes.take(4096)).toLowerCase().contains("<svg");

/// maxAssetBytes bounds one picture: generous for photographs, but bounded,
/// because the whole library is read when the sidebar opens.
const int maxAssetBytes = 32 * 1024 * 1024;

class CanvasAssets {
  /// _dir names the folder, creating it only before a write. Reading and
  /// sweeping must not create it: they run in the background, possibly after
  /// the library above it has been removed.
  static Future<String> _dir({bool create = false}) async {
    var dir = path.join(await CanvasStorage.libraryDir(), _dirName);
    if (create) await Directory(dir).create(recursive: true);
    return dir;
  }

  static Future<String?> _pathFor(String id, {bool create = false}) async {
    if (!_idPattern.hasMatch(id)) return null;
    return path.join(await _dir(create: create), id);
  }

  /// save stores a picture and returns its id, or null when it could not be
  /// stored. The id is the start of a hash of the bytes, so the same picture
  /// dropped in twice, or into another canvas, shares one file. The extension
  /// comes from the bytes, not the name they arrived under.
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

  /// saveAs stores a picture under the id it already has, for a canvas from
  /// elsewhere (canvas_bundle.dart), as every reference depends on it. The id
  /// is still checked against [_idPattern]: it is text from another machine.
  static Future<bool> saveAs(String id, List<int> bytes) async {
    if (bytes.isEmpty || bytes.length > maxAssetBytes) return false;
    // The id must be these bytes' hash, or a sender could put their own
    // picture under the name of one somebody else already uses.
    var file = await _pathFor(id, create: true);
    if (file == null) return false;
    try {
      var handle = File(file);
      // Already here (checked when stored): not hashed again, or a canvas
      // previewed twice would have every picture hashed twice.
      if (await handle.exists()) return true;
      if (!await idMatches(id, bytes)) return false;
      await writeWhole(file, bytes);
      return true;
    } catch (exception) {
      debugPrint("Unable to store the picture $id: $exception");
      return false;
    }
  }

  /// extensionForTest exposes [_extensionOf], which names stored pictures, to
  /// tests without writing files.
  @visibleForTesting
  static String extensionForTest(List<int> bytes) => _extensionOf(bytes);

  /// _extensionOf sniffs the format from the first bytes rather than the file
  /// name (a ".jpg" that is really a PNG is common), so the operating system
  /// can open the file.
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
    if (looksLikeSvg(bytes)) return ".svg";

    // Something else: no extension, as a wrong one is worse than none.
    return "";
  }

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

  /// saveMask keeps a picture's subject mask (ImageMask.subject) in the
  /// picture store under its digest, with ".mask" for its kind so the lists
  /// of pictures to choose from leave it out.
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

  /// exists checks the store without reading the picture: the picture cache
  /// asks about every crest on every refresh, and a stat call answers it.
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

  /// stored is every picture in the store, most recently added first.
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
      // No folder yet: nothing stored.
      return const [];
    }
  }

  /// sweep deletes stored pictures no saved document refers to. [liveIds]
  /// must be every id in the whole library plus whatever is open in the
  /// editor, since one picture can be used by several canvases.
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
      // No directory yet: nothing to sweep.
    }
    return removed;
  }
}
