import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
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

  testWidgets("and with a part of the words set apart, they are still drawn",
      (tester) async {
    // A fade is a paint on the letters, and a part's style once took any
    // paint on them for an outline's and drew every word clear: a faded
    // heading with one bold word was an empty box.
    var spec = plain.copyWith(fade: const GradientSpec(to: _to, angle: 90));
    late int lit;
    await tester.runAsync(() async {
      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 120, 120),
          Paint()..color = const Color(0xFF000000));
      paintWordsInBox(
          canvas, "HH HH", spec, const Rect.fromLTWH(0, 0, 120, 120),
          parts: const [TextPart(from: 1, to: 1, weight: 700)]);
      var image = await recorder.endRecording().toImage(_size, _size);
      var bytes = (await image.toByteData())!;
      lit = 0;
      for (var i = 0; i < _size * _size; i++) {
        if (_pinkness(bytes.getUint32(i * 4)) >= 0) lit++;
      }
      image.dispose();
    });
    expect(lit, greaterThan(100), reason: "the words are drawn");
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

  testWidgets("two boxes of one size in two places each have their own fade",
      (tester) async {
    // The shader is drawn where the canvas is, not where the paragraph is,
    // so a box's place is as much a part of its fade as its size: a second
    // box the same size further along took the first one's shader and was
    // all the second colour, and a faded heading dragged left its fade
    // behind.
    var spec = plain.copyWith(fade: const GradientSpec(to: _to, angle: 90));
    late List<(double, double)> ink;
    await tester.runAsync(() async {
      ink = await _inkAcross(300, (canvas) {
        paintTextInBox(canvas, "HH", spec, const Rect.fromLTWH(0, 0, 100, 60));
        paintTextInBox(
            canvas, "HH", spec, const Rect.fromLTWH(200, 0, 100, 60));
      });
    });
    var first = _mean(ink, 0, 100), second = _mean(ink, 200, 300);
    expect(first, greaterThanOrEqualTo(0));
    expect(second, closeTo(first, 0.05),
        reason: "the same words at the same place in their own box");
  });

  group("a fade runs across the element's box however its words are set", () {
    // In a box it did; in columns, wrapped round something, or riding a
    // line the words were drawn in the first colour only. What anybody
    // means by a fade across a text is one fade over all of it: the columns
    // together, the wrapped lines together, the letters on the line
    // together, not one restarting in each.
    var spec = plain.copyWith(
        fontSize: 20,
        align: TextAlignSpec.left,
        verticalAlign: VerticalAlignSpec.top,
        fade: const GradientSpec(to: _to, angle: 90));
    const words = "HHH HHH HHH HHH HHH HHH HHH HHH HHH HHH HHH HHH HHH HHH";

    TextElement text(
            {TextColumns columns = const TextColumns(),
            TextWrap wrap = const TextWrap(),
            TextOnCurve? curve}) =>
        TextElement(const ElementBase(id: "t", width: 300, height: 120),
            text: words,
            textSpec: spec,
            box: const BoxSpec(padding: 0),
            columns: columns,
            wrap: wrap,
            curve: curve);

    Future<List<(double, double)>> drawn(CanvasDocument doc) async =>
        _inkAcross(300, (canvas) {
          for (var e in doc.elements.whereType<TextElement>()) {
            paintElement(canvas, e, 0, document: doc);
          }
        });

    testWidgets("in columns, one fade across them all", (tester) async {
      late List<(double, double)> ink;
      await tester.runAsync(() async => ink = await drawn(CanvasDocument(
          elements: [text(columns: const TextColumns(count: 2, gap: 20))])));
      var left = _mean(ink, 0, 140), right = _mean(ink, 160, 300);
      expect(left, greaterThanOrEqualTo(0), reason: "the first column drawn");
      expect(right - left, greaterThan(0.15),
          reason: "the second column further along the fade than the first");
    });

    testWidgets("wrapped, one fade across both sides", (tester) async {
      late List<(double, double)> ink;
      await tester
          .runAsync(() async => ink = await drawn(CanvasDocument(elements: [
                text(wrap: const TextWrap(on: true)),
                ShapeElement(const ElementBase(
                    id: "s", x: 130, y: 0, width: 40, height: 120)),
              ])));
      var left = _mean(ink, 0, 130), right = _mean(ink, 170, 300);
      expect(left, greaterThanOrEqualTo(0), reason: "the left side drawn");
      expect(right - left, greaterThan(0.15),
          reason: "the right of the thing in the way further along");
    });

    testWidgets("on a line, across the letters' box", (tester) async {
      late List<(double, double)> ink;
      await tester.runAsync(() async =>
          ink = await drawn(CanvasDocument(elements: [
            LineElement(
                const ElementBase(id: "l", x: 0, y: 60, width: 300, height: 0),
                color: const Color(0x00000000)),
            text(curve: const TextOnCurve(elementId: "l"))
                .copyWith(text: "HHHHHHHHHH"),
          ])));
      var left = _mean(ink, 0, 60), right = _mean(ink, 140, 200);
      expect(left, greaterThanOrEqualTo(0), reason: "the first letters drawn");
      expect(right - left, greaterThan(0.15),
          reason: "the last letters further along than the first");
    });
  });
}

/// _inkAcross paints with [paint] on black, [width] by 120, and gives every
/// lit pixel's x and how far along the fade it is.
Future<List<(double, double)>> _inkAcross(
    int width, void Function(ui.Canvas) paint) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), 120),
      Paint()..color = const Color(0xFF000000));
  paint(canvas);
  var image = await recorder.endRecording().toImage(width, 120);
  var bytes = (await image.toByteData())!;
  var out = <(double, double)>[];
  for (var y = 0; y < 120; y++) {
    for (var x = 0; x < width; x++) {
      var lit = _pinkness(bytes.getUint32((y * width + x) * 4));
      if (lit >= 0) out.add((x.toDouble(), lit));
    }
  }
  image.dispose();
  return out;
}

/// _mean is how far along the fade the ink between [from] and [to] across
/// is on average, or -1 where there is none.
double _mean(List<(double, double)> ink, double from, double to) {
  var sum = 0.0, count = 0;
  for (var (x, lit) in ink) {
    if (x < from || x >= to) continue;
    sum += lit;
    count++;
  }
  return count == 0 ? -1 : sum / count;
}
