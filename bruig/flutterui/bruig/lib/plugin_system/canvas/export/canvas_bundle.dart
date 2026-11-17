import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:convert';

import 'package:archive/archive.dart' hide ZLibDecoder;
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
  archive
      .addFile(_stored(ArchiveFile.string(_documentEntry, document.encode())));

  for (var id in document.assetIds) {
    var bytes = await load(id);
    if (bytes == null) {
      debugPrint("The bundle is missing the picture $id");
      continue;
    }
    archive.addFile(_stored(
        ArchiveFile.bytes("$_pictureDir/$id", Uint8List.fromList(bytes))));
  }

  for (var id in document.mediaIds) {
    var bytes = await loadMedia(id);
    if (bytes == null) {
      debugPrint("The bundle is missing the media file $id");
      continue;
    }
    archive.addFile(_stored(
        ArchiveFile.bytes("$_mediaDir/$id", Uint8List.fromList(bytes))));
  }

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// _stored marks [file] to be stored as it is, not deflated: the large
/// entries are already compressed. (Level 0 was not that: it still wrote
/// each entry as deflate, in stored blocks.)
ArchiveFile _stored(ArchiveFile file) =>
    file..compression = CompressionType.none;

/// _TooBig is a bundle entry that inflated past the room left for it.
class _TooBig implements Exception {}

/// _Capped gathers inflated bytes, refusing more than [cap] of them.
class _Capped implements Sink<List<int>> {
  final int cap;
  final _bytes = BytesBuilder(copy: false);
  _Capped(this.cap);

  @override
  void add(List<int> chunk) {
    if (_bytes.length + chunk.length > cap) throw _TooBig();
    _bytes.add(chunk);
  }

  @override
  void close() {}

  Uint8List take() => _bytes.takeBytes();
}

/// _contentOf is [file]'s contents, no more than [left] bytes of them, or
/// null where there are more, or where it is packed some way a bundle never
/// is. A zip names each file's size, but that is what the sender wrote: the
/// library inflates a deflated file to whatever it holds, so a few megabytes
/// can be gigabytes. Here the bytes are counted as they come.
Uint8List? _contentOf(ArchiveFile file, int left) {
  var raw = file.rawContent;
  if (raw is! ZipFile || left < 0) return null;
  var packed = raw.getStream(decompress: false).toUint8List();
  switch (raw.compressionMethod) {
    case CompressionType.none:
      return packed.length <= left ? packed : null;
    case CompressionType.deflate:
      var out = _Capped(left);
      try {
        var sink = ZLibDecoder(raw: true).startChunkedConversion(out);
        const step = 1 << 16;
        for (var at = 0; at < packed.length; at += step) {
          sink.add(Uint8List.sublistView(packed, at,
              at + step > packed.length ? packed.length : at + step));
        }
        sink.close();
      } on _TooBig {
        return null;
      }
      return out.take();
    default:
      return null;
  }
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

/// unpackLimit is how long taking a received canvas apart may take.
const unpackLimit = Duration(minutes: 2);

/// unpackCanvasFile is [unpackCanvas] for [file], or null where it is
/// bigger than [maxBundleBytes], since it is read whole into memory, or
/// where it takes longer than [limit].
Future<CanvasBundle?> unpackCanvasFile(File file,
    {Duration limit = unpackLimit}) async {
  if (await file.length() > maxBundleBytes) return null;
  // Read and taken apart on an isolate of its own: a bundle can be a
  // gigabyte, and the whole app waited for it -- a canvas previewed in a
  // chat froze the chat. One that runs over is killed rather than left
  // running: a crafted canvas must not hold a core and its memory for as
  // long as it likes (security review, 2026-11-17).
  var port = ReceivePort();
  Isolate? isolate;
  try {
    isolate = await Isolate.spawn(_unpackIn, (port.sendPort, file.path),
        onExit: port.sendPort, onError: port.sendPort);
    var answer = await port.first.timeout(limit, onTimeout: () => null);
    return answer is CanvasBundle ? answer : null;
  } catch (exception) {
    debugPrint("Unable to read the canvas file: $exception");
    return null;
  } finally {
    isolate?.kill(priority: Isolate.immediate);
    port.close();
  }
}

Future<void> _unpackIn((SendPort, String) job) async {
  var (reply, at) = job;
  Isolate.exit(reply, await unpackCanvas(await File(at).readAsBytes()));
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
    // are about its own size. Far more is a zip bomb: each entry is
    // inflated against what is left of the room, and refused past it.
    var left = 64 * 1024 * 1024 + 4 * bytes.length;
    var entry = archive.findFile(_documentEntry);
    if (entry == null) return null;
    var json = _contentOf(entry, left);
    if (json == null) return null;
    left -= json.length;
    var document = _received(utf8.decode(json));
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
      var isMedia = file.name.startsWith("$_mediaDir/");
      if (isMedia && !CanvasMedia.isId(id)) continue;
      var content = _contentOf(file, left);
      if (content == null) return null;
      left -= content.length;
      (isMedia ? media : pictures)[id] = content;
    }
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
  // A Run panel's DartPad switch is not taken either: DartPad runs the code
  // on Google's site, telling it who reads, and that is the reader's to
  // choose (security review, 2026-11-17).
  Object? strip(Object? v) => switch (v) {
        Map<String, dynamic> m => {
            for (var e in m.entries)
              if (!(e.key == "document" && e.value is Map) &&
                  !(e.key == "dartpad" && e.value == true))
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
