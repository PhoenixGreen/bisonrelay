import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/export/document_export.dart';
import 'package:bruig/plugin_system/canvas/export/epub_check.dart';
import 'package:bruig/plugin_system/canvas/export/reader_test_book.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

// canvas_epub_check_test.dart is a book checked before it goes to a store
// (epub_check.dart): EPUBCheck where it is installed, as Apple refuses a
// book that fails it, and a check of our own that needs nothing. Ken,
// 2026-11-19, step 5 of the ebook plan.

CanvasDocument _book() => const CanvasDocument(
            title: "A book",
            size: CanvasSize(ratio: CanvasRatio.a4, width: 1240))
        .copyWith(kind: CanvasKind.pages)
        .withScenes(const [
      CanvasScene(id: "p1", name: "One"),
      CanvasScene(id: "p2", name: "Two"),
    ], at: 0);

/// _rezip is [bytes] with [change] made to its files, the mimetype first
/// and stored unless [compressMime].
Uint8List _rezip(List<int> bytes,
    {Map<String, String?> change = const {}, bool compressMime = false}) {
  var from = ZipDecoder().decodeBytes(bytes);
  var to = Archive();
  for (var f in from.files) {
    if (!f.isFile) continue;
    if (change.containsKey(f.name)) {
      var v = change[f.name];
      if (v == null) continue;
      var b = utf8.encode(v);
      to.addFile(ArchiveFile(f.name, b.length, b));
      continue;
    }
    var b = f.content as List<int>;
    var a = ArchiveFile(f.name, b.length, b);
    if (f.name == "mimetype" && !compressMime) {
      a.compression = CompressionType.none;
    }
    to.addFile(a);
  }
  return Uint8List.fromList(ZipEncoder().encode(to));
}

void main() {
  testWidgets("every store's book passes our own check", (tester) async {
    for (var p in StoreProfile.values) {
      var out = await tester
          .runAsync(() => renderDocument(_book(), profile: p, spreads: true));
      expect(selfCheckEpub(out!.data), isEmpty, reason: p.label);
    }
    expect(selfCheckEpub(readerTestBook()), isEmpty, reason: "the test book");
  });

  testWidgets("a broken book is named for what is wrong", (tester) async {
    var good = (await tester.runAsync(
            () => renderDocument(_book(), profile: StoreProfile.plain)))!
        .data;
    expect(selfCheckEpub(utf8.encode("not a zip")), [contains("not a zip")]);
    expect(selfCheckEpub(_rezip(good, compressMime: true)),
        contains(contains("compressed")));
    expect(selfCheckEpub(_rezip(good, change: {"OEBPS/page1.png": null})),
        contains(contains("OEBPS/page1.png is listed but not in the book")));
    expect(
        selfCheckEpub(_rezip(good, change: {"OEBPS/page0.xhtml": "<html><p>"})),
        contains(contains("page0.xhtml is not well-formed")));
    var opf = utf8.decode(ZipDecoder()
        .decodeBytes(good)
        .files
        .firstWhere((f) => f.name == "OEBPS/content.opf")
        .content as List<int>);
    expect(
        selfCheckEpub(_rezip(good, change: {
          "OEBPS/content.opf": opf.replaceFirst('idref="page1"', 'idref="gone"')
        })),
        contains(contains('"gone", which is not in the book')));
  });

  test("EPUBCheck's report: errors stop a store, warnings do not", () {
    var r = parseEpubcheckJson(jsonEncode({
      "messages": [
        {
          "ID": "RSC-005",
          "severity": "ERROR",
          "message": "Error while parsing file",
          "locations": [
            {"path": "OEBPS/page0.xhtml", "line": 12}
          ]
        },
        {"ID": "ACC-011", "severity": "WARNING", "message": "No alt text"},
        {"ID": "INF-1", "severity": "INFO", "message": "fine"},
      ]
    }))!;
    expect(r.errors,
        ["RSC-005: Error while parsing file (OEBPS/page0.xhtml, line 12)"]);
    expect(r.warnings, ["ACC-011: No alt text"]);
    expect(r.passed, isFalse);
    expect(parseEpubcheckJson("{nonsense"), isNull);
  });

  group("through EPUBCheck where it is installed", () {
    late Directory scratch;
    setUp(() async {
      scratch = await Directory.systemTemp.createTemp("bruig-fake-epubcheck");
      var script = File(path.join(scratch.path, "epubcheck"));
      // Writes a report naming one warning to the --json path it is given.
      await script.writeAsString('''#!/bin/sh
while [ \$# -gt 0 ]; do
  if [ "\$1" = "--json" ]; then shift; out="\$1"; fi
  shift
done
printf '{"messages":[{"ID":"OPF-085","severity":"WARNING","message":"dc:identifier is not a UUID"}]}' > "\$out"
''');
      await Process.run("chmod", ["+x", script.path]);
      useEpubcheckForTest(script.path);
    });
    tearDown(() async {
      forgetEpubcheckForTest();
      await scratch.delete(recursive: true);
    });

    testWidgets("its findings are read beside our own", (tester) async {
      var out = await tester
          .runAsync(() => renderDocument(_book(), profile: StoreProfile.apple));
      var report = (await tester.runAsync(() => checkEpub(out!.data)))!;
      expect(report.byEpubcheck, isTrue);
      expect(report.passed, isTrue);
      expect(report.warnings, ["OPF-085: dc:identifier is not a UUID"]);
    });
  });

  testWidgets("without EPUBCheck, our own check alone", (tester) async {
    useEpubcheckForTest(null);
    addTearDown(forgetEpubcheckForTest);
    var out = await tester
        .runAsync(() => renderDocument(_book(), profile: StoreProfile.kobo));
    var report = (await tester.runAsync(() => checkEpub(out!.data)))!;
    expect(report.byEpubcheck, isFalse);
    expect(report.passed, isTrue);
  });
}
