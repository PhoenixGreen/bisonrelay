import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/document_export.dart';
import 'package:bruig/plugin_system/canvas/export/epub_writer.dart';
import 'package:bruig/plugin_system/canvas/export/publish_targets.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:flutter/painting.dart';
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

/// flat is a backdrop that is one colour, which is what a page of a document
/// usually has behind it.
CanvasBackground flat(Color color) => CanvasBackground(
    spec: ProceduralSpec(style: ProceduralStyle.plain, background: color));

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

    /// colourAt reads a pixel out of one rendered page.
    Future<int> colourAt(
        WidgetTester tester, CanvasDocument doc, int page, int x, int y) async {
      var found = 0;
      await tester.runAsync(() async {
        var image = await renderDocumentPage(doc, page);
        try {
          var data = await image.toByteData();
          var at = (y * image.width + x) * 4;
          found = (data!.getUint8(at + 3) << 24) |
              (data.getUint8(at) << 16) |
              (data.getUint8(at + 1) << 8) |
              data.getUint8(at + 2);
        } finally {
          image.dispose();
        }
      });
      return found;
    }

    /// coloured is three pages, each a different flat colour, so that a page
    /// drawn as the wrong one is plain to see.
    CanvasDocument coloured() => CanvasDocument(
          title: "Colours",
          kind: CanvasKind.pages,
          size: const CanvasSize(ratio: CanvasRatio.a4, width: 200),
          scenes: [
            CanvasScene(id: "a", background: flat(const Color(0xFFFF0000))),
            CanvasScene(id: "b", background: flat(const Color(0xFF00FF00))),
            CanvasScene(id: "c", background: flat(const Color(0xFF0000FF))),
          ],
        );

    // renderFrame draws the *sequence*: handed a document moved to page four
    // and the default frame it draws page one. Every leaf of the book came
    // out as the first one, backdrop and all.
    testWidgets("every page is its own page, with its own backdrop",
        (tester) async {
      var doc = coloured();
      var first = await colourAt(tester, doc, 0, 10, 10);
      var second = await colourAt(tester, doc, 1, 10, 10);
      var third = await colourAt(tester, doc, 2, 10, 10);

      // Which channel leads, rather than the exact pixel: a plain backdrop is
      // the colour with the generator's own shading over it, and the test is
      // about which page was drawn.
      int red(int c) => (c >> 16) & 0xFF;
      int green(int c) => (c >> 8) & 0xFF;
      int blue(int c) => c & 0xFF;

      expect(red(first), greaterThan(green(first) + 40));
      expect(green(second), greaterThan(red(second) + 40));
      expect(blue(third), greaterThan(red(third) + 40));
    });

    // An element laid across the gutter belongs to one page and hangs over
    // the other. Printed a page at a time it was cut at the gutter and the
    // half on the other leaf was nowhere -- which is not what a spread is:
    // the left half is on one sheet and the right half on the next.
    testWidgets("and a spread carries on across the gutter", (tester) async {
      var wide = CanvasDocument(
        title: "Spread",
        kind: CanvasKind.pages,
        size: const CanvasSize(ratio: CanvasRatio.a4, width: 200),
        pages: const PagesSpec(facing: true),
        scenes: [
          const CanvasScene(id: "cover", cover: PageCover.front),
          // On the left leaf, reaching well over the gutter onto the right.
          CanvasScene(id: "left", elements: [
            ShapeElement(
                const ElementBase(
                    id: "s", x: 100, y: 0, width: 300, height: 400),
                fill: const Color(0xFF00FFFF)),
          ]),
          const CanvasScene(id: "right"),
        ],
      );

      expect(wide.facingAt(1), 2, reason: "the two leaves face each other");
      // Its own leaf has the left of it.
      expect(await colourAt(tester, wide, 1, 150, 40), 0xFF00FFFF);
      // And the leaf it hangs over has the rest, at the gutter edge.
      expect(await colourAt(tester, wide, 2, 10, 40), 0xFF00FFFF,
          reason: "the half of the picture printed on the next sheet");
      // The cover is not part of the spread and gets none of it.
      expect(await colourAt(tester, wide, 0, 10, 40), isNot(0xFF00FFFF));
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
