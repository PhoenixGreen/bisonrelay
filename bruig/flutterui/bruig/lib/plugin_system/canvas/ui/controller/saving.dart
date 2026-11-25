part of '../canvas_controller.dart';

// Loading a canvas and saving it: autosave after edits, Save and Save as. Part
// of CanvasController: its fields and lifecycle are in canvas_controller.dart.

extension CanvasSaving on CanvasController {
  /// load replaces the whole session with a document from disk.
  void load(CanvasDocument document, {String? folder, String? name}) {
    // A game and a stop waiting for an action are ended, as leaving the
    // page ends them: each holds a timer or a key hook, not only a field.
    if (gaming) gaming = false;
    _endWait();
    pause();
    stopAudio();
    // What is held live is let go of through the instruments holding it,
    // so before the document they are in is replaced.
    _letGoOfLive();
    // A channel listened to alone: the engine hears it so too.
    if (_mixerState.listening case (var channel, _)) listenAt(channel, null);
    // Empty sounds left as elements are dropped. An empty channel made on
    // purpose (named, with effects, Speech or slot clips) stays, since its
    // slots and mix would go with it.
    for (var e in document.elements) {
      if (e is AudioElement &&
          e.clip.timed &&
          e.clip.isEmpty &&
          e.instrument == null &&
          e.clip.channelName.isEmpty &&
          e.clip.mix.isDefault &&
          !document.session.slots
              .containsKey(e.clip.channel.isNotEmpty ? e.clip.channel : e.id)) {
        document = document.removeElement(e.id);
      }
      // A drawing saved mid-edit opens with its box fitted round it.
      if (e is VectorElement && e.edited) {
        var fitted = boxedToDrawing(e);
        if (!identical(fitted, e)) document = document.withElement(fitted);
      }
    }
    _document = document;
    this.folder = folder;
    this.name = name;
    _loads++;
    _forgetDocument();
    _undo.clear();
    _redo.clear();
    _interaction = null;
    _savedEdits = _edits;
    // The zoom and the pan go: both are a position inside the document being
    // replaced. The fit stays, since it is about the reader's screen.
    _zoom = 1;
    _pan = Offset.zero;
    slotsScroll.value = 0;
    // A piece of sound opens on what it is made with.
    if (document.kind.isAudio) _openSoundDesk();
    // Opened on the frame everything has arrived by, so a canvas whose
    // elements arrive does not open as an empty page.
    _frame = settledFrameOf(_document);
    // Counters set to start running do, as when the page first opens.
    startCounters();
    notifyListeners();
  }

  /// _forgetDocument lets go of everything kept about the canvas that was
  /// open: what was picked in it, what was open on it, what was fetched for
  /// it. All of it names that canvas's elements, scenes or sheets, and the
  /// session outlives the canvas, so anything left would be met by the next
  /// one. State that names part of a document belongs in this list:
  /// test/canvas_forget_document_test.dart fails for a field of the
  /// controller that is neither let go of here nor named there as meant to
  /// outlive a canvas.
  void _forgetDocument() {
    _offTimeline.clear();
    motionPlayer.clear();
    _selectedSlot = null;
    _selection = {};
    _offCanvas = const {};
    _backgroundSelected = false;
    _focusedPlayer = null;
    hoveredButton = null;
    _beforePreview = null;
    // Clips and scenes picked for the Chain and the timeline.
    _pickedMotion = _pickedPlacement = _pickedOf = null;
    _motionPicks = const {};
    _ownTab = null;
    _clipSettings.clear();
    _pickedScene = null;
    _pickedSceneWith = const {};
    _joinPicked = _joinPress = false;
    // What the playhead was on, which pause keeps for a join watched:
    // frames of that canvas's run, and the scene to go back to.
    _playheadOn = const OnTimeline();
    _playbackState.rangeEnd = null;
    // Its Code panels' picks, scrolls and runs shown, the panels showing
    // all their code, and the pane pressed or edited, by their ids.
    _forgetCodePicks();
    _codeFull.clear();
    _codePane.clear();
    _codeEditing = null;
    // Its Run panels: those run here, which alone may open live; those
    // running, whose runs are let go (nothing stops one: runCode drops what
    // it brings back); the one open live, which the stage shuts once it is
    // gone; and its task cards' checks.
    _codeRunHere.clear();
    _codeRuns.clear();
    _codeLive = null;
    _codeTaskChecks.clear();
    _codeTaskBusy.clear();
    // The editor's loop, round a stretch of that canvas's frames.
    _playbackState.looping = false;
    _playbackState.loop = null;
    // The stop played to, whose label shows while the playhead is on it.
    _playbackState.stoppedAt = null;
    // Rows folded by their own arrows: the rows are that canvas's.
    _laneState.flippedRows.clear();
    // Its live counters' counts, by its elements' ids.
    _counters.forget();
    _chainFocus = null;
    _sceneFrames.clear();
    _wordQuery = "";
    // The studios, each open on one of its elements or sheets.
    studio3dOpen.value = false;
    studio3dElement = null;
    scoreStudio.value = null;
    codeStudio.value = null;
    dataStudio.value = null;
    dataStudioView = null;
    // How it was looked at: its channels' heights, its narrow strips, the
    // stretch of the timeline in view. The screen puts a saved canvas's own
    // back (restoreCanvasView); one never saved starts as any does.
    laneHeights.clear();
    _narrowStrips.clear();
    timelineView = null;
    timelineViewRuns = false;
    timelineViewSet++;
    _effectsOf = null;
    // What was fetched and compared for its elements and devices.
    lastFetched.clear();
    _synthSeen = null;
    _panelState.forgetDocument();
    _abB.clear();
    // Its channels as worked on: armed, soloed, held off their lanes,
    // waiting for a knob, their lanes shown, picked, dragged into order,
    // and Phrasing or the clip editor open on one.
    _armed.clear();
    _mixerState.forgetDocument();
    _overridden.clear();
    _selectedChannels = {};
    _speechState.channelOrder = const [];
    _speechState.phrasing = null;
    phrasingPicked = const {0};
    _clipEditing = _pianoRoll = null;
    _clipEditorShown = _pianoRollShown = false;
    rollSelected.clear();
    // What its elements were in the middle of: copies being placed, a
    // stroke held back, a motion previewed part way, a text's piece or a
    // layout's cell picked, an anchor shown, a lesson's steps ticked, a
    // sprite or a tile map painted.
    _placingCopies = null;
    _pendingStroke = null;
    _pendingPicture = null;
    _pendingKeeps = _pendingTeaches = _pendingFills = false;
    _sessionState.motionPreview = null;
    _texts = _TextState();
    _keyframes.anchorsShown.clear();
    _keyframes.marks.clear();
    _keyframes.marksOf = null;
    _playTasks = _PlayTaskState();
    _layouts = _LayoutState();
    if (_spritePaint != null) paintSprite(null);
    if (_tilePaint != null) paintTiles(null);
    // A picture's layers or a drawing being edited, with what was picked in
    // them: a layer, a warp grid's points, a clone's source, the copies of
    // an element reused, a corner being made, typing (whose gesture goes
    // with the history), and the eyedropper, whose answer was for a setting
    // of the last canvas's.
    _imageEditing = null;
    _pictures.layerId = baseLayerId;
    _alsoPicked.clear();
    _imageSolo = false;
    _putWarpAway();
    cloneOffset = null;
    _pictures.cloneFrom = null;
    _copiesOf = null;
    _pickedCopies = {};
    _allCopiesChosen = false;
    _vectorEditing = null;
    _vectors.typing = -1;
    _resetVectorEditing();
    _vectors.corner = null;
    _vectors.onSampled = null;
    // The Curves opened on one of its keyframes; a chord being stepped into
    // the piano roll and the clip editor's cursor.
    _trackCurvesFrame = null;
    _stepAt = null;
    _stepHeld.clear();
    _clipCursor = 0;
    // What the slots and a Play left: the cue row last launched, the slot
    // being pressed, elements a trigger took off their timelines, a take
    // gathered while recording (pause has written it), the stop markers'
    // counts and where the last Play began.
    _sessionState.sceneLaunched = null;
    _sessionState.cueLaunchedMaster = false;
    _sessionState.slotPressed = null;
    _triggeredOff.clear();
    _taken.clear();
    _clipLog.clear();
    _sessionClock = 0;
    _playbackState.loopCounts.clear();
    _playbackState.playedFrom = null;
    _playbackState.motionPainted = -1;
    // A practice take's marks, by its notes' places: drawn on any sheet.
    _gameState.marks.clear();
    _gameState.wrongKeys.clear();
    _gameState.found.clear();
    _gameState.mouthsOfSlots.clear();
    // Its jobs still going: each drops what it brings back (see _stillOn),
    // so none may keep a channel, a picture or a voice busy here. A voice
    // still speaking is stopped.
    for (var stop in _speechState.stops.values) {
      stop.stop();
    }
    _speechState.stops.clear();
    _speechState.speakingNow.clear();
    _speechState.into.clear();
    _speechState.shaping.clear();
    speechQueue.clear();
    speechPreviewing = null;
    joining.clear();
    singing.clear();
    _mixerState.freezing.clear();
    _pictures.maskBusy = null;
    _pictures.maskNote = null;
    _laneState.flippedRowsAt = null;
  }

  /// _openSoundDesk opens the mixer and the effects: what an audio document
  /// is worked on with, there being no canvas to look at.
  void _openSoundDesk() {
    _openPanel(DockPanel.mixer);
    // One detail panel: the Chain on its sound.
    _showChain(ChainView.sound);
  }

  /// scheduleAutosave writes the document out once editing stops for a
  /// moment, so a burst of edits is one write. Only once saved: until then
  /// there is nowhere to write, and inventing a file would fill the library.
  void scheduleAutosave() {
    if (name == null || !_dirty) return;
    _autosave?.cancel();
    _autosave = Timer(CanvasController._autosaveDelay, () {
      _autosave = null;
      if (name != null && _dirty) save();
    });
  }

  /// _toSave is the document as written: a drawing still being edited gets
  /// its box fitted, as leaving editing would (not live, which would move
  /// the pencil's mirror lines). See _fitEditedVector.
  CanvasDocument get _toSave {
    // Never a look that is only being tried. See tryElement.
    var document = _beforePreview ?? _document;
    var e = editingVector;
    if (e == null) return document;
    var fitted = boxedToDrawing(e);
    return identical(fitted, e) ? document : document.withElement(fitted);
  }

  /// save writes back to where the document came from, if it has been saved.
  Future<bool> save() async {
    _autosave?.cancel();
    _autosave = null;
    var f = folder, n = name;
    if (n == null) return false;
    var at = _edits;
    var loads = _loads;
    var ok = await CanvasStorage.save(f ?? "", n, _toSave);
    // Tidying the stores is bookkeeping a save need not wait for, and need
    // not do every time: see CanvasLibrary.tidySoon.
    if (ok) {
      CanvasLibrary.tidySoon(open: _document.storedIds);
    }
    // Written, but another canvas has opened since: its edits are its own.
    if (ok && _stillOn(loads)) {
      _savedEdits = at;
      notifyListeners();
    }
    return ok;
  }

  /// detachFromFile lets go of the file this document was saved as, for
  /// when that file has gone (deleted from Files): the work stays open as a
  /// canvas never saved, with no folder or name and its changes unsaved, so
  /// nothing writes the file back and leaving asks before it is lost.
  void detachFromFile() {
    _autosave?.cancel();
    _autosave = null;
    folder = null;
    name = null;
    // A count no document has had: whatever is open is on disk nowhere.
    _savedEdits = -1;
    notifyListeners();
  }

  /// saveAs writes to a new place and makes it this document's home.
  Future<bool> saveAs(String folder, String name) async {
    var at = _edits;
    var loads = _loads;
    var ok =
        await CanvasStorage.save(folder, name, _toSave.copyWith(title: name));
    if (!ok) return false;
    // Written; but another canvas opened meanwhile is not the one saved,
    // and does not take its place or its name.
    if (!_stillOn(loads)) return true;
    this.folder = folder;
    this.name = name;
    _document = _document.copyWith(title: name);
    _savedEdits = at;
    notifyListeners();
    return true;
  }
}
