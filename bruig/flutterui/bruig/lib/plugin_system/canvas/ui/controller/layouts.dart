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

  /// removeLayoutCell takes cell [cell] out of [e]: in Panels, the cut
  /// beside it goes and its neighbour fills the room (what was docked in
  /// either is docked in the one left); elsewhere the cell goes, and what
  /// was docked in it is let go where it is.
  void removeLayoutCell(LayoutElement e, String cell) {
    var next = _document;
    List<String> gone;
    String? into;
    if (e.mode == LayoutMode.panels) {
      var path = e.root.pathTo(cell);
      if (path == null || path.isEmpty) return;
      // The sibling's first cell stays: the cut beside [cell] goes, so the
      // cell it is merged with keeps its name and style.
      var parent = e.root.nodeAt(path.sublist(0, path.length - 1))!;
      var keep = (path.last ? parent.a! : parent.b!).cells.first;
      LayoutElement merged;
      (merged, gone) = e.merge(keep);
      into = keep;
      next = next.withElement(merged);
    } else {
      gone = [cell];
      next = next.withElement(e.copyWith(cells: [
        for (var c in e.cells)
          if (c.id != cell) c
      ]));
    }
    for (var el in _document.elements) {
      var d = dockOf(el.base.dock);
      if (d == null || d.$1 != e.id || !gone.contains(d.$2)) continue;
      next = next
          .withElement(el.withBase(dock: into == null ? "" : "${e.id}:$into"));
    }
    apply(next);
    pickLayoutCell(e.id, into);
  }

  /// addLayoutCell puts a new cell in [e]: a Free shape in the middle, or a
  /// Grid cell in the first slot no cell covers (a row added if none is
  /// free). Picks it.
  void addLayoutCell(LayoutElement e,
      {LayoutCellShape shape = LayoutCellShape.rectangle}) {
    var id = newElementId();
    LayoutElement next;
    if (e.mode == LayoutMode.grid) {
      bool covered(int c, int r) => e.cells.any((x) =>
          c >= x.col &&
          c < x.col + x.colSpan &&
          r >= x.row &&
          r < x.row + x.rowSpan);
      (int, int)? free;
      for (var r = 0; r < e.rows.length && free == null; r++) {
        for (var c = 0; c < e.columns.length && free == null; c++) {
          if (!covered(c, r)) free = (c, r);
        }
      }
      var rows = e.rows;
      if (free == null) {
        if (rows.length >= LayoutElement.maxTracks) return;
        rows = [...rows, 1];
        free = (0, rows.length - 1);
      }
      next = e.copyWith(rows: rows, cells: [
        ...e.cells,
        LayoutCell(
            id: id,
            name: "Card ${e.cells.length + 1}",
            col: free.$1,
            row: free.$2),
      ]);
    } else {
      next = e.copyWith(cells: [
        ...e.cells,
        LayoutCell(
            id: id,
            name: "Frame ${e.cells.length + 1}",
            x: 0.35,
            y: 0.35,
            width: 0.3,
            height: 0.3,
            shape: shape),
      ]);
    }
    if (next.cells.length > LayoutElement.maxCells) return;
    setLayout(next);
    pickLayoutCell(e.id, id);
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
    var next = e.withBase(dock: "$layoutId:$cell");
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

  /// dockableCells is every cell an element on this page can be docked in:
  /// (layout id, cell id, what to call it).
  List<(String, String, String)> dockableCells(CanvasElement e) => [
        for (var l in _document.elements)
          if (l is LayoutElement && l.id != e.id)
            for (var (i, c) in l.shownCells.indexed)
              (
                l.id,
                c.id,
                "${l.name} · ${c.name.isEmpty ? "Cell ${i + 1}" : c.name}"
              )
      ];
}

/// _LayoutState is the cell picked in each layout, by element id.
class _LayoutState {
  final Map<String, String> picked = {};
}
