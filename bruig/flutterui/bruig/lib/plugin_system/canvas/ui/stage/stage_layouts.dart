part of 'canvas_stage.dart';

// A Layout (layout_element.dart) handled on the canvas. Selected, its lines
// show: a Panels cut or a Grid line between tracks is dragged to move it,
// and each cut has two knobs -- a ring to tilt it, a square on its
// gutter's edge to widen the gutter.
// Double-clicked, the cell under the pointer is picked (its settings
// show); a picked Free cell has the selection's handles, to move, size and
// turn it. Delete takes the picked cell out (in Panels, merges it).
// Every mark, press and drag is on the layout as it is drawn on this frame,
// turned, slanted and moved by its motion: its geometry in its own box laid
// out by its place there and taken back by the same place (LayoutFrame,
// layout_geometry.dart). Part of CanvasStageState: its fields, lifecycle and
// build are in canvas_stage.dart.

extension StageLayouts on CanvasStageState {
  LayoutElement? get _oneLayout => chosenLayout(controller);

  /// _layoutFrame is [e] on the page on this frame, where the painter
  /// draws it.
  LayoutFrame _layoutFrame(LayoutElement e) =>
      layoutFrameAt(e, controller.frame, document, live: controller.liveMotion);

  /// _layoutMarks is what the painter shows of the selected Layout.
  LayoutMarks? _layoutMarks() {
    // Its reading numbers show locked too: the order is not its shape.
    var chosen = _chosen;
    var e = chosen.length == 1 && chosen.first is LayoutElement
        ? chosen.first as LayoutElement
        : null;
    if (e == null || !controller.showHelpers) return null;
    // Laid out once for the build: its cells, cuts and tracks together.
    var frame = _layoutFrame(e);
    var geometry = frame.geometry;
    var free = !e.locked;
    var cuts = free ? geometry.cuts : const <LayoutCutLine>[];
    var lines = <(Offset, Offset)>[
      for (var c in cuts) (frame.toPage(c.from), frame.toPage(c.to)),
      if (free)
        for (var t in geometry.tracks)
          (frame.toPage(t.from), frame.toPage(t.to)),
    ];
    var knobs = <LayoutCutKnobs>[
      for (var c in cuts)
        if (_cutKnobs(frame, c) case var k?)
          (
            turn: frame.toPage(k.turn),
            gutter: frame.toPage(k.gutter),
            edgeA: (frame.toPage(k.edgeA.$1), frame.toPage(k.edgeA.$2)),
            edgeB: (frame.toPage(k.edgeB.$1), frame.toPage(k.edgeB.$2)),
          ),
    ];
    // Reading numbers, at each cell's middle: the clicked ones while the
    // order is being set, else the layout's own.
    var ordering = controller.orderingLayout == e.id;
    var clicked = controller.orderClicked;
    var badges = <LayoutBadge>[
      for (var p in geometry.places)
        (
          at: frame.toPage(_middleOf(p)),
          number: ordering
              ? (clicked.contains(p.cell.id)
                  ? clicked.indexOf(p.cell.id) + 1
                  : null)
              : e.numberOf(p.cell.id),
          ordering: ordering,
        ),
    ];
    Path? picked;
    var id = controller.layoutCell(e.id);
    if (id != null) {
      var place = layoutPlaceOf(e, e.bounds, id);
      if (place != null) picked = frame.pathOnPage(place.path);
    }
    return (
      lines: EqualList(lines),
      picked: NotCompared(picked),
      pickedCell: picked == null ? null : id,
      knobs: EqualList(knobs),
      badges: EqualList(badges),
    );
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

  /// _cutKnobs is where [line]'s knobs are in its layout's own box: the
  /// turn knob near its end, the gutter knob a quarter along on the gutter's
  /// edge -- kept off the line, where a thin gutter would hide it -- and
  /// the gutter's edges a short way either side of it. Their distances are
  /// a size on screen, so they are taken through the size [frame] draws the
  /// layout at.
  ({
    Offset turn,
    Offset gutter,
    (Offset, Offset) edgeA,
    (Offset, Offset) edgeB
  })? _cutKnobs(LayoutFrame frame, LayoutCutLine line) {
    var e = frame.layout;
    var node = e.root.nodeAt(line.path);
    if (node == null || node.isLeaf) return null;
    var along = line.to - line.from;
    var length = along.distance;
    if (length < 1e-6) return null;
    var dir = along / length, normal = Offset(-dir.dy, dir.dx);
    var half = cutGutter(e, node) / 2;
    var at = Offset.lerp(line.from, line.to, 0.25)!;
    var scale = _scale * frame.place.stretch;
    var reach = 18 / scale;
    return (
      turn: Offset.lerp(line.from, line.to, 0.88)!,
      gutter: at + normal * math.max(half, 9 / scale),
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

  /// _cutKnobAt is the cut of [frame]'s layout whose knob is drawn at
  /// document point [doc], and the drag that knob begins, or null.
  (LayoutCutLine, _DragMode)? _cutKnobAt(LayoutFrame frame, Offset doc) {
    for (var line in frame.geometry.cuts) {
      var k = _cutKnobs(frame, line);
      if (k == null) continue;
      for (var (at, mode) in [
        (k.turn, _DragMode.layoutCutTurn),
        (k.gutter, _DragMode.layoutCutGutter),
      ]) {
        if ((doc - frame.toPage(at)).distance <= 8 / _scale) {
          return (line, mode);
        }
      }
    }
    return null;
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

  /// _freeCellBox is a Free cell's own box on the page and the turn and
  /// slant it is drawn with (LayoutFrame.freeCellBox): its selection box.
  (Rect, BoxFrame) _freeCellBox(LayoutElement e, LayoutCell c) =>
      _layoutFrame(e).freeCellBox(c);

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
          l.bounds.contains(_layoutFrame(l).fromPage(doc))) {
        var place = _layoutFrame(l).cellAt(doc);
        if (place != null) controller.clickReadingOrder(place.cell.id);
        _mode = _DragMode.none;
        return true;
      }
      controller.finishReadingOrder();
    }
    var e = _oneLayout;
    if (e == null) return false;
    // A picked Free cell: its handles size and turn it, inside moves it.
    // Its middle, and where the pointer is, are taken in the layout's own
    // box, where a cell is placed and turned.
    if (_oneFreeCell case (var l, var c)?) {
      var r = freeCellRect(l, l.bounds, c);
      var handle = _hitHandle(stage);
      if (handle != null) {
        _beginLayoutDrag(
            l,
            handle == StageHandle.rotate
                ? _DragMode.layoutCellTurn
                : _DragMode.layoutCellSize);
        _layoutMiddle = r.center;
        return true;
      }
      var local = BoxFrame(c.turn, 0, 0)
              .unplace(_layoutFrame(l).fromPage(doc), r.center) -
          r.center;
      if (local.dx.abs() <= r.width / 2 && local.dy.abs() <= r.height / 2) {
        _beginLayoutDrag(l, _DragMode.layoutCellMove);
        return true;
      }
    }
    // The layout's own handles first: a cut half way meets the middle one.
    if (_hitHandle(stage) != null) return false;
    var frame = _layoutFrame(e);
    var reach = 10 / _scale;
    // A cut's knobs before its line, as they sit on or beside it.
    if (_cutKnobAt(frame, doc) case (var line, var mode)?) {
      _beginLayoutDrag(e, mode);
      _layoutCut = line;
      return true;
    }
    // Each line as it is drawn on the page.
    double away(Offset from, Offset to) =>
        _toSegment(doc, frame.toPage(from), frame.toPage(to));
    for (var line in frame.geometry.cuts) {
      if (away(line.from, line.to) <= reach) {
        _beginLayoutDrag(e, _DragMode.layoutCut);
        _layoutCut = line;
        return true;
      }
    }
    for (var line in frame.geometry.tracks) {
      if (away(line.from, line.to) <= reach) {
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

  /// _applyLayout moves what was pressed as the pointer goes to [doc]:
  /// the pointer taken into the layout's own box by where it is drawn, so
  /// what is dragged stays under it.
  void _applyLayout(Offset doc) {
    var start = _layoutStart;
    if (start == null) return;
    var frame = _layoutFrame(start);
    var local = frame.fromPage(doc);
    var from = frame.fromPage(_dragStart);
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
        LayoutNode next;
        if (_mode == _DragMode.layoutCutTurn) {
          // Turned by as much as the pointer has gone round the pivot.
          var pivot = cutPivot(node, line.box);
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
          var gutter = (cutGutter(start, node) + by * 2).clamp(0.0, 400.0);
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
          var d = local - from;
          if (_shiftHeld) {
            d = d.dx.abs() >= d.dy.abs() ? Offset(d.dx, 0) : Offset(0, d.dy);
          }
          moved = c.copyWith(
              x: c.x + d.dx / inner.width, y: c.y + d.dy / inner.height);
        } else if (_mode == _DragMode.layoutCellTurn) {
          var was = from - _layoutMiddle, to = local - _layoutMiddle;
          var swept = (math.atan2(to.dy, to.dx) - math.atan2(was.dy, was.dx)) *
              180 /
              math.pi;
          var turn = c.turn + swept;
          if (_shiftHeld) turn = steppedTurn(turn);
          moved = c.copyWith(turn: (turn + 180) % 360 - 180);
        } else {
          var was = from - _layoutMiddle, to = local - _layoutMiddle;
          var along = was.distanceSquared;
          if (along < 1e-6) return;
          var f = ((to.dx * was.dx + to.dy * was.dy) / along).clamp(0.05, 20.0);
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
    var place = _layoutFrame(e).cellAt(doc);
    controller.pickLayoutCell(e.id, place?.cell.id);
    return true;
  }
}
