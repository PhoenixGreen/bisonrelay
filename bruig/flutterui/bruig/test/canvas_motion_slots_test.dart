import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_player.dart';
import 'package:flutter_test/flutter_test.dart';

// The elements' slots through the controller, on its clock: a slot pressed
// with nothing playing plays the slots alone; a cue launches its row of
// every element's; Back to the timeline puts them back; and what was
// launched while recording is on the timeline after.

MotionClip across(String id, double by, {double length = 1}) =>
    MotionClip.ofKind(id, MotionKind.action, name: id).copyWith(
        length: length,
        after: ClipHold.last,
        quantise: () => Quantise.off.name,
        keys: {
          MotionProp.x: [
            const MotionKey(0, MotionNumber(0)),
            MotionKey(length, MotionNumber(by)),
          ],
        });

typedef MotionPoseSample = ({double dx, double scale});

void main() {
  int micros = 0;
  CanvasController make() {
    micros = 0;
    var c = CanvasController(CanvasDocument(
      frames: 24 * 20,
      frameRate: 24,
      audio: const AudioSettings(tempo: 120),
      elements: [
        ShapeElement(ElementBase(
            id: "a",
            width: 10,
            height: 10,
            motion: ElementMotion(
                clips: [across("go", 100)], slots: const ["go"]))),
        ShapeElement(ElementBase(
            id: "b",
            x: 50,
            width: 10,
            height: 10,
            motion: ElementMotion(
                clips: [across("hop", 0), across("run", 40)],
                slots: const ["hop", "run"]))),
      ],
    ));
    c.clockForTest = () => micros;
    return c;
  }

  /// at moves the clock on to [seconds], a frame at a time.
  void at(CanvasController c, double seconds) {
    var to = (seconds * 1e6).round();
    while (micros < to) {
      micros = (micros + 1e6 ~/ 48).clamp(0, to);
      c.tickClockForTest();
    }
    c.tickClockForTest();
  }

  double dx(CanvasController c, String id) =>
      poseWithMotion(c.document.elementById(id)!, c.frame, c.document,
              live: c.liveMotion)
          .dx;

  test("pressed with nothing playing, the slots play alone", () {
    var c = make();
    addTearDown(c.dispose);
    c.pressMotionSlot("a", 0);
    expect(c.sessionOnly, isTrue, reason: "the timeline stays where it is");
    expect(c.motionSlotState("a", 0), MotionSlotState.playing);
    at(c, 0.5);
    expect(c.frame, 0);
    expect(dx(c, "a"), closeTo(50, 2));
    expect(c.offTimeline, isTrue);
    c.pause();
    expect(c.liveMotion, isNull, reason: "playing only them, back after");
  });

  test("a cue launches its row of every element's slots", () {
    var c = make();
    addTearDown(c.dispose);
    c.launchScene(1);
    at(c, 0.5);
    expect(dx(c, "a"), 0, reason: "nothing in its row: as it was");
    expect(dx(c, "b"), closeTo(20, 2));
  });

  test("over the timeline, an element stays off it until Back", () {
    var c = make();
    addTearDown(c.dispose);
    c.play();
    c.pressMotionSlot("a", 0);
    at(c, 2);
    c.pause();
    expect(c.offTimeline, isTrue);
    expect(dx(c, "a"), 100, reason: "left where its clip took it");
    c.backToTimeline();
    expect(c.offTimeline, isFalse);
    expect(dx(c, "a"), 0);
  });

  test("launched while recording, it is on the timeline after", () {
    var c = make();
    addTearDown(c.dispose);
    c.recording = true;
    at(c, 1);
    c.pressMotionSlot("a", 0);
    at(c, 3);
    c.recording = false;
    var placed = c.motionOf("a").placed.single;
    expect(placed.clip, "go");
    expect(placed.start, closeTo(1, 0.05));
    expect(placed.length, closeTo(1, 0.05));
    c.pause();
    c.undo();
    expect(c.motionOf("a").placed, isEmpty, reason: "one step to take back");
  });

  // Ken, 2026-11-08: an arrival placed on the timeline and launched from its
  // slot showed only part of itself -- played on top of its own held first
  // frame: Pop at nothing, Slide in from twice as far, ending off the page.
  group("launched over the timeline", () {
    CanvasController arrivals() =>
        CanvasController(CanvasDocument(frames: 240, frameRate: 24, elements: [
          ShapeElement(const ElementBase(
              id: "a", name: "A", x: 300, y: 200, width: 50, height: 50)),
        ]));
    MotionPoseSample sample(CanvasController c) {
      var p = motionPoseIn(c.document, c.document.elementById("a")!, c.frame,
          live: c.motionPlayer.of("a"), clock: c.motionPlayer.clock);
      return (dx: p.dx, scale: p.scale);
    }

    for (var name in ["Pop", "Slide in"]) {
      testWidgets("$name, placed too, plays in full from its slot",
          (tester) async {
        var c = arrivals();
        addTearDown(c.dispose);
        var id = c.newClip("a", preset: presetNamed(name), slot: 0);
        c.placeClip("a", id, seconds: 0);
        c.pressMotionSlot("a", 0);
        var first = sample(c);
        var seen = <MotionPoseSample>[];
        for (var i = 0; i < 16; i++) {
          await tester.pump(const Duration(milliseconds: 80));
          seen.add(sample(c));
        }
        c.pause();
        if (name == "Pop") {
          expect(first.scale, closeTo(0, 0.01));
          expect(seen.map((s) => s.scale).reduce((a, b) => a > b ? a : b),
              greaterThan(1.05),
              reason: "it grows, overshoots");
          expect(seen.last.scale, closeTo(1, 0.01), reason: "and settles");
        } else {
          expect(first.dx, closeTo(-364, 2),
              reason: "from the page's edge once");
          expect(seen.last.dx, closeTo(0, 0.5),
              reason: "and in place at the end");
        }
      });
    }

    testWidgets(
        "an arrival waiting on the timeline does not hide a loop "
        "launched on another layer", (tester) async {
      var c = arrivals();
      addTearDown(c.dispose);
      // Pop placed a second in, on layer 1: at the start it waits, held small.
      var pop = c.newClip("a", preset: presetNamed("Pop"), layer: 1);
      c.placeClip("a", pop, seconds: 1);
      var spin = c.newClip("a", preset: presetNamed("Spin"), slot: 0);
      expect(motionPoseIn(c.document, c.document.elementById("a")!, 0).scale,
          closeTo(0, 0.01),
          reason: "on the timeline it waits");
      c.pressMotionSlot("a", 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(sample(c).scale, closeTo(1, 0.01),
          reason: "off it, the spin is seen");
      c.pause();
      expect(spin, isNotEmpty);
    });
  });
}
