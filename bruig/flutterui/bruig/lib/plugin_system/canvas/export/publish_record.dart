import 'dart:convert';
import 'dart:io';

import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// publish_record.dart remembers where a saved canvas has been published to.
//
// It exists so that a canvas can be *updated* rather than only sent. A pitch
// diagram put on a page and then corrected should replace what is on the page,
// and a shared file should be replaceable without the reader having to
// remember which of four similarly named files was the one they shared. So the
// destinations are written down, and the publish sheet offers Update and
// Unpublish for the ones it finds.
//
// Not written into the .bcanvas itself. A published-to record is about this
// machine -- a path on this disk, a file shared by this client -- and a canvas
// copied to another machine or sent to somebody else should arrive as a
// canvas, not as one claiming to be published somewhere it is not.
//
// One JSON file for the whole library rather than a sidecar per canvas: the
// records are tiny, the sheet wants to look one up before it has opened
// anything, and a directory of dotfiles shadowing the real documents is worse
// to explain than one file.

/// _fileName is the record file, hidden from the library listing by its
/// leading dot.
const _fileName = ".published.json";

/// PublishRecord is where one canvas has gone.
class PublishRecord {
  /// sharedPath is the file this canvas was written to for Files > Shared, or
  /// empty. Kept as the path rather than the share id because the path is what
  /// re-sharing an updated copy needs, and the id is discoverable from it.
  final String sharedPath;

  /// documentFolder and documentName are the post-library document this canvas
  /// was published into, so it can be embedded in a post or a page. Empty when
  /// it has not been.
  final String documentFolder;
  final String documentName;

  /// embedId is the picture the library document points at. Kept so an update
  /// can overwrite the same picture rather than leaving the old one behind and
  /// growing the embed store by a copy on every republish.
  final String embedId;

  /// format is what was published last -- "image/png", "image/gif" -- so the
  /// sheet can offer the same again without asking twice.
  final String format;

  final DateTime? publishedAt;

  const PublishRecord({
    this.sharedPath = "",
    this.documentFolder = "",
    this.documentName = "",
    this.embedId = "",
    this.format = "",
    this.publishedAt,
  });

  bool get isEmpty =>
      sharedPath.isEmpty && documentName.isEmpty;

  bool get hasShare => sharedPath.isNotEmpty;
  bool get hasDocument => documentName.isNotEmpty;

  PublishRecord copyWith({
    String? sharedPath,
    String? documentFolder,
    String? documentName,
    String? embedId,
    String? format,
    DateTime? publishedAt,
  }) =>
      PublishRecord(
        sharedPath: sharedPath ?? this.sharedPath,
        documentFolder: documentFolder ?? this.documentFolder,
        documentName: documentName ?? this.documentName,
        embedId: embedId ?? this.embedId,
        format: format ?? this.format,
        publishedAt: publishedAt ?? this.publishedAt,
      );

  Map<String, dynamic> toJson() => {
        if (sharedPath.isNotEmpty) "sharedPath": sharedPath,
        if (documentName.isNotEmpty) "documentFolder": documentFolder,
        if (documentName.isNotEmpty) "documentName": documentName,
        if (embedId.isNotEmpty) "embedId": embedId,
        if (format.isNotEmpty) "format": format,
        if (publishedAt != null)
          "publishedAt": publishedAt!.toIso8601String(),
      };

  factory PublishRecord.fromJson(Map<String, dynamic> json) => PublishRecord(
        sharedPath: json["sharedPath"] as String? ?? "",
        documentFolder: json["documentFolder"] as String? ?? "",
        documentName: json["documentName"] as String? ?? "",
        embedId: json["embedId"] as String? ?? "",
        format: json["format"] as String? ?? "",
        publishedAt: DateTime.tryParse(json["publishedAt"] as String? ?? ""),
      );
}

/// PublishRecords reads and writes the whole file.
class PublishRecords {
  PublishRecords._();

  /// key identifies one canvas. Folder and name rather than a generated id,
  /// because a canvas has no id of its own -- it is a file -- and renaming one
  /// losing its publish record is the honest outcome: the file at the old name
  /// is what was published, and there is nothing here that can tell a rename
  /// from a delete and a new document.
  static String key(String folder, String name) =>
      folder.isEmpty ? name : "$folder/$name";

  static Future<String> _path() async =>
      path.join(await CanvasStorage.libraryDir(), _fileName);

  static Future<Map<String, PublishRecord>> readAll() async {
    try {
      var file = File(await _path());
      if (!await file.exists()) return {};
      var json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return {};
      return {
        for (var entry in json.entries)
          if (entry.value is Map<String, dynamic>)
            entry.key:
                PublishRecord.fromJson(entry.value as Map<String, dynamic>),
      };
    } catch (_) {
      // An unreadable record file is not worth failing a publish over. The
      // worst case is being offered Publish where Update was expected.
      return {};
    }
  }

  static Future<PublishRecord?> read(String folder, String name) async =>
      (await readAll())[key(folder, name)];

  static Future<void> write(
      String folder, String name, PublishRecord record) async {
    var all = await readAll();
    if (record.isEmpty) {
      all.remove(key(folder, name));
    } else {
      all[key(folder, name)] = record;
    }
    try {
      await File(await _path()).writeAsString(
          const JsonEncoder.withIndent("  ")
              .convert({for (var e in all.entries) e.key: e.value.toJson()}),
          flush: true);
    } catch (exception) {
      debugPrint("Unable to save the canvas publish record: $exception");
    }
  }

  static Future<void> clear(String folder, String name) =>
      write(folder, name, const PublishRecord());
}
