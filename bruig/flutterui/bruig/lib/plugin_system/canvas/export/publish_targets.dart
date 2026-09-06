import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bruig/models/client.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_bundle.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/export/publish_record.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/embed_store.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/post_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:golib_plugin/golib_plugin.dart';
import 'package:path/path.dart' as path;

// publish_targets.dart is where a rendered canvas actually goes.
//
// Four destinations, and they are four rather than one because they are
// genuinely different things: a file on the reader's disk, a message in a
// chat, a document in the post library that a post or a page can embed, and a
// file shared with contacts. Each one is a few lines; what they share is only
// the bytes handed to them.
//
// Nothing here renders. The caller has already produced a CanvasExport, so a
// destination cannot silently produce a different picture from the one the
// publish sheet previewed.

/// publishedFolderName is the post-library folder canvases are published
/// into.
///
/// Its own folder rather than loose among the writer's posts, because a
/// published canvas is a generated document -- it is one line of embed markup
/// and nothing anybody would edit -- and mixing those in with drafts somebody
/// is writing makes both lists worse.
const String publishedFolderName = "Canvas";

/// sharedDirName is where the files offered to contacts are written, inside
/// the canvas library.
///
/// Written to a file of our own rather than shared straight out of the library
/// directory, because sharing a file publishes whatever is at that path from
/// then on -- and the library's .bcanvas is a document the reader goes on
/// editing. A separate rendered copy is what makes "published" a moment rather
/// than a live feed of unfinished work.
const String sharedDirName = "published";

/// extensionFor is the file extension a mime type gets.
String extensionFor(String mime) => switch (mime) {
      "image/png" => ".png",
      "image/jpeg" => ".jpg",
      "image/gif" => ".gif",
      "video/mp4" => ".mp4",
      "video/webm" => ".webm",
      "application/pdf" => ".pdf",
      "application/json" => ".bcanvas",
      bundleMime => ".bcanvas",
      _ => ".bin",
    };

/// embedMarkupFor is the app's own embed syntax carrying [export] inline.
///
/// The same markup a picture attached to a post uses, so a canvas pasted into
/// a chat, a post or a page renders through exactly the code every other
/// picture does. Inline base64 rather than a library reference, because a
/// message sent to somebody else has to carry its picture with it -- a
/// reference points at a store only this client has.
String embedMarkupFor(CanvasExport export) =>
    "--embed[type=${export.mime},data=${base64Encode(export.data)}]--";

/// saveToDisk asks where to put the file and writes it there.
///
/// Returns the path written, or null when the reader cancelled. Cancelling is
/// not an error and must not be reported as one.
Future<String?> saveToDisk(CanvasExport export, String suggestedName) async {
  try {
    var chosen = await FilePicker.platform.saveFile(
      dialogTitle: "Save the canvas",
      fileName: "$suggestedName${extensionFor(export.mime)}",
      bytes: export.data,
    );
    if (chosen == null) return null;

    // On the platforms where saveFile only returns a path, the bytes still
    // have to be written; on the ones where it writes them itself, writing
    // again is harmless because it is the same bytes to the same place.
    var file = File(chosen);
    if (!await file.exists() || await file.length() != export.data.length) {
      await file.writeAsBytes(export.data, flush: true);
    }
    return chosen;
  } catch (exception) {
    debugPrint("Unable to save the canvas to disk: $exception");
    return null;
  }
}

/// sendToChat posts the canvas into a chat as an inline embed.
///
/// Refuses rather than truncating when the result is over the wire limit: a
/// message that is too large fails at the far end with nothing to show for it,
/// and the reader can do something about it here -- turn the width down, or
/// switch to JPEG.
Future<String?> sendToChat(ChatModel chat, CanvasExport export,
    {String caption = ""}) async {
  var markup = embedMarkupFor(export);
  var message = caption.isEmpty ? markup : "$caption\n\n$markup";

  if (message.length > Golib.maxPayloadSize) {
    return "Too large to send: ${formatBytes(message.length)} against a "
        "limit of ${Golib.maxPayloadSizeStr}. Reduce the width or the "
        "quality.";
  }

  try {
    await chat.sendMsg(message);
    return null;
  } catch (exception) {
    return "Unable to send: $exception";
  }
}

/// publishToLibrary writes the canvas into the post library as a document that
/// a post or a page can embed.
///
/// The picture goes into the embed store and the document holds a reference to
/// it, which is exactly what a draft with a picture in it looks like -- so the
/// composer, the page publisher and the store all already know what to do with
/// it. That is the whole reason to publish here rather than inventing a fourth
/// kind of attachment.
Future<PublishRecord?> publishToLibrary(
  CanvasExport export,
  String name,
  PublishRecord existing,
) async {
  var clean = PostStorage.sanitizeName(name);
  if (clean == null) return null;

  try {
    // Reusing the embed id on an update overwrites the old picture instead of
    // leaving it behind. Without this, republishing a canvas ten times leaves
    // nine orphaned copies of it in the embed store.
    var id = existing.embedId.isNotEmpty ? existing.embedId : _newEmbedId();
    await EmbedStore.save(id, base64Encode(export.data));

    var content = "--embed[type=${export.mime},data=[content $id]]--\n";
    var written = await PostStorage.write(publishedFolderName, clean, content);
    if (written == null) return null;

    return existing.copyWith(
      documentFolder: publishedFolderName,
      documentName: written,
      embedId: id,
      format: export.mime,
      publishedAt: DateTime.now(),
    );
  } catch (exception) {
    debugPrint("Unable to publish the canvas to the library: $exception");
    return null;
  }
}

/// unpublishFromLibrary removes the document and its picture.
Future<void> unpublishFromLibrary(PublishRecord record) async {
  if (!record.hasDocument) return;
  try {
    await PostStorage.delete(PostEntry(
      name: record.documentName,
      folder: record.documentFolder,
      isFolder: false,
    ));
  } catch (exception) {
    debugPrint("Unable to remove the published canvas: $exception");
  }
  // The picture is deliberately left in the embed store rather than deleted
  // here. A post the reader wrote may already refer to it, and the store's own
  // sweep is what knows whether anything still does.
}

/// shareInFiles writes the canvas to a file and offers it to contacts.
///
/// Public rather than to one contact: a canvas is a picture somebody made to
/// be seen, and the Files area is where the app already puts those. Sharing it
/// with one person is a message, which is what sendToChat is for.
Future<PublishRecord?> shareInFiles(
  CanvasExport export,
  String name,
  PublishRecord existing, {
  String description = "",
}) async {
  var clean = CanvasStorage.sanitizeName(name);
  if (clean == null) return null;

  try {
    var dir = path.join(await CanvasStorage.libraryDir(), sharedDirName);
    await Directory(dir).create(recursive: true);
    var file = path.join(dir, "$clean${extensionFor(export.mime)}");

    // An existing share of the same canvas is withdrawn before the new file is
    // put in its place. Writing over the file without re-sharing leaves the
    // client offering the old hash, so contacts would fetch and get nothing.
    if (existing.hasShare) await unshareFiles(existing);

    await File(file).writeAsBytes(export.data, flush: true);
    await Golib.shareFile(
        file, null, 0, description.isEmpty ? clean : description);

    return existing.copyWith(
      sharedPath: file,
      format: export.mime,
      publishedAt: DateTime.now(),
    );
  } catch (exception) {
    debugPrint("Unable to share the canvas: $exception");
    return null;
  }
}

/// unshareFiles withdraws a shared canvas and deletes the copy that was
/// offered.
Future<void> unshareFiles(PublishRecord record) async {
  if (!record.hasShare) return;
  try {
    // The share is found by the path it was made from, because that is what
    // was recorded -- the id is assigned by the client and is not known until
    // afterwards. Listing is cheap and happens once, on an action the reader
    // asked for.
    var shared = await Golib.listSharedFiles();
    for (var entry in shared) {
      if (entry.sf.filename != path.basename(record.sharedPath)) continue;
      await Golib.unshareFile(entry.sf.fid, null);
    }
    var file = File(record.sharedPath);
    if (await file.exists()) await file.delete();
  } catch (exception) {
    debugPrint("Unable to unshare the canvas: $exception");
  }
}

/// _newEmbedId matches what the composer generates: twelve letters and digits.
/// See EmbedStore, which refuses anything else before it becomes a path.
///
/// Random rather than derived from the clock. Two canvases published in the
/// same microsecond is unlikely, but an id derived from a timestamp runs out
/// of entropy in its high bits and starts repeating characters, and a
/// collision here means one published canvas quietly showing another's
/// picture.
String _newEmbedId() {
  const alphabet =
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  var random = math.Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < 12; i++)
      alphabet.codeUnitAt(random.nextInt(alphabet.length)),
  ]);
}
