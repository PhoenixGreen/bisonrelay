import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_hit_test.dart';

// canvas_stage_hits_test.dart is what the stage finds under a point, asked
// of StageHitTest with no stage, controller or widget: the document, a frame
// and a scale are all it is made from.

ShapeElement _shape(String id, double x, double y, double w, double h,
        {ShapeKind kind = ShapeKind.rectangle,
        double rotation = 0,
        bool visible = true,
        bool locked = false}) =>
    ShapeElement(
        ElementBase(
            id: id,
            x: x,
            y: y,
            width: w,
            height: h,
            rotation: rotation,
            visible: visible,
            locked: locked),
        shape: kind);

StageHitTest _hits(List<CanvasElement> elements,
        {int frame = 0, double scale = 1}) =>
    StageHitTest(
        document: CanvasDocument(frames: 40, elements: elements),
        frame: frame,
        scale: scale);

void main() {
  test("a box is hit inside and not outside", () {
    var box = _shape("a", 100, 100, 200, 100);
    var hit = _hits([box]);
    expect(hit.contains(box, const Offset(150, 150)), isTrue);
    expect(hit.contains(box, const Offset(310, 150)), isFalse);
    expect(hit.contains(box, const Offset(150, 90)), isFalse);
  });

  test("a turned box is hit where it is drawn, not where its box lies", () {
    // 200 by 20 turned upright about its middle (200, 110).
    var bar = _shape("a", 100, 100, 200, 20, rotation: 90);
    var hit = _hits([bar]);
    expect(hit.contains(bar, const Offset(200, 30)), isTrue,
        reason: "above its box, on the turned bar");
    expect(hit.contains(bar, const Offset(120, 110)), isFalse,
        reason: "in its box, off the turned bar");
  });

  test("a circle is not hit in its box's corner", () {
    var ring = _shape("a", 100, 100, 100, 100, kind: ShapeKind.circle);
    var hit = _hits([ring]);
    expect(hit.contains(ring, const Offset(150, 150)), isTrue);
    expect(hit.contains(ring, const Offset(104, 104)), isFalse);
  });

  test("a line is hit near its stroke, and further off at a smaller scale", () {
    var line = const LineElement(
        ElementBase(id: "l", x: 100, y: 200, width: 400, height: 6),
        strokeWidth: 4);
    var curve = curveOfElement(line)!;
    var middle = (curve.first + curve.last) / 2;
    var near = middle + const Offset(0, 5);
    var off = middle + const Offset(0, 20);

    var close = _hits([line]);
    expect(close.contains(line, near), isTrue);
    expect(close.contains(line, off), isFalse);

    // The reach is so many pixels on screen: zoomed out, more of the page.
    var far = _hits([line], scale: 0.25);
    expect(far.contains(line, off), isTrue);
  });

  group("topmost", () {
    var back = _shape("back", 100, 100, 200, 200);
    var front = _shape("front", 150, 150, 200, 200);
    const both = Offset(200, 200);

    test("of two overlapping, the front one", () {
      expect(_hits([back, front]).topmost(both)?.id, "front");
      expect(_hits([front, back]).topmost(both)?.id, "back",
          reason: "front is the order drawn, not the name");
    });

    test("passes by a hidden or locked one", () {
      var hidden = _shape("front", 150, 150, 200, 200, visible: false);
      expect(_hits([back, hidden]).topmost(both)?.id, "back");
      var locked = _shape("front", 150, 150, 200, 200, locked: true);
      expect(_hits([back, locked]).topmost(both)?.id, "back");
      expect(_hits([back, front]).topmost(const Offset(50, 50)), isNull);
    });

    test("among and where narrow it", () {
      var hit = _hits([back, front]);
      expect(hit.topmost(both, among: [back])?.id, "back");
      expect(hit.topmost(both, where: (e) => e.id != "front")?.id, "back");
      expect(hit.topmost(both, among: [front], where: (e) => false), isNull);
    });
  });

  group("posed", () {
    test("partway through a move, where it is drawn, not where it rests", () {
      var moving = _shape("m", 100, 100, 80, 80).withBase(
          track: ElementTrack(const [
        Keyframe(frame: 0),
        Keyframe(frame: 20, dx: 300),
      ]));
      var hit = _hits([moving], frame: 10);
      var doc = hit.document;
      var at = hit.posed(moving);

      // The painter draws the resting box shifted by the pose.
      var pose = poseWithMotion(moving, 10, doc);
      expect(pose.dx, greaterThan(50), reason: "well on its way");
      expect(pose.dx, lessThan(250), reason: "and not there yet");
      expect(at, moving.bounds.shift(Offset(pose.dx, pose.dy)));

      // And it is hit there, not at its empty resting place.
      expect(hit.contains(moving, at.center), isTrue);
      expect(hit.contains(moving, moving.bounds.topLeft), isFalse);
      expect(hit.topmost(at.center)?.id, "m");
    });

    test("its moving loop counts", () {
      var floating = ShapeElement(
          const ElementBase(id: "f", x: 100, y: 100, width: 40, height: 40),
          animation: const ElementAnimation(
              loop: ElementLoop(preset: LoopPreset.float, cycle: 40)));
      // A quarter round, up by 6% of its 40.
      expect(_hits([floating], frame: 10).posed(floating).top,
          closeTo(100 - 2.4, 0.5));
      expect(_hits([floating]).posed(floating).top, closeTo(100, 1e-9));
    });
  });
}
