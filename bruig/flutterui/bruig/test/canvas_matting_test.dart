import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/render/matting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_matting_test.dart is the work at a cut-out's edge: alpha read back
// out of colours mixed at a soft edge, and a background's colour taken out
// of it.

/// _edge is a picture [w] wide whose left is [subject] and right [backdrop],
/// blending linearly across the middle [soft] pixels -- a soft edge with a
/// known alpha at every pixel -- and that alpha.
(Uint8List, List<double>) _edge(
    int w, int h, List<int> subject, List<int> backdrop, int soft) {
  var rgba = Uint8List(w * h * 4);
  var alphas = <double>[];
  var from = (w - soft) ~/ 2;
  for (var x = 0; x < w; x++) {
    var a = ((from + soft - x) / soft).clamp(0.0, 1.0);
    alphas.add(a);
    for (var y = 0; y < h; y++) {
      var i = (y * w + x) * 4;
      for (var c = 0; c < 3; c++) {
        rgba[i + c] = (subject[c] * a + backdrop[c] * (1 - a)).round();
      }
      rgba[i + 3] = 255;
    }
  }
  return (rgba, alphas);
}

void main() {
  test("a brushed edge gets the alpha its colours say it has", () {
    const w = 60, h = 10;
    var (rgba, truth) =
        _edge(w, h, const [230, 200, 80], const [30, 120, 40], 20);
    // The mask as a hard cut down the middle, which is what a subject found
    // in a hurry looks like at hair.
    var alpha = Uint8List(w * h);
    var band = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        alpha[y * w + x] = x < w / 2 ? 255 : 0;
        // The brush along the edge.
        band[y * w + x] = (x >= 18 && x < 42) ? 255 : 0;
      }
    }
    var out = refineAlpha(RefineJob(rgba, alpha, band, w, h, 20));
    // Within half the reach of the cut, which is the soft edge's width.
    for (var x = 21; x < 39; x++) {
      expect(out[5 * w + x] / 255, closeTo(truth[x], 0.08), reason: "x=$x");
    }
    expect(out[5 * w + 5], 255, reason: "unbrushed, as it was");
    expect(out[5 * w + 55], 0);
  });

  test("brushed inside the subject, away from its edge, nothing changes", () {
    // Dark hair framing a pale face, cut cleanly from a dark backdrop: a
    // stroke laid over the hair must not take the hair for background just
    // because the face is the nearest thing surely kept.
    const w = 80, h = 6;
    var rgba = Uint8List(w * h * 4);
    var alpha = Uint8List(w * h);
    var band = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var i = y * w + x;
        var colour = x < 30
            ? const [230, 190, 160] // face
            : x < 55
                ? const [40, 30, 25] // hair
                : const [20, 25, 35]; // backdrop
        for (var c = 0; c < 3; c++) {
          rgba[i * 4 + c] = colour[c];
        }
        rgba[i * 4 + 3] = 255;
        alpha[i] = x < 55 ? 255 : 0;
        band[i] = x >= 30 && x < 50 ? 255 : 0;
      }
    }
    var out = refineAlpha(RefineJob(rgba, alpha, band, w, h, 10));
    expect(out, alpha);
  });

  test("an edge too alike to tell apart is left as it was", () {
    const w = 40, h = 4;
    var (rgba, _) =
        _edge(w, h, const [120, 120, 120], const [125, 120, 118], 10);
    var alpha = Uint8List(w * h);
    var band = Uint8List(w * h)..fillRange(0, w * h, 255);
    for (var i = 0; i < w * h; i++) {
      alpha[i] = i % w < 20 ? 255 : 0;
      if (i % w < 5 || i % w > 35) band[i] = 0;
    }
    var out = refineAlpha(RefineJob(rgba, alpha, band, w, h, 8));
    expect(out, alpha);
  });

  test("decontaminating takes the background's colour out of the edge", () {
    const w = 60, h = 6;
    // Pale hair on a green pitch: the edge is green-tinged.
    var (rgba, truth) =
        _edge(w, h, const [240, 220, 180], const [20, 160, 30], 20);
    var alpha = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        alpha[y * w + x] = (truth[x] * 255).round();
      }
    }
    var out = decontaminate(DeconJob(rgba, alpha, w, h, 1, 8));
    // Halfway across the edge, mostly hidden: its colour is near the
    // hair's now, not the pitch's.
    var x = 34;
    var i = (3 * w + x) * 4;
    var a = rgba[i + 3] / 255;
    var green = out[i + 1] / a, red = out[i] / a;
    expect(red, greaterThan(200), reason: "towards the hair's colour");
    expect((green - 220).abs(), lessThan(30));
    expect(rgba[i], lessThan(160), reason: "where it started greener");
    // The subject's own pixels are not touched.
    var inside = (3 * w + 5) * 4;
    expect(out.sublist(inside, inside + 4), rgba.sublist(inside, inside + 4));
  });
}
