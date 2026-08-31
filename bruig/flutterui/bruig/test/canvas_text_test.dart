import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_text_test.dart is about words on the canvas: where they sit in their
// box, how they flow across columns, and what happens when they are hung on a
// line.
//
// Most of it is checked by rendering and reading pixels back, because that is
// the only place the answers are. Alignment in particular passed every model
// test there was while being visibly broken on screen: the value was stored
// and read back correctly, and the painter ignored it.

void main() {
  /// render draws [document] and returns its pixels.
  Future<ui.Image> render(CanvasDocument document) async {
    var recorder = ui.PictureRecorder();
    paintCanvasDocument(ui.Canvas(recorder), document);
    return recorder
        .endRecording()
        .toImage(document.size.width, document.size.height);
  }

  /// inkColumns is which columns of the image have any ink in them, as a
  /// fraction of the width. Enough to say where on the page something was
  /// drawn without caring what it says.
  Future<List<double>> inkColumns(CanvasDocument document) async {
    var image = await render(document);
    var data = await image.toByteData();
    var out = <double>[];
    for (var x = 0; x < image.width; x++) {
      for (var y = 0; y < image.height; y++) {
        var i = (y * image.width + x) * 4;
        if (data!.getUint8(i + 3) > 40 && data.getUint8(i) > 100) {
          out.add(x / image.width);
          break;
        }
      }
    }
    return out;
  }

  CanvasDocument withText(TextElement text) => CanvasDocument(
        size: const CanvasSize(width: 400),
        background: const CanvasBackground(),
        elements: [text],
      );

  TextElement text({
    TextAlignSpec align = TextAlignSpec.left,
    TextColumns columns = const TextColumns(),
    String content = "Hi",
    double size = 40,
  }) =>
      TextElement(
        const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 225),
        text: content,
        textSpec: TextSpec(
            fontSize: size, align: align, color: const Color(0xFFFFFFFF)),
        box: const BoxSpec(padding: 0),
        columns: columns,
      );

  group("alignment", () {
    // The reported bug: every alignment drew at the left. A TextPainter aligns
    // within its own width, and by default that width shrinks to the text --
    // so a centred line was centred inside a box exactly its own size and then
    // drawn at the element's left edge.
    testWidgets("left, centre and right put the words in different places",
        (tester) async {
      late List<double> left, centre, right;
      await tester.runAsync(() async {
        left = await inkColumns(withText(text(align: TextAlignSpec.left)));
        centre = await inkColumns(withText(text(align: TextAlignSpec.center)));
        right = await inkColumns(withText(text(align: TextAlignSpec.right)));
      });

      expect(left, isNotEmpty);
      expect(left.first, lessThan(0.1));
      expect(centre.first, greaterThan(0.3));
      expect(centre.last, lessThan(0.7));
      expect(right.last, greaterThan(0.9));
    });

    testWidgets("centred text is centred on the box", (tester) async {
      late List<double> ink;
      await tester.runAsync(() async {
        ink = await inkColumns(withText(text(align: TextAlignSpec.center)));
      });
      var middle = (ink.first + ink.last) / 2;
      expect(middle, closeTo(0.5, 0.03));
    });
  });

  group("columns", () {
    testWidgets("two columns put ink on both halves with a gutter between",
        (tester) async {
      late List<double> one, two;
      await tester.runAsync(() async {
        var body = List.filled(60, "word").join(" ");
        one = await inkColumns(withText(text(content: body, size: 14)));
        two = await inkColumns(withText(text(
            content: body,
            size: 14,
            columns: const TextColumns(count: 2, gap: 40))));
      });

      // One column fills the width; two leave a clear band down the middle.
      expect(one.where((x) => x > 0.45 && x < 0.55), isNotEmpty);
      expect(two.where((x) => x > 0.47 && x < 0.53), isEmpty,
          reason: "the gutter has no ink in it");
      expect(two.where((x) => x < 0.4), isNotEmpty);
      expect(two.where((x) => x > 0.6), isNotEmpty);
    });

    test("column width divides what is left after the gutters", () {
      const columns = TextColumns(count: 3, gap: 20);
      // 300 wide, two gutters of 20, leaves 260 over three columns.
      expect(columns.columnWidth(300), closeTo(260 / 3, 0.001));
      expect(const TextColumns().columnWidth(300), 300,
          reason: "one column is the whole box and costs nothing");
    });

    test("columns survive a round trip, and one column stays out of the file",
        () {
      var single = withText(text());
      expect(single.encode().contains("columns"), isFalse,
          reason: "the ordinary case adds nothing to a saved document");

      var many = withText(text(
          columns: const TextColumns(
              count: 3, gap: 12, ruleStyle: ColumnRuleStyle.dashed)));
      var back = CanvasDocument.decode(many.encode())!.elements.single
          as TextElement;
      expect(back.columns.count, 3);
      expect(back.columns.gap, 12);
      expect(back.columns.ruleStyle, ColumnRuleStyle.dashed);
    });
  });

  group("text on a line", () {
    CanvasDocument onALine({double curvature = 0}) => CanvasDocument(
          size: const CanvasSize(width: 400),
          background: const CanvasBackground(),
          elements: [
            LineElement(
              const ElementBase(id: "l", x: 40, y: 100, width: 320, height: 0),
              curvature: curvature,
            ),
            TextElement(
              const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 225),
              text: "ALONGTHELINE",
              textSpec: const TextSpec(
                  fontSize: 20,
                  align: TextAlignSpec.left,
                  color: Color(0xFFFFFFFF)),
              box: const BoxSpec(padding: 0),
              curve: const TextOnCurve(elementId: "l"),
            ),
          ],
        );

    testWidgets("the words follow the line rather than the box",
        (tester) async {
      late List<double> ink;
      await tester.runAsync(() async {
        ink = await inkColumns(onALine());
      });
      // The line starts at x=40 of 400, so nothing should be drawn before it.
      expect(ink.first, greaterThan(0.08));
      expect(ink.last, lessThan(0.95));
    });

    test("a curve pointing at nothing falls back to the box", () {
      // The line may have been deleted since. Falling back is visible and
      // fixable; vanishing is neither.
      var document = withText(TextElement(
        const ElementBase(id: "t", width: 400, height: 225),
        text: "Hi",
        curve: const TextOnCurve(elementId: "gone"),
      ));
      expect(() => paintCanvasDocument(
          ui.Canvas(ui.PictureRecorder()), document), returnsNormally);
    });

    test("the attachment survives a round trip", () {
      var document = withText(TextElement(
        const ElementBase(id: "t", width: 400, height: 225),
        text: "Hi",
        curve: const TextOnCurve(elementId: "l", offset: 0.25, away: true),
      ));
      var back =
          CanvasDocument.decode(document.encode())!.elements.single as TextElement;
      expect(back.curve!.elementId, "l");
      expect(back.curve!.offset, 0.25);
      expect(back.curve!.away, isTrue);
    });
  });

  group("layoutText", () {
    test("only fills the width when it is asked to", () {
      // Measuring wants the intrinsic width -- a player's name is placed by
      // its own size -- so filling cannot be the only behaviour.
      const spec = TextSpec(fontSize: 20);
      var loose = layoutText("Hi", spec, maxWidth: 300);
      var filled = layoutText("Hi", spec, maxWidth: 300, fillWidth: true);

      expect(loose.width, lessThan(300));
      expect(filled.width, 300);
    });
  });

  group("a line's angle", () {
    CanvasDocument angled(double degrees, {bool hide = false}) => CanvasDocument(
          size: const CanvasSize(width: 400),
          background: const CanvasBackground(),
          elements: [
            LineElement(
              // A real height: paintElement skips anything with a zero
              // dimension, so a hairline drawn as height 0 never appears at
              // all. The factory gives a new line four pixels for this reason.
              ElementBase(
                  id: "l", x: 40, y: 99, width: 320, height: 2,
                  rotation: degrees),
            ),
            TextElement(
              const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 225),
              text: "ALONGTHELINE",
              textSpec: const TextSpec(
                  fontSize: 20,
                  align: TextAlignSpec.left,
                  color: Color(0xFFFFFFFF)),
              box: const BoxSpec(padding: 0),
              curve: TextOnCurve(elementId: "l", hideHost: hide),
            ),
          ],
        );

    testWidgets("the text turns with it", (tester) async {
      // Changing a line's angle moved the line and left its text lying flat
      // where the line used to be -- the one thing attaching text to a line is
      // supposed to prevent.
      late List<double> flat, turned;
      await tester.runAsync(() async {
        flat = await inkColumns(angled(0));
        turned = await inkColumns(angled(80));
      });

      expect(flat, isNotEmpty);
      expect(turned, isNotEmpty);
      // Turned almost upright, the words occupy a narrow band rather than the
      // full width of the line.
      var flatSpan = flat.last - flat.first;
      var turnedSpan = turned.last - turned.first;
      expect(turnedSpan, lessThan(flatSpan * 0.6));
    });

    test("hiding the line leaves the words", () {
      // Not the line element's own Hide: a hidden element is skipped
      // everywhere, this one included, so the text would go with it.
      var document = angled(0, hide: true);
      var back = CanvasDocument.decode(document.encode())!;
      var text = back.elements.whereType<TextElement>().single;
      expect(text.curve!.hideHost, isTrue);
      expect(back.elements.whereType<LineElement>().length, 1,
          reason: "the line is still in the document, just not drawn");
    });

    testWidgets("a hidden line draws nothing of itself", (tester) async {
      late List<double> shown, hidden;
      await tester.runAsync(() async {
        shown = await inkColumns(angled(0));
        hidden = await inkColumns(angled(0, hide: true));
      });
      // Both start at the line's own left edge, since the text is laid along
      // it from there -- so what separates them is how much of the width has
      // ink in it. A drawn line is continuous; letters have gaps between them.
      expect(hidden.length, lessThan(shown.length * 0.9));
      expect(hidden, isNotEmpty, reason: "the words are still there");
    });
  });

  group("animatable channels", () {
    test("a keyframe can pin a slide, and it interpolates", () {
      var a = const Keyframe(frame: 0).withValue(KeyframeChannel.slide, 0);
      var b = const Keyframe(frame: 10).withValue(KeyframeChannel.slide, 1);
      var track = ElementTrack([a, b]);

      expect(track.at(0).values[KeyframeChannel.slide], 0);
      expect(track.at(10).values[KeyframeChannel.slide], 1);
      expect(track.at(5).values[KeyframeChannel.slide], closeTo(0.5, 0.001));
    });

    test("a channel only one end pins is held, not faded to zero", () {
      // Guessing a second value would send a caption back to the start of its
      // line the moment it stopped being keyed.
      var a = const Keyframe(frame: 0).withValue(KeyframeChannel.bow, 0.8);
      var b = const Keyframe(frame: 10, dx: 50);
      var track = ElementTrack([a, b]);

      expect(track.at(5).values[KeyframeChannel.bow], 0.8);
      expect(track.at(10).values[KeyframeChannel.bow], 0.8);
    });

    test("channels survive a round trip", () {
      var element = TextElement(
        ElementBase(
          id: "t",
          width: 100,
          height: 40,
          track: ElementTrack([
            const Keyframe(frame: 0).withValue(KeyframeChannel.slide, -0.4),
            const Keyframe(frame: 12).withValue(KeyframeChannel.slide, 0.6),
          ]),
        ),
        curve: const TextOnCurve(elementId: "l"),
      );
      var back = CanvasDocument.decode(
              CanvasDocument(elements: [element]).encode())!.elements.single;
      expect(back.track!.keyAt(12)!.values[KeyframeChannel.slide], 0.6);
    });

    test("a keyframe holding only a channel is not a resting pose", () {
      // isRest decides whether a track is worth keeping, so a keyframe that
      // pins a slide and nothing else must not look empty.
      var key = const Keyframe(frame: 4).withValue(KeyframeChannel.bow, 0.2);
      expect(key.isRest, isFalse);
      expect(const Keyframe(frame: 4).isRest, isTrue);
    });

    testWidgets("an animated slide moves the words along the line",
        (tester) async {
      late List<double> early, late_;
      await tester.runAsync(() async {
        CanvasDocument at(int frame) => CanvasDocument(
              size: const CanvasSize(width: 400),
              background: const CanvasBackground(),
              frames: 20,
              elements: [
                const LineElement(ElementBase(
                    id: "l", x: 20, y: 99, width: 360, height: 2)),
                TextElement(
                  ElementBase(
                    id: "t",
                    width: 400,
                    height: 225,
                    track: ElementTrack([
                      const Keyframe(frame: 0)
                          .withValue(KeyframeChannel.slide, -0.35),
                      const Keyframe(frame: 10)
                          .withValue(KeyframeChannel.slide, 0.35),
                    ]),
                  ),
                  text: "GO",
                  textSpec: const TextSpec(
                      fontSize: 24, color: Color(0xFFFFFFFF)),
                  box: const BoxSpec(padding: 0),
                  curve: const TextOnCurve(elementId: "l", hideHost: true),
                ),
              ],
            );

        var recorder = ui.PictureRecorder();
        paintCanvasDocument(ui.Canvas(recorder), at(0), frame: 0);
        var image = await recorder.endRecording().toImage(400, 225);
        early = await _inkOf(image);

        recorder = ui.PictureRecorder();
        paintCanvasDocument(ui.Canvas(recorder), at(10), frame: 10);
        image = await recorder.endRecording().toImage(400, 225);
        late_ = await _inkOf(image);
      });

      expect(early, isNotEmpty);
      expect(late_, isNotEmpty);
      expect(late_.first, greaterThan(early.first + 0.2),
          reason: "the caption travelled along the line");
    });
  });
}

/// _inkOf is which columns of [image] have ink, as fractions of its width.
Future<List<double>> _inkOf(ui.Image image) async {
  var data = await image.toByteData();
  var out = <double>[];
  for (var x = 0; x < image.width; x++) {
    for (var y = 0; y < image.height; y++) {
      var i = (y * image.width + x) * 4;
      if (data!.getUint8(i + 3) > 40 && data.getUint8(i) > 100) {
        out.add(x / image.width);
        break;
      }
    }
  }
  return out;
}
