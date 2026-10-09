import 'dart:async';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'dart:math' as math;
import 'dart:ui' show Color, Offset, Rect;

import 'package:bruig/components/paint_spec.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/responsive_layout.dart';
import 'package:bruig/plugin_system/canvas/render/scene_sequence.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/vector_text.dart';
import 'package:bruig/plugin_system/canvas/model/font_files.dart';
import 'package:bruig/plugin_system/canvas/model/vector_brush.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/render/vector_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_shapes.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/render/image_store.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/export/video_export.dart'
    show ffmpegPath;
import 'package:bruig/plugin_system/canvas/media/ffmpeg_video.dart';
import 'package:bruig/plugin_system/canvas/media/video_runtime.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/render/video_painter.dart';
import 'package:bruig/plugin_system/canvas/media/audio_engine.dart';
import 'package:bruig/plugin_system/canvas/media/audio_runtime.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/render/audio_painter.dart';

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

/// RetouchBrush is what the brush does to a picture's background.
enum RetouchBrush {
  off("Off"),

  /// erase takes the picture away, for a patch the automatic pass missed.
  erase("Rub out"),

  /// cutAround draws a boundary rather than a mark: everything outside it
  /// goes. See RemovalStroke.fill.
  cutAround("Cut around"),

  /// restore puts it back, for a hand or a shoulder the automatic pass ate.
  restore("Put back"),

  /// markBackground and markSubject do not change the picture at all: they
  /// leave evidence for RemovalMode.learn to work from. See
  /// BackgroundRemoval.hints.
  markBackground("Mark background"),
  markSubject("Mark subject");

  final String label;
  const RetouchBrush(this.label);

  bool get on => this != RetouchBrush.off;

  /// teaches is whether this brush leaves a hint rather than rubbing something
  /// out. The difference matters at the point the stroke is stored, and
  /// nowhere else.
  bool get teaches =>
      this == RetouchBrush.markBackground || this == RetouchBrush.markSubject;

  /// keeps is whether the mark is about the subject rather than the
  /// background.
  bool get keeps =>
      this == RetouchBrush.restore || this == RetouchBrush.markSubject;

  /// fills is whether the stroke is a boundary rather than a mark.
  bool get fills => this == RetouchBrush.cutAround;
}

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
/// _afterEntrance is how far into the timeline an element's entrance reaches.
///
/// The last frame the reveal channel touches, or nothing if it touches none.
/// A closing animation starts after it: overlapping the two bands has an
/// element arriving and leaving at once, which draws as a stutter and reads
/// as a bug.
int _afterEntrance(ElementTrack track) {
  var ends = 0;
  for (var key in track.keys) {
    if (key.values.containsKey(KeyframeChannel.reveal)) {
      ends = math.max(ends, key.frame);
    }
  }
  return ends;
}

/// _withClosingBand is [track] with one closing animation on it, running
/// [from] to [to] and replacing whatever closing keyframes it had.
///
/// Two callers lay this same pair -- the one that puts a closing preset on
/// an element and the one that puts it on a chart -- and they had a copy
/// each of the loop that clears the old keys and the two that write the new
/// ones.
/// _without is [track] with [channel] unpinned everywhere, and with any
/// keyframe that held nothing else dropped.
///
/// Taking the *keyframe* away instead threw out whatever else stood on that
/// frame: a chart moved by hand at frame 0 and then given an arrival had its
/// move deleted by choosing None, which is not what None means. It means no
/// arrival.
ElementTrack? _without(ElementTrack? track, String channel) {
  if (track == null) return null;
  var kept = <Keyframe>[
    for (var key in track.keys)
      if (key.values.containsKey(channel)) key.withoutValue(channel) else key,
  ]..removeWhere((key) => !key.posesElement && key.values.isEmpty);
  return kept.isEmpty ? null : ElementTrack(kept);
}

ElementTrack _withClosingBand(ElementTrack track, int from, int to) {
  for (var key in track.keys) {
    if (key.values.containsKey(KeyframeChannel.close)) {
      track = track.withoutFrame(key.frame);
    }
  }
  return _pinning(_pinning(track, from, KeyframeChannel.close, 0), to,
      KeyframeChannel.close, 1);
}

/// _pinning is [track] with [channel] pinned to [value] at [frame], keeping
/// whatever else that frame already holds.
///
/// A keyframe is a pose *and* whatever channels are pinned there, and laying
/// an animation down writes one key at each end of it. Written as a fresh
/// keyframe, those two ends flattened any pose that happened to be standing
/// on the same frame -- so animating an element that had been moved by hand
/// at the frame the playhead was on silently threw the move away.
ElementTrack _pinning(
        ElementTrack track, int frame, String channel, double value) =>
    track.withKey((track.keyAt(frame) ?? Keyframe(frame: frame))
        .withValue(channel, value));

/// FetchedRows is what one element's last refresh in this sitting returned.
///
/// Kept so the mapping controls can change their mind -- which column is the
/// axis, which one a series is drawn from -- without asking the source again.
class FetchedRows {
  /// fields is every path that led to a value in the first record.
  final List<String> fields;

  /// rows is the mapped table, and raw the same rows with the dates still in
  /// them, for a chart choosing its points by date.
  final List<List<String>> rows;
  final List<List<String>> raw;

  const FetchedRows(this.fields, this.rows, this.raw);
}

class CanvasController extends ChangeNotifier {
  CanvasController(CanvasDocument document,
      {AudioEngine? audioEngine, FrameSource? frameSource})
      : _document = document,
        _audioEngine = audioEngine,
        _frameSource = frameSource;

  CanvasDocument _document;
  CanvasDocument get document => _document;

  /// lastFetched is what each element's last refresh returned, by element id.
  ///
  /// Here rather than in the settings panel that runs the refresh, because
  /// two buttons run one -- the Data source section's and the one on the
  /// Table section, which is not inside that panel -- and a refresh from the
  /// second left the mapping controls with no rows in hand. Here rather than
  /// in a global, because a global outlives the document it describes: rows
  /// from a canvas that has been closed, filed under an element id another
  /// canvas may well use.
  ///
  /// Not in the document, deliberately: four thousand rows saved into every
  /// canvas so that a dropdown need not ask again is not a trade worth
  /// making. It is a fact about this sitting.
  final Map<String, FetchedRows> lastFetched = {};

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

  /// _fitScale is what the stage last reported: how much the canvas is
  /// shrunk to fill the window before any zoom is applied.
  ///
  /// The stage owns this -- it is the only thing that knows how much room
  /// there is -- and reports it so that the band can say what somebody is
  /// actually looking at. See [viewScale].
  double _fitScale = 1;

  /// viewScale is document pixels to screen pixels: what the percentage on
  /// the band means.
  ///
  /// Not [zoom], which is a multiple of the fitted size and is therefore 1
  /// whenever the whole canvas is showing -- whatever size that turned out to
  /// be. The band said 100% for a 4096-pixel canvas squeezed into a third of
  /// a window, which is a claim about the view that is plainly untrue.
  double get viewScale => _fitScale * _zoom;

  /// reportFitScale is the stage telling the controller how much room it
  /// found. Notifies only when the answer changes, since it is asked on every
  /// layout.
  void reportFitScale(double value) {
    if (!value.isFinite || value <= 0) return;
    if ((value - _fitScale).abs() < 0.0001) return;
    _fitScale = value;
    _notifyView();
  }

  /// setViewScale zooms so that one document pixel is [value] screen pixels,
  /// which is what typing a percentage into the band means.
  void setViewScale(double value) {
    if (!value.isFinite || value <= 0 || _fitScale <= 0) return;
    zoom = value / _fitScale;
  }

  /// atFit is whether the view is showing the whole canvas, untouched -- which
  /// is what the Fit button lights up for.
  bool get atFit => (_zoom - 1).abs() < 0.001 && _pan.dx == 0 && _pan.dy == 0;

  Offset2 _pan = const Offset2(0, 0);
  Offset2 get pan => _pan;

  /// revision counts every change that is about the *document* rather than
  /// about the view of it.
  ///
  /// What the sidebar watches. The controller notifies for everything --
  /// panning, zooming, hovering a button, every pixel of a drag -- and the
  /// settings panel is twenty or thirty text fields; laying those out for a
  /// change they do not show is most of what made clicking around feel slow.
  ///
  /// Safe by default, and that is the whole design: every notification moves
  /// this unless it is one of the handful that deliberately does not, so a
  /// field added later and forgotten costs a rebuild nobody needed rather
  /// than leaving a panel showing something that is no longer true.
  int get revision => _revision;
  int _revision = 0;

  /// _viewOnly is set only while [_notifyView] is running.
  bool _viewOnly = false;

  @override
  void notifyListeners() {
    // A drawing is edited only while it is there and is the one thing
    // selected. Whatever took that away -- an undo, a delete, a click on
    // the background, a selection pruned -- ends the editing, rather than
    // leaving its points drawn beside another element's settings.
    var editing = _vectorEditing;
    if (editing != null &&
        (_backgroundSelected ||
            _selection.length != 1 ||
            _selection.first != editing ||
            _document.elementById(editing) is! VectorElement)) {
      _vectorEditing = null;
      _resetVectorEditing();
    }
    if (!_viewOnly) _revision++;
    super.notifyListeners();
  }

  /// restoreFit puts back the frame the reader last chose, without telling
  /// anybody.
  ///
  /// Called from a State's initState, before this screen has built anything,
  /// which is exactly why it must not notify: the controller is handed round
  /// by a Provider, and notifying one during a build marks an inherited widget
  /// dirty while the framework is already building. Flutter catches that and
  /// throws -- and building the exception captures a stack four hundred frames
  /// deep, every time the page is opened, which is a visible stutter for a
  /// setting nobody has to be told about. Nothing has painted yet, so the
  /// first build reads the new value anyway.
  void restoreFit(CanvasFit value) {
    _fit = value;
    _zoom = 1;
    _pan = const Offset2(0, 0);
  }

  /// _notifyView tells everyone that the *view* moved -- the zoom, the pan,
  /// how the canvas is framed, which tool is in hand -- without claiming the
  /// document changed.
  void _notifyView() {
    _viewOnly = true;
    try {
      notifyListeners();
    } finally {
      _viewOnly = false;
    }
  }

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
    _notifyView();
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

  bool _showOverspill = false;

  /// showOverspill draws a margin of the world outside the canvas.
  ///
  /// Off by default, because what the canvas shows is what gets published and
  /// a permanent border of not-the-design around it is a border around every
  /// glance at the work.
  ///
  /// On, it is what makes an entrance possible to build. An element animated
  /// in from off the left starts outside the page, where it is clipped away
  /// entirely -- so its first keyframe cannot be seen, cannot be selected and
  /// cannot be dragged, and the only way to place it was to type coordinates
  /// and scrub until it appeared.
  bool get showOverspill => _showOverspill;

  set showOverspill(bool value) {
    if (_showOverspill == value) return;
    _showOverspill = value;
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
    _notifyView();
  }

  bool _showAllBounds = false;

  /// showAllBounds outlines every element on the canvas, not only the selected
  /// one.
  ///
  /// Editing furniture like the handles, and off by default: a canvas covered
  /// in outlines is a canvas nobody can see. What it is for is working on
  /// elements that have something to do with each other -- a chain of text
  /// boxes above all, where the box being flowed into is somewhere else on
  /// the page and invisible until it is clicked.
  ///
  /// One switch for the whole canvas rather than one per element, which is
  /// what this was: turning them on to line two boxes up meant turning them
  /// off again afterwards, one element at a time.
  bool get showAllBounds => _showAllBounds;

  set showAllBounds(bool value) {
    if (_showAllBounds == value) return;
    _showAllBounds = value;
    _notifyView();
  }

  bool _lockJoins = false;

  /// lockJoins keeps the connectors between text boxes from being changed by
  /// a drag.
  ///
  /// A connector is structural -- the words in several boxes depend on it --
  /// and it is dragged from a dot eight pixels across sitting on the same
  /// outline as the resize handles. Locked, the grips are still drawn, since
  /// they are how a chain is read; they simply do not answer the pointer.
  bool get lockJoins => _lockJoins;

  set lockJoins(bool value) {
    if (_lockJoins == value) return;
    _lockJoins = value;
    _notifyView();
  }

  bool _hideJoins = false;

  /// hideJoins leaves the lines between linked text boxes undrawn.
  ///
  /// The grips stay, and that is the point: the blue and the red dots still
  /// say there is a chain and whether the words all fit, while the lines stop
  /// crossing the design.
  bool get hideJoins => _hideJoins;

  set hideJoins(bool value) {
    if (_hideJoins == value) return;
    _hideJoins = value;
    _notifyView();
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

  RetouchBrush _retouch = RetouchBrush.off;

  /// retouch is whether the pointer is painting a picture's background in or
  /// out rather than moving things about.
  ///
  /// A mode rather than a modifier key, because retouching is a job somebody
  /// settles into for a minute at a time: a dozen strokes back and forth, each
  /// one wanting both hands free.
  RetouchBrush get retouch => _retouch;

  set retouch(RetouchBrush value) {
    if (_retouch == value) return;
    _retouch = value;
    notifyListeners();
  }

  /// _pendingStroke is a stroke that has been drawn but not yet applied, and
  /// _pendingPicture is the picture it was drawn on.
  ///
  /// A stroke used to land the moment the pointer came up, taking the brush's
  /// settings with it -- so changing hardness or cling afterwards did nothing
  /// at all to the stroke that had just been made, and the only way to try a
  /// setting was to undo, change it, and draw again. Held here instead, the
  /// same stroke is redrawn against whatever the settings currently say and
  /// applied when the reader is satisfied.
  List<Offset>? _pendingStroke;
  String? _pendingPicture;

  /// pendingKeeps and pendingTeaches are what the brush was doing when the
  /// stroke was drawn -- which of the four brushes it came from. Kept with the
  /// stroke rather than read live, because changing brush is choosing to do
  /// something else rather than to adjust this.
  bool _pendingKeeps = false;
  bool _pendingTeaches = false;
  bool _pendingFills = false;

  List<Offset>? get pendingStroke => _pendingStroke;
  String? get pendingPicture => _pendingPicture;
  bool get pendingKeeps => _pendingKeeps;
  bool get pendingTeaches => _pendingTeaches;
  bool get pendingFills => _pendingFills;
  bool get hasPendingStroke =>
      _pendingStroke != null && _pendingStroke!.isNotEmpty;

  /// holdStroke keeps a freshly drawn stroke back for adjustment.
  void holdStroke(String pictureId, List<Offset> points,
      {required bool keeps, required bool teaches, bool fills = false}) {
    if (points.isEmpty) return;
    _pendingPicture = pictureId;
    _pendingStroke = List.unmodifiable(points);
    _pendingKeeps = keeps;
    _pendingTeaches = teaches;
    _pendingFills = fills;
    notifyListeners();
  }

  /// discardStroke throws the held stroke away.
  void discardStroke() {
    if (_pendingStroke == null) return;
    _pendingStroke = null;
    _pendingPicture = null;
    notifyListeners();
  }

  /// applyStroke writes the held stroke onto its picture, with the brush's
  /// settings as they stand now.
  void applyStroke() {
    var id = _pendingPicture;
    var points = _pendingStroke;
    if (id == null || points == null || points.isEmpty) return;

    var picture = _document.elementById(id);
    if (picture is! ImageElement) {
      discardStroke();
      return;
    }

    var stroke = RemovalStroke(
      points: points,
      radius: _brushSize,
      keep: _pendingKeeps,
      // A hint is a sample rather than a mark on the picture, so it is taken
      // exactly where it was drawn: softening or snapping it would collect
      // colours the reader did not point at.
      hardness: _pendingTeaches ? 1 : _brushHardness,
      snap: _clingFor(_pendingTeaches, _pendingKeeps),
      fill: _pendingFills,
      fillInside: _pendingFills && _cutInside,
    );

    replaceElement(picture.copyWith(
        removal: _pendingTeaches
            ? picture.removal
                .copyWith(hints: [...picture.removal.hints, stroke])
            : picture.removal
                .copyWith(strokes: [...picture.removal.strokes, stroke])));
    discardStroke();
  }

  /// magnetiseCling finds the edge the held stroke crossed, and sets the cling
  /// to it.
  ///
  /// The number cling wants is "how different from the background does a pixel
  /// have to be before it is not the background", and that is not something
  /// anybody can read off a photograph -- so setting it by hand was always
  /// guessing, which is why it never worked. The picture knows it: the stroke
  /// crossed from one thing to another, and the two show up as two clusters of
  /// colour distance with a gap between them. See suggestSnap.
  ///
  /// Returns false when there is no edge to find -- a stroke drawn entirely on
  /// the background has one cluster, and inventing a split in it would cut the
  /// background in half for no reason.
  Future<bool> magnetiseCling() async {
    var stroke = pendingAsStroke();
    var id = _pendingPicture;
    if (stroke == null || id == null) return false;

    var picture = _document.elementById(id);
    if (picture is! ImageElement) return false;
    var source = images.original(picture.assetId);
    if (source == null) return false;

    var found = await snapForStroke(source, stroke);
    if (found == null) return false;
    brushSnap = found;
    return true;
  }

  /// pendingAsStroke is the held stroke as it would be applied right now,
  /// which is what the preview on the canvas is drawn from.
  RemovalStroke? pendingAsStroke() {
    var points = _pendingStroke;
    if (points == null || points.isEmpty) return null;
    return RemovalStroke(
      points: points,
      radius: _brushSize,
      keep: _pendingKeeps,
      hardness: _pendingTeaches ? 1 : _brushHardness,
      snap: _clingFor(_pendingTeaches, _pendingKeeps),
      fill: _pendingFills,
      fillInside: _pendingFills && _cutInside,
    );
  }

  /// _clingFor is how much a stroke should cling, which is not always what the
  /// setting says.
  ///
  /// Never for a hint, which is a sample rather than a mark on the picture and
  /// has to be taken exactly where it was drawn.
  ///
  /// And never for putting something back. Clinging means "spread only through
  /// pixels like the one I started on", which is how you find the edge of a
  /// background -- but what is being put back is the subject, and a subject is
  /// every colour there is. With it on, a stroke over a face brought back the
  /// few pixels nearest whatever was under the pointer and left the rest, so
  /// the brush appeared to do nothing at all.
  double _clingFor(bool teaches, bool keeps) =>
      teaches || keeps ? 0 : _brushSnap;

  double _brushHardness = 0.35;

  /// brushHardness is how abruptly a stroke stops at its own edge. See
  /// RemovalStroke.hardness.
  double get brushHardness => _brushHardness;

  set brushHardness(double value) {
    var next = value.clamp(0.05, 1.0);
    if (next == _brushHardness) return;
    _brushHardness = next;
    notifyListeners();
  }

  /// _brushSnap starts at nothing.
  ///
  /// A plain brush does what it is told, which is the behaviour to have by
  /// default; clinging is an aid for following an edge quickly and is worth
  /// reaching for deliberately. On by default it made the brush look broken,
  /// because a stroke that refused most of what it covered is indistinguishable
  /// from one that did not work.
  bool _cutInside = false;

  /// cutInside takes what a boundary encloses rather than what surrounds it.
  ///
  /// Read when the stroke is applied rather than when it is drawn, so it can
  /// be turned over while the stroke is held and the preview redraws -- which
  /// is the point of holding one.
  bool get cutInside => _cutInside;

  set cutInside(bool value) {
    if (_cutInside == value) return;
    _cutInside = value;
    notifyListeners();
  }

  double _brushSnap = 0;

  /// brushSnap makes a stroke cling to what is already in the picture. See
  /// RemovalStroke.snap.
  double get brushSnap => _brushSnap;

  set brushSnap(double value) {
    var next = value.clamp(0.0, 0.6);
    if (next == _brushSnap) return;
    _brushSnap = next;
    notifyListeners();
  }

  double _brushSize = 0.05;

  /// brushSize is the brush's radius as a fraction of the picture's shorter
  /// side, which is how a stroke is stored -- so the brush stays the same size
  /// relative to the picture however far the canvas is zoomed.
  double get brushSize => _brushSize;

  set brushSize(double value) {
    var next = value.clamp(0.005, 0.6);
    if (next == _brushSize) return;
    _brushSize = next;
    notifyListeners();
  }

  CanvasTool _tool = CanvasTool.select;

  /// tool is what dragging on the canvas does. Select to begin with, because
  /// that is what somebody who has just added an element wants to do to it.
  CanvasTool get tool => _tool;

  set tool(CanvasTool value) {
    if (_tool == value) return;
    _tool = value;
    _notifyView();
  }

  /// hoveredButton is the button under the pointer, which the renderer needs
  /// so hover colours can be seen while they are being chosen.
  String? hoveredButton;

  Timer? _playback;
  bool get playing => _playback != null;

  /// _loopCounts tracks how many times each loop marker has fired, so a marker
  /// with a repeat limit stops rather than running forever.
  final Map<int, int> _loopCounts = {};

  bool _opened = false;

  /// opened is whether this session has ever been shown.
  ///
  /// The session outlives the page now, so the page needs to tell its first
  /// visit from its second: on the first it restores whatever was last saved,
  /// and on every one after that the controller already holds the work in
  /// progress and restoring would throw it away.
  bool get opened => _opened;

  /// markOpened is called by the page as it builds.
  void markOpened() => _opened = true;

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
  List<CanvasElement> get selectedElements => [
        for (var e in _document.elements)
          if (_selection.contains(e.id)) e
      ];

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
    scheduleAutosave();

    // A selection can outlive the elements it names -- deleting, or loading a
    // different document -- and every reader of the selection would then have
    // to cope with an id that resolves to nothing. Pruning here means none of
    // them do.
    _selection = _selection.where((id) => _document.indexOf(id) >= 0).toSet();

    if (_frame >= _document.frames) _frame = _document.frames - 1;

    // A sound whose element has gone goes with it, and one on the timeline
    // goes where its new settings put it.
    _audioFollowsPage(turned: false);
    _syncTimeline();

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
    // While a drawing is being edited, Delete takes out the points picked,
    // or the shape picked -- and with neither, nothing: never the drawing.
    if (editingVector != null) {
      deleteVectorPoint();
      return;
    }
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

  /// _clipboard is what was last copied.
  ///
  /// Held on the controller rather than in the system clipboard, and only for
  /// as long as the app runs. A canvas element is a tree of colours, specs and
  /// keyframes with no sensible text form, and putting JSON on the system
  /// clipboard would mean every Cmd-C in the editor quietly replacing whatever
  /// the reader had copied from somewhere else.
  ///
  /// Static, so a copy survives the page being left and come back to -- which
  /// is the same reason the session itself outlives the screen.
  static List<CanvasElement> _clipboard = const [];

  /// _pasteOffset is how far each paste is stepped down and right.
  ///
  /// Offset rather than placed exactly on top: an element pasted onto its
  /// original is indistinguishable from nothing having happened, and the
  /// second paste of the same thing has to be visibly a third copy.
  static const double _pasteOffset = 16;

  bool get canPaste => _clipboard.isNotEmpty;

  /// copySelected puts the selection on the clipboard.
  void copySelected() {
    var chosen = selectedElements;
    if (chosen.isEmpty) return;
    _clipboard = List.unmodifiable(chosen);
    notifyListeners();
  }

  /// cutSelected copies and then deletes.
  void cutSelected() {
    if (_selection.isEmpty) return;
    copySelected();
    deleteSelected();
  }

  /// paste drops the clipboard onto the canvas and selects what it added.
  ///
  /// New ids, always. Pasting keeps the elements' order relative to each
  /// other and puts the whole lot on top, which is what pasting anywhere else
  /// does and what makes a pasted group findable.
  void paste() {
    if (_clipboard.isEmpty) return;
    var next = _document;
    var made = <String>{};
    for (var element in _clipboard) {
      CanvasElement copy;
      if (element is AudioElement && element.clip.timed) {
        // A sound on the timeline goes where the playhead is, on the channel
        // it was copied from -- which is how one channel comes to hold two.
        copy = element
            .copyWith(clip: element.clip.copyWith(at: _frame))
            .withId(newElementId());
      } else if (element is VideoElement && element.clip.timed) {
        // And a video on the timeline the same: at the playhead, in the same
        // place on the canvas -- the same shot, later.
        copy = element
            .copyWith(clip: element.clip.copyWith(at: _frame))
            .withId(newElementId());
      } else {
        copy = element
            .withId(newElementId())
            .withBase(x: element.x + _pasteOffset, y: element.y + _pasteOffset);
      }
      made.add(copy.id);
      next = next.addElement(copy);
    }
    apply(next);
    _backgroundSelected = false;
    _focusedPlayer = null;
    _selection = made;
    notifyListeners();
  }

  /// duplicateElement is the layer list's button: copy and paste in one press.
  ///
  /// The row's control was a copy, which did nothing anybody could see -- the
  /// canvas was unchanged and the only evidence was that a paste somewhere
  /// else would now produce this. What the button is actually reached for is a
  /// second one of these, so it makes one.
  ///
  /// The clipboard is deliberately left alone. Duplicating a layer is not a
  /// reason to lose whatever was copied to paste onto another canvas.
  void duplicateElement(String id) {
    var element = _document.elementById(id);
    if (element == null) return;
    var copy = element
        .withId(newElementId())
        .withBase(x: element.x + _pasteOffset, y: element.y + _pasteOffset);
    apply(_document.addElement(copy));
    _backgroundSelected = false;
    _focusedPlayer = null;
    _selection = {copy.id};
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

  /// alignSelected lines every chosen element up on one edge or middle.
  ///
  /// Against the whole selection's own box rather than against the canvas: two
  /// things picked out and aligned left means "put these two at the same
  /// left", and which left is the leftmost of the two. Aligning to the canvas
  /// is what the guides and the snapping are for, and doing both from one
  /// button would make the result depend on how many things were chosen.
  ///
  /// One element chosen is a no-op rather than a jump to the canvas edge --
  /// its own box is itself, so it is already aligned with it. The buttons say
  /// so by being dead until there are two.
  void alignSelected(CanvasAlign align, {bool transient = false}) {
    var chosen = [
      for (var e in selectedElements)
        if (!e.locked) e
    ];
    if (chosen.length < 2) return;

    Rect? box;
    for (var element in chosen) {
      box = box == null ? element.bounds : box.expandToInclude(element.bounds);
    }
    if (box == null) return;

    var next = _document;
    for (var element in chosen) {
      var at = element.bounds;
      var dx = switch (align) {
        CanvasAlign.left => box.left - at.left,
        CanvasAlign.centreX => box.center.dx - at.center.dx,
        CanvasAlign.right => box.right - at.right,
        _ => 0.0,
      };
      var dy = switch (align) {
        CanvasAlign.top => box.top - at.top,
        CanvasAlign.middleY => box.center.dy - at.center.dy,
        CanvasAlign.bottom => box.bottom - at.bottom,
        _ => 0.0,
      };
      if (dx == 0 && dy == 0) continue;
      next = next.withElement(_moved(element, dx, dy));
    }
    apply(next, transient: transient);
  }

  /// spreadSelected puts an even gap between the chosen elements.
  ///
  /// The two on the ends stay where they are and everything between them is
  /// moved, which is what makes this "spread these out" rather than "move
  /// everything". Needs three: with two there is nothing between them to
  /// space.
  ///
  /// Even *gaps* rather than even centres. Elements of different sizes spaced
  /// by their centres leave visibly different amounts of white between them,
  /// which is the thing anybody doing this is actually looking at.
  void spreadSelected(bool across, {bool transient = false}) {
    var chosen = [
      for (var e in selectedElements)
        if (!e.locked) e
    ];
    if (chosen.length < 3) return;
    chosen.sort((a, b) => across
        ? a.bounds.left.compareTo(b.bounds.left)
        : a.bounds.top.compareTo(b.bounds.top));

    var first = chosen.first.bounds;
    var last = chosen.last.bounds;
    var span = across ? last.right - first.left : last.bottom - first.top;
    var filled = chosen.fold<double>(
        0, (sum, e) => sum + (across ? e.bounds.width : e.bounds.height));
    var gap = (span - filled) / (chosen.length - 1);

    var next = _document;
    var at = across ? first.left : first.top;
    for (var element in chosen) {
      var bounds = element.bounds;
      var shift = at - (across ? bounds.left : bounds.top);
      if (shift != 0) {
        next = next.withElement(
            _moved(element, across ? shift : 0, across ? 0 : shift));
      }
      at += (across ? bounds.width : bounds.height) + gap;
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
  /// on, or the element has already been *posed* -- something that has been
  /// animated in space is being posed, not repositioned. To relocate an
  /// animated element wholesale, the X and Y fields in its settings still move
  /// the resting position, and the whole animation travels with it.
  ///
  /// Posed, rather than merely having keyframes. The two are not the same and
  /// the difference was a reported bug: applying one of the chart animation
  /// presets lays two keyframes that say nothing but how much of the chart has
  /// been drawn, and after that every drag of the chart wrote a move keyframe
  /// at the playhead -- with auto-keyframe switched off, which is precisely
  /// the setting that is supposed to mean "do not do that". A chart told how
  /// to arrive has not been animated in space, so dragging it moves it.
  bool posesRatherThanMoves(CanvasElement element) =>
      _document.isAnimated &&
      // Never for something a path is driving. Its poses belong to the route,
      // and one written by a drag would be overwritten the next time a point
      // moved -- so a drag moves where it starts from instead, and the whole
      // run travels with it.
      pathDriving(element.id) == null &&
      (_autoKeyframe || (element.track?.posesAnything == true));

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

  /// pathDriving is the path that owns [elementId]'s keyframes, if one does.
  ///
  /// A followed element's track is not its own: it is written by the path and
  /// rewritten whenever the route or its timing changes, so anything the
  /// reader put there by hand would vanish the next time a point moved. Rather
  /// than let them make edits that quietly disappear, the timeline refuses --
  /// it shows the path's points instead, and says where to go.
  PathElement? pathDriving(String elementId, {int? playerIndex}) {
    for (var element in _document.elements) {
      if (element is! PathElement) continue;
      var follow = element.follow;
      if (follow == null || follow.elementId != elementId) continue;
      if (follow.playerIndex != playerIndex) continue;
      return element;
    }
    return null;
  }

  /// applyPathFollow writes [path]'s route into its follower's keyframes.
  ///
  /// Baked rather than evaluated live, and that is the design. The renderer,
  /// the GIF encoder and a published interactive canvas all already know how
  /// to play a track; none of them needs to learn what a bezier is, and a
  /// document exported on one machine cannot disagree with the same document
  /// replayed on another. The cost is that the follower's own keyframes are
  /// owned by the path and rewritten whenever it changes, which is why the
  /// settings say so.
  ///
  /// One keyframe per frame between the first node and the last, sampled along
  /// the curve by arc length -- see PathElement.positionOnSegment on why by
  /// length rather than by the curve's parameter. Straight lines between the
  /// nodes would be cheaper and would not be a curve.
  void applyPathFollow(PathElement path) {
    var follow = path.follow;
    if (follow == null || path.nodes.length < 2) return;

    var target = _document.elementById(follow.elementId);
    if (target == null) return;

    var from = path.firstFrame;
    var to = path.lastFrame;
    if (to <= from) return;

    var index = follow.playerIndex;
    if (target is TeamElement && index != null) {
      if (index < 0 || index >= target.players.length) return;
      var spot = target.players[index];
      var rest = target.centreOf(spot);
      replaceElement(target.withPlayer(
          index, spot.copyWith(track: _bake(path, rest, from, to))));
      return;
    }

    // An element is placed by its top-left, so the route -- which describes
    // where the thing *is* -- is measured from its centre and the offset
    // shifted back. Without that a player following a curve runs with the
    // curve passing through his shoulder.
    replaceElement(
        target.withBase(track: _bake(path, target.center, from, to)));
  }

  /// _bake turns a path into a track of poses relative to [rest].
  ElementTrack _bake(PathElement path, Offset rest, int from, int to) {
    var keys = <Keyframe>[];
    for (var f = from; f <= to; f++) {
      var at = path.positionAtFrame(f);
      if (at == null) continue;
      keys.add(Keyframe(frame: f, dx: at.dx - rest.dx, dy: at.dy - rest.dy));
    }
    return ElementTrack(keys);
  }

  /// clearPathFollow takes the baked keyframes back off, which is what
  /// unlinking a follower has to do -- leaving them would strand the element
  /// on a route it is no longer attached to.
  void clearPathFollow(PathElement path) {
    var follow = path.follow;
    if (follow == null) return;
    var target = _document.elementById(follow.elementId);
    if (target == null) return;

    var index = follow.playerIndex;
    if (target is TeamElement && index != null) {
      if (index < 0 || index >= target.players.length) return;
      replaceElement(target.withPlayer(
          index, target.players[index].copyWith(clearTrack: true)));
      return;
    }
    replaceElement(target.withBase(clearTrack: true));
  }

  /// followerLabel names what a path is attached to, for the settings.
  String followerLabel(PathFollow? follow) {
    if (follow == null) return "Nothing";
    var target = _document.elementById(follow.elementId);
    if (target == null) return "Missing";
    var index = follow.playerIndex;
    if (target is TeamElement &&
        index != null &&
        index < target.players.length) {
      var spot = target.players[index];
      var who = spot.name.isNotEmpty ? spot.name : "#${spot.number}";
      return "$who (${target.name})";
    }
    return target.name;
  }

  /// setPlayerKeyframe writes one player's pose at the current frame.
  void setPlayerKeyframe(String teamId, int index, Keyframe key) {
    var team = _document.elementById(teamId);
    if (team is! TeamElement || index < 0 || index >= team.players.length) {
      return;
    }
    var spot = team.players[index];
    replaceElement(team.withPlayer(index,
        spot.copyWith(track: (spot.track ?? ElementTrack.empty).withKey(key))));
  }

  /// valueAt reads an animatable extra channel at the current frame, falling
  /// back to [orElse] when nothing has been keyed. See KeyframeChannel.
  double valueAt(CanvasElement element, String channel, double orElse) =>
      element.poseAt(_frame).values[channel] ?? orElse;

  /// hasValueKey is whether [channel] is pinned on this exact frame, which is
  /// what its little diamond shows.
  bool hasValueKey(CanvasElement element, String channel) =>
      element.track?.keyAt(_frame)?.values.containsKey(channel) ?? false;

  /// setValueKey pins one extra property at the current frame.
  ///
  /// Seeded at the start like every other first keyframe, so one press makes a
  /// movement rather than a value that holds for the whole document -- see
  /// ElementTrack.seededFor.
  ///
  /// [seed] is what turns that off, and a counter turns it off. The seed is a
  /// *resting pose* laid at frame 0, and a resting pose laid deliberately is
  /// the clearest way of saying "this element is animated in space" -- see
  /// ElementTrack.posesAnything. That is true of a chart told how much of
  /// itself to draw, and false of a number told what to say: pinning a count
  /// lit the position-size-angle-fade diamond and made every later drag write
  /// a pose, neither of which anybody had asked for. A count needs no seed
  /// anyway, because the first key already holds for every frame before it.
  void setValueKey(CanvasElement element, String channel, double value,
      {bool seed = true}) {
    var track = seed
        ? (element.track ?? ElementTrack.empty).seededFor(_frame)
        : (element.track ?? ElementTrack.empty);
    var at = track.at(_frame);
    replaceElement(element.withBase(
        track: track
            .withKey(at.copyWith(frame: _frame).withValue(channel, value))));
  }

  /// clearValueKey takes one property off this frame's keyframe, and the
  /// keyframe with it when that was all it held.
  void clearValueKey(CanvasElement element, String channel) {
    var track = element.track;
    var at = track?.keyAt(_frame);
    if (track == null || at == null) return;
    var without = at.withoutValue(channel);
    var next = without.isRest && without.frame != 0
        ? track.withoutFrame(_frame)
        : track.withKey(without);
    // And with it whatever it was half of: an arrival is a pair, and one of
    // them on its own is not half an arrival. See withoutHalfAnimations.
    replaceElement(withoutHalfAnimations(element, next));
  }

  /// clearElementKeyframes takes every keyframe off one element.
  void clearElementKeyframes(String id) {
    var element = _document.elementById(id);
    if (element == null || element.track == null) return;
    replaceElement(element.withBase(clearTrack: true));
  }

  /// clearPlayerKeyframes takes every keyframe off one player.
  void clearPlayerKeyframes(String teamId, int index) {
    var team = _document.elementById(teamId);
    if (team is! TeamElement || index < 0 || index >= team.players.length) {
      return;
    }
    if (team.players[index].track == null) return;
    replaceElement(
        team.withPlayer(index, team.players[index].copyWith(clearTrack: true)));
  }

  /// clearAllKeyframes takes the animation off the whole document.
  ///
  /// One undo step, deliberately: it is a single decision, and unpicking it
  /// element by element is not something anybody would want to do twenty-two
  /// times. See CanvasDocument.withoutKeyframes on what it leaves behind.
  void clearAllKeyframes() {
    if (!_document.hasKeyframes) return;
    apply(_document.withoutKeyframes());
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

  // ---- vector editing ----------------------------------------------------

  /// vectorEditing is the Vector element being edited point by point, by id,
  /// or null. vectorShape is the shape of it picked, and vectorPicks the
  /// points -- one, several, or none.
  String? get vectorEditing => _vectorEditing;
  String? _vectorEditing;
  int get vectorShape => _vectorShape;
  int _vectorShape = -1;
  Set<VectorPick> get vectorPicks => _vectorPicks;
  Set<VectorPick> _vectorPicks = const {};

  /// vectorPick is the one point picked, where exactly one is: the point
  /// whose handles are shown and can be pulled.
  VectorPick? get vectorPick =>
      _vectorPicks.length == 1 ? _vectorPicks.first : null;

  /// vectorTool is what a press on the drawing being edited does: pick and
  /// move points, put them down with the pen, scale them, or tint them.
  VectorTool get vectorTool => _vectorTool;
  VectorTool _vectorTool = VectorTool.select;

  set vectorTool(VectorTool tool) {
    if (_vectorTool == tool) return;
    if (tool != VectorTool.text) stopVectorTyping();
    _vectorTool = tool;
    // The pen taken out with one point picked carries on from that point.
    _vectorPenFrom = tool == VectorTool.pen && _vectorPicks.length == 1
        ? _vectorPicks.first
        : null;
    // The corner tool taken out with a rounded corner's point picked takes
    // that corner up, to be reshaped.
    if (tool == VectorTool.corner && _vectorPicks.length <= 2) {
      if (_vectorPicks.firstOrNull case var p?) {
        if (editingVector case var e? when cornerAt(e, p) != null) {
          _vectorTool = tool;
          adoptCorner(p);
          return;
        }
      }
    }
    // The Boolean tool taken out with a shape picked starts from that one.
    var e = editingVector;
    _vectorCombining = tool == VectorTool.boolean &&
            e != null &&
            _vectorShape >= 0 &&
            _vectorShape < (e.shapes?.length ?? 0)
        ? {groupOf(e, _vectorShape)}
        : const {};
    notifyListeners();
  }

  /// vectorPen is whether the pen is out. See vectorTool.
  bool get vectorPen => _vectorTool == VectorTool.pen;
  set vectorPen(bool on) =>
      vectorTool = on ? VectorTool.pen : VectorTool.select;

  /// vectorPenFrom is the point the pen's next point joins on from, or null
  /// before it has one -- when the next point starts a new shape.
  VectorPick? get vectorPenFrom => _vectorPenFrom;
  VectorPick? _vectorPenFrom;

  /// vectorPenShape is the shape the pen is drawing, or -1.
  int get vectorPenShape => _vectorPenFrom?.shape ?? -1;

  /// penFrom says where the pen's next point joins on from: the point just
  /// put down, or a point picked to carry on from.
  void penFrom(VectorPick? pick) {
    _vectorPenFrom = pick;
    if (pick != null) _vectorShape = pick.shape;
    notifyListeners();
  }

  /// finishPenShape ends the run the pen is drawing; the pen stays out,
  /// ready to start another.
  void finishPenShape() {
    if (_vectorPenFrom == null) return;
    _vectorPenFrom = null;
    _vectorPicks = const {};
    notifyListeners();
  }

  /// vectorCornerRound is whether the corner tool rounds a corner or cuts
  /// it, and vectorCornerSize how far back along each side it starts, in
  /// canvas units.
  ///
  /// Both reshape the corner the tool last made while it is still picked --
  /// see vectorCornerActive.
  bool get vectorCornerRound => _vectorCornerRound;
  bool _vectorCornerRound = true;
  set vectorCornerRound(bool on) {
    if (_vectorCornerRound == on) return;
    _vectorCornerRound = on;
    if (!reshapeCorner()) notifyListeners();
  }

  double get vectorCornerSize => _vectorCornerSize;
  double _vectorCornerSize = 20;
  set vectorCornerSize(double v) => sizeCorner(v);

  /// sizeCorner sets the corner size and reshapes the corner being made by
  /// it -- [transient] while a drag is still setting it.
  void sizeCorner(double v, {bool transient = false}) {
    if (_vectorCornerSize == v) return;
    _vectorCornerSize = v;
    if (!reshapeCorner(transient: transient)) notifyListeners();
  }

  /// _corner is the corner the corner tool last made: the drawing before
  /// it, the point it was made at, and the drawing and the two points it
  /// made. Still being made for as long as those two points are what is
  /// picked and nothing else has changed the drawing.
  ({
    VectorElement before,
    VectorPick at,
    VectorElement after,
    Set<VectorPick> picks
  })? _corner;

  /// vectorCornerActive is whether the corner the tool last made is still
  /// being made: its size and kind reshape it, and a drag on it goes on
  /// shaping it. Picking anything else finishes it.
  bool get vectorCornerActive {
    var c = _corner;
    return c != null &&
        identical(editingVector, c.after) &&
        c.picks.length == _vectorPicks.length &&
        c.picks.containsAll(_vectorPicks);
  }

  /// vectorCornerPoint is where the corner being made was, in the drawing's
  /// units, or null with none.
  Offset? get vectorCornerPoint {
    if (!vectorCornerActive) return null;
    var c = _corner!;
    return vectorNodeAt(c.before, c.at)?.point;
  }

  /// adoptCorner takes up the rounded corner the point at [pick] is one end
  /// of -- one made before, or a rounded box's -- as the corner being made,
  /// so its size and a drag reshape it: the size set to its own. Answers
  /// whether the point was one.
  bool adoptCorner(VectorPick pick) {
    var e = editingVector;
    if (e == null) return false;
    var found = cornerAt(e, pick);
    if (found == null) return false;
    var (before, at, reach, picks) = found;
    _corner = (before: before, at: at, after: e, picks: picks);
    _vectorPicks = picks;
    _vectorShape = pick.shape;
    _vectorCornerRound = true;
    _vectorCornerSize = (reach / VectorSpace(e).unitsPer).roundToDouble();
    notifyListeners();
    return true;
  }

  /// roundCorner rounds -- or cuts -- the corner at [at] as the corner
  /// settings say, picking the two points it makes and keeping it open to
  /// reshaping. Answers whether there was a corner there to round.
  bool roundCorner(VectorPick at, {bool transient = false}) {
    var e = editingVector;
    if (e == null) return false;
    return _shapeCorner(e, at, transient: transient);
  }

  /// reshapeCorner makes the corner being made again from the drawing as it
  /// was before it, at the size and kind now set. Answers whether there was
  /// one being made.
  bool reshapeCorner({bool transient = false}) {
    if (!vectorCornerActive) return false;
    var c = _corner!;
    return _shapeCorner(c.before, c.at, transient: transient);
  }

  bool _shapeCorner(VectorElement before, VectorPick at,
      {bool transient = false}) {
    var done = withCornered(
        before, at, _vectorCornerSize * VectorSpace(before).unitsPer,
        round: _vectorCornerRound);
    if (done == null) return false;
    var (after, picks) = done;
    _corner = (before: before, at: at, after: after, picks: picks);
    _vectorPicks = picks;
    _vectorShape = at.shape;
    replaceElement(after, transient: transient);
    return true;
  }

  /// vectorHandleDrag is what dragging a handle may change, and
  /// vectorHandleSnap whether it turns in fifteen-degree steps.
  VectorHandleDrag get vectorHandleDrag => _vectorHandleDrag;
  VectorHandleDrag _vectorHandleDrag = VectorHandleDrag.any;
  set vectorHandleDrag(VectorHandleDrag d) {
    if (_vectorHandleDrag == d) return;
    _vectorHandleDrag = d;
    notifyListeners();
  }

  bool get vectorHandleSnap => _vectorHandleSnap;
  bool _vectorHandleSnap = false;
  set vectorHandleSnap(bool on) {
    if (_vectorHandleSnap == on) return;
    _vectorHandleSnap = on;
    notifyListeners();
  }

  /// _copiedShapes is what the last copy of points copied, and _pastes how
  /// many times it has been pasted since -- each paste a step further off,
  /// so pastes do not land on top of one another.
  List<VectorShape> _copiedShapes = const [];
  int _pastes = 0;

  /// copyVectorPoints copies the points picked -- see copiedShapes --
  /// answering whether there was anything to copy.
  bool copyVectorPoints() {
    var e = editingVector;
    if (e == null || _vectorPicks.isEmpty) return false;
    var copied = copiedShapes(e, _vectorPicks);
    if (copied.isEmpty) return false;
    _copiedShapes = copied;
    _pastes = 0;
    return true;
  }

  /// cutVectorPoints copies the points picked and takes them out.
  bool cutVectorPoints() {
    if (!copyVectorPoints()) return false;
    deleteVectorPoint();
    _pastes = -1;
    return true;
  }

  /// pasteVectorPoints puts the points copied into the drawing being
  /// edited, a little down and to the right of where they were, and picks
  /// them -- answering whether there was anything to paste.
  bool pasteVectorPoints() {
    var e = editingVector;
    if (e == null || _copiedShapes.isEmpty) return false;
    _pastes++;
    var step = 10 * VectorSpace(e).unitsPer * _pastes;
    var (next, picks) = withPasted(e, _copiedShapes, Offset(step, step));
    _vectorPicks = picks;
    _vectorShape = picks.isEmpty ? -1 : picks.first.shape;
    replaceElement(next);
    return true;
  }

  /// pickAllVectorPoints picks every point of the drawing being edited.
  bool pickAllVectorPoints() {
    var e = editingVector;
    if (e == null) return false;
    pickVectorPoints(allPicks(e));
    return true;
  }

  /// editPickedPoints replaces the drawing being edited with what [edit]
  /// makes of it and the points picked, as one undo step.
  void editPickedPoints(
      VectorElement Function(VectorElement, Set<VectorPick>) edit) {
    var e = editingVector;
    if (e == null || _vectorPicks.isEmpty) return;
    var next = edit(e, _vectorPicks);
    if (!identical(next, e)) replaceElement(next);
  }

  /// vectorBrush is the pencil's brush as it is now -- one picked, then
  /// changed or not -- and vectorPencilColour the colour it draws in.
  VectorBrush get vectorBrush => _vectorBrush;
  VectorBrush _vectorBrush = builtInBrushes.first;
  set vectorBrush(VectorBrush b) {
    _vectorBrush = b;
    notifyListeners();
  }

  /// vectorPencilPoints is whether the drawing's points are shown while the
  /// pencil is out. Off to start with: drawing, they are in the way.
  bool get vectorPencilPoints => _vectorPencilPoints;
  bool _vectorPencilPoints = false;
  set vectorPencilPoints(bool on) {
    if (_vectorPencilPoints == on) return;
    _vectorPencilPoints = on;
    notifyListeners();
  }

  /// vectorLanes is how much of a drawing's shapes the timeline shows
  /// under the drawing's own keyframes: none of them, the shape picked, or
  /// every one. See VectorShapeLanes.
  VectorLanes get vectorLanes => _vectorLanes;
  VectorLanes _vectorLanes = VectorLanes.none;
  set vectorLanes(VectorLanes l) {
    if (_vectorLanes == l) return;
    _vectorLanes = l;
    notifyListeners();
  }

  /// retimeShapes changes when [e]'s shapes come in by [edit]: the shapes'
  /// timing first written out in the timeline's frames, as it plays now --
  /// see withTimingBaked -- so the change is in frames that can be seen; and
  /// the drawing's arrival then fitted round all of them again, the timeline
  /// lengthened where it has to be to hold it. [transient] while a drag is
  /// still making it.
  void retimeShapes(VectorElement e, VectorElement Function(VectorElement) edit,
      {bool transient = false}) {
    var next = withSpanFitted(edit(withTimingBaked(e)));
    var document = _document;
    if (vectorArrivalSpan(next) case (var at, var span)
        when at + span > document.frames - 1) {
      document = document.copyWith(frames: at + span + 1);
    }
    apply(document.withElement(next), transient: transient);
  }

  /// vectorShapeMade is the shape the shapes tool last drew, while it is
  /// still the one picked: the one its box moves and resizes. -1 with none.
  int get vectorShapeMade =>
      _vectorShapeMade >= 0 && _vectorShapeMade == _vectorShape
          ? _vectorShapeMade
          : -1;
  int _vectorShapeMade = -1;
  set vectorShapeMade(int i) => _vectorShapeMade = i;

  /// vectorShapeKind is the shape the shapes tool draws; vectorShapeSides a
  /// polygon's sides and a star's points; vectorStarInner how far in a
  /// star's inner points sit, as a share of its outer ones; and
  /// vectorShapeCorner a rounded box's corners, as a share of its shorter
  /// side.
  VectorShapeKind get vectorShapeKind => _vectorShapeKind;
  VectorShapeKind _vectorShapeKind = VectorShapeKind.box;
  set vectorShapeKind(VectorShapeKind k) {
    if (_vectorShapeKind == k) return;
    _vectorShapeKind = k;
    notifyListeners();
  }

  int get vectorShapeSides => _vectorShapeSides;
  int _vectorShapeSides = 5;
  set vectorShapeSides(int n) {
    if (_vectorShapeSides == n) return;
    _vectorShapeSides = n;
    notifyListeners();
  }

  double get vectorStarInner => _vectorStarInner;
  double _vectorStarInner = 0.45;
  set vectorStarInner(double v) {
    if (_vectorStarInner == v) return;
    _vectorStarInner = v;
    notifyListeners();
  }

  double get vectorShapeCorner => _vectorShapeCorner;
  double _vectorShapeCorner = 0.2;
  set vectorShapeCorner(double v) {
    if (_vectorShapeCorner == v) return;
    _vectorShapeCorner = v;
    notifyListeners();
  }

  /// vectorShapeFill and vectorShapeLine are the colours a new shape is
  /// drawn in, or null for none; vectorShapeWidth its line's width, in
  /// pixels on screen as it is drawn. A line, an arrow or a mark is always
  /// a line, whatever the fill is set to.
  Color? get vectorShapeFill => _vectorShapeFill;
  Color? _vectorShapeFill = const Color(0xFF8AB4F8);
  set vectorShapeFill(Color? c) {
    if (_vectorShapeFill == c) return;
    _vectorShapeFill = c;
    notifyListeners();
  }

  Color? get vectorShapeLine => _vectorShapeLine;
  Color? _vectorShapeLine = const Color(0xFF202124);
  set vectorShapeLine(Color? c) {
    if (_vectorShapeLine == c) return;
    _vectorShapeLine = c;
    notifyListeners();
  }

  double get vectorShapeWidth => _vectorShapeWidth;
  double _vectorShapeWidth = 3;
  set vectorShapeWidth(double v) {
    if (_vectorShapeWidth == v) return;
    _vectorShapeWidth = v;
    notifyListeners();
  }

  /// vectorEraseWhole is whether the eraser takes out whole lines and
  /// shapes, where it touches them, rather than rubbing out what it goes
  /// over; vectorEraseSize and vectorEraseSoft are its size on screen and
  /// how far its edge fades; vectorEraseLine and vectorEraseFill whether it
  /// rubs out lines, fills, or both.
  bool get vectorEraseWhole => _vectorEraseWhole;
  bool _vectorEraseWhole = false;
  set vectorEraseWhole(bool on) {
    if (_vectorEraseWhole == on) return;
    _vectorEraseWhole = on;
    notifyListeners();
  }

  double get vectorEraseSize => _vectorEraseSize;
  double _vectorEraseSize = 20;
  set vectorEraseSize(double v) {
    if (_vectorEraseSize == v) return;
    _vectorEraseSize = v;
    notifyListeners();
  }

  double get vectorEraseSoft => _vectorEraseSoft;
  double _vectorEraseSoft = 0;
  set vectorEraseSoft(double v) {
    if (_vectorEraseSoft == v) return;
    _vectorEraseSoft = v;
    notifyListeners();
  }

  bool get vectorEraseLine => _vectorEraseLine;
  bool _vectorEraseLine = true;
  set vectorEraseLine(bool on) {
    if (_vectorEraseLine == on) return;
    _vectorEraseLine = on;
    notifyListeners();
  }

  bool get vectorEraseFill => _vectorEraseFill;
  bool _vectorEraseFill = true;
  set vectorEraseFill(bool on) {
    if (_vectorEraseFill == on) return;
    _vectorEraseFill = on;
    notifyListeners();
  }

  /// clearVectorErasures takes every rub-out off the drawing being edited.
  void clearVectorErasures() {
    var e = editingVector;
    if (e == null || !hasErasures(e)) return;
    replaceElement(withoutErasures(e));
  }

  /// vectorMirrorAcross and vectorMirrorDown are the pencil's symmetry: a
  /// stroke drawn is mirrored across the drawing's upright middle line, its
  /// level middle line, or both -- left and right, top and bottom, all four.
  bool get vectorMirrorAcross => _vectorMirrorAcross;
  bool _vectorMirrorAcross = false;
  set vectorMirrorAcross(bool on) {
    if (_vectorMirrorAcross == on) return;
    _vectorMirrorAcross = on;
    notifyListeners();
  }

  bool get vectorMirrorDown => _vectorMirrorDown;
  bool _vectorMirrorDown = false;
  set vectorMirrorDown(bool on) {
    if (_vectorMirrorDown == on) return;
    _vectorMirrorDown = on;
    notifyListeners();
  }

  /// vectorQuickFill is whether a click with the pencil fills the area the
  /// lines close round it, rather than drawing -- the paint bucket -- and
  /// vectorFillGap the widest opening, in pixels on screen, it still counts
  /// as closed.
  bool get vectorQuickFill => _vectorQuickFill;
  bool _vectorQuickFill = false;
  set vectorQuickFill(bool on) {
    if (_vectorQuickFill == on) return;
    _vectorQuickFill = on;
    notifyListeners();
  }

  /// vectorTextStyle is the type new text in a drawing is set in -- its
  /// size in the canvas's own pixels -- and vectorTextColour its colour.
  VectorText get vectorTextStyle => _vectorTextStyle;
  VectorText _vectorTextStyle = const VectorText();
  Color get vectorTextColour => _vectorTextColour;
  Color _vectorTextColour = const Color(0xFF000000);
  set vectorTextColour(Color c) {
    _vectorTextColour = c;
    var e = editingVector;
    var i = _vectorTyping >= 0 ? _vectorTyping : _vectorShape;
    if (e?.shapes case var shapes? when i >= 0 && i < shapes.length) {
      if (shapes[i].liveText != null) {
        replaceElement(e!.withShape(i, shapes[i].copyWith(fill: c)),
            transient: _vectorTyping >= 0);
      }
    }
    notifyListeners();
  }

  /// vectorTyping is the shape of the drawing being typed into with the
  /// text tool, or -1.
  int get vectorTyping => _vectorTyping;
  int _vectorTyping = -1;

  /// _typedShape is the drawing, the shape being typed into and its index,
  /// while there is one.
  (VectorElement, int, VectorShape)? _typedShape() {
    var e = editingVector;
    var i = _vectorTyping;
    var shapes = e?.shapes;
    if (e == null || shapes == null || i < 0 || i >= shapes.length) {
      return null;
    }
    return (e, i, shapes[i]);
  }

  /// typedText is the text being typed, or the text of the shape picked
  /// where it is still text: what the text tool's settings show.
  VectorText? get typedText {
    if (_typedShape() case (_, _, var s)?) return s.liveText;
    var e = editingVector;
    var i = _vectorShape;
    if (e?.shapes case var shapes? when i >= 0 && i < shapes.length) {
      return shapes[i].liveText;
    }
    return null;
  }

  /// setVectorTextStyle sets the type new text is set in -- [size] here in
  /// the canvas's pixels -- and the text being typed, or picked, with it.
  void setVectorTextStyle(VectorText style) {
    // The type and nothing else: the words, the place and the signature of
    // whatever text the settings were showing are that text's, and new text
    // started with another's signature was never text at all -- it could
    // not be typed into.
    _vectorTextStyle = VectorText(
        family: style.family,
        weight: style.weight,
        italic: style.italic,
        size: style.size,
        spacing: style.spacing,
        leading: style.leading,
        align: style.align);
    var e = editingVector;
    var i = _vectorTyping >= 0 ? _vectorTyping : _vectorShape;
    var s = e?.shapes != null && i >= 0 && i < e!.shapes!.length
        ? e.shapes![i]
        : null;
    var t = s?.liveText;
    if (e != null && t != null) {
      var px = VectorSpace(e).unitsPer;
      retypeVectorText(
          i,
          t.copyWith(
              family: style.family,
              weight: style.weight,
              italic: style.italic,
              size: style.size * px,
              spacing: style.spacing,
              leading: style.leading,
              align: style.align));
    }
    notifyListeners();
  }

  /// retypeVectorText lays shape [shape] out again as [t] -- once its font
  /// is read, which is at once where it has been already.
  void retypeVectorText(int shape, VectorText t) {
    var pick = FontFiles.instance.cached(t.family, t.weight, t.italic);
    if (pick == null) {
      FontFiles.instance.load(t.family, t.weight, t.italic).then((p) {
        if (p != null) retypeVectorText(shape, t);
      });
      return;
    }
    var e = editingVector;
    var shapes = e?.shapes;
    if (e == null || shapes == null || shape >= shapes.length) return;
    var s = shapes[shape];
    var origin = s.textOrigin ?? s.text?.origin ?? t.origin;
    replaceElement(e.withShape(shape, typed(s, t, origin, pick)),
        transient: true);
  }

  /// newVectorText starts new text in the drawing being edited, its first
  /// line starting at [at] in the drawing's own units, and starts typing
  /// into it.
  Future<void> newVectorText(Offset at) async {
    stopVectorTyping();
    var e = editingVector;
    if (e == null) return;
    var style = _vectorTextStyle;
    var t = VectorText(
        family: style.family,
        weight: style.weight,
        italic: style.italic,
        size: style.size * VectorSpace(e).unitsPer,
        spacing: style.spacing,
        leading: style.leading,
        align: style.align,
        origin: at);
    await FontFiles.instance.load(t.family, t.weight, t.italic);
    e = editingVector;
    if (e == null) return;
    var shapes = e.shapes ?? const <VectorShape>[];
    beginInteraction();
    replaceElement(
        e.copyWith(shapes: [
          ...shapes,
          VectorShape(paths: const [], fill: _vectorTextColour, text: t),
        ]),
        transient: true);
    _vectorTyping = shapes.length;
    _vectorShape = shapes.length;
    _vectorPicks = const {};
    notifyListeners();
  }

  /// startVectorTyping types into shape [shape], text already.
  void startVectorTyping(int shape) {
    if (_vectorTyping == shape) return;
    stopVectorTyping();
    beginInteraction();
    _vectorTyping = shape;
    _vectorShape = shape;
    _vectorPicks = const {};
    notifyListeners();
  }

  /// stopVectorTyping finishes the text being typed: what was typed is one
  /// change, and text left empty is taken away.
  void stopVectorTyping() {
    if (_vectorTyping < 0) return;
    if (_typedShape() case (var e, var i, var s)?
        when (s.liveText?.text.trim() ?? "x").isEmpty) {
      var shapes = [...e.shapes!]..removeAt(i);
      replaceElement(e.copyWith(shapes: shapes), transient: true);
      if (_vectorShape == i) _vectorShape = -1;
    }
    _vectorTyping = -1;
    endInteraction();
    notifyListeners();
  }

  /// vectorKnifeGap is how far apart the knife leaves the two sides of a
  /// cut, in the canvas's own pixels.
  double get vectorKnifeGap => _vectorKnifeGap;
  double _vectorKnifeGap = 1;
  set vectorKnifeGap(double v) {
    if (_vectorKnifeGap == v) return;
    _vectorKnifeGap = v;
    notifyListeners();
  }

  double get vectorFillGap => _vectorFillGap;
  double _vectorFillGap = 3;
  set vectorFillGap(double v) {
    if (_vectorFillGap == v) return;
    _vectorFillGap = v;
    notifyListeners();
  }

  /// vectorPencilFill is the colour a fill brush fills its strokes with, and
  /// the quick fill fills an area with.
  Color get vectorPencilFill => _vectorPencilFill;
  Color _vectorPencilFill = const Color(0xFF8AB4F8);
  set vectorPencilFill(Color c) {
    if (_vectorPencilFill == c) return;
    _vectorPencilFill = c;
    notifyListeners();
  }

  Color get vectorPencilColour => _vectorPencilColour;
  Color _vectorPencilColour = const Color(0xFF202124);
  set vectorPencilColour(Color c) {
    if (_vectorPencilColour == c) return;
    _vectorPencilColour = c;
    notifyListeners();
  }

  /// stylusButtons is what the pen's three buttons do with the pencil out,
  /// in the order the pen reports them -- a right click, a middle click, a
  /// back click, which is what a tablet's driver sends for them -- and
  /// stylusEraser what its other end does.
  List<StylusAction> get stylusButtons => _stylusButtons;
  List<StylusAction> _stylusButtons = const [
    StylusAction.pickColour,
    StylusAction.pan,
    StylusAction.undo,
  ];
  void setStylusButton(int index, StylusAction action) {
    if (index < 0 || index >= _stylusButtons.length) return;
    _stylusButtons = [
      for (var (i, a) in _stylusButtons.indexed) i == index ? action : a,
    ];
    notifyListeners();
  }

  StylusAction get stylusEraser => _stylusEraser;
  StylusAction _stylusEraser = StylusAction.erase;
  set stylusEraser(StylusAction a) {
    if (_stylusEraser == a) return;
    _stylusEraser = a;
    notifyListeners();
  }

  /// vectorCombining is the shapes picked with the Boolean tool, to be
  /// combined -- each the first of its run of combined shapes.
  Set<int> get vectorCombining => _vectorCombining;
  Set<int> _vectorCombining = const {};

  /// toggleCombining picks shape [shape] for combining, or unpicks it.
  void toggleCombining(int shape) {
    var next = {..._vectorCombining};
    if (!next.remove(shape)) next.add(shape);
    _vectorCombining = next;
    notifyListeners();
  }

  /// clearCombining unpicks every shape picked for combining.
  void clearCombining() {
    if (_vectorCombining.isEmpty) return;
    _vectorCombining = const {};
    notifyListeners();
  }

  /// combineVector combines the shapes picked by [op], leaving the result
  /// picked.
  void combineVector(VectorCombine op) {
    var e = editingVector;
    if (e == null || _vectorCombining.length < 2) return;
    var (next, at) = withCombined(e, _vectorCombining, op);
    _vectorCombining = at >= 0 ? {at} : const {};
    _vectorPicks = const {};
    _vectorShape = -1;
    replaceElement(next);
  }

  /// separateVector undoes the combining of every picked result.
  void separateVector() {
    var e = editingVector;
    if (e == null || _vectorCombining.isEmpty) return;
    var next = e;
    for (var base in _vectorCombining) {
      next = withSeparated(next, base);
    }
    _vectorCombining = const {};
    replaceElement(next);
  }

  /// vectorTint is the tint brush's colour -- or gradient, laid across each
  /// stroke as the colour picker sets it.
  PaintSpec get vectorTint => _vectorTint;
  PaintSpec _vectorTint = const PaintSpec(Color(0xFFE5484D));
  set vectorTint(PaintSpec p) {
    if (_vectorTint == p) return;
    _vectorTint = p;
    notifyListeners();
  }

  /// vectorBrushSize is the tint brush's width on screen, in pixels: the
  /// same brush however far in the canvas is zoomed. vectorBrushSoft is how
  /// far its edge fades, 0 to 1.
  double get vectorBrushSize => _vectorBrushSize;
  double _vectorBrushSize = 24;
  set vectorBrushSize(double v) {
    if (_vectorBrushSize == v) return;
    _vectorBrushSize = v;
    notifyListeners();
  }

  double get vectorBrushSoft => _vectorBrushSoft;
  double _vectorBrushSoft = 0.5;
  set vectorBrushSoft(double v) {
    if (_vectorBrushSoft == v) return;
    _vectorBrushSoft = v;
    notifyListeners();
  }

  /// vectorTintLine and vectorTintFill are where the brush's tint shows: on
  /// the drawing's lines, in its fills. Both is both.
  bool get vectorTintLine => _vectorTintLine;
  bool _vectorTintLine = true;
  set vectorTintLine(bool on) {
    if (_vectorTintLine == on) return;
    _vectorTintLine = on;
    notifyListeners();
  }

  bool get vectorTintFill => _vectorTintFill;
  bool _vectorTintFill = true;
  set vectorTintFill(bool on) {
    if (_vectorTintFill == on) return;
    _vectorTintFill = on;
    notifyListeners();
  }

  /// clearVectorTints takes every tint off the drawing being edited.
  void clearVectorTints() {
    var e = editingVector;
    if (e == null || !hasTints(e)) return;
    replaceElement(withoutTints(e));
  }

  /// editingVector is the drawing being edited, where there is one and it has
  /// been taken apart -- which editing it always has. See startVectorEditing.
  VectorElement? get editingVector {
    var id = _vectorEditing;
    var e = id == null ? null : _document.elementById(id);
    return e is VectorElement && e.edited ? e : null;
  }

  /// editVector starts editing the drawing [id], or stops with null.
  void editVector(String? id) {
    if (_vectorEditing == id) return;
    stopVectorTyping();
    _fitEditedVector();
    _vectorEditing = id;
    _resetVectorEditing();
    // Edited is selected: the drawing being edited is the one thing picked,
    // so the settings beside it are its own. See notifyListeners.
    if (id != null) {
      _selection = {id};
      _backgroundSelected = false;
    }
    notifyListeners();
  }

  void _resetVectorEditing() {
    _vectorShape = -1;
    _vectorPicks = const {};
    _vectorTool = VectorTool.select;
    _vectorPenFrom = null;
    _vectorCombining = const {};
    _vectorShapeMade = -1;
  }

  void pickVectorShape(int shape) {
    if (_vectorShape == shape && _vectorPicks.isEmpty) return;
    _vectorShape = shape;
    _vectorPicks = const {};
    notifyListeners();
  }

  /// pickVectorPoint picks [pick] alone -- or, with [toggle], adds it to the
  /// points picked or takes it out, which is Shift and a click.
  void pickVectorPoint(VectorPick? pick, {bool toggle = false}) {
    Set<VectorPick> next;
    if (pick == null) {
      next = const {};
    } else if (toggle) {
      next = {..._vectorPicks};
      if (!next.remove(pick)) next.add(pick);
    } else {
      next = {pick};
    }
    if (setEquals(next, _vectorPicks)) return;
    _vectorPicks = next;
    if (pick != null) _vectorShape = pick.shape;
    notifyListeners();
  }

  /// pickVectorPoints picks [picks], all at once: a box dragged across the
  /// drawing.
  void pickVectorPoints(Set<VectorPick> picks) {
    _vectorPicks = {...picks};
    if (picks.isNotEmpty) _vectorShape = picks.first.shape;
    notifyListeners();
  }

  /// deleteVectorPoint takes out the points picked in the drawing being
  /// edited, returning whether there were any to take.
  bool deleteVectorPoint() {
    var e = editingVector, picks = _vectorPicks;
    if (e == null) return false;
    // A shape picked whole, with no points: every point of it.
    if (picks.isEmpty && _vectorShape >= 0) {
      var shape = e.shapes?.elementAtOrNull(_vectorShape);
      if (shape != null) {
        picks = {
          for (var (p, run) in shape.paths.indexed)
            for (var n = 0; n < run.nodes.length; n++)
              VectorPick(_vectorShape, p, n),
        };
      }
    }
    if (picks.isEmpty) return false;
    var next = withoutPoints(e, picks);
    _vectorPicks = const {};
    _vectorPenFrom = null;
    if ((next.shapes?.length ?? 0) < (e.shapes?.length ?? 0)) {
      _vectorShape = -1;
    }
    replaceElement(next);
    return true;
  }

  /// _leaveVectorIfUnpicked stops editing a drawing that is no longer the one
  /// selected: picking something else is how editing is finished.
  void _leaveVectorIfUnpicked() {
    var id = _vectorEditing;
    if (id == null) return;
    if (_selection.length == 1 && _selection.first == id) return;
    _fitEditedVector();
    _vectorEditing = null;
    _resetVectorEditing();
  }

  /// _fitEditedVector grows the box of the drawing being left to take in
  /// whatever the editing carried out past it, so the box drawn round it is
  /// round all of it. See boxedToDrawing.
  void _fitEditedVector() {
    var e = editingVector;
    if (e == null) return;
    var fitted = boxedToDrawing(e);
    if (identical(fitted, e)) return;
    apply(_document.withElement(fitted));
  }

  void selectOnly(String id) {
    if (_selection.length == 1 &&
        _selection.first == id &&
        !_backgroundSelected &&
        _offCanvas.isEmpty) {
      return;
    }
    _backgroundSelected = false;
    _offCanvas = const {};
    _selection = {id};
    _leaveVectorIfUnpicked();
    _focusedPlayer = null;
    notifyListeners();
  }

  /// selectMany picks out a set at once, for the things that work on several
  /// -- the alignment tools, and a sweep over empty space.
  void selectMany(Set<String> ids) {
    _backgroundSelected = false;
    _offCanvas = const {};
    _selection = {...ids};
    _leaveVectorIfUnpicked();
    _focusedPlayer = null;
    notifyListeners();
  }

  void toggleSelected(String id) {
    _backgroundSelected = false;
    _selection = {..._selection};
    _selection.contains(id) ? _selection.remove(id) : _selection.add(id);
    notifyListeners();
  }

  /// clipSelection is every clip picked on the timeline: the selection, and
  /// the clips picked that are on another canvas -- another scene's, or the
  /// master's seen from a scene -- which the timeline can reach while every
  /// scene plays. They are not in the selection, which is only ever the
  /// canvas in front of the reader; picked, they are lit and moved with the
  /// rest all the same.
  Set<String> get clipSelection =>
      _offCanvas.isEmpty ? _selection : {..._selection, ..._offCanvas};
  Set<String> _offCanvas = const {};

  bool _onCanvas(String id) => _document.indexOf(id) >= 0;

  /// pickClip picks the clip [id] on the timeline, wherever it is -- or,
  /// with [toggle], adds it to what is picked or takes it out.
  void pickClip(String id, {bool toggle = false}) {
    if (_onCanvas(id)) {
      toggle ? toggleSelected(id) : selectOnly(id);
      return;
    }
    if (toggle) {
      var next = {..._offCanvas};
      if (!next.remove(id)) next.add(id);
      _offCanvas = next;
    } else {
      _backgroundSelected = false;
      _focusedPlayer = null;
      _selection = {};
      _offCanvas = {id};
    }
    notifyListeners();
  }

  /// pickClips picks [ids] on the timeline, wherever each one is: a box
  /// dragged across the lanes.
  void pickClips(Set<String> ids) {
    _backgroundSelected = false;
    _focusedPlayer = null;
    _selection = {
      for (var id in ids)
        if (_onCanvas(id)) id
    };
    _offCanvas = {
      for (var id in ids)
        if (!_onCanvas(id)) id
    };
    notifyListeners();
  }

  // ---- scenes -------------------------------------------------------------

  /// playAll is whether Play runs the whole document or the scene in front of
  /// the reader.
  ///
  /// A mode rather than a second button, because it is the same act -- press
  /// play, watch it -- asked of two different things, and the answer is
  /// usually the same for a whole sitting: somebody building a scene plays
  /// the scene, somebody checking the sequence plays the sequence.
  bool get playAll => _playAll;
  bool _playAll = false;

  set playAll(bool value) {
    if (_playAll == value) return;
    _playAll = value;
    // What is picked on other canvases is out of reach again with one scene.
    if (!value) _offCanvas = const {};
    pause();
    stopPreview();
    notifyListeners();
  }

  /// previewAt is the frame of the *whole run* the canvas is showing, or null
  /// when it is showing the scene being edited.
  ///
  /// How a transition is watched: the stage draws the sequence rather than
  /// the scene, so what is seen is what will be published -- the same
  /// function, not a second one that agrees for now. See paintSequenceFrame.
  int? get previewAt => _previewAt;
  int? _previewAt;

  /// previewEnd is where the preview stops. Kept so that watching a
  /// transition does not run on through the rest of the document.
  int _previewEnd = 0;

  /// _previewFrom is the scene the preview was started on, so that watching a
  /// join leaves the editor where it was found. Somebody previewing the same
  /// join twice should not have to walk back to it in between.
  int? _previewFrom;

  /// _previewFromMaster is whether the shared canvas was the one open when
  /// the preview started, so that watching a join puts it back rather than
  /// leaving the reader on whichever scene the playhead stopped in.
  bool _previewFromMaster = false;

  /// previewTransitionAfter plays the join between a scene and the next one:
  /// a little of the scene before it, the transition, and a little of the
  /// scene after.
  void previewTransitionAfter(int index) {
    var document = _document;
    var scenes = document.allScenes;
    if (scenes.length < 2) return;

    // On the shared canvas the bar is editing the default every scene starts
    // from, and there is no "this scene" for it to be after -- so the first
    // join stands for all of them. Asked for the join after whatever scene
    // was last open, the button did nothing at all whenever that was the last
    // scene, which is what made it seem temperamental.
    if (document.editingMaster) index = 0;
    if (index < 0 || index >= scenes.length - 1) return;

    var over = document.transitionAfter(index);
    var start = document.startOfScene(index + 1);
    // A little of the scene being left, then the join, then a little of the
    // one arriving. Started at the join itself, as it was, a short transition
    // began before the eye had anything to compare it with -- which is the
    // one thing a preview is for.
    var lead = math.max(6, (document.frameRate * 0.4).round());
    _previewFrom = document.at;
    _previewFromMaster = document.editingMaster;
    _previewAt = math.max(0, start - over.overlap - lead);
    _previewEnd =
        math.min(document.sequenceFrames - 1, start + over.frames + lead);
    _startTimer();
    notifyListeners();
  }

  /// stopPreview puts the canvas back on the scene being edited.
  void stopPreview() {
    if (_previewAt == null) return;
    _previewAt = null;
    pause();
    // Back to the canvas it was started from. Playing the document walks the
    // editor through the scenes -- see _tick -- so without this, watching a
    // join left the reader two scenes further on than they were.
    var back = _previewFrom;
    var wasMaster = _previewFromMaster;
    _previewFrom = null;
    _previewFromMaster = false;
    if (back != null && back != _document.at) {
      _document = _document.goToScene(back);
      _frame = _frame.clamp(0, math.max(0, _document.frames - 1)).toInt();
      _audioFollowsPage(turned: true);
    }
    // And back onto the shared canvas where that is where it started: the
    // playhead walks the scenes while a join is watched, and returning to a
    // scene would leave somebody editing the master looking at scene one.
    if (wasMaster && !_document.editingMaster) {
      _document = _document.copyWith(onMaster: true);
      _frame = _frame.clamp(0, math.max(0, _document.frames - 1)).toInt();
    }
    notifyListeners();
  }

  /// scenes are the canvases this document plays, in order.
  List<CanvasScene> get scenes => _document.allScenes;

  /// setSceneFrames sets how many frames several scenes have, as one change:
  /// the scene strip's drag between two scenes, which gives one what it takes
  /// from the other. Each is held to at least one frame.
  void setSceneFrames(Map<int, int> lengths, {bool transient = false}) {
    var next = _document;
    for (var entry in lengths.entries) {
      var list = next.allScenes;
      if (entry.key < 0 || entry.key >= list.length) continue;
      var frames = entry.value.clamp(1, maxFrameCount).toInt();
      if (list[entry.key].frames == frames) continue;
      next =
          next.withScene(entry.key, list[entry.key].copyWith(frames: frames));
    }
    apply(next, transient: transient);
  }

  /// sceneAt is which one is being edited, and onMaster whether the shared
  /// canvas is showing instead of any of them.
  int get sceneAt => _document.at;
  bool get onMaster => _document.editingMaster;

  /// goToScene shows another canvas.
  ///
  /// Not an undo step: which scene you are looking at is where you are, not
  /// something you did to the document -- undo after moving about should take
  /// back the last edit, not walk backwards through the scenes it was made
  /// in. The selection goes with it, because the elements it names are on the
  /// canvas being left.
  void goToScene(int index) {
    var next = _document.goToScene(index).copyWith(onMaster: false);
    if (identical(next, _document)) return;
    if (!_document.editingMaster) _sceneFrames[_document.scene.id] = _frame;
    apply(next, transient: true);
    // Back where it was left. One playhead clamped to each scene in turn
    // lost a place in a long page to a visit to a short one, and a page
    // left part-way through came back somewhere else.
    if (_sceneFrames[_document.scene.id] case var kept?) _frame = kept;
    _afterSceneChange();
  }

  /// _sceneFrames is where the playhead was on each scene when it was last
  /// left, by scene id. Not in the document: it is where somebody is, not
  /// something they made.
  final Map<String, int> _sceneFrames = {};

  /// frameOn is the frame scene [index] is at: the playhead for the scene
  /// being edited, and for any other the frame it was left on -- or, for one
  /// not visited yet, the frame it would open on, which is the playhead's.
  ///
  /// What the facing page is drawn at. Drawn at a frame of its own choosing,
  /// a page left at the start of its chart's animation showed the chart
  /// finished as soon as the page beside it was opened.
  int frameOn(int index) {
    var list = _document.allScenes;
    if (index < 0 || index >= list.length) return _frame;
    var scene = list[index];
    var at = !_document.editingMaster && index == _document.at
        ? _frame
        : (_sceneFrames[scene.id] ?? _frame);
    return at.clamp(0, math.max(0, scene.frames - 1)).toInt();
  }

  /// showMaster puts the shared canvas in front of the reader, making one if
  /// there is none and switching it on if it is off: asking to edit the
  /// master is asking for a master.
  void showMaster() {
    var next = _document;
    if (next.master == null) {
      next =
          next.copyWith(master: CanvasScene(id: newSceneId(), name: "Master"));
    }
    apply(next.copyWith(masterOn: true, onMaster: true), transient: true);
    _afterSceneChange();
  }

  /// masterOn switches the shared canvas on and off. Off, it is kept: turning
  /// it off is not the same as throwing away what is on it.
  set masterOn(bool value) {
    if (_document.masterOn == value) return;
    var next = _document.copyWith(masterOn: value);
    if (!value && next.onMaster) next = next.copyWith(onMaster: false);
    apply(next);
    _afterSceneChange();
  }

  /// addScene puts a new canvas after the one being edited and goes to it.
  void addScene() {
    apply(_document.copyWith(onMaster: false).addScene(after: _document.at));
    _afterSceneChange();
  }

  void duplicateScene(int index) {
    apply(_document.copyWith(onMaster: false).duplicateScene(index));
    _afterSceneChange();
  }

  /// _sceneClipboard is the scene last copied, held the way an element's copy
  /// is: static, in memory, for as long as the app runs.
  ///
  /// Static is the point -- it is what makes a scene copied from one canvas
  /// paste into another, which is the whole reason the row has a Copy on it.
  /// Not the system clipboard, for the reason given on [_clipboard]: a canvas
  /// scene has no sensible text form, and putting JSON there would replace
  /// whatever the reader had copied from somewhere else.
  static CanvasScene? _sceneClipboard;

  /// hasCopiedScene is whether there is a scene waiting to be pasted.
  static bool get hasCopiedScene => _sceneClipboard != null;

  /// forgetCopiedScene empties it. For a test that needs to start from
  /// nothing copied, since the clipboard is deliberately static.
  @visibleForTesting
  static void forgetCopiedScene() => _sceneClipboard = null;

  /// copyScene takes a copy of one, to be pasted into this canvas or another.
  void copyScene(int index) {
    var list = _document.allScenes;
    if (index < 0 || index >= list.length) return;
    _sceneClipboard = list[index];
    notifyListeners();
  }

  /// pasteScene puts the copied scene in after the one being looked at.
  ///
  /// A fresh scene and fresh elements rather than the copy itself: two
  /// documents sharing an id is two documents whose scenes cannot be told
  /// apart, and a paste into the canvas it was copied from would be a second
  /// row naming the first one's elements.
  void pasteScene() {
    var from = _sceneClipboard;
    if (from == null) return;
    var list = [..._document.allScenes];
    var at = (_document.sceneAt + 1).clamp(0, list.length).toInt();
    list.insert(
        at,
        from.copyWith(
          id: newSceneId(),
          elements: [for (var e in from.elements) e.withId(newElementId())],
        ));
    apply(_document.copyWith(onMaster: false).withScenes(list, at: at));
    _afterSceneChange();
  }

  /// setShape changes the shape of the page, keeping the layout of the shape
  /// being left.
  ///
  /// The one route a ratio change takes. Both shapes join the document's
  /// targets, which is what marks them in the ratio list and what a new
  /// element is laid out for -- a document that has been designed at two
  /// shapes is a responsive document, and there is nothing else it could
  /// mean. A document that has only ever been one shape keeps an empty list,
  /// so nothing is marked and nothing is carried.
  void setShape(CanvasSize next, {int? frameRate}) {
    var was = _document.size;
    if (shapeKey(was) == shapeKey(next) && frameRate == null) {
      apply(_document.copyWith(size: next));
      return;
    }
    var moved = _document.forShape(next);
    if (frameRate != null) moved = moved.copyWith(frameRate: frameRate);

    var targets = [...moved.targets];
    for (var key in [shapeKey(was), shapeKey(next)]) {
      if (!targets.contains(key)) targets.add(key);
    }
    apply(moved.copyWith(targets: targets.length > 1 ? targets : const []));
  }

  /// setKind is whether this document is scenes or pages.
  ///
  /// Not just a flag: choosing pages says what shape the canvas is, how fast
  /// it runs and what happens between two of them, and somebody who has said
  /// "this is a document" should not then have to say "and A4" and "and one
  /// frame a second" and "and a page turn". So the three follow -- but only
  /// where they have not been decided already: a canvas that is on A4 and is
  /// then called a document is a canvas somebody has already shaped, and a
  /// screen ratio chosen on purpose is not an oversight to be corrected.
  ///
  /// Nothing is undone on the way back. Called Scenes again, a document keeps
  /// its paper, its rate and its covers: they are all things that were true
  /// of it, and a switch that threw a layout away would be a switch nobody
  /// dared press twice.
  void setKind(CanvasKind kind) {
    if (_document.kind == kind) return;
    if (kind != CanvasKind.pages) {
      apply(_document.copyWith(kind: kind));
      return;
    }

    // Paper, unless it is on paper already. A4 at 150dpi: the size somebody
    // means by "a page", and small enough that a document of thirty of them
    // is still something the editor can draw.
    var size = _document.size;
    var onPaper = size.ratio.isPaper;
    var next = onPaper
        ? size
        : size.copyWith(ratio: CanvasRatio.a4, width: a4PageWidth);

    // Pages turn, so a document of them runs at film's rate rather than at a
    // printed sheet's one frame a second -- see defaultRateFor. Only where
    // the rate is still whatever the shape gave it: a rate somebody typed is
    // theirs.
    var rate = _document.frameRate == defaultFrameRateFor(size.ratio)
        ? defaultRateFor(next.ratio, kind)
        : null;

    // Through setShape, which is the one place a shape change goes: it puts
    // away the layout of the shape being left and takes out the one being
    // opened. Written straight into the document the elements would keep the
    // numbers they had on a screen.
    //
    // One undo step for the whole of it. Calling this a document and then
    // pressing undo twice -- once for the kind and once for the paper it
    // brought with it -- is two steps for one decision.
    beginInteraction();
    if (!onPaper) setShape(next, frameRate: rate);
    apply(_document.copyWith(kind: kind, frameRate: onPaper ? rate : null));
    endInteraction();
  }

  /// forgetShape drops a shape from the document's targets, and the layouts
  /// kept for it.
  ///
  /// For a shape looked at once and not wanted: it is marked in the list and
  /// laid out for on every new element until it is said to be over.
  void forgetShape(String key) {
    if (key == shapeKey(_document.size)) return;
    var left = [
      for (var t in _document.targets)
        if (t != key) t
    ];
    CanvasElement dropped(CanvasElement e) => e.base.layouts.containsKey(key)
        ? e.withBase(layouts: {...e.base.layouts}..remove(key))
        : e;
    CanvasScene scene(CanvasScene s) =>
        s.copyWith(elements: [for (var e in s.elements) dropped(e)]);

    var next = _document.master == null
        ? _document
        : _document.copyWith(master: scene(_document.master!));
    apply(next.withScenes([for (var s in next.allScenes) scene(s)],
        at: next.at).copyWith(targets: left.length > 1 ? left : const []));
  }

  /// resetShape lays this shape out again from another one, by scale.
  ///
  /// The way back from an arrangement that has been dragged into a mess: it
  /// is the same seeding the first visit to a shape gets.
  void resetShape(String from) {
    var here = _document.size;
    var was = sizeForShape(from, here);

    CanvasScene scene(CanvasScene s) {
      // Laid out from the other shape exactly as a first visit to this one
      // would have been: the same block, the same measure, the same place.
      // Seeded by the layout's own scale alone it moved the boxes and left
      // the design inside them at this shape's size.
      var had = [
        for (var e in s.elements)
          if (e.base.layouts[from] case var layout?) showing(e, layout) else e,
      ];
      var seed = seedFor(had, was, here);
      return s.copyWith(elements: [
        for (var e in had)
          showing(
              e, seeded(ElementLayout.of(e.base), seed, coversPage(e, was))),
      ]);
    }

    var next = _document.master == null
        ? _document
        : _document.copyWith(master: scene(_document.master!));
    apply(
        next.withScenes([for (var s in next.allScenes) scene(s)], at: next.at));
  }

  /// addScenes puts [scenes] in after the one being looked at, and goes to
  /// the first of them.
  ///
  /// What a saved scene or a saved canvas is dropped into a document with:
  /// one scene from the first, every scene from the second. The ids are the
  /// caller's to make fresh -- see SavedPreset.buildScenes, which does.
  void addScenes(List<CanvasScene> scenes) {
    if (scenes.isEmpty) return;
    var list = [..._document.allScenes];
    var at = (_document.sceneAt + 1).clamp(0, list.length).toInt();
    list.insertAll(at, scenes);
    apply(_document.copyWith(onMaster: false).withScenes(list, at: at));
    _afterSceneChange();
  }

  void removeScene(int index) {
    apply(_document.copyWith(onMaster: false).removeScene(index));
    _afterSceneChange();
  }

  void moveScene(int from, int to) {
    apply(_document.moveScene(from, to));
    _afterSceneChange();
  }

  void renameScene(int index, String name) {
    var list = _document.allScenes;
    if (index < 0 || index >= list.length) return;
    apply(_document.withScene(index, list[index].copyWith(name: name.trim())));
  }

  /// setBackground writes the backdrop being edited.
  ///
  /// The shared canvas's own while that is the one open, and the document's
  /// otherwise. Which of the two an edit lands on is this file's business
  /// rather than the settings panel's: the panel edits "the background", and
  /// there is only ever one of those in front of the reader.
  void setBackground(CanvasBackground next, {bool transient = false}) {
    var document = _document;
    if (document.editingMaster) {
      apply(document.withMaster(document.master!.copyWith(background: next)),
          transient: transient);
      return;
    }
    // The shared canvas's own, where that is the one on screen. A backdrop on
    // the master is drawn in front of every scene's, so writing the scene's
    // from here would change nothing anybody can see -- which is what a dead
    // Background panel was. See CanvasDocument.editedBackground.
    if (document.sharedBackdrop) {
      apply(document.withMaster(document.master!.copyWith(background: next)),
          transient: transient);
      return;
    }
    // This scene's own, where it has one -- that is what is drawn, and the
    // document's underneath it is not -- or where there are several scenes,
    // so that an edit does not leak onto all of them. Writing the shared one
    // is how changing scene one's background changed scene two's.
    //
    // Owning it rather than counting scenes, because a scene can own one
    // while being the only scene left: two scenes, an edit -- which the scene
    // then owns -- and the second scene deleted, and every edit after that
    // went to the document's background underneath a scene background that
    // was still the one on screen. The panel died on removing a scene.
    // A document with no scenes at all cannot answer yes to either: the scene
    // it reports is one it makes up on the spot, and that one owns nothing.
    if (document.scene.background != null || document.hasScenes) {
      apply(
          document.withScene(
              document.at, document.scene.copyWith(background: next)),
          transient: transient);
      return;
    }
    apply(document.copyWith(background: next), transient: transient);
  }

  /// setMasterBackgroundOff leaves every scene its own backdrop, or puts the
  /// shared one back over them.
  ///
  /// The backdrop itself is kept either way: switching it off is a decision
  /// about what covers what, not an instruction to throw a design away.
  void setMasterBackgroundOff(bool off) {
    var master = _document.master;
    if (master == null) return;
    apply(_document.withMaster(master.copyWith(backgroundOff: off)));
  }

  /// setSceneHolds decides whether playback runs on into the next scene.
  void setSceneHolds(int index, bool holds) {
    var list = _document.allScenes;
    if (index < 0 || index >= list.length) return;
    apply(_document.withScene(index, list[index].copyWith(holds: holds)));
  }

  /// setSceneCover marks a page as the front or the back of the document.
  ///
  /// One of each at most, and each at its own end. A document with two front
  /// covers is not a thing, and a cover in the middle is a page: the marks
  /// are what the numbering and the pairing are read from, so two of them
  /// would give two answers to what number a page carries.
  void setSceneCover(int index, PageCover cover) {
    var list = _document.allScenes;
    if (index < 0 || index >= list.length) return;
    var next = [
      for (var (at, scene) in list.indexed)
        at == index
            ? scene.copyWith(cover: cover)
            // Whoever held this mark before gives it up, which is what makes
            // marking a page the front cover also mean "and not that one".
            : (cover.isCover && scene.cover == cover
                ? scene.copyWith(cover: PageCover.none)
                : scene),
    ];
    apply(_document.withScenes(next, at: _document.at));
  }

  /// setSceneTransition gives a scene its own way of giving way to the next,
  /// or takes it back to the document's default.
  void setSceneTransition(int index, SceneTransition? transition) {
    var list = _document.allScenes;
    if (index < 0 || index >= list.length) return;
    apply(_document.withScene(
        index,
        transition == null
            ? list[index].copyWith(clearTransition: true)
            : list[index].copyWith(transition: transition)));
  }

  /// setDefaultTransition changes what every scene without one of its own
  /// uses. It lives on the master canvas, which is where the things shared by
  /// every scene live.
  void setDefaultTransition(SceneTransition transition) {
    var master =
        _document.master ?? CanvasScene(id: newSceneId(), name: "Master");
    apply(_document.copyWith(master: master.copyWith(transition: transition)));
  }

  /// _afterSceneChange puts the editor back on solid ground: a selection
  /// naming elements of the canvas that has just been left is a selection of
  /// nothing, and a frame past the end of the new one is a frame that does
  /// not exist.
  void _afterSceneChange() {
    _audioFollowsPage(turned: true);
    _syncTimeline();
    _selection = {};
    _backgroundSelected = false;
    _focusedPlayer = null;
    _frame = _frame.clamp(0, math.max(0, _document.frames - 1)).toInt();
    notifyListeners();
  }

  void clearSelection() {
    if (_selection.isEmpty && !_backgroundSelected && _offCanvas.isEmpty) {
      return;
    }
    _backgroundSelected = false;
    _focusedPlayer = null;
    _offCanvas = const {};
    _selection = {};
    _leaveVectorIfUnpicked();
    notifyListeners();
  }

  void selectAll() {
    _backgroundSelected = false;
    _offCanvas = const {};
    // What is on the canvas: a sound on the timeline is not, and taking it
    // in would put the soundtrack one Delete away.
    _selection = {
      for (var e in _document.elements)
        if (!e.locked && !isTimelineSound(e)) e.id,
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
    _notifyView();
  }

  void resetZoom() {
    _zoom = 1;
    _pan = const Offset2(0, 0);
    _notifyView();
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
    _notifyView();
  }

  // ------------------------------------------------------------------------
  // Playback
  // ------------------------------------------------------------------------

  set frame(int value) {
    var next = value.clamp(0, math.max(0, _document.frames - 1)).toInt();
    if (next == _frame) return;
    _frame = next;
    _syncTimeline();
    notifyListeners();
  }

  /// stepFrame moves the playhead, and stops playback first.
  ///
  /// Stopping is the point: scrubbing while the timer is still running means
  /// the next tick undoes the step, so the key appears to do nothing. Taking
  /// hold of the playhead is saying you want it where you put it.
  ///
  /// While Play runs every scene, a step past either end of a scene goes on
  /// into the next or the previous one, as playing does.
  void stepFrame(int by) {
    pause();
    var document = _document;
    if (!_runsScenes) {
      frame = _frame + by;
      return;
    }
    var scenes = document.allScenes;
    var at = document.at;
    var f = _frame + by;
    while (f < 0 && at > 0) {
      at--;
      f += scenes[at].frames;
    }
    while (f >= scenes[at].frames && at < scenes.length - 1) {
      f -= scenes[at].frames;
      at++;
    }
    if (at != document.at) goToScene(at);
    frame = f;
  }

  /// rewind is the back-to-the-start button: the first frame of the scene,
  /// and -- pressed again there, while Play runs every scene -- the first
  /// frame of the scene before.
  void rewind() {
    var back = _runsScenes && _frame == 0 && _document.at > 0;
    stop();
    if (back) {
      goToScene(_document.at - 1);
      frame = 0;
    }
  }

  /// _runsScenes is whether the transport works across the scenes: Play all
  /// scenes, on a scene rather than the master.
  bool get _runsScenes =>
      _playAll && _document.hasScenes && !_document.editingMaster;

  void play() {
    if (playing) return;
    // Sounds that start by themselves start with the canvas -- before the
    // checks below, since a page that is a still is still a page with music
    // on it.
    _autoplayAudio();
    // _playback is set below; the timed media are cued once it is.
    scheduleMicrotask(_syncTimeline);

    // The whole document: the playhead runs through the sequence, and the
    // editor follows it -- the scene showing changes as it reaches each one,
    // so the panel, the timeline and the canvas all say the same thing about
    // where the playback has got to.
    if (_playAll && _document.hasScenes) {
      if (_document.playFrames <= 1) return;
      _previewEnd = _document.playFrames - 1;
      // From the playhead, wherever it has been put: the run's frame under
      // it on the ruler. It was from wherever the last run had been paused,
      // which -- after the playhead had been moved to edit something --
      // looked like a jump to anywhere. At the very end, from the start.
      var from = _document.editingMaster
          ? _frame
          : _document.startOfScene(_document.at) + _frame;
      if (from >= _previewEnd) {
        if (!_document.editingMaster && _document.at != 0) goToScene(0);
        _frame = 0;
        from = 0;
      }
      _previewAt = from;
      _loopCounts.clear();
      _startTimer();
      notifyListeners();
      return;
    }

    if (_document.frames <= 1) return;
    _loopCounts.clear();
    _startTimer();
    notifyListeners();
  }

  void _startTimer() {
    _playback?.cancel();
    // Twice a frame, to notice a frame falling due soon after it does; each
    // tick moves the playhead on by however many frames have actually
    // passed. See _tick.
    var interval = Duration(
        microseconds:
            (500000 / _document.frameRate).round().clamp(4000, 500000));
    _clockFrames = 0;
    _clockShift = 0;
    // A periodic timer's tick counts the intervals that have passed, not the
    // callbacks that ran: a late callback sees every interval it missed. So
    // tick times interval is the time since Play, by the same clock a test's
    // pretend time drives.
    _playback = Timer.periodic(
        interval, (t) => _tick(t.tick * interval.inMicroseconds));
  }

  /// _clockFrames is how many frames the playhead has been moved on since
  /// playback started.
  ///
  /// The playhead keeps time by the clock, not by counting ticks. It was a
  /// frame a tick, and a timer's ticks come late whenever the app is busy --
  /// so the playhead fell behind the sound, which plays on the sound card's
  /// own clock, until the two were far enough apart that the sound was
  /// pulled back to the playhead: heard as a skipped beat, or a jump.
  int _clockFrames = 0;

  /// _tick moves the playhead on to where the clock says it should be: one
  /// frame at a time, so a marker on a frame passed over is still obeyed.
  void _tick(int elapsed) {
    var rate = math.max(1, _document.frameRate);
    var seconds = (clockForTest?.call() ?? elapsed) / 1000000 + _clockShift;
    var now = seconds * rate;
    var due = now.floor() - _clockFrames;
    // A long stall -- the window dragged, the machine asleep -- is let go
    // rather than raced through: past a few frames behind, it carries on
    // from the clock without playing out what was missed.
    if (due > 6) {
      _clockFrames += due - 6;
      due = 6;
    }
    for (var i = 0; i < due && _playback != null; i++) {
      _clockFrames++;
      _step();
    }
    if (_playback != null) _followSound(now - _clockFrames);
  }

  /// _clockShift is how far, in seconds, the playhead's clock has been moved
  /// to keep with the sound -- see _followSound.
  double _clockShift = 0;

  /// _followSound keeps the playhead with the sound it is playing.
  ///
  /// The sound plays by the sound card's clock and the playhead went by the
  /// computer's, and the two do not run at quite the same speed. Over a long
  /// track they drifted apart until the sound was far enough out to be moved
  /// back to the playhead -- heard as a skip part way through. Now the
  /// playhead's clock is eased toward wherever the sound has actually got,
  /// a little each tick, so the two never part and the sound is never moved
  /// for drift. A difference too big to be drift -- a hold, a jump -- is
  /// left alone, for the cue to put right.
  ///
  /// [into] is how far past the frame it is on the playhead has got.
  void _followSound(double into) {
    var a = _audio;
    if (a == null) return;
    var rate = math.max(1, _document.frameRate);
    for (var (e, at) in _joinedCuts(_timedOnScreen.toList())) {
      if (at == null || e is! AudioElement || !a.isPlaying(e.id)) continue;
      var clip = e.clip;
      if (clip.loop != MediaLoop.none) continue;
      var position = a.positionOf(e.id), index = a.indexOf(e.id);
      if (position == null || index == null || index >= clip.playlist.length) {
        continue;
      }
      var before = 0.0;
      for (var s in clip.playlist.take(index)) {
        before += s.span;
      }
      var heard =
          clip.at + (before + position - clip.playlist[index].start) * rate;
      var ahead = (heard - (at + into)) / rate;
      if (ahead.abs() > 0.25) return;
      _clockShift += ahead * 0.1;
      return;
    }
  }

  void pause() {
    _playback?.cancel();
    _playback = null;
    _previewing = null;
    // A run of every scene, stopped, is the scene it stopped on at the frame
    // it stopped at -- which is where the playhead already is. Holding on to
    // the run's own frame kept the canvas drawing it while the playhead was
    // moved to edit, and the next Play went on from there instead. Watching
    // one join is different: it puts itself back. See stopPreview.
    if (_playAll && _previewFrom == null) _previewAt = null;
    _syncTimeline();
    notifyListeners();
  }

  void togglePlay() => playing ? pause() : play();

  void stop() {
    pause();
    stopPreview();
    stopAudio();
    frame = 0;
  }

  /// tickForTest advances the playhead one frame, the way the timer does.
  ///
  /// Playback is a real timer, and a test that waited on one would be a test
  /// that takes seconds to say something about arithmetic.
  @visibleForTesting
  void tickForTest() => _step();

  /// clockForTest stands in for the playback clock, in microseconds since
  /// Play, and tickClockForTest is a tick of the timer against it -- so a
  /// test can make a tick late without waiting for one to be.
  @visibleForTesting
  int Function()? clockForTest;

  @visibleForTesting
  void tickClockForTest() => _tick(0);

  /// _step advances one frame and obeys whatever marker is on the new one.
  ///
  /// The markers are applied after the advance rather than before, so a stop
  /// marker on frame 30 means "having reached 30, stop" -- which is what
  /// putting a marker on a frame looks like it should mean.
  void _step() {
    // Previewing one element: it alone moves on, and the playhead stays.
    if (_previewing case var one?) {
      if (one.frame + 1 > _previewingEnd) {
        pause();
        return;
      }
      _previewing = (id: one.id, frame: one.frame + 1);
      notifyListeners();
      return;
    }
    // Watching a transition: the playhead is running through the whole
    // document rather than through the scene, and it stops at the end of the
    // stretch that was asked for rather than looping.
    var preview = _previewAt;
    if (preview != null) {
      var next = preview + 1;
      if (next > _previewEnd) {
        stopPreview();
        return;
      }
      _previewAt = next;

      // Playing the document rather than watching one join: the editor is
      // walked along with the playhead, and a scene that has been told to
      // hold stops it there.
      if (_playAll) {
        var place = placeInSequence(_document, next);
        if (place.scene != _document.at) {
          var last = _document.allScenes[_document.at];
          if (last.holds) {
            stopPreview();
            return;
          }
          _document = _document.goToScene(place.scene);
          _audioFollowsPage(turned: true);
          _autoplayAudio();
        }
        _frame =
            place.frame.clamp(0, math.max(0, _document.frames - 1)).toInt();
      }
      _syncTimeline();
      notifyListeners();
      return;
    }

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
          var held =
              _loopCounts.update(action.frame, (v) => v + 1, ifAbsent: () => 1);
          if (held < action.holdFrames) _frame = next - 1 < 0 ? 0 : next;
          if (held >= action.holdFrames) _loopCounts.remove(action.frame);
        case TimelineActionKind.loop:
          var count =
              _loopCounts.update(action.frame, (v) => v + 1, ifAbsent: () => 1);
          if (action.repeats == 0 || count <= action.repeats) {
            _frame = action.target.clamp(0, _document.frames - 1).toInt();
          }
        case TimelineActionKind.jump:
          _frame = action.target.clamp(0, _document.frames - 1).toInt();
      }
    }
    _syncTimeline();
    notifyListeners();
  }

  // ------------------------------------------------------------------------
  // Live counters
  // ------------------------------------------------------------------------

  /// _counters is what each live counter is showing, by element id.
  ///
  /// Held here rather than on the element, and deliberately: a stopwatch that
  /// has been running for nine seconds is not a *design* that has been running
  /// for nine seconds, and writing every tick into the document would make a
  /// clock an unsaved change once a second and an undo history nobody could
  /// use. The document says how the counter behaves; this says where it has
  /// got to, and it goes when the window does.
  final Map<String, double> _counters = {};

  /// _countersRunning is which of them are counting, and _countersSince when
  /// each was last read, so that a tick advances by the time that has actually
  /// passed rather than by however often the timer happened to fire.
  final Set<String> _countersRunning = {};
  final Map<String, DateTime> _countersSince = {};

  Timer? _counterTimer;

  /// counterTicks counts how many times the running counters have moved.
  ///
  /// So that the stage's painter can tell that something changed: where a
  /// counter has got to is not in the document, so nothing else about the
  /// drawing is different from one tick to the next.
  int get counterTicks => _counterTicks;
  int _counterTicks = 0;

  /// counterValue is what [e] is showing now.
  ///
  /// A clock is the time of day whatever anybody has pressed -- there is
  /// nothing to start or stop about the afternoon -- and everything else is
  /// wherever its own count has got to, which starts at the start.
  double counterValue(CounterElement e) {
    if (!e.live) return e.from;
    if (e.source == CounterSource.clock) return _secondsOfDay();
    return _counters[e.id] ?? e.from;
  }

  /// counterRunning is whether [e] is counting at this moment.
  ///
  /// The element's own `running` is where it starts; this is where it has got
  /// to. A clock is always running.
  bool counterRunning(CounterElement e) =>
      e.live &&
      (e.source == CounterSource.clock || _countersRunning.contains(e.id));

  /// startCounters gets every counter that says it starts running going, which
  /// is what opening a canvas with a clock on it should do.
  void startCounters() {
    for (var e in _document.elements) {
      if (e is CounterElement && e.live && e.running) _runCounter(e, true);
    }
  }

  /// pressCounterButton is what one of a counter's own buttons does.
  ///
  /// Returns true where the press was handled here. Input is the exception:
  /// asking for a number is a question for whoever has a window, so it comes
  /// back false and the caller puts the box up -- see setCounterValue.
  bool pressCounterButton(CounterElement e, CounterButton button) {
    if (!e.live) return true;
    switch (button) {
      case CounterButton.startStop:
        _runCounter(e, !_countersRunning.contains(e.id));
        return true;
      case CounterButton.reset:
        _counters[e.id] = e.from;
        _countersSince[e.id] = DateTime.now();
        _counterTicks++;
        notifyListeners();
        return true;
      case CounterButton.input:
        return false;
    }
  }

  /// setCounterValue is the answer to the Set button: the number to count on
  /// from. It does not start or stop anything -- typing a value into a
  /// stopwatch that is running should not stop it.
  void setCounterValue(CounterElement e, double value) {
    _counters[e.id] = value;
    _countersSince[e.id] = DateTime.now();
    _counterTicks++;
    notifyListeners();
  }

  void _runCounter(CounterElement e, bool on) {
    if (on) {
      _counters.putIfAbsent(e.id, () => e.from);
      _countersSince[e.id] = DateTime.now();
      _countersRunning.add(e.id);
      _counterTicks++;
      _startCounterTimer();
    } else {
      _countersRunning.remove(e.id);
      if (_countersRunning.isEmpty) {
        _counterTimer?.cancel();
        _counterTimer = null;
      }
    }
    notifyListeners();
  }

  void _startCounterTimer() {
    if (_counterTimer != null) return;
    // Twenty times a second. A counter written to two decimal places wants to
    // be seen changing, and a clock written to the second does not -- but the
    // cost of the faster one is a repaint of a number, and the slower one
    // would make the fast one stutter.
    _counterTimer =
        Timer.periodic(const Duration(milliseconds: 50), (_) => tickCounters());
  }

  /// tickCounters moves every running counter on by the time that has passed.
  ///
  /// By the clock rather than by a fixed step per tick: a timer that loses
  /// time whenever the window is busy is a broken timer, and this is the kind
  /// of element somebody points a camera at.
  @visibleForTesting
  void tickCounters({DateTime? now}) {
    if (_countersRunning.isEmpty) return;
    var at = now ?? DateTime.now();
    var moved = false;
    for (var id in _countersRunning.toList()) {
      var e = _document.elementById(id);
      if (e is! CounterElement || !e.live) {
        _countersRunning.remove(id);
        continue;
      }
      var since = _countersSince[id] ?? at;
      var seconds = at.difference(since).inMicroseconds / 1000000;
      if (seconds <= 0) continue;
      _countersSince[id] = at;

      var value = _counters[id] ?? e.from;
      // Towards the far end, whichever way round the two ends are: 100 to 1
      // is a countdown and 1 to 100 is not, and the rate is how fast, not
      // which way.
      var step = e.rate.abs() * seconds * (e.span < 0 ? -1 : 1);
      value += step;

      // Stopped at the end, or back round to the start -- which is what makes
      // a metronome a metronome rather than a counter that ran out.
      var done = e.span < 0 ? value <= e.to : value >= e.to;
      if (done && e.span != 0) {
        if (e.loop) {
          var over = (value - e.to).abs();
          var span = e.span.abs();
          value = span <= 0 ? e.from : e.from + (over % span) * (e.span.sign);
        } else {
          value = e.to;
          _countersRunning.remove(id);
        }
      }
      _counters[id] = value;
      moved = true;
    }
    if (_countersRunning.isEmpty) {
      _counterTimer?.cancel();
      _counterTimer = null;
    }
    if (moved) {
      _counterTicks++;
      notifyListeners();
    }
  }

  /// _secondsOfDay is the reader's own clock, as a number of seconds.
  double _secondsOfDay() {
    var now = DateTime.now();
    return now.hour * 3600 +
        now.minute * 60 +
        now.second +
        now.millisecond / 1000;
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
      case ButtonActionKind.togglePlay:
        togglePlay();
      case ButtonActionKind.restart:
        frame = 0;
        play();
      case ButtonActionKind.toggleElement:
        var target = _document.elementById(action.elementId);
        if (target != null) {
          replaceElement(target.withBase(visible: !target.visible));
        }
      case ButtonActionKind.goToScene:
        var to = _document.sceneIndexNamed(action.elementId);
        if (to >= 0) {
          pause();
          goToScene(to);
          frame = 0;
        }
      case ButtonActionKind.openLink:
        return action.url;
      // A sound or a video: the same five things done to either.
      case ButtonActionKind.playSound:
        switch (_mediaById(action.elementId)) {
          case AudioElement e:
            unawaited(audio.play(e));
          case VideoElement e:
            unawaited(video.play(e));
        }
      case ButtonActionKind.pauseSound:
        _audio?.pause(action.elementId);
        _video?.pause(action.elementId);
      case ButtonActionKind.toggleSound:
        switch (_mediaById(action.elementId)) {
          case AudioElement e:
            unawaited(audio.toggle(e));
          case VideoElement e:
            unawaited(video.toggle(e));
        }
      case ButtonActionKind.stopSound:
        _audio?.stop(action.elementId);
        _video?.stop(action.elementId);
      case ButtonActionKind.muteSound:
        switch (_mediaById(action.elementId)) {
          case AudioElement e:
            audio.toggleMute(e);
          case VideoElement e:
            video.toggleMute(e);
        }
    }
    return null;
  }

  // ------------------------------------------------------------------------
  // Sound
  // ------------------------------------------------------------------------

  final AudioEngine? _audioEngine;
  AudioRuntime? _audio;

  /// audio is what is playing. Made the first time anything asks, so a
  /// canvas with no sound on it never opens a sound device.
  AudioRuntime get audio => _audio ??= AudioRuntime(
      engine: _audioEngine ?? SoLoudAudioEngine(),
      locate: (id) => CanvasMedia.existingPath(MediaKind.audio, id))
    ..addListener(notifyListeners);

  /// audioRevision changes whenever any sound's or video's state does, so
  /// the stage's painter knows to draw the speakers and the frames again.
  int get audioRevision => (_audio?.revision ?? 0) + (_video?.revision ?? 0);

  final FrameSource? _frameSource;
  VideoRuntime? _video;

  /// video plays the canvas's videos, through the same sound runtime as
  /// everything else. Made the first time anything asks, like [audio].
  VideoRuntime get video => _video ??= VideoRuntime(
      frames: _frameSource ?? FfmpegFrames(ffmpegPath),
      audio: audio,
      locate: (id) => CanvasMedia.existingPath(MediaKind.video, id))
    ..addListener(notifyListeners);

  /// videoShow is how [e] should be drawn now: its frame and its play bar.
  VideoShow videoShow(VideoElement e) {
    // On the timeline, outside its span, it is not there at all.
    if (e.clip.timed && !e.isLink) {
      var at = _timedFrame(e.id);
      if (at == null || _momentOf(e, at) == null) {
        return const VideoShow(hidden: true);
      }
    }
    var v = _video;
    if (v == null) return VideoShow.idle(e);
    var view = v.view(e);
    return VideoShow(
      playing: view.playing,
      muted: view.muted,
      volume: view.volume,
      position: view.position,
      start: view.start,
      end: view.end,
      frame: view.frame,
      poster: view.poster,
      opacity: view.opacity,
    );
  }

  /// pressVideo is a press on [part] of [e], [along] of the way along it
  /// for the two bars. Returns the address a link video asked to open, for
  /// the caller to ask about -- leaving the app is not decided down here.
  String? pressVideo(VideoElement e, VideoPart part, {double along = 0}) {
    var current = _mediaById(e.id);
    if (current is VideoElement) e = current;
    if (e.isLink) return linkAt(e.link, e.linkStart);
    // On the timeline it is the playhead's, and nothing on it is pressed.
    if (e.clip.timed) return null;
    switch (part) {
      case VideoPart.picture:
      case VideoPart.bigPlay:
      case VideoPart.playPause:
        unawaited(video.toggle(e));
      case VideoPart.track:
        unawaited(video.seekTo(e, along));
      case VideoPart.mute:
        video.toggleMute(e);
      case VideoPart.volume:
        video.setVolume(e, along);
        if (along > 0 && video.view(e).muted) video.setMuted(e, false);
    }
    return null;
  }

  /// audioUnavailable is whether the sound device could not be opened, for
  /// the settings to say so.
  bool get audioUnavailable => _audio?.unavailable ?? false;

  /// stopAudio stops every sound the canvas is playing.
  void stopAudio() {
    _video?.stopAll();
    _audio?.stopAll();
  }

  /// audioState is how [e]'s sound is doing, for the icon to show.
  AudioState audioState(AudioElement e) {
    var a = _audio;
    if (a == null) return AudioState.idle(e);
    var v = a.view(e);
    return AudioState(playing: v.playing, muted: v.muted, volume: v.volume);
  }

  /// pressAudio is a press on one of [e]'s own controls. [volume] is where
  /// on the volume bar, for that one.
  void pressAudio(AudioElement e, AudioControl part, {double? volume}) {
    var current = _audioById(e.id) ?? e;
    switch (part) {
      case AudioControl.playPause:
        unawaited(audio.toggle(current));
      case AudioControl.mute:
        audio.toggleMute(current);
      case AudioControl.volume:
        if (volume == null) return;
        audio.setVolume(current, volume);
        // Turning it up is asking to hear it.
        if (volume > 0 && audio.view(current).muted) {
          audio.setMuted(current, false);
        }
    }
  }

  /// _audioById finds an audio element on the canvas showing or on the
  /// master -- the two places a button on this page could mean.
  /// _mediaById is an Audio or Video element on the canvas showing or on the
  /// master -- what a button's media action is aimed at.
  CanvasElement? _mediaById(String id) {
    for (var e in [
      ..._document.elements,
      ...?_document.masterScene?.elements,
      ..._document.drawnBackground.media,
    ]) {
      if (e.id == id && (e is AudioElement || e is VideoElement)) return e;
    }
    return null;
  }

  AudioElement? _audioById(String id) {
    for (var e in _document.elements) {
      if (e is AudioElement && e.id == id) return e;
    }
    for (var e in _document.masterScene?.elements ?? const <CanvasElement>[]) {
      if (e is AudioElement && e.id == id) return e;
    }
    return null;
  }

  /// _pageAudio is every sound that belongs to what is on screen: the canvas
  /// showing, and the master under it.
  Iterable<AudioElement> get _pageAudio sync* {
    for (var e in _document.elements) {
      if (e is AudioElement) yield e;
    }
    if (!_document.editingMaster) {
      for (var e
          in _document.masterScene?.elements ?? const <CanvasElement>[]) {
        if (e is AudioElement) yield e;
      }
    }
  }

  /// _audioFollowsPage stops whatever does not belong on the canvas now
  /// showing. [turned] is whether the page actually changed: a master sound
  /// set to stop at the join stops then, and not when an unrelated edit is
  /// made.
  void _audioFollowsPage({required bool turned}) {
    var a = _audio;
    if (a == null) return;
    bool media(CanvasElement e) => e is AudioElement || e is VideoElement;
    // On the master's timeline, a clip runs on the run's clock under every
    // scene, so a turn is nothing to it. Stopped at the turn, it was started
    // again at once by the timeline -- heard as a restart, or as itself
    // twice over.
    bool carries(CanvasElement e) => switch (e) {
          AudioElement e => e.clip.acrossPages || e.clip.timed,
          VideoElement e => e.clip.acrossPages || e.clip.timed,
          _ => false,
        };
    // The background's too: what is drawn is what plays. A master's shared
    // backdrop is the master's, and carries on across a turn on the same
    // terms as anything else on the master.
    var fromMaster = _document.editingMaster || _document.sharedBackdrop;
    var keep = <String>{
      for (var e in _document.elements)
        if (media(e)) e.id,
      for (var e in _document.masterScene?.elements ?? const <CanvasElement>[])
        if (media(e) && (!turned || carries(e))) e.id,
      for (var e in _document.drawnBackground.media)
        if (!turned || !fromMaster || carries(e)) e.id,
    };
    _video?.keepOnly(keep.contains);
    // A video's sound goes where its video goes -- see VideoRuntime.
    a.keepOnly((id) => keep.contains(VideoRuntime.videoOfSound(id) ?? id));
  }

  /// _timedOnScreen is every piece of media on the timeline that is on
  /// screen, and the frame of *its* timeline the playhead is at.
  ///
  /// Two timelines: the scene's, which the playhead is on, and the whole
  /// run's, which media on the master and its backdrop follow -- they play
  /// under every scene, so their frame one is the run's frame one.
  Iterable<(CanvasElement, int)> get _timedOnScreen sync* {
    bool timed(CanvasElement e) => switch (e) {
          VideoElement v => v.clip.timed && !v.isLink && !v.clip.isEmpty,
          AudioElement a => a.clip.timed && !a.clip.isEmpty,
          _ => false,
        };
    var onMaster = _document.editingMaster;
    var run = onMaster
        ? _frame
        : _previewAt ?? _document.startOfScene(_document.at) + _frame;
    for (var e in _document.elements) {
      if (timed(e)) yield (e, onMaster ? run : _frame);
    }
    if (!onMaster) {
      for (var e
          in _document.masterScene?.elements ?? const <CanvasElement>[]) {
        if (timed(e)) yield (e, run);
      }
    }
    var fromMaster = onMaster || _document.sharedBackdrop;
    for (var e in _document.drawnBackground.media) {
      if (timed(e)) yield (e, fromMaster ? run : _frame);
    }
  }

  /// timedLanes is the media on the timeline that is on screen, for the
  /// Channels strip: each clip, how far its timeline is ahead of the scene's
  /// (the start of this scene in the run, for media that follows the run),
  /// and whether it can be changed from here.
  List<TimedLane> get timedLanes {
    var document = _document;
    var here = {for (var e in document.elements) e.id};
    var backdrop = {for (var e in document.drawnBackground.media) e.id};
    var onMaster = document.editingMaster;
    var fromMaster = onMaster || document.sharedBackdrop;
    // Which canvas each clip is on, for the strip's label: the master, or the
    // scene being edited.
    int sceneOf(CanvasElement e) => onMaster ||
            (!here.contains(e.id) && !backdrop.contains(e.id)) ||
            (backdrop.contains(e.id) && fromMaster)
        ? -1
        : document.at;
    // While every scene plays, every clip on the timeline can be moved and
    // trimmed from it -- the master's included, wherever it is seen from.
    var lanes = [
      for (var (e, at) in _timedOnScreen)
        TimedLane(
          e,
          offset: at - _frame,
          editable:
              allChannels || here.contains(e.id) || backdrop.contains(e.id),
          scene: sceneOf(e),
        ),
    ];
    // Every other scene's as well, where that has been asked for: each at its
    // place in the run, to be seen against the rest -- and moved, trimmed
    // and cut from here, held to its own scene. Not played from here: a
    // clip is played on its own scene.
    if (allChannels && document.hasScenes) {
      var base = onMaster ? 0 : document.startOfScene(document.at);
      for (var (i, scene) in document.allScenes.indexed) {
        if (!onMaster && i == document.at) continue;
        var offset = base - document.startOfScene(i);
        for (var e in scene.elements) {
          var clip = switch (e) {
            VideoElement v when !v.isLink => v.clip,
            AudioElement a => a.clip,
            _ => null,
          };
          if (clip == null || !clip.timed || clip.isEmpty) continue;
          lanes.add(TimedLane(e, offset: offset, scene: i));
        }
      }
    }
    return lanes;
  }

  /// allChannels is whether the timeline lists every scene's channels, or
  /// only the scene being edited and the master's. It is Play all scenes:
  /// watching the whole run is when every scene's sound is wanted in view.
  bool get allChannels => _playAll;

  /// timelineReach is how many frames the timeline shows: the scene's, or
  /// further where a clip on it runs on past the scene's end -- so the rest
  /// of a long video or song can be scrolled to, seen and trimmed. The frames
  /// past the scene are drawn as out of it; nothing plays there.
  int get timelineReach {
    var most = _document.frames;
    var rate = math.max(1, _document.frameRate);
    for (var lane in timedLanes) {
      var clip = lane.clip;
      if (clip.isEmpty || clip.runLength <= 0) continue;
      var end = clip.at - lane.offset + (clip.runLength * rate).ceil();
      if (end > most) most = end;
    }
    return most;
  }

  /// timelineChannels is the timeline's channels, each with the sounds on it,
  /// in the order they first appear. A channel is its sounds: one with none
  /// left is gone, and the empty lane under the last is not one -- it is
  /// where a new channel is started.
  List<TimelineChannel> get timelineChannels {
    var by = <String, List<TimedLane>>{};
    for (var lane in timedLanes) {
      (by[lane.channelKey] ??= []).add(lane);
    }
    var found = [
      for (var entry in by.entries) TimelineChannel(entry.key, entry.value),
    ];
    // By scene -- S1, S2, S3, with the master's last -- and in the order
    // each was first met within a scene. The scene being edited used to come
    // first, so the list reshuffled itself at every turn of the page.
    var met = {for (var (i, c) in found.indexed) c.key: i};
    int rank(TimelineChannel c) {
      var scene = c.first.scene;
      return scene < 0 ? 1 << 20 : scene;
    }

    found.sort((a, b) {
      var by = rank(a).compareTo(rank(b));
      return by != 0 ? by : met[a.key]!.compareTo(met[b.key]!);
    });
    if (_channelOrder.isEmpty) return found;
    // Then as they have been dragged into: the channels that have been
    // placed take the places such channels have in that order, among
    // themselves, and a channel never placed keeps its own.
    var placed = {for (var (i, k) in _channelOrder.indexed) k: i};
    var moved = [
      for (var c in found)
        if (placed.containsKey(c.key)) c
    ]..sort((a, b) => placed[a.key]!.compareTo(placed[b.key]!));
    var next = 0;
    return [
      for (var c in found) placed.containsKey(c.key) ? moved[next++] : c,
    ];
  }

  /// _channelOrder is the order channels have been dragged into, by key.
  /// Where somebody is working, not what they made, so it is not saved.
  List<String> _channelOrder = const [];

  /// moveChannel puts the channel [key] at [to] in the list -- the strip
  /// dragged up or down.
  void moveChannel(String key, int to) {
    var keys = [for (var c in timelineChannels) c.key];
    var from = keys.indexOf(key);
    if (from < 0) return;
    keys.removeAt(from);
    keys.insert(to.clamp(0, keys.length).toInt(), key);
    // The ones not in view now -- another scene's, with every scene off --
    // keep the places they were given.
    _channelOrder = [
      ...keys,
      for (var k in _channelOrder)
        if (!keys.contains(k)) k,
    ];
    notifyListeners();
  }

  /// channelLevels is how loud [channel] is now: the loudest of its sounds,
  /// each of which plays through a strip of its own set to the channel's.
  (double, double) channelLevels(TimelineChannel channel) {
    var l = 0.0, r = 0.0;
    for (var lane in channel.lanes) {
      var (a, b) = levels(lane.element.id);
      if (a > l) l = a;
      if (b > r) r = b;
    }
    return (l, r);
  }

  /// _setClips writes several clips at once, as one change: every sound on a
  /// channel when its strip is changed, say. Media on the backdrop has a lane
  /// of its own and is written the way it always was.
  void _setClips(List<(CanvasElement, MediaClip)> changes,
      {bool transient = false}) {
    var next = _document;
    for (var (e, clip) in changes) {
      var changed = switch (e) {
        VideoElement v => v.copyWith(clip: clip),
        AudioElement a => a.copyWith(clip: clip),
        _ => null,
      };
      if (changed == null) continue;
      var anywhere = _replacedAnywhere(next, changed);
      if (anywhere != null) {
        next = anywhere;
      } else if (changes.length == 1) {
        setTimedClip(e, clip, transient: transient);
        return;
      }
    }
    apply(next, transient: transient);
  }

  /// newChannelName is "Channel" and the next number not already taken. A
  /// channel holds sound, and a video's soundtrack beside it, so it is not
  /// "Audio".
  String newChannelName() {
    var taken = {for (var c in timelineChannels) c.name};
    for (var n = 1;; n++) {
      if (!taken.contains("Channel $n")) return "Channel $n";
    }
  }

  /// newChannelId is an id for a channel not made yet.
  String newChannelId() => "ch${newElementId()}";

  /// moveClipToChannel puts [lane]'s sound on [to] -- taking its name and its
  /// strip -- or, with none, on a channel of its own. The channel it leaves
  /// is gone if it was the last thing on it.
  void moveClipToChannel(TimedLane lane, TimelineChannel? to,
      {bool transient = false}) {
    var e = lane.element;
    if ((e is! AudioElement && e is! VideoElement) || !lane.editable) return;
    // Onto a channel of its own canvas: a channel is the clips on it, and
    // one holding a scene's clip and the master's would be two canvases'.
    if (to != null && to.first.scene != lane.scene) return;
    var clip = lane.clip;
    var moved = to == null
        ? clip.copyWith(
            channel: newChannelId(),
            channelName: newChannelName(),
            mix: const ChannelMix())
        : clip.copyWith(channel: to.key, channelName: to.name, mix: to.mix);
    _setClips([(lane.element, moved)], transient: transient);
  }

  /// splitClip cuts [lane]'s sound in two at [frame] of the scene: what is
  /// before stays, and what is after becomes a sound of its own on the same
  /// channel, starting where the cut was. The knife.
  bool splitClip(TimedLane lane, int frame) {
    var e = lane.element;
    // A sound, or a video -- whose two halves are two videos in the same
    // place on the canvas, each on screen while its half plays.
    if ((e is! AudioElement && e is! VideoElement) ||
        !lane.editable ||
        e.locked) {
      return false;
    }
    var clip = lane.clip;
    CanvasElement withClip(MediaClip c) => switch (e) {
          VideoElement v => v.copyWith(clip: c),
          AudioElement a => a.copyWith(clip: c),
          _ => e,
        };
    // Both halves on one channel. A video put on the timeline from its
    // settings has none of its own -- its lane is keyed by its id -- so it
    // is given one here, or the half after the cut would be a lane apart.
    if (clip.channel.isEmpty) {
      clip = clip.copyWith(
          channel: newChannelId(),
          channelName: clip.channelName.isNotEmpty ? clip.channelName : e.name);
    }
    var rate = math.max(1, _document.frameRate);
    var into = (frame - (clip.at - lane.offset)) / rate;
    if (into <= 0.05 || into >= clip.runLength - 0.05) return false;
    var from = 0.0;
    for (var (i, source) in clip.playlist.indexed) {
      var span = source.span;
      if (into < from + span) {
        var cut = source.start + (into - from);
        var before = [
          ...clip.playlist.take(i),
          source.copyWith(end: cut),
        ];
        var after = [
          source.copyWith(start: cut),
          ...clip.playlist.skip(i + 1),
        ];
        var first = withClip(
            clip.copyWith(playlist: before, fadeOut: 0, loop: MediaLoop.none));
        var second = withClip(clip.copyWith(
                playlist: after,
                fadeIn: 0,
                at: clip.at + (into * rate).round()))
            .withId(newElementId());
        var replaced = _replacedAnywhere(_document, first);
        var both =
            replaced == null ? null : _addedBeside(replaced, first.id, second);
        if (both == null) return false;
        apply(both);
        // Picked where it can be: on the canvas being edited.
        if (_document.elements.any((x) => x.id == second.id)) {
          selectOnly(second.id);
        }
        return true;
      }
      from += span;
    }
    return false;
  }

  /// selectedChannels are the channels picked -- by their strips, by a sound
  /// on them, or by a box dragged across them -- which a cut at the playhead
  /// is made on.
  Set<String> get selectedChannels => _selectedChannels;
  Set<String> _selectedChannels = {};

  /// selectedChannel is the one channel picked, where one is; setting it
  /// picks that alone.
  String? get selectedChannel =>
      _selectedChannels.isEmpty ? null : _selectedChannels.first;
  set selectedChannel(String? key) =>
      selectChannels(key == null ? const {} : {key});

  void selectChannels(Set<String> keys) {
    if (setEquals(keys, _selectedChannels)) return;
    _selectedChannels = {...keys};
    notifyListeners();
  }

  /// toggleChannel adds [key] to the channels picked, or takes it out.
  void toggleChannel(String key) {
    var next = {..._selectedChannels};
    if (!next.remove(key)) next.add(key);
    selectChannels(next);
  }

  /// cutAtPlayhead cuts the selected channel -- or the channel of the sound
  /// selected -- where the playhead is: every sound on it the playhead is
  /// part way through. The knife's key.
  bool cutAtPlayhead() {
    var keys = {..._selectedChannels};
    if (keys.isEmpty) {
      var picked = clipSelection;
      for (var lane in timedLanes) {
        if (picked.contains(lane.element.id)) keys.add(lane.channelKey);
      }
    }
    var cut = false;
    for (var channel in timelineChannels) {
      if (!keys.contains(channel.key) || channel.locked) continue;
      for (var lane in channel.lanes) {
        // Fresh each time: a cut changes the document the next one reads.
        var now = timedLanes.where((l) => l.element.id == lane.element.id);
        if (now.isEmpty) continue;
        if (splitClip(now.first, _frame)) cut = true;
      }
    }
    return cut;
  }

  /// lockChannel locks or unlocks every sound on [channel]: locked, none of
  /// them is moved, trimmed, faded, cut or dropped onto.
  void lockChannel(TimelineChannel channel, bool locked) {
    var next = _document;
    for (var lane in channel.lanes) {
      if (!lane.editable) continue;
      next = _replacedAnywhere(next, lane.element.withBase(locked: locked)) ??
          next;
    }
    apply(next);
  }

  /// renameChannel names [channel], on every sound it holds.
  void renameChannel(TimelineChannel channel, String name) {
    var named = name.trim();
    if (named.isEmpty) return;
    _setClips([
      for (var lane in channel.lanes)
        if (lane.editable)
          (lane.element, lane.clip.copyWith(channelName: named)),
    ]);
  }

  /// snapping is whether a sound dragged on the timeline lands on the
  /// seconds and the playhead when it comes near them.
  bool get snapping => _snapping;
  bool _snapping = false;
  set snapping(bool value) {
    if (_snapping == value) return;
    _snapping = value;
    notifyListeners();
  }

  /// timelineTool is what a press on a sound on the timeline does: take hold
  /// of it, or cut it in two.
  TimelineTool get timelineTool => _timelineTool;
  TimelineTool _timelineTool = TimelineTool.select;
  set timelineTool(TimelineTool value) {
    if (_timelineTool == value) return;
    _timelineTool = value;
    notifyListeners();
  }

  /// laneHeights is how tall each channel has been dragged, by channel. The
  /// reader's, for this session: how much room a waveform is given is not
  /// something the document says.
  final Map<String, double> laneHeights = {};

  /// setLaneHeight changes one channel's height.
  void setLaneHeight(String channel, double height) {
    laneHeights[channel] = height;
    notifyListeners();
  }

  /// headerWidth is the column of channel strips down the left of the
  /// timeline, dragged anywhere from an icon's width to the whole strip.
  double get headerWidth => _headerWidth;
  double _headerWidth = 150;
  set headerWidth(double value) {
    var next = value.clamp(timelineHeaderMin, timelineHeaderMax).toDouble();
    if (next == _headerWidth) return;
    _headerWidth = next;
    notifyListeners();
  }

  /// _waveforms is each stored sound's shape, read once and kept -- see
  /// waveformOf.
  static final Map<String, Float32List?> _waveforms = {};
  static final Set<String> _readingWaveform = {};

  /// waveformOf is [assetId]'s shape, as peaks from nought to one across the
  /// whole file, or null until it has been read -- it is read on first asking,
  /// off the main thread, and the timeline is told when it arrives.
  Float32List? waveformOf(String assetId) {
    if (_waveforms.containsKey(assetId)) return _waveforms[assetId];
    if (_readingWaveform.add(assetId)) _readWaveform(assetId);
    return null;
  }

  Future<void> _readWaveform(String assetId) async {
    Float32List? peaks;
    try {
      var path = await CanvasMedia.existingPath(MediaKind.audio, assetId);
      if (path != null) peaks = await audio.engine.peaks(path, waveformPoints);
    } catch (exception) {
      debugPrint("Unable to read the shape of $assetId: $exception");
    }
    _waveforms[assetId] = peaks;
    _readingWaveform.remove(assetId);
    if (!_disposedForWaveform) notifyListeners();
  }

  bool _disposedForWaveform = false;

  /// setTimedClip writes a clip moved or trimmed on the Channels strip back
  /// to whatever holds it: an element on this canvas, or the backdrop.
  void setTimedClip(CanvasElement e, MediaClip clip, {bool transient = false}) {
    var next = switch (e) {
      VideoElement v => v.copyWith(clip: clip),
      AudioElement a => a.copyWith(clip: clip),
      _ => null,
    };
    if (next == null) return;
    var anywhere = _replacedAnywhere(_document, next);
    if (anywhere != null) {
      apply(anywhere, transient: transient);
      return;
    }
    var bg = _document.drawnBackground;
    if (bg.video?.id == e.id && next is VideoElement) {
      setBackground(bg.copyWith(video: next), transient: transient);
    } else if (bg.sound?.id == e.id && next is AudioElement) {
      setBackground(bg.copyWith(sound: next), transient: transient);
    }
  }

  /// _replacedAnywhere is [doc] with [next] in place of the element of its
  /// id, wherever that is: the canvas being edited, the master seen from a
  /// scene, or another scene -- or null where it is none of them. What lets
  /// the timeline change any clip on it while every scene plays.
  ///
  /// A clip on a scene is held to that scene: it starts no earlier than the
  /// scene's first frame and no later than its last. The master's runs the
  /// length of the whole run, and goes where it is put.
  CanvasDocument? _replacedAnywhere(CanvasDocument doc, CanvasElement next) {
    List<CanvasElement> swapped(List<CanvasElement> list) =>
        [for (var e in list) e.id == next.id ? next : e];
    CanvasElement held(CanvasElement e, int frames) => switch (e) {
          VideoElement v when v.clip.timed => v.copyWith(
              clip: v.clip.copyWith(
                  at: v.clip.at.clamp(0, math.max(0, frames - 1)).toInt())),
          AudioElement a when a.clip.timed => a.copyWith(
              clip: a.clip.copyWith(
                  at: a.clip.at.clamp(0, math.max(0, frames - 1)).toInt())),
          _ => e,
        };
    var onMaster = doc.editingMaster;
    if (doc.elements.any((x) => x.id == next.id)) {
      return doc.withElement(onMaster ? next : held(next, doc.frames));
    }
    var master = doc.master;
    if (!onMaster &&
        master != null &&
        master.elements.any((x) => x.id == next.id)) {
      return doc.copyWith(
          master: master.copyWith(elements: swapped(master.elements)));
    }
    for (var (i, scene) in doc.allScenes.indexed) {
      if (!onMaster && i == doc.at) continue;
      if (!scene.elements.any((x) => x.id == next.id)) continue;
      next = held(next, scene.frames);
      return doc.withScene(
          i, scene.copyWith(elements: swapped(scene.elements)));
    }
    return null;
  }

  /// _addedBeside is [doc] with [added] put on whichever canvas [besideId]
  /// is on, just after it -- the second half of a clip cut in two.
  CanvasDocument? _addedBeside(
      CanvasDocument doc, String besideId, CanvasElement added) {
    List<CanvasElement> after(List<CanvasElement> list) => [
          for (var e in list) ...[e, if (e.id == besideId) added],
        ];
    if (doc.elements.any((x) => x.id == besideId)) {
      return doc.addElement(added);
    }
    var master = doc.master;
    if (!doc.editingMaster &&
        master != null &&
        master.elements.any((x) => x.id == besideId)) {
      return doc.copyWith(
          master: master.copyWith(elements: after(master.elements)));
    }
    for (var (i, scene) in doc.allScenes.indexed) {
      if (!doc.editingMaster && i == doc.at) continue;
      if (!scene.elements.any((x) => x.id == besideId)) continue;
      return doc.withScene(i, scene.copyWith(elements: after(scene.elements)));
    }
    return null;
  }

  int? _timedFrame(String id) {
    for (var (e, at) in _timedOnScreen) {
      if (e.id == id) return at;
    }
    return null;
  }

  ClipMoment? _momentOf(CanvasElement e, int frame) {
    var clip = switch (e) {
      VideoElement v => v.clip,
      AudioElement a => a.clip,
      _ => null,
    };
    if (clip == null) return null;
    var rate = _document.frameRate <= 0 ? 1 : _document.frameRate;
    return clip.momentAt((frame - clip.at) / rate);
  }

  /// _syncTimeline puts every timed piece of media where the playhead is:
  /// playing if it is playing, held on the frame under it if not, silent and
  /// out of sight outside its span.
  void _syncTimeline() {
    _applyMix();
    var going = playing;
    for (var (e, at) in _joinedCuts(_timedOnScreen.toList())) {
      var moment = at == null ? null : _momentOf(e, at);
      switch (e) {
        case VideoElement v:
          video.cue(v, moment, playing: going);
        case AudioElement a:
          audio.cue(a, moment, playing: going);
      }
    }
  }

  /// _joinedCuts is the timeline's sounds as they are played: a sound cut in
  /// two, its halves still end to end on one channel, is played as the one
  /// sound it was. The second half is cued with nothing, and the first runs
  /// on through the join.
  ///
  /// Played as two, the first half stopped and the second started at the
  /// cut, and neither on the sample: the playhead moves a frame at a time,
  /// so the first ran a little past the cut -- into what the second then
  /// played again -- and the second started a little late. Heard as a skip
  /// in the middle of what had been one clip.
  ///
  /// Only where nothing would be lost by it: the same file, the second
  /// starting in it where the first stops and on the timeline where the
  /// first ends, no fade at the join, neither looping. The level is whichever
  /// half the playhead is in, so each half's volume line still holds.
  List<(CanvasElement, int?)> _joinedCuts(List<(CanvasElement, int)> items) {
    var rate = math.max(1, _document.frameRate);
    bool joins(AudioElement a, AudioElement b) {
      var x = a.clip, y = b.clip;
      if (x.channel.isEmpty || x.channel != y.channel) return false;
      if (x.playlist.length != 1 || y.playlist.length != 1) return false;
      if (x.loop != MediaLoop.none || y.loop != MediaLoop.none) return false;
      if (x.fadeOut > 0 || y.fadeIn > 0 || x.muted != y.muted) return false;
      var s = x.playlist.single, t = y.playlist.single;
      if (s.assetId != t.assetId || s.end <= 0) return false;
      if ((t.start - s.end).abs() > 0.002) return false;
      return (y.at - (x.at + s.span * rate)).abs() <= 1;
    }

    var out = <(CanvasElement, int?)>[];
    var sounds = <int, List<AudioElement>>{};
    for (var (e, at) in items) {
      if (e is AudioElement && e.clip.timed) {
        (sounds[at] ??= []).add(e);
      } else {
        out.add((e, at));
      }
    }
    for (var MapEntry(key: at, value: list) in sounds.entries) {
      list.sort((a, b) => a.clip.at.compareTo(b.clip.at));
      var used = <String>{};
      for (var (i, head) in list.indexed) {
        if (!used.add(head.id)) continue;
        var chain = [head];
        for (var next in list.skip(i + 1)) {
          if (used.contains(next.id) || !joins(chain.last, next)) continue;
          chain.add(next);
          used.add(next.id);
        }
        if (chain.length == 1) {
          out.add((head, at));
          continue;
        }
        var here = chain.lastWhere((c) => c.clip.at <= at, orElse: () => head);
        var whole = head.clip.copyWith(
          playlist: [
            head.clip.playlist.single
                .copyWith(end: chain.last.clip.playlist.single.end),
          ],
          fadeOut: chain.last.clip.fadeOut,
          volume: here.clip.volume,
        );
        out.add((head.copyWith(clip: whole), at));
        for (var rest in chain.skip(1)) {
          out.add((rest, null));
        }
      }
    }
    return out;
  }

  // ------------------------------------------------------------------------
  // The mixer
  // ------------------------------------------------------------------------

  /// solo is which channels are soloed. The session's rather than the
  /// document's: soloing is listening to one thing for a moment, and an
  /// export plays every channel that is not muted.
  Set<String> get solo => _solo;
  final Set<String> _solo = {};

  /// toggleSolo solos or unsolos a channel, by its key.
  void toggleSolo(String id) {
    if (!_solo.remove(id)) _solo.add(id);
    _applyMix();
    notifyListeners();
  }

  /// setChannelMix changes one strip, as the Channels strip changes a clip --
  /// see setTimedClip.
  void setChannelMix(TimelineChannel channel, ChannelMix mix,
          {bool transient = false}) =>
      _setClips([
        for (var lane in channel.lanes)
          if (lane.editable) (lane.element, lane.clip.copyWith(mix: mix)),
      ], transient: transient);

  void setMasterMix(MasterMix mix, {bool transient = false}) =>
      apply(_document.copyWith(masterMix: mix), transient: transient);

  /// levels is how loud a strip -- by its element's id, or the master with
  /// none -- is coming out now, for the meters.
  (double, double) levels([String? channel]) =>
      _audio?.levels(channel) ?? (0, 0);

  /// _applyMix hands the runtime the mixer as it stands. Cheap when nothing
  /// has changed: the runtime compares before it calls the engine.
  void _applyMix() {
    var lanes = timedLanes;
    if (lanes.isEmpty && _audio == null) return;
    audio.setMix({
      for (var lane in lanes) lane.element.id: lane.clip.mix
    },
        // Soloed by channel, heard by sound: every sound on a soloed channel.
        solo: {
          for (var lane in lanes)
            if (_solo.contains(lane.channelKey)) lane.element.id,
        },
        master: _document.masterMix);
  }

  /// _autoplayAudio starts the sounds on screen that start by themselves.
  void _autoplayAudio() {
    var starting = [
      for (var e in _pageAudio)
        if (e.clip.autoplay && !e.clip.isEmpty && !e.clip.timed) e,
    ];
    if (starting.isNotEmpty) audio.autoplay(starting);

    var videos = [
      for (var e in [
        ..._document.elements,
        if (!_document.editingMaster) ...?_document.masterScene?.elements,
      ])
        if (e is VideoElement &&
            e.clip.autoplay &&
            !e.clip.isEmpty &&
            !e.clip.timed)
          e,
    ];

    // And the backdrop's, which is where a looping video or a music bed
    // usually is.
    for (var e in _document.drawnBackground.media) {
      switch (e) {
        case VideoElement v when v.clip.autoplay && !v.clip.timed:
          videos.add(v);
        case AudioElement a when a.clip.autoplay && !a.clip.timed:
          audio.autoplay([a]);
      }
    }
    if (videos.isNotEmpty) video.autoplay(videos);
  }

  // ------------------------------------------------------------------------
  // Keyframes
  // ------------------------------------------------------------------------

  /// setKeyframe writes the pose at the current frame for one element.
  void setKeyframe(String id, Keyframe key) {
    var element = _document.elementById(id);
    if (element == null) return;
    // Whatever that frame already pinned is kept. A keyframe holds the pose
    // *and* any channels -- a counter's number, a chart's arrival -- and
    // writing a pose over one wholesale threw the channels away: keying the
    // position on the frame a count starts took the count with it.
    var was = element.track?.keyAt(key.frame);
    var merged = was == null || was.values.isEmpty
        ? key
        : key.copyWith(values: {...was.values, ...key.values});
    var track = (element.track ?? ElementTrack.empty).withKey(merged);
    replaceElement(element.withBase(track: track));
  }

  /// applyChartAnimation puts a preset on a chart and lays the two keyframes
  /// that give it a length.
  ///
  /// One gesture, because it is one decision. A preset with no keyframes draws
  /// nothing different -- the reveal channel would never be pinned, so the
  /// chart would sit at "all of it" for every frame -- and asking somebody to
  /// choose a preset and then separately key a channel they have never heard
  /// of is asking them to know how this is implemented.
  ///
  /// The keyframes are ordinary ones. That is the point: the length of the
  /// animation is the gap between them on the timeline, dragged like anything
  /// else, rather than a duration stored on the chart where the timeline could
  /// not see it.
  ///
  /// A still document is given a second's worth of frames first. An animation
  /// on a one-frame canvas is an animation nobody can watch.
  /// [length] is how many frames it takes, and overrules everything else.
  /// Left out, the length comes from the animation's own Length setting where
  /// one has been asked for, and otherwise from wherever the keyframes already
  /// are -- so trying one preset after another to see how they look leaves the
  /// timing alone instead of resetting it every time. See
  /// applyTextAnimation, whose rules these now are.
  void applyChartAnimation(ChartElement element, ChartAnimationPreset preset,
      {int? length}) {
    beginInteraction();

    if (preset == ChartAnimationPreset.none) {
      // The reveal keyframes go with it and nothing else does. Clearing the
      // whole track took the chart's *pose* with it: a chart that had been
      // moved or faded by hand lost all of that for choosing None on a
      // dropdown, which is not what the word means.
      var without = _without(element.track, KeyframeChannel.reveal);
      replaceElement(element
          .copyWith(animation: element.animation.copyWith(preset: preset))
          .withBase(track: without, clearTrack: without == null));
      endInteraction();
      return;
    }

    var document = _document;
    if (!document.isAnimated) {
      document = document.copyWith(
          frames: math.max(2, document.frameRate * chartAnimationSeconds));
    }

    // Where it already is, if it is anywhere. From this frame otherwise, so a
    // chart animated while scrubbed to the middle starts where the reader is
    // looking rather than jumping the playhead.
    var (was, wasFor) = elementAnimationSpan(element);
    var from = was ?? _frame.clamp(0, document.frames - 2);
    var span = wasFor ??
        length ??
        (element.animation.length > 0
            ? element.animation.length
            : defaultAnimationFrames);
    span = math.max(1, span);
    if (document.frames - 1 < from + span) {
      document = document.copyWith(frames: from + span + 1);
    }
    var to = from + span;
    if (to <= from) {
      from = 0;
      to = document.frames - 1;
    }

    var track = element.track ?? ElementTrack.empty;
    for (var key in track.keys) {
      if (key.values.containsKey(KeyframeChannel.reveal)) {
        track = track.withoutFrame(key.frame);
      }
    }
    track = _pinning(_pinning(track, from, KeyframeChannel.reveal, 0), to,
        KeyframeChannel.reveal, 1);

    var next = element
        .copyWith(animation: element.animation.copyWith(preset: preset))
        .withBase(track: track);
    apply(document.withElement(next));
    endInteraction();
  }

  /// applyTextAnimation puts a preset on a text element and lays the two
  /// keyframes that give it a length.
  ///
  /// The chart's function with a different element, and deliberately so: the
  /// two animations use the same channels, the same stagger and the same
  /// timeline, so a canvas with a headline and a chart arriving together has
  /// them arriving together. See applyChartAnimation, which this mirrors line
  /// for line -- including the reason the keyframes are ordinary ones.
  /// [length] is how many frames it takes, and overrules everything else:
  /// zero means the usual two seconds, and it is what the Length setting
  /// passes.
  ///
  /// Left out, the length comes from the animation's own Length setting where
  /// one has been asked for, and otherwise from wherever the keyframes
  /// already are -- so trying one preset after another to see how they look
  /// leaves the timing alone instead of resetting it every time.
  void applyTextAnimation(TextElement element, TextAnimationPreset preset,
      {int? length}) {
    beginInteraction();

    if (preset == TextAnimationPreset.none) {
      var without = _without(element.track, KeyframeChannel.reveal);
      replaceElement(element
          .copyWith(animation: element.animation.copyWith(preset: preset))
          .withBase(track: without, clearTrack: without == null));
      endInteraction();
      return;
    }

    var document = _document;
    if (!document.isAnimated) {
      document = document.copyWith(
          frames: math.max(2, document.frameRate * chartAnimationSeconds));
    }

    // Where it already is, if it is anywhere: choosing a different preset
    // keeps the length that has been set rather than resetting it to the
    // default, which would undo the last thing somebody did every time they
    // tried the next preset in the list.
    var (was, wasFor) = textAnimationSpan(element);
    var from = was ?? _frame.clamp(0, document.frames - 2);
    // Whatever is already on the timeline wins: once an animation has been
    // laid down, its keyframes are where somebody has put them, and trying
    // the next preset in the list must not shove them about. The Length
    // setting is for laying a *new* one down -- which, after the keyframes
    // have been deleted, is what the next preset is.
    var span = wasFor ??
        length ??
        (element.animation.length > 0
            ? element.animation.length
            : defaultAnimationFrames);
    span = math.max(1, span == 0 ? defaultAnimationFrames : span);
    if (document.frames - 1 < from + span) {
      document = document.copyWith(frames: from + span + 1);
    }
    var to = from + span;
    if (to <= from) {
      from = 0;
      to = document.frames - 1;
    }

    var track = (element.track ?? ElementTrack.empty);
    for (var key in track.keys) {
      if (key.values.containsKey(KeyframeChannel.reveal)) {
        track = track.withoutFrame(key.frame);
      }
    }
    track = _pinning(_pinning(track, from, KeyframeChannel.reveal, 0), to,
        KeyframeChannel.reveal, 1);

    apply(document.withElement(element
        .copyWith(
            animation: element.animation.copyWith(
                preset: preset,
                // The curve the preset was designed around, and the way it
                // cuts where it cuts -- and only where the preset is actually
                // changing: re-laying the keyframes for some other reason
                // must not quietly undo numbers somebody chose. See
                // TextAnimationPreset.wants and its effect.
                ease: preset == element.animation.preset ? null : preset.wants,
                effect:
                    preset == element.animation.preset ? null : preset.effect))
        .withBase(track: track)));
    endInteraction();
  }

  /// textAnimationSpan is where [element]'s arrival sits on the timeline: the
  /// frame it starts on and how many frames it takes, or nulls where it has
  /// no keyframes yet.
  ///
  /// Read from the keyframes rather than kept on the animation, because the
  /// keyframes are the truth -- they can be dragged on the timeline, and a
  /// number stored beside them would be a second answer that goes stale the
  /// first time somebody does.
  (int?, int?) textAnimationSpan(TextElement element) {
    int? from;
    int? to;
    for (var key in element.track?.keys ?? const <Keyframe>[]) {
      if (!key.values.containsKey(KeyframeChannel.reveal)) continue;
      from = from == null ? key.frame : math.min(from, key.frame);
      to = to == null ? key.frame : math.max(to, key.frame);
    }
    if (from == null || to == null || to <= from) return (from, null);
    return (from, to - from);
  }

  /// defaultAnimationFrames is how long an animation runs for when nobody
  /// has said: the same two seconds a chart's uses.
  int get defaultAnimationFrames =>
      math.max(2, (_document.frameRate * chartAnimationSeconds).round());

  /// elementAnimationOf is [element]'s own arrival, for the kinds that have
  /// one, or an empty animation for the kinds that do not.
  ///
  /// A switch rather than an interface on CanvasElement: two kinds have this
  /// and nine do not, and a getter on the base class would be a promise that
  /// every element can be animated this way -- which a line, a background or
  /// a chart cannot, each for its own reason.
  static ElementAnimation elementAnimationOf(CanvasElement element) =>
      switch (element) {
        ShapeElement e => e.animation,
        ImageElement e => e.animation,
        VectorElement e => e.animation,
        LineElement e => e.animation,
        PathElement e => e.animation,
        TableElement e => e.animation,
        CounterElement e => e.animation,
        ButtonElement e => e.animation,
        AudioElement e => e.animation,
        VideoElement e => e.animation,
        _ => const ElementAnimation(),
      };

  /// animates is whether [element] is one of the kinds this applies to.
  ///
  /// Not a chart, which has an animation of its own that knows what a bar and
  /// a slice are -- see applyChartAnimation -- and not a text element, whose
  /// presets are scoped to words and letters. Everything else on the canvas
  /// is a thing in a box, and a thing in a box arrives the same way.
  static bool animates(CanvasElement element) =>
      element is ShapeElement ||
      element is ImageElement ||
      element is VectorElement ||
      element is LineElement ||
      element is PathElement ||
      element is TableElement ||
      // A counter is a thing in a box like the rest of them: it arrives and
      // leaves the same way, whatever its number is doing while it is there.
      element is CounterElement ||
      // And a button. Arriving is not pressing: one is what the canvas does
      // to it, the other what somebody does to the canvas.
      element is ButtonElement ||
      element is AudioElement ||
      element is VideoElement;

  static CanvasElement _withElementAnimation(
          CanvasElement element, ElementAnimation animation) =>
      switch (element) {
        ShapeElement e => e.copyWith(animation: animation),
        ImageElement e => e.copyWith(animation: animation),
        VectorElement e => e.copyWith(animation: animation),
        LineElement e => e.copyWith(animation: animation),
        PathElement e => e.copyWith(animation: animation),
        TableElement e => e.copyWith(animation: animation),
        CounterElement e => e.copyWith(animation: animation),
        ButtonElement e => e.copyWith(animation: animation),
        AudioElement e => e.copyWith(animation: animation),
        VideoElement e => e.copyWith(animation: animation),
        _ => element,
      };

  /// setElementLoop gives [element] [loop] -- [transient] while a drag on
  /// its bar is still making it. See ElementLoop.
  void setElementLoop(CanvasElement element, ElementLoop loop,
      {bool transient = false}) {
    if (!animates(element)) return;
    var was = elementAnimationOf(element);
    replaceElement(_withElementAnimation(element, was.copyWith(loop: loop)),
        transient: transient);
  }

  /// applyElementAnimation puts an arrival on a shape or a picture and lays
  /// the pair of keyframes that runs it.
  ///
  /// The text element's [applyTextAnimation], for the kinds that have no
  /// words -- deliberately the same rules, because they are the same
  /// keyframes on the same timeline: whatever is already laid down wins, the
  /// Length setting is for laying a new one down, and choosing None takes the
  /// keyframes away with it.
  void applyElementAnimation(
      CanvasElement element, ElementAnimationPreset preset,
      {int? length}) {
    if (!animates(element)) return;
    beginInteraction();
    var was = elementAnimationOf(element);

    if (preset == ElementAnimationPreset.none) {
      var without = _without(element.track, KeyframeChannel.reveal);
      replaceElement(
          _withElementAnimation(element, was.copyWith(preset: preset))
              .withBase(track: without, clearTrack: without == null));
      endInteraction();
      return;
    }

    var document = _document;
    if (!document.isAnimated) {
      document = document.copyWith(
          frames: math.max(2, document.frameRate * chartAnimationSeconds));
    }

    var (wasAt, wasFor) = elementAnimationSpan(element);
    var from = wasAt ?? _frame.clamp(0, document.frames - 2);
    var span = wasFor ??
        length ??
        (was.length > 0 ? was.length : defaultAnimationFrames);
    span = math.max(1, span == 0 ? defaultAnimationFrames : span);
    if (document.frames - 1 < from + span) {
      document = document.copyWith(frames: from + span + 1);
    }
    var to = from + span;
    if (to <= from) {
      from = 0;
      to = document.frames - 1;
    }

    var track = element.track ?? ElementTrack.empty;
    for (var key in track.keys) {
      if (key.values.containsKey(KeyframeChannel.reveal)) {
        track = track.withoutFrame(key.frame);
      }
    }
    track = _pinning(_pinning(track, from, KeyframeChannel.reveal, 0), to,
        KeyframeChannel.reveal, 1);

    // The preset's own curve and its own way of cutting, and only where the
    // preset is actually changing -- re-laying the keyframes for some other
    // reason must not quietly undo numbers somebody has set. Build up and
    // Break apart are the same motion and differ only in these, so a preset
    // that did not carry them would be a name with nothing behind it.
    var changing = preset != was.preset;
    apply(document.withElement(_withElementAnimation(
            element,
            was.copyWith(
                preset: preset,
                ease: changing ? preset.wants : null,
                effect: changing ? preset.effect : null))
        .withBase(track: track)));
    endInteraction();
  }

  /// elementAnimationSpan is where [element]'s arrival sits on the timeline:
  /// the frame it starts on and how many frames it takes. See
  /// textAnimationSpan, which reads the same channel for the same reasons.
  (int?, int?) elementAnimationSpan(CanvasElement element) {
    int? from;
    int? to;
    for (var key in element.track?.keys ?? const <Keyframe>[]) {
      if (!key.values.containsKey(KeyframeChannel.reveal)) continue;
      from = from == null ? key.frame : math.min(from, key.frame);
      to = to == null ? key.frame : math.max(to, key.frame);
    }
    if (from == null || to == null || to <= from) return (from, null);
    return (from, to - from);
  }

  /// anchorShown is whether [id]'s anchor point is drawn on the stage, where
  /// it can be dragged unless it is locked. A way of looking rather than
  /// part of the design: not saved, and not undone.
  bool anchorShown(String id) => _anchorsShown.contains(id);
  final Set<String> _anchorsShown = {};

  void showAnchor(String id, bool shown) {
    if (shown ? !_anchorsShown.add(id) : !_anchorsShown.remove(id)) return;
    notifyListeners();
  }

  /// setElementArrivalTiming moves [element]'s arrival on the timeline: to
  /// start [delay] frames into the scene, and to take [length] frames --
  /// either or both, the other left where it is. The scene grows to hold it.
  /// Part of whatever change is under way: the caller begins and ends it.
  void setElementArrivalTiming(CanvasElement element,
      {int? delay, int? length}) {
    var (at, span) = elementAnimationSpan(element);
    if (at == null || span == null) return;
    var from = math.max(0, delay ?? at);
    var took = math.max(1, length ?? span);
    if (from == at && took == span) return;
    var track =
        _without(element.track, KeyframeChannel.reveal) ?? ElementTrack.empty;
    track = _pinning(_pinning(track, from, KeyframeChannel.reveal, 0),
        from + took, KeyframeChannel.reveal, 1);
    var document = _document;
    if (from + took > document.frames - 1) {
      document = document.copyWith(frames: from + took + 1);
    }
    var next = element.withBase(track: track);
    // And what the next one is laid down with, so that trying another
    // preset keeps the length that was typed.
    if (length != null) {
      next = _withElementAnimation(
          next, elementAnimationOf(element).copyWith(length: took));
    }
    apply(document.withElement(next), transient: true);
  }

  /// previewSpanOf is the stretch of the scene a Preview of [element] plays:
  /// its arrival, its way out, and its loops -- its own and, for a drawing,
  /// its shapes' -- twice round, with a moment after. Two seconds from the
  /// start where it has none of them.
  (int, int) previewSpanOf(CanvasElement element) {
    var last = math.max(0, _document.frames - 1);
    var rate = math.max(1, _document.frameRate);
    int? start, end;
    void take(int a, int b) {
      start = math.min(start ?? a, a);
      end = math.max(end ?? b, b);
    }

    var (at, span) = elementAnimationSpan(element);
    if (at != null && span != null) take(at, at + span);
    int? closeFrom, closeTo;
    for (var key in element.track?.keys ?? const <Keyframe>[]) {
      if (!key.values.containsKey(KeyframeChannel.close)) continue;
      closeFrom = math.min(closeFrom ?? key.frame, key.frame);
      closeTo = math.max(closeTo ?? key.frame, key.frame);
    }
    if (closeFrom != null && closeTo != null) take(closeFrom, closeTo);
    var arrived = arrivalEnd(element);
    var loops = [
      elementAnimationOf(element).loop,
      if (element is VectorElement)
        for (var d in vectorDrawn(element.shapes ?? const []))
          if (d.style.animation case var own?
              when d.style.owns.contains(ShapeAnimationPart.looping))
            own.loop,
    ];
    for (var loop in loops) {
      if (!loop.on) continue;
      var (from, to) = loop.span(arrived: arrived, last: last);
      take(from, math.min(to, from + 2 * (loop.cycle + loop.gap) - loop.gap));
    }
    var a = start ?? 0;
    var b = end ?? a + rate * 2;
    b = math.min(last, b + (rate * 0.3).round());
    if (b <= a) b = math.min(last, a + 1);
    return (math.min(a, last), b);
  }

  /// previewing is the one element being previewed and the frame it is at, while
  /// a Preview plays: that element runs through its animation and everything
  /// else stays as it is at the playhead, which does not move. See
  /// previewElement.
  ({String id, int frame})? get previewing => _previewing;
  ({String id, int frame})? _previewing;
  int _previewingEnd = 0;

  /// previewElement plays [id]'s animation, and nothing else's, once. See
  /// previewing. Anything else playing stops first; pausing stops it.
  void previewElement(String id) {
    var element = _document.elementById(id);
    if (element == null) return;
    pause();
    stopPreview();
    var (from, to) = previewSpanOf(element);
    _previewing = (id: id, frame: from);
    _previewingEnd = to;
    _startTimer();
    notifyListeners();
  }

  /// applyElementExit is the way out for a shape or a picture, on its own
  /// pair of keyframes at the end of the timeline. See applyTextExit.
  void applyElementExit(CanvasElement element, ElementAnimationPreset preset) {
    if (!animates(element)) return;
    beginInteraction();
    var was = elementAnimationOf(element);

    var track = element.track ?? ElementTrack.empty;
    if (preset == ElementAnimationPreset.none) {
      var without = _without(track, KeyframeChannel.close);
      replaceElement(_withElementAnimation(element, was.copyWith(exit: preset))
          .withBase(track: without, clearTrack: without == null));
      endInteraction();
      return;
    }

    var document = _document;
    if (!document.isAnimated) {
      document = document.copyWith(
          frames: math.max(2, document.frameRate * chartAnimationSeconds * 2));
    }

    int? wasFrom;
    int? wasTo;
    for (var key in track.keys) {
      if (!key.values.containsKey(KeyframeChannel.close)) continue;
      wasFrom = wasFrom == null ? key.frame : math.min(wasFrom, key.frame);
      wasTo = wasTo == null ? key.frame : math.max(wasTo, key.frame);
    }

    var span = was.length > 0 ? was.length : defaultAnimationFrames;
    var to = wasTo ?? document.frames - 1;
    var entranceEnds = _afterEntrance(track);
    var from = wasFrom != null && wasTo != null && wasTo > wasFrom
        ? wasFrom
        : math.max(entranceEnds + 1, to - span);
    if (from >= to) from = math.max(0, to - 1);

    track = _withClosingBand(track, from, to);

    apply(document.withElement(
        _withElementAnimation(element, was.copyWith(exit: preset))
            .withBase(track: track)));
    endInteraction();
  }

  /// applyTextExit is the way out, on its own pair of keyframes at the end of
  /// the timeline. See applyChartExit.
  void applyTextExit(TextElement element, TextAnimationPreset preset) {
    beginInteraction();

    var track = element.track ?? ElementTrack.empty;
    if (preset == TextAnimationPreset.none) {
      var without = _without(track, KeyframeChannel.close);
      replaceElement(element
          .copyWith(animation: element.animation.copyWith(exit: preset))
          .withBase(track: without, clearTrack: without == null));
      endInteraction();
      return;
    }

    var document = _document;
    if (!document.isAnimated) {
      document = document.copyWith(
          frames: math.max(2, document.frameRate * chartAnimationSeconds * 2));
    }

    // Where the exit already is, if it is anywhere -- the same rule the
    // arrival follows: an exit that has been laid down and dragged stays
    // where it was put, however many presets are tried in it.
    int? wasFrom;
    int? wasTo;
    for (var key in track.keys) {
      if (!key.values.containsKey(KeyframeChannel.close)) continue;
      wasFrom = wasFrom == null ? key.frame : math.min(wasFrom, key.frame);
      wasTo = wasTo == null ? key.frame : math.max(wasTo, key.frame);
    }

    var span = element.animation.length > 0
        ? element.animation.length
        : defaultAnimationFrames;
    var to = wasTo ?? document.frames - 1;
    var entranceEnds = _afterEntrance(track);
    var from = wasFrom != null && wasTo != null && wasTo > wasFrom
        ? wasFrom
        : math.max(entranceEnds + 1, to - span);
    if (from >= to) from = math.max(0, to - 1);

    track = _withClosingBand(track, from, to);

    apply(document.withElement(element
        .copyWith(animation: element.animation.copyWith(exit: preset))
        .withBase(track: track)));
    endInteraction();
  }

  /// applyChartExit puts a closing preset on a chart and lays the pair of
  /// keyframes that runs it.
  ///
  /// At the end of the timeline rather than at the playhead, which is where
  /// the entrance is laid: a closing animation is the thing that happens
  /// last, and a chart that faded out in the middle and stayed gone is not
  /// what anybody choosing one is asking for. It is two ordinary keyframes,
  /// dragged like the others -- see [applyChartAnimation], which lays the
  /// other pair for the same reasons.
  ///
  /// It never starts before the entrance has finished. Overlapping the two
  /// bands would have a chart arriving and leaving at once, which draws as a
  /// stutter and reads as a bug.
  void applyChartExit(ChartElement element, ChartAnimationPreset preset) {
    beginInteraction();

    var track = element.track ?? ElementTrack.empty;
    if (preset == ChartAnimationPreset.none) {
      // The keys go with it. A chart with no closing animation and a pair of
      // close keyframes still on its track would be pinned at "gone" for the
      // end of the timeline.
      var without = _without(track, KeyframeChannel.close);
      replaceElement(element
          .copyWith(animation: element.animation.copyWith(exit: preset))
          .withBase(track: without, clearTrack: without == null));
      endInteraction();
      return;
    }

    var document = _document;
    if (!document.isAnimated) {
      document = document.copyWith(
          frames: math.max(2, document.frameRate * chartAnimationSeconds * 2));
    }

    var span = element.animation.length > 0
        ? element.animation.length
        : defaultAnimationFrames;
    var to = document.frames - 1;
    // Clear of the entrance, which is whatever the reveal channel already
    // reaches.
    var entranceEnds = _afterEntrance(track);
    var from = math.max(entranceEnds + 1, to - span);
    if (from >= to) from = math.max(0, to - 1);

    track = _withClosingBand(track, from, to);

    apply(document.withElement(element
        .copyWith(animation: element.animation.copyWith(exit: preset))
        .withBase(track: track)));
    endInteraction();
  }

  /// shiftKeyframes moves a whole band of keyframes by [delta] frames.
  ///
  /// The two ends of an animation are one thing, so the timeline drags them
  /// as one -- see KeyframeBand. Refused rather than clamped when either end
  /// would run off the timeline: sliding a band into the end of the canvas
  /// and having it silently squash is worse than it stopping.
  void shiftKeyframes(String id, List<int> frames, int delta) {
    if (delta == 0 || frames.isEmpty) return;
    var element = _document.elementById(id);
    var track = element?.track;
    if (element == null || track == null) return;

    var moving = [
      for (var frame in frames)
        if (track.keyAt(frame) != null) track.keyAt(frame)!,
    ];
    if (moving.length != frames.length) return;
    for (var key in moving) {
      var at = key.frame + delta;
      if (at < 0 || at > _document.frames - 1) return;
    }

    var next = track;
    for (var key in moving) {
      next = next.withoutFrame(key.frame);
    }
    for (var key in moving) {
      next = next.withKey(key.copyWith(frame: key.frame + delta));
    }
    replaceElement(element.withBase(track: next));
  }

  /// removeKeyframe drops the pose at [frame], and drops the track entirely
  /// when it was the last one -- so an element with no animation left carries
  /// no empty track into the saved file.
  void removeKeyframe(String id, int frame) {
    var element = _document.elementById(id);
    var track = element?.track;
    if (element == null || track == null) return;

    replaceElement(withoutHalfAnimations(element, track.withoutFrame(frame)));
  }

  /// setKeyframeEasing writes how the element travels *out* of a keyframe.
  ///
  /// Easing belongs to the keyframe it leaves, which is why this is here and
  /// not on the animation: one arrival can be laid down and then eased, and a
  /// run of keyframes copied and pasted keeps whatever easing each of them
  /// had.
  ///
  /// [all] sets every keyframe on the element at once, and [channel] narrows
  /// that to the keyframes carrying one thing -- a counter's number, say --
  /// so setting the count's easing does not restyle a move somebody laid by
  /// hand on the same element.
  void setKeyframeEasing(
    CanvasElement element,
    KeyframeEasing easing, {
    bool all = false,
    String? channel,
  }) {
    var track = element.track;
    if (track == null) return;
    var next = track;
    for (var key in track.keys) {
      if (!all && key.frame != _frame) continue;
      if (channel != null && !key.values.containsKey(channel)) continue;
      next = next.withKey(key.copyWith(easing: easing));
    }
    if (identical(next, track)) return;
    replaceElement(element.withBase(track: next));
  }

  /// clearPose takes the *pose* off one frame and leaves whatever else that
  /// keyframe pinned.
  ///
  /// What the position-size-angle-fade diamond does, as against deleting the
  /// keyframe: one keyframe holds the pose and the channels together, so
  /// pressing a diamond labelled "position, size, angle and fade" took a
  /// counter's number and a chart's arrival away with them. Deleting the
  /// keyframe itself still deletes all of it -- an animation is a pair, and a
  /// deliberate delete on the timeline means the whole mark.
  void clearPose(String id, int frame) {
    var element = _document.elementById(id);
    var track = element?.track;
    if (element == null || track == null) return;
    var here = track.keyAt(frame);
    if (here == null) return;
    if (here.values.isEmpty) {
      removeKeyframe(id, frame);
      return;
    }
    replaceElement(element.withBase(
        track: track.withKey(Keyframe(frame: frame, values: here.values))));
  }

  /// withoutHalfAnimations takes away any arrival or exit that has lost one
  /// of its two keyframes, and turns the setting off with it.
  ///
  /// An animation is a *pair*: nothing to travel between is not half an
  /// arrival, it is none of one. Left alone, deleting one keyframe left the
  /// other sitting on the timeline, the preset still chosen in the panel, and
  /// nothing to show for either -- and the next preset chosen would then be
  /// laid out against the orphan. Deleting one of them is how somebody says
  /// they are done with it, so the setting goes back to None and the whole
  /// thing is there to be added again.
  CanvasElement withoutHalfAnimations(
      CanvasElement element, ElementTrack next) {
    var lost = <String>{};
    for (var channel in [KeyframeChannel.reveal, KeyframeChannel.close]) {
      var count = 0;
      for (var key in next.keys) {
        if (key.values.containsKey(channel)) count++;
      }
      if (count > 0 && count < 2) lost.add(channel);
    }

    for (var channel in lost) {
      for (var key in next.keys) {
        if (!key.values.containsKey(channel)) continue;
        var without = key.withoutValue(channel);
        next = without.isRest && without.frame != 0
            ? next.withoutFrame(key.frame)
            : next.withKey(without);
      }
    }

    var out = element;
    if (out is TextElement) {
      out = out.copyWith(
          animation: out.animation.copyWith(
        preset: lost.contains(KeyframeChannel.reveal)
            ? TextAnimationPreset.none
            : null,
        exit: lost.contains(KeyframeChannel.close)
            ? TextAnimationPreset.none
            : null,
      ));
    } else if (out is ChartElement) {
      out = out.copyWith(
          animation: out.animation.copyWith(
        preset: lost.contains(KeyframeChannel.reveal)
            ? ChartAnimationPreset.none
            : null,
        exit: lost.contains(KeyframeChannel.close)
            ? ChartAnimationPreset.none
            : null,
      ));
    }

    return next.isEmpty
        ? out.withBase(clearTrack: true)
        : out.withBase(track: next);
  }

  // ------------------------------------------------------------------------
  // Loading and saving
  // ------------------------------------------------------------------------

  /// load replaces the whole session with a document from disk.
  void load(CanvasDocument document, {String? folder, String? name}) {
    pause();
    stopAudio();
    // The empty channels "Add audio" used to leave: a sound with nothing in
    // it, on the canvas as an element. A channel now is only its sounds.
    for (var e in document.elements) {
      if (e is AudioElement && e.clip.timed && e.clip.isEmpty) {
        document = document.removeElement(e.id);
      }
      // A drawing saved while it was being edited, before saving fitted its
      // box: fitted now, so it opens drawn round all of it.
      if (e is VectorElement && e.edited) {
        var fitted = boxedToDrawing(e);
        if (!identical(fitted, e)) document = document.withElement(fitted);
      }
    }
    _document = document;
    this.folder = folder;
    this.name = name;
    _selection = {};
    _backgroundSelected = false;
    _focusedPlayer = null;
    // Opened on the frame everything has arrived by, rather than on nought.
    //
    // A canvas whose elements arrive shows none of them on its first frame,
    // and an empty page reads as a document that has failed to load rather
    // than one that is about to play. Nought for a canvas with no arrivals,
    // which is the same thing said the other way.
    _frame = document.settledFrame;
    _undo.clear();
    _redo.clear();
    _interaction = null;
    _dirty = false;
    // The zoom and the pan go, because both are a position inside the document
    // being replaced and mean nothing in the new one.
    //
    // The fit stays. It is a fact about the reader's screen rather than about
    // any document -- the whole frame on a monitor, the width on a laptop --
    // so resetting it here made "remember how I like the canvas framed" a
    // setting that lasted until the next time a canvas was opened, which is
    // the moment it was most wanted.
    _zoom = 1;
    _pan = const Offset2(0, 0);
    notifyListeners();
  }

  /// _autosave is the pending write, if any.
  Timer? _autosave;

  /// _autosaveDelay is how long the editing has to stop for.
  ///
  /// Long enough that dragging a player across a pitch is one write rather
  /// than sixty, short enough that walking away from the machine mid-thought
  /// does not lose the thought.
  static const Duration _autosaveDelay = Duration(seconds: 3);

  /// scheduleAutosave writes the document out shortly, once the editing stops.
  ///
  /// Only for a document that has been saved at least once, which is the whole
  /// rule: until then there is nowhere to write to, and inventing a filename
  /// would put documents in the library that the reader never asked to keep.
  /// Somebody who opens a preset, plays with it and navigates away should find
  /// nothing new in their files.
  ///
  /// Debounced rather than throttled: each edit pushes the write further out,
  /// so a burst of edits costs one write at the end instead of one every few
  /// seconds throughout.
  void scheduleAutosave() {
    if (name == null || !_dirty) return;
    _autosave?.cancel();
    _autosave = Timer(_autosaveDelay, () {
      _autosave = null;
      if (name != null && _dirty) save();
    });
  }

  /// _toSave is the document as it is written out: as it is, except that a
  /// drawing still being edited is written with its box fitted round it, as
  /// leaving the editing would fit it. Left alone in the editor -- the box
  /// moving under a drawing while it is drawn would move the pencil's
  /// mirror lines with it -- but a document closed mid-edit must not come
  /// back with a box that cuts through the drawing. See _fitEditedVector.
  CanvasDocument get _toSave {
    var e = editingVector;
    if (e == null) return _document;
    var fitted = boxedToDrawing(e);
    return identical(fitted, e) ? _document : _document.withElement(fitted);
  }

  /// save writes back to where this document came from, or nowhere when it has
  /// never been saved.
  Future<bool> save() async {
    _autosave?.cancel();
    _autosave = null;
    var f = folder, n = name;
    if (n == null) return false;
    var ok = await CanvasStorage.save(f ?? "", n, _toSave);
    // Not awaited: tidying the stores is bookkeeping, and a save should not
    // wait on a walk of the whole library to report that it worked. Only what
    // is not an asset goes -- see CanvasLibrary.tidy.
    if (ok) {
      unawaited(CanvasLibrary.tidy(
          open: {..._document.assetIds, ..._document.mediaIds}));
    }
    if (ok) {
      _dirty = false;
      notifyListeners();
    }
    return ok;
  }

  /// saveAs writes to a new place and makes it this document's home.
  Future<bool> saveAs(String folder, String name) async {
    var ok =
        await CanvasStorage.save(folder, name, _toSave.copyWith(title: name));
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
    _disposedForWaveform = true;
    _autosave?.cancel();
    _playback?.cancel();
    _counterTimer?.cancel();
    _video?.removeListener(notifyListeners);
    _video?.dispose();
    _audio?.removeListener(notifyListeners);
    _audio?.dispose();
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

/// TimedLane is one clip on the Channels strip.
class TimedLane {
  final CanvasElement element;

  /// offset is how many frames the clip's timeline is ahead of the scene's:
  /// nought for a clip on this scene, the scene's start in the run for one
  /// that follows the run.
  final int offset;

  /// editable is false for a clip on the master seen from a page: it is
  /// changed on the master, where it lives.
  final bool editable;

  /// scene is which canvas the clip is on: -1 for the master, and otherwise
  /// the scene's place in the list.
  final int scene;

  const TimedLane(this.element,
      {this.offset = 0, this.editable = true, this.scene = -1});

  /// sceneLabel is the scene, as the channel strip names it: M for the
  /// master, S1 for the first scene.
  String get sceneLabel => scene < 0 ? "M" : "S${scene + 1}";

  MediaClip get clip => switch (element) {
        VideoElement v => v.clip,
        AudioElement a => a.clip,
        _ => const MediaClip(),
      };

  /// channelKey is the channel this is on: its own, for a clip with none.
  String get channelKey => clip.channel.isNotEmpty ? clip.channel : element.id;
}

/// TimelineChannel is one channel of the timeline and the sounds on it.
class TimelineChannel {
  final String key;
  final List<TimedLane> lanes;
  const TimelineChannel(this.key, this.lanes);

  TimedLane get first => lanes.first;

  String get name {
    var named = first.clip.channelName;
    return named.isNotEmpty ? named : first.element.name;
  }

  /// mix is the channel's strip, which every sound on it carries.
  ChannelMix get mix => first.clip.mix;

  bool get editable => lanes.any((l) => l.editable);
  bool get video => first.element is VideoElement;

  /// sceneLabel is which canvas the channel's clips are on -- see
  /// TimedLane.sceneLabel.
  String get sceneLabel => first.sceneLabel;

  /// locked is whether every sound on it is locked -- see lockChannel.
  bool get locked => lanes.every((l) => l.element.locked);
}

/// TimelineTool is what a press on a sound does. See timelineTool.
enum TimelineTool { select, knife }

/// timelineHeaderMin and timelineHeaderMax bound the channel strips' column:
/// from the icon alone to everything on it.
const double timelineHeaderMin = 28;
const double timelineHeaderMax = 240;

/// waveformPoints is how finely a sound's shape is read: enough for a lane
/// several screens wide, few enough to draw every frame.
const int waveformPoints = 2400;
