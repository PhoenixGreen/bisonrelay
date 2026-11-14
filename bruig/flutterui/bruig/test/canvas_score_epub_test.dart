import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/export/document_export.dart';
import 'package:bruig/plugin_system/canvas/export/epub_layers.dart';
import 'package:bruig/plugin_system/canvas/export/video_export.dart';
import 'package:bruig/plugin_system/canvas/render/score_sheet.dart';
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

  // Ken, 2026-11-14: "would it be possible to click a note on the
  // instrument and have it play both as a mouse/keyboard input and a midi
  // instrument input?"
  testWidgets("its instrument is one the reader plays", (tester) async {
    var ffmpeg = await tester.runAsync(ffmpegPath);
    await tester.runAsync(() async {
      var c = sheet.lesson();
      c.showSheetKeyboard(sheet.sheetOf(c), true);
      var keys = c.sheetKeyboard(sheet.sheetOf(c))!;
      var built = (await buildEpubStage(c.document, 0,
          pixels: 1, width: 1280, height: 720))!;
      var layer = built.stage.layers.firstWhere((l) => l.id == keys.id);
      var kb = layer.keyboard!;
      var range = keys.instrument!.highKey - keys.instrument!.lowKey + 1;
      expect(kb.keys, hasLength(range), reason: "every key, lit");
      expect(kb.low, keys.instrument!.lowKey);
      expect(kb.keys.where((k) => k.black), hasLength(15));
      // Its sound: each key a slice of one file, the instrument's own.
      var file = built.files.firstWhere((f) => f.href == kb.sound);
      expect(file.mime, ffmpeg == null ? "audio/wav" : "audio/mp4");
      expect(file.bytes.length, greaterThan(20000));
      c.dispose();
    });
  });

  testWidgets("written into the book: a surface to play, every key lit",
      (tester) async {
    await tester.runAsync(() async {
      var c = sheet.lesson();
      c.showSheetKeyboard(sheet.sheetOf(c), true);
      var export =
          (await renderDocument(c.document, as: DocumentAs.interactiveEpub))!;
      var zip = ZipDecoder().decodeBytes(export.data);
      String text(String name) =>
          utf8.decode(zip.files.firstWhere((f) => f.name == name).content);
      var page = XmlDocument.parse(text("OEBPS/page0.xhtml"));
      var board = page.descendantElements
          .firstWhere((e) => (e.getAttribute("class") ?? "") == "hit keys");
      // A button: a div there left the keyboard under it undrawn.
      expect(board.name.local, "button");
      var keys = jsonDecode(board.getAttribute("data-keys")!) as List;
      expect(keys, hasLength(37));
      expect(zip.files.map((f) => f.name),
          contains("OEBPS/${board.getAttribute("data-sound")}"),
          reason: "its sound is in the book");
      expect(
          page.descendantElements
              .where((e) => (e.getAttribute("class") ?? "") == "pic kp"),
          hasLength(37));
      var script = text("OEBPS/media.js");
      for (var bit in [
        "awsedftgyhujk",
        "requestMIDIAccess",
        "decodeAudioData"
      ]) {
        expect(script, contains(bit), reason: bit);
      }
      c.dispose();
    });
  });

  testWidgets("a range of bars: its Play plays them, its track goes along them",
      (tester) async {
    await tester.runAsync(() async {
      var c = sheet.lesson();
      c.replaceElement(sheet.sheetOf(c).copyWith(fromBar: 2, toBar: 3));
      var (start, end) = sheetFrames(sheet.sheetOf(c), c.document)!;
      var built = (await buildEpubStage(c.document, 0,
          pixels: 1, width: 1280, height: 720))!;
      var s = built.stage.layers.firstWhere((l) => l.id == "sheet");
      var play = s.controls.firstWhere((b) => b.label == "Play");
      expect(play.act, "range");
      expect([play.data["from"], play.data["to"]], ["$start", "$end"]);
      var seek = s.controls.firstWhere((b) => b.act == "seek");
      expect([seek.data["from"], seek.data["to"]], ["$start", "$end"]);
      var steps = s.controls
          .firstWhere((b) => b.act == "next")
          .data["frames"]!
          .split(",")
          .map(int.parse);
      expect(steps.every((f) => f >= start && f < end), isTrue);
      c.dispose();
    });
  });
}
