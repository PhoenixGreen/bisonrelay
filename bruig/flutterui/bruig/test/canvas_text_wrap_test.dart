import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/text_flow.dart';
import 'package:bruig/plugin_system/canvas/render/text_wrap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_text_wrap_test.dart is words set around the things in their way.
//
// A second way of setting type -- line by line against the elements round the
// box, rather than once as a paragraph -- so what is pinned here is that it
// only happens when it is asked for, that the room it leaves is the room the
// obstacles actually take, and that what the overflow grip says still matches
// what is drawn.

const _words = "One two three four five six seven eight nine ten eleven "
    "twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen "
    "twenty twentyone twentytwo twentythree twentyfour";

TextElement _text({TextWrap wrap = const TextWrap()}) => TextElement(
      const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 200),
      text: _words,
      box: const BoxSpec(padding: 0),
      textSpec: const TextSpec(
          fontSize: 14, align: TextAlignSpec.left, color: Color(0xFFFFFFFF)),
      wrap: wrap,
    );

ShapeElement _blocker({double x = 0, double width = 160}) => ShapeElement(
      ElementBase(id: "s", x: x, y: 40, width: width, height: 80),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("the room a line has", () {
    const box = Rect.fromLTWH(0, 0, 400, 200);

    test("is the whole width where nothing is in the way", () {
      expect(freeRuns(box, const [], 0, 20, WrapSide.both), [(0.0, 400.0)]);
    });

    test("is what is left either side of something narrow", () {
      var runs = freeRuns(
          box, [const Rect.fromLTWH(150, 0, 100, 50)], 0, 20, WrapSide.both);
      expect(runs, [(0.0, 150.0), (250.0, 400.0)]);
    });

    test("and one side of it when that is what was asked for", () {
      var blocked = [const Rect.fromLTWH(150, 0, 100, 50)];
      expect(freeRuns(box, blocked, 0, 20, WrapSide.left), [(0.0, 150.0)]);
      expect(freeRuns(box, blocked, 0, 20, WrapSide.right), [(250.0, 400.0)]);
    });

    test("two things overlapping are one hole", () {
      var runs = freeRuns(
          box,
          [
            const Rect.fromLTWH(100, 0, 100, 50),
            const Rect.fromLTWH(150, 0, 100, 50),
          ],
          0,
          20,
          WrapSide.both);
      expect(runs, [(0.0, 100.0), (250.0, 400.0)]);
    });

    test("and a line below whatever is in the way has all of it back", () {
      var runs = freeRuns(
          box, [const Rect.fromLTWH(150, 0, 100, 50)], 60, 80, WrapSide.both);
      expect(runs, [(0.0, 400.0)]);
    });
  });

  group("what is drawn", () {
    Future<Map<int, int>> ink(CanvasDocument document, {Rect? within}) async {
      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 400, 200),
          Paint()..color = const Color(0xFF000000));
      for (var element in document.elements) {
        if (element is ShapeElement) continue;
        paintElement(canvas, element, 0, document: document);
      }
      var picture = recorder.endRecording();
      var image = await picture.toImage(400, 200);
      var bytes = (await image.toByteData())!;
      var counts = <int, int>{};
      for (var i = 0; i < bytes.lengthInBytes; i += 4) {
        if (within != null) {
          var at = i ~/ 4;
          if (!within.contains(
              Offset((at % 400).toDouble(), (at ~/ 400).toDouble()))) {
            continue;
          }
        }
        var pixel = bytes.getUint32(i);
        counts[pixel] = (counts[pixel] ?? 0) + 1;
      }
      image.dispose();
      picture.dispose();
      return counts;
    }

    int lit(Map<int, int> ink) {
      var total = 0;
      for (var entry in ink.entries) {
        if (entry.key != 0x000000FF) total += entry.value;
      }
      return total;
    }

    testWidgets("keeps out of the way of what overlaps the box",
        (tester) async {
      // The shape sits over the right of the box between y 40 and 120, so
      // there should be no words in that rectangle at all.
      const behind = Rect.fromLTWH(250, 45, 140, 70);
      late int wrapped;
      late int straight;
      await tester.runAsync(() async {
        wrapped = lit(await ink(
            CanvasDocument(elements: [
              _text(wrap: const TextWrap(on: true, gap: 8)),
              _blocker(x: 240, width: 160),
            ]),
            within: behind));
        straight = lit(await ink(
            CanvasDocument(elements: [_text(), _blocker(x: 240, width: 160)]),
            within: behind));
      });
      expect(straight, greaterThan(200),
          reason: "without it the words run under the shape");
      expect(wrapped, 0, reason: "with it they keep out of its way");
    });

    testWidgets("and only when something is actually in the way",
        (tester) async {
      // A box with nothing overlapping it sets exactly as it always did.
      late int alone;
      late int asked;
      await tester.runAsync(() async {
        alone = lit(await ink(CanvasDocument(elements: [_text()])));
        asked = lit(await ink(
            CanvasDocument(elements: [_text(wrap: const TextWrap(on: true))])));
      });
      expect(asked, alone,
          reason: "the same words in the same places: $alone against $asked");
    });
  });

  group("what is never treated as an obstacle", () {
    test("the boxes this one shares its words with", () {
      // They are one paragraph in several places, and they are routinely laid
      // over each other while a chain is being arranged. Treated as something
      // to go around, the box the words come *from* squeezed them into
      // whatever strip was left -- which reads as the wrapping having deleted
      // them.
      var tail = TextElement(
        const ElementBase(id: "t", x: 100, y: 100, width: 430, height: 400),
        text: _words,
        wrap: const TextWrap(on: true, gap: 12),
      );
      var head = TextElement(
        const ElementBase(id: "a", x: 60, y: 130, width: 400, height: 460),
        text: "Head of the chain",
        flowTo: "t",
      );
      var doc = CanvasDocument(elements: [head, tail, _blocker(x: 460)]);

      var blocked = wrapObstacles(tail, doc, 0, tail.bounds);
      expect(blocked.length, 1, reason: "the shape, and not the box in front");
      expect(blocked.single.left, greaterThan(400));

      // And the same from the other end of the chain: the box the words are
      // passed *to* is not something to go around either.
      var fromHead = wrapObstacles(
          head.copyWith(wrap: const TextWrap(on: true)), doc, 0, head.bounds);
      expect(fromHead.any((r) => r.overlaps(tail.bounds.deflate(40))), isFalse,
          reason: "the tail is not in the way: $fromHead");
    });

    test("and nothing at all when going round it would leave no room", () {
      // Something covering the box from side to side leaves nowhere to put
      // the words. Drawn over the top of it they are visibly wrong, which is
      // something to act on; silently deleted they are not.
      var text = _text(wrap: const TextWrap(on: true, gap: 8));
      const room = Rect.fromLTWH(0, 0, 400, 200);
      var across = [const Rect.fromLTRB(-20, -20, 420, 220)];
      expect(wrapFits(_words, text.textSpec, room, across, text.wrap), isFalse);
      expect(
          wrapFits(_words, text.textSpec, room,
              [const Rect.fromLTRB(300, 40, 420, 120)], text.wrap),
          isTrue);
    });
  });

  group("the words that do not fit", () {
    test("are counted against the room the obstacles leave", () {
      // What the overflow grip says has to be what is on the canvas: a box
      // with something in the middle of it holds fewer words than its
      // rectangle suggests.
      const room = Rect.fromLTWH(0, 0, 400, 60);
      const spec = TextSpec(fontSize: 14, align: TextAlignSpec.left);
      var clear = CanvasDocument(elements: [
        _text(wrap: const TextWrap(on: true)),
      ]);
      var blocked = CanvasDocument(elements: [
        _text(wrap: const TextWrap(on: true, gap: 8)),
        _blocker(x: 120, width: 200),
      ]);

      var wideOpen =
          flowFor(clear.elementById("t") as TextElement, clear, room, spec);
      var crowded =
          flowFor(blocked.elementById("t") as TextElement, blocked, room, spec);
      expect(crowded.overflows, isTrue);
      expect(wideOpen.overflows, isTrue);

      // And the crowded box shows less of it.
      var wrappedText = layoutWrapped(
          _words,
          spec,
          room,
          wrapObstacles(
              blocked.elementById("t") as TextElement, blocked, 0, room),
          const TextWrap(on: true, gap: 8));
      var openText =
          layoutWrapped(_words, spec, room, const [], const TextWrap(on: true));
      expect(wrappedText.consumed, lessThan(openText.consumed));
    });
  });
}
