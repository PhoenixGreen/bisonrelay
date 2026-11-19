import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/export/reader_test_book.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

// canvas_reader_test_book_test.dart is the one-page EPUB that finds out what
// a reading app lets a book do (reader_test_book.dart). Ken, 2026-11-19: the
// first step of the plan, opened in Apple Books, Kobo, Google Play Books,
// Thorium and Bison Relay's own reader.

void main() {
  var bytes = readerTestBook(made: DateTime.utc(2026, 11, 19));
  var archive = ZipDecoder().decodeBytes(bytes);
  String text(String name) => utf8.decode(
      archive.files.firstWhere((f) => f.name == name).content as List<int>);

  test("an EPUB a reader will open: its mimetype first and stored", () {
    expect(archive.files.first.name, "mimetype");
    expect(utf8.decode(archive.files.first.content as List<int>),
        "application/epub+zip");
    // Stored, not deflated: readers look for the bytes at a fixed place.
    expect(String.fromCharCodes(bytes.sublist(30, 38)), "mimetype");
    expect(String.fromCharCodes(bytes.sublist(38, 58)), "application/epub+zip");
  });

  test("every file it lists is in it, and its XML is well formed", () {
    var opf = XmlDocument.parse(text("OEBPS/content.opf"));
    var hrefs = [
      for (var item in opf.findAllElements("item")) item.getAttribute("href")!
    ];
    for (var href in hrefs) {
      expect(archive.files.any((f) => f.name == "OEBPS/$href"), isTrue,
          reason: "$href is in the book");
    }
    for (var name in [
      "OEBPS/test.xhtml",
      "OEBPS/nav.xhtml",
      "META-INF/container.xml"
    ]) {
      expect(() => XmlDocument.parse(text(name)), returnsNormally,
          reason: "$name parses");
    }
    var page = opf
        .findAllElements("item")
        .firstWhere((i) => i.getAttribute("href") == "test.xhtml");
    expect(page.getAttribute("properties"), "scripted",
        reason: "a page that runs a script says so");
    expect(text("OEBPS/content.opf"), contains("pre-paginated"));
  });

  test("before its script runs, the page already says scripts are not", () {
    var page = text("OEBPS/test.xhtml");
    expect(page, contains("Not running"));
    expect(page, contains('<script src="test.js"></script>'));
    for (var id in ["bSound", "bMidi", "bMic"]) {
      expect(page, contains('id="$id"'));
    }
  });

  test("its tone is a WAV half a second long", () {
    var wav = archive.files
        .firstWhere((f) => f.name == "OEBPS/tone.wav")
        .content as List<int>;
    expect(String.fromCharCodes(wav.sublist(0, 4)), "RIFF");
    expect(String.fromCharCodes(wav.sublist(8, 12)), "WAVE");
    expect(wav.length, 44 + 22050 ~/ 2 * 2 + 0, reason: "0.5 s, 16-bit mono");
  });
}
