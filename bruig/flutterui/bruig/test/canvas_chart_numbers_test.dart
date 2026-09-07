import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_numbers.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
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
}
