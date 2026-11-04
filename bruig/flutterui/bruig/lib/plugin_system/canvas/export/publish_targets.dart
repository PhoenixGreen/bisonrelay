import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bruig/models/client.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_bundle.dart';
import 'package:bruig/plugin_system/canvas/export/epub_writer.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/export/publish_record.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/embed_store.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/post_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:golib_plugin/golib_plugin.dart';
import 'package:path/path.dart' as path;

// publish_targets.dart is where a rendered canvas goes: a file on disk, a
// chat message, a post-library document, or a file shared with contacts.
//
// Nothing here renders: the caller hands over the CanvasExport the publish
// sheet previewed, so a destination cannot produce a different picture.

/// publishedFolderName is the post-library folder canvases are published
/// into, keeping these generated one-line documents apart from drafts.
const String publishedFolderName = "Canvas";

// Files offered to contacts are rendered copies in CanvasStorage.sharedDir,
// never the library's .bcanvas: sharing publishes whatever is at the path
// from then on, and the library document goes on being edited.

/// extensionFor is the file extension a mime type gets.
String extensionFor(String mime) => switch (mime) {
      "image/png" => ".png",
      "image/jpeg" => ".jpg",
      "image/gif" => ".gif",
      "video/mp4" => ".mp4",
      "video/webm" => ".webm",
      "audio/wav" => ".wav",
      "audio/flac" => ".flac",
      "audio/mpeg" => ".mp3",
      "audio/mp4" => ".m4a",
      "audio/ogg" => ".opus",
      "application/pdf" => ".pdf",
      epubMime => ".epub",
      "application/json" => ".bcanvas",
      bundleMime => ".bcanvas",
      _ => ".bin",
    };

/// embedMarkupFor is the app's own embed syntax carrying [export] inline,
/// as a picture attached to a post uses. Inline base64 rather than a
/// library reference, because a message sent to somebody else must carry
/// its picture: a reference points at a store only this client has.
String embedMarkupFor(CanvasExport export) =>
    "--embed[type=${export.mime},data=${base64Encode(export.data)}]--";

/// saveToDisk asks where to put the file and writes it there. Returns the
/// path written, or null when cancelled (not an error) or on failure.
Future<String?> saveToDisk(CanvasExport export, String suggestedName) async {
  try {
    var chosen = await FilePicker.platform.saveFile(
      dialogTitle: "Save the canvas",
      fileName: "$suggestedName${extensionFor(export.mime)}",
      bytes: export.data,
    );
    if (chosen == null) return null;

    // Some platforms' saveFile only returns a path, so the bytes are always
    // written; where it wrote them already, this rewrites the same bytes.
    await File(chosen).writeAsBytes(export.data, flush: true);
    return chosen;
  } catch (exception) {
    debugPrint("Unable to save the canvas to disk: $exception");
    return null;
  }
}

/// saveAllToDisk writes one file per shape into a folder chosen once.
/// Answers with the folder, or null where cancelled. A shape that could not
/// be written is left out of `written` rather than stopping the rest.
Future<({String folder, List<String> written})?> saveAllToDisk(
  List<({String tag, CanvasExport export})> shapes,
  String suggestedName,
) async {
  if (shapes.isEmpty) return null;
  try {
    var folder = await FilePicker.platform.getDirectoryPath(
        dialogTitle: "Where to put the ${shapes.length} files");
    if (folder == null) return null;

    var written = <String>[];
    for (var shape in shapes) {
      var name =
          "$suggestedName-${shape.tag}${extensionFor(shape.export.mime)}";
      try {
        await File(path.join(folder, name))
            .writeAsBytes(shape.export.data, flush: true);
        written.add(name);
      } catch (exception) {
        debugPrint("Unable to write $name: $exception");
      }
    }
    return (folder: folder, written: written);
  } catch (exception) {
    debugPrint("Unable to save the canvas to disk: $exception");
    return null;
  }
}

/// sendToChat posts the canvas into a chat as an inline embed, answering
/// with an error message or null. Over the wire limit it refuses, since an
/// oversized message fails at the far end with nothing to show.
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

/// publishToLibrary writes the canvas into the post library as a document
/// that a post or a page can embed. The picture goes into the embed store
/// and the document references it, exactly as a draft with a picture does.
Future<PublishRecord?> publishToLibrary(
  CanvasExport export,
  String name,
  PublishRecord existing,
) async {
  var clean = PostStorage.sanitizeName(name);
  if (clean == null) return null;

  try {
    // Reusing the embed id on an update overwrites the old picture rather
    // than orphaning a copy per republish.
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
  // The picture is left in the embed store: a post may refer to it, and
  // the store's own sweep knows whether anything still does.
}

/// shareInFiles writes the canvas to a file and shares it publicly in
/// Files. (Sending to one person is [sendToChat].)
Future<PublishRecord?> shareInFiles(
  CanvasExport export,
  String name,
  PublishRecord existing, {
  String description = "",
}) async {
  var clean = CanvasStorage.sanitizeName(name);
  if (clean == null) return null;

  try {
    var dir = await CanvasStorage.sharedDir();
    var file = path.join(dir, "$clean${extensionFor(export.mime)}");

    // Withdraw an existing share first: overwriting the file without
    // re-sharing leaves the client offering the old hash.
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
    // Found by file name, as the record keeps the path, not the share id.
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

/// _newEmbedId matches what the composer generates: twelve letters and
/// digits, which EmbedStore requires before it becomes a path. Securely
/// random, since a collision would show one canvas's picture for another.
String _newEmbedId() {
  const alphabet =
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  var random = math.Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < 12; i++)
      alphabet.codeUnitAt(random.nextInt(alphabet.length)),
  ]);
}
