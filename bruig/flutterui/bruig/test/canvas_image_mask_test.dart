import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_mask.dart';
import 'package:bruig/plugin_system/canvas/render/image_silhouette.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/image_masking.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_image_mask_test.dart is a picture's mask: saved as a recipe, and
// drawn -- a subject, marks over it, its edge refined -- through the same
// placement as the picture.

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
    test("no mask is not written", () {
      expect(const ImageElement(_box, assetId: "red").props()["mask"], isNull);
    });

    test("a mask comes back as it was", () {
      var mask = const ImageMask(
        subject: "abcdefabcdef0123.mask",
        marks: [
          MaskMark(
              kind: MaskMarkKind.brush,
              points: [Offset(0.1, 0.2), Offset(0.3, 0.4)],
              pressure: [0.5, 1],
              radius: 0.05,
              hardness: 0.2,
              strength: 0.7),
          MaskMark(
              kind: MaskMarkKind.lasso,
              hide: false,
              points: [Offset(0, 0), Offset(1, 0), Offset(1, 1)]),
          MaskMark(
              kind: MaskMarkKind.fade,
              radial: true,
              points: [Offset(0.5, 0.5), Offset(1, 0.5)]),
        ],
        refine: MaskRefine(
            shift: -2,
            smooth: 3,
            feather: 4,
            contrast: 0.5,
            decontaminate: 0.8),
        invert: true,
        on: false,
      );
      var e = ImageElement(_box, assetId: "red", mask: mask);
      var back = (elementFromJson(e.toJson()) as ImageElement).mask;
      expect(back.subject, mask.subject);
      expect(back.marks.length, 3);
      var brush = back.marks[0];
      expect(brush.kind, MaskMarkKind.brush);
      expect(brush.points, mask.marks[0].points);
      expect(brush.pressure, [0.5, 1]);
      expect(brush.radius, 0.05);
      expect(brush.hardness, 0.2);
      expect(brush.strength, 0.7);
      expect(brush.hide, isTrue);
      expect(back.marks[1].hide, isFalse);
      expect(back.marks[2].radial, isTrue);
      expect(back.refine.shift, -2);
      expect(back.refine.smooth, 3);
      expect(back.refine.feather, 4);
      expect(back.refine.contrast, 0.5);
      expect(back.refine.decontaminate, 0.8);
      expect(back.invert, isTrue);
      expect(back.on, isFalse);
      expect(e.assetIds, contains("abcdefabcdef0123.mask"),
          reason: "the subject is kept as the picture is");
    });
  });

  group("drawing", () {
    late ui.Image red, halfMask, middleMask;
    late _Pictures images;
    setUpAll(() async {
      red = await _picture(20, 20, (x, y) => [255, 0, 0, 255]);
      // White on the left half, black on the right: a subject's mask.
      halfMask = await _picture(
          20, 20, (x, y) => x < 10 ? [255, 255, 255, 255] : [0, 0, 0, 255]);
      // A white square in the middle.
      middleMask = await _picture(
          20,
          20,
          (x, y) => x >= 6 && x < 14 && y >= 6 && y < 14
              ? [255, 255, 255, 255]
              : [0, 0, 0, 255]);
      images = _Pictures({
        "red": red,
        "half.mask": halfMask,
        "middle.mask": middleMask,
      });
    });

    Future<List<int>> pixel(ImageElement e, int x, int y) async {
      var document = CanvasDocument(
          size: const CanvasSize(width: 100, ratio: CanvasRatio.square),
          elements: [e]);
      var image = await renderFrame(document, images: images);
      try {
        var raw =
            await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        var p = raw!.buffer.asUint8List();
        var i = (y * image.width + x) * 4;
        return [p[i], p[i + 1], p[i + 2], p[i + 3]];
      } finally {
        image.dispose();
      }
    }

    bool isRed(List<int> p) => p[0] > 200 && p[1] < 60;
    bool isPage(List<int> p) => p[0] < 80;

    ImageElement masked(ImageMask mask, {ImageCrop crop = const ImageCrop()}) =>
        ImageElement(_box,
            assetId: "red", fit: ImageFit.stretch, crop: crop, mask: mask);

    test("a subject keeps what is white in it", () async {
      var e = masked(const ImageMask(subject: "half.mask"));
      expect(isRed(await pixel(e, 25, 50)), isTrue);
      expect(isPage(await pixel(e, 75, 50)), isTrue);
    });

    test("inverted, it keeps the rest", () async {
      var e = masked(const ImageMask(subject: "half.mask", invert: true));
      expect(isPage(await pixel(e, 25, 50)), isTrue);
      expect(isRed(await pixel(e, 75, 50)), isTrue);
    });

    test("switched off, the picture is whole", () async {
      var e = masked(const ImageMask(subject: "half.mask", on: false));
      expect(isRed(await pixel(e, 75, 50)), isTrue);
    });

    test("a lasso takes away what it goes round", () async {
      var e = masked(const ImageMask(marks: [
        MaskMark(kind: MaskMarkKind.lasso, points: [
          Offset(0, 0),
          Offset(0.5, 0),
          Offset(0.5, 1),
          Offset(0, 1)
        ])
      ]));
      expect(isPage(await pixel(e, 25, 50)), isTrue);
      expect(isRed(await pixel(e, 75, 50)), isTrue);
    });

    test("a brush hides where it goes, and another puts it back", () async {
      var hidden = const MaskMark(
          kind: MaskMarkKind.brush,
          points: [Offset(0.2, 0.5), Offset(0.8, 0.5)],
          radius: 0.1,
          hardness: 1);
      var e = masked(ImageMask(marks: [hidden]));
      expect(isPage(await pixel(e, 50, 50)), isTrue);
      expect(isRed(await pixel(e, 50, 10)), isTrue, reason: "only there");

      var back = masked(ImageMask(marks: [
        hidden,
        const MaskMark(
            kind: MaskMarkKind.brush,
            hide: false,
            points: [Offset(0.5, 0.5)],
            radius: 0.1,
            hardness: 1),
      ]));
      expect(isRed(await pixel(back, 50, 50)), isTrue);
      expect(isPage(await pixel(back, 25, 50)), isTrue);
    });

    test("a lighter press paints a thinner line", () async {
      var e = masked(const ImageMask(marks: [
        MaskMark(
            kind: MaskMarkKind.brush,
            points: [Offset(0.1, 0.5), Offset(0.9, 0.5)],
            pressure: [0.1, 0.1],
            radius: 0.2,
            hardness: 1),
      ]));
      // Full pressure reaches 20 units either side; this one about 6.
      expect(isPage(await pixel(e, 50, 50)), isTrue);
      expect(isRed(await pixel(e, 50, 35)), isTrue);
    });

    test("a fade hides one end and keeps the other", () async {
      var e = masked(const ImageMask(marks: [
        MaskMark(kind: MaskMarkKind.fade, points: [Offset(0, 0), Offset(1, 0)])
      ]));
      var left = await pixel(e, 5, 50), right = await pixel(e, 95, 50);
      var middle = await pixel(e, 50, 50);
      expect(isPage(left), isTrue);
      expect(isRed(right), isTrue);
      expect(middle[0], inInclusiveRange(left[0] + 30, right[0] - 30),
          reason: "and fades between");
    });

    test("a radial fade keeps the middle and hides the corners", () async {
      var e = masked(const ImageMask(marks: [
        MaskMark(
            kind: MaskMarkKind.fade,
            radial: true,
            points: [Offset(0.5, 0.5), Offset(0.9, 0.5)])
      ]));
      expect(isRed(await pixel(e, 50, 50)), isTrue);
      expect(isPage(await pixel(e, 3, 3)), isTrue);
    });

    test("shifting the edge out gives back a rim", () async {
      var plain = masked(const ImageMask(subject: "middle.mask"));
      // The square is 30..70 across; 26 is outside it.
      expect(isPage(await pixel(plain, 26, 50)), isTrue);
      var shifted = masked(const ImageMask(
          subject: "middle.mask", refine: MaskRefine(shift: 2)));
      // Two of the picture's pixels is ten canvas units here.
      expect(isRed(await pixel(shifted, 26, 50)), isTrue);
      var shrunk = masked(const ImageMask(
          subject: "middle.mask", refine: MaskRefine(shift: -2)));
      expect(isPage(await pixel(shrunk, 34, 50)), isTrue);
    });

    test("feathering softens the edge", () async {
      var e = masked(const ImageMask(
          subject: "middle.mask", refine: MaskRefine(feather: 4)));
      var edge = await pixel(e, 30, 50);
      expect(edge[0], inInclusiveRange(60, 220),
          reason: "half-way at the edge");
    });

    test("the outline traces what the mask leaves", () async {
      var e = masked(const ImageMask(subject: "half.mask")).copyWith(
          outline: const ImageOutline(width: 6, color: ui.Color(0xFF00FF00)));
      var beside = await pixel(e, 53, 50);
      expect(beside[1], greaterThan(200), reason: "green just past the mask");
      expect(isPage(await pixel(e, 80, 50)), isTrue);
    });

    test("the mask follows the picture when it is cropped", () async {
      // The right half of the picture shown, and the picture's own right
      // quarter hidden: the element's right half goes.
      var e = masked(
          const ImageMask(marks: [
            MaskMark(kind: MaskMarkKind.lasso, points: [
              Offset(0.75, 0),
              Offset(1, 0),
              Offset(1, 1),
              Offset(0.75, 1)
            ])
          ]),
          crop: const ImageCrop(left: 0.5));
      expect(isRed(await pixel(e, 25, 50)), isTrue);
      expect(isPage(await pixel(e, 75, 50)), isTrue);
    });

    test("a picture layer has a mask of its own", () async {
      var layer =
          ImageLayer.picture("red", const Rect.fromLTWH(0, 0, 1000, 1000));
      layer = layer.copyWith(
          look: layer.look!
              .copyWith(mask: const ImageMask(subject: "half.mask")));
      var e = ImageElement(_box, layers: [ImageLayer.base, layer]);
      expect(isRed(await pixel(e, 25, 50)), isTrue);
      expect(isPage(await pixel(e, 75, 50)), isTrue);
    });
  });

  group("quick select", () {
    late ui.Image disc;
    setUpAll(() async {
      // A red disc in the middle of blue, a little noisy.
      disc = await _picture(120, 120, (x, y) {
        var d = (Offset(x + 0.5, y + 0.5) - const Offset(60, 60)).distance;
        var n = (x * 7 + y * 13) % 11 - 5;
        return d < 30 ? [200 + n, 40, 40, 255] : [40, 60 + n, 200, 255];
      });
    });

    test("a stroke on a fresh picture keeps what it went over, and its like",
        () async {
      var png = await quickSelectMask(disc, const ImageMask(), null,
          const [Offset(0.45, 0.5), Offset(0.55, 0.5)], 0.03,
          subtract: false);
      expect(await _maskAt(png!, 0.5, 0.5), greaterThan(200));
      expect(await _maskAt(png, 0.5, 0.29), greaterThan(200),
          reason: "the disc's own edge, well away from the stroke");
      expect(await _maskAt(png, 0.1, 0.1), lessThan(50),
          reason: "and nothing of the blue");
    });

    test("taking away removes what was brushed from what was kept", () async {
      // Everything kept to begin with -- a mask that is only inverted
      // nothing is everything shown -- then the disc taken away.
      var png = await quickSelectMask(
          disc,
          const ImageMask(marks: [
            MaskMark(kind: MaskMarkKind.lasso, hide: false, points: [
              Offset(0, 0),
              Offset(1, 0),
              Offset(1, 1),
              Offset(0, 1)
            ])
          ]),
          null,
          const [Offset(0.5, 0.5)],
          0.04,
          subtract: true);
      expect(await _maskAt(png!, 0.5, 0.5), lessThan(50));
      expect(await _maskAt(png, 0.1, 0.1), greaterThan(200));
    });

    test("without the system's finder, a subject is still guessed", () async {
      var png = await guessSubjectMask(disc);
      expect(await _maskAt(png!, 0.5, 0.5), greaterThan(200));
      expect(await _maskAt(png, 0.05, 0.05), lessThan(50));
    });
  });
}

/// _readMask decodes a mask PNG and reads its grey at fractions [x], [y].
Future<int> _maskAt(Uint8List png, double x, double y) async {
  var codec = await ui.instantiateImageCodec(png);
  var image = (await codec.getNextFrame()).image;
  var raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  var px = (x * image.width).floor().clamp(0, image.width - 1);
  var py = (y * image.height).floor().clamp(0, image.height - 1);
  return raw!.getUint8((py * image.width + px) * 4);
}
