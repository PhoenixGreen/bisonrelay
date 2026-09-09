import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/text_flow.dart';
import 'package:bruig/plugin_system/canvas/render/image_silhouette.dart';
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
          box,
          [const WrapShape(Rect.fromLTWH(150, 0, 100, 50))],
          0,
          20,
          WrapSide.both);
      expect(runs, [(0.0, 150.0), (250.0, 400.0)]);
    });

    test("and one side of it when that is what was asked for", () {
      var blocked = [const WrapShape(Rect.fromLTWH(150, 0, 100, 50))];
      expect(freeRuns(box, blocked, 0, 20, WrapSide.left), [(0.0, 150.0)]);
      expect(freeRuns(box, blocked, 0, 20, WrapSide.right), [(250.0, 400.0)]);
    });

    test("two things overlapping are one hole", () {
      var runs = freeRuns(
          box,
          [
            const WrapShape(Rect.fromLTWH(100, 0, 100, 50)),
            const WrapShape(Rect.fromLTWH(150, 0, 100, 50)),
          ],
          0,
          20,
          WrapSide.both);
      expect(runs, [(0.0, 100.0), (250.0, 400.0)]);
    });

    test("and a line below whatever is in the way has all of it back", () {
      var runs = freeRuns(
          box,
          [const WrapShape(Rect.fromLTWH(150, 0, 100, 50))],
          60,
          80,
          WrapSide.both);
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

  group("a paragraph break", () {
    const paragraphs = "unpredictable.\n\nNow, I've applied the mobile theme "
        "settings to remove the back and three-dot buttons, creating a much "
        "cleaner and more consistent experience.\n\nThe navigation now uses "
        "the same first-, second- and third-click behaviour.";
    const spec = TextSpec(fontSize: 16, align: TextAlignSpec.left);
    const box = Rect.fromLTWH(35, 35, 280, 420);

    test("does not stop the rest of the words being set", () {
      // The reported fault, and it had nothing to do with the shape: fitting
      // words cannot advance past a line break, so a paragraph gap that
      // nothing consumed stalled the layout on it and everything after the
      // first paragraph was lost.
      var out = layoutWrapped(
          paragraphs,
          spec,
          box,
          [const WrapShape(Rect.fromLTRB(293, 110, 577, 365))],
          const TextWrap(on: true));
      expect(out.consumed, paragraphs.length,
          reason: "all of it, not just the first line");
      expect(out.lines.length, greaterThan(10));

      // And it is a line of its own, so the paragraphs are still apart.
      var first = out.lines.first;
      var second = out.lines[1];
      expect(
          second.box.top - first.box.top, greaterThan(first.box.height * 1.5),
          reason: "an empty line between them");
    });

    test("and the words still keep out of the way", () {
      var out = layoutWrapped(
          paragraphs,
          spec,
          box,
          [const WrapShape(Rect.fromLTRB(293, 110, 577, 365))],
          const TextWrap(on: true));
      var beside = out.lines.where((l) => l.box.top > 110 && l.box.top < 340);
      expect(beside, isNotEmpty);
      expect(beside.every((l) => l.box.right <= 293.5), isTrue,
          reason: "narrowed while the shape is beside them");
      expect(out.lines.last.box.right, box.right,
          reason: "and the full width again below it");
    });

    test("and no line starts with the space it broke on", () {
      var out = layoutWrapped(
          paragraphs, spec, box, const [], const TextWrap(on: true));
      for (var line in out.lines) {
        expect(paragraphs[line.from].trim(), isNotEmpty,
            reason: "a line beginning with a space starts a word's width in");
      }
    });
  });

  group("how tightly the words follow", () {
    test("a round shape, which is not its box", () {
      // A circle's box is a square: kept to that, the words stayed clear of
      // the corners as though they were full, most obviously by the top and
      // bottom of the circle where there is nearly a whole square of room
      // they would not go into.
      var text = TextElement(
        const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 320),
        text: _words,
        wrap: const TextWrap(on: true, gap: 8),
      );
      var circle = ShapeElement(
        const ElementBase(id: "s", x: 200, y: 40, width: 240, height: 240),
        shape: ShapeKind.circle,
      );
      var doc = CanvasDocument(elements: [text, circle]);
      var blocked = wrapObstacles(text, doc, 0, text.bounds);

      double roomAt(double y) =>
          freeRuns(text.bounds, blocked, y, y + 19, WrapSide.both).first.$2;

      // Across the middle the circle is at its widest, and the words stop at
      // its left edge less the gap.
      expect(roomAt(150), closeTo(192, 1));
      // By its top and bottom edges there is much more room, because there is
      // much less circle.
      expect(roomAt(40), greaterThan(roomAt(150) + 30));
      expect(roomAt(240), greaterThan(roomAt(150) + 15));
    });

    test("and a square shape, which is", () {
      var text = TextElement(
        const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 320),
        text: _words,
        wrap: const TextWrap(on: true, gap: 8),
      );
      var square = ShapeElement(
        const ElementBase(id: "s", x: 200, y: 40, width: 240, height: 240),
      );
      var doc = CanvasDocument(elements: [text, square]);
      var blocked = wrapObstacles(text, doc, 0, text.bounds);

      double roomAt(double y) =>
          freeRuns(text.bounds, blocked, y, y + 19, WrapSide.both).first.$2;
      expect(roomAt(40), closeTo(roomAt(150), 1),
          reason: "a rectangle takes the same room out of every line");
    });
  });

  group("a picture", () {
    // A cut-out -- a badge, a player, anything with its background taken out
    // -- does not fill its frame, and the difference is most of the picture.
    // Text set around its box keeps a wide empty margin round nothing.

    /// _Cut is a picture whose ink is a narrow column down the middle: the
    /// left and right thirds of it are see-through.
    late ImageSilhouette narrow;

    setUpAll(() {
      var rows = 64;
      var left = Float32List(rows)..fillRange(0, rows, 1 / 3);
      var right = Float32List(rows)..fillRange(0, rows, 2 / 3);
      narrow = ImageSilhouette(left, right, rows);
    });

    test("is wrapped by its ink, not by its frame", () {
      const drawn = Rect.fromLTWH(200, 0, 300, 300);
      var shape = WrapShape(drawn,
          silhouette: narrow,
          drawn: drawn,
          shown: const Rect.fromLTWH(0, 0, 600, 600),
          picture: const Size(600, 600));

      var span = shape.spanIn(100, 120)!;
      expect(span.$1, closeTo(300, 1), reason: "a third across the picture");
      expect(span.$2, closeTo(400, 1), reason: "two thirds across it");
    });

    test("and a row with nothing on it takes no room at all", () {
      var rows = 8;
      var left = Float32List(rows)..fillRange(0, rows, 2);
      var right = Float32List(rows)..fillRange(0, rows, -1);
      // Ink on the bottom half only.
      for (var row = 4; row < rows; row++) {
        left[row] = 0.25;
        right[row] = 0.75;
      }
      const drawn = Rect.fromLTWH(0, 0, 400, 400);
      var shape = WrapShape(drawn,
          silhouette: ImageSilhouette(left, right, rows),
          drawn: drawn,
          shown: const Rect.fromLTWH(0, 0, 100, 100),
          picture: const Size(100, 100));

      expect(shape.spanIn(20, 40), isNull, reason: "nothing up here");
      var low = shape.spanIn(300, 320)!;
      expect(low.$1, closeTo(100, 1));
      expect(low.$2, closeTo(300, 1));
    });

    testWidgets("and its ink is read from the picture's own alpha",
        (tester) async {
      // The whole point of the profile: a picture with its background taken
      // out is mostly nothing, and where the nothing is is a fact about the
      // pixels.
      late ImageSilhouette read;
      await tester.runAsync(() async {
        var recorder = ui.PictureRecorder();
        var canvas = ui.Canvas(recorder);
        // A disc in the middle of a transparent square.
        canvas.drawCircle(
            const Offset(50, 50), 40, Paint()..color = const Color(0xFFFFFFFF));
        var image = await recorder.endRecording().toImage(100, 100);
        read = (await silhouetteOf(image, rows: 10))!;
        image.dispose();
      });

      // Across the middle the disc is at its widest; at the top and bottom
      // rows there is nothing at all.
      expect(read.left[0] > read.right[0], isTrue,
          reason: "nothing on the first row");
      expect(read.left[5], closeTo(0.1, 0.03));
      expect(read.right[5], closeTo(0.9, 0.03));
      // And a row near the top of the disc is narrower than the middle one.
      expect(
          read.right[1] - read.left[1], lessThan(read.right[5] - read.left[5]));
    });

    test("keeps its box until its ink has been read", () {
      // The profile comes from the decoded pixels and a painter cannot wait
      // for it, so the box is the answer on the first frame and the shape
      // arrives on a later one.
      var text = _text(wrap: const TextWrap(on: true, gap: 4));
      var picture = ImageElement(
        const ElementBase(id: "i", x: 200, y: 40, width: 200, height: 100),
      );
      var doc = CanvasDocument(elements: [text, picture]);
      var blocked = wrapObstacles(text, doc, 0, text.bounds);
      expect(blocked.single.silhouette, isNull);
      expect(blocked.single.spanIn(60, 80), (196.0, 404.0));
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
      expect(blocked.single.bounds.left, greaterThan(400));

      // And the same from the other end of the chain: the box the words are
      // passed *to* is not something to go around either.
      var fromHead = wrapObstacles(
          head.copyWith(wrap: const TextWrap(on: true)), doc, 0, head.bounds);
      expect(fromHead.any((r) => r.bounds.overlaps(tail.bounds.deflate(40))),
          isFalse,
          reason: "the tail is not in the way: $fromHead");
    });

    test("and nothing at all when going round it would leave no room", () {
      // Something covering the box from side to side leaves nowhere to put
      // the words. Drawn over the top of it they are visibly wrong, which is
      // something to act on; silently deleted they are not.
      var text = _text(wrap: const TextWrap(on: true, gap: 8));
      const room = Rect.fromLTWH(0, 0, 400, 200);
      var across = [const WrapShape(Rect.fromLTRB(-20, -20, 420, 220))];
      expect(wrapFits(_words, text.textSpec, room, across, text.wrap), isFalse);
      expect(
          wrapFits(_words, text.textSpec, room,
              [const WrapShape(Rect.fromLTRB(300, 40, 420, 120))], text.wrap),
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
