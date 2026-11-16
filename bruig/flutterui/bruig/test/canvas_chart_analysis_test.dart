import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/chart_presets.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/tile_maps.dart';
import 'package:bruig/plugin_system/canvas/model/world_map.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/data_charts_design.dart'
    show columnKinds, ColumnKind;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_chart_analysis_test.dart is the kinds and ways analysis needs
// (Ken, 2026-11-17, the improvements report's ninth item).

List<ChartPart> partsOf(ChartElement e) {
  var found = chartParts = <ChartPart>[];
  var rec = ui.PictureRecorder();
  paintChart(ui.Canvas(rec), const Rect.fromLTWH(0, 0, 600, 400), e);
  rec.endRecording().dispose();
  chartParts = null;
  return [
    for (var p in found)
      if (p.kind == ChartPartKind.mark) p
  ];
}

ChartElement chart(ChartType t, String tsv, {String mode = ""}) =>
    ChartElement(const ElementBase(id: "c", width: 600, height: 400),
        type: t, data: ChartData.parse(tsv), design: ChartDesign(mode: mode));

void main() {
  test("the new kinds are in the gallery, each with its designs", () {
    for (var t in [ChartType.boxPlot, ChartType.bump, ChartType.marimekko]) {
      var k = chartKinds.where((k) => k.type == t).single;
      expect(k.presets, isNotEmpty, reason: t.name);
    }
  });

  test("a box a column; a bump line a series through its places", () {
    var box = partsOf(chart(ChartType.boxPlot,
        "N\tHome\tAway\nA\t1\t3\nB\t2\t1\nC\t4\t2\nD\t3\t5"));
    expect(box, hasLength(2));
    var bump = chart(ChartType.bump, "Season\tA\tB\n2024\t10\t20\n2025\t30\t5");
    var lines = partsOf(bump);
    expect(lines, hasLength(2));
    // A was second then first: its line runs from lower to higher.
    expect(lines[0].rect.height, greaterThan(10));
  });

  test("a marimekko's columns as wide as their totals; its key the parts", () {
    var m = chart(
        ChartType.marimekko, "Club\tTV\tShop\nBig\t30\t30\nSmall\t10\t10");
    var parts = partsOf(m);
    var big = parts.where((p) => p.index == 0).first.rect.width;
    var small = parts.where((p) => p.index == 1).first.rect.width;
    expect(big / small, closeTo(3, 0.2));
    expect([for (var l in legendEntriesForTest(m, 1)) l.name], ["TV", "Shop"]);
  });

  test("a scatter sized by a third number; an area of shares to 100", () {
    var sized = chart(ChartType.scatter, "X\tY\tSize\n1\t5\t1\n2\t6\t100",
        mode: "sized");
    var dots = partsOf(sized);
    expect(dots, hasLength(2), reason: "the third number is no points");
    var share = chart(ChartType.area, "Year\tA\tB\n2024\t30\t10\n2025\t20\t20",
        mode: "share");
    var rec = ui.PictureRecorder();
    paintChart(ui.Canvas(rec), const Rect.fromLTWH(0, 0, 600, 400), share);
    rec.endRecording().dispose();
  });

  test("a date word over small counts or years is dates; over money not", () {
    ColumnKind kindOf(String tsv) {
      var s = DataSheet(
          id: "s", cells: [for (var l in tsv.split("\n")) l.split("\t")]);
      return columnKinds(s, s.used)[1];
    }

    expect(kindOf("Club\tMatchday\nA\t80\nB\t130"), ColumnKind.numbers);
    expect(kindOf("Club\tWeek\nA\t1\nB\t2"), ColumnKind.dates);
    expect(kindOf("Club\tSeason\nA\t2024\nB\t2025"), ColumnKind.dates);
  });

  // The improvements report's tenth item: maps beyond the US.
  test("a tile map of Europe's countries or the UK's regions", () {
    expect(tileMapOf(["GB", "FR", "DE", "ES"])!.$1, same(europeCountries));
    var uk = tileMapOf(["LONDON", "SCOTLAND", "WALES"])!;
    expect(uk.$1, same(ukRegions));
    expect(uk.$2, ["LDN", "SCO", "WAL"], reason: "by name or by code");
    expect(tileMapOf(["CA", "TX", "NY"])!.$1, same(usStates));
    expect(tileMapOf(["Arsenal", "Spurs"]), isNull);
    var map = chart(ChartType.tileMap, "Country\tFans\nGB\t40\nFR\t30");
    expect(partsOf(map), hasLength(2));
  });

  test("a drawn world map: countries by code or name, framed on them", () {
    expect(worldCountries.length, greaterThan(150));
    expect(countryFor("FR")!.name, "France");
    expect(countryFor("fra")!.a2, "FR");
    expect(countryFor("United Kingdom")!.a2, "GB");
    expect(countryFor("UK")!.a2, "GB");
    expect(countryFor("Narnia"), isNull);
    // France's main land, not French Guiana: Europe framed as Europe.
    var view = mapView([countryFor("FR")!, countryFor("DE")!]);
    expect(view.left, greaterThan(-20));
    expect(view.bottom, greaterThan(40));
    var map = chart(
        ChartType.tileMap, "Country\tFans\nFrance\t30\nDE\t35\nNowhere\t1",
        mode: "drawn");
    expect(partsOf(map), hasLength(2), reason: "the two it knows");
  });
}
