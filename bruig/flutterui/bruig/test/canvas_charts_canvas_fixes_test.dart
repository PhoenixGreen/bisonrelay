import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/chart_presets.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/chart_play.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/table_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/data_charts_design.dart'
    show columnKinds, ColumnKind;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_charts_canvas_fixes_test.dart is what building the Charts canvas
// found (Ken, 2026-11-17: "test all of the table and chart designs ... look
// at the process for user experience, gaps, fixes and improvements"): each
// design made from a sheet's ticked columns as the gallery makes it, and
// what it got wrong.

List<List<String>> cellsOf(String tsv) =>
    [for (var l in tsv.trim().split("\n")) l.split("\t")];

/// made is [kind]'s design [name] from [tsv] with [ticks] ticked, as the
/// gallery makes it.
ChartElement? made(ChartType kind, String name, String tsv, List<String> ticks,
    {double width = 480, double height = 300}) {
  var sheet = DataSheet(id: "s", cells: cellsOf(tsv));
  var range = sheet.used;
  var kinds = columnKinds(sheet, range);
  List<int> of(ColumnKind k) => [
        for (var c = 0; c < kinds.length; c++)
          if (kinds[c] == k) c
      ];
  var head = sheet.cells.first;
  var p = picksOf(sheet, range, [for (var t in ticks) head.indexOf(t)],
      of(ColumnKind.numbers), of(ColumnKind.dates), of(ColumnKind.names));
  var k = chartKinds.firstWhere((k) => k.type == kind);
  var preset = k.presets.firstWhere((p) => p.name == name);
  return presetChart(k, preset, p,
      ChartElement(ElementBase(id: "c", width: width, height: height)));
}

Future<ByteData> drawn(ChartElement e) async {
  var rec = ui.PictureRecorder();
  paintChart(ui.Canvas(rec), Rect.fromLTWH(0, 0, e.width, e.height), e);
  var image =
      await rec.endRecording().toImage(e.width.round(), e.height.round());
  return (await image.toByteData())!;
}

const seasons = """Season\tArsenal\tLiverpool\tChelsea
2023\t89\t82\t63
2024\t74\t84\t69
2025\t79\t88\t66""";

const weeks = """Week\tClub\tPts
1\tArsenal\t3
1\tChelsea\t1
2\tArsenal\t6
2\tChelsea\t4""";

void main() {
  test("weeks, seasons and years are when; a group in runs is a name", () {
    ColumnKind kindOf(String tsv, int c) {
      var s = DataSheet(id: "s", cells: cellsOf(tsv));
      return columnKinds(s, s.used)[c];
    }

    expect(kindOf(seasons, 0), ColumnKind.dates, reason: "Season 2023…");
    expect(kindOf(weeks, 0), ColumnKind.dates, reason: "Week 1, 1, 2, 2");
    expect(kindOf("Event\tYear\nLaunch\t2016\nDEX\t2020", 1), ColumnKind.dates,
        reason: "years, whatever the heading");
    expect(kindOf("Club\tDays injured\nA\t3\nB\t12", 1), ColumnKind.numbers,
        reason: "a heading that only holds a date word");
    expect(kindOf("Club\tGroup\tPts\nA\tTop\t9\nB\tTop\t8\nC\tRest\t5", 1),
        ColumnKind.names,
        reason: "runs of words that aren't dates are groups");
    expect(
        kindOf("When\tN\nJan 5\t1\nJan 5\t2\nJan 12\t3", 0), ColumnKind.dates,
        reason: "runs of dates are still dates");
  });

  test("a line of a wide sheet: a line a column, named, the top three lit",
      () async {
    var lines = made(ChartType.line, "Editorial lines", seasons,
        ["Season", "Arsenal", "Liverpool", "Chelsea"])!;
    expect(lines.data.series, hasLength(3));
    expect(lines.data.named, [0, 1, 2]);
    var lit = made(ChartType.line, "Top three lit", seasons,
        ["Season", "Arsenal", "Liverpool", "Chelsea"])!;
    expect(lit.data.series, hasLength(3));
    expect(lit.data.series.map((s) => s.color.a), everyElement(greaterThan(0)));
    var area =
        made(ChartType.area, "Filled area", seasons, ["Season", "Arsenal"])!;
    expect(area.data.categories, ["2023", "2024", "2025"]);
  });

  test("a timeline placed by the years its events happened", () {
    var t = made(ChartType.timeline, "Along a line",
        "Event\tYear\nLaunch\t2016\nDEX\t2020", ["Event", "Year"])!;
    expect(t.data.categories, ["Launch", "DEX"]);
    expect(t.data.series.single.values, [2016, 2020]);
  });

  test("a ranking of a long sheet shows each name once, as at the last date",
      () {
    var bars = made(ChartType.horizontalBar, "Ranked list", weeks,
        ["Week", "Club", "Pts"])!;
    expect(bars.data.categories, ["Arsenal", "Chelsea"]);
    expect(bars.data.series.single.values, [6, 4]);
  });

  test("paired small charts keep their pairs", () {
    var c = made(ChartType.groupedBar, "Small charts",
        "Club\tHome\tAway\nA\t3\t2\nB\t4\t1", ["Club", "Home", "Away"])!;
    expect(c.type, ChartType.groupedBar);
  });

  test("a scatter's points named by the names ticked; the name is saved", () {
    var c = made(
        ChartType.scatter,
        "Labelled points",
        "Club\tWages\tPts\nArsenal\t235\t79\nSpurs\t200\t52",
        ["Club", "Wages", "Pts"])!;
    expect(c.sheet!.pointNames, 0);
    expect(c.data.pointNames, ["Arsenal", "Spurs"]);
    expect(
        SheetLink.fromJson(jsonDecode(jsonEncode(c.sheet!.toJson()))), c.sheet);
  });

  test("a column put in or taken out moves every column a link names", () {
    var doc = CanvasDocument(sheets: [
      DataSheet(id: "s", cells: cellsOf("A\tB\tC\tD\n1\t2\tx\ty")),
    ], elements: [
      const ChartElement(ElementBase(id: "c"),
          sheet: SheetLink("s", CellRange(0, 0, 1, 3),
              labels: 0, series: [1], sortBy: 1, colourBy: 2, pointNames: 3)),
    ]);
    SheetLink link(CanvasDocument d) =>
        (d.elementById("c") as ChartElement).sheet!;
    var put = link(columnsInserted(doc, "s", 1, 1));
    expect(put.series, [2]);
    expect((put.sortBy, put.colourBy, put.pointNames), (2, 3, 4));
    var gone = link(columnsDeleted(doc, "s", 2, 1));
    expect((gone.sortBy, gone.colourBy, gone.pointNames), (1, -1, 2));
  });

  test("a needle gauge of one value reads it against a hundred", () async {
    var g = made(ChartType.gauge, "Needle over bands", "Vote\tYes\nDCP\t84",
        ["Vote", "Yes"])!;
    var a = await drawn(g);
    var b = await drawn(g.copyWith(
        data: g.data.copyWith(series: [
      g.data.series.single.copyWith(values: [100])
    ])));
    expect(a.buffer.asUint8List(), isNot(b.buffer.asUint8List()),
        reason: "84 is not drawn as the whole");
  });

  test("a radar's leader picked out, the others faded", () {
    var r = made(
        ChartType.radar,
        "Leader against the rest",
        "Measure\tA\tB\tC\nPace\t90\t50\t60\nPassing\t80\t60\t55\n"
            "Shooting\t70\t40\t50",
        ["Measure", "A", "B", "C"])!;
    expect(r.data.series[0].color.a, greaterThan(r.data.series[1].color.a));
  });

  test("an up-and-down treemap reads its change; a calendar needs days", () {
    var t = made(
        ChartType.treemap,
        "Up and down",
        "Area\tSize\tChange\nWages\t330\t6\nTransfers\t120\t-12",
        ["Area", "Size", "Change"])!;
    expect(t.data.series, hasLength(2));
    expect(
        made(ChartType.heatmap, "Calendar", "Club\tAug\tSep\nA\t1\t2\nB\t3\t4",
            ["Club", "Aug", "Sep"]),
        isNull);
  });

  test("bullet rows of different sizes each on their own scale", () async {
    var b = made(
        ChartType.bullet,
        "Against target",
        "Measure\tActual\tTarget\nTickets\t41000\t45000\nDebuts\t4\t3",
        ["Measure", "Actual", "Target"])!;
    // Drawn again with no debuts: on the tickets' scale the 4 was a
    // sliver, so the two were all but the same; on its own, its bar shows.
    var a = (await drawn(b)).buffer.asUint8List();
    var none = (await drawn(b.copyWith(
            data: b.data.copyWith(series: [
      b.data.series[0].copyWith(values: [41000, 0]),
      b.data.series[1],
    ]))))
        .buffer
        .asUint8List();
    var differ = 0;
    for (var i = 0; i < a.length; i += 4) {
      if (a[i] != none[i] || a[i + 1] != none[i + 1]) differ++;
    }
    expect(differ, greaterThan(b.width * 10));
  });

  test("a table's words all made smaller to fit, never cut or broken", () {
    var rows = cellsOf("Rank\tPlayer\tGoals\n1\tHaaland\t27\n2\tSalah\t24\n"
        "3\tIsak\t21\n4\tPalmer\t19");
    var roomy = TableElement(
        const ElementBase(id: "t", width: 900, height: 600),
        rows: rows);
    expect(tableTextFit(roomy, const Rect.fromLTWH(0, 0, 900, 600)), 1);
    var cramped = TableElement(
        const ElementBase(id: "u", width: 200, height: 80),
        rows: rows);
    var k = tableTextFit(cramped, const Rect.fromLTWH(0, 0, 200, 80));
    expect(k, lessThan(1), reason: "five rows in 80: smaller words");
    expect(k, greaterThanOrEqualTo(0.25));
    var rec = ui.PictureRecorder();
    paintTable(ui.Canvas(rec), const Rect.fromLTWH(0, 0, 200, 80), cramped);
    rec.endRecording().dispose();
  });

  test("whole numbers stay whole part-way through a race or an arrival", () {
    var a = ChartData.parse("Club\tPts\nArsenal\t3\nSpurs\t1");
    var b = ChartData.parse("Club\tPts\nArsenal\t9\nSpurs\t4");
    var mid = const ChartElement(ElementBase(id: "c"))
        .copyWith(data: chartBlend(a, b, 0.55));
    expect(formatSeries(mid, 0, mid.data.valueAt(0, 0)), "6");
    var counting = const ChartElement(ElementBase(id: "c")).copyWith(data: b);
    expect(formatSeries(counting, 0, 9 * 0.37), "3");
    var decimals = const ChartElement(ElementBase(id: "c"))
        .copyWith(data: ChartData.parse("Year\tDCR\n2016\t2.1\n2017\t5.8"));
    expect(formatSeries(decimals, 0, 2.1), "2.1");
  });

  test("a table's padding shrinks with its words when they must fit", () {
    var rows = cellsOf("Pos\tClub\tP\tW\tD\tL\n1\tArsenal\t20\t14\t4\t2\n"
        "2\tLiverpool\t20\t13\t5\t2");
    var t = TableElement(const ElementBase(id: "t", width: 260, height: 90),
        rows: rows, cellPadding: 16);
    var k = tableTextFit(t, const Rect.fromLTWH(0, 0, 260, 90));
    // Padding of 16 a side in columns as narrow as "L": counted, so not the
    // floor of a quarter.
    expect(k, greaterThan(0.3));
    expect(k, lessThan(1));
  });
}
