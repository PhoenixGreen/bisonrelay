import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/models/canvas_writing_library.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/export/publish_record.dart';
import 'package:bruig/plugin_system/canvas/export/publish_targets.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_document.dart';
import 'package:bruig/plugin_system/canvas/storage/writing_library.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/document_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/text_documents.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/embed_store.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';

import 'support/canvas_app.dart';

// canvas_writing_library_test.dart is the Writing library as the Canvas is
// handed it (WritingLibrary): with none handed, a text keeps its words and the
// picker says there is no library; through the app's own (PostStorageLibrary)
// over a real folder, the documents listed one level deep, read, and a canvas
// published into the library and taken out again.

void main() {
  group("with no library handed to the Canvas", () {
    test("a text showing a document keeps its words", () async {
      var c = CanvasController(const CanvasDocument().addElement(
          const TextElement(ElementBase(id: "t"),
              text: "Typed", document: TextDocumentRef(name: "Words"))));
      addTearDown(c.dispose);
      expect(WritingLibrary.current.here, isFalse);
      expect(await refreshTextDocuments(c), isFalse);
      expect((c.document.elementById("t") as TextElement).text, "Typed");
    });

    test("nothing is published", () async {
      var record = await publishToLibrary(
          CanvasExport(Uint8List.fromList([1, 2, 3]), "image/png",
              width: 1, height: 1),
          "Picture",
          const PublishRecord());
      expect(record, isNull);
    });

    testWidgets("the picker says there is no library, not that it is empty",
        (tester) async {
      await pumpCanvasApp(
          tester,
          Builder(
              builder: (context) => TextButton(
                  onPressed: () => pickTextDocument(context),
                  child: const Text("Choose"))));
      await tester.tap(find.text("Choose"));
      await tester.pumpAndSettle();
      expect(find.text("There is no Writing library here to read from."),
          findsOneWidget);
    });
  });

  group("through the app's library", () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync("canvas-writing-library");
      PostStorage.rootOverride = root.path;
      WritingLibrary.use(const PostStorageLibrary());
    });
    tearDown(() {
      WritingLibrary.forgetForTest();
      PostStorage.rootOverride = null;
      root.deleteSync(recursive: true);
    });

    test("lists every document, one folder deep, and reads one", () async {
      await PostStorage.write("", "Loose", "At the top.");
      await PostStorage.write("Essays", "First", "In a folder.");
      var listed = await WritingLibrary.current.documents();
      expect([for (var d in listed) (d.folder, d.name)],
          containsAll([("", "Loose"), ("Essays", "First")]));
      expect(
          await WritingLibrary.current
              .read(const TextDocumentRef(folder: "Essays", name: "First")),
          "In a folder.");
      expect(
          await WritingLibrary.current
              .read(const TextDocumentRef(name: "Gone")),
          isNull);
    });

    test("a canvas is published as a document embedding its picture", () async {
      var picture = Uint8List.fromList([137, 80, 78, 71]);
      var record = (await publishToLibrary(
          CanvasExport(picture, "image/png", width: 1, height: 1),
          "My picture",
          const PublishRecord()))!;
      expect((record.documentFolder, record.documentName),
          (publishedFolderName, "My picture"));
      var written =
          await PostStorage.read(record.documentFolder, record.documentName);
      expect(written,
          "--embed[type=image/png,data=[content ${record.embedId}]]--\n");
      expect(await EmbedStore.load(record.embedId), isNotNull);

      // Published again, the same picture is replaced, not copied.
      var again = (await publishToLibrary(
          CanvasExport(picture, "image/png", width: 1, height: 1),
          "My picture",
          record))!;
      expect(again.embedId, record.embedId);

      await unpublishFromLibrary(again);
      expect(await PostStorage.read(again.documentFolder, again.documentName),
          isNull);
    });
  });
}
