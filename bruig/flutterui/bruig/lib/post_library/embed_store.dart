import 'dart:io';

import 'package:bruig/post_library/post_storage.dart';
import 'package:path/path.dart' as path;

// embed_store.dart keeps the pictures a draft refers to.
//
// A post being written does not carry its images in its text. It carries
// references -- "data=[content abc123]" -- into a map that, until this file
// existed, lived only in memory. So a draft saved with a picture in it came
// back after a restart with the reference intact and nothing behind it: the
// reported "missing embed image", and the image genuinely gone.
//
// The pictures are written beside the library instead, in a folder the
// library itself cannot see (PostStorage.list skips anything beginning with
// a dot). Beside rather than inside the .md, because inlining the base64
// would turn a two-megabyte photograph into a three-megabyte text file that
// the speller, the preview and the size estimate all walk on every keystroke.
//
// Keyed by the reference's own id, so a draft can be renamed or moved
// between folders without its pictures having to follow it.

/// _dirName is the folder inside the library. The leading dot is what keeps
/// it out of the library listing.
const _dirName = ".embeds";

/// _idPattern is what trackEmbed generates: twelve letters and digits.
///
/// Checked before an id is ever joined onto a path. These ids are generated
/// rather than typed, so this is not where an attack would come from -- but
/// an id that reached here from a draft file is text from disk, and text
/// from disk becoming part of a path is exactly the shape of a mistake worth
/// refusing to make.
final _idPattern = RegExp(r"^[a-zA-Z0-9]{12}$");

/// _reference matches an embed's reference to its stored data.
final _reference = RegExp(r"data=\[content ([a-zA-Z0-9]{12})\]");

/// EmbedStore reads and writes the pictures a draft refers to.
class EmbedStore {
  /// _dir names the folder, creating it only when something is about to be
  /// written there.
  ///
  /// Reading and sweeping must not create it. They run in the background --
  /// the sweep is deliberately not awaited -- and a directory conjured up
  /// after the thing above it has been taken away is a directory nobody
  /// asked for. It showed up first as a test failing to delete its own
  /// temporary folder, "Directory not empty", on whichever test the race
  /// happened to land on.
  static Future<String> _dir({bool create = false}) async {
    var dir = path.join(await PostStorage.libraryDir(), _dirName);
    if (create) await Directory(dir).create(recursive: true);
    return dir;
  }

  static Future<String?> _pathFor(String id, {bool create = false}) async {
    if (!_idPattern.hasMatch(id)) return null;
    return path.join(await _dir(create: create), id);
  }

  /// idsIn returns every embed id [content] refers to.
  static Set<String> idsIn(String content) =>
      _reference.allMatches(content).map((m) => m.group(1)!).toSet();

  /// save writes one embed's data. Failing is not fatal: the picture is
  /// still in memory and the post can still be published, so the cost is
  /// that it will not survive a restart.
  static Future<void> save(String id, String data) async {
    var file = await _pathFor(id, create: true);
    if (file == null) return;
    try {
      await File(file).writeAsString(data, flush: true);
    } catch (_) {
      // A full disk, or a library directory that has gone away underneath.
    }
  }

  /// load returns one embed's data, or null when it is not there.
  static Future<String?> load(String id) async {
    var file = await _pathFor(id);
    if (file == null) return null;
    try {
      return await File(file).readAsString();
    } catch (_) {
      return null;
    }
  }

  /// loadFor returns the data for every embed [content] refers to, leaving
  /// out any that are missing.
  ///
  /// A missing one is not an error to report. A draft written before this
  /// file existed refers to pictures that were never stored anywhere, and
  /// there is nothing to be done about it now beyond not pretending
  /// otherwise -- the embed shows as unresolved, which is the truth.
  static Future<Map<String, String>> loadFor(String content) async {
    var out = <String, String>{};
    for (var id in idsIn(content)) {
      var data = await load(id);
      if (data != null) out[id] = data;
    }
    return out;
  }

  /// sweep deletes stored embeds that no draft refers to any more.
  ///
  /// [liveIds] has to be every id in the whole library plus whatever is in
  /// the composer, because one picture can be referred to from more than one
  /// draft -- a post duplicated, or text pasted between two of them -- and
  /// deleting it while a second draft still points at it would break that
  /// draft to tidy up after the first.
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
