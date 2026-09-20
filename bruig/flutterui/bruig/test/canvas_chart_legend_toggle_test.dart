import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_chart_legend_toggle_test.dart is the key as something to press.
//
// A chart of six pots across four eras is unreadable all at once, and the way
// anybody reads one is by taking the others away for a moment. That is a thing
// a reader does, not a thing an author does -- so it belongs on the chart
// itself, on the entry that already names the series, and it has to survive
// being published.

const int _w = 400, _h = 300;
const Rect _rect = Rect.fromLTWH(0, 0, 400, 300);

ChartElement _chart({List<bool> hidden = const [false, false]}) => ChartElement(
      const ElementBase(id: "c", width: 400, height: 300),
      showLegend: true,
      showGrid: false,
      showAxes: false,
      showXLabels: false,
      showYLabels: false,
      data: ChartData(
        categories: const ["a", "b", "c"],
        series: [
          ChartSeries(
              name: "One",
              color: const Color(0xFF30E0A0),
              values: const [10, 20, 30],
              hidden: hidden[0]),
          ChartSeries(
              name: "Two",
              color: const Color(0xFFE8546B),
              values: const [200, 400, 600],
              hidden: hidden[1]),
        ],
      ),
    );

/// _ink is how much of one colour the chart laid down.
Future<int> _ink(ChartElement e, bool Function(int r, int g, int b) is_) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(_rect, Paint()..color = const Color(0xFF000000));
  paintChart(canvas, _rect, e);
  var image = await recorder.endRecording().toImage(_w, _h);
  var bytes = (await image.toByteData())!;
  image.dispose();
  var n = 0;
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    var p = bytes.getUint32(i);
    if (is_((p >> 24) & 0xFF, (p >> 16) & 0xFF, (p >> 8) & 0xFF)) n++;
  }
  return n;
}

bool _green(int r, int g, int b) => g > 120 && r < 120 && b < 180;
bool _red(int r, int g, int b) => r > 150 && g < 120 && b < 140;

void main() {
  group("a series switched off from the key", () {
    test("is remembered, and saved", () {
      var data = _chart(hidden: const [false, true]).data;
      expect(data.series[1].hidden, isTrue);
      var back = ChartData.fromJson(data.toJson());
      expect(back.series[1].hidden, isTrue);
      expect(back.series[0].hidden, isFalse);
      // A chart with nothing switched off saves the file it always did.
      expect(
          (ChartData.fromJson(_chart().data.toJson()).series[0].toJson())
              .containsKey("off"),
          isFalse);
    });

    testWidgets("is not drawn", (tester) async {
      late int on, off;
      await tester.runAsync(() async {
        on = await _ink(_chart(), _red);
        off = await _ink(_chart(hidden: const [false, true]), _red);
      });
      expect(on, greaterThan(0));
      // Not nothing at all: the key still names it, and its swatch is drawn
      // hollow in its own colour so there is something to press to bring it
      // back.
      expect(off, lessThan(on ~/ 4), reason: "$off against $on");
    });

    testWidgets("and the axis is re-scaled to what is left", (tester) async {
      // Which is the point of switching one off. A pot worth two hundred
      // against a stream worth six hundred is a flat line until the stream is
      // out of the way; if the axis still reached six hundred, taking it away
      // would show nothing new.
      late int small, alone;
      await tester.runAsync(() async {
        small = await _ink(_chart(), _green);
        alone = await _ink(_chart(hidden: const [false, true]), _green);
      });
      expect(alone, greaterThan(small),
          reason: "the smaller series grows into the room: $alone vs $small");
    });

    test("still has an entry in the key, and knows which series it is", () {
      var entries =
          legendEntriesForTest(_chart(hidden: const [false, true]), 1);
      expect(entries.length, 2);
      expect(entries[1].name, "Two");
      expect(entries[1].hidden, isTrue);
      expect(entries[1].series, 1);
    });
  });

  group("the key's hit areas", () {
    test("are one per series, in the order the series are in", () {
      var rects = chartLegendRects(_chart(), _rect);
      expect(rects.length, 2);
      expect(rects[0].$1, 0);
      expect(rects[1].$1, 1);
      for (var (_, box) in rects) {
        expect(box.width, greaterThan(0));
        expect(box.height, greaterThan(0));
        expect(_rect.overlaps(box), isTrue,
            reason: "a target outside the element is a target nobody can hit");
      }
    });

    test("do not overlap each other", () {
      var rects = chartLegendRects(_chart(), _rect);
      expect(rects[0].$2.overlaps(rects[1].$2), isFalse);
    });

    test("are none where the key does not stand for series", () {
      // A pie's entries are its categories, and neither of a candlestick's
      // two is a series that can be switched off.
      var pie = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        type: ChartType.pie,
        showLegend: true,
        data: ChartData.parse("Cat\tA\nx\t1\ny\t2"),
      );
      expect(chartLegendRects(pie, _rect), isEmpty);
    });

    test("and none at all with the key switched off", () {
      var quiet = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        showLegend: false,
        data: ChartData.parse("Cat\tA\nx\t1\ny\t2"),
      );
      expect(chartLegendRects(quiet, _rect), isEmpty);
    });
  });
}
