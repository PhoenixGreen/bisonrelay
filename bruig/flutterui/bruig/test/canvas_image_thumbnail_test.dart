import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/render/image_store.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_image_thumbnail_test.dart is the small copy of a picture the tiles
// and the layer thumbnails draw, rather than the whole decoded picture.

ui.Image _picture(int width, int height) {
  var r = ui.PictureRecorder();
  ui.Canvas(r).drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFFCC3322));
  return r.endRecording().toImageSync(width, height);
}

void main() {
  test("a big picture's thumbnail is small, its shape, and made once", () {
    var store = CanvasImageStore();
    addTearDown(store.dispose);
    var big = _picture(2000, 1000);
    store.putForTest("big", big);
    var thumb = store.thumbnail(big);
    expect(thumb.width, lessThanOrEqualTo(256));
    expect(thumb.width / thumb.height, closeTo(2, 0.05));
    expect(identical(store.thumbnail(big), thumb), isTrue,
        reason: "kept, not made again for every tile");
  });

  test("a small picture, or one not the store's, is its own thumbnail", () {
    var store = CanvasImageStore();
    addTearDown(store.dispose);
    var small = _picture(100, 80);
    store.putForTest("small", small);
    expect(identical(store.thumbnail(small), small), isTrue);
    var stranger = _picture(1500, 1500);
    addTearDown(stranger.dispose);
    expect(identical(store.thumbnail(stranger), stranger), isTrue,
        reason: "nothing would know when to let a copy of it go");
  });

  test("forgotten, a picture's thumbnail goes with it", () {
    var store = CanvasImageStore();
    addTearDown(store.dispose);
    var big = _picture(1200, 1200);
    store.putForTest("aaaaaaaaaaaaaaaa", big);
    var thumb = store.thumbnail(big);
    store.forget("aaaaaaaaaaaaaaaa");
    expect(thumb.debugDisposed, isTrue);
  });
}
