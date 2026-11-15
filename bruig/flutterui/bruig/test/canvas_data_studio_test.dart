import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/data_grid.dart';
import 'package:bruig/plugin_system/canvas/ui/data_studio.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_data_studio_test.dart is the Data Studio (Ken, 2026-11-15: Table
// and Chart made one Data element, built in a full-screen studio like
// Calc): its sheet typed into, pasted, cleared and sorted; rows and columns
// put in and taken out, the views of the sheet following -- a chart's
// columns with them; sheets added and named; tables and charts put down
// from a selection; the picked one's own settings beside it.

const league = [
  ["Club", "W", "D", "GD", "Pts"],
  ["Arsenal", "14", "4", "28", "46"],
  ["Liverpool", "13", "5", "25", "44"],
  ["Chelsea", "12", "4", "17", "40"],
];

CanvasDocument opened() => CanvasDocument.fromJson(CanvasDocument(elements: [
      TableElement(
          const ElementBase(id: "t1", name: "League", width: 500, height: 220),
          rows: league),
      ChartElement(
          const ElementBase(id: "c1", name: "Points", width: 500, height: 300),
          fromTable: const TableLink(
              tableId: "t1", categoryColumn: 0, valueColumns: [3, 4])),
    ]).toJson());

void main() {
  group("rows and columns", () {
    test("a column taken out of a chart's series lets that series go", () {
      var doc = opened();
      var id = doc.sheets.single.id;
      var next = columnsDeleted(doc, id, 3, 1); // GD
      var ch = next.elementById("c1") as ChartElement;
      expect(ch.sheet!.range, const CellRange(0, 0, 3, 3));
      expect(ch.sheet!.series, [3], reason: "Pts, where it is now");
      expect(next.sheets.single.cells.first, ["Club", "W", "D", "Pts"]);
    });

    test("a column put in before a series moves it; the range grows", () {
      var doc = opened();
      var next = columnsInserted(doc, doc.sheets.single.id, 1, 2);
      var ch = next.elementById("c1") as ChartElement;
      expect(ch.sheet!.range, const CellRange(0, 0, 3, 6));
      expect(ch.sheet!.labels, 0);
      expect(ch.sheet!.series, [5, 6]);
      var t = next.elementById("t1") as TableElement;
      expect(t.sheet!.range.cols, 7);
    });

    test("rows put in inside a range grow it, before it move it", () {
      var doc = opened();
      var id = doc.sheets.single.id;
      var inside = rowsInserted(doc, id, 2, 1);
      expect((inside.elementById("t1") as TableElement).sheet!.range,
          const CellRange(0, 0, 4, 4));
      var before = rowsInserted(doc, id, 0, 2);
      expect((before.elementById("t1") as TableElement).sheet!.range,
          const CellRange(2, 0, 5, 4));
      var gone = rowsDeleted(doc, id, 1, 2);
      expect((gone.elementById("t1") as TableElement).sheet!.range,
          const CellRange(0, 0, 1, 4));
    });

    test("rows sorted by a column: numbers by value, blanks last, stable", () {
      var doc = opened();
      var id = doc.sheets.single.id;
      var next = rowsSorted(doc, id, const CellRange(1, 0, 3, 4), 3); // GD
      expect([for (var r in next.sheets.single.cells.skip(1)) r[0]],
          ["Chelsea", "Liverpool", "Arsenal"]);
    });
  });

  group("the studio", () {
    late CanvasController c;

    Future<void> studio(WidgetTester tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.25;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      c = CanvasController(opened(), audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      c.openDataStudio(c.document.sheets.single.id, view: "c1");
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

    Offset cellAt(WidgetTester tester, int r, int col) =>
        tester.getTopLeft(find.byType(DataGrid)) +
        Offset(dataHeaderWidth + col * dataColumnWidth + dataColumnWidth / 2,
            dataRowHeight + r * dataRowHeight + dataRowHeight / 2);
    DataSheet sheet() => c.document.sheets.single;
    ChartElement chart() => c.document.elementById("c1") as ChartElement;
    TableElement table() => c.document.elementById("t1") as TableElement;

    testWidgets(
        "a cell clicked and typed into: the sheet, the table and the chart",
        (tester) async {
      await studio(tester);
      await tester.tapAt(cellAt(tester, 1, 4));
      await tester.pump();
      expect(
          tester
              .widget<TextField>(
                  find.byKey(const ValueKey("dataStudioNameBox")))
              .controller!
              .text,
          "E2");
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.pump();
      expect(find.byKey(const ValueKey("dataGridEditor")), findsOneWidget,
          reason: "typing starts editing, as in Calc");
      await tester.enterText(
          find.byKey(const ValueKey("dataGridEditor")), "50");
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(sheet().raw(1, 4), "50");
      expect(table().rows[1][4], "50");
      expect(chart().data.series[1].values.first, 50);
      // Moved down a row by Enter; shift-arrows extend; the sum of two.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(
          tester.widget<Text>(find.byKey(const ValueKey("dataStudioSum"))).data,
          "84");
      // The formula bar writes the anchor.
      await tester.enterText(
          find.byKey(const ValueKey("dataStudioFormula")), "45");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(sheet().raw(2, 4), "45");
      // Delete clears the selection; Undo brings it back.
      await tester.tapAt(cellAt(tester, 3, 4));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(sheet().raw(3, 4), "");
      c.undo();
      await tester.pumpAndSettle();
      expect(sheet().raw(3, 4), "40");
    });

    testWidgets("pasted from a spreadsheet: tab-separated rows, put in place",
        (tester) async {
      await studio(tester);
      await tester.tapAt(cellAt(tester, 4, 0));
      await tester.pump();
      tester
          .state<DataGridState>(find.byType(DataGrid))
          .pasteText("Spurs\t8\t5\t4\t29\nBrighton\t7\t7\t3\t28\n");
      await tester.pumpAndSettle();
      expect(sheet().cells.sublist(4), [
        ["Spurs", "8", "5", "4", "29"],
        ["Brighton", "7", "7", "3", "28"],
      ]);
    });

    testWidgets(
        "＋ Chart puts a chart of the selection on the canvas; − Column on a "
        "series lets it go", (tester) async {
      await studio(tester);
      var before = c.document.elements.length;
      await tester.tapAt(cellAt(tester, 0, 0));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("dataStudioAddChart")));
      await tester.pumpAndSettle();
      expect(c.document.elements.length, before + 1);
      var made = c.document.elements.last as ChartElement;
      expect(made.sheet!.range, const CellRange(0, 0, 3, 1));
      expect(made.data.categories, ["Arsenal", "Liverpool", "Chelsea"]);
      expect(made.data.series.single.name, "W");
      expect(find.byKey(ValueKey("dataStudioView-${made.id}")), findsOneWidget);
      // GD (column D) taken out: the Points chart lets that series go.
      await tester.tapAt(cellAt(tester, 1, 3));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("dataStudioColumnOut")));
      await tester.pumpAndSettle();
      expect([for (var s in chart().data.series) s.name], ["Pts"]);
      expect(table().rows.first, ["Club", "W", "D", "Pts"]);
    });

    testWidgets("sheets added and named; the picked view's own settings",
        (tester) async {
      await studio(tester);
      expect(find.byKey(const ValueKey("dataView")), findsOneWidget,
          reason: "the chart's settings, as on the canvas");
      await tester.tap(find.byKey(const ValueKey("dataStudioAddSheet")));
      await tester.pumpAndSettle();
      expect(c.document.sheets, hasLength(2));
      var id = c.document.sheets.last.id;
      await tester.tap(find.byKey(ValueKey("dataStudioTab-$id")));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(ValueKey("dataStudioTab-$id")));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey("dataStudioRename")), "Fixtures");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(c.document.sheets.last.name, "Fixtures");
      // Empty and shown nowhere: it can be taken out again.
      await tester.tap(find.byKey(const ValueKey("dataStudioRemoveSheet")));
      await tester.pumpAndSettle();
      expect(c.document.sheets, hasLength(1));
    });

    testWidgets("the quick settings' Data Studio button opens it",
        (tester) async {
      tester.view.physicalSize = const Size(600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var ctl = CanvasController(opened(), audioEngine: FakeEngine({}));
      addTearDown(ctl.dispose);
      ctl.selectOnly("t1");
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
          body: SingleChildScrollView(
            child: SizedBox(
              width: 340,
              child: Builder(
                builder: (context) => CanvasControlScope(
                  maxWidth: 300,
                  child: Column(
                      children: elementSettings(context, ctl, ctl.selected!)),
                ),
              ),
            ),
          ),
        )),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("dataOpenStudio")));
      await tester.pumpAndSettle();
      expect(ctl.dataStudio.value, ctl.document.sheets.single.id);
      expect(ctl.dataStudioView, "t1");
    });
  });
}
