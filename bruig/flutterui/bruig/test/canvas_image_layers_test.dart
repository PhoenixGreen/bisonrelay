import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_effects.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/render/image_silhouette.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_image_layers_test.dart is a picture made of layers: how the stack is
// saved, how it is composited, and where a layer is on the canvas when the
// element and the layer are both turned.

/// _Pictures hands back a decoded picture per asset id.
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

/// _picture is a [size] square made by [pixel], which gives each pixel's
/// straight RGBA.
Future<ui.Image> _picture(int size, List<int> Function(int x, int y) pixel) {
  var pixels = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      var p = pixel(x, y);
      var i = (y * size + x) * 4;
      var a = p[3] / 255;
      // Premultiplied, which is what decodeImageFromPixels expects.
      pixels[i] = (p[0] * a).round();
      pixels[i + 1] = (p[1] * a).round();
      pixels[i + 2] = (p[2] * a).round();
      pixels[i + 3] = p[3];
    }
  }
  var done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      pixels, size, size, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

Future<List<int>> _pixel(
    ImageElement e, CanvasImageSource images, int x, int y) async {
  var document = CanvasDocument(
    size: const CanvasSize(width: 100, ratio: CanvasRatio.square),
    elements: [e],
  );
  var image = await renderFrame(document, images: images);
  try {
    var raw =
        await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    var pixels = raw!.buffer.asUint8List();
    var i = (y * image.width + x) * 4;
    return [pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]];
  } finally {
    image.dispose();
  }
}

const _box = ElementBase(id: "i", x: 0, y: 0, width: 100, height: 100);

void main() {
  test("a flipped layer with an effect keeps both when it is saved", () {
    var l = ImageLayer.picture(
            "aaaaaaaaaaaaaaa1", const Rect.fromLTWH(0, 0, 500, 500))
        .copyWith(
            flipX: true,
            effects: const [LayerEffect(kind: EffectKind.dropShadow)]);
    var back = ImageLayer.fromJson(l.toJson())!;
    expect(back.flipX, isTrue);
    expect(back.effects.single.kind, EffectKind.dropShadow);
    // And a flip saved the old way is still read.
    var old = l.copyWith(effects: const []).toJson()
      ..remove("flipX")
      ..["fx"] = true;
    expect(ImageLayer.fromJson(old)!.flipX, isTrue);
  });

  group("saving", () {
    test("a picture with no layers is written as it always was", () {
      var e = const ImageElement(_box, assetId: "red");
      expect(e.props().containsKey("layers"), isFalse);
      expect(e.layered, isFalse);
      expect(e.stack.single.isBase, isTrue);
    });

    test("an untouched base layer alone is not worth writing", () {
      var e =
          const ImageElement(_box, assetId: "red", layers: [ImageLayer.base]);
      expect(e.layered, isFalse);
      expect(e.props().containsKey("layers"), isFalse);
    });

    test("every layer comes back as it was saved", () {
      var picture =
          ImageLayer.picture("blue", const Rect.fromLTWH(100, 200, 300, 400))
              .placed(const Rect.fromLTWH(100, 200, 300, 400), turn: 30)
              .copyWith(
                  blend: LayerBlend.multiply,
                  opacity: 0.5,
                  clip: true,
                  flipX: true,
                  name: "Cannon");
      var fade = ImageLayer.solid(const PaintSpec(ui.Color(0xFF112233),
          gradient: GradientSpec(to: ui.Color(0xFF445566))));
      var e = ImageElement(_box, assetId: "red", layers: [
        ImageLayer.base.copyWith(opacity: 0.8),
        picture,
        fade,
      ]);
      var back = elementFromJson(e.toJson()) as ImageElement;

      expect(back.layers.length, 3);
      expect(back.layers[0].isBase, isTrue);
      expect(back.layers[0].opacity, 0.8);

      var p = back.layers[1];
      expect(p.kind, LayerKind.picture);
      expect(p.id, picture.id);
      expect(p.name, "Cannon");
      expect(p.look!.assetId, "blue");
      expect(p.place, const Rect.fromLTWH(100, 200, 300, 400));
      expect(p.turn, 30);
      expect(p.blend, LayerBlend.multiply);
      expect(p.opacity, 0.5);
      expect(p.clip, isTrue);
      expect(p.flipX, isTrue);
      expect(p.flipY, isFalse);

      expect(back.layers[2].kind, LayerKind.fill);
      expect(back.layers[2].fill.fades, isTrue);
      expect(back.layers[2].fill.color, const ui.Color(0xFF112233));
    });

    test("a stack that lost its base gets it back at the bottom", () {
      var e = ImageElement(_box, assetId: "red", layers: [
        ImageLayer.picture("blue", const Rect.fromLTWH(0, 0, 9, 9))
      ]);
      expect(e.stack.length, 2);
      expect(e.stack.first.isBase, isTrue);
    });

    test("the pictures in layers are the element's assets too", () {
      var e = ImageElement(_box, assetId: "red", layers: [
        ImageLayer.base,
        ImageLayer.picture("blue", const Rect.fromLTWH(0, 0, 9, 9)),
      ]);
      expect(e.assetIds, containsAll(["red", "blue"]));
    });
  });

  group("compositing", () {
    late ui.Image red, blue, halves, middle;
    late _Pictures images;
    setUpAll(() async {
      red = await _picture(8, (x, y) => [255, 0, 0, 255]);
      blue = await _picture(8, (x, y) => [0, 0, 255, 255]);
      // Red on the left half, green on the right.
      halves = await _picture(
          8, (x, y) => x < 4 ? [255, 0, 0, 255] : [0, 255, 0, 255]);
      // A white square in the middle and nothing round it: a cut-out.
      middle = await _picture(
          8,
          (x, y) => x >= 2 && x < 6 && y >= 2 && y < 6
              ? [255, 255, 255, 255]
              : [0, 0, 0, 0]);
      images = _Pictures(
          {"red": red, "blue": blue, "halves": halves, "middle": middle});
    });

    ImageElement over(ImageLayer layer, {String base = "red"}) =>
        ImageElement(_box,
            assetId: base,
            fit: ImageFit.stretch,
            layers: [ImageLayer.base, layer]);

    test("a picture layer is drawn in its place and nowhere else", () async {
      var e = over(
          ImageLayer.picture("blue", const Rect.fromLTWH(500, 500, 500, 500)));
      expect((await _pixel(e, images, 75, 75)).sublist(0, 3), [0, 0, 255]);
      expect((await _pixel(e, images, 25, 25)).sublist(0, 3), [255, 0, 0]);
      expect((await _pixel(e, images, 75, 25)).sublist(0, 3), [255, 0, 0]);
    });

    test("a hidden layer is not drawn", () async {
      var e = over(ImageLayer.picture(
              "blue", const Rect.fromLTWH(0, 0, layerUnits, layerUnits))
          .copyWith(visible: false));
      expect((await _pixel(e, images, 50, 50)).sublist(0, 3), [255, 0, 0]);
    });

    test("a blend mode blends with the layers below", () async {
      // Blue multiplied over red is black: neither has what the other has.
      var e = over(ImageLayer.solid(const PaintSpec(ui.Color(0xFF0000FF)))
          .copyWith(blend: LayerBlend.multiply));
      expect((await _pixel(e, images, 50, 50)).sublist(0, 3), [0, 0, 0]);

      // And screened, it is the two together.
      var screened = over(
          ImageLayer.solid(const PaintSpec(ui.Color(0xFF0000FF)))
              .copyWith(blend: LayerBlend.screen));
      expect((await _pixel(screened, images, 50, 50)).sublist(0, 3),
          [255, 0, 255]);
    });

    test("opacity lets the layer below through", () async {
      var e = over(ImageLayer.solid(const PaintSpec(ui.Color(0xFF0000FF)))
          .copyWith(opacity: 0.5));
      var p = await _pixel(e, images, 50, 50);
      expect(p[0], closeTo(128, 3));
      expect(p[2], closeTo(128, 3));
    });

    test("a clipped layer shows only where the layer under it does", () async {
      var e =
          ImageElement(_box, assetId: "middle", fit: ImageFit.stretch, layers: [
        ImageLayer.base,
        ImageLayer.solid(const PaintSpec(ui.Color(0xFF00FF00)))
            .copyWith(clip: true),
      ]);
      expect((await _pixel(e, images, 50, 50)).sublist(0, 3), [0, 255, 0],
          reason: "over the cut-out");
      var outside = await _pixel(e, images, 10, 10);
      expect(outside[1], lessThan(100),
          reason: "and not over the hole round it");
    });

    test("a clipped layer keeps its own blend mode", () async {
      // Red, multiplied, over the white middle: red there, and still
      // nothing round it.
      var e =
          ImageElement(_box, assetId: "middle", fit: ImageFit.stretch, layers: [
        ImageLayer.base,
        ImageLayer.solid(const PaintSpec(ui.Color(0xFFFF0000)))
            .copyWith(clip: true, blend: LayerBlend.multiply),
      ]);
      expect((await _pixel(e, images, 50, 50)).sublist(0, 3), [255, 0, 0]);
      expect((await _pixel(e, images, 10, 10))[0], lessThan(100));
    });

    test("a layer blends with its picture, not with the canvas", () async {
      // Round the cut-out there is nothing in the picture, and a multiply
      // over nothing is the colour itself -- as it is in any editor. Blended
      // with the canvas instead, it would multiply into the dark page under
      // the element and come out nearly black.
      var e =
          ImageElement(_box, assetId: "middle", fit: ImageFit.stretch, layers: [
        ImageLayer.base,
        ImageLayer.solid(const PaintSpec(ui.Color(0xFF00FF00)))
            .copyWith(blend: LayerBlend.multiply),
      ]);
      var bare = await _pixel(
          const ImageElement(_box, assetId: "middle", fit: ImageFit.stretch),
          images,
          10,
          10);
      expect(bare[1], lessThan(100), reason: "the page is dark there");
      expect((await _pixel(e, images, 10, 10)).sublist(0, 3), [0, 255, 0]);
    });

    test("a flipped layer is mirrored in its place", () async {
      var flat = over(ImageLayer.picture(
          "halves", const Rect.fromLTWH(0, 0, layerUnits, layerUnits)));
      expect((await _pixel(flat, images, 20, 50)).sublist(0, 3), [255, 0, 0]);
      var flipped = over(ImageLayer.picture(
              "halves", const Rect.fromLTWH(0, 0, layerUnits, layerUnits))
          .copyWith(flipX: true));
      expect(
          (await _pixel(flipped, images, 20, 50)).sublist(0, 3), [0, 255, 0]);
    });

    test("a turned layer turns about its own middle", () async {
      // A wide strip across the middle, turned a quarter, stands up.
      var e = over(ImageLayer.picture(
              "blue", const Rect.fromLTWH(0, 400, layerUnits, 200))
          .placed(const Rect.fromLTWH(0, 400, layerUnits, 200), turn: 90));
      expect((await _pixel(e, images, 50, 10)).sublist(0, 3), [0, 0, 255]);
      expect((await _pixel(e, images, 10, 50)).sublist(0, 3), [255, 0, 0]);
    });

    test("layers over an empty base still draw", () async {
      var e = ImageElement(_box, layers: [
        ImageLayer.base,
        ImageLayer.picture("blue", const Rect.fromLTWH(0, 0, 500, 500)),
      ]);
      expect((await _pixel(e, images, 25, 25)).sublist(0, 3), [0, 0, 255]);
    });
  });

  group("placing", () {
    test("frame and layer units are each other's inverse", () {
      const inner = Rect.fromLTWH(20, 40, 200, 100);
      const rect = Rect.fromLTWH(70, 65, 50, 25);
      var place = layerPlace(inner, rect);
      expect(place, const Rect.fromLTWH(250, 250, 250, 250));
      expect(layerRect(inner, place), rect);
    });

    test("a new picture arrives whole, in the middle, in its proportions", () {
      const inner = Rect.fromLTWH(0, 0, 300, 300);
      var place = placeFor(inner, const Size(400, 200));
      var rect = layerRect(inner, place);
      expect(rect.width / rect.height, closeTo(2, 1e-9));
      expect(rect.center, inner.center);
      expect(rect.width, closeTo(200, 1e-9));
    });

    test("the topmost shown picture under a point is the one picked", () {
      var low = ImageLayer.picture("a", const Rect.fromLTWH(0, 0, 600, 600));
      var high =
          ImageLayer.picture("b", const Rect.fromLTWH(400, 400, 600, 600));
      var e = ImageElement(_box, layers: [ImageLayer.base, low, high]);
      expect(layerAt(e, const Offset(50, 50)).id, high.id);
      expect(layerAt(e, const Offset(20, 20)).id, low.id);
      expect(layerAt(e, const Offset(90, 10)).isBase, isTrue);
      var hidden = e.withLayer(high.id, (l) => l.copyWith(visible: false));
      expect(layerAt(hidden, const Offset(50, 50)).id, low.id);
    });

    test("resizing a turned layer in a turned element keeps the far corner",
        () {
      var layer =
          ImageLayer.picture("a", const Rect.fromLTWH(250, 250, 500, 500))
              .placed(const Rect.fromLTWH(250, 250, 500, 500), turn: 30);
      var e = ImageElement(
          const ElementBase(
              id: "i", x: 0, y: 0, width: 100, height: 100, rotation: 20),
          layers: [ImageLayer.base, layer]);
      var space = LayerSpace(e, layer);
      var far = space.corners[0];
      // The bottom-right corner, pulled out.
      var to = space.corners[2] + const Offset(10, 5);
      var rect = space.resized(to, 2, (r, h, p) => boxResized(r, h, p));
      var next = e.withLayer(layer.id,
          (l) => l.placed(layerPlace(space.inner, rect), turn: l.turn));
      var after = LayerSpace(next, next.layerById(layer.id)!);
      expect((after.corners[0] - far).distance, lessThan(1e-6));
      expect((after.corners[2] - to).distance, lessThan(1e-6));
    });

    test("a layer turned to a point faces it", () {
      var layer =
          ImageLayer.picture("a", const Rect.fromLTWH(0, 0, 1000, 1000));
      var e = ImageElement(_box, layers: [ImageLayer.base, layer]);
      var space = LayerSpace(e, layer);
      expect(space.turnTo(const Offset(50, 0)), closeTo(0, 1e-9));
      expect(space.turnTo(const Offset(100, 50)), closeTo(90, 1e-9));
    });
  });
}
