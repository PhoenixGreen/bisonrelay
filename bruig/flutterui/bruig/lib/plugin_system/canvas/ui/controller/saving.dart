part of '../canvas_controller.dart';

// Loading a canvas and saving it: autosave after edits, Save and Save as. Part
// of CanvasController: its fields and lifecycle are in canvas_controller.dart.

extension CanvasSaving on CanvasController {
  /// load replaces the whole session with a document from disk.
  void load(CanvasDocument document, {String? folder, String? name}) {
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
    _offTimeline.clear();
    motionPlayer.clear();
    _selectedSlot = null;
    _selection = {};
    _backgroundSelected = false;
    _focusedPlayer = null;
    _beforePreview = null;
    _undo.clear();
    _redo.clear();
    _interaction = null;
    _savedEdits = _edits;
    // The zoom and the pan go: both are a position inside the document being
    // replaced. The fit stays, since it is about the reader's screen.
    _zoom = 1;
    _pan = const Offset2(0, 0);
    // A piece of sound opens on what it is made with.
    if (document.kind.isAudio) _openSoundDesk();
    // Opened on the frame everything has arrived by, so a canvas whose
    // elements arrive does not open as an empty page.
    _frame = settledFrameOf(_document);
    notifyListeners();
  }

  /// _openSoundDesk opens the mixer and the effects: what an audio document
  /// is worked on with, there being no canvas to look at.
  void _openSoundDesk() {
    _mixerOpen = true;
    _effectsOpen = true;
    // One detail panel: the Chain on its sound.
    _animationOpen = false;
    _chainMotion = false;
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
      CanvasLibrary.tidySoon(
          open: {..._document.assetIds, ..._document.mediaIds});
    }
    if (ok) {
      _savedEdits = at;
      notifyListeners();
    }
    return ok;
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
