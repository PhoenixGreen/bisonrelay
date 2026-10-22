import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_strokes.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_image_frame_test.dart is a picture's frame as an artboard: sized,
// it is sized round its layers rather than stretching them -- unless it is
// told to scale its content -- and the base picture has a place of its own
// in it.

final _layer =
    ImageLayer.picture("aaaaaaaaaaaaaaa1", const Rect.fromLTWH(0, 0, 500, 500));

ImageElement _element({bool scale = false}) => ImageElement(
      const ElementBase(id: "i", x: 100, y: 100, width: 200, height: 200),
      assetId: "basebasebasebase",
      layers: [ImageLayer.base, _layer],
      scaleContent: scale,
    );

/// onPage is where a layer of [e] is on the page.
Rect onPage(ImageElement e, String id) =>
    layerRect(e.box.inner(e.bounds), e.layerById(id)!.place);

class _Pictures extends CanvasImageSource {
  final Map<String, ui.Image> images;
  _Pictures(this.images);
  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) =>
      images[assetId];
}

void main() {
  group("resizing the frame", () {
    test("keeps every layer its size, where it is on the page", () {
      var e = _element();
      var picture = onPage(e, _layer.id), base = onPage(e, baseLayerId);
      var wider = e.withBase(width: 400) as ImageElement;
      expect(onPage(wider, _layer.id), picture);
      expect(onPage(wider, baseLayerId), base,
          reason: "the base picture too: the frame grew round it");
    });

    test("from the left edge as well as the right", () {
      var e = _element();
      var picture = onPage(e, _layer.id);
      var grown = e.withBase(x: 50, width: 250) as ImageElement;
      var at = onPage(grown, _layer.id);
      expect(at.left, closeTo(picture.left, 1e-9));
      expect(at.width, closeTo(picture.width, 1e-9));
    });

    test("scales everything with it when told to", () {
      var e = _element(scale: true);
      var wider = e.withBase(width: 400) as ImageElement;
      expect(wider.layerById(_layer.id)!.place, _layer.place,
          reason: "the same share of a bigger frame");
      expect(onPage(wider, _layer.id).width, 200);
    });

    test("moved without a change of size, the layers go with it", () {
      var e = _element();
      var moved = e.withBase(x: 160) as ImageElement;
      expect(moved.layerById(_layer.id)!.place, _layer.place);
      expect(onPage(moved, _layer.id).left, 160);
    });

    test("a picture with no layers is its picture, filling its frame", () {
      var plain = const ImageElement(
          ElementBase(id: "p", x: 0, y: 0, width: 200, height: 200),
          assetId: "basebasebasebase");
      var wider = plain.withBase(width: 400) as ImageElement;
      expect(wider.layered, isFalse);
      expect(onPage(wider, baseLayerId).width, 400);
    });

    test("paint stays where it was painted", () {
      var e = _element().withLayers([
        ImageLayer.base,
        const ImageLayer(id: "paint", kind: LayerKind.paint, strokes: [
          StrokeMark(
              kind: StrokeKind.paint, points: [Offset(0.5, 0.5)], radius: 0.05),
        ]),
      ]);
      var wider = e.withBase(width: 400) as ImageElement;
      var s = wider.layerById("paint")!.strokes.single;
      // The middle of the old frame, 200 across from its left, is a quarter
      // of the way across the new one.
      expect(s.points.single.dx, closeTo(0.25, 1e-9));
      expect(s.points.single.dy, closeTo(0.5, 1e-9));
      expect(s.radius, closeTo(0.05, 1e-9),
          reason: "the shorter side did not change");
    });
  });

  group("the base picture's own place", () {
    test("comes back as it was saved", () {
      var e = _element().withLayer(baseLayerId,
          (l) => l.copyWith(basePlace: const Rect.fromLTWH(0, 0, 500, 1000)));
      var back = elementFromJson(e.toJson()) as ImageElement;
      expect(back.layerById(baseLayerId)!.place,
          const Rect.fromLTWH(0, 0, 500, 1000));
    });

    test("a new picture in the base fills its frame again", () {
      var e = _element().withLayer(baseLayerId,
          (l) => l.copyWith(basePlace: const Rect.fromLTWH(0, 0, 500, 1000)));
      var fitted = fitToPicture(e, const Size(400, 200));
      expect(fitted.layerById(baseLayerId)!.place,
          const Rect.fromLTWH(0, 0, layerUnits, layerUnits));
    });

    test("is where it is drawn", () async {
      Future<ui.Image> solid(List<int> rgba) async {
        var pixels = Uint8List(4 * 4 * 4);
        for (var i = 0; i < 16; i++) {
          pixels.setRange(i * 4, i * 4 + 4, rgba);
        }
        var done = ui.ImmutableBuffer.fromUint8List(pixels);
        var desc = ui.ImageDescriptor.raw(await done,
            width: 4, height: 4, pixelFormat: ui.PixelFormat.rgba8888);
        var codec = await desc.instantiateCodec();
        return (await codec.getNextFrame()).image;
      }

      var images = _Pictures({
        "red": await solid([255, 0, 0, 255]),
        "blue": await solid([0, 0, 255, 255]),
      });
      // A blue layer over the right half, and the red base in the left
      // half only: nothing at all under the frame's top right.
      var e = ImageElement(
          const ElementBase(id: "i", x: 0, y: 0, width: 100, height: 100),
          assetId: "red",
          fit: ImageFit.stretch,
          layers: [
            const ImageLayer(
                id: baseLayerId,
                kind: LayerKind.base,
                basePlace: Rect.fromLTWH(0, 0, 500, 1000)),
            ImageLayer.picture("blue", const Rect.fromLTWH(500, 500, 500, 500))
                .copyWith(
                    look: const ImageElement(
                        ElementBase(
                            id: "b", x: 500, y: 500, width: 500, height: 500),
                        assetId: "blue",
                        fit: ImageFit.stretch)),
          ]);
      var document = CanvasDocument(
          size: const CanvasSize(width: 100, ratio: CanvasRatio.square),
          elements: [e]);
      var image = await renderFrame(document, images: images);
      var raw =
          (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!
              .buffer
              .asUint8List();
      List<int> at(int x, int y) {
        var i = (y * image.width + x) * 4;
        return [raw[i], raw[i + 1], raw[i + 2]];
      }

      expect(at(25, 50), [255, 0, 0], reason: "the base, in its half");
      expect(at(75, 75), [0, 0, 255], reason: "the layer");
      expect(at(75, 25), isNot([255, 0, 0]),
          reason: "the base does not reach past its place");
      image.dispose();
    });
  });
}
