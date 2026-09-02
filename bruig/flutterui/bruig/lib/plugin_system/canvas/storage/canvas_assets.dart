import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

// canvas_assets.dart keeps the pictures a canvas refers to.
//
// A document holds asset ids, never bytes -- see ImageElement. The bytes live
// once here, in a folder the library listing cannot see, so a canvas with the
// same badge on it eleven times is one copy of the badge and the document
// stays a few kilobytes of readable JSON.
//
// This is the same arrangement the post library uses for a draft's embeds, and
// it exists for the same reason: a document that referred to pictures held
// only in memory came back after a restart with the references intact and
// nothing behind them.
//
// Stored as the raw file bytes rather than as base64. The post library's embed
// store keeps base64 because that is the form a post carries them in; nothing
// about a canvas needs text, and base64 is a third larger for no gain.

/// _dirName is the folder inside the library. The leading dot is what keeps it
/// out of the library listing, which skips dotted names.
const _dirName = canvasPicturesFolder;

/// _oldDirName is what the folder was called when it was hidden, and is only
/// ever used to find one left over and move it. See CanvasAssets._migrate.
const _oldDirName = ".assets";

/// _idPattern is what an id may look like: sixteen letters and digits, and
/// optionally a file extension.
///
/// The extension is there so the folder can be opened and looked at. Without
/// one, every picture is a file the operating system cannot preview, name or
/// open -- which is most of why the store was hard to find and impossible to
/// reuse anything from by hand.
///
/// Old ids have no extension and still match, because they are still the names
/// of files on disk that saved documents point at.
///
/// Checked before an id is ever joined onto a path. These ids are generated
/// rather than typed, so this is not where an attack would come from -- but an
/// id that reached here from a saved document is text from disk, and text from
/// disk becoming part of a path is exactly the shape of a mistake worth
/// refusing to make.
final _idPattern = RegExp(r"^[a-zA-Z0-9]{16}(\.[a-z0-9]{1,5})?$");

/// maxAssetBytes bounds one picture.
///
/// Generous, because a canvas is a design tool and somebody will legitimately
/// drop a photograph in -- but bounded, because the whole library is read when
/// the sidebar opens and one 200MB file would stall it.
const int maxAssetBytes = 32 * 1024 * 1024;

int _counter = 0;
final math.Random _random = math.Random();

/// newAssetId makes an id unique within a session and unlikely to collide
/// across them.
String newAssetId() {
  const alphabet = "abcdefghijklmnopqrstuvwxyz0123456789";
  var buffer = StringBuffer();
  var salt = (_counter++ << 20) ^ _random.nextInt(1 << 30);
  for (var i = 0; i < 16; i++) {
    buffer.write(alphabet[(salt ^ _random.nextInt(1 << 30)) % alphabet.length]);
    salt >>= 1;
  }
  return buffer.toString();
}

/// CanvasAssets reads and writes the pictures.
class CanvasAssets {
  /// _dir names the folder, creating it only when something is about to be
  /// written there.
  ///
  /// Reading and sweeping must not create it: they run in the background, and
  /// a directory conjured up after the library above it has been taken away is
  /// a directory nobody asked for.
  /// _migrate moves a store made while the folder was hidden.
  ///
  /// Careful rather than clever, because this touches pictures nobody else has
  /// a copy of and every saved canvas points at them by name:
  ///
  ///  - nothing to move, nothing happens;
  ///  - both present, nothing happens either. That is a store in a state this
  ///    cannot reason about, and refusing to guess leaves both folders where
  ///    they can be seen and sorted out rather than merging them and
  ///    overwriting one picture with another of the same name.
  ///  - the move itself is a rename, which is atomic within a directory: it
  ///    either happened or it did not, and there is no state where half the
  ///    pictures are in each.
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
      // A store that cannot be moved is still a store, and refusing to open
      // Canvas over a folder name would be worse than leaving it where it is.
    }
  }

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

  /// save writes one picture and returns its id, or null when it could not be
  /// stored.
  /// save stores a picture and returns the id a document refers to it by.
  ///
  /// The id is the picture's own content -- the first part of a hash of the
  /// bytes -- rather than a fresh random name. So dropping the same photograph
  /// into a second canvas, or into the same one twice, finds the copy that is
  /// already there instead of writing another beside it, and the two elements
  /// share one file. That is the reuse the store was always supposed to give
  /// and never did: every import wrote a new name for identical bytes.
  ///
  /// The extension comes from what the bytes actually are rather than from the
  /// name they arrived under, which may be wrong or missing.
  static Future<String?> save(List<int> bytes) async {
    if (bytes.isEmpty || bytes.length > maxAssetBytes) return null;

    var id = "${sha256.convert(bytes).toString().substring(0, 16)}"
        "${_extensionOf(bytes)}";
    var file = await _pathFor(id, create: true);
    if (file == null) return null;

    try {
      var handle = File(file);
      // Already stored, by this canvas or another. Writing it again would be
      // the same bytes to the same path for nothing.
      if (await handle.exists()) return id;
      await handle.writeAsBytes(bytes, flush: true);
      return id;
    } catch (_) {
      return null;
    }
  }

  /// _extensionOf sniffs the format from the first few bytes.
  ///
  /// From the bytes rather than from the file name it came in under: a
  /// screenshot saved as ".jpg" that is really a PNG is common enough, and the
  /// point of the extension is that the operating system can open the file.
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

  /// saveBase64 stores a picture that arrived as text -- which is the form an
  /// embed pasted out of a post carries.
  static Future<String?> saveBase64(String data) async {
    try {
      return await save(base64Decode(data));
    } catch (_) {
      return null;
    }
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

  /// sweepUnused deletes every stored picture no saved canvas refers to.
  ///
  /// Called after a canvas is saved or deleted, which are the only two moments
  /// the answer can change. Nothing called [sweep] at all until now, so a
  /// picture dropped into a canvas and then deleted stayed on disk for good --
  /// invisible, unreachable, and counted against nothing.
  ///
  /// Failing is not worth reporting. The cost of a missed sweep is some bytes
  /// nobody can see, and a canvas that had just been saved successfully should
  /// not raise an error about tidying up afterwards.
  static Future<int> sweepUnused() async {
    try {
      return await sweep(await CanvasStorage.liveAssetIds());
    } catch (_) {
      return 0;
    }
  }

  /// sweep deletes stored pictures that no saved document refers to.
  ///
  /// [liveIds] has to be every id in the whole library plus whatever is open
  /// in the editor, because one picture can be referred to from more than one
  /// canvas -- a document duplicated, or an element copied between two of them
  /// -- and deleting it while a second document still points at it would break
  /// that document to tidy up after the first.
  static Future<int> sweep(Set<String> liveIds) async {
    var removed = 0;
    try {
      var dir = Directory(await _dir());
      await for (var entry in dir.list(followLinks: false)) {
        if (entry is! File) continue;
        var id = path.basename(entry.path);
        if (liveIds.contains(id)) continue;
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
