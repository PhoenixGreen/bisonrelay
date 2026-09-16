import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_data.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_chart_axis_labels_test.dart is the writing along a chart's two axes.
//
// One switch used to do both, on the grounds that they are read together or
// not at all. Often enough they are not: a bar chart named by its categories
// does not always want the figures up the side as well, and a chart of dates
// wants the dates and nothing else.
//
// By axis rather than by what is written there, which is the part worth
// pinning: which of the two an axis carries depends on which way the chart is
// drawn, and on horizontal bars the categories run up the side. "The X labels"
// has to mean whatever is written along the bottom either way, because that is
// what somebody looking at the chart means by it.

const int _w = 300, _h = 200;
const Rect _rect = Rect.fromLTWH(0, 0, 300, 200);

ChartElement _chart({
  bool x = true,
  bool y = true,
  ChartType type = ChartType.bar,
  double? xSize,
  Color? xColour,
  double? ySize,
  Color? yColour,
}) =>
    ChartElement(
      const ElementBase(id: "c", width: 300, height: 200),
      type: type,
      showXLabels: x,
      showYLabels: y,
      xLabelSize: xSize,
      xLabelColor: xColour,
      yLabelSize: ySize,
      yLabelColor: yColour,
      showLegend: false,
      showGrid: false,
      labelSpec: const TextSpec(fontSize: 14, color: Color(0xFFFFFFFF)),
      data: ChartData.parse("Cat\tA\nJan\t10\nFeb\t6\nMar\t14"),
    );

/// _pixels renders a chart, as ARGB.
Future<List<int>> _pixels(ChartElement e) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(_rect, Paint()..color = const Color(0xFF000000));
  paintChart(canvas, _rect, e);
  var image = await recorder.endRecording().toImage(_w, _h);
  var bytes = (await image.toByteData())!;
  image.dispose();
  return [
    for (var i = 0; i < bytes.lengthInBytes; i += 4)
      (bytes.getUint32(i) >> 8) | ((bytes.getUint32(i) & 0xFF) << 24),
  ];
}

/// _ink counts the pixels of one colour in a strip of the picture.
int _ink(List<int> px, Rect strip, bool Function(int r, int g, int b) is_) {
  var n = 0;
  for (var y = strip.top.round(); y < strip.bottom.round(); y++) {
    for (var x = strip.left.round(); x < strip.right.round(); x++) {
      var p = px[y * _w + x];
      if (is_((p >> 16) & 0xFF, (p >> 8) & 0xFF, p & 0xFF)) n++;
    }
  }
  return n;
}

bool _white(int r, int g, int b) => r > 150 && g > 150 && b > 150;

// The strips each axis' writing lands in. The bottom one starts clear of the
// side one: the lowest figure up the side sits level with the writing along
// the bottom, and a strip that ran the whole width would count it twice.
const _bottom = Rect.fromLTWH(50, 170, 250, 30);
const _side = Rect.fromLTWH(0, 0, 40, 170);

void main() {
  group("each axis", () {
    testWidgets("can be switched off without the other", (tester) async {
      late int bothBottom, bothSide, noXBottom, noXSide, noYBottom, noYSide;
      await tester.runAsync(() async {
        var both = await _pixels(_chart());
        bothBottom = _ink(both, _bottom, _white);
        bothSide = _ink(both, _side, _white);

        var noX = await _pixels(_chart(x: false));
        noXBottom = _ink(noX, _bottom, _white);
        noXSide = _ink(noX, _side, _white);

        var noY = await _pixels(_chart(y: false));
        noYBottom = _ink(noY, _bottom, _white);
        noYSide = _ink(noY, _side, _white);
      });

      expect(bothBottom, greaterThan(20), reason: "the category names");
      expect(bothSide, greaterThan(20), reason: "the figures up the side");

      expect(noXBottom, 0, reason: "X off takes the writing along the bottom");
      expect(noXSide, greaterThan(20), reason: "and leaves the side alone");

      expect(noYSide, 0, reason: "Y off takes the writing up the side");
      expect(noYBottom, greaterThan(20));
    });

    testWidgets("gives back the room its writing took", (tester) async {
      // Room kept for labels that are switched off is a margin of nothing
      // down one side, which looks like a chart pushed off centre.
      late int drawnLeft, gonelEft;
      await tester.runAsync(() async {
        // The bars themselves, which start further left once the figures up
        // the side are not there to make room for.
        bool blue(int r, int g, int b) => b > 120 && b > r + 40;
        var both = await _pixels(_chart());
        var noY = await _pixels(_chart(y: false));
        int firstColumn(List<int> px) {
          for (var x = 0; x < _w; x++) {
            for (var y = 0; y < 170; y++) {
              var p = px[y * _w + x];
              if (blue((p >> 16) & 0xFF, (p >> 8) & 0xFF, p & 0xFF)) return x;
            }
          }
          return _w;
        }

        drawnLeft = firstColumn(both);
        gonelEft = firstColumn(noY);
      });
      expect(gonelEft, lessThan(drawnLeft - 10));
    });

    testWidgets("has its own size", (tester) async {
      late int smallBottom, bigBottom, smallSide;
      await tester.runAsync(() async {
        var small = await _pixels(_chart(xSize: 8, ySize: 8));
        smallBottom = _ink(small, _bottom, _white);
        smallSide = _ink(small, _side, _white);

        var big = await _pixels(_chart(xSize: 22, ySize: 8));
        bigBottom = _ink(big, _bottom, _white);
        // Not to the pixel: a taller strip along the bottom lifts the plot,
        // and the lowest figure up the side moves with it.
        expect(_ink(big, _side, _white), closeTo(smallSide, smallSide * 0.3),
            reason: "and setting one does not set the other");
      });
      expect(bigBottom, greaterThan(smallBottom * 1.5));
    });

    testWidgets("and its own colour", (tester) async {
      late int redBottom, greenSide, redSide;
      await tester.runAsync(() async {
        var px = await _pixels(_chart(
            xColour: const Color(0xFFFF4040),
            yColour: const Color(0xFF40FF80)));
        bool red(int r, int g, int b) => r > 150 && g < 110 && b < 110;
        bool green(int r, int g, int b) => g > 150 && r < 110;
        redBottom = _ink(px, _bottom, red);
        redSide = _ink(px, _side, red);
        greenSide = _ink(px, _side, green);
      });
      expect(redBottom, greaterThan(20), reason: "X is written in its own");
      expect(greenSide, greaterThan(20), reason: "and Y in its own");
      expect(redSide, 0, reason: "neither in the other's");
    });

    test("takes the chart's label type until it is given one", () {
      var e = _chart();
      expect(e.xLabels.fontSize, e.labelSpec.fontSize);
      expect(e.yLabels.color, e.labelSpec.color);

      var own = e.copyWith(xLabelSize: 30);
      expect(own.xLabels.fontSize, 30);
      expect(own.yLabels.fontSize, e.labelSpec.fontSize,
          reason: "one axis, not both");
      expect(own.xLabels.fontFamily, e.labelSpec.fontFamily,
          reason: "the font and the weight stay the chart's");
    });
  });

  group("which axis carries what", () {
    testWidgets("depends on which way the chart is drawn", (tester) async {
      // On horizontal bars the categories run up the side and the values
      // along the bottom, so switching off the Y labels takes the *names*.
      late int side, bottom;
      await tester.runAsync(() async {
        var px = await _pixels(_chart(type: ChartType.horizontalBar, y: false));
        side = _ink(px, _side, _white);
        bottom = _ink(px, _bottom, _white);
      });
      expect(side, 0, reason: "the names were up the side, and Y is off");
      expect(bottom, greaterThan(20),
          reason: "the figures along the bottom stay");
    });
  });

  group("what is saved", () {
    test("is the old key while both axes agree", () {
      var off = _chart(x: false, y: false);
      expect(off.props()["noAxisLabels"], isTrue);
      expect(off.props().containsKey("noXLabels"), isFalse);
    });

    test("and one key each when they do not", () {
      expect(_chart(x: false).props()["noXLabels"], isTrue);
      expect(_chart(x: false).props().containsKey("noAxisLabels"), isFalse);
      expect(_chart(y: false).props()["noYLabels"], isTrue);
    });

    test("and a chart saved before the switch was split reads back whole", () {
      var old = ChartElement.fromJson(
          {"noAxisLabels": true}, const ElementBase(id: "c"));
      expect(old.showXLabels, isFalse);
      expect(old.showYLabels, isFalse);

      var on = ChartElement.fromJson(const {}, const ElementBase(id: "c"));
      expect(on.showXLabels, isTrue);
      expect(on.showYLabels, isTrue);
    });

    test("and the type each axis was given comes back with it", () {
      var e = _chart(
          xSize: 9,
          xColour: const Color(0xFFFF4040),
          yColour: const Color(0xFF40FF80));
      var back = ChartElement.fromJson(e.props(), const ElementBase(id: "c"));
      expect(back.xLabelSize, 9);
      expect(back.xLabelColor, const Color(0xFFFF4040));
      expect(back.yLabelColor, const Color(0xFF40FF80));
      expect(back.yLabelSize, isNull,
          reason: "the one nobody set still follows");
    });
  });
}
