import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_data_formulas_test.dart is the Data element's sheets worked out:
// formulas and number formats reaching the tables and charts that show
// them, formulas' references following rows put in, taken out and sorted,
// and the fill handle carrying a selection on.

DataSheet sheetOf(List<List<String>> cells,
        {Map<String, CellFormat> formats = const {},
        Map<int, CellFormat> columns = const {}}) =>
    DataSheet(
        id: "s",
        name: "League",
        cells: cells,
        formats: formats,
        columnFormats: columns);

CanvasDocument docOf(DataSheet s, {SheetLink? chart}) => CanvasDocument(
      sheets: [s],
      elements: [
        TableElement(const ElementBase(id: "t"), sheet: SheetLink("s", s.used)),
        if (chart != null)
          ChartElement(const ElementBase(id: "c"), sheet: chart),
      ],
    );

/// made is [doc] with its views made from their sheets, as opening it does.
CanvasDocument made(CanvasDocument doc) =>
    dataSynced(const CanvasDocument(), doc);

void main() {
  test("a formula shows what it works out to, in the table and the chart", () {
    var s = sheetOf([
      ["Club", "W", "D", "Pts"],
      ["Arsenal", "14", "4", "=B2*3+C2"],
      ["Chelsea", "12", "4", "=B3*3+C3"],
      ["Total", "=SUM(B2:B3)", "", "=SUM(D2:D3)"],
    ]);
    var doc = made(docOf(s,
        chart: const SheetLink("s", CellRange(0, 0, 2, 3), series: [3])));
    var t = doc.elementById("t") as TableElement;
    expect(t.rows[1][3], "46");
    expect(t.rows[3], ["Total", "26", "", "86"]);
    var ch = doc.elementById("c") as ChartElement;
    expect(ch.data.series.single.values, [46, 40]);
  });

  test("formats write a table's numbers; the chart still reads the numbers",
      () {
    var s = sheetOf([
      ["Month", "Price", "Change"],
      ["Jan", "14.2", ""],
      ["Feb", "15.8", "=(B3-B2)/B2"],
    ], columns: {
      1: const CellFormat(CellFormatKind.money),
      2: const CellFormat(CellFormatKind.percent),
    });
    var doc = made(docOf(s,
        chart: const SheetLink("s", CellRange(0, 0, 2, 1), series: [1])));
    var t = doc.elementById("t") as TableElement;
    expect(t.rows[1][1], r"$14.20");
    expect(t.rows[2][2], "11.3%");
    expect((doc.elementById("c") as ChartElement).data.series.single.values,
        [14.2, 15.8]);
    // Others.
    expect(const CellFormat(CellFormatKind.short).write(1234567.0), "1.2M");
    expect(const CellFormat(CellFormatKind.money, symbol: "£").write(-5.0),
        "-£5.00");
    expect(const CellFormat(CellFormatKind.number, decimals: 1).write(1234.56),
        "1,234.6");
    expect(const CellFormat(CellFormatKind.date).write(46341.0), "15/11/2026");
    var back = DataSheet.fromJson(s.toJson())!;
    expect(back.columnFormats[1], const CellFormat(CellFormatKind.money));
  });

  test("a formula that reads itself is a cycle, not a hang", () {
    var s = sheetOf([
      ["=B1", "=A1"]
    ]);
    expect(sheetShown(s, 0, 0), "#CYCLE!");
  });

  test("rows put in and taken out: formulas and formats follow", () {
    var s = sheetOf([
      ["Club", "Pts"],
      ["Arsenal", "46"],
      ["Chelsea", "40"],
      ["Total", "=SUM(B2:B3)"],
    ], formats: {
      "B4": const CellFormat(CellFormatKind.number, decimals: 1)
    });
    var doc = rowsInserted(docOf(s), "s", 2, 1);
    var t = doc.sheets.single;
    expect(t.raw(4, 1), "=SUM(B2:B4)", reason: "the range grew round it");
    expect(t.formats.keys, ["B5"]);
    doc = rowsDeleted(docOf(s), "s", 1, 1);
    expect(doc.sheets.single.raw(2, 1), "=SUM(B2:B2)");
    doc = columnsInserted(docOf(s), "s", 1, 1);
    expect(doc.sheets.single.raw(3, 2), "=SUM(C2:C3)");
  });

  test("sorted: each row's formula still reads its own row", () {
    var s = sheetOf([
      ["Club", "W", "D", "Pts"],
      ["Chelsea", "12", "4", "=B2*3+C2"],
      ["Arsenal", "14", "4", "=B3*3+C3"],
    ]);
    var doc = rowsSorted(docOf(s), "s", const CellRange(1, 0, 2, 3), 3,
        descending: true);
    var t = doc.sheets.single;
    expect(t.raw(1, 0), "Arsenal");
    expect(t.raw(1, 3), "=B2*3+C2");
    expect(sheetShown(t, 1, 3), "46");
    expect(sheetShown(t, 2, 3), "40");
  });

  test("the fill handle: series carried on, formulas copied", () {
    String fillDown(List<String> col, int n) {
      var s = sheetOf([
        for (var v in col) [v]
      ]);
      var f = sheetFilled(s, CellRange(0, 0, col.length - 1, 0),
          CellRange(col.length, 0, col.length + n - 1, 0));
      return [for (var r = col.length; r < col.length + n; r++) f.raw(r, 0)]
          .join(",");
    }

    expect(fillDown(["1", "3"], 3), "5,7,9");
    expect(fillDown(["5"], 2), "6,7", reason: "Calc counts one number up");
    expect(fillDown(["0.5", "1"], 2), "1.5,2");
    expect(fillDown(["Jan"], 3), "Feb,Mar,Apr");
    expect(fillDown(["Monday", "Wednesday"], 2), "Friday,Sunday");
    expect(fillDown(["Nov", "Dec"], 2), "Jan,Feb");
    expect(fillDown(["Week 1"], 2), "Week 2,Week 3");
    expect(fillDown(["Q01"], 2), "Q02,Q03");
    expect(fillDown(["red", "blue"], 3), "red,blue,red");
    expect(fillDown(["=A1*2"], 2), "=A2*2,=A3*2");
    // Across: the next columns.
    var s = sheetOf([
      ["10", "=A1+1"],
    ]);
    var f = sheetFilled(
        s, const CellRange(0, 0, 0, 1), const CellRange(0, 2, 0, 3));
    expect(f.cells.single, ["10", "=A1+1", "10", "=C1+1"]);
  });
}
