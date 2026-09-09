import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_text_fill_test.dart is a picture or a pattern showing through the
// letters.
//
// The thing worth pinning is where the fill is drawn: across the whole line
// and then cut to the shape of the type, rather than restarting inside every
// glyph. That is the whole effect, and it is invisible in the model -- both
// versions have the same settings and only the pixels tell them apart.

Future<Map<int, int>> _ink(TextElement element) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 400, 200),
      Paint()..color = const Color(0xFF000000));
  paintElement(canvas, element, 0,
      document: CanvasDocument(elements: [element]));
  var picture = recorder.endRecording();
  var image = await picture.toImage(400, 200);
  var bytes = (await image.toByteData())!;
  var counts = <int, int>{};
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    var pixel = bytes.getUint32(i);
    counts[pixel] = (counts[pixel] ?? 0) + 1;
  }
  image.dispose();
  picture.dispose();
  return counts;
}

/// _reddish counts pixels the pattern's ink has touched.
///
/// Not an exact colour: every generator draws through _fade, so its ink is
/// mixed with whatever it is over and comes out somewhere between the two.
int _reddish(Map<int, int> ink) {
  var total = 0;
  for (var e in ink.entries) {
    var r = (e.key >> 24) & 0xFF;
    var g = (e.key >> 16) & 0xFF;
    var b = (e.key >> 8) & 0xFF;
    if (r > 0x30 && r > g && r >= b) total += e.value;
  }
  return total;
}

TextElement _headline(TextSpec spec) => TextElement(
      const ElementBase(id: "t", x: 0, y: 20, width: 400, height: 90),
      text: "PATTERN",
      textSpec: spec,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const white = 0xFFFFFFFF;
  const plain = TextSpec(fontSize: 40, color: Color(0xFFFFFFFF));

  group("a pattern inside the letters", () {
    testWidgets("is drawn through them and nowhere else", (tester) async {
      // Cut to the type: nothing of the pattern is outside the words, and
      // the words are no longer the flat colour they were.
      late Map<int, int> flat;
      late Map<int, int> filled;
      await tester.runAsync(() async {
        flat = await _ink(_headline(plain));
        filled = await _ink(_headline(plain.copyWith(
            fill: const TextFill(
          kind: TextFillKind.pattern,
          pattern: ProceduralSpec(
            style: ProceduralStyle.halftone,
            background: Color(0xFF00FF00),
            foreground: Color(0xFFFF0000),
            accent: Color(0xFFFF0000),
          ),
        ))));
      });

      expect(flat[white]!, greaterThan(500), reason: "white letters");
      expect(filled[white] ?? 0, 0,
          reason: "none of the type is the flat colour any more");
      expect(filled[0x00FF00FF] ?? 0, greaterThan(200),
          reason: "the pattern's ground shows through the letters");
      expect(_reddish(filled), greaterThan(20), reason: "and so do its dots");

      // And the letters are still letters: the same pixels are covered as
      // before, give or take the antialiasing.
      var covered = 0;
      for (var e in filled.entries) {
        if (e.key != 0x000000FF) covered += e.value;
      }
      var was = 0;
      for (var e in flat.entries) {
        if (e.key != 0x000000FF) was += e.value;
      }
      expect(covered, closeTo(was, was * 0.25),
          reason: "the fill is the shape of the type: $was then $covered");
    });

    testWidgets("runs through the whole word rather than each letter",
        (tester) async {
      // A pattern restarted inside every glyph is a row of little patterns.
      // Zoomed right in, one letter's worth of the fill is one flat area --
      // so the number of colours in the word says whether the fill is one
      // picture across it or seven copies of the same small one.
      late int across;
      await tester.runAsync(() async {
        across = (await _ink(_headline(plain.copyWith(
                fill: const TextFill(
          kind: TextFillKind.pattern,
          zoom: 1,
          pattern: ProceduralSpec(
            style: ProceduralStyle.speedLines,
            background: Color(0xFF000080),
            foreground: Color(0xFFFFFF00),
            accent: Color(0xFFFFFF00),
          ),
        )))))
            .length;
      });
      // A burst drawn once across the line puts its rays at a different angle
      // in every letter, which is many colours; drawn per letter it would be
      // the same few.
      expect(across, greaterThan(8), reason: "$across colours");
    });

    test("and it survives being saved", () {
      var spec = plain.copyWith(
          fill: const TextFill(
        kind: TextFillKind.pattern,
        zoom: 2.5,
        pattern: ProceduralSpec(style: ProceduralStyle.flames),
      ));
      var back = TextSpec.fromJson(spec.toJson());
      expect(back.fill.kind, TextFillKind.pattern);
      expect(back.fill.pattern.style, ProceduralStyle.flames);
      expect(back.fill.zoom, 2.5);
      expect(back.fill.on, isTrue);

      // A plain colour writes nothing at all.
      expect(plain.toJson().containsKey("fill"), isFalse);
      expect(const TextFill().on, isFalse);
      expect(const TextFill(kind: TextFillKind.image).on, isFalse,
          reason: "a picture fill with no picture is still the colour");
    });
  });

  group("the drawn patterns", () {
    test("are offered alongside the generated backgrounds", () {
      var labels = [for (var s in ProceduralStyle.values) s.label];
      for (var wanted in [
        "Halftone",
        "Speed lines",
        "Crosshatch",
        "Paint splatter",
        "Flames",
      ]) {
        expect(labels, contains(wanted));
      }
    });

    testWidgets("and each of them draws something", (tester) async {
      // A style in the list that draws nothing is a style somebody chooses
      // once and never again.
      await tester.runAsync(() async {
        for (var style in [
          ProceduralStyle.halftone,
          ProceduralStyle.speedLines,
          ProceduralStyle.crosshatch,
          ProceduralStyle.splatter,
          ProceduralStyle.flames,
        ]) {
          var ink = await _ink(_headline(plain.copyWith(
              fill: TextFill(
            kind: TextFillKind.pattern,
            pattern: ProceduralSpec(
              style: style,
              background: const Color(0xFF00FF00),
              foreground: const Color(0xFFFF0000),
              accent: const Color(0xFFFF00FF),
              density: 0.8,
              intensity: 1,
            ),
          ))));
          expect(_reddish(ink), greaterThan(10),
              reason: "${style.name} drew nothing inside the letters");
        }
      });
    });
  });
}
