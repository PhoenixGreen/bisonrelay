import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart';
import 'package:bruig/plugin_system/canvas/model/stage_spot.dart';
import 'package:bruig/plugin_system/canvas/render/camera_3d.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:flutter_test/flutter_test.dart';

// A Camera on a 3D stage lives in the scene (Ken): the stage's camera when
// played, exported or looked through, from where it stands -- turned round
// what it looks at by a turn, brought closer by a size, aimed at whoever it
// is on -- and the stage's own while editing.

const view = StageCamera(yaw: 10, pitch: 15, distance: 8, lens: 35);

BackgroundElement stage() => BackgroundElement(
    const ElementBase(id: "st", x: 0, y: 0, width: 1280, height: 720),
    backdrop: BackdropKind.stage,
    stage: StageElement(const ElementBase(id: ""),
        camera: const StageCamera(yaw: -30, distance: 12)));

CanvasController make() {
  var c = CanvasController(CanvasDocument(frames: 96, frameRate: 24, elements: [
    stage(),
    ShapeElement(const ElementBase(
        id: "hero",
        x: 900,
        y: 200,
        width: 100,
        height: 300,
        spot: StageSpot("st", x: 3, z: -2))),
    const CameraElement(ElementBase(id: "cam", width: 1280, height: 720),
        view: view),
  ]));
  addTearDown(c.dispose);
  return c;
}

StageElement staged(CanvasController c) =>
    (c.document.elementById("st") as BackgroundElement).staged;

void main() {
  test("added on a stage, it stands where the stage's camera is", () {
    var doc = CanvasDocument(elements: [stage()]);
    var cam = newElement(ElementKind.camera, doc) as CameraElement;
    expect(cam.view?.yaw, -30);
    expect(cam.view?.distance, 12);
    var back = elementFromJson(cam.toJson()) as CameraElement;
    expect(back.view?.distance, 12, reason: "kept");
  });

  test("on a stage it is not a frame on the page", () {
    var c = make();
    expect(isStageScene(c.document), isTrue);
    expect(sceneFraming(c.document, 0), isNull);
  });

  test("drawn through it, the stage sees through it; not otherwise", () {
    var c = make();
    var s = staged(c);
    expect(s.cameraAt(0).yaw, -30, reason: "editing: its own");
    var seen = directedBy(c.document, null, () => s.cameraAt(0));
    expect((seen.yaw, seen.distance, seen.pitch), (10, 8, 15));
    expect(s.cameraAt(0).yaw, -30, reason: "and its own again after");
  });

  test("a turn orbits; a size brings it closer", () {
    var c = make();
    var clip = MotionClip.ofKind("m", MotionKind.camera, name: "m")
        .copyWith(length: 1, keys: {
      MotionProp.turn: const [
        MotionKey(0, MotionNumber(0)),
        MotionKey(1, MotionNumber(90)),
      ],
      MotionProp.scale: const [
        MotionKey(0, MotionNumber(1)),
        MotionKey(1, MotionNumber(2)),
      ],
    });
    c.setMotion("cam", ElementMotion(clips: [clip]));
    c.placeClip("cam", "m", seconds: 0);
    var cam = c.document.elementById("cam") as CameraElement;
    var at = camera3dAt(cam, staged(c), 24, c.document);
    expect(at.yaw, closeTo(100, 1e-6));
    expect(at.distance, closeTo(4, 1e-6));
  });

  test("pushed in on someone, it ends aimed at where they stand", () {
    var c = make();
    var id =
        c.newClip("cam", preset: presetNamed("Push in on…"), target: "hero");
    c.placeClip("cam", id, seconds: 0);
    var cam = c.document.elementById("cam") as CameraElement;
    var start = camera3dAt(cam, staged(c), 0, c.document);
    expect((start.tx, start.tz), (0, 0), reason: "where it stood");
    var end = camera3dAt(cam, staged(c), 48, c.document);
    expect(end.tx, closeTo(3, 1e-6));
    expect(end.tz, closeTo(-2, 1e-6));
    expect(end.distance, closeTo(8 / 1.7, 1e-6), reason: "and closer");
    var half = camera3dAt(cam, staged(c), 18, c.document);
    expect(half.tx, inExclusiveRange(0.1, 2.9), reason: "on its way");
  });

  test("shaken, it pans and comes back", () {
    var c = make();
    var id = c.newClip("cam", preset: presetNamed("Camera shake"));
    c.placeClip("cam", id, seconds: 0);
    var cam = c.document.elementById("cam") as CameraElement;
    var mid = camera3dAt(cam, staged(c), 2, c.document);
    expect(mid.tx != 0 || mid.tz != 0, isTrue);
    var after = camera3dAt(cam, staged(c), 30, c.document);
    expect((after.tx, after.tz), (0, 0));
  });

  test("its settings in 3D are its own view", () {
    var c = make();
    var cam = c.document.elementById("cam") as CameraElement;
    c.replaceElement(cam.withView(view.copyWith(lens: 85)));
    expect((c.document.elementById("cam") as CameraElement).view?.lens, 85);
    var seen = directedBy(c.document, null, () => staged(c).cameraAt(0));
    expect(seen.lens, 85);
  });

  test("exported, the stage is drawn through it", () async {
    var c = make();
    var looked = c.document.withElement(
        (c.document.elementById("cam") as CameraElement)
            .withView(view.copyWith(pitch: 70, yaw: 90, distance: 4)));
    var without = c.document.removeElement("cam");
    Future<List<int>> pixels(CanvasDocument d) async {
      var image = await renderFrame(d, scale: 0.25);
      var bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return bytes!.buffer.asUint8List();
    }

    var a = await pixels(looked), b = await pixels(without);
    var differ = 0;
    for (var i = 0; i < a.length; i += 4) {
      if ((a[i] - b[i]).abs() + (a[i + 1] - b[i + 1]).abs() > 30) differ++;
    }
    expect(differ, greaterThan(a.length ~/ 4 ~/ 20),
        reason: "a stage seen from above, not from its own camera");
  });
}
