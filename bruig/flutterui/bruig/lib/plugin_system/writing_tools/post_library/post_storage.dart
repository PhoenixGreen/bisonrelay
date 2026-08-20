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

/// _orderFile is where a folder's chosen order is kept.
///
/// One hidden file per folder, holding the names in the order they should be
/// shown. Hidden because the listing already skips dotted names, so it needs
/// no special case to stay out of the library it describes -- and because it
/// is the library's own bookkeeping rather than something the user wrote.
///
/// Names rather than positions, so a file renamed outside the app, or one
/// deleted while the app was closed, drops out of the order instead of
/// shifting everything after it. Anything the file does not mention is shown
/// after what it does, in the alphabetical order the library always used.
const _orderFile = ".order";

/// notesFolderName is the one folder in the library the app keeps for itself.
///
/// Notes taken around the app are written into it as ordinary Markdown
/// documents (see notes/note_storage.dart), which is the whole point: a note
/// is a post you have not decided to send, so it belongs in the same library,
/// in the same format, openable in the same composer. What it needs on top of
/// an ordinary folder is only that it stays put -- it is pinned to the bottom
/// of the top-level listing, and refuses to be renamed or deleted, because
/// notes are still being filed into it by name from elsewhere in the app and
/// a folder that could vanish under them would strand every one of them.
///
/// It is not created here. Nothing makes it until the first note is written,
/// so somebody who turns notes off never grows an empty folder they did not
/// ask for.
const notesFolderName = "Bison Relay Notes";

/// pagesFolderName and storeFolderName are the library's other two reserved
/// folders: the pages of the reader's own site, and the store's product
/// copy.
///
/// Reserved for the same reason the notes folder is, and only that reason.
/// Pages are written here and published from here, so the folder is named
/// from elsewhere in the app -- a folder that could be renamed or moved out
/// from under that would strand every page filed into it.
///
/// Like the notes folder, neither is created until something is put in one.
const pagesFolderName = "Pages";
const storeFolderName = "Store";

/// reservedFolderNames are the folders the app keeps for itself, in the
/// order they are pinned at the bottom of the top-level listing.
///
/// A list rather than a check per folder: the three behave identically, and
/// the rules below read once for all of them instead of growing a clause
/// each time one is added.
const List<String> reservedFolderNames = [
  notesFolderName,
  pagesFolderName,
  storeFolderName,
];

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

  /// isNotesFolder marks the notes folder specifically -- the one the notes
  /// feature files into. See [notesFolderName].
  bool get isNotesFolder => isFolder && name == notesFolderName;

  /// isReservedFolder marks any folder the app keeps for itself. The sidebar
  /// draws these differently and offers neither Rename nor Delete on them,
  /// and the listing pins them to the bottom. See [reservedFolderNames].
  bool get isReservedFolder =>
      isFolder && reservedFolderNames.contains(name);
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

    // The reserved folders are held out of the ordering entirely and put
    // back on the end, so they are always the last rows of the top level
    // however the rest has been arranged. They fill up on their own, without
    // anyone filing into them, and a folder that drifted up the list as it
    // grew would put itself between somebody and the writing they came here
    // for.
    //
    // Kept in reservedFolderNames' order rather than the order they were
    // read in, so the three do not swap places between listings.
    var reserved = [
      for (var name in reservedFolderNames)
        ...folders.where((f) => f.name == name),
    ];
    folders.removeWhere((f) => f.isReservedFolder);

    // Documents first. They are what the library is for -- a folder is
    // where some of them are kept -- and putting the folders on top meant
    // scrolling past the filing to reach the writing.
    var order = await readOrder(folder);
    var ordered = _inOrder(documents, order);

    // In the Pages folder the front page is pinned first, however the rest
    // has been arranged. It is the page every visitor lands on, so it is
    // the one to keep at hand -- the same reasoning that puts index.md at
    // the top of the served listing.
    if (folder == pagesFolderName) {
      var front = ordered.where(isFrontPageName).toList();
      ordered = [...front, ...ordered.where((e) => !isFrontPageName(e))];
    }

    return [
      ...ordered,
      ..._inOrder(folders, order),
      ...reserved,
    ];
  }

  /// isFrontPageName is whether a document in the Pages folder is the site's
  /// front page.
  ///
  /// Kept here rather than taken from page_documents.dart because storage
  /// must not depend on the publishing layer above it -- and because the
  /// rule is a name, not a state. Matches whatever a reader typed:
  /// "index", "Index" and "index.md" are all the front page.
  static bool isFrontPageName(PostEntry entry) {
    if (entry.isFolder) return false;
    var name = entry.name.toLowerCase().trim();
    if (name.endsWith(".md")) name = name.substring(0, name.length - 3);
    return name == "index";
  }

  /// _inOrder puts the entries the order file names first, in its order, and
  /// leaves everything else after them exactly as it was.
  static List<PostEntry> _inOrder(List<PostEntry> entries, List<String> order) {
    if (order.isEmpty) return entries;
    var byName = {for (var e in entries) e.name: e};
    var out = <PostEntry>[];
    for (var name in order) {
      var entry = byName.remove(name);
      if (entry != null) out.add(entry);
    }
    // What the order has never heard of -- a document made on another
    // machine, or before anything was moved -- keeps its alphabetical place
    // at the end rather than disappearing.
    for (var entry in entries) {
      if (byName.containsKey(entry.name)) out.add(entry);
    }
    return out;
  }

  /// readOrder is the names [folder] has been arranged into, or empty when
  /// nothing in it has been moved.
  static Future<List<String>> readOrder(String folder) async {
    var dirPath = await _resolve(folder, null);
    if (dirPath == null) return const [];
    var file = File(path.join(dirPath, _orderFile));
    if (!await file.exists()) return const [];
    try {
      return (await file.readAsLines())
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// writeOrder records the order [folder] should be shown in.
  static Future<bool> writeOrder(String folder, List<String> names) async {
    var dirPath = await _resolve(folder, null);
    if (dirPath == null) return false;
    try {
      await Directory(dirPath).create(recursive: true);
      await File(path.join(dirPath, _orderFile))
          .writeAsString(names.join("\n"));
      return true;
    } catch (_) {
      return false;
    }
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
  ///
  /// Refuses the reserved folders: things are still being filed into them by
  /// name from elsewhere in the app, and renaming one would send the next to
  /// a folder of the old name made fresh beside it.
  static Future<String?> rename(PostEntry entry, String newName) async {
    if (entry.isReservedFolder) return null;
    // The front page is named for what visitors ask for. Renaming it does
    // not rename the front page -- it takes the site's entrance away and
    // leaves an ordinary page behind. Refused here as well as hidden from
    // the menu, since the menu is not the only caller.
    if (entry.folder == pagesFolderName && isFrontPageName(entry)) return null;
    // ...and nothing else may be renamed onto one either, which would leave
    // two folders claiming the same reserved name.
    if (entry.isFolder &&
        reservedFolderNames.contains(sanitizeName(newName))) {
      return null;
    }

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

  /// move puts a document in another folder, "" being the top level.
  ///
  /// Only documents. The library is one level deep, so a folder has nowhere
  /// to move to.
  static Future<bool> move(PostEntry entry, String toFolder) async {
    if (entry.isFolder || entry.folder == toFolder) return false;
    var from = await _resolve(entry.folder, entry.name, asDocument: true);
    var to = await _resolve(toFolder, entry.name, asDocument: true);
    if (from == null || to == null) return false;

    var source = File(from);
    if (!await source.exists()) return false;
    // Refused rather than overwritten: a document of the same name in the
    // destination is somebody else's work.
    if (await File(to).exists()) return false;

    await Directory(path.dirname(to)).create(recursive: true);
    await source.rename(to);
    return true;
  }

  /// folderNames lists the folders a document could be moved into.
  ///
  /// Not the reserved notes folder. What is in there is a note *about*
  /// something -- a file, a chat, a post -- and a document dropped in beside
  /// them is about nothing, so it would sit there forever as a row no page
  /// ever opens. Moving the other way is allowed and is how a note is
  /// promoted to an ordinary post: it leaves the folder, and the page it came
  /// from starts a fresh note next time.
  static Future<List<String>> folderNames() async => [
        for (var entry in await list())
          if (entry.isFolder && !entry.isReservedFolder) entry.name,
      ];

  /// delete removes a document, or a folder and everything in it.
  ///
  /// A reserved folder is refused; what is inside one is not, so there is
  /// still a way to clear it out. See [reservedFolderNames].
  static Future<void> delete(PostEntry entry) async {
    if (entry.isReservedFolder) return;
    if (entry.folder == pagesFolderName && isFrontPageName(entry)) return;
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
