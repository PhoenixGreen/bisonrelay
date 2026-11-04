import 'dart:io';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/components/md_elements.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/ui/picture_options_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;

// image_picking.dart is how a picture gets onto the canvas: through the
// app's own picture controls (width, quality, format), since a canvas is
// sent under the same payload limit as everything else Bison Relay sends.
// The bytes go to CanvasAssets, which is content-addressed: a picture used
// on eleven canvases is stored once.

/// _compressAbove is the size past which the size controls are offered on
/// the way in. Not a limit: publishing checks the real one against the
/// rendered PNG.
const int _compressAbove = 512 * 1024;

/// pictureSize is a stored picture's own width and height in pixels, decoded
/// from the bytes: CanvasImageStore answers null until it has loaded, which
/// is just when a picture has been chosen.
Future<Size?> pictureSize(String assetId) async {
  try {
    var bytes = await CanvasAssets.load(assetId);
    if (bytes == null) return null;
    var descriptor = await ui.ImageDescriptor.encoded(
        await ui.ImmutableBuffer.fromUint8List(Uint8List.fromList(bytes)));
    var size = Size(descriptor.width.toDouble(), descriptor.height.toDouble());
    descriptor.dispose();
    return size.isEmpty ? null : size;
  } catch (exception) {
    debugPrint("Unable to measure the canvas picture $assetId: $exception");
    return null;
  }
}

/// compressCanvasPicture runs a picture already on the canvas back through
/// the size controls (offered on the way in only past [_compressAbove]) and
/// stores the result. The new asset id, or null if nothing changed.
Future<String?> compressCanvasPicture(
    BuildContext context, String assetId) async {
  var bytes = await CanvasAssets.load(assetId);
  if (bytes == null) {
    if (context.mounted) _report(context, "That picture is no longer there.");
    return null;
  }

  if (!context.mounted) return null;
  var result = await showCanvasPictureOptions(context,
      original: Uint8List.fromList(bytes),
      mime: _mimeOf(bytes),
      title: "Picture size");
  if (result == null) return null;

  var id = await CanvasAssets.save(result);
  // Content-addressed, so compressing to exactly what was already there hands
  // back the same id. Nothing to do, and nothing to say about it.
  if (id == assetId) return null;
  // The smaller copy is in the library under the same name as the one it was
  // made from; the original stays there too, until it is removed.
  if (id != null) {
    await CanvasLibrary.addPicture(
        id, await CanvasLibrary.named(assetId) ?? "Picture", result);
  }
  return id;
}

/// _mimeOf sniffs the stored bytes, which is the only way to know: an asset id
/// is a hash and the file beside it has whatever extension save() worked out,
/// neither of which is a mime type.
String _mimeOf(List<int> bytes) =>
    lookupMimeType("", headerBytes: bytes.take(64).toList()) ?? "image/png";

/// pickCanvasImage asks for a picture, offers to compress it, stores it, and
/// returns its asset id, or null if cancelled. [vectors] offers drawings
/// (.svg) too, stored in the Vectors store, for where a drawing serves as a
/// picture (a text's icon, a table cell's badge); off for the Image element.
Future<String?> pickCanvasImage(BuildContext context,
    {bool vectors = true}) async {
  // The extensions rather than FileType.image, which leaves out SVG on macOS.
  var picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: [
      "png",
      "jpg",
      "jpeg",
      "gif",
      "webp",
      if (vectors) "svg",
    ],
    withData: false,
  );
  var chosen = picked?.files.singleOrNull?.path;
  if (chosen == null || chosen.trim().isEmpty) return null;

  try {
    var file = File(chosen.trim());
    var bytes = await file.readAsBytes();
    var mime = lookupMimeType(chosen) ?? "image/png";

    // A vector has no pixels to scale: the compressor would make it a bitmap.
    if (bytes.length > _compressAbove && !isSvgMime(mime)) {
      if (!context.mounted) return null;
      var result = await showCanvasPictureOptions(context,
          original: bytes, mime: mime, title: "Add a picture");
      // Cancelled there is cancelled altogether, not "store the big one".
      if (result == null) return null;
      bytes = result;
    }

    if (isSvgMime(mime)) {
      var vector = await CanvasMedia.saveVector(bytes);
      if (vector == null) {
        if (context.mounted) {
          _report(context, "That drawing is too large for a canvas.");
        }
        return null;
      }
      await CanvasLibrary.addVector(
          vector, path.basenameWithoutExtension(chosen.trim()));
      return vector;
    }

    var id = await CanvasAssets.save(bytes);
    if (id == null) {
      if (context.mounted) {
        _report(context, "That picture is too large for a canvas.");
      }
      return null;
    }
    // In the library from now on, whether or not anything keeps using it.
    await CanvasLibrary.addPicture(
        id, path.basenameWithoutExtension(chosen.trim()), bytes);
    return id;
  } catch (exception) {
    if (context.mounted) {
      _report(context, "Unable to read ${path.basename(chosen)}: $exception");
    } else {
      debugPrint("Unable to read ${path.basename(chosen)}: $exception");
    }
    return null;
  }
}

/// pickCanvasVector asks for a drawing (.svg), stores it with the drawings
/// and puts it in the library, and returns its id -- or null for none.
Future<String?> pickCanvasVector(BuildContext context) async {
  var picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ["svg"],
    withData: false,
  );
  var chosen = picked?.files.singleOrNull?.path;
  if (chosen == null || chosen.trim().isEmpty) return null;
  try {
    var bytes = await File(chosen.trim()).readAsBytes();
    if (!String.fromCharCodes(bytes.take(4096))
        .toLowerCase()
        .contains("<svg")) {
      if (context.mounted) {
        _report(context, "${path.basename(chosen)} is not a drawing.");
      }
      return null;
    }
    var id = await CanvasMedia.saveVector(bytes);
    if (id == null) {
      if (context.mounted) {
        _report(context, "That drawing is too large for a canvas.");
      }
      return null;
    }
    await CanvasLibrary.addVector(
        id, path.basenameWithoutExtension(chosen.trim()));
    return id;
  } catch (exception) {
    if (context.mounted) {
      _report(context, "Unable to read ${path.basename(chosen)}: $exception");
    }
    return null;
  }
}

/// _report says something went wrong, and does not itself go wrong: the
/// snackbar is looked up only now, and guarded, since a throw here from a
/// fire-and-forget callback would be swallowed and the button do nothing.
// ignore: use_build_context_synchronously
void _report(BuildContext context, String message) {
  debugPrint(message);
  if (!context.mounted) return;
  try {
    SnackBarModel.of(context).error(message);
  } catch (_) {
    // No snackbar here. The message is already in the log, and a picker that
    // fell over is not made better by falling over twice.
  }
}
