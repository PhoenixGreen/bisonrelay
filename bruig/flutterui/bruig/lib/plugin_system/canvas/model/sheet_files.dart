import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/sheet_formula.dart'
    show generalNumber, serialOf;
import 'package:xml/xml.dart';

// sheet_files.dart is the Data Studio's files (Ken's plan, approved
// 2026-11-15: "Import CSV, XLSX and ODS, and export CSV"): a spreadsheet
// saved by Calc, Excel or Sheets read into sheets of the canvas -- its
// values and its formulas, which the canvas works out itself -- and a sheet
// written out as CSV for them to open.
//
// Values and formulas are read; styles, charts and pictures are not. Each
// is read with packages the app already has (archive, xml): an XLSX or ODS
// file is a zip of XML.

/// ReadSheet is one sheet read from a file: its name and its cells.
class ReadSheet {
  final String name;
  final List<List<String>> cells;
  const ReadSheet(this.name, this.cells);
}

/// readSheets reads the file [name] holding [bytes] -- by its ending, CSV
/// (or TSV, or text), XLSX or ODS -- or throws a FormatException saying
/// why it can't.
List<ReadSheet> readSheets(String name, List<int> bytes) {
  var lower = name.toLowerCase();
  var base =
      name.split(RegExp(r"[/\\]")).last.replaceAll(RegExp(r"\.[^.]+$"), "");
  if (lower.endsWith(".xlsx")) return readXlsx(bytes);
  if (lower.endsWith(".ods")) return readOds(bytes);
  var text = utf8.decode(bytes, allowMalformed: true);
  return [ReadSheet(base.isEmpty ? "Imported" : base, readCsv(text))];
}

/// _cap is how many rows or columns a sheet read from a file may have: a
/// file can say a row repeats a million times.
const _cap = 5000;

// ---------- CSV ----------

/// readCsv reads [text]: comma-, semicolon- or tab-separated, as its first
/// line shows, with quoted cells ("a, b" and "say ""hi""") and either line
/// ending; a byte-order mark in front is passed over.
List<List<String>> readCsv(String text) {
  if (text.startsWith("﻿")) text = text.substring(1);
  var first = text.split("\n").first;
  int count(String c) => c.allMatches(first).length;
  var sep = [",", ";", "\t"].reduce((a, b) => count(b) > count(a) ? b : a);
  var rows = <List<String>>[];
  var row = <String>[];
  var cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    var ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"' && cell.isEmpty) {
      quoted = true;
    } else if (ch == sep) {
      row.add(cell.toString());
      cell.clear();
    } else if (ch == "\n" || ch == "\r") {
      if (ch == "\r" && i + 1 < text.length && text[i + 1] == "\n") i++;
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = [];
      if (rows.length >= _cap) break;
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

/// csvOf is [sheet] as CSV: each cell as it shows, quoted where it holds a
/// comma, a quote or a line break.
String csvOf(DataSheet sheet) {
  String quote(String v) =>
      v.contains(RegExp(r'[",\n\r]')) ? '"${v.replaceAll('"', '""')}"' : v;
  return [
    for (var r = 0; r < sheet.rowCount; r++)
      [
        for (var c = 0; c < sheet.cells[r].length; c++)
          quote(sheetShown(sheet, r, c))
      ].join(","),
  ].join("\n");
}

// ---------- XLSX ----------

XmlDocument? _xmlIn(Archive zip, String path) {
  var f = zip.findFile(path);
  if (f == null) return null;
  return XmlDocument.parse(utf8.decode(f.content, allowMalformed: true));
}

/// readXlsx reads an Excel workbook: every sheet, its values and formulas.
List<ReadSheet> readXlsx(List<int> bytes) {
  Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException("That isn't an XLSX file.");
  }
  var book = _xmlIn(zip, "xl/workbook.xml");
  if (book == null) throw const FormatException("That isn't an XLSX file.");
  var rels = _xmlIn(zip, "xl/_rels/workbook.xml.rels");
  var targets = <String, String>{
    for (var r in rels?.findAllElements("Relationship") ?? <XmlElement>[])
      r.getAttribute("Id") ?? "": r.getAttribute("Target") ?? "",
  };
  var shared = [
    for (var si in _xmlIn(zip, "xl/sharedStrings.xml")?.findAllElements("si") ??
        <XmlElement>[])
      si.findAllElements("t").map((t) => t.innerText).join(),
  ];
  var out = <ReadSheet>[];
  for (var (i, s) in book.findAllElements("sheet").indexed) {
    var name = s.getAttribute("name") ?? "Sheet ${i + 1}";
    var id = s.getAttribute("r:id") ??
        s.attributes
            .where((a) => a.name.local == "id")
            .map((a) => a.value)
            .firstOrNull;
    var target = targets[id] ?? "worksheets/sheet${i + 1}.xml";
    var path = target.startsWith("/") ? target.substring(1) : "xl/$target";
    var doc = _xmlIn(zip, path);
    if (doc == null) continue;
    var rows = <List<String>>[];
    for (var row in doc.findAllElements("row")) {
      var r =
          (int.tryParse(row.getAttribute("r") ?? "") ?? rows.length + 1) - 1;
      if (r >= _cap) break;
      var cells = <String>[];
      var next = 0;
      for (var cEl in row.findElements("c")) {
        var at = cellAt(cEl.getAttribute("r") ?? "");
        var col = at?.$2 ?? next;
        next = col + 1;
        if (col >= _cap) continue;
        var t = cEl.getAttribute("t") ?? "n";
        var f = cEl.getElement("f")?.innerText;
        var v = cEl.getElement("v")?.innerText ?? "";
        String raw;
        if (f != null && f.isNotEmpty) {
          raw = "=$f";
        } else {
          raw = switch (t) {
            "s" => _shared(shared, v),
            "b" => v == "1" ? "TRUE" : "FALSE",
            "inlineStr" =>
              cEl.findAllElements("t").map((x) => x.innerText).join(),
            "e" => v,
            _ => v,
          };
          // A typed word that would read as a formula stays a word.
          if (t != "n" && raw.startsWith("=")) raw = "'$raw";
        }
        while (cells.length < col) {
          cells.add("");
        }
        cells.add(raw);
      }
      while (rows.length < r) {
        rows.add([]);
      }
      rows.add(cells);
    }
    out.add(ReadSheet(name, _trimmed(rows)));
  }
  if (out.isEmpty) throw const FormatException("That workbook has no sheets.");
  return out;
}

String _shared(List<String> shared, String v) {
  var k = int.tryParse(v);
  return k != null && k >= 0 && k < shared.length ? shared[k] : "";
}

// ---------- ODS ----------

/// readOds reads an OpenDocument spreadsheet (Calc's own): every sheet,
/// its values and formulas.
List<ReadSheet> readOds(List<int> bytes) {
  Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException("That isn't an ODS file.");
  }
  var content = _xmlIn(zip, "content.xml");
  if (content == null) throw const FormatException("That isn't an ODS file.");
  String? attr(XmlElement e, String local) => e.attributes
      .where((a) => a.name.local == local)
      .map((a) => a.value)
      .firstOrNull;
  var out = <ReadSheet>[];
  for (var table in content.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == "table" && e.name.prefix == "table")) {
    var rows = <List<String>>[];
    for (var row in table.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == "table-row")) {
      var cells = <String>[];
      for (var cEl in row.children.whereType<XmlElement>().where((e) =>
          e.name.local == "table-cell" ||
          e.name.local == "covered-table-cell")) {
        var raw = _odsCell(cEl, attr);
        var times =
            int.tryParse(attr(cEl, "number-columns-repeated") ?? "") ?? 1;
        // A file fills the rest of a row with one repeated empty cell.
        if (raw.isEmpty && times > 1) times = math.min(times, 1);
        for (var k = 0; k < times && cells.length < _cap; k++) {
          cells.add(raw);
        }
      }
      var times = int.tryParse(attr(row, "number-rows-repeated") ?? "") ?? 1;
      var empty = cells.every((v) => v.isEmpty);
      if (empty && times > 1) times = 1;
      for (var k = 0; k < times && rows.length < _cap; k++) {
        rows.add([...cells]);
      }
    }
    out.add(ReadSheet(
        attr(table, "name") ?? "Sheet ${out.length + 1}", _trimmed(rows)));
  }
  if (out.isEmpty) throw const FormatException("That file has no sheets.");
  return out;
}

String _odsCell(XmlElement c, String? Function(XmlElement, String) attr) {
  var formula = attr(c, "formula");
  if (formula != null && formula.isNotEmpty) return _odsFormula(formula);
  var type = attr(c, "value-type");
  switch (type) {
    case "float" || "percentage" || "currency":
      return attr(c, "value") ?? "";
    case "boolean":
      return attr(c, "boolean-value") == "true" ? "TRUE" : "FALSE";
    case "date":
      var d = DateTime.tryParse(attr(c, "date-value") ?? "");
      return d == null ? "" : generalNumber(serialOf(d));
  }
  var text = c.children
      .whereType<XmlElement>()
      .where((e) => e.name.local == "p")
      .map((p) => p.innerText)
      .join("\n");
  return text.startsWith("=") ? "'$text" : text;
}

/// _odsFormula is a Calc formula as ODS writes it -- "of:=SUM([.A1:.B2])"
/// -- as the canvas writes it: "=SUM(A1:B2)".
String _odsFormula(String f) {
  var s = f.replaceFirst(RegExp(r"^\w+:"), "");
  s = s.replaceAllMapped(
      RegExp(
          r"\[\$?[^\]]*?\.(\$?[A-Z]+\$?\d+)(?::\$?[^\]]*?\.(\$?[A-Z]+\$?\d+))?\]"),
      (m) => m.group(2) == null ? m.group(1)! : "${m.group(1)}:${m.group(2)}");
  s = s.replaceAll(";", ",");
  return s.startsWith("=") ? s : "=$s";
}

List<List<String>> _trimmed(List<List<String>> rows) {
  var out = [
    for (var r in rows)
      () {
        var n = r.length;
        while (n > 0 && r[n - 1].isEmpty) {
          n--;
        }
        return r.sublist(0, n);
      }(),
  ];
  while (out.isNotEmpty && out.last.isEmpty) {
    out.removeLast();
  }
  return out;
}
