import 'dart:convert';
import 'dart:io';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_presets.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_data.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/data_connect.dart';
import 'package:bruig/plugin_system/canvas/ui/data_studio.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/canvas_audio_fake.dart';

// canvas_data_connect_test.dart is Connect data (Ken, 2026-11-15: "how do
// you ... import or use an API?"; the prototype's steps chosen 2026-11-16):
// a sheet owns its connection. A table's old source moves onto its sheet on
// opening; a refresh fills the sheet from A1 keeping the sheet's own columns
// with their rows, grows the views that showed it whole, and says which
// cells changed; the studio's steps and the connected sheet's card.

const league = [
  ["Team", "Pts"],
  ["Arsenal", "9"],
  ["Chelsea", "6"],
];

const source = DataSource(
  kind: DataKind.file,
  where: "/nowhere.json",
  columns: [
    SourceColumn(header: "Team", path: "name"),
    SourceColumn(header: "Pts", path: "points"),
  ],
  matchColumn: 0,
);

void main() {
  // The sidebars' sections open, as these tests are of what each control
  // does; where they are folded is the sidebar's own test.
  setUp(() => CanvasSection.openAll = true);
  tearDown(() => CanvasSection.openAll = false);
  group("a refresh into a sheet", () {
    test("fills from A1; its own columns stay with their rows", () {
      var sheet = const DataSheet(id: "s", cells: [
        ["Team", "Pts", "Note"],
        ["Arsenal", "9", "top"],
        ["Chelsea", "6", "watch"],
      ]);
      var next = sheetFromSource(
          sheet,
          [
            ["Team", "Pts"],
            ["Chelsea", "12"],
            ["Arsenal", "10"],
            ["Spurs", "4"],
          ],
          source);
      expect(next.cells, [
        ["Team", "Pts", "Note"],
        ["Chelsea", "12", "watch"],
        ["Arsenal", "10", "top"],
        ["Spurs", "4", ""],
      ]);
      expect(next.source, source);
    });

    test("an empty sheet fills; headings kept only once connected", () {
      var empty = const DataSheet(id: "s");
      expect(sheetFromSource(empty, league, source).cells, league);
      var connected = const DataSheet(id: "s", cells: [
        ["Club", "Points"],
        ["Arsenal", "9"],
      ]);
      var again = sheetFromSource(connected, league, source, keepHeads: true);
      expect(again.cells.first, ["Club", "Points"]);
    });

    test("the cells that changed", () {
      expect(
          changedCells(league, [
            ["Team", "Pts"],
            ["Arsenal", "10"],
            ["Chelsea", "6"],
            ["Spurs", "4"],
          ]),
          {(1, 1), (3, 0), (3, 1)});
    });
  });

  group("the sheet owns the connection", () {
    test("a table's source moves onto its sheet on opening", () {
      var json = CanvasDocument(elements: [
        TableElement(const ElementBase(id: "t"),
            rows: league,
            source: footballData.applyTo(const DataSource(), "PL")),
      ]).toJson();
      var doc = CanvasDocument.fromJson(
          jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
      var sheet = doc.sheets.single;
      expect(sheet.source.preset, footballData.id);
      expect((doc.elements.single as TableElement).source.on, isFalse);
      // And saved and opened again, still there.
      var back = CanvasDocument.fromJson(
          jsonDecode(jsonEncode(doc.toJson())) as Map<String, dynamic>);
      expect(back.sheets.single.source.preset, footballData.id);
      expect(back.sheets.single.source.host, "api.football-data.org");
    });

    test("a refresh grows the tables that showed the sheet whole, one step",
        () {
      var doc = CanvasDocument.fromJson(CanvasDocument(elements: [
        TableElement(const ElementBase(id: "t"), rows: league),
      ]).toJson());
      var c = CanvasController(doc, audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      var id = c.document.sheets.single.id;
      var changed = c.receiveSheet(
          id,
          [
            ...league,
            ["Spurs", "4"]
          ],
          source);
      expect(changed, {(3, 0), (3, 1)});
      var t = c.document.elementById("t") as TableElement;
      expect(t.rows.length, 4, reason: "the view grew to the new rows");
      expect(c.sheetById(id)!.source, source);
      c.undo();
      expect((c.document.elementById("t") as TableElement).rows.length, 3);
      expect(c.sheetById(id)!.source.on, isFalse);
    });

    test("disconnected, the numbers stay", () {
      var doc = CanvasDocument.fromJson(CanvasDocument(elements: [
        TableElement(const ElementBase(id: "t"), rows: league),
      ]).toJson());
      var c = CanvasController(doc, audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      var id = c.document.sheets.single.id;
      c.receiveSheet(id, league, source);
      c.setSheetSource(id, const DataSource());
      expect(c.sheetById(id)!.source.on, isFalse);
      expect(c.sheetById(id)!.cells, league);
    });
  });

  group("reading an answer", () {
    var answer = {
      "competition": {"name": "PL"},
      "standings": [
        {
          "table": [
            {
              "team": {"name": "Arsenal", "crest": "https://x/a.png"},
              "points": 9
            },
            {
              "team": {"name": "Chelsea", "crest": "https://x/c.png"},
              "points": 6
            },
          ]
        }
      ],
    };

    test("the lists in it, and the fields its records have", () {
      expect(listsIn(answer), [("standings", 1), ("standings.0.table", 2)]);
      expect(fieldsAt(answer, "standings.0.table"),
          containsAll(["team.name", "team.crest", "points"]));
      var mapped = mapData(
          answer,
          const DataSource(
              kind: DataKind.file,
              where: "x",
              rowsPath: "standings.0.table",
              columns: [
                SourceColumn(header: "Team", path: "team.name"),
                SourceColumn(header: "Pts", path: "points"),
              ]));
      expect(mapped.rows, [
        ["Team", "Pts"],
        ["Arsenal", "9"],
        ["Chelsea", "6"],
      ]);
    });

    test("a file fetched for a sheet, through the same engine", () async {
      var dir = await Directory.systemTemp.createTemp("connect");
      addTearDown(() => dir.delete(recursive: true));
      var file = File("${dir.path}/league.json");
      await file.writeAsString(jsonEncode([
        {"name": "Arsenal", "points": 9},
        {"name": "Spurs", "points": 4},
      ]));
      var got = await fetchSheetRows(source.copyWith(where: file.path), league,
          allowed: false, proxied: false);
      expect(got.worked, isTrue);
      expect(got.rows, [
        ["Team", "Pts"],
        ["Arsenal", "9"],
        ["Spurs", "4"],
      ]);
      var missing = await fetchSheetRows(
          source.copyWith(where: "${dir.path}/gone.json"), league,
          allowed: false, proxied: false);
      expect(missing.problem, contains("no file"));
      var web = await fetchSheetRows(
          source.copyWith(kind: DataKind.url, where: "https://example.com/x"),
          league,
          allowed: false,
          proxied: false);
      expect(web.problem, contains("Fetching is switched off"),
          reason: "nothing is asked of the web while fetching is off");
    });
  });

  group("in the Data Studio", () {
    late CanvasController c;

    Future<void> studio(WidgetTester tester,
        {DataSource sheetSource = const DataSource(),
        double scale = 1.25}) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var doc = CanvasDocument.fromJson(CanvasDocument(elements: [
        TableElement(const ElementBase(id: "t"), rows: league),
      ]).toJson());
      c = CanvasController(doc, audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      var id = c.document.sheets.single.id;
      if (sheetSource.on) c.setSheetSource(id, sheetSource);
      c.openDataStudio(id, view: "t");
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (_) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (_) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(
              create: (_) => CanvasPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: DataStudio(
                    controller: c,
                    sheetId: c.dataStudio.value!,
                    onDone: c.closeDataStudio))),
      ));
      await tester.pumpAndSettle();
    }

    String step(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const ValueKey("connectStep"))).data!;

    testWidgets("Connect data: a source chosen, its settings, fetching off",
        (tester) async {
      await studio(tester);
      final connect = find.byKey(const ValueKey("dataStudioConnectData"));
      await tester.ensureVisible(connect);
      await tester.tap(connect);
      await tester.pumpAndSettle();
      expect(step(tester), startsWith("Step 1 of 4"));
      expect(find.byKey(ValueKey("connectSource-${footballData.id}")),
          findsOneWidget);
      // Nothing chosen, nothing to go on to.
      expect(
          tester
              .widget<Material>(find.descendant(
                  of: find.byKey(const ValueKey("connectNext")),
                  matching: find.byType(Material)))
              .color,
          isNotNull);
      await tester.tap(find.byKey(const ValueKey("connectSource-web")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("connectNext")));
      await tester.pumpAndSettle();
      expect(step(tester), startsWith("Step 2 of 4"));
      expect(find.byKey(const ValueKey("connectFetchingOff")), findsOneWidget,
          reason: "fetching is off until the reader turns it on");
      expect(find.byKey(const ValueKey("connectKey")), findsOneWidget);
      // Back, a preset instead: its competitions offered.
      await tester.tap(find.byKey(const ValueKey("connectBack")));
      await tester.pumpAndSettle();
      final preset = find.byKey(ValueKey("connectSource-${footballData.id}"));
      await tester.ensureVisible(preset);
      await tester.tap(preset);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("connectNext")));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("connectChoice")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("connectCancel")));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("connectStep")), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets("a connected sheet: its card, its tab, edit and disconnect",
        (tester) async {
      await studio(tester,
          sheetSource: footballData.applyTo(const DataSource(), "PL"));
      expect(find.byKey(const ValueKey("sheetSourceCard")), findsOneWidget);
      expect(
          find.textContaining(
              "· ${footballData.shortLabel.isEmpty ? footballData.label : footballData.shortLabel}"),
          findsWidgets);
      await tester.ensureVisible(find.byKey(const ValueKey("sheetSourceEdit")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("sheetSourceEdit")));
      await tester.pumpAndSettle();
      expect(
          tester.widget<Text>(find.byKey(const ValueKey("connectTitle"))).data,
          "Edit connection");
      expect(step(tester), startsWith("Step 2 of 4"));
      await tester.tap(find.byKey(const ValueKey("connectCancel")));
      await tester.pumpAndSettle();
      await tester
          .ensureVisible(find.byKey(const ValueKey("sheetSourceDisconnect")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("sheetSourceDisconnect")));
      await tester.pumpAndSettle();
      expect(c.document.sheets.single.source.on, isFalse);
      expect(c.document.sheets.single.cells, league);
      expect(find.byKey(const ValueKey("sheetSourceCard")), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets("the whole way: a file, its columns, into this sheet",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var dir = (await tester
          .runAsync(() => Directory.systemTemp.createTemp("connect")))!;
      addTearDown(() => dir.deleteSync(recursive: true));
      var path = "${dir.path}/league.json";
      await tester.runAsync(() => File(path).writeAsString(jsonEncode({
            "updated": "today",
            "clubs": [
              {"name": "Arsenal", "points": 10, "crest": "a"},
              {"name": "Chelsea", "points": 12, "crest": "c"},
              {"name": "Spurs", "points": 4, "crest": "s"},
            ]
          })));
      await studio(tester);
      final connect = find.byKey(const ValueKey("dataStudioConnectData"));
      await tester.ensureVisible(connect);
      await tester.tap(connect);
      await tester.pumpAndSettle();
      await tester
          .ensureVisible(find.byKey(const ValueKey("connectSource-file")));
      await tester.tap(find.byKey(const ValueKey("connectSource-file")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("connectNext")));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey("connectPath")),
              matching: find.byType(TextField)),
          path);
      await tester.pump();

      // Fetch an example: real reading, outside the test's own clock.
      Future<void> settleReal() async {
        for (var i = 0; i < 20; i++) {
          await tester
              .runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
          await tester.pump();
        }
      }

      await tester.tap(find.byKey(const ValueKey("connectNext")));
      await settleReal();
      expect(step(tester), startsWith("Step 3 of 4"));
      // The rows found for it, and a column for each field; the sheet shows
      // what will come.
      expect(
          find.byKey(const ValueKey("dataStudioPreviewBar")), findsOneWidget);
      expect(find.byKey(const ValueKey("connectColumn-0")), findsOneWidget);
      expect(find.byKey(const ValueKey("connectPicture-2")), findsOneWidget,
          reason: "a crest is offered as a picture");
      // The crest left out; the first column renamed.
      await tester.tap(find.byKey(const ValueKey("connectColumnOn-2")));
      await tester.pump();
      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey("connectHeader-0-name")),
              matching: find.byType(TextField)),
          "Team");
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("connectNext")));
      await tester.pumpAndSettle();
      expect(step(tester), startsWith("Step 4 of 4"));
      await tester
          .tap(find.byKey(const ValueKey("studioPill-connectInto-false")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("connectNext")));
      await settleReal();

      var sheet = c.document.sheets.single;
      expect(sheet.cells, [
        ["Team", "Points"],
        ["Arsenal", "10"],
        ["Chelsea", "12"],
        ["Spurs", "4"],
      ]);
      expect(sheet.source.kind, DataKind.file);
      expect(sheet.source.fetchedAt, isNotNull);
      expect((c.document.elementById("t") as TableElement).rows.length, 4,
          reason: "the table showing it whole grew with it");
      expect(find.byKey(const ValueKey("sheetSourceCard")), findsOneWidget);
      // One step to undo.
      c.undo();
      await tester.pumpAndSettle();
      expect(c.document.sheets.single.cells, league);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    for (var scale in [0.65, 1.5]) {
      testWidgets("the steps fit at text size $scale", (tester) async {
        await studio(tester, scale: scale);
        final connect = find.byKey(const ValueKey("dataStudioConnectData"));
        await tester.ensureVisible(connect);
        await tester.tap(connect);
        await tester.pumpAndSettle();
        final web = find.byKey(const ValueKey("connectSource-web"));
        await tester.ensureVisible(web);
        await tester.tap(web);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey("connectNext")));
        await tester.pumpAndSettle();
        expect(step(tester), startsWith("Step 2 of 4"));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
