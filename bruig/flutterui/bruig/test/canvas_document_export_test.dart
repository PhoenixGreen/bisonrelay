import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/export/document_export.dart';
import 'package:bruig/plugin_system/canvas/export/epub_writer.dart';
import 'package:bruig/plugin_system/canvas/export/publish_targets.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_document_export_test.dart is the book a document of pages is
// published as.
//
// An EPUB is a zip with a handful of short XML files in it, and what makes it
// an EPUB rather than a zip is where those files are and what they say. So
// the test opens the archive and reads them, which is what a reader does.

EpubPage page(String title,
        {EpubSide side = EpubSide.centre,
        bool cover = false,
        List<EpubLink> links = const []}) =>
    EpubPage(
      png: Uint8List.fromList(const [137, 80, 78, 71, 13, 10, 26, 10]),
      width: 1240,
      height: 1754,
      title: title,
      side: side,
      cover: cover,
      links: links,
    );

Archive openEpub(Uint8List bytes) => ZipDecoder().decodeBytes(bytes);

String textOf(Archive archive, String path) {
  var file = archive.files.firstWhere((f) => f.name == path,
      orElse: () => throw StateError("no $path in the book"));
  return utf8.decode(file.content as List<int>);
}

void main() {
  group("the archive itself", () {
    test("says what it is in its first entry, uncompressed", () {
      // A reader identifies an EPUB by finding these exact bytes at a fixed
      // offset in the file. Deflated, or second, they are somewhere else and
      // the file is a zip.
      var bytes = writeEpub(pages: [page("One")], title: "A document");
      var archive = openEpub(bytes);
      expect(archive.files.first.name, "mimetype");
      expect(utf8.decode(archive.files.first.content as List<int>),
          "application/epub+zip");

      // Thirty bytes of local file header, then the name, then the data --
      // which is exactly where a reader looks for it.
      var raw = ascii.decode(bytes.sublist(30, 30 + 28));
      expect(raw, "mimetypeapplication/epub+zip",
          reason: "stored, not deflated, at the head of the file");
    });

    test("and carries the four files a reader looks for", () {
      var bytes = writeEpub(pages: [page("One"), page("Two")], title: "Book");
      var names = openEpub(bytes).files.map((f) => f.name).toList();
      expect(names, contains("META-INF/container.xml"));
      expect(names, contains("OEBPS/content.opf"));
      expect(names, contains("OEBPS/nav.xhtml"));
      expect(names, contains("OEBPS/page0.xhtml"));
      expect(names, contains("OEBPS/page1.png"));
    });
  });

  group("what the package says", () {
    test("the pages are fixed, not reflowed", () {
      // A canvas is a design: its words are placed and its columns are where
      // somebody put them. Reflowing it into a phone-shaped column throws
      // away the whole of the work.
      var opf = textOf(openEpub(writeEpub(pages: [page("One")], title: "Book")),
          "OEBPS/content.opf");
      expect(opf, contains('property="rendition:layout">pre-paginated'));

      var html = textOf(
          openEpub(writeEpub(pages: [page("One")], title: "Book")),
          "OEBPS/page0.xhtml");
      expect(html, contains('content="width=1240, height=1754"'),
          reason: "without a viewport a reader reflows it anyway");
    });

    test("and which side of the spine each page is on", () {
      // The reader cannot work this out: it depends on the covers and on
      // where the numbering starts.
      var opf = textOf(
        openEpub(writeEpub(
          pages: [
            page("Cover", cover: true),
            page("One", side: EpubSide.left),
            page("Two", side: EpubSide.right),
          ],
          title: "Book",
          facing: true,
        )),
        "OEBPS/content.opf",
      );
      expect(opf, contains('idref="page1" properties="page-spread-left"'));
      expect(opf, contains('idref="page2" properties="page-spread-right"'));
      expect(opf, contains('idref="page0"/>'), reason: "a cover is alone");
      expect(opf, contains('property="rendition:spread">landscape'));
      expect(opf, contains('properties="cover-image"'));
    });

    test("and the same document twice is the same book", () {
      // A reader keeps somebody's place by identifier. A new one on every
      // export is a document that loses its bookmarks each time it is sent.
      String idOf(Uint8List bytes) {
        var opf = textOf(openEpub(bytes), "OEBPS/content.opf");
        return RegExp(r'<dc:identifier[^>]*>([^<]+)')
            .firstMatch(opf)!
            .group(1)!;
      }

      expect(idOf(writeEpub(pages: [page("One")], title: "Book")),
          idOf(writeEpub(pages: [page("One")], title: "Book")));
      expect(idOf(writeEpub(pages: [page("One")], title: "Book")),
          isNot(idOf(writeEpub(pages: [page("One")], title: "Other"))));
    });
  });

  group("the interactive one", () {
    var pressable = page("One", links: const [
      EpubLink(x: 100, y: 200, width: 300, height: 80, href: "page2.xhtml"),
    ]);

    test("puts a hotspot where the button was", () {
      var html = textOf(
          openEpub(
              writeEpub(pages: [pressable], title: "Book", interactive: true)),
          "OEBPS/page0.xhtml");
      expect(html, contains('href="page2.xhtml"'));
      expect(html, contains("left:100.00px"));
      expect(html, contains("width:300.00px"));
    });

    test("and the plain one does not", () {
      // The difference between the two kinds is exactly this. Both are fixed
      // layout, because both are this canvas.
      var html = textOf(openEpub(writeEpub(pages: [pressable], title: "Book")),
          "OEBPS/page0.xhtml");
      expect(html, isNot(contains("page2.xhtml")));
      expect(html, contains('<img class="page"'));
    });

    test("and a page with nothing to press is not called scripted", () {
      var opf = textOf(
          openEpub(writeEpub(
              pages: [page("One"), pressable],
              title: "Book",
              interactive: true)),
          "OEBPS/content.opf");
      expect(
          opf,
          contains('id="page1" href="page1.xhtml" '
              'media-type="application/xhtml+xml" properties="scripted"'));
      expect(
          opf,
          contains('id="page0" href="page0.xhtml" '
              'media-type="application/xhtml+xml"/>'));
    });
  });

  test("a book needs a page", () {
    expect(
        () => writeEpub(pages: const [], title: "Book"), throwsArgumentError);
  });

  group("a real document", () {
    /// book is three A5 pages, the first a cover, with a button on page two
    /// that goes to page three.
    CanvasDocument book() => CanvasDocument(
          title: "A little book",
          kind: CanvasKind.pages,
          size: const CanvasSize(ratio: CanvasRatio.a4, width: 300),
          pages: const PagesSpec(facing: true),
          scenes: [
            const CanvasScene(id: "c", cover: PageCover.front),
            CanvasScene(id: "p1", elements: [
              ButtonElement(const ElementBase(id: "b", width: 90, height: 30),
                  label: "On",
                  action: const ButtonAction(
                      kind: ButtonActionKind.goToScene, elementId: "p2")),
            ]),
            const CanvasScene(id: "p2"),
          ],
        );

    testWidgets("becomes a book with a page for every leaf", (tester) async {
      // Through runAsync: rendering a page into an image and encoding it as a
      // PNG both wait on the engine, and a widget test's fake clock never
      // lets them finish. See bisonrelay flutter_test_real_io.
      var made = await tester
          .runAsync(() => renderDocument(book(), as: DocumentAs.epub));
      expect(made, isNotNull);
      expect(made!.mime, epubMime);
      expect(extensionFor(made.mime), ".epub");

      var archive = openEpub(made.data);
      var names = archive.files.map((f) => f.name).toSet();
      expect(names.contains("OEBPS/page2.xhtml"), isTrue);
      expect(names.contains("OEBPS/page3.xhtml"), isFalse,
          reason: "three leaves, three pages");

      var opf = textOf(archive, "OEBPS/content.opf");
      expect(opf, contains("<dc:title>A little book</dc:title>"));
      // The cover stands alone and the two after it face each other, which is
      // the document's own pairing rule and not something a reader can work
      // out.
      expect(opf, contains('idref="page0"/>'));
      expect(opf, contains('idref="page1" properties="page-spread-left"'));
      expect(opf, contains('idref="page2" properties="page-spread-right"'));
    });

    testWidgets("and a plain one has no links on it", (tester) async {
      var made = await tester
          .runAsync(() => renderDocument(book(), as: DocumentAs.epub));
      var html = textOf(openEpub(made!.data), "OEBPS/page1.xhtml");
      expect(html, isNot(contains("<a ")));
    });

    testWidgets("while the interactive one keeps the button", (tester) async {
      var made = await tester.runAsync(
          () => renderDocument(book(), as: DocumentAs.interactiveEpub));
      var html = textOf(openEpub(made!.data), "OEBPS/page1.xhtml");
      expect(html, contains('href="page2.xhtml"'),
          reason: "the button went to the third leaf, which is page2.xhtml");
    });

    testWidgets("a button that moves a playhead is left out", (tester) async {
      // A book has no playhead. A hotspot over one would make the page look
      // broken rather than make it work.
      var playing = CanvasDocument(
        title: "Book",
        kind: CanvasKind.pages,
        size: const CanvasSize(ratio: CanvasRatio.a4, width: 300),
        scenes: [
          CanvasScene(id: "p1", elements: [
            ButtonElement(const ElementBase(id: "b", width: 90, height: 30),
                label: "Play",
                action: const ButtonAction(kind: ButtonActionKind.play)),
          ]),
          const CanvasScene(id: "p2"),
        ],
      );
      var made = await tester.runAsync(
          () => renderDocument(playing, as: DocumentAs.interactiveEpub));
      var html = textOf(openEpub(made!.data), "OEBPS/page0.xhtml");
      expect(html, isNot(contains("<a ")));
    });

    testWidgets("and a PDF is still a PDF", (tester) async {
      var made = await tester
          .runAsync(() => renderDocument(book(), as: DocumentAs.pdf));
      expect(made, isNotNull);
      expect(made!.mime, "application/pdf");
      expect(String.fromCharCodes(made.data.take(5)), "%PDF-");
    });
  });
}
