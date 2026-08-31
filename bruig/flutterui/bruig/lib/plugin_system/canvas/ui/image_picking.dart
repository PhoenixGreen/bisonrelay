import 'dart:io';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/screens/compress.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;

// image_picking.dart is how a picture gets onto the canvas.
//
// It goes through the app's own compression screen -- the same one an
// attachment and an embedded picture use -- rather than a second one written
// for here. A canvas is published into a chat, a post or a page, all of which
// have the same payload limit as everything else Bison Relay sends, so the
// question "is this small enough to send" has one answer and one place to
// decide it.
//
// The bytes are then handed to CanvasAssets, which is content-addressed: the
// same badge dropped onto eleven canvases is stored once, and a document that
// refers to it keeps an id rather than the picture.

/// _compressAbove is the size past which the compression screen is offered.
///
/// Not a hard limit. A large picture on a canvas is legitimate -- the canvas
/// may be exported at 4096 wide for a poster -- so this is the point at which
/// it is worth asking, not the point at which it is refused. Publishing checks
/// the real limit against the rendered PNG, which is the only size that
/// actually matters.
const int _compressAbove = 512 * 1024;

/// pickCanvasImage asks for a picture, offers to compress it, stores it, and
/// returns its asset id -- or null if the reader changed their mind at any
/// point along the way.
Future<String?> pickCanvasImage(BuildContext context) async {
  var snackbar = SnackBarModel.of(context);

  var picked = await FilePicker.platform.pickFiles(
    type: FileType.image,
    withData: false,
  );
  var chosen = picked?.files.singleOrNull?.path;
  if (chosen == null || chosen.trim().isEmpty) return null;

  try {
    var file = File(chosen.trim());
    var bytes = await file.readAsBytes();
    var mime = lookupMimeType(chosen) ?? "image/png";

    if (bytes.length > _compressAbove) {
      if (!context.mounted) return null;
      var result =
          await showCompressScreen(context, original: bytes, mime: mime);
      // Cancelled at the compression screen means cancelled altogether: the
      // reader was asked whether to shrink it and said no to the whole thing,
      // which is not the same as saying "store the big one".
      if (result == null) return null;
      bytes = result.data;
    }

    var id = await CanvasAssets.save(bytes);
    if (id == null) {
      if (context.mounted) {
        snackbar.error("That picture is too large for a canvas.");
      }
      return null;
    }
    return id;
  } catch (exception) {
    if (context.mounted) {
      snackbar.error("Unable to read ${path.basename(chosen)}: $exception");
    }
    return null;
  }
}
