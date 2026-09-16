import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/table_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_gradient_paint_test.dart is the second colour actually reaching the
// canvas.
//
// A model test says the field is stored; it says nothing about whether the
// painter reads it. Two dead controls have shipped here before on exactly
// that gap, so each of these paints the thing and looks at the pixels: the
// top of the area should be one colour and the bottom the other.

const _from = Color(0xFF3D7EFF);
const _to = Color(0xFFFF3DAA);
const _fade = GradientSpec(to: _to); // 180 on a compass: downwards.

/// _pinkness is how far along the fade a pixel is: 0 at the first colour, 1
/// at the second, and -1 for a pixel that is neither.
double _pinkness(int pixel) {
  var r = (pixel >> 24) & 0xFF;
  var b = (pixel >> 8) & 0xFF;
  if (r + b < 0x60) return -1;
  return (r / (r + b)).clamp(0.0, 1.0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const size = 120;
  var area = const Rect.fromLTWH(0, 0, 120.0, 120.0);

  /// _rowOf paints through [draw] and reads one line across the picture.
  Future<List<int>> rowOf(void Function(ui.Canvas) draw, int y) async {
    var recorder = ui.PictureRecorder();
    var canvas = ui.Canvas(recorder);
    canvas.drawRect(area, Paint()..color = const Color(0xFF000000));
    draw(canvas);
    var image = await recorder.endRecording().toImage(size, size);
    var bytes = (await image.toByteData())!;
    var out = <int>[];
    for (var x = 0; x < size; x++) {
      out.add(bytes.getUint32((y * size + x) * 4));
    }
    image.dispose();
    return out;
  }

  /// _fadesDown is the whole check: near the first colour at the top, near
  /// the second at the bottom.
  Future<void> fadesDown(WidgetTester tester, void Function(ui.Canvas) draw,
      {int top = 12, int bottom = 108}) async {
    // The middle of the row rather than the most of anything in it: a table
    // has grid lines and words over its fill, and a white pixel sits halfway
    // along a blue-to-pink fade whatever the fill underneath it is doing.
    double middle(List<int> row) {
      var lit = [
        for (var p in row)
          if (_pinkness(p) >= 0) _pinkness(p),
      ]..sort();
      return lit.isEmpty ? -1 : lit[lit.length ~/ 2];
    }

    late double high;
    late double low;
    await tester.runAsync(() async {
      high = middle(await rowOf(draw, top));
      low = middle(await rowOf(draw, bottom));
    });
    expect(high, greaterThanOrEqualTo(0), reason: "something was drawn");
    expect(low, greaterThan(high + 0.2),
        reason: "the second colour is at the bottom, the first at the top");
  }

  testWidgets("a shape's fill", (tester) async {
    var e = const ShapeElement(
      ElementBase(id: "s", width: 120, height: 120),
      fill: _from,
    ).copyWith(fillFade: _fade);
    await fadesDown(tester, (canvas) => paintElement(canvas, e, 0));
  });

  testWidgets(
      "a box's fill -- a picture's background, a button, a band "
      "behind words", (tester) async {
    const box = BoxSpec(fill: _from, fillFade: _fade);
    await fadesDown(tester, (canvas) => paintBox(canvas, area, box));
  });

  testWidgets("a line's stroke", (tester) async {
    // Down the picture, so the fade has somewhere to run.
    var e = const LineElement(
      ElementBase(id: "l", x: 0, y: 0, width: 4, height: 120),
      strokeWidth: 20,
      color: _from,
    ).copyWith(fade: _fade);
    await fadesDown(tester, (canvas) => paintElement(canvas, e, 0),
        top: 20, bottom: 100);
  });

  testWidgets("a table's cells, once across the whole table", (tester) async {
    var e = const TableElement(
      ElementBase(id: "t", width: 120, height: 120),
      rows: [
        ["a", "b"],
        ["c", "d"],
        ["e", "f"],
        ["g", "h"],
      ],
      headerRow: false,
      cellFill: _from,
    ).copyWith(cellFade: _fade);
    await fadesDown(tester, (canvas) => paintTable(canvas, area, e));
  });

  testWidgets("and a flat colour stays flat", (tester) async {
    // The other half of every one of these: no second colour, no fade.
    const e = ShapeElement(
      ElementBase(id: "s", width: 120, height: 120),
      fill: _from,
    );
    late List<double> lit;
    await tester.runAsync(() async {
      var top = await rowOf((canvas) => paintElement(canvas, e, 0), 12);
      var bottom = await rowOf((canvas) => paintElement(canvas, e, 0), 108);
      lit = [
        for (var p in [...top, ...bottom])
          if (_pinkness(p) >= 0) _pinkness(p),
      ];
    });
    expect(lit.length, greaterThan(50));
    expect(lit.reduce(math.max) - lit.reduce(math.min), lessThan(0.02));
  });
}
