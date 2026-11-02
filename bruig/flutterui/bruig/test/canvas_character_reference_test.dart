import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/character_reference.dart';
import 'package:bruig/plugin_system/canvas/render/character/reference_sheet.dart';
import 'package:bruig/plugin_system/canvas/render/character/reference_trace.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_character_reference_test.dart is a model sheet read for the
// Character Studio: Ken's reference (2026-11-01) -- a girl front, side and
// back, and eight faces -- cut into its figures and measured.

Future<SheetPixels> _sheet(WidgetTester tester) async {
  var bytes = File("test/fixtures/character_sheet.jpg").readAsBytesSync();
  return (await tester.runAsync(() async {
    var codec = await ui.instantiateImageCodec(bytes);
    var img = (await codec.getNextFrame()).image;
    var rgba = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    return SheetPixels(rgba!.buffer.asUint8List(), img.width, img.height);
  }))!;
}

void main() {
  testWidgets("the sheet is cut into its three figures and its faces",
      (tester) async {
    var p = await _sheet(tester);
    var cuts = findCuts(p);
    // ignore: avoid_print
    print([for (var c in cuts) "${c.rect} ${c.figure}"]);
    var figures = [
      for (var c in cuts)
        if (c.figure) c
    ];
    expect(figures, hasLength(3), reason: "front, side and back");
    expect(cuts.where((c) => !c.figure), isNotEmpty, reason: "the faces");
    var m = measureFigure(p, figures.first.rect)!;
    // ignore: avoid_print
    print(
        "heads ${m.headsTall} hair ${m.withHair} skull ${m.skull} top ${m.top} chin ${m.chin} bottom ${m.bottom}");
    expect(m.headsTall, inInclusiveRange(4.5, 6.8));
    var colours = paletteOf(p, [for (var f in figures) f.rect]);
    // ignore: avoid_print
    print([for (var c in colours) c.toARGB32().toRadixString(16)]);
    expect(colours.length, greaterThanOrEqualTo(5));
  });

  test("a reference keeps its cuts, and a side serves the other side", () {
    var r = CharacterReference("sheet.png",
        cuts: {
          "0,0": const ui.Rect.fromLTWH(10, 5, 60, 240),
          "90,0": const ui.Rect.fromLTWH(100, 5, 50, 240),
        },
        skulls: {"0,0": 24},
        strength: 0.4);
    var back = CharacterReference.fromJson(r.toJson())!;
    expect(back, r);
    expect(r.cutFor("90,0"),
        (const ui.Rect.fromLTWH(100, 5, 50, 240), false, "90,0"));
    expect(r.cutFor("270,0"),
        (const ui.Rect.fromLTWH(100, 5, 50, 240), true, "90,0"),
        reason: "mirrored");
    expect(r.cutFor("180,0"), isNull);
  });

  test("a sheet laid over a view: to the front's scale, on the ground", () {
    var r = CharacterReference("sheet.png",
        cuts: {"0,0": const ui.Rect.fromLTWH(10, 20, 60, 200)},
        skulls: {"0,0": 40});
    var at =
        r.laidOver("0,0", const ui.Rect.fromLTWH(0, 0, 300, 560), 60, 540)!;
    // Skull to feet, 180 of the sheet's pixels, is the 480 from head to
    // ground.
    expect(at.laid.height, closeTo(200 * 480 / 180, 1e-9));
    expect(at.laid.bottom, 540);
    expect(at.laid.center.dx, 150);
    expect(CharacterReference.onBox(const ui.Offset(10, 40), at).dy,
        closeTo(60, 1e-9),
        reason: "the skull at the top of the head");
    var side =
        r.laidOver("270,0", const ui.Rect.fromLTWH(0, 0, 300, 560), 60, 540);
    expect(side, isNull, reason: "no side cut");
  });

  test("a trace: a region for each paint on each part, holes kept", () {
    // A grey sheet; a red square with a blue square inside it -- a hole --
    // and its left half on part 0, right half on part 1; the edges soft,
    // blended with the sheet.
    const w = 40, h = 40;
    var rgba = Uint8List(w * h * 4);
    void put(int x, int y, (int, int, int) c) {
      var i = (y * w + x) * 4;
      rgba[i] = c.$1;
      rgba[i + 1] = c.$2;
      rgba[i + 2] = c.$3;
      rgba[i + 3] = 255;
    }

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        put(x, y, (180, 180, 190));
        if (x >= 8 && x < 32 && y >= 8 && y < 32) put(x, y, (220, 30, 30));
        if (x >= 16 && x < 24 && y >= 16 && y < 24) put(x, y, (30, 40, 220));
        // A soft edge: half red, half sheet.
        if (y == 7 && x >= 8 && x < 32) put(x, y, (200, 105, 110));
      }
    }
    var p = SheetPixels(rgba, w, h);
    const palette = [ui.Color(0xFFDC1E1E), ui.Color(0xFF1E28DC)];
    var regions = traceRegions(p, const ui.Rect.fromLTWH(0, 0, 40, 40), palette,
        (q) => q.dx < 20 ? 0 : 1);
    var red = [
      for (var r in regions)
        if (r.colour == 0) r
    ];
    var blue = [
      for (var r in regions)
        if (r.colour == 1) r
    ];
    expect(red, hasLength(2), reason: "one on each part");
    expect(blue, hasLength(2));
    expect(red.map((r) => r.part).toSet(), {0, 1});
    // The red halves are cut around the blue: a ring each side.
    for (var r in red) {
      expect(r.area, closeTo(24 * 24 / 2 - 8 * 8 / 2, 24));
      expect(r.bounds.top, closeTo(8, 1), reason: "the soft edge is not red");
    }
    // On one part, the red is one region with the blue a hole in it.
    var whole = traceRegions(
        p, const ui.Rect.fromLTWH(0, 0, 40, 40), palette, (q) => 0);
    expect(whole.first.colour, 0);
    expect(whole.first.rings, hasLength(2), reason: "its outline and its hole");
    var shape = traceShape(red.first, palette, (q) => q * 2);
    expect(shape.fill, palette[0]);
    expect(shape.evenOdd, isTrue);
    expect(
        blendOf(const ui.Color(0xFFC8696E), const ui.Color(0xFFB4B4BE), palette)
            ?.$1,
        0,
        reason: "half red, half sheet");
  });
}
