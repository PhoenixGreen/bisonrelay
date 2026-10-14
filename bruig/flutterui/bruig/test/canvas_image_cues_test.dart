import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_effects.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart'
    show VectorCue;
import 'package:bruig/plugin_system/canvas/render/image_silhouette.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'canvas_panel_helpers.dart';

// canvas_image_cues_test.dart is a picture built up a layer at a time as it
// arrives, and a look kept and put on another picture.

class _Pictures implements CanvasImageSource {
  final Map<String, ui.Image> images;
  _Pictures(this.images);
  @override
  bool get loading => false;
  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) =>
      images[assetId];
  @override
  CanvasVector? resolveVector(String assetId) => null;
  @override
  ImageSilhouette? resolveOutline(String assetId, BackgroundRemoval removal) =>
      null;
}

Future<ui.Image> _solid(List<int> c) {
  var pixels = Uint8List(8 * 8 * 4);
  for (var i = 0; i < 64; i++) {
    for (var k = 0; k < 4; k++) {
      pixels[i * 4 + k] = c[k];
    }
  }
  var done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      pixels, 8, 8, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

ImageLayer _picture(String asset) =>
    ImageLayer.picture(asset, const Rect.fromLTWH(0, 0, 1000, 1000));

void main() {
  group("timing", () {
    test("together, every layer takes the whole arrival", () {
      var stack = [ImageLayer.base, _picture("a"), _picture("b")];
      expect(layerTimes(stack, 30), [(0.0, 30.0), (0.0, 30.0), (0.0, 30.0)]);
      expect(layersSequenced(stack), isFalse);
    });

    test("one after another, they share it out in turn", () {
      var stack = [
        ImageLayer.base,
        _picture("a").copyWith(cue: VectorCue.after),
        _picture("b").copyWith(cue: VectorCue.after),
      ];
      var times = layerTimes(stack, 30);
      expect(times[0], (0.0, 10.0));
      expect(times[1], (10.0, 10.0));
      expect(times[2], (20.0, 10.0));
      expect(layersSequenced(stack), isTrue);
    });

    test("staggered, each overlaps the one before by a third", () {
      var e = withLayersStaggered(
          ImageElement(const ElementBase(id: "i"),
              layers: [ImageLayer.base, _picture("a"), _picture("b")]),
          30);
      expect(e.stack[0].cue, VectorCue.together);
      expect(e.stack[1].cue, VectorCue.gap);
      expect(e.stack[1].cueGap, -10);
      var times = layerTimes(e.stack, 30);
      expect(times.last.$1 + times.last.$2, closeTo(30, 1e-9),
          reason: "the last finishes as the arrival does");
      expect(times[1].$1, lessThan(times[0].$2), reason: "overlapping");
      expect(withLayersTogether(e).stack.any((l) => l.cue != VectorCue.together),
          isFalse);
    });

    test("cues come back as they were saved", () {
      var layer = _picture("a")
          .copyWith(cue: VectorCue.gap, cueGap: -4, cueLength: 12);
      var back = ImageLayer.fromJson(layer.toJson())!;
      expect(back.cue, VectorCue.gap);
      expect(back.cueGap, -4);
      expect(back.cueLength, 12);
      expect(ImageLayer.base.copyWith(cue: VectorCue.after).plain, isFalse);
    });
  });

  group("arriving", () {
    late _Pictures images;
    setUpAll(() async {
      images = _Pictures({
        "red": await _solid([255, 0, 0, 255]),
        "blue": await _solid([0, 0, 255, 255]),
      });
    });

    Future<List<int>> pixelAt(ImageElement e, int frame) async {
      var document = CanvasDocument(
              size: const CanvasSize(width: 100, ratio: CanvasRatio.square),
              elements: [e])
          .copyWith(frames: 40);
      var image =
          await renderFrame(document, images: images, frame: frame);
      try {
        var raw =
            await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        var p = raw!.buffer.asUint8List();
        var i = (50 * 100 + 50) * 4;
        return [p[i], p[i + 1], p[i + 2]];
      } finally {
        image.dispose();
      }
    }

    ImageElement arriving(VectorCue cue) => ImageElement(
          ElementBase(
              id: "i",
              x: 0,
              y: 0,
              width: 100,
              height: 100,
              track: ElementTrack(const [
                Keyframe(frame: 0, values: {KeyframeChannel.reveal: 0}),
                Keyframe(frame: 30, values: {KeyframeChannel.reveal: 1}),
              ])),
          assetId: "red",
          fit: ImageFit.stretch,
          animation:
              const ElementAnimation(preset: ElementAnimationPreset.fadeIn),
          layers: [
            ImageLayer.base,
            _picture("blue").copyWith(cue: cue),
          ],
        );

    test("the layer over comes in after the one under it", () async {
      var e = arriving(VectorCue.after);
      var early = await pixelAt(e, 12);
      expect(early[0], greaterThan(150), reason: "the red in: $early");
      expect(early[2], lessThan(40), reason: "the blue not yet");
      var late = await pixelAt(e, 30);
      expect(late[2], greaterThan(220), reason: "and then the blue: $late");
    });

    test("together, the picture arrives as one", () async {
      var e = arriving(VectorCue.together);
      var half = await pixelAt(e, 15);
      var whole = await pixelAt(e, 30);
      // The whole picture part way in -- the blue over the dark page, the
      // red under it never seen on its own.
      expect(half[0], lessThan(40));
      expect(half[2], lessThan(whole[2]));
      expect(half[2], greaterThan(40));
    });
  });

  group("looks", () {
    var graded = ImageElement(const ElementBase(id: "g"),
        assetId: "red",
        layers: [
          ImageLayer.solid(const PaintSpec(ui.Color(0xFF101010))),
          ImageLayer.base.copyWith(
              opacity: 0.8,
              effects: [const LayerEffect(kind: EffectKind.dropShadow)]),
          _picture("blue"),
          ImageLayer.adjusting(AdjustKind.keepColour),
          ImageLayer.texturing(TextureKind.grain),
        ]);

    test("a look keeps the grade and none of the pictures", () {
      var data = lookData(graded);
      var kinds = [
        for (var l in data["layers"] as List) (l as Map)["k"],
      ];
      expect(kinds, ["fill", "adjustment", "texture"]);
      expect((data["layers"] as List).first["under"], isTrue);
      expect(data.toString(), isNot(contains("blue")));
    });

    test("worn, it replaces the grade and keeps the pictures", () {
      var target = ImageElement(const ElementBase(id: "t"),
          assetId: "photo",
          layers: [
            ImageLayer.base,
            _picture("player"),
            ImageLayer.adjusting(AdjustKind.invert),
          ]);
      var worn = withLookApplied(target, lookData(graded));
      var stack = worn.stack;
      expect([for (var l in stack) l.kind], [
        LayerKind.fill,
        LayerKind.base,
        LayerKind.picture,
        LayerKind.adjustment,
        LayerKind.texture,
      ]);
      expect(stack[2].look!.assetId, "player", reason: "its own picture");
      expect(stack[3].adjust.kind, AdjustKind.keepColour,
          reason: "its invert gone, the look's adjustment instead");
      expect(worn.assetId, "photo");
      expect(stack[1].opacity, 0.8);
      expect(stack[1].effects.single.kind, EffectKind.dropShadow);
      expect(stack[3].id, isNot(graded.stack[3].id), reason: "fresh layers");
    });
  });

  group("in the panel", () {
    Future<CanvasController> pumpPanel(WidgetTester tester, ImageElement e) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(const CanvasDocument().addElement(e));
      addTearDown(c.dispose);
      c.selectOnly(e.id);
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
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
      ));
      await tester.pumpAndSettle();
      return c;
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      var found = find.byKey(ValueKey(key));
      await tester.ensureVisible(found);
      await tester.tap(found);
      await tester.pumpAndSettle();
    }

    Future<void> idle(WidgetTester tester) async {
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 4)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    testWidgets("Stagger brings the layers in one after another",
        (tester) async {
      var c = await pumpPanel(
          tester,
          ImageElement(
              const ElementBase(id: "i", x: 0, y: 0, width: 100, height: 100),
              assetId: "red",
              layers: [ImageLayer.base, _picture("blue")]));
      await openSection(tester, "image.picture.animation");
      await tapKey(tester, "imageLayersStagger");
      var e = c.document.elementById("i")! as ImageElement;
      expect(e.animation.on, isTrue, reason: "an arrival to stagger over");
      expect(layersSequenced(e.stack), isTrue);
      c.undo();
      expect((c.document.elementById("i")! as ImageElement).animation.on,
          isFalse,
          reason: "one step");

      // And the picked layer's cue is chosen in its Animation.
      await tapKey(tester, "imageLayersStagger");
      var top = (c.document.elementById("i")! as ImageElement).stack.last;
      await tapKey(tester, "imageLayer-${top.id}");
      await openSection(tester, "image.picture.animation");
      await tapKey(tester, "imageLayerCue-${top.id}");
      await tester.tap(find.text(top.cue.next.label).last);
      await tester.pumpAndSettle();
      expect(
          (c.document.elementById("i")! as ImageElement).stack.last.cue,
          top.cue.next);
      expect(tester.takeException(), isNull);
    });

    testWidgets("a look is kept, and worn by another picture",
        (tester) async {
      var root = Directory.systemTemp.createTempSync("looks");
      addTearDown(() => root.deleteSync(recursive: true));
      CanvasStorage.rootOverride = root.path;
      addTearDown(() => CanvasStorage.rootOverride = null);
      SavedPresetStore.looks.forget();

      var c = await pumpPanel(
          tester,
          ImageElement(
              const ElementBase(id: "g", x: 0, y: 0, width: 100, height: 100),
              assetId: "red",
              layers: [
                ImageLayer.base,
                ImageLayer.adjusting(AdjustKind.keepColour),
              ]));
      await idle(tester);
      await openSection(tester, "image.frame");
      await tapKey(tester, "imageLookSave");
      await idle(tester);
      expect(SavedPresetStore.looks.presets, hasLength(1));

      // Another picture, with nothing on it.
      c.addElement(const ImageElement(
          ElementBase(id: "t", x: 0, y: 0, width: 100, height: 100),
          assetId: "photo"));
      await tester.pumpAndSettle();
      await openSection(tester, "image.frame");
      await tapKey(tester, "imageLookPick");
      await tester.tap(find.text(SavedPresetStore.looks.presets.single.name).last);
      await tester.pumpAndSettle();
      var t = c.document.elementById("t")! as ImageElement;
      expect(t.stack.last.adjust.kind, AdjustKind.keepColour);
      expect(t.assetId, "photo");
      expect(tester.takeException(), isNull);
    });
  });
}
