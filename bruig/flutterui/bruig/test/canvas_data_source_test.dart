import 'dart:convert';
import 'dart:io';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_presets.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_data.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_data_source_test.dart is about numbers arriving from somewhere else
// and becoming a table.
//
// Two things are worth pinning down. The mapping, because an API that changes
// shape or a record missing a field has to give a blank cell rather than a
// broken canvas. And the refusals: fetching is off unless it has been turned
// on, and it is refused outright when a proxy is configured -- a request from
// here would not go through it, and quietly not going through somebody's Tor
// proxy is the worst thing this feature could do.

void main() {
  // The shape football-data.org actually answers with.
  Map<String, dynamic> standings() => {
        "standings": [
          {
            "type": "TOTAL",
            "table": [
              {
                "position": 1,
                "team": {"shortName": "Man City", "crest": "https://x/mc.png"},
                "playedGames": 2,
                "won": 2,
                "draw": 0,
                "lost": 0,
                "goalsFor": 6,
                "goalsAgainst": 2,
                "goalDifference": 4,
                "points": 6,
              },
              {
                "position": 2,
                "team": {"shortName": "Arsenal", "crest": "https://x/ar.png"},
                "playedGames": 2,
                "won": 2,
                "draw": 0,
                "lost": 0,
                "goalsFor": 4,
                "goalsAgainst": 0,
                "goalDifference": 4,
                "points": 6,
              },
            ],
          },
          {"type": "HOME", "table": []},
        ],
      };

  group("the mapping", () {
    test("a preset turns the answer into a league table", () {
      var source = footballData.applyTo(const DataSource(), "PL");
      var rows = rowsFromJson(standings(), source);

      expect(rows.first, [
        "",
        "",
        "Team",
        "Played",
        "Won",
        "Drawn",
        "Lost",
        "For",
        "Against",
        "GD",
        "Points"
      ]);
      expect(rows[1][2], "Man City");
      expect(rows[1].last, "6");
      expect(rows[2][2], "Arsenal");
      expect(rows.length, 3, reason: "the header and two teams");
    });

    test("whole numbers do not arrive as 6.0", () {
      // A points column reading 6.0 all the way down is a table nobody keeps.
      var source = footballData.applyTo(const DataSource(), "PL");
      var rows = rowsFromJson(standings(), source);
      for (var cell in rows[1].skip(3)) {
        expect(cell, isNot(contains(".")));
      }
    });

    test("it takes the first standings, not the empty home one", () {
      var source = footballData.applyTo(const DataSource(), "PL");
      expect(source.rowsPath, "standings.0.table");
      expect(rowsFromJson(standings(), source).length, 3);
    });

    test("a missing field is a blank cell, not a broken table", () {
      var json = standings();
      (json["standings"][0]["table"][1]["team"] as Map).remove("shortName");
      var rows =
          rowsFromJson(json, footballData.applyTo(const DataSource(), "PL"));
      expect(rows[2][2], "");
      expect(rows[2].last, "6", reason: "the rest of the row still arrived");
    });

    test("a path that leads nowhere gives no rows at all", () {
      // Refused rather than half a table: replacing good rows with rubbish is
      // worse than replacing nothing.
      var source = const DataSource(
          kind: DataKind.file,
          where: "x",
          rowsPath: "nothing.here",
          columns: [SourceColumn(header: "A", path: "a")]);
      expect(rowsFromJson(standings(), source), isEmpty);
    });

    test("a plain list of records needs no path", () {
      var source = const DataSource(kind: DataKind.file, where: "x", columns: [
        SourceColumn(header: "Name", path: "name"),
        SourceColumn(header: "Score", path: "score"),
      ]);
      var rows = rowsFromJson([
        {"name": "Hull", "score": 3},
      ], source);
      expect(rows, [
        ["Name", "Score"],
        ["Hull", "3"],
      ]);
    });

    test("a path walks lists as well as maps", () {
      expect(
          valueAtPath({
            "a": [
              {"b": 7}
            ]
          }, "a.0.b"),
          7);
      expect(valueAtPath({"a": []}, "a.3.b"), isNull);
      expect(valueAtPath({"a": 1}, "a.b"), isNull);
    });
  });

  group("reading a file", () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp("canvas_data_test");
    });
    tearDown(() => dir.delete(recursive: true));

    test("a file becomes rows, with no connection made", () async {
      var file = File("${dir.path}/table.json");
      await file.writeAsString(jsonEncode(standings()));

      var source = footballData
          .applyTo(const DataSource(), "PL")
          .copyWith(kind: DataKind.file, where: file.path);
      // allowFetching stays false throughout: a file must never need it.
      var result = await loadData(source);
      expect(result.worked, isTrue, reason: result.problem);
      expect(result.rows!.length, 3);
    });

    test("a missing file says so", () async {
      var result = await loadData(const DataSource(
          kind: DataKind.file,
          where: "/nowhere/at/all.json",
          columns: [SourceColumn(header: "A", path: "a")]));
      expect(result.worked, isFalse);
      expect(result.problem, contains("no file"));
    });

    test("a file that is not JSON says that instead", () async {
      var file = File("${dir.path}/notjson.json");
      await file.writeAsString("Hull City, 6 points");
      var result = await loadData(DataSource(
          kind: DataKind.file,
          where: file.path,
          columns: const [SourceColumn(header: "A", path: "a")]));
      expect(result.worked, isFalse);
      expect(result.problem, contains("not JSON"));
    });
  });

  group("what stops a fetch", () {
    var source = footballData.applyTo(const DataSource(), "PL");

    test("it is off unless it has been turned on", () async {
      var result = await loadData(source);
      expect(result.worked, isFalse);
      expect(result.problem, contains("switched off"));
    });

    test("a configured proxy refuses it rather than going round it", () async {
      // The one that matters. Somebody who has pointed this app at Tor has
      // said how they want it to reach the network; a request from the canvas
      // would not go that way, so it is not made.
      var result = await loadData(source, allowFetching: true, proxied: true);
      expect(result.worked, isFalse);
      expect(result.problem, contains("proxy"));
    });

    test("pictures are not collected either", () async {
      // Collecting crests is a request each, so it is behind the same switch.
      var rows = [
        ["", "Team"],
        ["https://x/mc.png", "Man City"],
      ];
      expect(
          await collectPictures(
              rows,
              const DataSource(columns: [
                SourceColumn(picture: true),
                SourceColumn(header: "Team"),
              ])),
          rows);
    });
  });

  test("a key is never written into the document", () {
    // A canvas is a thing people send each other. The address and the mapping
    // travel with it; the key is the reader's and stays on their machine.
    var element = TableElement(
      const ElementBase(id: "t"),
      rows: const [
        ["a"]
      ],
      source: footballData.applyTo(const DataSource(), "ELC"),
    );
    var encoded = CanvasDocument(elements: [element]).encode();
    expect(encoded, contains("football-data.org"));
    expect(encoded.toLowerCase(), isNot(contains("x-auth-token")));
    expect(encoded.toLowerCase(), isNot(contains("\"key\"")));

    var back = CanvasDocument.decode(encoded)!.elements.first as TableElement;
    expect(back.source.host, "api.football-data.org");
    expect(back.source.columns.length, footballDataColumns.length);
    expect(back.source.preset, "football-data.org");
  });
  group("a chart reading a table", () {
    TableElement league() => TableElement(
          const ElementBase(id: "t"),
          headerRow: true,
          rows: const [
            ["", "Team", "GD", "Points"],
            ["1", "Man City", "4", "6"],
            ["2", "Arsenal", "4", "6"],
            ["3", "Liverpool", "2", "5"],
          ],
        );

    test("the table's header names the series", () {
      var data = chartDataFromTable(league(),
          const TableLink(tableId: "t", categoryColumn: 1, valueColumns: [3]));
      expect(data.categories, ["Man City", "Arsenal", "Liverpool"]);
      expect(data.series.single.name, "Points",
          reason: "without anybody typing it");
      expect(data.series.single.values, [6, 6, 5]);
    });

    test("two columns are two series", () {
      var data = chartDataFromTable(
          league(),
          const TableLink(
              tableId: "t", categoryColumn: 1, valueColumns: [2, 3]));
      expect([for (var s in data.series) s.name], ["GD", "Points"]);
      expect(data.series.first.values, [4, 4, 2]);
      expect(data.series.first.color, isNot(data.series.last.color),
          reason: "two series a reader can tell apart");
    });

    test("a column that is not numbers is flat rather than an error", () {
      // A league table has a crest column and a form column in it, and
      // picking one should give a chart that is obviously wrong rather than
      // an exception.
      var data = chartDataFromTable(league(),
          const TableLink(tableId: "t", categoryColumn: 1, valueColumns: [1]));
      expect(data.series.single.values, [0, 0, 0]);
    });

    test("the header row is never a data point", () {
      var data = chartDataFromTable(league(),
          const TableLink(tableId: "t", categoryColumn: 1, valueColumns: [3]));
      expect(data.categories, isNot(contains("Team")));
      expect(data.categories.length, 3);
    });

    test("a link with no columns chosen produces nothing", () {
      expect(chartDataFromTable(league(), const TableLink(tableId: "t")).series,
          isEmpty);
    });

    test("the link survives a round trip", () {
      var chart = ChartElement(
        const ElementBase(id: "c"),
        fromTable: const TableLink(
            tableId: "t", categoryColumn: 1, valueColumns: [2, 3]),
      );
      var back =
          CanvasDocument.decode(CanvasDocument(elements: [chart]).encode())!
              .elements
              .first;
      var link = (back as ChartElement).fromTable;
      expect(link.tableId, "t");
      expect(link.categoryColumn, 1);
      expect(link.valueColumns, [2, 3]);
    });
  });
}
