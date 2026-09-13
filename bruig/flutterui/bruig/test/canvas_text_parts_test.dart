import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_text_parts_test.dart is "these words, not the others".
//
// One idea rather than a setting on each feature that needs it: colour these
// words, echo that one, animate the first five. What is pinned here is the
// counting -- which is where this sort of thing goes wrong, because a reader
// says "the sixth word" and a string is a list of characters.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sentence = "You come across an idea";

  group("counting", () {
    test("a word is the word somebody means", () {
      // Counted from one, because "the sixth word" is how it is said and
      // making somebody say "the fifth" is making them do arithmetic to talk
      // to a settings panel.
      var range = rangeOf(sentence, const TextPart(from: 5, to: 5))!;
      expect(sentence.substring(range.$1, range.$2), "idea");

      var first = rangeOf(sentence, const TextPart(from: 1, to: 1))!;
      expect(sentence.substring(first.$1, first.$2), "You");
    });

    test("a run of words is one range", () {
      var range = rangeOf(sentence, const TextPart(from: 2, to: 4))!;
      expect(sentence.substring(range.$1, range.$2), "come across an");
    });

    test("nothing for the end means to the end", () {
      // Which is what "words ten till the end" needs, and what a number
      // cannot say once the words are edited.
      var range = rangeOf(sentence, const TextPart(from: 4))!;
      expect(sentence.substring(range.$1, range.$2), "an idea");
      expect(const TextPart(from: 4).toTheEnd, isTrue);
    });

    test("letters are the letters, not the spaces", () {
      // "The third letter" means the third one somebody can see.
      var range = rangeOf(
          sentence, const TextPart(unit: TextUnit.characters, from: 1, to: 3))!;
      expect(sentence.substring(range.$1, range.$2), "You");

      var later = rangeOf(
          sentence, const TextPart(unit: TextUnit.characters, from: 4, to: 4))!;
      expect(sentence.substring(later.$1, later.$2), "c",
          reason: "the fourth letter is the first of the second word");
    });

    test("a part naming something that is not there is nothing", () {
      // Rather than clamping to the last word, which would be a part that
      // appeared to work and coloured something else.
      expect(rangeOf(sentence, const TextPart(from: 12)), isNull);
      expect(rangeOf(sentence, const TextPart(from: 3, to: 2)), isNull);
      expect(rangeOf("", const TextPart()), isNull);
    });

    test("and it says what it is in words", () {
      expect(const TextPart(from: 6, to: 6).says, "Word 6");
      expect(const TextPart(from: 1, to: 5).says, "Words 1 to 5");
      expect(const TextPart(from: 10).says, "From word 10 to the end");
      expect(const TextPart().says, "Every word");
      expect(const TextPart(unit: TextUnit.characters, from: 3, to: 3).says,
          "Letter 3");
    });

    test("where two overlap, the later one wins", () {
      // The list is the reader's own order, and what they added last is what
      // they are working on.
      const parts = [
        TextPart(from: 1, to: 5, color: Color(0xFFFF0000)),
        TextPart(from: 5, to: 5, color: Color(0xFF00FF00)),
      ];
      var at = rangeOf(sentence, parts.last)!.$1;
      expect(partAt(sentence, parts, at)?.color, const Color(0xFF00FF00));
      expect(partAt(sentence, parts, 0)?.color, const Color(0xFFFF0000));
      expect(partAt(sentence, const [], 0), isNull);
    });
  });

  group("drawn", () {
    Future<Map<int, int>> ink(TextElement element) async {
      const size = Size(400, 120);
      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      canvas.drawRect(
          Offset.zero & size, Paint()..color = const Color(0xFF000000));
      paintElement(canvas, element, 0,
          document: CanvasDocument(elements: [element]));
      var picture = recorder.endRecording();
      var image = await picture.toImage(400, 120);
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

    TextElement withParts(List<TextPart> parts) => TextElement(
          const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 120),
          text: sentence,
          textSpec: const TextSpec(fontSize: 26, color: Color(0xFF808080)),
          parts: parts,
        );

    testWidgets("one word can be another colour", (tester) async {
      // The reference: a sentence in a quiet colour with its last word in
      // white.
      late Map<int, int> plain;
      late Map<int, int> parted;
      await tester.runAsync(() async {
        plain = await ink(withParts(const []));
        parted = await ink(withParts(
            const [TextPart(from: 5, to: 5, color: Color(0xFFFFFFFF))]));
      });

      expect(plain[0xFFFFFFFF] ?? 0, 0, reason: "nothing is white to begin");
      expect(parted[0xFFFFFFFF] ?? 0, greaterThan(30),
          reason: "the fifth word should be");
      expect(parted[0x808080FF] ?? 0, greaterThan(30),
          reason: "and the rest should not have changed");
    });

    testWidgets("and a range of them", (tester) async {
      late Map<int, int> one;
      late Map<int, int> several;
      await tester.runAsync(() async {
        one = await ink(withParts(
            const [TextPart(from: 5, to: 5, color: Color(0xFFFFFFFF))]));
        several = await ink(withParts(
            const [TextPart(from: 2, to: 5, color: Color(0xFFFFFFFF))]));
      });
      expect(several[0xFFFFFFFF] ?? 0, greaterThan((one[0xFFFFFFFF] ?? 0) * 2),
          reason: "four words of white against one");
    });

    testWidgets("a part survives being saved and read back", (tester) async {
      var element = withParts(const [
        TextPart(
            unit: TextUnit.characters,
            from: 3,
            to: 9,
            color: Color(0xFF00FF00),
            weight: 700,
            italic: true),
      ]);
      var back = elementFromJson(element.toJson()) as TextElement;
      expect(back.parts.single.unit, TextUnit.characters);
      expect(back.parts.single.from, 3);
      expect(back.parts.single.to, 9);
      expect(back.parts.single.color, const Color(0xFF00FF00));
      expect(back.parts.single.weight, 700);
      expect(back.parts.single.italic, isTrue);

      // And an element with none writes none.
      expect(withParts(const []).toJson().containsKey("parts"), isFalse);
    });
  });

  group("a highlight band", () {
    /// _band is the rectangle the highlight covers, read off the pixels: a
    /// band in a colour nothing else on the canvas uses.
    Future<(Rect?, Set<int>)> bandInk(TextAlignSpec align,
        {double radius = 0}) async {
      const size = Size(400, 120);
      var element = TextElement(
        const ElementBase(id: "t", x: 50, y: 20, width: 300, height: 80),
        text: "Marked",
        textSpec: TextSpec(
            fontSize: 26, color: const Color(0xFFFFFFFF), align: align),
        parts: [
          TextPart(
            from: 1,
            to: 1,
            highlight: PartHighlight(
                color: const Color(0xFF0040FF),
                padLeft: 20,
                padRight: 20,
                padTop: 8,
                padBottom: 8,
                radius: radius),
          ),
        ],
      );
      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      canvas.drawRect(
          Offset.zero & size, Paint()..color = const Color(0xFF000000));
      paintElement(canvas, element, 0,
          document: CanvasDocument(elements: [element]));
      var picture = recorder.endRecording();
      var image = await picture.toImage(400, 120);
      var bytes = (await image.toByteData())!;
      Rect? found;
      var on = <int>{};
      for (var i = 0; i < bytes.lengthInBytes; i += 4) {
        var p = bytes.getUint32(i);
        var r = (p >> 24) & 0xFF, g = (p >> 16) & 0xFF, b = (p >> 8) & 0xFF;
        if (!(b > 0x80 && b > r + 0x40 && b > g + 0x40)) continue;
        var at = i ~/ 4;
        on.add(at);
        var point =
            Rect.fromLTWH((at % 400).toDouble(), (at ~/ 400).toDouble(), 1, 1);
        found = found == null ? point : found.expandToInclude(point);
      }
      image.dispose();
      picture.dispose();
      return (found, on);
    }

    Future<Rect?> band(TextAlignSpec align, {double radius = 0}) async =>
        (await bandInk(align, radius: radius)).$1;

    testWidgets("keeps its padding whichever way the words are aligned",
        (tester) async {
      // The box clips what does not fit in it, and on a left-aligned line the
      // words start at the box's own edge -- so the band's left padding was
      // clipped away and its rounded corners came out square. Centred there
      // is slack either side and the band was whole, which is why this read
      // as an alignment bug.
      late Rect? left;
      late Rect? centre;
      late Rect? right;
      await tester.runAsync(() async {
        left = await band(TextAlignSpec.left);
        centre = await band(TextAlignSpec.center);
        right = await band(TextAlignSpec.right);
      });
      expect(left, isNotNull);
      expect(centre, isNotNull);
      expect(right, isNotNull);
      // The element runs from 50 to 350 with the box's own 8 of padding
      // inside that, so the words run from 58 to 342. The band's padding is
      // 20, so a band that has kept it reaches 38 and 362 -- outside the
      // box, which is where padding on the outside of the letters has to go.
      var l = left!, c = centre!, r = right!;
      expect(l.left, closeTo(38, 2),
          reason: "the left padding reaches past the box's own edge");
      expect(r.right, closeTo(362, 2),
          reason: "and the right padding does at the other end");
      // The same band wherever it is: the padding does not depend on which
      // way the line is aligned.
      expect(l.width, closeTo(c.width, 2));
      expect(r.width, closeTo(c.width, 2));
    });

    testWidgets("and its corners are rounded, not cut off", (tester) async {
      late (Rect?, Set<int>) square;
      late (Rect?, Set<int>) rounded;
      await tester.runAsync(() async {
        square = await bandInk(TextAlignSpec.left);
        rounded = await bandInk(TextAlignSpec.left, radius: 20);
      });
      // The same ground either way: a radius takes the corners out of the
      // band, it does not take the padding off it.
      var flat = square.$1!, round = rounded.$1!;
      expect(round.width, closeTo(flat.width, 2));
      expect(round.height, closeTo(flat.height, 2));

      /// at is whether the band covers a point, counted in whole pixels.
      bool at((Rect?, Set<int>) ink, double x, double y) =>
          ink.$2.contains((y.round() * 400) + x.round());

      // The left corner is the one that was being cut square by the box's
      // own clip: a band pushed up against the edge had nowhere to round
      // into. Rounded, that corner is empty; square, it is filled.
      expect(at(square, flat.left + 1, flat.top + 1), isTrue,
          reason: "a square band fills its corner");
      expect(at(rounded, round.left + 1, round.top + 1), isFalse,
          reason: "a rounded one does not");
      expect(at(rounded, round.left + 1, round.center.dy), isTrue,
          reason: "but it still reaches the edge between the corners");
    });
  });

  group("the echo", () {
    Future<int> ink(TextAnimation animation) async {
      const size = Size(400, 200);
      var element = TextElement(
        const ElementBase(id: "t", x: 0, y: 20, width: 400, height: 60),
        text: "obvious",
        textSpec: const TextSpec(fontSize: 30, color: Color(0xFFFFFFFF)),
        animation: animation,
      );
      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      canvas.drawRect(
          Offset.zero & size, Paint()..color = const Color(0xFF000000));
      paintElement(canvas, element, 0,
          document: CanvasDocument(elements: [element]));
      var picture = recorder.endRecording();
      var image = await picture.toImage(400, 200);
      var bytes = (await image.toByteData())!;
      var lit = 0;
      for (var i = 0; i < bytes.lengthInBytes; i += 4) {
        if (bytes.getUint32(i) != 0x000000FF) lit++;
      }
      image.dispose();
      picture.dispose();
      return lit;
    }

    testWidgets("makes copies, and more of them where more are asked for",
        (tester) async {
      late int none;
      late int few;
      late int many;
      await tester.runAsync(() async {
        none = await ink(const TextAnimation());
        few = await ink(const TextAnimation(
            preset: TextAnimationPreset.echoDown,
            echo: TextEchoSpec(copies: 2)));
        many = await ink(const TextAnimation(
            preset: TextAnimationPreset.echoDown,
            echo: TextEchoSpec(copies: 6)));
      });

      expect(few, greaterThan(none));
      expect(many, greaterThan(few),
          reason: "six copies cover more than two: $few then $many");
    });

    testWidgets("and they stay when the animation is over", (tester) async {
      // A look as much as an arrival, which is what the reference is.
      expect(TextMotion.echo.keeps, isTrue);
      late int drawn;
      await tester.runAsync(() async {
        drawn = await ink(
            const TextAnimation(preset: TextAnimationPreset.echoDown));
      });
      expect(drawn, greaterThan(0));
    });

    test("every direction is offered", () {
      var special = TextAnimationPreset.inFamily(TextAnimationFamily.special);
      expect(special.length, greaterThanOrEqualTo(5));
      expect([for (var p in special) p.label], contains("Echo upwards"));
      expect([for (var p in special) p.label], contains("Echo both ways"));
      expect([for (var p in special) p.label], contains("Echo each word"));
    });

    test("its settings survive being saved", () {
      var animation = const TextAnimation(
        preset: TextAnimationPreset.echoDown,
        echo: TextEchoSpec(copies: 7, spacing: 1.5, fade: 0.4, shrink: 0.9),
      );
      var back = TextAnimation.fromJson(animation.toJson());
      expect(back.echo.copies, 7);
      expect(back.echo.spacing, 1.5);
      expect(back.echo.fade, 0.4);
      expect(back.echo.shrink, 0.9);
      expect(back.echoes, isTrue);
    });
  });

  group("an animation pointed at a part", () {
    const line = "You come across an idea";

    Future<Map<int, int>> ink(TextElement element, double reveal) async {
      const size = Size(400, 200);
      var posed = element.withBase(
        track: ElementTrack([
          Keyframe(frame: 0, values: {KeyframeChannel.reveal: reveal}),
        ]),
      );
      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      canvas.drawRect(
          Offset.zero & size, Paint()..color = const Color(0xFF000000));
      paintElement(canvas, posed, 0,
          document: CanvasDocument(elements: [posed]));
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

    // The part arrives on its own account -- see TextPartAnimation -- with
    // the element's own arrival left off, so what is measured is the part.
    TextElement headline({required bool onItsOwn}) => TextElement(
          const ElementBase(id: "t", x: 0, y: 20, width: 400, height: 80),
          text: line,
          textSpec: const TextSpec(fontSize: 26, color: Color(0xFFFFFFFF)),
          parts: [
            TextPart(
                from: 5,
                to: 5,
                animation: onItsOwn
                    ? const TextPartAnimation(
                        preset: TextAnimationPreset.fadeIn,
                        ease: ChartEase.linear)
                    : const TextPartAnimation()),
          ],
          animation: onItsOwn
              ? const TextAnimation()
              : const TextAnimation(
                  preset: TextAnimationPreset.fadeIn, ease: ChartEase.linear),
        );

    testWidgets("leaves the other words alone", (tester) async {
      // The reference: one word arrives and the line it is in sits still.
      late Map<int, int> partly;
      late Map<int, int> wholly;
      await tester.runAsync(() async {
        partly = await ink(headline(onItsOwn: true), 0);
        wholly = await ink(headline(onItsOwn: false), 0);
      });

      expect(wholly[0xFFFFFFFF] ?? 0, 0,
          reason: "pointed at all the words, none of them has arrived");
      expect(partly[0xFFFFFFFF] ?? 0, greaterThan(50),
          reason: "pointed at one word, the rest of the line is already there");
    });

    testWidgets("and the part itself is the thing that moves", (tester) async {
      late Map<int, int> atNothing;
      late Map<int, int> atAll;
      await tester.runAsync(() async {
        atNothing = await ink(headline(onItsOwn: true), 0);
        atAll = await ink(headline(onItsOwn: true), 1);
      });
      expect(atAll[0xFFFFFFFF]!, greaterThan(atNothing[0xFFFFFFFF]! + 30),
          reason: "the word it points at should arrive on top of the rest");
    });

    test("and it survives being saved", () {
      var back = TextPartAnimation.fromJson(const TextPartAnimation(
              preset: TextAnimationPreset.echoDown, offset: 6, length: 12)
          .toJson());
      expect(back.preset, TextAnimationPreset.echoDown);
      expect(back.offset, 6);
      expect(back.length, 12);
      expect(const TextPartAnimation().toJson(), isEmpty,
          reason: "a part that arrives with the rest writes nothing");
    });
  });
}
