import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion_convert.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter_test/flutter_test.dart';

// Old canvases, animated with keyframes, made into clips: the same move,
// frame for frame -- every scene and the master -- and what a clip cannot
// say kept as keyframes.

ShapeElement shape(String id, List<Keyframe> keys) => ShapeElement(ElementBase(
    id: id, x: 100, y: 100, width: 50, height: 50, track: ElementTrack(keys)));

/// same checks [before] and [after] draw [id] alike on every frame.
void same(CanvasDocument before, CanvasDocument after, String id) {
  var a = before.elementById(id)!, b = after.elementById(id)!;
  expect(b.track, isNull, reason: "its keyframes gone");
  for (var f = 0; f <= before.frames; f++) {
    var p = poseWithMotion(a, f, before), q = poseWithMotion(b, f, after);
    var why = "$id at frame $f";
    expect(q.dx, closeTo(p.dx, 1e-6), reason: why);
    expect(q.dy, closeTo(p.dy, 1e-6), reason: why);
    expect(q.scale, closeTo(p.scale, 1e-6), reason: why);
    expect(q.rotate, closeTo(p.rotate, 1e-6), reason: why);
    expect(q.opacity, closeTo(p.opacity, 1e-6), reason: why);
    for (var ch in const ["reveal", "close", "count", "bow"]) {
      // Nothing set is the element as it is, which a held end of a stretch
      // that comes to rest also is.
      var want = p.values[ch], got = q.values[ch];
      if (want == null) continue;
      expect(got ?? (ch == "reveal" ? 1.0 : 0.0), closeTo(want, 1e-6),
          reason: "$why: $ch");
    }
  }
}

CanvasDocument doc(List<CanvasElement> elements) =>
    CanvasDocument(frames: 96, frameRate: 24, elements: elements);

void main() {
  test("a move, eased between its keys, is the same as a clip", () {
    var before = doc([
      shape("a", const [
        Keyframe(frame: 12, dx: 0, easing: KeyframeEasing.easeOut),
        Keyframe(
            frame: 36,
            dx: 200,
            dy: -40,
            scale: 1.5,
            easing: KeyframeEasing.easeInOut),
        Keyframe(frame: 60, dx: 120, rotate: 45, opacity: 0.4),
      ]),
    ]);
    var c = convertTracks(before);
    expect((c.converted, c.kept), (1, 0));
    same(before, c.document, "a");
    var clip = c.document.elementById("a")!.base.motion.clips.single;
    expect(clip.name, "Keyframes");
  });

  test("a count through a middle value, and a move with it", () {
    var counter = CounterElement(
        ElementBase(
            id: "n",
            width: 100,
            height: 40,
            track: ElementTrack(const [
              Keyframe(frame: 0, values: {"count": 0}),
              Keyframe(frame: 24, dx: 30, values: {"count": 140}),
              Keyframe(frame: 48, values: {"count": 100}),
            ])),
        from: 0,
        to: 100);
    var before = doc([counter]);
    var c = convertTracks(before);
    expect(c.converted, 1);
    same(before, c.document, "n");
  });

  test("a single keyframe holds everywhere, as it did", () {
    var before = doc([
      shape("a", const [Keyframe(frame: 30, dx: 50, opacity: 0.5)]),
    ]);
    var c = convertTracks(before);
    same(before, c.document, "a");
  });

  test("what a clip cannot say keeps its keyframes", () {
    var before = doc([
      shape("a", const [
        Keyframe(frame: 0, values: {"cam.yaw": 0}),
        Keyframe(frame: 24, values: {"cam.yaw": 30}),
      ]),
      shape("b", const [Keyframe(frame: 0), Keyframe(frame: 24, dx: 10)]),
    ]);
    var c = convertTracks(before);
    expect((c.converted, c.kept), (1, 1));
    expect(c.document.elementById("a")!.track, isNotNull);
    expect(hasTracks(c.document), isFalse,
        reason: "nothing more a clip could say");
  });

  test("every scene, and the master", () {
    var one = doc([
      shape("a", const [Keyframe(frame: 0), Keyframe(frame: 24, dx: 10)]),
    ]);
    var two = CanvasScene(id: "s2", name: "Two", frames: 96, elements: [
      shape("b", const [Keyframe(frame: 0), Keyframe(frame: 24, dy: 10)]),
    ]);
    var master = CanvasScene(id: "m", name: "Master", frames: 96, elements: [
      shape("c", const [Keyframe(frame: 0), Keyframe(frame: 24, scale: 2)]),
    ]);
    var before =
        one.withScenes([one.scene, two], at: 0).copyWith(master: master);
    expect(hasTracks(before), isTrue);
    var c = convertTracks(before);
    expect(c.converted, 3);
    expect(hasTracks(c.document), isFalse);
    same(before.goToScene(1), c.document.goToScene(1), "b");
  });

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
