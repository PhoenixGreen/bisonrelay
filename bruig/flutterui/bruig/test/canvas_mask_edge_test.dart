import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_mask.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_mask_edge_test.dart is a picture faded away to nothing by its mask
// leaving nothing behind at its edges. Drawn to the picture's edges, the
// half-covered pixel along each was a quarter left showing: a hairline round
// every faded picture placed inside its frame.

class _Pictures extends CanvasImageSource {
  final Map<String, ui.Image> images;
  _Pictures(this.images);
  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) =>
      images[assetId];
}

Future<ui.Image> _solid(List<int> rgba) async {
  var pixels = Uint8List(8 * 8 * 4);
  for (var i = 0; i < 64; i++) {
    pixels.setRange(i * 4, i * 4 + 4, rgba);
  }
  var desc = ui.ImageDescriptor.raw(
      await ui.ImmutableBuffer.fromUint8List(pixels),
      width: 8,
      height: 8,
      pixelFormat: ui.PixelFormat.rgba8888);
  return (await (await desc.instantiateCodec()).getNextFrame()).image;
}

void main() {
  test("a picture faded out to its rim leaves no line at its edges", () async {
    var images = _Pictures({
      "blue": await _solid([0, 0, 255, 255]),
      "red": await _solid([255, 0, 0, 255]),
    });
    // A red picture over a blue one, faded out well before its rim, and
    // placed at an odd fraction of a pixel so its edges fall between them.
    var layer =
        ImageLayer.picture("red", const Rect.fromLTWH(203.3, 207.7, 501, 499));
    layer = layer.copyWith(
        look: layer.look!.copyWith(
            mask: const ImageMask(marks: [
      MaskMark(
          kind: MaskMarkKind.fade,
          radial: true,
          points: [Offset(0.5, 0.5), Offset(0.5, 0.2)]),
    ])));
    var e = ImageElement(
        const ElementBase(id: "i", x: 0, y: 0, width: 200, height: 200),
        assetId: "blue",
        fit: ImageFit.stretch,
        layers: [ImageLayer.base, layer]);
    var doc = CanvasDocument(
        size: const CanvasSize(width: 200, ratio: CanvasRatio.square),
        elements: [e]);
    var image = await renderFrame(doc, images: images);
    var raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    // The picture's own rectangle, in pixels: 1000 layer units across the
    // 200-pixel frame.
    var r = const Rect.fromLTWH(203.3, 207.7, 501, 499);
    var left = r.left / 5,
        top = r.top / 5,
        right = r.right / 5,
        bottom = r.bottom / 5;
    bool nearEdge(int x, int y) =>
        y >= top - 2 &&
            y <= bottom + 2 &&
            ((x - left).abs() < 2 || (x - right).abs() < 2) ||
        x >= left - 2 &&
            x <= right + 2 &&
            ((y - top).abs() < 2 || (y - bottom).abs() < 2);
    var worst = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (!nearEdge(x, y)) continue;
        var red = raw[(y * image.width + x) * 4];
        if (red > worst) worst = red;
      }
    }
    expect(worst, lessThan(8),
        reason: "faded away well inside its rim, nothing of it at its edges");
    image.dispose();
  });
}
