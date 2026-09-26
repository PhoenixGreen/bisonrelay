import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/render/image_placement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_image_crop_test.dart is a crop behaving like a crop.
//
// It used to be taken off the picture *before* the fit, and covering then
// re-filled the frame with whatever was left -- so cropping the top of a
// picture that cover was already trimming moved the picture and took nothing
// away, which reads as a zoom. Reported as "the crop is no longer acting like
// a crop tool: moving a handle zooms and stretches the image".

void main() {
  const picture = Size(1000, 1000);

  test("a crop takes a share of what the frame is showing", () {
    // A wide frame on a square picture: cover is already trimming the top and
    // the bottom, which is the case the old order got wrong.
    var frame = const Rect.fromLTWH(0, 0, 400, 200);
    var before = placeImage(picture, frame, ImageFit.cover);
    expect(before.src.width, 1000, reason: "the full width is shown");
    expect(before.src.height, 500, reason: "and half the height");

    // A quarter off the top of what is shown, with the frame trimmed by the
    // same quarter -- which is what ImageElement.croppedTo does.
    var after = placeImage(
      picture,
      const Rect.fromLTWH(0, 0, 400, 150),
      ImageFit.cover,
      crop: const ImageCrop(top: 0.25),
    );

    expect(after.src.left, before.src.left, reason: "nothing moved sideways");
    expect(after.src.width, before.src.width);
    expect(after.src.top, closeTo(before.src.top + 125, 0.5),
        reason: "a quarter of the window is gone from the top");
    expect(after.src.height, closeTo(375, 0.5));
    // The picture that is left is drawn at exactly the scale it was, which is
    // what "it does not move" means.
    expect(after.dst.width / after.src.width,
        closeTo(before.dst.width / before.src.width, 0.001));
    expect(after.dst.height / after.src.height,
        closeTo(before.dst.height / before.src.height, 0.001));
  });

  test("and the window is what reframing moves, not what is left of it", () {
    var placed = placeImage(
      picture,
      const Rect.fromLTWH(0, 0, 400, 150),
      ImageFit.cover,
      crop: const ImageCrop(top: 0.25),
    );
    // The slack is what cover trimmed, and the crop is not slack: a part the
    // reader has taken off must not come back by dragging the rest about.
    expect(placed.window.height, closeTo(500, 0.5));
    expect(placed.slack.dy, closeTo(500, 0.5));
    expect(placed.slack.dx, 0);
  });

  test("the crop trims the frame so the rest stays put", () {
    // The model's half of it: the element's box comes in with the crop.
    var e = ImageElement(
      const ElementBase(id: "i", x: 100, y: 100, width: 400, height: 200),
      assetId: "a",
    );
    var cropped = e.croppedTo(const ImageCrop(top: 0.25));
    expect(cropped.height, 150, reason: "a quarter off the top");
    expect(cropped.y, 150, reason: "and the top edge came down to meet it");
    expect(cropped.x, 100, reason: "the other edges are where they were");
    expect(cropped.width, 400);
  });

  test("zoom takes a smaller window, which is what zooming in is", () {
    var frame = const Rect.fromLTWH(0, 0, 400, 200);
    var one = placeImage(picture, frame, ImageFit.cover);
    var two = placeImage(picture, frame, ImageFit.cover,
        framing: const ImageFraming(zoom: 2));

    expect(two.src.width, closeTo(one.src.width / 2, 0.5));
    expect(two.src.height, closeTo(one.src.height / 2, 0.5));
    expect(two.dst, one.dst, reason: "into the same frame, so twice the size");
  });

  test("and zoom works with a crop set as well", () {
    var one = placeImage(picture, const Rect.fromLTWH(0, 0, 400, 150),
        ImageFit.cover,
        crop: const ImageCrop(top: 0.25));
    var two = placeImage(picture, const Rect.fromLTWH(0, 0, 400, 150),
        ImageFit.cover,
        crop: const ImageCrop(top: 0.25),
        framing: const ImageFraming(zoom: 2));
    expect(two.src.width, closeTo(one.src.width / 2, 0.5));
  });

  test("a picture with no crop is placed exactly as it always was", () {
    var frame = const Rect.fromLTWH(0, 0, 400, 200);
    for (var fit in ImageFit.values) {
      var placed = placeImage(picture, frame, fit);
      expect(placed.src.width, greaterThan(0), reason: fit.name);
      expect(placed.window, placed.src,
          reason: "nothing cropped, so the window is what is drawn");
    }
    // Cover still fills the frame and centres what it trims.
    var cover = placeImage(picture, frame, ImageFit.cover);
    expect(cover.dst, frame);
    expect(cover.src.top, closeTo(250, 0.5));
  });
}
