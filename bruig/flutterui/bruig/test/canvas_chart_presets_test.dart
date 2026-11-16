import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/chart_presets.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_styles.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/table_presets.dart';
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

  // The research's motion rules: a line drawn steadily, bars easing out
  // without overshooting, staggered a little.
  test("designs arrive by the motion rules", () {
    var all = picksOf(
        sheet, range, [0, 1, 2], const [2, 3, 4, 5, 6], const [0], const [1]);
    for (var k in chartKinds) {
      for (var pr in k.presets) {
        var chart = presetChart(k, pr, all, like);
        if (chart == null || !chart.animation.on) continue;
        var a = chart.animation;
        expect(
            a.ease,
            isNot(
                anyOf(ChartEase.overshoot, ChartEase.bounce, ChartEase.spring)),
            reason: "${k.name} · ${pr.name}: no overshoot on data marks");
        if (a.preset == ChartAnimationPreset.drawOn) {
          expect(a.ease, ChartEase.linear, reason: "${k.name} · ${pr.name}");
        }
      }
    }
  });

  // Ken, 2026-11-17: the remaining designs -- every way of every kind
  // drawn; the top and the rest; a histogram.
  test("no two designs of a kind share a name; nor do two of a table", () {
    for (var k in chartKinds) {
      var names = [for (var p in k.presets) p.name];
      expect(names.toSet(), hasLength(names.length), reason: k.name);
    }
    for (var k in tableKinds) {
      var names = [for (var p in k.presets) p.name];
      expect(names.toSet(), hasLength(names.length), reason: k.name);
    }
  });

  test("every way of every kind draws, arriving and at rest", () {
    var all = picksOf(sheet, range, [0, 1, 2, 3, 4, 5, 6],
        const [2, 3, 4, 5, 6], const [0], const [1]);
    for (var k in chartKinds) {
      var ways = chartModes[k.type.name];
      if (ways == null) continue;
      for (var pr in k.presets) {
        var chart = presetChart(k, pr, all, like);
        if (chart == null) continue;
        for (var (m, _) in ways) {
          var c = chart.copyWith(design: chart.design.copyWith(mode: m));
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
  });

  test("the top five and everyone else; a histogram's counts", () {
    var link = const SheetLink("s", CellRange(0, 0, 6, 6),
        labels: 1, series: [2], sortBy: 2, top: 2, others: true);
    var d = chartDataOf(sheet, link, const ChartData());
    expect(d.categories.last, "All others");
    expect(d.categories, hasLength(3));
    var shown = d.series.single.values;
    // Each club once (its latest points): Arsenal 6, Chelsea 4, and Spurs'
    // 3 as everyone else.
    expect(d.categories.take(2), ["Arsenal", "Chelsea"]);
    expect(shown, [6, 4, 3], reason: "nothing lost");
    expect(SheetLink.fromJson(link.toJson()), link);
    var bins = chartDataOf(
        sheet,
        link.copyWith(top: 0, others: false, bins: 3, sortBy: -1),
        const ChartData());
    expect(bins.categories, hasLength(3));
    expect(bins.series.single.values.fold(0.0, (a, b) => a + b), 6);
  });

  // Ken, 2026-11-17: "do the Not done list" -- a flow as where the money
  // goes, bubbles in groups, a radar against another.
  test("the last designs: money, groups and against another", () async {
    ChartPreset named(ChartType t, String n) => chartKinds
        .firstWhere((k) => k.type == t)
        .presets
        .firstWhere((p) => p.name == n);
    expect(
        named(ChartType.sankey, "Where the money goes")
            .apply(like, picks([2]))
            .design
            .mode,
        "money");
    expect(
        named(ChartType.radar, "Against another")
            .apply(like, picks([2]))
            .design
            .mode,
        "compare");
    var groups = named(ChartType.bubbles, "In groups");
    // Grouped by a second column of names, else a cluster a column of
    // numbers; with neither, it says what it needs.
    var byName =
        picksOf(sheet, range, [1, 0, 2], const [2], const [], const [1, 0]);
    expect(groups.needs!(byName), isNull);
    expect(
        groups.needs!(
            picksOf(sheet, range, [1, 2], const [2], const [], const [1])),
        isNotNull);

    // A colour-by column of words: each bubble's group.
    var clubs = const DataSheet(id: "g", cells: [
      ["Club", "Group", "Pts"],
      ["Arsenal", "Top four", "74"],
      ["City", "Top four", "71"],
      ["Spurs", "Chasing", "52"],
    ]);
    var d = chartDataOf(
        clubs,
        const SheetLink("g", CellRange(0, 0, 3, 2),
            labels: 0, series: [2], colourBy: 1),
        const ChartData());
    expect(d.groups, ["Top four", "Top four", "Chasing"]);
    expect(d.marks.toSet(), hasLength(2), reason: "a colour a group");

    Future<Set<int>> colours(ChartElement e) async {
      var recorder = ui.PictureRecorder();
      paintChart(ui.Canvas(recorder), const Rect.fromLTWH(0, 0, 480, 300), e);
      var image = await recorder.endRecording().toImage(480, 300);
      var b = (await image.toByteData())!;
      return {
        for (var i = 0; i < b.lengthInBytes; i += 4)
          if (b.getUint8(i + 3) == 255) b.getUint32(i)
      };
    }

    int rgba(Color c) =>
        ((c.r * 255).round() << 24) |
        ((c.g * 255).round() << 16) |
        ((c.b * 255).round() << 8) |
        255;
    var flow = like.copyWith(
        type: ChartType.sankey,
        showXLabels: false,
        data: ChartData.parse(
            "Flow\tGBP\nTickets > Revenue\t110\nTV > Revenue\t260\nRevenue > Wages\t330\nRevenue > Profit\t40"));
    // Profit's node in the accent; drawn a colour a node, nothing is.
    const accent = Color(0xFFF2B33D);
    await expectLater(
        colours(flow.copyWith(design: const ChartDesign(mode: "money"))),
        completion(contains(rgba(accent))));
    await expectLater(colours(flow), completion(isNot(contains(rgba(accent)))));
  });

  // Ken, 2026-11-17 (the improvements report's third item): the gallery
  // ranks kinds by how well they suit the ticked columns, and says why.
  test("how well a kind suits the columns ticked, and why", () {
    DataSheet sheetOf(String tsv) => DataSheet(
        id: "f", cells: [for (var l in tsv.split("\n")) l.split("\t")]);
    Picks pick(DataSheet s, {List<int> names = const [0]}) =>
        picksOf(s, s.used, [0, 1], const [1], const [], names);
    KindFit fit(ChartType t, DataSheet s) =>
        kindFit(chartKinds.firstWhere((k) => k.type == t), pick(s));
    var eight = sheetOf("Club\tPts\n"
        "${[for (var i = 0; i < 8; i++) "C$i\t${20 - i}"].join("\n")}");
    expect(fit(ChartType.horizontalBar, eight).score, 1);
    expect(fit(ChartType.pie, eight).poor, isTrue);
    expect(fit(ChartType.pie, eight).why, contains("8 parts"));
    expect(fit(ChartType.gauge, eight).why, contains("first of 8"));
    expect(fit(ChartType.funnel, eight).score, 1, reason: "they fall");
    var rising = sheetOf("Stage\tN\nA\t1\nB\t5\nC\t9");
    expect(fit(ChartType.funnel, rising).poor, isTrue);
    expect(fit(ChartType.tileMap, eight).why, contains("grid"));
    var signed = sheetOf("Club\tChange\nA\t5\nB\t-3\nC\t2");
    expect(fit(ChartType.pie, signed).why, contains("below zero"));
    expect(fit(ChartType.diverging, signed).score, 1);
  });
}
