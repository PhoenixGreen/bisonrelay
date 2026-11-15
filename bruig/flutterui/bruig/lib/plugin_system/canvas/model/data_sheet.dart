import 'dart:math' as math;

import 'package:flutter/foundation.dart';

// data_sheet.dart is the Data element's data (Ken, 2026-11-15: Table and
// Chart made one "Data" element, its data kept in sheets edited in a
// spreadsheet-like Data Studio): a canvas keeps its data in sheets, as a
// Calc workbook does, and each Data element on it -- shown as a table or a
// chart -- is a view of a range of one (SheetLink). Several can view one
// sheet, so a league table and a chart of its points read the same numbers
// and cannot disagree.
//
// A sheet holds what was typed in each cell (raw text); what a cell shows
// is worked out from it (sheetShown). See data_sync.dart for how views are
// kept in step with their sheet.

/// CellRange is a block of cells, from row [r0] and column [c0] to [r1] and
/// [c1] inclusive, counted from 0.
@immutable
class CellRange {
  final int r0, c0, r1, c1;
  const CellRange(this.r0, this.c0, this.r1, this.c1);

  /// of is the range [rows] tall and [cols] wide at [r0], [c0].
  factory CellRange.of(int rows, int cols, {int r0 = 0, int c0 = 0}) =>
      CellRange(r0, c0, r0 + math.max<int>(1, rows) - 1,
          c0 + math.max<int>(1, cols) - 1);

  int get rows => r1 - r0 + 1;
  int get cols => c1 - c0 + 1;

  bool contains(int r, int c) => r >= r0 && r <= r1 && c >= c0 && c <= c1;
  bool overlaps(CellRange o) =>
      !(o.r1 < r0 || o.r0 > r1 || o.c1 < c0 || o.c0 > c1);

  /// a1 is it as a spreadsheet writes it: "A1:H9".
  String get a1 => r0 == r1 && c0 == c1
      ? cellName(r0, c0)
      : "${cellName(r0, c0)}:${cellName(r1, c1)}";

  /// parse reads "A1:H9", "B4" or "a1:c3"; null for anything else.
  static CellRange? parse(String text) {
    var parts = text.trim().toUpperCase().split(":");
    if (parts.isEmpty || parts.length > 2) return null;
    var a = cellAt(parts.first), b = parts.length == 2 ? cellAt(parts[1]) : a;
    if (a == null || b == null) return null;
    return CellRange(math.min(a.$1, b.$1), math.min(a.$2, b.$2),
        math.max(a.$1, b.$1), math.max(a.$2, b.$2));
  }

  @override
  bool operator ==(Object other) =>
      other is CellRange &&
      other.r0 == r0 &&
      other.c0 == c0 &&
      other.r1 == r1 &&
      other.c1 == c1;

  @override
  int get hashCode => Object.hash(r0, c0, r1, c1);

  @override
  String toString() => a1;
}

/// columnName is column [c] as a spreadsheet letters it: A, B, … Z, AA.
String columnName(int c) {
  var s = "";
  for (var n = c + 1; n > 0; n = (n - 1) ~/ 26) {
    s = String.fromCharCode(65 + (n - 1) % 26) + s;
  }
  return s;
}

/// cellName is the cell at row [r], column [c]: "B4".
String cellName(int r, int c) => "${columnName(c)}${r + 1}";

/// cellAt reads "B4" (or "$B$4") as its row and column; null otherwise.
(int, int)? cellAt(String text) {
  var m = RegExp(r"^\$?([A-Z]{1,3})\$?(\d+)$").firstMatch(text.trim());
  if (m == null) return null;
  var c = 0;
  for (var ch in m.group(1)!.codeUnits) {
    c = c * 26 + (ch - 64);
  }
  var r = int.parse(m.group(2)!);
  if (r < 1) return null;
  return (r - 1, c - 1);
}

/// SheetLink is a Data element's view of a sheet: which sheet, the range it
/// shows (its first row the headings), and for a chart which of its
/// columns label the axis and which are its series, counted from the
/// range's first column.
@immutable
class SheetLink {
  final String sheet;
  final CellRange range;
  final int labels;
  final List<int> series;

  const SheetLink(this.sheet, this.range,
      {this.labels = 0, this.series = const []});

  SheetLink copyWith(
          {String? sheet, CellRange? range, int? labels, List<int>? series}) =>
      SheetLink(sheet ?? this.sheet, range ?? this.range,
          labels: labels ?? this.labels, series: series ?? this.series);

  Map<String, dynamic> toJson() => {
        "id": sheet,
        "range": range.a1,
        if (labels != 0) "labels": labels,
        if (series.isNotEmpty) "series": series,
      };

  static SheetLink? fromJson(Object? j) {
    if (j is! Map) return null;
    var id = j["id"], range = CellRange.parse("${j["range"] ?? ""}");
    if (id is! String || id.isEmpty || range == null) return null;
    return SheetLink(id, range,
        labels: j["labels"] is num ? (j["labels"] as num).toInt() : 0,
        series: [
          if (j["series"] case List s)
            for (var c in s)
              if (c is num) c.toInt(),
        ]);
  }

  @override
  bool operator ==(Object other) =>
      other is SheetLink &&
      other.sheet == sheet &&
      other.range == range &&
      other.labels == labels &&
      listEquals(other.series, series);

  @override
  int get hashCode => Object.hash(sheet, range, labels, Object.hashAll(series));
}

/// DataSheet is one sheet: its name and what was typed in each cell, row by
/// row (rows may be ragged: a missing cell is empty).
@immutable
class DataSheet {
  final String id;
  final String name;
  final List<List<String>> cells;

  const DataSheet(
      {required this.id, this.name = "Sheet", this.cells = const []});

  int get rowCount => cells.length;
  int get columnCount => cells.fold(0, (n, r) => math.max(n, r.length));

  /// raw is what was typed in row [r], column [c]: empty past the edge.
  String raw(int r, int c) =>
      r >= 0 && r < cells.length && c >= 0 && c < cells[r].length
          ? cells[r][c]
          : "";

  /// used is the block from A1 holding everything typed.
  CellRange get used => CellRange.of(rowCount, columnCount);

  DataSheet copyWith({String? name, List<List<String>>? cells}) =>
      DataSheet(id: id, name: name ?? this.name, cells: cells ?? this.cells);

  /// withBlock is it with [rows] written from [r0], [c0] -- and the cells
  /// of [clear] it doesn't reach emptied, where a view grew smaller. Rows
  /// and columns past the edge are added; empty ones left at the end are
  /// taken off.
  DataSheet withBlock(int r0, int c0, List<List<String>> rows,
      {CellRange? clear}) {
    var height = math.max(cells.length, r0 + rows.length);
    var next = [
      for (var r = 0; r < height; r++)
        [...(r < cells.length ? cells[r] : const <String>[])]
    ];
    void put(int r, int c, String v) {
      var row = next[r];
      if (c >= row.length) {
        if (v.isEmpty) return;
        row.addAll(List.filled(c - row.length + 1, ""));
      }
      row[c] = v;
    }

    if (clear != null) {
      for (var r = clear.r0; r <= clear.r1 && r < next.length; r++) {
        for (var c = clear.c0; c <= clear.c1; c++) {
          var inBlock = r >= r0 &&
              r < r0 + rows.length &&
              c >= c0 &&
              c < c0 + rows[r - r0].length;
          if (!inBlock) put(r, c, "");
        }
      }
    }
    for (var (i, row) in rows.indexed) {
      for (var (j, v) in row.indexed) {
        put(r0 + i, c0 + j, v);
      }
    }
    return copyWith(cells: _trimmed(next));
  }

  /// withCell is it with [text] typed in row [r], column [c].
  DataSheet withCell(int r, int c, String text) => withBlock(r, c, [
        [text]
      ]);

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "cells": cells,
      };

  static DataSheet? fromJson(Object? j) {
    if (j is! Map) return null;
    var id = j["id"];
    if (id is! String || id.isEmpty) return null;
    return DataSheet(
        id: id,
        name: j["name"] is String ? j["name"] as String : "Sheet",
        cells: [
          if (j["cells"] case List rows)
            for (var r in rows)
              if (r is List) [for (var c in r) "${c ?? ""}"],
        ]);
  }
}

/// _trimmed is [rows] without the empty cells ending each row and the empty
/// rows ending the sheet.
List<List<String>> _trimmed(List<List<String>> rows) {
  var out = [
    for (var r in rows)
      () {
        var n = r.length;
        while (n > 0 && r[n - 1].isEmpty) {
          n--;
        }
        return n == r.length ? r : r.sublist(0, n);
      }(),
  ];
  while (out.isNotEmpty && out.last.isEmpty) {
    out.removeLast();
  }
  return out;
}

/// sheetShown is what cell [r], [c] of [sheet] shows: for now what was
/// typed; formulas and number formats come in with the Data Studio.
String sheetShown(DataSheet sheet, int r, int c) => sheet.raw(r, c);

/// sheetBlock is what [range] of [sheet] shows, a row of strings per row.
List<List<String>> sheetBlock(DataSheet sheet, CellRange range) => [
      for (var r = range.r0; r <= range.r1; r++)
        [for (var c = range.c0; c <= range.c1; c++) sheetShown(sheet, r, c)],
    ];
