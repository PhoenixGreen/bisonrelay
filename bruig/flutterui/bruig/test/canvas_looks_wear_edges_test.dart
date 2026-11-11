import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/render/layer_effects.dart';
import 'package:bruig/plugin_system/canvas/render/motion_looks.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_looks_wear_edges_test.dart is the two looks added for Ken's privacy
// video (2026-11-11): Wear, which eats an element away as worn ink is, and
// Edges, which fades it into what is under it. Both on any element, as the
// other looks are, so an icon, a slab or a picture can be printed into the
// page rather than laid on it.

const size = 200;

/// drawn is a solid red square the size of the picture, with [looks] on it.
Future<ByteData> drawn(List<MotionDevice> looks) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  var box = const Rect.fromLTWH(0, 0, 200, 200);
  paintWithLooks(canvas, box, looks,
      (on) => on.drawRect(box, Paint()..color = const Color(0xFFFF0000)));
  var image = await recorder.endRecording().toImage(size, size);
  var bytes = (await image.toByteData())!;
  image.dispose();
  return bytes;
}

int alphaAt(ByteData b, int x, int y) => b.getUint8((y * size + x) * 4 + 3);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(TextureShader.load);

  test("Wear takes marks out of it, more the more Amount", () async {
    int cleared(ByteData b) {
      var n = 0;
      for (var i = 0; i < size * size; i++) {
        if (b.getUint8(i * 4 + 3) < 128) n++;
      }
      return n;
    }

    var none = cleared(await drawn(const []));
    var light = cleared(await drawn(const [
      MotionDevice(MotionDeviceKind.wear, id: "w", values: {"amount": 0.25}),
    ]));
    var heavy = cleared(await drawn(const [
      MotionDevice(MotionDeviceKind.wear, id: "w", values: {"amount": 0.7}),
    ]));
    expect(none, 0);
    expect(light, greaterThan(0), reason: "worn: some of it gone");
    expect(light, lessThan(size * size ~/ 2), reason: "but most of it there");
    expect(heavy, greaterThan(light), reason: "more Amount, more worn");
  });

  test("Wear's dust and halftone wear it too; at nought it is untouched",
      () async {
    for (var texture in [1, 2]) {
      var b = await drawn([
        MotionDevice(MotionDeviceKind.wear,
            id: "w", values: {"texture": texture.toDouble(), "amount": 0.6}),
      ]);
      var gone = 0;
      for (var i = 0; i < size * size; i++) {
        if (b.getUint8(i * 4 + 3) < 128) gone++;
      }
      expect(gone, greaterThan(0), reason: "texture $texture");
    }
    var untouched = await drawn(const [
      MotionDevice(MotionDeviceKind.wear, id: "w", values: {"amount": 0}),
    ]);
    expect(alphaAt(untouched, 100, 100), 255);
  });

  test("Edges fades it to nothing at its edges, whole in the middle", () async {
    var b = await drawn(const [
      MotionDevice(MotionDeviceKind.edges,
          id: "e", values: {"feather": 0.2, "fade": 0}),
    ]);
    expect(alphaAt(b, 100, 100), greaterThan(240), reason: "the middle");
    expect(alphaAt(b, 1, 100), lessThan(60), reason: "the left edge");
    expect(alphaAt(b, 1, 1), lessThan(30), reason: "a corner");
  });

  test("Edges round the middle: an oval, gone by the rim", () async {
    var b = await drawn(const [
      MotionDevice(MotionDeviceKind.edges,
          id: "e", values: {"feather": 0, "fade": 7, "reach": 0.5}),
    ]);
    expect(alphaAt(b, 100, 100), greaterThan(240));
    expect(alphaAt(b, 100, 3), lessThan(40), reason: "near the rim, top");
    expect(alphaAt(b, 175, 100), lessThan(alphaAt(b, 130, 100)),
        reason: "fading outwards");
  });

  test("both are looks, offered with the others", () {
    expect(MotionDeviceKind.on(MotionDeviceSide.look),
        containsAll([MotionDeviceKind.wear, MotionDeviceKind.edges]));
  });
}
