import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stroke.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/text_flow.dart';
import 'package:bruig/plugin_system/canvas/render/image_silhouette.dart';
import 'package:bruig/plugin_system/canvas/render/text_wrap.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
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
          const TextWrap(on: true),
          parts: const []);
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
          const TextWrap(on: true),
          parts: const []);
      var beside = out.lines.where((l) => l.box.top > 110 && l.box.top < 340);
      expect(beside, isNotEmpty);
      expect(beside.every((l) => l.box.right <= 293.5), isTrue,
          reason: "narrowed while the shape is beside them");
      expect(out.lines.last.box.right, box.right,
          reason: "and the full width again below it");
    });

    test("and no line starts with the space it broke on", () {
      var out = layoutWrapped(
          paragraphs, spec, box, const [], const TextWrap(on: true),
          parts: const []);
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

  group("a shape is gone round as it is drawn", () {
    // The words go round the outline the shape is drawn with, laid on the
    // page as it is drawn, turn and slant and all: anything else leaves
    // words over the shape or a gap where there is none.
    WrapShape around(ShapeElement shape) {
      var text = TextElement(
        const ElementBase(id: "t", x: 0, y: 0, width: 800, height: 400),
        text: _words,
        wrap: const TextWrap(on: true, gap: 8),
      );
      var doc = CanvasDocument(elements: [text, shape]);
      return wrapObstacles(text, doc, 0, text.bounds).single;
    }

    const oblong = ElementBase(id: "s", x: 200, y: 40, width: 400, height: 200);

    void expectRect(Rect actual, Rect expected) {
      expect(actual.left, closeTo(expected.left, 0.01));
      expect(actual.top, closeTo(expected.top, 0.01));
      expect(actual.right, closeTo(expected.right, 0.01));
      expect(actual.bottom, closeTo(expected.bottom, 0.01));
    }

    test("a circle in an oblong box, as its disc", () {
      // A circle is drawn round in the middle of whatever box it has.
      var it = around(const ShapeElement(oblong, shape: ShapeKind.circle));
      expectRect(it.path!.getBounds(), const Rect.fromLTRB(300, 40, 500, 240));
      expect(it.path!.contains(const Offset(250, 140)), isFalse,
          reason: "the box's end beside the disc is room for words");
    });

    test("a square in an oblong box, as its square", () {
      var it = around(const ShapeElement(oblong, shape: ShapeKind.square));
      expectRect(it.path!.getBounds(), const Rect.fromLTRB(300, 40, 500, 240));
    });

    test("a star at its own depth", () {
      // Between two points, deeper than the default star's cut.
      var star = ShapeElement(
          const ElementBase(id: "s", x: 200, y: 40, width: 200, height: 200),
          shape: ShapeKind.star,
          innerRatio: 0.7);
      var it = around(star);
      var between = -math.pi / 2 + math.pi / 5;
      var point =
          const Offset(300, 140) + Offset.fromDirection(between, 100 * 0.6);
      expect(it.path!.contains(point), isTrue,
          reason: "a shallow star fills what a deep one cuts away");
    });

    test("a slanted shape, slanted", () {
      // Leaning right at the bottom: its lower right corner is past the
      // box's edge, and its upper right corner short of it.
      var slanted = const ShapeElement(oblong).withBase(skewX: 20);
      var it = around(slanted as ShapeElement);
      var lean = math.tan(20 * math.pi / 180) * 100;
      expect(it.path!.contains(Offset(600 + lean - 4, 236)), isTrue);
      expect(it.path!.contains(Offset(600 - lean + 4, 44)), isFalse);
      var span = it.spanIn(226, 238)!;
      expect(span.$2, greaterThan(600 + lean * 0.75 + 8),
          reason: "the words keep clear of the corner past the box");
    });

    test("a turned shape's corner past its box is gone round", () {
      // Turned, a corner reaches above the box it was given: the words on a
      // line beside that corner go round it too.
      var turned = const ShapeElement(oblong).withBase(rotation: 30);
      var it = around(turned as ShapeElement);
      expect(it.bounds.top, lessThan(oblong.y - 8));
      expect(it.spanIn(10, 30), isNotNull,
          reason: "a line above the box, beside the turned corner");
    });

    // A line or a path is gone round as its stroke is drawn on the frame:
    // as thick as it is, turned, slanted, bowed and moved.
    WrapShape aroundStroke(CanvasElement stroke, {int frame = 0}) {
      var text = TextElement(
        const ElementBase(id: "t", x: 0, y: 0, width: 800, height: 400),
        text: _words,
        wrap: const TextWrap(on: true, gap: 8),
      );
      var doc = CanvasDocument(frames: 24, elements: [text, stroke]);
      return wrapObstacles(text, doc, frame, text.bounds).single;
    }

    LineElement line(Offset a, Offset b, {double width = 6}) =>
        LineElement(const ElementBase(id: "s"), strokeWidth: width)
            .withEnds(a, b);

    test("a level line, as thick as it is drawn", () {
      // Its box is a sliver; its stroke reaches 10 above and below.
      var it = aroundStroke(
          line(const Offset(200, 140), const Offset(600, 140), width: 20));
      expect(it.spanIn(116, 124), isNotNull,
          reason: "the words keep the gap from the stroke's edge");
      expect(it.spanIn(100, 110), isNull, reason: "and no further");
    });

    test("a turned line, along its stroke", () {
      // Turned upright about its middle: from (400, 40) down to (400, 240).
      var it = aroundStroke(line(const Offset(300, 140), const Offset(500, 140))
          .withBase(rotation: 90));
      var span = it.spanIn(60, 70)!;
      expect(span.$1, closeTo(400 - 3 - 8, 1));
      expect(span.$2, closeTo(400 + 3 + 8, 1));
      expect(it.spanIn(10, 20), isNull, reason: "above its top end");
    });

    test("a slanted line, along its stroke", () {
      // Level, slanted down by 30 degrees about its middle.
      var it = aroundStroke(line(const Offset(300, 140), const Offset(500, 140))
          .withBase(skewY: 30));
      var drop = math.tan(30 * math.pi / 180) * 100;
      expect(it.spanIn(140 + drop - 2, 140 + drop + 2), isNotNull,
          reason: "beside its right end, below its box");
      var span = it.spanIn(140 - drop - 2, 140 - drop + 2)!;
      expect(span.$2, lessThan(400), reason: "only its left end up there");
    });

    test("a bowed line, round its bow", () {
      // Bowed down 60 at its middle, out of its box.
      var bowed = line(const Offset(200, 140), const Offset(600, 140))
          .copyWith(curvature: 0.3);
      var it = aroundStroke(bowed);
      var span = it.spanIn(194, 198)!;
      expect((span.$1 + span.$2) / 2, closeTo(400, 2));
      expect(span.$2 - span.$1, lessThan(300), reason: "its bow, not its box");
    });

    test("a turned path, along its stroke", () {
      var path = PathElement(
          const ElementBase(
              id: "s", x: 200, y: 40, width: 400, height: 200, rotation: 90),
          nodes: const [
            PathNode(x: 0, y: 0.5, frame: 0),
            PathNode(x: 1, y: 0.5, frame: 10),
          ],
          endEnd: LineEnd.none);
      var it = aroundStroke(path);
      // Upright through (400, 140), 400 long.
      var span = it.spanIn(0, 10)!;
      expect(span.$1, closeTo(400 - 1.5 - 8, 1));
      expect(span.$2, closeTo(400 + 1.5 + 8, 1));
    });

    test("a line turned by its keys, as it is on the frame", () {
      // Level as it rests; upright on frame 20, through (400, 140).
      var turning =
          line(const Offset(300, 140), const Offset(500, 140)).withBase(
              track: ElementTrack(const [
        Keyframe(frame: 0),
        Keyframe(frame: 20, rotate: 90),
      ]));
      var it = aroundStroke(turning, frame: 20);
      expect(it.spanIn(60, 70), isNotNull, reason: "where it is drawn");
      expect(it.spanIn(60, 70)!.$2 - it.spanIn(60, 70)!.$1, lessThan(40));
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

  group("something taller than the words", () {
    test("is still something to go around", () {
      // A picture beside a column usually is taller than the column -- that
      // is what a picture beside a column looks like. Dropped as a
      // "background" for reaching past the top and the bottom of the box,
      // the words ran straight under it.
      var text = _text(wrap: const TextWrap(on: true, gap: 8));
      var tall = ShapeElement(
        const ElementBase(id: "s", x: 240, y: -60, width: 200, height: 400),
      );
      var doc = CanvasDocument(elements: [text, tall]);
      var blocked = wrapObstacles(text, doc, 0, text.bounds);
      expect(blocked, hasLength(1),
          reason: "reaching past both edges is not a reason to ignore it");

      var out = layoutWrapped(
          _words, text.textSpec, text.bounds, blocked, text.wrap,
          parts: const []);
      expect(out.lines, isNotEmpty);
      expect(out.lines.every((l) => l.box.right <= 232.5), isTrue,
          reason: "every line stops at its edge, the last one included");
    });

    test("and one that covers the words entirely falls back", () {
      // Which is what a panel behind a headline is. There is nowhere to put
      // the words, so they are set the ordinary way and drawn over it.
      var text = _text(wrap: const TextWrap(on: true, gap: 8));
      var panel = ShapeElement(
        const ElementBase(id: "s", x: -20, y: -20, width: 500, height: 300),
      );
      var doc = CanvasDocument(elements: [text, panel]);
      var blocked = wrapObstacles(text, doc, 0, text.bounds);
      expect(blocked, hasLength(1));
      expect(
          wrapFits(_words, text.textSpec, text.bounds, blocked, text.wrap,
              parts: const []),
          isFalse);
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
      expect(
          wrapFits(_words, text.textSpec, room, across, text.wrap,
              parts: const []),
          isFalse);
      expect(
          wrapFits(_words, text.textSpec, room,
              [const WrapShape(Rect.fromLTRB(300, 40, 420, 120))], text.wrap,
              parts: const []),
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
          const TextWrap(on: true, gap: 8),
          parts: const []);
      var openText = layoutWrapped(
          _words, spec, room, const [], const TextWrap(on: true),
          parts: const []);
      expect(wrappedText.consumed, lessThan(openText.consumed));
    });
  });

  group("a line with a bigger word on it", () {
    // A wrapped line was given the height of the plain type whatever was on
    // it, so a word set twice the size reached down over the line below.
    const spec = TextSpec(fontSize: 14, align: TextAlignSpec.left);
    const big = [TextPart(from: 2, to: 2, scale: 2)];

    test("is as tall as that word, so the next line starts below it", () {
      var out = layoutWrapped(
          _words,
          spec,
          const Rect.fromLTWH(0, 0, 400, 200),
          [const WrapShape(Rect.fromLTWH(240, 40, 160, 80))],
          const TextWrap(on: true),
          parts: big);
      var first = out.lines.first;
      expect(first.words.height, greaterThan(out.lines.last.words.height * 1.5),
          reason: "the second word is on the first line, twice the size");
      expect(out.lines[1].box.top,
          greaterThanOrEqualTo(first.box.top + first.words.height - 0.5),
          reason: "the second line starts below the first one's words");
    });

    test("and the words beside it share its baseline", () {
      // Something in the middle of the first line cuts it in two runs; the
      // big word is in the left one.
      var out = layoutWrapped(
          _words,
          spec,
          const Rect.fromLTWH(0, 0, 400, 200),
          [const WrapShape(Rect.fromLTWH(150, 0, 60, 80))],
          const TextWrap(on: true),
          parts: big);
      var left = out.lines[0], right = out.lines[1];
      expect(right.box.left, greaterThan(left.box.right - 0.5),
          reason: "the two runs of the first line");
      double baseline(WrappedLine l) =>
          l.box.top + l.drop + l.words.lines.first.baseline;
      expect(baseline(right), closeTo(baseline(left), 0.01));
    });

    test("and what does not fit below it passes on to the next box", () {
      // Every line drawn is inside the box: the words that would hang out
      // of the bottom are counted as not fitting, not drawn over the edge.
      const room = Rect.fromLTWH(0, 0, 200, 60);
      var out = layoutWrapped(
          _words,
          spec,
          room,
          [const WrapShape(Rect.fromLTWH(150, 0, 50, 20))],
          const TextWrap(on: true),
          parts: const [TextPart(from: 4, to: 4, scale: 2)]);
      for (var line in out.lines) {
        expect(line.box.top + line.drop + line.words.height,
            lessThanOrEqualTo(room.bottom + 0.5),
            reason: "line ${_words.substring(line.from, line.to)}");
      }
      expect(out.consumed, lessThan(_words.length));
    });
  });

  group("a word too wide for the room beside something", () {
    // The first word of a run was taken however wide it was, so a long word
    // beside a picture ran on over the picture, and one wider than the box
    // past its edge, where a box would have moved it to the next line or,
    // wider than a line, broken it.
    const spec = TextSpec(fontSize: 14, align: TextAlignSpec.left);

    test("waits for a line with room for it", () {
      const room = Rect.fromLTWH(0, 0, 400, 200);
      const text = "Hi extraordinarily wide words";
      var out = layoutWrapped(
          text,
          spec,
          room,
          [const WrapShape(Rect.fromLTWH(60, 0, 340, 60))],
          const TextWrap(on: true),
          parts: const []);
      for (var line in out.lines) {
        expect(line.words.width, lessThanOrEqualTo(line.box.width + 0.5),
            reason: "\"${text.substring(line.from, line.to)}\" in its room");
      }
      var long = out.lines
          .firstWhere((l) => text.substring(l.from, l.to).contains("extra"));
      expect(long.box.top, greaterThanOrEqualTo(60 - 0.5),
          reason: "below what was in its way");
      expect(out.consumed, text.length, reason: "every word set");
    });

    test("and one wider than the box is broken, as a box breaks it", () {
      const room = Rect.fromLTWH(0, 0, 200, 200);
      const text = "Supercalifragilisticexpialidocious end";
      var out = layoutWrapped(
          text,
          spec,
          room,
          [const WrapShape(Rect.fromLTWH(100, 150, 100, 50))],
          const TextWrap(on: true),
          parts: const []);
      for (var line in out.lines) {
        expect(line.words.width, lessThanOrEqualTo(line.box.width + 0.5),
            reason: "\"${text.substring(line.from, line.to)}\" in its room");
      }
      var box = layOutWords(text, spec, parts: const [], maxWidth: 200);
      expect(out.lines.first.to - out.lines.first.from,
          box.charactersIn(box.lines.first.height + 0.5),
          reason: "the first line as many letters as a box's first line");
      expect(out.consumed, text.length, reason: "every letter set");
    });
  });

  group("wrapped words are set like any others", () {
    /// _lit is how many pixels of a given kind a document puts down.
    Future<Map<int, int>> ink(CanvasDocument document) async {
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
        var pixel = bytes.getUint32(i);
        counts[pixel] = (counts[pixel] ?? 0) + 1;
      }
      image.dispose();
      picture.dispose();
      return counts;
    }

    CanvasDocument around(TextSpec spec) => CanvasDocument(elements: [
          TextElement(
            const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 200),
            text: _words,
            box: const BoxSpec(padding: 0),
            textSpec: spec,
            wrap: const TextWrap(on: true, gap: 8),
          ),
          _blocker(x: 240, width: 160),
        ]);

    testWidgets("with their outline", (tester) async {
      // Wrapped text was laid out and painted straight, so the Outline
      // setting stopped meaning anything the moment Wrap around things was
      // turned on -- which is the sort of thing nobody thinks to check,
      // because it is a setting in another section.
      late int green;
      await tester.runAsync(() async {
        var ink2 = await ink(around(const TextSpec(
            fontSize: 14,
            color: Color(0xFF000080),
            outlineWidth: 3,
            outlineColor: Color(0xFF00FF00))));
        green = 0;
        for (var e in ink2.entries) {
          var r = (e.key >> 24) & 0xFF, g = (e.key >> 16) & 0xFF;
          var b = (e.key >> 8) & 0xFF;
          if (g > 0x40 && g > r && g > b) green += e.value;
        }
      });
      expect(green, greaterThan(200));
    });

    testWidgets("and with a pattern showing through them", (tester) async {
      // The same for Painted with: a wrapped paragraph was drawn in the flat
      // colour whatever the fill said.
      late int patterned;
      await tester.runAsync(() async {
        var ink2 = await ink(around(const TextSpec(
            fontSize: 14,
            color: Color(0xFF000080),
            fill: TextFill(
              kind: TextFillKind.pattern,
              pattern: ProceduralSpec(
                style: ProceduralStyle.halftone,
                background: Color(0xFFFF0000),
                foreground: Color(0xFFFF0000),
                accent: Color(0xFFFF0000),
              ),
            ))));
        patterned = 0;
        for (var e in ink2.entries) {
          var r = (e.key >> 24) & 0xFF, g = (e.key >> 16) & 0xFF;
          var b = (e.key >> 8) & 0xFF;
          if (r > 0x40 && r > g && r > b) patterned += e.value;
        }
      });
      expect(patterned, greaterThan(200));
    });

    testWidgets("and with their highlights and underlines", (tester) async {
      // Wrapped, the marks were not drawn at all: the wrap draws line by
      // line and never asked for them.
      late Map<int, int> marked;
      await tester.runAsync(() async {
        var doc = around(const TextSpec(fontSize: 14));
        var e = doc.elementById("t") as TextElement;
        marked = await ink(CanvasDocument(elements: [
          e.copyWith(
            highlight: const PartHighlight(color: Color(0xFFFF0000)),
            parts: const [
              TextPart(
                  from: 3,
                  underline: PartUnderline(color: Color(0xFF00FF00), width: 3)),
            ],
          ),
          _blocker(x: 240, width: 160),
        ]));
      });
      expect(marked[0xFF0000FF] ?? 0, greaterThan(200),
          reason: "the element's highlight behind the words");
      expect(marked[0x00FF00FF] ?? 0, greaterThan(200),
          reason: "and a part's underline under them, on every line");
    });

    testWidgets("and with a part counted in letters on a later line",
        (tester) async {
      // Each line's parts are counted again from its first word, and a part
      // counted in letters was left out: its colour and its highlight were
      // drawn on the first line and nowhere else.
      late Map<int, int> marked;
      await tester.runAsync(() async {
        var doc = around(const TextSpec(fontSize: 14));
        var e = doc.elementById("t") as TextElement;
        marked = await ink(CanvasDocument(elements: [
          e.copyWith(parts: const [
            // Letters 120 to 160: well past the first line.
            TextPart(
                unit: TextUnit.characters,
                from: 120,
                to: 160,
                color: Color(0xFF0000FF),
                highlight: PartHighlight(color: Color(0xFFFF0000))),
          ]),
          _blocker(x: 240, width: 160),
        ]));
      });
      expect(marked[0x0000FFFF] ?? 0, greaterThan(200),
          reason: "the letters in the part's colour");
      expect(marked[0xFF0000FF] ?? 0, greaterThan(200),
          reason: "and its highlight behind them");
    });
  });
}
