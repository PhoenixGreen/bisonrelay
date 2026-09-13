import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';

// canvas_element_animation_test.dart is a shape or a picture arriving.
//
// The same two keyframes a chart and a headline use, driving the same
// motions -- so what is worth pinning is that it really is the same
// machinery, and that the cutting effects draw something different at each
// end of the arrival.

const _size = 240.0;

ShapeElement _shape(ElementAnimation animation,
    {double? reveal, double? close}) {
  var element = ShapeElement(
    const ElementBase(id: "s", x: 40, y: 40, width: 160, height: 160),
    fill: const Color(0xFFFFFFFF),
    animation: animation,
  );
  if (reveal == null && close == null) return element;
  return element.withBase(
      track: ElementTrack([
    Keyframe(frame: 0, values: {
      if (reveal != null) KeyframeChannel.reveal: reveal,
      if (close != null) KeyframeChannel.close: close,
    }),
  ])) as ShapeElement;
}

/// _ink is every pixel the element lights, by where it is.
Future<Set<int>> _ink(CanvasElement element) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, _size, _size),
      Paint()..color = const Color(0xFF000000));
  paintElement(canvas, element, 0,
      document: CanvasDocument(elements: [element]));
  var picture = recorder.endRecording();
  var image = await picture.toImage(_size.toInt(), _size.toInt());
  var bytes = (await image.toByteData())!;
  var on = <int>{};
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    if (bytes.getUint32(i) != 0x000000FF) on.add(i ~/ 4);
  }
  image.dispose();
  picture.dispose();
  return on;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("a shape's own arrival", () {
    testWidgets("is not drawn before it starts and is whole at the end",
        (tester) async {
      const animation = ElementAnimation(preset: ElementAnimationPreset.fadeIn);
      late Set<int> before;
      late Set<int> after;
      late Set<int> none;
      await tester.runAsync(() async {
        before = await _ink(_shape(animation, reveal: 0));
        after = await _ink(_shape(animation, reveal: 1));
        none = await _ink(_shape(const ElementAnimation()));
      });
      expect(before, isEmpty, reason: "nothing has arrived yet");
      expect(after.length, none.length,
          reason: "and at the end it is exactly the shape it would have been");
    });

    testWidgets("leaves an element with no keyframes alone", (tester) async {
      // The channels default to 1 and 0 -- all of it, and not leaving -- so
      // an element that has been given a preset but never laid down on the
      // timeline is drawn the way it always was.
      late Set<int> plain;
      late Set<int> chosen;
      await tester.runAsync(() async {
        plain = await _ink(_shape(const ElementAnimation()));
        chosen = await _ink(
            _shape(const ElementAnimation(preset: ElementAnimationPreset.pop)));
      });
      expect(chosen.length, plain.length);
    });

    testWidgets("moves the shape when the motion is a movement",
        (tester) async {
      // Linear, so this is about the movement rather than about the curve:
      // eased, half the time is most of the way there.
      const sliding = ElementAnimation(
          preset: ElementAnimationPreset.slideLeft, ease: ChartEase.linear);
      late Set<int> early;
      late Set<int> done;
      await tester.runAsync(() async {
        early = await _ink(_shape(sliding, reveal: 0.5));
        done = await _ink(_shape(sliding, reveal: 1));
      });
      expect(early, isNotEmpty);
      // Somewhere else, and specifically further left: it is still coming in
      // from that side. Measured by where the ink starts rather than by how
      // much of it overlaps, since a shape half way through a slide of its
      // own width still covers most of where it lands.
      int leftmost(Set<int> ink) =>
          ink.map((at) => at % _size.toInt()).reduce((a, b) => a < b ? a : b);
      expect(leftmost(early), lessThan(leftmost(done) - 20),
          reason: "half way through it is still to the left of its place");
    });

    testWidgets("and the way out is the arrival played backwards",
        (tester) async {
      const both = ElementAnimation(
          preset: ElementAnimationPreset.fadeIn,
          exit: ElementAnimationPreset.fadeIn);
      late Set<int> going;
      late Set<int> gone;
      await tester.runAsync(() async {
        going = await _ink(_shape(both, reveal: 1, close: 0.5));
        gone = await _ink(_shape(both, reveal: 1, close: 1));
      });
      expect(going, isNotEmpty, reason: "half way out it is still there");
      expect(gone, isEmpty, reason: "and at the end of it, it is not");
    });
  });

  group("the cutting effects", () {
    for (var preset in [
      ElementAnimationPreset.mosaic,
      ElementAnimationPreset.glitch,
      ElementAnimationPreset.assemble,
      ElementAnimationPreset.shatter,
    ]) {
      testWidgets("${preset.label} draws something different on the way in",
          (tester) async {
        var animation = ElementAnimation(
            preset: preset, effect: preset.effect ?? const EffectSpec());
        late Set<int> early;
        late Set<int> done;
        await tester.runAsync(() async {
          early = await _ink(_shape(animation, reveal: 0.3));
          done = await _ink(_shape(animation, reveal: 1));
        });
        expect(done, isNotEmpty, reason: "it ends up whole");
        expect(early, isNotEmpty, reason: "and it is on its way, not absent");
        expect(early.difference(done).isNotEmpty || early.length != done.length,
            isTrue,
            reason: "part way through it is not simply the finished element");
      });
    }

    testWidgets("throw their pieces outside the element's own box",
        (tester) async {
      // What makes a shatter read as one: the tiles leave the box. A version
      // that kept them inside it is a fade in squares.
      const animation = ElementAnimation(
          preset: ElementAnimationPreset.shatter,
          effect: EffectSpec(pieces: 8, scatter: 1.2, stagger: 0));
      late Set<int> early;
      await tester.runAsync(() async {
        early = await _ink(_shape(animation, reveal: 0.25));
      });
      var outside = early.where((at) {
        var x = at % _size, y = at ~/ _size;
        return x < 38 || x > 202 || y < 38 || y > 202;
      });
      expect(outside, isNotEmpty,
          reason: "pieces are thrown clear of where the shape sits");
    });

    testWidgets("and the pieces settle exactly where the element was",
        (tester) async {
      const animation = ElementAnimation(
          preset: ElementAnimationPreset.assemble,
          effect: EffectSpec(pieces: 6, scatter: 0.5));
      late Set<int> assembled;
      late Set<int> plain;
      await tester.runAsync(() async {
        assembled = await _ink(_shape(animation, reveal: 1));
        plain = await _ink(_shape(const ElementAnimation()));
      });
      expect(assembled.length, plain.length,
          reason: "at the end there are no seams and nothing is missing");
    });
  });

  group("choosing one", () {
    CanvasController controllerWith(CanvasElement element) => CanvasController(
        CanvasDocument(frames: 48, frameRate: 12).addElement(element));

    ShapeElement shapeIn(CanvasController c) =>
        c.document.elements.single as ShapeElement;

    test("gives it a length on the timeline", () {
      // The same two keyframes a headline gets, on the same channel, so a
      // shape and a headline can be dragged to arrive together.
      var controller = controllerWith(_shape(const ElementAnimation()));
      addTearDown(controller.dispose);

      controller.applyElementAnimation(
          shapeIn(controller), ElementAnimationPreset.slideUp);

      var band = bandsIn(shapeIn(controller).track).single;
      expect(band.channel, KeyframeChannel.reveal);
      expect(band.real, isTrue, reason: "two keyframes, not one");
      expect(
          shapeIn(controller).animation.preset, ElementAnimationPreset.slideUp);
    });

    test("and choosing None takes them away again", () {
      var controller = controllerWith(_shape(const ElementAnimation()));
      addTearDown(controller.dispose);

      controller.applyElementAnimation(
          shapeIn(controller), ElementAnimationPreset.fadeIn);
      controller.applyElementAnimation(
          shapeIn(controller), ElementAnimationPreset.none);

      expect(shapeIn(controller).animation.on, isFalse);
      expect(shapeIn(controller).track, isNull,
          reason: "no animation left, so no empty track in the saved file");
    });

    test("brings the preset's own way of cutting with it", () {
      var controller = controllerWith(_shape(const ElementAnimation()));
      addTearDown(controller.dispose);

      controller.applyElementAnimation(
          shapeIn(controller), ElementAnimationPreset.shatter);
      var thrown = shapeIn(controller).animation.effect.scatter;
      expect(thrown, ElementAnimationPreset.shatter.effect!.scatter);

      // And leaves it alone afterwards: it is a starting point, not a
      // setting that cannot be changed.
      var element = shapeIn(controller);
      controller.replaceElement(element.copyWith(
          animation:
              element.animation.copyWith(effect: const EffectSpec(pieces: 3))));
      controller.applyElementAnimation(
          shapeIn(controller), ElementAnimationPreset.shatter);
      expect(shapeIn(controller).animation.effect.pieces, 3,
          reason: "trying the same preset again does not undo the numbers");
    });

    test("the way out is a second pair, after the first", () {
      var controller = controllerWith(_shape(const ElementAnimation()));
      addTearDown(controller.dispose);

      controller.applyElementAnimation(
          shapeIn(controller), ElementAnimationPreset.fadeIn);
      controller.applyElementExit(
          shapeIn(controller), ElementAnimationPreset.assemble);

      var bands = bandsIn(shapeIn(controller).track);
      expect(bands.length, 2);
      var arrive = bands.firstWhere((b) => b.channel == KeyframeChannel.reveal);
      var leave = bands.firstWhere((b) => b.channel == KeyframeChannel.close);
      expect(leave.from, greaterThan(arrive.to),
          reason: "it never starts before the arrival has finished");
    });
  });

  group("the curves", () {
    /// _widthAt is how wide the shape is drawn, which is what a scaling
    /// preset changes.
    Future<int> widthAt(ChartEase ease, double reveal) async {
      var ink = await _ink(_shape(
          ElementAnimation(preset: ElementAnimationPreset.scaleIn, ease: ease),
          reveal: reveal));
      if (ink.isEmpty) return 0;
      var xs = ink.map((at) => at % _size.toInt());
      return xs.reduce((a, b) => a > b ? a : b) -
          xs.reduce((a, b) => a < b ? a : b);
    }

    testWidgets("an overshoot actually goes past its place", (tester) async {
      // The whole of what an overshoot is. Decided on the eased number rather
      // than on the playhead, "finished" caught the moment it first went
      // past 1 -- so the element snapped to its place and the overshoot, the
      // settle and every wobble of a spring were never drawn. Both curves
      // came out as a slower ease-out.
      late int rest;
      late int past;
      await tester.runAsync(() async {
        rest = await widthAt(ChartEase.overshoot, 1);
        // Where back-out is above 1, which is most of the second half.
        past = await widthAt(ChartEase.overshoot, 0.62);
      });
      expect(past, greaterThan(rest),
          reason: "part way through it is larger than it ends up");
    });

    testWidgets("and a spring swings both ways before it settles",
        (tester) async {
      late int rest;
      late List<int> swing;
      await tester.runAsync(() async {
        rest = await widthAt(ChartEase.spring, 1);
        swing = [
          for (var at in [0.1, 0.2, 0.3, 0.45])
            await widthAt(ChartEase.spring, at),
        ];
      });
      expect(swing.where((w) => w > rest), isNotEmpty,
          reason: "it passes its place");
      expect(swing.where((w) => w < rest), isNotEmpty,
          reason: "and comes back under it");
    });
  });

  group("a glitch", () {
    Future<Set<int>> at(double reveal) => _ink(_shape(
        const ElementAnimation(
            preset: ElementAnimationPreset.glitch, ease: ChartEase.linear),
        reveal: reveal));

    testWidgets("holds still and then jumps, rather than sliding",
        (tester) async {
      // What makes it read as a glitch. Worked out from the progress alone
      // the bands slide smoothly from far to near, and the eye reads that as
      // the element sliding in slices. The progress is chopped into ticks:
      // nothing moves within one, and everything moves between two.
      late Set<int> a;
      late Set<int> b;
      late Set<int> c;
      await tester.runAsync(() async {
        // Two moments inside one twelfth, and one in the next.
        a = await at(0.26);
        b = await at(0.32);
        c = await at(0.36);
      });
      expect(a.difference(b), isEmpty, reason: "within a tick it is held");
      expect(b.difference(c), isNotEmpty, reason: "and at the next it jumps");
    });

    testWidgets("tears some bands and leaves others alone", (tester) async {
      // Every band moving is a wobble; a few of them moving is damage.
      late Set<int> torn;
      late Set<int> whole;
      await tester.runAsync(() async {
        torn = await at(0.2);
        whole = await at(1);
      });
      expect(torn.intersection(whole), isNotEmpty,
          reason: "some of it is still where it belongs");
      // The damage shows as holes rather than as spill: a band is clipped to
      // where it sits in the finished picture and the drawing moves
      // underneath it, so a tear takes ink away and never puts any outside
      // the element. A picture that bled past its own edges when it glitched
      // would be a picture that cannot be trusted in a layout.
      expect(whole.difference(torn), isNotEmpty,
          reason: "and some of it has been torn away");
      expect(torn.difference(whole), isEmpty,
          reason: "with nothing thrown outside the element");
    });
  });

  group("the settings and the timeline", () {
    test("a shape and a picture both carry an animation", () {
      var shape = ShapeElement(const ElementBase(id: "s"),
          animation: const ElementAnimation(
              preset: ElementAnimationPreset.glitch, length: 30));
      var image = ImageElement(const ElementBase(id: "i"),
          animation:
              const ElementAnimation(preset: ElementAnimationPreset.shatter));
      expect(CanvasController.animates(shape), isTrue);
      expect(CanvasController.animates(image), isTrue);
      expect(CanvasController.elementAnimationOf(shape).preset,
          ElementAnimationPreset.glitch);
      expect(CanvasController.elementAnimationOf(image).preset,
          ElementAnimationPreset.shatter);
    });

    test("and it survives being saved", () {
      var shape = ShapeElement(const ElementBase(id: "s"),
          animation: const ElementAnimation(
              preset: ElementAnimationPreset.assemble,
              exit: ElementAnimationPreset.shatter,
              effect: EffectSpec(pieces: 14, scatter: 0.9, spin: 0.3),
              length: 42));
      var back = elementFromJson(shape.toJson()) as ShapeElement;
      expect(back.animation, shape.animation);
    });

    test("the presets carry their own way of cutting", () {
      // Build up and Break apart are the same motion: what makes them two
      // animations is how far the pieces are thrown and how much they turn,
      // so a preset that did not carry those would be a name with nothing
      // behind it.
      expect(ElementAnimationPreset.assemble.motion, TextMotion.pieces);
      expect(ElementAnimationPreset.shatter.motion, TextMotion.pieces);
      expect(ElementAnimationPreset.shatter.effect!.scatter,
          greaterThan(ElementAnimationPreset.assemble.effect!.scatter));
    });
  });
}
