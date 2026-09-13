import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_text_columns_test.dart is a paragraph broken into columns.
//
// Two things were wrong with it and they had the same cause: the columns were
// worked out from a height rather than from the lines. A column showed
// whatever fitted in its rectangle, so a line three quarters taller than the
// room left over showed three quarters of itself along the bottom -- and the
// same three quarters appeared again at the top of the next column.

void main() {
  group("where one column stops and the next starts", () {
    /// lines is a paragraph laid out at [height] a line, out of a font whose
    /// letters want a little more room than that -- which is the ordinary
    /// case: Inter at a line height of 1.2 asks for 19.2 and is given 19.
    List<ui.LineMetrics> lines(int count,
        {double height = 19, double ascent = 15.4, double descent = 3.8}) {
      return [
        for (var i = 0; i < count; i++)
          ui.LineMetrics(
            hardBreak: false,
            ascent: ascent,
            descent: descent,
            unscaledAscent: ascent,
            height: height,
            width: 100,
            left: 0,
            baseline: height * i + ascent,
            lineNumber: i,
          ),
      ];
    }

    test("the edge is below the ink of the line above it", () {
      // A line's ascent and descent are the font's; a line's height is the
      // type's. Set tighter than the font wants -- which is most of the
      // time -- the descenders of one line hang below the box of the next, so
      // a column cut at the box boundary began with the bottom of a line that
      // belonged to the column before it.
      var metrics = lines(4);
      var edges = lineEdges(metrics);
      expect(edges.length, 5, reason: "four lines have five boundaries");
      expect(edges.first, 0);

      for (var i = 0; i < metrics.length; i++) {
        var ink = metrics[i].baseline + metrics[i].descent;
        expect(edges[i + 1], greaterThan(ink),
            reason: "nothing of line $i survives the edge under it");
      }
    });

    test("and above the letters of the line below it", () {
      // The other half: the edge must not eat into the line that starts
      // there. It takes the empty room over its capitals and nothing more.
      var metrics = lines(4);
      var edges = lineEdges(metrics);
      for (var i = 1; i < metrics.length; i++) {
        var capitals = metrics[i].baseline - metrics[i].ascent * 0.75;
        expect(edges[i], lessThan(capitals), reason: "line $i is not cut into");
      }
    });

    test("and where the two cannot both be had, the letters win", () {
      // Set tight enough -- and some headlines are -- the descenders of one
      // line reach past the capitals of the next, and no cut shows all of
      // both. Given that choice, a sliver of a descender is better than
      // flattened capitals.
      var metrics = lines(4, height: 15);
      var edges = lineEdges(metrics);
      for (var i = 1; i < metrics.length; i++) {
        var capitals = metrics[i].baseline - metrics[i].ascent * 0.75;
        expect(edges[i], lessThan(capitals), reason: "line $i is not cut into");
        expect(edges[i], greaterThan(metrics[i].baseline - metrics[i].ascent),
            reason: "and the edge has still moved down off the box boundary");
      }
    });

    test("and the tidying is on to begin with", () {
      // A column top that begins with a blank line is a fault every time it
      // happens, so the setting is there to turn the tidying off rather than
      // to ask for it.
      expect(const TextColumns().noBlankStart, isTrue);
    });

    test("and the setting survives being saved on a one-column box", () {
      // It is asked of a box with one column too -- a chain of boxes is the
      // same question asked of boxes -- and the columns were only written out
      // when there was more than one of them, so it was forgotten every time
      // the canvas was opened. Turned *off* now, since on is the default and
      // off is the thing that would be forgotten.
      var element = TextElement(
        const ElementBase(id: "t", width: 400, height: 200),
        text: "Words",
        columns: const TextColumns(noBlankStart: false),
      );
      var back = elementFromJson(element.toJson()) as TextElement;
      expect(back.columns.noBlankStart, isFalse);
      expect(back.columns.count, 1);

      // And a box with nothing to say still writes nothing.
      expect(
          TextElement(const ElementBase(id: "t"), text: "Words")
              .toJson()
              .containsKey("columns"),
          isFalse);
    });

    test("a blank line is not left at the top of a column", () {
      // The gap between two paragraphs is a line like any other, and a column
      // that starts on one starts with an empty row -- which reads as a
      // mistake in the setting rather than as a paragraph break.
      var metrics = [
        for (var (i, width) in [100.0, 100.0, 0.0, 100.0, 100.0, 100.0].indexed)
          ui.LineMetrics(
            hardBreak: false,
            ascent: 15.4,
            descent: 3.8,
            unscaledAscent: 15.4,
            height: 19,
            width: width,
            left: 0,
            baseline: 19 * i + 15.4,
            lineNumber: i,
          ),
      ];

      // Two lines to a column, so the second one would start on the blank.
      var left = columnRuns(metrics, 40, 3);
      expect(left[1].$1, 2, reason: "the blank line begins the second column");

      var tidied = columnRuns(metrics, 40, 3, noBlankStart: true);
      expect(tidied[1].$1, 3, reason: "passed over rather than drawn");
      expect(tidied[0], left[0], reason: "and the first column is untouched");
    });

    test("a paragraph the font is happy with is cut at the line boxes", () {
      // Nothing to move: with room to spare the boundary is the box's own.
      var metrics = lines(3, height: 30);
      var edges = lineEdges(metrics);
      expect(edges[1], closeTo(30, 0.6));
      expect(edges[2], closeTo(60, 0.6));
    });
  });
  TestWidgetsFlutterBinding.ensureInitialized();

  /// lines lays a paragraph out and hands back its line metrics, which is
  /// what the packing works from.
  List<ui.LineMetrics> lines(String text, TextSpec spec, double width) =>
      layoutText(text, spec, maxWidth: width, fillWidth: true)
          .computeLineMetrics();

  const spec = TextSpec(fontSize: 10, lineHeight: 1.2);
  var paragraph = List.filled(60, "some words that wrap around").join(" ");

  group("which lines go in which column", () {
    test("a line that does not fit goes to the next column whole", () {
      var metrics = lines(paragraph, spec, 200);
      expect(metrics.length, greaterThan(12));

      // A height deliberately between two lines: the packing must round down.
      var lineHeight = metrics.first.height;
      var runs = columnRuns(metrics, lineHeight * 5.75, 3);

      expect(runs.length, 3);
      expect(runs.first.$2 - runs.first.$1, 5,
          reason: "five whole lines, not five and three quarters");
      // And the next column starts exactly where the last one stopped.
      expect(runs[1].$1, runs[0].$2);
      expect(runs[2].$1, runs[1].$2);
    });

    test("no line is in two columns, and none is skipped", () {
      var metrics = lines(paragraph, spec, 160);
      var runs = columnRuns(metrics, metrics.first.height * 7.4, 4);

      var seen = <int>[];
      for (var (from, to) in runs) {
        for (var i = from; i < to; i++) {
          seen.add(i);
        }
      }
      expect(seen, seen.toSet().toList(), reason: "no line drawn twice");
      expect(seen, List.generate(seen.length, (i) => i),
          reason: "and none left out of the middle");
    });

    test("a column too short for one line still gets one", () {
      // Otherwise a box shorter than a line takes no lines at all and draws
      // nothing, which reads as the text having been lost.
      var metrics = lines(paragraph, spec, 200);
      var runs = columnRuns(metrics, 1, 2);
      expect(runs.length, 2);
      expect(runs.first.$2 - runs.first.$1, 1);
    });

    test("text that fits in one column leaves the rest empty", () {
      var metrics = lines("Just a line", spec, 400);
      var runs = columnRuns(metrics, 500, 3);
      expect(runs.length, 1, reason: "no empty columns are asked for");
    });

    test("nothing at all is no columns", () {
      expect(columnRuns(const [], 100, 3), isEmpty);
      expect(columnRuns(lines("x", spec, 100), 100, 0), isEmpty);
    });
  });

  group("fitting the type to the box", () {
    test("a paragraph in three columns is set larger than in one", () {
      // Fitted to one column's box, the type came out a third of the size it
      // could be and all of it landed in the first column -- which read as
      // columns not working with Fit to box at all.
      const box = Size(200, 300);
      var one = fitFontSize(paragraph, spec, box);
      var three = fitFontSize(paragraph, spec, box, columns: 3);
      expect(three, greaterThan(one * 1.4));
    });

    test("and the fitted size really does fit", () {
      const box = Size(200, 300);
      var size = fitFontSize(paragraph, spec, box, columns: 3);
      var metrics = lines(paragraph, spec.copyWith(fontSize: size), box.width);
      var runs = columnRuns(metrics, box.height, 3);
      expect(runs.last.$2, metrics.length,
          reason: "every line is in one of the three columns");
    });

    test("one column is what it always was", () {
      const box = Size(200, 300);
      expect(fitFontSize(paragraph, spec, box, columns: 1),
          fitFontSize(paragraph, spec, box));
    });
  });

  group("the type a text element is drawn in", () {
    TextElement text({bool autoSize = false, int columns = 1}) => TextElement(
          const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 300),
          text: "A paragraph that is long enough to wrap several times over",
          textSpec: const TextSpec(fontSize: 12),
          autoSize: autoSize,
          columns: TextColumns(count: columns),
        );

    test("is the type it is set in, unless it is being fitted", () {
      var plain = text();
      expect(drawnTextSpec(plain, plain.bounds).fontSize, 12);

      var fitted = text(autoSize: true);
      expect(drawnTextSpec(fitted, fitted.bounds).fontSize, isNot(12),
          reason: "Fit to box takes its size from the room");
    });

    test("and the columns are part of the room", () {
      var one = text(autoSize: true);
      var three = text(autoSize: true, columns: 3);
      // Three narrow columns of the same height hold more text than one wide
      // one of that height, so the type can be larger -- but each line is
      // narrower, so it is not three times larger.
      expect(drawnTextSpec(three, three.bounds).fontSize,
          isNot(drawnTextSpec(one, one.bounds).fontSize));
    });

    test("an empty box is left alone rather than divided by nothing", () {
      var thin = TextElement(
        const ElementBase(id: "t", x: 0, y: 0, width: 0, height: 0),
        text: "x",
        autoSize: true,
      );
      expect(drawnTextSpec(thin, thin.bounds).fontSize, thin.textSpec.fontSize);
    });
  });

  group("the rule between two columns", () {
    /// bottoms is how far down the picture the text reaches and how far the
    /// rule reaches, in pixels. Measured off the drawing, because where a
    /// line is drawn is the whole question.
    Future<(double, double)> bottoms(TextElement element, Size size) async {
      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      canvas.drawRect(
          Offset.zero & size, Paint()..color = const Color(0xFF000000));
      paintElement(canvas, element, 0);
      var picture = recorder.endRecording();
      var image =
          await picture.toImage(size.width.round(), size.height.round());
      var bytes = (await image.toByteData())!;

      // Read the way the bytes come -- red, green, blue, alpha -- where a
      // Color is written alpha first.
      var text = 0.0, rule = 0.0;
      for (var y = 0; y < size.height; y++) {
        for (var x = 0; x < size.width; x++) {
          var pixel = bytes.getUint32(((y * size.width.round()) + x) * 4);
          if (pixel == 0x00FFFFFF) rule = y.toDouble();
          if (pixel == 0xFFFFFFFF) text = y.toDouble();
        }
      }
      image.dispose();
      picture.dispose();
      return (text, rule);
    }

    testWidgets("stops with the text rather than with the box", (tester) async {
      // The columns hold a whole number of lines, so the room under the last
      // one is not text -- and a rule drawn through it is a line beside a row
      // that is not there. It reached the bottom of the box, which on the
      // reported canvas was the best part of another row.
      const size = Size(400, 300);
      const fontSize = 14.0;
      var element = TextElement(
        const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 300),
        // Short: it lands in the first column and does not fill it, which is
        // when the rule ran on furthest.
        text: "Four short lines, and no more.",
        textSpec: const TextSpec(fontSize: fontSize, color: Color(0xFFFFFFFF)),
        columns: const TextColumns(
          count: 3,
          gap: 20,
          ruleStyle: ColumnRuleStyle.solid,
          ruleWidth: 2,
          ruleColor: Color(0xFF00FFFF),
        ),
      );

      late double text;
      late double rule;
      await tester.runAsync(() async {
        (text, rule) = await bottoms(element, size);
      });

      expect(rule, greaterThan(10), reason: "it should be drawn at all");
      expect(text, greaterThan(10), reason: "and so should the text");
      // A little past the last line is right -- a rule stopping dead on the
      // bottom baseline reads as too short, and descenders hang below it --
      // but not another row past it.
      expect(rule - text, lessThan(fontSize * 1.3),
          reason: "the rule ended at $rule and the text at $text");
    });
  });

  group("a paragraph in columns arriving", () {
    /// spread is how far the ink reaches outside the element's own box.
    Future<int> spread(double reveal) async {
      const size = Size(800, 600);
      const box = Rect.fromLTWH(200, 250, 400, 100);
      var element = TextElement(
        const ElementBase(id: "t", x: 200, y: 250, width: 400, height: 100),
        text: "One two three four five six seven eight nine ten",
        textSpec: const TextSpec(fontSize: 20, color: Color(0xFFFFFFFF)),
        columns: const TextColumns(count: 3, gap: 16),
        animation: const TextAnimation(
            preset: TextAnimationPreset.punch, ease: ChartEase.linear),
      ).withBase(
        track: ElementTrack([
          Keyframe(frame: 0, values: {KeyframeChannel.reveal: reveal}),
        ]),
      );

      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      canvas.drawRect(
          Offset.zero & size, Paint()..color = const Color(0xFF000000));
      paintElement(canvas, element, 0,
          document: CanvasDocument(elements: [element]));
      var picture = recorder.endRecording();
      var image = await picture.toImage(800, 600);
      var bytes = (await image.toByteData())!;
      var outside = 0;
      for (var y = 0; y < 600; y++) {
        for (var x = 0; x < 800; x++) {
          if (bytes.getUint32(((y * 800) + x) * 4) == 0x000000FF) continue;
          if (!box.contains(Offset(x.toDouble(), y.toDouble()))) outside++;
        }
      }
      image.dispose();
      picture.dispose();
      return outside;
    }

    testWidgets("is not cut off at the edge of its column", (tester) async {
      // Each column is clipped to the lines it holds, because every column
      // draws the same paragraph at a different offset and the clip is what
      // makes it show its own share. Animated inside that clip, the clip
      // stayed where the finished text will be while the words moved through
      // it -- so a punch, a slam or a rotate was cut off at the column edge,
      // which a one-column box was not. The motion goes round the columns
      // now, so the clips travel with it.
      late int early;
      late int rest;
      await tester.runAsync(() async {
        early = await spread(0.2);
        rest = await spread(1);
      });
      expect(rest, 0, reason: "at rest the words are inside their box");
      expect(early, greaterThan(1000),
          reason: "twice the size, a fifth of the way through a punch");
    });
  });
}
