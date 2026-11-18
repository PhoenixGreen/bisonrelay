part of 'canvas_stage.dart';

// A Layout (layout_element.dart) handled on the canvas. Selected, its lines
// show: a Panels cut or a Grid line between tracks is dragged to move it.
// Double-clicked, the cell under the pointer is picked (its settings
// show); a picked Free cell has the selection's handles, to move, size and
// turn it. Delete takes the picked cell out (in Panels, merges it). Part of
// CanvasStageState: its fields, lifecycle and build are in canvas_stage.dart.

extension StageLayouts on CanvasStageState {
  /// _oneLayout is the one selected Layout, unlocked, or null.
  LayoutElement? get _oneLayout {
    var chosen = _chosen;
    if (chosen.length != 1) return null;
    var e = chosen.first;
    return e is LayoutElement && !e.locked ? e : null;
  }

  /// _intoLayout is document point [p] in [e]'s own frame, its turn undone.
  Offset _intoLayout(LayoutElement e, Offset p) =>
      _turned(p, e.bounds.center, -e.rotation);

  Offset _outOfLayout(LayoutElement e, Offset p) =>
      _turned(p, e.bounds.center, e.rotation);

  static Offset _turned(Offset p, Offset about, double degrees) {
    if (degrees == 0) return p;
    var a = degrees * math.pi / 180;
    var d = p - about;
    return about +
        Offset(d.dx * math.cos(a) - d.dy * math.sin(a),
            d.dx * math.sin(a) + d.dy * math.cos(a));
  }

  /// _layoutMarks is what the painter shows of the selected Layout.
  LayoutMarks? _layoutMarks() {
    var e = _oneLayout;
    if (e == null || !controller.showHelpers) return null;
    var lines = <(Offset, Offset)>[
      for (var c in layoutCutLines(e, e.bounds))
        (_outOfLayout(e, c.from), _outOfLayout(e, c.to)),
      for (var t in layoutTrackLines(e, e.bounds))
        (_outOfLayout(e, t.from), _outOfLayout(e, t.to)),
    ];
    Path? picked;
    var id = controller.layoutCell(e.id);
    if (id != null) {
      var place = layoutPlaceOf(e, e.bounds, id);
      if (place != null) {
        picked = e.rotation == 0
            ? place.path
            : place.path.transform(_turnMatrix(e.bounds.center, e.rotation));
      }
    }
    return LayoutMarks(lines, picked);
  }

  static Float64List _turnMatrix(Offset c, double degrees) {
    var a = degrees * math.pi / 180;
    var cs = math.cos(a), sn = math.sin(a);
    return Float64List.fromList([
      cs, sn, 0, 0, //
      -sn, cs, 0, 0,
      0, 0, 1, 0,
      c.dx - cs * c.dx + sn * c.dy, c.dy - sn * c.dx - cs * c.dy, 0, 1,
    ]);
  }

  /// _oneFreeCell is the selected Free layout and its picked cell, which has
  /// the selection's handles.
  (LayoutElement, LayoutCell)? get _oneFreeCell {
    var e = _oneLayout;
    if (e == null || e.mode != LayoutMode.free) return null;
    var id = controller.layoutCell(e.id);
    var cell = id == null ? null : e.cellById(id);
    return cell == null ? null : (e, cell);
  }

  /// _freeCellBounds is a Free cell's own rectangle on the page, upright:
  /// its middle turned with the layout, its own turn left to the frame.
  Rect _freeCellBounds(LayoutElement e, LayoutCell c) {
    var inner = layoutInner(e, e.bounds);
    var r = Rect.fromLTWH(
        inner.left + c.x * inner.width,
        inner.top + c.y * inner.height,
        c.width * inner.width,
        c.height * inner.height);
    return Rect.fromCenter(
        center: _outOfLayout(e, r.center), width: r.width, height: r.height);
  }

  static double _toSegment(Offset p, Offset a, Offset b) {
    var ab = b - a;
    var t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) /
        math.max(1e-9, ab.distanceSquared);
    return (p - (a + ab * t.clamp(0.0, 1.0))).distance;
  }

  /// _pressLayout starts on the selected Layout, if the press is on a line
  /// to drag or a picked Free cell's handles or inside. Answers whether it
  /// was taken.
  bool _pressLayout(Offset stage, Offset doc) {
    var e = _oneLayout;
    if (e == null) return false;
    // A picked Free cell: its handles size and turn it, inside moves it.
    if (_oneFreeCell case (var l, var c)?) {
      var handle = _hitHandle(stage);
      if (handle != null) {
        _beginLayoutDrag(
            l,
            handle == StageHandle.rotate
                ? _DragMode.layoutCellTurn
                : _DragMode.layoutCellSize);
        _layoutMiddle = _freeCellBounds(l, c).center;
        _handle = handle;
        return true;
      }
      var box = _freeCellBounds(l, c);
      var local = BoxFrame(l.rotation + c.turn, 0, 0).invert(doc - box.center);
      if (local.dx.abs() <= box.width / 2 && local.dy.abs() <= box.height / 2) {
        _beginLayoutDrag(l, _DragMode.layoutCellMove);
        return true;
      }
    }
    // The layout's own handles first: a cut half way meets the middle one.
    if (_hitHandle(stage) != null) return false;
    var local = _intoLayout(e, doc);
    var reach = 10 / _scale;
    for (var line in layoutCutLines(e, e.bounds)) {
      if (_toSegment(local, line.from, line.to) <= reach) {
        _beginLayoutDrag(e, _DragMode.layoutCut);
        _layoutCut = line;
        return true;
      }
    }
    for (var line in layoutTrackLines(e, e.bounds)) {
      if (_toSegment(local, line.from, line.to) <= reach) {
        _beginLayoutDrag(e, _DragMode.layoutTrack);
        _layoutTrack = line;
        return true;
      }
    }
    return false;
  }

  void _beginLayoutDrag(LayoutElement e, _DragMode mode) {
    _mode = mode;
    _layoutStart = e;
    controller.beginInteraction();
  }

  /// _applyLayout moves what was pressed as the pointer goes to [doc].
  void _applyLayout(Offset doc) {
    var start = _layoutStart;
    if (start == null) return;
    var local = _intoLayout(start, doc);
    switch (_mode) {
      case _DragMode.layoutCut:
        var line = _layoutCut;
        if (line == null) return;
        var node = start.root.nodeAt(line.path);
        if (node == null || node.isLeaf) return;
        var at = cutAtPoint(node, line.box, local);
        controller.setLayout(
            start.copyWith(
                root: start.root.replaced(line.path, node.withCut(at: at))),
            transient: true);
      case _DragMode.layoutTrack:
        var line = _layoutTrack;
        if (line == null) return;
        var inner = layoutInner(start, start.bounds);
        var from = _intoLayout(start, _dragStart);
        var by = line.column ? local.dx - from.dx : local.dy - from.dy;
        controller.setLayout(
            line.column
                ? start.copyWith(
                    columns: tracksMoved(start.columns, line.index, by,
                        inner.width, start.gutter))
                : start.copyWith(
                    rows: tracksMoved(start.rows, line.index, by, inner.height,
                        start.rowGutter)),
            transient: true);
      case _DragMode.layoutCellMove ||
            _DragMode.layoutCellSize ||
            _DragMode.layoutCellTurn:
        var id = controller.layoutCell(start.id);
        var c = id == null ? null : start.cellById(id);
        if (c == null) return;
        var inner = layoutInner(start, start.bounds);
        LayoutCell moved;
        if (_mode == _DragMode.layoutCellMove) {
          var d = local - _intoLayout(start, _dragStart);
          if (_shiftHeld) {
            d = d.dx.abs() >= d.dy.abs() ? Offset(d.dx, 0) : Offset(0, d.dy);
          }
          moved = c.copyWith(
              x: c.x + d.dx / inner.width, y: c.y + d.dy / inner.height);
        } else if (_mode == _DragMode.layoutCellTurn) {
          var from = _dragStart - _layoutMiddle, to = doc - _layoutMiddle;
          var swept =
              (math.atan2(to.dy, to.dx) - math.atan2(from.dy, from.dx)) *
                  180 /
                  math.pi;
          var turn = c.turn + swept;
          if (_shiftHeld) turn = (turn / 15).round() * 15;
          moved = c.copyWith(turn: (turn + 180) % 360 - 180);
        } else {
          var from = _dragStart - _layoutMiddle, to = doc - _layoutMiddle;
          var along = from.distanceSquared;
          if (along < 1e-6) return;
          var f =
              ((to.dx * from.dx + to.dy * from.dy) / along).clamp(0.05, 20.0);
          var w = c.width * f, h = c.height * f;
          moved = c.copyWith(
              x: c.x + (c.width - w) / 2,
              y: c.y + (c.height - h) / 2,
              width: w,
              height: h);
        }
        controller.setLayout(start.withCell(moved), transient: true);
      default:
    }
  }

  /// _doubleClickLayout picks the cell of [e] under [doc]; none where it is
  /// a gutter. Answers whether [e] was a layout.
  bool _doubleClickLayout(CanvasElement e, Offset doc) {
    if (e is! LayoutElement) return false;
    var place = layoutCellAt(e, e.bounds, _intoLayout(e, doc));
    controller.pickLayoutCell(e.id, place?.cell.id);
    return true;
  }

  /// _removeLayoutCell takes the selected Layout's picked cell out, as
  /// Delete does. Answers whether there was one.
  bool _removeLayoutCell() {
    var e = _oneLayout;
    if (e == null) return false;
    var id = controller.layoutCell(e.id);
    if (id == null || e.shownCells.length < 2) return false;
    controller.removeLayoutCell(e, id);
    return true;
  }
}
