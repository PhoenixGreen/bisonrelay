part of 'canvas_stage.dart';

// A drag on the canvas: moving, resizing, skewing and turning what was pressed,
// from the press that begins it (_beginTransform) to each step that applies
// it; a chart's label, a table's column rule, an anchor and the held marker's
// note dragged. Part of CanvasStageState: its fields, lifecycle and build are
// in canvas_stage.dart.

extension StageDrag on CanvasStageState {
  /// _docSlop is the pointer's reach in document units: the slop is in
  /// screen pixels (how still a hand is), so divided by the zoom.
  double get _docSlop => handleHitSlop / _scale;

  /// _applyChartLabel moves or sizes the selected chart's label taken by
  /// [grab] to [doc] (stage_parts.dart works out the new chart). Transient:
  /// the drag is one undo step.
  void _applyChartLabel(ChartLabelGrab grab, Offset doc) {
    var element = controller.selected;
    if (element is! ChartElement) return;
    var next = chartLabelDragged(element, _hit.posed(element), grab, doc);
    if (next != null) controller.replaceElement(next, transient: true);
  }

  /// _applyTableColumn moves the selected table's rule right of [column] to
  /// [doc] (stage_parts.dart works out the new table). Transient: the drag
  /// is one undo step.
  void _applyTableColumn(int column, Offset doc) {
    var element = controller.selected;
    if (element is! TableElement) return;
    var next = tableColumnDragged(element, _hit.posed(element), column, doc);
    if (next != null) controller.replaceElement(next, transient: true);
  }

  /// _applyAnchor puts element [id]'s anchor point at [doc], where it is
  /// laid out on this frame, and leaves what is drawn there where it is: on
  /// a frame its keys or its loop turn or size it about the anchor, its
  /// resting box moves to make up for the anchor's move
  /// (CanvasElement.anchorDrawnAt), so where it rests, and where its keys
  /// turn it from, move with it. Transient: the drag is one undo step.
  void _applyAnchor(String id, Offset doc) {
    if (document.elementById(id) case var e?) {
      var on = _hit.placed(e);
      var (ax, ay, shift) = on.drawn.anchorDrawnAt(doc, on.pose, on.box);
      var rest = _restOfDrawn(e, on.box.shift(shift));
      controller.replaceElement(
          e.withBase(anchorX: ax, anchorY: ay, x: rest.left, y: rest.top),
          transient: true);
    }
  }

  /// _anchorDrawn is where [e]'s anchor is drawn on this frame, which its
  /// mark shows and a press takes.
  Offset _anchorDrawn(CanvasElement e) {
    var on = _hit.placed(e);
    return on.place.place(on.drawn.anchorIn(on.box));
  }

  /// _restOfDrawn is the box [e] rests in for its box to be laid out from
  /// [drawn]: the same box, but for a page number mirrored onto a left-hand
  /// page, which rests across the page from where it is drawn
  /// (CounterElement.drawnBox).
  Rect _restOfDrawn(CanvasElement e, Rect drawn) => e is CounterElement
      ? e.drawnBox(drawn,
          page: document.size.rect, leftHand: document.pageIsLeftHand)
      : drawn;

  /// _dragMarkerNote moves the held marker's label for [drag], or sizes it
  /// by the pointer's distance from its middle.
  void _dragMarkerNote(_MarkerNoteDrag drag, Offset doc) {
    var was = drag.was;
    var page = controller.document.size.size;
    TimelineAction next;
    if (drag.sizing) {
      var centre =
          Offset(was.noteAt.dx * page.width, was.noteAt.dy * page.height);
      var from = (drag.from - centre).distance;
      var ratio = from < 1 ? 1.0 : (doc - centre).distance / from;
      next = was.copyWith(
          noteSize: (was.noteSize * ratio).clamp(0.3, 6.0).toDouble());
    } else {
      var by = doc - drag.from;
      next = was.copyWith(
          noteAt: Offset((was.noteAt.dx + by.dx / page.width).clamp(0.0, 1.0),
              (was.noteAt.dy + by.dy / page.height).clamp(0.0, 1.0)));
    }
    replaceMarker(controller, next, transient: true);
  }

  /// _snapReach is how near a line, in document units, what is dragged
  /// on this step must come to be caught: the guides' snapWithin is in
  /// screen pixels (the hand's aim does not improve with zoom), so divided
  /// by the zoom. Null while Alt is held, which frees every drag that
  /// snaps: to lines, to a line's angles, or to a 3D stage's steps.
  double? get _snapReach => HardwareKeyboard.instance.isAltPressed
      ? null
      : document.guides.snapWithin / _scale;

  /// _hasTravelled is whether the press has gone far enough, to [stage], to
  /// be a drag: once it has, it stays one.
  bool _hasTravelled(Offset stage) {
    if (_travelled) return true;
    if ((stage - _pressedAt).distance <= CanvasStageState._dragThreshold) {
      return false;
    }
    _travelled = true;
    return true;
  }

  void _onPointerMove(PointerMoveEvent event) {
    // A gesture that takes every move before the stage's own steps: see
    // StageGesture.takesAll.
    if (_gesture case var gesture? when gesture.takesAll) {
      _moveGesture(gesture, event.localPosition);
      return;
    }
    _pointer = event;
    // Pressed as well as hovering: the brush ring must follow a stroke.
    _hoverAt = event.localPosition;
    if (_brushAt != null) _moveBrush(event.localPosition);
    if (_gesture case var gesture?) {
      _moveGesture(gesture, event.localPosition);
      return;
    }
    if (_mode == _DragMode.none) {
      _updateHover(event.localPosition);
      return;
    }

    // Nothing moves until the press travels far enough to be a drag.
    if (!_hasTravelled(event.localPosition)) return;

    var doc = _toDocument(event.localPosition);

    switch (_mode) {
      case _DragMode.warpMove ||
            _DragMode.warpScale ||
            _DragMode.warpTurn ||
            _DragMode.warpMarquee:
        _dragWarp(doc);
      case _DragMode.vectorPoint:
        _applyVectorMove(doc);
      case _DragMode.vectorPoints:
        var before = _vectorBefore;
        if (before != null) {
          var space = VectorSpace(before);
          var by = space.toDrawing(doc) - space.toDrawing(_vectorFrom);
          controller.replaceElement(
              withPointsMoved(before, controller.vectorPicks, by),
              transient: true);
        }
      case _DragMode.vectorMarquee:
        setState(() => _marquee = Rect.fromPoints(_dragStart, doc));
      case _DragMode.vectorScale:
        _applyScale(doc);
      case _DragMode.vectorTint:
        _applyTint(doc);
      case _DragMode.vectorCorner:
        _applyCorner(doc);
      case _DragMode.vectorPencil:
        _applyPencil(doc);
      case _DragMode.vectorKnife:
        if ((doc - _knife.last).distance * _scale >= 2) {
          setState(() => _knife = [..._knife, doc]);
        }
      case _DragMode.vectorShapeDraw:
        _drawShape(doc);
      case _DragMode.vectorShapeFit:
        _fitShape(doc);
      case _DragMode.vectorItems:
        _dragItems(doc);
      case _DragMode.vectorItemsBox:
        setState(() => _marquee = Rect.fromPoints(_dragStart, doc));
      case _DragMode.vectorRub:
        if (_onPage(doc)) _carryStroke(doc);
      case _DragMode.vectorErase:
        if (controller.editingVector case var e?) {
          var next = withoutShapesAt(e, doc, _eraseReach);
          if (!identical(next, e)) {
            controller.replaceElement(next, transient: true);
          }
        }
      case _DragMode.vectorPen:
        var e = controller.editingVector, pick = controller.vectorPick;
        if (e != null && pick != null) {
          // A hand that shifts a little as it clicks puts a corner down:
          // handles a few pixels long would round it off.
          var pulled = (doc - _vectorFrom).distance * _scale >=
              CanvasStageState._penPullMin;
          controller.replaceElement(
              withPenHandles(e, pick, pulled ? doc : _vectorFrom),
              transient: true);
        }
      case _DragMode.imageFrame:
        _applyFraming(doc);
      case _DragMode.imageLayerMove ||
            _DragMode.imageLayerSize ||
            _DragMode.imageLayerTurn:
        _dragLayer(doc);
      case _DragMode.imageMask:
        _dragMask(doc);
      case _DragMode.imageBrush:
        _dragBrush(doc);
      case _DragMode.imageQuick:
        if (_maskOn case var on?) {
          setState(() => _quickTrail = [..._quickTrail, on.toPicture(doc)]);
        }
      default:
        break;
    }
  }

  /// _beginTransform begins a move, resize, slant or turn of the selection:
  /// it notes where each selected element started, which every step of the
  /// drag works from, and opens the undo step that the gesture's end
  /// closes. The press that calls it makes the gesture (a _BoxDrag) from
  /// what it returns.
  _BoxStart _beginTransform() {
    // Whatever mode an earlier press left: this press is the box's.
    _mode = _DragMode.none;
    var moving = {for (var e in controller.selectedElements) e.id};
    var start = _BoxStart(
      bounds: {
        for (var e in controller.selectedElements) e.id: e.bounds,
      },
      // And the elements themselves, for a resize that scales what is
      // inside: its factor is measured from the drag's start.
      elements: {
        for (var e in controller.selectedElements) e.id: e,
      },
      // Where each element is on this frame, which a move works from. A
      // resize writes the resting size, as a posed size would bake a scale
      // in, but is laid out here and taken back (_restingAfterResize), so
      // the corner held stays where it is drawn. A move from the resting
      // bounds would lose the frame's pose.
      posed: {
        for (var e in controller.selectedElements) e.id: _hit.posed(e),
      },
      // What a move writes: each element's value at the press plus the
      // travel, never where it is drawn, which holds whatever else moves it
      // on this frame (CanvasController.moveOrigin).
      from: {
        for (var e in controller.selectedElements)
          e.id: controller.moveOrigin(e),
      },
      // The box the handles are on, bigger than the element's own for a
      // line or path (see _visualBounds). A resize is measured against it
      // and applied to the real rectangle in proportion.
      visual: {
        for (var e in controller.selectedElements) e.id: _visualBounds(e),
      },
      seen: {
        for (var e in controller.selectedElements) e.id: _seenBounds(e),
      },
      rotation: {
        for (var e in controller.selectedElements) e.id: e.rotation,
      },
      placed: _lonePlaced(),
      snapper: Snapper(document.guides, document.size.size,
          others: _otherBounds(moving)),
    );
    controller.beginInteraction();
    return start;
  }

  /// _lonePlaced is the lone selection as the painter lays it out on this
  /// frame, where its box is laid out by that place (_loneBox): what a resize,
  /// slant or turn of it works from. Null for several, one copy of several
  /// (sized and turned by its own values: _beginCopyBox), and whatever keeps
  /// a box of its own.
  ElementOnPage? _lonePlaced() {
    if (_oneCopy != null || _loneBox == null) return null;
    var e = _chosen.single;
    return _hit.placed(e, instance: e.base.motion.instances == null ? null : 0);
  }

  /// _otherBounds is everything not dragged, locked included, to snap to:
  /// the upright box round each as it is drawn now, turned and all, each
  /// copy of one reused by its own (StageHitTest.reaches). [moving] is the
  /// ids of the selection being dragged.
  List<Rect> _otherBounds(Set<String> moving) {
    if (!document.guides.snapTo.objects) return const [];
    var hit = _hit;
    return [
      for (var element in document.elements)
        if (!moving.contains(element.base.id) && element.base.visible)
          ...(hit.reaches(element) ?? [hit.posed(element)]),
    ];
  }

  /// _seenBounds is the upright box [e] is seen in, so it is snapped by the
  /// corners that show: round its box as it is drawn on this frame
  /// (_drawnReach), or for what keeps an answer of its own, the box its
  /// handles are on (see _visualBounds) turned and slanted about its middle.
  Rect _seenBounds(CanvasElement e) {
    if (_hit.reach(e) case var drawn?) return drawn;
    var box = _visualBounds(e);
    // A line's or a path's is round its curve as drawn already.
    if (e is StrokedElement) return box;
    var frame = BoxFrame(
        e.movedRotationAt(controller.frame, document,
            live: controller.liveMotion),
        e.base.skewX,
        e.base.skewY);
    if (frame.upright) return box;
    var corners = frame.corners(box);
    var xs = corners.map((p) => p.dx), ys = corners.map((p) => p.dy);
    return Rect.fromLTRB(xs.reduce(math.min), ys.reduce(math.min),
        xs.reduce(math.max), ys.reduce(math.max));
  }

  /// _applyMove moves the selection by [delta] from where [start] found
  /// it, and says which lines the move is caught on.
  SnapLines _applyMove(Offset delta, _BoxStart start) {
    if (_shiftHeld) {
      delta = delta.dx.abs() > delta.dy.abs()
          ? Offset(delta.dx, 0)
          : Offset(0, delta.dy);
    }
    // Snapped once, against the whole selection's box as it is seen, so
    // things moved together stay together. Alt turns it off.
    var box = start.seenBox;
    // Not on a 3D stage, where page lines mean nothing: staged elements snap
    // to the floor's 3D steps (see CanvasController.movedTo).
    var onStage = start.from.keys
        .any((id) => document.elementById(id)?.base.spot != null);
    var reach = _snapReach;
    var caught = SnapLines.none;
    if (reach != null && box != null && !onStage) {
      var snap = start.snapper.move(box.shift(delta), reach: reach);
      delta += snap.nudge;
      caught = snap.lines;
    }

    var next = document;
    for (var entry in start.from.entries) {
      var element = next.elementById(entry.key);
      if (element == null || element.locked) continue;
      // A camera moves by where it looks, from its start: its frame is not
      // its box (see cameraFraming).
      if (start.elements[entry.key] case CameraElement camera) {
        next = next.withElement(controller.cameraShifted(camera, delta));
        continue;
      }
      // A page number drawn mirrored across the page is placed the other
      // way across, so what is drawn follows the pointer (drawnBox).
      var by = element is CounterElement &&
              element.mirroredOn(leftHand: document.pageIsLeftHand)
          ? Offset(-delta.dx, delta.dy)
          : delta;
      // Through the controller, so an animated element is posed rather than
      // moved. See CanvasController.posesRatherThanMoves.
      next = next.withElement(
          controller.movedTo(element, entry.value + by, free: reach == null));
    }
    controller.apply(next, transient: true);
    return caught;
  }

  /// _applyLineEnd drags one end of a single straight line, if [handle] is
  /// on one, and says whether it did. A line is its two ends, not a box (a
  /// box is at least eight pixels deep, so a line could never be level). Its
  /// ends are where it is drawn on this frame, turned, slanted and moved by
  /// its motion, and so at two corners of the box round it as drawn; the
  /// corner nearer an end takes that end. The end goes under the pointer and
  /// the other stays where it is drawn, the line's resting ends being laid
  /// so (LineElement.withEndsDrawnAt): like a path's point, an end is moved,
  /// not posed, whatever frame it is dragged on, and its motion is left as
  /// it is. The end snaps to level, upright or diagonal on the page within a
  /// few degrees, always with Shift; Alt frees it.
  bool _applyLineEnd(StageHandle handle, Offset delta, _BoxStart from) {
    // A lone line's box is always upright (_boxIsDrawn); one copy of a
    // reused line has a box of its own.
    if (from.visual.length != 1 || !_frameOfSelection.upright) return false;
    // The line at the drag's start: every step works from it, since crossing
    // one end past the other swaps the ends and their arrows.
    var line = from.elements[from.visual.keys.first];
    if (line is! LineElement || line.curvature != 0 || line.locked) {
      return false;
    }
    var pose = line.drawnPoseAt(controller.frame, document,
        live: controller.liveMotion);
    var place = line.placedBy(pose);
    var start = place.place(line.start);
    var end = place.place(line.end);
    var box = from.visual.values.first;
    var corner = switch (handle) {
      StageHandle.topLeft => box.topLeft,
      StageHandle.topRight => box.topRight,
      StageHandle.bottomLeft => box.bottomLeft,
      StageHandle.bottomRight => box.bottomRight,
      _ => null,
    };
    if (corner == null) return false;
    var movesStart = (corner - start).distance < (corner - end).distance;
    var fixed = movesStart ? end : start;
    var moving = (movesStart ? start : end) + delta;
    if (_snapReach != null) {
      moving = snapLineAngle(fixed, moving, always: _shiftHeld);
    }
    var next = movesStart
        ? line.withEndsDrawnAt(moving, fixed, pose)
        : line.withEndsDrawnAt(fixed, moving, pose);
    controller.apply(document.withElement(next), transient: true);
    return true;
  }

  /// _applyCameraZoom zooms the one selected camera by a handle dragged
  /// [delta], and says whether it did: out shows more, in less, about the
  /// frame's middle, which keeps the page's shape.
  bool _applyCameraZoom(StageHandle handle, Offset delta, _BoxStart from) {
    if (from.elements.length != 1) return false;
    var start = from.elements.values.first;
    if (start is! CameraElement || start.locked) return false;
    var frame = from.posed[start.id];
    if (frame == null) return false;
    var mid = frame.center;
    double? ratio(double edge, double centre, double by) {
      var was = edge - centre;
      if (was.abs() < 1e-6) return null;
      return (was + by) / was;
    }

    var rx = handle.movesLeft
        ? ratio(frame.left, mid.dx, delta.dx)
        : handle.movesRight
            ? ratio(frame.right, mid.dx, delta.dx)
            : null;
    var ry = handle.movesTop
        ? ratio(frame.top, mid.dy, delta.dy)
        : handle.movesBottom
            ? ratio(frame.bottom, mid.dy, delta.dy)
            : null;
    var grow = math.max(rx ?? 0, ry ?? 0);
    if (grow <= 0) grow = 0.05;
    controller.apply(
        document.withElement(controller.cameraZoomed(start, 1 / grow)),
        transient: true);
    return true;
  }

  /// _applySkew slants the one selected element by a side handle dragged
  /// [delta]: top or bottom across, left or right up and down. The held side
  /// follows the pointer and the opposite stays put, so the element slants
  /// about its middle and moves by half as much.
  void _applySkew(Offset delta, StageHandle handle, _BoxStart from) {
    if (from.elements.length != 1) return;
    var start = from.elements.values.first;
    if (start.locked) return;
    if (from.placed case var on? when !on.place.turnsAndSlantsOnly) {
      _skewAsDrawn(delta, handle, start, on);
      return;
    }
    var box = start.bounds;
    // The drag in the element's turned frame but not its slanted one: the
    // slant is what changes.
    var d = BoxFrame(-start.rotation, 0, 0).apply(delta);
    double tanOf(double deg) => math.tan(deg * math.pi / 180);
    double degOf(double t) =>
        (math.atan(t) * 180 / math.pi).clamp(-maxSkew, maxSkew);
    var skewX = start.base.skewX, skewY = start.base.skewY;
    Offset shift;
    switch (handle) {
      case StageHandle.topCenter || StageHandle.bottomCenter:
        if (box.height <= 0) return;
        var sign = handle == StageHandle.topCenter ? -1 : 1;
        skewX = degOf(tanOf(skewX) + sign * d.dx / box.height);
        shift = Offset(d.dx / 2, 0);
      case StageHandle.centerLeft || StageHandle.centerRight:
        if (box.width <= 0) return;
        var sign = handle == StageHandle.centerLeft ? -1 : 1;
        skewY = degOf(tanOf(skewY) + sign * d.dy / box.width);
        shift = Offset(0, d.dy / 2);
      default:
        return;
    }
    var page = BoxFrame(start.rotation, 0, 0).apply(shift);
    controller.replaceElement(
        start.withBase(
            skewX: skewX,
            skewY: skewY,
            x: start.x + page.dx,
            y: start.y + page.dy),
        transient: true);
  }

  /// _skewAsDrawn slants [start], laid out by [on] on a frame where more than
  /// its own turn and slant place it (its keys or its loop turn, size or
  /// squash it, or something moves it), by a side handle dragged [delta]:
  /// the side opposite stays where it is drawn and the side pulled follows
  /// the pointer as far as a slant can take it. A slant shears along the
  /// element's own across (or down), as it rests, applied after what its keys
  /// and loop turn, so the side pulled travels along one line on the page for
  /// each; of its own slant and the other, the one that takes it further is
  /// changed, so a side its loop has spun upright still leans along itself.
  void _skewAsDrawn(
      Offset delta, StageHandle handle, CanvasElement start, ElementOnPage on) {
    var box = on.box;
    var (pulled, kept, across) = switch (handle) {
      StageHandle.topCenter => (box.topCenter, box.bottomCenter, true),
      StageHandle.bottomCenter => (box.bottomCenter, box.topCenter, true),
      StageHandle.centerLeft => (box.centerLeft, box.centerRight, false),
      StageHandle.centerRight => (box.centerRight, box.centerLeft, false),
      _ => (null, null, true),
    };
    if (pulled == null || kept == null || on.place.flattens) return;
    double tanOf(double deg) => math.tan(deg * math.pi / 180);
    double degOf(double t) => math.atan(t) * 180 / math.pi;
    var base = on.drawn.base;
    ElementPlace slanted(double x, double y) =>
        on.drawn.withBase(skewX: x, skewY: y).placedIn(box, on.pose);
    Offset span(ElementPlace p) => p.place(pulled) - p.place(kept);
    // How far the side pulled moves, the other kept still, for one more of
    // each slant's tangent: a slant is a shear, so it goes as far again for
    // each one more.
    var was = span(on.place);
    var tx = tanOf(base.skewX), ty = tanOf(base.skewY);
    var byX = span(slanted(degOf(tx + 1), base.skewY)) - was;
    var byY = span(slanted(base.skewX, degOf(ty + 1))) - was;
    var useX = across
        ? byX.distanceSquared >= byY.distanceSquared
        : byX.distanceSquared > byY.distanceSquared;
    var travel = useX ? byX : byY;
    if (travel.distanceSquared < 1e-12) return;
    var more =
        (delta.dx * travel.dx + delta.dy * travel.dy) / travel.distanceSquared;
    double clamped(double t) => degOf(t).clamp(-maxSkew, maxSkew);
    var skewX = useX ? clamped(tx + more) : base.skewX;
    var skewY = useX ? base.skewY : clamped(ty + more);
    // The box moved so the side opposite is drawn where it was.
    var shift = on.place.place(kept) - slanted(skewX, skewY).place(kept);
    var rest = _restOfDrawn(start, box.shift(shift));
    controller.replaceElement(
        start.withBase(skewX: skewX, skewY: skewY, x: rest.left, y: rest.top),
        transient: true);
  }

  /// _applyResize resizes the selection by [handle] dragged [delta] from
  /// where [start] found it, and says which lines the dragged edge is
  /// caught on.
  SnapLines _applyResize(Offset delta, StageHandle handle, _BoxStart start) {
    if (_applyLineEnd(handle, delta, start)) return SnapLines.none;
    if (_applyCameraZoom(handle, delta, start)) return SnapLines.none;
    // A lone element turned, slanted or moved on this frame is sized where
    // it is drawn. Several, an upright element nothing moves, and what keeps
    // a box of its own are sized by their boxes as they rest.
    if (start.placed case var on?
        when !on.place.turnsAndSlantsOnly ||
            on.drawn.rotation != 0 ||
            on.drawn.base.skewX != 0 ||
            on.drawn.base.skewY != 0) {
      return _resizeAsDrawn(delta, handle, start, on);
    }

    // One box for the whole drag, so things resized together keep their sizes
    // and gaps in proportion.
    var group = start.visualBox;
    if (group == null) return SnapLines.none;

    // The dragged edge alone lands on the lines a move does, so the held
    // edge stays put: upright boxes only, and Alt turns it off.
    var caught = SnapLines.none;
    if (_snapReach case var reach? when _frameOfSelection.upright) {
      var snap = start.snapper.edges(group.shift(delta),
          left: handle.movesLeft,
          top: handle.movesTop,
          right: handle.movesRight,
          bottom: handle.movesBottom,
          reach: reach);
      delta += snap.nudge;
      caught = snap.lines;
    }

    // Into the element's own frame, so pulling a tilted element's right edge
    // widens it rather than moving it sideways.
    delta = _frameOfSelection.invert(delta);

    var several = start.visual.length > 1;
    var first = document.elementById(start.visual.keys.first);
    var (keep, inside) = _resizeHolds(first, several: several);
    var (left, top, right, bottom) = _resizedEdges(
        group,
        handle,
        group.left + (handle.movesLeft ? delta.dx : 0),
        group.top + (handle.movesTop ? delta.dy : 0),
        group.right + (handle.movesRight ? delta.dx : 0),
        group.bottom + (handle.movesBottom ? delta.dy : 0),
        keep: keep);

    var sx = group.width == 0 ? 1.0 : (right - left) / group.width;
    var sy = group.height == 0 ? 1.0 : (bottom - top) / group.height;

    var next = document;
    for (var entry in start.visual.entries) {
      var element = next.elementById(entry.key);
      if (element == null || element.locked) continue;
      var visual = entry.value;
      var real = start.bounds[entry.key] ?? visual;
      var width = math.max(1.0, real.width * sx);
      var height = math.max(1.0, real.height * sy);
      // Laid out where it is drawn on this frame, as the box the handles are
      // on is, then taken back to where it rests: on a frame its motion
      // moves or sizes it, the corner held stays where it is drawn.
      var (x, y) = _restingAfterResize(element, real, start.posed[entry.key],
          left, top, group, sx, sy, width, height);

      // Proportions the person keeps scale everything inside (type,
      // spacing, a chip's padding), from the element at the drag's start.
      var from = start.elements[entry.key] ?? element;
      element = inside ? from.scaledBy(sx) : element;
      next = next.withElement(element.withBase(
        x: x,
        y: y,
        width: width,
        height: height,
        // The scale applied inside the box, kept where the shape switch reads
        // it (see ElementBase.typeScale), so a shape change does not undo the
        // drag by the wrong amount.
        typeScale: inside ? from.base.typeScale * sx : null,
      ));
    }
    controller.apply(next, transient: true);
    return caught;
  }

  /// _resizeHolds is whether a resize keeps the proportions, and whether it
  /// scales what is inside, for the selection whose first element is
  /// [first]. Shift keeps proportions; a picture keeps them without the key,
  /// Shift freeing it (see CanvasElement.keepsAspect), as does a group:
  /// pulled out of shape, every gap would be. A hold the person asks for
  /// scales the inside. One its kind keeps (a square or a circle) Shift
  /// cannot let go, so there Shift is the other thing a held resize could
  /// do: scale the inside, or not.
  (bool, bool) _resizeHolds(CanvasElement? first, {required bool several}) {
    var keep = several
        ? !_shiftHeld
        : ((first?.keepsAspect ?? false) ? !_shiftHeld : _shiftHeld);
    var inside = keep;
    if (!several && (first?.keepsAspectByKind ?? false)) {
      keep = true;
      inside = first!.base.lockAspect != _shiftHeld;
    }
    return (keep, inside);
  }

  /// _resizedEdges is [box] pulled by [handle] to [left], [top], [right] and
  /// [bottom], kept in its proportions by whichever way it moved further if
  /// [keep], and no smaller than a minimum: the sides the handle does not
  /// move stay where they are.
  (double, double, double, double) _resizedEdges(Rect box, StageHandle handle,
      double left, double top, double right, double bottom,
      {required bool keep}) {
    if (keep && box.height > 0) {
      var aspect = box.width / box.height;
      if ((right - left).abs() > (bottom - top).abs() * aspect) {
        var height = (right - left).abs() / aspect;
        handle.movesTop ? top = bottom - height : bottom = top + height;
      } else {
        var width = (bottom - top).abs() * aspect;
        handle.movesLeft ? left = right - width : right = left + width;
      }
    }

    // A minimum size, not a selection turned inside out: a negative width
    // draws nothing and cannot be grabbed again.
    const minimum = 8.0;
    if (right - left < minimum) {
      handle.movesLeft ? left = right - minimum : right = left + minimum;
    }
    if (bottom - top < minimum) {
      handle.movesTop ? top = bottom - minimum : bottom = top + minimum;
    }
    return (left, top, right, bottom);
  }

  /// _resizeAsDrawn resizes the lone element, laid out by [on] on a frame
  /// where more than its own turn and slant place it, by [handle] dragged
  /// [delta]. The handle and the pointer are taken back into the element's
  /// own box through that place, the box is sized there, and moved so the
  /// corner or side held is drawn where it was: a place moves with its box,
  /// and a resize changes nothing else of it, so the side pulled is drawn
  /// under the pointer. Squashed, or stretched unevenly by its loop, the box
  /// still changes along its own sides, so the side pulled may move further
  /// on the page than its box grows: it is drawn stretched. A resize writes
  /// the resting box, never a pose.
  SnapLines _resizeAsDrawn(
      Offset delta, StageHandle handle, _BoxStart start, ElementOnPage on) {
    var element = document.elementById(on.drawn.id);
    var place = on.place;
    if (element == null || element.locked || place.flattens) {
      return SnapLines.none;
    }
    var box = on.box;

    // As a move snaps, where the box is drawn upright.
    var caught = SnapLines.none;
    var (drawn, frame) = place.boxOnPage(box);
    if (_snapReach case var reach? when frame.upright) {
      var snap = start.snapper.edges(drawn.shift(delta),
          left: handle.movesLeft,
          top: handle.movesTop,
          right: handle.movesRight,
          bottom: handle.movesBottom,
          reach: reach);
      delta += snap.nudge;
      caught = snap.lines;
    }

    var grip = Offset(
        handle.movesLeft
            ? box.left
            : handle.movesRight
                ? box.right
                : box.center.dx,
        handle.movesTop
            ? box.top
            : handle.movesBottom
                ? box.bottom
                : box.center.dy);
    var to = place.unplace(place.place(grip) + delta);
    var (keep, inside) = _resizeHolds(element, several: false);
    var (left, top, right, bottom) = _resizedEdges(
        box,
        handle,
        handle.movesLeft ? to.dx : box.left,
        handle.movesTop ? to.dy : box.top,
        handle.movesRight ? to.dx : box.right,
        handle.movesBottom ? to.dy : box.bottom,
        keep: keep);
    var sized = Rect.fromLTRB(left, top, right, bottom);
    var held = Offset(handle.movesLeft ? box.right : box.left,
        handle.movesTop ? box.bottom : box.top);
    var shift =
        place.place(held) - on.drawn.placedIn(sized, on.pose).place(held);
    var rest = _restOfDrawn(element, sized.shift(shift));
    var sx = box.width == 0 ? 1.0 : sized.width / box.width;
    var from = start.elements[element.id] ?? element;
    var next = (inside ? from.scaledBy(sx) : element).withBase(
      x: rest.left,
      y: rest.top,
      width: rest.width,
      height: rest.height,
      typeScale: inside ? from.base.typeScale * sx : null,
    );
    controller.apply(document.withElement(next), transient: true);
    return caught;
  }

  /// _restingAfterResize is where an element resized to [width] by
  /// [height] rests, its box at the drag's start resting at [rest] and drawn
  /// at [posed] on this frame: [posed] laid out in the dragged box [group],
  /// whose top left is now at [left], [top] and which is [sx] by [sy] what
  /// it was, and taken back through the pose's move and its size about the
  /// anchor (CanvasElement.boundsWith), which a resize leaves as they are.
  /// Where nothing moves it, [rest] laid out so.
  (double, double) _restingAfterResize(
      CanvasElement e,
      Rect rest,
      Rect? posed,
      double left,
      double top,
      Rect group,
      double sx,
      double sy,
      double width,
      double height) {
    // A reused element's posed box is round all its copies, not its own.
    if (posed == null || posed == rest || e.base.motion.instances != null) {
      return (
        left + (rest.left - group.left) * sx,
        top + (rest.top - group.top) * sy,
      );
    }
    // How far the pose puts its box's corner from where it rests, for a box
    // [w] across: its move, and the corner drawn in or out about the anchor
    // as the pose sizes it.
    var size = rest.width > 0 ? posed.width / rest.width : 1.0;
    double offset(double was, double now, double w, double share) =>
        now - was - w * share * (1 - size);
    var dx = offset(rest.left, posed.left, rest.width, e.base.anchorX);
    var dy = offset(rest.top, posed.top, rest.height, e.base.anchorY);
    var drawnLeft = left + (posed.left - group.left) * sx;
    var drawnTop = top + (posed.top - group.top) * sy;
    return (
      drawnLeft - dx - width * e.base.anchorX * (1 - size),
      drawnTop - dy - height * e.base.anchorY * (1 - size),
    );
  }

  void _applyRotate(Offset doc, _BoxStart start) {
    if (start.placed case var on? when !on.place.turnsAndSlantsOnly) {
      _turnAsDrawn(doc, start, on);
      return;
    }
    var bounds = _selectionBounds;
    if (bounds == null) return;
    var centre = bounds.center;
    // One element turns about its anchor, which stays put.
    if (controller.selection.length == 1) {
      var one = document.elementById(controller.selection.first);
      if (one != null && !one.anchorCentred) {
        centre =
            one.turnedAboutCentre(one.anchorIn(one.bounds), one.bounds.center);
      }
    }

    var from = math.atan2(_dragStart.dy - centre.dy, _dragStart.dx - centre.dx);
    var to = math.atan2(doc.dy - centre.dy, doc.dx - centre.dx);
    var degrees = (to - from) * 180 / math.pi;

    var next = document;
    for (var entry in start.rotation.entries) {
      var element = next.elementById(entry.key);
      if (element == null || element.locked) continue;
      var rotation = entry.value + degrees;
      if (_shiftHeld) rotation = steppedTurn(rotation);
      next = next.withElement(element.turnedTo(rotation));
    }
    controller.apply(next, transient: true);
  }

  /// _turnAsDrawn turns the lone element, laid out by [on] on a frame where
  /// more than its own turn and slant place it, as the turning handle is
  /// dragged to [doc]: about its anchor as drawn, which stays there, by the
  /// angle swept about it. The turn is the element's own, as it rests, so
  /// under a squash, laid over it after, the angle is swept as the squash
  /// found it, and the point pressed stays on the line to the pointer.
  void _turnAsDrawn(Offset doc, _BoxStart start, ElementOnPage on) {
    var element = document.elementById(on.drawn.id);
    if (element == null || element.locked) return;
    var anchor = on.drawn.anchorIn(on.box);
    var pivot = on.place.place(anchor);
    var from = on.place.unsquashed(_dragStart - pivot);
    var to = on.place.unsquashed(doc - pivot);
    var degrees = (math.atan2(to.dy, to.dx) - math.atan2(from.dy, from.dx)) *
        180 /
        math.pi;
    var rotation = (start.rotation[element.id] ?? element.rotation) + degrees;
    if (_shiftHeld) rotation = steppedTurn(rotation);
    var turned =
        on.drawn.withBase(rotation: rotation).placedIn(on.box, on.pose);
    var rest =
        _restOfDrawn(element, on.box.shift(pivot - turned.place(anchor)));
    controller.apply(
        document.withElement(
            element.withBase(rotation: rotation, x: rest.left, y: rest.top)),
        transient: true);
  }
}
