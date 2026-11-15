import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/tabular_text.dart';

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
  var block = sheetBlock(sheet, link.range);
  if (e is TableElement) {
    return sameGrid(e.rows, block) ? e : e.copyWith(rows: block);
  }
  if (e is ChartElement) {
    var data = chartDataOf(block, link, e.data);
    return sameData(e.data, data) ? e : e.copyWith(data: data);
  }
  return e;
}

/// chartDataOf is the chart [block] makes (its first row the headings),
/// labelled by column [SheetLink.labels], a series from each of
/// [SheetLink.series]. Each series keeps how [was]'s one in its place
/// looked; a blank cell is a gap.
ChartData chartDataOf(List<List<String>> block, SheetLink link, ChartData was) {
  if (block.isEmpty)
    return was.copyWith(categories: const [], series: const []);
  String at(List<String> row, int c) => c >= 0 && c < row.length ? row[c] : "";
  var body = block.skip(1).toList();
  var series = <ChartSeries>[
    for (var (i, c) in link.series.indexed)
      () {
        var name = at(block.first, c);
        var values = [
          for (var row in body) cellNumber(at(row, c)) ?? double.nan
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
    categories: [for (var row in body) at(row, link.labels)],
    series: series,
    estimated: est.isEmpty
        ? const []
        : [for (var i = 0; i < body.length; i++) i < est.length && est[i]],
  );
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
      var shown = sheetShown(sheet, sr, sc);
      var same = number != null
          ? (number.isNaN ? shown.trim().isEmpty : cellNumber(shown) == number)
          : shown == text;
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

/// chartColumnsFor is which columns of [block] (its first row the
/// headings) a chart of it is labelled by -- the first that isn't numbers
/// -- and draws: every column of numbers but that one.
(int, List<int>) chartColumnsFor(List<List<String>> block) {
  var cols = block.fold(0, (n, r) => math.max(n, r.length));
  var body = block.skip(1).toList();
  bool numbers(int c) {
    var seen = 0, ok = 0;
    for (var row in body) {
      var v = c < row.length ? row[c].trim() : "";
      if (v.isEmpty) continue;
      seen++;
      if (cellNumber(v) != null) ok++;
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
  return _withSheet(doc, s.copyWith(cells: cells), (l) {
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
  return _withSheet(doc, s.copyWith(cells: cells), (l) {
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
  return _withSheet(doc, s.copyWith(cells: cells), (l) {
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
  return _withSheet(doc, s.copyWith(cells: cells), (l) {
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
/// column [by] -- numbers by value, before words -- smallest first or, with
/// [descending], largest; only columns [rows].c0 to c1 move.
CanvasDocument rowsSorted(CanvasDocument doc, String id, CellRange rows, int by,
    {bool descending = false}) {
  var s = _sheetIn(doc, id);
  if (s == null || rows.rows < 2) return doc;
  var order = [for (var r = rows.r0; r <= rows.r1; r++) r];
  int compare(int a, int b) {
    var x = sheetShown(s, a, by), y = sheetShown(s, b, by);
    var nx = cellNumber(x), ny = cellNumber(y);
    int d;
    if (nx != null && ny != null) {
      d = nx.compareTo(ny);
    } else if (nx != null || ny != null) {
      d = nx != null ? -1 : 1;
    } else if (x.isEmpty || y.isEmpty) {
      // Blanks last, whichever way.
      return x.isEmpty == y.isEmpty ? 0 : (x.isEmpty ? 1 : -1);
    } else {
      d = x.toLowerCase().compareTo(y.toLowerCase());
    }
    return descending ? -d : d;
  }

  // A stable sort: ties keep their order.
  var keyed = [for (var (i, r) in order.indexed) (i, r)];
  keyed.sort((a, b) {
    var d = compare(a.$2, b.$2);
    return d != 0 ? d : a.$1.compareTo(b.$1);
  });
  var block = [
    for (var (_, r) in keyed)
      [for (var c = rows.c0; c <= rows.c1; c++) s.raw(r, c)],
  ];
  return doc.copyWith(sheets: [
    for (var x in doc.sheets)
      x.id == id ? s.withBlock(rows.r0, rows.c0, block) : x,
  ]);
}
