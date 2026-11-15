import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/sheet_files.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_sheet_files_test.dart is the Data Studio's files: CSV, XLSX and ODS
// read into sheets -- values and formulas, which the canvas then works out
// -- and a sheet written as CSV. The XLSX and ODS files are made here as
// Excel and Calc write them: a zip of XML.

List<int> zipOf(Map<String, String> files) {
  var a = Archive();
  for (var MapEntry(:key, :value) in files.entries) {
    var bytes = utf8.encode(value);
    a.addFile(ArchiveFile(key, bytes.length, bytes));
  }
  return ZipEncoder().encode(a);
}

void main() {
  test("CSV: commas, semicolons or tabs; quoted cells; either line ending", () {
    expect(readCsv('Club,Pts\r\n"Brighton & Hove, Albion",28\r\nSpurs,29'), [
      ["Club", "Pts"],
      ["Brighton & Hove, Albion", "28"],
      ["Spurs", "29"],
    ]);
    expect(
        readCsv("﻿a;b\n1;2\n"),
        [
          ["a", "b"],
          ["1", "2"],
        ],
        reason: "a semicolon file, as Calc writes for a decimal comma");
    expect(readCsv('say\n"he said ""hi"""\n'), [
      ["say"],
      ['he said "hi"'],
    ]);
    expect(readCsv("a\tb\n1\t2"), [
      ["a", "b"],
      ["1", "2"],
    ]);
  });

  test("a sheet as CSV: what each cell shows, quoted where it must be", () {
    var s = const DataSheet(id: "s", cells: [
      ["Club", "Pts", "Note"],
      ["Arsenal", "46", 'top, "for now"'],
      ["Total", "=SUM(B2:B2)"],
    ], columnFormats: {
      1: CellFormat(CellFormatKind.number, decimals: 1)
    });
    expect(
        csvOf(s), 'Club,Pts,Note\nArsenal,46.0,"top, ""for now"""\nTotal,46.0');
    expect(readCsv(csvOf(s))[1][2], 'top, "for now"', reason: "round trip");
  });

  test("XLSX: shared words, numbers, TRUE, formulas, gaps; every sheet", () {
    var bytes = zipOf({
      "xl/workbook.xml": '''<?xml version="1.0"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets><sheet name="League" sheetId="1" r:id="rId1"/><sheet name="Notes" sheetId="2" r:id="rId2"/></sheets></workbook>''',
      "xl/_rels/workbook.xml.rels": '''<?xml version="1.0"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="x" Target="worksheets/sheet1.xml"/>
<Relationship Id="rId2" Type="x" Target="worksheets/sheet2.xml"/></Relationships>''',
      "xl/sharedStrings.xml": '''<?xml version="1.0"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>Club</t></si><si><t>Pts</t></si><si><r><t>Ars</t></r><r><t>enal</t></r></si><si><t>=not a formula</t></si></sst>''',
      "xl/worksheets/sheet1.xml": '''<?xml version="1.0"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>
<row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2"><v>46</v></c><c r="D2" t="b"><v>1</v></c></row>
<row r="4"><c r="A4" t="s"><v>3</v></c><c r="B4"><f>SUM(B2:B3)</f><v>46</v></c></row>
</sheetData></worksheet>''',
      "xl/worksheets/sheet2.xml": '''<?xml version="1.0"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
<row r="1"><c r="A1" t="inlineStr"><is><t>Hello</t></is></c></row></sheetData></worksheet>''',
    });
    var sheets = readSheets("League.xlsx", bytes);
    expect(sheets.map((s) => s.name), ["League", "Notes"]);
    expect(sheets.first.cells, [
      ["Club", "Pts"],
      ["Arsenal", "46", "", "TRUE"],
      [],
      ["'=not a formula", "=SUM(B2:B3)"],
    ]);
    var made = DataSheet(id: "s", cells: sheets.first.cells);
    expect(sheetShown(made, 3, 1), "46", reason: "worked out by the canvas");
    expect(sheetShown(made, 3, 0), "=not a formula");
    expect(sheets.last.cells, [
      ["Hello"]
    ]);
    expect(() => readSheets("x.xlsx", [1, 2, 3]), throwsFormatException);
  });

  test("ODS: Calc's own, repeated cells and rows, formulas, dates", () {
    var bytes = zipOf({
      "content.xml": '''<?xml version="1.0" encoding="UTF-8"?>
<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">
<office:body><office:spreadsheet>
<table:table table:name="League">
<table:table-row><table:table-cell office:value-type="string"><text:p>Club</text:p></table:table-cell><table:table-cell office:value-type="string"><text:p>Pts</text:p></table:table-cell><table:table-cell table:number-columns-repeated="1020"/></table:table-row>
<table:table-row><table:table-cell office:value-type="string"><text:p>Arsenal</text:p></table:table-cell><table:table-cell office:value-type="float" office:value="46"><text:p>46</text:p></table:table-cell></table:table-row>
<table:table-row><table:table-cell office:value-type="string"><text:p>Chelsea</text:p></table:table-cell><table:table-cell office:value-type="float" office:value="40"><text:p>40</text:p></table:table-cell></table:table-row>
<table:table-row><table:table-cell office:value-type="string"><text:p>Total</text:p></table:table-cell><table:table-cell table:formula="of:=SUM([.B2:.B3])" office:value-type="float" office:value="86"><text:p>86</text:p></table:table-cell></table:table-row>
<table:table-row><table:table-cell office:value-type="date" office:date-value="2026-11-15"><text:p>15/11/26</text:p></table:table-cell><table:table-cell office:value-type="percentage" office:value="0.25"><text:p>25%</text:p></table:table-cell><table:table-cell table:number-columns-repeated="2" office:value-type="float" office:value="7"><text:p>7</text:p></table:table-cell></table:table-row>
<table:table-row table:number-rows-repeated="1048570"><table:table-cell table:number-columns-repeated="1024"/></table:table-row>
</table:table>
<table:table table:name="Empty"/>
</office:spreadsheet></office:body></office:document-content>''',
    });
    var sheets = readSheets("league.ods", bytes);
    expect(sheets.map((s) => s.name), ["League", "Empty"]);
    var cells = sheets.first.cells;
    expect(cells.length, 5, reason: "a million empty rows not read");
    expect(cells[0], ["Club", "Pts"]);
    expect(cells[3], ["Total", "=SUM(B2:B3)"]);
    expect(cells[4], ["46341", "0.25", "7", "7"]);
    var made = DataSheet(id: "s", cells: cells);
    expect(sheetShown(made, 3, 1), "86");
  });
}
