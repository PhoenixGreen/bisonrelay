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

  group("shortened", () {
    // Every number by its own size, on one axis. The fixed styles scale
    // everything by one amount, which is right when the numbers are of one
    // size and wrong the moment they are not: a chart in millions writes a
    // billion as 1000.0M and a thousand as 0.0M.
    const shortened = ChartNumbers(style: NumberStyle.compact);

    test("picks the unit each number reaches", () {
      expect(shortened.format(950), "950.0");
      expect(shortened.format(1500), "1.5K");
      expect(shortened.format(2400000), "2.4M");
      expect(shortened.format(3.2e9), "3.2B");
      expect(shortened.format(1.8e12), "1.8T");
      expect(shortened.format(4e15), "4.0Q");
    });

    test("and the decimals and grouping are still the chart's", () {
      const round = ChartNumbers(style: NumberStyle.compact, decimals: 0);
      expect(round.format(2400000), "2M");
      // Grouping still applies where a number is large enough to need it --
      // a chart in the shortened style can still reach 1,000K.
      const many = ChartNumbers(style: NumberStyle.compact, decimals: 1);
      expect(many.format(-2400000), "-2.4M");
    });

    test("below a thousand it is the number itself", () {
      expect(shortened.format(0), "0.0");
      expect(shortened.format(-12.5), "-12.5");
    });

    test("it survives being saved", () {
      var back = ChartNumbers.fromJson(shortened.toJson());
      expect(back.style, NumberStyle.compact);
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
          legendEntriesForTest(pie(const ChartNumbers()), 1).map((k) => k.name),
          ["One: 1.0M", "Two: 2.5M"],
          reason: "automatic, which is what it did before");

      expect(
          legendEntriesForTest(
                  pie(const ChartNumbers(
                      style: NumberStyle.plain, decimals: 0)),
                  1)
              .map((k) => k.name),
          ["One: 1,000,000", "Two: 2,500,000"]);

      expect(
          legendEntriesForTest(
                  pie(const ChartNumbers(
                      style: NumberStyle.millions, decimals: 2)),
                  1)
              .map((k) => k.name),
          ["One: 1.00M", "Two: 2.50M"]);
    });
  });

  group("the words naming an axis", () {
    // The X label and the Y label are the words under and beside the plot --
    // "Coin", "Price" -- and each can be taken off on its own. The tick
    // values and the category names are a different question and belong to
    // Axes labels: "the labels on the axes" means those, "the X label" means
    // the word underneath them.
    ChartElement titled({bool x = true, bool y = true, bool all = true}) =>
        ChartElement(
          const ElementBase(id: "c", width: 400, height: 300),
          xAxisLabel: "Coin",
          yAxisLabel: "Price",
          showXLabels: all,
          showYLabels: all,
          showXTitle: x,
          showYTitle: y,
        );

    test("each one is shown on its own", () {
      expect(titled().showsXTitle, isTrue);
      expect(titled(x: false).showsXTitle, isFalse);
      expect(titled(x: false).showsYTitle, isTrue,
          reason: "taking one off leaves the other");
    });

    test("and a title with nothing in it is not drawn either way", () {
      var blank = titled().copyWith(xAxisLabel: "");
      expect(blank.showsXTitle, isFalse);
      expect(blank.showsYTitle, isTrue);
    });

    test("switching off the tick values leaves the titles alone", () {
      // They were under that switch, on the grounds that both are writing on
      // an axis. Switching the figures off then took the word naming the axis
      // with it, and left the switch that asks for the word doing nothing --
      // what an axis is measured in and what it is called are two questions.
      expect(titled(all: false).showsXTitle, isTrue);
      expect(titled(all: false).showsYTitle, isTrue);
      // And the gutters are still kept, because there is still writing there.
      expect(titled(all: false).showAxisLabels, isTrue);
      // Nothing written on the axes at all only when the titles are off too.
      expect(titled(all: false, x: false, y: false).showAxisLabels, isFalse);
    });

    test("a chart saved before they existed shows both", () {
      var old =
          ChartElement.fromJson(const {"id": "c"}, const ElementBase(id: "c"));
      expect(old.showXTitle, isTrue);
      expect(old.showYTitle, isTrue);
      expect(old.toJson().containsKey("noXTitle"), isFalse);
    });

    test("and one switched off survives being saved", () {
      var off = titled(x: false);
      var back = ChartElement.fromJson(off.toJson(), off.base);
      expect(back.showXTitle, isFalse);
      expect(back.showYTitle, isTrue);
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

  group("a log scale and a row nobody has filled in", () {
    // Adding a row puts a zero in every series -- that is what the row *is*
    // until the numbers arrive. Refusing the whole scale for it meant a log
    // chart stopped being one the moment a row was added and came back only
    // after every series had been typed into, which reads as the switch
    // being broken.
    ChartElement charting(List<double> values) => ChartElement(
          const ElementBase(id: "c", width: 400, height: 300),
          logScale: true,
          data: ChartData(categories: const [
            "a",
            "b"
          ], series: [
            ChartSeries(
                name: "s", color: const Color(0xFF112233), values: values),
          ]),
        );

    test("a zero does not switch it off", () {
      expect(charting([10, 0]).logs, isTrue);
      expect(charting([10, 100]).logs, isTrue);
    });

    test("but a negative does", () {
      // A reading below zero is one a log axis genuinely cannot show, and
      // drawing it anyway would be a chart that lies.
      expect(charting([10, -1]).logs, isFalse);
    });

    test("and nothing above zero is nothing to scale", () {
      expect(charting([0, 0]).logs, isFalse);
      expect(charting([]).logs, isFalse);
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

    test("and a series can be written its own way", () {
      // A price beside a market cap is two series four orders of magnitude
      // apart: one style across both writes either "0.0B" against the price
      // or eleven digits against the cap.
      var e = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        numbers: const ChartNumbers(style: NumberStyle.plain, decimals: 2),
        data: ChartData(categories: const [
          "Decred"
        ], series: [
          const ChartSeries(
              name: "Price", color: Color(0xFF000000), values: [18.4]),
          ChartSeries(
              name: "Market cap",
              color: const Color(0xFF000000),
              values: const [290000000],
              numbers: const ChartNumbers(style: NumberStyle.millions)),
        ]),
      );
      expect(formatSeries(e, 0, 18.4), "18.40",
          reason: "a series that says nothing is written the chart's way");
      expect(formatSeries(e, 1, 290000000), "290.0M");
      // The axis keeps the chart's own: there is one of it, and it cannot be
      // two things at once.
      expect(formatAxis(e, 290000000), formatAxis(e, 290000000));
      expect(formatTick(e, 290000000), "290,000,000.00");
    });

    test("a series' own style survives being saved", () {
      var series = const ChartSeries(
          name: "Cap",
          color: Color(0xFF112233),
          values: [1],
          numbers: ChartNumbers(style: NumberStyle.billions, decimals: 2));
      var back = ChartSeries.fromJson(series.toJson(), 0);
      expect(back.numbers?.style, NumberStyle.billions);
      expect(back.numbers?.decimals, 2);

      // And a series with nothing of its own saves nothing, so every chart
      // written until now reads back exactly as it was.
      const plain =
          ChartSeries(name: "A", color: Color(0xFF112233), values: [1]);
      expect(plain.toJson().containsKey("numbers"), isFalse);
      expect(ChartSeries.fromJson(plain.toJson(), 0).numbers, isNull);
    });

    test("and going back to the chart's way forgets it", () {
      // copyWith fills a null with what was there before, which is right for
      // "change this field" and wrong for "follow the chart again" -- the
      // same trap the type override has, and the same flag out of it.
      var own = const ChartSeries(
          name: "Cap",
          color: Color(0xFF112233),
          values: [1],
          numbers: ChartNumbers(style: NumberStyle.billions));
      expect(own.copyWith(name: "Cap!").numbers, isNotNull);
      expect(own.copyWith(writtenLikeChart: true).numbers, isNull);
    });
  });
}
