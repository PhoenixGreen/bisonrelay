import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/export/document_export.dart';
import 'package:bruig/plugin_system/canvas/export/video_export.dart'
    show ffmpegPath;
import 'package:bruig/plugin_system/canvas/model/book_details.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_store_profiles_test.dart is an EPUB made for one store
// (StoreProfile): what it carries and what it is held to. Ken, 2026-11-19,
// step 4 of the ebook plan: Kindle runs no scripts and charges by the
// megabyte, Apple and Kobo cap a page's pixels, and each store asks for an
// author.

CanvasDocument _book([BookDetails details = const BookDetails()]) =>
    const CanvasDocument(
            title: "A book",
            size: CanvasSize(ratio: CanvasRatio.a4, width: 1240))
        .copyWith(kind: CanvasKind.pages, pages: PagesSpec(book: details))
        .withScenes(const [
      CanvasScene(id: "p1", name: "One"),
      CanvasScene(id: "p2", name: "Two"),
    ], at: 0);

void main() {
  Archive open(List<int> bytes) => ZipDecoder().decodeBytes(bytes);
  String text(Archive a, String name) => utf8
      .decode(a.files.firstWhere((f) => f.name == name).content as List<int>);

  testWidgets("Apple's book is interactive, its pages within 5.6 megapixels",
      (tester) async {
    var out = await tester.runAsync(
        () => renderDocument(_book(), scale: 2, profile: StoreProfile.apple));
    var a = open(out!.data);
    expect(out.width * out.height, lessThanOrEqualTo(5600000),
        reason: "an A4 page at twice its size is 8.7 megapixels");
    expect(out.width, greaterThan(1240), reason: "only as small as it must");
    expect(text(a, "META-INF/com.apple.ibooks.display-options.xml"),
        contains("interactive"));
  });

  testWidgets("Kobo's within 3.8 megapixels", (tester) async {
    var out = await tester.runAsync(
        () => renderDocument(_book(), scale: 2, profile: StoreProfile.kobo));
    expect(out!.width * out.height, lessThanOrEqualTo(3800000));
  });

  testWidgets("Kindle's is plain, its pages JPEG where ffmpeg is",
      (tester) async {
    var ffmpeg = await tester.runAsync(ffmpegPath);
    var out = await tester
        .runAsync(() => renderDocument(_book(), profile: StoreProfile.kindle));
    var a = open(out!.data);
    var names = a.files.map((f) => f.name).toSet();
    var opf = text(a, "OEBPS/content.opf");
    expect(text(a, "META-INF/com.apple.ibooks.display-options.xml"),
        isNot(contains("interactive")),
        reason: "Amazon runs no scripts");
    if (ffmpeg == null) {
      expect(names, contains("OEBPS/page0.png"));
      return;
    }
    expect(names, contains("OEBPS/page0.jpg"));
    expect(names, isNot(contains("OEBPS/page0.png")));
    expect(opf, contains('href="page0.jpg" media-type="image/jpeg"'));
    expect(text(a, "OEBPS/page0.xhtml"), contains('src="page0.jpg"'));
    var jpeg = a.files.firstWhere((f) => f.name == "OEBPS/page0.jpg");
    var bytes = jpeg.content as List<int>;
    expect(bytes.sublist(0, 2), [0xFF, 0xD8], reason: "a JPEG's start");
  });

  group("what a store would say", () {
    test("no author is a problem everywhere", () {
      for (var p in StoreProfile.values) {
        var r = storeReadiness(_book(), p);
        expect(r.any((x) => x.problem && x.text.contains("author")), isTrue,
            reason: p.label);
      }
      var done = storeReadiness(
          _book(const BookDetails(author: "Ken", description: "A book.")),
          StoreProfile.kobo);
      expect(done, isEmpty);
    });

    test("Kindle's delivery fee, and how ffmpeg cuts it", () {
      var with_ = storeReadiness(_book(), StoreProfile.kindle);
      var without = storeReadiness(_book(), StoreProfile.kindle, ffmpeg: false);
      String fee(List<Readiness> r) =>
          r.firstWhere((x) => x.text.contains("Amazon keeps")).text;
      expect(fee(with_), contains("MB"));
      expect(without.any((x) => x.text.contains("Install ffmpeg")), isTrue);
      double dollars(String s) =>
          double.parse(RegExp(r"\$(\d+\.\d+)").firstMatch(s)![1]!);
      expect(dollars(fee(without)), greaterThan(dollars(fee(with_))));
    });

    test("Apple: the ISBN that cannot come later, and its limit", () {
      var r = storeReadiness(_book(), StoreProfile.apple, scale: 2);
      expect(r.any((x) => x.text.contains("never later")), isTrue);
      expect(r.any((x) => x.text.contains("5.6-megapixel")), isTrue);
      var small = storeReadiness(_book(), StoreProfile.apple);
      expect(small.any((x) => x.text.contains("megapixel")), isFalse,
          reason: "an A4 page at its own size is within it");
    });

    test("a page held to a limit keeps its shape", () {
      var s = scaleFor(_book(), StoreProfile.kobo, 2);
      var size = _book().size.exportSize;
      expect(size.width * s * size.height * s, lessThanOrEqualTo(3800000));
      expect(scaleFor(_book(), StoreProfile.direct, 2), 2);
    });
  });
}
