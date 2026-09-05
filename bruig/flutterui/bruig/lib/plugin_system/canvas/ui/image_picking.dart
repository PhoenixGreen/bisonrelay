import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/components/md_elements.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/ui/picture_options_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;

// image_picking.dart is how a picture gets onto the canvas.
//
// It goes through the app's own picture controls -- the same width, quality
// and format an embedded picture and a site's picture are offered -- rather
// than a second set written for here. A canvas is published into a chat, a
// post or a page, all of which have the same payload limit as everything else
// Bison Relay sends, so the question "how big should this be" has one answer
// and one place to decide it.
//
// The bytes are then handed to CanvasAssets, which is content-addressed: the
// same badge dropped onto eleven canvases is stored once, and a document that
// refers to it keeps an id rather than the picture.

/// _compressAbove is the size past which the size controls are offered on the
/// way in.
///
/// Not a hard limit. A large picture on a canvas is legitimate -- the canvas
/// may be exported at 4096 wide for a poster -- so this is the point at which
/// it is worth asking, not the point at which it is refused. Publishing checks
/// the real limit against the rendered PNG, which is the only size that
/// actually matters.
const int _compressAbove = 512 * 1024;

/// pictureSize is a stored picture's own width and height in pixels.
///
/// Decoded from the bytes rather than asked of CanvasImageStore, because the
/// store answers asynchronously and answers null until it has finished -- and
/// the moment this is wanted is the moment a picture has just been chosen,
/// which is exactly when the store has not got it yet.
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

/// compressCanvasPicture runs a picture that is already on the canvas back
/// through the size controls and stores the result.
///
/// The picture is only *offered* them on the way in, and only when it is over
/// [_compressAbove] -- which means a reader who wanted the controls for a
/// smaller one, or who accepted a size on the way in and changed their mind,
/// had nowhere to go. Returns the new asset id, or null if nothing changed.
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
  return id == assetId ? null : id;
}

/// _mimeOf sniffs the stored bytes, which is the only way to know: an asset id
/// is a hash and the file beside it has whatever extension save() worked out,
/// neither of which is a mime type.
String _mimeOf(List<int> bytes) =>
    lookupMimeType("", headerBytes: bytes.take(64).toList()) ?? "image/png";

/// pickCanvasImage asks for a picture, offers to compress it, stores it, and
/// returns its asset id -- or null if the reader changed their mind at any
/// point along the way.
Future<String?> pickCanvasImage(BuildContext context) async {
  // The extensions rather than FileType.image, which is the platform's idea
  // of a picture and does not include SVG on macOS -- so the one format a
  // badge in a table cell is nearly always in could not be chosen at all.
  var picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ["png", "jpg", "jpeg", "gif", "webp", "svg"],
    withData: false,
  );
  var chosen = picked?.files.singleOrNull?.path;
  if (chosen == null || chosen.trim().isEmpty) return null;

  try {
    var file = File(chosen.trim());
    var bytes = await file.readAsBytes();
    var mime = lookupMimeType(chosen) ?? "image/png";

    // A vector has no pixels to scale and no quality to trade away, and
    // putting one through the compressor would turn a few kilobytes of markup
    // into a bitmap of whatever size it happened to be drawn at.
    if (bytes.length > _compressAbove && !isSvgMime(mime)) {
      if (!context.mounted) return null;
      var result = await showCanvasPictureOptions(context,
          original: bytes, mime: mime, title: "Add a picture");
      // Cancelled there means cancelled altogether: the reader was asked how
      // big it should be and said no to the whole thing, which is not the
      // same as saying "store the big one".
      if (result == null) return null;
      bytes = result;
    }

    var id = await CanvasAssets.save(bytes);
    if (id == null) {
      if (context.mounted) {
        _report(context, "That picture is too large for a canvas.");
      }
      return null;
    }
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

/// _report says something went wrong, and does not itself go wrong.
///
/// Looked up when there is something to say rather than before the picker
/// opens, and guarded. Asking for the snackbar first meant that on any screen
/// without one, reaching for the *error channel* threw before the file dialog
/// was ever asked for -- and the throw was swallowed, because the caller was a
/// fire-and-forget callback, so the button simply did nothing at all.
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
