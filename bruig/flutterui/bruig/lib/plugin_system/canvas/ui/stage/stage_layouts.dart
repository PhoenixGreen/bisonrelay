part of 'canvas_stage.dart';

// A Layout (layout_element.dart) handled on the canvas. Selected, its lines
// show: a Panels cut or a Grid line between tracks is dragged to move it,
// and each cut has two knobs -- a ring to tilt it, a square on its
// gutter's edge to widen the gutter.
// Double-clicked, the cell under the pointer is picked (its settings
// show); a picked Free cell has the selection's handles, to move, size and
// turn it. Delete takes the picked cell out (in Panels, merges it). Part of
// CanvasStageState: its fields, lifecycle and build are in canvas_stage.dart.

extension StageLayouts on CanvasStageState {
  LayoutElement? get _oneLayout => chosenLayout(controller);

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
    // Its reading numbers show locked too: the order is not its shape.
    var chosen = _chosen;
    var e = chosen.length == 1 && chosen.first is LayoutElement
        ? chosen.first as LayoutElement
        : null;
    if (e == null || !controller.showHelpers) return null;
    var free = !e.locked;
    var lines = <(Offset, Offset)>[
      if (free) ...[
        for (var c in layoutCutLines(e, e.bounds))
          (_outOfLayout(e, c.from), _outOfLayout(e, c.to)),
        for (var t in layoutTrackLines(e, e.bounds))
          (_outOfLayout(e, t.from), _outOfLayout(e, t.to)),
      ],
    ];
    var knobs = [
      for (var c
          in free ? layoutCutLines(e, e.bounds) : const <LayoutCutLine>[])
        if (_cutKnobs(e, c) case var k?)
          LayoutCutKnobs(
              _outOfLayout(e, k.turn),
              _outOfLayout(e, k.gutter),
              (_outOfLayout(e, k.edgeA.$1), _outOfLayout(e, k.edgeA.$2)),
              (_outOfLayout(e, k.edgeB.$1), _outOfLayout(e, k.edgeB.$2))),
    ];
    // Reading numbers, at each cell's middle: the clicked ones while the
    // order is being set, else the layout's own.
    var ordering = controller.orderingLayout == e.id;
    var clicked = controller.orderClicked;
    var badges = [
      for (var p in layoutPlaces(e, e.bounds))
        LayoutBadge(
            _outOfLayout(e, _middleOf(p)),
            ordering
                ? (clicked.contains(p.cell.id)
                    ? clicked.indexOf(p.cell.id) + 1
                    : null)
                : e.numberOf(p.cell.id),
            ordering: ordering),
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
    return LayoutMarks(lines, picked, knobs: knobs, badges: badges);
  }

  /// _middleOf is the middle of a cell's outline: the mean of its corners,
  /// inside it whatever its slant.
  static Offset _middleOf(LayoutPlace p) {
    if (p.points.isEmpty) return p.bounds.center;
    var sum = Offset.zero;
    for (var q in p.points) {
      sum += q;
    }
    return sum / p.points.length.toDouble();
  }

  /// _cutKnobs is where [line]'s knobs are in [e]'s own frame: the turn
  /// knob near its end, the gutter knob a quarter along on the gutter's
  /// edge -- kept off the line, where a thin gutter would hide it -- and
  /// the gutter's edges a short way either side of it.
  ({
    Offset turn,
    Offset gutter,
    (Offset, Offset) edgeA,
    (Offset, Offset) edgeB
  })? _cutKnobs(LayoutElement e, LayoutCutLine line) {
    var node = e.root.nodeAt(line.path);
    if (node == null || node.isLeaf) return null;
    var along = line.to - line.from;
    var length = along.distance;
    if (length < 1e-6) return null;
    var dir = along / length, normal = Offset(-dir.dy, dir.dx);
    var half = _cutGutterOf(e, node) / 2;
    var at = Offset.lerp(line.from, line.to, 0.25)!;
    var reach = 18 / _scale;
    return (
      turn: Offset.lerp(line.from, line.to, 0.88)!,
      gutter: at + normal * math.max(half, 9 / _scale),
      edgeA: (
        at + normal * half - dir * reach,
        at + normal * half + dir * reach
      ),
      edgeB: (
        at - normal * half - dir * reach,
        at - normal * half + dir * reach
      ),
    );
  }

  static double _cutGutterOf(LayoutElement e, LayoutNode n) =>
      n.gutter ?? (n.vertical ? e.gutter : e.rowGutter);

  /// _cutPivot is the point a cut turns about, in its layout's frame: where
  /// it crosses its box's middle, which its place (at) names.
  static Offset _cutPivot(LayoutNode n, Rect box) => n.vertical
      ? Offset(box.left + n.at * box.width, box.center.dy)
      : Offset(box.center.dx, box.top + n.at * box.height);

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
    // Setting the reading order: a cell clicked is numbered next; a press
    // off the layout ends it, kept.
    if (controller.orderingLayout case var id?) {
      var l = controller.document.elementById(id);
      if (l is LayoutElement &&
          l.visible &&
          l.bounds.contains(_intoLayout(l, doc))) {
        var place = layoutCellAt(l, l.bounds, _intoLayout(l, doc));
        if (place != null) controller.clickReadingOrder(place.cell.id);
        _mode = _DragMode.none;
        return true;
      }
      controller.finishReadingOrder();
    }
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
    // A cut's knobs before its line, as they sit on or beside it.
    for (var line in layoutCutLines(e, e.bounds)) {
      var k = _cutKnobs(e, line);
      if (k == null) continue;
      for (var (at, mode) in [
        (k.turn, _DragMode.layoutCutTurn),
        (k.gutter, _DragMode.layoutCutGutter),
      ]) {
        if ((local - at).distance <= 8 / _scale) {
          _beginLayoutDrag(e, mode);
          _layoutCut = line;
          return true;
        }
      }
    }
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
      case _DragMode.layoutCutTurn || _DragMode.layoutCutGutter:
        var line = _layoutCut;
        if (line == null) return;
        var node = start.root.nodeAt(line.path);
        if (node == null || node.isLeaf) return;
        var from = _intoLayout(start, _dragStart);
        LayoutNode next;
        if (_mode == _DragMode.layoutCutTurn) {
          // Turned by as much as the pointer has gone round the pivot.
          var pivot = _cutPivot(node, line.box);
          var a = from - pivot, b = local - pivot;
          var swept =
              (math.atan2(b.dy, b.dx) - math.atan2(a.dy, a.dx)) * 180 / math.pi;
          swept = (swept + 540) % 360 - 180;
          var tilt = node.tilt + swept;
          tilt = _shiftHeld
              ? (tilt / 5).round() * 5.0
              : (tilt.abs() < 0.75 ? 0.0 : (tilt * 10).round() / 10);
          next = node.withCut(tilt: tilt);
        } else {
          // Widened by twice how far the pointer has gone across the cut,
          // as the gutter grows on both sides of it.
          var along = line.to - line.from;
          var length = along.distance;
          if (length < 1e-6) return;
          var normal = Offset(-along.dy, along.dx) / length;
          var by =
              (local - from).dx * normal.dx + (local - from).dy * normal.dy;
          var gutter = (_cutGutterOf(start, node) + by * 2).clamp(0.0, 400.0);
          next = node.withCut(
              gutter: _shiftHeld
                  ? (gutter / 10).round() * 10.0
                  : gutter.roundToDouble());
        }
        controller.setLayout(
            start.copyWith(root: start.root.replaced(line.path, next)),
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
}
