import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_player.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_master_times_test.dart is the master's clips timed on the run's
// clock under a run of scenes, as the master is drawn (Ken's systems
// review, 2026-11-08): a master clip held to the end ends at the run's end,
// not the first scene's.

ShapeElement _held(String id) => ShapeElement(ElementBase(
    id: id,
    width: 20,
    height: 20,
    motion: const ElementMotion(clips: [
      MotionClip(id: "c", length: 1)
    ], placed: [
      ClipPlacement(
          id: "p", clip: "c", start: 0, endPin: ClipPin(PinKind.sceneEnd)),
    ])));

void main() {
  test("a master clip held to the end ends at the run's end", () {
    var doc = CanvasDocument(
        frameRate: 24,
        masterOn: true,
        master: CanvasScene(id: "m", elements: [_held("logo")]),
        scenes: const [
          CanvasScene(id: "a", frames: 48),
          CanvasScene(id: "b", frames: 48),
        ]);
    expect(doc.sequenceFrames, 96);
    expect(masterTimesOf(doc)!.span("p")!.end, closeTo(4, 1e-9),
        reason: "the run's four seconds, not the scene's two");
    expect(motionTimesOf(doc).span("p")!.end, closeTo(2, 1e-9),
        reason: "the scene's own clock is as it was");
  });

  test("no run of scenes, or a book: the scene's clock", () {
    var one = CanvasDocument(
        frameRate: 24,
        masterOn: true,
        master: CanvasScene(id: "m", elements: [_held("logo")]),
        scenes: const [CanvasScene(id: "a", frames: 48)]);
    expect(masterTimesOf(one), isNull);
  });

  // Ken's systems review, 2026-11-08: a take of the master's was dropped.
  test("a take on the master is kept on the master, along the run", () {
    var hud = ShapeElement(const ElementBase(
        id: "hud",
        width: 20,
        height: 20,
        motion: ElementMotion(clips: [MotionClip(id: "c", length: 1)])));
    var doc = CanvasDocument(
        frameRate: 24,
        masterOn: true,
        master: CanvasScene(id: "m", elements: [hud]),
        scenes: const [
          CanvasScene(id: "a", frames: 48),
          CanvasScene(id: "b", frames: 48),
        ]).goToScene(1);
    var take = MotionPlayed("hud", "c", 0, 0.5, loop: false)
      ..end = 1.5
      ..to = 1;
    var copy = MotionPlayed("hud#i0", "c", 0, 0.5, loop: false)..end = 1.5;
    var id = 0;
    var next = writeMotionTakes(doc, [take, copy], () => "p${id++}");
    var placed = next.master!.elements.single.base.motion.placed.single;
    expect(placed.start, closeTo(2.5, 1e-9),
        reason: "half a second into the second scene: 2.5 s along the run");
    expect(placed.length, closeTo(1, 1e-9));
  });
}
