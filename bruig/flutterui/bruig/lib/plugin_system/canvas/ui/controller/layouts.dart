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
      replaceElement(e.copyWith(order: clicked, unread: [
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
    replaceElement(e.copyWith(order: ids));
  }

  /// setCellRead puts [cell] in [e]'s reading, at the end, or leaves it out.
  void setCellRead(LayoutElement e, String cell, bool read) {
    var ids = [for (var c in e.reading) c.id];
    replaceElement(read
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
      replaceElement(e.copyWith(order: const [], unread: const []));

  /// splitLayoutCell cuts Panels cell [cell] of [e] in two and picks the new
  /// half; [vertical] cuts top to bottom.
  void splitLayoutCell(LayoutElement e, String cell, {required bool vertical}) {
    var (layout: next, cell: fresh) = e.split(cell, vertical: vertical);
    replaceElement(next);
    pickLayoutCell(e.id, fresh);
  }

  /// removeLayoutCell takes cell [cell] out of [e] (LayoutElement
  /// .removeCell): in Panels, the cut beside it goes and what was on its
  /// other side fills the room, and what was docked in it is docked in the
  /// cell that met it; elsewhere the cell goes, and what was docked in it is
  /// let go where it is (layoutsSynced, as for any cell that goes).
  void removeLayoutCell(LayoutElement e, String cell) {
    var (layout: next, :into) = e.removeCell(cell);
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
    if (e.addCell(shape: shape) case (layout: var next, cell: var id)?) {
      replaceElement(next);
      pickLayoutCell(e.id, id);
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
            for (var c in l.shownCells)
              (dock: LayoutDock(l.id, c.id), name: "${l.name} · ${l.nameOf(c)}")
      ];
}

/// _LayoutState is the cell picked in each layout, by element id, and the
/// reading order being clicked.
class _LayoutState {
  final Map<String, String> picked = {};
  String? ordering;
  final List<String> clicked = [];
}
