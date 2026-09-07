import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_numbers.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_chart_numbers_test.dart is how a number is written on a chart.
//
// Worth pinning to the character, because that is the whole of the feature:
// somebody who asks for 1.0M and gets 1M has not been given what they asked
// for, and neither has somebody who asks for 1M and gets 1.0M.

void main() {
  String at(ChartNumbers numbers, double v) => numbers.format(v);

  group("the styles", () {
    const million = 1000000.0;

    test("a million, five ways", () {
      // The list this was asked for, in order.
      expect(
          at(const ChartNumbers(style: NumberStyle.plain, decimals: 0),
              million),
          "1,000,000");
      expect(
          at(const ChartNumbers(style: NumberStyle.thousands, decimals: 0),
              million),
          "1,000K");
      expect(
          at(const ChartNumbers(style: NumberStyle.millions, decimals: 2),
              million),
          "1.00M");
      expect(
          at(const ChartNumbers(style: NumberStyle.millions, decimals: 1),
              million),
          "1.0M");
      expect(
          at(const ChartNumbers(style: NumberStyle.millions, decimals: 0),
              million),
          "1M");
    });

    test("no decimals means no decimal point", () {
      // Not "1.M", and not a nought after it either.
      var written = at(
          const ChartNumbers(style: NumberStyle.millions, decimals: 0),
          1500000);
      expect(written, "2M", reason: "rounded, and nothing after the digit");
      expect(written, isNot(contains(".")));
    });

    test("the separators can be switched off", () {
      expect(
          at(
              const ChartNumbers(
                  style: NumberStyle.plain, decimals: 0, separators: false),
              million),
          "1000000");
    });

    test("and they group the whole part only", () {
      expect(
          at(const ChartNumbers(style: NumberStyle.plain, decimals: 2),
              1234567.891),
          "1,234,567.89");
      expect(
          at(const ChartNumbers(style: NumberStyle.plain, decimals: 1), -12345),
          "-12,345.0",
          reason: "the minus sign is not a digit to group");
      expect(at(const ChartNumbers(style: NumberStyle.plain, decimals: 0), 999),
          "999");
    });

    test("billions, for a chain that has reached them", () {
      expect(
          at(const ChartNumbers(style: NumberStyle.billions, decimals: 2),
              2500000000),
          "2.50B");
    });

    test("a number that is not a number is nothing at all", () {
      expect(at(const ChartNumbers(), double.nan), "");
      expect(at(const ChartNumbers(), double.infinity), "");
    });
  });

  group("automatic", () {
    test("is what a chart did before any of this existed", () {
      // The default has to keep every chart already drawn exactly as it was.
      const numbers = ChartNumbers();
      expect(numbers.style, NumberStyle.automatic);
      expect(at(numbers, 1000000), "1.0M");
      expect(at(numbers, 12000), "12k");
      expect(at(numbers, 1234), "1234");
      expect(at(numbers, 12.5), "12.5");
      expect(at(numbers, 0.125), "0.13");
    });

    test("and it is what a chart with nothing saved gets", () {
      var chart =
          ChartElement(const ElementBase(id: "c", width: 400, height: 300));
      expect(chart.numbers.style, NumberStyle.automatic);
      // The places start at one rather than at none, so choosing a style
      // gives "1.0M" rather than silently rounding everything.
      expect(chart.numbers.decimals, 1);
      expect(chart.numbers.separators, isTrue);
    });
  });

  group("saved and read back", () {
    test("a style survives", () {
      var chart = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        numbers: const ChartNumbers(
            style: NumberStyle.millions, decimals: 2, separators: false),
      );
      var back = elementFromJson(chart.toJson()) as ChartElement;
      expect(back.numbers.style, NumberStyle.millions);
      expect(back.numbers.decimals, 2);
      expect(back.numbers.separators, isFalse);
    });

    test("and a chart saved before there were styles is automatic", () {
      var chart =
          ChartElement(const ElementBase(id: "c", width: 400, height: 300));
      var json = chart.toJson();
      expect(json.containsKey("numbers"), isFalse,
          reason: "nothing to say, so nothing written");
      expect((elementFromJson(json) as ChartElement).numbers.style,
          NumberStyle.automatic);
    });
  });

  group("everywhere the chart writes one", () {
    // One setting for the axis, the bars and the legend, because they are the
    // same numbers -- an axis saying 1,500,000 beside a bar saying 1.5M is a
    // chart that has changed its mind half way across.

    ChartElement pie(ChartNumbers numbers) => ChartElement(
          const ElementBase(id: "c", width: 400, height: 300),
          type: ChartType.pie,
          numbers: numbers,
          showLegend: true,
          legend: const ChartLegend(values: true),
          data: ChartData(categories: const [
            "One",
            "Two"
          ], series: [
            ChartSeries(
                name: "Sales",
                color: chartPalette[0],
                values: const [1000000, 2500000]),
          ]),
        );

    test("the legend's values are written in the chart's own style", () {
      expect(
          legendEntriesForTest(pie(const ChartNumbers()), 1).map((k) => k.$2),
          ["One: 1.0M", "Two: 2.5M"],
          reason: "automatic, which is what it did before");

      expect(
          legendEntriesForTest(
                  pie(const ChartNumbers(
                      style: NumberStyle.plain, decimals: 0)),
                  1)
              .map((k) => k.$2),
          ["One: 1,000,000", "Two: 2,500,000"]);

      expect(
          legendEntriesForTest(
                  pie(const ChartNumbers(
                      style: NumberStyle.millions, decimals: 2)),
                  1)
              .map((k) => k.$2),
          ["One: 1.00M", "Two: 2.50M"]);
    });
  });

  group("the axis and the values apart", () {
    ChartElement chart({ChartNumbers? axis}) => ChartElement(
          const ElementBase(id: "c", width: 400, height: 300),
          numbers: const ChartNumbers(style: NumberStyle.millions, decimals: 3),
          axisNumbers: axis,
        );

    test("the axis follows the values until it is told not to", () {
      // They are the same numbers, and an axis saying 1,500,000 beside a bar
      // saying 1.5M is a chart that has changed its mind half way across.
      var following = chart();
      expect(following.axisNumbers, isNull);
      expect(following.axisFigures.format(2049000), "2.049M");
      expect(following.numbers.format(2049000), "2.049M");
    });

    test("and then it is a scale rather than a reading", () {
      // The pairing this exists for: an exact figure on the bar, a round one
      // up the side.
      var apart = chart(
          axis: const ChartNumbers(style: NumberStyle.millions, decimals: 1));
      expect(apart.numbers.format(2049000), "2.049M");
      expect(apart.axisFigures.format(2049000), "2.0M");
    });

    test("saying they are the same again clears the axis's own", () {
      // copyWith cannot say "back to null" with a null, so the state has its
      // own flag -- and without it, switching the axis back to following the
      // values would silently do nothing.
      var apart = chart(axis: const ChartNumbers(style: NumberStyle.plain));
      expect(apart.copyWith(axisFollowsValues: true).axisNumbers, isNull);
      expect(
          apart.copyWith(numbers: const ChartNumbers()).axisNumbers, isNotNull,
          reason: "an unrelated change must not clear it");
    });

    test("both survive being saved and read back", () {
      var apart = chart(
          axis: const ChartNumbers(style: NumberStyle.millions, decimals: 1));
      var back = elementFromJson(apart.toJson()) as ChartElement;
      expect(back.numbers.decimals, 3);
      expect(back.axisNumbers?.decimals, 1);
      // And a chart that never had one still has none.
      expect((elementFromJson(chart().toJson()) as ChartElement).axisNumbers,
          isNull);
    });
  });

  group("the words naming the axes", () {
    ChartElement titled({TextSpec? spec, double gap = 0}) => ChartElement(
          const ElementBase(id: "c", width: 400, height: 300),
          xAxisLabel: "Month",
          yAxisLabel: "Transactions",
          axisSpec: spec,
          axisGap: gap,
        );

    test("have their own size, which starts as the label size", () {
      // Sharing meant that making the figures up the side smaller shrank the
      // words naming them with it.
      var chart = titled();
      expect(chart.axisSpec, isNull);
      expect(chart.axisText.fontSize, chart.labelSpec.fontSize);

      var bigger = titled(spec: chart.labelSpec.copyWith(fontSize: 40));
      expect(bigger.axisText.fontSize, 40);
      expect(bigger.labelSpec.fontSize, isNot(40),
          reason: "the tick labels are left where they were");
    });

    test("and their own distance from the plot", () {
      expect(titled().axisGap, 0, reason: "the layout as it was");
      expect(titled(gap: 24).axisGap, 24);
    });

    test("both survive being saved and read back", () {
      var chart = titled(spec: const TextSpec(fontSize: 30), gap: 18);
      var back = elementFromJson(chart.toJson()) as ChartElement;
      expect(back.axisText.fontSize, 30);
      expect(back.axisGap, 18);
      // A chart saved before either existed writes neither and reads back
      // following the labels.
      var plain = titled().toJson();
      expect(plain.containsKey("axisSpec"), isFalse);
      expect(plain.containsKey("axisGap"), isFalse);
    });
  });

  group("drawn", () {
    /// leftmostInk is the first column of the picture the series reaches, as
    /// a fraction of its width. The plot starts where the writing beside it
    /// ends, so pushing the axis title out moves this right.
    Future<double> leftmostInk(ChartElement e,
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

      for (var x = 0; x < size.width; x++) {
        for (var y = 0; y < size.height; y++) {
          if (bytes.getUint32(((y * size.width.round()) + x) * 4) ==
              0x00AAFFFF) {
            return x / size.width;
          }
        }
      }
      return 1;
    }

    ChartElement bars({double gap = 0, TextSpec? spec}) => ChartElement(
          const ElementBase(id: "c", width: 400, height: 300),
          yAxisLabel: "Transactions",
          axisGap: gap,
          axisSpec: spec,
          showLegend: false,
          data: ChartData(categories: const [
            "a",
            "b"
          ], series: [
            ChartSeries(
                name: "S",
                color: const Color(0xFF00AAFF),
                values: const [10, 20]),
          ]),
        );

    test("asking for room moves the axis title away from the plot", () async {
      // Which is what the setting is for: the title sits against the plot by
      // default, and how much air a design wants is not a thing a drawing
      // routine knows.
      var tight = await leftmostInk(bars());
      var roomy = await leftmostInk(bars(gap: 60));
      expect(roomy, greaterThan(tight + 0.1),
          reason: "the plot should start further in: $tight then $roomy");
    });

    test("and so does setting it in bigger type", () async {
      var small = await leftmostInk(bars());
      var large = await leftmostInk(
          bars(spec: const TextSpec(fontSize: 40, weight: 600)));
      expect(large, greaterThan(small));
    });
  });

  group("which numbers go where", () {
    test("the axis is asked separately from the values", () {
      // The two functions the painter calls: one for a reading, one for a
      // scale. Pinned here because a chart that asked the wrong one would
      // look right until somebody set them differently.
      var e = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        numbers: const ChartNumbers(style: NumberStyle.millions, decimals: 3),
        axisNumbers:
            const ChartNumbers(style: NumberStyle.millions, decimals: 1),
      );
      expect(formatTick(e, 2049000), "2.049M");
      expect(formatAxis(e, 2049000), "2.0M");
    });
  });
}
