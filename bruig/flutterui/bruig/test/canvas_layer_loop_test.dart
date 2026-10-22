import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/render/image_silhouette.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_layer_loop_test.dart is a picture's layers looping on their own,
// and the picture drifting as a whole: a drift moves and grows the box, not
// the picture inside it; and an adjustment over layers that move is worked
// into each, so it goes where they go.

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

Future<ui.Image> _solid(List<int> rgba) {
  var pixels = Uint8List(4 * 4 * 4);
  for (var i = 0; i < 16; i++) {
    pixels.setRange(i * 4, i * 4 + 4, rgba);
  }
  var done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      pixels, 4, 4, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

/// _zoom is a drift in, twice as close by its end.
const _zoom =
    ElementLoop(preset: LoopPreset.driftIn, strength: 1 / driftPerStrength);

void main() {
  late _Pictures images;
  setUpAll(() async {
    images = _Pictures({
      "red": await _solid([255, 0, 0, 255]),
      "blue": await _solid([0, 0, 255, 255]),
    });
  });

  Future<List<int>> pixel(ImageElement e, int frame, int x, int y) async {
    var document = CanvasDocument(
        size: const CanvasSize(width: 100, ratio: CanvasRatio.square),
        frames: 11,
        elements: [e]);
    var image = await renderFrame(document, images: images, frame: frame);
    try {
      var raw =
          await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      var p = raw!.buffer.asUint8List();
      var i = (y * image.width + x) * 4;
      return [p[i], p[i + 1], p[i + 2]];
    } finally {
      image.dispose();
    }
  }

  /// picture is red, with a blue layer over its middle -- (40..60) on the
  /// page -- looping as [loop] says.
  ImageElement picture(
          {ElementLoop loop = const ElementLoop(),
          ElementAnimation animation = const ElementAnimation(),
          List<ImageLayer> over = const []}) =>
      ImageElement(const ElementBase(id: "i", width: 100, height: 100),
          assetId: "red",
          fit: ImageFit.stretch,
          animation: animation,
          layers: [
            ImageLayer.base,
            ImageLayer.picture("blue", const Rect.fromLTWH(400, 400, 200, 200))
                .copyWith(id: "b", loop: loop),
            ...over,
          ]);

  test("a layer's drift grows its box, not the picture inside it", () async {
    var e = picture(loop: _zoom);
    expect(await pixel(e, 0, 50, 50), [0, 0, 255]);
    expect(await pixel(e, 0, 35, 50), [255, 0, 0], reason: "its box at first");
    // By the end, twice the size about its middle: 30..70.
    expect(await pixel(e, 10, 35, 50), [0, 0, 255],
        reason: "the box itself has grown");
    expect(await pixel(e, 10, 20, 50), [255, 0, 0]);
  });

  test("the picture's own drift moves every layer as one", () async {
    var e = picture(animation: const ElementAnimation(loop: _zoom));
    // Twice as close about the frame's middle: the blue middle now 30..70.
    expect(await pixel(e, 10, 35, 50), [0, 0, 255]);
  });

  test("an adjustment over a looping layer is worked into it", () async {
    var invert = ImageLayer.adjusting(AdjustKind.invert).copyWith(id: "invert");
    var e = picture(loop: _zoom, over: [invert]);
    // Red turned cyan, blue turned yellow -- the blue where its drift has
    // carried it, adjusted there.
    expect(await pixel(e, 10, 10, 50), [0, 255, 255], reason: "the base");
    expect(await pixel(e, 10, 35, 50), [255, 255, 0],
        reason: "the layer, grown, adjusted as it goes");
  });

  test("a layer's loop is kept", () {
    var e = picture(loop: _zoom);
    var back = elementFromJson(e.toJson()) as ImageElement;
    expect(back.layerById("b")!.loop.preset, LoopPreset.driftIn);
  });

  test("a drift is drawn between frames while the editor plays", () async {
    // How much blue there is along the middle row: its drift in widens it.
    Future<int> blueFrom(int frame, double between) async {
      var document = CanvasDocument(
          size: const CanvasSize(width: 100, ratio: CanvasRatio.square),
          frames: 11,
          elements: [picture(loop: _zoom)]);
      betweenFrames = between;
      var image = await renderFrame(document, images: images, frame: frame);
      betweenFrames = 0;
      try {
        var raw =
            await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        var p = raw!.buffer.asUint8List();
        var blue = 0;
        for (var x = 0; x < image.width; x++) {
          blue += p[(50 * image.width + x) * 4 + 2];
        }
        return blue;
      } finally {
        image.dispose();
      }
    }

    var on4 = await blueFrom(4, 0), on5 = await blueFrom(5, 0);
    var half = await blueFrom(4, 0.5);
    expect(on5, greaterThan(on4), reason: "it grows frame by frame");
    expect(half, greaterThan(on4), reason: "half a frame on, it has grown");
    expect(half, lessThan(on5), reason: "but not a whole frame's worth");
  });

  test("driftAt takes a time between frames", () {
    var at4 = _zoom.driftAt(4, last: 10)!, at5 = _zoom.driftAt(5, last: 10)!;
    var half = _zoom.driftAt(4.5, last: 10)!;
    expect(half, greaterThan(at4));
    expect(half, lessThan(at5));
  });
}
