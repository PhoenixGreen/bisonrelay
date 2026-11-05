import 'dart:convert';
import 'dart:io';

import 'package:bruig/config.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:flutter/foundation.dart';
import 'package:bruig/plugin_system/canvas/storage/character_designs.dart';
import 'package:path/path.dart' as path;

// canvas_storage.dart is the whole filesystem side of the canvas library:
// JSON documents in plain folders under "<appDataDir>/Canvas".
//
// The same shape as the post library (see
// writing_tools/post_library/post_storage.dart): one level of folders, a
// hidden order file, names sanitised down to a known-safe set, so saved
// canvases behave as saved posts do. Written straight from Dart: a plugin
// has no filesystem, which is why installing one is safe.

/// _libraryDirName is the folder inside the app data directory, beside
/// downloads, palettes, themes and my-posts.
const _libraryDirName = "Canvas";

/// canvasPicturesFolder is where the pictures live, inside the library.
/// Named here because the listing has to leave it out: it is a real, visible
/// folder, which would otherwise show as a folder of canvases.
const canvasPicturesFolder = "Pictures";

/// canvasAudioFolder and canvasVideoFolder are where sounds and videos live,
/// beside the pictures and left out of the listing for the same reason. See
/// CanvasMedia.
const canvasAudioFolder = "Audio";
const canvasVideoFolder = "Videos";

/// canvasVectorFolder is where vector drawings live -- .svg files, kept apart
/// from the pictures because a drawing is edited point by point and a
/// picture is not. See VectorElement.
const canvasVectorFolder = "Vectors";

/// canvasModelFolder is where imported 3D models live -- .glb and .gltf
/// files. See CanvasMedia.
const canvasModelFolder = "Models";

/// canvasVoicesFolder, canvasSoundBankFolder and the rest are the folders
/// things are downloaded to, the first time they are wanted: the voices
/// speech is made with (kokoro_speech.dart, qwen_speech.dart), the
/// instruments' sound bank (part_render.dart) and the VRoid characters
/// (vroid_assets.dart).
const canvasVoicesFolder = "voices";
const canvasSoundBankFolder = "soundbanks";
const canvasVroidFolder = "VRoid";

/// isCanvasAppFolder is whether [name] is one of the folders the app keeps
/// its own things in at the top of the library. None is listed with the
/// documents, and no folder of documents can take one's name. Without
/// regard to case, as the file system on a Mac has none.
bool isCanvasAppFolder(String name) => _appFolders.contains(name.toLowerCase());

final _appFolders = {
  for (final f in [
    canvasPicturesFolder,
    canvasAudioFolder,
    canvasVideoFolder,
    canvasVectorFolder,
    canvasModelFolder,
    canvasVoicesFolder,
    canvasSoundBankFolder,
    canvasVroidFolder,
    canvasCharacter3dFolder,
  ])
    f.toLowerCase(),
};

/// canvasExtension is what a saved canvas is called on disk: its own
/// extension rather than ".json", so the listing need not open a file to
/// know it, and an exported canvas is recognisable when it comes back.
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

/// inTestsUnaimed is whether this is a test that has not said where its
/// library is: the real one, and what is downloaded on this machine, is not
/// looked in.
bool get inTestsUnaimed =>
    Platform.environment.containsKey("FLUTTER_TEST") &&
    !CanvasStorage.overridden;

/// writeWhole writes [bytes] to [file] by way of a file beside it, renamed
/// over it: an interrupted write leaves the old file or none, never half of
/// one, which for a file named by its content would be kept for ever.
Future<void> writeWhole(String file, List<int> bytes) async {
  var temp = File("$file.tmp");
  await temp.writeAsBytes(bytes, flush: true);
  await temp.rename(file);
}

/// writeWholeText is [writeWhole] for text.
Future<void> writeWholeText(String file, String text) =>
    writeWhole(file, utf8.encode(text));

/// CanvasStorage reads and writes the library.
class CanvasStorage {
  /// rootOverride replaces the app data directory, for tests: a real
  /// directory rather than a mocked filesystem, to prove that a name from a
  /// text field cannot write outside the library.
  @visibleForTesting
  static String? rootOverride;

  /// overridden is whether a test has said where the library is.
  static bool get overridden => rootOverride != null;

  /// liveAssetIds is every stored picture that some saved canvas still uses:
  /// every folder and document, since one picture can be used by several
  /// canvases -- and the 3D characters' decals.
  static Future<Set<String>> liveAssetIds() async =>
      {...(await liveIds()).$1, ...await CharacterDesigns.pictureIds()};

  /// liveMediaIds is every stored sound or video that some saved canvas still
  /// uses -- [liveAssetIds] for the media store.
  static Future<Set<String>> liveMediaIds() async =>
      {...(await liveIds()).$2, ...await CharacterDesigns.vectorIds()};

  /// liveIds is every saved canvas's pictures and media, in one walk of the
  /// library (one level deep, as the post library is).
  ///
  /// A document is read only when it has changed since it was last read --
  /// by its modified time and size -- and then off the editor's isolate: a
  /// tidy after every save once read every canvas whole, twice, in the
  /// middle of editing. A zip bundle is not a document and is left alone.
  static Future<(Set<String>, Set<String>)> liveIds() async {
    var assets = <String>{}, media = <String>{};
    var folders = <String>[""];
    for (var entry in await list("")) {
      if (entry.isFolder) folders.add(entry.name);
    }
    var seen = <String>{};
    for (var folder in folders) {
      for (var entry in await list(folder)) {
        if (entry.isFolder) continue;
        var file = await pathFor(folder, entry.name);
        if (file == null) continue;
        seen.add(file);
        var ids = await _idsOf(file);
        if (ids == null) continue;
        assets.addAll(ids.$1);
        media.addAll(ids.$2);
      }
    }
    _ids.removeWhere((file, _) => !seen.contains(file));
    return (assets, media);
  }

  /// _ids is each document's pictures and media as last read, with the
  /// modified time and size they were read at.
  static final Map<String, (DateTime, int, Set<String>, Set<String>)> _ids =
      {};

  static Future<(Set<String>, Set<String>)?> _idsOf(String file) async {
    try {
      var stat = await File(file).stat();
      if (_ids[file] case (var at, var size, var a, var m)
          when at == stat.modified && size == stat.size) {
        return (a, m);
      }
      var head = await File(file).openRead(0, 2).first;
      if (head.length == 2 && head[0] == 0x50 && head[1] == 0x4b) return null;
      var text = await File(file).readAsString();
      var ids = await compute(_documentIds, text);
      if (ids == null) return null;
      _ids[file] = (stat.modified, stat.size, ids.$1, ids.$2);
      return ids;
    } catch (_) {
      return null;
    }
  }

  /// sharedDir is `<appDataDir>/shared`, beside the library and downloads:
  /// where a canvas published to Files > Shared is written, and written
  /// over when it is published again. Created on first use.
  static Future<String> sharedDir() async {
    var root = rootOverride ?? await defaultAppDataDir();
    var dir = path.join(root, sharedFilesDirName);
    await Directory(dir).create(recursive: true);
    return dir;
  }

  /// libraryDir is `<appDataDir>/Canvas`, created on first use.
  static Future<String> libraryDir() async {
    var root = rootOverride ?? await defaultAppDataDir();
    var dir = path.join(root, _libraryDirName);
    await Directory(dir).create(recursive: true);
    return dir;
  }

  /// speechTakesDir is where a Speech device's takes are kept until they are
  /// saved or put on the timeline: beside the library, not in it -- the
  /// Audio library is only what the reader keeps. A tidy deletes those no
  /// canvas has any more: see CanvasLibrary.tidy.
  static Future<String> speechTakesDir() async {
    var dir = path.join(await libraryDir(), ".speech-takes");
    await Directory(dir).create(recursive: true);
    return dir;
  }

  /// sanitizeName reduces what the user typed to something safe as a single
  /// path segment, or returns null if nothing usable is left.
  ///
  /// The security boundary of the feature: every name reaching the filesystem
  /// comes from a text field, and "../../config" or a separator would write
  /// anywhere. A known-safe set is kept and everything else dropped, rather
  /// than blacklisting dangerous forms.
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
  /// sanitiser would not have produced: a folder name also arrives from the
  /// saved "which folder was open" preference and from a document's path.
  static Future<String?> _dirFor(String folder) async {
    var root = await libraryDir();
    if (folder.isEmpty) return root;
    if (sanitizeName(folder) != folder || isCanvasAppFolder(folder)) return null;
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
        // The app's own folders are real ones, so they can be opened and
        // looked at; the listing leaves them out by name.
        if (isCanvasAppFolder(base)) continue;

        if (entry is Directory) {
          // One level only: subfolders are listed at the top and never
          // inside one.
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
    if (order.isEmpty) return [...folders, ...documents];

    // Names rather than positions, so a file renamed or deleted outside the
    // app drops out of the order instead of shifting everything after it.
    // Anything the order does not mention follows what it does, folders first,
    // which is where a listing with no order of its own puts them.
    var left = {
      for (var e in [...folders, ...documents]) orderKeyFor(e): e,
    };
    var ordered = <CanvasEntry>[];
    for (var key in order) {
      var entry = left.remove(key);
      if (entry != null) ordered.add(entry);
    }
    return [
      ...ordered,
      ...folders.where((f) => left.containsKey(orderKeyFor(f))),
      ...documents.where((d) => left.containsKey(orderKeyFor(d))),
    ];
  }

  /// orderKeyFor is how an entry is named in the order file. A folder is
  /// prefixed and a document is not: that tells them apart, so a folder and
  /// a canvas of the same name are two lines, and a bare name (as in older
  /// order files) still means a document.
  static String orderKeyFor(CanvasEntry entry) =>
      entry.isFolder ? "f:${entry.name}" : entry.name;

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

  /// saveOrder writes the order a listing should come back in. Takes the
  /// entries rather than names, so folders and documents cannot be confused
  /// (see [orderKeyFor]).
  static Future<void> saveOrder(
      String folder, List<CanvasEntry> entries) async {
    var dir = await _dirFor(folder);
    if (dir == null) return;
    try {
      var keys = [for (var e in entries) orderKeyFor(e)];
      await File(path.join(dir, _orderFile))
          .writeAsString("${keys.join("\n")}\n", flush: true);
    } catch (exception) {
      debugPrint("Unable to save the canvas order: $exception");
    }
  }

  /// keepPlace keeps a renamed or copied entry where its original was: the
  /// order is a list of names, and a name it does not mention goes to the
  /// end. [after] puts the new name directly after the old one and leaves the
  /// old one, which is a copy; without it the new name takes the old one's
  /// place, which is a rename. Nothing happens where there is no order file,
  /// since the listing is alphabetical then.
  static Future<void> keepPlace(String folder,
      {required String was, required String now, bool after = false}) async {
    var dir = await _dirFor(folder);
    if (dir == null) return;
    var order = await _readOrder(dir);
    var at = order.indexOf(was);
    if (at < 0) return;

    var next = [...order];
    if (after) {
      next.insert(at + 1, now);
    } else {
      next[at] = now;
    }
    try {
      await File(path.join(dir, _orderFile))
          .writeAsString("${next.join("\n")}\n", flush: true);
    } catch (exception) {
      debugPrint("Unable to save the canvas order: $exception");
    }
  }

  /// load reads one document, or null when it is missing or unreadable: the
  /// caller says so and leaves the file alone. See CanvasDocument.decode on
  /// why a document that will not parse must never be overwritten.
  static Future<CanvasDocument?> load(String folder, String name) async {
    var file = await pathFor(folder, name);
    if (file == null) return null;
    try {
      return CanvasDocument.decode(await File(file).readAsString());
    } catch (_) {
      return null;
    }
  }

  /// save writes a document, creating its folder if it does not exist yet,
  /// and returns whether it was written. The name is sanitised by the caller;
  /// this refuses rather than corrects, so a save never silently goes
  /// somewhere else.
  static Future<bool> save(
      String folder, String name, CanvasDocument document) async {
    var dir = await _dirFor(folder);
    if (dir == null || sanitizeName(name) != name) return false;
    try {
      await Directory(dir).create(recursive: true);
      // Written to a temporary file and renamed (see writeWhole), so an
      // interrupted save never leaves a truncated document.
      await writeWholeText(
          path.join(dir, "$name$canvasExtension"), document.encode());
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
    // Refuses to write over an existing document: renaming onto a name in
    // use is a mistake, and there is nothing to undo it with.
    if (await File(target).exists()) return false;
    try {
      await File(source).rename(target);
      // Under its new name, in the place it was already in.
      await keepPlace(folder, was: from, now: to);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// move puts a canvas in another folder, keeping its name. Its own method
  /// rather than a rename, because the check differs: it refuses a name
  /// already in use *there*, the only way a move can destroy anything. The
  /// order file is not touched: the canvas drops out of the old order and
  /// lands at the end of the new folder.
  static Future<bool> move(String from, String name, String to) async {
    if (from == to) return true;
    var source = await pathFor(from, name);
    var target = await pathFor(to, name);
    if (source == null || target == null) return false;
    try {
      if (!await File(source).exists()) return false;
      if (await File(target).exists()) return false;
      await Directory(path.dirname(target)).create(recursive: true);
      await File(source).rename(target);
      return true;
    } catch (exception) {
      debugPrint("Unable to move $name: $exception");
      return false;
    }
  }

  /// folderNames is every folder in the library, in the order a listing shows
  /// them. For the "move to" list.
  static Future<List<String>> folderNames() async => [
        for (var entry in await list(""))
          if (entry.isFolder) entry.name,
      ];

  /// renameFolder renames a folder, with everything in it. Separate from
  /// [rename], which appends the document extension to both names. Refuses
  /// to write over anything that already exists, since that would merge two
  /// folders with no way back.
  static Future<bool> renameFolder(String from, String to) async {
    var clean = sanitizeName(to);
    if (clean == null || sanitizeName(from) != from) return false;
    if (isCanvasAppFolder(clean) || isCanvasAppFolder(from)) return false;
    try {
      var library = await libraryDir();
      var source = Directory(path.join(library, from));
      var target = Directory(path.join(library, clean));
      if (!await source.exists() || await target.exists()) return false;
      await source.rename(target.path);
      // A folder is ordered among the documents at the top level, under a
      // name of its own -- see [orderKeyFor].
      await keepPlace("", was: "f:$from", now: "f:$clean");
      return true;
    } catch (exception) {
      debugPrint("Unable to rename the folder $from: $exception");
      return false;
    }
  }

  static Future<bool> createFolder(String name) async {
    var clean = sanitizeName(name);
    if (clean == null || isCanvasAppFolder(clean)) return false;
    try {
      await Directory(path.join(await libraryDir(), clean))
          .create(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// deleteFolder removes a folder and everything in it, and refuses when it
  /// still holds documents unless [force] says otherwise: there is no undo,
  /// so the caller counts what is inside and asks again.
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

/// _documentIds is a saved document's pictures and media, read on an
/// isolate of its own: see CanvasStorage.liveIds.
(Set<String>, Set<String>)? _documentIds(String text) {
  var document = CanvasDocument.decode(text);
  if (document == null) return null;
  return (document.assetIds, document.mediaIds);
}
