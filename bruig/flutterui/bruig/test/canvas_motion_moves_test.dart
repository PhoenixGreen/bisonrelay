import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/instances.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_motion_moves_test.dart is the moves of the motion chain: wiggle,
// oscillate, spring, follow a path, look at something and squash -- each
// asking the devices to its left where the element is, and changing it.

/// clip moves across by [keys] (seconds, pixels), placed at the start.
MotionClip clip(List<(double, double)> keys) => MotionClip(
      id: "go",
      kind: MotionKind.action,
      length: 4,
      keys: {
        MotionProp.x: [for (var (t, v) in keys) MotionKey(t, MotionNumber(v))],
      },
    );

CanvasDocument doc(List<MotionDevice> devices,
        {List<(double, double)>? keys,
        InstanceSet? instances,
        List<CanvasElement> more = const []}) =>
    CanvasDocument(frames: 240, frameRate: 24, elements: [
      ShapeElement(ElementBase(
          id: "a",
          width: 20,
          height: 20,
          motion: ElementMotion(
              clips: keys == null ? const [] : [clip(keys)],
              placed: keys == null
                  ? const []
                  : const [ClipPlacement(id: "p", clip: "go", length: 4)],
              devices: devices,
              instances: instances))),
      ...more,
    ]);

Keyframe pose(CanvasDocument d, int frame, {int? instance}) =>
    poseWithMotion(d.elementById("a")!, frame, d, instance: instance);

void main() {
  test("a target is kept", () {
    var d = const MotionDevice(MotionDeviceKind.lookAt, target: "hero");
    expect(MotionDevice.fromJson(d.toJson())!.target, "hero");
    expect(d.switched(false).target, "hero");
    expect(d.withValue("smooth", 0.5).target, "hero");
  });

  test("wiggle wanders, the same each time; each instance its own", () {
    var d = doc(const [
      MotionDevice(MotionDeviceKind.instances, id: "m0"),
      MotionDevice(MotionDeviceKind.wiggle,
          id: "m1", values: {"amount": 20, "seed": 1}),
    ], instances: const InstanceSet().withCount(2, gap: 0));
    var seen = {for (var f = 0; f < 48; f += 6) pose(d, f, instance: 0).dx};
    expect(seen.length, greaterThan(4), reason: "it moves");
    expect(seen.every((x) => x.abs() <= 20), isTrue);
    expect(pose(d, 30, instance: 0).dx, pose(d, 30, instance: 0).dx);
    expect(pose(d, 30, instance: 0).dx, isNot(pose(d, 30, instance: 1).dx),
        reason: "each its own seed");
    var same = doc(const [
      MotionDevice(MotionDeviceKind.instances, id: "m0"),
      MotionDevice(MotionDeviceKind.wiggle,
          id: "m1", values: {"amount": 20, "seed": 0}),
    ], instances: const InstanceSet().withCount(2, gap: 0));
    expect(pose(same, 30, instance: 0).dx, pose(same, 30, instance: 1).dx);
  });

  test("oscillate swings up and down, side to side, in size or turn", () {
    MotionDevice osc(double moves) => MotionDevice(MotionDeviceKind.oscillate,
        values: {"rate": 1, "amount": 30, "moves": moves});
    // A quarter of a second at once a second: the top of the swing.
    expect(pose(doc([osc(0)]), 6).dy, closeTo(30, 1e-6));
    expect(pose(doc([osc(1)]), 6).dx, closeTo(30, 1e-6));
    expect(pose(doc([osc(2)]), 6).scale, closeTo(1.3, 1e-6));
    expect(pose(doc([osc(3)]), 6).rotate, closeTo(30, 1e-6));
  });

  test("a spring overshoots a sudden move, and settles", () {
    var keys = [(0.0, 0.0), (1.0, 0.0), (1.05, 100.0), (4.0, 100.0)];
    var d = doc(const [
      MotionDevice(MotionDeviceKind.spring,
          values: {"stiffness": 20, "damping": 0.15})
    ], keys: keys);
    var after = [for (var f = 25; f < 60; f++) pose(d, f).dx];
    expect(after.reduce(math.max), greaterThan(102), reason: "past it");
    expect(pose(d, 90).dx, closeTo(100, 1), reason: "settled");
    expect(pose(d, 12).dx, closeTo(0, 1e-6), reason: "still before");
  });

  test("follow path goes along a line, and turns with it", () {
    var line = LineElement(
        const ElementBase(id: "line", x: 20, y: 100, width: 200, height: 1));
    var d = doc(const [
      MotionDevice(MotionDeviceKind.followPath,
          target: "line", values: {"lap": 4})
    ], more: [
      line
    ]);
    var e = d.elementById("a")!;
    var mid = e.boundsWith(pose(d, 48)).center;
    expect(mid.dx, closeTo(120, 1), reason: "halfway along at two seconds");
    expect(mid.dy, closeTo(100.5, 1));
    // The line is its box corner to corner: 200 across, 1 down.
    expect(
        pose(d, 48).rotate, closeTo(math.atan(1 / 200) * 180 / math.pi, 1e-6),
        reason: "heading the way the line goes");
    var none = doc(const [MotionDevice(MotionDeviceKind.followPath)]);
    expect(pose(none, 48).dx, 0, reason: "no path, nowhere to go");
  });

  test("look at turns to face what it looks at", () {
    ShapeElement at(double x, double y) => ShapeElement(
        ElementBase(id: "hero", x: x, y: y, width: 20, height: 20));
    var right = doc(
        const [MotionDevice(MotionDeviceKind.lookAt, target: "hero")],
        more: [at(300, 0)]);
    expect(pose(right, 0).rotate, closeTo(0, 1e-6));
    var below = doc(
        const [MotionDevice(MotionDeviceKind.lookAt, target: "hero")],
        more: [at(0, 300)]);
    expect(pose(below, 0).rotate, closeTo(90, 1e-6));
  });

  test("two looking at each other do not ask for ever", () {
    var d = CanvasDocument(elements: [
      ShapeElement(const ElementBase(
          id: "a",
          width: 20,
          height: 20,
          motion: ElementMotion(
              devices: [MotionDevice(MotionDeviceKind.lookAt, target: "b")]))),
      ShapeElement(const ElementBase(
          id: "b",
          x: 200,
          width: 20,
          height: 20,
          motion: ElementMotion(
              devices: [MotionDevice(MotionDeviceKind.lookAt, target: "a")]))),
    ]);
    expect(poseWithMotion(d.elementById("a")!, 0, d).rotate, closeTo(0, 1e-6));
  });

  test("squash stretches it the way it goes, as fast as it goes", () {
    var d = doc(const [
      MotionDevice(MotionDeviceKind.squash, values: {"amount": 1, "bySpeed": 1})
    ], keys: [
      (0.0, 0.0),
      (4.0, 1200.0)
    ]);
    var p = pose(d, 24);
    expect(p.values[KeyframeChannel.squash], closeTo(1.5, 0.01),
        reason: "300 px a second of 600");
    expect(p.values[KeyframeChannel.squashAngle], closeTo(0, 1e-6));
    var still = doc(const [MotionDevice(MotionDeviceKind.squash)]);
    expect(pose(still, 24).values.containsKey(KeyframeChannel.squash), isFalse);
  });

  test("squashed, it is drawn wider than tall", () async {
    var d = CanvasDocument(frames: 240, frameRate: 24, elements: [
      ShapeElement(
          ElementBase(
              id: "a",
              x: 100,
              y: 100,
              width: 40,
              height: 40,
              motion: ElementMotion(clips: [
                clip([(0.0, 0.0), (4.0, 1200.0)])
              ], placed: const [
                ClipPlacement(id: "p", clip: "go", length: 4)
              ], devices: const [
                MotionDevice(MotionDeviceKind.squash,
                    values: {"amount": 1, "bySpeed": 1})
              ])),
          fill: const Color(0xFF000000)),
    ]);
    var rec = PictureRecorder();
    var canvas = Canvas(rec);
    // Drawn where it has got to by a second in, at 300 across.
    canvas.translate(-300, 0);
    paintElement(canvas, d.elementById("a")!, 24, document: d, frameRate: 24);
    var img = await rec.endRecording().toImage(300, 300);
    var px = (await img.toByteData())!;
    var l = 300, r = -1, t = 300, b = -1;
    for (var y = 0; y < 300; y++) {
      for (var x = 0; x < 300; x++) {
        if (px.getUint8((y * 300 + x) * 4 + 3) > 128) {
          l = math.min(l, x);
          r = math.max(r, x);
          t = math.min(t, y);
          b = math.max(b, y);
        }
      }
    }
    var w = r - l + 1, h = b - t + 1;
    expect(w / h, closeTo(1.5 * 1.5, 0.2), reason: "1.5 wide, 1/1.5 tall");
  });

  test("follow sound grows with a channel's loudness", () {
    // Ten seconds that are loud from 2 s to 4 s.
    var peaks = Float32List(100);
    for (var i = 20; i < 40; i++) {
      peaks[i] = 0.8;
    }
    var was = motionSoundPeaks;
    motionSoundPeaks = (id) => id == "voice.mp3" ? peaks : null;
    addTearDown(() => motionSoundPeaks = was);
    var d = doc(const [
      MotionDevice(MotionDeviceKind.followSound,
          target: "voice", values: {"amount": 1, "smooth": 0})
    ], more: [
      AudioElement(const ElementBase(id: "vo", visible: false),
          clip: const MediaClip(
              timed: true,
              volume: 1,
              channel: "voice",
              playlist: [MediaSource(assetId: "voice.mp3", length: 10)])),
    ]);
    expect(pose(d, 72).scale, closeTo(1 + 0.8 * 0.45, 1e-6),
        reason: "three seconds in: loud");
    expect(pose(d, 168).scale, 1, reason: "seven seconds in: quiet");
    var none = doc(const [MotionDevice(MotionDeviceKind.followSound)]);
    expect(pose(none, 72).scale, 1, reason: "no channel chosen");
  });
}
