import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_text_part_animation_test.dart is a part of the text arriving on its
// own account, at its own moment.
//
// The order a headline is built in: the line arrives, a word in it lands a
// few frames later, its underline is drawn under that, and then the whole
// thing leaves. What is pinned here is the timing -- offsets are measured
// against the element's own two keyframes, so dragging those carries the
// parts with them.

const _line = "You come across an idea";
const _black = 0x000000FF;

/// _ink draws [element] on [frame] and counts the pixels of each colour.
Future<Map<int, int>> _ink(TextElement element, int frame,
    {Rect? within}) async {
  var document = CanvasDocument(
    size: const CanvasSize(width: 400, ratio: CanvasRatio.wide),
    background: const CanvasBackground(),
    elements: [element],
    frames: 48,
    frameRate: 12,
  );
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 400, 200),
      Paint()..color = const Color(0xFF000000));
  paintElement(canvas, element, frame, document: document);
  var picture = recorder.endRecording();
  var image = await picture.toImage(400, 200);
  var bytes = (await image.toByteData())!;
  var counts = <int, int>{};
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    if (within != null) {
      var at = i ~/ 4;
      if (!within
          .contains(Offset((at % 400).toDouble(), (at ~/ 400).toDouble()))) {
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

/// _bright is the pixels at least [least] of the way to white, which is how
/// "further through a fade" is asked -- the alpha lands in the channels.
int _bright(Map<int, int> ink, int least) {
  var total = 0;
  for (var entry in ink.entries) {
    if ((entry.key >> 24 & 0xFF) >= least) total += entry.value;
  }
  return total;
}

/// _there is the pixels that have fully arrived.
///
/// Not everything that is not the background: a word half way through a fade
/// still paints every pixel it will end up covering, only in grey, so a count
/// of what is lit cannot tell "arrived" from "on its way".
int _there(Map<int, int> ink) => ink[0xFFFFFFFF] ?? 0;

/// _headline is a text element whose own arrival runs from frame 0 to 10.
TextElement _headline({
  List<TextPart> parts = const [],
  TextAnimation animation = const TextAnimation(
      preset: TextAnimationPreset.fadeIn, ease: ChartEase.linear),
  String text = _line,
}) =>
    TextElement(
      const ElementBase(id: "t", x: 0, y: 20, width: 400, height: 90),
      text: text,
      textSpec: const TextSpec(fontSize: 26, color: Color(0xFFFFFFFF)),
      parts: parts,
      animation: animation,
    ).withBase(
        track: ElementTrack([
      const Keyframe(frame: 0, values: {KeyframeChannel.reveal: 0}),
      const Keyframe(frame: 10, values: {KeyframeChannel.reveal: 1}),
    ])) as TextElement;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("a part with a moment of its own", () {
    // The last word of the line, which is at the right-hand end of it -- so
    // its own half of the canvas says whether it has arrived without the rest
    // of the sentence getting in the way.
    const rightHalf = Rect.fromLTWH(200, 0, 200, 200);

    TextPart late_(int offset) => TextPart(
          from: 5,
          to: 5,
          animation: TextPartAnimation(
              preset: TextAnimationPreset.fadeIn,
              offset: offset,
              ease: ChartEase.linear),
        );

    testWidgets("lands after the line it is in", (tester) async {
      // The arrival runs 0 to 10; the part starts at 6 and so is barely
      // there when the line has finished.
      late int lineAt10;
      late int partAt10;
      await tester.runAsync(() async {
        lineAt10 = _there(await _ink(
            _headline(parts: [late_(6)], text: _line), 10,
            within: rightHalf));
        partAt10 = _there(await _ink(
            _headline(parts: [late_(0)], text: _line), 10,
            within: rightHalf));
      });
      expect(partAt10, greaterThan(lineAt10 + 100),
          reason: "offset by six frames, the word is still on its way when "
              "the line has arrived: $lineAt10 against $partAt10");
    });

    testWidgets("and the rest of the line does not wait for it",
        (tester) async {
      // Which is the whole point of a part having a moment of its own: at
      // frame 10 the sentence is there even though its last word is not.
      const leftHalf = Rect.fromLTWH(0, 0, 200, 200);
      late int left;
      await tester.runAsync(() async {
        left = _there(await _ink(_headline(parts: [late_(8)], text: _line), 10,
            within: leftHalf));
      });
      expect(left, greaterThan(300), reason: "the line is there");
    });

    testWidgets("a negative offset brings it forward", (tester) async {
      late int early;
      late int onTime;
      await tester.runAsync(() async {
        early = _bright(
            await _ink(_headline(parts: [late_(-6)], text: _line), 3,
                within: rightHalf),
            0xC0);
        onTime = _bright(
            await _ink(_headline(parts: [late_(0)], text: _line), 3,
                within: rightHalf),
            0xC0);
      });
      expect(early, greaterThan(onTime + 40),
          reason: "brought forward, the word is further on: $onTime then "
              "$early");
    });

    test("its own length overrides the arrival's", () {
      // Half way through a six-frame animation that started at the same
      // moment as a ten-frame one.
      var part = const TextPart(
          from: 1,
          animation:
              TextPartAnimation(preset: TextAnimationPreset.fadeIn, length: 6));
      expect(timingOf(part, frame: 3, from: 0, span: 10).words, 0.5);
      expect(timingOf(part, frame: 6, from: 0, span: 10).words, 1);

      // And without one it takes as long as the arrival.
      var same = const TextPart(
          from: 1,
          animation: TextPartAnimation(preset: TextAnimationPreset.fadeIn));
      expect(timingOf(same, frame: 5, from: 0, span: 10).words, 0.5);
    });

    test("a part that arrives with the rest has no timing of its own", () {
      expect(
          timingOf(const TextPart(from: 1), frame: 3, from: 0, span: 10).words,
          1);
      expect(partsAnimate(const [TextPart(from: 1)]), isFalse);
      expect(
          partsAnimate(const [
            TextPart(
                from: 1,
                animation:
                    TextPartAnimation(preset: TextAnimationPreset.fadeIn))
          ]),
          isTrue);
    });
  });

  group("a part's mark", () {
    testWidgets("is drawn on when it is asked to be", (tester) async {
      // A word arrives and *then* gets underlined, which is the usual thing
      // and what a mark that simply appeared could not do.
      const green = 0x00FF00FF;
      TextElement at(bool drawn, int offset) => _headline(parts: [
            TextPart(
              from: 2,
              to: 4,
              underline:
                  const PartUnderline(color: Color(0xFF00FF00), width: 4),
              animation: TextPartAnimation(marks: drawn, markOffset: offset),
            ),
          ]);

      // Measured once the words have arrived, so what is being compared is
      // how much of the mark has been drawn and not how far the paragraph's
      // own fade has got -- a mark belongs to the words it is on, so it
      // arrives and leaves with them.
      late int always;
      late int early;
      late int late_;
      await tester.runAsync(() async {
        always = (await _ink(at(false, 0), 10))[green] ?? 0;
        early = (await _ink(at(true, 5), 7))[green] ?? 0;
        late_ = (await _ink(at(true, 8), 2))[green] ?? 0;
      });

      expect(always, greaterThan(40), reason: "a mark that is simply there");
      expect(early, lessThan(always),
          reason: "being drawn on, it is only part way across: "
              "$always against $early");
      expect(late_, 0,
          reason: "offset by eight frames it has not started at frame 2");
    });

    testWidgets("and it arrives and leaves with the words it is on",
        (tester) async {
      // Drawn outside the animation, as it was, an underline stayed behind on
      // an empty canvas after the sentence it belonged to had left.
      const green = 0x00FF00FF;
      var marked = TextElement(
        const ElementBase(id: "t", x: 0, y: 20, width: 400, height: 90),
        text: _line,
        textSpec: const TextSpec(fontSize: 26, color: Color(0xFFFFFFFF)),
        parts: const [
          TextPart(
              from: 2,
              to: 4,
              underline: PartUnderline(color: Color(0xFF00FF00), width: 4)),
        ],
        animation: const TextAnimation(
            preset: TextAnimationPreset.fadeIn,
            exit: TextAnimationPreset.fadeIn,
            ease: ChartEase.linear),
      ).withBase(
          track: ElementTrack([
        const Keyframe(frame: 0, values: {KeyframeChannel.reveal: 0}),
        const Keyframe(frame: 10, values: {KeyframeChannel.reveal: 1}),
        const Keyframe(frame: 20, values: {KeyframeChannel.close: 0}),
        const Keyframe(frame: 30, values: {KeyframeChannel.close: 1}),
      ])) as TextElement;

      late int there;
      late int arriving;
      late int gone;
      await tester.runAsync(() async {
        there = (await _ink(marked, 20))[green] ?? 0;
        arriving = (await _ink(marked, 2))[green] ?? 0;
        gone = _lit(await _ink(marked, 30));
      });
      expect(there, greaterThan(40), reason: "the line is under the words");
      expect(arriving, 0,
          reason: "and is as faint as they are while they arrive");
      expect(gone, 0, reason: "and it goes with them");
    });

    testWidgets("and it is drawn to the end by the time it is over",
        (tester) async {
      const green = 0x00FF00FF;
      late int done;
      await tester.runAsync(() async {
        done = (await _ink(
                _headline(parts: const [
                  TextPart(
                    from: 2,
                    to: 4,
                    underline:
                        PartUnderline(color: Color(0xFF00FF00), width: 4),
                    animation: TextPartAnimation(marks: true),
                  ),
                ]),
                10))[green] ??
            0;
      });
      expect(done, greaterThan(40));
    });
  });

  group("the presets that were not working", () {
    testWidgets("a mask pointed at a part raises the part, not its line",
        (tester) async {
      // A line-scoped piece narrowed to a part is that part's own line: the
      // whole line, as it was, is a mask that raised the sentence.
      // Well clear of the part, and at a frame where the part is half way
      // up: a mask that took the whole line would be drawing a second,
      // rising copy of these words over the ones that are already here.
      const start = Rect.fromLTWH(0, 0, 150, 200);
      late int alone;
      late int masked;
      await tester.runAsync(() async {
        alone = _lit(await _ink(_headline(), 10, within: start));
        masked = _lit(await _ink(
            _headline(parts: const [
              TextPart(
                  from: 5,
                  to: 5,
                  animation: TextPartAnimation(
                      preset: TextAnimationPreset.maskUp,
                      offset: 6,
                      ease: ChartEase.linear)),
            ]),
            10,
            within: start));
      });
      expect(alone, greaterThan(300), reason: "the line is there");
      expect(masked, alone,
          reason: "the words the mask is not pointed at are untouched: "
              "$alone against $masked");
    });

    testWidgets("a scramble pointed at a part churns only that part",
        (tester) async {
      // Well clear of the part, so nothing the layer's own clip does at its
      // edges can be mistaken for the letters having changed.
      const start = Rect.fromLTWH(0, 0, 150, 200);
      late int plain;
      late int scrambling;
      await tester.runAsync(() async {
        plain = _lit(await _ink(_headline(), 5, within: start));
        scrambling = _lit(await _ink(
            _headline(parts: const [
              TextPart(
                  from: 5,
                  to: 5,
                  animation: TextPartAnimation(
                      preset: TextAnimationPreset.scramble,
                      ease: ChartEase.linear)),
            ]),
            5,
            within: start));
      });
      expect(scrambling, plain,
          reason: "the letters outside the part are exactly as they were");
    });

    testWidgets("draw the outline leaves the words where they are",
        (tester) async {
      // It is a mark drawn *on* the words, like an underline: they are there
      // from the first frame and the stroke arrives over them. Hiding them
      // and writing them on turned the whole element into a wipe.
      //
      // The stroke is the mark's own colour here, since this type has no
      // outline of its own -- see outlineSpecFor, which invents neither the
      // colour nor the stroke.
      late int early;
      late int done;
      late int noColour;
      await tester.runAsync(() async {
        Future<int> at(int frame, {Color? mark}) async => _lit(await _ink(
            _headline(
                animation: TextAnimation(
                    preset: TextAnimationPreset.strokeOn,
                    ease: ChartEase.linear,
                    draw: TextDrawSpec(color: mark))),
            frame));
        early = await at(3, mark: const Color(0xFF00FF00));
        done = await at(10, mark: const Color(0xFF00FF00));
        noColour = await at(3);
      });
      expect(early, greaterThan(0), reason: "the words are already there");
      expect(done, greaterThan(early),
          reason: "and the stroke arrives over them: $early then $done");
      // And with no colour given for it there is no stroke: the words, and
      // nothing else.
      expect(noColour, lessThan(early));
    });

    testWidgets("an outline draws on text that has parts", (tester) async {
      // A style cannot carry both a stroke and a colour, so a part's colour
      // applied to an outline run threw -- and the paragraph could not be
      // built at all.
      late int lit;
      await tester.runAsync(() async {
        lit = _lit(await _ink(
            TextElement(
              const ElementBase(id: "t", x: 0, y: 20, width: 400, height: 90),
              text: _line,
              textSpec: const TextSpec(
                  fontSize: 26,
                  color: Color(0xFF000000),
                  outlineWidth: 2,
                  outlineColor: Color(0xFF00FF00)),
              parts: const [
                TextPart(from: 2, to: 3, color: Color(0xFFFF0000), weight: 700)
              ],
            ),
            0));
      });
      expect(lit, greaterThan(100));
    });

    test("a bounce asks for the curve that makes it a bounce", () {
      // The same rise, eased so it overshoots and settles. Played with the
      // ordinary ease-out it is a slide with a misleading name.
      expect(TextAnimationPreset.bounce.wants, ChartEase.bounce);
      expect(TextAnimationPreset.fadeIn.wants, isNull);

      var controller = CanvasController(
          CanvasDocument(frames: 48, frameRate: 12).addElement(TextElement(
              const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 100),
              text: _line)));
      addTearDown(controller.dispose);
      controller.applyTextAnimation(
          controller.document.elements.single as TextElement,
          TextAnimationPreset.bounce);
      expect(
          (controller.document.elements.single as TextElement).animation.ease,
          ChartEase.bounce);
    });
  });

  group("the length of an arrival", () {
    CanvasController controllerFor([TextElement? element]) {
      var controller = CanvasController(
          CanvasDocument(frames: 96, frameRate: 12).addElement(element ??
              TextElement(
                  const ElementBase(
                      id: "t", x: 0, y: 0, width: 400, height: 100),
                  text: _line)));
      addTearDown(controller.dispose);
      return controller;
    }

    TextElement textIn(CanvasController c) =>
        c.document.elements.single as TextElement;

    int? spanOf(CanvasController c) {
      int? from;
      int? to;
      for (var key in textIn(c).track?.keys ?? const <Keyframe>[]) {
        if (!key.values.containsKey(KeyframeChannel.reveal)) continue;
        from = from == null ? key.frame : math.min(from, key.frame);
        to = to == null ? key.frame : math.max(to, key.frame);
      }
      return from == null || to == null ? null : to - from;
    }

    test("is what a new animation is laid down with", () {
      // The setting was written and then ignored: an animation added
      // afterwards came out at the default length regardless.
      var controller = controllerFor(TextElement(
        const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 100),
        text: _line,
        animation: const TextAnimation(length: 8),
      ));
      controller.frame = 0;
      controller.applyTextAnimation(
          textIn(controller), TextAnimationPreset.fadeIn);
      expect(spanOf(controller), 8);
    });

    test("and the exit is laid down with it too", () {
      var controller = controllerFor(TextElement(
        const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 100),
        text: _line,
        animation: const TextAnimation(length: 9),
      ));
      controller.frame = 0;
      controller.applyTextAnimation(
          textIn(controller), TextAnimationPreset.fadeIn);
      controller.applyTextExit(textIn(controller), TextAnimationPreset.fadeIn);

      int? from;
      int? to;
      for (var key in textIn(controller).track!.keys) {
        if (!key.values.containsKey(KeyframeChannel.close)) continue;
        from = from == null ? key.frame : math.min(from, key.frame);
        to = to == null ? key.frame : math.max(to, key.frame);
      }
      expect(to! - from!, 9);
    });

    test("but changing it leaves an animation already laid down alone", () {
      // Once it is on the timeline the keyframes are where it is. The
      // setting is for laying a new one down -- which, after the keyframes
      // have been deleted, is what the next preset is.
      var controller = controllerFor();
      controller.frame = 0;
      controller.applyTextAnimation(
          textIn(controller), TextAnimationPreset.fadeIn,
          length: 10);
      expect(spanOf(controller), 10);

      controller.replaceElement(textIn(controller).copyWith(
          animation: textIn(controller).animation.copyWith(length: 30)));
      controller.applyTextAnimation(
          textIn(controller), TextAnimationPreset.words);
      expect(spanOf(controller), 10, reason: "the keyframes have not moved");

      // Delete one of them and the animation is gone, so the next one chosen
      // is a new one and takes the setting.
      controller.removeKeyframe("t", 0);
      expect(textIn(controller).animation.on, isFalse);
      controller.applyTextAnimation(
          textIn(controller), TextAnimationPreset.fadeIn);
      expect(spanOf(controller), 30);
    });

    test("deleting a keyframe takes the animation with it", () {
      // An animation is a pair: nothing to travel between is not half an
      // arrival, it is none of one. The orphan used to sit on the timeline
      // with the preset still chosen and nothing to show for either.
      var controller = controllerFor();
      controller.frame = 0;
      controller.applyTextAnimation(
          textIn(controller), TextAnimationPreset.fadeIn,
          length: 10);
      controller.applyTextExit(textIn(controller), TextAnimationPreset.fadeIn);
      expect(textIn(controller).animation.closes, isTrue);

      // The far end of the exit.
      var last = 0;
      for (var key in textIn(controller).track!.keys) {
        if (key.values.containsKey(KeyframeChannel.close)) {
          last = math.max(last, key.frame);
        }
      }
      controller.removeKeyframe("t", last);

      expect(textIn(controller).animation.closes, isFalse,
          reason: "the leaving setting goes back to None");
      expect([
        for (var key in textIn(controller).track?.keys ?? const <Keyframe>[])
          if (key.values.containsKey(KeyframeChannel.close)) key
      ], isEmpty, reason: "and its other keyframe goes too");
      expect(textIn(controller).animation.on, isTrue,
          reason: "the arrival is untouched");
      expect(spanOf(controller), 10);
    });

    test("but the timeline does not write back to it", () {
      // It is a setting, not a reading: a field that changed itself every
      // time the timeline was nudged would be one nobody could rely on.
      var controller = controllerFor();
      controller.frame = 0;
      controller.applyTextAnimation(
          textIn(controller), TextAnimationPreset.fadeIn,
          length: 12);
      expect(textIn(controller).animation.length, 0,
          reason: "laying keyframes out is not somebody asking for a length");
    });

    test("and choosing another preset leaves the timing alone", () {
      // Or trying the next preset in the list would undo the last thing
      // somebody did, every time.
      var controller = controllerFor();
      controller.frame = 4;
      controller.applyTextAnimation(
          textIn(controller), TextAnimationPreset.fadeIn,
          length: 7);
      controller.applyTextAnimation(
          textIn(controller), TextAnimationPreset.words);
      expect(spanOf(controller), 7);
    });
  });

  group("the end curve", () {
    CanvasController controllerFor() {
      var controller = CanvasController(
          CanvasDocument(frames: 96, frameRate: 12).addElement(TextElement(
              const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 100),
              text: _line)));
      addTearDown(controller.dispose);
      return controller;
    }

    TextElement textIn(CanvasController c) =>
        c.document.elements.single as TextElement;

    test("survives the same preset being applied again", () {
      // Re-laying the keyframes for any other reason was putting the preset's
      // own curve back, so a chosen curve would not stay chosen.
      var controller = controllerFor();
      controller.applyTextAnimation(
          textIn(controller), TextAnimationPreset.bounce);
      expect(textIn(controller).animation.ease, ChartEase.bounce);

      controller.replaceElement(textIn(controller).copyWith(
          animation:
              textIn(controller).animation.copyWith(ease: ChartEase.linear)));
      controller.applyTextAnimation(
          textIn(controller), TextAnimationPreset.bounce);
      expect(textIn(controller).animation.ease, ChartEase.linear,
          reason: "the curve somebody chose is still the curve");
    });

    test("and only a new preset brings its own", () {
      var controller = controllerFor();
      controller.applyTextAnimation(
          textIn(controller), TextAnimationPreset.fadeIn);
      controller.replaceElement(textIn(controller).copyWith(
          animation:
              textIn(controller).animation.copyWith(ease: ChartEase.spring)));

      controller.applyTextAnimation(
          textIn(controller), TextAnimationPreset.fadeUp);
      expect(textIn(controller).animation.ease, ChartEase.spring,
          reason: "a preset with no curve of its own leaves it alone");

      controller.applyTextAnimation(
          textIn(controller), TextAnimationPreset.bounce);
      expect(textIn(controller).animation.ease, ChartEase.bounce);
    });
  });

  group("the way out", () {
    // An arrival over frames 0 to 10, and an exit over 20 to 30.
    TextElement leaving({required bool partly}) => TextElement(
          const ElementBase(id: "t", x: 0, y: 20, width: 400, height: 90),
          text: _line,
          textSpec: const TextSpec(fontSize: 26, color: Color(0xFFFFFFFF)),
          parts: [
            TextPart(
                from: 5,
                to: 5,
                animation: partly
                    ? const TextPartAnimation(
                        preset: TextAnimationPreset.fadeIn,
                        ease: ChartEase.linear)
                    : const TextPartAnimation()),
          ],
          animation: const TextAnimation(
              preset: TextAnimationPreset.fadeIn,
              exit: TextAnimationPreset.fadeIn,
              ease: ChartEase.linear),
        ).withBase(
            track: ElementTrack([
          const Keyframe(frame: 0, values: {KeyframeChannel.reveal: 0}),
          const Keyframe(frame: 10, values: {KeyframeChannel.reveal: 1}),
          const Keyframe(frame: 20, values: {KeyframeChannel.close: 0}),
          const Keyframe(frame: 30, values: {KeyframeChannel.close: 1}),
        ])) as TextElement;

    testWidgets("takes the parts with it", (tester) async {
      // A part has a moment of its own on the way in. On the way out the
      // paragraph goes as one -- a word left hanging in mid-air while the
      // line it belongs to leaves is not an exit.
      late int plain;
      late int withPart;
      await tester.runAsync(() async {
        plain = _lit(await _ink(leaving(partly: false), 30));
        withPart = _lit(await _ink(leaving(partly: true), 30));
      });
      expect(plain, 0, reason: "the line has gone");
      expect(withPart, 0,
          reason: "and so has the word that arrived on its own");
    });

    testWidgets("and they are all still there half way out", (tester) async {
      late int lit;
      await tester.runAsync(() async {
        lit = _lit(await _ink(leaving(partly: true), 20));
      });
      expect(lit, greaterThan(300));
    });
  });

  group("an echo that resolves", () {
    Future<int> lit(bool resolve, int frame) async => _lit(await _ink(
        _headline(
            animation: TextAnimation(
                preset: TextAnimationPreset.echoDown,
                ease: ChartEase.linear,
                echo: TextEchoSpec(resolve: resolve))),
        frame));

    testWidgets("leaves nothing behind when it is over", (tester) async {
      late int kept;
      late int gone;
      late int midway;
      await tester.runAsync(() async {
        kept = await lit(false, 10);
        gone = await lit(true, 10);
        midway = await lit(true, 4);
      });
      expect(midway, greaterThan(gone + 200),
          reason: "the copies are there on the way: $midway then $gone");
      expect(kept, greaterThan(gone + 200),
          reason: "an echo that does not resolve keeps them: $kept, $gone");
    });

    test("so the still drawing takes over at the end", () {
      const kept = TextAnimation(preset: TextAnimationPreset.echoDown);
      expect(kept.keeps, isTrue);
      expect(
          const TextAnimation(
                  preset: TextAnimationPreset.echoDown,
                  echo: TextEchoSpec(resolve: true))
              .keeps,
          isFalse);
      expect(
          TextEchoSpec.fromJson(const TextEchoSpec(resolve: true).toJson())
              .resolve,
          isTrue);
    });
  });

  group("an old document", () {
    test("opens with its pointed animation on the part it pointed at", () {
      // The arrival used to be able to name one part and happen to that
      // instead of to the paragraph. Read back unchanged, such a document
      // would open with the animation apparently applied to everything.
      var json = {
        "kind": "text",
        "id": "t",
        "text": _line,
        "animation": {"preset": "echoDown", "part": 1, "gap": 0.5},
        "parts": [
          {"from": 1, "to": 2},
          {"from": 5, "to": 5},
        ],
      };
      var back = elementFromJson(json) as TextElement;
      expect(back.parts[1].animation.preset, TextAnimationPreset.echoDown);
      expect(back.parts[1].animation.gap, 0.5);
      expect(back.parts[0].animation.on, isFalse);
    });
  });
}
