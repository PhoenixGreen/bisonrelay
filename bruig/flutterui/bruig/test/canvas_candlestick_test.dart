import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_presets.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_cartesian.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_candlestick_test.dart is the one chart type that reads four series
// as a single mark.
//
// Two halves worth testing separately. Which of the four numbers is which is
// arithmetic and is checked as such; whether the thing actually appears on the
// canvas is checked by drawing it and looking at the pixels, because a
// painter that computes the right rectangle and draws it off the plot passes
// every model test there is.

void main() {
  ChartElement candles(ChartData data,
      {ChartElement Function(ChartElement)? and}) {
    var e = ChartElement(
      const ElementBase(id: "c", width: 400, height: 300),
      type: ChartType.candlestick,
      data: data,
      showXLabels: false,
      showYLabels: false,
      showLegend: false,
    );
    return and == null ? e : and(e);
  }

  /// ohlc builds the four series a candlestick is drawn from.
  ChartData ohlc(
    List<String> when,
    List<double> open,
    List<double> high,
    List<double> low,
    List<double> close, {
    List<String> names = const ["Open", "High", "Low", "Close"],
  }) =>
      ChartData(categories: when, series: [
        ChartSeries(name: names[0], color: chartPalette[0], values: open),
        ChartSeries(name: names[1], color: chartPalette[1], values: high),
        ChartSeries(name: names[2], color: chartPalette[2], values: low),
        ChartSeries(name: names[3], color: chartPalette[3], values: close),
      ]);

  group("which number is which", () {
    test("by name, in whatever order they arrive", () {
      // A source is free to send them in any order, and the mapping has
      // already named the columns -- naming them again in a fifth setting is
      // a thing to get wrong.
      var data = ohlc(
        ["Mon"],
        [4],
        [1],
        [2],
        [3],
        names: ["Close price", "Open price", "Session high", "Daily low"],
      );
      var it = data.ohlcAt(0)!;
      expect(it.open, 1, reason: "the series named Open price");
      expect(it.high, 2);
      expect(it.low, 3);
      expect(it.close, 4);
    });

    test("by position when the names do not say", () {
      // Which is the order every market API sends them in, and the order
      // anybody typing four columns would use.
      var data =
          ohlc(["Mon"], [10], [12], [9], [11], names: ["A", "B", "C", "D"]);
      var it = data.ohlcAt(0)!;
      expect([it.open, it.high, it.low, it.close], [10, 12, 9, 11]);
    });

    test("half a match is no match", () {
      // A chart drawing the high as the open because one column happened to
      // be called "Closing" and another "Close" would be wrong in a way
      // nobody could see. All four or none.
      var data = ohlc(["Mon"], [10], [12], [9], [11],
          names: ["Open", "Peak", "Trough", "Close"]);
      var it = data.ohlcAt(0)!;
      expect([it.open, it.high, it.low, it.close], [10, 12, 9, 11],
          reason: "fell back to position rather than pairing two of four");
    });

    test("three series is not a candle", () {
      var data = ChartData(categories: const [
        "Mon"
      ], series: [
        for (var i = 0; i < 3; i++)
          ChartSeries(name: "S$i", color: chartPalette[i], values: const [1]),
      ]);
      expect(data.ohlcAt(0), isNull);
    });

    test("a day that closed where it opened still has a body to draw", () {
      var it = ohlc(["Mon"], [10], [11], [9], [10]).ohlcAt(0)!;
      expect(it.rose, isTrue, reason: "unchanged is not a fall");
      expect(it.top, it.bottom);
    });
  });

  group("the axis", () {
    test("a candlestick does not have to start at zero", () {
      // A bar is read as a length and must; a price is read as a position and
      // must not, or a month of trading between 12 and 16 is a flat line
      // along the top of the plot.
      expect(ChartType.candlestick.startsAtZero, isFalse);
      for (var type in ChartType.values) {
        if (type != ChartType.candlestick) {
          expect(type.startsAtZero, isTrue, reason: type.name);
        }
      }
    });
  });

  group("drawn", () {
    /// ink is every colour that ended up on the canvas, by how many pixels.
    Future<Map<int, int>> ink(ChartElement e,
        {Size size = const Size(400, 300)}) async {
      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      canvas.drawRect(
          Offset.zero & size, Paint()..color = const Color(0xFF101014));
      paintChart(canvas, Offset.zero & size, e);
      var image = await recorder
          .endRecording()
          .toImage(size.width.round(), size.height.round());
      var bytes = await image.toByteData();
      var counts = <int, int>{};
      for (var i = 0; i < bytes!.lengthInBytes; i += 4) {
        var pixel = bytes.getUint32(i);
        counts[pixel] = (counts[pixel] ?? 0) + 1;
      }
      return counts;
    }

    int rgba(Color c) =>
        ((c.r * 255).round() << 24) |
        ((c.g * 255).round() << 16) |
        ((c.b * 255).round() << 8) |
        (c.a * 255).round();

    test("a rising period and a falling one are told apart by colour",
        () async {
      // The colour is the reading here rather than a label for a series,
      // which is the whole of what makes this type different from four lines.
      var e = candles(ohlc(
        ["Mon", "Tue"],
        [10, 16],
        [17, 17],
        [9, 11],
        [16, 11],
      ));
      var counts = await ink(e);

      expect(counts[rgba(e.riseColor)] ?? 0, greaterThan(50),
          reason: "Monday closed six up and is not drawn");
      expect(counts[rgba(e.fallColor)] ?? 0, greaterThan(50),
          reason: "Tuesday closed five down and is not drawn");
    });

    /// band is the topmost and bottommost row the candles reached, as
    /// fractions of the picture's height.
    Future<(double, double)> band(ChartElement e,
        {Size size = const Size(400, 300)}) async {
      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      canvas.drawRect(
          Offset.zero & size, Paint()..color = const Color(0xFF101014));
      paintChart(canvas, Offset.zero & size, e);
      var image = await recorder
          .endRecording()
          .toImage(size.width.round(), size.height.round());
      var bytes = (await image.toByteData())!;
      var wanted = {rgba(e.riseColor), rgba(e.fallColor)};

      var top = size.height, bottom = 0.0;
      for (var y = 0; y < size.height; y++) {
        for (var x = 0; x < size.width; x++) {
          var pixel = bytes.getUint32(((y * size.width.round()) + x) * 4);
          if (!wanted.contains(pixel)) continue;
          if (y < top) top = y.toDouble();
          if (y > bottom) bottom = y.toDouble();
        }
      }
      return (top / size.height, bottom / size.height);
    }

    test("the range is the prices, not zero to the high", () async {
      // Drawn against an axis from zero, a month between 12 and 16 is a
      // smudge along the top. Against its own range it fills the plot.
      var e = candles(ohlc(
        ["Mon", "Tue", "Wed"],
        [12.0, 13.0, 15.0],
        [13.0, 15.5, 16.0],
        [11.8, 12.9, 14.4],
        [13.0, 15.0, 14.5],
      ));
      var (top, bottom) = await band(e);
      // On an axis from zero these three days occupy the top quarter of the
      // plot and the rest of it is empty; on their own range they fill it.
      // Half rather than all of it: the axis still ends on round numbers, so
      // three days between 11.8 and 16 are drawn against 10 to 18. On an axis
      // from zero the same three fill a seventh.
      expect(bottom - top, greaterThan(0.45),
          reason: "the candles should use the height of the plot, not a "
              "seventh of it");
      expect(bottom, greaterThan(0.7),
          reason: "and the lowest low belongs near the bottom of it");
    });

    test(
        "four series and no candlestick draws four somethings, not four "
        "candles", () async {
      // The type is what decides it. The same data as lines is still a chart,
      // and none of it may be drawn in the candle colours.
      // In a colour nothing else uses: the default rise colour is also the
      // third of the series palette, so a line chart drawing its third series
      // would look like a candle.
      var e = candles(
          ohlc(["Mon", "Tue"], [10, 16], [17, 17], [9, 11], [16, 11]),
          and: (c) => c.copyWith(
              type: ChartType.line, riseColor: const Color(0xFF00AAFF)));
      var counts = await ink(e);
      expect(counts[rgba(e.riseColor)] ?? 0, 0);
    });

    test("nothing is drawn where there are not four series", () async {
      var thin = ChartData(categories: const [
        "Mon"
      ], series: [
        ChartSeries(name: "Open", color: chartPalette[0], values: const [10]),
      ]);
      var e = candles(thin).copyWith(riseColor: const Color(0xFF00AAFF));
      var counts = await ink(e);
      expect(counts[rgba(e.riseColor)] ?? 0, 0);
    });
  });

  group("the presets that need it", () {
    test("an OHLC source brings the drawing with it", () {
      // Four columns of open, high, low and close drawn as four lines is not
      // what anybody choosing this was asking for.
      expect(coinGeckoCandles.chartType, ChartType.candlestick);
      expect(coinGeckoCandles.chartValues, [1, 2, 3, 4]);
      expect(dcrdexCandles.chartType, ChartType.candlestick);
    });

    test("the columns are named so the order does not have to be right", () {
      for (var preset in [coinGeckoCandles, dcrdexCandles]) {
        var names = [
          for (var c in preset.columns.skip(1)) c.header.toLowerCase()
        ];
        expect(names, ["open", "high", "low", "close"], reason: preset.id);
      }
    });

    test("dcrdex sends records and CoinGecko sends arrays", () {
      // Both were checked against the live API. One walks into a record by
      // name, the other into a row by index, and the same mapping reads both.
      expect(dcrdexCandles.rowsPath, "sticks");
      expect(dcrdexCandles.shape, DataShape.records);
      expect(coinGeckoCandles.columns[1].path, "1");
    });

    test("the two colours survive being saved and read back", () {
      var e = candles(const ChartData()).copyWith(
          riseColor: const Color(0xFF00AAFF),
          fallColor: const Color(0xFFFF8800));
      var back = elementFromJson(e.toJson()) as ChartElement;
      expect(back.riseColor, const Color(0xFF00AAFF));
      expect(back.fallColor, const Color(0xFFFF8800));
      expect(back.type, ChartType.candlestick);
    });
  });

  group("a log axis", () {
    // Scatter rather than a line: the points are what is being measured, and
    // a line chart joins them, so every column of the picture holds ink from
    // somewhere between two of them.
    ChartElement lineOf(List<double> values, {bool log = true}) => ChartElement(
          const ElementBase(id: "c", width: 400, height: 300),
          type: ChartType.scatter,
          logScale: log,
          showXLabels: false,
          showYLabels: false,
          showLegend: false,
          data: ChartData(
            categories: [for (var i = 0; i < values.length; i++) "$i"],
            series: [
              ChartSeries(
                  name: "Supply",
                  color: const Color(0xFF00AAFF),
                  values: values)
            ],
          ),
        );

    test("it is refused where it cannot mean anything", () {
      // A negative number is a reading a log axis genuinely cannot show, so
      // rather than drawing a chart that lies it is drawn evenly and the
      // settings say why. A zero is different -- see below.
      expect(lineOf([1, 10, 100]).logs, isTrue);
      expect(lineOf([-1, 10]).logs, isFalse, reason: "a negative");
      expect(lineOf([1, 10], log: false).logs, isFalse);
      expect(lineOf(const []).logs, isFalse, reason: "nothing to scale");
      expect(lineOf([0, 0]).logs, isFalse, reason: "nothing above zero");
    });

    test("a zero is a row nobody has filled in, not a reason to give up", () {
      // Adding a row puts a zero in every series. Refusing the scale for it
      // meant a log chart stopped being one the moment a row was added, and
      // came back only once every series had been typed into.
      expect(lineOf([0, 10, 100]).logs, isTrue);
    });

    test("and the decades still rule the axis with one in the data", () async {
      // The range has to be taken from the numbers it can describe. Seeded
      // with the zero it falls back to a linear range, and the scale quietly
      // stops being a log scale while still calling itself one.
      var rows = await _pointRows(lineOf([0, 1, 10, 100, 1000]));
      // The zero sits on the floor; the four decades above it are evenly
      // spaced, which is what a log axis is.
      var decades = rows.sublist(1);
      var gaps = [
        for (var i = 1; i < decades.length; i++) decades[i - 1] - decades[i],
      ];
      for (var gap in gaps) {
        expect(gap, closeTo(gaps.first, gaps.first.abs() * 0.2),
            reason: "each decade is the same distance as the last: $rows");
      }
    });

    test("how many lines rule it can be asked for", () {
      var byDefault = axisTicksForTest(0, 100);
      var few = axisTicksForTest(0, 100, want: 2);
      var many = axisTicksForTest(0, 100, want: 20);
      expect(few.length, lessThan(byDefault.length));
      expect(many.length, greaterThan(byDefault.length));

      // And still round: every line is a whole multiple of the step, which
      // is what anybody reads a value off.
      var step = many[1] - many[0];
      for (var i = 1; i < many.length; i++) {
        expect(many[i] - many[i - 1], closeTo(step, step * 0.001));
      }
    });

    test("and every number typed into it does something", () {
      // Reported: typing 4, 6, 7, 8 or 9 changed nothing. Rounding the step
      // to the nearest 1, 2, 2.5 or 5 times a power of ten answers "make the
      // numbers round" and ignores "give me this many" -- over 0 to 100,
      // five lines, six, seven, eight and nine all came out as the same six.
      var counts = [
        for (var want = 2; want <= 12; want++)
          axisTicksForTest(0, 100, want: want).length,
      ];
      // Never fewer for asking for more.
      for (var i = 1; i < counts.length; i++) {
        expect(counts[i], greaterThanOrEqualTo(counts[i - 1]),
            reason: "asking for more lines gave fewer: $counts");
      }
      // And it actually moves: the middle of that range used to be one
      // answer repeated five times.
      expect(counts.toSet().length, greaterThan(6),
          reason: "eleven numbers should not give five answers: $counts");
      // Most of them land exactly on what was asked for.
      var exact = 0;
      for (var want = 2; want <= 12; want++) {
        if (counts[want - 2] == want) exact++;
      }
      expect(exact, greaterThan(5), reason: "$counts");
    });

    test("without running the axis past the numbers to get there", () {
      // A big step can always hit a small count by ruling a range of a
      // hundred up to a thousand. That answers the question and ruins the
      // chart, so the room it wastes counts against it.
      for (var want = 2; want <= 12; want++) {
        var ticks = axisTicksForTest(0, 100, want: want);
        expect(ticks.last, lessThanOrEqualTo(140),
            reason: "asked for $want lines and ruled up to ${ticks.last}");
        expect(ticks.first, 0);
      }
    });

    test("and it works on ranges that are not one to a hundred", () {
      for (var (lo, hi) in [(0.0, 37.0), (0.0, 1.0), (0.0, 2.4e9)]) {
        var counts = [
          for (var want = 2; want <= 10; want++)
            axisTicksForTest(lo, hi, want: want).length,
        ];
        expect(counts.toSet().length, greaterThan(4),
            reason: "$lo..$hi gave $counts");
        expect(counts.first, lessThan(counts.last));
      }
    });

    test("and on a log axis it is how many decades are labelled", () {
      var all = axisTicksForTest(1, 1e12, want: 20, log: true);
      var some = axisTicksForTest(1, 1e12, want: 3, log: true);
      expect(all.length, greaterThan(some.length),
          reason: "asking for more lines labels more of the decades");
      // Still powers of ten: there is nothing between two decades to move.
      for (var tick in some) {
        var power = math.log(tick) / math.ln10;
        expect(power, closeTo(power.roundToDouble(), 0.001));
      }
    });

    test("a pie is not drawn on one", () {
      var pie = lineOf([1, 10, 100]).copyWith(type: ChartType.pie);
      expect(pie.logs, isFalse);
    });

    test("decades are evenly spaced, which is the whole point", () async {
      // 1, 10, 100, 1000 on a linear axis is three points along the bottom
      // and one at the top. On a log axis the four are equally far apart, and
      // that is what makes something that grew a thousandfold readable at
      // both ends.
      var e = lineOf([1, 10, 100, 1000]);
      var rows = await _pointRows(e);
      expect(rows.length, 4, reason: "four points, four heights");

      var gaps = [
        for (var i = 1; i < rows.length; i++) rows[i - 1] - rows[i],
      ];
      for (var gap in gaps) {
        expect(gap, closeTo(gaps.first, gaps.first * 0.12),
            reason: "the decades should be a fixed distance apart: $gaps");
      }
    });

    test("and evenly, without it, they are not", () async {
      var rows = await _pointRows(lineOf([1, 10, 100, 1000], log: false));
      var gaps = [
        for (var i = 1; i < rows.length; i++) rows[i - 1] - rows[i],
      ];
      // The last step is ten times the one before it, so nothing like even.
      expect(gaps.last, greaterThan(gaps.first * 5));
    });

    test("it survives being saved and read back", () {
      var back = elementFromJson(lineOf([1, 10]).toJson()) as ChartElement;
      expect(back.logScale, isTrue);
    });
  });
}

/// _pointRows is the height of each drawn point, as a row in the picture.
///
/// Measured off the picture rather than computed, because what is being asked
/// is where the chart actually put them: an axis that works out the right
/// fractions and a painter that ignores them is a chart that is wrong in the
/// only place anybody looks.
Future<List<double>> _pointRows(ChartElement e,
    {Size size = const Size(400, 300)}) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF101014));
  paintChart(canvas, Offset.zero & size, e);
  var image = await recorder
      .endRecording()
      .toImage(size.width.round(), size.height.round());
  var bytes = (await image.toByteData())!;

  // The series is drawn in a colour nothing else on the chart uses, so its
  // ink can be picked out of the picture. Gathered per slot rather than per
  // column, because where a point is drawn within its slot is the painter's
  // business and not what is being asked.
  var wanted = 0x00AAFFFF;
  var slots = e.data.categories.length;
  var sums = List<double>.filled(slots, 0);
  var counts = List<int>.filled(slots, 0);

  for (var y = 0; y < size.height; y++) {
    for (var x = 0; x < size.width; x++) {
      if (bytes.getUint32(((y * size.width.round()) + x) * 4) != wanted) {
        continue;
      }
      var slot = (x * slots / size.width).floor().clamp(0, slots - 1);
      sums[slot] += y;
      counts[slot]++;
    }
  }
  return [
    for (var i = 0; i < slots; i++)
      if (counts[i] > 0) sums[i] / counts[i],
  ];
}
