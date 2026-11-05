import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_strokes.dart';
import 'package:bruig/plugin_system/canvas/model/elements/parallax_element.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:flutter_test/flutter_test.dart';

// A canvas received from somebody else is read within limits: what it asks
// for is held to what the editor could have made, and a wrong type in one
// place costs that one setting, not the whole canvas.

void main() {
  test("a chain of devices is read only so long", () {
    var many = [
      for (var i = 0; i < 5000; i++) {"kind": DeviceKind.reverb.name},
    ];
    expect(
        ChannelMix.fromJson({"devices": many}).devices.length, maxChainDevices);
    expect(ReturnChannel.fromJson({"id": "r", "devices": many})!.devices.length,
        maxChainDevices);
  });

  test("a scenery layer is no smaller than the editor makes one", () {
    var layer = ParallaxLayer.fromJson({"size": 0.002});
    expect(layer.size, greaterThanOrEqualTo(0.1));
  });

  test("a curve's points: on the square, in order, and only so many", () {
    var flat = <num>[];
    for (var i = 0; i < 10000; i++) {
      flat
        ..add(i.isEven ? 5 : -3)
        ..add(i / 10000);
    }
    var a = ImageAdjustment.fromJson({
      "curves": {
        CurveChannel.rgb.name: [0.9, 0.1, 0.1, 0.9, ...flat],
      }
    });
    var points = a.curves[CurveChannel.rgb]!;
    expect(points.length, lessThanOrEqualTo(64));
    expect(
        points.every((p) => p.dx >= 0 && p.dx <= 1 && p.dy >= 0 && p.dy <= 1),
        isTrue);
    for (var i = 1; i < points.length; i++) {
      expect(points[i].dx, greaterThanOrEqualTo(points[i - 1].dx));
    }
  });

  test("a painted stroke is cut off past a long way, and strokes are counted",
      () {
    // Back and forth across the frame, far further than any hand would go.
    var zigzag = <num>[];
    for (var i = 0; i < 20000; i++) {
      zigzag
        ..add(i.isEven ? 0.0 : 1.0)
        ..add(0.5);
    }
    var stroke = StrokeMark.fromJson({"p": zigzag});
    var gone = 0.0;
    for (var i = 1; i < stroke.points.length; i++) {
      gone += (stroke.points[i] - stroke.points[i - 1]).distance;
    }
    expect(gone, lessThanOrEqualTo(201));
    var strokes = strokesFromJson([
      for (var i = 0; i < maxStrokes + 50; i++)
        <String, dynamic>{
          "p": [0, 0]
        },
    ]);
    expect(strokes.length, maxStrokes);
  });

  test("a button's name that is not text is skipped, not the whole canvas", () {
    var counter = elementFromJson({
      "kind": "counter",
      "id": "n",
      "buttons": [1, null, "reset"],
    });
    expect(counter, isA<CounterElement>());
  });
}
