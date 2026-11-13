import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_painter.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// The Camera element: the part of the page shown, taking over from the
// canvas -- framed by its box, moved by its clips, never in the picture,
// and caught on the canvas by its frame's edge alone.

ShapeElement red(String id, Rect r) => ShapeElement(
    ElementBase(id: id, x: r.left, y: r.top, width: r.width, height: r.height),
    fill: const Color(0xFFFF0000),
    strokeWidth: 0);

CanvasDocument square(List<CanvasElement> elements) => CanvasDocument(
    frames: 96,
    frameRate: 24,
    size: const CanvasSize(width: 300, ratio: CanvasRatio.square),
    elements: elements);

void main() {
  test("kept, and made the size of the page", () {
    var doc = square(const []);
    var cam = newElement(ElementKind.camera, doc) as CameraElement;
    expect(cam.bounds, doc.size.rect);
    var back = elementFromJson(cam.toJson());
    expect(back, isA<CameraElement>());
  });

  test("its frame is what is shown: half as wide, twice as close", () {
    var cam = CameraElement(
        const ElementBase(id: "c", x: 150, y: 150, width: 150, height: 150));
    var doc = square([cam]);
    var (zoom, at) = sceneFraming(doc, 0)!;
    expect(zoom, 2);
    expect(at, const Offset(225, 225));
    expect(cameraFrame(cam, 0, doc), const Rect.fromLTWH(150, 150, 150, 150));
  });

  test("it takes over from the scene's slow move", () {
    var doc = square(const []).withScene(
        0, square(const []).scene.copyWith(camera: const SceneCamera()));
    expect(sceneFraming(doc, 0)?.$1, 1, reason: "the slow move, at its start");
    var withCam = doc.addElement(
        const CameraElement(ElementBase(id: "c", width: 100, height: 100)));
    expect(sceneFraming(withCam, 0)!.$1, 3);
  });

  test("pushed in on something, it ends on it, closer", () {
    var c = CanvasController(square([
      red("t", const Rect.fromLTWH(200, 40, 40, 40)),
      const CameraElement(ElementBase(id: "c", width: 300, height: 300)),
    ]));
    addTearDown(c.dispose);
    var id = c.newClip("c", preset: presetNamed("Push in on…"), target: "t");
    c.placeClip("c", id, seconds: 0);
    var (zoom, at) = sceneFraming(c.document, 48)!;
    expect(zoom, closeTo(1.7, 1e-6));
    // On the target, held in far enough to keep the page filled.
    var half = 150 / 1.7;
    expect(at.dx, closeTo(300 - half, 1e-6));
    expect(at.dy, closeTo(half, 1e-6));
  });

  test("never drawn, and what it shows fills the picture", () async {
    // Red in the top-left quarter; the camera on that quarter.
    var doc = square([
      red("r", const Rect.fromLTWH(0, 0, 150, 150)),
      const CameraElement(ElementBase(id: "c", width: 150, height: 150)),
    ]);
    var image = await renderFrame(doc);
    var raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    int redAt(int x, int y) => raw.getUint8((y * image.width + x) * 4);
    expect(redAt(image.width - 5, image.height - 5), greaterThan(200),
        reason: "the far corner is the quarter, filled out");
    var without = await renderFrame(square([
      red("r", const Rect.fromLTWH(0, 0, 150, 150)),
    ]));
    var raw2 = (await without.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    expect(
        raw2.getUint8(
            ((without.height - 5) * without.width + without.width - 5) * 4),
        lessThan(100));
  });

  testWidgets("on the canvas, caught by its frame, not inside it",
      (tester) async {
    var key = GlobalKey<CanvasStageState>();
    var c = CanvasController(CanvasDocument(elements: [
      red("s", const Rect.fromLTWH(500, 300, 200, 200)),
      const CameraElement(
          ElementBase(id: "c", x: 0, y: 0, width: 1280, height: 720)),
    ]));
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 900,
                  height: 700,
                  child: CanvasStage(key: key, controller: c)))),
    ));
    await tester.pumpAndSettle();
    var stage = key.currentState!;
    await tester.tapAt(stage.toStagePoint(const Offset(600, 400)));
    await tester.pumpAndSettle();
    expect(c.selection, {"s"}, reason: "through the frame, to what it shows");
    c.clearSelection();
    await tester.tapAt(stage.toStagePoint(const Offset(640, 1)));
    await tester.pumpAndSettle();
    expect(c.selection, {"c"}, reason: "on its edge");
  });

  // Ken, 2026-11-14: the camera was hard to select, move and zoom.
  group("taken hold of", () {
    CanvasDocument wide(CameraElement cam) =>
        CanvasDocument(frames: 96, frameRate: 24, elements: [cam]);

    test("moved: where it looks, by the drag, kept on the page", () {
      var c = CanvasController(wide(const CameraElement(
          ElementBase(id: "c", x: 320, y: 180, width: 640, height: 360))));
      addTearDown(c.dispose);
      var cam = c.document.elementById("c") as CameraElement;
      var moved = c.cameraShifted(cam, const Offset(100, 50)) as CameraElement;
      expect(cameraFrame(moved, 0, c.document.withElement(moved)).center,
          const Offset(740, 410));
      // Far past the edge, it stops where the picture meets the page's.
      var far = c.cameraShifted(cam, const Offset(5000, 0)) as CameraElement;
      expect(cameraFrame(far, 0, c.document.withElement(far)).right, 1280);
      expect(far.bounds.right, 1280, reason: "no pose the frame cannot follow");
    });

    test("moved where it is keyed: a key on this frame, without a jump", () {
      var c = CanvasController(wide(CameraElement(ElementBase(
          id: "c",
          width: 1280,
          height: 720,
          track: ElementTrack(const [
            Keyframe(frame: 0, scale: 2, dx: -100),
            Keyframe(frame: 48, scale: 2, dx: 100),
          ])))));
      addTearDown(c.dispose);
      c.frame = 0;
      var cam = c.document.elementById("c") as CameraElement;
      var before = cameraFrame(cam, 0, c.document).center;
      var moved = c.cameraShifted(cam, const Offset(30, 20)) as CameraElement;
      expect(cameraFrame(moved, 0, c.document.withElement(moved)).center,
          before + const Offset(30, 20));
      expect(moved.track!.keyAt(0)!.dx, -70);
      expect(moved.x, 0, reason: "its box stays where it was");
    });

    test("zoomed: about the middle of what it shows", () {
      var c = CanvasController(wide(const CameraElement(
          ElementBase(id: "c", x: 320, y: 180, width: 640, height: 360))));
      addTearDown(c.dispose);
      var cam = c.document.elementById("c") as CameraElement;
      var closer = c.cameraZoomed(cam, 2) as CameraElement;
      var (zoom, at) = cameraFraming(closer, 0, c.document.withElement(closer));
      expect(zoom, closeTo(4, 1e-9));
      expect(at, const Offset(640, 360));
      // Never further out than the whole page.
      var out = c.cameraZoomed(cam, 0.1) as CameraElement;
      expect(cameraFraming(out, 0, c.document.withElement(out)).$1, 1);
    });
  });

  group("on the canvas", () {
    Future<(CanvasController, CanvasStageState)> stageWith(
        WidgetTester tester, CameraElement cam) async {
      var key = GlobalKey<CanvasStageState>();
      var c =
          CanvasController(CanvasDocument(frames: 96, frameRate: 24, elements: [
        red("s", const Rect.fromLTWH(500, 300, 200, 200)),
        cam,
      ]));
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    width: 900,
                    height: 700,
                    child: CanvasStage(key: key, controller: c)))),
      ));
      await tester.pumpAndSettle();
      return (c, key.currentState!);
    }

    double scaleOf(CanvasStageState stage) =>
        (stage.toStagePoint(const Offset(100, 0)) -
                stage.toStagePoint(Offset.zero))
            .dx /
        100;

    testWidgets("caught by its name tab", (tester) async {
      var (c, stage) = await stageWith(
          tester,
          const CameraElement(
              ElementBase(id: "c", name: "Camera", width: 1280, height: 720)));
      var cam = c.document.elementById("c") as CameraElement;
      var tab = cameraTab(cam, cameraFrame(cam, 0, c.document), scaleOf(stage));
      await tester.tapAt(stage.toStagePoint(tab.center));
      await tester.pumpAndSettle();
      expect(c.selection, {"c"});
    });

    testWidgets("a keyed camera dragged by its tab moves without a jump",
        (tester) async {
      var (c, stage) = await stageWith(
          tester,
          CameraElement(ElementBase(
              id: "c",
              name: "Camera",
              width: 1280,
              height: 720,
              track: ElementTrack(const [
                Keyframe(frame: 0, scale: 2),
                Keyframe(frame: 48, scale: 2, dx: 100),
              ]))));
      var cam = c.document.elementById("c") as CameraElement;
      var frame = cameraFrame(cam, 0, c.document);
      var tab = cameraTab(cam, frame, scaleOf(stage));
      var from = stage.toStagePoint(tab.center);
      await tester.dragFrom(from, Offset(60 * scaleOf(stage), 0),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      var now = c.document.elementById("c") as CameraElement;
      expect(cameraFrame(now, 0, c.document).center.dx,
          closeTo(frame.center.dx + 60, 2));
    });

    testWidgets("its corner handle zooms it about its middle", (tester) async {
      var (c, stage) = await stageWith(
          tester,
          const CameraElement(
              ElementBase(id: "c", name: "Camera", width: 1280, height: 720)));
      c.selectOnly("c");
      await tester.pumpAndSettle();
      // The bottom-right corner, pulled half way to the middle.
      await tester.dragFrom(
          stage.toStagePoint(const Offset(1280, 720)),
          stage.toStagePoint(const Offset(960, 540)) -
              stage.toStagePoint(const Offset(1280, 720)),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      var now = c.document.elementById("c") as CameraElement;
      var (zoom, at) = cameraFraming(now, 0, c.document);
      expect(zoom, closeTo(2, 0.05));
      expect(at.dx, closeTo(640, 1));
    });
  });
}
