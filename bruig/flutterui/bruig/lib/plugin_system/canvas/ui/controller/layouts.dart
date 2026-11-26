part of '../canvas_controller.dart';

// Part of CanvasController: Layouts (layout_element.dart) -- the cell picked
// in each, its cells split, merged, added and taken away, and elements
// docked into a cell. What is docked moves with the whole layout through
// layoutsSynced (layout_sync.dart), on every change; editing the cells
// leaves it be.

extension CanvasLayouts on CanvasController {
  /// layoutCell is the cell picked in layout [layoutId], or null for the
  /// whole layout (session only, as a text's picked layer is).
  String? layoutCell(String layoutId) => _layouts.picked[layoutId];

  /// pickLayoutCell picks cell [cell] of layout [layoutId], or none.
  void pickLayoutCell(String layoutId, String? cell) {
    if (_layouts.picked[layoutId] == cell) return;
    if (cell == null) {
      _layouts.picked.remove(layoutId);
    } else {
      _layouts.picked[layoutId] = cell;
    }
    notifyListeners();
  }

  /// orderingLayout is the layout whose reading order is being set by
  /// clicking its cells in turn ("Set reading order"), or null; and
  /// orderClicked the cells clicked so far, in turn.
  String? get orderingLayout => _layouts.ordering;
  List<String> get orderClicked => List.unmodifiable(_layouts.clicked);

  /// beginReadingOrder starts numbering [e]'s cells by clicking them.
  void beginReadingOrder(LayoutElement e) {
    _layouts.ordering = e.id;
    _layouts.clicked.clear();
    notifyListeners();
  }

  /// clickReadingOrder numbers [cell] next; clicked again, it is taken out
  /// and those after it move up.
  void clickReadingOrder(String cell) {
    if (_layouts.ordering == null) return;
    if (!_layouts.clicked.remove(cell)) _layouts.clicked.add(cell);
    notifyListeners();
  }

  /// finishReadingOrder ends the numbering: kept, the cells clicked are the
  /// order and those not clicked are left out (none clicked changes
  /// nothing); not kept, the order stays as it was.
  void finishReadingOrder({bool keep = true}) {
    var id = _layouts.ordering;
    if (id == null) return;
    var e = _document.elementById(id);
    var clicked = [..._layouts.clicked];
    _layouts.ordering = null;
    _layouts.clicked.clear();
    if (keep && e is LayoutElement && clicked.isNotEmpty) {
      setLayout(e.copyWith(order: clicked, unread: [
        for (var c in e.shownCells)
          if (!clicked.contains(c.id)) c.id
      ]));
    }
    notifyListeners();
  }

  /// moveInReading moves [cell] [by] places in [e]'s reading order.
  void moveInReading(LayoutElement e, String cell, int by) {
    var ids = [for (var c in e.reading) c.id];
    var i = ids.indexOf(cell);
    if (i < 0) return;
    var to = (i + by).clamp(0, ids.length - 1);
    if (to == i) return;
    ids
      ..removeAt(i)
      ..insert(to, cell);
    setLayout(e.copyWith(order: ids));
  }

  /// setCellRead puts [cell] in [e]'s reading, at the end, or leaves it out.
  void setCellRead(LayoutElement e, String cell, bool read) {
    var ids = [for (var c in e.reading) c.id];
    setLayout(read
        ? e.copyWith(order: [
            ...ids,
            cell
          ], unread: [
            for (var u in e.unread)
              if (u != cell) u
          ])
        : e.copyWith(order: [
            for (var id in ids)
              if (id != cell) id
          ], unread: [
            ...e.unread,
            cell
          ]));
  }

  /// resetReadingOrder reads [e]'s cells in their own order, none left out.
  void resetReadingOrder(LayoutElement e) =>
      setLayout(e.copyWith(order: const [], unread: const []));

  /// setLayout writes layout [e].
  void setLayout(LayoutElement e, {bool transient = false}) =>
      replaceElement(e, transient: transient);

  /// splitLayoutCell cuts Panels cell [cell] of [e] in two and picks the new
  /// half; [vertical] cuts top to bottom.
  void splitLayoutCell(LayoutElement e, String cell, {required bool vertical}) {
    var (next, fresh) = e.split(cell, vertical: vertical);
    setLayout(next);
    pickLayoutCell(e.id, fresh);
  }

  /// removeLayoutCell takes cell [cell] out of [e] (LayoutElement
  /// .removeCell): in Panels, the cut beside it goes and what was on its
  /// other side fills the room, and what was docked in it is docked in the
  /// cell that met it; elsewhere the cell goes, and what was docked in it is
  /// let go where it is (layoutsSynced, as for any cell that goes).
  void removeLayoutCell(LayoutElement e, String cell) {
    var (next, into) = e.removeCell(cell);
    if (identical(next, e)) return;
    var doc = _document.withElement(next);
    if (into != null) {
      for (var el in _document.elements) {
        if (el.base.docked == LayoutDock(e.id, cell)) {
          doc = doc
              .withElement(el.withBase(dock: LayoutDock(e.id, into).toJson()));
        }
      }
    }
    apply(doc);
    pickLayoutCell(e.id, into);
  }

  /// addLayoutCell puts a new cell in [e] (LayoutElement.addCell): a Free
  /// shape in the middle, or a Grid cell in the first slot no cell covers.
  /// Picks it.
  void addLayoutCell(LayoutElement e,
      {LayoutCellShape shape = LayoutCellShape.rectangle}) {
    if (e.addCell(shape: shape) case (var next, var id)?) {
      setLayout(next);
      pickLayoutCell(e.id, id);
    }
  }

  /// setLayoutTracks gives a Grid [columns] and [rows]: cells past the end
  /// are brought inside, so none is lost.
  void setLayoutTracks(LayoutElement e,
      {List<double>? columns, List<double>? rows}) {
    var cols = columns ?? e.columns, rs = rows ?? e.rows;
    if (cols.isEmpty || rs.isEmpty) return;
    setLayout(e.copyWith(columns: cols, rows: rs, cells: [
      for (var c in e.cells)
        c.copyWith(
            col: c.col.clamp(0, cols.length - 1),
            row: c.row.clamp(0, rs.length - 1),
            colSpan: c.colSpan
                .clamp(1, cols.length - c.col.clamp(0, cols.length - 1)),
            rowSpan:
                c.rowSpan.clamp(1, rs.length - c.row.clamp(0, rs.length - 1))),
    ]));
  }

  /// setLayoutMode makes [e] a layout of [mode], starting from the cells it
  /// has: their names and styles kept, placed afresh.
  void setLayoutMode(LayoutElement e, LayoutMode mode) {
    if (e.mode == mode) return;
    var cells = e.shownCells;
    switch (mode) {
      case LayoutMode.panels:
        // The cells side by side, then cut in rows of two.
        LayoutNode build(List<LayoutCell> list) {
          if (list.length == 1) return LayoutNode.leaf(list.single.id);
          var half = list.length ~/ 2;
          return LayoutNode.cut(
              vertical: list.length <= 2,
              at: half / list.length,
              a: build(list.sublist(0, half)),
              b: build(list.sublist(half)));
        }
        setLayout(e.copyWith(
            mode: mode,
            root: build(cells.isEmpty ? [const LayoutCell(id: "c1")] : cells),
            cells: cells.isEmpty ? [const LayoutCell(id: "c1")] : cells));
      case LayoutMode.grid:
        var n = cells.length.clamp(1, 1000);
        var cols = n <= 2 ? n : (n <= 4 ? 2 : 3);
        var rows = (n / cols).ceil();
        setLayout(e.copyWith(
            mode: mode,
            columns: List.filled(cols, 1.0),
            rows: List.filled(rows, 1.0),
            cells: [
              for (var (i, c) in cells.indexed)
                c.copyWith(
                    col: i % cols, row: i ~/ cols, colSpan: 1, rowSpan: 1)
            ]));
      case LayoutMode.free:
        // Each where it was drawn, as a share of the box.
        var box = layoutInner(e, e.bounds);
        var places = layoutPlaces(e, e.bounds);
        setLayout(e.copyWith(mode: mode, cells: [
          for (var p in places)
            p.cell.copyWith(
                x: (p.bounds.left - box.left) / box.width,
                y: (p.bounds.top - box.top) / box.height,
                width: p.bounds.width / box.width,
                height: p.bounds.height / box.height,
                turn: 0),
        ]));
    }
  }

  /// dockElement docks [e] in cell [cell] of layout [layoutId], or lets it
  /// go with an empty [layoutId]. [fit] sizes it to the cell.
  void dockElement(CanvasElement e, String layoutId, String cell,
      {bool fit = false}) {
    if (layoutId.isEmpty) {
      replaceElement(e.withBase(dock: "", dockOut: false));
      return;
    }
    var next = e.withBase(dock: LayoutDock(layoutId, cell).toJson());
    var layout = _document.elementById(layoutId);
    if (fit && layout is LayoutElement) {
      var place = layoutPlaceOf(layout, layout.bounds, cell);
      if (place != null) {
        var r = place.bounds;
        next = next.withBase(
            x: r.left, y: r.top, width: r.width, height: r.height);
      }
    }
    replaceElement(next);
  }

  /// dockableCells is every cell an element on this page can be docked in,
  /// and what to call it.
  List<({LayoutDock dock, String name})> dockableCells(CanvasElement e) => [
        for (var l in _document.elements)
          if (l is LayoutElement && l.id != e.id)
            for (var (i, c) in l.shownCells.indexed)
              (
                dock: LayoutDock(l.id, c.id),
                name: "${l.name} · ${c.name.isEmpty ? "Cell ${i + 1}" : c.name}"
              )
      ];
}

/// _LayoutState is the cell picked in each layout, by element id, and the
/// reading order being clicked.
class _LayoutState {
  final Map<String, String> picked = {};
  String? ordering;
  final List<String> clicked = [];
}
