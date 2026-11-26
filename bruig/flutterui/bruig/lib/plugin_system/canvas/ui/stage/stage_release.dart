part of 'canvas_stage.dart';

// Letting go, and the pointer passing over: what a press finishes, and what is
// lit under the pointer. Part of CanvasStageState: its fields, lifecycle and
// build are in canvas_stage.dart.

extension StageRelease on CanvasStageState {
  /// _onPointerUp ends what the press began. [cancelled] is a press the
  /// system took away: it is ended the same, its undo step closed and what a
  /// drag changed kept, but no click, drop or box is acted on.
  void _onPointerUp(PointerEvent event, {bool cancelled = false}) {
    // A press that never went the drag threshold and was let go where it
    // began, never one the system took away: a press that travelled moved
    // something, so coming back does not also make it a click.
    var clicked = !cancelled &&
        !_travelled &&
        (event.localPosition - _pressedAt).distance <=
            CanvasStageState._buttonClickSlop;
    // A gesture that takes the release before the stage's own steps ends
    // there: see StageGesture.takesAll.
    if (_gesture case var gesture? when gesture.takesAll) {
      _endGesture(gesture, event.localPosition,
          cancelled: cancelled, clicked: clicked);
      return;
    }
    if (_liveTapPending) {
      _liveTapPending = false;
      if (!cancelled) _replayTap(event.position);
      return;
    }
    // A gesture ends itself, and with it any click riding on it. What
    // follows is for the kinds still on _DragMode (see
    // StageGesture.endsRelease).
    if (_gesture case var gesture?) {
      _endGesture(gesture, event.localPosition,
          cancelled: cancelled, clicked: clicked);
      if (gesture.endsRelease) return;
    }

    if (_mode == _DragMode.vectorMarquee) {
      var box = _marquee, e = controller.editingVector;
      if (cancelled) {
        // Taken away: nothing is picked and the editing goes on.
      } else if (box != null && e != null && box.width > 2 && box.height > 2) {
        var inside = picksIn(e, box);
        controller.pickVectorPoints(
            _shiftHeld ? {...controller.vectorPicks, ...inside} : inside);
      } else if (_vectorShapeUnder >= 0 && !_travelled) {
        controller.pickVectorShape(_vectorShapeUnder);
      } else if (!_vectorPressedOutside && !_shiftHeld) {
        // A click on empty space unpicks.
        controller.pickVectorShape(-1);
      } else if (_vectorPressedOutside && !_travelled) {
        // A click off the drawing finishes editing, and does what it would
        // have.
        controller.editVector(null);
        var hit = _hitElement(_dragStart);
        if (hit == null) {
          controller.clearSelection();
        } else if (hit.id != controller.selected?.id) {
          controller.selectOnly(hit.id);
        }
      }
      _vectorPressedOutside = false;
      _vectorShapeUnder = -1;
      setState(() => _marquee = null);
    }
    if (_mode == _DragMode.vectorPoints ||
        _mode == _DragMode.vectorPen ||
        _mode == _DragMode.vectorScale ||
        _mode == _DragMode.vectorTint ||
        _mode == _DragMode.vectorCorner ||
        _mode == _DragMode.vectorPencil ||
        _mode == _DragMode.vectorErase ||
        _mode == _DragMode.vectorRub ||
        _mode == _DragMode.vectorShapeDraw ||
        _mode == _DragMode.vectorShapeFit ||
        _mode == _DragMode.vectorItems) {
      if (_mode == _DragMode.vectorShapeDraw && !cancelled) {
        if (!_travelled) _drawShape(_shapeFrom, clicked: true);
        if (_vectorBefore?.shapes case var was?) {
          controller.vectorShapeMade = was.length;
          controller.pickVectorShape(was.length);
        }
      }
      if (_mode == _DragMode.vectorPencil) _mergePencil();
      _penInto = const {};
      _stroke = null;
      _strokeOn = {};
      if (_mode == _DragMode.vectorScale &&
          _scaleLetsGo &&
          !_travelled &&
          !cancelled) {
        controller.pickVectorPoints(const {});
      }
      _scaleLetsGo = false;
      _penSamples = [];
      _penRuns = [];
      _vectorBefore = null;
      _widths = {};
      controller.endInteraction();
      if (_tintWaiting != null) {
        _tintWaiting = null;
        if (!cancelled) controller.editVector(null);
      }
    }
    if (_mode == _DragMode.warpMarquee) _finishWarpMarquee(pick: !cancelled);
    if (_mode == _DragMode.vectorKnife) _finishKnife(apply: !cancelled);
    if (_mode == _DragMode.vectorItemsBox) {
      var box = _marquee;
      var e = controller.editingVector;
      if (!cancelled && box != null && e != null && _travelled) {
        controller.pickVectorItems(itemsIn(e, box), add: _shiftHeld);
      }
      setState(() => _marquee = null);
    }
    // Every mode that opened an interaction closes it here: beginInteraction
    // only takes the document if none is held, so one left open would merge
    // into the next gesture's undo step.
    if (_mode == _DragMode.warpMove ||
        _mode == _DragMode.warpScale ||
        _mode == _DragMode.warpTurn ||
        _mode == _DragMode.imageFrame ||
        _mode == _DragMode.imageLayerMove ||
        _mode == _DragMode.imageLayerSize ||
        _mode == _DragMode.imageLayerTurn ||
        _mode == _DragMode.imageMask ||
        _mode == _DragMode.imageBrush ||
        _mode == _DragMode.vectorPoint) {
      controller.endInteraction();
    }
    if (_mode == _DragMode.imageQuick && _quickTrail.isNotEmpty && !cancelled) {
      unawaited(controller.imageTool == ImageTool.refine
          ? controller.refineEdge(_quickTrail)
          : controller.quickSelect(_quickTrail, subtract: _quickSubtract));
      // Left on the canvas until the cut lands, so the stroke does not vanish
      // meanwhile.
    }
    _mode = _DragMode.none;
    _maskOn = null;
    _strokeAt = null;
  }

  /// _selectWithin toggles each unlocked, shown element that [box], an
  /// elements' marquee let go, overlaps: unless the box is too small to be
  /// more than a click.
  void _selectWithin(Rect box) {
    if (box.width <= 3 || box.height <= 3) return;
    // What the box is drawn round on screen: where each is drawn now.
    var hit = _hit;
    for (var e in document.elements) {
      if (!e.locked && e.visible && box.overlaps(hit.posed(e))) {
        controller.toggleSelected(e.id);
      }
    }
  }

  /// _updateHover keeps the renderer told what is under the pointer.
  void _updateHover(Offset stage) {
    _hoverAt = stage;
    // The cursor is worked out at build: onto a ruler or off it rebuilds.
    var ruler = _rulerUnder(stage);
    if (ruler != _hoverRuler) setState(() => _hoverRuler = ruler);
    var doc = _toDocument(stage);
    _hoverCode(doc);
    // For a Look at that faces the pointer. It moves what faces it, so the
    // element hit below, after it, may not be the one _hoverCode hit.
    controller.stagePointer = doc;
    controller.tilePaint?.hoverAt(doc);
    if (controller.editingImage != null &&
        (controller.imageTool == ImageTool.brush ||
            controller.imageTool == ImageTool.quick ||
            controller.imageTool == ImageTool.refine ||
            controller.imageTool.paints)) {
      setState(() {});
    }
    var hot = _gizmo()?.hit(doc, _gizmoReach);
    if (hot != _gizmoHot) setState(() => _gizmoHot = hot);
    var element = _hitElement(doc);
    var id = element is ButtonElement ? element.id : null;

    String? counter;
    var at = -1;
    if (element is CounterElement) {
      at = _counterButtonAt(element, doc);
      if (at >= 0) counter = element.id;
    }

    // Whether a click here presses something, for the cursor.
    var selected = element != null && controller.isOnlySelected(element.id);
    var pressable = counter != null ||
        (selected &&
            (element is ButtonElement ||
                (element is VideoElement &&
                    _videoPartAt(element, doc) != null) ||
                (element is AudioElement &&
                    _audioPartAt(element, doc) != null)));

    if (id != controller.hoveredButton ||
        counter != _hoveredCounter ||
        at != _hoveredCounterAt ||
        pressable != _hoverPressable) {
      controller.hoveredButton = id;
      setState(() {
        _hoveredCounter = counter;
        _hoveredCounterAt = at;
        _hoverPressable = pressable;
      });
    }
  }
}
