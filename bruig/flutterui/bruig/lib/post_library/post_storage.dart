import 'dart:io';

import 'package:bruig/config.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// post_storage.dart is the whole filesystem side of the saved-post library:
// plain Markdown files in plain folders under "<appDataDir>/my-posts".
//
// Written straight from Dart, as themes and palettes already are -- there is
// no reason for a file the user asked to save to make a round trip through
// the Go client. It is deliberately *not* a plugin capability either: a
// plugin runs with no filesystem and no network, and that sandbox is the
// whole reason installing one is safe. Handing it a file API would undo it.
//
// The format is the point. A ".md" file in a folder is readable by every
// Markdown editor there is, and stays readable if Bison Relay is never
// installed again. Nothing here writes an index, a manifest or a database:
// the directory listing is the library.

/// _libraryDirName is the folder inside the app data directory, beside
/// downloads, palettes, themes and logs.
const _libraryDirName = "my-posts";

const _extension = ".md";

/// maxNameLength bounds a folder or document name. Chosen well under the 255
/// bytes most filesystems allow, since the name is also what has to fit in a
/// sidebar row.
const int maxNameLength = 64;

/// PostEntry is one row of the library: a folder or a document.
class PostEntry {
  /// name is what the user sees and typed. For a document this is the
  /// filename without its ".md".
  final String name;

  /// folder is the folder this lives in, or "" for the top level. Never a
  /// path: the library is one level deep.
  final String folder;

  final bool isFolder;

  /// modified and size are shown in the list, and are null for a folder,
  /// whose own size means nothing to a reader.
  final DateTime? modified;
  final int? size;

  const PostEntry({
    required this.name,
    required this.folder,
    required this.isFolder,
    this.modified,
    this.size,
  });
}

/// PostStorage reads and writes the library.
///
/// One level of folders, deliberately. The user asked for folders holding
/// documents, and a tree would need a breadcrumb, a move operation and a
/// recursive delete to be worth having. This has none of those because it
/// needs none of them.
class PostStorage {
  /// rootOverride replaces the app data directory, for tests.
  ///
  /// A seam rather than a mock of path_provider: what these tests are for is
  /// proving that a name from a text field cannot write outside the library,
  /// and that is worth checking against a real directory rather than a
  /// stubbed filesystem that would happily agree with whatever the code did.
  @visibleForTesting
  static String? rootOverride;

  /// libraryDir is `<appDataDir>/my-posts`, created on first use.
  static Future<String> libraryDir() async {
    var root = rootOverride ?? await defaultAppDataDir();
    var dir = path.join(root, _libraryDirName);
    await Directory(dir).create(recursive: true);
    return dir;
  }

  /// sanitizeName reduces what the user typed to something that is safe as a
  /// single path segment, or returns null if nothing usable is left.
  ///
  /// This is the security boundary of the whole feature. Every name reaching
  /// the filesystem comes from a text field, and a name like "../../config"
  /// or one with a separator in it would write wherever it pleased. Rather
  /// than blacklisting the dangerous forms -- there are always more --
  /// this keeps a known-safe set and drops everything else.
  static String? sanitizeName(String raw) {
    var out = StringBuffer();
    for (var rune in raw.trim().runes) {
      var c = String.fromCharCode(rune);
      var ok = (rune >= 0x30 && rune <= 0x39) || // 0-9
          (rune >= 0x41 && rune <= 0x5A) || // A-Z
          (rune >= 0x61 && rune <= 0x7A) || // a-z
          c == " " ||
          c == "-" ||
          c == "_" ||
          c == "(" ||
          c == ")";
      out.write(ok ? c : "-");
    }

    // Collapse the runs the substitution above creates, so "a???b" is
    // "a-b" rather than "a---b".
    var name = out
        .toString()
        .replaceAll(RegExp(r"-{2,}"), "-")
        .replaceAll(RegExp(r"\s{2,}"), " ")
        .trim();
    // A leading dot would hide the file; a name of only dots and dashes is
    // not a name. Both are covered by trimming them off the ends.
    name = name.replaceAll(RegExp(r"^[-.\s]+|[-.\s]+$"), "");
    if (name.isEmpty) return null;
    if (name.length > maxNameLength) {
      name = name.substring(0, maxNameLength).trim();
    }
    return name.isEmpty ? null : name;
  }

  /// suggestName proposes a document name from the text being written: its
  /// first heading, or failing that its first few words.
  ///
  /// A suggestion and not a rule -- the name is confirmed in a dialog before
  /// anything is written, and never changes afterwards on its own. A file
  /// that renamed itself as the first line was edited would be a surprise
  /// every time.
  static String suggestName(String content) {
    for (var line in content.split("\n")) {
      var text = line.trim().replaceAll(RegExp(r"^#+\s*"), "").trim();
      if (text.isEmpty) continue;
      var words = text.split(RegExp(r"\s+")).take(8).join(" ");
      return sanitizeName(words) ?? "Untitled";
    }
    return "Untitled";
  }

  /// _resolve turns a folder and name into a path inside the library, or
  /// null if either is unusable.
  ///
  /// Both are sanitized here rather than being trusted from the caller, so
  /// there is one place to look to know that nothing escapes the library --
  /// and a second check costs nothing next to the cost of being wrong.
  static Future<String?> _resolve(String folder, String? name,
      {bool asDocument = false}) async {
    var root = await libraryDir();
    var dir = root;
    if (folder.isNotEmpty) {
      var safeFolder = sanitizeName(folder);
      if (safeFolder == null) return null;
      dir = path.join(root, safeFolder);
    }
    if (name == null) return dir;

    var safeName = sanitizeName(name);
    if (safeName == null) return null;
    return path.join(dir, asDocument ? "$safeName$_extension" : safeName);
  }

  /// list returns the contents of [folder], folders first and then documents,
  /// each alphabetically.
  ///
  /// Folders first because at the top level they are the structure and the
  /// loose documents are the exceptions; alphabetically because a list that
  /// reorders itself as files are saved is one nobody can build a memory of.
  static Future<List<PostEntry>> list([String folder = ""]) async {
    var dirPath = await _resolve(folder, null);
    if (dirPath == null) return const [];
    var dir = Directory(dirPath);
    if (!await dir.exists()) return const [];

    var folders = <PostEntry>[];
    var documents = <PostEntry>[];
    await for (var entry in dir.list(followLinks: false)) {
      var name = path.basename(entry.path);
      if (name.startsWith(".")) continue;

      if (entry is Directory) {
        // Only at the top level: the library is one deep, and a folder
        // inside a folder would be unreachable rather than merely unused.
        if (folder.isEmpty) {
          folders.add(PostEntry(name: name, folder: "", isFolder: true));
        }
        continue;
      }
      if (entry is! File || !name.endsWith(_extension)) continue;

      FileStat stat;
      try {
        stat = await entry.stat();
      } catch (_) {
        // A file that vanished between the listing and the stat; skipping it
        // is more useful than failing the whole list.
        continue;
      }
      documents.add(PostEntry(
        name: name.substring(0, name.length - _extension.length),
        folder: folder,
        isFolder: false,
        modified: stat.modified,
        size: stat.size,
      ));
    }

    int byName(PostEntry a, PostEntry b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    folders.sort(byName);
    documents.sort(byName);
    return [...folders, ...documents];
  }

  /// read returns a document's Markdown, or null if it is gone.
  static Future<String?> read(String folder, String name) async {
    var filePath = await _resolve(folder, name, asDocument: true);
    if (filePath == null) return null;
    var file = File(filePath);
    if (!await file.exists()) return null;
    try {
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  /// write saves [content], creating the folder if it does not exist.
  /// Returns the name actually written, which is the sanitized one.
  static Future<String?> write(
      String folder, String name, String content) async {
    var filePath = await _resolve(folder, name, asDocument: true);
    if (filePath == null) return null;
    await Directory(path.dirname(filePath)).create(recursive: true);
    await File(filePath).writeAsString(content, flush: true);
    return sanitizeName(name);
  }

  /// exists reports whether a document is already there, so a new one does
  /// not silently land on top of it.
  static Future<bool> exists(String folder, String name) async {
    var filePath = await _resolve(folder, name, asDocument: true);
    if (filePath == null) return false;
    return File(filePath).exists();
  }

  /// createFolder makes a top-level folder. Returns the name actually
  /// created.
  static Future<String?> createFolder(String name) async {
    var dirPath = await _resolve("", name);
    if (dirPath == null) return null;
    await Directory(dirPath).create(recursive: true);
    return sanitizeName(name);
  }

  /// rename moves a folder or document to a new name in the same place.
  static Future<String?> rename(PostEntry entry, String newName) async {
    var from =
        await _resolve(entry.folder, entry.name, asDocument: !entry.isFolder);
    var to = await _resolve(entry.folder, newName, asDocument: !entry.isFolder);
    if (from == null || to == null || from == to) return null;

    var source = entry.isFolder ? Directory(from) : File(from);
    if (!await source.exists()) return null;
    // Refused rather than merged or overwritten: renaming one document onto
    // another would destroy the second, and the user asked for neither.
    if (entry.isFolder
        ? await Directory(to).exists()
        : await File(to).exists()) {
      return null;
    }
    await source.rename(to);
    return sanitizeName(newName);
  }

  /// delete removes a document, or a folder and everything in it.
  static Future<void> delete(PostEntry entry) async {
    var target =
        await _resolve(entry.folder, entry.name, asDocument: !entry.isFolder);
    if (target == null) return;
    if (entry.isFolder) {
      var dir = Directory(target);
      if (await dir.exists()) await dir.delete(recursive: true);
      return;
    }
    var file = File(target);
    if (await file.exists()) await file.delete();
  }
}
