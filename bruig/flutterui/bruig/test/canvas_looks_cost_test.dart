import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/render/motion_looks.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_looks_cost_test.dart is an element's looks drawing it once each,
// not twice for every look to its left (Ken's systems review, 2026-11-08:
// three of them drew it eight times).

void main() {
  test("a shadow, a glow and an outline draw the element once", () async {
    var drawn = 0;
    var rec = ui.PictureRecorder();
    var canvas = ui.Canvas(rec);
    canvas.scale(2);
    const box = Rect.fromLTWH(40, 40, 40, 40);
    paintWithLooks(canvas, box, const [
      MotionDevice(MotionDeviceKind.shadow, id: "s"),
      MotionDevice(MotionDeviceKind.glow, id: "g"),
      MotionDevice(MotionDeviceKind.outline, id: "o", values: {"width": 3}),
    ], (on) {
      drawn++;
      on.drawRect(box, Paint()..color = const Color(0xFF2060FF));
    });
    expect(drawn, 1);
    // And still drawn where it is, at the scale it is seen: its middle the
    // element's own blue, over its looks.
    var img = await rec.endRecording().toImage(240, 240);
    var px = (await img.toByteData())!.buffer.asUint8List();
    var at = (120 * 240 + 120) * 4;
    expect((px[at], px[at + 1], px[at + 2]), (0x20, 0x60, 0xFF));
    var shadowed = (175 * 240 + 120) * 4;
    expect(px[shadowed + 3], greaterThan(0), reason: "its shadow below it");
  });
}
