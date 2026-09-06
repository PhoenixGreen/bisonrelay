import 'dart:convert';
import 'dart:io';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_presets.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_data.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_picture_cache.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        "Points",
        "Form"
      ]);
      expect(rows[1][2], "Man City");
      expect(rows[1][10], "6", reason: "points");
      // No form in this sample, so the guide is all dashes -- padded rather
      // than empty, so the column lines up whatever a club has played.
      expect(rows[1].last, "— — — — | —");
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
      expect(rows[2][10], "6", reason: "the rest of the row still arrived");
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

  group("what a refresh must not break", () {
    // A table somebody has set up: their own column names, their own rules
    // written against those names, their own badges.
    List<List<String>> mine() => [
          ["Pos", "Crest", "Club", "Points"],
          ["1", "img:mine-hull", "Hull City", "6"],
          ["2", "img:mine-arsenal", "Arsenal", "4"],
        ];

    var source = const DataSource(
      kind: DataKind.file,
      where: "x",
      matchColumn: 2,
      columns: [
        SourceColumn(header: "Position", path: "position"),
        SourceColumn(header: "Badge", path: "crest", picture: true, keep: true),
        SourceColumn(header: "Team", path: "team"),
        SourceColumn(header: "Pts", path: "points"),
      ],
    );

    test("the reader's column names survive it", () {
      // Rules pick their cells out by column name, so a refresh that renamed
      // the headers switched every rule off -- the crest column's padding
      // among them. The reader named these columns; the source did not.
      var arrived = [
        ["Position", "Badge", "Team", "Pts"],
        ["1", "", "Hull City", "9"],
      ];
      var merged = keepHeaders(mine(), arrived);
      expect(merged.first, ["Pos", "Crest", "Club", "Points"]);
      expect(merged[1][3], "9", reason: "the numbers still arrived");
    });

    test("a column the table did not have takes the source's name", () {
      var arrived = [
        ["Position", "Badge", "Team", "Pts", "Form"],
        ["1", "", "Hull City", "9", "WWD"],
      ];
      expect(keepHeaders(mine(), arrived).first.last, "Form");
    });

    test("a table with no header row is left alone", () {
      var arrived = [
        ["1", "", "Hull City", "9"],
      ];
      expect(identical(keepHeaders(mine(), arrived, headerRow: false), arrived),
          isTrue);
    });

    test("names and badges both survive together", () {
      // The two merges run one after the other on a refresh, and neither may
      // undo the other.
      var arrived = [
        ["Position", "Badge", "Team", "Pts"],
        ["1", "", "Arsenal", "9"],
        ["2", "", "Hull City", "7"],
      ];
      var merged = keepColumns(mine(), arrived, source);
      merged = keepHeaders(mine(), merged);
      expect(merged.first, ["Pos", "Crest", "Club", "Points"]);
      expect(merged[1][1], "img:mine-arsenal",
          reason: "Arsenal has climbed and brought its badge");
      expect(merged[2][1], "img:mine-hull");
    });
  });

  group("a form guide", () {
    // football-data.org sends "D,W,W,W,W" -- oldest first, and fewer than
    // five early in a season. As a cell that reads "D,W,W,W,W", which is not
    // what anybody wants to look at.
    const column =
        SourceColumn(header: "Form", path: "form", spread: 5, divider: "|");

    List<List<String>> rowsFor(String form) => rowsFromJson(
            [
              {"form": form},
            ],
            const DataSource(
                kind: DataKind.file, where: "x", columns: [column]));

    test("five results are laid out with the last marked off", () {
      expect(rowsFor("D,W,W,W,W")[1].single, "D W W W | W");
    });

    test("a short season is padded on the left", () {
      // So the most recent game is in the same place in every row whatever a
      // club has played, which is the whole reason the column lines up.
      expect(rowsFor("W,L")[1].single, "— — — W | L");
      expect(rowsFor("")[1].single, "— — — — | —");
    });

    test("more than five keeps the newest", () {
      expect(rowsFor("L,L,W,D,W,W")[1].single, "L W D W | W");
    });

    test("without a spread the value is left exactly as it came", () {
      var plain = rowsFromJson(
          [
            {"form": "D,W,W"},
          ],
          const DataSource(kind: DataKind.file, where: "x", columns: [
            SourceColumn(header: "Form", path: "form"),
          ]));
      expect(plain[1].single, "D,W,W");
    });

    test("the preset asks for one, and knows what else the API sends", () {
      expect(footballDataColumns.last.path, "form");
      expect(footballDataColumns.last.spread, 5);
      expect(footballDataColumns.last.divider, "|");

      // Every field a standings record carries, so the mapping is a list
      // before anything has been fetched. Taken from the published response.
      for (var field in ["form", "team.tla", "team.name", "goalDifference"]) {
        expect(footballData.fields, contains(field), reason: field);
      }
      for (var column in footballDataColumns) {
        expect(footballData.fields, contains(column.path),
            reason: "the preset maps ${column.path}");
      }
    });

    test("the spread survives a round trip", () {
      var back = SourceColumn.fromJson(column.toJson());
      expect(back.spread, 5);
      expect(back.divider, "|");
    });
  });

  group("the picture cache", () {
    // The store is content-addressed, so a crest fetched twice is one file --
    // but it is also two requests, and a league table is twenty crests that
    // have not changed since last week. On a rate-limited free tier that is
    // most of the allowance spent on pictures nobody needed.
    late Directory root;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      root = await Directory.systemTemp.createTemp("canvas_picture_cache");
      CanvasStorage.rootOverride = root.path;
    });

    tearDown(() async {
      CanvasStorage.rootOverride = null;
      if (await root.exists()) await root.delete(recursive: true);
    });

    test("a remembered crest is not asked for again", () async {
      var id = (await CanvasAssets.save(List.filled(64, 3, growable: false)))!;
      await CanvasPictureCache.remember("https://crests/65.png", id);

      expect(await CanvasPictureCache.known("https://crests/65.png"), id);
      expect(await CanvasPictureCache.known("https://crests/64.png"), isNull,
          reason: "a different crest is a different question");
    });

    test("a swept picture is forgotten rather than handed back", () async {
      // The store drops pictures no canvas refers to. An entry pointing at
      // one of those would hand back an id that draws a grey placeholder,
      // which is worse than fetching again.
      var id = (await CanvasAssets.save(List.filled(64, 7)))!;
      await CanvasPictureCache.remember("https://crests/70.png", id);
      await CanvasAssets.sweepUnused();

      expect(await CanvasAssets.exists(id), isFalse);
      expect(await CanvasPictureCache.known("https://crests/70.png"), isNull);
    });

    test("the cache holds no bytes, only the name of a file", () async {
      // It is an optimisation and nothing else: everything in it is checked
      // against the store before it is trusted, which is what makes it safe
      // to throw away.
      var id = (await CanvasAssets.save(List.filled(64, 9)))!;
      await CanvasPictureCache.remember("https://crests/1.png", id);
      var prefs = await SharedPreferences.getInstance();
      var saved = [
        for (var key in prefs.getKeys())
          if (key.startsWith("canvasPicture:")) prefs.getString(key),
      ];
      expect(saved, [id]);
    });
  });

  group("which fields the mapping offers", () {
    // Reported: a column mapped to the form guide was marked "not in the
    // data". The key is in every record football-data.org sends; its value is
    // null until a club has played, and a null field was being left out of
    // the list altogether.
    Future<DataResult> read(Map<String, dynamic> record) async {
      var dir = await Directory.systemTemp.createTemp("canvas_fields_test");
      addTearDown(() => dir.delete(recursive: true));
      var file = File("${dir.path}/one.json");
      await file.writeAsString(jsonEncode([record]));
      return loadData(DataSource(
          kind: DataKind.file,
          where: file.path,
          columns: const [SourceColumn(header: "A", path: "position")]));
    }

    test("a field that is there but empty is still a field", () async {
      var result = await read({"position": 1, "form": null});
      expect(result.worked, isTrue, reason: result.problem);
      expect(result.fields, contains("form"),
          reason: "the key is there; it is empty, which is a different thing");
    });

    test("an empty list is a field rather than nothing", () async {
      var result = await read({"position": 1, "matches": []});
      expect(result.fields, contains("matches"));
    });

    test("nested fields still come back by their full path", () async {
      var result = await read({
        "position": 1,
        "team": {"shortName": "Hull City", "crest": null},
      });
      expect(result.fields, contains("team.shortName"));
      expect(result.fields, contains("team.crest"),
          reason: "a club with no badge on file has not lost the field");
    });

    test("a null form still lays out as a padded guide", () async {
      // The other half of the same report: the column has to keep working,
      // not just stay in the list.
      var rows = rowsFromJson(
          [
            {"form": null},
          ],
          const DataSource(kind: DataKind.file, where: "x", columns: [
            SourceColumn(header: "Form", path: "form", spread: 5, divider: "|"),
          ]));
      expect(rows[1].single, "— — — — | —");
    });
  });
}
