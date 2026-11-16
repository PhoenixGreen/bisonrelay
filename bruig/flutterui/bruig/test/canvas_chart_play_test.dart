import 'dart:convert';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/chart_play.dart';
import 'package:bruig/plugin_system/canvas/model/chart_words.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_chart_play_test.dart is a chart in motion and its live words
// (prototype v6): words in braces worked out from the numbers, whole ones
// kept whole part-way; a chart part-way between two dates, bars between
// their places; playing through its dates without a stop, and through its
// steps, each held then eased into the next.

const weeks = [
  ["Date", "Team", "Points"],
  ["16 Aug", "Arsenal", "3"],
  ["16 Aug", "Chelsea", "1"],
  ["16 Aug", "Spurs", "0"],
  ["23 Aug", "Arsenal", "4"],
  ["23 Aug", "Chelsea", "4"],
  ["23 Aug", "Spurs", "6"],
];

const sheet = DataSheet(id: "s", cells: weeks);
final range = CellRange(0, 0, weeks.length - 1, 2);
final race =
    SheetLink("s", range, labels: 1, series: [2], through: 0, sortBy: 2);

ChartData read(SheetLink link) => chartDataOf(sheet, link, const ChartData());

void main() {
  group("live words", () {
    var data = read(race);

    test("worked out from the numbers drawn", () {
      expect(data.categories, ["Spurs", "Arsenal", "Chelsea"]);
      expect(liveWords(data, "{leader by Points} top on {most Points}"),
          "Spurs top on 6");
      expect(liveWords(data, "{last by Points}, {least Points}"), "Chelsea, 4");
      expect(liveWords(data, "{Points of Arsenal}"), "4");
      expect(liveWords(data, "{total of points} in all, {average of Points}"),
          "14 in all, 4.7");
      expect(liveWords(data, "{count} clubs on {date}"), "3 clubs on 23 Aug");
      expect(liveWords(data, "No braces"), "No braces");
      expect(liveWords(data, "{who knows}"), "{?who knows}");
      expect(unknownWords(data, "{date} {nope}"), ["nope"]);
    });

    test("words to offer", () {
      expect([for (var (n, _) in wordChoices(data)) n],
          containsAll(["Date", "Leader", "Most Points", "Points of Spurs"]));
    });
  });

  group("in motion", () {
    test("part-way between two dates: numbers and places between", () {
      var a = read(race.copyWith(at: "16 Aug"));
      var b = read(race.copyWith(at: "23 Aug"));
      expect(a.categories, ["Arsenal", "Chelsea", "Spurs"]);
      var half = chartBlend(a, b, 0.5);
      expect(half.categories, b.categories);
      // Spurs: from 0 in third place to 6 in first.
      expect(half.series.single.values.first, 3);
      expect(half.slotAt(0), 1, reason: "half way from slot 2 to slot 0");
      // Whole numbers stay whole in the words, part-way.
      expect(liveWords(half, "{Points of Chelsea}"), anyOf("2", "3"));
      expect(chartBlend(a, b, 0), same(a));
      expect(chartBlend(a, b, 1), same(b));
    });

    test("playing through its dates, a second each, without a stop", () {
      var e = ChartElement(const ElementBase(id: "c"),
          type: ChartType.horizontalBar, sheet: race, play: 1);
      expect(throughDates(sheet, race), ["16 Aug", "23 Aug"]);
      expect(playLength(e, sheet), 1);
      var start = chartPlaying(e, sheet, 0);
      expect(start.data.at, "16 Aug");
      expect(start.data.categories.first, "Arsenal");
      var mid = chartPlaying(e, sheet, 0.5);
      expect(mid.data.slots, isNotEmpty, reason: "bars on their way");
      var end = chartPlaying(e, sheet, 5);
      expect(end.data.at, "23 Aug");
      expect(end.data.categories.first, "Spurs");
      // Still, it is itself.
      expect(chartPlaying(e.copyWith(play: 0), sheet, 1), isA<ChartElement>());
    });

    test("through its steps: each held, then eased into the next", () {
      var link = race.copyWith(through: -1);
      var e = ChartElement(const ElementBase(id: "c"),
          sheet: link,
          play: 2,
          title: "Whole league",
          steps: const [
            ChartStep(name: "All", title: "Whole league"),
            ChartStep(
                name: "Top",
                title: "{leader by Points} leads",
                highlights: [
                  ChartHighlight(reach: ChartReach.top, n: 1, fade: true)
                ]),
          ]);
      expect(playLength(e, sheet), 2);
      expect(chartPlaying(e, sheet, 0.5).title, "Whole league");
      expect(chartPlaying(e, sheet, 0.5).data.marks, isEmpty,
          reason: "held on the first step");
      var second = chartPlaying(e, sheet, 4);
      expect(second.title, "{leader by Points} leads");
      expect(second.highlights, hasLength(1));
      expect(second.data.marks, isNotEmpty);
    });

    test("play and steps go through JSON", () {
      var e = ChartElement(const ElementBase(id: "c"),
          play: 1.5,
          stepAt: 1,
          steps: const [
            ChartStep(name: "A", title: "One", at: "16 Aug"),
            ChartStep(
                name: "B",
                notes: [ChartNote(text: "Average")],
                highlights: [ChartHighlight(who: "Spurs")]),
          ]);
      var back = elementFromJson(
              jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>)
          as ChartElement;
      expect(back.play, 1.5);
      expect(back.stepAt, 1);
      expect(back.steps, e.steps);
    });
  });
}
