part of 'canvas_stage.dart';

// A drag on the canvas: moving, resizing, skewing and turning what was pressed,
// from the press that begins it (_beginTransform) to each step that applies
// it, and the parts of charts, tables and synths. Part of CanvasStageState: its
// fields, lifecycle and build are in canvas_stage.dart.

extension StageDrag on CanvasStageState {
  /// _selectedChartLabels are the lone selected chart's placed labels.
  List<Rect> _selectedChartLabels() {
    var element = controller.selected;
    if (element is! ChartElement || !controller.showHelpers) return const [];
    return chartLabelPlaces(element, _hit.posed(element))
        .values
        .where((r) => !r.isEmpty)
        .toList();
  }

  /// _docSlop is the pointer's reach in document units: the slop is in
  /// screen pixels (how still a hand is), so divided by the zoom.
  double get _docSlop => handleHitSlop / _scale;

  /// _applyPart writes a part-drag onto the selected element (stage_parts.dart
  /// works out the new element). Transient: the drag is one undo step.
  void _applyPart(Offset doc, {required bool chartLabel}) {
    var element = controller.selected;
    if (element == null) return;
    var bounds = _hit.posed(element);
    CanvasElement? next;
    if (chartLabel) {
      var grab = _labelGrab;
      if (grab == null || element is! ChartElement) return;
      next = chartLabelDragged(element, bounds, grab, doc);
    } else {
      var at = _columnGrab;
      if (at == null || element is! TableElement) return;
      next = tableColumnDragged(element, bounds, at, doc);
    }
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

  /// _pressMarkerNote takes a press on the held marker's canvas label.
  bool _pressMarkerNote(Offset doc) {
    var note = controller.holdingMarker;
    if (note == null || controller.gaming) return false;
    var laid = markerNoteLayout(controller.document.size.size, note);
    var sizing = laid.corner.contains(doc);
    if (!sizing && !laid.box.contains(doc)) return false;
    controller.beginInteraction();
    _noteWas = note;
    _noteSizing = sizing;
    _noteFrom = doc;
    _mode = _DragMode.none;
    return true;
  }

  /// _dragMarkerNote moves the held marker's label, or sizes it by the
  /// pointer's distance from its middle.
  void _dragMarkerNote(Offset doc) {
    var was = _noteWas!;
    var page = controller.document.size.size;
    TimelineAction next;
    if (_noteSizing) {
      var centre =
          Offset(was.noteAt.dx * page.width, was.noteAt.dy * page.height);
      var from = (_noteFrom - centre).distance;
      var ratio = from < 1 ? 1.0 : (doc - centre).distance / from;
      next = was.copyWith(
          noteSize: (was.noteSize * ratio).clamp(0.3, 6.0).toDouble());
    } else {
      var by = doc - _noteFrom;
      next = was.copyWith(
          noteAt: Offset((was.noteAt.dx + by.dx / page.width).clamp(0.0, 1.0),
              (was.noteAt.dy + by.dy / page.height).clamp(0.0, 1.0)));
    }
    replaceMarker(controller, next, transient: true);
  }

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
    if (_inLive) return;
    _pointer = event;
    if (_noteWas != null) {
      _dragMarkerNote(_toDocument(event.localPosition));
      return;
    }
    // Pressed as well as hovering: the brush ring must follow a stroke.
    _hoverAt = event.localPosition;
    if (_brushAt != null) _moveBrush(event.localPosition);
    if (_painting != null) {
      _paintStrokeAt(_toDocument(event.localPosition));
      return;
    }
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
    var delta = doc - _dragStart;

    switch (_mode) {
      case _DragMode.copies:
        _moveCopies(delta);
      case _DragMode.copySize || _DragMode.copyTurn:
        _applyCopyBox(doc);
      case _DragMode.pieceMove || _DragMode.pieceSize || _DragMode.pieceTurn:
        _applyPiece(doc);
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
      case _DragMode.player:
        _applyPlayerMove(doc);
      case _DragMode.stageOrbit:
        if (controller.stageOf(_orbiting ?? "") case var s?) {
          var from = _orbitFrom ?? s.cameraAt(controller.frame);
          var d = event.localPosition - _orbitAt;
          var yaw = from.yaw + d.dx * CanvasOrbitPad.degreesPerPixel * 0.5;
          var pitch = (from.pitch + d.dy * CanvasOrbitPad.degreesPerPixel * 0.5)
              .clamp(-10.0, 89.0);
          controller.putStage(
              controller.stageFilmed(
                  s, from.copyWith(yaw: (yaw * 10).round() / 10, pitch: pitch)),
              transient: true);
        }
      case _DragMode.stagePan:
        if (controller.stageOf(_orbiting ?? "") case var s?) {
          var from = _orbitFrom ?? s.cameraAt(controller.frame);
          var d = (event.localPosition - _orbitAt) / _scaleOrOne;
          controller.putStage(
              controller.stageFilmed(s, StageView(s.bounds, from).panned(d)),
              transient: true);
        }
      case _DragMode.gizmo:
        if (_gizmoDrag case (var g, var part, var from, var id)?) {
          if (document.elementById(id) case var e?) {
            var guides = document.guides;
            var snap =
                guides.stageSnap && !HardwareKeyboard.instance.isAltPressed;
            var spot = g.dragged(part, from, doc,
                pageScale: _scale,
                step: snap ? guides.stageStep : 0,
                turn: snap ? guides.stageTurn : 0);
            controller.replaceElement(controller.spotted(e, spot),
                transient: true);
          }
        }
      case _DragMode.parallaxPan:
        if ((controller.parallaxOf(_orbiting ?? ""), _panFrom)
            case (var p?, var from?)) {
          // Against the drag, in design units: dragging the scenery left
          // moves the camera right.
          var d = (event.localPosition - _orbitAt) / _scaleOrOne;
          controller.putBackdrop(
              controller.parallaxFilmed(
                  p,
                  from.copyWith(
                      x: (from.x - d.dx).roundToDouble(),
                      y: (from.y - d.dy).roundToDouble())),
              transient: true);
        }
      case _DragMode.spritePaint:
        if (controller.spritePaint case var session?) {
          unawaited(session.strokeTo(doc));
        }
      case _DragMode.tilePaint:
        controller.tilePaint?.strokeTo(doc);
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
      case _DragMode.chartLabel:
        _applyPart(doc, chartLabel: true);
      case _DragMode.tableColumn:
        _applyPart(doc, chartLabel: false);
      case _DragMode.counterPart:
        _applyCounterPart(doc);
      case _DragMode.synthKnob:
        _turnSynthKnob(doc);
      case _DragMode.codeScrub:
        if (document.elementById(_codeScrub ?? "") case CodeElement e) {
          controller.seekCode(codeTrackSeconds(e, doc));
        }
      case _DragMode.codeDivider:
        if (_codeDivider case (var id, var d)?) {
          if (document.elementById(id) case CodeElement e) {
            controller.replaceElement(codeDividerDragged(e, d, doc),
                transient: true);
          }
        }
      case _DragMode.codeTab:
        if (_codeTabAt != null ||
            (_toStage(doc) - _pressedAt).distance >
                CanvasStageState._buttonClickSlop) {
          setState(() => _codeTabAt = doc);
        }
      case _DragMode.synthScreen:
        if (_synthScreen case (var id, var grab)?) {
          if (document.elementById(id) case SynthModuleElement e) {
            controller.setSynth(
                synthScreenDragged(e, grab, synthPanelPoint(e, doc)),
                transient: true);
          }
        }
      case _DragMode.synthCable:
        if (_synthCable case var c?) {
          setState(() => _synthCable = (
                from: c.from,
                port: c.port,
                out: c.out,
                lifted: c.lifted,
                at: doc
              ));
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
      rotation: {
        for (var e in controller.selectedElements) e.id: e.rotation,
      },
    );
    controller.beginInteraction();
    return start;
  }

  /// _otherBounds is everything not dragged, locked included, to snap to:
  /// where each is drawn now, which is where it is seen. [start] is the
  /// selection being dragged.
  List<Rect> _otherBounds(_BoxStart start) {
    if (!document.guides.snapTo.objects) return const [];
    var moving = start.posed.keys.toSet();
    var hit = _hit;
    return [
      for (var element in document.elements)
        if (!moving.contains(element.base.id) && element.base.visible)
          hit.posed(element),
    ];
  }

  Rect? _startBoxOfSelection(_BoxStart start) {
    Rect? box;
    for (var entry in start.posed.entries) {
      box = box == null ? entry.value : box.expandToInclude(entry.value);
    }
    return box;
  }

  void _applyMove(Offset delta, _BoxStart start) {
    if (_shiftHeld) {
      delta = delta.dx.abs() > delta.dy.abs()
          ? Offset(delta.dx, 0)
          : Offset(0, delta.dy);
    }
    // Snapped once, against the whole selection's box, so things moved
    // together stay together. Alt turns it off.
    var box = _startBoxOfSelection(start);
    // Not on a 3D stage, where page lines mean nothing: staged elements snap
    // to the floor's 3D steps (see CanvasController.movedTo).
    var onStage = start.posed.keys
        .any((id) => document.elementById(id)?.base.spot != null);
    if (box != null && !onStage && !HardwareKeyboard.instance.isAltPressed) {
      var snapped = snapTopLeft(
        box.topLeft + delta,
        box.size,
        document.guides,
        document.size.size,
        within: document.guides.snapWithin / _scale,
        others: _otherBounds(start),
      );
      delta = snapped.at - box.topLeft;
      _snappedTo = snapped;
    } else {
      _snappedTo = null;
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
      next = next.withElement(
          controller.movedTo(element, entry.value.topLeft + delta));
    }
    controller.apply(next, transient: true);
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
    if (!HardwareKeyboard.instance.isAltPressed) {
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

  void _applyResize(Offset delta, StageHandle handle, _BoxStart start) {
    if (_applyLineEnd(handle, delta, start)) return;
    if (_applyCameraZoom(handle, delta, start)) return;

    // The dragged edge lands on the lines a move does: upright boxes only,
    // and Alt turns it off.
    if (_frameOfSelection.upright && !HardwareKeyboard.instance.isAltPressed) {
      delta = _snapResize(handle, delta, start);
    } else {
      _snappedTo = null;
    }

    // Into the element's own frame, so pulling a tilted element's right edge
    // widens it rather than moving it sideways.
    delta = _frameOfSelection.invert(delta);

    // One box for the whole drag, so things resized together keep their sizes
    // and gaps in proportion.
    Rect? group;
    for (var box in start.visual.values) {
      group = group == null ? box : group.expandToInclude(box);
    }
    if (group == null) return;
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
  }

  /// _snapResize snaps the dragged edge alone onto a line, against the union
  /// of what is resized.
  Offset _snapResize(StageHandle handle, Offset delta, _BoxStart start) {
    Rect? box;
    for (var visual in start.visual.values) {
      box = box == null ? visual : box.expandToInclude(visual);
    }
    if (box == null) {
      _snappedTo = null;
      return delta;
    }

    var guides = document.guides;
    var within = guides.snapWithin / _scale;
    var canvas = document.size.size;
    var others = _otherBounds(start);
    var dx = delta.dx;
    var dy = delta.dy;
    double? onVertical;
    double? onHorizontal;

    if (handle.movesLeft || handle.movesRight) {
      var at = (handle.movesLeft ? box.left : box.right) + dx;
      var line = snapEdgeTo(at, guides, canvas,
          vertical: true, within: within, others: others);
      if (line != null) {
        dx += line - at;
        onVertical = line;
      }
    }
    if (handle.movesTop || handle.movesBottom) {
      var at = (handle.movesTop ? box.top : box.bottom) + dy;
      var line = snapEdgeTo(at, guides, canvas,
          vertical: false, within: within, others: others);
      if (line != null) {
        dy += line - at;
        onHorizontal = line;
      }
    }

    _snappedTo = onVertical == null && onHorizontal == null
        ? null
        : SnapResult(box.topLeft,
            onVertical: onVertical, onHorizontal: onHorizontal);
    return Offset(dx, dy);
  }

  /// _anchorUnder is the element whose shown, unlocked anchor is at [stage].
  String? _anchorUnder(Offset stage) {
    for (var id in controller.selection) {
      if (!controller.anchorShown(id)) continue;
      var e = document.elementById(id);
      if (e == null || e.base.anchorLocked || e.locked) continue;
      if ((_toStage(e.anchorAt(controller.frame)) - stage).distance <= 10) {
        return id;
      }
    }
    return null;
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
      if (_shiftHeld) rotation = (rotation / 15).round() * 15;
      next = next.withElement(element.turnedTo(rotation));
    }
    controller.apply(next, transient: true);
  }
}
