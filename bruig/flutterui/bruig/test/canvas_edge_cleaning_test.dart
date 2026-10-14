import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_mask.dart';
import 'package:bruig/plugin_system/canvas/render/image_store.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_edge_cleaning_test.dart is the picture store handing back a picture
// with its edge colours cleaned, as a mask asks -- worked out off the main
// thread, so not at once, and kept once it is.

Future<ui.Image> _picture() {
  // Pale on the left, green on the right: a subject cut from a pitch.
  var pixels = Uint8List(40 * 20 * 4);
  for (var y = 0; y < 20; y++) {
    for (var x = 0; x < 40; x++) {
      var i = (y * 40 + x) * 4;
      var a = ((25 - x) / 10).clamp(0.0, 1.0);
      pixels[i] = (240 * a + 20 * (1 - a)).round();
      pixels[i + 1] = (220 * a + 160 * (1 - a)).round();
      pixels[i + 2] = (180 * a + 30 * (1 - a)).round();
      pixels[i + 3] = 255;
    }
  }
  var done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      pixels, 40, 20, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

void main() {
  test("a cleaned picture comes later, is kept, and is cleaner", () async {
    var store = CanvasImageStore();
    addTearDown(store.dispose);
    var picture = await _picture();
    store.putForTest("cleancleanclean1", picture);
    var look = ImageElement(const ElementBase(id: ""),
        assetId: "cleancleanclean1",
        mask: const ImageMask(
            marks: [
              MaskMark(
                  kind: MaskMarkKind.fade,
                  points: [Offset(0.375, 0.5), Offset(0.625, 0.5)])
            ],
            invert: true,
            refine: MaskRefine(decontaminate: 1)));
    // Inverted, the fade keeps the left: hidden on the right, as the green.
    look = look.copyWith(
        mask: look.mask.copyWith(invert: false, marks: [
      const MaskMark(
          kind: MaskMarkKind.fade,
          points: [Offset(0.625, 0.5), Offset(0.375, 0.5)])
    ]));
    expect(store.cleaned(look, picture), isNull, reason: "not at once");
    expect(store.loading, isTrue, reason: "an export waits for it");
    for (var i = 0; i < 100 && store.cleaned(look, picture) == null; i++) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    var cleaned = store.cleaned(look, picture);
    expect(cleaned, isNotNull);
    expect(store.loading, isFalse);

    Future<List<int>> at(ui.Image image, int x) async {
      var raw =
          (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
      var i = (10 * image.width + x) * 4;
      return [raw.getUint8(i), raw.getUint8(i + 1), raw.getUint8(i + 2)];
    }

    // Two thirds across the soft edge, where it is mostly hidden: the red
    // that was dragged down by the pitch is the subject's again.
    var before = await at(picture, 22), after = await at(cleaned!, 22);
    expect(after[0], greaterThan(before[0] + 30));
    // Well inside the subject, nothing moves.
    expect(await at(cleaned, 2), await at(picture, 2));
  });
}
