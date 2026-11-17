import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/chart_presets.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/chart_timelines.dart';
import 'package:bruig/plugin_system/canvas/ui/data/data_charts_design.dart'
    show columnKinds, ColumnKind;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_chart_timelines_test.dart is the timeline's researched ways (Ken,
// 2026-11-17: "more designs for the timeline chart"): spans packed into
// rows, swimlanes, eras, a value line, cards, bubbles, a serpentine and
// "we are here" -- each drawing every event, and the gallery reading
// starts, ends, groups and words from the ticked columns.

const history = [
  ["Event", "Start", "End", "Track", "Price", "About"],
  ["Launch", "2016", "", "Chain", "1", "The chain starts, with no ICO at all."],
  [
    "Politeia",
    "2017",
    "2018",
    "Governance",
    "40",
    "Proposals and votes, public."
  ],
  [
    "Lightning",
    "2018",
    "2019",
    "Payments",
    "20",
    "Instant payments over channels."
  ],
  [
    "DCRDEX",
    "2019",
    "2020",
    "Trading",
    "13",
    "Trading coins with no middleman."
  ],
  [
    "Treasury",
    "2021",
    "",
    "Governance",
    "180",
    "Stakeholders approve each spend."
  ],
  [
    "Bison Relay",
    "2021",
    "2023",
    "Messaging",
    "20",
    "Private messages, paid for."
  ],
];

const area = Rect.fromLTWH(0, 0, 800, 450);

List<ChartPart> marksOf(ChartElement e) {
  var found = chartParts = <ChartPart>[];
  var rec = ui.PictureRecorder();
  paintChart(ui.Canvas(rec), area, e);
  rec.endRecording().dispose();
  chartParts = null;
  return [
    for (var p in found)
      if (p.kind == ChartPartKind.mark) p
  ];
}

/// timeline is the history as a timeline drawn [mode]'s way, its second
/// series the ends (or, with [prices], the prices), grouped by its track.
ChartElement timeline(String mode, {bool prices = false}) {
  var rows = history.skip(1).toList();
  var data = ChartData(
    categories: [for (var r in rows) r[0]],
    series: [
      ChartSeries(
          name: "Start",
          color: const Color(0xFF3366FF),
          values: [for (var r in rows) double.parse(r[1])]),
      ChartSeries(
          name: prices ? "Price" : "End",
          color: const Color(0xFFFF6633),
          values: [
            for (var r in rows) double.tryParse(r[prices ? 4 : 2]) ?? double.nan
          ]),
    ],
    groups: [for (var r in rows) r[3]],
    pointNames: [for (var r in rows) r[5]],
  );
  return ChartElement(const ElementBase(id: "t", width: 800, height: 450),
      type: ChartType.timeline, data: data, design: ChartDesign(mode: mode));
}

void main() {
  setUp(() => timelineNow = () => 2022.5);

  test("every way is offered and draws every event", () {
    var ways = {for (var (w, _) in chartModes["timeline"]!) w};
    expect(ways, containsAll(timelineWays));
    for (var way in timelineWays) {
      var prices = way == "value" || way == "bubbles";
      var marks = marksOf(timeline(way, prices: prices));
      var rows = {for (var m in marks) m.index};
      expect(rows, hasLength(history.length - 1), reason: way);
      for (var m in marks) {
        expect(area.inflate(1).contains(m.rect.center), isTrue,
            reason: "$way: ${m.index} at ${m.rect}");
      }
    }
  });

  test("evenly spaced: in order, equal steps, whatever the dates", () {
    var e = timeline("").copyWith(design: const ChartDesign(even: true));
    var xs = {for (var m in marksOf(e)) m.rect.center.dx.round()}.toList()
      ..sort();
    // 2016, 2017, 2018, 2019 and 2021 (two events): five places.
    expect(xs, hasLength(5));
    var steps = [for (var i = 1; i < xs.length; i++) xs[i] - xs[i - 1]];
    for (var d in steps) {
      expect(d, closeTo(steps.first, 2));
    }
    // By date instead, 2019 to 2021 is twice as far as 2016 to 2017.
    var dated = {for (var m in marksOf(timeline(""))) m.rect.center.dx.round()}
        .toList()
      ..sort();
    expect((dated[4] - dated[3]) / (dated[1] - dated[0]), closeTo(2, 0.1));
    expect(ChartDesign.fromJson(const ChartDesign(even: true).toJson()).even,
        isTrue);
  });

  test("the same start: each group measured from its own first", () {
    var marks = {for (var m in marksOf(timeline("aligned"))) m.index: m.rect};
    // Launch (chain, 2016) and Politeia (governance, 2017) both start their
    // lanes: the same x.
    expect(marks[0]!.left, closeTo(marks[1]!.left, 12));
    // Treasury (governance, 2021) four years on from Politeia.
    expect(marks[4]!.left, greaterThan(marks[1]!.left + 50));
  });

  test("spans: events that overlap take separate rows, the rest share", () {
    var marks = {for (var m in marksOf(timeline("spans"))) m.index: m.rect};
    // Politeia (2017-18) and Launch (2016) fit one row; Treasury and
    // Bison Relay both start in 2021, so they can't.
    expect(marks[4]!.center.dy, isNot(closeTo(marks[5]!.center.dy, 1)));
    // A bar as long as its span: Bison Relay's two years twice
    // Lightning's one.
    expect(marks[5]!.width / marks[2]!.width, closeTo(2, 0.05));
  });

  test("swimlanes: a lane a group, in order of first appearance", () {
    var marks = {for (var m in marksOf(timeline("lanes"))) m.index: m.rect};
    // Politeia and Treasury are both governance: one lane.
    expect(marks[1]!.center.dy, closeTo(marks[4]!.center.dy, 30));
    // Chain, then Governance, then Payments, down the page.
    expect(marks[0]!.center.dy, lessThan(marks[1]!.center.dy));
    expect(marks[1]!.center.dy, lessThan(marks[2]!.center.dy));
  });

  test("bubbles: sized by number, the largest the treasury vote's", () {
    var marks = {
      for (var m in marksOf(timeline("bubbles", prices: true))) m.index: m.rect
    };
    var biggest = marks.entries
        .reduce((a, b) => a.value.width >= b.value.width ? a : b)
        .key;
    expect(biggest, 4);
  });

  test("cards: alternating sides, none overlapping one on its side", () {
    var cards = [
      for (var m in marksOf(timeline("cards"))) m.rect,
    ];
    for (var k = 0; k + 2 < cards.length; k++) {
      expect(cards[k].overlaps(cards[k + 2]), isFalse, reason: "$k");
      expect(cards[k].center.dx < area.center.dx,
          isNot(cards[k + 1].center.dx < area.center.dx));
    }
  });

  test("a serpentine draws on: half way, the later events not yet there", () {
    var e = timeline("serpentine").copyWith(
        animation: const ChartAnimation(preset: ChartAnimationPreset.drawOn));
    var found = chartParts = <ChartPart>[];
    var rec = ui.PictureRecorder();
    paintChart(ui.Canvas(rec), area, e, reveal: 0.4);
    rec.endRecording().dispose();
    chartParts = null;
    var shown = {
      for (var p in found)
        if (p.kind == ChartPartKind.mark) p.index
    };
    expect(shown, isNotEmpty);
    expect(shown.length, lessThan(history.length - 1));
  });

  group("the gallery", () {
    var sheet = const DataSheet(id: "h", cells: history);
    var range = const CellRange(0, 0, 6, 5);
    late Picks all;
    setUp(() {
      var kinds = columnKinds(sheet, range);
      List<int> of(ColumnKind k) => [
            for (var c = 0; c < kinds.length; c++)
              if (kinds[c] == k) c
          ];
      all = picksOf(sheet, range, const [0, 1, 2, 3, 4, 5],
          of(ColumnKind.numbers), of(ColumnKind.dates), of(ColumnKind.names));
    });
    var kind = chartKinds.firstWhere((k) => k.type == ChartType.timeline);
    const like = ChartElement(ElementBase(id: "c", width: 600, height: 400));
    ChartElement made(String name) => presetChart(
        kind, kind.presets.firstWhere((p) => p.name == name), all, like)!;

    test("its dates place it, not the price ticked beside them", () {
      expect(all.dates, [1, 2]);
      var line = made("Along a line");
      expect(line.sheet!.series, [1]);
      expect(line.sheet!.labels, 0);
    });

    test("spans read the ends, swimlanes the track, cards the words", () {
      var spans = made("Spans");
      expect(spans.sheet!.series, [1, 2]);
      expect(spans.design.mode, "spans");
      var lanes = made("Swimlanes");
      expect(lanes.sheet!.colourBy, 3);
      var cards = made("Cards");
      expect(cards.sheet!.pointNames, 5);
      var value = made("On a value line");
      expect(value.sheet!.series, [1, 4]);
    });

    test("each new design says what it needs without it", () {
      var bare = picksOf(
          sheet, range, const [0, 1], const [4], const [1, 2], const [0, 3, 5]);
      for (var name in ["Spans", "Era bands", "On a value line"]) {
        var p = kind.presets.firstWhere((p) => p.name == name);
        expect(p.needs?.call(bare), isNotNull, reason: name);
      }
    });
  });
}
