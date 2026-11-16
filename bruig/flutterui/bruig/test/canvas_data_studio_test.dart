import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/own_motion.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/data_grid.dart';
import 'package:bruig/plugin_system/canvas/ui/data_studio.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
    Offset columnLetter(WidgetTester tester, int col) =>
        tester.getTopLeft(find.byType(DataGrid)) +
        Offset(dataHeaderWidth + col * dataColumnWidth + dataColumnWidth / 2,
            dataRowHeight / 2);
    Offset rowNumber(WidgetTester tester, int r) =>
        tester.getTopLeft(find.byType(DataGrid)) +
        Offset(dataHeaderWidth / 2,
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
          tester
              .widget<Text>(find.byKey(const ValueKey("dataStudioSum")))
              .textSpan!
              .toPlainText(),
          "Sum 84");
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

    testWidgets(
        "a formula typed shows its answer; a column given Money; the fill "
        "handle carries a series on", (tester) async {
      await studio(tester);
      // A total under Pts.
      await tester.tapAt(cellAt(tester, 4, 4));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.pump();
      await tester.enterText(
          find.byKey(const ValueKey("dataGridEditor")), "=SUM(E2:E4)");
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(sheet().raw(4, 4), "=SUM(E2:E4)");
      expect(sheetShown(sheet(), 4, 4), "130");
      // Column B (W) as money, picked by its letter.
      await tester.tapAt(tester.getTopLeft(find.byType(DataGrid)) +
          const Offset(
              dataHeaderWidth + dataColumnWidth * 1.5, dataRowHeight / 2));
      await tester.pump();
      await tester
          .ensureVisible(find.byKey(const ValueKey("dataStudioFormat")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("dataStudioFormat")));
      await tester.pumpAndSettle();
      await tester.tap(find.text(r"Money $").last);
      await tester.pumpAndSettle();
      expect(sheet().columnFormats[1]?.kind, CellFormatKind.money);
      expect(table().rows[1][1], r"$14.00");
      expect(sheetValue(sheet(), 1, 1), 14,
          reason: "still a number underneath");
      // Fewer decimals.
      await tester.tap(find.byKey(const ValueKey("dataStudioFewer")));
      await tester.pumpAndSettle();
      expect(table().rows[1][1], r"$14.0");
      // A series down column G: 1, 2, then the handle dragged two rows on.
      c.setSheetCells(c.document.sheets.single.id, 0, 6, [
        ["1"],
        ["2"]
      ]);
      await tester.pumpAndSettle();
      await tester.tapAt(cellAt(tester, 0, 6));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      var corner = tester.getTopLeft(find.byType(DataGrid)) +
          const Offset(dataHeaderWidth + 7 * dataColumnWidth,
              dataRowHeight + 2 * dataRowHeight);
      var g = await tester.startGesture(corner, kind: PointerDeviceKind.mouse);
      await g.moveTo(corner + const Offset(0, dataRowHeight * 1.5));
      await tester.pump();
      await g.moveTo(corner + const Offset(-8, dataRowHeight * 1.6));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect([for (var r = 0; r < 4; r++) sheet().raw(r, 6)],
          ["1", "2", "3", "4"]);
    });

    // Ken, 2026-11-16: "RangeError ... Not in inclusive range 0..3: -3" from
    // the grid's cells painter. On a Mac the grid bounces past its top and
    // left edges, and the offset goes negative; the first row drawn was then
    // row -3.
    testWidgets("dragged past its top-left corner on a Mac: bounces, no error",
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await studio(tester);
        // As a trackpad flick leaves it: past both edges, bouncing back.
        for (var view in tester.widgetList<SingleChildScrollView>(
            find.descendant(
                of: find.byType(DataGrid),
                matching: find.byType(SingleChildScrollView)))) {
          view.controller!.position.jumpTo(-61);
        }
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull, reason: "past the edge");
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: "bouncing back");
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
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
        "＋ Chart puts a chart of the selection on the canvas; a series' "
        "column deleted lets it go", (tester) async {
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
      // GD (column D) taken out, from its letter's right-click menu: the
      // Points chart lets that series go.
      await tester.tapAt(columnLetter(tester, 3),
          buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("dataGridMenu-delete")));
      await tester.pumpAndSettle();
      expect([for (var s in chart().data.series) s.name], ["Pts"]);
      expect(table().rows.first, ["Club", "W", "D", "Pts"]);
    });

    // Ken, 2026-11-16: the bar's − Row, + Row, − Column and + Column moved
    // to the ends of the row numbers and column letters, as − and + with a
    // box for how many; 40 rows to start. Rows and columns put in or taken
    // out where the selection is: the headers' right-click menu.
    testWidgets("the grid's ends: 40 rows to start, more or fewer by a number",
        (tester) async {
      await studio(tester);
      expect(find.byKey(const ValueKey("dataStudioRowIn")), findsNothing);
      expect(sheet().shownRows, 40);
      expect(sheet().shownColumns, 26);
      // Scrolled to the grid's end, where the ends are (they follow the
      // grid's scrolling, from outside its scroll view).
      Future<void> toEnd() async {
        for (var view in tester.widgetList<SingleChildScrollView>(
            find.descendant(
                of: find.byType(DataGrid),
                matching: find.byType(SingleChildScrollView)))) {
          var p = view.controller!.position;
          p.jumpTo(p.maxScrollExtent);
        }
        await tester.pumpAndSettle();
      }

      Future<void> press(String key) async {
        await toEnd();
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
      }

      await toEnd();

      await tester.enterText(
          find.byKey(const ValueKey("dataGridRowStep")), "5");
      await press("dataGridRowsMore");
      expect(sheet().gridRows, 45);
      await press("dataGridColumnsMore");
      expect(sheet().gridColumns, 27);
      await press("dataGridColumnsLess");
      expect(sheet().gridColumns, 26);
      // Fewer than are typed in: what was past the edge goes, in one undo.
      await tester.enterText(
          find.byKey(const ValueKey("dataGridRowStep")), "42");
      await press("dataGridRowsLess");
      expect(sheet().gridRows, 3);
      expect(sheet().rowCount, 3, reason: "Chelsea's row went");
      expect(table().rows, hasLength(3));
      c.undo();
      await tester.pumpAndSettle();
      expect(sheet().gridRows, 45);
      expect(sheet().rowCount, 4);
      // Saved with the canvas, and only where it isn't the usual size.
      expect(DataSheet.fromJson(sheet().toJson())!.gridRows, 45);
      expect(const DataSheet(id: "x").toJson().containsKey("gridRows"), false);
      expect(tester.takeException(), isNull);
    });

    testWidgets("a row number's menu puts rows in above and below; deletes",
        (tester) async {
      await studio(tester);
      Future<void> menu(int r, String choice) async {
        await tester.tapAt(rowNumber(tester, r),
            buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey("dataGridMenu-$choice")));
        await tester.pumpAndSettle();
      }

      await menu(1, "before");
      expect(sheet().raw(2, 0), "Arsenal");
      expect(sheet().raw(1, 0), "");
      await menu(2, "after");
      expect(sheet().raw(3, 0), "");
      expect(sheet().raw(4, 0), "Liverpool");
      await menu(1, "delete");
      expect(sheet().raw(1, 0), "Arsenal");
      // A column letter's: in to the left.
      await tester.tapAt(columnLetter(tester, 0),
          buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("dataGridMenu-before")));
      await tester.pumpAndSettle();
      expect(sheet().raw(0, 1), "Club");
      expect(tester.takeException(), isNull);
    });

    // Ken, 2026-11-16: the Sheet tab's side panel is about the sheet; what a
    // table or chart looks like is the Table and Charts tabs'.
    testWidgets(
        "the side is the sheet's: its data, itself, the selection, what is "
        "made from it", (tester) async {
      await studio(tester);
      double top(String key) => tester.getTopLeft(find.byKey(ValueKey(key))).dy;
      // In that order, one scroll, no view's own settings.
      expect(
          top("dataStudioConnectData"), lessThan(top("dataStudioSheetName")));
      expect(top("dataStudioSheetName"), lessThan(top("dataStudioSum")));
      expect(top("dataStudioFormat"), lessThan(top("dataStudioAddTable")));
      expect(top("dataStudioAddTable"), lessThan(top("dataStudioView-c1")));
      expect(find.byKey(const ValueKey("dataView")), findsNothing);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey("dataStudioSide")),
              matching: find.byKey(const ValueKey("dataStudioRemoveView"))),
          findsOneWidget);
      // Sort, Undo and Redo on the row below the bar, with the formula; the
      // bar itself the tabs and Done.
      double middle(String key) =>
          tester.getCenter(find.byKey(ValueKey(key))).dy;
      expect(
          middle("dataStudioSortUp"), closeTo(middle("dataStudioFormula"), 4),
          reason: "same row");
      expect(top("dataStudioUndo"), greaterThan(top("dataStudioDone")));
      expect(middle("dataStudioConnectData"),
          greaterThan(middle("dataStudioFormula")),
          reason: "Connect data is in the side panel now");

      Future<void> tap(String key) async {
        var at = find.byKey(ValueKey(key));
        await tester.ensureVisible(at);
        await tester.pumpAndSettle();
        await tester.tap(at);
        await tester.pumpAndSettle();
      }

      // Renamed, and sized, from This sheet.
      await tester.enterText(
          find.byKey(const ValueKey("dataStudioSheetName")), "League");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(sheet().name, "League");
      await tester.enterText(
          find.byKey(const ValueKey("dataStudioSheetRows")), "60");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(sheet().gridRows, 60);
      // The table picked: pointed at the selection instead, then off to the
      // Table tab to be designed.
      await tap("dataStudioView-t1");
      await tester.tapAt(cellAt(tester, 0, 0));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      for (var i = 0; i < 2; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      await tap("dataStudioUseSelection");
      expect(table().sheet!.range, const CellRange(0, 0, 2, 1));
      expect(table().rows, [
        ["Club", "W"],
        ["Arsenal", "14"],
        ["Liverpool", "13"]
      ]);
      await tap("dataStudioDesign");
      expect(
          find.byKey(const ValueKey("dataStudioTableDesign")), findsOneWidget);
      await tap("dataStudioTab-sheet");
      // Taken off the canvas, and undone.
      await tap("dataStudioView-t1");
      await tap("dataStudioRemoveView");
      expect(c.document.elementById("t1"), isNull);
      expect(find.byKey(const ValueKey("dataStudioView-t1")), findsNothing);
      c.undo();
      await tester.pumpAndSettle();
      expect(c.document.elementById("t1"), isNotNull);
      expect(tester.takeException(), isNull);
    });

    for (var scale in [0.65, 1.5]) {
      testWidgets("nothing overflows at text size $scale, 1280 wide",
          (tester) async {
        await studio(tester);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        tester.view.physicalSize = const Size(1280, 800);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey("dataStudioView-t1")));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    // Ken, 2026-11-17: sheets left behind by deleted tables piled up, and a
    // sheet something showed couldn't be removed at all.
    testWidgets(
        "a sheet removed with what shows it; sheets nothing shows tidied away",
        (tester) async {
      await studio(tester);
      Future<void> tap(String key) async {
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
      }

      // Two more sheets; nothing shows them, so they're offered to tidy.
      await tap("dataStudioAddSheet");
      await tap("dataStudioAddSheet");
      expect(c.document.sheets, hasLength(3));
      expect(find.text("Remove unused (2)"), findsOneWidget);
      await tap("dataStudioTidySheets");
      expect(find.byKey(const ValueKey("dataStudioAsking")), findsOneWidget);
      await tap("dataStudioNotSure");
      expect(c.document.sheets, hasLength(3), reason: "cancelled");
      await tap("dataStudioTidySheets");
      await tap("dataStudioSure");
      expect(c.document.sheets, hasLength(1));
      expect(find.byKey(const ValueKey("dataStudioTidySheets")), findsNothing);
      // The league sheet, which the table and chart show: with another
      // sheet to go to, it can go, and they with it -- once asked.
      await tap("dataStudioAddSheet");
      // A tab waits to see whether a tap is a double tap (which renames).
      await tester.tap(
          find.byKey(ValueKey("dataStudioTab-${c.document.sheets.first.id}")));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tap("dataStudioRemoveSheet");
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey("dataStudioAsking")))
              .data,
          contains("2 tables or charts"));
      await tap("dataStudioSure");
      expect(c.document.sheets, hasLength(1));
      expect(c.document.elementById("t1"), isNull);
      expect(c.document.elementById("c1"), isNull);
      c.undo();
      await tester.pumpAndSettle();
      expect(c.document.sheets, hasLength(2));
      expect(c.document.elementById("c1"), isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets("sheets added, named and taken out again", (tester) async {
      await studio(tester);
      expect(find.byKey(const ValueKey("dataStudioImport")), findsOneWidget);
      expect(find.byKey(const ValueKey("dataStudioExport")), findsOneWidget);
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

  // Found making the Charts canvas (Ken, 2026-11-17: "try the whole
  // system"): a new Data element's first steps.
  group("a new Data element's first steps", () {
    const form = [
      ["Pos", "Club", "Pts", "Form"],
      ["1", "Arsenal", "46", "W W D W W"],
      ["2", "Liverpool", "44", "W D W W L"],
      ["3", "Man United", "31", "L W L W D"],
    ];

    test("the rows are named by the club, not its form or its code", () {
      var s = const DataSheet(id: "s", cells: form);
      var g = const CellRange(0, 0, 3, 3);
      expect(namingColumn(s, g), 1);
      expect(namingScore(s, g, 3), lessThan(namingScore(s, g, 1)));
      expect(namingScore(s, g, 2), 0, reason: "numbers name nothing");
      var codes = const DataSheet(id: "c", cells: [
        ["Code", "Club"],
        ["ARS", "Arsenal"],
        ["LIV", "Liverpool"],
      ]);
      expect(namingColumn(codes, const CellRange(0, 0, 2, 1)), 1);
    });

    test("a paste that grows the sheet grows the views that showed it all", () {
      var c =
          CanvasController(const CanvasDocument(), audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      c.addElement(newElement(ElementKind.table, c.document));
      var t = c.document.elements.last as TableElement;
      var id = t.sheet!.sheet;
      c.pasteSheetCells(id, 0, 0, form);
      var grown = c.document.elementById(t.id) as TableElement;
      expect(grown.sheet!.range, const CellRange(0, 0, 3, 3));
      expect(grown.rows.first, form.first);
      c.undo();
      expect((c.document.elementById(t.id) as TableElement).sheet!.range,
          t.sheet!.range,
          reason: "one step");
    });

    testWidgets(
        "the first chart is chosen from the gallery, and takes its own place",
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var c =
          CanvasController(const CanvasDocument(), audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      c.addElement(newElement(ElementKind.table, c.document));
      var t = c.document.elements.last as TableElement;
      c.pasteSheetCells(t.sheet!.sheet, 0, 0, form);
      c.openDataStudio(t.sheet!.sheet, view: t.id);
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
      await tester.tap(find.text("Charts").first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("dataStudioChartMake")));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("chartsGallery")), findsOneWidget,
          reason: "straight to the designs");
      List<ChartElement> charts() =>
          c.document.elements.whereType<ChartElement>().toList();
      expect(charts().single.sheet!.labels, 1, reason: "Club, not Form");
      await tester.tap(find.byKey(const ValueKey("chartsKind-horizontalBar")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("chartsPreset-0")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("chartsGalleryStart")));
      await tester.pumpAndSettle();
      expect(charts(), hasLength(1), reason: "in the starter's place");
      expect(charts().single.type, ChartType.horizontalBar);
      // Its arrival laid on the timeline: a preset with no keyframes to
      // time it would draw nothing different.
      expect(charts().single.animation.on, isTrue);
      expect(ownSpan(charts().single, MotionKind.arrive, 24), isNotNull);
      // Later, + New chart adds one beside it.
      await tester.tap(find.byKey(const ValueKey("chartsNew")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("chartsKind-bar")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("chartsPreset-0")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("chartsGalleryStart")));
      await tester.pumpAndSettle();
      expect(charts(), hasLength(2));
      expect(tester.takeException(), isNull);
    });
  });
}
