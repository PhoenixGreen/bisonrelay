import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:bruig/plugin_system/canvas/canvas.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/embed_store.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';

// canvas_writing_library.dart is the Writing library as the Canvas asks for
// it (WritingLibrary), over the library's own storage. It lives with the app
// rather than in either feature: the Canvas may not reach into the
// library's storage, and the writing tools may not know the Canvas.

/// PostStorageLibrary is the Writing library (PostStorage) as a
/// WritingLibrary, handed to the Canvas at start.
class PostStorageLibrary extends WritingLibrary {
  const PostStorageLibrary();

  @override
  bool get here => true;

  /// documents is the top level's documents and each folder's, in the order
  /// the library lists them: it is one level deep (PostStorage.list).
  @override
  Future<List<TextDocumentRef>> documents() async {
    var out = <TextDocumentRef>[];
    for (var entry in await PostStorage.list()) {
      if (!entry.isFolder) {
        out.add(TextDocumentRef(folder: entry.folder, name: entry.name));
        continue;
      }
      for (var inside in await PostStorage.list(entry.name)) {
        if (inside.isFolder) continue;
        out.add(TextDocumentRef(folder: inside.folder, name: inside.name));
      }
    }
    return out;
  }

  @override
  Future<String?> read(TextDocumentRef ref) =>
      PostStorage.read(ref.folder, ref.name);

  /// publishPicture keeps the picture in the embed store and writes a
  /// document that embeds it from there, as a draft with a picture does.
  @override
  Future<({TextDocumentRef at, String pictureId})?> publishPicture(
      String folder, String name, String mime, Uint8List data,
      {String pictureId = ""}) async {
    var clean = PostStorage.sanitizeName(name);
    if (clean == null) return null;
    var id = pictureId.isNotEmpty ? pictureId : _newEmbedId();
    await EmbedStore.save(id, base64Encode(data));
    var content = "--embed[type=$mime,data=[content $id]]--\n";
    var written = await PostStorage.write(folder, clean, content);
    if (written == null) return null;
    return (at: TextDocumentRef(folder: folder, name: written), pictureId: id);
  }

  @override
  Future<void> remove(TextDocumentRef ref) => PostStorage.delete(
      PostEntry(name: ref.name, folder: ref.folder, isFolder: false));
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
