import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_effects.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/render/image_silhouette.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'canvas_panel_helpers.dart';

// canvas_image_effects_test.dart is a layer's effects and a texture layer:
// saved, and drawn -- read back pixel by pixel.

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

Future<ui.Image> _picture(int w, int h, List<int> Function(int x, int y) f) {
  var pixels = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var p = f(x, y);
      var a = p[3] / 255;
      var i = (y * w + x) * 4;
      pixels[i] = (p[0] * a).round();
      pixels[i + 1] = (p[1] * a).round();
      pixels[i + 2] = (p[2] * a).round();
      pixels[i + 3] = p[3];
    }
  }
  var done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      pixels, w, h, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

const _box = ElementBase(id: "i", x: 0, y: 0, width: 100, height: 100);

void main() {
  group("saving", () {
    test("effects and a texture come back as they were", () {
      var texture = ImageLayer.texturing(TextureKind.grunge).copyWith(
          texture: const TextureSpec(
                  kind: TextureKind.grunge, colour: ui.Color(0xFF102030))
              .withValue("cover", 0.7)
              .copyWith(seed: 42));
      var picture = ImageLayer.picture("red", const Rect.fromLTWH(0, 0, 9, 9))
          .copyWith(effects: [
        const LayerEffect(
                kind: EffectKind.dropShadow, colour: ui.Color(0xFF00FF00))
            .withValue("distance", 30),
        const LayerEffect(kind: EffectKind.blur, on: false),
      ]);
      var e = ImageElement(_box,
          assetId: "red", layers: [ImageLayer.base, picture, texture]);
      var back = (elementFromJson(e.toJson()) as ImageElement).layers;
      expect(back[1].effects, hasLength(2));
      expect(back[1].effects[0].value("distance"), 30);
      expect(back[1].effects[0].colour, const ui.Color(0xFF00FF00));
      expect(back[1].effects[1].on, isFalse);
      expect(back[2].kind, LayerKind.texture);
      expect(back[2].blend, LayerBlend.multiply,
          reason: "grunge starts multiplied");
      expect(back[2].texture.value("cover"), 0.7);
      expect(back[2].texture.seed, 42);
      expect(back[2].texture.colour, const ui.Color(0xFF102030));
    });

    test("a base picture with an effect is no longer plain", () {
      var e = ImageElement(_box, assetId: "red", layers: [
        ImageLayer.base
            .copyWith(effects: [const LayerEffect(kind: EffectKind.blur)])
      ]);
      expect(e.layered, isTrue);
    });
  });

  group("drawing", () {
    late _Pictures images;
    setUpAll(() async {
      images = _Pictures({
        "white": await _picture(8, 8, (x, y) => [255, 255, 255, 255]),
        "grey": await _picture(8, 8, (x, y) => [128, 128, 128, 255]),
        "black": await _picture(8, 8, (x, y) => [0, 0, 0, 255]),
        // A white square in the middle third of black: a light on black,
        // the kind of picture that is screened over a scene.
        "light": await _picture(
            30,
            30,
            (x, y) => x >= 10 && x < 20 && y >= 10 && y < 20
                ? [255, 255, 255, 255]
                : [0, 0, 0, 255]),
        // A red square in the middle third, nothing round it.
        "square": await _picture(
            30,
            30,
            (x, y) => x >= 10 && x < 20 && y >= 10 && y < 20
                ? [255, 0, 0, 255]
                : [0, 0, 0, 0]),
      });
    });

    Future<Uint8List> render(ImageElement e, {double scale = 1}) async {
      var document = CanvasDocument(
          size: const CanvasSize(width: 100, ratio: CanvasRatio.square),
          elements: [e]);
      var image = await renderFrame(document, images: images, scale: scale);
      try {
        var raw =
            await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        return raw!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }

    List<int> at(Uint8List p, int x, int y, {int width = 100}) {
      var i = (y * width + x) * 4;
      return [p[i], p[i + 1], p[i + 2]];
    }

    /// onWhite is the square over a white ground, with [effects].
    ImageElement onWhite(List<LayerEffect> effects) =>
        ImageElement(_box, assetId: "white", fit: ImageFit.stretch, layers: [
          ImageLayer.base,
          ImageLayer.picture("square", const Rect.fromLTWH(0, 0, 1000, 1000))
              .copyWith(effects: effects),
        ]);

    test("a vignette darkens the corners and leaves the middle", () async {
      var p = await render(ImageElement(_box,
          assetId: "white",
          fit: ImageFit.stretch,
          layers: [
            ImageLayer.base,
            ImageLayer.texturing(TextureKind.vignette)
          ]));
      expect(at(p, 50, 50)[0], greaterThan(240));
      expect(at(p, 2, 2)[0], lessThan(120));
    });

    test("grain varies about the grey it lies over", () async {
      var p = await render(ImageElement(_box,
          assetId: "grey",
          fit: ImageFit.stretch,
          layers: [ImageLayer.base, ImageLayer.texturing(TextureKind.grain)]));
      var values = [
        for (var y = 10; y < 90; y += 3)
          for (var x = 10; x < 90; x += 3) at(p, x, y)[0]
      ];
      var mean = values.reduce((a, b) => a + b) / values.length;
      var spread = values.map((v) => (v - mean).abs()).reduce((a, b) => a + b) /
          values.length;
      expect(mean, closeTo(128, 20));
      expect(spread, greaterThan(5), reason: "it is grain, not grey");
    });

    test("a new seed is a different grain", () async {
      ImageElement grain(int seed) =>
          ImageElement(_box, assetId: "grey", fit: ImageFit.stretch, layers: [
            ImageLayer.base,
            ImageLayer.texturing(TextureKind.grain).copyWith(
                texture: TextureSpec(kind: TextureKind.grain, seed: seed))
          ]);
      var a = await render(grain(1)), b = await render(grain(2));
      var same = await render(grain(1));
      expect(a, same, reason: "the same seed draws the same");
      expect(a, isNot(b));
    });

    test("a texture is the same texture drawn twice the size", () async {
      // Halftone dots measured in the frame's units: a dot at a point of
      // the canvas is a dot there at any size it is exported at.
      var e =
          ImageElement(_box, assetId: "white", fit: ImageFit.stretch, layers: [
        ImageLayer.base,
        ImageLayer.texturing(TextureKind.halftone).copyWith(
            texture: const TextureSpec(kind: TextureKind.halftone)
                .withValue("cell", 100)
                .withValue("angle", 0)
                .withValue("dot", 0.5))
      ]);
      var one = await render(e), two = await render(e, scale: 2);
      var agree = 0, count = 0;
      for (var y = 3; y < 100; y += 7) {
        for (var x = 3; x < 100; x += 7) {
          count++;
          var a = at(one, x, y)[0] < 128;
          var b = at(two, x * 2, y * 2, width: 200)[0] < 128;
          if (a == b) agree++;
        }
      }
      expect(agree / count, greaterThan(0.9));
    });

    test("a drop shadow falls down and to the right", () async {
      var p = await render(onWhite([
        const LayerEffect(kind: EffectKind.dropShadow)
            .withValue("distance", 60)
            .withValue("blur", 0)
            .withValue("opacity", 1),
      ]));
      // The square is 33..66; the shadow is a little under and right of it.
      expect(at(p, 68, 68)[0], lessThan(60), reason: "shadow");
      expect(at(p, 30, 30)[0], greaterThan(240), reason: "not up and left");
      expect(at(p, 50, 50), [255, 0, 0], reason: "the square over it");
    });

    test("an outer glow is round the layer in its colour", () async {
      var p = await render(onWhite([
        const LayerEffect(
                kind: EffectKind.outerGlow, colour: ui.Color(0xFF0000FF))
            .withValue("spread", 40)
            .withValue("size", 0)
            .withValue("opacity", 1),
      ]));
      var beside = at(p, 30, 50);
      expect(beside[2], greaterThan(200));
      expect(beside[0], lessThan(60));
    });

    test("a screened layer glows round what is bright in it", () async {
      var p = await render(
          ImageElement(_box, assetId: "black", fit: ImageFit.stretch, layers: [
        ImageLayer.base,
        ImageLayer.picture("light", const Rect.fromLTWH(250, 250, 500, 500))
            .copyWith(blend: LayerBlend.screen, effects: [
          const LayerEffect(
                  kind: EffectKind.outerGlow, colour: ui.Color(0xFF0000FF))
              .withValue("spread", 40)
              .withValue("size", 0)
              .withValue("opacity", 1),
        ]),
      ]));
      // The light is 42..58 of a layer 25..75: the glow is round the light,
      // not round the black the light is on.
      expect(at(p, 39, 50)[2], greaterThan(150), reason: "round the light");
      expect(at(p, 23, 50)[2], lessThan(40), reason: "not round the layer");
      expect(at(p, 50, 50), [255, 255, 255]);
    });

    test("an inner shadow darkens the inside of one edge", () async {
      var p = await render(onWhite([
        const LayerEffect(kind: EffectKind.innerShadow)
            .withValue("distance", 60)
            .withValue("blur", 0)
            .withValue("opacity", 1),
      ]));
      expect(at(p, 35, 50)[0], lessThan(60), reason: "the lit edge");
      expect(at(p, 62, 62)[0], greaterThan(200), reason: "the far corner");
      expect(at(p, 25, 50)[0], greaterThan(240), reason: "only inside");
    });

    test("a motion blur smears along its line and not across it", () async {
      var p = await render(onWhite([
        const LayerEffect(kind: EffectKind.motionBlur)
            .withValue("distance", 200),
      ]));
      var along = at(p, 75, 50), across = at(p, 50, 75);
      expect(along[1], lessThan(240), reason: "red carried sideways");
      expect(across[1], greaterThan(245), reason: "but not up or down");
    });

    test("a blur softens the edge", () async {
      var p = await render(onWhite([
        const LayerEffect(kind: EffectKind.blur).withValue("amount", 60),
      ]));
      expect(at(p, 33, 50)[1], inInclusiveRange(40, 230));
    });

    test("a colour fringe splits the channels apart", () async {
      var p = await render(onWhite([
        const LayerEffect(kind: EffectKind.fringe).withValue("distance", 50),
      ]));
      // Red moved left of where the green and blue are.
      var left = at(p, 30, 50);
      expect(left[0], greaterThan(200));
    });

    test("an effect switched off does nothing", () async {
      var plain = await render(onWhite(const []));
      var off = await render(onWhite(const [
        LayerEffect(kind: EffectKind.dropShadow, on: false),
      ]));
      expect(off, plain);
    });
  });

  group("in the panel", () {
    Future<CanvasController> pumpPanel(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(const CanvasDocument().addElement(
          const ImageElement(_box, assetId: "white", fit: ImageFit.stretch)));
      addTearDown(c.dispose);
      c.selectOnly("i");
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
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

    ImageElement now(CanvasController c) =>
        c.document.elementById("i")! as ImageElement;

    Future<void> tapKey(WidgetTester tester, String key) async {
      var found = find.byKey(ValueKey(key));
      await tester.ensureVisible(found);
      await tester.tap(found);
      await tester.pumpAndSettle();
    }

    testWidgets("a texture is added and set", (tester) async {
      var c = await pumpPanel(tester);
      await addLayer(tester, "imageAddTexture");
      expect(c.pickedLayer?.kind, LayerKind.texture);
      expect(find.byKey(const ValueKey("textureKind")), findsOneWidget);
      var seed = c.pickedLayer!.texture.seed;
      await tapKey(tester, "textureSeed");
      expect(c.pickedLayer!.texture.seed, isNot(seed));
      expect(tester.takeException(), isNull);
    });

    testWidgets("an effect is added from its tile, and taken off",
        (tester) async {
      var c = await pumpPanel(tester);
      await tapKey(tester, "imageLayer-base");
      await openSection(tester, "image.picture.effects");
      await tapKey(tester, "effectTile-dropShadow");
      var base = now(c).stack.firstWhere((l) => l.isBase);
      expect(base.effects.single.kind, EffectKind.dropShadow);
      expect(c.trying, isFalse);
      expect(find.byKey(const ValueKey("effect-dropShadow")), findsOneWidget);

      await tapKey(tester, "effectRemove-dropShadow");
      expect(now(c).stack.firstWhere((l) => l.isBase).effects, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}
