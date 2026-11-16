import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/chart_presets.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_styles.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_chart_presets_test.dart is the Charts tab's gallery as a model
// (Ken, 2026-11-17; prototype v7): every kind reads ticked columns or says
// what it needs; every starting design builds a chart from them and draws
// in every style.

const weeks = [
  ["Week", "Club", "Pts", "GD", "Won", "Drawn", "Lost"],
  ["1", "Arsenal", "3", "2", "1", "0", "0"],
  ["1", "Chelsea", "1", "0", "0", "1", "0"],
  ["1", "Spurs", "0", "-1", "0", "0", "1"],
  ["2", "Arsenal", "6", "4", "2", "0", "0"],
  ["2", "Chelsea", "4", "1", "1", "1", "0"],
  ["2", "Spurs", "3", "0", "1", "0", "1"],
];

void main() {
  var sheet = const DataSheet(id: "s", cells: weeks);
  var range = const CellRange(0, 0, 6, 6);
  Picks picks(List<int> cols) =>
      picksOf(sheet, range, cols, const [2, 3, 4, 5, 6], const [0], const [1]);
  const like = ChartElement(ElementBase(id: "c", width: 480, height: 300));

  test("each kind reads the ticked columns, or says what it needs", () {
    var one = picks([1, 2]);
    expect(
        chartKinds
            .firstWhere((k) => k.type == ChartType.horizontalBar)
            .reads(one),
        isNotNull);
    expect(chartKinds.firstWhere((k) => k.type == ChartType.scatter).reads(one),
        isNull,
        reason: "a scatter needs two numbers");
    expect(chartKinds.firstWhere((k) => k.type == ChartType.line).reads(one),
        isNull,
        reason: "a line needs a date");
    var timed = picks([0, 1, 2]);
    var line =
        chartKinds.firstWhere((k) => k.type == ChartType.line).reads(timed)!;
    expect(line.labels, 0);
    expect(line.colourBy, 1, reason: "a line per club");
    for (var k in chartKinds) {
      expect(k.needs, isNotEmpty);
      expect(k.presets, isNotEmpty);
    }
  });

  test("every design builds from the columns and draws in every style", () {
    var all = picks([0, 1, 2, 3, 4, 5, 6]);
    var made = 0;
    for (var k in chartKinds) {
      for (var pr in k.presets) {
        var chart = presetChart(k, pr, all, like);
        if (chart == null) continue;
        made++;
        expect(chart.type, isNotNull);
        for (var st in [null, ...dataStyles]) {
          var c = st == null ? chart : chartInStyle(chart, st);
          for (var reveal in [1.0, 0.4]) {
            var recorder = ui.PictureRecorder();
            paintChart(
                ui.Canvas(recorder), const Rect.fromLTWH(0, 0, 480, 300), c,
                reveal: reveal);
            recorder.endRecording().dispose();
          }
        }
      }
    }
    expect(made, greaterThan(60));
  });

  test("a race needs a date column; with one it plays through it", () {
    var bars = chartKinds.firstWhere((k) => k.type == ChartType.horizontalBar);
    var race = bars.presets.firstWhere((p) => p.plays);
    expect(race.needs!(picks([1, 2])), "a date column");
    var chart = presetChart(bars, race, picks([0, 1, 2]), like)!;
    expect(chart.sheet!.through, 0);
    expect(chart.play, greaterThan(0));
  });

  test("an extra changes the design; a style keeps it", () {
    var cols = chartKinds.firstWhere((k) => k.type == ChartType.bar);
    var chart = presetChart(cols, cols.presets.first, picks([1, 2]), like,
        mods: {ChartModifier.average, ChartModifier.highlight})!;
    expect(chart.notes.single.kind, ChartNoteKind.line);
    expect(chart.highlights, hasLength(1));
    var styled = chartInStyle(chart, dataStyleNamed("Minimal")!);
    expect(styled.notes, chart.notes);
    expect(styled.sheet, chart.sheet);
    expect(styled.sliceColors, isEmpty, reason: "columns keep one colour");
  });

  test("a chart's design: saved only when set, and drawn", () {
    var d = const ChartDesign(track: true, labelsAbove: true, half: true);
    var c =
        const ChartElement(ElementBase(id: "c"), type: ChartType.horizontalBar)
            .copyWith(design: d);
    var back = ChartElement.fromJson(c.toJson(), c.base);
    expect(back.design, d);
    expect(
        const ChartElement(ElementBase(id: "c")).toJson().containsKey("design"),
        isFalse);
    // Every switch drawn, on the types it means something for.
    var all = picksOf(sheet, range, [0, 1, 2, 3, 4], const [2, 3, 4, 5, 6],
        const [0], const [1]);
    for (var type in [
      ChartType.bar,
      ChartType.horizontalBar,
      ChartType.line,
      ChartType.scatter,
      ChartType.pie,
      ChartType.donut
    ]) {
      var kind = chartKinds.firstWhere((k) => k.type == type);
      var chart = presetChart(kind, kind.presets.first, all, like);
      if (chart == null) continue;
      var on = chart.copyWith(
          showValues: true,
          design: const ChartDesign(
              track: true,
              valuesInside: true,
              labelsAbove: true,
              step: true,
              quadrants: true,
              trend: true,
              connect: true,
              half: true,
              gaps: true));
      var recorder = ui.PictureRecorder();
      paintChart(ui.Canvas(recorder), const Rect.fromLTWH(0, 0, 480, 300), on);
      recorder.endRecording().dispose();
    }
  });

  // Ken, 2026-11-17: the research's nine new kinds, each with its ways.
  test("the new kinds: in the gallery, their ways saved, each drawn", () {
    var added = [
      ChartType.diverging,
      ChartType.dumbbell,
      ChartType.waterfall,
      ChartType.heatmap,
      ChartType.bigNumber,
      ChartType.beeswarm,
      ChartType.parliament,
      ChartType.tileMap,
      ChartType.pyramid,
    ];
    for (var t in added) {
      var kind = chartKinds.firstWhere((k) => k.type == t);
      expect(kind.isNew, isTrue);
      expect(chartModes[t.name], isNotNull);
    }
    expect(modeOf(const ChartDesign(), "dumbbell"), "gap");
    expect(modeOf(const ChartDesign(mode: "arrows"), "dumbbell"), "arrows");
    expect(modeOf(const ChartDesign(mode: "nonsense"), "dumbbell"), "gap");
    var c = const ChartElement(ElementBase(id: "c"), type: ChartType.heatmap)
        .copyWith(design: const ChartDesign(mode: "calendar"));
    expect(ChartElement.fromJson(c.toJson(), c.base).design.mode, "calendar");
    expect(ChartElement.fromJson(c.toJson(), c.base).type, ChartType.heatmap);
    // Every way of every new kind drawn from the sheet, at rest and arriving.
    var all = picksOf(sheet, range, [0, 1, 2, 3, 4, 5, 6],
        const [2, 3, 4, 5, 6], const [0], const [1]);
    for (var t in added) {
      var kind = chartKinds.firstWhere((k) => k.type == t);
      for (var (m, _) in chartModes[t.name]!) {
        var chart = presetChart(kind, kind.presets.first, all, like);
        if (chart == null) continue;
        chart = chart.copyWith(design: chart.design.copyWith(mode: m));
        for (var reveal in [1.0, 0.3]) {
          var recorder = ui.PictureRecorder();
          paintChart(
              ui.Canvas(recorder), const Rect.fromLTWH(0, 0, 480, 300), chart,
              reveal: reveal);
          recorder.endRecording().dispose();
        }
      }
    }
  });
}
