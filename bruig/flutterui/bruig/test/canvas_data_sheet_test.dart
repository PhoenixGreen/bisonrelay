import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/elements_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_data_sheet_test.dart is the Data element's sheets (Ken, 2026-11-15:
// Table and Chart made one Data element, its data in sheets): a table and a
// chart viewing one sheet stay in step whichever is changed, in every
// scene; old canvases' tables and charts get sheets of their own on
// opening, a chart that read a table viewing that table's sheet.

const league = [
  ["Club", "W", "D", "Pts"],
  ["Arsenal", "14", "4", "46"],
  ["Liverpool", "13", "5", "44"],
  ["Chelsea", "12", "4", "40"],
];

TableElement table(String id, {List<List<String>> rows = league}) =>
    TableElement(ElementBase(id: id, name: "League", width: 400, height: 200),
        rows: rows);

Widget _app(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  // Ken, 2026-11-17: a league's position stays 1, 2, 3 while the clubs are
  // sorted by points (the old table Order's "Keep the numbering", for a
  // table showing a sheet).
  group("a numbered first column", () {
    const table = [
      ["Pos", "Club", "Pts"],
      ["1", "Arsenal", "10"],
      ["2", "Chelsea", "30"],
      ["3", "Spurs", "20"],
    ];
    var link = const SheetLink("s", CellRange(0, 0, 3, 2), sortBy: 2);

    test("keeps its place while the rows move; saved", () {
      var sheet = const DataSheet(id: "s", cells: table);
      var t = TableElement(const ElementBase(id: "t"),
          sheet: link.copyWith(numbering: true));
      var shown = viewFromSheet(t, sheet) as TableElement;
      expect(shown.rows.skip(1).map((r) => "${r[0]} ${r[1]}"),
          ["1 Chelsea", "2 Spurs", "3 Arsenal"]);
      var plain = viewFromSheet(t.copyWith(sheet: link), sheet) as TableElement;
      expect(plain.rows[1][0], "2", reason: "moving with its row");
      expect(
          SheetLink.fromJson(link.copyWith(numbering: true).toJson())!
              .numbering,
          isTrue);
      expect(link.toJson().containsKey("numbering"), isFalse);
    });

    test("a cell typed in it isn't written back over another row's place", () {
      var t = viewFromSheet(
          TableElement(const ElementBase(id: "t"),
              sheet: link.copyWith(numbering: true)),
          const DataSheet(id: "s", cells: table));
      var c = CanvasController(
          const CanvasDocument(sheets: [DataSheet(id: "s", cells: table)])
              .addElement(t),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      var now = c.document.elementById("t") as TableElement;
      expect(now.rows[1][1], "Chelsea");
      // Chelsea's points changed, in the table.
      var rows = [
        for (var r in now.rows) [...r]
      ];
      rows[1][2] = "31";
      c.replaceElement(now.copyWith(rows: rows));
      var sheet = c.document.sheets.single;
      expect(sheet.raw(2, 2), "31", reason: "Chelsea's row");
      expect([for (var r = 1; r <= 3; r++) sheet.raw(r, 0)], ["1", "2", "3"],
          reason: "the positions stay where they were in the sheet");
    });
  });

  group("sheets", () {
    test("ranges read and written as a spreadsheet does", () {
      expect(columnName(0), "A");
      expect(columnName(25), "Z");
      expect(columnName(26), "AA");
      expect(cellAt("B4"), (3, 1));
      expect(cellAt(r"$AA$10"), (9, 26));
      expect(CellRange.parse("c3:a1"), const CellRange(0, 0, 2, 2));
      expect(CellRange.parse("A1:H9")!.a1, "A1:H9");
      expect(CellRange.parse("nope"), isNull);
    });

    test("a block written grows the sheet, clears what it left, and keeps", () {
      var s = const DataSheet(id: "s", cells: [
        ["a", "b", "c"],
        ["1", "2", "3"],
      ]);
      var t = s.withBlock(
          0,
          0,
          [
            ["x"]
          ],
          clear: const CellRange(0, 0, 1, 2));
      expect(
          t.cells,
          [
            ["x"]
          ],
          reason: "the rest of the old range emptied, empty ends trimmed");
      var u = s.withCell(3, 4, "far");
      expect(u.rowCount, 4);
      expect(u.raw(3, 4), "far");
      expect(u.raw(2, 0), "");
      var back = DataSheet.fromJson(u.toJson())!;
      expect(back.cells, u.cells);
      expect(back.name, u.name);
    });
  });

  group("old canvases", () {
    test(
        "a table gets a sheet; a chart that read it views it; a chart of its "
        "own gets one, its gaps kept", () {
      var doc = CanvasDocument(elements: [
        table("t1"),
        ChartElement(const ElementBase(id: "c1"),
            fromTable: const TableLink(
                tableId: "t1", categoryColumn: 0, valueColumns: [3])),
        ChartElement(const ElementBase(id: "c2", name: "Price"),
            xAxisLabel: "Month",
            data: const ChartData(categories: [
              "Jan",
              "Feb",
              "Mar"
            ], series: [
              ChartSeries(
                  name: "USD",
                  color: Color(0xFF4C8DF6),
                  values: [14.2, double.nan, 17])
            ])),
      ]);
      var opened = CanvasDocument.fromJson(doc.toJson());
      expect(opened.sheets, hasLength(2));
      var t = opened.elementById("t1") as TableElement;
      var c1 = opened.elementById("c1") as ChartElement;
      var c2 = opened.elementById("c2") as ChartElement;
      expect(t.sheet!.range, const CellRange(0, 0, 3, 3));
      expect(t.rows, league, reason: "nothing it shows changed");
      expect(c1.sheet!.sheet, t.sheet!.sheet, reason: "one set of numbers");
      expect(c1.fromTable.tableId, "", reason: "the old copying link let go");
      expect(c1.data.categories, ["Arsenal", "Liverpool", "Chelsea"]);
      expect(c1.data.series.single.name, "Pts");
      expect(c1.data.series.single.values, [46, 44, 40]);
      var s2 = opened.sheets.firstWhere((s) => s.id == c2.sheet!.sheet);
      expect(s2.name, "Price");
      expect(s2.cells.first, ["Month", "USD"]);
      expect(c2.data.series.single.values[1].isNaN, isTrue,
          reason: "a gap stays a gap");
      expect(c2.data.series.single.values[0], 14.2);
      // Opened again: nothing more to do.
      var again = CanvasDocument.fromJson(opened.toJson());
      expect(again.sheets, hasLength(2));
      expect(identical(dataAdopted(again), again), isTrue);
    });
  });

  group("kept in step", () {
    late CanvasController c;
    setUp(() {
      c = CanvasController(
          CanvasDocument.fromJson(CanvasDocument(elements: [
            table("t1"),
            ChartElement(const ElementBase(id: "c1"),
                fromTable: const TableLink(
                    tableId: "t1", categoryColumn: 0, valueColumns: [3])),
          ]).toJson()),
          audioEngine: FakeEngine({}));
    });
    tearDown(() => c.dispose());
    TableElement t() => c.document.elementById("t1") as TableElement;
    ChartElement ch() => c.document.elementById("c1") as ChartElement;

    test("a cell typed in the table changes the chart, in one undo step", () {
      var rows = [
        for (var r in t().rows) [...r]
      ];
      rows[1][3] = "50";
      c.replaceElement(t().copyWith(rows: rows));
      expect(c.document.sheets.single.raw(1, 3), "50");
      expect(ch().data.series.single.values.first, 50,
          reason: "Ken: typing in the table didn't change the chart");
      c.undo();
      expect(c.document.sheets.single.raw(1, 3), "46");
      expect(ch().data.series.single.values.first, 46);
    });

    test("the chart's own numbers changed: into the sheet, and the table", () {
      var s = ch().data.series.single;
      c.replaceElement(ch().copyWith(
          data: ch().data.copyWith(series: [
        s.copyWith(values: [46, 44, 41])
      ])));
      expect(t().rows[3][3], "41");
    });

    test("a row added to the table grows its range, and the chart's", () {
      c.replaceElement(t().copyWith(rows: [
        ...t().rows,
        ["Spurs", "8", "5", "29"]
      ]));
      expect(t().sheet!.range, const CellRange(0, 0, 4, 3));
      expect(c.document.sheets.single.raw(4, 0), "Spurs");
      // The chart views its own range; widened to it, it shows the row.
      c.replaceElement(
          ch().copyWith(sheet: ch().sheet!.copyWith(range: t().sheet!.range)));
      expect(ch().data.categories.last, "Spurs");
      expect(ch().data.series.single.values.last, 29);
    });

    test("a series added to the chart takes the next column of the sheet", () {
      c.replaceElement(ch().copyWith(
          data: ch().data.copyWith(series: [
        ...ch().data.series,
        const ChartSeries(
            name: "GD", color: Color(0xFF2ED6A1), values: [28, 25, 17]),
      ])));
      expect(ch().sheet!.series, [3, 4]);
      expect(c.document.sheets.single.raw(0, 4), "GD");
      expect(c.document.sheets.single.raw(2, 4), "25");
    });

    test("the sheet changed: every view of it, in every scene, follows", () {
      c.duplicateScene(0);
      expect(c.document.allScenes, hasLength(2));
      var sheet = c.document.sheets.single;
      c.apply(c.document.copyWith(sheets: [sheet.withCell(2, 3, "45")]));
      // Here (the copy, its own ids, viewing the same sheet)...
      var here = c.document.elements;
      expect(here.whereType<ChartElement>().single.data.series.single.values[1],
          45);
      expect(here.whereType<TableElement>().single.rows[2][3], "45");
      var other = c.document.allScenes.firstWhere(
          (s) => !identical(s, c.document.allScenes[c.document.at]));
      var copies = other.elements.whereType<ChartElement>();
      expect(copies.single.data.series.single.values[1], 45,
          reason: "the other scene's copy too");
    });

    test("a table added with no sheet is given one", () {
      c.addElement(table("t2", rows: const [
        ["A", "B"],
        ["1", "2"]
      ]));
      var t2 = c.document.elementById("t2") as TableElement;
      expect(t2.sheet, isNotNull);
      expect(c.document.sheets, hasLength(2));
      expect(c.document.sheets.last.cells, [
        ["A", "B"],
        ["1", "2"]
      ]);
    });
  });

  group("in its settings", () {
    Future<CanvasController> panel(WidgetTester tester) async {
      // At Ken's larger text size: View and Sheet share a row.
      tester.platformDispatcher.textScaleFactorTestValue = 1.25;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.physicalSize = const Size(600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var c =
          CanvasController(const CanvasDocument(), audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(Row(children: [
        SizedBox(width: 200, child: CanvasElementsPanel(controller: c)),
        Expanded(
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) => SingleChildScrollView(
              child: SizedBox(
                width: 340,
                child: CanvasControlScope(
                  maxWidth: 300,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: c.selected == null
                          ? const []
                          : elementSettings(context, c, c.selected!)),
                ),
              ),
            ),
          ),
        ),
      ])));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets(
        "the Data chip puts down a table of a sheet; View makes it a chart of "
        "the same sheet, its columns of numbers drawn", (tester) async {
      var c = await panel(tester);
      expect(find.text("Chart"), findsNothing, reason: "one chip, not two");
      await tester.tap(find.text("Data"));
      await tester.pumpAndSettle();
      var t = c.document.elements.whereType<TableElement>().single;
      expect(t.sheet, isNotNull);
      expect(c.document.sheets.single.cells, t.rows);
      expect(find.byKey(const ValueKey("dataSheet")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("dataView-chart")));
      await tester.pumpAndSettle();
      var ch = c.document.elements.single as ChartElement;
      expect(ch.id, t.id, reason: "the same element, in its place");
      expect(ch.sheet!.sheet, t.sheet!.sheet);
      expect(ch.data.categories, ["First", "Second", "Third"]);
      expect([for (var s in ch.data.series) s.name], ["Value", "Change"]);
      // Its columns picked in its settings: Change taken off.
      if (find.byKey(const ValueKey("chartSheetLabels")).evaluate().isEmpty) {
        await tester.ensureVisible(find.text("Data source"));
        await tester.tap(find.text("Data source"));
        await tester.pumpAndSettle();
      }
      var change = find.byKey(const ValueKey("chartSheetSeries-2"));
      await tester.ensureVisible(change);
      await tester.tap(change);
      await tester.pumpAndSettle();
      ch = c.document.elements.single as ChartElement;
      expect([for (var s in ch.data.series) s.name], ["Value"]);
      // And back: a table again, the whole range.
      await tester.ensureVisible(find.byKey(const ValueKey("dataView-table")));
      await tester.tap(find.byKey(const ValueKey("dataView-table")));
      await tester.pumpAndSettle();
      var back = c.document.elements.single as TableElement;
      expect(back.rows, c.document.sheets.single.cells);
      c.undo();
      expect(c.document.elements.single, isA<ChartElement>());
    });
  });
}
