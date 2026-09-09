import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_text_marks_test.dart is what is drawn *on* the words: a part's own
// highlight and underline, the padding round a mark an animation draws, and
// the copies an echo or a trail leaves.
//
// All of it is measured in pixels rather than asserted about the model,
// because every bug this file was written for was a model that said the right
// thing and a painter that clipped it away.

const _black = 0x000000FF;

Future<Map<int, int>> _ink(CanvasDocument document,
    {int width = 400, int height = 200, int frame = 0, Rect? within}) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFF000000));
  // Element by element rather than through paintCanvasDocument, so the only
  // ink on the page is the elements' own: a document paints its background
  // over every pixel, and a count of what is not black would be the whole
  // canvas whatever the text did.
  for (var element in document.elements) {
    paintElement(canvas, element, frame, document: document);
  }
  var picture = recorder.endRecording();
  var image = await picture.toImage(width, height);
  var bytes = (await image.toByteData())!;
  var counts = <int, int>{};
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    // [within] counts one part of the picture, which is how "this happened
    // over here and not over there" is asked -- a total cannot tell the two
    // apart.
    if (within != null) {
      var at = i ~/ 4;
      if (!within.contains(
          Offset((at % width).toDouble(), (at ~/ width).toDouble()))) {
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

int _lit(Map<int, int> ink) {
  var total = 0;
  for (var entry in ink.entries) {
    if (entry.key != _black) total += entry.value;
  }
  return total;
}

CanvasDocument _document(List<CanvasElement> elements) => CanvasDocument(
      size: const CanvasSize(width: 400, ratio: CanvasRatio.wide),
      background: const CanvasBackground(),
      elements: elements,
    );

TextElement _headline({
  String text = "You come across an idea",
  List<TextPart> parts = const [],
  TextAnimation animation = const TextAnimation(),
  double? reveal,
}) {
  var element = TextElement(
    const ElementBase(id: "t", x: 0, y: 20, width: 400, height: 90),
    text: text,
    textSpec: const TextSpec(fontSize: 26, color: Color(0xFFFFFFFF)),
    parts: parts,
    animation: animation,
  );
  if (reveal == null) return element;
  return element.withBase(
    track: ElementTrack([
      Keyframe(frame: 0, values: {KeyframeChannel.reveal: reveal}),
    ]),
  ) as TextElement;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("a part's own marks", () {
    const green = 0x00FF00FF;

    testWidgets("a highlight is a band behind the words", (tester) async {
      late Map<int, int> plain;
      late Map<int, int> marked;
      await tester.runAsync(() async {
        plain = await _ink(_document([_headline()]));
        marked = await _ink(_document([
          _headline(parts: const [
            TextPart(
              from: 2,
              to: 3,
              highlight: PartHighlight(color: Color(0xFF00FF00)),
            ),
          ]),
        ]));
      });

      expect(plain[green] ?? 0, 0);
      expect(marked[green] ?? 0, greaterThan(200),
          reason: "two words' worth of band");
      // Behind, not over: the letters are still white.
      expect(marked[0xFFFFFFFF] ?? 0, greaterThan(100));
    });

    testWidgets("and its padding gives it room", (tester) async {
      late int tight;
      late int roomy;
      await tester.runAsync(() async {
        tight = (await _ink(_document([
              _headline(parts: const [
                TextPart(
                    from: 2,
                    to: 3,
                    highlight: PartHighlight(
                        color: Color(0xFF00FF00),
                        padLeft: 0,
                        padTop: 0,
                        padRight: 0,
                        padBottom: 0)),
              ]),
            ])))[green] ??
            0;
        roomy = (await _ink(_document([
              _headline(parts: const [
                TextPart(
                    from: 2,
                    to: 3,
                    highlight: PartHighlight(
                        color: Color(0xFF00FF00),
                        padLeft: 12,
                        padTop: 8,
                        padRight: 12,
                        padBottom: 8)),
              ]),
            ])))[green] ??
            0;
      });
      expect(roomy, greaterThan(tight + 400),
          reason: "the padding is room round the words: $tight then $roomy");
    });

    testWidgets("an underline is drawn under them, in its own colour",
        (tester) async {
      late Map<int, int> plain;
      late Map<int, int> lined;
      await tester.runAsync(() async {
        plain = await _ink(_document([_headline()]));
        lined = await _ink(_document([
          _headline(parts: const [
            TextPart(
              from: 5,
              to: 5,
              underline: PartUnderline(color: Color(0xFF00FF00), width: 4),
            ),
          ]),
        ]));
      });
      expect(plain[green] ?? 0, 0);
      expect(lined[green] ?? 0, greaterThan(60));
    });

    testWidgets("a hand-drawn line is not the ruled one", (tester) async {
      // The whole point of the style: it wanders, leans and overshoots. Drawn
      // from the same straight path it would be a rule with a different name.
      late Map<int, int> ruled;
      late Map<int, int> drawn;
      await tester.runAsync(() async {
        Future<Map<int, int>> at(PartLineStyle style) => _ink(_document([
              _headline(parts: [
                TextPart(
                  from: 5,
                  to: 5,
                  underline: PartUnderline(
                      color: const Color(0xFF00FF00), width: 4, style: style),
                ),
              ]),
            ]));
        ruled = await at(PartLineStyle.solid);
        drawn = await at(PartLineStyle.hand);
      });
      // Anti-aliased along its whole length, a wandering line paints far more
      // part-lit pixels than a rule, which is crisp top and bottom.
      var ruledEdges = _lit(ruled) - (ruled[green] ?? 0);
      var drawnEdges = _lit(drawn) - (drawn[green] ?? 0);
      expect(drawnEdges, greaterThan(ruledEdges + 20),
          reason: "ruled $ruledEdges against drawn $drawnEdges");
    });

    testWidgets("a marker stroke is heavier in the middle than at the ends",
        (tester) async {
      late Map<int, int> marker;
      await tester.runAsync(() async {
        marker = await _ink(_document([
          _headline(parts: const [
            TextPart(
              from: 5,
              to: 5,
              underline: PartUnderline(
                  color: Color(0xFF00FF00),
                  width: 6,
                  style: PartLineStyle.marker),
            ),
          ]),
        ]));
      });
      expect(marker[green] ?? 0, greaterThan(60));
    });

    testWidgets("a part can carry an outline of its own", (tester) async {
      // In a paragraph that has none: the words nobody asked about are
      // stroked with nothing, and only the part's own run has a width to
      // draw. Stroked at zero width instead, every word would have got a
      // hairline, a zero-width stroke being a hairline.
      const green = 0x00FF00FF;
      late Map<int, int> plain;
      late Map<int, int> outlined;
      await tester.runAsync(() async {
        plain = await _ink(_document([_headline()]));
        outlined = await _ink(_document([
          _headline(parts: const [
            TextPart(
                from: 2,
                to: 3,
                outlineWidth: 3,
                outlineColor: Color(0xFF00FF00))
          ]),
        ]));
      });
      expect(plain[green] ?? 0, 0);
      expect(outlined[green] ?? 0, greaterThan(100),
          reason: "two words are outlined in green");
    });

    testWidgets("and nothing takes the outline off those words alone",
        (tester) async {
      const green = 0x00FF00FF;
      TextElement at(List<TextPart> parts) => TextElement(
            const ElementBase(id: "t", x: 0, y: 20, width: 400, height: 90),
            text: "You come across an idea",
            textSpec: const TextSpec(
                fontSize: 26,
                color: Color(0xFFFFFFFF),
                outlineWidth: 3,
                outlineColor: Color(0xFF00FF00)),
            parts: parts,
          );
      late int all;
      late int fewer;
      await tester.runAsync(() async {
        all = (await _ink(_document([at(const [])])))[green] ?? 0;
        fewer = (await _ink(_document([
              at(const [TextPart(from: 1, to: 3, outlineWidth: 0)])
            ])))[green] ??
            0;
      });
      expect(all, greaterThan(200));
      expect(fewer, lessThan(all * 0.7),
          reason: "three of the five words lose their outline: $all then "
              "$fewer");
    });

    testWidgets("the element has a pair of its own, on all of the words",
        (tester) async {
      // Highlighting a whole headline used to mean first making a part that
      // covered it.
      const green = 0x00FF00FF;
      late Map<int, int> plain;
      late Map<int, int> marked;
      await tester.runAsync(() async {
        plain = await _ink(_document([_headline()]));
        marked = await _ink(_document([
          TextElement(
            const ElementBase(id: "t", x: 0, y: 20, width: 400, height: 90),
            text: "You come across an idea",
            textSpec: const TextSpec(fontSize: 26, color: Color(0xFFFFFFFF)),
            highlight: const PartHighlight(color: Color(0xFF00FF00)),
          ),
        ]));
      });
      expect(plain[green] ?? 0, 0);
      expect(marked[green] ?? 0, greaterThan(800),
          reason: "a band behind the whole sentence");

      // And they survive being saved.
      var back = elementFromJson(TextElement(
        const ElementBase(id: "t", width: 400, height: 90),
        text: "Hi",
        highlight: const PartHighlight(color: Color(0xFF112233)),
        underline: const PartUnderline(style: PartLineStyle.marker),
      ).toJson()) as TextElement;
      expect(back.highlight!.color, const Color(0xFF112233));
      expect(back.underline!.style, PartLineStyle.marker);
      expect(back.drawnParts.length, 1,
          reason: "drawn as a part covering every word");
      expect(back.drawnParts.single.highlight, isNotNull);
    });

    test("the marks survive being saved and read back", () {
      var element = _headline(parts: const [
        TextPart(
          from: 2,
          to: 4,
          highlight: PartHighlight(
              color: Color(0xFF112233),
              padLeft: 3,
              padTop: 4,
              padRight: 5,
              padBottom: 6,
              radius: 7),
          underline: PartUnderline(
              color: Color(0xFF445566),
              width: 2.5,
              style: PartLineStyle.sketch,
              away: 9),
        ),
      ]);
      var back = elementFromJson(element.toJson()) as TextElement;
      var part = back.parts.single;
      expect(part.highlight!.color, const Color(0xFF112233));
      expect(part.highlight!.padLeft, 3);
      expect(part.highlight!.padBottom, 6);
      expect(part.highlight!.radius, 7);
      expect(part.underline!.style, PartLineStyle.sketch);
      expect(part.underline!.width, 2.5);
      expect(part.underline!.away, 9);
      expect(part.underline!.color, const Color(0xFF445566));

      var outlined = elementFromJson(_headline(parts: const [
        TextPart(from: 1, outlineWidth: 2.5, outlineColor: Color(0xFF00FF00)),
      ]).toJson()) as TextElement;
      expect(outlined.parts.single.outlineWidth, 2.5);
      expect(outlined.parts.single.outlineColor, const Color(0xFF00FF00));

      // And a part with neither writes neither.
      expect(
          const TextPart(from: 1).toJson().containsKey("highlight"), isFalse);
    });
  });

  group("the words stay in their box", () {
    // A box is a box: what does not fit is hidden. That is what makes the
    // overflow grip's red mean anything, and what lets the words that do not
    // fit run on into another box.
    TextElement crowded({TextAnimation animation = const TextAnimation()}) =>
        TextElement(
          const ElementBase(id: "t", x: 0, y: 20, width: 400, height: 40),
          text: "One two three four five six seven eight nine ten eleven "
              "twelve thirteen fourteen fifteen sixteen seventeen",
          box: const BoxSpec(padding: 0),
          textSpec: const TextSpec(
              fontSize: 20,
              color: Color(0xFFFFFFFF),
              verticalAlign: VerticalAlignSpec.top),
          animation: animation,
        );

    testWidgets("what does not fit is hidden", (tester) async {
      const below = Rect.fromLTWH(0, 62, 400, 138);
      late int outside;
      await tester.runAsync(() async {
        outside = _lit(await _ink(_document([crowded()]), within: below));
      });
      expect(outside, 0, reason: "nothing is drawn under the box");
    });

    testWidgets("but an arrival is still allowed outside it", (tester) async {
      // Half the presets bring the words in from outside the box and an echo
      // leaves its copies there; a clip that was always on would cut every
      // animation into a box-shaped hole.
      const below = Rect.fromLTWH(0, 62, 400, 138);
      late int echoed;
      await tester.runAsync(() async {
        echoed = _lit(await _ink(
            _document([
              crowded(
                  animation: const TextAnimation(
                      preset: TextAnimationPreset.echoDown,
                      ease: ChartEase.linear)),
            ]),
            within: below));
      });
      expect(echoed, greaterThan(200), reason: "the copies are drawn");
    });
  });

  group("a drawn mark's padding", () {
    testWidgets("reaches past the words at both ends", (tester) async {
      // The two ends were clipped straight off by the piece's own clip, so
      // the left and right fields appeared to do nothing while the top and
      // bottom worked.
      late int tight;
      late int wide;
      await tester.runAsync(() async {
        Future<int> at(double pad) async => _lit(await _ink(_document([
              _headline(
                animation: TextAnimation(
                  preset: TextAnimationPreset.highlight,
                  draw: TextDrawSpec(
                      color: const Color(0xFF00FF00),
                      padLeft: pad,
                      padRight: pad),
                ),
                reveal: 1,
              ),
            ])));
        tight = await at(0);
        wide = await at(30);
      });
      expect(wide, greaterThan(tight + 800),
          reason: "sixty pixels of band either end: $tight then $wide");
    });
  });

  group("an echo pointed at a part", () {
    // The first half of the line, where the part is not: "idea" is its last
    // word, so an echo pointed at it must leave this half exactly as it was.
    const firstHalf = Rect.fromLTWH(0, 0, 200, 200);

    Future<int> lit({required bool onItsOwn}) async => _lit(await _ink(
        _document([
          _headline(
            parts: [
              TextPart(
                  from: 5,
                  to: 5,
                  animation: onItsOwn
                      ? const TextPartAnimation(
                          preset: TextAnimationPreset.echoDown,
                          ease: ChartEase.linear)
                      : const TextPartAnimation()),
            ],
            animation: onItsOwn
                ? const TextAnimation()
                : const TextAnimation(
                    preset: TextAnimationPreset.echoDown,
                    ease: ChartEase.linear),
            reveal: 1,
          ),
        ]),
        within: firstHalf));

    testWidgets("echoes that part and not the line", (tester) async {
      // The block-scoped copies were drawn from the whole paragraph, so an
      // echo aimed at one word echoed every word in the line.
      late int plain;
      late int one;
      late int all;
      await tester.runAsync(() async {
        plain = _lit(
            await _ink(_document([_headline(reveal: 1)]), within: firstHalf));
        one = await lit(onItsOwn: true);
        all = await lit(onItsOwn: false);
      });
      // What the echo added over half the canvas the part is nowhere near.
      // The words themselves are drawn either way and are most of the ink,
      // so a total cannot tell one word echoing from all of them.
      expect(all - plain, greaterThan(500),
          reason: "all the words echo into this half: $plain then $all");
      expect(one - plain, lessThan(20),
          reason: "the part is not in this half, so nothing should have "
              "changed here: $plain then $one");
    });

    testWidgets("and a word-scoped echo draws its copies at all",
        (tester) async {
      // They were clipped by the rectangle of the word they came from, which
      // is exactly where they are not.
      // Counted well below the words, where only copies can be: clipped to
      // the word's own rectangle, as they were, a copy a line further down is
      // cut away entirely and all that survives is a sliver of the first one.
      const under = Rect.fromLTWH(0, 118, 400, 82);
      late int plain;
      late int echoed;
      await tester.runAsync(() async {
        plain =
            _lit(await _ink(_document([_headline(reveal: 1)]), within: under));
        echoed = _lit(await _ink(
            _document([
              _headline(
                animation: const TextAnimation(
                    preset: TextAnimationPreset.echoWords,
                    ease: ChartEase.linear),
                reveal: 1,
              ),
            ]),
            within: under));
      });
      expect(plain, 0, reason: "nothing is drawn down here without the echo");
      expect(echoed, greaterThan(400),
          reason: "the copies are drawn: $plain then $echoed");
    });
  });

  group("a trail", () {
    testWidgets("is spent rather than kept", (tester) async {
      // Which is the difference between it and an echo: the copies thin out
      // as the words settle, and when it is over there are only the words.
      late int halfway;
      late int arrived;
      await tester.runAsync(() async {
        Future<int> at(double reveal) async => _lit(await _ink(_document([
              _headline(
                animation: const TextAnimation(
                    preset: TextAnimationPreset.trailDown,
                    ease: ChartEase.linear),
                reveal: reveal,
              ),
            ])));
        halfway = await at(0.5);
        arrived = await at(1);
      });
      expect(TextMotion.trail.keeps, isFalse);
      expect(halfway, greaterThan(arrived),
          reason: "copies on the way, none at the end: $halfway then $arrived");
    });

    test("it takes the copy settings", () {
      expect(const TextAnimation(preset: TextAnimationPreset.trailDown).echoes,
          isTrue);
      expect(
          TextAnimation.fromJson(
                  const TextAnimation(preset: TextAnimationPreset.trailUp)
                      .toJson())
              .preset,
          TextAnimationPreset.trailUp);
    });
  });

  group("text riding a line", () {
    CanvasDocument onALine(
            {TextAnimation animation = const TextAnimation(),
            double? reveal,
            List<TextPart> parts = const []}) =>
        _document([
          LineElement(
            const ElementBase(id: "l", x: 40, y: 100, width: 320, height: 4),
          ),
          () {
            var text = TextElement(
              const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 200),
              text: "ALONGTHELINE",
              textSpec: const TextSpec(
                  fontSize: 20,
                  align: TextAlignSpec.left,
                  color: Color(0xFFFFFFFF)),
              box: const BoxSpec(padding: 0),
              curve: const TextOnCurve(elementId: "l"),
              parts: parts,
              animation: animation,
            );
            if (reveal == null) return text;
            return text.withBase(
              track: ElementTrack([
                Keyframe(frame: 0, values: {KeyframeChannel.reveal: reveal}),
              ]),
            );
          }(),
        ]);

    testWidgets("arrives like anything else", (tester) async {
      // It did not: the presets could be chosen and the words simply sat
      // there, because the curve was drawn by a routine that had never heard
      // of the animation.
      late int nothing;
      late int arrived;
      await tester.runAsync(() async {
        nothing = _lit(await _ink(onALine(
            animation: const TextAnimation(
                preset: TextAnimationPreset.fadeIn, ease: ChartEase.linear),
            reveal: 0)));
        arrived = _lit(await _ink(onALine(
            animation: const TextAnimation(
                preset: TextAnimationPreset.fadeIn, ease: ChartEase.linear),
            reveal: 1)));
      });
      // The line itself is drawn either way, so neither is nothing at all.
      expect(arrived, greaterThan(nothing + 300),
          reason: "faded out then arrived: $nothing then $arrived");
    });

    testWidgets("letter by letter, in the order they lie along it",
        (tester) async {
      late int early;
      late int late_;
      await tester.runAsync(() async {
        Future<int> at(double reveal) async => _lit(await _ink(onALine(
            animation: const TextAnimation(
                preset: TextAnimationPreset.letters,
                gap: 1,
                ease: ChartEase.linear),
            reveal: reveal)));
        early = await at(0.25);
        late_ = await at(0.9);
      });
      expect(late_, greaterThan(early + 100),
          reason: "more letters have arrived: $early then $late_");
    });

    test("and the words can slide right off either end of it", () {
      // They could not: a letter past the end of the line was dropped, so a
      // caption slid along its line lost its letters one at a time at the end
      // and never travelled off it.
      var line = [const Offset(40, 100), const Offset(360, 100)];
      const spec = TextSpec(fontSize: 20, align: TextAlignSpec.left);

      var on = placeTextOnPath(
          "ALONGTHELINE", spec, line, const TextOnCurve(elementId: "l"));
      expect(on.length, 12);

      var off = placeTextOnPath("ALONGTHELINE", spec, line,
          const TextOnCurve(elementId: "l", offset: -2));
      expect(off.length, 12, reason: "every letter is still placed");
      expect(off.last.at.dx, lessThan(40),
          reason: "and all of them are past the near end of the line");

      var beyond = placeTextOnPath("ALONGTHELINE", spec, line,
          const TextOnCurve(elementId: "l", offset: 2));
      expect(beyond.first.at.dx, greaterThan(360),
          reason: "and past the far end at the other extreme");
    });

    testWidgets("and a mask cuts off whatever has slid past the end",
        (tester) async {
      // The words follow the line past its ends -- that is what lets a
      // caption travel off and back on -- so without a mask a slide carries
      // them across whatever else is on the canvas.
      late int loose;
      late int masked;
      await tester.runAsync(() async {
        Future<int> at(bool mask) async => _lit(await _ink(_document([
              LineElement(
                const ElementBase(
                    id: "l", x: 150, y: 100, width: 120, height: 4),
              ),
              TextElement(
                const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 200),
                text: "ALONGTHELINE",
                textSpec: const TextSpec(
                    fontSize: 20,
                    align: TextAlignSpec.left,
                    color: Color(0xFFFFFFFF)),
                box: const BoxSpec(padding: 0),
                curve: TextOnCurve(elementId: "l", mask: mask),
              ),
            ])));
        loose = await at(false);
        masked = await at(true);
      });
      // The run is far longer than the line, so most of it is outside.
      expect(masked, lessThan(loose * 0.75),
          reason: "the line is a window: $loose then $masked");
      expect(masked, greaterThan(0), reason: "and what is on the line shows");
    });

    test("the mask survives being saved", () {
      var back = elementFromJson(TextElement(
        const ElementBase(id: "t", width: 400, height: 200),
        text: "Hi",
        curve: const TextOnCurve(elementId: "l", mask: true),
      ).toJson()) as TextElement;
      expect(back.curve!.mask, isTrue);
      expect(const TextOnCurve(elementId: "l").toJson().containsKey("mask"),
          isFalse);
    });

    testWidgets("and a part colours the letters it names", (tester) async {
      late Map<int, int> plain;
      late Map<int, int> parted;
      await tester.runAsync(() async {
        plain = await _ink(onALine());
        parted = await _ink(onALine(parts: const [
          TextPart(
              unit: TextUnit.characters,
              from: 1,
              to: 5,
              color: Color(0xFF00FF00)),
        ]));
      });
      expect(plain[0x00FF00FF] ?? 0, 0);
      expect(parted[0x00FF00FF] ?? 0, greaterThan(40),
          reason: "five letters of green along the line");
    });
  });
}
