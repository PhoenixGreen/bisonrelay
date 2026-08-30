import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
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
const _dirName = ".assets";

/// _idPattern is what [newAssetId] generates: sixteen letters and digits.
///
/// Checked before an id is ever joined onto a path. These ids are generated
/// rather than typed, so this is not where an attack would come from -- but an
/// id that reached here from a saved document is text from disk, and text from
/// disk becoming part of a path is exactly the shape of a mistake worth
/// refusing to make.
final _idPattern = RegExp(r"^[a-zA-Z0-9]{16}$");

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
  static Future<String> _dir({bool create = false}) async {
    var dir = path.join(await CanvasStorage.libraryDir(), _dirName);
    if (create) await Directory(dir).create(recursive: true);
    return dir;
  }

  static Future<String?> _pathFor(String id, {bool create = false}) async {
    if (!_idPattern.hasMatch(id)) return null;
    return path.join(await _dir(create: create), id);
  }

  /// save writes one picture and returns its id, or null when it could not be
  /// stored.
  static Future<String?> save(List<int> bytes) async {
    if (bytes.isEmpty || bytes.length > maxAssetBytes) return null;
    var id = newAssetId();
    var file = await _pathFor(id, create: true);
    if (file == null) return null;
    try {
      await File(file).writeAsBytes(bytes, flush: true);
      return id;
    } catch (_) {
      return null;
    }
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
