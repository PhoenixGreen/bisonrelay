part of '../canvas_controller.dart';

// Part of CanvasController: the Data element's views (data_sheet.dart): a
// table or a chart of a range of one of the canvas's sheets, switched
// between the two, or pointed at another sheet. Keeping each in step with
// its sheet is data_sync.dart's, in apply.

extension CanvasDataViews on CanvasController {
  DataSheet? sheetById(String id) =>
      _document.sheets.where((s) => s.id == id).firstOrNull;

  /// showDataAs shows Data element [e] as [kind] -- a table or a chart --
  /// in its place, of the same range of the same sheet; a chart labelled by
  /// the range's first column of words and drawing its columns of numbers.
  /// One change to undo.
  void showDataAs(CanvasElement e, ElementKind kind) {
    if (e.kind == kind || !isDataView(e)) return;
    if (kind != ElementKind.table && kind != ElementKind.chart) return;
    var made = newElement(kind, _document).rebase(e.base);
    if (linkOf(e) case var link?) {
      made = withLink(made, _linkFor(made, link));
    }
    replaceElement(made);
  }

  /// showSheet points Data element [e] at sheet [id], all of what it holds.
  void showSheet(CanvasElement e, String id) {
    var sheet = sheetById(id);
    if (sheet == null || !isDataView(e)) return;
    replaceElement(withLink(e, _linkFor(e, SheetLink(id, sheet.used))));
  }

  /// showRange points Data element [e] at [range] of the sheet it shows,
  /// as a new view of that range would be: which rows it shows and how
  /// they are ordered start again, since its columns are no longer the
  /// ones they named.
  void showRange(CanvasElement e, CellRange range) {
    var link = linkOf(e);
    if (link == null || !isDataView(e)) return;
    replaceElement(withLink(e, _linkFor(e, SheetLink(link.sheet, range))));
  }

  /// _linkFor is [link] as [e] views it: for a chart, which columns label
  /// it and which it draws.
  SheetLink _linkFor(CanvasElement e, SheetLink link) {
    var sheet = sheetById(link.sheet);
    if (e is! ChartElement || sheet == null) return link;
    var (labels, series) = chartColumnsOf(sheet, link.range);
    return link.copyWith(labels: labels, series: series);
  }
}
