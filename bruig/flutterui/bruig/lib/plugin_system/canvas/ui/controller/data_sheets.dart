part of '../canvas_controller.dart';

// Part of CanvasController: the canvas's sheets (data_sheet.dart), as the
// Data Studio edits them -- cells typed, pasted and cleared, rows and
// columns put in, taken out and sorted, sheets added, named and removed --
// and the Data elements put down from it. Each change is one step to undo;
// every view of a sheet follows it in the same step (data_sync.dart).

extension CanvasDataSheets on CanvasController {
  /// setSheet writes [sheet] over the one of its id.
  void setSheet(DataSheet sheet, {bool transient = false}) => apply(
      _document.copyWith(sheets: [
        for (var s in _document.sheets) s.id == sheet.id ? sheet : s,
      ]),
      transient: transient);

  /// setSheetCells writes [rows] into sheet [id] from row [r], column [c].
  void setSheetCells(String id, int r, int c, List<List<String>> rows) {
    var s = sheetById(id);
    if (s != null) setSheet(s.withBlock(r, c, rows));
  }

  /// pasteSheetCells writes [rows] into sheet [id] from row [r], column
  /// [c], as setSheetCells does -- and, where the paste makes the sheet
  /// bigger, grows every table and chart that showed it whole, in the same
  /// step: a league pasted over a new Data element's sample is seen whole
  /// in its table, as a refresh would be (found making the Charts canvas,
  /// 2026-11-17: the table stayed on the sample's A1:C4).
  void pasteSheetCells(String id, int r, int c, List<List<String>> rows) {
    var s = sheetById(id);
    if (s == null) return;
    var next = s.withBlock(r, c, rows);
    var doc = _document.copyWith(sheets: [
      for (var x in _document.sheets) x.id == id ? next : x,
    ]);
    apply(viewsRegrown(doc, id, s.used, next.used));
  }

  /// clearSheetCells empties [range] of sheet [id].
  void clearSheetCells(String id, CellRange range) =>
      setSheetCells(id, range.r0, range.c0, [
        for (var r = 0; r < range.rows; r++) List.filled(range.cols, ""),
      ]);

  /// addSheet puts a new sheet in the canvas, holding [cells], and answers
  /// its id.
  String addSheet({String? name, List<List<String>> cells = const []}) {
    var ids = {for (var s in _document.sheets) s.id};
    var names = {for (var s in _document.sheets) s.name};
    var n = _document.sheets.length + 1;
    while (ids.contains("sheet$n") || names.contains("Sheet $n")) {
      n++;
    }
    var id = "sheet$n";
    var wanted = (name ?? "").trim().isEmpty ? "Sheet $n" : name!.trim();
    var free = wanted;
    for (var k = 2; names.contains(free); k++) {
      free = "$wanted $k";
    }
    apply(_document.copyWith(sheets: [
      ..._document.sheets,
      DataSheet(id: id, name: free, cells: cells),
    ]));
    return id;
  }

  /// addMadeSheet puts in a new sheet made from another as [made] says
  /// (sheet_reshape.dart), named for what it is, and answers its id. It
  /// follows its source from then on.
  String addMadeSheet(SheetMade made, {String? name}) {
    var from = sheetById(made.from);
    if (from == null) return "";
    var other = made.kind == ReshapeKind.join ? sheetById(made.other) : null;
    var mine = _interaction == null;
    if (mine) beginInteraction();
    var id = addSheet(
        name: name ?? made.says(from, other),
        cells: reshaped(made, from, other));
    var s = sheetById(id)!;
    setSheet(s.copyWith(made: made));
    if (mine) endInteraction();
    return id;
  }

  /// setSheetSource connects sheet [id] to [source] (or, typed, disconnects
  /// it, keeping the numbers it has), fetching nothing.
  void setSheetSource(String id, DataSource source) {
    var s = sheetById(id);
    if (s != null) setSheet(s.copyWith(source: source));
  }

  /// receiveSheet puts what a refresh of [source] brought into sheet [id] --
  /// [rows], header first -- in one step to undo: the sheet, and every
  /// table and chart that showed it whole grown or shrunk to what came. It
  /// answers the cells that changed, for the grid to show.
  Set<(int, int)> receiveSheet(
      String id, List<List<String>> rows, DataSource source) {
    var s = sheetById(id);
    if (s == null) return const {};
    var next = sheetFromSource(s, rows, source, keepHeads: s.source.on);
    var doc = _document.copyWith(sheets: [
      for (var x in _document.sheets) x.id == id ? next : x,
    ]);
    apply(viewsRegrown(doc, id, s.used, next.used));
    return changedCells(s.cells, next.cells);
  }

  /// addReadSheets puts [read] -- sheets read from a file (sheet_files.dart)
  /// -- in the canvas, as one change to undo, and answers their ids.
  List<String> addReadSheets(List<ReadSheet> read) {
    var mine = _interaction == null;
    if (mine) beginInteraction();
    var ids = [for (var s in read) addSheet(name: s.name, cells: s.cells)];
    if (mine) endInteraction();
    return ids;
  }

  void renameSheet(String id, String name) {
    var s = sheetById(id);
    var n = name.trim();
    if (s != null && n.isNotEmpty && n != s.name) setSheet(s.copyWith(name: n));
  }

  /// removeSheets takes sheets [ids] out of the canvas, with whatever shows
  /// them, in one undo.
  void removeSheets(Set<String> ids) {
    if (ids.isNotEmpty) apply(sheetsRemoved(_document, ids));
  }


  void insertSheetRows(String id, int at, [int n = 1]) =>
      apply(rowsInserted(_document, id, at, n));
  void deleteSheetRows(String id, int at, [int n = 1]) =>
      apply(rowsDeleted(_document, id, at, n));
  void insertSheetColumns(String id, int at, [int n = 1]) =>
      apply(columnsInserted(_document, id, at, n));
  void deleteSheetColumns(String id, int at, [int n = 1]) =>
      apply(columnsDeleted(_document, id, at, n));
  /// resizeSheet gives sheet [id]'s grid [rows] by [columns]: what is
  /// typed past a new edge goes with them, in one undo.
  void resizeSheet(String id, int rows, int columns) =>
      apply(sheetResized(_document, id, rows, columns));

  /// removeDataView takes table or chart [id] off the canvas, wherever it
  /// is.
  void removeDataView(String id) {
    if (_document.elementById(id) != null) {
      deleteElement(id);
    } else {
      apply(viewRemoved(_document, id));
    }
  }

  void sortSheetRows(String id, CellRange rows, int by,
          {bool descending = false}) =>
      apply(rowsSorted(_document, id, rows, by, descending: descending));

  /// fillSheet carries [from] of sheet [id] on over [to] (the fill
  /// handle).
  void fillSheet(String id, CellRange from, CellRange to) {
    var s = sheetById(id);
    if (s != null) setSheet(sheetFilled(s, from, to));
  }

  /// formatSheetCells gives [range] of sheet [id] number format [format]
  /// (null for General): whole columns, where [range] is every row of
  /// them, as their column's.
  void formatSheetCells(String id, CellRange range, CellFormat? format,
      {bool columns = false}) {
    var s = sheetById(id);
    if (s == null) return;
    if (columns) {
      var cols = {...s.columnFormats};
      var cells = {...s.formats};
      for (var c = range.c0; c <= range.c1; c++) {
        format == null ? cols.remove(c) : cols[c] = format;
        // A column's format is over its cells' own: they go.
        cells.removeWhere((k, _) => cellAt(k)?.$2 == c);
      }
      setSheet(s.copyWith(columnFormats: cols, formats: cells));
      return;
    }
    var cells = {...s.formats};
    for (var r = range.r0; r <= range.r1; r++) {
      for (var c = range.c0; c <= range.c1; c++) {
        format == null
            ? cells.remove(cellName(r, c))
            : cells[cellName(r, c)] = format;
      }
    }
    setSheet(s.copyWith(formats: cells));
  }

  /// addSheetRule gives sheet [id] colour rule [rule], over any it had
  /// on the same range.
  void addSheetRule(String id, SheetRule rule) {
    var s = sheetById(id);
    if (s == null) return;
    setSheet(s.copyWith(rules: [
      for (var r in s.rules)
        if (r.range != rule.range) r,
      rule,
    ]));
  }

  /// clearSheetRules takes out sheet [id]'s colour rules that reach into
  /// [range].
  void clearSheetRules(String id, CellRange range) {
    var s = sheetById(id);
    if (s == null) return;
    setSheet(s.copyWith(rules: [
      for (var r in s.rules)
        if (!r.range.overlaps(range)) r,
    ]));
  }

  /// addDataView puts down a Data element showing [range] of sheet [id] as
  /// [kind] -- a table or a chart, labelled and drawn from its columns --
  /// selects it and answers it.
  CanvasElement addDataView(ElementKind kind, String id, CellRange range) {
    var made = newElement(kind, _document);
    made = withLink(made, _linkFor(made, SheetLink(id, range)));
    addElement(made);
    return _document.elementById(made.id) ?? made;
  }

  /// openDataStudio gives the page to the Data Studio, on sheet [id] --
  /// with view [view] picked, where one is given.
  void openDataStudio(String id, {String? view}) {
    if (playing) pause();
    dataStudioView = view;
    dataStudio.value = id;
  }

  void closeDataStudio() {
    dataStudio.value = null;
    dataStudioView = null;
  }
}
