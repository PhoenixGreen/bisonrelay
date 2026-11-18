part of 'canvas_stage.dart';

// Letting go, and the pointer passing over: what a press finishes, and what is
// lit under the pointer. Part of CanvasStageState: its fields, lifecycle and
// build are in canvas_stage.dart.

extension StageRelease on CanvasStageState {
  void _onPointerUp(PointerEvent event) {
    if (_liveTapPending) {
      _liveTapPending = false;
      _replayTap(event.position);
      return;
    }
    if (_inLive) {
      _inLive = false;
      return;
    }
    if (_noteWas != null) {
      _noteWas = null;
      controller.endInteraction();
      return;
    }
    if (_releaseSynth(_toDocument(event.localPosition))) return;
    if (_releaseCode(_toDocument(event.localPosition))) return;
    var codeEdit = _pendingCodeEdit;
    _pendingCodeEdit = null;
    if (document.elementById(codeEdit?.$1 ?? "") case CodeElement e
        when codeEdit != null &&
            (event.localPosition - _pressedAt).distance <= CanvasStageState._buttonClickSlop) {
      controller.endInteraction();
      _mode = _DragMode.none;
      _handle = null;
      if (controller.playing) controller.pause();
      _codeEditBegun = false;
      controller.editCodePane(e, codeEdit.$2);
      return;
    }
    _legendHold?.cancel();
    _legendHold = null;
    if (_painting != null) {
      _commitStroke();
      return;
    }
    _playerIndex = -1;

    // A press on a selected button that never became a drag is a click,
    // which runs it. Measured in stage pixels, so it holds at any zoom.
    var counter = _pendingCounter;
    var counterAt = _pendingCounterAt;
    _pendingCounter = null;
    _pendingCounterAt = -1;
    if (_counterPart != null) {
      _counterPart = null;
      controller.endInteraction();
      _mode = _DragMode.none;
    }
    if (counter != null &&
        (event.localPosition - _pressedAt).distance <= CanvasStageState._buttonClickSlop) {
      controller.endInteraction();
      _mode = _DragMode.none;
      _handle = null;
      _pressCounter(counter, counterAt);
      return;
    }

    var legend = _pendingLegend;
    var legendAt = _pendingLegendAt;
    _pendingLegend = null;
    _pendingLegendAt = -1;
    if (legend != null &&
        (event.localPosition - _pressedAt).distance <= CanvasStageState._buttonClickSlop) {
      controller.endInteraction();
      _mode = _DragMode.none;
      _handle = null;
      _toggleSeries(legend, legendAt);
      return;
    }

    var sheet = _pendingSheet;
    _pendingSheet = null;
    if (sheet != null &&
        (event.localPosition - _pressedAt).distance <= CanvasStageState._buttonClickSlop) {
      controller.endInteraction();
      _mode = _DragMode.none;
      _handle = null;
      controller.sheetPressed(
          sheet,
          sheet.movedBoundsAt(controller.frame, controller.document,
              live: controller.liveMotion),
          _pendingSheetAt);
      return;
    }

    var film = _pendingVideo;
    _pendingVideo = null;
    if (film != null &&
        (event.localPosition - _pressedAt).distance <= CanvasStageState._buttonClickSlop) {
      controller.endInteraction();
      _mode = _DragMode.none;
      _handle = null;
      _pressVideo(film, _pendingVideoPart, _pendingVideoAt);
      return;
    }

    if (_keyDown case (var e, var key)?) {
      _keyDown = null;
      controller.noteOff(e, key);
      controller.endInteraction();
      _mode = _DragMode.none;
      _handle = null;
      return;
    }

    var sound = _pendingAudio;
    _pendingAudio = null;
    if (sound != null &&
        (event.localPosition - _pressedAt).distance <= CanvasStageState._buttonClickSlop) {
      controller.endInteraction();
      _mode = _DragMode.none;
      _handle = null;
      _pressAudio(sound, _pendingAudioPart, _pendingAudioAt);
      return;
    }

    var button = _pendingButton;
    _pendingButton = null;
    if (button != null &&
        (event.localPosition - _pressedAt).distance <= CanvasStageState._buttonClickSlop) {
      controller.endInteraction();
      _mode = _DragMode.none;
      _handle = null;
      var url = controller.runButtonAction(button.action);
      if (url != null && url.isNotEmpty) widget.onButtonLink?.call(url);
      return;
    }

    if (_mode == _DragMode.flow) {
      _dropFlow(event.localPosition);
      setState(() {
        _flowFrom = null;
        _flowAt = null;
        _mode = _DragMode.none;
      });
      return;
    }

    if (_mode == _DragMode.vectorMarquee) {
      var box = _marquee, e = controller.editingVector;
      if (box != null && e != null && box.width > 2 && box.height > 2) {
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
      if (_mode == _DragMode.vectorShapeDraw) {
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
      if (_mode == _DragMode.vectorScale && _scaleLetsGo && !_travelled) {
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
        controller.editVector(null);
      }
    }
    if (_mode == _DragMode.warpMarquee) _finishWarpMarquee();
    if (_mode == _DragMode.marquee) {
      var box = _marquee;
      if (box != null && box.width > 3 && box.height > 3) {
        for (var e in document.elements) {
          if (!e.locked && e.visible && box.overlaps(e.bounds)) {
            controller.toggleSelected(e.id);
          }
        }
      }
      setState(() => _marquee = null);
    }
    if (_mode == _DragMode.node || _mode == _DragMode.handle) {
      // Re-baked once at the end, not every pixel: a route is dozens of
      // keyframes.
      var path = _selectedPath();
      if (path != null) controller.applyPathFollow(path);
      controller.endInteraction();
      _nodeIndex = -1;
    }
    // Every mode that opened an interaction closes it here: beginInteraction
    // only takes the document if none is held, so one left open would merge
    // into the next gesture's undo step.
    if (_mode == _DragMode.guide) _finishGuide();
    if (_mode == _DragMode.spritePaint) {
      if (controller.spritePaint case var session?) {
        unawaited(session.strokeEnd());
      }
    }
    if (_mode == _DragMode.tilePaint) controller.tilePaint?.strokeEnd();
    if (_mode == _DragMode.vectorKnife) _finishKnife();
    if (_mode == _DragMode.vectorItemsBox) {
      var box = _marquee;
      var e = controller.editingVector;
      if (box != null && e != null && _travelled) {
        controller.pickVectorItems(itemsIn(e, box), add: _shiftHeld);
      }
      setState(() => _marquee = null);
    }
    if (_mode == _DragMode.move && !_travelled) {
      if ((_pressedCopy, _pressedCopyOf) case (var id?, var of?)) {
        controller.pickCopy(of, id);
      }
    }
    _pressedCopy = null;
    if (_mode == _DragMode.copies ||
        _mode == _DragMode.copySize ||
        _mode == _DragMode.copyTurn ||
        _mode == _DragMode.pieceMove ||
        _mode == _DragMode.pieceSize ||
        _mode == _DragMode.pieceTurn ||
        _mode == _DragMode.layoutCut ||
        _mode == _DragMode.layoutCutTurn ||
        _mode == _DragMode.layoutCutGutter ||
        _mode == _DragMode.layoutTrack ||
        _mode == _DragMode.layoutCellMove ||
        _mode == _DragMode.layoutCellSize ||
        _mode == _DragMode.layoutCellTurn ||
        _mode == _DragMode.move ||
        _mode == _DragMode.anchor ||
        _mode == _DragMode.resize ||
        _mode == _DragMode.skew ||
        _mode == _DragMode.warpMove ||
        _mode == _DragMode.warpScale ||
        _mode == _DragMode.warpTurn ||
        _mode == _DragMode.rotate ||
        _mode == _DragMode.chartLabel ||
        _mode == _DragMode.stageOrbit ||
        _mode == _DragMode.stagePan ||
        _mode == _DragMode.gizmo ||
        _mode == _DragMode.parallaxPan ||
        _mode == _DragMode.tableColumn ||
        _mode == _DragMode.imageFrame ||
        _mode == _DragMode.imageLayerMove ||
        _mode == _DragMode.imageLayerSize ||
        _mode == _DragMode.imageLayerTurn ||
        _mode == _DragMode.imageMask ||
        _mode == _DragMode.imageBrush ||
        _mode == _DragMode.vectorPoint ||
        _mode == _DragMode.player ||
        _mode == _DragMode.guide) {
      controller.endInteraction();
    }
    if (_mode == _DragMode.imageQuick && _quickTrail.isNotEmpty) {
      unawaited(controller.imageTool == ImageTool.refine
          ? controller.refineEdge(_quickTrail)
          : controller.quickSelect(_quickTrail, subtract: _quickSubtract));
      // Left on the canvas until the cut lands, so the stroke does not vanish
      // meanwhile.
    }
    // A still press on the stage with the page locked is a click on nothing:
    // it clears the selection.
    if (_lockedPress && !_travelled) controller.clearSelection();
    _lockedPress = false;
    if (_gizmoDrag != null) setState(() => _gizmoDrag = null);
    _mode = _DragMode.none;
    _handle = null;
    _maskOn = null;
    _strokeAt = null;
    if (_snappedTo != null) setState(() => _snappedTo = null);
  }

  /// _updateHover keeps the renderer told what is under the pointer.
  void _updateHover(Offset stage) {
    _hoverAt = stage;
    _hoverCode(stage);
    // For a Look at that faces the pointer.
    controller.stagePointer = _toDocument(stage);
    controller.tilePaint?.hoverAt(_toDocument(stage));
    if (controller.editingImage != null &&
        (controller.imageTool == ImageTool.brush ||
            controller.imageTool == ImageTool.quick ||
            controller.imageTool == ImageTool.refine ||
            controller.imageTool.paints)) {
      setState(() {});
    }
    var doc = _toDocument(stage);
    var hot = _gizmo()?.hit(doc, _gizmoReach);
    if (hot != _gizmoHot) setState(() => _gizmoHot = hot);
    var element = _hitElement(doc);
    var id = element is ButtonElement ? element.id : null;

    String? counter;
    var at = -1;
    if (element is CounterElement && element.live) {
      at = _counterButtonAt(element, doc);
      if (at >= 0) counter = element.id;
    }

    // Whether a click here presses something, for the cursor.
    var selected = element != null &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id;
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
