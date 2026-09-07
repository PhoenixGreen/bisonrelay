import 'dart:convert';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/data_presets.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_chart_source_test.dart is a chart fetching its own numbers.
//
// The fixtures are cut down from the real responses -- dcrdata's chart
// endpoint and CoinGecko's market chart -- rather than invented, because the
// shape of the answer is the whole of the mapping. Both were checked against
// the live APIs while this was written; what is pinned here is what they
// actually send, so a preset that stops matching one of them fails here
// rather than on somebody's canvas.

void main() {
  // dcrdata answers with parallel arrays: an array of timestamps and an array
  // of values, the same length, named for what they hold.
  var dcrdata = jsonEncode({
    "t": [1454889600, 1454976000, 1455062400, 1455148800],
    "supply": [
      168720623595120,
      169504574718296,
      170288525841472,
      171072476964648
    ],
    "axis": "time",
    "bin": "day",
  });

  // CoinGecko answers with a list of two-element arrays: when, and what.
  var gecko = jsonEncode({
    "prices": [
      [1786233600000, 12.866159254844426],
      [1786320000000, 12.881773733164675],
      [1786406400000, 12.73139693227813],
    ],
  });

  group("parallel arrays", () {
    test("become rows, one per index", () {
      var source = dcrdataChart.applyTo(const DataSource(), "coin-supply");
      var rows = rowsFromJson(jsonDecode(dcrdata), source);

      expect(rows.first, ["Date", "Coin supply (DCR)"]);
      expect(rows.length, 5, reason: "a header and four days");
      // In DCR rather than in atoms, which is what the chain counts in.
      expect(rows[1][1], "1687206.2359512");
    });

    test("the shortest array decides how many rows there are", () {
      // These are read while they are being written: dcrdata's timestamps
      // arrive one ahead of the value it is still counting, and a chart whose
      // last point pairs today with an empty value has a spike in it that
      // nothing on the chain ever did.
      var source = dcrdataChart.applyTo(const DataSource(), "coin-supply");
      var short = jsonEncode({
        "t": [1454889600, 1454976000, 1455062400],
        "supply": [168720623595120, 169504574718296],
      });
      expect(rowsFromJson(jsonDecode(short), source).length, 3);
    });

    test("a missing array is no rows rather than half of them", () {
      var source = dcrdataChart
          .applyTo(const DataSource(), "coin-supply")
          .copyWith(columns: const [
        SourceColumn(header: "Date", path: "t"),
        SourceColumn(header: "Nope", path: "notthere"),
      ]);
      expect(rowsFromJson(jsonDecode(dcrdata), source), isEmpty);
    });

    test("a record-shaped source is unaffected", () {
      // The two shapes share a function, so the ordinary path has to be shown
      // still to work.
      var source = const DataSource(
        kind: DataKind.url,
        where: "https://example.test/x",
        rowsPath: "teams",
        columns: [SourceColumn(header: "Team", path: "name")],
      );
      var rows = rowsFromJson(
          jsonDecode('{"teams":[{"name":"Hull City"},{"name":"Leeds"}]}'),
          source);
      expect(rows, [
        ["Team"],
        ["Hull City"],
        ["Leeds"],
      ]);
    });
  });

  group("timestamps", () {
    test("seconds and milliseconds are told apart by size", () {
      expect(asDate(1454889600)!.toUtc().year, 2016);
      expect(asDate(1786233600000)!.toUtc().year, 2026);
      expect(asDate("2026-02-08T00:00:00Z")!.toUtc().year, 2026);
      expect(asDate("nonsense"), isNull);
      expect(asDate(null), isNull);
    });

    test("a date column is written out rather than left as a number", () {
      var source = coinGeckoPrice.applyTo(const DataSource(), "decred");
      var rows = rowsFromJson(jsonDecode(gecko), source);
      expect(rows.first, ["Date", "Price (USD)"]);
      expect(rows[1][0], isNot(contains("1786")),
          reason: "a chart labelled 1786233600000 is a chart nobody can read");
      expect(rows[1][1], startsWith("12.86"));
    });
  });

  group("thinning", () {
    List<List<String>> rows(int n) => [
          for (var i = 0; i < n; i++) ["$i"]
        ];

    test("leaves a short series alone", () {
      expect(thinTo(rows(50), 120).length, 50);
      expect(thinTo(rows(50), 0).length, 50);
    });

    test("keeps the ends", () {
      // The last point especially: a price chart that stops three weeks ago
      // because the arithmetic happened to land there is quietly wrong about
      // today.
      var thinned = thinTo(rows(3864), 120);
      expect(thinned.length, 120);
      expect(thinned.first.first, "0");
      expect(thinned.last.first, "3863");
    });

    test("and spreads the rest evenly", () {
      var thinned = thinTo(rows(1000), 10);
      expect([for (var r in thinned) int.parse(r.first)],
          [0, 111, 222, 333, 444, 555, 666, 777, 888, 999]);
    });
  });

  group("mapping rows onto a chart", () {
    test("the header names the series", () {
      var source = dcrdataChart.applyTo(const DataSource(), "ticket-price");
      var rows = rowsFromJson(
          jsonDecode(jsonEncode({
            "t": [1454889600, 1454976000],
            "price": [200000000, 210000000],
          })),
          source);

      var data = chartDataFromRows(rows, const ChartSourceMap());
      expect(data.series.single.name, "Ticket price (DCR)");
      expect(data.series.single.values, [2, 2.1]);
      expect(data.categories.length, 2);
    });

    test("more than one value column is more than one series", () {
      var rows = [
        ["Coin", "Price", "Market cap"],
        ["Decred", "16", "230"],
        ["Bitcoin", "79477", "1595937"],
      ];
      var data =
          chartDataFromRows(rows, const ChartSourceMap(valueColumns: [1, 2]));
      expect([for (var s in data.series) s.name], ["Price", "Market cap"]);
      expect(data.categories, ["Decred", "Bitcoin"]);
      expect(data.series[1].values, [230, 1595937]);
    });

    test("a column of words charts as zeroes rather than failing", () {
      var rows = [
        ["Coin", "Symbol"],
        ["Decred", "dcr"],
      ];
      var data = chartDataFromRows(rows, const ChartSourceMap());
      expect(data.series.single.values, [0]);
    });

    test("nothing chosen is no chart, not an empty one with axes", () {
      expect(
          chartDataFromRows([
            ["a"],
            ["1"]
          ], const ChartSourceMap(valueColumns: [])).isEmpty,
          isTrue);
    });
  });

  group("the presets themselves", () {
    test("dcrdata picks its columns from the series chosen", () {
      // Every series has its values in an array named after itself, so the
      // choice has to decide the mapping and not only the address.
      var supply = dcrdataChart.applyTo(const DataSource(), "coin-supply");
      var price = dcrdataChart.applyTo(const DataSource(), "ticket-price");

      expect(supply.columns[1].path, "supply");
      expect(price.columns[1].path, "price");
      expect(supply.shape, DataShape.columns);
      expect(supply.where, contains("coin-supply"));
      expect(price.columns[1].divide, 1e8, reason: "the chain counts atoms");
    });

    test("a chart source and a table source are offered different recipes", () {
      // Four thousand daily figures is a chart and is not a table; a league
      // table is a table, and a chart of it comes from the table beside it.
      var forCharts = [for (var p in presetsFor(chart: true)) p.id];
      var forTables = [for (var p in presetsFor(chart: false)) p.id];

      expect(forCharts, contains(dcrdataChart.id));
      expect(forCharts, isNot(contains(footballData.id)));
      expect(forTables, contains(footballData.id));
      expect(forTables, isNot(contains(dcrdataChart.id)));
      expect(forTables, contains(coinGeckoMarkets.id),
          reason: "a handful of coins is a table as readily as a chart");
    });

    test("every preset can be found again by the id it saves", () {
      for (var preset in dataPresets) {
        expect(presetById(preset.id)?.label, preset.label);
      }
    });

    test("a chart's source survives being saved and read back", () {
      var chart = ChartElement(
        const ElementBase(id: "c", x: 0, y: 0, width: 400, height: 300),
        source: dcrdataChart.applyTo(const DataSource(), "ticket-price"),
        fromSource: const ChartSourceMap(valueColumns: [1], maxPoints: 120),
      );
      var back = elementFromJson(chart.toJson()) as ChartElement;

      expect(back.source.preset, dcrdataChart.id);
      expect(back.source.shape, DataShape.columns);
      expect(back.source.columns[1].divide, 1e8);
      expect(back.source.columns[0].date, isNotEmpty);
      expect(back.fromSource.maxPoints, 120);
    });
  });

  group("moving a column", () {
    // The order of the columns is the order of the table, so moving one is a
    // thing people want -- and everything that refers to a column by number
    // has to be carried across with it, or a chart that was drawing the price
    // starts drawing the date and nothing says so.

    test("an index follows the column it points at", () {
      // The column being moved goes where it was sent.
      expect(movedIndex(1, 1, 3), 3);
      expect(movedIndex(4, 4, 0), 0);
      // The ones it moves past shuffle up or down by one.
      expect(movedIndex(2, 1, 3), 1);
      expect(movedIndex(3, 1, 3), 2);
      expect(movedIndex(0, 1, 3), 0, reason: "before both, so untouched");
      expect(movedIndex(4, 1, 3), 4, reason: "after both, so untouched");
      // And the other way.
      expect(movedIndex(1, 3, 1), 2);
      expect(movedIndex(2, 3, 1), 3);
      expect(movedIndex(0, 3, 1), 0);
    });

    test("and closes up behind a removed one", () {
      expect(indexAfterRemoval(0, 2), 0);
      expect(indexAfterRemoval(3, 2), 2);
      expect(indexAfterRemoval(2, 2), isNull,
          reason: "it was the one that went");
    });

    test("the source carries its own references", () {
      var source = const DataSource(columns: [
        SourceColumn(header: "Date", path: "t"),
        SourceColumn(header: "Team", path: "team"),
        SourceColumn(header: "Points", path: "points"),
      ], matchColumn: 1);

      var moved = source.withColumnMoved(1, 2);
      expect(
          [for (var c in moved.columns) c.header], ["Date", "Points", "Team"]);
      expect(moved.matchColumn, 2, reason: "still the team's column");

      var without = source.withoutColumn(0);
      expect([for (var c in without.columns) c.header], ["Team", "Points"]);
      expect(without.matchColumn, 0);
      expect(source.withoutColumn(1).matchColumn, -1,
          reason: "what identified a row has gone, so nothing does");
    });

    test("a chart goes on drawing the columns it was drawing", () {
      var map = const ChartSourceMap(categoryColumn: 0, valueColumns: [1, 3]);

      var moved = map.afterMove(3, 1);
      expect(moved.categoryColumn, 0);
      expect(moved.valueColumns, [1, 2],
          reason: "the same two columns, at their new numbers");

      var gone = map.afterRemoval(1);
      expect(gone.valueColumns, [2], reason: "one series went with its column");

      var axisGone = const ChartSourceMap(categoryColumn: 2, valueColumns: [3])
          .afterRemoval(2);
      expect(axisGone.categoryColumn, 0,
          reason: "the axis fell back rather than pointing past the end");
      expect(axisGone.valueColumns, [2]);
    });

    test("moving nothing anywhere silly is left alone", () {
      var source = const DataSource(columns: [
        SourceColumn(header: "A"),
        SourceColumn(header: "B"),
      ]);
      expect(source.withColumnMoved(0, 0).columns.length, 2);
      expect(source.withColumnMoved(0, 5).columns.first.header, "A");
      expect(source.withColumnMoved(-1, 1).columns.first.header, "A");
      expect(source.withoutColumn(7).columns.length, 2);
    });
  });
}
