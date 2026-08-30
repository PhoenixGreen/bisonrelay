import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/render/image_store.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:flutter/foundation.dart';

// canvas_controller.dart holds everything about the canvas being edited that
// is not the document itself: what is selected, where the playhead is, how far
// in the view is zoomed, what can be undone, and whether any of it has been
// saved.
//
// The document is immutable (see canvas_document.dart), so every edit goes
// through [apply], which is the only place the document is replaced. That one
// funnel is what makes undo a list of past documents rather than a list of
// operations to reverse -- and reversible operations are where an editor like
// this usually goes wrong, because the reverse of "resize" is not "resize
// back" once a rotation has happened in between.
//
// It also means an edit cannot half-happen. There is no state in which the
// selection refers to an element the document no longer has, because both
// change in one assignment.

/// _maxUndo bounds the history.
///
/// Documents are small -- a few kilobytes of value objects, sharing every
/// element that did not change -- so this can be generous. It is bounded at
/// all only because a session spent nudging a slider would otherwise grow
/// without limit.
const int _maxUndo = 120;

/// minZoom and maxZoom bound the view.
///
/// These are multiples of the fitted size, not of the document's own pixels --
/// see [CanvasController.zoom]. So 1 is "the whole canvas, filling the area",
/// 0.25 is a quarter of that with room around it, and 16 is close enough to
/// nudge a single player dot into place.
const double minZoom = 0.25;
const double maxZoom = 16;

/// CanvasTool is what dragging on the canvas does.
///
/// Two tools rather than one gesture that guesses. Dragging meant "move what
/// is under the pointer, or sweep a selection over empty space", and panning
/// was on the middle button and the space bar -- both of which are invisible,
/// and one of which most trackpads do not have. With a tool chosen explicitly
/// the reader can also *stop* the view moving, which is what somebody nudging
/// a player into place actually wants.
enum CanvasTool {
  /// select moves and selects elements. The view does not move at all in this
  /// tool -- not by dragging and not by scrolling -- so nothing shifts under a
  /// careful adjustment.
  select("Select", "Move and select elements; the view stays put"),

  /// pan moves the view. Dragging slides the canvas about and the wheel zooms.
  pan("Pan", "Drag to move around the canvas, scroll to zoom");

  final String label;
  final String description;
  const CanvasTool(this.label, this.description);
}

/// CanvasFit is how large the canvas's frame is drawn.
///
/// Two modes, because "as big as it will go" means two different things
/// depending on the shape of the document. A 16:9 banner in a wide window is
/// limited by the height; a 9:16 story is limited by the width, and fitting the
/// whole of it leaves it a narrow strip down the middle with most of the
/// window empty on either side.
enum CanvasFit {
  /// whole shows all of the canvas at once, limited by whichever of the two
  /// dimensions runs out first. Nothing scrolls.
  whole("Show the whole canvas"),

  /// width fills the area's full width and lets the canvas be as tall as it
  /// needs, scrolling if that is taller than the window. What a tall document
  /// wants: readable at the cost of not seeing all of it at once.
  width("Fit to width");

  final String label;
  const CanvasFit(this.label);
}

/// CanvasController is the editing session.
class CanvasController extends ChangeNotifier {
  CanvasController(CanvasDocument document) : _document = document;

  CanvasDocument _document;
  CanvasDocument get document => _document;

  final CanvasImageStore images = CanvasImageStore();

  final List<CanvasDocument> _undo = [];
  final List<CanvasDocument> _redo = [];

  /// _interaction is the document as it was when a drag began.
  ///
  /// A drag produces dozens of edits a second and every one of them must not
  /// be its own undo step -- otherwise undoing a move means pressing it forty
  /// times. So the whole gesture is one step: the document is remembered when
  /// the gesture starts and pushed onto the history when it ends.
  CanvasDocument? _interaction;

  Set<String> _selection = {};
  Set<String> get selection => _selection;

  bool _backgroundSelected = false;

  /// backgroundSelected is whether the canvas's own background is the thing
  /// being edited.
  ///
  /// Its own flag rather than a sentinel id inside [selection], because the
  /// background is not an element and every operation that walks the selection
  /// -- delete, duplicate, nudge, group into a keyframe -- would have had to
  /// learn to skip it. Missing one of them is silent: the operation finds no
  /// element for the id and quietly does nothing, which looks exactly like a
  /// bug in the operation.
  ///
  /// It is exclusive with the element selection. Both mean "this is what the
  /// settings below the layer list are about", and there is only one of those.
  bool get backgroundSelected => _backgroundSelected;

  /// selectBackground makes the background the selected layer.
  void selectBackground() {
    if (_backgroundSelected && _selection.isEmpty) return;
    _selection = {};
    _backgroundSelected = true;
    notifyListeners();
  }

  int _frame = 0;
  int get frame => _frame;

  double _zoom = 1;

  /// zoom is a multiple of the size at which the canvas fills the area it is
  /// drawn in -- not of the document's own pixels.
  ///
  /// That is the difference between this and every other zoom control, and it
  /// is deliberate. A canvas has no natural size on screen: the same document
  /// is 1280 pixels wide or 4096 depending only on what it is going to be
  /// published at, and a zoom measured against that would mean the same design
  /// opened at two different export widths filled the window very differently.
  /// So the canvas always fills the area to begin with, and zoom is how far in
  /// you have gone from there. 1 is the whole canvas; anything above it is a
  /// detail, and pans.
  ///
  /// The fitted size itself is worked out by the stage, which is the only
  /// thing that knows how much room there is. See CanvasStage.
  double get zoom => _zoom;

  /// atFit is whether the view is showing the whole canvas, untouched -- which
  /// is what the Fit button lights up for.
  bool get atFit =>
      (_zoom - 1).abs() < 0.001 && _pan.dx == 0 && _pan.dy == 0;

  Offset2 _pan = const Offset2(0, 0);
  Offset2 get pan => _pan;

  CanvasFit _fit = CanvasFit.whole;

  /// fit is how large the frame is drawn. See [CanvasFit].
  CanvasFit get fit => _fit;

  set fit(CanvasFit value) {
    if (_fit == value) return;
    _fit = value;
    // Changing what "all of it" means invalidates a zoom that was chosen
    // against the old frame: a 3x zoom on a whole-canvas frame is a very
    // different amount of magnification once the frame is four times the size.
    _zoom = 1;
    _pan = const Offset2(0, 0);
    notifyListeners();
  }

  bool _autoKeyframe = false;

  /// autoKeyframe makes every move record itself.
  ///
  /// With it on, dragging anything while the playhead is on frame N writes a
  /// keyframe at frame N instead of moving the thing. That is how an animation
  /// is actually built: park the playhead, drag one player, move the playhead,
  /// drag the next -- rather than pressing Add keyframe before and after every
  /// single movement and hoping the two ends were captured.
  ///
  /// Off by default, because with it on a document cannot be tidied up without
  /// recording the tidying.
  bool get autoKeyframe => _autoKeyframe;

  set autoKeyframe(bool value) {
    if (_autoKeyframe == value) return;
    _autoKeyframe = value;
    notifyListeners();
  }

  bool _showHelpers = true;

  /// showHelpers is whether the editing furniture is drawn: the box around the
  /// selection, the resize handles and the rotation ring.
  ///
  /// On by default -- without it there is no way to resize or rotate anything.
  /// Turned off to see the design as it will actually be published, which
  /// matters most on the work this tool is for: a pitch of twenty-two dots
  /// with a box and eight handles over one of them is a picture of an editor,
  /// not a picture of a formation.
  ///
  /// It hides the handles from the pointer as well as from the eye. A handle
  /// that can be grabbed where nothing is drawn is a click that appears to do
  /// nothing and then resizes something.
  bool get showHelpers => _showHelpers;

  set showHelpers(bool value) {
    if (_showHelpers == value) return;
    _showHelpers = value;
    notifyListeners();
  }

  int? _focusedPlayer;

  /// focusedPlayer is which player of the selected team the timeline is about.
  ///
  /// A player is not an element -- it has no id and cannot be selected -- but
  /// it does have its own keyframes, so something has to say which player the
  /// keyframe controls are pointed at. Set by clicking one on the canvas, and
  /// cleared whenever the selection changes, since a player of a team that is
  /// no longer selected is not being edited by anything.
  int? get focusedPlayer => _focusedPlayer;

  set focusedPlayer(int? value) {
    if (_focusedPlayer == value) return;
    _focusedPlayer = value;
    notifyListeners();
  }

  /// focusedTeam is the selected element when it is a team, and null
  /// otherwise. What the timeline asks before offering a player's keyframes.
  TeamElement? get focusedTeam {
    var element = selected;
    return element is TeamElement ? element : null;
  }

  CanvasTool _tool = CanvasTool.select;

  /// tool is what dragging on the canvas does. Select to begin with, because
  /// that is what somebody who has just added an element wants to do to it.
  CanvasTool get tool => _tool;

  set tool(CanvasTool value) {
    if (_tool == value) return;
    _tool = value;
    notifyListeners();
  }

  /// hoveredButton is the button under the pointer, which the renderer needs
  /// so hover colours can be seen while they are being chosen.
  String? hoveredButton;

  Timer? _playback;
  bool get playing => _playback != null;

  /// _loopCounts tracks how many times each loop marker has fired, so a marker
  /// with a repeat limit stops rather than running forever.
  final Map<int, int> _loopCounts = {};

  /// folder and name are where this document is saved, or null when it has
  /// never been saved. Save writes back to them; Save As changes them.
  String? folder;
  String? name;

  bool _dirty = false;

  /// dirty is whether there are changes the file on disk does not have.
  ///
  /// Set by [apply] rather than by comparing documents, because comparing two
  /// documents deeply on every keystroke is expensive and because an edit that
  /// happens to restore the saved state is still an edit somebody may want to
  /// keep.
  bool get dirty => _dirty;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// selectedElements are the chosen elements in paint order, which is the
  /// order every multi-element operation wants.
  List<CanvasElement> get selectedElements =>
      [for (var e in _document.elements) if (_selection.contains(e.id)) e];

  /// selected is the one chosen element, or null when none or several are.
  /// What the settings bar asks, since it shows one element's controls.
  CanvasElement? get selected =>
      _selection.length == 1 ? _document.elementById(_selection.first) : null;

  // ------------------------------------------------------------------------
  // Editing
  // ------------------------------------------------------------------------

  /// apply replaces the document, pushing the old one onto the undo history.
  ///
  /// [transient] skips the history, for the many small changes inside one
  /// gesture. The gesture's own first document was already remembered by
  /// [beginInteraction], so nothing is lost.
  void apply(CanvasDocument next, {bool transient = false}) {
    if (identical(next, _document)) return;

    if (!transient && _interaction == null) {
      _undo.add(_document);
      if (_undo.length > _maxUndo) _undo.removeAt(0);
      _redo.clear();
    }

    _document = next;
    _dirty = true;

    // A selection can outlive the elements it names -- deleting, or loading a
    // different document -- and every reader of the selection would then have
    // to cope with an id that resolves to nothing. Pruning here means none of
    // them do.
    _selection = _selection
        .where((id) => _document.indexOf(id) >= 0)
        .toSet();

    if (_frame >= _document.frames) _frame = _document.frames - 1;

    notifyListeners();
  }

  /// beginInteraction starts a gesture: everything until [endInteraction] is
  /// one undo step.
  void beginInteraction() {
    _interaction ??= _document;
  }

  /// endInteraction closes the gesture, pushing its starting document onto the
  /// history if anything actually changed.
  void endInteraction() {
    var before = _interaction;
    _interaction = null;
    if (before == null || identical(before, _document)) return;
    _undo.add(before);
    if (_undo.length > _maxUndo) _undo.removeAt(0);
    _redo.clear();
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_document);
    _document = _undo.removeLast();
    _dirty = true;
    _selection = _selection.where((id) => _document.indexOf(id) >= 0).toSet();
    if (_frame >= _document.frames) _frame = _document.frames - 1;
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_document);
    _document = _redo.removeLast();
    _dirty = true;
    _selection = _selection.where((id) => _document.indexOf(id) >= 0).toSet();
    if (_frame >= _document.frames) _frame = _document.frames - 1;
    notifyListeners();
  }

  /// replaceElement is the commonest edit there is: one element changed.
  void replaceElement(CanvasElement element, {bool transient = false}) =>
      apply(_document.withElement(element), transient: transient);

  void addElement(CanvasElement element, {bool select = true}) {
    apply(_document.addElement(element));
    if (select) selectOnly(element.id);
  }

  void deleteSelected() {
    if (_selection.isEmpty) return;
    var next = _document;
    for (var id in _selection) {
      next = next.removeElement(id);
    }
    _selection = {};
    apply(next);
  }

  /// duplicateSelected copies the chosen elements, offset a little so the copy
  /// is visibly a second thing rather than sitting exactly on the original.
  void duplicateSelected() {
    if (_selection.isEmpty) return;
    var next = _document;
    var made = <String>{};
    for (var element in selectedElements) {
      var copy = element
          .withId(newElementId())
          .withBase(x: element.x + 24, y: element.y + 24);
      next = next.addElement(copy);
      made.add(copy.id);
    }
    apply(next);
    _selection = made;
    notifyListeners();
  }

  /// nudgeSelected moves everything chosen, which is what the arrow keys do.
  void nudgeSelected(double dx, double dy, {bool transient = false}) {
    if (_selection.isEmpty) return;
    var next = _document;
    for (var element in selectedElements) {
      if (element.locked) continue;
      next = next.withElement(_moved(element, dx, dy));
    }
    apply(next, transient: transient);
  }

  /// posesRatherThanMoves is whether dragging [element] should record a
  /// keyframe instead of relocating it.
  ///
  /// This is the difference between "put this somewhere else" and "from here,
  /// go there", and getting it wrong is what made animation appear not to work
  /// at all. A keyframe's dx and dy are offsets from the element's *resting*
  /// position, so moving the resting position moves every keyframe with it: a
  /// pose captured at frame 1, a drag at frame 20 and a second pose captured
  /// there recorded two identical offsets of zero, and the element sat
  /// motionless in its new place. Nothing was broken; the drag had answered a
  /// different question from the one being asked.
  ///
  /// So a drag poses when the document is animated and either auto-keyframe is
  /// on, or the element has already been given keyframes -- something that has
  /// been animated is being posed, not repositioned. To relocate an animated
  /// element wholesale, the X and Y fields in its settings still move the
  /// resting position, and the whole animation travels with it.
  bool posesRatherThanMoves(CanvasElement element) =>
      _document.isAnimated &&
      (_autoKeyframe || (element.track?.isEmpty == false));

  /// _moved is one element shifted, as either a pose or a relocation.
  CanvasElement _moved(CanvasElement element, double dx, double dy) {
    if (!posesRatherThanMoves(element)) {
      return element.withBase(x: element.x + dx, y: element.y + dy);
    }
    var track = (element.track ?? ElementTrack.empty).seededFor(_frame);
    var pose = track.at(_frame);
    return element.withBase(
      track: track.withKey(
          pose.copyWith(frame: _frame, dx: pose.dx + dx, dy: pose.dy + dy)),
    );
  }

  /// movedTo is the stage's drag: where [element]'s top-left should now be.
  ///
  /// An absolute target rather than a delta, so a drag stays exact over its
  /// whole length. Accumulating deltas drifts, and on a pose it would compound
  /// into the keyframe -- a slow drag and a fast one would end up in different
  /// places.
  CanvasElement movedTo(CanvasElement element, Offset topLeft) {
    if (!posesRatherThanMoves(element)) {
      return element.withBase(x: topLeft.dx, y: topLeft.dy);
    }
    var track = (element.track ?? ElementTrack.empty).seededFor(_frame);
    var pose = track.at(_frame);
    return element.withBase(
      track: track.withKey(pose.copyWith(
        frame: _frame,
        dx: topLeft.dx - element.x,
        dy: topLeft.dy - element.y,
      )),
    );
  }

  /// setPlayerKeyframe writes one player's pose at the current frame.
  void setPlayerKeyframe(String teamId, int index, Keyframe key) {
    var team = _document.elementById(teamId);
    if (team is! TeamElement || index < 0 || index >= team.players.length) {
      return;
    }
    var spot = team.players[index];
    replaceElement(team.withPlayer(
        index,
        spot.copyWith(
            track: (spot.track ?? ElementTrack.empty).withKey(key))));
  }

  /// removePlayerKeyframe drops one, and the track with it when it was the
  /// last -- so a player who no longer moves carries no empty track into the
  /// saved file.
  void removePlayerKeyframe(String teamId, int index, int frame) {
    var team = _document.elementById(teamId);
    if (team is! TeamElement || index < 0 || index >= team.players.length) {
      return;
    }
    var spot = team.players[index];
    var track = spot.track;
    if (track == null) return;
    var next = track.withoutFrame(frame);
    replaceElement(team.withPlayer(
        index,
        next.isEmpty
            ? spot.copyWith(clearTrack: true)
            : spot.copyWith(track: next)));
  }

  // ------------------------------------------------------------------------
  // Selection
  // ------------------------------------------------------------------------

  void selectOnly(String id) {
    if (_selection.length == 1 && _selection.first == id && !_backgroundSelected) {
      return;
    }
    _backgroundSelected = false;
    _selection = {id};
    _focusedPlayer = null;
    notifyListeners();
  }

  void toggleSelected(String id) {
    _backgroundSelected = false;
    _selection = {..._selection};
    _selection.contains(id) ? _selection.remove(id) : _selection.add(id);
    notifyListeners();
  }

  void clearSelection() {
    if (_selection.isEmpty && !_backgroundSelected) return;
    _backgroundSelected = false;
    _focusedPlayer = null;
    _selection = {};
    notifyListeners();
  }

  void selectAll() {
    _backgroundSelected = false;
    _selection = {
      for (var e in _document.elements)
        if (!e.locked) e.id,
    };
    notifyListeners();
  }

  // ------------------------------------------------------------------------
  // View
  // ------------------------------------------------------------------------

  set zoom(double value) {
    var next = value.clamp(minZoom, maxZoom);
    if (next == _zoom) return;
    _zoom = next;
    // Coming back to the whole canvas re-centres it. Left alone, a pan made
    // while zoomed in would push the fitted canvas off to one side, where it
    // would sit with empty space beside it and no obvious way to say why.
    if ((_zoom - 1).abs() < 0.001) _pan = const Offset2(0, 0);
    notifyListeners();
  }

  void resetZoom() {
    _zoom = 1;
    _pan = const Offset2(0, 0);
    notifyListeners();
  }

  /// showWhole and fitWidth are the two frame buttons on the band. Each also
  /// clears the zoom, since pressing "show me all of it" while zoomed in and
  /// being shown a corner of it is not what either button says.
  void showWhole() {
    fit = CanvasFit.whole;
    resetZoom();
  }

  void fitWidth() {
    fit = CanvasFit.width;
    resetZoom();
  }

  void zoomBy(double factor) => zoom = _zoom * factor;

  set pan(Offset2 value) {
    _pan = value;
    notifyListeners();
  }

  // ------------------------------------------------------------------------
  // Playback
  // ------------------------------------------------------------------------

  set frame(int value) {
    var next = value.clamp(0, math.max(0, _document.frames - 1)).toInt();
    if (next == _frame) return;
    _frame = next;
    notifyListeners();
  }

  /// stepFrame moves the playhead, and stops playback first.
  ///
  /// Stopping is the point: scrubbing while the timer is still running means
  /// the next tick undoes the step, so the key appears to do nothing. Taking
  /// hold of the playhead is saying you want it where you put it.
  void stepFrame(int by) {
    pause();
    frame = _frame + by;
  }

  void play() {
    if (playing || _document.frames <= 1) return;
    _loopCounts.clear();
    var interval = Duration(
        microseconds: (1000000 / _document.frameRate).round().clamp(8000, 1000000));
    _playback = Timer.periodic(interval, (_) => _tick());
    notifyListeners();
  }

  void pause() {
    _playback?.cancel();
    _playback = null;
    notifyListeners();
  }

  void togglePlay() => playing ? pause() : play();

  void stop() {
    pause();
    frame = 0;
  }

  /// _tick advances one frame and obeys whatever marker is on the new one.
  ///
  /// The markers are applied after the advance rather than before, so a stop
  /// marker on frame 30 means "having reached 30, stop" -- which is what
  /// putting a marker on a frame looks like it should mean.
  void _tick() {
    var next = _frame + 1;
    if (next >= _document.frames) next = 0;
    _frame = next;

    for (var action in _document.actions) {
      if (action.frame != next) continue;
      switch (action.kind) {
        case TimelineActionKind.stop:
          pause();
        case TimelineActionKind.pause:
          // Implemented by stepping the playhead back to where it is, for as
          // many ticks as the hold asks for. Held as a countdown on the action
          // rather than by sleeping, so the window stays responsive and the
          // playhead can still be dragged out of the hold.
          var held = _loopCounts.update(action.frame, (v) => v + 1,
              ifAbsent: () => 1);
          if (held < action.holdFrames) _frame = next - 1 < 0 ? 0 : next;
          if (held >= action.holdFrames) _loopCounts.remove(action.frame);
        case TimelineActionKind.loop:
          var count = _loopCounts.update(action.frame, (v) => v + 1,
              ifAbsent: () => 1);
          if (action.repeats == 0 || count <= action.repeats) {
            _frame = action.target.clamp(0, _document.frames - 1).toInt();
          }
        case TimelineActionKind.jump:
          _frame = action.target.clamp(0, _document.frames - 1).toInt();
      }
    }
    notifyListeners();
  }

  /// runButtonAction is what pressing a button element does, both in the
  /// editor's preview and in a published interactive canvas.
  ///
  /// Returns the URL a link button asked to open, if any, so that the decision
  /// to actually open it -- which is a decision about leaving the app -- stays
  /// with the caller and never happens down here.
  String? runButtonAction(ButtonAction action) {
    switch (action.kind) {
      case ButtonActionKind.goToFrame:
        pause();
        frame = action.frame;
      case ButtonActionKind.playFrom:
        frame = action.frame;
        play();
      case ButtonActionKind.playToFrame:
        play();
      case ButtonActionKind.play:
        play();
      case ButtonActionKind.pause:
        pause();
      case ButtonActionKind.restart:
        frame = 0;
        play();
      case ButtonActionKind.toggleElement:
        var target = _document.elementById(action.elementId);
        if (target != null) {
          replaceElement(target.withBase(visible: !target.visible));
        }
      case ButtonActionKind.openLink:
        return action.url;
    }
    return null;
  }

  // ------------------------------------------------------------------------
  // Keyframes
  // ------------------------------------------------------------------------

  /// setKeyframe writes the pose at the current frame for one element.
  void setKeyframe(String id, Keyframe key) {
    var element = _document.elementById(id);
    if (element == null) return;
    var track = (element.track ?? ElementTrack.empty).withKey(key);
    replaceElement(element.withBase(track: track));
  }

  /// removeKeyframe drops the pose at [frame], and drops the track entirely
  /// when it was the last one -- so an element with no animation left carries
  /// no empty track into the saved file.
  void removeKeyframe(String id, int frame) {
    var element = _document.elementById(id);
    var track = element?.track;
    if (element == null || track == null) return;
    var next = track.withoutFrame(frame);
    replaceElement(next.isEmpty
        ? element.withBase(clearTrack: true)
        : element.withBase(track: next));
  }

  // ------------------------------------------------------------------------
  // Loading and saving
  // ------------------------------------------------------------------------

  /// load replaces the whole session with a document from disk.
  void load(CanvasDocument document, {String? folder, String? name}) {
    pause();
    _document = document;
    this.folder = folder;
    this.name = name;
    _selection = {};
    _backgroundSelected = false;
    _focusedPlayer = null;
    _frame = 0;
    _undo.clear();
    _redo.clear();
    _interaction = null;
    _dirty = false;
    _fit = CanvasFit.whole;
    _zoom = 1;
    _pan = const Offset2(0, 0);
    notifyListeners();
  }

  /// save writes back to where this document came from, or nowhere when it has
  /// never been saved.
  Future<bool> save() async {
    var f = folder, n = name;
    if (n == null) return false;
    var ok = await CanvasStorage.save(f ?? "", n, _document);
    if (ok) {
      _dirty = false;
      notifyListeners();
    }
    return ok;
  }

  /// saveAs writes to a new place and makes it this document's home.
  Future<bool> saveAs(String folder, String name) async {
    var ok = await CanvasStorage.save(folder, name, _document.copyWith(title: name));
    if (!ok) return false;
    this.folder = folder;
    this.name = name;
    _document = _document.copyWith(title: name);
    _dirty = false;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _playback?.cancel();
    images.dispose();
    super.dispose();
  }
}

/// Offset2 is a pair of doubles.
///
/// Its own type rather than dart:ui's Offset so that this file -- which is
/// pure session state and is unit tested without a widget binding -- imports
/// nothing from the framework. It converts at the one place the stage needs
/// it.
class Offset2 {
  final double dx;
  final double dy;
  const Offset2(this.dx, this.dy);

  Offset2 operator +(Offset2 other) => Offset2(dx + other.dx, dy + other.dy);

  @override
  bool operator ==(Object other) =>
      other is Offset2 && other.dx == dx && other.dy == dy;

  @override
  int get hashCode => Object.hash(dx, dy);
}
