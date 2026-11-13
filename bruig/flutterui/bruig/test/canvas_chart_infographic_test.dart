import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/render/chart_infographic.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_chart_infographic_test.dart is the infographic chart types (Ken,
// 2026-11-13: "I'd like all 6 suggestions and any other infographic
// elements you think would be useful"): gauge, pictogram, sankey, treemap,
// timeline, funnel, bubbles, bullet, slope, share bar and lollipop -- each
// drawn, arriving an item at a time, and their layouts sound.

const samples = {
  ChartType.gauge: "Cat\tShare\nMined\t84\nTo come\t16",
  ChartType.pictogram: "Cat\tShare\nStaked\t62\nNot\t38",
  ChartType.sankey:
      "Cat\tReward\nStakeholders\t89\nTreasury\t10\nMiners\t1\nTreasury > Development\t6",
  ChartType.treemap: "Cat\tDCR\nA\t420\nB\t160\nC\t110\nD\t60\nE\t40",
  ChartType.timeline: "Cat\tYear\nLaunch\t2016\nDCRDEX\t2020\nv2.1.7\t2026",
  ChartType.funnel: "Cat\tN\nBought\t1000\nLive\t820\nVoted\t600",
  ChartType.bubbles: "Cat\tDCR\nStaked\t62\nMixed\t67\nTreasury\t4",
  ChartType.bullet: "Cat\tNow\tTarget\nStaked\t62\t50\nMixed\t67\t60",
  ChartType.slope: "Cat\t2020\t2026\nStaked\t50\t62\nMixed\t20\t67",
  ChartType.shareBar: "Cat\tShare\nPoS\t89\nTreasury\t10\nPoW\t1",
  ChartType.lollipop: "Cat\tYes\nDCP-0012\t99.9\nDCP-0013\t99.98",
};

ChartElement chart(ChartType type, String tsv,
        {ChartAnimation animation = const ChartAnimation()}) =>
    ChartElement(const ElementBase(id: "c", width: 400, height: 260),
        type: type,
        data: ChartData.parse(tsv),
        title: "",
        showValues: true,
        animation: animation);

Future<ByteData> drawn(ChartElement e, {double reveal = 1}) async {
  var rec = ui.PictureRecorder();
  paintChart(ui.Canvas(rec), const ui.Rect.fromLTWH(0, 0, 400, 260), e,
      reveal: reveal);
  var image = await rec.endRecording().toImage(400, 260);
  return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
}

int inked(ByteData b) {
  var n = 0;
  for (var i = 3; i < b.lengthInBytes; i += 4) {
    if (b.getUint8(i) > 0) n++;
  }
  return n;
}

void main() {
  test("every infographic type is in the list, after the others", () {
    expect(samples.keys.toSet(),
        ChartType.values.where((t) => t.isInfographic).toSet());
    for (var t in samples.keys) {
      expect(t.isCircular, isTrue, reason: "${t.name}: no axes");
    }
  });

  group("each draws", () {
    for (var MapEntry(key: type, value: tsv) in samples.entries) {
      test(type.name, () async {
        var full = inked(await drawn(chart(type, tsv)));
        expect(full, greaterThan(400), reason: "something drawn");
        // Arriving an item at a time: part way, less is drawn.
        var e = chart(type, tsv,
            animation:
                const ChartAnimation(preset: ChartAnimationPreset.popIn));
        var half = inked(await drawn(e, reveal: 0.3));
        expect(half, lessThan(full), reason: "part way in");
        // With nothing to draw, nothing breaks.
        await drawn(chart(type, "Cat\tA"));
      });
    }
  });

  // Ken's infographic: a timeline in a short box had its words past the
  // box's edges, cut -- "Decred 2.0" half gone.
  test("a short timeline keeps its words inside its box", () async {
    var e = ChartElement(const ElementBase(id: "t", width: 400, height: 90),
        type: ChartType.timeline,
        data: ChartData.parse(samples[ChartType.timeline]!),
        title: "",
        showValues: true);
    var rec = ui.PictureRecorder();
    var canvas = ui.Canvas(rec);
    // Not clipped to its box, so what goes past it shows.
    paintInfographic(canvas, const ui.Rect.fromLTWH(0, 100, 400, 90), e, 1);
    var image = await rec.endRecording().toImage(400, 300);
    var b = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    var outside = 0;
    for (var y = 0; y < 300; y++) {
      if (y >= 100 && y < 190) continue;
      for (var x = 0; x < 400; x++) {
        if (b.getUint8((y * 400 + x) * 4 + 3) > 0) outside++;
      }
    }
    expect(outside, 0);
  });

  test("a treemap's tiles fill its box without overlapping", () {
    var values = <double>[420, 160, 110, 60, 40];
    var area = const ui.Rect.fromLTWH(0, 0, 400, 260);
    var rects = treemapRects(values, area);
    var total = values.fold<double>(0, (t, v) => t + v);
    for (var (i, r) in rects.indexed) {
      expect(r.width * r.height,
          closeTo(area.width * area.height * values[i] / total, 1),
          reason: "tile $i as big as its share");
      expect(
          area.inflate(0.01).contains(r.topLeft) &&
              area.inflate(0.01).contains(r.bottomRight),
          isTrue);
      for (var j = i + 1; j < rects.length; j++) {
        var o = r.intersect(rects[j]);
        expect(o.width <= 0.01 || o.height <= 0.01, isTrue,
            reason: "$i and $j apart");
      }
    }
  });

  test("bubbles: areas by value, none overlapping, all in the box", () {
    var values = <double>[62, 67, 4, 20];
    var area = const ui.Rect.fromLTWH(0, 0, 400, 260);
    var circles = bubbleCircles(values, area);
    for (var (i, (c, r)) in circles.indexed) {
      expect(r * r / (circles[0].$2 * circles[0].$2),
          closeTo(values[i] / values[0], 1e-6));
      expect(
          area.inflate(0.5).contains(c - ui.Offset(r, r)) &&
              area.inflate(0.5).contains(c + ui.Offset(r, r)),
          isTrue,
          reason: "bubble $i inside");
      for (var j = i + 1; j < circles.length; j++) {
        expect((circles[j].$1 - c).distance,
            greaterThanOrEqualTo(r + circles[j].$2 - 0.01));
      }
    }
  });

  test("a sankey reads 'From > To', and a lone name from the series", () {
    var flows =
        sankeyFlows(chart(ChartType.sankey, samples[ChartType.sankey]!));
    expect(flows.map((f) => "${f.from}>${f.to}=${f.value}"), [
      "Reward>Stakeholders=89.0",
      "Reward>Treasury=10.0",
      "Reward>Miners=1.0",
      "Treasury>Development=6.0",
    ]);
  });

  test("a pictogram shares its icons out as a waffle does", () {
    expect(waffleCells([62, 38], cells: 10), [6, 4]);
    var e = chart(ChartType.pictogram, samples[ChartType.pictogram]!)
        .copyWith(pictoShape: PictoShape.coin, pictoCount: 20);
    var back = ChartElement.fromJson(e.props(), e.base);
    expect(back.pictoShape, PictoShape.coin);
    expect(back.pictoCount, 20);
    for (var s in PictoShape.values) {
      expect(pictoPath(s, const ui.Rect.fromLTWH(0, 0, 40, 40)).getBounds(),
          isNot(ui.Rect.zero),
          reason: s.name);
    }
  });

  group("a header of years", () {
    // A slope's two ends by year were read as a row of data.
    test("names the series", () {
      var d = ChartData.parse("Cat\t2020\t2026\nStaked\t50\t62");
      expect(d.series.map((s) => s.name), ["2020", "2026"]);
      expect(d.categories, ["Staked"]);
    });
    test("as does an empty corner", () {
      var d = ChartData.parse("\t5\t9\nStaked\t50\t62");
      expect(d.series.map((s) => s.name), ["5", "9"]);
    });
    test("but a row of one year is data, as a timeline pastes", () {
      var d = ChartData.parse("Launch\t2016\nDCRDEX\t2020");
      expect(d.categories, ["Launch", "DCRDEX"]);
    });
    test("and years not going up are data", () {
      var d = ChartData.parse("Then\t2026\t2020\nNow\t1\t2");
      expect(d.categories, ["Then", "Now"]);
    });
  });
}
