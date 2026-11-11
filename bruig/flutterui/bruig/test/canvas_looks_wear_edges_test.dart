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

  test("all three are looks, offered with the others", () {
    expect(
        MotionDeviceKind.on(MotionDeviceSide.look),
        containsAll([
          MotionDeviceKind.wear,
          MotionDeviceKind.edges,
          MotionDeviceKind.lens
        ]));
  });

  // A ledger read through a magnifying glass that goes round over it (Ken's
  // privacy video, 2026-11-11).
  group("Lens", () {
    /// stripes is the box striped in 4 px bars of red and nothing, a
    /// period of 8, under a Lens at [time].
    Future<ByteData> stripes(MotionDevice lens, {double time = 0}) async {
      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      var box = const Rect.fromLTWH(0, 0, 200, 200);
      paintWithLooks(canvas, box, [lens], (on) {
        for (var x = 0.0; x < 200; x += 8) {
          on.drawRect(Rect.fromLTWH(x, 0, 4, 200),
              Paint()..color = const Color(0xFFFF0000));
        }
      }, time: time);
      var image = await recorder.endRecording().toImage(size, size);
      var bytes = (await image.toByteData())!;
      image.dispose();
      return bytes;
    }

    /// period is how far apart the red bars are along row [y], from [x0]
    /// to [x1].
    double period(ByteData b, int y, int x0, int x1) {
      var starts = <int>[];
      var was = false;
      for (var x = x0; x < x1; x++) {
        var red = b.getUint8((y * size + x) * 4) > 128 &&
            b.getUint8((y * size + x) * 4 + 3) > 128;
        if (red && !was) starts.add(x);
        was = red;
      }
      if (starts.length < 2) return 0;
      return (starts.last - starts.first) / (starts.length - 1);
    }

    test("what is under the glass is drawn bigger; the rest as it is",
        () async {
      var b = await stripes(const MotionDevice(MotionDeviceKind.lens,
          id: "l",
          values: {"size": 0.6, "zoom": 2, "orbit": 0, "x": 0.5, "y": 0.5}));
      expect(period(b, 100, 70, 130), closeTo(16, 1),
          reason: "inside, twice as far apart");
      expect(period(b, 5, 0, 60), closeTo(8, 0.5), reason: "outside, as drawn");
    });

    test("no glass where the element is not there", () async {
      Future<int> rim(double presence) async {
        var recorder = ui.PictureRecorder();
        var canvas = ui.Canvas(recorder);
        var box = const Rect.fromLTWH(0, 0, 200, 200);
        paintWithLooks(
            canvas,
            box,
            const [
              MotionDevice(MotionDeviceKind.lens,
                  id: "l", values: {"size": 0.6, "orbit": 0}),
            ],
            (on) {},
            presence: presence);
        var image = await recorder.endRecording().toImage(size, size);
        var bytes = (await image.toByteData())!;
        image.dispose();
        // On the rim, straight up from the middle: 60 px out.
        return alphaAt(bytes, 100, 40);
      }

      expect(await rim(1), greaterThan(100), reason: "there: its rim");
      expect(await rim(0), 0, reason: "gone, or not yet come: nothing");
    });

    test("the glass goes round its middle, so many laps a second", () {
      const d = MotionDevice(MotionDeviceKind.lens,
          id: "l", values: {"orbit": 0.5, "laps": 0.25, "x": 0.5, "y": 0.5});
      const box = Rect.fromLTWH(0, 0, 200, 100);
      expect(lensAt(d, box, 0), const Offset(150, 50),
          reason: "from the right");
      var quarter = lensAt(d, box, 1);
      expect(quarter.dx, closeTo(100, 1e-6));
      expect(quarter.dy, closeTo(75, 1e-6), reason: "a quarter round, below");
    });
  });
}
