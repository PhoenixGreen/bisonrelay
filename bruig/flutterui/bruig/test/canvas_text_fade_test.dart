import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_text_fade_test.dart is words painted in two colours.
//
// A TextStyle is built before the text is laid out, so the letters have no
// bounds to build a shader from -- which is why this was left out when every
// other colour learned to fade. The answer is not to measure the letters but
// to run the fade across the box they are drawn in, which is known up front
// and is also what anybody means by a fade across a heading: one that
// restarted on every line, or ended early because the last line is short,
// would be neither.

const _size = 120;
const _from = Color(0xFF3D7EFF); // blue
const _to = Color(0xFFFF3DAA); // pink

/// _pinkness is how far along the fade a pixel is, or -1 where nothing was
/// drawn.
double _pinkness(int pixel) {
  var r = (pixel >> 24) & 0xFF;
  var b = (pixel >> 8) & 0xFF;
  if (r + b < 0x60) return -1;
  return (r / (r + b)).clamp(0.0, 1.0);
}

/// _row paints the words and reads the line with the most ink on it.
///
/// Found rather than given: where the words sit down the box depends on the
/// font, the size and the vertical alignment, and a fixed row lands between
/// the lines as easily as on one.
Future<List<double>> _row(TextSpec spec, int _) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 120, 120),
      Paint()..color = const Color(0xFF000000));
  paintTextInBox(canvas, "HHHH", spec, const Rect.fromLTWH(0, 0, 120, 120));
  var image = await recorder.endRecording().toImage(_size, _size);
  var bytes = (await image.toByteData())!;
  var best = <double>[];
  for (var y = 0; y < _size; y++) {
    var row = <double>[];
    for (var x = 0; x < _size; x++) {
      var lit = _pinkness(bytes.getUint32((y * _size + x) * 4));
      if (lit >= 0) row.add(lit);
    }
    if (row.length > best.length) best = row;
  }
  image.dispose();
  return best;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const plain = TextSpec(fontSize: 40, color: _from);

  testWidgets("one colour until a second is chosen", (tester) async {
    late List<double> lit;
    await tester.runAsync(() async => lit = await _row(plain, 60));
    expect(lit.length, greaterThan(10), reason: "something was drawn");
    expect(lit.reduce(math.max) - lit.reduce(math.min), lessThan(0.02));
  });

  testWidgets("and across the box once one is", (tester) async {
    // 90 on a compass runs left to right, so the words start in the first
    // colour and end in the second.
    var spec = plain.copyWith(fade: const GradientSpec(to: _to, angle: 90));
    late List<double> lit;
    await tester.runAsync(() async => lit = await _row(spec, 60));
    expect(lit.length, greaterThan(10));
    expect(lit.last - lit.first, greaterThan(0.3),
        reason: "the far side of the box is the second colour");
  });

  testWidgets("the outline still decides its own colour", (tester) async {
    // An outlined letter has no fill to fade, and the outline is painted
    // through the same slot a shader would use.
    var spec = plain.copyWith(
      fade: const GradientSpec(to: _to, angle: 90),
      outlineWidth: 2,
      outlineColor: const Color(0xFF00FF00),
    );
    late List<double> lit;
    await tester.runAsync(() async => lit = await _row(spec, 60));
    // Green is neither of the two: the fade must not have claimed the
    // outline's paint.
    expect(lit.isEmpty || lit.reduce(math.max) < 0.9, isTrue);
  });

  testWidgets("it survives being saved, and costs nothing unused",
      (tester) async {
    var spec = plain.copyWith(fade: const GradientSpec(to: _to, angle: 45));
    expect(TextSpec.fromJson(spec.toJson()).fade, spec.fade);
    expect(plain.toJson().containsKey("fade"), isFalse);
    expect(spec.copyWith(flatText: true).fade, isNull);
  });

  testWidgets("two boxes of different heights are two layouts", (tester) async {
    // The gradient is baked into the style, so the layout cache has to know
    // the box -- and the *height* in particular, because nothing else in the
    // key carries it: maxWidth is the width, and two boxes of one width and
    // two heights would otherwise be one layout and one shader.
    //
    // A fade running down, so the height is what decides it.
    var spec = plain.copyWith(fade: const GradientSpec(to: _to));

    /// _lowest is how far along the fade the bottom of the words gets.
    Future<double> lowest(double height) async {
      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 120, 120),
          Paint()..color = const Color(0xFF000000));
      paintTextInBox(canvas, "H", spec, Rect.fromLTWH(0, 0, 120, height));
      var image = await recorder.endRecording().toImage(_size, _size);
      var bytes = (await image.toByteData())!;
      var best = -1.0;
      for (var y = 0; y < _size; y++) {
        for (var x = 0; x < _size; x++) {
          var lit = _pinkness(bytes.getUint32((y * _size + x) * 4));
          if (lit > best) best = lit;
        }
      }
      image.dispose();
      return best;
    }

    late double tall;
    late double short;
    await tester.runAsync(() async {
      // The tall box first, so a cache that ignored the height would hand the
      // short one the tall one's shader.
      tall = await lowest(120);
      short = await lowest(48);
    });

    expect(tall, greaterThan(0.1), reason: "the words were drawn and do fade");
    expect(short, greaterThan(tall + 0.05),
        reason: "the same glyph is further along a short box's fade, which "
            "it cannot be if the two share a cached shader");
  });
}
