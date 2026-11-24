import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_text_leaving_test.dart is a text's box and pieces coming and going
// with it: nothing of it before it arrives, even with words held back as a
// part, and all of it gone when it has left by its own leaving preset. The
// words went by the presets; the box and a piece's box (a badge's ring, a
// card) stood there from the start of the scene and stayed after the words
// had gone (Ken, 2026-11-24: a scene's first part left its rings behind
// under the second).

/// _doc is a page with one text: a red box, and a piece with a red box of
/// its own, arriving at [arriveAt] seconds and leaving half a second later;
/// [heldBack] gives it words that come a second after it, as a part.
CanvasDocument _doc({double arriveAt = 0, bool heldBack = false}) =>
    CanvasDocument.fromJson({
      "version": 1,
      "size": {"ratio": "square", "width": 100},
      "frameRate": 24,
      "frames": 48,
      "background": {
        "spec": {"style": "plain", "bg": 0xFFFFFFFF}
      },
      "elements": [
        {
          "kind": "text",
          "id": "t",
          "name": "Card",
          "x": 10.0,
          "y": 10.0,
          "w": 80.0,
          "h": 80.0,
          "text": heldBack ? "LATER" : "",
          if (heldBack)
            "parts": [
              {
                "from": 1,
                "to": 1,
                "animation": {"preset": "fadeIn", "offset": 24}
              }
            ],
          "textSpec": {"font": "Inter", "size": 12.0, "color": 0xFF000000},
          "box": {"fill": 0xFFFF0000, "pad": 0.0},
          "items": [
            {
              "id": "p",
              "t": "X",
              "slot": "middleCentre",
              "box": {"fill": 0xFFFF0000, "pad": 10.0},
              "spec": {"font": "Inter", "size": 12.0, "color": 0xFFFF0000}
            }
          ],
          "animation": {"preset": "fadeIn", "exit": "fadeIn", "gap": 0.35},
          "motion": {
            "clips": [
              {
                "id": "a",
                "name": "Arrives",
                "kind": "arrive",
                "length": 0.1,
                "after": "last",
                "inside": {"own": true}
              },
              {
                "id": "l",
                "name": "Leaves",
                "kind": "leave",
                "length": 0.5,
                "layer": 1,
                "inside": {"own": true}
              }
            ],
            "placed": [
              {"id": "ap", "clip": "a", "start": arriveAt, "length": 0.1},
              {
                "id": "lp",
                "clip": "l",
                "layer": 1,
                "start": arriveAt + 0.5,
                "length": 0.5
              }
            ]
          }
        }
      ]
    });

/// _red counts the red pixels of frame [frame] of [doc].
Future<int> _red(int frame, [CanvasDocument? doc]) async {
  var image = await renderFrame(doc ?? _doc(), frame: frame);
  try {
    var raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    var p = raw!.buffer.asUint8List();
    var n = 0;
    for (var i = 0; i < p.length; i += 4) {
      if (p[i] > 200 && p[i + 1] < 80 && p[i + 2] < 80) n++;
    }
    return n;
  } finally {
    image.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("before it leaves, its box is there", () async {
    expect(await _red(6), greaterThan(1000));
  });

  test("half gone, its box is fading", () async {
    // Faded red over white is no longer pure red.
    expect(await _red(18), lessThan(await _red(6)));
  });

  test("gone, nothing of it is left, box and pieces", () async {
    expect(await _red(36), 0);
  });

  test("before it arrives, nothing of it, box and pieces", () async {
    var later = _doc(arriveAt: 1);
    expect(await _red(6, later), 0);
    expect(await _red(26, later), greaterThan(1000), reason: "arrived");
  });

  test("words held back as a part do not show its box early", () async {
    // A badge's label, a panel's title: the part comes after the element,
    // so the element's box waits for the element.
    var later = _doc(arriveAt: 1, heldBack: true);
    expect(await _red(6, later), 0);
    expect(await _red(26, later), greaterThan(1000));
  });
}
