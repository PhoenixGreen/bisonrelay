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
}
