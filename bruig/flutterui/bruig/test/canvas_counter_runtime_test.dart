import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/counter_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_counter_runtime_test.dart is where a counter's number comes from.
//
// Two places, which is the whole shape of this element: the timeline, where
// the count is keyframes and the number between them is interpolated like any
// other animated property; and a clock, where it runs in real time and the
// buttons under it mean something.
//
// The keyframes hold the *value* rather than a fraction of the way through,
// which is what makes a point in the middle worth having: a count from 0 to
// 100 can pass through 140 and come back, and a fraction cannot say that.

CanvasController _with(CounterElement counter, {int frames = 100}) =>
    CanvasController(CanvasDocument(
      size: const CanvasSize(width: 800, ratio: CanvasRatio.wide),
      frames: frames,
      elements: [counter],
    ));

CounterElement _counterIn(CanvasController c) =>
    c.document.elements.single as CounterElement;

const _base = ElementBase(id: "c", x: 40, y: 40, width: 300, height: 120);

void main() {
  group("counting on the timeline", () {
    test("is the value at the frame, between the two ends", () {
      var controller = _with(const CounterElement(_base, from: 0, to: 100));
      addTearDown(controller.dispose);

      controller.frame = 0;
      controller.setValueKey(_counterIn(controller), KeyframeChannel.count, 0);
      controller.frame = 20;
      controller.setValueKey(
          _counterIn(controller), KeyframeChannel.count, 100);

      double at(int frame) {
        controller.frame = frame;
        return controller.valueAt(
            _counterIn(controller), KeyframeChannel.count, 0);
      }

      expect(at(0), 0);
      expect(at(10), closeTo(50, 0.001));
      expect(at(20), 100);
    });

    test("and holds at the end rather than carrying on", () {
      // Every other keyframed property holds; a counter that kept counting
      // after its last keyframe would be a number nobody had asked for.
      var controller = _with(const CounterElement(_base, from: 0, to: 100));
      addTearDown(controller.dispose);
      controller.frame = 0;
      controller.setValueKey(_counterIn(controller), KeyframeChannel.count, 0);
      controller.frame = 20;
      controller.setValueKey(
          _counterIn(controller), KeyframeChannel.count, 100);

      controller.frame = 90;
      expect(
          controller.valueAt(_counterIn(controller), KeyframeChannel.count, 0),
          100);
    });

    test("a point in between can be higher than either end", () {
      // Which is the reason the channel holds the number and not a fraction.
      var controller = _with(const CounterElement(_base, from: 0, to: 100));
      addTearDown(controller.dispose);

      controller.frame = 0;
      controller.setValueKey(_counterIn(controller), KeyframeChannel.count, 0);
      controller.frame = 10;
      controller.setValueKey(
          _counterIn(controller), KeyframeChannel.count, 140);
      controller.frame = 20;
      controller.setValueKey(
          _counterIn(controller), KeyframeChannel.count, 100);

      controller.frame = 10;
      expect(
          controller.valueAt(_counterIn(controller), KeyframeChannel.count, 0),
          140);
      controller.frame = 15;
      expect(
          controller.valueAt(_counterIn(controller), KeyframeChannel.count, 0),
          closeTo(120, 0.001),
          reason: "and it comes back down from there");
    });

    test("and the two ends are keyframes like any other", () {
      // So they are dragged on the timeline rather than typed as frame
      // numbers, and nothing about the timeline had to learn what a counter
      // is.
      var controller = _with(const CounterElement(_base, from: 5, to: 9));
      addTearDown(controller.dispose);
      controller.frame = 12;
      controller.setValueKey(_counterIn(controller), KeyframeChannel.count, 5);
      expect(_counterIn(controller).track?.keyAt(12), isNotNull);
      expect(
          controller.hasValueKey(_counterIn(controller), KeyframeChannel.count),
          isTrue);
    });
  });

  group("what the canvas actually draws", () {
    testWidgets("is the keyframed number, not the counter's starting value",
        (tester) async {
      // The live callback used to answer for every counter, keyed or not --
      // and for a keyed one it says "where its clock has got to", which is
      // where the count starts. So the value moved in the settings panel as
      // the playhead moved and the number on the canvas never changed.
      var controller = _with(const CounterElement(_base, from: 0, to: 100));
      addTearDown(controller.dispose);
      controller.frame = 0;
      controller.setValueKey(_counterIn(controller), KeyframeChannel.count, 0);
      controller.frame = 20;
      controller.setValueKey(
          _counterIn(controller), KeyframeChannel.count, 100);

      Future<List<int>> shot(int frame) async {
        var recorder = ui.PictureRecorder();
        var canvas = ui.Canvas(recorder);
        canvas.drawRect(const Rect.fromLTWH(0, 0, 400, 200),
            Paint()..color = const Color(0xFF000000));
        paintElement(canvas, _counterIn(controller), frame,
            counterValue: controller.counterValue,
            counterRunning: controller.counterRunning);
        var picture = recorder.endRecording();
        var image = await picture.toImage(400, 200);
        var bytes = (await image.toByteData())!;
        image.dispose();
        picture.dispose();
        return [
          for (var i = 0; i < bytes.lengthInBytes; i += 4) bytes.getUint32(i)
        ];
      }

      late List<int> start, middle, end;
      await tester.runAsync(() async {
        start = await shot(0);
        middle = await shot(10);
        end = await shot(20);
      });
      expect(middle, isNot(start), reason: "half way through it says 50");
      expect(end, isNot(middle));
    });
  });

  group("a keyframe that only carries a number", () {
    test("does not say the element has been posed", () {
      // The pose diamond covers position, size, angle and fade. A count is
      // none of those, and lighting it said they were pinned here when they
      // were not.
      var controller = _with(const CounterElement(_base, from: 0, to: 100));
      addTearDown(controller.dispose);
      controller.frame = 8;
      // Seedless, the way the counter's own buttons pin it: the seed is a
      // resting pose at frame 0, and a resting pose laid deliberately is how
      // a track says the element is animated in space.
      controller.setValueKey(_counterIn(controller), KeyframeChannel.count, 40,
          seed: false);

      var key = _counterIn(controller).track?.keyAt(8);
      expect(key, isNotNull);
      expect(key!.posesElement, isFalse);
      expect(key.values.containsKey(KeyframeChannel.count), isTrue);
      expect(_counterIn(controller).track?.posesAnything, isFalse,
          reason: "so a drag still moves it rather than posing it");
    });

    test("and survives a pose being laid on the same frame", () {
      // A keyframe holds the pose and the channels together; writing a pose
      // over one used to throw the count away.
      var controller = _with(const CounterElement(_base, from: 0, to: 100));
      addTearDown(controller.dispose);
      controller.frame = 8;
      controller.setValueKey(_counterIn(controller), KeyframeChannel.count, 40,
          seed: false);
      controller.setKeyframe(
          "c", _counterIn(controller).poseAt(8).copyWith(frame: 8, dx: 12));

      var key = _counterIn(controller).track?.keyAt(8);
      expect(key?.dx, 12);
      expect(key?.values[KeyframeChannel.count], 40);
    });

    test("and is left behind when the pose is taken away again", () {
      var controller = _with(const CounterElement(_base, from: 0, to: 100));
      addTearDown(controller.dispose);
      controller.frame = 8;
      controller.setValueKey(_counterIn(controller), KeyframeChannel.count, 40,
          seed: false);
      controller.setKeyframe(
          "c", _counterIn(controller).poseAt(8).copyWith(frame: 8, dx: 12));

      // What the pose diamond does, which is not what deleting the keyframe
      // does: a deliberate delete on the timeline takes the whole mark, and
      // an animation is a pair.
      controller.clearPose("c", 8);
      var key = _counterIn(controller).track?.keyAt(8);
      expect(key?.values[KeyframeChannel.count], 40,
          reason: "the diamond says position, size, angle and fade");
      expect(key?.dx, 0);

      controller.removeKeyframe("c", 8);
      expect(_counterIn(controller).track?.keyAt(8), isNull,
          reason: "deleting the keyframe deletes all of it");
    });
  });

  group("arriving and leaving", () {
    test("is offered on a counter like any other thing in a box", () {
      // It was not: the counter was missing from the three lists that decide
      // which kinds have an arrival, so the whole section did nothing.
      expect(CanvasController.animates(const CounterElement(_base)), isTrue);
      expect(
          CanvasController.elementAnimationOf(const CounterElement(_base,
                  animation:
                      ElementAnimation(preset: ElementAnimationPreset.fadeUp)))
              .preset,
          ElementAnimationPreset.fadeUp);
    });

    test("and choosing a preset lays the keyframes that run it", () {
      var controller = _with(const CounterElement(_base));
      addTearDown(controller.dispose);
      controller.applyElementAnimation(
          _counterIn(controller), ElementAnimationPreset.fadeUp);

      var e = _counterIn(controller);
      expect(e.animation.preset, ElementAnimationPreset.fadeUp);
      expect(e.track?.keys.length ?? 0, greaterThanOrEqualTo(2),
          reason: "an arrival is a pair of keyframes");
    });
  });

  group("how the number travels between two points", () {
    test("slides, by default", () {
      var controller = _with(const CounterElement(_base, from: 0, to: 100));
      addTearDown(controller.dispose);
      controller.frame = 0;
      controller.setValueKey(_counterIn(controller), KeyframeChannel.count, 0,
          seed: false);
      controller.frame = 20;
      controller.setValueKey(_counterIn(controller), KeyframeChannel.count, 100,
          seed: false);

      controller.frame = 10;
      expect(
          controller.valueAt(_counterIn(controller), KeyframeChannel.count, -1),
          closeTo(50, 0.001));
    });

    test("or stays as it is until the next point, on Hold", () {
      // A count that goes up in steps rather than sliding: the number holds
      // and then changes, which is what a scoreboard does.
      var controller = _with(const CounterElement(_base, from: 0, to: 100));
      addTearDown(controller.dispose);
      controller.frame = 0;
      controller.setValueKey(_counterIn(controller), KeyframeChannel.count, 0,
          seed: false);
      controller.frame = 20;
      controller.setValueKey(_counterIn(controller), KeyframeChannel.count, 100,
          seed: false);

      var first = _counterIn(controller).track!.keyAt(0)!;
      controller.setKeyframe("c", first.copyWith(easing: KeyframeEasing.hold));

      double at(int frame) {
        controller.frame = frame;
        return controller.valueAt(
            _counterIn(controller), KeyframeChannel.count, -1);
      }

      expect(at(1), 0);
      expect(at(19), 0, reason: "all the way to the next point");
      expect(at(20), 100, reason: "and then it is the next point");
    });

    test("and one easing can be given to every point at once", () {
      // A count is usually one movement in several hops, and setting each hop
      // by hand is the same choice made four times.
      var controller = _with(const CounterElement(_base, from: 0, to: 100));
      addTearDown(controller.dispose);
      for (var frame in [0, 8, 16]) {
        controller.frame = frame;
        controller.setValueKey(
            _counterIn(controller), KeyframeChannel.count, frame * 5,
            seed: false);
      }
      // A move keyframed on the same element, which is not the count's to
      // restyle.
      controller.setKeyframe("c", const Keyframe(frame: 20, dx: 30));

      controller.setKeyframeEasing(_counterIn(controller), KeyframeEasing.hold,
          all: true, channel: KeyframeChannel.count);

      var track = _counterIn(controller).track!;
      for (var frame in [0, 8, 16]) {
        expect(track.keyAt(frame)?.easing, KeyframeEasing.hold,
            reason: "frame $frame");
      }
      expect(track.keyAt(20)?.easing, KeyframeEasing.linear,
          reason: "the move keyframe carries no number and is left alone");
    });

    test("and the easing belongs to the keyframe it leaves", () {
      // The same field the timeline's own panel shows: one value, two places
      // to reach it, rather than a second kind of easing only counters have.
      var controller = _with(const CounterElement(_base));
      addTearDown(controller.dispose);
      controller.frame = 4;
      controller.setValueKey(_counterIn(controller), KeyframeChannel.count, 5,
          seed: false);
      var key = _counterIn(controller).track!.keyAt(4)!;
      controller.setKeyframe(
          "c", key.copyWith(easing: KeyframeEasing.easeInOut));

      var after = _counterIn(controller).track!.keyAt(4)!;
      expect(after.easing, KeyframeEasing.easeInOut);
      expect(after.values[KeyframeChannel.count], 5,
          reason: "and setting it does not take the number away");
    });
  });

  group("counting in real time", () {
    CounterElement live({
      double from = 0,
      double to = 60,
      double rate = 1,
      bool loop = false,
      List<CounterButton> buttons = const [CounterButton.startStop],
    }) =>
        CounterElement(_base,
            from: from,
            to: to,
            rate: rate,
            loop: loop,
            keyed: false,
            buttons: buttons);

    test("starts where the count starts, and holds until it is started", () {
      var controller = _with(live());
      addTearDown(controller.dispose);
      var e = _counterIn(controller);
      expect(controller.counterValue(e), 0);
      expect(controller.counterRunning(e), isFalse);

      controller.tickCounters(
          now: DateTime(2026).add(const Duration(hours: 1)));
      expect(controller.counterValue(e), 0, reason: "nothing is running");
    });

    test("moves by the time that has actually passed", () {
      // By the clock rather than by a fixed step per tick: a timer that loses
      // time whenever the window is busy is a broken timer.
      var controller = _with(live(rate: 2));
      addTearDown(controller.dispose);
      var e = _counterIn(controller);
      // From now, because a running counter is measured against the clock:
      // a moment in the past is no time at all having passed.
      var start = DateTime.now();

      controller.pressCounterButton(e, CounterButton.startStop);
      expect(controller.counterRunning(e), isTrue);

      controller.tickCounters(now: start.add(const Duration(seconds: 3)));
      expect(controller.counterValue(e), greaterThan(0));
      expect(controller.counterValue(e), lessThanOrEqualTo(6.01));
    });

    test("stops at the far end", () {
      var controller = _with(live(to: 5, rate: 10));
      addTearDown(controller.dispose);
      var e = _counterIn(controller);
      controller.pressCounterButton(e, CounterButton.startStop);
      controller.tickCounters(now: DateTime.now().add(const Duration(days: 1)));

      expect(controller.counterValue(e), 5);
      expect(controller.counterRunning(e), isFalse,
          reason: "a count that has finished is not still counting");
    });

    test("and starts again when it is told to loop", () {
      // Which is what makes a metronome rather than a counter that ran out.
      var controller = _with(live(to: 5, rate: 10, loop: true));
      addTearDown(controller.dispose);
      var e = _counterIn(controller);
      controller.pressCounterButton(e, CounterButton.startStop);
      controller.tickCounters(
          now: DateTime.now().add(const Duration(seconds: 2)));

      expect(controller.counterRunning(e), isTrue);
      expect(controller.counterValue(e), lessThan(5));
    });

    test("counts down when the ends are the other way round", () {
      var controller = _with(live(from: 10, to: 0, rate: 1));
      addTearDown(controller.dispose);
      var e = _counterIn(controller);
      controller.pressCounterButton(e, CounterButton.startStop);
      controller.tickCounters(
          now: DateTime.now().add(const Duration(seconds: 3)));

      expect(controller.counterValue(e), lessThan(10),
          reason: "the rate is how fast, not which way");
      expect(controller.counterValue(e), greaterThanOrEqualTo(0));
    });

    test("stop holds it where it is, and start picks it up again", () {
      var controller = _with(live(rate: 1));
      addTearDown(controller.dispose);
      var e = _counterIn(controller);
      controller.pressCounterButton(e, CounterButton.startStop);
      controller.tickCounters(
          now: DateTime.now().add(const Duration(seconds: 4)));
      var held = controller.counterValue(e);
      expect(held, greaterThan(0));

      controller.pressCounterButton(e, CounterButton.startStop);
      expect(controller.counterRunning(e), isFalse);
      controller.tickCounters(
          now: DateTime.now().add(const Duration(seconds: 40)));
      expect(controller.counterValue(e), held, reason: "stopped is stopped");

      controller.pressCounterButton(e, CounterButton.startStop);
      expect(controller.counterRunning(e), isTrue);
    });

    test("reset takes it back to the start", () {
      var controller = _with(live(rate: 1));
      addTearDown(controller.dispose);
      var e = _counterIn(controller);
      controller.setCounterValue(e, 30);
      expect(controller.counterValue(e), 30);

      controller.pressCounterButton(e, CounterButton.reset);
      expect(controller.counterValue(e), 0);
    });

    test("and Set is the one press the controller cannot answer", () {
      // Asking for a number needs a window, which the controller has not got.
      var controller = _with(live());
      addTearDown(controller.dispose);
      expect(
          controller.pressCounterButton(
              _counterIn(controller), CounterButton.input),
          isFalse);
      expect(
          controller.pressCounterButton(
              _counterIn(controller), CounterButton.reset),
          isTrue);
    });

    test("typing a value does not stop a running counter", () {
      var controller = _with(live(rate: 1));
      addTearDown(controller.dispose);
      var e = _counterIn(controller);
      controller.pressCounterButton(e, CounterButton.startStop);
      controller.setCounterValue(e, 12);
      expect(controller.counterValue(e), 12);
      expect(controller.counterRunning(e), isTrue);
    });

    test("a clock runs whether anybody pressed anything or not", () {
      var controller = _with(const CounterElement(_base,
          keyed: false,
          source: CounterSource.clock,
          separator: CounterSeparator.hours));
      addTearDown(controller.dispose);
      var e = _counterIn(controller);
      expect(controller.counterRunning(e), isTrue,
          reason: "there is nothing to start or stop about the afternoon");
      var now = controller.counterValue(e);
      expect(now, greaterThanOrEqualTo(0));
      expect(now, lessThan(86400));
    });

    test("and a keyed counter ignores all of it", () {
      var controller = _with(const CounterElement(_base, from: 7, to: 9));
      addTearDown(controller.dispose);
      var e = _counterIn(controller);
      expect(controller.counterValue(e), 7);
      expect(controller.counterRunning(e), isFalse);
      controller.pressCounterButton(e, CounterButton.startStop);
      expect(controller.counterRunning(e), isFalse);
    });

    test("counters that say they start running do", () {
      var controller = _with(const CounterElement(_base,
          keyed: false, running: true, to: 1000, rate: 1));
      addTearDown(controller.dispose);
      controller.startCounters();
      expect(controller.counterRunning(_counterIn(controller)), isTrue);
    });
  });

  group("the start button", () {
    testWidgets("says which of its two jobs it would do next", (tester) async {
      // The only honest label for a control with two jobs -- and it has to
      // follow what is actually running rather than what the element says it
      // does when it opens, or a stopwatch that has been started still says
      // Start.
      const e = CounterElement(_base,
          keyed: false,
          buttons: [CounterButton.startStop],
          buttonSpec: TextSpec(fontSize: 16, color: Color(0xFFFFFFFF)),
          buttonBox: BoxSpec(fill: Color(0xFF000000), padding: 6));

      Future<List<int>> shot(bool running) async {
        var recorder = ui.PictureRecorder();
        var canvas = ui.Canvas(recorder);
        canvas.drawRect(const Rect.fromLTWH(0, 0, 300, 120),
            Paint()..color = const Color(0xFF000000));
        paintCounter(canvas, const Rect.fromLTWH(0, 0, 300, 120), e, 0,
            running: running);
        var picture = recorder.endRecording();
        var image = await picture.toImage(300, 120);
        var bytes = (await image.toByteData())!;
        image.dispose();
        picture.dispose();
        return [
          for (var i = 0; i < bytes.lengthInBytes; i += 4) bytes.getUint32(i)
        ];
      }

      late List<int> stopped, going;
      await tester.runAsync(() async {
        stopped = await shot(false);
        going = await shot(true);
      });
      expect(going, isNot(stopped),
          reason: "Start and Stop are not the same word");
    });
  });

  group("the drawing", () {
    const room = Rect.fromLTWH(0, 0, 300, 120);

    test("puts one button across the width and three side by side", () {
      const one = CounterElement(_base,
          keyed: false, buttons: [CounterButton.startStop]);
      const three = CounterElement(_base, keyed: false, buttons: [
        CounterButton.startStop,
        CounterButton.reset,
        CounterButton.input,
      ]);

      expect(counterButtonRects(one, room), hasLength(1));
      var rects = counterButtonRects(three, room);
      expect(rects, hasLength(3));
      expect(rects[0].width, closeTo(rects[2].width, 0.001));
      expect(rects[0].right, lessThan(rects[1].left), reason: "with a gap");
      // Along the bottom of the box, inside its padding.
      expect(rects.last.bottom, closeTo(one.box.inner(room).bottom, 0.001));
    });

    test("and none at all for a counter with no buttons", () {
      expect(counterButtonRects(const CounterElement(_base), room), isEmpty);
    });

    testWidgets("shrinks the type until the whole count fits", (tester) async {
      // The width of a number changes as it counts, so a counter set to look
      // right at 42 is cut off at 1,234,567.
      const small = CounterElement(_base, from: 0, to: 42);
      const large = CounterElement(_base, from: 0, to: 1234567);
      expect(counterFitScale(small, room, 0), 1,
          reason: "a short count needs no shrinking");
      expect(counterFitScale(large, room, 0), lessThan(1));
    });

    testWidgets("by the widest value it will ever show, not the one showing",
        (tester) async {
      // Otherwise the figures change size partway through the count, which is
      // worse than their being small.
      const e = CounterElement(_base, from: 0, to: 1234567);
      expect(counterFitScale(e, room, 0), counterFitScale(e, room, 1234567));
    });
  });

  group("placing the words and the buttons", () {
    const room = Rect.fromLTWH(0, 0, 300, 120);

    test("a row until somebody says otherwise", () {
      const e = CounterElement(_base, keyed: false, buttons: [
        CounterButton.startStop,
        CounterButton.reset,
      ]);
      var rects = counterButtonRects(e, room);
      expect(rects[0].top, closeTo(rects[1].top, 0.001),
          reason: "side by side along the bottom");
    });

    test("and where they were put once they are let loose", () {
      const e = CounterElement(_base,
          keyed: false,
          looseButtons: true,
          buttons: [CounterButton.startStop, CounterButton.reset],
          buttonAt: [Offset(-0.3, -0.2), Offset(0.3, 0.2)]);
      var rects = counterButtonRects(e, room);
      var inner = e.box.inner(room);
      expect(rects[0].center.dx,
          closeTo(inner.center.dx - inner.width * 0.3, 0.001));
      expect(rects[1].center.dy,
          closeTo(inner.center.dy + inner.height * 0.2, 0.001));
    });

    test("a button nobody has placed gets somewhere of its own", () {
      // Three buttons stacked on one another the moment the setting is
      // switched on would look like two of them had gone.
      const e =
          CounterElement(_base, keyed: false, looseButtons: true, buttons: [
        CounterButton.startStop,
        CounterButton.reset,
        CounterButton.input,
      ]);
      var places = {for (var i = 0; i < 3; i++) e.placedButton(i)};
      expect(places, hasLength(3));
    });

    test("and a placement is a fraction of the box, not a position in it", () {
      // So the words stay where they were put when the counter is resized.
      const e = CounterElement(_base,
          keyed: false,
          looseButtons: true,
          buttons: [CounterButton.startStop],
          buttonAt: [Offset(0.25, 0)]);
      var small = counterButtonRects(e, const Rect.fromLTWH(0, 0, 200, 100));
      var large = counterButtonRects(e, const Rect.fromLTWH(0, 0, 400, 200));
      var smallInner = e.box.inner(const Rect.fromLTWH(0, 0, 200, 100));
      var largeInner = e.box.inner(const Rect.fromLTWH(0, 0, 400, 200));
      expect(
          (small.first.center.dx - smallInner.center.dx) / smallInner.width,
          closeTo(
              (large.first.center.dx - largeInner.center.dx) / largeInner.width,
              0.001));
    });

    testWidgets("the gap pushes the words off the number", (tester) async {
      Future<List<int>> shot(double gap) async {
        var e = CounterElement(_base,
            before: "£",
            after: "bpm",
            gap: gap,
            fit: false,
            numberSpec: const TextSpec(fontSize: 40, color: Color(0xFFFFFFFF)),
            affixSpec: const TextSpec(fontSize: 20, color: Color(0xFFFFFFFF)));
        var recorder = ui.PictureRecorder();
        var canvas = ui.Canvas(recorder);
        canvas.drawRect(room, Paint()..color = const Color(0xFF000000));
        paintCounter(canvas, room, e, 42);
        var picture = recorder.endRecording();
        var image = await picture.toImage(300, 120);
        var bytes = (await image.toByteData())!;
        image.dispose();
        picture.dispose();
        return [
          for (var i = 0; i < bytes.lengthInBytes; i += 4) bytes.getUint32(i)
        ];
      }

      late List<int> tight, loose;
      await tester.runAsync(() async {
        tight = await shot(0);
        loose = await shot(1.5);
      });
      expect(loose, isNot(tight));
    });
  });
}
