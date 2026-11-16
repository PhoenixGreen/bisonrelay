import 'dart:convert';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'canvas_audio_fake.dart';

// canvas_chart_reading_test.dart is how a chart reads its sheet in the
// Charts tab's ways (prototype v6): rows with the same label brought
// together, one date at a time, a line for each word of a column, places
// picked with a gap, marks coloured by a column; and highlights -- top N,
// one, a rule, the rest faded -- worked into the marks the painters draw.

const weeks = [
  ["Date", "Team", "Result", "Scored", "Points"],
  ["16 Aug", "Arsenal", "W", "2", "3"],
  ["16 Aug", "Chelsea", "D", "1", "1"],
  ["16 Aug", "Spurs", "L", "0", "0"],
  ["23 Aug", "Arsenal", "D", "1", "4"],
  ["23 Aug", "Chelsea", "W", "3", "4"],
  ["23 Aug", "Spurs", "W", "2", "3"],
];

const league = [
  ["Team", "Last", "GD", "Points"],
  ["Man City", "W", "5", "9"],
  ["Arsenal", "W", "5", "9"],
  ["Hull", "D", "3", "7"],
  ["Chelsea", "L", "1", "6"],
  ["Brentford", "D", "3", "5"],
  ["Fulham", "L", "-4", "0"],
];

DataSheet sheetOf(List<List<String>> cells) => DataSheet(id: "s", cells: cells);

ChartData read(List<List<String>> cells, SheetLink link,
        {ChartType type = ChartType.bar,
        List<ChartHighlight> highlights = const []}) =>
    chartDataOf(sheetOf(cells), link, const ChartData(),
        type: type, highlights: highlights);

SheetLink linkOf(List<List<String>> cells,
        {required int labels, required List<int> series}) =>
    SheetLink("s", CellRange(0, 0, cells.length - 1, cells.first.length - 1),
        labels: labels, series: series);

void main() {
  group("reading as only a chart can", () {
    test("rows with the same label brought together", () {
      var link = linkOf(weeks, labels: 0, series: [3]).copyWith(group: "total");
      var d = read(weeks, link);
      expect(d.categories, ["16 Aug", "23 Aug"]);
      expect(d.series.single.values, [3, 6]);
      var most = read(weeks, link.copyWith(group: "most"));
      expect(most.series.single.values, [2, 3]);
      var count = read(weeks, link.copyWith(group: "count"));
      expect(count.series.single.values, [3, 3]);
      expect(link.charted, isTrue);
      expect(link.plain, isFalse);
    });

    test("one date at a time: the last, or the one asked for", () {
      var link = linkOf(weeks, labels: 1, series: [4]).copyWith(through: 0);
      expect(read(weeks, link).series.single.values, [4, 4, 3]);
      var first = read(weeks, link.copyWith(at: "16 Aug"));
      expect(first.categories, ["Arsenal", "Chelsea", "Spurs"]);
      expect(first.series.single.values, [3, 1, 0]);
    });

    test("a line for each word of a column", () {
      var link = linkOf(weeks, labels: 0, series: [4]).copyWith(colourBy: 1);
      var d = read(weeks, link, type: ChartType.line);
      expect(d.categories, ["16 Aug", "23 Aug"]);
      expect([for (var s in d.series) s.name], ["Arsenal", "Chelsea", "Spurs"]);
      expect(d.series[1].values, [1, 4]);
      // As bars, the same column colours each bar instead.
      var bars = read(weeks, link.copyWith(group: "total"));
      expect(bars.series.length, 1);
    });

    test("places, with a gap between groups; the bottom few", () {
      var link = linkOf(league, labels: 0, series: [3])
          .copyWith(sortBy: 3, places: "1-2, 5-6");
      var d = read(league, link);
      expect(d.categories, ["Man City", "Arsenal", "…", "Brentford", "Fulham"]);
      expect(d.series.single.values[2].isNaN, isTrue);
      var closed = read(league, link.copyWith(gap: false));
      expect(closed.categories, ["Man City", "Arsenal", "Brentford", "Fulham"]);
      var bottom = read(
          league,
          linkOf(league, labels: 0, series: [3])
              .copyWith(top: 2, bottom: true));
      expect(bottom.categories, ["Brentford", "Fulham"]);
      expect(placesIn("1-3, 16-19, 20"), {1, 2, 3, 16, 17, 18, 19, 20});
    });

    test("coloured by a column: results as a form guide's, numbers a scale",
        () {
      var byResult = read(
          league, linkOf(league, labels: 0, series: [3]).copyWith(colourBy: 1));
      expect(byResult.marks[0], resultColours["w"]);
      expect(byResult.marks[2], resultColours["d"]);
      expect(byResult.marks[3], resultColours["l"]);
      var byGd = read(
          league, linkOf(league, labels: 0, series: [3]).copyWith(colourBy: 2));
      expect(byGd.marks[0], const Color(0xFF2FE08A), reason: "the most, green");
      expect(byGd.marks[5], const Color(0xFFE8645A), reason: "the least, red");
    });

    test("the new options go through JSON", () {
      var link = linkOf(league, labels: 0, series: [3]).copyWith(
          group: "total",
          bottom: true,
          top: 3,
          places: "1-3",
          gap: false,
          colourBy: 1,
          through: 2,
          at: "16 Aug");
      var back = SheetLink.fromJson(jsonDecode(jsonEncode(link.toJson())));
      expect(back, link);
    });
  });

  group("highlights", () {
    var link = linkOf(league, labels: 0, series: [3]);

    test("the top few by a column, in their colour; ties in sheet order", () {
      var d = read(league, link, highlights: const [
        ChartHighlight(reach: ChartReach.top, n: 2, colour: Color(0xFF2FE08A)),
      ]);
      expect(d.marks.take(3), [
        const Color(0xFF2FE08A),
        const Color(0xFF2FE08A),
        null,
      ]);
    });

    test("one picked out, the rest faded; a rule; switched off", () {
      var d = read(league, link, highlights: const [
        ChartHighlight(who: "Chelsea", colour: Color(0xFFF2B33D), fade: true),
      ]);
      expect(d.marks[3], const Color(0xFFF2B33D));
      expect(d.marks[0]!.a, lessThan(0.5), reason: "the rest faded");
      var rule = read(league, link, highlights: const [
        ChartHighlight(
            reach: ChartReach.when,
            by: 2,
            op: "<",
            value: 0,
            colour: Color(0xFFE8645A)),
      ]);
      expect([for (var m in rule.marks) m != null],
          [false, false, false, false, false, true]);
      var off = read(league, link, highlights: const [
        ChartHighlight(who: "Chelsea", off: true),
      ]);
      expect(off.marks, isEmpty);
    });

    test("on lines, a highlight colours the lines it picks out", () {
      var lines = linkOf(weeks, labels: 0, series: [4]).copyWith(colourBy: 1);
      var d = read(weeks, lines, type: ChartType.line, highlights: const [
        ChartHighlight(reach: ChartReach.top, n: 1, colour: Color(0xFF123456)),
      ]);
      // Arsenal and Chelsea both end on 4: the first in the sheet wins.
      expect(d.series[0].color, const Color(0xFF123456));
      expect(d.series[1].color, isNot(const Color(0xFF123456)));
    });

    test("highlights go through JSON, and a change is drawn at once", () {
      const h = ChartHighlight(
          name: "Bottom 2",
          reach: ChartReach.bottom,
          n: 2,
          by: 3,
          colour: Color(0xFFE8645A),
          fade: true,
          named: true);
      expect(ChartHighlight.fromJson(jsonDecode(jsonEncode(h.toJson()))), h);

      var doc = CanvasDocument.fromJson(CanvasDocument(elements: [
        ChartElement(const ElementBase(id: "c", width: 400, height: 300),
            data: ChartData(categories: [
              for (var r in league.skip(1)) r[0]
            ], series: [
              ChartSeries(
                  name: "Points",
                  color: const Color(0xFF4C8DF6),
                  values: [for (var r in league.skip(1)) double.parse(r[3])]),
            ])),
      ]).toJson());
      var c = CanvasController(doc, audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      var chart = c.document.elementById("c") as ChartElement;
      expect(chart.data.marks, isEmpty);
      // Its own sheet has two columns: ranked by its first series.
      c.replaceElement(chart.copyWith(highlights: [h.copyWith(by: -1)]));
      chart = c.document.elementById("c") as ChartElement;
      expect(chart.highlights, [h.copyWith(by: -1)]);
      expect(chart.data.marks.last, const Color(0xFFE8645A));

      // And drawn: bars, a pie and points take the marks.
      for (var type in [
        ChartType.bar,
        ChartType.pie,
        ChartType.scatter,
        ChartType.lollipop
      ]) {
        var recorder = ui.PictureRecorder();
        paintChart(ui.Canvas(recorder), const Rect.fromLTWH(0, 0, 400, 300),
            chart.copyWith(type: type));
        recorder.endRecording().dispose();
      }
    });
  });
}
