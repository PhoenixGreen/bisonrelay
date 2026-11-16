import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/sheet_formula.dart';
import 'package:flutter/foundation.dart' show listEquals;

// data_sync.dart keeps every Data element -- a table or a chart -- in step
// with the sheet it views (data_sheet.dart), whichever side changed:
//
// - A sheet changed (in the Data Studio): every view of it is made again
//   from it, in every scene, on the master and in the Cast.
// - A view changed its own data (a cell typed on the stage, its data
//   editor, a refresh from its source): what it changed is written into the
//   sheet, and so reaches every other view of it.
// - A table or chart with no sheet (an old canvas, one pasted from another
//   canvas, a new one): it is given a sheet of its own made from its data.
//
// Ken, 2026-11-15: a chart kept its own copy of a table's numbers, so typing
// in the table didn't change the chart; one set of numbers ends that.

/// linkOf is [e]'s view of a sheet, if it is a Data element with one.
SheetLink? linkOf(CanvasElement e) => switch (e) {
      TableElement t => t.sheet,
      ChartElement c => c.sheet,
      _ => null,
    };

bool isDataView(CanvasElement e) => e is TableElement || e is ChartElement;

/// withLink is [e] viewing [link].
CanvasElement withLink(CanvasElement e, SheetLink link) => switch (e) {
      TableElement t => t.copyWith(sheet: link),
      ChartElement c => c.copyWith(sheet: link),
      _ => e,
    };

/// numText is [v] as a sheet holds a typed number: no ".0" on a whole one;
/// a gap (NaN) an empty cell.
String numText(double v) {
  if (v.isNaN) return "";
  if (v.isInfinite) return v > 0 ? "∞" : "-∞";
  if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
  return v.toString();
}

/// viewFromSheet is [e] made from its sheet: [e] itself, untouched, when it
/// already shows what the sheet says.
CanvasElement viewFromSheet(CanvasElement e, DataSheet sheet) {
  var link = linkOf(e);
  if (link == null) return e;
  if (e is TableElement) {
    var g = link.range;
    var order = [g.r0, ...viewRows(sheet, link)];
    var block = [
      for (var r in order)
        [for (var c = g.c0; c <= g.c1; c++) sheetShown(sheet, r, c)],
    ];
    var looks = <List<SheetCellLook?>>[];
    if (sheet.rules.isNotEmpty || sheet.spotlight.isNotEmpty) {
      looks = [
        for (var r in order)
          [
            for (var c = g.c0; c <= g.c1; c++)
              r == g.r0 ? null : _spotlit(sheet, r, g) ?? sheetLook(sheet, r, c)
          ],
      ];
      if (looks.every((row) => row.every((l) => l == null))) looks = const [];
    }
    if (sameGrid(e.rows, block) && _sameLooks(e.sheetLooks, looks)) return e;
    return e.copyWith(rows: block, sheetLooks: looks);
  }
  if (e is ChartElement) {
    var data = chartDataOf(sheet, link, e.data, type: e.type, highlights: [
      ...e.highlights,
      if (sheet.spotlight.isNotEmpty)
        ChartHighlight(
            who: sheet.spotlight, colour: sheet.spotlightColour, named: true),
    ]);
    return sameData(e.data, data) && listEquals(e.data.marks, data.marks)
        ? e
        : e.copyWith(data: data);
  }
  return e;
}

/// chartDataOf is the chart [link]'s range of [sheet] makes (its first
/// row the headings): labelled by column [SheetLink.labels] as the sheet
/// shows it, a series from each of [SheetLink.series] read from the cells'
/// values (so "\$14.20" and a formula are numbers). Each series keeps how
/// [was]'s one in its place looked; a blank or a word is a gap.
ChartData chartDataOf(DataSheet sheet, SheetLink link, ChartData was,
    {ChartType type = ChartType.bar,
    List<ChartHighlight> highlights = const []}) {
  var (data, valuesOf) = link.charted
      ? _chartedData(sheet, link, was, type)
      : (
          _plainData(sheet, link, was),
          (int col) {
            var g = link.range;
            return [
              for (var r in viewRows(sheet, link))
                switch (sheetValue(sheet, r, g.c0 + col)) {
                  double v => v,
                  _ => double.nan,
                }
            ];
          }
        );
  if (!highlights.any((h) => !h.off) || data.series.isEmpty) return data;
  var first = link.series.isEmpty ? -1 : link.series.first;
  List<double> by(int col) => valuesOf(col < 0 ? first : col);
  // A line each (colour by words): the highlights pick out lines, ranked by
  // where each ends.
  if (data.categories.isNotEmpty &&
      data.series.length > 1 &&
      link.colourBy >= 0 &&
      (type == ChartType.line || type == ChartType.area)) {
    var names = [for (var s in data.series) s.name];
    List<double> ends(int col) => [
          for (var s in data.series)
            s.values.lastWhere((v) => !v.isNaN, orElse: () => double.nan)
        ];
    var lit = marksOf(highlights, names, ends, (i) => data.series[i].color);
    return data.copyWith(series: [
      for (var (i, s) in data.series.indexed)
        lit[i] == null ? s : s.copyWith(color: lit[i]),
    ]);
  }
  var lit = marksOf(highlights, data.categories, by,
      (i) => data.markAt(i) ?? data.series.first.color);
  return data.copyWith(marks: [
    for (var i = 0; i < data.categories.length; i++) lit[i] ?? data.markAt(i),
  ]);
}

ChartData _plainData(DataSheet sheet, SheetLink link, ChartData was) {
  var g = link.range;
  var rows = viewRows(sheet, link);
  var series = <ChartSeries>[
    for (var (i, p) in link.series.indexed)
      () {
        var c = g.c0 + p;
        var name = sheetShown(sheet, g.r0, c);
        var values = [
          for (var r in rows)
            switch (sheetValue(sheet, r, c)) {
              double v => v,
              _ => double.nan,
            }
        ];
        return i < was.series.length
            ? was.series[i].copyWith(name: name, values: values)
            : ChartSeries(
                name: name,
                color: chartPalette[i % chartPalette.length],
                values: values);
      }(),
  ];
  var est = was.estimated;
  return ChartData(
    categories: [for (var r in rows) sheetShown(sheet, r, g.c0 + link.labels)],
    series: series,
    estimated: est.isEmpty
        ? const []
        : [for (var i = 0; i < rows.length; i++) i < est.length && est[i]],
  );
}

bool _sameLooks(List<List<SheetCellLook?>> a, List<List<SheetCellLook?>> b) {
  if (a.length != b.length) return false;
  for (var r = 0; r < a.length; r++) {
    if (a[r].length != b[r].length) return false;
    for (var c = 0; c < a[r].length; c++) {
      if (a[r][c] != b[r][c]) return false;
    }
  }
  return true;
}

/// sameGrid is whether [a] and [b] read the same, a missing cell empty.
bool sameGrid(List<List<String>> a, List<List<String>> b) {
  var rows = math.max(a.length, b.length);
  for (var r = 0; r < rows; r++) {
    var x = r < a.length ? a[r] : const <String>[];
    var y = r < b.length ? b[r] : const <String>[];
    for (var c = 0; c < math.max(x.length, y.length); c++) {
      if ((c < x.length ? x[c] : "") != (c < y.length ? y[c] : "")) {
        return false;
      }
    }
  }
  return true;
}

/// sameData is whether two charts' data draw the same numbers and labels.
bool sameData(ChartData a, ChartData b) {
  if (a.categories.length != b.categories.length ||
      a.series.length != b.series.length) {
    return false;
  }
  for (var i = 0; i < a.categories.length; i++) {
    if (a.categories[i] != b.categories[i]) return false;
  }
  for (var s = 0; s < a.series.length; s++) {
    var x = a.series[s], y = b.series[s];
    if (x.name != y.name || x.values.length != y.values.length) return false;
    for (var i = 0; i < x.values.length; i++) {
      var p = x.values[i], q = y.values[i];
      if (!(p == q || (p.isNaN && q.isNaN))) return false;
    }
  }
  return true;
}

/// sheetWithView is [sheet] with what view [e] shows written into it -- only
/// the cells that read differently, so a formula or a typed "1,240" that
/// still reads the same is kept -- and the range it views now, grown or
/// shrunk to what it holds.
(DataSheet, SheetLink) sheetWithView(DataSheet sheet, CanvasElement e) {
  var link = linkOf(e)!;
  var range = link.range;
  if (!link.plain) return (_mappedBack(sheet, e, link), link);
  if (e is TableElement) {
    var rows = e.rows;
    var cols = math.max(1, e.columnCount);
    var block = [
      for (var r = 0; r < math.max(1, rows.length); r++)
        [
          for (var c = 0; c < cols; c++)
            () {
              var want =
                  r < rows.length && c < rows[r].length ? rows[r][c] : "";
              var sr = range.r0 + r, sc = range.c0 + c;
              return sheetShown(sheet, sr, sc) == want
                  ? sheet.raw(sr, sc)
                  : want;
            }(),
        ],
    ];
    var next = CellRange.of(block.length, cols, r0: range.r0, c0: range.c0);
    return (
      sheet.withBlock(range.r0, range.c0, block, clear: range),
      link.copyWith(range: next)
    );
  }
  if (e is ChartElement) {
    var data = e.data;
    var series = [...link.series];
    // More series than columns: each new one takes the next column past
    // the range. Fewer: the link lets go of the last ones; the cells stay.
    var width = range.cols;
    while (series.length < data.series.length) {
      series.add(width++);
    }
    if (series.length > data.series.length) {
      series = series.sublist(0, data.series.length);
    }
    var height = 1 + data.categories.length;
    var block = [
      for (var r = 0; r < height; r++)
        [for (var c = 0; c < width; c++) sheet.raw(range.r0 + r, range.c0 + c)],
    ];
    void want(int r, int c, String text, {double? number}) {
      var sr = range.r0 + r, sc = range.c0 + c;
      var same = number != null
          ? switch (sheetValue(sheet, sr, sc)) {
              double v => v == number,
              null => number.isNaN,
              _ => false,
            }
          : sheetShown(sheet, sr, sc) == text;
      if (!same) block[r][c] = text;
    }

    for (var (i, s) in data.series.indexed) {
      want(0, series[i], s.name);
      for (var r = 0; r < data.categories.length; r++) {
        var v = r < s.values.length ? s.values[r] : double.nan;
        want(1 + r, series[i], numText(v), number: v);
      }
    }
    for (var r = 0; r < data.categories.length; r++) {
      want(1 + r, link.labels, data.categories[r]);
    }
    var next = CellRange.of(height, width, r0: range.r0, c0: range.c0);
    return (
      sheet.withBlock(range.r0, range.c0, block, clear: range),
      link.copyWith(range: next, series: series)
    );
  }
  return (sheet, link);
}

/// _mappedBack is [sheet] with what view [e] -- which shows its rows its
/// own way (sorted, filtered, cut to its top) -- changed written into the
/// rows each of its rows shows. Its range stays: rows it gained or lost
/// can't be placed in the sheet from here.
DataSheet _mappedBack(DataSheet sheet, CanvasElement e, SheetLink link) {
  var g = link.range;
  var order = [g.r0, ...viewRows(sheet, link)];
  var out = sheet;
  void put(int r, int c, String text, {double? number}) {
    var same = number != null
        ? switch (sheetValue(sheet, r, c)) {
            double v => v == number,
            null => number.isNaN,
            _ => false,
          }
        : sheetShown(sheet, r, c) == text;
    if (!same) out = out.withCell(r, c, text);
  }

  if (e is TableElement) {
    for (var (i, r) in order.indexed) {
      if (i >= e.rows.length) break;
      for (var c = 0; c < g.cols && c < e.rows[i].length; c++) {
        put(r, g.c0 + c, e.rows[i][c]);
      }
    }
  } else if (e is ChartElement) {
    var data = e.data;
    for (var (i, col) in link.series.indexed) {
      if (i >= data.series.length) break;
      put(g.r0, g.c0 + col, data.series[i].name);
      for (var (k, r) in order.skip(1).indexed) {
        if (k >= data.series[i].values.length) break;
        var v = data.series[i].values[k];
        put(r, g.c0 + col, numText(v), number: v);
      }
    }
    for (var (k, r) in order.skip(1).indexed) {
      if (k < data.categories.length)
        put(r, g.c0 + link.labels, data.categories[k]);
    }
  }
  return out;
}

/// _mapViews is [doc] with [f] applied to every element everywhere -- this
/// scene, the others, the master and the Cast -- the lists nothing changed
/// in left as they were.
CanvasDocument _mapViews(
    CanvasDocument doc, CanvasElement Function(CanvasElement e) f) {
  List<CanvasElement> mapped(List<CanvasElement> list) {
    List<CanvasElement>? out;
    for (var (i, e) in list.indexed) {
      var n = isDataView(e) ? f(e) : e;
      if (!identical(n, e)) (out ??= [...list])[i] = n;
    }
    return out ?? list;
  }

  var out = doc;
  var here = mapped(doc.elements);
  if (!identical(here, doc.elements)) out = out.copyWith(elements: here);
  for (var (i, scene) in doc.allScenes.indexed) {
    if (!doc.editingMaster && i == doc.at) continue;
    var list = mapped(scene.elements);
    if (!identical(list, scene.elements)) {
      out = out.withScene(i, scene.copyWith(elements: list));
    }
  }
  if (doc.master case var master? when !doc.editingMaster) {
    var list = mapped(master.elements);
    if (!identical(list, master.elements)) {
      out = out.copyWith(master: master.copyWith(elements: list));
    }
  }
  var cast = mapped(doc.cast);
  if (!identical(cast, doc.cast)) out = out.copyWith(cast: cast);
  return out;
}

/// _allViews is every Data element everywhere in [doc].
Iterable<CanvasElement> _allViews(CanvasDocument doc) sync* {
  yield* doc.elements.where(isDataView);
  for (var (i, scene) in doc.allScenes.indexed) {
    if (!doc.editingMaster && i == doc.at) continue;
    yield* scene.elements.where(isDataView);
  }
  if (doc.master case var master? when !doc.editingMaster) {
    yield* master.elements.where(isDataView);
  }
  yield* doc.cast.where(isDataView);
}

/// viewsOf is every Data element in [doc] that views sheet [id].
List<CanvasElement> viewsOf(CanvasDocument doc, String id) => [
      for (var e in _allViews(doc))
        if (linkOf(e)?.sheet == id) e
    ];

/// dataAdopted is [doc] with every table and chart that has no sheet -- or
/// names one it doesn't have -- given one made from its own data. A chart
/// that read a table (the old TableLink) views that table's sheet instead.
/// [doc] itself when there is nothing to do.
CanvasDocument dataAdopted(CanvasDocument doc) {
  var have = {for (var s in doc.sheets) s.id};
  var orphans = [
    for (var e in _allViews(doc))
      if (linkOf(e) case var link
          when link == null || !have.contains(link.sheet))
        e,
  ];
  if (orphans.isEmpty) return doc;

  var sheets = [...doc.sheets];
  var names = {for (var s in sheets) s.name};
  var made = <String, SheetLink>{};
  String freeId(String want) {
    var id = want;
    for (var n = 2; have.contains(id); n++) {
      id = "$want-$n";
    }
    have.add(id);
    return id;
  }

  String freeName(String want) {
    var name = want;
    for (var n = 2; names.contains(name); n++) {
      name = "$want $n";
    }
    names.add(name);
    return name;
  }

  SheetLink adopt(CanvasElement e, List<List<String>> cells,
      {int labels = 0, List<int> series = const []}) {
    var wanted = linkOf(e)?.sheet ?? "";
    // A view pasted with others of its sheet: the first brings the sheet,
    // the rest find it.
    if (wanted.isNotEmpty && made.containsKey("#$wanted")) {
      return made["#$wanted"]!.copyWith(labels: labels, series: series);
    }
    var id = freeId(wanted.isNotEmpty ? wanted : "sheet-${e.id}");
    var name = freeName(e.base.name.trim().isNotEmpty
        ? e.base.name.trim()
        : (e is ChartElement ? "Chart" : "Table"));
    sheets.add(DataSheet(id: id, name: name, cells: cells));
    var cols = cells.fold(1, (n, r) => math.max(n, r.length));
    var link = SheetLink(id, CellRange.of(cells.length, cols),
        labels: labels, series: series);
    if (wanted.isNotEmpty) made["#$wanted"] = link;
    return link;
  }

  // Tables first, so a chart that read one can view its sheet.
  for (var e in orphans.whereType<TableElement>()) {
    var rows = e.rows.isEmpty
        ? const [
            [""]
          ]
        : e.rows;
    made[e.id] = adopt(e, [
      for (var r in rows) [...r]
    ]);
  }
  for (var e in orphans.whereType<ChartElement>()) {
    var from = e.fromTable;
    var table = from.tableId.isEmpty
        ? null
        : made[from.tableId] ??
            _allViews(doc)
                .whereType<TableElement>()
                .where((t) => t.id == from.tableId && t.sheet != null)
                .map((t) => t.sheet)
                .firstOrNull;
    if (table != null && from.valueColumns.isNotEmpty) {
      made[e.id] = table.copyWith(
          labels: from.categoryColumn, series: [...from.valueColumns]);
      continue;
    }
    var d = e.data;
    var header = [
      e.xAxisLabel,
      for (var s in d.series) s.name,
    ];
    var body = [
      for (var (i, c) in d.categories.indexed)
        [
          c,
          for (var s in d.series)
            numText(i < s.values.length ? s.values[i] : double.nan),
        ],
    ];
    made[e.id] = adopt(e, [header, ...body],
        labels: 0, series: [for (var i = 0; i < d.series.length; i++) i + 1]);
  }

  var next = doc.copyWith(sheets: sheets);
  var byId = {for (var s in sheets) s.id: s};
  return _mapViews(next, (e) {
    var link = made[e.id];
    if (link == null) return e;
    var linked = withLink(e, link);
    if (linked is ChartElement && linked.fromTable.tableId.isNotEmpty) {
      linked = linked.copyWith(fromTable: const TableLink());
    }
    return viewFromSheet(linked, byId[link.sheet]!);
  });
}

/// dataRefreshed is [doc] with every view made from its sheet as it opens:
/// what isn't kept in the file (a table's colour-rule looks) made again,
/// and nothing touched that already agrees.
CanvasDocument dataRefreshed(CanvasDocument doc) {
  if (doc.sheets.isEmpty) return doc;
  var sheets = {for (var s in doc.sheets) s.id: s};
  return _mapViews(doc, (e) {
    var sheet = sheets[linkOf(e)?.sheet];
    return sheet == null ? e : viewFromSheet(e, sheet);
  });
}

/// dataSynced is [next] -- a change from [was] -- with its sheets and every
/// view of them in step (see the top of this file). [next] itself when it
/// changed no data.
CanvasDocument dataSynced(CanvasDocument was, CanvasDocument next) {
  if (identical(was.sheets, next.sheets) &&
      identical(was.elements, next.elements)) {
    return next;
  }
  var sheets = {for (var s in next.sheets) s.id: s};
  var before = {for (var e in was.elements) e.id: e};
  var changed = <String>{
    // Sheets changed themselves (the Data Studio).
    for (var s in next.sheets)
      if (!identical(was.sheets.where((w) => w.id == s.id).firstOrNull, s))
        s.id,
  };
  var relinked = <String, SheetLink>{};
  var remake = <String>{};
  var orphan = false;

  for (var e in next.elements) {
    if (!isDataView(e)) continue;
    var link = linkOf(e);
    if (link == null || !sheets.containsKey(link.sheet)) {
      orphan = true;
      continue;
    }
    var old = before[e.id];
    if (identical(old, e)) continue;
    // Shown from somewhere else now (another range, sheet or column): made
    // from the sheet, not written into it.
    if (old == null || linkOf(old) != link || old.kind != e.kind) {
      remake.add(e.id);
      continue;
    }
    // Its highlights or its type changed: its marks, and a line per word,
    // are made again from the sheet.
    if (e is ChartElement &&
        old is ChartElement &&
        (!listEquals(old.highlights, e.highlights) || old.type != e.type)) {
      remake.add(e.id);
      continue;
    }
    // A chart reading its rows as only a chart can (grouped, one date at a
    // time) holds no cells of the sheet to write back.
    if (link.charted) continue;
    var sheet = sheets[link.sheet]!;
    if (changed.contains(link.sheet)) continue;
    if (identical(viewFromSheet(e, sheet), e)) continue;
    // Its own data changed: into the sheet with it.
    var (written, now) = sheetWithView(sheet, e);
    sheets[link.sheet] = written;
    changed.add(link.sheet);
    if (now != link) relinked[e.id] = now;
  }

  var out = next;
  if (orphan) {
    out = dataAdopted(out);
    for (var s in out.sheets) {
      sheets.putIfAbsent(s.id, () => s);
    }
  }
  if (changed.isEmpty && remake.isEmpty) return out;
  out = out.copyWith(sheets: [
    for (var s in out.sheets) sheets[s.id] ?? s,
  ]);
  return _mapViews(out, (e) {
    var link = relinked[e.id] ?? linkOf(e);
    if (link == null) return e;
    if (!changed.contains(link.sheet) && !remake.contains(e.id)) return e;
    var sheet = sheets[link.sheet];
    if (sheet == null) return e;
    var linked = relinked.containsKey(e.id) ? withLink(e, link) : e;
    return viewFromSheet(linked, sheet);
  });
}

/// chartColumnsOf is which columns of [range] of [sheet] (its first row
/// the headings) a chart of it is labelled by -- the first that isn't
/// numbers -- and draws: every column of numbers but that one.
(int, List<int>) chartColumnsOf(DataSheet sheet, CellRange range) {
  var cols = range.cols;
  bool numbers(int c) {
    var seen = 0, ok = 0;
    for (var r = range.r0 + 1; r <= range.r1; r++) {
      var v = sheetValue(sheet, r, range.c0 + c);
      if (v == null || v == "") continue;
      seen++;
      if (v is double) ok++;
    }
    return seen > 0 && ok * 5 >= seen * 4;
  }

  var labels = 0;
  for (var c = 0; c < cols; c++) {
    if (!numbers(c)) {
      labels = c;
      break;
    }
  }
  var series = [
    for (var c = 0; c < cols; c++)
      if (c != labels && numbers(c)) c,
  ];
  if (series.isEmpty && cols > 1) series = [labels == cols - 1 ? 0 : cols - 1];
  return (labels, series);
}

// ---------- Rows and columns put in and taken out ----------
//
// As in Calc: a view's range moves with the cells it shows, grows when rows
// or columns go in inside it and shrinks when they come out, and a chart's
// label and series columns follow their columns (Ken, 2026-11-15: moving or
// deleting a table's column broke the chart reading it).

/// _withSheet is [doc] with [sheet] in place of the one of its id, and every
/// view of it relinked by [relink].
CanvasDocument _withSheet(CanvasDocument doc, DataSheet sheet,
    SheetLink Function(SheetLink link) relink) {
  var out = doc.copyWith(sheets: [
    for (var s in doc.sheets) s.id == sheet.id ? sheet : s,
  ]);
  return _mapViews(out, (e) {
    var link = linkOf(e);
    if (link == null || link.sheet != sheet.id) return e;
    var next = relink(link);
    return next == link ? e : withLink(e, next);
  });
}

DataSheet? _sheetIn(CanvasDocument doc, String id) =>
    doc.sheets.where((s) => s.id == id).firstOrNull;

/// _moved is [s] -- its cells already moved into [cells] -- with every
/// formula's references and every cell's format following the [n] rows
/// (or [columns]) put in before [at] or taken out from it.
DataSheet _moved(DataSheet s, List<List<String>> cells, int at, int n,
    {bool columns = false}) {
  var fixed = [
    for (var row in cells)
      [
        for (var v in row)
          v.startsWith("=") ? movedFormula(v, at, n, columns: columns) : v
      ],
  ];
  int? to(int x) {
    if (n > 0) return x >= at ? x + n : x;
    if (x >= at && x < at - n) return null;
    return x >= at - n ? x + n : x;
  }

  var formats = <String, CellFormat>{
    for (var MapEntry(:key, :value) in s.formats.entries)
      if (cellAt(key) case (var r, var c))
        if (columns ? to(c) : to(r) case var m?)
          (columns ? cellName(r, m) : cellName(m, c)): value,
  };
  var columnFormats = columns
      ? <int, CellFormat>{
          for (var MapEntry(:key, :value) in s.columnFormats.entries)
            if (to(key) case var m?) m: value,
        }
      : s.columnFormats;
  // Colour rules' ranges move and grow as views' do.
  var rules = [
    for (var rule in s.rules)
      if (columns
              ? _spanAfter(rule.range.c0, rule.range.c1, at, n)
              : _spanAfter(rule.range.r0, rule.range.r1, at, n)
          case (var a, var b))
        rule.copyWith(
            range: columns
                ? CellRange(rule.range.r0, a, rule.range.r1, b)
                : CellRange(a, rule.range.c0, b, rule.range.c1)),
  ];
  return s.copyWith(
      cells: fixed,
      formats: formats,
      columnFormats: columnFormats,
      rules: rules);
}

/// _spanAfter is span [a]..[b] with [n] put in before [at] (n > 0) or the
/// [-n] at [at] taken out (n < 0); null where all of it was taken out.
(int, int)? _spanAfter(int a, int b, int at, int n) {
  if (n > 0) {
    if (at <= a) return (a + n, b + n);
    if (at <= b) return (a, b + n);
    return (a, b);
  }
  var end = at - n - 1;
  var na = a < at ? a : (a > end ? a + n : at);
  var nb = b < at ? b : (b > end ? b + n : at - 1);
  if (nb < na) return a >= at && b <= end ? null : (na, na);
  return (na, nb);
}

/// rowsInserted is [doc] with [n] empty rows put in sheet [id] before row
/// [at].
CanvasDocument rowsInserted(CanvasDocument doc, String id, int at, int n) {
  var s = _sheetIn(doc, id);
  if (s == null || n <= 0) return doc;
  var cells = [...s.cells];
  if (at < cells.length) {
    cells.insertAll(at, [for (var i = 0; i < n; i++) <String>[]]);
  }
  return _withSheet(doc, _moved(s, cells, at, n), (l) {
    var (r0, r1) = _spanAfter(l.range.r0, l.range.r1, at, n)!;
    return l.copyWith(range: CellRange(r0, l.range.c0, r1, l.range.c1));
  });
}

/// rowsDeleted is [doc] with rows [at] to [at] + [n] - 1 of sheet [id] taken
/// out.
CanvasDocument rowsDeleted(CanvasDocument doc, String id, int at, int n) {
  var s = _sheetIn(doc, id);
  if (s == null || n <= 0) return doc;
  var cells = [
    for (var (r, row) in s.cells.indexed)
      if (r < at || r >= at + n) row,
  ];
  return _withSheet(doc, _moved(s, cells, at, -n), (l) {
    var span = _spanAfter(l.range.r0, l.range.r1, at, -n) ?? (at, at);
    return l.copyWith(
        range: CellRange(span.$1, l.range.c0, span.$2, l.range.c1));
  });
}

/// columnsInserted is [doc] with [n] empty columns put in sheet [id] before
/// column [at].
CanvasDocument columnsInserted(CanvasDocument doc, String id, int at, int n) {
  var s = _sheetIn(doc, id);
  if (s == null || n <= 0) return doc;
  var cells = [
    for (var row in s.cells)
      at < row.length
          ? [
              ...row.sublist(0, at),
              for (var i = 0; i < n; i++) "",
              ...row.sublist(at)
            ]
          : row,
  ];
  return _withSheet(doc, _moved(s, cells, at, n, columns: true), (l) {
    var g = l.range;
    var (c0, c1) = _spanAfter(g.c0, g.c1, at, n)!;
    // Inside the range: the columns past it, counted from its start, move.
    int rel(int p) => g.c0 + p >= at && at > g.c0 ? p + n : p;
    return l.copyWith(
        range: CellRange(g.r0, c0, g.r1, c1),
        labels: rel(l.labels),
        series: [for (var p in l.series) rel(p)]);
  });
}

/// columnsDeleted is [doc] with columns [at] to [at] + [n] - 1 of sheet
/// [id] taken out; a chart's series of them let go, its labels on the
/// first column left if those went.
CanvasDocument columnsDeleted(CanvasDocument doc, String id, int at, int n) {
  var s = _sheetIn(doc, id);
  if (s == null || n <= 0) return doc;
  var cells = [
    for (var row in s.cells)
      [
        for (var (c, v) in row.indexed)
          if (c < at || c >= at + n) v
      ],
  ];
  return _withSheet(doc, _moved(s, cells, at, -n, columns: true), (l) {
    var g = l.range;
    var span = _spanAfter(g.c0, g.c1, at, -n) ?? (at, at);
    // Each column the link names, where it is now, or null if it went.
    int? rel(int p) {
      var a = g.c0 + p;
      if (a >= at && a < at + n) return null;
      return (a < at ? a : a - n) - span.$1;
    }

    return l.copyWith(
        range: CellRange(g.r0, span.$1, g.r1, span.$2),
        labels: rel(l.labels) ?? 0,
        series: [
          for (var p in l.series)
            if (rel(p) case var q?) q
        ]);
  });
}

/// rowsSorted is [doc] with rows [rows] of sheet [id] put in order of
/// column [by] -- numbers by value, before words, blanks last -- smallest
/// first or, with [descending], largest; only columns [rows].c0 to c1
/// move, their formats with them, a formula's references moving as a
/// copied one's do (as Calc sorts).
CanvasDocument rowsSorted(CanvasDocument doc, String id, CellRange rows, int by,
    {bool descending = false}) {
  var s = _sheetIn(doc, id);
  if (s == null || rows.rows < 2) return doc;
  int compare(int a, int b) {
    var x = sheetValue(s, a, by), y = sheetValue(s, b, by);
    bool blank(Object? v) => v == null || v == "";
    if (blank(x) || blank(y)) {
      return blank(x) == blank(y) ? 0 : (blank(x) ? 1 : -1);
    }
    var d = compareValues(x, y);
    return descending ? -d : d;
  }

  // A stable sort: ties keep their order.
  var order = [for (var r = rows.r0; r <= rows.r1; r++) r];
  var keyed = [for (var (i, r) in order.indexed) (i, r)];
  keyed.sort((a, b) {
    var d = compare(a.$2, b.$2);
    return d != 0 ? d : a.$1.compareTo(b.$1);
  });
  var block = [
    for (var (i, (_, r)) in keyed.indexed)
      [
        for (var c = rows.c0; c <= rows.c1; c++)
          shiftedFormula(s.raw(r, c), rows.r0 + i - r, 0)
      ],
  ];
  var formats = {...s.formats};
  for (var (i, (_, r)) in keyed.indexed) {
    for (var c = rows.c0; c <= rows.c1; c++) {
      var f = s.formats[cellName(r, c)];
      var to = cellName(rows.r0 + i, c);
      if (f == null) {
        formats.remove(to);
      } else {
        formats[to] = f;
      }
    }
  }
  var sorted = s.withBlock(rows.r0, rows.c0, block).copyWith(formats: formats);
  return doc.copyWith(sheets: [
    for (var x in doc.sheets) x.id == id ? sorted : x,
  ]);
}

// ---------- The fill handle ----------

const _fillLists = [
  [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December"
  ],
  [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec"
  ],
  [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    "Sunday"
  ],
  ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
];

/// _filled is the [count] cells that carry on after [src] -- one line of
/// a selection, in order -- [step] cells apart (a row or a column) from
/// where each of [src] was: numbers by their step (one alone counting up
/// by 1), names of months and days in order, words ending in a number
/// counting on, and anything else over again, a formula's references
/// moved as a copy's are.
List<String> _filled(List<String> src, int count,
    String Function(String raw, int moved) copied) {
  var n = src.length;
  double? step(List<double> v) =>
      v.length == 1 ? 1 : (v.last - v.first) / (v.length - 1);

  var formulas = src.any((v) => v.startsWith("="));
  var numbers = [for (var v in src) typedValue(v)];
  if (!formulas && numbers.every((v) => v is double)) {
    var v = numbers.cast<double>();
    var d = step(v)!;
    return [
      for (var t = 1; t <= count; t++)
        generalNumber(double.parse((v.last + d * t).toStringAsFixed(10)))
    ];
  }
  if (!formulas) {
    for (var list in _fillLists) {
      var at = [
        for (var v in src)
          list.indexWhere((x) => x.toLowerCase() == v.trim().toLowerCase())
      ];
      if (at.any((i) => i < 0)) continue;
      var d = n == 1 ? 1 : ((at.last - at.first) / (n - 1)).round();
      String styled(String word) {
        var sample = src.last.trim();
        if (sample == sample.toUpperCase()) return word.toUpperCase();
        if (sample == sample.toLowerCase()) return word.toLowerCase();
        return word;
      }

      return [
        for (var t = 1; t <= count; t++)
          styled(list[(at.last + d * t) % list.length])
      ];
    }
    var parts = [for (var v in src) RegExp(r"^(.*?)(\d+)(\D*)$").firstMatch(v)];
    if (parts.every((m) => m != null) &&
        parts.map((m) => "${m!.group(1)}|${m.group(3)}").toSet().length == 1) {
      var head = parts.first!.group(1)!, tail = parts.first!.group(3)!;
      var width = parts.last!.group(2)!.length;
      var v = [for (var m in parts) double.parse(m!.group(2)!)];
      var d = step(v)!;
      return [
        for (var t = 1; t <= count; t++)
          "$head${(v.last + d * t).round().abs().toString().padLeft(width, "0")}$tail"
      ];
    }
  }
  return [
    for (var t = 0; t < count; t++) copied(src[t % n], n + t - t % n),
  ];
}

/// sheetFilled is [sheet] with [from] carried on over [to], which lies
/// below it (the same columns) or to its right (the same rows). Formats
/// come too.
DataSheet sheetFilled(DataSheet sheet, CellRange from, CellRange to) {
  var down = to.r0 > from.r1;
  var formats = {...sheet.formats};
  var block = List.generate(to.rows, (_) => List.filled(to.cols, ""));
  if (down) {
    for (var c = from.c0; c <= from.c1; c++) {
      var src = [for (var r = from.r0; r <= from.r1; r++) sheet.raw(r, c)];
      var out =
          _filled(src, to.rows, (raw, moved) => shiftedFormula(raw, moved, 0));
      for (var t = 0; t < to.rows; t++) {
        block[t][c - to.c0] = out[t];
        var f = sheet.formats[cellName(from.r0 + t % from.rows, c)];
        var at = cellName(to.r0 + t, c);
        f == null ? formats.remove(at) : formats[at] = f;
      }
    }
  } else {
    for (var r = from.r0; r <= from.r1; r++) {
      var src = [for (var c = from.c0; c <= from.c1; c++) sheet.raw(r, c)];
      var out =
          _filled(src, to.cols, (raw, moved) => shiftedFormula(raw, 0, moved));
      for (var t = 0; t < to.cols; t++) {
        block[r - to.r0][t] = out[t];
        var f = sheet.formats[cellName(r, from.c0 + t % from.cols)];
        var at = cellName(r, to.c0 + t);
        f == null ? formats.remove(at) : formats[at] = f;
      }
    }
  }
  return sheet.withBlock(to.r0, to.c0, block).copyWith(formats: formats);
}

/// sourcesAdopted moves each table's data source onto its sheet (Connect
/// data, 2026-11-16: the sheet owns its connection, and every table and
/// chart of it follows one refresh). Only where the table shows its sheet
/// whole from A1 and the sheet has no source of its own; the table's own is
/// cleared, so there is one place it is kept. [doc] itself when there is
/// nothing to move.
CanvasDocument sourcesAdopted(CanvasDocument doc) {
  var moved = <String, DataSource>{};
  var from = <String>{};
  for (var e in _allViews(doc)) {
    if (e is! TableElement || !e.source.on) continue;
    var link = e.sheet;
    if (link == null || !link.plain) continue;
    if (link.range.r0 != 0 || link.range.c0 != 0) continue;
    var sheet = doc.sheets.where((s) => s.id == link.sheet).firstOrNull;
    if (sheet == null || sheet.source.on || moved.containsKey(sheet.id)) {
      continue;
    }
    moved[sheet.id] = e.source;
    from.add(e.id);
  }
  if (moved.isEmpty) return doc;
  var next = doc.copyWith(sheets: [
    for (var s in doc.sheets)
      if (moved[s.id] case var src?) s.copyWith(source: src) else s,
  ]);
  return _mapViews(
      next,
      (e) => e is TableElement && from.contains(e.id)
          ? e.copyWith(source: const DataSource())
          : e);
}

/// sheetFromSource is [sheet] filled with [rows] -- what a refresh brought,
/// header first -- under [source]. The source's columns are written from
/// A1, in place of what the sheet held; columns of the sheet's own past
/// them are kept, matched row by row on the source's match column (else
/// its first), so a note typed beside a team stays with that team. Columns
/// the source marks keep are put back the same way, and with [keepHeads]
/// (a sheet already connected) its own headings over the source's.
DataSheet sheetFromSource(
    DataSheet sheet, List<List<String>> rows, DataSource source,
    {bool keepHeads = false}) {
  var before = sheet.cells;
  var after = keepColumns(before, rows, source);
  if (keepHeads) after = keepHeaders(before, after);
  var width = after.fold(0, (n, r) => math.max(n, r.length));
  var own = before.isEmpty ? 0 : before.first.length - width;
  if (own > 0 && before.first.length > width) {
    var at = source.matchColumn < 0 ? 0 : source.matchColumn;
    String key(List<String> r) =>
        at < r.length ? r[at].trim().toLowerCase() : "";
    var was = {
      for (var r in before.skip(1))
        if (key(r).isNotEmpty) key(r): r
    };
    List<String> rest(List<String>? r) => [
          for (var c = width; c < width + own; c++)
            r != null && c < r.length ? r[c] : ""
        ];
    after = [
      for (var (i, row) in after.indexed)
        [
          ...row,
          ...List.filled(width - row.length, ""),
          ...rest(i == 0 ? before.first : was[key(row)]),
        ]
    ];
  }
  return sheet.copyWith(cells: after, source: source);
}

/// changedCells is every cell that reads differently in [after] than in
/// [before], for a refresh to show what moved.
Set<(int, int)> changedCells(
    List<List<String>> before, List<List<String>> after) {
  String at(List<List<String>> g, int r, int c) =>
      r < g.length && c < g[r].length ? g[r][c] : "";
  var out = <(int, int)>{};
  var rows = math.max(before.length, after.length);
  for (var r = 0; r < rows; r++) {
    var cols = math.max(r < before.length ? before[r].length : 0,
        r < after.length ? after[r].length : 0);
    for (var c = 0; c < cols; c++) {
      if (at(before, r, c) != at(after, r, c)) out.add((r, c));
    }
  }
  return out;
}

/// viewsRegrown is [doc] with every view of sheet [id] that showed the
/// whole of [was] now showing [now]: a refresh that brings more rows (or
/// fewer) is seen whole in the tables and charts that showed it whole.
CanvasDocument viewsRegrown(
        CanvasDocument doc, String id, CellRange was, CellRange now) =>
    was == now
        ? doc
        : _mapViews(doc, (e) {
            var link = linkOf(e);
            if (link == null || link.sheet != id || link.range != was) {
              return e;
            }
            return withLink(e, link.copyWith(range: now));
          });

/// _aggregate is [how] of [values] -- a group's numbers -- gaps left out
/// (count counts the rows).
double _aggregate(String how, List<double> values) {
  if (how == "count") return values.length.toDouble();
  var v = [
    for (var x in values)
      if (!x.isNaN) x
  ];
  if (v.isEmpty) return double.nan;
  return switch (how) {
    "total" => v.fold(0.0, (a, b) => a + b),
    "average" => v.fold(0.0, (a, b) => a + b) / v.length,
    "most" => v.reduce(math.max),
    "least" => v.reduce(math.min),
    _ => v.last,
  };
}

/// placesIn reads "1-3, 16-19" as the places it names.
Set<int> placesIn(String spec) {
  var out = <int>{};
  for (var part in spec.split(",")) {
    var m = RegExp(r"^\s*(\d+)\s*(?:-\s*(\d+))?\s*$").firstMatch(part);
    if (m == null) continue;
    var a = int.parse(m.group(1)!), b = int.parse(m.group(2) ?? m.group(1)!);
    for (var i = math.min(a, b); i <= math.max(a, b) && i - a < 1000; i++) {
      out.add(i);
    }
  }
  return out;
}

/// resultColours are the colours a column of results is given, as a form
/// guide's boxes are: a win green, a draw grey, a loss red.
const Map<String, Color> resultColours = {
  "w": Color(0xFF2FE08A),
  "d": Color(0xFFC9D6EA),
  "l": Color(0xFFE8645A),
};

/// scaleColour is where [v] sits between [lo] and [hi], from red to green.
Color scaleColour(double v, double lo, double hi) {
  var t = hi == lo ? 1.0 : ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
  return Color.lerp(const Color(0xFFE8645A), const Color(0xFF2FE08A), t)!;
}

/// _chartedData is a chart reading its rows as only a chart can (see
/// SheetLink.charted): one date at a time, rows with the same label brought
/// together, a line for each word of a column, places picked, marks
/// coloured by a column. With it, the numbers of any column of the range,
/// one per category, for the highlights to rank.
(ChartData, List<double> Function(int col)) _chartedData(
    DataSheet sheet, SheetLink link, ChartData was, ChartType type) {
  var g = link.range;
  String shown(int r, int col) => sheetShown(sheet, r, g.c0 + col);
  double number(int r, int col) => switch (sheetValue(sheet, r, g.c0 + col)) {
        double v => v,
        _ => double.nan,
      };
  var rows = viewRows(
      sheet,
      SheetLink(link.sheet, g,
          whereColumn: link.whereColumn, where: link.where));
  bool words(int col) {
    var seen = 0, text = 0;
    for (var r in rows) {
      var v = sheetValue(sheet, r, g.c0 + col);
      if (v == null || v == "") continue;
      seen++;
      if (v is! double) text++;
    }
    return seen > 0 && text * 2 >= seen;
  }

  // One date at a time: the one asked for, else the last.
  if (link.through >= 0 && link.through < g.cols) {
    var dates = <String>[];
    for (var r in rows) {
      var d = shown(r, link.through);
      if (!dates.contains(d)) dates.add(d);
    }
    var at = dates.contains(link.at) ? link.at : dates.lastOrNull ?? "";
    rows = [
      for (var r in rows)
        if (shown(r, link.through) == at) r
    ];
  }

  var colourBy =
      link.colourBy >= 0 && link.colourBy < g.cols ? link.colourBy : -1;
  var lines = colourBy >= 0 &&
      words(colourBy) &&
      (type == ChartType.line || type == ChartType.area);
  var keys = <String>[], subs = <String>[];
  var groups = <String, List<int>>{};
  for (var r in rows) {
    var k = shown(r, link.labels);
    var sub = lines ? shown(r, colourBy) : "";
    if (!keys.contains(k)) keys.add(k);
    if (lines && !subs.contains(sub)) subs.add(sub);
    (groups["$k\u0000$sub"] ??= []).add(r);
  }
  double valueOf(List<int> rs, int col) {
    var v = [for (var r in rs) number(r, col)];
    if (link.group.isEmpty) return v.isEmpty ? double.nan : v.last;
    return _aggregate(link.group, v);
  }

  if (lines) {
    var col = link.series.isEmpty ? -1 : link.series.first;
    var series = [
      for (var (i, sub) in subs.indexed)
        () {
          var values = [
            for (var k in keys)
              col < 0 || groups["$k\u0000$sub"] == null
                  ? double.nan
                  : valueOf(groups["$k\u0000$sub"]!, col)
          ];
          return i < was.series.length && was.series[i].name == sub
              ? was.series[i].copyWith(values: values)
              : ChartSeries(
                  name: sub,
                  color: chartPalette[i % chartPalette.length],
                  values: values);
        }(),
    ];
    List<double> lineValues(int c) => [
          for (var k in keys)
            valueOf([
              for (var sub in subs) ...?groups["$k\u0000$sub"],
            ], c)
        ];
    return (ChartData(categories: keys, series: series), lineValues);
  }

  // A mark per label, in order of a column if asked.
  var items = [for (var k in keys) (k, groups["$k\u0000"]!)];
  if (link.sortBy >= 0) {
    var keyed = [
      for (var (i, it) in items.indexed) (i, it, valueOf(it.$2, link.sortBy))
    ];
    keyed.sort((a, b) {
      if (a.$3.isNaN || b.$3.isNaN) {
        var d = a.$3.isNaN == b.$3.isNaN ? 0 : (a.$3.isNaN ? 1 : -1);
        return d != 0 ? d : a.$1.compareTo(b.$1);
      }
      var d = a.$3.compareTo(b.$3);
      if (link.descending) d = -d;
      return d != 0 ? d : a.$1.compareTo(b.$1);
    });
    items = [for (var (_, it, _) in keyed) it];
  }
  // Which places: the first or last few, or places named, a gap between
  // groups of them.
  var placed = [for (var (i, it) in items.indexed) (i + 1, it)];
  if (link.top > 0 && placed.length > link.top) {
    placed = link.bottom
        ? placed.sublist(placed.length - link.top)
        : placed.sublist(0, link.top);
  }
  var wanted = placesIn(link.places);
  if (wanted.isNotEmpty) {
    placed = [
      for (var p in placed)
        if (wanted.contains(p.$1)) p
    ];
  }
  var shownItems = <(String, List<int>)?>[];
  for (var (i, p) in placed.indexed) {
    if (link.gap &&
        wanted.isNotEmpty &&
        i > 0 &&
        p.$1 != placed[i - 1].$1 + 1) {
      shownItems.add(null);
    }
    shownItems.add(p.$2);
  }

  List<double> columnValues(int col) => [
        for (var it in shownItems) it == null ? double.nan : valueOf(it.$2, col)
      ];
  var series = <ChartSeries>[
    for (var (i, col) in link.series.indexed)
      () {
        var name = sheetShown(sheet, g.r0, g.c0 + col);
        var values = columnValues(col);
        return i < was.series.length
            ? was.series[i].copyWith(name: name, values: values)
            : ChartSeries(
                name: name,
                color: chartPalette[i % chartPalette.length],
                values: values);
      }(),
  ];

  // Coloured by a column: words a colour each (results as a form guide's),
  // numbers a scale.
  var marks = <Color?>[];
  if (colourBy >= 0) {
    if (words(colourBy)) {
      var seen = <String>[];
      for (var r in rows) {
        var w = shown(r, colourBy);
        if (!seen.contains(w)) seen.add(w);
      }
      marks = [
        for (var it in shownItems)
          if (it == null)
            null
          else
            () {
              var w = shown(it.$2.last, colourBy);
              return resultColours[w.trim().toLowerCase()] ??
                  chartPalette[seen.indexOf(w) % chartPalette.length];
            }(),
      ];
    } else {
      var v = columnValues(colourBy);
      var real = [
        for (var x in v)
          if (!x.isNaN) x
      ];
      var lo = real.isEmpty ? 0.0 : real.reduce(math.min);
      var hi = real.isEmpty ? 0.0 : real.reduce(math.max);
      marks = [for (var x in v) x.isNaN ? null : scaleColour(x, lo, hi)];
    }
  }

  return (
    ChartData(
        categories: [for (var it in shownItems) it?.$1 ?? "…"],
        series: series,
        marks: marks),
    columnValues
  );
}

/// _spotlit is the look of row [r] of [g] when it is the sheet's spotlight
/// -- a cell of it says the spotlit name -- else null.
SheetCellLook? _spotlit(DataSheet sheet, int r, CellRange g) {
  var who = sheet.spotlight.trim().toLowerCase();
  if (who.isEmpty) return null;
  for (var c = g.c0; c <= g.c1; c++) {
    if (sheetShown(sheet, r, c).trim().toLowerCase() == who) {
      return SheetCellLook(fill: sheet.spotlightColour.withValues(alpha: 0.35));
    }
  }
  return null;
}
