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

  /// _applyAnchor puts element [id]'s anchor point at [doc]. Transient: the
  /// drag is one undo step.
  void _applyAnchor(String id, Offset doc) {
    if (document.elementById(id) case var e?) {
      controller.replaceElement(e.withAnchorAt(doc, controller.frame),
          transient: true);
    }
  }

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
      case _DragMode.layoutCut ||
            _DragMode.layoutCutTurn ||
            _DragMode.layoutCutGutter ||
            _DragMode.layoutTrack ||
            _DragMode.layoutCellMove ||
            _DragMode.layoutCellSize ||
            _DragMode.layoutCellTurn:
        _applyLayout(doc);
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
      // resize works from the resting bounds instead: it writes the base
      // size, and a posed size would bake a scale in. A move from the
      // resting bounds would lose the frame's pose.
      posed: {
        for (var e in controller.selectedElements) e.id: _hit.posed(e),
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
      snapper: Snapper(document.guides, document.size.size,
          others: _otherBounds(moving)),
    );
    controller.beginInteraction();
    return start;
  }

  /// _otherBounds is everything not dragged, locked included, to snap to:
  /// where each is drawn now, which is where it is seen. [moving] is the
  /// ids of the selection being dragged.
  List<Rect> _otherBounds(Set<String> moving) {
    if (!document.guides.snapTo.objects) return const [];
    var hit = _hit;
    return [
      for (var element in document.elements)
        if (!moving.contains(element.base.id) && element.base.visible)
          hit.posed(element),
    ];
  }

  /// _seenBounds is the upright box [e] is seen in: the box its handles are
  /// on (see _visualBounds), turned and slanted about its middle as it is
  /// drawn, so a turned element is snapped by the corners that show.
  Rect _seenBounds(CanvasElement e) {
    var box = _visualBounds(e);
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
    var onStage = start.posed.keys
        .any((id) => document.elementById(id)?.base.spot != null);
    var reach = _snapReach;
    var caught = SnapLines.none;
    if (reach != null && box != null && !onStage) {
      var snap = start.snapper.move(box.shift(delta), reach: reach);
      delta += snap.nudge;
      caught = snap.lines;
    }

    var next = document;
    for (var entry in start.posed.entries) {
      var element = next.elementById(entry.key);
      if (element == null || element.locked) continue;
      // A camera moves by where it looks, from its start: its frame is not
      // its box (see cameraFraming).
      if (start.elements[entry.key] case CameraElement camera) {
        next = next.withElement(controller.cameraShifted(camera, delta));
        continue;
      }
      // Through the controller, so an animated element is posed rather than
      // moved. See CanvasController.posesRatherThanMoves.
      next = next.withElement(controller
          .movedTo(element, entry.value.topLeft + delta, free: reach == null));
    }
    controller.apply(next, transient: true);
    return caught;
  }

  /// _applyLineEnd drags one end of a single straight line, if [handle] is
  /// on one, and says whether it did. A line is its two ends, not a box (a
  /// box is at least eight pixels deep, so a line could never be level). The
  /// end snaps to level, upright or diagonal within a few degrees, always
  /// with Shift; Alt frees it.
  bool _applyLineEnd(StageHandle handle, Offset delta, _BoxStart from) {
    if (from.visual.length != 1 || !_frameOfSelection.upright) return false;
    // The line at the drag's start: every step works from it, since crossing
    // one end past the other swaps the ends and their arrows.
    var line = from.elements[from.visual.keys.first];
    if (line is! LineElement || line.curvature != 0 || line.locked) {
      return false;
    }
    var was = line.bounds;
    var start = line.flipped ? was.bottomLeft : was.topLeft;
    var end = line.flipped ? was.topRight : was.bottomRight;
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
        ? line.withEnds(moving, fixed)
        : line.withEnds(fixed, moving);
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

  /// _applyResize resizes the selection by [handle] dragged [delta] from
  /// where [start] found it, and says which lines the dragged edge is
  /// caught on.
  SnapLines _applyResize(Offset delta, StageHandle handle, _BoxStart start) {
    if (_applyLineEnd(handle, delta, start)) return SnapLines.none;
    if (_applyCameraZoom(handle, delta, start)) return SnapLines.none;

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

    var left = group.left + (handle.movesLeft ? delta.dx : 0);
    var right = group.right + (handle.movesRight ? delta.dx : 0);
    var top = group.top + (handle.movesTop ? delta.dy : 0);
    var bottom = group.bottom + (handle.movesBottom ? delta.dy : 0);

    // Shift keeps proportions, by whichever axis moved further. A picture
    // keeps them without the key, Shift freeing it (see
    // CanvasElement.keepsAspect), as does a group: pulled out of shape, every
    // gap would be.
    var first = document.elementById(start.visual.keys.first);
    var keep = several
        ? !_shiftHeld
        : ((first?.keepsAspect ?? false) ? !_shiftHeld : _shiftHeld);
    if (keep && group.height > 0) {
      var aspect = group.width / group.height;
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

    var sx = group.width == 0 ? 1.0 : (right - left) / group.width;
    var sy = group.height == 0 ? 1.0 : (bottom - top) / group.height;

    var next = document;
    for (var entry in start.visual.entries) {
      var element = next.elementById(entry.key);
      if (element == null || element.locked) continue;
      var visual = entry.value;
      var real = start.bounds[entry.key] ?? visual;

      // Keeping proportions scales everything inside (type, spacing, a chip's
      // padding), from the element at the drag's start.
      var from = start.elements[entry.key] ?? element;
      element = keep ? from.scaledBy(sx) : element;
      next = next.withElement(element.withBase(
        x: left + (real.left - group.left) * sx,
        y: top + (real.top - group.top) * sy,
        width: math.max(1, real.width * sx),
        height: math.max(1, real.height * sy),
        // The scale applied inside the box, kept where the shape switch reads
        // it (see ElementBase.typeScale), so a shape change does not undo the
        // drag by the wrong amount.
        typeScale: keep ? from.base.typeScale * sx : null,
      ));
    }
    controller.apply(next, transient: true);
    return caught;
  }

  void _applyRotate(Offset doc, _BoxStart start) {
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
}
