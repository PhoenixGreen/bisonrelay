import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_data.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_chart_gaps_test.dart is a cell nobody filled in.
//
// A nought and a blank are different facts. A fund that did not exist until
// 2020 and a fund that held nothing in 2019 are not the same thing, and a
// chart that draws both as a bar of no height says the second about the first.
// Every cell used to be a number, so a blank was a nought and there was no way
// to say the other thing at all.

const int _w = 300, _h = 200;
const Rect _rect = Rect.fromLTWH(0, 0, 300, 200);
const Color _ink = Color(0xFF30E0A0);

ChartElement _chart(List<double> values,
        {ChartType type = ChartType.bar, double floor = 0}) =>
    ChartElement(
      const ElementBase(id: "c", width: 300, height: 200),
      type: type,
      showLegend: false,
      showGrid: false,
      showAxes: false,
      showXLabels: false,
      showYLabels: false,
      showPoints: false,
      strokeWidth: 4,
      barFloor: floor,
      data: ChartData(
        categories: const ["a", "b", "c", "d", "e"],
        series: [ChartSeries(name: "A", color: _ink, values: values)],
      ),
    );

/// _paint renders a chart and hands back which pixels it drew in.
Future<Set<int>> _paint(ChartElement e) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(_rect, Paint()..color = const Color(0xFF000000));
  paintChart(canvas, _rect, e);
  var image = await recorder.endRecording().toImage(_w, _h);
  var bytes = (await image.toByteData())!;
  image.dispose();
  var lit = <int>{};
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    var p = bytes.getUint32(i);
    if (((p >> 24) & 0xFF) > 60 || ((p >> 8) & 0xFF) > 60) lit.add(i ~/ 4);
  }
  return lit;
}

/// _column is how many pixels were drawn in the vertical strip a category
/// sits in -- which is what says whether its bar, or its bit of line, is
/// there at all.
int _column(Set<int> lit, int of, int outOf) {
  var from = (_w * of / outOf).round(), to = (_w * (of + 1) / outOf).round();
  var n = 0;
  for (var at in lit) {
    var x = at % _w;
    if (x >= from && x < to) n++;
  }
  return n;
}

void main() {
  group("a blank cell", () {
    test("is not the same number as a nought", () {
      var blank = ChartData.fromJson(const {
        "categories": ["a", "b"],
        "series": [
          {
            "name": "A",
            "values": [null, 0]
          }
        ],
      });
      expect(blank.hasValueAt(0, 0), isFalse);
      expect(blank.hasValueAt(0, 1), isTrue);
      expect(blank.valueAt(0, 1), 0);
    });

    test("and survives being saved", () {
      var data = ChartData(
        categories: const ["a", "b"],
        series: const [
          ChartSeries(name: "A", color: _ink, values: [missingValue, 4])
        ],
      );
      var back = ChartData.fromJson(data.toJson());
      expect(back.hasValueAt(0, 0), isFalse,
          reason: "JSON has no NaN, so a gap is written as a null");
      expect(back.valueAt(0, 1), 4);
    });

    test("and reads and writes as an empty cell in pasted text", () {
      var data = ChartData.parse("Cat\tA\n2019\t\n2020\t4");
      expect(data.hasValueAt(0, 0), isFalse,
          reason: "a cell with nothing in it is a cell nobody filled in");
      expect(data.valueAt(0, 1), 4);
      // And back out the same way, so the text view is a round trip.
      expect(data.asText(), "\tA\n2019\t\n2020\t4");
      // Something unreadable is still a nought: that is a typo in a number,
      // not an absence.
      expect(ChartData.parse("Cat\tA\n2019\tn/a").hasValueAt(0, 0), isTrue);
    });

    testWidgets("draws no bar where a reading draws one", (tester) async {
      late int read, gap;
      await tester.runAsync(() async {
        read = _column(await _paint(_chart(const [5, 3, 5, 5, 5])), 1, 5);
        gap = _column(
            await _paint(_chart(const [5, missingValue, 5, 5, 5])), 1, 5);
      });
      expect(read, greaterThan(0));
      expect(gap, 0, reason: "a blank is nothing at all");
    });

    testWidgets("and a nought is told apart from it by the least height",
        (tester) async {
      // A bar of no height has no pixels, so with no floor a measured nought
      // and a year nobody has a figure for look identical. A sliver says
      // "measured, and it was nothing"; nothing at all says "there is nothing
      // to measure". Dash's budget is nought every year by design, and that
      // is the whole point of its chart.
      late int bare, floored, gap;
      await tester.runAsync(() async {
        bare = _column(await _paint(_chart(const [5, 0, 5, 5, 5])), 1, 5);
        floored = _column(
            await _paint(_chart(const [5, 0, 5, 5, 5], floor: 4)), 1, 5);
        gap = _column(
            await _paint(_chart(const [5, missingValue, 5, 5, 5], floor: 4)),
            1,
            5);
      });
      expect(bare, 0, reason: "no floor, no pixels");
      expect(floored, greaterThan(0), reason: "a floor gives it a sliver");
      expect(gap, 0, reason: "and a blank still draws nothing at all");
    });

    testWidgets("breaks a line rather than drawing across it", (tester) async {
      late int joined, broken;
      await tester.runAsync(() async {
        joined = _column(
            await _paint(_chart(const [5, 5, 5, 5, 5], type: ChartType.line)),
            2,
            5);
        broken = _column(
            await _paint(
                _chart(const [5, 5, missingValue, 5, 5], type: ChartType.line)),
            2,
            5);
      });
      expect(joined, greaterThan(0));
      // A line drawn straight across a year nobody has a figure for is a line
      // claiming a figure.
      expect(broken, lessThan(joined ~/ 3),
          reason: "the line stops either side of the hole: $broken of $joined");
    });

    testWidgets("leaves the rest of the line alone", (tester) async {
      late int before, after;
      await tester.runAsync(() async {
        var lit = await _paint(
            _chart(const [5, 5, missingValue, 5, 5], type: ChartType.line));
        before = _column(lit, 0, 5);
        after = _column(lit, 4, 5);
      });
      expect(before, greaterThan(0));
      expect(after, greaterThan(0));
    });
  });
}
