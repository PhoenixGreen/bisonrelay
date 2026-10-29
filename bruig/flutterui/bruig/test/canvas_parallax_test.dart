import 'dart:typed_data';
import 'dart:ui';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/parallax_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart'
    show cameraChannel;
import 'package:bruig/plugin_system/canvas/presets/parallax_looks.dart';
import 'package:bruig/plugin_system/canvas/render/parallax_painter.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_parallax_test.dart is the parallax background: layers of scenery
// moving by their share of the camera's move, drifting by themselves, going
// on for ever without a seam, and a camera keyed on the timeline -- on the
// canvas's own background and on a Background element.

const page = Rect.fromLTWH(0, 0, 640, 360);

ParallaxElement scenery(List<ParallaxLayer> layers,
        {ParallaxCamera camera = const ParallaxCamera(), String id = ""}) =>
    ParallaxElement(ElementBase(id: id, width: 640, height: 360),
        camera: camera, layers: layers);

Future<Uint8List> draw(ParallaxElement p, {int frame = 0}) async {
  var rec = PictureRecorder();
  paintParallax(Canvas(rec), page, p, frame);
  var img = await rec.endRecording().toImage(640, 360);
  return (await img.toByteData())!.buffer.asUint8List();
}

/// alpha is the coverage of the pixel at (x, y) in [rgba].
int alpha(Uint8List rgba, int x, int y) => rgba[(y * 640 + x) * 4 + 3];

void main() {
  group("the model", () {
    test("scenery is saved whole", () {
      var p = scenery([
        ...parallaxLooks[1].layers,
        const ParallaxLayer(
            kind: SceneryKind.picture,
            assetId: "pic1",
            autoX: 12,
            offset: Offset(5, -3),
            repeatY: true,
            anchor: LayerAnchor.top,
            opacity: 0.5,
            visible: false),
      ], camera: const ParallaxCamera(x: 120, y: -4, zoom: 1.5));
      var back = ParallaxElement.fromJson(
          p.props(), const ElementBase(id: ""));
      expect(back.props(), p.props());
      expect(back.assetIds, {"pic1"});
    });

    test("both kinds of background carry it, and own its pictures", () {
      var p = scenery([
        const ParallaxLayer(kind: SceneryKind.picture, assetId: "pic2"),
      ]);
      var el = const BackgroundElement(ElementBase(id: "bg")).withParallax(p);
      var elBack = elementFromJson(el.toJson()) as BackgroundElement;
      expect(elBack.isParallax, isTrue);
      expect(elBack.toJson(), el.toJson());
      expect(elBack.assetIds, {"pic2"},
          reason: "or the picture store sweeps it away");

      var doc = CanvasDocument(
          background: CanvasBackground(
              backdrop: BackdropKind.parallax,
              parallax: p.rebase(const ElementBase(id: backgroundParallaxId))
                  as ParallaxElement));
      var docBack = CanvasDocument.fromJson(doc.toJson());
      expect(docBack.background.isParallax, isTrue);
      expect(docBack.background.toJson(), doc.background.toJson());
      expect(docBack.background.assetIds, contains("pic2"));
    });

    test("a ridge ends where it begins, so its tiles join", () {
      for (var kind in [SceneryKind.mountains, SceneryKind.hills]) {
        for (var seed in [1, 7, 42]) {
          var l = ParallaxLayer(kind: kind, seed: seed, amount: 0.8);
          expect(ridge(l, 0), closeTo(ridge(l, 1), 1e-9),
              reason: "${kind.name} seed $seed");
        }
      }
    });

    test("it moves by its share of the camera, and drifts by itself", () {
      const cam = ParallaxCamera(x: 200, y: 40);
      expect(layerShift(const ParallaxLayer(scrollX: 0, scrollY: 0), cam, 0),
          Offset.zero);
      expect(
          layerShift(const ParallaxLayer(scrollX: 0.5, scrollY: 0.25), cam, 0),
          const Offset(-100, -10));
      expect(
          layerShift(
              const ParallaxLayer(scrollX: 0, scrollY: 0, autoX: 10), cam, 3),
          const Offset(30, 0));
      expect(layerZoom(const ParallaxLayer(scrollX: 0, scrollY: 0),
              const ParallaxCamera(zoom: 2)),
          1, reason: "the sky does not come nearer");
    });

    test("only a keyed camera, a drift or a moving pattern moves it", () {
      expect(parallaxLooks[1].scenery.moves, isFalse);
      expect(parallaxLooks[0].scenery.moves, isTrue,
          reason: "its clouds drift");
      var keyed = parallaxLooks[1].scenery.withBase(
          track: ElementTrack([
        Keyframe(frame: 0).withValue(cameraChannel("x"), 0),
      ])) as ParallaxElement;
      expect(keyed.moves, isTrue);
    });
  });

  group("drawing it", () {
    test("a sky stays put and the ground moves with the camera", () async {
      const sky = ParallaxLayer(
          kind: SceneryKind.sky,
          scrollX: 0,
          scrollY: 0,
          anchor: LayerAnchor.fill);
      const hills = ParallaxLayer(kind: SceneryKind.hills, scrollX: 1);
      expect(
          await draw(scenery([sky], camera: const ParallaxCamera(x: 333))),
          await draw(scenery([sky])));
      expect(
          await draw(scenery([hills], camera: const ParallaxCamera(x: 333))),
          isNot(await draw(scenery([hills]))));
    });

    test("repeated, it goes on for ever; not, the camera passes it",
        () async {
      const ground = ParallaxLayer(
          kind: SceneryKind.ground, height: 0.2, scrollX: 1, amount: 0);
      var far = await draw(
          scenery([ground], camera: const ParallaxCamera(x: 7777)));
      for (var x = 0; x < 640; x += 7) {
        expect(alpha(far, x, 355), 255, reason: "no gap at x $x");
      }
      var gone = await draw(scenery([ground.copyWith(repeatX: false)],
          camera: const ParallaxCamera(x: 7777)));
      expect(alpha(gone, 320, 355), 0);
    });

    test("clouds drift from frame to frame", () async {
      const clouds = ParallaxLayer(
          kind: SceneryKind.clouds,
          scrollX: 0,
          autoX: 40,
          anchor: LayerAnchor.fill);
      expect(await draw(scenery([clouds]), frame: 30),
          isNot(await draw(scenery([clouds]))));
    });

    test("a hidden layer is not drawn", () async {
      const hills = ParallaxLayer(kind: SceneryKind.hills);
      expect(await draw(scenery([hills.copyWith(visible: false)])),
          await draw(scenery(const [])));
    });

    test("the canvas background draws it, behind everything", () async {
      Future<Uint8List> doc(CanvasBackground bg) async {
        var rec = PictureRecorder();
        paintCanvasDocument(
            Canvas(rec), CanvasDocument(frames: 48, background: bg));
        var img = await rec.endRecording().toImage(320, 180);
        return (await img.toByteData())!.buffer.asUint8List();
      }

      var p = parallaxLooks[2].scenery;
      var shown = CanvasBackground(backdrop: BackdropKind.parallax, parallax: p);
      var kept = CanvasBackground(parallax: p);
      expect(await doc(shown), isNot(await doc(kept)));
      expect(await doc(kept), await doc(const CanvasBackground()),
          reason: "kept but not shown changes nothing");
    });
  });

  group("its camera", () {
    test("is keyed on the canvas background, and pans across in one press",
        () {
      var c = CanvasController(CanvasDocument(
          frames: 48,
          background: CanvasBackground(
              backdrop: BackdropKind.parallax,
              parallax: parallaxLooks[1].scenery.rebase(
                      const ElementBase(id: backgroundParallaxId))
                  as ParallaxElement)));
      addTearDown(c.dispose);
      ParallaxElement get() => c.parallaxOf(backgroundParallaxId)!;
      c.putBackdrop(c.parallaxFilmed(get(), const ParallaxCamera(x: 50)));
      expect(get().camera.x, 50, reason: "not keyed yet: the setting");
      c.panAcross(get(), 900);
      expect(c.document.background.parallax!.track!.keys.map((k) => k.frame),
          [0, 47]);
      expect(get().cameraAt(0).x, 50);
      expect(get().cameraAt(47).x, 950);
      c.frame = 20;
      c.putBackdrop(c.parallaxFilmed(get(), const ParallaxCamera(x: 0)));
      expect(get().track!.keys.map((k) => k.frame), [0, 20, 47],
          reason: "once keyed, a change is made on the frame looked at");
      expect(c.hasCameraKey(get()), isTrue);
      c.clearCameraKey(get());
      expect(c.hasCameraKey(get()), isFalse);
    });

    test("on a Background element, its keys are on the element's track", () {
      var bg = const BackgroundElement(
              ElementBase(id: "bg", width: 640, height: 360))
          .withParallax(parallaxLooks[3].scenery);
      var c = CanvasController(CanvasDocument(frames: 48).addElement(bg));
      addTearDown(c.dispose);
      c.frame = 12;
      c.keyCamera(c.parallaxOf("bg")!);
      var after = c.document.elementById("bg")!;
      expect(after, isA<BackgroundElement>());
      expect(after.track!.keys.map((k) => k.frame), [0, 12]);
    });
  });

  group("the panel", () {
    setUpAll(() => CanvasSection.openAll = true);
    tearDownAll(() => CanvasSection.openAll = false);

    Widget host(CanvasController c) => MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
                create: (c) => ThemeNotifier(doLoad: false)),
            ChangeNotifierProvider<SnackBarModel>(
                create: (c) => SnackBarModel()),
            ChangeNotifierProvider<CanvasPreferences>(
                create: (c) => CanvasPreferences()),
          ],
          child: MaterialApp(
              home: Scaffold(
                  body: SizedBox(
                      width: 420, child: CanvasDesignPanel(controller: c)))),
        );

    Future<void> tap(WidgetTester tester, String key) async {
      var f = find.byKey(ValueKey(key));
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    testWidgets("the background becomes scenery, edited layer by layer",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(const CanvasDocument(frames: 48));
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(900, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(c));
      await tester.pumpAndSettle();
      ParallaxElement get() => c.document.background.parallax!;

      await tap(tester, "backdropKind-parallax");
      expect(c.document.background.isParallax, isTrue);
      expect(get().layers, parallaxLooks.first.layers,
          reason: "a whole scene to start from");
      expect(find.byKey(const ValueKey("addLayer")), findsNothing,
          reason: "the pattern's layers are not offered");

      await tap(tester, "parallaxLook-Night city");
      expect(get().layers, parallaxLooks[2].layers);

      // The front layer is the one picked; take it nearer than nothing,
      // then further, hide it, and add one.
      var n = get().layers.length;
      await tap(tester, "parallaxDown-${n - 1}");
      expect(get().layers[n - 2], parallaxLooks[2].layers[n - 1]);
      await tap(tester, "parallaxUp-${n - 2}");
      expect(get().layers, parallaxLooks[2].layers);
      await tap(tester, "parallaxEye-0");
      expect(get().layers[0].visible, isFalse);
      var add = find.byKey(const ValueKey("parallaxAdd"));
      await tester.ensureVisible(add);
      tester
          .widget<CanvasDropdown<SceneryKind?>>(add)
          .onChanged(SceneryKind.clouds);
      await tester.pumpAndSettle();
      expect(get().layers.last.kind, SceneryKind.clouds);

      await tap(tester, "parallax-scrollX-more");
      expect(get().layers.last.scrollX, closeTo(0.15, 1e-9));
      await tap(tester, "parallaxRepeatX");
      expect(get().layers.last.repeatX, isFalse);

      await tap(tester, "parallaxCamX-more");
      expect(get().camera.x, 50);
      await tap(tester, "parallaxPanAcross");
      expect(get().track!.keys.length, 2);

      await tap(tester, "backdropKind-flat");
      expect(c.document.background.isParallax, isFalse);
      expect(get().layers.last.kind, SceneryKind.clouds,
          reason: "kept for coming back to");
      expect(tester.takeException(), isNull);
    });

    testWidgets("a Background element becomes scenery", (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(const CanvasDocument(frames: 48).addElement(
          const BackgroundElement(
              ElementBase(id: "bg", width: 640, height: 360))));
      addTearDown(c.dispose);
      c.selectOnly("bg");
      tester.view.physicalSize = const Size(900, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(c));
      await tester.pumpAndSettle();
      BackgroundElement get() =>
          c.document.elementById("bg")! as BackgroundElement;
      await tap(tester, "backdropKind-parallax");
      expect(get().isParallax, isTrue);
      c.frame = 10;
      await tester.pumpAndSettle();
      await tap(tester, "parallaxKey");
      expect(get(), isA<BackgroundElement>());
      expect(get().track!.keys.map((k) => k.frame), [0, 10]);
      expect(tester.takeException(), isNull);
    });
  });
}
