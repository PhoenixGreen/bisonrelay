import 'dart:convert';
import 'dart:io';

import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// publish_record.dart remembers where a saved canvas has been published,
// so the publish sheet can offer Update and Unpublish rather than only a
// fresh send.
//
// Not written into the .bcanvas: the record is about this machine (a path
// on this disk, a file shared by this client), and a copied canvas should
// not claim to be published somewhere it is not. One JSON file serves the
// whole library, so the sheet can look a record up before opening anything.

/// _fileName is the record file, hidden from the library listing by its
/// leading dot.
const _fileName = ".published.json";

/// PublishRecord is where one canvas has gone.
class PublishRecord {
  /// sharedPath is the file this canvas was written to for Files > Shared, or
  /// empty. The path, not the share id, because re-sharing needs the path.
  final String sharedPath;

  /// documentFolder and documentName are the post-library document this
  /// canvas was published into, or empty.
  final String documentFolder;
  final String documentName;

  /// embedId is the picture the library document points at, so an update
  /// overwrites it rather than adding a copy to the embed store.
  final String embedId;

  /// format is the MIME type published last, offered again by the sheet.
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

  bool get isEmpty => sharedPath.isEmpty && documentName.isEmpty;

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
        if (publishedAt != null) "publishedAt": publishedAt!.toIso8601String(),
      };

  factory PublishRecord.fromJson(Map<String, dynamic> json) => PublishRecord(
        sharedPath: jsonStr(json["sharedPath"]) ?? "",
        documentFolder: jsonStr(json["documentFolder"]) ?? "",
        documentName: jsonStr(json["documentName"]) ?? "",
        embedId: jsonStr(json["embedId"]) ?? "",
        format: jsonStr(json["format"]) ?? "",
        publishedAt: DateTime.tryParse(jsonStr(json["publishedAt"]) ?? ""),
      );
}

/// PublishRecords reads and writes the whole file.
class PublishRecords {
  PublishRecords._();

  /// key identifies one canvas by folder and name, as a canvas has no id of
  /// its own. A renamed canvas therefore loses its record.
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
      // Not worth failing a publish over: the worst case is being offered
      // Publish where Update was expected.
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
      await writeWholeText(
          await _path(),
          const JsonEncoder.withIndent("  ")
              .convert({for (var e in all.entries) e.key: e.value.toJson()}));
    } catch (exception) {
      debugPrint("Unable to save the canvas publish record: $exception");
    }
  }

  static Future<void> clear(String folder, String name) =>
      write(folder, name, const PublishRecord());
}
