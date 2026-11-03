import 'dart:typed_data';
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_scene.dart';
import 'package:flutter_test/flutter_test.dart';

// A 3D stage's set as Flutter GPU draws it: the floor's texture, made from
// its colour and what it is made of, and the wall's with its skirting. The
// scene itself is drawn in the app; here, where there is no GPU, a sketch
// of the set stands in for it.

StageElement set({FloorPattern pattern = FloorPattern.grid, double size = 6}) =>
    StageElement(const ElementBase(id: "st"),
        pattern: pattern, size: size, floor: const Color(0xFFC9B391));

/// colour is pixel [x], [y] of RGBA [px], [n] wide, as 0xRRGGBB.
int colour(Uint8List px, int n, int x, int y) {
  final i = (y * n + x) * 4;
  return (px[i] << 16) | (px[i + 1] << 8) | px[i + 2];
}

void main() {
  test("the floor is its colour, with what it is made of in a darker shade",
      () {
    final (plain, n, _) = floorTexture(set(pattern: FloorPattern.plain));
    final colours = {
      for (var y = 0; y < n; y += 7)
        for (var x = 0; x < n; x += 7) colour(plain, n, x, y)
    };
    expect(colours, {0xC9B391});
    for (final p in [
      FloorPattern.grid,
      FloorPattern.tiles,
      FloorPattern.boards,
      FloorPattern.grass
    ]) {
      final (px, m, _) = floorTexture(set(pattern: p));
      final seen = {
        for (var y = 0; y < m; y += 3)
          for (var x = 0; x < m; x += 3) colour(px, m, x, y)
      };
      expect(seen.length, 2, reason: "$p: the colour and its shade");
      expect(seen, contains(0xC9B391), reason: "$p");
    }
  });

  test("the same floor every time, and never too big to make quickly", () {
    final (a, n, h) = floorTexture(set(pattern: FloorPattern.grass));
    final (b, _, _) = floorTexture(set(pattern: FloorPattern.grass));
    expect(a, b);
    expect((n, h), (768, 768), reason: "64 a metre across 12 m");
    final (_, big, _) = floorTexture(set(size: 50));
    expect(big, lessThanOrEqualTo(1024));
  });

  test("the wall darkens to its skirting board at the foot", () {
    final (px, w, h) = wallTexture(0xFFE9DCC6);
    expect(colour(px, w, 0, 0), 0xE9DCC6, reason: "the top as picked");
    final foot = colour(px, w, 0, h - 1), above = colour(px, w, 0, h - 13);
    expect(foot >> 16, lessThan(above >> 16), reason: "the skirting darker");
  });

  test("where 3D cannot be drawn, a sketch of the set stands in", () async {
    final rec = PictureRecorder();
    paintStage(Canvas(rec), const Rect.fromLTWH(0, 0, 320, 180), set(), 0);
    final img = await rec.endRecording().toImage(320, 180);
    final data = (await img.toByteData())!;
    int at(int x, int y) => data.getUint32((y * 320 + x) * 4);
    // Sky at the top, the floor at the bottom.
    expect(at(160, 2) >> 8, 0xBFE0F4);
    expect(at(160, 178) >> 8, 0xC9B391);
  });
}
