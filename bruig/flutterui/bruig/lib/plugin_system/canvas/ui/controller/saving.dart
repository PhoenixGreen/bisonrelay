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
  /// one. State that names part of a document belongs in this list.
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
    // A join previewed and paused, which pause keeps: frames of that
    // canvas's run, and the scene to go back to.
    _previewJoin = null;
    _previewAt = null;
    _previewEnd = 0;
    _previewFrom = null;
    _previewFromMaster = false;
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
    timelineViewSet++;
    _effectsOf = null;
    // What was fetched and compared for its elements and devices.
    lastFetched.clear();
    _synthSeen = null;
    _panelState.forgetDocument();
    _abB.clear();
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
    var ok = await CanvasStorage.save(f ?? "", n, _toSave);
    // Tidying the stores is bookkeeping a save need not wait for, and need
    // not do every time: see CanvasLibrary.tidySoon.
    if (ok) {
      CanvasLibrary.tidySoon(open: _document.storedIds);
    }
    if (ok) {
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
    var ok =
        await CanvasStorage.save(folder, name, _toSave.copyWith(title: name));
    if (!ok) return false;
    this.folder = folder;
    this.name = name;
    _document = _document.copyWith(title: name);
    _savedEdits = at;
    notifyListeners();
    return true;
  }
}
