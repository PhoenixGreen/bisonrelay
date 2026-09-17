import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_frame_rate_test.dart is how many frames a second a canvas runs at,
// and where that number comes from when nobody has said.
//
// It follows the shape, because the shape is what the document is: an A4 page
// has no frames to have a rate between, and a screen that moves wants film's
// twenty-four. The rest is a short list of the numbers anybody actually asks
// for, and a box for everything else.

void main() {
  test("a page is one frame a second and a screen is twenty-four", () {
    expect(defaultFrameRateFor(CanvasRatio.a4), 1);
    expect(defaultFrameRateFor(CanvasRatio.a4Wide), 1);
    expect(defaultFrameRateFor(CanvasRatio.wide), 24);
    expect(defaultFrameRateFor(CanvasRatio.square), 24);
    expect(defaultFrameRateFor(CanvasRatio.custom), 24);
  });

  test("and the paper shapes are the ones that know they are paper", () {
    expect(CanvasRatio.a4.isPaper, isTrue);
    expect(CanvasRatio.a4Wide.isPaper, isTrue);
    for (var ratio in CanvasRatio.values) {
      if (ratio == CanvasRatio.a4 || ratio == CanvasRatio.a4Wide) continue;
      expect(ratio.isPaper, isFalse, reason: ratio.name);
    }
  });

  test("the offered rates are the ones worth offering", () {
    // Twelve for something light, twenty-four for film, thirty for a screen
    // recording, sixty for something smooth -- and one, which is a still.
    expect(canvasFrameRates, containsAll([1, 12, 24, 30, 60]));
    expect(canvasFrameRates.first, 1);
  });

  test("and a document keeps whatever rate it is given", () {
    var document = const CanvasDocument(frameRate: 25);
    expect(document.copyWith(frameRate: 48).frameRate, 48);
    expect(canvasFrameRates.contains(document.frameRate), isFalse,
        reason: "so the list shows Custom beside the number");
  });
}
