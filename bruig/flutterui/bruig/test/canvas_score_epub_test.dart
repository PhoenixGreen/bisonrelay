import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/export/document_export.dart';
import 'package:bruig/plugin_system/canvas/export/epub_layers.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'canvas_score_sheet_test.dart' as sheet;

// canvas_score_epub_test.dart is a score sheet in an interactive book (Ken,
// 2026-11-14: "Exporting as an epub on Apple books puts a play button over
// the top which when pressed doesn't work ... rather than the ugly play
// button, ... a playbar"). The sheet is pictures the book's clock switches
// and moves -- its pages, each note lit, the playhead, the track -- never a
// film; its playbar is buttons the clock answers; and with it the page has
// no start screen over it.

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp("canvas_score_epub");
    CanvasStorage.rootOverride = root.path;
  });
  tearDown(() async {
    CanvasStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets("the sheet and its keyboard as layers the clock plays",
      (tester) async {
    await tester.runAsync(() async {
      var c = sheet.lesson();
      c.showSheetKeyboard(sheet.sheetOf(c), true);
      var doc = c.document;
      var keys = c.sheetKeyboard(sheet.sheetOf(c))!;
      var built =
          (await buildEpubStage(doc, 0, pixels: 1, width: 1280, height: 720))!;
      var stage = built.stage;
      expect(stage.ownPlay, isTrue, reason: "its playbar plays the page");
      expect(stage.autoplay, isFalse, reason: "nothing until it is pressed");
      var layers = {for (var l in stage.layers) l.id: l};
      var s = layers["sheet"]!;
      expect(s.clip, isNull, reason: "never a film");
      // A page, a picture of each note as it is lit, the playhead, the
      // track's fill and knob: each with its keyframes.
      expect(s.parts.length, greaterThan(10));
      expect(
          s.parts
              .where((p) => p.keys.any((k) => k.css.containsKey("transform"))),
          isNotEmpty,
          reason: "the playhead and the knob move");
      expect(s.parts.where((p) => p.clipKeys.isNotEmpty), hasLength(1),
          reason: "the track's fill");
      expect([for (var b in s.controls) b.act],
          ["goto", "prev", "toggle", "next", "seek"]);
      var step = s.controls.firstWhere((b) => b.act == "next");
      expect(step.data["frames"]!.split(",").length, greaterThan(20),
          reason: "a note start to step to, through the repeats");
      var k = layers[keys.id]!;
      expect(k.clip, isNull);
      expect(k.parts.length, greaterThan(3), reason: "the keys and each lit");
      c.dispose();
    });
  });

  testWidgets("written into the book: the playbar, and no start screen",
      (tester) async {
    await tester.runAsync(() async {
      var c = sheet.lesson();
      var export =
          (await renderDocument(c.document, as: DocumentAs.interactiveEpub))!;
      var zip = ZipDecoder().decodeBytes(export.data);
      String text(String name) =>
          utf8.decode(zip.files.firstWhere((f) => f.name == name).content);
      var page = text("OEBPS/page0.xhtml");
      expect(() => XmlDocument.parse(page), returnsNormally);
      var bar = XmlDocument.parse(page)
          .descendantElements
          .where((e) => (e.getAttribute("class") ?? "") == "hit bar")
          .toList();
      expect([for (var b in bar) b.getAttribute("data-act")],
          ["goto", "prev", "toggle", "next", "seek"]);
      expect(bar[2].findAllElements("span"), isNotEmpty,
          reason: "a pause for while it plays");
      expect(page, contains('data-intro="false"'));
      expect(page, isNot(contains('id="intro"')));
      var script = text("OEBPS/media.js");
      for (var bit in [
        'case "next"',
        'case "seek"',
        'classList.add("playing")',
        'classList.remove("playing")',
      ]) {
        expect(script, contains(bit), reason: bit);
      }
      c.dispose();
    });
  });
}
