import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/scene_sequence.dart';
import 'package:bruig/plugin_system/canvas/render/video_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/camera_section.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/transitions_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_blend_camera_test.dart is a video laid on as light, and a scene
// with a slow camera move over it.

Future<ui.Image> _solid(Color c) async {
  var r = ui.PictureRecorder();
  ui.Canvas(r).drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = c);
  return r.endRecording().toImage(4, 4);
}

Future<Color> _pixel(
    void Function(ui.Canvas) paint, int w, int h, int x, int y) async {
  var r = ui.PictureRecorder();
  paint(ui.Canvas(r));
  var image = await r.endRecording().toImage(w, h);
  var bytes = (await image.toByteData())!;
  var p = bytes.getUint32((y * w + x) * 4);
  image.dispose();
  return Color(((p & 0xFF) << 24) | (p >> 8));
}

void main() {
  group("a video's blend", () {
    test("screen brightens what is under it rather than covering it", () async {
      var frame = await _solid(const Color(0xFF800000)); // half red
      Future<Color> over(LayerBlend blend) => _pixel((canvas) {
            canvas.drawRect(const Rect.fromLTWH(0, 0, 40, 40),
                Paint()..color = const Color(0xFF008000)); // half green
            paintElement(
                canvas,
                VideoElement(const ElementBase(id: "v", width: 40, height: 40),
                    clip: const MediaClip(
                        timed: true,
                        playlist: [MediaSource(assetId: "v.mp4", length: 1)]),
                    blend: blend,
                    controls: const []),
                0,
                videoShow: (_) => VideoShow(frame: frame));
          }, 40, 40, 20, 20);
      var normal = await over(LayerBlend.normal);
      var screened = await over(LayerBlend.screen);
      expect(normal.g, lessThan(0.05), reason: "normally the video covers it");
      expect(screened.r, greaterThan(0.45), reason: "the video's red");
      expect(screened.g, greaterThan(0.45), reason: "and the green under it");
    });

    test("is saved", () {
      var v = const VideoElement(ElementBase(id: "v"), blend: LayerBlend.add);
      expect(
          VideoElement.fromJson(v.toJson(), const ElementBase(id: "v")).blend,
          LayerBlend.add);
    });
  });

  group("a scene's camera", () {
    test("never shows past the edge of the page", () {
      const page = Rect.fromLTWH(0, 0, 100, 50);
      var (zoom, focus) = const SceneCamera(
              fromZoom: 2, toZoom: 2, fromX: 0, toX: 0, fromY: 0, toY: 0)
          .at(0, page);
      expect(zoom, 2);
      expect(focus, const Offset(25, 12.5), reason: "held a quarter in");
      var (still, _) =
          const SceneCamera(fromZoom: 0.5, toZoom: 0.5).at(0, page);
      expect(still, 1, reason: "never smaller than the page");
    });

    /// _scene is a white page with black down its left eighth -- on the
    /// scene -- and a black dot in its bottom-right corner on the master.
    CanvasDocument scene(SceneCamera? camera) => CanvasDocument(
          size: const CanvasDocument().size,
          background: const CanvasBackground(
              spec: ProceduralSpec(background: Color(0xFFFFFFFF))),
          masterOn: true,
          master: CanvasScene(id: "m", elements: [
            ShapeElement(
                ElementBase(
                    id: "corner",
                    x: const CanvasDocument().size.size.width - 20,
                    y: const CanvasDocument().size.size.height - 20,
                    width: 20,
                    height: 20),
                fill: const Color(0xFF000000)),
          ]),
          scenes: [
            CanvasScene(id: "a", frames: 10, camera: camera, elements: [
              ShapeElement(
                  ElementBase(
                      id: "edge",
                      width: const CanvasDocument().size.size.width / 8,
                      height: const CanvasDocument().size.size.height),
                  fill: const Color(0xFF000000)),
            ]),
            const CanvasScene(id: "b", frames: 10),
          ],
        );

    test("moves the scene and not the master, in the run", () async {
      var size = const CanvasDocument().size.size;
      var w = size.width.round(), h = size.height.round();
      Future<Color> at(CanvasDocument d, int x, int y) =>
          _pixel((c) => paintSequenceFrame(c, d, 0), w, h, x, y);
      var still = scene(null),
          pushed = scene(const SceneCamera(fromZoom: 2, toZoom: 2));
      var x = (w * 0.05).round(), y = h ~/ 2;
      expect((await at(still, x, y)).r, lessThan(0.1),
          reason: "the black edge");
      expect((await at(pushed, x, y)).r, greaterThan(0.9),
          reason: "zoomed in two times, the edge is off the picture");
      expect((await at(pushed, w - 10, h - 10)).r, lessThan(0.1),
          reason: "the master's corner stays put");
    });

    test("is saved", () {
      var d = scene(const SceneCamera(toZoom: 1.3, toX: 0.4));
      var back = CanvasDocument.decode(d.encode())!.allScenes.first.camera!;
      expect(back.toZoom, 1.3);
      expect(back.toX, 0.4);
    });

    testWidgets("the panel sets a push in", (tester) async {
      var c = CanvasController(scene(null));
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(600, 2400);
      tester.view.devicePixelRatio = 1.0;
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
                    width: 280, child: CanvasTransitionsPanel(controller: c)))),
      ));
      await tester.pumpAndSettle();
      tester
          .widget<CanvasDropdown<CameraMove>>(
              find.byKey(const ValueKey("cameraMove")))
          .onChanged(CameraMove.pushIn);
      await tester.pumpAndSettle();
      var camera = c.document.allScenes.first.camera!;
      expect(camera.toZoom, greaterThan(camera.fromZoom));
    });
  });
}
