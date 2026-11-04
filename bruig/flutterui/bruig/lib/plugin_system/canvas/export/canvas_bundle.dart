import 'dart:io';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:flutter/foundation.dart';

// canvas_bundle.dart is a canvas with its pictures and media inside it.
//
// A saved .bcanvas holds only asset ids pointing at this machine's stores
// (see canvas_assets.dart), so a canvas sent elsewhere needs its files with
// it. A bundle is a zip of the document JSON plus those files: smaller than
// base64 in the JSON, and openable with any unzip tool.
//
// The ids are kept as they are. They are hashes of the files' bytes, so a
// picture the recipient already has is not stored twice.

/// _documentEntry is the document, added first so a listing shows it first.
const String _documentEntry = "canvas.json";

/// _pictureDir is where the pictures go, named by their asset ids.
const String _pictureDir = "pictures";

/// _mediaDir is where sounds and videos go, named by their CanvasMedia ids.
const String _mediaDir = "media";

/// bundleMime marks a canvas that carries its pictures. It saves as
/// .bcanvas, like a plain canvas.
const String bundleMime = "application/x-bruig-canvas";

/// looksLikeBundle is whether these bytes are a zip rather than plain JSON.
/// Sniffed, because both forms share the .bcanvas extension.
bool looksLikeBundle(List<int> bytes) =>
    bytes.length > 4 &&
    bytes[0] == 0x50 &&
    bytes[1] == 0x4B &&
    (bytes[2] == 0x03 || bytes[2] == 0x05) &&
    (bytes[3] == 0x04 || bytes[3] == 0x06);

/// packCanvas writes [document] and the pictures and media it refers to
/// into one file. An id [pictures] or [media] cannot load is left out
/// rather than failing the bundle: it is already missing on the sender's
/// screen.
Future<Uint8List> packCanvas(
  CanvasDocument document, {
  Future<List<int>?> Function(String id)? pictures,
  Future<List<int>?> Function(String id)? media,
}) async {
  var load = pictures ?? CanvasAssets.load;
  var loadMedia =
      media ?? (String id) => CanvasMedia.load(CanvasMedia.kindOf(id), id);
  var archive = Archive();
  archive.addFile(ArchiveFile.string(_documentEntry, document.encode()));

  for (var id in document.assetIds) {
    var bytes = await load(id);
    if (bytes == null) {
      debugPrint("The bundle is missing the picture $id");
      continue;
    }
    archive.addFile(
        ArchiveFile.bytes("$_pictureDir/$id", Uint8List.fromList(bytes)));
  }

  for (var id in document.mediaIds) {
    var bytes = await loadMedia(id);
    if (bytes == null) {
      debugPrint("The bundle is missing the media file $id");
      continue;
    }
    archive.addFile(
        ArchiveFile.bytes("$_mediaDir/$id", Uint8List.fromList(bytes)));
  }

  // Stored, not deflated: the large entries are already compressed, and
  // unpackCanvas's zip-bomb check relies on it.
  return Uint8List.fromList(ZipEncoder().encode(archive, level: 0));
}

/// CanvasBundle is an unpacked bundle.
class CanvasBundle {
  final CanvasDocument document;

  /// pictures is the asset id each picture was stored under, and its bytes.
  final Map<String, Uint8List> pictures;

  /// media is the sounds and videos, by media id.
  final Map<String, Uint8List> media;

  const CanvasBundle(this.document, this.pictures, [this.media = const {}]);
}

/// maxBundleBytes is the biggest canvas file read from a chat or a folder.
const int maxBundleBytes = 1 << 30;

/// unpackCanvasFile is [unpackCanvas] for [file], or null where it is
/// bigger than [maxBundleBytes], since it is read whole into memory.
Future<CanvasBundle?> unpackCanvasFile(File file) async {
  if (await file.length() > maxBundleBytes) return null;
  return unpackCanvas(await file.readAsBytes());
}

/// unpackCanvas reads a bundle or a plain .bcanvas from outside the
/// library; null when the bytes are neither.
Future<CanvasBundle?> unpackCanvas(List<int> bytes) async {
  try {
    if (!looksLikeBundle(bytes)) {
      var document = _received(utf8.decode(bytes));
      return document == null ? null : CanvasBundle(document, const {});
    }

    var archive = ZipDecoder().decodeBytes(bytes);
    // A bundle is stored, not compressed (see packCanvas), so its contents
    // are about its own size. Far more is a zip bomb, refused before
    // anything is inflated.
    var room = 64 * 1024 * 1024 + 4 * bytes.length;
    var declared = 0;
    for (var file in archive.files) {
      declared += file.size;
    }
    if (declared > room) return null;
    var entry = archive.findFile(_documentEntry);
    if (entry == null) return null;
    var document = _received(utf8.decode(entry.content));
    if (document == null) return null;

    var pictures = <String, Uint8List>{};
    var media = <String, Uint8List>{};
    for (var file in archive.files) {
      if (!file.isFile) continue;
      if (!file.name.startsWith("$_pictureDir/") &&
          !file.name.startsWith("$_mediaDir/")) {
        continue;
      }
      // Only the last part of the name is used, so "pictures/../../x" names
      // a picture "x". CanvasAssets.saveAs checks the id again before it
      // becomes a path.
      var id = file.name.split("/").last;
      if (id.isEmpty) continue;
      if (file.name.startsWith("$_mediaDir/")) {
        if (CanvasMedia.isId(id)) media[id] = Uint8List.fromList(file.content);
        continue;
      }
      pictures[id] = Uint8List.fromList(file.content);
    }
    var inflated = pictures.values.fold(0, (n, b) => n + b.length) +
        media.values.fold(0, (n, b) => n + b.length);
    if (inflated > room) return null;
    return CanvasBundle(document, pictures, media);
  } catch (exception) {
    debugPrint("Unable to read the canvas bundle: $exception");
    return null;
  }
}

/// _received is a canvas from elsewhere with every reference to a Writing
/// document removed (the words it last read are kept). Otherwise it would
/// read whatever document of that name the recipient has.
CanvasDocument? _received(String text) {
  Object? strip(Object? v) => switch (v) {
        Map<String, dynamic> m => {
            for (var e in m.entries)
              if (!(e.key == "document" && e.value is Map))
                e.key: strip(e.value),
          },
        List l => [for (var x in l) strip(x)],
        _ => v,
      };
  try {
    var json = finiteJson(strip(jsonDecode(text)));
    return json is Map<String, dynamic> ? CanvasDocument.fromJson(json) : null;
  } catch (_) {
    return null;
  }
}

/// storeBundlePictures puts a bundle's pictures and media into their
/// stores under the ids the document uses, and returns how many were
/// stored. The caller saves the document afterwards, so a canvas is never
/// listed before its files are there.
Future<int> storeBundlePictures(CanvasBundle bundle) async {
  var stored = 0;
  for (var entry in bundle.pictures.entries) {
    if (await CanvasAssets.saveAs(entry.key, entry.value)) stored++;
  }
  for (var entry in bundle.media.entries) {
    var kind = CanvasMedia.kindOf(entry.key);
    if (await CanvasMedia.saveBytes(kind, entry.key, entry.value)) stored++;
  }
  return stored;
}
