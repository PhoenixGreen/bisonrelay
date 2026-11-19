import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/export/document_export.dart';
import 'package:bruig/plugin_system/canvas/model/book_details.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/canvas_settings_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'support/canvas_app.dart';
import 'support/canvas_panel_helpers.dart';

// canvas_book_details_test.dart is what a book tells a store and a reader
// (book_details.dart): author, description, series and each edition's ISBN,
// kept with the canvas and written into every EPUB. Ken, 2026-11-19: step 2
// of the ebook plan, set before any upload as Apple takes an ISBN only with
// a book's first.

const _details = BookDetails(
  subtitle: "Ten years of a coin that governs itself",
  author: "Ken Cameron, Stakey",
  publisher: "Bison Relay Books",
  description: "A comic history <with> data & charts.",
  language: "en-GB",
  subjects: "Comics, Cryptocurrency, History",
  series: "Decred Stories",
  seriesNumber: 1,
  published: "2026-12-01",
  rights: "© 2026 Ken Cameron",
  isbns: {"ebook": "978-0-306-40615-7", "interactive": "0306406152"},
);

CanvasDocument _book([BookDetails details = _details]) => const CanvasDocument(
      title: "The History of Decred",
      size: CanvasSize(ratio: CanvasRatio.a4, width: 1240),
    )
        .copyWith(
      kind: CanvasKind.pages,
      pages: PagesSpec(book: details),
    )
        .withScenes(const [
      CanvasScene(id: "p1", name: "Cover"),
      CanvasScene(id: "p2", name: "One"),
    ], at: 0);

void main() {
  group("an ISBN", () {
    test("is checked by its last digit, ten or thirteen long", () {
      expect(isbnProblem("978-0-306-40615-7"), isNull);
      expect(isbnProblem("0-306-40615-2"), isNull);
      expect(isbnProblem("080442957X"), isNull, reason: "X stands for 10");
      expect(isbnProblem(""), isNull, reason: "none is not wrong");
      expect(isbnProblem("978-0-306-40615-8"), contains("should be 7"));
      expect(isbnProblem("12345"), isNotNull);
      expect(isbnProblem("123-4-567-89012-3"), contains("978 or 979"));
    });

    test("an old ten-digit one is written as thirteen", () {
      expect(isbn13("0-306-40615-2"), "9780306406157");
      expect(isbn13("978 0 306 40615 7"), "9780306406157");
      expect(isbn13("not one"), isNull);
    });
  });

  test("kept with the canvas, and junk in a file read safely", () {
    var doc = _book();
    var back = CanvasDocument.fromJson(
        jsonDecode(doc.encode()) as Map<String, dynamic>);
    var book = back.pages.book;
    expect(book.author, "Ken Cameron, Stakey");
    expect(book.authors, ["Ken Cameron", "Stakey"]);
    expect(book.seriesNumber, 1);
    expect(book.isbnOf(BookEdition.interactive), "0306406152");

    var junk = BookDetails.fromJson({
      "author": "a" * 5000,
      "language": 7,
      "seriesNumber": -4,
      "isbns": {"ebook": 12, "nonsense": "978", "print": "9780306406157"},
    });
    expect(junk.author.length, 500);
    expect(junk.language, "en");
    expect(junk.seriesNumber, 0);
    expect(junk.isbns, {"print": "9780306406157"});
    expect(const PagesSpec().isDefault, isTrue);
    expect(const PagesSpec(book: _details).isDefault, isFalse);
  });

  group("written into the EPUB", () {
    Future<XmlDocument> opfOf(WidgetTester tester, DocumentAs as) async {
      var out = await tester.runAsync(() => renderDocument(_book(), as: as));
      var archive = ZipDecoder().decodeBytes(out!.data);
      var file = archive.files.firstWhere((f) => f.name == "OEBPS/content.opf");
      return XmlDocument.parse(utf8.decode(file.content as List<int>));
    }

    String all(XmlDocument opf, String name) =>
        opf.findAllElements(name).map((e) => e.innerText).join("|");

    testWidgets("who wrote it, what it is, and its series", (tester) async {
      var opf = await opfOf(tester, DocumentAs.epub);
      expect(all(opf, "dc:title"),
          "The History of Decred|Ten years of a coin that governs itself");
      expect(all(opf, "dc:creator"), "Ken Cameron|Stakey");
      expect(all(opf, "dc:publisher"), "Bison Relay Books");
      expect(
          all(opf, "dc:description"), "A comic history <with> data & charts.",
          reason: "escaped, and read back as written");
      expect(all(opf, "dc:language"), "en-GB");
      expect(all(opf, "dc:subject"), "Comics|Cryptocurrency|History");
      expect(all(opf, "dc:date"), "2026-12-01");
      expect(all(opf, "dc:rights"), "© 2026 Ken Cameron");
      var metas = opf.findAllElements("meta").map((m) => m.toXmlString());
      expect(metas.any((m) => m.contains("belongs-to-collection")), isTrue);
      expect(
          metas.any((m) => m.contains("group-position") && m.contains(">1<")),
          isTrue);
    });

    testWidgets("each edition under its own ISBN", (tester) async {
      var plain = await opfOf(tester, DocumentAs.epub);
      expect(all(plain, "dc:identifier"), "urn:isbn:9780306406157");
      var interactive = await opfOf(tester, DocumentAs.interactiveEpub);
      expect(all(interactive, "dc:identifier"), "urn:isbn:9780306406157",
          reason: "0306406152 is the same book written as ten digits");
    });

    testWidgets("a book with no details still has an identifier",
        (tester) async {
      var out = await tester.runAsync(() =>
          renderDocument(_book(const BookDetails()), as: DocumentAs.epub));
      var archive = ZipDecoder().decodeBytes(out!.data);
      var opf = utf8.decode(archive.files
          .firstWhere((f) => f.name == "OEBPS/content.opf")
          .content as List<int>);
      expect(opf, contains("urn:uuid:"));
      expect(opf, contains("<dc:language>en</dc:language>"));
    });
  });

  testWidgets("set in the canvas settings, and a wrong ISBN is said",
      (tester) async {
    var controller = CanvasController(_book(const BookDetails()));
    addTearDown(controller.dispose);
    setTestScreen(tester, const Size(1400, 1400));
    await tester
        .pumpWidget(canvasApp(CanvasSettingsPanel(controller: controller)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("bookDetails")), findsOneWidget);
    expect(find.textContaining("Stores ask for an author"), findsOneWidget);

    await enterValue(tester, find.byKey(const ValueKey("bookAuthor")), "Ken");
    await tester.pumpAndSettle();
    expect(controller.document.pages.book.author, "Ken");

    await enterValue(tester, find.byKey(const ValueKey("bookIsbnebook")),
        "978-0-306-40615-8");
    await tester.pumpAndSettle();
    expect(controller.document.pages.book.isbnOf(BookEdition.ebook),
        "978-0-306-40615-8");
    expect(find.textContaining("should be 7"), findsOneWidget);
  });
}
