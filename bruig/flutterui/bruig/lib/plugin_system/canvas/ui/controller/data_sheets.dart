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
    apply(_document.copyWith(sheets: [
      ..._document.sheets,
      DataSheet(id: id, name: name ?? "Sheet $n", cells: cells),
    ]));
    return id;
  }

  void renameSheet(String id, String name) {
    var s = sheetById(id);
    var n = name.trim();
    if (s != null && n.isNotEmpty && n != s.name) setSheet(s.copyWith(name: n));
  }

  /// removeSheet takes sheet [id] out -- only one nothing on the canvas
  /// shows -- and answers whether it did.
  bool removeSheet(String id) {
    if (viewsOf(_document, id).isNotEmpty) return false;
    apply(_document.copyWith(sheets: [
      for (var s in _document.sheets)
        if (s.id != id) s
    ]));
    return true;
  }

  void insertSheetRows(String id, int at, [int n = 1]) =>
      apply(rowsInserted(_document, id, at, n));
  void deleteSheetRows(String id, int at, [int n = 1]) =>
      apply(rowsDeleted(_document, id, at, n));
  void insertSheetColumns(String id, int at, [int n = 1]) =>
      apply(columnsInserted(_document, id, at, n));
  void deleteSheetColumns(String id, int at, [int n = 1]) =>
      apply(columnsDeleted(_document, id, at, n));
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
