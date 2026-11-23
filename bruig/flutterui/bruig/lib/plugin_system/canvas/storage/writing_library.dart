import 'package:flutter/foundation.dart';

import 'package:bruig/plugin_system/canvas/model/text_document.dart';

// writing_library.dart is the Writing tools' library of documents, as the
// Canvas needs it: a text or a Speech device reads its words from one, and a
// canvas can be published into it as a picture a post or page embeds.
//
// The Canvas never reaches into the library's storage. The app hands it a
// WritingLibrary at start (WritingLibrary.use), from outside both features,
// since neither may know the other's insides; until then, and in a test that
// hands it none, there is no library, and the Canvas says so where a
// document is asked for rather than showing an empty one.

/// WritingLibrary is what the Canvas asks of the Writing library. A document
/// is named by a TextDocumentRef's folder and name, as [documents] gives
/// them; how the library keeps its folders is its own affair.
abstract class WritingLibrary {
  const WritingLibrary();

  /// current is the library the app handed the Canvas, or [none].
  static WritingLibrary get current => _current;
  static WritingLibrary _current = none;

  /// none is no library at all: nothing listed, nothing read, nothing
  /// published.
  static const WritingLibrary none = _NoWritingLibrary();

  /// use hands the Canvas [library], once at start.
  static void use(WritingLibrary library) => _current = library;

  /// forgetForTest takes the library away, as a new run has none.
  @visibleForTesting
  static void forgetForTest() => _current = none;

  /// here is whether there is a library to read and publish into.
  bool get here;

  /// documents is every document in the library, each by where it is, in
  /// the order the library lists them.
  Future<List<TextDocumentRef>> documents();

  /// read is [ref]'s words as written (Markdown), or null where it has gone
  /// or cannot be read. Always read afresh: the library tells nobody of an
  /// edit, so a text showing a document learns of one by reading it again
  /// and comparing the words.
  Future<String?> read(TextDocumentRef ref);

  /// publishPicture puts [data], a picture in the format [mime], into the
  /// library as a document of its own in [folder], named from [name], for a
  /// post or a page to embed. [pictureId] is the picture's id from an earlier
  /// publish, so it is replaced rather than copied. Answers where the
  /// document is and the picture's id, or null where [name] makes no name.
  Future<({TextDocumentRef at, String pictureId})?> publishPicture(
      String folder, String name, String mime, Uint8List data,
      {String pictureId = ""});

  /// remove deletes the document at [ref]. A picture it held is left: a post
  /// may embed it too, and the library's own sweep knows whether one does.
  Future<void> remove(TextDocumentRef ref);
}

/// _NoWritingLibrary is [WritingLibrary.none].
class _NoWritingLibrary extends WritingLibrary {
  const _NoWritingLibrary();

  @override
  bool get here => false;

  @override
  Future<List<TextDocumentRef>> documents() async => const [];

  @override
  Future<String?> read(TextDocumentRef ref) async => null;

  @override
  Future<({TextDocumentRef at, String pictureId})?> publishPicture(
          String folder, String name, String mime, Uint8List data,
          {String pictureId = ""}) async =>
      null;

  @override
  Future<void> remove(TextDocumentRef ref) async {}
}
