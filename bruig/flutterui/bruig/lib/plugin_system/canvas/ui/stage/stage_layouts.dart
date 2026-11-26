part of 'canvas_stage.dart';

// A Layout (layout_element.dart) handled on the canvas. Selected, its lines
// show: a Panels cut or a Grid line between tracks is dragged to move it,
// and each cut has two knobs -- a ring to tilt it, a square on its
// gutter's edge to widen the gutter.
// Double-clicked, the cell under the pointer is picked (its settings
// show); a picked Free cell has the selection's handles, to move, size and
// turn it. Delete takes the picked cell out (in Panels, merges it). The
// seven drags are cases of StageGesture, at the foot.
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

  /// _cutKnobAt is the drag begun by the knob of [frame]'s layout drawn at
  /// document point [doc], or null: the ring tilts its cut, the square
  /// widens its gutter.
  _CutDrag? _cutKnobAt(LayoutFrame frame, Offset doc) {
    bool at(Offset knob) => (doc - frame.toPage(knob)).distance <= 8 / _scale;
    for (var line in frame.geometry.cuts) {
      var k = _cutKnobs(frame, line);
      if (k == null) continue;
      if (at(k.turn)) return _CutTilt(frame.layout, doc, line);
      if (at(k.gutter)) return _CutGutter(frame.layout, doc, line);
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
    var drag = _layoutDragAt(stage, doc);
    if (drag == null) return false;
    _gesture = drag;
    controller.beginInteraction();
    return true;
  }

  /// _layoutDragAt is the drag a press at [stage] begins on the selected
  /// Layout, or null: on a picked Free cell's handles or inside it, on a
  /// cut's knob, or on a cut or Grid line.
  _LayoutDrag? _layoutDragAt(Offset stage, Offset doc) {
    var e = _oneLayout;
    if (e == null) return null;
    // A picked Free cell: its handles size and turn it, inside moves it.
    // Its middle, and where the pointer is, are taken in the layout's own
    // box, where a cell is placed and turned.
    if (_oneFreeCell case (var l, var c)?) {
      var r = freeCellRect(l, l.bounds, c);
      var handle = _hitHandle(stage);
      if (handle != null) {
        return handle == StageHandle.rotate
            ? _FreeCellTurn(l, doc, c, r.center)
            : _FreeCellSize(l, doc, c, r.center);
      }
      var local = BoxFrame(c.turn, 0, 0)
              .unplace(_layoutFrame(l).fromPage(doc), r.center) -
          r.center;
      if (local.dx.abs() <= r.width / 2 && local.dy.abs() <= r.height / 2) {
        return _FreeCellMove(l, doc, c);
      }
    }
    // The layout's own handles first: a cut half way meets the middle one.
    if (_hitHandle(stage) != null) return null;
    var frame = _layoutFrame(e);
    var reach = 10 / _scale;
    // A cut's knobs before its line, as they sit on or beside it.
    if (_cutKnobAt(frame, doc) case var knob?) return knob;
    // Each line as it is drawn on the page.
    double away(Offset from, Offset to) =>
        _toSegment(doc, frame.toPage(from), frame.toPage(to));
    for (var line in frame.geometry.cuts) {
      if (away(line.from, line.to) <= reach) return _CutMove(e, doc, line);
    }
    for (var line in frame.geometry.tracks) {
      if (away(line.from, line.to) <= reach) return _TrackDrag(e, doc, line);
    }
    return null;
  }

  /// _applyLayout is [drag] with the pointer at [doc]: the pointer and the
  /// press taken into the layout's own box by where it is drawn, so what is
  /// dragged stays under it. It changes the layout as the document has it
  /// now, so a cell taken out meanwhile stays out; once what it holds has
  /// gone, it does nothing.
  void _applyLayout(_LayoutDrag drag, Offset doc) {
    var now = document.elementById(drag.start.id);
    if (now is! LayoutElement) return;
    var frame = _layoutFrame(drag.start);
    var next = drag._moved(
        this, now, frame.fromPage(drag.pressed), frame.fromPage(doc));
    if (next != null) controller.setLayout(next, transient: true);
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

/// _LayoutDrag is a Layout's line or picked Free cell dragged. Each is one
/// undo step, opened as it begins (_pressLayout), and works from the layout
/// as the press found it, so that rounding does not build up.
sealed class _LayoutDrag extends StageGesture {
  _LayoutDrag(this.start, this.pressed);

  /// start is the layout as it was when it was pressed.
  final LayoutElement start;

  /// pressed is where the press landed, in the document.
  final Offset pressed;

  @override
  bool get opensUndoStep => true;

  @override
  bool get waitsToTravel => true;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage._applyLayout(this, doc);

  /// _moved is [now], the layout as the document has it, with the pointer
  /// gone from [from] to [to] in the layout's own box, worked out from
  /// [start]; or null to leave it as it is.
  LayoutElement? _moved(
      CanvasStageState stage, LayoutElement now, Offset from, Offset to);

  @override
  void release(CanvasStageState stage, Offset at,
      {required bool travelled, required bool clicked}) {}

  @override
  void cancel(CanvasStageState stage) {}
}

/// _CutDrag is a Panels cut taken: its line moved, or tilted or widened by
/// a knob.
sealed class _CutDrag extends _LayoutDrag {
  _CutDrag(super.start, super.pressed, this.line);

  /// line is the cut taken, as the press found it.
  final LayoutCutLine line;

  /// was is the cut in [start].
  LayoutNode? get was => start.root.nodeAt(line.path);

  /// _cutIn is [now] with the cut made [next] of itself, or null when [now]
  /// no longer has that cut between the same cells.
  LayoutElement? _cutIn(
      LayoutElement now, LayoutNode Function(LayoutNode) next) {
    var cut = now.root.nodeAt(line.path), before = was;
    if (cut == null || cut.isLeaf || before == null || before.isLeaf) {
      return null;
    }
    if (!listEquals(cut.cells, before.cells)) return null;
    return now.copyWith(root: now.root.replaced(line.path, next(cut)));
  }
}

/// _CutMove is a cut's line dragged to where the pointer is.
class _CutMove extends _CutDrag {
  _CutMove(super.start, super.pressed, super.line);

  @override
  LayoutElement? _moved(
          CanvasStageState stage, LayoutElement now, Offset from, Offset to) =>
      _cutIn(now, (cut) => cut.withCut(at: cutAtPoint(cut, line.box, to)));
}

/// _CutTilt is a cut tilted by its ring knob, by as much as the pointer has
/// gone round the point it turns about; in 5-degree steps with Shift.
class _CutTilt extends _CutDrag {
  _CutTilt(super.start, super.pressed, super.line);

  @override
  LayoutElement? _moved(
      CanvasStageState stage, LayoutElement now, Offset from, Offset to) {
    var before = was;
    if (before == null || before.isLeaf) return null;
    var pivot = cutPivot(before, line.box);
    var a = from - pivot, b = to - pivot;
    var swept =
        (math.atan2(b.dy, b.dx) - math.atan2(a.dy, a.dx)) * 180 / math.pi;
    swept = (swept + 540) % 360 - 180;
    var tilt = before.tilt + swept;
    tilt = stage._shiftHeld
        ? (tilt / 5).round() * 5.0
        : (tilt.abs() < 0.75 ? 0.0 : (tilt * 10).round() / 10);
    return _cutIn(now, (cut) => cut.withCut(tilt: tilt));
  }
}

/// _CutGutter is a cut's gutter widened by its square knob, by twice how
/// far the pointer has gone across the cut, as the gutter grows on both
/// sides of it; in steps of 10 with Shift.
class _CutGutter extends _CutDrag {
  _CutGutter(super.start, super.pressed, super.line);

  @override
  LayoutElement? _moved(
      CanvasStageState stage, LayoutElement now, Offset from, Offset to) {
    var before = was;
    if (before == null || before.isLeaf) return null;
    var along = line.to - line.from;
    var length = along.distance;
    if (length < 1e-6) return null;
    var normal = Offset(-along.dy, along.dx) / length;
    var by = (to - from).dx * normal.dx + (to - from).dy * normal.dy;
    var gutter = (cutGutter(start, before) + by * 2).clamp(0.0, 400.0);
    gutter = stage._shiftHeld
        ? (gutter / 10).round() * 10.0
        : gutter.roundToDouble();
    return _cutIn(now, (cut) => cut.withCut(gutter: gutter));
  }
}

/// _TrackDrag is a Grid's line between two tracks dragged, widening one
/// and narrowing the other.
class _TrackDrag extends _LayoutDrag {
  _TrackDrag(super.start, super.pressed, this.line);

  /// line is the line taken, as the press found it.
  final LayoutTrackLine line;

  @override
  LayoutElement? _moved(
      CanvasStageState stage, LayoutElement now, Offset from, Offset to) {
    if (now.columns.length != start.columns.length ||
        now.rows.length != start.rows.length) {
      return null;
    }
    var inner = layoutInner(start, start.bounds);
    var by = line.column ? to.dx - from.dx : to.dy - from.dy;
    return line.column
        ? now.copyWith(
            columns: tracksMoved(
                start.columns, line.index, by, inner.width, start.gutter))
        : now.copyWith(
            rows: tracksMoved(
                start.rows, line.index, by, inner.height, start.rowGutter));
  }
}

/// _FreeCellDrag is the picked Free cell taken by its own box: moved from
/// inside, sized by a corner or side, or turned by the round handle. It
/// goes on while the cell is in the layout and still the one picked.
sealed class _FreeCellDrag extends _LayoutDrag {
  _FreeCellDrag(super.start, super.pressed, this.cell);

  /// cell is the cell as the press found it.
  final LayoutCell cell;

  @override
  LayoutElement? _moved(
      CanvasStageState stage, LayoutElement now, Offset from, Offset to) {
    if (stage.controller.layoutCell(start.id) != cell.id ||
        now.cellById(cell.id) == null) {
      return null;
    }
    var moved = _cellMoved(stage, from, to);
    return moved == null ? null : now.withCell(moved);
  }

  /// _cellMoved is [cell] with the pointer gone from [from] to [to] in the
  /// layout's own box, or null to leave it as it is.
  LayoutCell? _cellMoved(CanvasStageState stage, Offset from, Offset to);
}

/// _FreeCellMove is the cell moved by the drag, along one axis with Shift.
class _FreeCellMove extends _FreeCellDrag {
  _FreeCellMove(super.start, super.pressed, super.cell);

  @override
  LayoutCell _cellMoved(CanvasStageState stage, Offset from, Offset to) {
    var inner = layoutInner(start, start.bounds);
    var d = to - from;
    if (stage._shiftHeld) {
      d = d.dx.abs() >= d.dy.abs() ? Offset(d.dx, 0) : Offset(0, d.dy);
    }
    return cell.copyWith(
        x: cell.x + d.dx / inner.width, y: cell.y + d.dy / inner.height);
  }
}

/// _FreeCellSize is the cell sized about its middle, by how much farther
/// from it the pointer is along the line pressed on.
class _FreeCellSize extends _FreeCellDrag {
  _FreeCellSize(super.start, super.pressed, super.cell, this.middle);

  /// middle is the cell's middle in the layout's own box at the press.
  final Offset middle;

  @override
  LayoutCell? _cellMoved(CanvasStageState stage, Offset from, Offset to) {
    var was = from - middle, now = to - middle;
    var along = was.distanceSquared;
    if (along < 1e-6) return null;
    var f = ((now.dx * was.dx + now.dy * was.dy) / along).clamp(0.05, 20.0);
    var w = cell.width * f, h = cell.height * f;
    return cell.copyWith(
        x: cell.x + (cell.width - w) / 2,
        y: cell.y + (cell.height - h) / 2,
        width: w,
        height: h);
  }
}

/// _FreeCellTurn is the cell turned by the angle swept about its middle, in
/// 15-degree steps with Shift.
class _FreeCellTurn extends _FreeCellDrag {
  _FreeCellTurn(super.start, super.pressed, super.cell, this.middle);

  /// middle is the cell's middle in the layout's own box at the press.
  final Offset middle;

  @override
  LayoutCell _cellMoved(CanvasStageState stage, Offset from, Offset to) {
    var was = from - middle, now = to - middle;
    var swept = (math.atan2(now.dy, now.dx) - math.atan2(was.dy, was.dx)) *
        180 /
        math.pi;
    var turn = cell.turn + swept;
    if (stage._shiftHeld) turn = steppedTurn(turn);
    return cell.copyWith(turn: (turn + 180) % 360 - 180);
  }
}
