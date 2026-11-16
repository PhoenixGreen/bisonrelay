part of '../canvas_controller.dart';

// Part of CanvasController: the Data element's views (data_sheet.dart): a
// table or a chart of a range of one of the canvas's sheets, switched
// between the two, or pointed at another sheet. Keeping each in step with
// its sheet is data_sync.dart's, in apply.

extension CanvasDataViews on CanvasController {
  /// stylePage puts the page being made in [style] (page_style.dart): its
  /// charts and tables, its words by their size, and its ground. One change
  /// to undo (Ken, 2026-11-17, the improvements report's fifth item).
  void stylePage(DataStyle style) {
    var before = _document.elements;
    var after = pageInStyle(before, style);
    var mine = _interaction == null;
    if (mine) beginInteraction();
    for (var (i, e) in after.indexed) {
      if (!identical(e, before[i])) replaceElement(e);
    }
    var bg = _document.background;
    setBackground(
        bg.copyWith(spec: bg.spec.copyWith(background: style.ground)));
    if (mine) endInteraction();
  }

  /// layOutPage puts [views] over the page in [layout], filling it below
  /// where the first of them starts. One change to undo.
  void layOutPage(List<CanvasElement> views, PageLayout layout) {
    if (views.isEmpty) return;
    var page = _document.size.size;
    var top = views.map((v) => v.base.y).reduce(math.min);
    var area = layoutArea(page, top);
    var gap = page.width * 0.025;
    var rects = layout == PageLayout.report
        ? reportLayoutRects([
            for (var v in views)
              v is ChartElement && v.type == ChartType.bigNumber
                  ? "figure"
                  : v is TableElement
                      ? "table"
                      : "chart"
          ], area, gap)
        : pageLayoutRects(views.length, layout, area, gap);
    // On a baseline grid, a sixtieth of the page's height: lined up.
    var unit = page.height / 60;
    rects = [for (var r in rects) snapToBaseline(r, unit)];
    var mine = _interaction == null;
    if (mine) beginInteraction();
    for (var (i, v) in views.indexed) {
      var r = rects[i];
      replaceElement(v.rebase(v.base
          .copyWith(x: r.left, y: r.top, width: r.width, height: r.height)));
    }
    if (mine) endInteraction();
  }

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
