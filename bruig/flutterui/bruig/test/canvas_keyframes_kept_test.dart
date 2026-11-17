import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter_test/flutter_test.dart';

// A canvas animated with keyframes keeps them when it opens: they are not
// made into clips.

ShapeElement shape(String id, List<Keyframe> keys) => ShapeElement(ElementBase(
    id: id, x: 100, y: 100, width: 50, height: 50, track: ElementTrack(keys)));

CanvasDocument doc(List<CanvasElement> elements) =>
    CanvasDocument(frames: 96, frameRate: 24, elements: elements);

void main() {
  // The Keyframes card keys an element's own track; opening a canvas leaves
  // them there, so the card still has them (Ken, 2026-11-11).
  test("opened, a canvas keeps its keyframes where the card keyed them", () {
    var saved = doc([
      shape("a", const [Keyframe(frame: 0), Keyframe(frame: 24, dx: 10)]),
    ]);
    var c = CanvasController(const CanvasDocument());
    addTearDown(c.dispose);
    c.load(saved);
    var a = c.document.elementById("a")!;
    expect(a.track?.keys, hasLength(2), reason: "its keyframes, as saved");
    expect(a.base.motion.placed, isEmpty, reason: "not made into a clip");
  });
}
