import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/sheet_formula.dart';
import 'package:bruig/plugin_system/canvas/model/tabular_text.dart';
import 'package:flutter/foundation.dart';

export 'package:bruig/plugin_system/canvas/model/sheet_formula.dart'
    show SheetError;

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

  /// The rows this view shows of its range, without changing the sheet
  /// (Ken's plan: "the table shows all 20 clubs, the chart the top 5"):
  /// in order of column [sortBy] (-1, the sheet's own order), largest first
  /// where [descending]; only those whose column [whereColumn] meets
  /// [where] (a COUNTIF criterion: ">5", "Arsenal", "<>0"); the first
  /// [top] of them (0, all).
  final int sortBy;
  final bool descending;
  final int top;
  final int whereColumn;
  final String where;

  // How a chart reads its rows (the Data Studio's Charts tab, prototype v6):

  /// group brings rows with the same label together: "" each row, or
  /// "total", "average", "count", "most", "least" of their numbers.
  final String group;

  /// bottom takes the last [top] rows rather than the first.
  final bool bottom;

  /// places is which places to show, as "1-3, 16-19", counted after the
  /// order; [gap] puts an empty slot between groups of them.
  final String places;
  final bool gap;

  /// colourBy is a column (counted from the range's first) that colours each
  /// mark: words a colour each, numbers a scale; on a line chart, words
  /// make a line each. -1, none.
  final int colourBy;

  /// through is a column of dates the chart shows one at a time, [at] the
  /// one shown (empty, the last). -1, none.
  final int through;
  final String at;

  /// split draws a small chart for each word of a column (Arsenal's, then
  /// Chelsea's...), all on one scale. -1, one chart.
  final int split;

  const SheetLink(this.sheet, this.range,
      {this.labels = 0,
      this.series = const [],
      this.sortBy = -1,
      this.descending = true,
      this.top = 0,
      this.whereColumn = -1,
      this.where = "",
      this.group = "",
      this.bottom = false,
      this.places = "",
      this.gap = true,
      this.colourBy = -1,
      this.through = -1,
      this.at = "",
      this.split = -1});

  /// plain is whether it shows its range's rows as they are.
  bool get plain =>
      sortBy < 0 &&
      top <= 0 &&
      (whereColumn < 0 || where.trim().isEmpty) &&
      !charted;

  /// charted is whether it reads its rows as only a chart can: grouped, one
  /// date at a time, coloured by a column, or by places or from the bottom.
  bool get charted =>
      group.isNotEmpty ||
      through >= 0 ||
      colourBy >= 0 ||
      places.trim().isNotEmpty ||
      (bottom && top > 0) ||
      split >= 0;

  SheetLink copyWith(
          {String? sheet,
          CellRange? range,
          int? labels,
          List<int>? series,
          int? sortBy,
          bool? descending,
          int? top,
          int? whereColumn,
          String? where,
          String? group,
          bool? bottom,
          String? places,
          bool? gap,
          int? colourBy,
          int? through,
          String? at,
          int? split}) =>
      SheetLink(sheet ?? this.sheet, range ?? this.range,
          labels: labels ?? this.labels,
          series: series ?? this.series,
          sortBy: sortBy ?? this.sortBy,
          descending: descending ?? this.descending,
          top: top ?? this.top,
          whereColumn: whereColumn ?? this.whereColumn,
          where: where ?? this.where,
          group: group ?? this.group,
          bottom: bottom ?? this.bottom,
          places: places ?? this.places,
          gap: gap ?? this.gap,
          colourBy: colourBy ?? this.colourBy,
          through: through ?? this.through,
          at: at ?? this.at,
          split: split ?? this.split);

  Map<String, dynamic> toJson() => {
        "id": sheet,
        "range": range.a1,
        if (labels != 0) "labels": labels,
        if (series.isNotEmpty) "series": series,
        if (sortBy >= 0) "sortBy": sortBy,
        if (sortBy >= 0 && !descending) "ascending": true,
        if (top > 0) "top": top,
        if (whereColumn >= 0 && where.isNotEmpty) "whereColumn": whereColumn,
        if (whereColumn >= 0 && where.isNotEmpty) "where": where,
        if (group.isNotEmpty) "group": group,
        if (bottom) "bottom": true,
        if (places.isNotEmpty) "places": places,
        if (!gap) "gap": false,
        if (colourBy >= 0) "colourBy": colourBy,
        if (through >= 0) "through": through,
        if (at.isNotEmpty) "at": at,
        if (split >= 0) "split": split,
      };

  static SheetLink? fromJson(Object? j) {
    if (j is! Map) return null;
    var id = j["id"], range = CellRange.parse("${j["range"] ?? ""}");
    if (id is! String || id.isEmpty || range == null) return null;
    int n(String k, int or) => j[k] is num ? (j[k] as num).toInt() : or;
    return SheetLink(id, range,
        labels: n("labels", 0),
        series: [
          if (j["series"] case List s)
            for (var c in s)
              if (c is num) c.toInt(),
        ],
        sortBy: n("sortBy", -1),
        descending: j["ascending"] != true,
        top: n("top", 0),
        whereColumn: n("whereColumn", -1),
        where: j["where"] is String ? j["where"] as String : "",
        group: j["group"] is String ? j["group"] as String : "",
        bottom: j["bottom"] == true,
        places: j["places"] is String ? j["places"] as String : "",
        gap: j["gap"] != false,
        colourBy: n("colourBy", -1),
        through: n("through", -1),
        at: j["at"] is String ? j["at"] as String : "",
        split: n("split", -1));
  }

  @override
  bool operator ==(Object other) =>
      other is SheetLink &&
      other.sheet == sheet &&
      other.range == range &&
      other.labels == labels &&
      listEquals(other.series, series) &&
      other.sortBy == sortBy &&
      other.descending == descending &&
      other.top == top &&
      other.whereColumn == whereColumn &&
      other.where == where &&
      other.group == group &&
      other.bottom == bottom &&
      other.places == places &&
      other.gap == gap &&
      other.colourBy == colourBy &&
      other.through == through &&
      other.at == at &&
      other.split == split;

  @override
  int get hashCode => Object.hash(
      sheet,
      range,
      labels,
      Object.hashAll(series),
      sortBy,
      descending,
      top,
      whereColumn,
      where,
      group,
      bottom,
      places,
      gap,
      colourBy,
      through,
      at,
      split);
}

/// DataSheet is one sheet: its name and what was typed in each cell, row by
/// row (rows may be ragged: a missing cell is empty).
@immutable
class DataSheet {
  final String id;
  final String name;
  final List<List<String>> cells;

  /// formats are cells' own number formats, by name ("B2"); columnFormats
  /// a whole column's, by index -- a cell's own over its column's.
  final Map<String, CellFormat> formats;
  final Map<int, CellFormat> columnFormats;

  /// rules are its colour rules (Calc's conditional formatting): data
  /// bars, colour scales and highlights, drawn by the tables showing them.
  final List<SheetRule> rules;

  /// source is where its numbers come from (Connect data in the Data
  /// Studio): a web address or a file, mapped into columns. Every table and
  /// chart of the sheet follows a refresh. Off for a sheet typed in.
  final DataSource source;

  /// spotlight is one row picked out everywhere the sheet is shown (the
  /// Charts tab's "pick it out everywhere"): its mark lit in every chart of
  /// the sheet, its row tinted in every table. Empty, none.
  final String spotlight;
  final Color spotlightColour;

  /// gridRows and gridColumns are how many rows and columns the Data
  /// Studio's grid has (Ken, 2026-11-16: 40 rows to start, more added at
  /// the end of the row numbers): at least, since the cells typed always
  /// show. See [shownRows].
  final int gridRows, gridColumns;

  const DataSheet(
      {required this.id,
      this.name = "Sheet",
      this.cells = const [],
      this.formats = const {},
      this.columnFormats = const {},
      this.rules = const [],
      this.source = const DataSource(),
      this.spotlight = "",
      this.spotlightColour = const Color(0xFFF2B33D),
      this.gridRows = defaultGridRows,
      this.gridColumns = defaultGridColumns});

  static const int defaultGridRows = 40, defaultGridColumns = 26;

  /// shownRows and shownColumns are how many the grid has: its own size, or
  /// as many as are typed in, whichever is more.
  int get shownRows => math.max(gridRows, rowCount);
  int get shownColumns => math.max(gridColumns, columnCount);

  /// formatAt is cell [r], [c]'s number format: its own, its column's, or
  /// null for General.
  CellFormat? formatAt(int r, int c) =>
      formats[cellName(r, c)] ?? columnFormats[c];

  int get rowCount => cells.length;
  int get columnCount => cells.fold(0, (n, r) => math.max(n, r.length));

  /// raw is what was typed in row [r], column [c]: empty past the edge.
  String raw(int r, int c) =>
      r >= 0 && r < cells.length && c >= 0 && c < cells[r].length
          ? cells[r][c]
          : "";

  /// used is the block from A1 holding everything typed.
  CellRange get used => CellRange.of(rowCount, columnCount);

  DataSheet copyWith(
          {String? name,
          List<List<String>>? cells,
          Map<String, CellFormat>? formats,
          Map<int, CellFormat>? columnFormats,
          List<SheetRule>? rules,
          DataSource? source,
          String? spotlight,
          Color? spotlightColour,
          int? gridRows,
          int? gridColumns}) =>
      DataSheet(
          id: id,
          name: name ?? this.name,
          cells: cells ?? this.cells,
          formats: formats ?? this.formats,
          columnFormats: columnFormats ?? this.columnFormats,
          rules: rules ?? this.rules,
          source: source ?? this.source,
          spotlight: spotlight ?? this.spotlight,
          spotlightColour: spotlightColour ?? this.spotlightColour,
          gridRows: gridRows ?? this.gridRows,
          gridColumns: gridColumns ?? this.gridColumns);

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
        if (formats.isNotEmpty)
          "formats": {
            for (var MapEntry(:key, :value) in formats.entries)
              key: value.toJson()
          },
        if (columnFormats.isNotEmpty)
          "columnFormats": {
            for (var MapEntry(:key, :value) in columnFormats.entries)
              "$key": value.toJson()
          },
        if (rules.isNotEmpty) "rules": [for (var r in rules) r.toJson()],
        if (source.kind != DataKind.typed) "source": source.toJson(),
        if (spotlight.isNotEmpty) "spotlight": spotlight,
        if (spotlight.isNotEmpty) "spotlightColour": spotlightColour.toARGB32(),
        if (gridRows != defaultGridRows) "gridRows": gridRows,
        if (gridColumns != defaultGridColumns) "gridColumns": gridColumns,
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
        ],
        formats: {
          if (j["formats"] case Map f)
            for (var MapEntry(:key, :value) in f.entries)
              if (key is String)
                if (CellFormat.fromJson(value) case var cf?) key: cf,
        },
        columnFormats: {
          if (j["columnFormats"] case Map f)
            for (var MapEntry(:key, :value) in f.entries)
              if (int.tryParse("$key") case var c?)
                if (CellFormat.fromJson(value) case var cf?) c: cf,
        },
        spotlight: j["spotlight"] is String ? j["spotlight"] as String : "",
        spotlightColour: j["spotlightColour"] is int
            ? Color(j["spotlightColour"] as int)
            : const Color(0xFFF2B33D),
        gridRows: j["gridRows"] is int
            ? math.max(1, j["gridRows"] as int)
            : defaultGridRows,
        gridColumns: j["gridColumns"] is int
            ? math.max(1, j["gridColumns"] as int)
            : defaultGridColumns,
        source: j["source"] is Map<String, dynamic>
            ? DataSource.fromJson(j["source"] as Map<String, dynamic>)
            : const DataSource(),
        rules: [
          if (j["rules"] case List rs)
            for (var r in rs)
              if (SheetRule.fromJson(r) case var rule?) rule,
        ]);
  }
}

/// CellFormatKind is how a cell writes its number.
enum CellFormatKind {
  general("General"),
  number("Number 1,234.5"),
  money("Money 1,234.50"),
  percent("Percent 12.5%"),
  short("Short 1.2k"),
  date("Date 15/11/2026"),
  text("Text, as typed");

  final String label;
  const CellFormatKind(this.label);
}

/// CellFormat is a cell's (or a column's) number format: how its number is
/// written, to how many decimals, money with which sign, a date how.
@immutable
class CellFormat {
  final CellFormatKind kind;
  final int? decimals;
  final String symbol;
  final String date;
  const CellFormat(this.kind,
      {this.decimals, this.symbol = r"$", this.date = "dd/mm/yyyy"});

  /// places is how many decimals it writes.
  int get places =>
      decimals ??
      switch (kind) {
        CellFormatKind.money => 2,
        CellFormatKind.percent || CellFormatKind.short => 1,
        _ => 0,
      };

  CellFormat copyWith(
          {CellFormatKind? kind,
          int? decimals,
          bool clearDecimals = false,
          String? symbol,
          String? date}) =>
      CellFormat(kind ?? this.kind,
          decimals: clearDecimals ? null : decimals ?? this.decimals,
          symbol: symbol ?? this.symbol,
          date: date ?? this.date);

  /// write is [v] as this format writes it.
  String write(Object? v) {
    if (v is! double) return sheetText(v);
    var zeros = places > 0 ? ".${"0" * places}" : "";
    return switch (kind) {
      CellFormatKind.general =>
        decimals == null ? generalNumber(v) : textFormat(v, "0$zeros"),
      CellFormatKind.number => textFormat(v, "#,##0$zeros"),
      CellFormatKind.money => v < 0
          ? "-$symbol${textFormat(-v, "#,##0$zeros")}"
          : "$symbol${textFormat(v, "#,##0$zeros")}",
      CellFormatKind.percent => textFormat(v, "0$zeros%"),
      CellFormatKind.short => _short(v, places),
      CellFormatKind.date => textFormat(v, date),
      CellFormatKind.text => generalNumber(v),
    };
  }

  static String _short(double v, int places) {
    var a = v.abs();
    var (d, s) = a >= 1e12
        ? (1e12, "T")
        : a >= 1e9
            ? (1e9, "B")
            : a >= 1e6
                ? (1e6, "M")
                : a >= 1e3
                    ? (1e3, "k")
                    : (1.0, "");
    var zeros = s.isEmpty ? "" : (places > 0 ? ".${"0" * places}" : "");
    return "${textFormat(v / d, "0$zeros")}$s";
  }

  Map<String, dynamic> toJson() => {
        "kind": kind.name,
        if (decimals != null) "decimals": decimals,
        if (kind == CellFormatKind.money) "symbol": symbol,
        if (kind == CellFormatKind.date) "date": date,
      };

  static CellFormat? fromJson(Object? j) {
    if (j is! Map) return null;
    var kind = CellFormatKind.values.asNameMap()[j["kind"]];
    if (kind == null) return null;
    return CellFormat(kind,
        decimals: j["decimals"] is num ? (j["decimals"] as num).toInt() : null,
        symbol: j["symbol"] is String ? j["symbol"] as String : r"$",
        date: j["date"] is String ? j["date"] as String : "dd/mm/yyyy");
  }

  @override
  bool operator ==(Object other) =>
      other is CellFormat &&
      other.kind == kind &&
      other.decimals == decimals &&
      other.symbol == symbol &&
      other.date == date;
  @override
  int get hashCode => Object.hash(kind, decimals, symbol, date);
}

/// sheetText is a value as General writes it.
String sheetText(Object? v) => switch (v) {
      null => "",
      double d => generalNumber(d),
      bool b => b ? "TRUE" : "FALSE",
      SheetError e => e.code,
      _ => "$v",
    };

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

/// _calcs are each sheet's worked-out values, kept with it: a sheet never
/// changes, so what its formulas come to doesn't either.
final Expando<_SheetCalc> _calcs = Expando();

class _SheetCalc {
  final DataSheet sheet;
  final Map<int, Object?> _done = {};
  final Set<int> _working = {};
  _SheetCalc(this.sheet);

  Object? value(int r, int c) {
    var key = r * 100000 + c;
    if (_done.containsKey(key)) return _done[key];
    var raw = sheet.raw(r, c);
    Object? v;
    if (raw.startsWith("=") && raw.length > 1) {
      if (!_working.add(key)) return SheetError.cycle;
      try {
        var node = parseFormula(raw.substring(1));
        v = node == null ? SheetError.syntax : evaluateFormula(node, value);
      } finally {
        _working.remove(key);
      }
    } else {
      v = typedValue(raw);
    }
    _done[key] = v;
    return v;
  }
}

/// typedValue is what typed text [raw] is: a number where it reads as one
/// ("1,240", "+4%" -- read as tables and charts always read them), nothing
/// where it is empty, and otherwise the text ("'" in front keeps it text).
Object? typedValue(String raw) {
  if (raw.isEmpty) return null;
  if (raw.startsWith("'")) return raw.substring(1);
  return cellNumber(raw) ?? raw;
}

/// sheetValue is the value of cell [r], [c] of [sheet]: a number, text,
/// TRUE/FALSE, an error or null; a formula's worked out.
Object? sheetValue(DataSheet sheet, int r, int c) =>
    (_calcs[sheet] ??= _SheetCalc(sheet)).value(r, c);

/// sheetShown is what cell [r], [c] of [sheet] shows: what was typed, as
/// it was typed, unless a formula works it out or a format writes it.
String sheetShown(DataSheet sheet, int r, int c) {
  var raw = sheet.raw(r, c);
  var format = sheet.formatAt(r, c);
  if (!raw.startsWith("=") &&
      (format == null || format.kind == CellFormatKind.text)) {
    return raw.startsWith("'") ? raw.substring(1) : raw;
  }
  var v = sheetValue(sheet, r, c);
  return format == null ? sheetText(v) : format.write(v);
}

/// sheetBlock is what [range] of [sheet] shows, a row of strings per row.
List<List<String>> sheetBlock(DataSheet sheet, CellRange range) => [
      for (var r = range.r0; r <= range.r1; r++)
        [for (var c = range.c0; c <= range.c1; c++) sheetShown(sheet, r, c)],
    ];

// ---------- Colour rules ----------

/// SheetRuleKind is what a colour rule does.
enum SheetRuleKind {
  bars("Data bars"),
  scale("Colour scale"),
  above("Above"),
  below("Below"),
  top("Top"),
  equal("Equal to");

  final String label;
  const SheetRuleKind(this.label);
}

/// SheetRule is a colour rule over [range]: data bars in [colour]; a scale
/// from [low] to [high]; or [colour] behind the cells above or below
/// [value] (the average, empty), among the top [value], or equal to it.
@immutable
class SheetRule {
  final CellRange range;
  final SheetRuleKind kind;
  final Color colour;
  final Color low, high;
  final String value;
  const SheetRule(this.range, this.kind,
      {this.colour = const Color(0xFF2ED6A1),
      this.low = const Color(0xFFF4A6A0),
      this.high = const Color(0xFFA6E6C8),
      this.value = ""});

  SheetRule copyWith({CellRange? range}) => SheetRule(range ?? this.range, kind,
      colour: colour, low: low, high: high, value: value);

  Map<String, dynamic> toJson() => {
        "range": range.a1,
        "kind": kind.name,
        "colour": colour.toARGB32(),
        if (kind == SheetRuleKind.scale) "low": low.toARGB32(),
        if (kind == SheetRuleKind.scale) "high": high.toARGB32(),
        if (value.isNotEmpty) "value": value,
      };

  static SheetRule? fromJson(Object? j) {
    if (j is! Map) return null;
    var range = CellRange.parse("${j["range"] ?? ""}");
    var kind = SheetRuleKind.values.asNameMap()[j["kind"]];
    if (range == null || kind == null) return null;
    Color c(String k, Color or) => j[k] is int ? Color(j[k] as int) : or;
    const plain = SheetRule(CellRange(0, 0, 0, 0), SheetRuleKind.bars);
    return SheetRule(range, kind,
        colour: c("colour", plain.colour),
        low: c("low", plain.low),
        high: c("high", plain.high),
        value: j["value"] is String ? j["value"] as String : "");
  }

  @override
  bool operator ==(Object other) =>
      other is SheetRule &&
      other.range == range &&
      other.kind == kind &&
      other.colour == colour &&
      other.low == low &&
      other.high == high &&
      other.value == value;
  @override
  int get hashCode => Object.hash(range, kind, colour, low, high, value);
}

/// SheetCellLook is what a sheet's colour rules make of one cell: a colour
/// behind it, a bar along it (how far, 0 to 1, and its colour).
@immutable
class SheetCellLook {
  final Color? fill;
  final double? bar;
  final Color barColour;
  const SheetCellLook(
      {this.fill, this.bar, this.barColour = const Color(0xFF2ED6A1)});

  @override
  bool operator ==(Object other) =>
      other is SheetCellLook &&
      other.fill == fill &&
      other.bar == bar &&
      other.barColour == barColour;
  @override
  int get hashCode => Object.hash(fill, bar, barColour);
}

/// sheetLook is what [sheet]'s colour rules make of cell [r], [c]: null
/// where none of them says anything. A later rule over an earlier.
SheetCellLook? sheetLook(DataSheet sheet, int r, int c) {
  if (sheet.rules.isEmpty) return null;
  var v = sheetValue(sheet, r, c);
  if (v is! double && v is! String) return null;
  Color? fill;
  double? bar;
  var barColour = const Color(0xFF2ED6A1);
  for (var rule in sheet.rules) {
    if (!rule.range.contains(r, c)) continue;
    if (rule.kind == SheetRuleKind.equal) {
      if (criterionMatches(v, rule.value.isEmpty ? "" : "=${rule.value}")) {
        fill = rule.colour;
      }
      continue;
    }
    if (v is! double) continue;
    var all = _ruleNumbers(sheet, rule.range);
    if (all.isEmpty) continue;
    var lo = all.first, hi = all.last;
    switch (rule.kind) {
      case SheetRuleKind.bars:
        var base = math.min(0.0, lo);
        bar = hi == base ? 1 : ((v - base) / (hi - base)).clamp(0.0, 1.0);
        barColour = rule.colour;
      case SheetRuleKind.scale:
        var t = hi == lo ? 0.5 : (v - lo) / (hi - lo);
        fill = Color.lerp(rule.low, rule.high, t);
      case SheetRuleKind.above || SheetRuleKind.below:
        var at = cellNumber(rule.value) ??
            all.fold<double>(0, (a, b) => a + b) / all.length;
        if (rule.kind == SheetRuleKind.above ? v > at : v < at) {
          fill = rule.colour;
        }
      case SheetRuleKind.top:
        var n = (cellNumber(rule.value) ?? 3).round().clamp(1, all.length);
        if (v >= all[all.length - n]) fill = rule.colour;
      case SheetRuleKind.equal:
        break;
    }
  }
  return fill == null && bar == null
      ? null
      : SheetCellLook(fill: fill, bar: bar, barColour: barColour);
}

final Expando<Map<CellRange, List<double>>> _ruleNumbersOf = Expando();

/// _ruleNumbers is the numbers in [range] of [sheet], smallest first.
List<double> _ruleNumbers(DataSheet sheet, CellRange range) =>
    (_ruleNumbersOf[sheet] ??= {}).putIfAbsent(range, () {
      var out = <double>[];
      for (var r = range.r0; r <= math.min(range.r1, sheet.rowCount - 1); r++) {
        for (var c = range.c0; c <= range.c1; c++) {
          if (sheetValue(sheet, r, c) case double v) out.add(v);
        }
      }
      return out..sort();
    });

/// viewRows is the sheet rows view [link] shows of [sheet] under its
/// headings, in order: filtered by its [SheetLink.where], sorted by its
/// column, cut to its top.
List<int> viewRows(DataSheet sheet, SheetLink link) {
  var g = link.range;
  var rows = [for (var r = g.r0 + 1; r <= g.r1; r++) r];
  if (link.plain) return rows;
  if (link.whereColumn >= 0 && link.where.trim().isNotEmpty) {
    rows = [
      for (var r in rows)
        if (criterionMatches(
            sheetValue(sheet, r, g.c0 + link.whereColumn), link.where.trim()))
          r
    ];
  }
  if (link.sortBy >= 0) {
    var c = g.c0 + link.sortBy;
    var keyed = [for (var (i, r) in rows.indexed) (i, r)];
    bool blank(Object? v) => v == null || v == "";
    keyed.sort((a, b) {
      var x = sheetValue(sheet, a.$2, c), y = sheetValue(sheet, b.$2, c);
      if (blank(x) || blank(y)) {
        var d = blank(x) == blank(y) ? 0 : (blank(x) ? 1 : -1);
        return d != 0 ? d : a.$1.compareTo(b.$1);
      }
      var d = compareValues(x, y);
      if (link.descending) d = -d;
      return d != 0 ? d : a.$1.compareTo(b.$1);
    });
    rows = [for (var (_, r) in keyed) r];
  }
  if (link.top > 0 && rows.length > link.top) rows = rows.sublist(0, link.top);
  return rows;
}
