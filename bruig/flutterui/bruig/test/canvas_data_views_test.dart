import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/export/epub_layers.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/sheet_files.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/data_studio.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_data_views_test.dart is each Data element's own view of its sheet
// (Ken's plan: "the table shows all 20 clubs, the chart the top 5") --
// sorted, filtered and cut to its top without changing the sheet, typing in
// it still reaching the right row -- and the sheet's colour rules (data
// bars, scales, highlights) as the tables showing it draw them.

const league = [
  ["Club", "W", "D", "Pts"],
  ["Chelsea", "12", "4", "40"],
  ["Arsenal", "14", "4", "46"],
  ["Spurs", "8", "5", "29"],
  ["Liverpool", "13", "5", "44"],
];

CanvasDocument docOf(
    {SheetLink? table, SheetLink? chart, List<SheetRule> rules = const []}) {
  var s = DataSheet(id: "s", name: "League", cells: league, rules: rules);
  return dataSynced(
      const CanvasDocument(),
      CanvasDocument(sheets: [
        s
      ], elements: [
        TableElement(const ElementBase(id: "t"),
            sheet: table ?? SheetLink("s", s.used)),
        ChartElement(const ElementBase(id: "c"),
            sheet: chart ?? SheetLink("s", s.used, series: [3])),
      ]));
}

void main() {
  group("a view's own rows", () {
    test("sorted, cut to its top, filtered: the sheet left as it is", () {
      var doc = docOf(
          table: const SheetLink("s", CellRange(0, 0, 4, 3), sortBy: 3, top: 3),
          chart: const SheetLink("s", CellRange(0, 0, 4, 3),
              series: [3], whereColumn: 1, where: ">12"));
      var t = doc.elementById("t") as TableElement;
      expect([for (var r in t.rows) r[0]],
          ["Club", "Arsenal", "Liverpool", "Chelsea"]);
      var ch = doc.elementById("c") as ChartElement;
      expect(ch.data.categories, ["Arsenal", "Liverpool"]);
      expect(doc.sheets.single.cells, league, reason: "the sheet unchanged");
      var smallest = viewRows(
          doc.sheets.single,
          const SheetLink("s", CellRange(0, 0, 4, 3),
              sortBy: 3, descending: false, top: 2));
      expect(smallest, [3, 1], reason: "Spurs, Chelsea");
    });

    test("typed into in its own order: into the sheet row it shows", () {
      var c = CanvasController(
          docOf(
              table: const SheetLink("s", CellRange(0, 0, 4, 3),
                  sortBy: 3, top: 3)),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      var t = c.document.elementById("t") as TableElement;
      var rows = [
        for (var r in t.rows) [...r]
      ];
      rows[1][3] = "47"; // Arsenal, shown first
      c.replaceElement(t.copyWith(rows: rows));
      expect(c.document.sheets.single.raw(2, 3), "47",
          reason: "Arsenal's row in the sheet, not the sheet's first");
      expect(c.document.sheets.single.raw(1, 3), "40");
    });

    test("kept in the file", () {
      const link = SheetLink("s", CellRange(0, 0, 4, 3),
          sortBy: 3, descending: false, top: 3, whereColumn: 1, where: ">8");
      expect(SheetLink.fromJson(link.toJson()), link);
    });
  });

  group("colour rules", () {
    test("bars, scales and highlights, worked out from the range", () {
      var s = const DataSheet(id: "s", cells: league, rules: [
        SheetRule(CellRange(1, 3, 4, 3), SheetRuleKind.bars),
        SheetRule(CellRange(1, 1, 4, 1), SheetRuleKind.scale),
        SheetRule(CellRange(1, 2, 4, 2), SheetRuleKind.above),
        SheetRule(CellRange(1, 0, 4, 0), SheetRuleKind.equal, value: "Arsenal"),
      ]);
      expect(sheetLook(s, 2, 3)!.bar, 1, reason: "the largest, a full bar");
      expect(sheetLook(s, 3, 3)!.bar, closeTo(29 / 46, 1e-9));
      expect(sheetLook(s, 3, 1)!.fill,
          const SheetRule(CellRange(0, 0, 0, 0), SheetRuleKind.scale).low,
          reason: "the smallest W at the low end");
      expect(sheetLook(s, 3, 2)?.fill, isNotNull, reason: "5 is above 4.5");
      expect(sheetLook(s, 1, 2), isNull);
      expect(sheetLook(s, 2, 0)?.fill, isNotNull);
      expect(sheetLook(s, 0, 3), isNull, reason: "the heading is outside");
      var top = DataSheet(id: "s", cells: league, rules: const [
        SheetRule(CellRange(1, 3, 4, 3), SheetRuleKind.top, value: "2"),
      ]);
      expect([for (var r = 1; r <= 4; r++) sheetLook(top, r, 3) != null],
          [false, true, false, true]);
    });

    test("a table shows them, cell by cell; opened again, it still does", () {
      var doc = docOf(rules: const [
        SheetRule(CellRange(1, 3, 4, 3), SheetRuleKind.bars),
      ]);
      var t = doc.elementById("t") as TableElement;
      expect(t.sheetLookAt(2, 3)?.bar, 1);
      expect(t.sheetLookAt(0, 3), isNull);
      var opened = CanvasDocument.fromJson(doc.toJson());
      expect(
          (opened.elementById("t") as TableElement).sheetLookAt(2, 3)?.bar, 1,
          reason: "made again from the sheet's rules on opening");
      expect(opened.sheets.single.rules.single.kind, SheetRuleKind.bars);
    });

    test("they move with rows put in", () {
      var doc = docOf(rules: const [
        SheetRule(CellRange(1, 3, 4, 3), SheetRuleKind.bars),
      ]);
      var next = rowsInserted(doc, "s", 0, 2);
      expect(
          next.sheets.single.rules.single.range, const CellRange(3, 3, 6, 3));
    });
  });

  group("in the settings and the studio", () {
    Widget app(Widget child) => MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
                create: (_) => ThemeNotifier(doLoad: false)),
            ChangeNotifierProvider<SnackBarModel>(
                create: (_) => SnackBarModel()),
            ChangeNotifierProvider<CanvasPreferences>(
                create: (_) => CanvasPreferences()),
          ],
          child: MaterialApp(home: Scaffold(body: child)),
        );

    testWidgets("Rows shown: sorted by Pts, the top 3", (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.25;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.physicalSize = const Size(600, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var c = CanvasController(docOf(), audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      c.selectOnly("t");
      await tester.pumpWidget(app(ListenableBuilder(
        listenable: c,
        builder: (context, _) => SingleChildScrollView(
          child: SizedBox(
            width: 340,
            child: CanvasControlScope(
              maxWidth: 300,
              child: Column(children: elementSettings(context, c, c.selected!)),
            ),
          ),
        ),
      )));
      await tester.pumpAndSettle();
      Future<void> pick(String key, String option) async {
        await tester.ensureVisible(find.byKey(ValueKey(key)));
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        await tester.tap(find.text(option).last);
        await tester.pumpAndSettle();
      }

      await pick("dataRowsSort", "Pts (D)");
      await pick("dataRowsTop", "The top 3");
      var t = c.document.elementById("t") as TableElement;
      expect([for (var r in t.rows) r[0]],
          ["Club", "Arsenal", "Liverpool", "Chelsea"]);
      expect(c.document.sheets.single.cells, league);
      expect(tester.takeException(), isNull);
    });

    testWidgets("the studio's colour rules: data bars on the selection",
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var c = CanvasController(docOf(), audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      c.openDataStudio("s", view: "t");
      await tester.pumpWidget(app(
          DataStudio(controller: c, sheetId: "s", onDone: c.closeDataStudio)));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey("dataStudioNameBox")), "D2:D5");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("dataStudioRules")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Data bars").last);
      await tester.pumpAndSettle();
      expect(c.document.sheets.single.rules.single.range,
          const CellRange(1, 3, 4, 3));
      expect((c.document.elementById("t") as TableElement).sheetLookAt(2, 3),
          isNotNull);
      await tester.tap(find.byKey(const ValueKey("dataStudioRules")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Clear colour rules here").last);
      await tester.pumpAndSettle();
      expect(c.document.sheets.single.rules, isEmpty);
    });
  });

  group("files and books", () {
    test("sheets read from a file: named apart, one change to undo", () {
      var c = CanvasController(docOf(), audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      var ids = c.addReadSheets(const [
        ReadSheet("League", [
          ["a"]
        ]),
        ReadSheet("Fixtures", [
          ["b"]
        ]),
      ]);
      expect(ids, hasLength(2));
      expect(c.document.sheets.map((s) => s.name),
          ["League", "League 2", "Fixtures"]);
      c.undo();
      expect(c.document.sheets, hasLength(1));
    });

    test("in a book: a sorted, cut, colour-ruled table is drawn as it shows",
        () async {
      var doc = CanvasDocument.fromJson(docOf(
          table: const SheetLink("s", CellRange(0, 0, 4, 3), sortBy: 3, top: 3),
          rules: const [
            SheetRule(CellRange(1, 3, 4, 3), SheetRuleKind.bars),
          ]).toJson());
      var t = doc.elementById("t") as TableElement;
      expect(t.rows.length, 4);
      expect(t.sheetLookAt(1, 3)?.bar, 1, reason: "Arsenal first, a full bar");
      // A page that doesn't move is one picture of it, drawn from this
      // element as it is here; built, it doesn't fail on it.
      var built =
          await buildEpubStage(doc, 0, pixels: 1, width: 1280, height: 720);
      if (built != null) {
        expect(built.stage.layers.any((l) => l.id == "t"), isTrue);
      }
    });
  });
}
