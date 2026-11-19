import 'package:bruig/plugin_system/canvas/export/document_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_document_estimate_test.dart is the size the publish sheet says a
// book will be. Ken, 2026-11-19: the piano book was estimated at 4 MB and
// made at 17 -- the estimate counted only the page pictures, and the book
// carried its piano's sound once a page. An interactive book's estimate
// counts what it carries, and a piano played on every page once.

AudioElement _piano(String id, {int lowKey = 48}) =>
    AudioElement(ElementBase(id: id, x: 100, y: 1000, width: 1000, height: 200),
        clip: const MediaClip(timed: true),
        instrument: InstrumentPart(lowKey: lowKey));

CanvasDocument _book(List<AudioElement> pianos) => const CanvasDocument(
            title: "Piano",
            size: CanvasSize(ratio: CanvasRatio.a4, width: 1240))
        .copyWith(kind: CanvasKind.pages)
        .withScenes([
      for (var (i, p) in pianos.indexed)
        CanvasScene(id: "p$i", name: "Lesson $i", elements: [p]),
    ], at: 0);

void main() {
  test("a book that plays carries more than its pages", () {
    var book = _book([_piano("a"), _piano("b")]);
    var plain = estimateDocumentBytes(book);
    var interactive = estimateDocumentBytes(book, interactive: true);
    expect(interactive, greaterThan(plain * 2),
        reason: "each page's picture, what plays on it, and its sound");
  });

  test("the same piano on every page is carried once", () {
    var same = estimateDocumentBytes(_book([_piano("a"), _piano("b")]),
        interactive: true);
    var two = estimateDocumentBytes(
        _book([_piano("a"), _piano("b", lowKey: 36)]),
        interactive: true);
    var keys = const InstrumentPart().keys;
    expect(two - same, (keys * 1.6 * 96 * 1000 / 8).round(),
        reason: "a second, different piano adds its keys once");
  });

  test("the videos it carries are added as stored", () {
    var book = _book([_piano("a")]);
    expect(
        estimateDocumentBytes(book, interactive: true, mediaBytes: 5000000) -
            estimateDocumentBytes(book, interactive: true),
        5000000);
    expect(estimateDocumentBytes(book, mediaBytes: 5000000),
        estimateDocumentBytes(book),
        reason: "a plain book carries no video");
  });
}
