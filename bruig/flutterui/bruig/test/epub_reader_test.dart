import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bruig/components/epub_reader/epub_book.dart';
import 'package:bruig/components/epub_reader/epub_reader_view.dart';
import 'package:bruig/components/epub_reader/reader_shell.dart';
import 'package:bruig/components/epub_reader/reader_inputs.dart';
import 'package:bruig/plugin_system/canvas/media/midi_input.dart';
import 'package:bruig/plugin_system/canvas/export/document_export.dart';
import 'package:bruig/plugin_system/canvas/export/reader_test_book.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/canvas_app.dart';

// epub_reader_test.dart is Bison Relay's own EPUB reader (lib/components/
// epub_reader): a book unpacked safely, its package read for pages, spreads,
// contents and panels, and the view that turns its pages. Ken, 2026-11-19:
// "build something like Thorium" so the History and Piano books read in
// full inside Bison Relay. The pages themselves are drawn by a web view,
// which a test cannot start: its shell is checked in a browser instead.

/// _zip is an EPUB of [files], its mimetype first.
List<int> _zip(Map<String, String> files) {
  var a = Archive();
  var mime = utf8.encode("application/epub+zip");
  a.addFile(ArchiveFile("mimetype", mime.length, mime));
  for (var e in files.entries) {
    var b = utf8.encode(e.value);
    a.addFile(ArchiveFile(e.key, b.length, b));
  }
  return ZipEncoder().encode(a);
}

const _container = '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''';

/// _comic is three pages of the History book, as the canvas exports it.
CanvasDocument _comic() {
  LayoutElement layout(String id) => LayoutElement(
      ElementBase(id: id, x: 20, y: 20, width: 1200, height: 1714),
      root: const LayoutNode.cut(
          vertical: false, a: LayoutNode.leaf("a"), b: LayoutNode.leaf("b")),
      cells: const [LayoutCell(id: "a"), LayoutCell(id: "b")],
      order: const ["b", "a"]);
  return const CanvasDocument(
          title: "Comic", size: CanvasSize(ratio: CanvasRatio.a4, width: 1240))
      .copyWith(kind: CanvasKind.pages)
      .withScenes([
    const CanvasScene(id: "c", name: "Cover"),
    CanvasScene(id: "p1", name: "One", elements: [layout("L1")]),
    CanvasScene(id: "p2", name: "Two", elements: [layout("L2")]),
  ], at: 0);
}

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp("epub-test"));
  tearDown(() async => tmp.delete(recursive: true));

  group("unpacking", () {
    test("a name that climbs out of the book is refused", () async {
      expect(safeJoin("/b", "OPS/p.xhtml"), "/b/OPS/p.xhtml");
      expect(safeJoin("/b", "../etc/passwd"), isNull);
      expect(safeJoin("/b", "OPS/../../x"), isNull);
      expect(safeJoin("/b", "/etc/passwd"), isNull);
      expect(safeJoin("/b", "C:/Windows"), isNull);
      var bad =
          _zip({"../evil.txt": "x", "META-INF/container.xml": _container});
      await expectLater(unpackEpub(bad, tmp.path), throwsA(isA<EpubError>()));
      expect(
          File(path.join(tmp.parent.path, "evil.txt")).existsSync(), isFalse);
    });

    test("what is not a book says so", () async {
      await expectLater(unpackEpub(utf8.encode("hello"), tmp.path),
          throwsA(isA<EpubError>()));
      await expectLater(unpackEpub(_zip({"x.txt": "x"}), tmp.path),
          throwsA(isA<EpubError>()));
    });
  });

  test("a flowing book: its pages, contents and title", () async {
    var book = await unpackEpub(
        _zip({
          "META-INF/container.xml": _container,
          "OPS/book.opf": '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:title>A Tale</dc:title><dc:creator>Ann</dc:creator><dc:language>en</dc:language>
</metadata>
<manifest>
<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
<item id="c1" href="text/one%20a.xhtml" media-type="application/xhtml+xml"/>
<item id="c2" href="text/two.xhtml" media-type="application/xhtml+xml"/>
<item id="notes" href="text/notes.xhtml" media-type="application/xhtml+xml"/>
</manifest>
<spine><itemref idref="c1"/><itemref idref="c2"/><itemref idref="notes" linear="no"/></spine>
</package>''',
          "OPS/nav.xhtml":
              '''<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
<nav epub:type="toc"><ol><li><a href="text/one%20a.xhtml">One</a><ol><li><a href="text/two.xhtml#s">Two</a></li></ol></li></ol></nav></body></html>''',
          "OPS/text/one a.xhtml": "<html/>",
          "OPS/text/two.xhtml": "<html/>",
          "OPS/text/notes.xhtml": "<html/>",
        }),
        tmp.path);
    expect(book.title, "A Tale");
    expect(book.authors, ["Ann"]);
    expect(book.fixed, isFalse);
    expect([
      for (var p in book.pages) p.href
    ], [
      "OPS/text/one a.xhtml",
      "OPS/text/two.xhtml"
    ], reason: "a page out of the reading order is left out");
    expect([for (var c in book.contents) (c.title, c.depth)],
        [("One", 0), ("Two", 1)]);
    expect(book.pageOf(book.contents[1].href), 1);
  });

  testWidgets("the History book as the canvas exports it", (tester) async {
    var out = await tester.runAsync(
        () => renderDocument(_comic(), as: DocumentAs.epub, spreads: true));
    var book = (await tester.runAsync(() => unpackEpub(out!.data, tmp.path)))!;
    expect(book.fixed, isTrue);
    expect(book.spread, EpubSpread.landscape);
    expect(book.pages.length, 3);
    expect(book.pages.first.width, greaterThan(0));
    // The cover alone on the right, then the next two face each other.
    expect(book.spreads, [(null, 0), (1, 2)]);
    // The panels, from the Panel View marks, in the order set: b, then a.
    var panels = book.pages[1].panels;
    expect(panels.length, 2);
    expect(panels.first.y, greaterThan(panels.last.y),
        reason: "b (the lower panel) is read first");
    expect(panels.every((p) => p.width > 0.5 && p.x >= 0 && p.x < 0.1), isTrue);
  });

  group("spreads", () {
    EpubBook of(List<EpubSide> sides) => EpubBook(
        folder: "/b",
        title: "",
        layout: EpubLayout.fixed,
        pages: [for (var (i, s) in sides.indexed) EpubPage("p$i", side: s)]);

    test("a page marked for a side keeps it; centred stands alone", () {
      expect(
          of([EpubSide.center, EpubSide.left, EpubSide.right, EpubSide.right])
              .spreads,
          [(0, null), (1, 2), (null, 3)]);
      expect(of(List.filled(5, EpubSide.any)).spreads,
          [(null, 0), (1, 2), (3, 4)]);
      expect(of([EpubSide.any, EpubSide.left]).spreads, [(null, 0), (1, null)]);
    });
  });

  testWidgets("the reader test book opens: one scripted page", (tester) async {
    var book =
        (await tester.runAsync(() => unpackEpub(readerTestBook(), tmp.path)))!;
    expect(book.title, "Reader test");
    expect(book.pages.single.width, 1240);
    expect(book.pages.single.height, 1754);
  });

  testWidgets("the view: its place, its buttons, and no web view in a test",
      (tester) async {
    var out = await tester.runAsync(
        () => renderDocument(_comic(), as: DocumentAs.epub, spreads: true));
    var file = File(path.join(tmp.path, "Comic.epub"));
    await tester.runAsync(() => file.writeAsBytes(out!.data));
    var turned = <int>[];
    var key = GlobalKey<EpubReaderViewState>();
    setTestScreen(tester, const Size(900, 1000));
    await tester.pumpWidget(canvasApp(
        EpubReaderView(key: key, filePath: file.path, onPage: turned.add)));
    for (var i = 0;
        i < 400 &&
            key.currentState?.book == null &&
            find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(key.currentState!.book, isNotNull,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(" | "));
    expect(find.byKey(const ValueKey("epubNoView")), findsOneWidget);
    expect(find.text("Page 1 of 3"), findsOneWidget,
        reason: "upright, one page at a time");
    await tester.tap(find.byKey(const ValueKey("epubForward")));
    await tester.pump();
    expect(find.text("Page 2 of 3"), findsOneWidget);
    expect(turned, [1]);
    // Wide: the spreads, the cover alone.
    setTestScreen(tester, const Size(1600, 800));
    await tester.pump();
    await tester.pump();
    expect(find.text("Pages 2–3 of 3"), findsOneWidget);
    expect(
        File(path.join(key.currentState!.book!.folder, readerShellName))
            .existsSync(),
        isTrue,
        reason: "the shell beside the pages");
    await tester.pumpWidget(const SizedBox());
  });

  // Ken, 2026-11-19: "double click on a panel then swipe to move back and
  // forward through the panels in order", as Kindle's Panel View does.
  testWidgets("Panel View: a double tap, then panel by panel across pages",
      (tester) async {
    var out = await tester.runAsync(
        () => renderDocument(_comic(), as: DocumentAs.epub, spreads: true));
    var file = File(path.join(tmp.path, "Comic.epub"));
    await tester.runAsync(() => file.writeAsBytes(out!.data));
    var key = GlobalKey<EpubReaderViewState>();
    setTestScreen(tester, const Size(900, 1000));
    await tester.pumpWidget(canvasApp(
        EpubReaderView(key: key, filePath: file.path, initialPage: 1)));
    for (var i = 0; i < 400 && key.currentState?.book == null; i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    var r = key.currentState!;
    var panels = r.book!.pages[1].panels;
    // A double tap inside the first panel read (b, the lower one).
    var b = panels.first;
    r.doubleTap("single", b.x + b.width / 2, b.y + b.height / 2);
    await tester.pump();
    expect(r.panel, (1, 0));
    expect(find.text("Panel 1 of 2 · page 2"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("epubForward")));
    await tester.pump();
    expect(r.panel, (1, 1));
    await tester.tap(find.byKey(const ValueKey("epubForward")));
    await tester.pump();
    expect((r.panel, r.page), ((2, 0), 2), reason: "onto the next page");
    await tester.tap(find.byKey(const ValueKey("epubBack")));
    await tester.pump();
    expect((r.panel, r.page), ((1, 1), 1), reason: "and back again");
    // Another double tap: whole pages.
    r.doubleTap("single", 0.5, 0.5);
    await tester.pump();
    expect(r.panel, isNull);
    expect(find.text("Page 2 of 3"), findsOneWidget);
    // The bar's button starts at the page's first panel.
    await tester.tap(find.byKey(const ValueKey("epubPanels")));
    await tester.pump();
    expect(r.panel, (1, 0));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(r.panel, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  // A book asks Bison Relay for the keyboard (window.bisonReader.midi), as
  // Apple's web engine has no Web MIDI; the keys reach it from the app's own
  // MIDI connection.
  test("a key on the app's keyboard reaches a tap beside the canvas's", () {
    var midi = MidiInput();
    var canvas = <int>[], book = <(int, int)>[];
    midi.onNote = (k, v) => canvas.add(k);
    void tap(int k, int v) => book.add((k, v));
    midi.addNoteTap(tap);
    midi.handle(Uint8List.fromList([0x90, 60, 100]));
    midi.handle(Uint8List.fromList([0x80, 60, 0]));
    expect(canvas, [60, 60]);
    expect(book, [(60, 100), (60, 0)]);
    midi.removeNoteTap(tap);
    midi.handle(Uint8List.fromList([0x90, 62, 90]));
    expect(book.length, 2, reason: "let go of, it hears no more");

    // A book listening has the keyboard to itself: the canvas's instrument
    // is not played by the same keys a moment later (Ken, 2026-11-19).
    void alone(int k, int v) => book.add((k, v));
    midi.addNoteTap(alone, exclusive: true);
    midi.handle(Uint8List.fromList([0x90, 64, 80]));
    expect(canvas, [60, 60, 62], reason: "the canvas hears nothing new");
    expect(book.last, (64, 80));
    midi.removeNoteTap(alone);
    midi.handle(Uint8List.fromList([0x90, 65, 80]));
    expect(canvas.last, 65, reason: "and has it back once the book is done");
  });

  testWidgets("a page asking for the keyboard is given it, once",
      (tester) async {
    var out = await tester.runAsync(
        () => renderDocument(_comic(), as: DocumentAs.epub, spreads: true));
    var file = File(path.join(tmp.path, "Comic.epub"));
    await tester.runAsync(() => file.writeAsBytes(out!.data));
    var inputs = _Keys();
    var key = GlobalKey<EpubReaderViewState>();
    setTestScreen(tester, const Size(900, 1000));
    await tester.pumpWidget(canvasApp(
        EpubReaderView(key: key, filePath: file.path, inputs: inputs)));
    for (var i = 0; i < 400 && key.currentState?.book == null; i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    key.currentState!.heard([
      {"type": "midi"}
    ]);
    await tester.pump();
    key.currentState!.heard([
      {"type": "midi"}
    ]);
    await tester.pump();
    expect(inputs.asked, 1);
    await tester.pumpWidget(const SizedBox());
    expect(inputs.stopped, isTrue, reason: "closed, the keyboard is let go");
  });
}

class _Keys implements ReaderInputs {
  var asked = 0;
  var stopped = false;
  @override
  Future<VoidCallback?> listenToKeys(
      void Function(int key, int velocity) onKey) async {
    asked++;
    return () => stopped = true;
  }
}
