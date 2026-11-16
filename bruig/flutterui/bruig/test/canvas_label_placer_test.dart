import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/label_placer.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_label_placer_test.dart is the one rule that keeps a chart's words
// apart (Ken, 2026-11-17, the improvements report's first item): a label
// takes the first clear place it asks for, or none; a row of names too
// wide for their slots is written smaller, then every second or third.

void main() {
  test("a label takes the first clear place, else the next, else none", () {
    var p = LabelPlacer(const Rect.fromLTWH(0, 0, 200, 100));
    var a = p.place([const Rect.fromLTWH(10, 10, 50, 12)]);
    expect(a, const Rect.fromLTWH(10, 10, 50, 12));
    var b = p.place([
      const Rect.fromLTWH(30, 12, 50, 12), // on a
      const Rect.fromLTWH(30, 40, 50, 12),
    ]);
    expect(b, const Rect.fromLTWH(30, 40, 50, 12));
    expect(p.place([const Rect.fromLTWH(20, 10, 40, 12)]), isNull);
    expect(p.place([const Rect.fromLTWH(180, 10, 40, 12)]), isNull,
        reason: "outside the chart");
  });

  test("what is kept clear is not handed out", () {
    var dot = Rect.fromCircle(center: const Offset(50, 50), radius: 6);
    var p = LabelPlacer(const Rect.fromLTWH(0, 0, 200, 100), keepClear: [dot]);
    var around =
        LabelPlacer.around(const Offset(50, 50), const Size(30, 10), 6);
    var at = p.place(around)!;
    expect(at.overlaps(dot), isFalse);
    expect(at.bottom, lessThanOrEqualTo(dot.top), reason: "above, first");
  });

  test("names too wide for their slots: smaller, then every few", () {
    const spec = TextSpec(fontSize: 10);
    var fits = AxisNames.of(["A", "B"], spec, 200);
    expect((fits.scale, fits.every), (1.0, 1));
    var long = [for (var i = 0; i < 20; i++) "Club name $i"];
    var crowded = AxisNames.of(long, spec, 20);
    expect(crowded.every, greaterThan(1));
    expect(crowded.scale, 0.75);
    expect(crowded.shows(0, 20), isTrue);
    expect(crowded.shows(1, 20), isFalse);
  });

  test("a scatter of close points draws its names through the placer",
      () async {
    var names = [for (var i = 0; i < 8; i++) "Club $i"];
    var c = ChartElement(const ElementBase(id: "s", width: 300, height: 200),
        type: ChartType.scatter,
        showValues: true,
        data: ChartData(categories: [
          "10",
          "11",
          "12",
          "13",
          "50",
          "51",
          "52",
          "90"
        ], series: const [
          ChartSeries(
              name: "y",
              color: Color(0xFF3366FF),
              values: [5, 5.2, 5.1, 5.3, 6, 6.1, 6, 9])
        ], pointNames: names));
    var rec = ui.PictureRecorder();
    paintChart(ui.Canvas(rec), const Rect.fromLTWH(0, 0, 300, 200), c);
    rec.endRecording().dispose();
  });
}
