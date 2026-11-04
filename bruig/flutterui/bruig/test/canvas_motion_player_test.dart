import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_player.dart';
import 'package:flutter_test/flutter_test.dart';

// The slots played live: launched, carried on from, ended as each clip
// says, stopped by toggle and gate, followed by Then and by another clip's
// end -- and what was played while recording, written onto the timeline.

/// across is a clip that moves [by] across in [length] seconds.
MotionClip across(String id, double by,
        {double length = 1,
        int layer = 0,
        ClipHold after = ClipHold.last,
        bool loop = false,
        ClipLaunch launch = ClipLaunch.trigger,
        ClipThen then = ClipThen.nothing,
        List<ClipTrigger> triggers = const []}) =>
    MotionClip.ofKind(id, MotionKind.action, layer: layer, name: id).copyWith(
        length: length,
        after: after,
        loop: loop,
        launch: launch,
        then: then,
        triggers: triggers,
        keys: {
          MotionProp.x: [
            const MotionKey(0, MotionNumber(0)),
            MotionKey(length, MotionNumber(by)),
          ],
        });

CanvasDocument doc(List<MotionClip> a, {List<MotionClip> b = const []}) =>
    CanvasDocument(frames: 240, frameRate: 24, elements: [
      ShapeElement(ElementBase(
          id: "a",
          width: 10,
          height: 10,
          motion: ElementMotion(clips: a, slots: [for (var c in a) c.id]))),
      ShapeElement(ElementBase(
          id: "b",
          x: 50,
          width: 10,
          height: 10,
          motion: ElementMotion(clips: b, slots: [for (var c in b) c.id]))),
    ]);

double dx(MotionPlayer p, CanvasDocument d, String id, double at) {
  p.step(d, 0, at);
  return poseWithMotion(d.elementById(id)!, 0, d, live: p).dx;
}

void main() {
  test("launched, it leaves its timeline and plays on the clock", () {
    var d = doc([across("go", 100)]);
    var p = MotionPlayer();
    p.launch(d, 0, "a", "go", 0);
    expect(dx(p, d, "a", 0.5), closeTo(50, 1e-6));
    expect(p.isOff("a"), isTrue);
    expect(p.slotState("a", d.elementById("a")!.base.motion.clip("go")),
        MotionSlotState.playing);
  });

  test("played out, it holds its last frame, or goes back as it was", () {
    var d =
        doc([across("hold", 100), across("back", 100, after: ClipHold.rest)]);
    var p = MotionPlayer();
    p.launch(d, 0, "a", "hold", 0);
    expect(dx(p, d, "a", 3), 100);
    p.launch(d, 0, "a", "back", 3);
    expect(dx(p, d, "a", 3.5), closeTo(150, 1e-6),
        reason: "from where the last left it");
    expect(dx(p, d, "a", 5), 100, reason: "back to where it began");
  });

  test("toggled, a clip playing is stopped; a gate stops when let go", () {
    var d = doc([
      across("t", 100, length: 4, launch: ClipLaunch.toggle),
      across("g", 100, length: 4, launch: ClipLaunch.gate),
    ]);
    var p = MotionPlayer();
    p.press(d, 0, "a", "t", 0);
    p.step(d, 0, 0);
    p.press(d, 0, "a", "t", 1);
    expect(dx(p, d, "a", 1), 25, reason: "held where it was stopped");
    expect(p.slotState("a", d.elementById("a")!.base.motion.clip("t")),
        MotionSlotState.stopped);
    p.press(d, 0, "a", "g", 2);
    p.step(d, 0, 2);
    p.release(d, "a", "g", 4);
    expect(dx(p, d, "a", 4), closeTo(25 + 50, 1e-6));
    expect(dx(p, d, "a", 9), closeTo(75, 1e-6), reason: "stopped, not played");
  });

  test("a launch waits for its moment", () {
    var d = doc([across("go", 100)]);
    var p = MotionPlayer();
    p.launch(d, 0, "a", "go", 2);
    expect(dx(p, d, "a", 1), 0);
    expect(p.slotState("a", d.elementById("a")!.base.motion.clip("go")),
        MotionSlotState.queued);
    expect(dx(p, d, "a", 2.5), closeTo(50, 1e-6));
  });

  test("Then plays the next slot, where it left off", () {
    var d = doc([across("one", 100, then: ClipThen.next), across("two", 10)]);
    var p = MotionPlayer();
    p.launch(d, 0, "a", "one", 0);
    p.step(d, 0, 0);
    p.step(d, 0, 1);
    expect(dx(p, d, "a", 1.5), closeTo(105, 1e-6));
  });

  test("a clip that starts when another ends does", () {
    var d = doc([
      across("one", 100)
    ], b: [
      across("answer", 20, triggers: const [
        ClipTrigger(ClipTriggerKind.clipEnds, target: "one")
      ])
    ]);
    var p = MotionPlayer();
    p.launch(d, 0, "a", "one", 0);
    p.step(d, 0, 0);
    p.step(d, 0, 1);
    expect(dx(p, d, "b", 1.5), closeTo(10, 1e-6));
  });

  test("layers add: a loop on one, a move on another", () {
    var d = doc([across("move", 100), across("bob", 10, layer: 1, loop: true)]);
    var p = MotionPlayer();
    p.launch(d, 0, "a", "move", 0);
    p.launch(d, 0, "a", "bob", 0);
    expect(dx(p, d, "a", 0.5), closeTo(55, 1e-6));
  });

  test("recorded, what was played is on the timeline as it was played", () {
    var d = doc([across("whole", 100), across("cut", 100, length: 4)]);
    var p = MotionPlayer();
    p.launch(d, 0, "a", "whole", 1);
    p.step(d, 0, 1, recording: true);
    p.step(d, 0, 2, recording: true);
    p.launch(d, 0, "a", "cut", 3);
    p.step(d, 0, 3, recording: true);
    p.stop("a", at: 4);
    p.step(d, 0, 4, recording: true);
    var n = 0;
    var next = writeMotionTakes(d, p.takeLog(d, 4), () => "p${n++}");
    var placed = next.elementById("a")!.base.motion.placed;
    expect([
      for (var x in placed) (x.clip, x.start, x.length, x.to)
    ], [
      ("whole", 1, 1, null),
      ("cut", 3, 1, 1),
    ]);
  });

  test("halted, everything stops where it is; cleared, back to the timeline",
      () {
    var d = doc([across("go", 100)]);
    var p = MotionPlayer();
    p.launch(d, 0, "a", "go", 0);
    p.step(d, 0, 0);
    p.halt(d, 0, 0.5);
    expect(dx(p, d, "a", 2), closeTo(50, 1e-6));
    expect(p.playing, isFalse);
    p.clear();
    expect(poseWithMotion(d.elementById("a")!, 0, d, live: p).dx, 0);
  });
}
