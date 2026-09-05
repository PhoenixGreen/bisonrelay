import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:flutter/foundation.dart';

// canvas_bundle.dart is a canvas with its pictures inside it.
//
// A saved .bcanvas is the document and nothing else: pictures live once in the
// asset store beside the library and the document holds their ids -- see
// canvas_assets.dart, which is the right arrangement for a canvas being worked
// on, and exactly the wrong one for a canvas being sent to somebody. The file
// arrived, opened, and had a grey placeholder where every photograph had been,
// because the ids pointed at a store on the sender's machine.
//
// So a bundle: a zip holding the same document JSON and a folder of the
// pictures it refers to. A zip rather than the pictures base64'd into the
// JSON, which was the other obvious answer -- base64 is a third larger, and
// the whole point of a bundle is that it travels. It is also a format anybody
// can open: a bundle that will not load into this app can still be taken apart
// with the thing every operating system already has.
//
// The ids inside are the sender's, and they are kept. They are hashes of the
// pictures' own bytes, so the same photograph in two canvases is the same id on
// every machine, and a bundle unpacked into a library that already holds one of
// its pictures adds nothing.

/// _documentEntry is the document, at the top so that anything listing the
/// archive shows what it is first.
const String _documentEntry = "canvas.json";

/// _pictureDir is where the pictures go, named by their asset ids.
const String _pictureDir = "pictures";

/// bundleMime marks a canvas that carries its pictures.
///
/// Its own type rather than application/zip, because what matters to whatever
/// receives it is that this is a canvas -- and it saves as .bcanvas either
/// way, since a reader has no reason to care which of the two forms their
/// canvas came in.
const String bundleMime = "application/x-bruig-canvas";

/// looksLikeBundle is whether these bytes are a zip rather than the plain
/// JSON a .bcanvas has always been.
///
/// Sniffed rather than taken from the file name, because both forms are saved
/// under the same extension on purpose: one kind of canvas file, which either
/// has its pictures with it or does not need any.
bool looksLikeBundle(List<int> bytes) =>
    bytes.length > 4 &&
    bytes[0] == 0x50 &&
    bytes[1] == 0x4B &&
    (bytes[2] == 0x03 || bytes[2] == 0x05) &&
    (bytes[3] == 0x04 || bytes[3] == 0x06);

/// packCanvas writes [document] and the pictures it refers to into one file.
///
/// [pictures] is asked for each id the document uses; one that comes back null
/// is left out rather than failing the whole bundle. A canvas that has lost a
/// picture already looks like that on the sender's screen, and refusing to
/// export it would strand the other nineteen.
Future<Uint8List> packCanvas(
  CanvasDocument document, {
  Future<List<int>?> Function(String id)? pictures,
}) async {
  var load = pictures ?? CanvasAssets.load;
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

  // Stored rather than deflated. Everything of any size in here is a PNG or a
  // JPEG, which are compressed already; deflating them again spends the time
  // and saves nothing, and the document itself is a few kilobytes.
  return Uint8List.fromList(ZipEncoder().encode(archive, level: 0));
}

/// CanvasBundle is what came out of one.
class CanvasBundle {
  final CanvasDocument document;

  /// pictures is the asset id each picture was stored under, and its bytes.
  final Map<String, Uint8List> pictures;

  const CanvasBundle(this.document, this.pictures);
}

/// unpackCanvas reads a bundle, or a plain .bcanvas, into a document and its
/// pictures.
///
/// Null when the bytes are neither. Both forms go through here so that
/// whatever opens a canvas from outside the library has one thing to call and
/// cannot get the two the wrong way round.
Future<CanvasBundle?> unpackCanvas(List<int> bytes) async {
  try {
    if (!looksLikeBundle(bytes)) {
      var document = CanvasDocument.decode(utf8.decode(bytes));
      return document == null ? null : CanvasBundle(document, const {});
    }

    var archive = ZipDecoder().decodeBytes(bytes);
    var entry = archive.findFile(_documentEntry);
    if (entry == null) return null;
    var document = CanvasDocument.decode(utf8.decode(entry.content));
    if (document == null) return null;

    var pictures = <String, Uint8List>{};
    for (var file in archive.files) {
      if (!file.isFile || !file.name.startsWith("$_pictureDir/")) continue;
      // Only the last part of the name is used, so a bundle carrying
      // "pictures/../../something" names a picture called "something" and
      // nothing else. The id is checked again by CanvasAssets.saveAs before
      // it becomes a path; this is the first of the two.
      var id = file.name.split("/").last;
      if (id.isEmpty) continue;
      pictures[id] = Uint8List.fromList(file.content);
    }
    return CanvasBundle(document, pictures);
  } catch (exception) {
    debugPrint("Unable to read the canvas bundle: $exception");
    return null;
  }
}

/// storeBundlePictures puts a bundle's pictures into the asset store, under
/// the ids the document already refers to them by.
///
/// Returns how many were stored. The document is saved by the caller, after
/// this, so a canvas is never listed before the pictures it needs are there.
Future<int> storeBundlePictures(CanvasBundle bundle) async {
  var stored = 0;
  for (var entry in bundle.pictures.entries) {
    if (await CanvasAssets.saveAs(entry.key, entry.value)) stored++;
  }
  return stored;
}
