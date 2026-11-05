import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'canvas_audio_fake.dart';

// The editor's Play starts "The scene starts" clips as a published canvas
// does -- from the top, and as each scene begins playing them all -- and
// its Stop puts what they moved back on the timeline, so the next Play
// starts as whoever the canvas is sent to will see it.

/// spin is a clip that starts with the scene.
MotionClip spin() => presetNamed("Spin once")!
    .clip("spin")
    .copyWith(triggers: const [ClipTrigger(ClipTriggerKind.sceneStarts)]);

/// slotted is a clip with no trigger: it plays from its slot.
MotionClip slotted() => presetNamed("Spin once")!.clip("spin");

ShapeElement box(String id, MotionClip clip) => ShapeElement(ElementBase(
    id: id,
    width: 40,
    height: 40,
    motion: ElementMotion.none.withClip(clip).inSlot(0, clip.id)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  CanvasController editor(CanvasDocument doc) {
    var c = CanvasController(doc, audioEngine: FakeEngine({}));
    addTearDown(() {
      c.pause();
      c.dispose();
    });
    return c;
  }

  CanvasDocument one(List<ShapeElement> elements) =>
      const CanvasDocument(frames: 48).copyWith(elements: elements);

  test("Play from the top starts the clips that start with the scene", () {
    var c = editor(one([box("a", spin())]));
    expect(c.motionPlayer.isOff("a"), isFalse);
    c.play();
    expect(c.motionPlayer.isOff("a"), isTrue, reason: "the scene started");
  });

  test("Play from part-way through does not: the scene has not started", () {
    var c = editor(one([box("a", spin())]));
    c.frame = 12;
    c.play();
    expect(c.motionPlayer.isOff("a"), isFalse);
  });

  test("a clip with no trigger waits for its slot", () {
    var c = editor(one([box("a", slotted())]));
    c.play();
    expect(c.motionPlayer.isOff("a"), isFalse);
  });

  test("Stop puts what the scene started back on the timeline", () {
    var c = editor(one([box("a", spin())]));
    c.play();
    c.pause();
    expect(c.motionPlayer.isOff("a"), isTrue,
        reason: "paused, it stays where it was stopped");
    c.play();
    c.stopPlaying();
    expect(c.motionPlayer.isOff("a"), isFalse, reason: "stopped, it is back");

    c.play();
    expect(c.motionPlayer.isOff("a"), isTrue,
        reason: "and the next Play from the top starts it again");
    c.stop();
    expect(c.motionPlayer.isOff("a"), isFalse);
  });

  test("but what was launched from a slot stays off until Back", () {
    var c = editor(one([box("a", spin()), box("b", slotted())]));
    c.play();
    c.pressMotionSlot("b", 0);
    expect(c.motionPlayer.isOff("b"), isTrue);
    c.stopPlaying();
    expect(c.motionPlayer.isOff("a"), isFalse);
    expect(c.motionPlayer.isOff("b"), isTrue, reason: "as it always has");
    c.backToTimeline();
    expect(c.motionPlayer.isOff("b"), isFalse);
  });

  test("playing every scene, each scene's clips start as it begins", () {
    var c = editor(const CanvasDocument().withScenes([
      CanvasScene(id: "s1", frames: 3, elements: [box("a", spin())]),
      CanvasScene(id: "s2", frames: 3, elements: [box("b", spin())]),
    ]));
    c.playAll = true;
    c.play();
    expect(c.motionPlayer.isOff("a"), isTrue);
    for (var i = 0; i < 3; i++) {
      c.tickForTest();
    }
    expect(c.document.at, 1);
    expect(c.motionPlayer.isOff("b"), isTrue, reason: "the second began");
    expect(c.motionPlayer.isOff("a"), isFalse,
        reason: "the first's elements are not on it");
  });

  test("a game still starts its scene's clips, by its own start", () {
    var c = editor(one([box("a", spin())]).copyWith(game: true));
    c.gaming = true;
    addTearDown(() => c.gaming = false);
    expect(c.motionPlayer.isOff("a"), isTrue);
  });
}
