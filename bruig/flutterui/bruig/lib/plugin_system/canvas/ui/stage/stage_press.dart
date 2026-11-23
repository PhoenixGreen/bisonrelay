part of 'canvas_stage.dart';

// A press on the canvas, and what it starts: a move, a resize, a copy box, a
// tool's stroke. Part of CanvasStageState: its fields, lifecycle and build are
// in canvas_stage.dart.

extension StagePress on CanvasStageState {
  bool get _shiftHeld => HardwareKeyboard.instance.isShiftPressed;

  /// _onPointerDown is a press on the stage, tried against each step in
  /// turn until one takes it. The order is the order of what is drawn over
  /// what, and of what must win where two would answer the same press.
  void _onPointerDown(PointerDownEvent event) {
    _pointer = event;
    // An editor or live preview open, or the camera's view, before anything
    // else: the press is not on the page as it looks.
    if (_pressOverlays(event)) return;
    var press = _beginPress(event);
    // Placing copies, and the facing page, before the tools: the page itself
    // answers these, whatever tool is out.
    if (_pressPage(press)) return;
    // The tools that take a press before anything on the page.
    if (_pressTools(press)) return;
    // Option takes a camera, after the tools that have their own use for it.
    if (_pressAltCamera(press)) return;
    // The selection's grips, before what lies under them.
    if (_pressSelectionGrips(press)) return;
    // The flow grips and handles round the selection.
    if (_pressHandles(press)) return;
    // Parts of the selected element, before the element whose box holds
    // them.
    if (_pressSelectionParts(press)) return;
    var element = _pressedElement(press);
    if (element == null) return;
    // An element's own controls that answer a press at once.
    if (_pressElementControls(press, element)) return;
    // A selected element's controls whose click waits for the release.
    if (_pressSelectedControls(press, element)) return;
    // A second click opens what the first selected.
    if (_pressSecondClick(press, element)) return;
    // Last, select what was pressed and begin moving it.
    _pressSelectAndMove(press, element);
  }

  /// _pressOverlays takes a press while an editor or a live preview is open,
  /// or the page is seen through the camera: none of them is the page as it
  /// is drawn. It also takes the keyboard's focus for the stage. True if it
  /// took the press.
  bool _pressOverlays(PointerDownEvent event) {
    // Not while typing: an editor is a real text field with its own
    // pointers, and clicking off it moves focus, which closes it (see
    // CanvasTextEditor._onFocus). Taking focus would also close a cell editor
    // before its own picture button's tap finished. A counter's Set field
    // does not hold presses back: the focus a press takes closes it.
    var typing = switch (_editing) {
      TextEdit() || CellEdit() => true,
      CounterSet() || null => false,
    };
    if (typing || controller.codeEditing != null) return true;
    // A press off a live preview shuts it. One on it belongs to the preview:
    // shutting it would pull the page from under the click.
    if (controller.codeLive != null) {
      if (_codeLiveRect()?.contains(event.localPosition) ?? false) {
        _gesture = _LivePress();
        return true;
      }
      controller.endLiveCode();
    }
    _focus.requestFocus();
    // Through the camera the page is drawn moved, so a press would land
    // elsewhere than it looks: it only puts the page back. See
    // CanvasController.cameraView.
    if (controller.cameraView) {
      controller.cameraView = false;
      return true;
    }
    return false;
  }

  /// _beginPress resets what the last press left and works out, once, the
  /// points every later step reads.
  _Press _beginPress(PointerDownEvent event) {
    var stage = event.localPosition;
    _pressedAt = stage;
    _travelled = false;
    var doc = _toDocument(stage);
    _dragStart = doc;
    return _Press(event, stage, doc);
  }

  /// _pressPage takes a press that places copies, or one on the facing page,
  /// which opens it. True if it took the press.
  bool _pressPage(_Press press) {
    var _Press(:event, :stage, :doc) = press;
    if (controller.placingCopies case var placing?
        when event.buttons == kPrimaryMouseButton) {
      controller.beginInteraction();
      controller.placeCopyAt(placing, doc);
      controller.endInteraction();
      _mode = _DragMode.none;
      return true;
    }

    // A press on the facing page opens it, before the pan check (panning is
    // a drag) and the hit test (an element hanging over the spine would take
    // it), unless it is on a grip: a picture across the spread has handles on
    // the other leaf.
    if (_facingPage case var beside?
        when _view.onFacingPage(stage) && !_onSelectionGrip(stage, doc)) {
      controller.goToScene(beside);
      _mode = _DragMode.none;
      return true;
    }
    return false;
  }

  /// _pressTools takes a press for a tool or session that comes before
  /// anything on the page: the marker's label, sampling a colour, the
  /// stylus, the 3D gizmo, a locked stage, panning, a picture's open layers,
  /// a ruler's new guide, an anchor point, a sprite or tile map being
  /// painted, a drawing being edited, and a guide. True if one took the
  /// press.
  bool _pressTools(_Press press) {
    var _Press(:event, :stage, :doc) = press;
    // A held marker's canvas label: dragged to move, or sized by its grip.
    // Not in a game, where the page is the player's.
    if (_pressMarkerNote(doc)) return true;

    if (controller.sampling) {
      _mode = _DragMode.none;
      _sampleAt(doc);
      return true;
    }

    // The pen's buttons and eraser end, with the pencil out, before the
    // middle button's pan.
    if (_stylusPress(event, doc)) return true;

    // The stage gizmo, drawn on top, before anything under it.
    if (_pressGizmo(event, doc)) return true;

    // With the page locked, a press on a stage takes its camera.
    if (_pressLockedStage(event, doc)) return true;

    // The pan tool and middle button pan (Space plays). Not with the page
    // locked, and not the pan tool on a 3D stage, which has its own tools.
    if (!controller.pageLocked &&
        ((controller.tool == CanvasTool.pan && !controller.onStage3d) ||
            event.buttons == kMiddleMouseButton)) {
      _gesture = _Pan(startPan: _clampedPan, from: stage);
      return true;
    }

    // With a picture's layers open, a press on it works on them; elsewhere
    // it finishes editing.
    if (controller.editingImage case var picture?) {
      if (_pressLayers(picture, doc)) return true;
      controller.editImage(null);
    }

    // A press in a ruler pulls out a new guide, before anything on the page.
    if (_pullGuide(stage)) return true;

    // An anchor point shown and unlocked, before the element it sits on.
    if (_anchorUnder(stage) case var id?) {
      _gesture = _AnchorDrag(id);
      controller.beginInteraction();
      return true;
    }

    // A sprite or tile map being painted takes a press on it first.
    if (controller.spritePaint case var session?) {
      if (session.sprite case var e? when !e.locked && e.bounds.contains(doc)) {
        _gesture = _SpritePaint();
        unawaited(session.strokeStart(doc));
        return true;
      }
    }
    if (controller.tilePaint case var session?) {
      if (session.map case var e? when !e.locked && e.bounds.contains(doc)) {
        _gesture = _TilePaint();
        session.strokeStart(doc);
        return true;
      }
    }

    // A drawing being edited takes the press first; outside it, editing
    // ends and the press goes on.
    if (controller.editingVector case var vector?
        when _pressVector(vector, doc)) {
      return true;
    }

    // A guide, after what is drawn over it or is a tool in hand. It is a
    // hairline, so its reach is tight (see guideGrabSlop), but within it the
    // guide wins over what lies under it. Not where a mark drawn over it
    // lies on it (see _drawnOverGuide). Before Option's camera, since
    // Option frees a guide's drag from snapping.
    if (!_drawnOverGuide(stage, doc) && _grabGuide(doc)) return true;
    return false;
  }

  /// _pressMarkerNote takes a press on the held marker's canvas label.
  bool _pressMarkerNote(Offset doc) {
    var note = controller.holdingMarker;
    if (note == null || controller.gaming) return false;
    var laid = markerNoteLayout(controller.document.size.size, note);
    var sizing = laid.corner.contains(doc);
    if (!sizing && !laid.box.contains(doc)) return false;
    controller.beginInteraction();
    _gesture = _MarkerNoteDrag(note, sizing: sizing, from: doc);
    _mode = _DragMode.none;
    return true;
  }

  /// _pressAltCamera takes a press with Option held for the camera of a 3D
  /// stage or a parallax backdrop under it. True if it took the press.
  bool _pressAltCamera(_Press press) {
    var _Press(:stage, :doc) = press;
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
        _gesture = _ParallaxPan(p.id, p.cameraAt(controller.frame), stage);
        controller.beginInteraction();
        return true;
      }
      if (held case var s? when !s.locked) {
        _gesture = _StageOrbit(s.id, s.cameraAt(controller.frame), stage,
            clickClears: false);
        controller.beginInteraction();
        return true;
      }
    }
    return false;
  }

  /// _pressSelectionGrips takes a press on a selected path's points, inside
  /// the box of a selected element whose box is not its shape, outside the
  /// frame (which clears the selection), or on a picture piece's or a
  /// Layout's own grips. True if it took the press.
  bool _pressSelectionGrips(_Press press) {
    var _Press(:stage, :doc) = press;
    // A selected path's points and handles first: they are over the curve.
    var path = _selectedPath();
    if (path != null) {
      var grab = _hitPathControl(path, doc);
      if (grab != null) {
        var (index, isHandle, isOut) = grab;
        _gesture = _PathPointDrag(index, isHandle: isHandle, handleOut: isOut);
        controller.beginInteraction();
        return true;
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
        _gesture = _BoxMove(_beginTransform());
        return true;
      }
    }

    // Outside the frame there is nothing to hit: a click clears the selection.
    if (!_view.viewRect.contains(stage) && _hitHandle(stage) == null) {
      if (!_shiftHeld) controller.clearSelection();
      _mode = _DragMode.none;
      return true;
    }

    // A picture piece's own box first: its handles, or a drag inside it.
    if (_pressPiece(stage, doc)) return true;
    // A Layout's lines and picked Free cell (stage_layouts.dart).
    if (_pressLayout(stage, doc)) return true;
    return false;
  }

  /// _pressHandles takes a press on a text's flow grip, which starts a link,
  /// or on a resize, slant or turn handle of the selection or its one picked
  /// copy. True if it took the press.
  bool _pressHandles(_Press press) {
    var _Press(:stage, :doc) = press;
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
        if (controller.lockJoins) return true;
        // The incoming grip takes the arriving link, which belongs to the
        // box in front; where its loose end drops says what it means.
        var from = grip.out
            ? controller.selection.first
            : (selected is TextElement
                ? flowSourceOf(selected, document)?.id
                : null);
        if (from != null) {
          setState(() => _gesture = _FlowLinkDrag(from, stage));
          return true;
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
          _gesture = _beginCopyBox(e, i, turning: handle == StageHandle.rotate);
          return true;
        }
        var skewing = side &&
            _chosen.length == 1 &&
            (controller.skewHandles || HardwareKeyboard.instance.isMetaPressed);
        var start = _beginTransform();
        _gesture = handle == StageHandle.rotate
            ? _BoxTurn(start)
            : skewing
                ? _BoxSlant(start, handle)
                : _BoxResize(start, handle);
        return true;
      }
    }
    return false;
  }

  /// _pressSelectionParts takes a press for the retouching brush, a team's
  /// player, or a part of the selected element drawn inside its box: a
  /// chart's placed label, a table's column rule. True if it took the
  /// press.
  bool _pressSelectionParts(_Press press) {
    var _Press(:doc) = press;
    // The retouching brush first: while on, a drag is a stroke.
    if (controller.retouch.on) {
      var picture = _selectedPicture();
      if (picture != null) {
        var stroke = _RetouchStroke(picture.id);
        _gesture = stroke;
        _mode = _DragMode.none;
        controller.beginInteraction();
        _paintStrokeAt(stroke, doc, start: true);
        return true;
      }
    }

    // A player of any team, before anything else: one dragged out of his
    // team's box, or in the other half, would find no team or the wrong one.
    // A dot is the smallest, topmost thing and beats every box.
    var hit = _hitAnyPlayer(doc);
    if (hit != null) {
      var (team, index) = hit;
      controller.selectAlone(team.id);
      // Held by where they stand, not their token's middle, which on a pitch
      // seen at an angle is off the ground.
      _gesture = _PlayerDrag(
          index,
          doc -
              playerPlace(teamGround(document, team, controller.frame), team,
                      team.players[index], controller.frame)
                  .ground);
      // Clicking a player points the timeline at them: they have no id.
      controller.focusedPlayer = index;
      controller.beginInteraction();
      return true;
    }

    // A selected chart's placed label, before the chart whose box holds it.
    if (_chartLabelAt(doc) case var grab?) {
      // A placed key both moves and holds switches: decided on release by
      // how far the pointer went.
      _LegendClick? click;
      var chart = _labelledChart!;
      if (grab.part == ChartLabelPart.legend &&
          controller.selection.length == 1) {
        var at = _legendSeriesAt(chart, doc);
        if (at >= 0) click = _LegendClick(chart, at);
      }
      _gesture = _ChartLabelDrag(grab, click: click);
      controller.beginInteraction();
      return true;
    }

    // A selected table's column rule, before the table.
    if (_tableColumnAt(doc) case var divider?) {
      _gesture = _TableColumnDrag(divider);
      controller.beginInteraction();
      return true;
    }
    return false;
  }

  /// _pressedElement finds the element the press is on, for the steps that
  /// follow. It returns null when it took the press itself: a master
  /// speaker or video pressed from a page, or a press on no element, which
  /// begins a marquee.
  CanvasElement? _pressedElement(_Press press) {
    var _Press(:doc) = press;
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
        return null;
      }
      if (_masterVideoAt(doc) case (var film, var part)?) {
        _pressVideo(film, part, doc);
        _mode = _DragMode.none;
        return null;
      }
    }

    // A text element's piece counts as that element wherever it is drawn
    // (gaps or sides can put it outside its box), and beats what is under it.
    var element = held ?? _topmostOf(_hitElement(doc), _textPieceOwner(doc));
    if (element == null) {
      if (!_shiftHeld) controller.clearSelection();
      setState(() => _gesture = _ElementsMarquee(doc));
      return null;
    }
    return element;
  }

  /// _pressElementControls takes a press on the controls of [element] that
  /// act at once, picked or not: a synth module's, a metronome's, a Code or
  /// Run panel's, and a play, code or synth task's. True if one took the
  /// press.
  bool _pressElementControls(_Press press, CanvasElement element) {
    var _Press(:doc) = press;
    // A synth module's controls answer a press picked or not, as a rack's
    // do; its panel picks and moves it.
    if (element is SynthModuleElement && _pressSynth(element, doc)) return true;
    // Each of these is pressed where it is drawn now (StageHitTest.posed),
    // which its motion may have taken away from its resting place.
    if (element is MetronomeElement) {
      if (metronomePartAt(element, doc, box: _hit.posed(element))
          case var part?) {
        _pressMetronome(element, part);
        _mode = _DragMode.none;
        return true;
      }
    }
    // A Code panel's tabs, files and pane dividers, and a Run panel's Run
    // button, answer a press picked or not.
    if (element is CodeElement && _pressCode(press, element)) return true;
    if (element is CodeRunElement && _pressCodeRun(element, doc)) return true;
    // A play task's own steps, ticked by the student, and its Start again.
    if (element is PlayTaskElement && _pressPlayTask(element, doc)) {
      return true;
    }
    if (element is CodeTaskElement &&
        codeTaskButtonAt(element, doc, box: _hit.posed(element))) {
      controller.selectAlone(element.id);
      controller.checkCodeTask(element);
      _mode = _DragMode.none;
      return true;
    }
    if (element is SynthTaskElement) {
      if (synthTaskButtonAt(element, doc, box: _hit.posed(element))
          case var b?) {
        _pressSynthTask(element, b);
        _mode = _DragMode.none;
        return true;
      }
    }
    return false;
  }

  /// _pressSelectedControls takes a press on the controls of a selected
  /// [element] whose click waits for the release, when the travel is known:
  /// a button, a video's or speaker's controls, a sheet, an instrument's
  /// keys, a live counter's buttons and pieces, a chart's key. A press that
  /// travels moves the element instead. True if one took the press.
  bool _pressSelectedControls(_Press press, CanvasElement element) {
    var _Press(:doc) = press;
    // A selected button is tried by a click and moved by a drag, so its
    // action waits for pointer-up, when the travel is known. See
    // PendingClick.
    if (element is ButtonElement && controller.isOnlySelected(element.id)) {
      _gesture = _BoxMove(_beginTransform(), click: _ButtonClick(element));
      return true;
    }

    // A selected speaker's or video's controls, on the same terms: a press
    // that stays put plays, mutes, sets the volume or seeks; one that
    // travels moves it.
    if (element is VideoElement && controller.isOnlySelected(element.id)) {
      var part = _videoPartAt(element, doc);
      if (part != null) {
        _gesture =
            _BoxMove(_beginTransform(), click: _VideoClick(element, part, doc));
        return true;
      }
    }

    // A selected sheet with a score: a press that stays put moves the
    // playhead to the note there; one that travels moves the sheet. Its
    // playbar takes a press picked or not.
    var onBar = element is SheetElement &&
        (sheetBarRect(element, _hit.posed(element))?.contains(doc) ?? false);
    if (onBar) controller.selectAlone(element.id);
    if (element is SheetElement &&
        element.score.isNotEmpty &&
        controller.isOnlySelected(element.id)) {
      _gesture = _BoxMove(_beginTransform(), click: _SheetClick(element, doc));
      return true;
    }

    // A selected instrument's keys sound on press and stop on release; a
    // press that travels releases the note and moves the keyboard. Further
    // down the key is harder, as on a real one.
    if (element is AudioElement &&
        element.instrument != null &&
        controller.isOnlySelected(element.id)) {
      var keys = keyboardLayout(element.instrument!, _hit.posed(element));
      if (keys.keyAt(doc) case (var key, var depth)?) {
        controller.noteOn(element, key,
            velocity: (50 + depth * 77).round(),
            place: neckPlaceAt(keys, element.instrument!, doc));
        _gesture = _BoxMove(_beginTransform(), click: _KeyHeld(element, key));
        return true;
      }
    }

    if (element is AudioElement && controller.isOnlySelected(element.id)) {
      var part = _audioPartAt(element, doc);
      if (part != null) {
        _gesture =
            _BoxMove(_beginTransform(), click: _AudioClick(element, part, doc));
        return true;
      }
    }

    // A live counter's buttons, on the same terms: only when selected and the
    // press does not become a drag. A loose piece is both, so the press is
    // armed here and the drag moves the piece.
    if (element is CounterElement && controller.isOnlySelected(element.id)) {
      var part = _counterPartUnder(element, doc);
      var at = element.live ? _counterButtonAt(element, doc) : -1;
      if (part != null) {
        controller.beginInteraction();
        _dragStart = doc;
        var click = at >= 0 && element.live ? _CounterClick(element, at) : null;
        setState(
            () => _gesture = _CounterPieceDrag(element.id, part, click: click));
        return true;
      }
      if (at >= 0) {
        _gesture =
            _BoxMove(_beginTransform(), click: _CounterClick(element, at));
        return true;
      }
    }

    // A chart's key entry switches its series, on the same terms.
    if (element is ChartElement && controller.isOnlySelected(element.id)) {
      var at = _legendSeriesAt(element, doc);
      if (at >= 0) {
        var click = _LegendClick(element, at);
        // Held rather than tapped, the press moves the key instead.
        click.hold = Timer(CanvasStageState._legendHoldDelay, () {
          click.hold = null;
          _holdLegend(element);
        });
        _gesture = _BoxMove(_beginTransform(), click: click);
        return true;
      }
    }
    return false;
  }

  /// _pressSecondClick takes the second click of a double click on a
  /// selected [element], which opens it: a drawing or a picture for
  /// editing, a table's cell or a text for typing, a Layout's cell. A press
  /// it does not take is remembered as a first click. True if it took the
  /// press.
  bool _pressSecondClick(_Press press, CanvasElement element) {
    var _Press(:doc) = press;
    // A second click on a selected drawing opens it for editing.
    if (element is VectorElement &&
        !element.locked &&
        _secondClickOn(element)) {
      _mode = _DragMode.none;
      var at = doc;
      unawaited(startVectorEditing(context, controller, element).then((_) {
        var e = controller.editingVector;
        if (!mounted || e == null || e.id != element.id) return;
        var reach = handleReach(e.handleSize) / _scale;
        var shape = shapeAt(e, at, reach);
        if (shape >= 0) controller.pickVectorShape(shape);
      }));
      return true;
    }

    // A second click on a selected picture opens its layers, the one under
    // the click picked. With the base picked, a drag moves the picture
    // inside its box (see _framing).
    if (element is ImageElement && !element.locked && _secondClickOn(element)) {
      controller.editImage(element.id, layer: layerAt(element, doc).id);
      _mode = _DragMode.none;
      return true;
    }

    // A second click on a selected table's cell opens it for typing.
    if (element is TableElement && !element.locked && _secondClickOn(element)) {
      var at = tableCellAt(element, _hit.posed(element), doc);
      if (at != null) {
        setState(
            () => _editing = CellEdit(element.id, row: at.$1, column: at.$2));
        _mode = _DragMode.none;
        return true;
      }
    }

    // A second click on a selected Layout picks the cell under it.
    if (element is LayoutElement && _secondClickOn(element)) {
      _doubleClickLayout(element, doc);
      _mode = _DragMode.none;
      return true;
    }

    // A second click on a selected text element opens it for typing; the
    // first only selects, so it can still be dragged. Not one whose words
    // come from a document or a flow: it does not own them, and typing would
    // be overwritten.
    if (element is TextElement &&
        !element.wordsFromDocument &&
        flowSourceOf(element, document) == null &&
        _secondClickOn(element)) {
      // A locked piece is neither opened nor picked, and it is not the
      // element's own words under it: the click is an ordinary one.
      var piece = _textItemAt(element, doc, locked: true);
      if (piece != null && piece.locked) {
        _lastClickAt = clock.now();
        return false;
      }
      // A picture has no words: it is picked, which gives it its own box
      // to move, size, turn or delete (stage_text_pieces.dart).
      if (piece != null && piece.isIcon) {
        controller.pickTextLayer(element.id, piece.id);
        _mode = _DragMode.none;
        return true;
      }
      setState(() {
        _editing =
            TextEdit(element.id, itemId: piece?.id, click: _pointer?.position);
      });
      // Pick the typed piece in Layers, so its settings show.
      controller.pickTextLayer(element.id, piece?.id);
      _mode = _DragMode.none;
      return true;
    }
    _lastClickAt = clock.now();
    return false;
  }

  /// _pressSelectAndMove is the press no earlier step took: a reused
  /// element's copy, or else [element] selected (or, with Shift, toggled)
  /// and its move begun.
  void _pressSelectAndMove(_Press press, CanvasElement element) {
    var _Press(:doc, :click) = press;
    var copy = _copyAt(element, doc);
    if (copy != null && _pressCopy(element, copy, click)) return;

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

    // The click an earlier step armed on the element's own controls (a Code
    // panel's code) rides on the move, and then the copy pressed.
    _gesture = _BoxMove(_beginTransform(), click: click, copy: copy);
  }

  /// _secondClickOn is whether this press is the second of a double click
  /// on [e]: Shift is not held, [e] is the one element selected, and the
  /// last click was within the double-click window.
  bool _secondClickOn(CanvasElement e) =>
      !_shiftHeld &&
      controller.isOnlySelected(e.id) &&
      clock.now().difference(_lastClickAt) <
          CanvasStageState._doubleClickWindow;

  /// _copyAt is the copy of reused [element] at [doc], as the click that
  /// would pick it, or null where there is none.
  _CopyPick? _copyAt(CanvasElement element, Offset doc) {
    var set = element.base.motion.instances;
    if (set == null) return null;
    var i = element.instanceAt(doc, controller.frame, controller.document,
        live: controller.liveMotion);
    if (i == null) return null;
    return _CopyPick(element.id, set.items[i].id);
  }

  /// _pressCopy takes a press on [copy] of reused [element]. Alt drags out
  /// new copies of it (or of those picked), made once the press travels;
  /// Shift picks it in or out; with
  /// copies picked, it is picked and dragged alone. Otherwise the press goes
  /// on to the element: a drag moves them all, a click picks this one (see
  /// _CopyPick). The copies dragged carry [click], armed by an earlier step
  /// on the element's own controls, till the release. True if handled.
  bool _pressCopy(CanvasElement element, _CopyPick copy, PendingClick? click) {
    var set = element.base.motion.instances!;
    var id = copy.id;
    var picked = controller.pickedCopiesOf(element.id);
    if (HardwareKeyboard.instance.isAltPressed) {
      if (!controller.selection.contains(element.id)) {
        controller.selectOnly(element.id);
      }
      controller.beginInteraction();
      _gesture = _CopiesDrag(null, const {},
          click: click, copying: picked.contains(id) ? picked : {id});
      return true;
    }
    if (_shiftHeld && controller.selection.contains(element.id)) {
      controller.pickCopy(element.id, id, toggle: true);
      _mode = _DragMode.none;
      return true;
    }
    if (picked.isNotEmpty) {
      if (!picked.contains(id)) {
        controller.pickCopy(element.id, id);
        picked = {id};
      }
      controller.beginInteraction();
      _gesture = _CopiesDrag(set, picked, click: click);
      return true;
    }
    return false;
  }

  /// _beginCopyBox begins sizing or, [turning], turning copy [i] of reused
  /// [e] by its own box, and opens the undo step the gesture's end closes.
  _CopyBoxDrag _beginCopyBox(CanvasElement e, int i, {required bool turning}) {
    var set = e.base.motion.instances!;
    var drag = _CopyBoxDrag(
        turning: turning,
        pivot: e.anchorIn(e.boundsWith(_copyPose(e, i))),
        size: set.sizeOf(i),
        turn: set.turnOf(i));
    controller.beginInteraction();
    return drag;
  }

  /// _applyCopyBox sizes or turns the one picked copy as its handle is
  /// dragged to [doc], for [drag]: sized evenly (a copy has one Size) by how
  /// much farther from its anchor the pointer is along the line pressed on;
  /// turned by the angle swept, in 15-degree steps with Shift.
  void _applyCopyBox(_CopyBoxDrag drag, Offset doc) {
    var e = controller.selected;
    if (e == null) return;
    var from = _dragStart - drag.pivot, to = doc - drag.pivot;
    if (drag.turning) {
      var swept = (math.atan2(to.dy, to.dx) - math.atan2(from.dy, from.dx)) *
          180 /
          math.pi;
      var turn = drag.turn + swept;
      if (_shiftHeld) turn = steppedTurn(turn);
      turn = (turn + 180) % 360 - 180;
      controller.setCopyOwn(e.id, CopyValue.turn.name, turn, transient: true);
      return;
    }
    var along = from.distanceSquared;
    if (along < 1e-6) return;
    var f = (to.dx * from.dx + to.dy * from.dy) / along;
    var size = (drag.size * f).clamp(CopyValue.size.min, CopyValue.size.max);
    controller.setCopyOwn(e.id, CopyValue.size.name, size, transient: true);
  }

  /// _moveCopies puts the copies [drag] moves [delta] from their start,
  /// along one axis with Shift. An Alt-drag's copies are made on its first
  /// step, beside those it copies, and are what it moves.
  void _moveCopies(_CopiesDrag drag, Offset delta) {
    var of = controller.selected?.id;
    if (drag.copying case var ids? when of != null) {
      drag.copying = null;
      drag.dragged = controller.duplicateCopies(of, ids, Offset.zero);
      drag.start = controller.motionOf(of).instances;
    }
    var from = drag.start;
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
            drag.dragged.contains(x.id)
                ? x.copyWith(dx: x.dx + delta.dx, dy: x.dy + delta.dy)
                : x,
        ]),
        transient: true);
  }
}

/// _Press is what every step of a press reads: the event, where it landed
/// on the stage, and the same point in the document. It is made once, as
/// the press begins, so no step works the point out again after another
/// has changed the view.
class _Press {
  _Press(this.event, this.stage, this.doc);

  final PointerDownEvent event;
  final Offset stage;
  final Offset doc;

  /// click is a click an earlier step armed on the element's own controls
  /// for the move a later step begins (_pressSelectAndMove): a Code panel's
  /// code, pressed, opens for typing if the press stays put.
  PendingClick? click;
}
