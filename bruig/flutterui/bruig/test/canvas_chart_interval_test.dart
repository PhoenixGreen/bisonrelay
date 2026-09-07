import 'package:bruig/plugin_system/canvas/model/chart_interval.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_chart_interval_test.dart is a chart taking a reading on the dates it
// was asked for.
//
// Thinning a series evenly gives a readable chart and a meaningless axis: the
// points land wherever the arithmetic put them, so a ten-year chart is read
// against "Mar 17, Nov 19, Jul 22". One a year, on a date chosen, gives an
// axis that says 2017, 2018, 2019 and readings that can be compared with each
// other -- which is the whole of what this is for, and all of it is in where
// the marks fall.

void main() {
  /// daily is a date for every day between two years, which is the shape of
  /// every chain series there is.
  List<DateTime?> daily(DateTime from, DateTime to) {
    var out = <DateTime?>[];
    for (var at = from; !at.isAfter(to); at = at.add(const Duration(days: 1))) {
      out.add(at);
    }
    return out;
  }

  group("where the marks fall", () {
    test("a yearly reading lands on the date it was given", () {
      // The case this was built for: one a year on the seventh of February.
      const interval = ChartInterval(
          unit: IntervalUnit.year, month: DateTime.february, day: 7);
      var marks = interval.marks(DateTime(2020, 5, 1), DateTime(2024, 3, 1));

      expect([
        for (var m in marks) "${m.year}-${m.month}-${m.day}"
      ], [
        "2020-2-7",
        "2021-2-7",
        "2022-2-7",
        "2023-2-7",
        "2024-2-7",
      ]);
    });

    test("and the first one is not inside the series", () {
      // Walked back from the anchor, so a series starting a fortnight after
      // it still has a reading near its beginning rather than losing its
      // first year.
      const interval = ChartInterval(
          unit: IntervalUnit.year, month: DateTime.february, day: 7);
      var marks = interval.marks(DateTime(2020, 2, 21), DateTime(2021, 6, 1));
      expect(marks.first.year, 2020);
      expect(marks.first.month, 2);
    });

    test("every other year is every other year", () {
      // Phased on the anchor's own year rather than on whichever year the
      // data starts in, so the same setting gives the same years whatever
      // range is fetched. The first mark is a step before the series begins
      // -- see below -- and is dropped for want of a row near it.
      const interval =
          ChartInterval(unit: IntervalUnit.year, every: 2, month: 6, day: 1);
      var marks = interval.marks(DateTime(2016, 1, 1), DateTime(2024, 1, 1));
      expect([for (var m in marks) m.year], [2014, 2016, 2018, 2020, 2022]);
      expect(marks.every((m) => m.month == 6 && m.day == 1), isTrue);
    });

    test("an anniversary does not walk through the calendar", () {
      // Stepped through the year number rather than by adding 365 days, which
      // loses a day every fourth year.
      const interval = ChartInterval(unit: IntervalUnit.year, month: 3, day: 1);
      var marks = interval.marks(DateTime(2016, 1, 1), DateTime(2030, 1, 1));
      for (var mark in marks) {
        expect([mark.month, mark.day], [3, 1], reason: "$mark");
      }
    });

    test("the 31st of a short month is its last day, not the 1st of the next",
        () {
      const interval = ChartInterval(unit: IntervalUnit.month, day: 31);
      var marks = interval.marks(DateTime(2021, 1, 1), DateTime(2021, 5, 1));
      var february = marks.firstWhere((m) => m.month == 2);
      expect(february.day, 28);
      expect(marks.every((m) => m.day >= 28), isTrue,
          reason: "$marks — none of them should have slipped into the next "
              "month");
    });

    test("a weekly reading lands on the weekday asked for", () {
      const interval =
          ChartInterval(unit: IntervalUnit.week, weekday: DateTime.friday);
      var marks = interval.marks(DateTime(2026, 1, 5), DateTime(2026, 2, 1));
      expect(marks.every((m) => m.weekday == DateTime.friday), isTrue,
          reason: "$marks");
    });

    test("quarters sit on the quarter, not three months from the data", () {
      const interval = ChartInterval(unit: IntervalUnit.quarter, day: 1);
      var marks = interval.marks(DateTime(2024, 2, 14), DateTime(2024, 12, 31));
      expect([for (var m in marks) m.month], [1, 4, 7, 10]);
    });

    test("no unit, no marks", () {
      expect(
          const ChartInterval().marks(DateTime(2020), DateTime(2024)), isEmpty);
      expect(
          const ChartInterval(unit: IntervalUnit.year)
              .marks(DateTime(2024), DateTime(2020)),
          isEmpty,
          reason: "a series that ends before it starts");
    });
  });

  group("which rows stand for them", () {
    test("the row nearest each reading", () {
      var when = daily(DateTime(2020, 1, 1), DateTime(2023, 12, 31));
      var picked = pickAtIntervals(
          when,
          const ChartInterval(
              unit: IntervalUnit.year, month: DateTime.february, day: 7));

      expect(picked.length, 4, reason: "four years in the series");
      for (var i in picked) {
        expect(when[i]!.month, 2);
        expect(when[i]!.day, 7, reason: "the reading is on the day asked for");
      }
    });

    test("nothing is drawn where the data has a gap", () {
      // A chart that draws a point for a year it has no figures for is a
      // chart telling a lie about the gap.
      var when = <DateTime?>[
        DateTime(2020, 2, 7),
        DateTime(2021, 2, 7),
        // Nothing at all for two years.
        DateTime(2024, 2, 7),
      ];
      var picked = pickAtIntervals(
          when,
          const ChartInterval(
              unit: IntervalUnit.year, month: DateTime.february, day: 7));
      expect(picked, [0, 1, 2]);
    });

    test("and no row stands for two readings", () {
      // A series that stops half way through has fewer readings, not the same
      // one over and over.
      var when = daily(DateTime(2020, 1, 1), DateTime(2020, 3, 1));
      var picked = pickAtIntervals(
          when, const ChartInterval(unit: IntervalUnit.year, month: 6, day: 1));
      expect(picked.length, lessThanOrEqualTo(1));
      expect(picked.toSet().length, picked.length);
    });

    test("no interval keeps every row", () {
      var when = daily(DateTime(2020, 1, 1), DateTime(2020, 1, 10));
      expect(pickAtIntervals(when, const ChartInterval()).length, when.length);
    });

    test("rows with no date at all fall back to keeping them", () {
      var picked = pickAtIntervals(
          const [null, null], const ChartInterval(unit: IntervalUnit.year));
      expect(picked, [0, 1]);
    });
  });

  group("through to the chart", () {
    /// A year of daily readings, as the mapping would produce them: the cells
    /// formatted for the eye, and the raw rows with the times still in them.
    (List<List<String>>, List<List<String>>) series() {
      var rows = <List<String>>[
        ["Date", "Supply"]
      ];
      var raw = <List<String>>[
        ["Date", "Supply"]
      ];
      for (var at = DateTime(2020, 1, 1);
          at.isBefore(DateTime(2024, 1, 1));
          at = at.add(const Duration(days: 1))) {
        rows.add(["${at.day}/${at.month}/${at.year}", "${at.year}"]);
        raw.add([at.toIso8601String(), "${at.year}"]);
      }
      return (rows, raw);
    }

    test("one reading a year, on the day asked for", () {
      var (rows, raw) = series();
      var map = const ChartSourceMap(
        valueColumns: [1],
        interval: ChartInterval(
            unit: IntervalUnit.year, month: DateTime.february, day: 7),
      );

      var data = chartDataFromRows(rows, map, when: datesIn(raw, 0));
      expect(data.categories, ["7/2/2020", "7/2/2021", "7/2/2022", "7/2/2023"]);
      expect(data.series.single.values, [2020, 2021, 2022, 2023]);
    });

    test("and it replaces the thinning rather than joining it", () {
      // Two answers to the same question. Both applied, a set of yearly
      // readings would be thinned to every third year and still labelled as
      // though it were yearly.
      var (rows, raw) = series();
      var map = const ChartSourceMap(
        valueColumns: [1],
        maxPoints: 2,
        interval: ChartInterval(unit: IntervalUnit.year, month: 2, day: 7),
      );
      expect(
          chartDataFromRows(rows, map, when: datesIn(raw, 0)).categories.length,
          4);
    });

    test("without the dates it thins instead", () {
      // Which is what happens on a canvas opened this morning: the raw rows
      // are this sitting's, so a chart that has not been refreshed falls back
      // rather than drawing nothing.
      var (rows, _) = series();
      var map = const ChartSourceMap(
        valueColumns: [1],
        maxPoints: 12,
        interval: ChartInterval(unit: IntervalUnit.year, month: 2, day: 7),
      );
      expect(chartDataFromRows(rows, map).categories.length, 12);
    });

    test("dates are read out of the unformatted rows", () {
      // The formatted cell has lost them: "Feb 26" has no day in it, and a
      // two-digit year does not parse back to anything anybody means.
      expect(datesIn(const [], 0), isNull);
      expect(
          datesIn(const [
            ["Date"],
            ["not a date"],
          ], 0),
          isNull);
      var dates = datesIn(const [
        ["Date"],
        ["1454889600"],
        ["2026-02-07T00:00:00Z"],
      ], 0);
      expect(dates!.length, 2);
      expect(dates.first!.toUtc().year, 2016);
      expect(dates.last!.toUtc().day, 7);
    });

    test("the mapping survives being saved and read back", () {
      var map = const ChartSourceMap(
        valueColumns: [1],
        interval:
            ChartInterval(unit: IntervalUnit.year, every: 2, month: 2, day: 7),
      );
      var back = ChartSourceMap.fromJson(map.toJson());
      expect(back.interval.unit, IntervalUnit.year);
      expect(back.interval.every, 2);
      expect(back.interval.month, 2);
      expect(back.interval.day, 7);
      // An older chart, saved before intervals existed, takes every point.
      expect(
          ChartSourceMap.fromJson(const {
            "cat": 0,
            "vals": [1]
          }).interval.on,
          isFalse);
    });
  });

  group("the raw rows the loader keeps", () {
    test("a date column arrives twice: written out, and as it came", () {
      var source = const DataSource(
        shape: DataShape.columns,
        columns: [
          SourceColumn(header: "Date", path: "t", date: "MMM yy"),
          SourceColumn(header: "Supply", path: "supply", divide: 1e8),
        ],
      );
      var json = {
        "t": [1454889600, 1454976000],
        "supply": [100000000, 200000000],
      };

      var rows = rowsFromJson(json, source);
      var raw = rowsFromJson(json, source, raw: true);

      expect(rows[1][0], isNot(contains("1454")),
          reason: "the cells the reader sees are the formatted ones");
      expect(raw[1][0], "1454889600",
          reason: "and the raw ones still have the time in them");
      // Everything else is untouched: the scaling is not a formatting choice.
      expect(raw[1][1], rows[1][1]);
    });
  });

  group("what a reading is made of", () {
    /// Two years of one transaction a day, so a yearly total is a number
    /// anybody can check: 366 and 365.
    (List<List<String>>, List<List<String>>) perDay() {
      var rows = <List<String>>[
        ["Date", "Transactions"]
      ];
      var raw = <List<String>>[
        ["Date", "Transactions"]
      ];
      for (var at = DateTime(2020, 1, 1);
          at.isBefore(DateTime(2022, 1, 1));
          at = at.add(const Duration(days: 1))) {
        rows.add(["${at.day}/${at.month}/${at.year}", "1"]);
        raw.add([at.toIso8601String(), "1"]);
      }
      return (rows, raw);
    }

    test("a year of transactions added up is the year's transactions", () {
      // The case this exists for. One a day, so the total is the number of
      // days in the year.
      var (rows, raw) = perDay();
      var data = chartDataFromRows(
        rows,
        const ChartSourceMap(
          valueColumns: [1],
          interval:
              ChartInterval(unit: IntervalUnit.year, how: IntervalPick.total),
        ),
        when: datesIn(raw, 0),
      );

      expect(data.series.single.values, [366, 365],
          reason: "2020 was a leap year");
      expect(data.categories, ["1/1/2020", "1/1/2021"]);
    });

    test("and the same series averaged is one a day", () {
      // Which is what the seconds between blocks would want: adding those up
      // over a year is a number that means nothing.
      var (rows, raw) = perDay();
      var data = chartDataFromRows(
        rows,
        const ChartSourceMap(
          valueColumns: [1],
          interval:
              ChartInterval(unit: IntervalUnit.year, how: IntervalPick.mean),
        ),
        when: datesIn(raw, 0),
      );
      expect(data.series.single.values, [1, 1]);
    });

    test("the highest and the lowest are the period's own", () {
      var rows = <List<String>>[
        ["Date", "Rate"],
        ["1 Jan", "5"],
        ["2 Jan", "9"],
        ["3 Jan", "1"],
      ];
      var when = <DateTime?>[
        DateTime(2020, 1, 1),
        DateTime(2020, 1, 2),
        DateTime(2020, 1, 3),
      ];
      ChartData at(IntervalPick how) => chartDataFromRows(
            rows,
            ChartSourceMap(
                valueColumns: const [1],
                interval: ChartInterval(unit: IntervalUnit.year, how: how)),
            when: when,
          );

      expect(at(IntervalPick.high).series.single.values, [9]);
      expect(at(IntervalPick.low).series.single.values, [1]);
      expect(at(IntervalPick.total).series.single.values, [15]);
    });

    test("a period runs from its own mark, not around it", () {
      // A reading *on* the seventh of February is the row nearest it from
      // either side; a year *added up* from the seventh of February is the
      // rows from that date until the next one. The sixth of February belongs
      // to the year before.
      var when = <DateTime?>[
        DateTime(2020, 2, 6),
        DateTime(2020, 2, 7),
        DateTime(2020, 2, 8),
      ];
      var groups = groupAtIntervals(
          when,
          const ChartInterval(
              unit: IntervalUnit.year, month: DateTime.february, day: 7));

      expect(groups.length, 2);
      expect(groups.first.rows, [0], reason: "the sixth is last year's");
      expect(groups.last.rows, [1, 2]);
    });

    test("a period with nothing in it is not drawn as zero", () {
      // A bar of nothing for a year says the chain stopped, which is a
      // different claim from having no figures.
      var when = <DateTime?>[
        DateTime(2020, 6, 1),
        DateTime(2023, 6, 1),
      ];
      var groups = groupAtIntervals(
          when, const ChartInterval(unit: IntervalUnit.year, month: 6, day: 1));
      expect(groups.length, 2);
      expect([for (var g in groups) g.at.year], [2020, 2023]);
    });

    test("combining nothing is nothing rather than an error", () {
      expect(IntervalPick.total.of(const []), 0);
      expect(IntervalPick.mean.of(const []), 0);
      expect(IntervalPick.nearest.of(const [4, 9]), 4);
    });

    test("it survives being saved and read back", () {
      var interval =
          const ChartInterval(unit: IntervalUnit.year, how: IntervalPick.total);
      expect(ChartInterval.fromJson(interval.toJson()).how, IntervalPick.total);
      // An older chart, saved before there was a choice, takes the reading on
      // the date -- which is what it was doing.
      expect(ChartInterval.fromJson(const {"unit": "year"}).how,
          IntervalPick.nearest);
    });
  });
}
