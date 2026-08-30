import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_chart_data_test.dart is about the quick-entry box.
//
// Pasting a table in and getting a chart is the fastest path this feature has,
// and it works by sniffing rather than asking -- which separator, and whether
// the first row is a header. Sniffing is the right call for the speed, and it
// is also exactly the kind of thing that quietly guesses wrong, so the guesses
// are pinned here.

void main() {
  test("a tab separated table with a header", () {
    var data = ChartData.parse("\tSales\tCosts\n"
        "Q1\t10\t4\n"
        "Q2\t20\t9\n");
    expect(data.categories, ["Q1", "Q2"]);
    expect(data.series.length, 2);
    expect(data.series[0].name, "Sales");
    expect(data.series[0].values, [10.0, 20.0]);
    expect(data.series[1].name, "Costs");
    expect(data.series[1].values, [4.0, 9.0]);
  });

  test("commas work too", () {
    var data = ChartData.parse(",Sales\nQ1,10\nQ2,20");
    expect(data.categories, ["Q1", "Q2"]);
    expect(data.series.single.values, [10.0, 20.0]);
  });

  test("runs of spaces work, so a table typed by hand parses", () {
    var data = ChartData.parse("Name    Sales\nQ1      10\nQ2      20");
    expect(data.categories, ["Q1", "Q2"]);
    expect(data.series.single.name, "Sales");
    expect(data.series.single.values, [10.0, 20.0]);
  });

  test("a first row of numbers is data, not a header", () {
    // The header is sniffed by whether the cells after the first parse as
    // numbers. A table with no header must not lose its first row.
    var data = ChartData.parse("Q1\t10\nQ2\t20");
    expect(data.categories, ["Q1", "Q2"]);
    expect(data.series.single.values, [10.0, 20.0]);
    expect(data.series.single.name, "Series 1");
  });

  test("percentages and blanks do not throw", () {
    var data = ChartData.parse("\tShare\nA\t40%\nB\t\nC\tnonsense");
    expect(data.series.single.values, [40.0, 0.0, 0.0]);
  });

  test("ragged rows are a gap, not an error", () {
    var data = ChartData.parse("\tOne\tTwo\nA\t1\t2\nB\t3");
    expect(data.valueAt(1, 1), 0);
    expect(data.valueAt(0, 1), 3);
  });

  test("valueAt is safe outside the data", () {
    var data = ChartData.parse("\tOne\nA\t1");
    expect(data.valueAt(9, 0), 0);
    expect(data.valueAt(0, 9), 0);
    expect(data.valueAt(-1, -1), 0);
  });

  test("blank lines and stray whitespace are ignored", () {
    var data = ChartData.parse("\n\n\tOne\n\n  A\t1  \n\nB\t2\n\n");
    expect(data.categories, ["A", "B"]);
    expect(data.series.single.values, [1.0, 2.0]);
  });

  test("nothing in, nothing out", () {
    expect(ChartData.parse("").isEmpty, isTrue);
    expect(ChartData.parse("   \n  ").isEmpty, isTrue);
  });

  test("asText and parse round trip", () {
    // The round trip is the whole feature of the entry box: what it shows is
    // what it will read back, so editing the text edits the chart.
    var original = ChartData.parse("\tSales\tCosts\nQ1\t10\t4.5\nQ2\t20\t9");
    var again = ChartData.parse(original.asText());

    expect(again.categories, original.categories);
    expect(again.series.length, original.series.length);
    for (var i = 0; i < original.series.length; i++) {
      expect(again.series[i].name, original.series[i].name);
      expect(again.series[i].values, original.series[i].values);
    }
  });

  test("whole numbers come back without a decimal point", () {
    // 10.0 printed as "10.0" would be read back fine but looks wrong in the
    // box, and every value in a typical table is a whole number.
    var text = ChartData.parse("\tOne\nA\t10\nB\t2.5").asText();
    expect(text, contains("10"));
    expect(text, isNot(contains("10.0")));
    expect(text, contains("2.5"));
  });
}
