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
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/camera_section.dart';
import 'package:bruig/plugin_system/canvas/ui/animation_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart'
    show DeviceKnob;
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_cards.dart'
    show StudioDrop;
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

    // Ken, 2026-11-08: pushed in, the box round the element selected was
    // left where the element was set, not where the camera showed it.
    testWidgets("the box round the selected goes with the camera",
        (tester) async {
      var c = CanvasController(CanvasDocument(
        frames: 10,
        background: const CanvasBackground(
            spec: ProceduralSpec(background: Color(0xFFFFFFFF))),
        scenes: [
          CanvasScene(
              id: "a",
              frames: 10,
              camera: const SceneCamera(fromZoom: 2, toZoom: 2),
              elements: [
                ShapeElement(
                    const ElementBase(
                        id: "box", x: 560, y: 300, width: 100, height: 100),
                    fill: const Color(0xFF000000)),
              ]),
        ],
      ));
      addTearDown(c.dispose);
      c.selectOnly("box");
      c.cameraView = true;
      tester.view.physicalSize = const Size(1000, 700);
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
                    width: 1000,
                    height: 700,
                    child: CanvasStage(controller: c)))),
      ));
      await tester.pumpAndSettle();
      var paint = find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is StagePainter);
      var p = tester.widget<CustomPaint>(paint).painter as StagePainter;
      var (zoom, focus) = p.camera!;
      expect(zoom, closeTo(2, 1e-6));
      // Where the camera shows the box's left edge.
      var mid = c.document.size.rect.center;
      Offset seen(Offset onPage) =>
          (mid + (onPage - focus) * zoom) * p.scale + p.origin;
      var size = tester.getSize(paint);
      var rec = ui.PictureRecorder();
      p.paint(ui.Canvas(rec), size);
      var img = await tester.runAsync(() =>
          rec.endRecording().toImage(size.width.round(), size.height.round()));
      var px = (await tester.runAsync(() => img!.toByteData()))!
          .buffer
          .asUint8List();
      // The selection's blue, a line a pixel wide drawn between pixels.
      bool blueNear(Offset at) {
        for (var dy = -2; dy <= 2; dy++) {
          for (var dx = -3; dx <= 3; dx++) {
            var x = at.dx.round() + dx, y = at.dy.round() + dy;
            if (x < 0 || y < 0 || x >= size.width || y >= size.height) {
              continue;
            }
            var i = (y * size.width.round() + x) * 4;
            if (px[i + 2] > 0xB0 && px[i + 2] > px[i] + 0x50) return true;
          }
        }
        return false;
      }

      // A quarter down its left edge: clear of the handle at its middle.
      expect(blueNear(seen(const Offset(560, 325))), isTrue,
          reason: "the box's edge where the camera shows the element");
      // Not where the element is set on the page, unmoved by the camera.
      expect(blueNear(const Offset(560, 325) * p.scale + p.origin), isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("the Animation panel, a scene picked, sets a push in",
        (tester) async {
      var c = CanvasController(scene(null));
      addTearDown(c.dispose);
      c.pickScene(0);
      tester.view.physicalSize = const Size(1600, 600);
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
                body: Align(
                    alignment: Alignment.topLeft,
                    child: AnimationPanel(controller: c, height: 360)))),
      ));
      await tester.pumpAndSettle();
      // The Camera card's Move, as the prototype's scene chain has it.
      expect(find.byKey(const ValueKey("sceneCameraCard")), findsOneWidget);
      tester
          .widget<StudioDrop<CameraMove>>(
              find.byKey(const ValueKey("cameraMove")))
          .onChanged(CameraMove.pushIn);
      await tester.pumpAndSettle();
      var camera = c.document.allScenes.first.camera!;
      expect(camera.toZoom, greaterThan(camera.fromZoom));
    });
    // The prototype's Camera: Orbit among its moves, and a Shake.
    test("orbits once round, and shakes without showing the page edge", () {
      const page = Rect.fromLTWH(0, 0, 800, 450);
      var round = CameraMove.orbit.camera(0.3)!;
      expect(CameraMove.of(round), CameraMove.orbit);
      var (z0, a) = round.at(0, page);
      var (_, b) = round.at(0.5, page);
      var (_, back) = round.at(1, page);
      expect(z0, greaterThan(1));
      expect(a.dx, greaterThan(page.center.dx), reason: "starts right");
      expect(b.dx, lessThan(page.center.dx), reason: "half way: left");
      expect((back - a).distance, lessThan(1), reason: "and round again");

      var shaken = const SceneCamera(toZoom: 1, shake: 1);
      var seen = <Offset>{};
      for (var f = 0; f < 24; f++) {
        var (zoom, at) = shaken.at(f / 23, page, seconds: f / 24);
        expect(zoom, greaterThan(1), reason: "room to shake in");
        var hx = page.width / 2 / zoom, hy = page.height / 2 / zoom;
        expect(at.dx - hx, greaterThanOrEqualTo(-1e-9));
        expect(at.dx + hx, lessThanOrEqualTo(page.width + 1e-9));
        expect(at.dy - hy, greaterThanOrEqualTo(-1e-9));
        expect(at.dy + hy, lessThanOrEqualTo(page.height + 1e-9));
        seen.add(at);
      }
      expect(seen.length, greaterThan(10), reason: "it moves");
      var kept = SceneCamera.fromJson(shaken.copyWith(orbit: true).toJson())!;
      expect((kept.shake, kept.orbit), (1.0, true));
    });

    testWidgets("the Camera card's Shake, kept through a change of move",
        (tester) async {
      var c = CanvasController(scene(null));
      addTearDown(c.dispose);
      c.pickScene(0);
      tester.view.physicalSize = const Size(1600, 600);
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
                body: Align(
                    alignment: Alignment.topLeft,
                    child: ListenableBuilder(
                        listenable: c,
                        builder: (context, _) =>
                            AnimationPanel(controller: c, height: 360))))),
      ));
      await tester.pumpAndSettle();
      tester
          .widget<DeviceKnob>(find.byKey(const ValueKey("cameraShake")))
          .onChanged(0.5);
      await tester.pumpAndSettle();
      expect(c.document.allScenes.first.camera?.shake, 0.5,
          reason: "still, and shaking");
      tester
          .widget<StudioDrop<CameraMove>>(
              find.byKey(const ValueKey("cameraMove")))
          .onChanged(CameraMove.orbit);
      await tester.pumpAndSettle();
      var camera = c.document.allScenes.first.camera!;
      expect((camera.orbit, camera.shake), (true, 0.5));
      expect(tester.takeException(), isNull);
    });
  });
}
