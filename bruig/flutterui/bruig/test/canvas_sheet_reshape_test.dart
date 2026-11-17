import 'dart:convert';

import 'support/canvas_app.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/sheet_reshape.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/data/data_studio.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/canvas_audio_fake.dart';

// canvas_sheet_reshape_test.dart is a sheet made from another (Ken,
// 2026-11-17, the improvements report's second item): long, wide, grouped
// and joined; made again when its source changes, its charts with it.

List<List<String>> cellsOf(String tsv) =>
    [for (var l in tsv.trim().split("\n")) l.split("\t")];

const wide = """Season\tArsenal\tChelsea
2024\t74\t69
2025\t79\t66""";

void main() {
  // The sidebars' sections open, as these tests are of what each control
  // does; where they are folded is the sidebar's own test.
  setUp(() => CanvasSection.openAll = true);
  tearDown(() => CanvasSection.openAll = false);
  var source = DataSheet(id: "w", name: "Points", cells: cellsOf(wide));

  test("wide to long, and long back to wide", () {
    var long =
        reshaped(const SheetMade("w", ReshapeKind.long, keep: [0]), source);
    expect(long, [
      ["Season", "Series", "Value"],
      ["2024", "Arsenal", "74"],
      ["2024", "Chelsea", "69"],
      ["2025", "Arsenal", "79"],
      ["2025", "Chelsea", "66"],
    ]);
    var back = reshaped(
        const SheetMade("l", ReshapeKind.wide, rows: 0, columns: 1, value: 2),
        DataSheet(id: "l", cells: long));
    expect(back, source.cells);
  });

  test("wide from several value columns: a column a word for each", () {
    var long = DataSheet(id: "l", cells: [
      ["Season", "Club", "Pts", "GD"],
      ["2024", "Arsenal", "74", "28"],
      ["2025", "Arsenal", "79", "35"],
    ]);
    var m = const SheetMade("l", ReshapeKind.wide,
        rows: 0, columns: 1, value: 2, values: [2, 3]);
    expect(reshaped(m, long), [
      ["Season", "Arsenal · Pts", "Arsenal · GD"],
      ["2024", "74", "28"],
      ["2025", "79", "35"],
    ]);
    expect(SheetMade.fromJson(m.toJson()), m);
  });

  test("grouped: added up, averaged, counted", () {
    var s = DataSheet(
        id: "g",
        cells: cellsOf("Club\tGroup\tPts\nA\tTop\t9\nB\tTop\t7\nC\tRest\t4"));
    expect(reshaped(const SheetMade("g", ReshapeKind.group, by: 1), s), [
      ["Group", "Pts"],
      ["Top", "16"],
      ["Rest", "4"],
    ]);
    expect(
        reshaped(const SheetMade("g", ReshapeKind.group, by: 1, how: "average"),
            s)[1],
        ["Top", "8"]);
    expect(
        reshaped(
            const SheetMade("g", ReshapeKind.group, by: 1, how: "count"), s),
        [
          ["Group", "Count"],
          ["Top", "2"],
          ["Rest", "1"],
        ]);
  });

  test("joined on a column, case and spaces aside", () {
    var crests = DataSheet(
        id: "c",
        cells: cellsOf("Club\tCity\narsenal \tLondon\nChelsea\tLondon"));
    var clubs =
        DataSheet(id: "p", cells: cellsOf("Club\tPts\nArsenal\t79\nSpurs\t52"));
    expect(
        reshaped(
            const SheetMade("p", ReshapeKind.join,
                other: "c", on: 0, otherOn: 0),
            clubs,
            crests),
        [
          ["Club", "Pts", "City"],
          ["Arsenal", "79", "London"],
          ["Spurs", "52", ""],
        ]);
  });

  test("a made sheet follows its source, and its chart with it; saved", () {
    var c = CanvasController(CanvasDocument(sheets: [source]),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    var id = c.addMadeSheet(const SheetMade("w", ReshapeKind.long, keep: [0]));
    expect(c.sheetById(id)!.name, "Points, a row a value");
    var made = c.sheetById(id)!;
    c.addDataView(ElementKind.chart, id, made.used);
    c.setSheetCells("w", 1, 1, [
      ["80"]
    ]);
    expect(c.sheetById(id)!.cells[1], ["2024", "Arsenal", "80"]);
    var chart = c.document.elements.whereType<ChartElement>().single;
    expect(chart.data.series.expand((s) => s.values), contains(80));
    c.undo();
    expect(c.sheetById(id)!.cells[1][2], "74", reason: "one step with it");
    var back =
        DataSheet.fromJson(jsonDecode(jsonEncode(c.sheetById(id)!.toJson())))!;
    expect(back.made, c.sheetById(id)!.made);
    // Stopped, it keeps its cells and follows no more.
    c.setSheet(c.sheetById(id)!.copyWith(unmade: true));
    c.setSheetCells("w", 1, 1, [
      ["99"]
    ]);
    expect(c.sheetById(id)!.cells[1][2], "74");
  });

  testWidgets("made in the Studio: a long sheet from a wide one, opened",
      (tester) async {
    setTestScreen(tester, const Size(1600, 1400));
    var c = CanvasController(CanvasDocument(sheets: [source]),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    c.openDataStudio("w");
    await tester.pumpWidget(canvasApp(
        DataStudio(controller: c, sheetId: "w", onDone: c.closeDataStudio)));
    await tester.pumpAndSettle();
    final make = find.byKey(const ValueKey("dataStudioReshapeMake"));
    await tester.ensureVisible(make);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey("dataStudioReshapeSize")))
            .data,
        "4 rows by 3 columns");
    await tester.tap(make);
    await tester.pumpAndSettle();
    expect(c.document.sheets, hasLength(2));
    expect(find.byKey(const ValueKey("dataStudioMadeFrom")), findsOneWidget,
        reason: "the new sheet is shown, saying what it is made from");
    expect(tester.takeException(), isNull);
  });
}
