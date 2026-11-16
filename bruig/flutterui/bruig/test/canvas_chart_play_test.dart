import 'dart:convert';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/chart_play.dart';
import 'package:bruig/plugin_system/canvas/model/chart_words.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'canvas_audio_fake.dart';

// canvas_chart_play_test.dart is a chart in motion and its live words
// (prototype v6): words in braces worked out from the numbers, whole ones
// kept whole part-way; a chart part-way between two dates, bars between
// their places; playing through its dates without a stop, and through its
// steps, each held then eased into the next. Steps moved on by the
// timeline's marks or by the scenes instead of their own pace; a chart
// gliding to new numbers in the editor; lines sliding between places.

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

  group("steps that follow", () {
    var e = ChartElement(const ElementBase(id: "c"),
        sheet: race.copyWith(through: -1),
        play: 2,
        title: "Whole league",
        follow: ChartStepsFollow.marks.name,
        steps: const [
          ChartStep(name: "All", title: "Whole league"),
          ChartStep(
              name: "Top",
              title: "Top one",
              highlights: [ChartHighlight(reach: ChartReach.top, n: 1)]),
          ChartStep(name: "End", title: "The end"),
        ]);

    test("the marks: a step from each mark on", () {
      // Marks at 2s and 5s at 30 frames a second, given out of order.
      expect(stepByMarks([150, 60], 3, 30, 30), (0, double.infinity));
      expect(stepByMarks([150, 60], 3, 75, 30), (1, 0.5));
      expect(stepByMarks([150, 60], 3, 210, 30), (2, 2.0));
      expect(stepByMarks([10, 20, 30, 40], 3, 45, 30).$1, 2,
          reason: "no further than the last step");
      expect(stepByMarks([], 3, 500, 30), (0, double.infinity));
    });

    test("the scenes: a step in each scene it is in", () {
      expect(stepByScenes([1, 3, 4], 3), 1);
      expect(stepByScenes([1, 3, 4], 4), 2);
      expect(stepByScenes([1, 3, 4], 0), 0, reason: "not in it: the first");
    });

    test("eased into a step, then held; not paced by its own clock", () {
      expect(chartPlaying(e, sheet, 4), same(e));
      var held = chartAtStep(e, sheet, 1, 5);
      expect(held.title, "Top one");
      expect(held.data.marks, isNotEmpty);
      var early = chartAtStep(e, sheet, 1, 0.05);
      expect(early.title, "Whole league", reason: "still most like the first");
      var late = chartAtStep(e, sheet, 1, stepGlide * 0.9);
      expect(late.title, "Top one");
      expect(chartAtStep(e, sheet, 9, 5).title, "The end");
      expect(chartAtStep(e, sheet, 0, 0).title, "Whole league");
    });

    test("what it follows goes through JSON; its own pace by default", () {
      ChartElement round(ChartElement c) => elementFromJson(
              jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>)
          as ChartElement;
      expect(round(e).follow, "marks");
      var own = e.copyWith(follow: "time");
      expect(own.toJson().containsKey("follow"), isFalse);
      expect(round(own).follow, "time");
      expect(ChartStepsFollow.fromName("nonsense"), ChartStepsFollow.time);
    });
  });

  group("gliding to new numbers", () {
    tearDown(chartGlides.clear);
    ChartData points(List<double> v) => ChartData(
        categories: const ["A", "B"],
        series: [ChartSeries(name: "P", color: Colors.blue, values: v)]);

    testWidgets("eased frame by frame, then let go", (tester) async {
      // A frame drawn after [wait], as the stage draws one when asked.
      Future<void> frame([Duration wait = Duration.zero]) async {
        tester.binding.scheduleFrame();
        await tester.pump(wait);
      }

      var beats = chartGlideBeat.value;
      startGlide("g", points([0, 10]));
      await frame();
      expect(glided("g", points([10, 0])).series.single.values, [0, 10],
          reason: "the first frame drawn starts it");
      await frame(chartGlideTime ~/ 2);
      var half = glided("g", points([10, 0])).series.single.values;
      expect(half[0], inExclusiveRange(0, 10));
      expect(half[1], inExclusiveRange(0, 10));
      await frame();
      expect(chartGlideBeat.value, greaterThan(beats),
          reason: "asks for the next frame while under way");
      await frame(chartGlideTime);
      expect(glided("g", points([10, 0])).series.single.values, [10, 0]);
      expect(chartGlides, isEmpty);
    });

    testWidgets("a change of numbers in the editor starts one", (tester) async {
      var doc = CanvasDocument.fromJson(CanvasDocument(elements: [
        ChartElement(const ElementBase(id: "c", width: 400, height: 300),
            data: points([1, 2])),
      ]).toJson());
      var c = CanvasController(doc, audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      var chart = c.document.elementById("c") as ChartElement;
      c.replaceElement(chart.copyWith(title: "Only words"));
      expect(chartGlides, isEmpty, reason: "the same numbers: nothing to ease");
      c.replaceElement(chart.copyWith(data: points([5, 1])));
      expect(chartGlides.keys, ["c"]);
      expect(chartGlides["c"]!.$1.series.single.values, [1, 2]);
      await tester.pump(chartGlideTime * 2);
    });
  });

  test("lines slide between places, as bars do", () {
    List<double> xs(ChartData d) {
      var parts = <ChartPart>[];
      chartParts = parts;
      var recorder = ui.PictureRecorder();
      paintChart(
          ui.Canvas(recorder),
          const Rect.fromLTWH(0, 0, 600, 400),
          ChartElement(const ElementBase(id: "c", width: 600, height: 400),
              type: ChartType.line, data: d));
      chartParts = null;
      recorder.endRecording().dispose();
      return [
        for (var p in parts.where((p) => p.kind == ChartPartKind.mark))
          p.rect.center.dx
      ];
    }

    var d = ChartData(categories: const [
      "A",
      "B",
      "C"
    ], series: [
      ChartSeries(name: "P", color: Colors.blue, values: const [1, 2, 3]),
    ]);
    var still = xs(d);
    var moving = xs(d.copyWith(slots: [0.5, 0.5, 2]));
    expect(moving[0], greaterThan(still[0]));
    expect(moving[1], lessThan(still[1]));
    expect(moving[0], closeTo(moving[1], 0.01), reason: "passing each other");
    expect(moving[2], closeTo(still[2], 0.01));
  });
}
