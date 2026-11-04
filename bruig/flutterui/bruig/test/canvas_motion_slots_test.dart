import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
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
}
