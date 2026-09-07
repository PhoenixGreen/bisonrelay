import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_presets.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
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
      showAxisLabels: false,
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
}
