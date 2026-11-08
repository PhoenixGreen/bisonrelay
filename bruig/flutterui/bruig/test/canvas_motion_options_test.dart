import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_motion_options_test.dart is the motion devices' options the
// prototype has and the app lacked (Ken's audit, 2026-11-08): Time's Loop
// going on past its end, a Spring chasing another element, Look at facing
// the camera, and a Blur's Motion blur.

/// _across moves an element [by] to the right over a second.
MotionClip _across(double by) => MotionClip(
      id: "go",
      kind: MotionKind.action,
      length: 1,
      keys: {
        MotionProp.x: [
          const MotionKey(0, MotionNumber(0)),
          MotionKey(1, MotionNumber(by)),
        ],
      },
    );

CanvasDocument _doc(List<MotionDevice> devices,
        {double by = 100, List<CanvasElement> more = const []}) =>
    CanvasDocument(frames: 240, frameRate: 24, elements: [
      ShapeElement(
          ElementBase(
              id: "a",
              x: 100,
              y: 100,
              width: 40,
              height: 40,
              motion: ElementMotion(
                  clips: [_across(by)],
                  placed: const [ClipPlacement(id: "p", clip: "go", length: 1)],
                  devices: devices)),
          fill: const Color(0xFF000000)),
      ...more,
    ]);

Keyframe _pose(CanvasDocument d, int frame) =>
    poseWithMotion(d.elementById("a")!, frame, d);

void main() {
  test("Time's Continue goes on at the speed it ended going", () {
    var d = _doc(const [
      MotionDevice(MotionDeviceKind.time,
          id: "t", values: {"loop": 3, "every": 1}),
    ]);
    expect(_pose(d, 12).dx, closeTo(50, 1e-6), reason: "within its stretch");
    expect(_pose(d, 48).dx, closeTo(200, 1e-6),
        reason: "a second on past its end, a hundred further");
    var cycled = _doc(const [
      MotionDevice(MotionDeviceKind.time,
          id: "t", values: {"loop": 1, "every": 1}),
    ]);
    expect(_pose(cycled, 36).dx, closeTo(50, 1e-6),
        reason: "Cycle starts it again instead");
  });

  test("a Spring chases another element, settling where it is", () {
    var rock = ShapeElement(
        const ElementBase(id: "r", x: 400, y: 300, width: 40, height: 40));
    var d = _doc([
      const MotionDevice(MotionDeviceKind.spring,
          id: "s", values: {"follows": 1}, target: "r"),
    ], more: [
      rock
    ]);
    var p = _pose(d, 60);
    expect(p.dx, closeTo(300, 1e-6), reason: "centre on its centre");
    expect(p.dy, closeTo(200, 1e-6));
    expect(
        const MotionDevice(MotionDeviceKind.spring, values: {"follows": 1})
            .takesTarget,
        isTrue,
        reason: "and the chain offers it one");
    expect(const MotionDevice(MotionDeviceKind.spring).takesTarget, isFalse);
  });

  test("Look at the camera: with none, the middle of the page", () {
    var d = _doc(const [
      MotionDevice(MotionDeviceKind.lookAt, id: "l", target: lookAtCamera),
    ], by: 0);
    var page = d.size.rect.center;
    var me = const Offset(120, 120);
    var want = math.atan2(page.dy - me.dy, page.dx - me.dx) * 180 / math.pi;
    expect(_pose(d, 0).rotate, closeTo(want, 1e-6));
  });

  test("a Blur's Motion blur smears it along the way it moves", () async {
    Future<int> leftOfIt(double smear) async {
      // Two thousand four hundred a second: a hundred a frame.
      var d = _doc([
        MotionDevice(MotionDeviceKind.blur,
            id: "b", values: {"amount": 0, "motion": smear}),
      ], by: 2400);
      var e = d.elementById("a")!;
      var rec = PictureRecorder();
      var canvas = Canvas(rec);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 3000, 400),
          Paint()..color = const Color(0xFFFFFFFF));
      paintElement(canvas, e, 6, document: d, frameRate: 24);
      var img = await rec.endRecording().toImage(3000, 400);
      var px = (await img.toByteData())!;
      // Frame 6: a quarter of the way, 600 on: its left edge at 700.
      int red(int x, int y) => px.getUint8((y * 3000 + x) * 4);
      return red(690, 120);
    }

    expect(await leftOfIt(0), 255, reason: "sharp: white beside it");
    expect(await leftOfIt(1), lessThan(250), reason: "smeared into it");
  });
}
