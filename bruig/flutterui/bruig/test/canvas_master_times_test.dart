import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
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
}
