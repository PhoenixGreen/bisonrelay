import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/export/document_export.dart';
import 'package:bruig/plugin_system/canvas/export/epub_check.dart';
import 'package:bruig/plugin_system/canvas/export/epub_tasks.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/play_task_element.dart';
import 'package:flutter/painting.dart' show Rect;
import 'package:flutter_test/flutter_test.dart';

// canvas_epub_tasks_test.dart is a play task card working in an interactive
// EPUB (epub_tasks.dart): the card as drawn, with a layer that ticks each
// step as it is played -- through Bison Relay's keyboard, the reader's MIDI
// or the microphone -- or, where nothing can be heard, as the student taps
// it. Ken, 2026-11-19, step 7 of the ebook plan. The script itself is
// checked in a browser; here, what the book carries for it.

const _task = PlayTaskElement(
    ElementBase(id: "task1", x: 100, y: 1200, width: 1000, height: 400),
    title: "Practise",
    checks: [
      PlayCheck(PlayCheckKind.keys, "Find every C", steps: "C2 C3 C4 C5"),
      PlayCheck(PlayCheckKind.order, "Play the tune", steps: "C4 D4 E4+G4"),
      PlayCheck(PlayCheckKind.along, "Play along with the music"),
      PlayCheck(PlayCheckKind.self, "Say the finger numbers"),
    ]);

CanvasDocument _book() => const CanvasDocument(
            title: "Piano",
            size: CanvasSize(ratio: CanvasRatio.a4, width: 1240))
        .copyWith(kind: CanvasKind.pages)
        .withScenes(const [
      CanvasScene(id: "p1", name: "Lesson one", elements: [_task]),
    ], at: 0);

void main() {
  test("the card's steps, as notes, and where each is on the page", () {
    var t = epubTaskOf(_task, 0.5)!;
    expect(t.box, const Rect.fromLTWH(50, 600, 500, 200));
    var spec = jsonDecode(t.json) as Map<String, dynamic>;
    var checks = spec["checks"] as List;
    expect([for (var c in checks) c["kind"]], ["keys", "order", "self", "self"],
        reason: "play along is the student's to tick in a book");
    expect(checks[0]["steps"], [
      [36],
      [48],
      [60],
      [72]
    ]);
    expect(
        checks[1]["steps"],
        [
          [60],
          [62],
          [64, 67]
        ],
        reason: "a chord's notes together");
    var mark = (checks[0]["mark"] as List).cast<num>();
    expect(mark[2], greaterThan(0));
    expect(spec["again"], isNotNull, reason: "a place for its button");
    expect(spec["banner"], isNotNull);
    expect(
        epubTaskOf(_task.withBase(rotation: 5) as PlayTaskElement, 1), isNull,
        reason: "a turned card is left as drawn");
  });

  testWidgets("an interactive book carries the card's layer and its script",
      (tester) async {
    var out = await tester
        .runAsync(() => renderDocument(_book(), profile: StoreProfile.direct));
    var a = ZipDecoder().decodeBytes(out!.data);
    String text(String name) => utf8
        .decode(a.files.firstWhere((f) => f.name == name).content as List<int>);
    var page = text("OEBPS/page0.xhtml");
    expect(page, contains('class="task"'));
    expect(page, contains('<script src="tasks.js"></script>'));
    expect(text("OEBPS/tasks.js"), contains("bisonReader"));
    expect(text("OEBPS/tasks.js"), contains("requestMIDIAccess"));
    var opf = text("OEBPS/content.opf");
    expect(
        opf, contains('href="tasks.js" media-type="application/javascript"'));
    expect(opf, contains('properties="scripted"'));
    expect(selfCheckEpub(out.data), isEmpty);
  });

  testWidgets("a plain book has the card as drawn, and nothing over it",
      (tester) async {
    var out = await tester
        .runAsync(() => renderDocument(_book(), profile: StoreProfile.kindle));
    var a = ZipDecoder().decodeBytes(out!.data);
    expect(a.files.any((f) => f.name == "OEBPS/tasks.js"), isFalse);
    var page = utf8.decode(a.files
        .firstWhere((f) => f.name == "OEBPS/page0.xhtml")
        .content as List<int>);
    expect(page, isNot(contains('class="task"')));
  });
}
