import 'dart:io';

import 'package:bruig/config.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// canvas_storage.dart is the whole filesystem side of the canvas library:
// JSON documents in plain folders under "<appDataDir>/Canvas".
//
// Deliberately the same shape as the post library next door (see
// writing_tools/post_library/post_storage.dart) -- one level of folders, a
// hidden order file, names sanitised down to a known-safe set -- because a
// reader who has learned how saved posts behave should not have to learn a
// second thing for saved canvases. The differences are only the extension and
// the fact that a canvas carries pictures, which live in a sibling asset
// store.
//
// Written straight from Dart, like themes, palettes and posts. It is not a
// plugin capability and could not be: a plugin runs with no filesystem, which
// is the whole reason installing one is safe.

/// _libraryDirName is the folder inside the app data directory, beside
/// downloads, palettes, themes and my-posts.
const _libraryDirName = "Canvas";

/// canvasPicturesFolder is where the pictures live, inside the library.
///
/// Named here rather than only in canvas_assets.dart because the listing has
/// to leave it out: it is a real, visible folder so that somebody can open it
/// and see what is in it, which means it would otherwise appear as a canvas
/// folder of its own.
const canvasPicturesFolder = "Pictures";

/// canvasExtension is what a saved canvas is called on disk.
///
/// A distinct extension rather than ".json" so that the library listing does
/// not have to open a file to know whether it belongs here, and so that a
/// canvas exported out of the app is recognisable when it comes back.
const canvasExtension = ".bcanvas";

/// _orderFile keeps a folder's chosen order, hidden from the listing by its
/// leading dot -- the same arrangement, and for the same reasons, as the post
/// library's.
const _orderFile = ".order";

/// maxNameLength bounds a folder or document name, well under what any
/// filesystem allows, because the name also has to fit in a sidebar row.
const int maxNameLength = 64;

/// CanvasEntry is one row of the library.
class CanvasEntry {
  /// name is what the user sees and typed. For a document this is the
  /// filename without its extension.
  final String name;

  /// folder is the folder this lives in, or "" for the top level. Never a
  /// path: the library is one level deep.
  final String folder;

  final bool isFolder;
  final DateTime? modified;
  final int? size;

  const CanvasEntry({
    required this.name,
    required this.folder,
    required this.isFolder,
    this.modified,
    this.size,
  });
}

/// CanvasStorage reads and writes the library.
class CanvasStorage {
  /// rootOverride replaces the app data directory, for tests.
  ///
  /// A seam rather than a mock of path_provider: what the tests are for is
  /// proving that a name from a text field cannot write outside the library,
  /// and that is worth checking against a real directory rather than a stubbed
  /// filesystem that would agree with whatever the code did.
  @visibleForTesting
  static String? rootOverride;

  /// liveAssetIds is every stored picture that some saved canvas still uses.
  ///
  /// Every folder and every document, because one picture can be used by more
  /// than one canvas -- a document duplicated, or an element copied between two
  /// of them -- and a sweep that only looked at the open one would delete a
  /// picture another document is still showing.
  static Future<Set<String>> liveAssetIds() async {
    var live = <String>{};
    // The top level, and then each folder in it. The library is one level
    // deep, the same as the post library's.
    var pending = <String>[""];
    for (var entry in await list("")) {
      if (entry.isFolder) pending.add(entry.name);
    }

    for (var folder in pending) {
      for (var entry in await list(folder)) {
        if (entry.isFolder) continue;
        var document = await load(folder, entry.name);
        if (document != null) live.addAll(document.assetIds);
      }
    }
    return live;
  }

  /// libraryDir is `<appDataDir>/Canvas`, created on first use.
  static Future<String> libraryDir() async {
    var root = rootOverride ?? await defaultAppDataDir();
    var dir = path.join(root, _libraryDirName);
    await Directory(dir).create(recursive: true);
    return dir;
  }

  /// sanitizeName reduces what the user typed to something safe as a single
  /// path segment, or returns null if nothing usable is left.
  ///
  /// This is the security boundary of the feature. Every name reaching the
  /// filesystem comes from a text field, and a name like "../../config" or one
  /// with a separator in it would write wherever it pleased. Rather than
  /// blacklisting the dangerous forms -- there are always more -- this keeps a
  /// known-safe set and drops everything else.
  static String? sanitizeName(String raw) {
    var out = StringBuffer();
    for (var rune in raw.trim().runes) {
      var c = String.fromCharCode(rune);
      var ok = (rune >= 0x30 && rune <= 0x39) ||
          (rune >= 0x41 && rune <= 0x5A) ||
          (rune >= 0x61 && rune <= 0x7A) ||
          c == " " ||
          c == "-" ||
          c == "_" ||
          c == "(" ||
          c == ")";
      out.write(ok ? c : "-");
    }

    var name = out
        .toString()
        .replaceAll(RegExp(r"-{2,}"), "-")
        .replaceAll(RegExp(r"\s{2,}"), " ")
        .trim();
    while (name.startsWith(".") || name.startsWith("-")) {
      name = name.substring(1).trim();
    }
    if (name.length > maxNameLength) name = name.substring(0, maxNameLength);
    name = name.trim();
    return name.isEmpty ? null : name;
  }

  /// _dirFor resolves a folder name to a directory, refusing anything the
  /// sanitiser would not have produced.
  ///
  /// Checked here as well as at the point a name is chosen, because a folder
  /// name also arrives from the saved "which folder was open" preference and
  /// from a document's own path -- neither of which went through a text field
  /// on this run.
  static Future<String?> _dirFor(String folder) async {
    var root = await libraryDir();
    if (folder.isEmpty) return root;
    if (sanitizeName(folder) != folder) return null;
    return path.join(root, folder);
  }

  static Future<String?> pathFor(String folder, String name) async {
    var dir = await _dirFor(folder);
    if (dir == null || sanitizeName(name) != name) return null;
    return path.join(dir, "$name$canvasExtension");
  }

  /// list returns a folder's contents: its subfolders when at the top level,
  /// then its documents, in the saved order and alphabetically after it.
  static Future<List<CanvasEntry>> list(String folder) async {
    var dir = await _dirFor(folder);
    if (dir == null) return [];

    var folders = <CanvasEntry>[];
    var documents = <CanvasEntry>[];
    try {
      await for (var entry in Directory(dir).list(followLinks: false)) {
        var base = path.basename(entry.path);
        if (base.startsWith(".")) continue;
        // The picture store is a real folder now, so that it can be opened and
        // looked at -- which means the listing has to leave it out by name
        // rather than relying on it being hidden.
        if (base == canvasPicturesFolder) continue;

        if (entry is Directory) {
          // One level only, so subfolders are listed at the top and never
          // inside one. A tree would need a breadcrumb, a move and a recursive
          // delete to be worth having, and this needs none of those.
          if (folder.isEmpty) {
            folders.add(CanvasEntry(name: base, folder: "", isFolder: true));
          }
          continue;
        }
        if (entry is! File || !base.endsWith(canvasExtension)) continue;

        var stat = await entry.stat();
        documents.add(CanvasEntry(
          name: base.substring(0, base.length - canvasExtension.length),
          folder: folder,
          isFolder: false,
          modified: stat.modified,
          size: stat.size,
        ));
      }
    } catch (_) {
      return [];
    }

    folders
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    documents
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    var order = await _readOrder(dir);
    if (order.isNotEmpty) {
      // Names rather than positions, so a file renamed or deleted outside the
      // app drops out of the order instead of shifting everything after it.
      // Anything the order does not mention follows what it does.
      var byName = {for (var d in documents) d.name: d};
      var ordered = <CanvasEntry>[];
      for (var name in order) {
        var entry = byName.remove(name);
        if (entry != null) ordered.add(entry);
      }
      documents = [
        ...ordered,
        ...documents.where((d) => byName.containsKey(d.name))
      ];
    }

    return [...folders, ...documents];
  }

  static Future<List<String>> _readOrder(String dir) async {
    try {
      var file = File(path.join(dir, _orderFile));
      if (!await file.exists()) return [];
      return (await file.readAsLines())
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveOrder(String folder, List<String> names) async {
    var dir = await _dirFor(folder);
    if (dir == null) return;
    try {
      await File(path.join(dir, _orderFile))
          .writeAsString("${names.join("\n")}\n", flush: true);
    } catch (exception) {
      debugPrint("Unable to save the canvas order: $exception");
    }
  }

  /// load reads one document, or null when it is missing or unreadable.
  ///
  /// Null rather than an exception, because the caller's response is the same
  /// either way -- say so and leave the file alone. See CanvasDocument.decode
  /// on why a document that will not parse must never be overwritten.
  static Future<CanvasDocument?> load(String folder, String name) async {
    var file = await pathFor(folder, name);
    if (file == null) return null;
    try {
      return CanvasDocument.decode(await File(file).readAsString());
    } catch (_) {
      return null;
    }
  }

  /// save writes a document, creating its folder if it does not exist yet.
  ///
  /// Returns whether it was written. The name is sanitised by the caller
  /// before it gets here; this refuses rather than corrects, so a save that
  /// would have gone somewhere unexpected does not silently go somewhere else
  /// instead.
  static Future<bool> save(
      String folder, String name, CanvasDocument document) async {
    var dir = await _dirFor(folder);
    if (dir == null || sanitizeName(name) != name) return false;
    try {
      await Directory(dir).create(recursive: true);
      // Written to a temporary file and renamed, because a save that is
      // interrupted halfway -- the app quitting, the disk filling -- would
      // otherwise leave a truncated document where a good one was. The rename
      // is atomic within a directory: either the old file or the new one, and
      // never half of either.
      var target = path.join(dir, "$name$canvasExtension");
      var temp = File("$target.tmp");
      await temp.writeAsString(document.encode(), flush: true);
      await temp.rename(target);
      return true;
    } catch (exception) {
      debugPrint("Unable to save the canvas $name: $exception");
      return false;
    }
  }

  static Future<bool> exists(String folder, String name) async {
    var file = await pathFor(folder, name);
    return file != null && await File(file).exists();
  }

  static Future<bool> delete(String folder, String name) async {
    var file = await pathFor(folder, name);
    if (file == null) return false;
    try {
      await File(file).delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> rename(String folder, String from, String to) async {
    var source = await pathFor(folder, from);
    var target = await pathFor(folder, to);
    if (source == null || target == null) return false;
    // Refuses to write over an existing document. Renaming onto a name already
    // in use is a mistake, not an instruction, and there is nothing to undo it
    // with.
    if (await File(target).exists()) return false;
    try {
      await File(source).rename(target);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> createFolder(String name) async {
    var clean = sanitizeName(name);
    if (clean == null) return false;
    try {
      await Directory(path.join(await libraryDir(), clean))
          .create(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// deleteFolder removes a folder and everything in it, and refuses when it
  /// still holds documents unless [force] says otherwise.
  ///
  /// The refusal is the default because a folder of saved work is exactly the
  /// thing there is no undo for. The caller counts what is inside and says so
  /// before asking again.
  static Future<bool> deleteFolder(String name, {bool force = false}) async {
    var dir = await _dirFor(name);
    if (dir == null || name.isEmpty) return false;
    try {
      var target = Directory(dir);
      if (!await target.exists()) return false;
      if (!force) {
        var contents = await list(name);
        if (contents.isNotEmpty) return false;
      }
      await target.delete(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// uniqueName returns [wanted], or the first "wanted 2", "wanted 3" that is
  /// free. Used by Duplicate and by Save As, where refusing would be a dead
  /// end rather than a safeguard.
  static Future<String> uniqueName(String folder, String wanted) async {
    var clean = sanitizeName(wanted) ?? "Canvas";
    if (!await exists(folder, clean)) return clean;
    for (var i = 2; i < 1000; i++) {
      var candidate = sanitizeName("$clean $i");
      if (candidate == null) break;
      if (!await exists(folder, candidate)) return candidate;
    }
    return clean;
  }
}
