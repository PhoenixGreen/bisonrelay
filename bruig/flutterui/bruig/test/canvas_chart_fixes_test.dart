import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_chart_fixes_test.dart is what the Charts canvas showed (Ken,
// 2026-11-14: "fix all ten items on the list"): stacked values covered,
// negative bars growing from their tips, radial bars as rings with no
// words, a pictogram with no values or room, funnels out of proportion,
// pies named only in their legend, a scatter with no numbers across, a
// timeline with no dates, small items without words, and three
// collisions.

const red = Color(0xFFFF0000), blue = Color(0xFF0000FF);

ChartElement chart(ChartType type, String tsv,
        {double w = 400,
        double h = 300,
        bool values = false,
        bool names = true,
        bool legend = false,
        List<Color> colours = const [red, blue, red, blue, red, blue],
        ChartAnimation animation = const ChartAnimation()}) =>
    ChartElement(ElementBase(id: "c", width: w, height: h),
        type: type,
        data: ChartData.parse(tsv),
        title: "",
        showValues: values,
        showXLabels: names,
        showLegend: legend,
        sliceColors: colours,
        animation: animation);

Future<(ByteData, int, int)> draw(ChartElement e, {double reveal = 1}) async {
  var w = e.width.round(), h = e.height.round();
  var rec = ui.PictureRecorder();
  paintChart(ui.Canvas(rec), Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), e,
      reveal: reveal);
  var image = await rec.endRecording().toImage(w, h);
  var raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return (raw, w, h);
}

Color at(ByteData raw, int w, int x, int y) {
  var i = (y * w + x) * 4;
  return Color.fromARGB(raw.getUint8(i + 3), raw.getUint8(i),
      raw.getUint8(i + 1), raw.getUint8(i + 2));
}

bool near(Color a, Color b) =>
    (a.r - b.r).abs() < 0.08 &&
    (a.g - b.g).abs() < 0.08 &&
    (a.b - b.b).abs() < 0.08 &&
    a.a > 0.9;

/// inked counts the drawn pixels in [r].
int inked(ByteData raw, int w, Rect r) {
  var n = 0;
  for (var y = r.top.toInt(); y < r.bottom; y++) {
    for (var x = r.left.toInt(); x < r.right; x++) {
      if (raw.getUint8((y * w + x) * 4 + 3) > 40) n++;
    }
  }
  return n;
}

/// columnOf finds, across row [y], where colour [c] starts and ends.
(int, int)? spanOf(ByteData raw, int w, int y, Color c) {
  int? a, b;
  for (var x = 0; x < w; x++) {
    if (near(at(raw, w, x, y), c)) {
      a ??= x;
      b = x;
    }
  }
  return a == null ? null : (a, b!);
}

void main() {
  test("1. a stack's parts each show their value", () async {
    var e = chart(ChartType.stackedBar, "Cat\tA\tB\nQ1\t50\t50",
        values: true, colours: const []);
    e = e.copyWith(
        data: e.data.copyWith(series: [
      e.data.series[0].copyWith(color: red),
      e.data.series[1].copyWith(color: blue),
    ]));
    var (raw, w, h) = await draw(e);
    // The lower (red) part, its middle: a number written on it.
    var reds = <Offset>[];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (near(at(raw, w, x, y), red)) reds.add(Offset(x * 1.0, y * 1.0));
      }
    }
    var box = Rect.fromPoints(reds.first, reds.last);
    var notRed = 0;
    for (var y = (box.center.dy - 6).round(); y < box.center.dy + 6; y++) {
      for (var x = (box.center.dx - 10).round(); x < box.center.dx + 10; x++) {
        if (!near(at(raw, w, x, y), red)) notRed++;
      }
    }
    expect(notRed, greaterThan(10), reason: "its value, on it");
  });

  test("2. a negative bar grows out of the axis, not from its tip", () async {
    var e = chart(ChartType.bar, "Cat\tV\nA\t10\nB\t-10",
        names: false,
        colours: const [red, blue],
        animation: const ChartAnimation(preset: ChartAnimationPreset.grow));
    var (full, w, _) = await draw(e);
    var (half, _, h) = await draw(e, reveal: 0.6);
    // The blue bar's top edge when whole: the axis.
    int? axis;
    for (var y = 0; y < h && axis == null; y++) {
      if (spanOf(full, w, y, blue) != null) axis = y;
    }
    expect(spanOf(half, w, axis! + 2, blue), isNotNull,
        reason: "part grown, it is at the axis");
  });

  test("3. radial bars: the largest three quarters round, named", () async {
    var e = chart(ChartType.radialBar, "Cat\tV\nRead\t100\nRun\t50",
        w: 300, h: 300);
    var (raw, w, h) = await draw(e);
    // Up and left of the middle, on the outer ring: the quarter left
    // over, not a bar.
    var c = const Offset(150, 150);
    var r = 300 / 2 * 0.88 - 300 * 0.88 / 2 * 0.25 * 0.5;
    var p = c + Offset(-r * 0.7071, -r * 0.7071);
    expect(near(at(raw, w, p.dx.round(), p.dy.round()), red), isFalse);
    // Its name, left of where it starts at the top.
    expect(inked(raw, w, Rect.fromLTWH(20, 10, 110, 40)), greaterThan(20));
  });

  test("4. a pictogram fills a tall box, its values along its foot", () async {
    var flat =
        chart(ChartType.pictogram, "Cat\tV\nYes\t60\nNo\t40", w: 220, h: 300);
    var (raw, w, h) = await draw(flat);
    var icons = inked(raw, w, Rect.fromLTWH(0, 0, w * 1.0, h * 1.0));
    // Ten in a row of 22-pixel cells would ink under a sixth of the box.
    expect(icons, greaterThan(220 * 300 / 6));
    var valued = chart(ChartType.pictogram, "Cat\tV\nYes\t60\nNo\t40",
        w: 400, h: 120, values: true);
    var (r2, w2, h2) = await draw(valued);
    expect(inked(r2, w2, Rect.fromLTWH(0, h2 - 18.0, w2 * 1.0, 18)),
        greaterThan(30),
        reason: "Yes 60%, No 40% along the foot");
  });

  test("5. a funnel's stages are as wide as their values", () async {
    var e = chart(ChartType.funnel, "Cat\tV\nVisited\t1000\nPaid\t100",
        names: false, colours: const [red, blue]);
    var (raw, w, h) = await draw(e);
    var top = spanOf(raw, w, 2, red)!;
    var bottomRow = h - 2;
    var bottom = spanOf(raw, w, bottomRow, blue)!;
    var ratio = (bottom.$2 - bottom.$1 + 1) / (top.$2 - top.$1 + 1);
    // The second stage narrows to 80% of itself at its foot.
    expect(ratio, closeTo(0.08, 0.03));
  });

  test("6. a pie names its slices round it when the legend does not", () async {
    var named =
        chart(ChartType.pie, "Cat\tV\nBasic\t60\nPlus\t40", w: 400, h: 300);
    var (raw, w, _) = await draw(named);
    // Out to the sides of the pie, its names and their lines.
    // Clear of where the pie was before names made room round it.
    var outside = inked(raw, w, const Rect.fromLTWH(0, 0, 55, 300)) +
        inked(raw, w, const Rect.fromLTWH(345, 0, 55, 300));
    expect(outside, greaterThan(30));
    var keyed = chart(ChartType.pie, "Cat\tV\nBasic\t60\nPlus\t40",
        w: 400, h: 300, legend: true);
    var (r2, w2, _) = await draw(keyed);
    expect(inked(r2, w2, const Rect.fromLTWH(345, 100, 55, 100)), 0,
        reason: "with a legend, the names are in it");
  });

  test("7. a scatter of numbers is spaced by them", () async {
    var e =
        chart(ChartType.scatter, "X\tY\n1\t5\n2\t5\n10\t5", colours: const []);
    e = e.copyWith(
        showGrid: false,
        data: e.data.copyWith(series: [e.data.series[0].copyWith(color: red)]));
    var (raw, w, h) = await draw(e);
    var xs = <int>[];
    var lastX = -100;
    for (var x = 0; x < w; x++) {
      for (var y = 0; y < h; y++) {
        if (near(at(raw, w, x, y), red)) {
          if (xs.isEmpty || x - lastX > 15) xs.add(x);
          lastX = x;
          break;
        }
      }
    }
    expect(xs, hasLength(3));
    // 1 and 2 close together, 10 far off: not evenly spaced by place.
    expect(xs[2] - xs[1], greaterThan((xs[1] - xs[0]) * 4));
  });

  test("8. a timeline writes its dates with Values off", () async {
    // As much is written with Values off as on: its dates either way.
    Future<int> ink(bool values) async {
      var (raw, w, h) = await draw(chart(
          ChartType.timeline, "Cat\tYear\nLaunch\t2016\nNow\t2026",
          names: false, values: values));
      return inked(raw, w, Rect.fromLTWH(0, 0, w * 1.0, h * 1.0));
    }

    expect(await ink(false), await ink(true));
  });

  test("9. a tiny bubble's name is beside it, on a line", () async {
    var e =
        chart(ChartType.bubbles, "Cat\tV\nBig\t100\nTiny\t1", w: 400, h: 300);
    var (raw, w, h) = await draw(e);
    var (bare, _, _) = await draw(chart(
        ChartType.bubbles, "Cat\tV\nBig\t100\nTiny\t1",
        w: 400, h: 300, names: false));
    expect(inked(raw, w, Rect.fromLTWH(0, 0, w * 1.0, h * 1.0)),
        greaterThan(inked(bare, w, Rect.fromLTWH(0, 0, w * 1.0, h * 1.0)) + 40),
        reason: "Big's name in it, Tiny's beside it");
  });

  test("10. a bullet at its most stops short of its band's end", () async {
    var e = chart(ChartType.bullet, "Cat\tNow\nSales\t100",
        names: false, colours: const [red]);
    var (raw, w, h) = await draw(e);
    var bar = spanOf(raw, w, h ~/ 2, red)!;
    expect(bar.$2, lessThan(w - 20), reason: "room past it, in its band");
  });

  test("10. a slope's top dot is clear of its column's heading", () async {
    var e = chart(ChartType.slope, "Cat\t2024\t2026\nA\t10\t50\nB\t20\t30",
        names: false, colours: const [red, blue]);
    var (raw, w, _) = await draw(e);
    var fs = e.labelSpec.fontSize;
    var reds = 0;
    for (var y = 0; y < (fs * 2).round(); y++) {
      for (var x = 0; x < w; x++) {
        if (near(at(raw, w, x, y), red)) reds++;
      }
    }
    expect(reds, 0, reason: "no part of a dot in the headings' row");
  });

  test("10. a sankey's middle names are on a plate over the ribbons", () async {
    const tsv = "Cat\tBudget\nHousing\t40\nOther\t60\nOther > Travel\t30"
        "\nOther > Savings\t30";
    Future<int> dark(bool names) async {
      // Bright ribbons, so only a plate is dark.
      var e = chart(ChartType.sankey, tsv,
          names: names,
          w: 600,
          h: 300,
          colours: const [
            Color(0xFF7CFC9A),
            Color(0xFFFFE066),
            Color(0xFF7CFC9A),
            Color(0xFFFFE066),
          ]).copyWith(
          labelSpec: const TextSpec(fontSize: 14, color: Color(0xFFFFFFFF)));
      var (raw, w, h) = await draw(e);
      // Just right of the middle column, where its names are.
      var labelW = 600 * 0.22, nodeW = 600 * 0.025;
      var mid = (600 - labelW - nodeW) / 2 + nodeW + 4;
      var n = 0;
      for (var y = 0; y < h; y++) {
        for (var x = mid.round(); x < mid + 40; x++) {
          var c = at(raw, w, x, y);
          if (c.a > 0.5 && c.computeLuminance() < 0.02) n++;
        }
      }
      return n;
    }

    expect(await dark(true), greaterThan(80),
        reason: "a dark plate behind the names over the ribbons");
  });
}
