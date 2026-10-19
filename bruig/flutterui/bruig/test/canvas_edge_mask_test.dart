import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/edge_mask.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/render/edge_mask_painter.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_edge_mask_test.dart is a video's or a pattern's box with its edges
// softened and faded: drawn, and read back pixel by pixel.

Future<Uint8List> _masked(EdgeMask mask) async {
  var recorder = ui.PictureRecorder();
  var canvas = Canvas(recorder);
  const box = Rect.fromLTWH(0, 0, 100, 100);
  paintEdgeMasked(canvas, box, mask,
      () => canvas.drawRect(box, Paint()..color = const Color(0xFFFF0000)));
  var image = await recorder.endRecording().toImage(100, 100);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!
        .buffer
        .asUint8List();
  } finally {
    image.dispose();
  }
}

int _alpha(Uint8List p, int x, int y) => p[(y * 100 + x) * 4 + 3];

void main() {
  test("no mask draws the box whole", () async {
    var p = await _masked(const EdgeMask());
    expect(_alpha(p, 0, 0), 255);
    expect(_alpha(p, 50, 50), 255);
  });

  test("soft edges fade out round the rim and keep the middle", () async {
    var p = await _masked(const EdgeMask(feather: 0.2));
    expect(_alpha(p, 50, 50), 255);
    expect(_alpha(p, 0, 50), lessThan(60));
    expect(_alpha(p, 0, 0), lessThan(30));
  });

  test("a fade from the left is gone at the left and whole past its reach",
      () async {
    var p = await _masked(const EdgeMask(fade: EdgeFade.left, reach: 0.5));
    expect(_alpha(p, 1, 50), lessThan(15));
    expect(_alpha(p, 25, 50), inInclusiveRange(100, 160));
    expect(_alpha(p, 75, 50), 255);
  });

  test("a fade round the middle keeps the middle and loses the corners",
      () async {
    var p = await _masked(const EdgeMask(fade: EdgeFade.middle, reach: 0.4));
    expect(_alpha(p, 50, 50), 255);
    expect(_alpha(p, 2, 2), 0);
  });

  test("a video's and a pattern's masks come back as they were", () {
    const mask = EdgeMask(feather: 0.1, fade: EdgeFade.topBottom, reach: 0.3);
    var video = const VideoElement(ElementBase(id: "v"), edges: mask);
    var back = elementFromJson(video.toJson()) as VideoElement;
    expect(back.edges.feather, 0.1);
    expect(back.edges.fade, EdgeFade.topBottom);
    expect(back.edges.reach, 0.3);
    var pattern = const BackgroundElement(ElementBase(id: "b"), mask: mask);
    var again = elementFromJson(pattern.toJson()) as BackgroundElement;
    expect(again.mask.fade, EdgeFade.topBottom);
    expect(
        (elementFromJson(const BackgroundElement(ElementBase(id: "c")).toJson())
                as BackgroundElement)
            .mask
            .on,
        isFalse);
  });
}
