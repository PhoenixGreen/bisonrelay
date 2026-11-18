part of 'canvas_stage.dart';

// A press on the canvas, and what it starts: a move, a resize, a copy box, a
// tool's stroke. Part of CanvasStageState: its fields, lifecycle and build are
// in canvas_stage.dart.

extension StagePress on CanvasStageState {
  bool get _shiftHeld => HardwareKeyboard.instance.isShiftPressed;

  void _onPointerDown(PointerDownEvent event) {
    _pointer = event;
    // Not while typing: an editor is a real text field with its own
    // pointers, and clicking off it moves focus, which closes it (see
    // CanvasTextEditor._onFocus). Taking focus would also close a cell editor
    // before its own picture button's tap finished.
    if (_editingText != null ||
        _editingCell != null ||
        controller.codeEditing != null) {
      return;
    }
    // A press off a live preview shuts it. One on it belongs to the preview:
    // shutting it would pull the page from under the click.
    if (controller.codeLive != null) {
      if (_codeLiveRect()?.contains(event.localPosition) ?? false) {
        _inLive = true;
        return;
      }
      controller.endLiveCode();
    }
    _focus.requestFocus();
    // Through the camera the page is drawn moved, so a press would land
    // elsewhere than it looks: it only puts the page back. See
    // CanvasController.cameraView.
    if (controller.cameraView) {
      controller.cameraView = false;
      return;
    }
    var stage = event.localPosition;
    _pressedAt = stage;
    _travelled = false;
    var doc = _toDocument(stage);
    _dragStart = doc;
    _pressedCopy = null;
    if (controller.placingCopies case var placing?
        when event.buttons == kPrimaryMouseButton) {
      controller.beginInteraction();
      controller.placeCopyAt(placing, doc);
      controller.endInteraction();
      _mode = _DragMode.none;
      return;
    }

    // A press on the facing page opens it, before the pan check (panning is
    // a drag) and the hit test (an element hanging over the spine would take
    // it), unless it is on a grip: a picture across the spread has handles on
    // the other leaf.
    if (_facingPage case var beside?
        when _onFacingPage(stage) && !_onSelectionGrip(stage, doc)) {
      controller.goToScene(beside);
      _mode = _DragMode.none;
      return;
    }

    // A held marker's canvas label: dragged to move, or sized by its grip.
    // Not in a game, where the page is the player's.
    if (_pressMarkerNote(doc)) return;

    if (controller.sampling) {
      _mode = _DragMode.none;
      _sampleAt(doc);
      return;
    }

    // The pen's buttons and eraser end, with the pencil out, before the
    // middle button's pan.
    if (_stylusPress(event, doc)) return;

    // The stage gizmo, drawn on top, before anything under it.
    if (_pressGizmo(doc)) return;

    // With the page locked, a press on a stage takes its camera.
    if (_pressLockedStage(event, doc)) return;

    // The pan tool and middle button pan (Space plays). Not with the page
    // locked, and not the pan tool on a 3D stage, which has its own tools.
    if (!controller.pageLocked &&
        ((controller.tool == CanvasTool.pan && !controller.onStage3d) ||
            event.buttons == kMiddleMouseButton)) {
      _mode = _DragMode.pan;
      _startPan = _clampedPan;
      _dragStart = stage;
      return;
    }

    // With a picture's layers open, a press on it works on them; elsewhere
    // it finishes editing.
    if (controller.editingImage case var picture?) {
      if (_pressLayers(picture, doc)) return;
      controller.editImage(null);
    }

    // A guide before anything on the canvas: it is a hairline, so its reach
    // is tight (see guideGrabSlop), but within it the guide wins.
    if (_startGuideDrag(stage, doc)) return;

    // An anchor point shown and unlocked, before the element it sits on.
    if (_anchorUnder(stage) case var id?) {
      _anchorOf = id;
      _mode = _DragMode.anchor;
      controller.beginInteraction();
      return;
    }

    // A sprite or tile map being painted takes a press on it first.
    if (controller.spritePaint case var session?) {
      if (session.sprite case var e? when !e.locked && e.bounds.contains(doc)) {
        _mode = _DragMode.spritePaint;
        unawaited(session.strokeStart(doc));
        return;
      }
    }
    if (controller.tilePaint case var session?) {
      if (session.map case var e? when !e.locked && e.bounds.contains(doc)) {
        _mode = _DragMode.tilePaint;
        session.strokeStart(doc);
        return;
      }
    }

    // A drawing being edited takes the press first; outside it, editing
    // ends and the press goes on.
    if (controller.editingVector case var vector?
        when _pressVector(vector, doc)) {
      return;
    }

    // Option on a 3D stage takes its camera: across orbits, down looks from
    // higher. On a Background element showing one, or, hitting nothing else,
    // the background's own.
    if (HardwareKeyboard.instance.isAltPressed) {
      var hit = _hitElement(doc);
      var held = switch (hit) {
        StageElement s => s,
        BackgroundElement b when b.isStage => b.staged,
        null => controller.stageOf(backgroundStageId),
        _ => null,
      };
      var scenery = switch (hit) {
        BackgroundElement b when b.isParallax => b.parallaxed,
        null => controller.parallaxOf(backgroundParallaxId),
        _ => null,
      };
      if (scenery case var p? when !p.locked) {
        _orbiting = p.id;
        _panFrom = p.cameraAt(controller.frame);
        _orbitAt = stage;
        _mode = _DragMode.parallaxPan;
        controller.beginInteraction();
        return;
      }
      if (held case var s? when !s.locked) {
        _orbiting = s.id;
        _orbitFrom = s.cameraAt(controller.frame);
        _orbitAt = stage;
        _mode = _DragMode.stageOrbit;
        controller.beginInteraction();
        return;
      }
    }

    // A selected path's points and handles first: they are over the curve.
    var path = _selectedPath();
    if (path != null) {
      var grab = _hitPathControl(path, doc);
      if (grab != null) {
        var (index, isHandle, isOut) = grab;
        _nodeIndex = index;
        _nodeHandleOut = isOut;
        _mode = isHandle ? _DragMode.handle : _DragMode.node;
        controller.beginInteraction();
        return;
      }
    }

    // Inside the box of a selected element whose box is not its shape (a
    // curved line, a path, text on a line) takes hold of it. Selecting one
    // still needs the stroke, or a bowed line's empty box would steal clicks.
    if (!_shiftHeld && controller.selection.length == 1) {
      var chosen = document.elementById(controller.selection.first);
      if (chosen != null &&
          !chosen.locked &&
          chosen.visible &&
          _boxIsNotTheShape(chosen) &&
          _visualBounds(chosen).contains(doc) &&
          _hitElement(doc) == null) {
        _beginTransform(_DragMode.move, null);
        return;
      }
    }

    // Outside the frame there is nothing to hit: a click clears the selection.
    if (!_viewRect.contains(stage) && _hitHandle(stage) == null) {
      if (!_shiftHeld) controller.clearSelection();
      _mode = _DragMode.none;
      return;
    }

    // A picture piece's own box first: its handles, or a drag inside it.
    if (_pressPiece(stage, doc)) return;

    // No flow grips or resize handles when the press is on a piece of text
    // drawn outside its box: see _looseTextPiece.
    if (_looseTextPiece(doc) == null) {
      // A flow grip before the resize handles, if nearer: on a short box the
      // grip lands on the middle handle.
      var nearest = _nearestHandle(stage);
      if (_hitFlowGrip(stage, beat: nearest?.$2 ?? double.infinity)
          case var grip?) {
        var selected = document.elementById(controller.selection.first);
        // A locked connector shows, as a chain is read by it, but ignores
        // the pointer.
        if (controller.lockJoins) return;
        // The incoming grip takes the arriving link, which belongs to the
        // box in front; where its loose end drops says what it means.
        var from = grip.out
            ? controller.selection.first
            : (selected is TextElement
                ? flowSourceOf(selected, document)?.id
                : null);
        if (from != null) {
          setState(() {
            _flowFrom = from;
            _flowAt = stage;
            _mode = _DragMode.flow;
          });
          return;
        }
      }

      var handle = nearest?.$1;
      if (handle != null) {
        // A side handle slants instead with Command or the Skew switch on.
        var side = handle == StageHandle.topCenter ||
            handle == StageHandle.bottomCenter ||
            handle == StageHandle.centerLeft ||
            handle == StageHandle.centerRight;
        // The one copy's box sizes and turns that copy by its own values. A
        // copy has no slant.
        if (_oneCopy case (var e, var i)?) {
          _beginCopyBox(e, i,
              handle == StageHandle.rotate
                  ? _DragMode.copyTurn
                  : _DragMode.copySize,
              handle);
          return;
        }
        var skewing = side &&
            _chosen.length == 1 &&
            (controller.skewHandles || HardwareKeyboard.instance.isMetaPressed);
        _beginTransform(
            handle == StageHandle.rotate
                ? _DragMode.rotate
                : skewing
                    ? _DragMode.skew
                    : _DragMode.resize,
            handle);
        return;
      }
    }

    // The retouching brush first: while on, a drag is a stroke.
    if (controller.retouch.on) {
      var picture = _selectedPicture();
      if (picture != null) {
        _painting = picture.id;
        _mode = _DragMode.none;
        controller.beginInteraction();
        _paintStrokeAt(doc, start: true);
        return;
      }
    }

    // A player of any team, before anything else: one dragged out of his
    // team's box, or in the other half, would find no team or the wrong one.
    // A dot is the smallest, topmost thing and beats every box.
    var hit = _hitAnyPlayer(doc);
    if (hit != null) {
      var (team, index) = hit;
      if (controller.selection.length != 1 ||
          controller.selection.first != team.id) {
        controller.selectOnly(team.id);
      }
      _mode = _DragMode.player;
      _playerIndex = index;
      // Held by where they stand, not their token's middle, which on a pitch
      // seen at an angle is off the ground.
      _playerGrab = doc -
          playerPlace(teamGround(document, team, controller.frame), team,
                  team.players[index], controller.frame)
              .ground;
      // Clicking a player points the timeline at them: they have no id.
      controller.focusedPlayer = index;
      controller.beginInteraction();
      return;
    }

    // A selected chart's placed label, before the chart whose box holds it.
    var chart = controller.selected;
    if (chart is ChartElement && !chart.locked) {
      var grab = chartLabelGrabAt(
          chart, chart.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion), doc, _docSlop);
      if (grab != null) {
        // A placed key both moves and holds switches: decided on release by
        // how far the pointer went.
        if (grab.part == ChartLabelPart.legend &&
            controller.selection.length == 1) {
          var at = _legendSeriesAt(chart, doc);
          if (at >= 0) {
            _pendingLegend = chart;
            _pendingLegendAt = at;
          }
        }
        _labelGrab = grab;
        _mode = _DragMode.chartLabel;
        controller.beginInteraction();
        return;
      }
    }

    // A selected table's column rule, before the table.
    var table = controller.selected;
    if (table is TableElement && !table.locked) {
      var divider =
          tableColumnAt(table, table.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion), doc, _docSlop);
      if (divider != null) {
        _columnGrab = divider;
        _mode = _DragMode.tableColumn;
        controller.beginInteraction();
        return;
      }
    }

    // The selection comes first: pressed anywhere on it, it is what moves,
    // whatever is drawn over it, so a drag after picking in Layers moves
    // what was picked. With nothing selected under the pointer, the topmost
    // thing wins.
    var held = _selectedAt(doc);

    // A master speaker pressed from a page. It cannot be selected there (the
    // master is edited on its own), so a press presses it: background music
    // with a mute switch lives on the master.
    if (held == null) {
      if (_masterAudioAt(doc) case (var sound, var part)?) {
        _pressAudio(sound, part, doc);
        _mode = _DragMode.none;
        return;
      }
      if (_masterVideoAt(doc) case (var film, var part)?) {
        _pressVideo(film, part, doc);
        _mode = _DragMode.none;
        return;
      }
    }

    // A text element's piece counts as that element wherever it is drawn
    // (gaps or sides can put it outside its box), and beats what is under it.
    var element =
        held ?? _topmostOf(_hitElement(doc), _textPieceOwner(doc));
    if (element == null) {
      if (!_shiftHeld) controller.clearSelection();
      _mode = _DragMode.marquee;
      setState(() => _marquee = Rect.fromPoints(doc, doc));
      return;
    }

    // A synth module's controls answer a press picked or not, as a rack's
    // do; its panel picks and moves it.
    if (element is SynthModuleElement && _pressSynth(element, doc)) return;
    if (element is MetronomeElement) {
      if (metronomePartAt(element, doc) case var part?) {
        _pressMetronome(element, part);
        _mode = _DragMode.none;
        return;
      }
    }
    // A Code panel's tabs, files and pane dividers, and a Run panel's Run
    // button, answer a press picked or not.
    if (element is CodeElement && _pressCode(element, doc)) return;
    if (element is CodeRunElement && _pressCodeRun(element, doc)) return;
    // A play task's own steps, ticked by the student, and its Start again.
    if (element is PlayTaskElement && _pressPlayTask(element, doc)) return;
    if (element is CodeTaskElement && codeTaskButtonAt(element, doc)) {
      if (controller.selection.length != 1 ||
          controller.selection.first != element.id) {
        controller.selectOnly(element.id);
      }
      controller.checkCodeTask(element);
      _mode = _DragMode.none;
      return;
    }
    if (element is SynthTaskElement) {
      if (synthTaskButtonAt(element, doc) case var b?) {
        _pressSynthTask(element, b);
        _mode = _DragMode.none;
        return;
      }
    }

    // A selected button is tried by a click and moved by a drag, so its
    // action waits for pointer-up, when the travel is known. See
    // _onPointerUp.
    if (element is ButtonElement &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id) {
      _pendingButton = element;
      _beginTransform(_DragMode.move, null);
      return;
    }

    // A selected speaker's or video's controls, on the same terms: a press
    // that stays put plays, mutes, sets the volume or seeks; one that
    // travels moves it.
    if (element is VideoElement &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id) {
      var part = _videoPartAt(element, doc);
      if (part != null) {
        _pendingVideo = element;
        _pendingVideoPart = part;
        _pendingVideoAt = doc;
        _beginTransform(_DragMode.move, null);
        return;
      }
    }

    // A selected sheet with a score: a press that stays put moves the
    // playhead to the note there; one that travels moves the sheet. Its
    // playbar takes a press picked or not.
    var onBar = element is SheetElement &&
        (sheetBarRect(
                    element,
                    element.movedBoundsAt(controller.frame, controller.document,
                        live: controller.liveMotion))
                ?.contains(doc) ??
            false);
    if (onBar &&
        (controller.selection.length != 1 ||
            controller.selection.first != element.id)) {
      controller.selectOnly(element.id);
    }
    if (element is SheetElement &&
        element.score.isNotEmpty &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id) {
      _pendingSheet = element;
      _pendingSheetAt = doc;
      _beginTransform(_DragMode.move, null);
      return;
    }

    // A selected instrument's keys sound on press and stop on release; a
    // press that travels releases the note and moves the keyboard. Further
    // down the key is harder, as on a real one.
    if (element is AudioElement &&
        element.instrument != null &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id) {
      var keys =
          keyboardLayout(element.instrument!, element.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion));
      if (keys.keyAt(doc) case (var key, var depth)?) {
        controller.noteOn(element, key,
            velocity: (50 + depth * 77).round(),
            place: neckPlaceAt(keys, element.instrument!, doc));
        _keyDown = (element, key);
        _beginTransform(_DragMode.move, null);
        return;
      }
    }

    if (element is AudioElement &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id) {
      var part = _audioPartAt(element, doc);
      if (part != null) {
        _pendingAudio = element;
        _pendingAudioPart = part;
        _pendingAudioAt = doc;
        _beginTransform(_DragMode.move, null);
        return;
      }
    }

    // A live counter's buttons, on the same terms: only when selected and the
    // press does not become a drag. A loose piece is both, so the press is
    // armed here and the mode moves the piece.
    if (element is CounterElement &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id) {
      var part = _counterPartUnder(element, doc);
      var at = element.live ? _counterButtonAt(element, doc) : -1;
      if (part != null) {
        controller.beginInteraction();
        _counterPart = element.id;
        _counterPartAt = part;
        _dragStart = doc;
        if (at >= 0 && element.live) {
          _pendingCounter = element;
          _pendingCounterAt = at;
        }
        setState(() => _mode = _DragMode.counterPart);
        return;
      }
      if (at >= 0) {
        _pendingCounter = element;
        _pendingCounterAt = at;
        _beginTransform(_DragMode.move, null);
        return;
      }
    }

    // A chart's key entry switches its series, on the same terms.
    if (element is ChartElement &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id) {
      var at = _legendSeriesAt(element, doc);
      if (at >= 0) {
        _pendingLegend = element;
        _pendingLegendAt = at;
        // Held rather than tapped, the press moves the key instead.
        _legendHold = Timer(CanvasStageState._legendHoldDelay, () => _holdLegend(element));
        _beginTransform(_DragMode.move, null);
        return;
      }
    }

    // A second click on a selected drawing opens it for editing.
    if (element is VectorElement &&
        !_shiftHeld &&
        !element.locked &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id &&
        _pressedAt != Offset.zero &&
        clock.now().difference(_lastClickAt) < CanvasStageState._doubleClickWindow) {
      _mode = _DragMode.none;
      var at = doc;
      unawaited(startVectorEditing(context, controller, element).then((_) {
        var e = controller.editingVector;
        if (!mounted || e == null || e.id != element.id) return;
        var reach = (e.handleSize / 2 + handleHitSlop) / _scale;
        var shape = shapeAt(e, at, reach);
        if (shape >= 0) controller.pickVectorShape(shape);
      }));
      return;
    }

    // A second click on a selected picture opens its layers, the one under
    // the click picked. With the base picked, a drag moves the picture
    // inside its box (see _framing).
    if (element is ImageElement &&
        !_shiftHeld &&
        !element.locked &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id &&
        _pressedAt != Offset.zero &&
        clock.now().difference(_lastClickAt) < CanvasStageState._doubleClickWindow) {
      controller.editImage(element.id, layer: layerAt(element, doc).id);
      _mode = _DragMode.none;
      return;
    }

    // A second click on a selected table's cell opens it for typing.
    if (element is TableElement &&
        !_shiftHeld &&
        !element.locked &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id &&
        _pressedAt != Offset.zero &&
        clock.now().difference(_lastClickAt) < CanvasStageState._doubleClickWindow) {
      var at = tableCellAt(element, element.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion), doc);
      if (at != null) {
        setState(() => _editingCell = (element.id, at.$1, at.$2));
        _mode = _DragMode.none;
        return;
      }
    }

    // A second click on a selected text element opens it for typing; the
    // first only selects, so it can still be dragged. Not one whose words
    // come from a document or a flow: it does not own them, and typing would
    // be overwritten.
    if (element is TextElement &&
        !element.document.on &&
        flowSourceOf(element, document) == null &&
        !_shiftHeld &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id &&
        _pressedAt != Offset.zero &&
        clock.now().difference(_lastClickAt) < CanvasStageState._doubleClickWindow) {
      // A picture has no words: it is picked, which gives it its own box
      // to move, size, turn or delete (stage_text_pieces.dart).
      var piece = _textItemAt(element, doc);
      if (piece != null && piece.isIcon) {
        controller.pickTextLayer(element.id, piece.id);
        _mode = _DragMode.none;
        return;
      }
      setState(() {
        _editingText = element.id;
        _editingItem = piece?.id;
        _editingClick = _pointer?.position;
      });
      // Pick the typed piece in Layers, so its settings show.
      controller.pickTextLayer(element.id, _editingItem);
      _mode = _DragMode.none;
      return;
    }
    _lastClickAt = clock.now();

    if (_pressCopy(element, doc)) return;

    if (_shiftHeld) {
      controller.toggleSelected(element.id);
    } else if (!controller.selection.contains(element.id)) {
      controller.selectOnly(element.id);
    }

    // A team with its frame locked, or on a pitch, is selectable but its box
    // does not move. A player drag was dealt with above.
    if (element is TeamElement && element.frameFixed) {
      _mode = _DragMode.none;
      return;
    }

    _beginTransform(_DragMode.move, null);
  }

  /// _pressCopy takes a press on reused [element] at [doc] for the copy
  /// there. Alt drags out new copies of it (or of those picked); Shift picks
  /// it in or out; with copies picked, it is picked and dragged alone.
  /// Otherwise the press goes on to the element: a drag moves them all, a
  /// click picks this one (see _onPointerUp). True if handled.
  bool _pressCopy(CanvasElement element, Offset doc) {
    var set = element.base.motion.instances;
    if (set == null) return false;
    var i = element.instanceAt(doc, controller.frame, controller.document,
        live: controller.liveMotion);
    if (i == null) return false;
    var id = set.items[i].id;
    _pressedCopy = id;
    _pressedCopyOf = element.id;
    var picked = controller.pickedCopiesOf(element.id);
    if (HardwareKeyboard.instance.isAltPressed) {
      if (!controller.selection.contains(element.id)) {
        controller.selectOnly(element.id);
      }
      controller.beginInteraction();
      _dragCopies = controller.duplicateCopies(
          element.id, picked.contains(id) ? picked : {id}, Offset.zero);
      _copiesStart = controller.motionOf(element.id).instances;
      _pressedCopy = null;
      _mode = _DragMode.copies;
      return true;
    }
    if (_shiftHeld && controller.selection.contains(element.id)) {
      controller.pickCopy(element.id, id, toggle: true);
      _pressedCopy = null;
      _mode = _DragMode.none;
      return true;
    }
    if (picked.isNotEmpty) {
      if (!picked.contains(id)) {
        controller.pickCopy(element.id, id);
        picked = {id};
      }
      controller.beginInteraction();
      _dragCopies = picked;
      _copiesStart = set;
      _pressedCopy = null;
      _mode = _DragMode.copies;
      return true;
    }
    return false;
  }

  void _beginCopyBox(
      CanvasElement e, int i, _DragMode mode, StageHandle? handle) {
    var set = e.base.motion.instances!;
    _mode = mode;
    _handle = handle;
    _copyPivot = e.anchorIn(e.boundsWith(_copyPose(e, i)));
    _copySize = set.sizeOf(i);
    _copyTurn = set.turnOf(i);
    controller.beginInteraction();
  }

  /// _applyCopyBox sizes or turns the one picked copy as its handle is
  /// dragged to [doc]: sized evenly (a copy has one Size) by how much farther
  /// from its anchor the pointer is along the line pressed on; turned by the
  /// angle swept, in 15-degree steps with Shift.
  void _applyCopyBox(Offset doc) {
    var e = controller.selected;
    if (e == null) return;
    var from = _dragStart - _copyPivot, to = doc - _copyPivot;
    if (_mode == _DragMode.copyTurn) {
      var swept = (math.atan2(to.dy, to.dx) - math.atan2(from.dy, from.dx)) *
          180 /
          math.pi;
      var turn = _copyTurn + swept;
      if (_shiftHeld) turn = (turn / 15).round() * 15;
      turn = (turn + 180) % 360 - 180;
      controller.setCopyOwn(e.id, CopyValue.turn.name, turn, transient: true);
      return;
    }
    var along = from.distanceSquared;
    if (along < 1e-6) return;
    var f = (to.dx * from.dx + to.dy * from.dy) / along;
    var size = (_copySize * f).clamp(CopyValue.size.min, CopyValue.size.max);
    controller.setCopyOwn(e.id, CopyValue.size.name, size, transient: true);
  }

  /// _moveCopies puts the dragged copies [delta] from their start, along one
  /// axis with Shift.
  void _moveCopies(Offset delta) {
    var from = _copiesStart, of = controller.selected?.id;
    if (from == null || of == null) return;
    if (_shiftHeld) {
      delta = delta.dx.abs() >= delta.dy.abs()
          ? Offset(delta.dx, 0)
          : Offset(0, delta.dy);
    }
    controller.setInstances(
        of,
        from.copyWith(items: [
          for (var x in from.items)
            _dragCopies.contains(x.id)
                ? x.copyWith(dx: x.dx + delta.dx, dy: x.dy + delta.dy)
                : x,
        ]),
        transient: true);
  }
}
