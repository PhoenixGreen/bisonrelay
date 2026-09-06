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

      // Pos and Badge are named -- the mapping and the order refer to them by
      // name -- and hidden on the canvas. See TableElement.hiddenHeaders.
      expect(rows.first, [
        "Pos",
        "Badge",
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

  group("keeping your own columns", () {
    // A table whose numbers come from an API and whose badges were chosen by
    // hand. Without this a refresh is all or nothing: stale numbers, or the
    // hand-made column wiped twice a week.
    var source = const DataSource(
      kind: DataKind.file,
      where: "x",
      matchColumn: 1,
      columns: [
        SourceColumn(header: "Pos", path: "position"),
        SourceColumn(header: "Team", path: "team"),
        SourceColumn(header: "Badge", path: "crest", picture: true, keep: true),
        SourceColumn(header: "Points", path: "points"),
      ],
    );

    List<List<String>> before() => [
          ["Pos", "Team", "Badge", "Points"],
          ["1", "Hull City", "img:mine-hull", "6"],
          ["2", "Arsenal", "img:mine-arsenal", "4"],
        ];

    test("a kept column survives the refresh", () {
      var after = [
        ["Pos", "Team", "Badge", "Points"],
        ["1", "Hull City", "", "9"],
        ["2", "Arsenal", "", "7"],
      ];
      var merged = keepColumns(before(), after, source);
      expect(merged[1][2], "img:mine-hull");
      expect(merged[1][3], "9", reason: "the numbers still came through");
    });

    test("a badge follows its team up the table", () {
      // The one that matters. Arsenal has climbed above Hull; kept by row
      // number, Arsenal would be wearing Hull's badge.
      var after = [
        ["Pos", "Team", "Badge", "Points"],
        ["1", "Arsenal", "", "9"],
        ["2", "Hull City", "", "7"],
      ];
      var merged = keepColumns(before(), after, source);
      expect(merged[1][1], "Arsenal");
      expect(merged[1][2], "img:mine-arsenal");
      expect(merged[2][2], "img:mine-hull");
    });

    test("a club that was not there before gets nothing, not somebody else's",
        () {
      var after = [
        ["Pos", "Team", "Badge", "Points"],
        ["1", "Leeds", "", "9"],
      ];
      expect(keepColumns(before(), after, source)[1][2], "");
    });

    test("matching by position is still available for a fixed list", () {
      var byPosition = source.copyWith(matchColumn: -1);
      var after = [
        ["Pos", "Team", "Badge", "Points"],
        ["1", "Arsenal", "", "9"],
      ];
      expect(keepColumns(before(), after, byPosition)[1][2], "img:mine-hull",
          reason: "the first row keeps the first row's picture");
    });

    test("nothing marked keep leaves the new rows exactly as they came", () {
      var plain = source.copyWith(columns: [
        for (var c in source.columns) c.copyWith(keep: false),
      ]);
      var after = [
        ["Pos", "Team", "Badge", "Points"],
        ["1", "Hull City", "", "9"],
      ];
      expect(identical(keepColumns(before(), after, plain), after), isTrue);
    });
  });

  test("a hidden heading keeps its name and is not drawn", () {
    // A column of badges needs a name for the mapping and the order to refer
    // to, and wants nothing written over the badges.
    var table = TableElement(
      const ElementBase(id: "t"),
      headerRow: true,
      rows: const [
        ["Pos", "Badge", "Team"],
        ["1", "img:x", "Hull City"],
      ],
      hiddenHeaders: const [1],
    );

    expect(table.header[1], "Badge", reason: "the name is still there");
    expect(table.shows(0, 1), isFalse, reason: "and is not drawn");
    expect(table.shows(0, 2), isTrue);
    expect(table.shows(1, 1), isTrue,
        reason: "only the header is hidden, not the column");

    var back =
        CanvasDocument.decode(CanvasDocument(elements: [table]).encode())!
            .elements
            .first;
    expect((back as TableElement).hiddenHeaders, [1]);
  });

  test("the football preset names its badge column and hides it", () {
    expect(footballData.hiddenHeaders, [0, 1]);
    expect(footballDataColumns[1].header, "Badge");
    expect(footballDataColumns[1].keep, isTrue,
        reason: "badges chosen by hand survive a refresh");
    expect(footballData.matchColumn, 2);
    expect(footballDataColumns[footballData.matchColumn].header, "Team",
        reason: "rows are matched by the club, not by their position");
  });
}
