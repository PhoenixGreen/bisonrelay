import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/storage_manager.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_channels.dart';
import 'package:bruig/plugin_system/canvas/ui/scene_strip.dart';
import 'package:bruig/plugin_system/canvas/ui/slots_window.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_view.dart';
import 'package:bruig/plugin_system/canvas/ui/play_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_columns.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/image_timeline.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// canvas_timeline.dart is the strip along the bottom of the canvas: the
// transport, the ruler and playhead, the markers and cues on it, a row of
// keyframes, and the channels under them.
//
// The keyframe row shows one track at a time: a focused team player's, a
// selected path's points, or the selected element's own. Element animation
// is clips now (legacy tracks are converted when a canvas opens, see
// model/motion_convert.dart), shown in the element's rows among the
// channels; the keyframe row is for what still has a track.

/// timelineHeight is the strip's height with no channels showing, the least
/// it can be dragged down to. The room above it is the channels', whatever
/// the timeline is dragged open to: see CanvasTimeline.height.
///
/// Added up rather than written down, and it has to add up to what is
/// drawn: the strip's own padding comes out of the same box, and a total
/// short of the drawing paints the marks outside the widget, where they
/// cannot be clicked.
const double timelineHeight = _transportHeight +
    _stripPadTop +
    _stripGap +
    _stripHeight +
    _stripPadBottom +
    _notesGutter;

/// timelineCollapsedHeight is the timeline dragged down to its play bar
/// alone: the transport and nothing under it, for watching with as little
/// on screen as there can be.
const double timelineCollapsedHeight = 1 + // the border along its top
    _stripPadTop +
    _transportHeight +
    _stripPadBottom +
    _notesGutter -
    _scrollbarHeight;

/// _transportHeight is the play bar: its controls, with no captions over
/// them -- the captions are their hover text. See CanvasControlScope.
const double _transportHeight = playBarHeight;

/// timelineRowsLeast is the shortest the timeline's rows are without a play
/// bar of their own (see CanvasTimeline.showBar): the strip.
const double timelineRowsLeast = timelineHeight - _transportHeight - _stripGap;

/// _stripPadTop is the room above the play bar, so its buttons do not sit
/// hard against the timeline's top edge.
const double _stripPadTop = 4;
const double _stripPadBottom = 6;

/// _stripGap is the room between the play bar and the ruler under it.
const double _stripGap = 8;

/// _markRow is where the keyframes sit inside the strip, and _stripHeight is
/// tall enough for them with air under. Every hit test and the painter read
/// these, so a mark cannot be drawn somewhere the pointer is not looking for
/// it. Markers are flags on the ruler: see _paintMarkers.
const double _markRow = _rulerHeight + 14;

/// _loopBelow is how far under the keyframes the selected element's loop
/// bar runs.
const double _loopBelow = 8;
const double _stripHeight = _markRow + 12;

/// _notesGutter is the empty band kept along the bottom of the strip, clear
/// of the notes button (a 24px wedge in the content area's bottom-left
/// corner), so frame 1 can still start at the strip's left edge.
const double _notesGutter = 20;

/// _flagWidth is how far a marker's pennant reaches from its staff.
const double _flagWidth = 12;

/// _scrollbarHeight is the bar along the bottom that shows, and moves, the
/// stretch of frames on screen. Taken out of the notes gutter, so the total
/// does not change.
const double _scrollbarHeight = 10;

/// _braceHeight is how far down the ruler the loop brace comes.
const double _braceHeight = 7;

/// _BracePart is which part of the loop brace is held: an end, or all of it.
enum _BracePart { start, end, whole }

/// _rulerHeight is the frame numbers and the playhead.
const double _rulerHeight = 30;

/// _markGrabWidth and _markGrabHeight are how close the pointer has to be to
/// a keyframe mark to take hold of it rather than scrub: generous across,
/// since marks crowd on a squeezed timeline, and tall enough to cover the
/// mark and the air either side.
const double _markGrabWidth = 9;
const double _markGrabHeight = 12;

/// _pathDriving is the path that owns a row's keyframes, if one does. A
/// followed element's track is written by the path and rewritten whenever a
/// point moves, so the strip shows nothing for it and says where the timing
/// lives instead. Shared by the strip and the ruler under it.
PathElement? _pathDriving(CanvasController controller) {
  var team = controller.focusedTeam;
  var index = controller.focusedPlayer;
  if (team != null && index != null) {
    return controller.pathDriving(team.id, playerIndex: index);
  }
  var element = controller.selected;
  if (element == null || element is PathElement) return null;
  return controller.pathDriving(element.id);
}

class CanvasTimeline extends StatefulWidget {
  final CanvasController controller;

  /// height is how tall the timeline is, at least timelineHeight: whatever it
  /// has over that is the channels', under the keyframe strip. Dragged from
  /// its top edge, through onResize. See CanvasChannels.
  final double height;
  final ValueChanged<double>? onResize;

  /// showBar is whether the play bar is drawn here, over the rows or under
  /// them: as the timeline is used on its own. The Canvas page draws the bar
  /// itself, along every panel (see CanvasPlayBar), and passes false.
  final bool showBar;

  /// slotsOnly is the timeline showing the slots alone: each row's name
  /// and its slots, with no frames -- the Slots panel where the timeline's
  /// rows are not beside it. See CanvasController.slotsWithRows.
  final bool slotsOnly;

  const CanvasTimeline({
    required this.controller,
    this.height = timelineHeight,
    this.onResize,
    this.showBar = true,
    this.slotsOnly = false,
    super.key,
  });

  @override
  State<CanvasTimeline> createState() => CanvasTimelineState();
}

class CanvasTimelineState extends State<CanvasTimeline> {
  /// shownView and playheadFrame are what the strip is showing and where the
  /// playhead is on it, in the same frames, for tests, since the strip is
  /// painted rather than laid out.
  @visibleForTesting
  TimelineView get shownView => _viewNow;
  @visibleForTesting
  int get playheadFrame => _origin + controller.frame;

  CanvasController get controller => widget.controller;

  /// _dragBand is the pair of frames being dragged as one, or null: a chart's
  /// entrance is two keyframes that are meaningless apart, so the bar joining
  /// them moves both. See KeyframeBand.
  List<int>? _dragBand;

  /// _pressedBand is the band the pointer went down on, found on the press
  /// for the same reason as _pressedFrame.
  List<int>? _pressedBand;

  /// _bandAnchor is the frame the band drag last acted from.
  int _bandAnchor = 0;

  /// _dragKey is the frame of the mark being dragged along the ruler, or null
  /// while the drag is an ordinary scrub.
  int? _dragKey;

  /// _pressedFrame is the mark under the pointer when it went down: a
  /// horizontal drag is only recognised once the pointer has travelled, by
  /// which time its reported start is past what it was aimed at. See
  /// onHorizontalDragDown.
  int? _pressedFrame;

  /// _pressedLoop and _dragLoop are the end of the loop's bar a press is on
  /// and a drag is moving (false its start, true its end), or null.
  bool? _pressedLoop;
  bool? _dragLoop;

  /// _pressedBrace and _dragBrace are the part of the loop brace (the control
  /// bar's Loop, along the top of the ruler) a press is on and the one being
  /// dragged; _braceFrom where the drag took hold, and _braceWas the loop
  /// then. See _braceAt.
  _BracePart? _pressedBrace;
  _BracePart? _dragBrace;
  int _braceFrom = 0;
  (int, int) _braceWas = (0, 1);

  /// _selectedKeys are the frames of the marks that have been clicked. Shift
  /// picks up another; clicking the bar between a pair picks up both ends.
  /// Cleared whenever the row changes underneath it, so Delete never lands on
  /// a mark that is not there.
  final Set<int> _selectedKeys = {};

  /// _copied is what was last copied: each keyframe, and how far it sits after
  /// the first of them, so a paste at the playhead keeps the run's shape.
  List<(int, Keyframe)> _copied = const [];

  /// _shiftHeld is whether a click adds to the selection rather than starting
  /// a new one.
  bool get _shiftHeld => HardwareKeyboard.instance.isShiftPressed;

  /// _focus is what lets Delete reach this strip. Requested when a mark is
  /// clicked, because a mark is not a widget and cannot take focus itself.
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    controller.addListener(_onChanged);
    _readSettings();
  }

  static const _headerKey = "canvasTimelineHeader";
  static const _slotsKey = "canvasTimelineSlotsColumn";

  /// _barAbove and _barBelow are the play bar drawn here, over the rows or
  /// under them: see CanvasTimeline.showBar and CanvasController.barBelow.
  bool get _barAbove => widget.showBar && !controller.barBelow;
  bool get _barBelow => widget.showBar && controller.barBelow;

  /// _least is the shortest the timeline is with its rows: the strip, and
  /// the bar where it is drawn here.
  double get _least => widget.showBar ? timelineHeight : timelineRowsLeast;

  /// _stripTop is where the keyframe strip starts, down the timeline: under
  /// the play bar, or, with the bar below or elsewhere, at the top.
  double get _stripTop =>
      _stripPadTop + (_barAbove ? _transportHeight + _stripGap : 0);

  /// _overBar is whether [dy], down the timeline, is on the play bar, which
  /// scrolls sideways itself, so the wheel there is not the frames'.
  bool _overBar(double dy) {
    if (!widget.showBar) return false;
    if (!_barBelow) return dy < _stripTop;
    var height = math.max(timelineCollapsedHeight, widget.height) +
        (_showScenes ? sceneStripHeight : 0);
    var bottomPad = _stripPadBottom + _notesGutter - _scrollbarHeight;
    return dy > height - bottomPad - _transportHeight - _stripGap;
  }

  Future<void> _readSettings() async {
    var header = double.tryParse(await StorageManager.readString(_headerKey));
    var slots = double.tryParse(await StorageManager.readString(_slotsKey));
    if (!mounted) return;
    if (header != null) controller.headerWidth = header;
    if (slots != null) controller.slotsColumn = slots;
  }

  @override
  void dispose() {
    _focus.dispose();
    controller.removeListener(_onChanged);
    super.dispose();
  }

  /// _zoomSeen is the last zoom the play bar's menu asked for that this has
  /// taken up: see CanvasController.askTimelineZoom.
  int _zoomSeen = -1;

  /// _bodyWidth is how wide the timeline was last laid out, for the slots
  /// shown alone to fill.
  double _bodyWidth = 0;

  /// _slotsW is the slots' column here: beside the rows, as the controller
  /// has it, or, the slots shown alone, as many as fit.
  double get _slotsW => widget.slotsOnly
      ? math.min(
          controller.slotsContent,
          math.max(CanvasController.slotsColumnMin,
              _bodyWidth - 20 - controller.headerWidth))
      : controller.slotsWidth;

  /// _leftW is everything left of the frames: the strips, then the slots.
  double get _leftW => controller.headerWidth + _slotsW;

  void _onChanged() {
    if (!mounted) return;
    if (_zoomSeen < 0) _zoomSeen = controller.timelineZoomAsked;
    if (controller.timelineZoomAsked != _zoomSeen) {
      _zoomSeen = controller.timelineZoomAsked;
      var factor = controller.timelineZoomFactor;
      factor == 0 ? _setView(TimelineView.whole(_total)) : _zoomBy(factor);
    }
    // A mark that is no longer on this row cannot stay selected, or Delete
    // would take a keyframe the reader never picked.
    _selectedKeys.removeWhere((at) => _targetTrack?.keyAt(at) == null);
    setState(() {});
  }

  /// _frameAt turns a horizontal position into a frame number of the scene
  /// being edited.
  int _frameAt(double x, double width) =>
      _sceneView.frameAt(x, width, controller.document.frames);

  double _xFor(int frame, double width) => _sceneView.centreOf(frame, width);

  /// _marquee is the stretch being dragged out over the keyframes to select
  /// them, as two x positions, or null; _pressedMarquee is whether the press
  /// was on empty strip below the ruler, where a drag selects rather than
  /// scrubs.
  (double, double)? _marquee;
  bool _pressedMarquee = false;

  /// _narrowTo is a mark pressed while it was one of several picked: a click
  /// on it picks it alone, a drag from it moves them all. Which it was is
  /// only known when the pointer comes up.
  int? _narrowTo;
  List<int>? _narrowBand;

  /// _pressX is where the pointer went down on the strip. A drag is only
  /// recognised some way past it, so a drag that starts a box or moves a
  /// selection measures from here, not from where it was recognised.
  double _pressX = 0;

  /// _lastHead is where the playhead was on the last build, in the frames
  /// laid out (see build, which follows it when it moves).
  int? _lastHead;

  /// _scrubTo puts the playhead under [x]. Where the timeline runs along
  /// every scene, a point over another scene goes to that scene, at the frame
  /// of it the ruler says.
  void _scrubTo(double x, double width) {
    var document = controller.document;
    if (_runs && !document.editingMaster) {
      controller.goToRunFrame(_viewNow.frameAt(x, width, _total));
      return;
    }
    controller.frame = _frameAt(x, width);
  }

  /// _runs is whether the timeline is laid along the whole run rather than
  /// the one scene, as while Play runs every scene. The ruler and the scene
  /// strip are then one scale, and the scene being edited is its stretch of
  /// the run. See CanvasSceneStrip.
  bool get _runs => controller.playAll && controller.document.hasScenes;

  /// _origin is where the scene being edited starts in the run, in frames:
  /// nought unless the timeline runs, and on the master, whose frames are the
  /// run's already.
  int get _origin {
    var document = controller.document;
    if (!_runs || document.editingMaster) return 0;
    return document.startOfScene(document.at);
  }

  /// _total is how many frames the timeline is laid along: the run where it
  /// runs, otherwise the scene, and past either to the end of a clip that goes
  /// on longer. See CanvasController.timelineReach.
  int get _total => _runs
      ? math.max(controller.document.sequenceFrames,
          _origin + controller.timelineReach)
      : controller.timelineReach;

  /// _sceneView is the view in the scene's own frames: the run's, moved back
  /// by where the scene starts, so the keyframes, markers and channels sit
  /// under their stretch of the ruler.
  TimelineView get _sceneView =>
      TimelineView(_viewNow.first - _origin, _viewNow.span);

  /// _sceneGap is the room the scene strip takes under the keyframes, while
  /// it shows, and _scenesTop where its boxes start: the first row over the
  /// channels.
  double get _sceneGap => _showScenes ? sceneStripHeight : 0;
  double get _scenesTop => _keysRoom - 1 + sceneStripLead;

  /// _keysShown is whether the keyframe row is under the ruler, and _keysRoom
  /// the strip's height with it or without (the ruler alone, with its
  /// playhead, markers and cues).
  bool get _keysShown => controller.keyframesShown;
  double get _keysRoom => _keysShown ? _stripHeight : _rulerHeight + 2;

  /// _ranRun is whether the last build ran along the whole run, so a view
  /// zoomed in one way of counting is not kept for the other.
  bool _ranRun = false;

  /// _view is the stretch of frames zoomed to, or null for all of them,
  /// which then follows the timeline's length as it changes. _viewNow is the
  /// one this build is drawn with. See TimelineView.
  TimelineView? _view;
  TimelineView _viewNow = const TimelineView(0, 1);

  /// _viewSetSeen is the last view put back from outside that this has taken
  /// up: see CanvasController.timelineView.
  int _viewSetSeen = -1;

  /// _setView zooms or scrolls. All of it is stored as null, so a timeline
  /// made longer afterwards is still shown whole.
  void _setView(TimelineView next) {
    var frames = _total;
    var fitted = next.fitted(frames);
    setState(() => _view = fitted.isWhole(frames) ? null : fitted);
  }

  /// _zoomBy zooms in by [factor] (out, below one) about the playhead.
  void _zoomBy(double factor) => _setView(
      _viewNow.zoomed(factor, _origin + controller.frame + 0.5, _total));

  /// _laneWidth is the width the frames are laid across: the body, less its
  /// padding and the strip column.
  double _laneWidth(double bodyWidth) => math.max(1, bodyWidth - 20 - _leftW);

  /// _overSide is whether [dx], across the timeline, is over the mixer
  /// beside the rows or the slots, which scroll themselves.
  bool _overSide(double dx) {
    var x = dx - 10;
    return x < 0 || (_slotsW > 0 && x >= controller.headerWidth && x < _leftW);
  }

  /// _onSignal is the wheel: with Ctrl or Cmd it zooms about the pointer;
  /// sideways, with Shift, or anywhere over the keyframe strip, it scrolls
  /// along the frames; plainly, over the channels, it is left to them.
  void _onSignal(PointerSignalEvent event, double bodyWidth) {
    if (event is! PointerScrollEvent) return;
    var keys = HardwareKeyboard.instance;
    var zoom = keys.isControlPressed || keys.isMetaPressed;
    var local = event.localPosition;
    var stripTop = _stripTop;
    var overStrip =
        local.dy >= stripTop && local.dy <= stripTop + _keysRoom + _sceneGap;
    // Not over the play bar, the mixer or the slots, which scroll sideways
    // themselves.
    if (_overBar(local.dy) || _overSide(local.dx)) return;
    var delta = event.scrollDelta;
    var sideways = keys.isShiftPressed || delta.dx.abs() > delta.dy.abs();
    if (!zoom && !sideways && !overStrip) return;
    // Scrolling along is the reader's choice (see controller.trackpadScrolls); zooming
    // asks for a key held down, so it is never done by accident.
    if (!zoom && !controller.trackpadScrolls) return;
    var frames = _total;
    var width = _laneWidth(bodyWidth);
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      var d = (e as PointerScrollEvent).scrollDelta;
      if (zoom) {
        var x = local.dx - 10 - _leftW;
        var around = _viewNow.first + _viewNow.framesPer(x, width);
        _setView(_viewNow.zoomed(math.exp(-d.dy / 300), around, frames));
      } else {
        var by = d.dx != 0 ? d.dx : d.dy;
        _setView(_viewNow.scrolled(_viewNow.framesPer(by, width), frames));
      }
    });
  }

  /// _pinch is the trackpad's last scale, so each update zooms by how much
  /// the fingers moved since the one before.
  double _pinch = 1;

  void _onPanZoom(PointerPanZoomUpdateEvent event, double bodyWidth) {
    // Not over the play bar, the mixer or the slots: see _onSignal.
    if (_overBar(event.localPosition.dy) || _overSide(event.localPosition.dx)) {
      return;
    }
    var frames = _total;
    var width = _laneWidth(bodyWidth);
    var next = _viewNow;
    if ((event.scale - _pinch).abs() > 0.001) {
      var x = event.localPosition.dx - 10 - _leftW;
      var around = next.first + next.framesPer(x, width);
      next = next.zoomed(event.scale / _pinch, around, frames);
      _pinch = event.scale;
    }
    var pan = event.panDelta;
    // Sideways only: up and down belong to the channels' own list. And only
    // when asked for: see controller.trackpadScrolls.
    if (controller.trackpadScrolls && pan.dx.abs() > pan.dy.abs()) {
      next = next.scrolled(-next.framesPer(pan.dx, width), frames);
    }
    if (next != _viewNow) _setView(next);
  }

  /// _targetName is what the keyframe controls are pointed at, for the
  /// tooltips: a player when one has been clicked, otherwise the element.
  String? get _targetName {
    var team = controller.focusedTeam;
    var index = controller.focusedPlayer;
    if (team != null && index != null && index < team.players.length) {
      var spot = team.players[index];
      var who = spot.name.isNotEmpty ? spot.name : "#${spot.number}";
      return "$who (${team.name})";
    }
    return controller.selected?.name;
  }

  /// _targetTrack is the track the keyframe controls read and write. A player
  /// has no id and cannot be selected, so the focused player is what says the
  /// controls are about them; everything goes through this rather than
  /// controller.selected, so a player's keyframes behave as an element's do.
  ElementTrack? get _targetTrack {
    var team = controller.focusedTeam;
    var index = controller.focusedPlayer;
    if (team != null && index != null && index < team.players.length) {
      return team.players[index].track;
    }
    // A path's marks are its points. Its own track is empty (what moves is
    // the follower, whose keyframes the path writes), so without this a
    // selected path would show a bare strip.
    var path = _selectedPath;
    if (path != null) {
      return ElementTrack([for (var n in path.nodes) Keyframe(frame: n.frame)]);
    }
    // Nothing for whatever a path is driving: those marks belong to the
    // route, and the copy shown would be overwritten.
    if (_drivingPath != null) return null;
    return controller.selected?.track;
  }

  /// _selectedPath is the selected element when it is a path.
  PathElement? get _selectedPath {
    var element = controller.selected;
    return element is PathElement ? element : null;
  }

  PathElement? get _drivingPath => _pathDriving(controller);

  /// _pressedFlag and _dragFlag are the frame of the flag pressed on the
  /// ruler, and of the one being dragged: see _flagAt.
  int? _pressedFlag;
  int? _dragFlag;

  /// _flagAt is the frame of the flag under [local], or null: on the ruler,
  /// from the staff to the end of the pennant.
  int? _flagAt(Offset local, double width) {
    if (local.dy > _rulerHeight) return null;
    for (var a in controller.document.actions) {
      var x = _xFor(a.frame, width);
      if (local.dx >= x - 5 && local.dx <= x + _flagWidth + 2) return a.frame;
    }
    return null;
  }

  /// _moveAction moves the flag on [from] to [to], and the playhead with it
  /// so its settings stay the ones on screen. Refused onto a frame that has
  /// one already: two on a frame is one of them lost.
  bool _moveAction(int from, int to) {
    if (from == to) return false;
    var document = controller.document;
    if (document.actions.any((a) => a.frame == to)) return false;
    var last = document.frames - 1;
    if (to < 0 || to > last) return false;
    controller.apply(
        document.copyWith(actions: [
          for (var a in document.actions)
            a.frame == from ? a.copyWith(frame: to) : a,
        ]),
        transient: true);
    controller.frame = to;
    return true;
  }

  /// _retime moves a mark from one frame to another: one entry point for the
  /// three things a mark can belong to, since the ruler dragging it does not
  /// know which it holds.
  void _retime(int from, int to) {
    if (from == to) return;

    var path = _selectedPath;
    if (path != null) {
      var index = path.nodes.indexWhere((n) => n.frame == from);
      if (index < 0) return;
      var next = path.retimeNode(index, to);
      controller.replaceElement(next);
      // Re-baked, or the follower would go on running the old timing while
      // the point sits somewhere else.
      controller.applyPathFollow(next);
      return;
    }

    var track = _targetTrack;
    var key = track?.keyAt(from);
    if (track == null || key == null) return;
    // Not through _removeTargetKey and the like, which route a path to its
    // points; a path has been dealt with above.
    var moved = track.withoutFrame(from).withKey(key.copyWith(frame: to));
    var team = controller.focusedTeam;
    var index = controller.focusedPlayer;
    if (team != null && index != null) {
      controller.replaceElement(
          team.withPlayer(index, team.players[index].copyWith(track: moved)));
      return;
    }
    var element = controller.selected;
    if (element != null) {
      controller.replaceElement(element.withBase(track: moved));
    }
  }

  /// _copyKeys puts the selected keyframes on this strip's own clipboard, not
  /// the system's: they are pasted elsewhere on this timeline a moment later.
  /// Relative to the first, so the run keeps its shape wherever it lands.
  void _copyKeys() {
    var track = _targetTrack;
    if (track == null || _selectedKeys.isEmpty) return;
    var frames = _selectedKeys.toList()..sort();
    var first = frames.first;
    var copied = <(int, Keyframe)>[];
    for (var at in frames) {
      var key = track.keyAt(at);
      if (key != null) copied.add((at - first, key));
    }
    if (copied.isEmpty) return;
    setState(() => _copied = copied);
    _say(copied.length == 1
        ? "Keyframe copied. Move the playhead and paste it."
        : "${copied.length} keyframes copied. Move the playhead and paste "
            "them.");
  }

  /// _pasteKeys lays the copied run down with its first keyframe on the
  /// playhead. Refused rather than merged where it would land on keyframes
  /// already there: two on one frame is one, and eating one end of a pair
  /// leaves half an animation.
  void _pasteKeys() {
    var track = _targetTrack;
    if (track == null || _copied.isEmpty) return;
    var at = controller.frame;
    var last = controller.document.frames - 1;

    var wanted = [for (var (offset, _) in _copied) at + offset];
    if (wanted.last > last) {
      _say("There is not room for that before the end of the timeline.");
      return;
    }
    var taken = [
      for (var frame in wanted)
        if (track.keyAt(frame) != null) frame,
    ];
    if (taken.isNotEmpty) {
      _say(taken.length == 1
          ? "There is already a keyframe on frame ${taken.first}. Keyframes "
              "cannot sit on top of each other -- move the playhead clear of "
              "the ones that are there."
          : "Frames ${taken.join(", ")} already have keyframes. Keyframes "
              "cannot sit on top of each other -- move the playhead clear of "
              "the ones that are there.");
      return;
    }

    controller.beginInteraction();
    var next = track;
    for (var (offset, key) in _copied) {
      next = next.withKey(key.copyWith(frame: at + offset));
    }
    _writeTrack(next);
    controller.endInteraction();
    setState(() {
      _selectedKeys
        ..clear()
        ..addAll(wanted);
    });
  }

  /// _writeTrack puts a whole track back on whatever the strip is pointed at.
  void _writeTrack(ElementTrack track) {
    var team = controller.focusedTeam;
    var index = controller.focusedPlayer;
    if (team != null && index != null) {
      controller.replaceElement(
          team.withPlayer(index, team.players[index].copyWith(track: track)));
      return;
    }
    var element = controller.selected;
    if (element != null) {
      controller.replaceElement(element.withBase(track: track));
    }
  }

  /// _say puts a message where the reader is looking, which for a refusal is
  /// the only way they learn why nothing happened.
  void _say(String message) {
    if (!mounted) return;
    SnackBarModel.of(context, listen: false).success(message);
  }

  /// _pathKeyframe adds or removes a point when a path is selected: for a path
  /// the diamond's "something here" is a point. Not through setKeyframe, which
  /// would write a pose onto the path's own track, where nothing reads it.
  bool _pathKeyframe({required bool add, int? at}) {
    var path = _selectedPath;
    if (path == null) return false;
    PathElement next;
    if (add) {
      next = path.insertAtFrame(controller.frame);
    } else {
      var index = path.nodeIndexAtFrame(at ?? controller.frame);
      next = index == null ? path : path.withoutNode(index);
    }
    if (identical(next, path)) return true;
    controller.replaceElement(next);
    controller.applyPathFollow(next);
    return true;
  }

  void _removeTargetKey(int frame) {
    if (_pathKeyframe(add: false, at: frame)) return;
    var team = controller.focusedTeam;
    var index = controller.focusedPlayer;
    if (team != null && index != null) {
      controller.removePlayerKeyframe(team.id, index, frame);
      return;
    }
    var element = controller.selected;
    if (element != null) controller.removeKeyframe(element.id, frame);
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var document = controller.document;
    var actionHere =
        document.actions.where((a) => a.frame == controller.frame).firstOrNull;
    var keyHere = _targetTrack?.keyAt(controller.frame);
    var target = _targetName;

    // A view put back (the canvas opened as it was left) taken up. The
    // frames on screen are all of them or the stretch zoomed to, to the end
    // of the longest clip, and along every scene while Play runs them all.
    if (controller.timelineViewSet != _viewSetSeen) {
      _viewSetSeen = controller.timelineViewSet;
      _view = controller.timelineView;
    }
    if (_runs != _ranRun) {
      _ranRun = _runs;
      _view = null;
    }
    var frames = _total;
    var view = _view?.fitted(frames) ?? TimelineView.whole(frames);
    // Kept up with the playhead whenever it moves (played, stepped, or taken
    // to another scene) so it is never off the strip. Not when it has stayed
    // put: a view scrolled away from a still playhead is on purpose.
    var head = _origin + controller.frame;
    var moved = head != _lastHead &&
        (head < view.first || head > view.first + view.span);
    // Playing, it keeps up only while Follow is on: off, the view stays
    // where it was put. Moved by hand, it always keeps up.
    if (_view != null &&
        (controller.playing ? controller.followPlayhead : moved)) {
      view = view.following(head, frames);
      _view = view;
    }
    _lastHead = head;
    _viewNow = view;
    // Kept, for the next visit: see CanvasController.canvasView.
    controller.timelineView = _view;

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Stack(children: [
        LayoutBuilder(
          builder: (context, box) {
            _bodyWidth = box.maxWidth;
            return Listener(
              onPointerSignal: (e) => _onSignal(e, box.maxWidth),
              onPointerPanZoomStart: (_) => _pinch = 1,
              onPointerPanZoomUpdate: (e) => _onPanZoom(e, box.maxWidth),
              child: TimelineColumns(
                slotsWidth: _slotsW,
                headerWidth: controller.headerWidth,
                lanes: !widget.slotsOnly,
                child: _body(
                    context, theme, document, actionHere, keyHere, target),
              ),
            );
          },
        ),
        // The line between the slots and the time, where the slots are out
        // beside the rows: dragged, the slots' column is wider or narrower,
        // the slots themselves one size.
        if (!_collapsed && !widget.slotsOnly && _slotsW > 0)
          Positioned(
            left: 10 + _leftW - 5,
            top: _stripTop,
            bottom: _barBelow
                ? _stripPadBottom +
                    _notesGutter -
                    _scrollbarHeight +
                    _transportHeight +
                    _stripGap
                : 0,
            width: 5,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                supportedDevices: timelinePointers,
                key: const ValueKey("slotsGrip"),
                behavior: HitTestBehavior.opaque,
                // From the width seen: the column may be wider than the
                // slots in it, which grow into it.
                onHorizontalDragStart: (_) => controller.slotsColumn = _slotsW,
                onHorizontalDragUpdate: (d) =>
                    controller.slotsColumn += d.delta.dx,
                onHorizontalDragEnd: (_) => StorageManager.saveString(
                    _slotsKey, controller.slotsColumn.toString()),
              ),
            ),
          ),
        // The line between the channel strips and what is right of them --
        // the slots, or the frames: dragged, the strips are wider or
        // narrower, down to icons.
        if (!_collapsed)
          Positioned(
            // On the strips' side of the line only, clear of the fade handle of a
            // sound starting on frame one.
            left: 10 + controller.headerWidth - 5,
            top: _stripTop,
            bottom: _barBelow
                ? _stripPadBottom +
                    _notesGutter -
                    _scrollbarHeight +
                    _transportHeight +
                    _stripGap
                : 0,
            width: 5,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                supportedDevices: timelinePointers,
                key: const ValueKey("headerGrip"),
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (d) =>
                    controller.headerWidth += d.delta.dx,
                onHorizontalDragEnd: (_) => StorageManager.saveString(
                    _headerKey, controller.headerWidth.toString()),
              ),
            ),
          ),
        // The top edge is a grip: dragged up, the timeline opens room for the
        // channels under the keyframe strip; dragged down, it closes it.
        if (widget.onResize != null)
          Positioned(
            key: const ValueKey("timelineGrip"),
            top: 0,
            left: 0,
            right: 0,
            height: 6,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpDown,
              child: GestureDetector(
                supportedDevices: timelinePointers,
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (d) {
                  _gripFrom = d.globalPosition.dy;
                  _gripHeight = widget.height;
                },
                onVerticalDragUpdate: (d) => widget
                    .onResize!(_gripHeight + _gripFrom - d.globalPosition.dy),
              ),
            ),
          ),
      ]),
    );
  }

  /// _gripFrom and _gripHeight are where a drag of the top edge began and how
  /// tall the timeline was then, measured from there rather than by adding up
  /// the drag's steps: the first few pixels of a drag never arrive as one.
  double _gripFrom = 0, _gripHeight = timelineHeight;

  /// _cueLaunches is a launch for each cue over the slots beside the rows:
  /// the whole row, every element's and channel's, from the next bar.
  Widget _cueLaunches(ThemeNotifier theme) {
    var colors = theme.colors;
    return Container(
      width: _slotsW,
      decoration: BoxDecoration(
          border: Border(right: BorderSide(color: colors.outlineVariant))),
      // Along with the slots under it: see slots_window.dart. At its end,
      // Stop all (Ken), where it stays as the cues scroll.
      child: Row(children: [
        Expanded(
          child: slotsScroller(
            controller,
            Padding(
                padding: const EdgeInsets.fromLTRB(3, 4, 2, 4),
                child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < controller.slotsShown; i++) ...[
                        if (i > 0) const SizedBox(width: 3),
                        SizedBox(
                          width: CanvasController.slotCellWidth,
                          height: 20,
                          child: Material(
                            color: controller.sceneLaunched == i
                                ? colors.primaryContainer
                                : colors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(3),
                            child: InkWell(
                              key: ValueKey("cueLaunch-$i"),
                              borderRadius: BorderRadius.circular(3),
                              onTap: () => controller.launchScene(i),
                              child: Row(children: [
                                Icon(Icons.play_arrow,
                                    size: 12, color: colors.onSurface),
                                Expanded(
                                  child: Text(
                                      controller.session.scenes[i].isEmpty
                                          ? "${i + 1}"
                                          : controller.session.scenes[i],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          color: colors.onSurface)),
                                ),
                              ]),
                            ),
                          ),
                        ),
                      ],
                    ])),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 4, 3, 4),
          child: Tooltip(
            message: "Stop all clips, on the next bar",
            child: Material(
              color: controller.anyClipPlaying
                  ? colors.primaryContainer
                  : colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(3),
              child: InkWell(
                key: const ValueKey("stopAllClips"),
                borderRadius: BorderRadius.circular(3),
                onTap: controller.stopAllClips,
                child: SizedBox(
                  width: 22,
                  height: 20,
                  child: Icon(Icons.stop, size: 13, color: colors.onSurface),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  /// _stripHeader is the column beside the keyframe strip, the width of the
  /// channels' strips under it: the zoom, and what each row of marks is.
  Widget _stripHeader(ThemeNotifier theme, String? target) {
    var colors = theme.colors;
    var muted = TextStyle(fontSize: 10, color: colors.onSurfaceVariant);
    var frames = _total;
    var whole = _viewNow.isWhole(frames);
    // Big enough to hit. The show-and-hide pair are a little narrower than
    // the zoom buttons, so all six fit the column as it starts.
    Widget zoom(String key, IconData icon, VoidCallback? onTap,
            {bool active = false, double width = 24}) =>
        InkResponse(
          key: ValueKey(key),
          radius: 14,
          onTap: onTap,
          child: SizedBox(
            width: width,
            height: 24,
            child: Icon(icon,
                size: 19,
                color: onTap == null
                    ? colors.onSurfaceVariant.withValues(alpha: 0.35)
                    : active
                        ? colors.primary
                        : colors.onSurfaceVariant),
          ),
        );
    // Narrowed, the labels go and the icons stay.
    var named = controller.headerWidth >= 64;
    return Container(
      width: controller.headerWidth,
      padding: EdgeInsets.only(left: 4, right: named ? 8 : 2),
      decoration: BoxDecoration(
          border: Border(right: BorderSide(color: colors.outlineVariant))),
      child: Stack(children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: _rulerHeight,
          // Narrowed, it keeps what it has room for: zoom out and in first,
          // then the one button.
          child: Row(children: [
            if (controller.headerWidth >= 60)
              zoom("timelineZoomOut", Icons.zoom_out,
                  whole ? null : () => _zoomBy(0.5)),
            if (controller.headerWidth >= 100 ||
                (controller.headerWidth < 60 && controller.headerWidth >= 34))
              zoom("timelineZoomFit", Icons.fit_screen_outlined,
                  whole ? null : () => _setView(TimelineView.whole(frames))),
            // Every channel a size taller, round to the least again.
            if (controller.headerWidth >= 124)
              Tooltip(
                message: "Channel height: "
                    "${const ["small", "medium", "large"][controller.laneSize]}"
                    " -- click for the next",
                child: zoom(
                    "timelineLaneHeight",
                    const [
                      Icons.density_small,
                      Icons.density_medium,
                      Icons.density_large
                    ][controller.laneSize],
                    controller.nextLaneSize),
              ),
            // The keyframe row, shown or hidden for room.
            if (controller.headerWidth >= 130)
              Tooltip(
                message:
                    _keysShown ? "Hide the keyframes" : "Show the keyframes",
                child: zoom(
                    "keyframesShown",
                    _keysShown ? Icons.diamond : Icons.diamond_outlined,
                    () => controller.keyframesShown = !_keysShown,
                    active: _keysShown,
                    width: 20),
              ),
            if (controller.headerWidth >= 60)
              zoom(
                  "timelineZoomIn",
                  Icons.zoom_in,
                  _viewNow.span <= math.min(timelineMinSpan, frames) + 0.01
                      ? null
                      : () => _zoomBy(2)),
            const Spacer(),
            if (!whole && controller.headerWidth >= 186)
              Text(
                  "${(frames / _viewNow.span).toStringAsFixed(frames / _viewNow.span < 10 ? 1 : 0)}×",
                  style: muted),
          ]),
        ),
        if (_showScenes)
          Positioned(
            left: 0,
            right: 0,
            top: _scenesTop,
            height: sceneBoxHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                named
                    ? "Scenes ${controller.scenes.length}"
                    : "${controller.scenes.length}",
                key: const ValueKey("sceneStripLabel"),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: muted,
              ),
            ),
          ),
        if (_keysShown)
          Positioned(
            left: 0,
            right: 0,
            top: _markRow - 8,
            height: 16,
            child: Row(children: [
              // A drawing's shapes (none, the one picked, or all of them) on lanes of
              // their own under these keyframes, and a picture's layers.
              if (vectorLanesFor(controller) != null ||
                  imageLanesFor(controller) != null)
                InkResponse(
                  key: const ValueKey("vectorLanesToggle"),
                  radius: 12,
                  onTap: () =>
                      controller.vectorLanes = controller.vectorLanes.next,
                  child: Tooltip(
                    message: imageLanesFor(controller) != null
                        ? imageLanesLabel(controller.vectorLanes.next)
                        : controller.vectorLanes.next.label,
                    child: Icon(
                        switch (controller.vectorLanes) {
                          VectorLanes.none => Icons.chevron_right,
                          VectorLanes.picked => Icons.expand_more,
                          VectorLanes.all => Icons.unfold_more,
                        },
                        size: 14,
                        color: controller.vectorLanes == VectorLanes.none
                            ? colors.onSurfaceVariant
                            : colors.primary),
                  ),
                )
              else
                Icon(Icons.diamond_outlined,
                    size: 11, color: colors.onSurfaceVariant),
              if (named) ...[
                const SizedBox(width: 4),
                Expanded(
                  child: Text(target ?? "Keyframes",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: muted.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface)),
                ),
              ],
            ]),
          ),
      ]),
    );
  }

  /// _collapsed is the timeline dragged down to its play bar.
  bool get _collapsed => widget.height < _least - 0.5;

  /// _showScenes is whether the scene strip is over the channels: while Play
  /// runs every scene, so what is playing, and how long each scene is, can be
  /// seen and changed as it plays. The timeline grows by the strip rather than
  /// taking it from the channels. See CanvasSceneStrip.
  bool get _showScenes => _runs && !_collapsed;

  Widget _body(
      BuildContext context,
      ThemeNotifier theme,
      CanvasDocument document,
      TimelineAction? actionHere,
      Keyframe? keyHere,
      String? target) {
    // The play bar, where it is drawn here: over the timeline, or under it.
    var bar = CanvasPlayBar(controller: controller);
    // Everything under the bar: the strip, the channels and the scroll bar.
    var rows = <Widget>[
      if (!_collapsed)
        SizedBox(
          // Less the border along the timeline's top, which comes out of the
          // same height.
          height: _keysRoom - 1 + _sceneGap,
          // A firm line under the keyframes, so the channels scrolling up under
          // it do not seem to vanish into the strip.
          child: Container(
            foregroundDecoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: theme.colors.outline.withValues(alpha: 0.8)))),
            child: Row(children: [
              _stripHeader(theme, target),
              // Over the slots beside the rows: a launch for each cue.
              if (_slotsW > 0) _cueLaunches(theme),
              if (widget.slotsOnly)
                const Spacer()
              else
                Expanded(
                    child: LayoutBuilder(
                  builder: (context, constraints) => Stack(children: [
                    GestureDetector(
                      supportedDevices: timelinePointers,
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        // The brace is switched on the release, and leaves playing alone: a
                        // loop is set while listening.
                        if (_braceAt(
                                details.localPosition, constraints.maxWidth) !=
                            null) {
                          return;
                        }
                        controller.pause();
                        // Selected on the press and the playhead moved on the release: moved
                        // on the press, it would jump at the start of every drag. A drag
                        // never reaches onTapUp.
                        var mark = _keyframeAt(
                            details.localPosition, constraints.maxWidth);
                        var band = mark != null
                            ? null
                            : _bandAt(
                                details.localPosition, constraints.maxWidth);
                        setState(() {
                          _narrowTo = null;
                          _narrowBand = null;
                          if (mark != null &&
                              !_shiftHeld &&
                              _selectedKeys.length > 1 &&
                              _selectedKeys.contains(mark)) {
                            // Pressed on one of several picked: it may be the start of dragging
                            // them all, so they stay picked. A click picks this one alone; see
                            // onTapUp.
                            _narrowTo = mark;
                          } else if (mark != null) {
                            // Shift adds to the selection; an ordinary click starts
                            // a new one.
                            if (!_shiftHeld) _selectedKeys.clear();
                            if (!_selectedKeys.add(mark) && _shiftHeld) {
                              _selectedKeys.remove(mark);
                            }
                          } else if (band != null &&
                              !_shiftHeld &&
                              _selectedKeys.length > band.length &&
                              band.every(_selectedKeys.contains)) {
                            // The bar of a pair that is part of a bigger selection: kept, so
                            // dragging it drags them all.
                            _narrowBand = band;
                          } else if (band != null) {
                            // Both ends: the bar says the two belong together.
                            if (!_shiftHeld) _selectedKeys.clear();
                            _selectedKeys.addAll(band);
                          } else {
                            _selectedKeys.clear();
                          }
                        });
                      },
                      onTapUp: (details) {
                        // Focus is asked for here rather than on the press: the press is
                        // followed by the framework handing focus to the enclosing scope,
                        // and without focus the strip never sees Delete, copy or paste.
                        if (_narrowTo case var only?) {
                          setState(() => _selectedKeys
                            ..clear()
                            ..add(only));
                          _narrowTo = null;
                        }
                        if (_narrowBand case var pair?) {
                          setState(() => _selectedKeys
                            ..clear()
                            ..addAll(pair));
                          _narrowBand = null;
                        }
                        if (_selectedKeys.isNotEmpty) {
                          FocusScope.of(context).requestFocus(_focus);
                        }
                        // A click after all. A mark puts the playhead on itself; anywhere else
                        // scrubs. A click on the brace switches the loop off, as Ableton's
                        // does; the Loop button puts it back.
                        if (_braceAt(
                                details.localPosition, constraints.maxWidth) !=
                            null) {
                          controller.looping = !controller.looping;
                          return;
                        }
                        var mark = _keyframeAt(
                            details.localPosition, constraints.maxWidth);
                        if (mark != null) {
                          controller.frame = mark;
                        } else {
                          _scrubTo(
                              details.localPosition.dx, constraints.maxWidth);
                        }
                      },
                      // A drag that starts on a mark retimes that mark; anywhere else it
                      // scrubs, decided once at the start. The mark is found on the press,
                      // not the drag start: a horizontal drag is only recognised after about
                      // eighteen pixels, past whatever it was aimed at.
                      onHorizontalDragDown: (details) {
                        _pressX = details.localPosition.dx;
                        // The loop brace along the top of the ruler wins:
                        // it is what the press is on.
                        _pressedBrace = _braceAt(
                            details.localPosition, constraints.maxWidth);
                        // An end of the loop's bar, under the keyframes.
                        _pressedLoop = _loopEndAt(
                            details.localPosition, constraints.maxWidth);
                        // A flag on the ruler first: it is what the press is
                        // on, and dragged, it moves.
                        _pressedFlag = _flagAt(
                            details.localPosition, constraints.maxWidth);
                        _pressedFrame = _pressedFlag != null
                            ? null
                            : _keyframeAt(
                                details.localPosition, constraints.maxWidth);
                        // The bar between a pair, when the press was not on either end. A
                        // mark wins: dragging an end changes the animation's length, dragging
                        // the middle moves it.
                        _pressedBand = _pressedFrame != null
                            ? null
                            : _bandAt(
                                details.localPosition, constraints.maxWidth);
                        // Empty strip under the ruler: a drag there draws a
                        // box over the keyframes and selects what it covers.
                        // On the ruler, a drag still scrubs.
                        _pressedMarquee = _pressedLoop == null &&
                            _pressedFlag == null &&
                            _pressedFrame == null &&
                            _pressedBand == null &&
                            _targetTrack != null &&
                            _keysShown &&
                            details.localPosition.dy > _rulerHeight &&
                            details.localPosition.dy < _keysRoom;
                      },
                      onHorizontalDragStart: (details) {
                        _dragBrace = _pressedBrace;
                        if (_dragBrace != null) {
                          // Moved while it plays: a loop is set by ear.
                          _braceFrom = _frameAt(_pressX, constraints.maxWidth);
                          _braceWas = controller.loopRange;
                          return;
                        }
                        controller.pause();
                        _dragLoop = _pressedLoop;
                        if (_dragLoop != null) {
                          controller.beginInteraction();
                          return;
                        }
                        _dragFlag = _pressedFlag;
                        if (_dragFlag != null) controller.beginInteraction();
                        _dragKey = _pressedFrame;
                        _dragBand = _pressedBand;
                        _bandAnchor = _frameAt(_pressX, constraints.maxWidth);
                        // A mark that is one of several selected takes the rest with it,
                        // keeping their spacing.
                        var grabbed = _pressedFrame != null
                            ? {_pressedFrame!}
                            : (_pressedBand?.toSet() ?? const <int>{});
                        if (_selectedKeys.length > 1 &&
                            grabbed.isNotEmpty &&
                            _selectedKeys.containsAll(grabbed)) {
                          _dragKey = null;
                          _dragBand = (_selectedKeys.toList()..sort());
                        }
                        _narrowTo = null;
                        _narrowBand = null;
                        // A keyframe, or several, moved by a drag is one
                        // change however many frames it passes through.
                        if (_dragKey != null || _dragBand != null) {
                          controller.beginInteraction();
                        }
                        if (_pressedMarquee) {
                          var x = _pressX;
                          setState(() {
                            _marquee = (x, x);
                            if (!_shiftHeld) _selectedKeys.clear();
                          });
                        }
                      },
                      onHorizontalDragUpdate: (details) {
                        var at = _frameAt(
                            details.localPosition.dx, constraints.maxWidth);
                        if (_dragBrace case var part?) {
                          _moveBrace(part, at);
                          return;
                        }
                        if (_dragLoop != null) {
                          _moveLoopEnd(_dragLoop!, at);
                          return;
                        }
                        if (_dragFlag != null) {
                          if (_moveAction(_dragFlag!, at)) _dragFlag = at;
                          return;
                        }
                        if (_dragBand != null) {
                          _shiftBand(at);
                          return;
                        }
                        if (_marquee case (var from, _)) {
                          _selectWithin(from, details.localPosition.dx,
                              constraints.maxWidth);
                          return;
                        }
                        if (_dragKey == null) {
                          _scrubTo(
                              details.localPosition.dx, constraints.maxWidth);
                          return;
                        }
                        _retime(_dragKey!, at);
                        _dragKey = at;
                      },
                      onHorizontalDragEnd: (_) {
                        if (_dragKey != null || _dragBand != null) {
                          controller.endInteraction();
                        }
                        if (_marquee != null) {
                          setState(() => _marquee = null);
                          if (_selectedKeys.isNotEmpty) {
                            FocusScope.of(context).requestFocus(_focus);
                          }
                        }
                        _pressedMarquee = false;
                        _dragBrace = null;
                        _pressedBrace = null;
                        if (_dragLoop != null) controller.endInteraction();
                        _dragLoop = null;
                        _pressedLoop = null;
                        if (_dragFlag != null) controller.endInteraction();
                        _dragFlag = null;
                        _pressedFlag = null;
                        _dragKey = null;
                        _dragBand = null;
                        _pressedFrame = null;
                        _pressedBand = null;
                      },
                      onHorizontalDragCancel: () {
                        if (_dragKey != null || _dragBand != null) {
                          controller.endInteraction();
                        }
                        if (_marquee != null) {
                          setState(() => _marquee = null);
                          if (_selectedKeys.isNotEmpty) {
                            FocusScope.of(context).requestFocus(_focus);
                          }
                        }
                        _pressedMarquee = false;
                        _dragBrace = null;
                        _pressedBrace = null;
                        if (_dragLoop != null) controller.endInteraction();
                        _dragLoop = null;
                        _pressedLoop = null;
                        if (_dragFlag != null) controller.endInteraction();
                        _dragFlag = null;
                        _pressedFlag = null;
                        _dragKey = null;
                        _dragBand = null;
                        _pressedFrame = null;
                        _pressedBand = null;
                      },
                      child: CustomPaint(
                        key: const ValueKey("keyframeStrip"),
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                        painter: _TimelinePainter(
                          view: _sceneView,
                          // Ticks along the whole of what is laid out (the run, where the
                          // timeline runs), counted from the scene's own start.
                          origin: _origin,
                          frames: _total - _origin,
                          scene: _runs ? _total - _origin : document.frames,
                          marks: _markRow,
                          // The joins go with the scene strip they sit over.
                          sceneStarts: _runs && !document.editingMaster
                              ? [
                                  for (var i = 0;
                                      i < document.allScenes.length;
                                      i++)
                                    document.startOfScene(i) - _origin,
                                ]
                              : const [0],
                          frame: controller.frame,
                          frameRate: document.frameRate,
                          // A piece of sound is counted in bars and beats,
                          // under its structure.
                          bars: document.kind.isAudio ? document.audio : null,
                          brace:
                              controller.looping ? controller.loopRange : null,
                          looping: controller.looping,
                          // The focused player's, when one is focused (see _targetTrack): the
                          // same keyframes the diamond button adds and removes.
                          keyframes: _keysShown
                              ? _targetTrack?.keys ?? const []
                              : const [],
                          bands: _keysShown ? _bands : const [],
                          loop: _keysShown ? _loopBar : null,
                          selected: _selectedKeys,
                          actions: document.actions,
                          marquee: _marquee,
                          cues: [
                            if (controller.cuesShown)
                              for (var c in document.cues)
                                (
                                  c.frame -
                                      (document.editingMaster
                                          ? 0
                                          : document.startOfScene(document.at)),
                                  c.name
                                ),
                          ],
                          colors: theme.colors,
                          xFor: (f) => _xFor(f, constraints.maxWidth),
                        ),
                      ),
                    ),
                    // The scenes, under the keyframes and over the channels,
                    // on the ruler's own scale.
                    if (_showScenes)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: _scenesTop,
                        height: sceneBoxHeight,
                        child: CanvasSceneStrip(
                            controller: controller,
                            view: _viewNow,
                            origin: _origin),
                      ),
                  ]),
                )),
            ]),
          ),
        ),
      // The channels: the media on the timeline, one lane each, in whatever
      // room the timeline has been dragged open to, under a drawing's shape
      // lanes where they are shown. See VectorShapeLanes.
      if (widget.height > _least + 4)
        Expanded(
            child: CanvasChannels(
                controller: controller,
                view: _sceneView,
                // The elements' rows, each with its own sound under it:
                // see motion_lanes.dart and element_sound.dart.
                motionRows: true,
                leading: widget.slotsOnly
                    ? null
                    : Column(mainAxisSize: MainAxisSize.min, children: [
                        VectorShapeLanes(
                            controller: controller, view: _sceneView),
                        ImageLayerLanes(
                            controller: controller, view: _sceneView),
                      ]))),
      // Which stretch of the timeline is on screen, and a handle to move
      // it: under the frames, not the strip column.
      if (!_collapsed && !widget.slotsOnly)
        SizedBox(
          height: _scrollbarHeight,
          child: Row(children: [
            SizedBox(width: _leftW),
            Expanded(
              child: _TimelineScrollbar(
                key: const ValueKey("timelineScrollbar"),
                view: _viewNow,
                frames: _total,
                colors: theme.colors,
                onView: _setView,
              ),
            ),
          ]),
        ),
    ];
    return Container(
      height: (widget.showBar
              ? math.max(timelineCollapsedHeight, widget.height)
              : widget.height) +
          (_showScenes ? sceneStripHeight : 0),
      padding: const EdgeInsets.fromLTRB(10, _stripPadTop, 10,
          _stripPadBottom + _notesGutter - _scrollbarHeight),
      decoration: BoxDecoration(
        color: theme.colors.surfaceContainerLow,
        border: Border(
            top: BorderSide(color: theme.colors.outlineVariant, width: 1)),
      ),
      // Squeezed shorter than its fixed rows (the strip, the scroll bar,
      // a play bar of its own) by the panels around it, it is laid out at
      // that least and cut off at the bottom, rather than overflowing.
      child: LayoutBuilder(builder: (context, box) {
        var least = (_collapsed ? 0.0 : _keysRoom - 1 + _sceneGap) +
            (!_collapsed && !widget.slotsOnly ? _scrollbarHeight : 0) +
            (_barAbove || _barBelow
                ? _transportHeight + (_collapsed ? 0 : _stripGap)
                : 0);
        var tall = math.max(box.maxHeight, least);
        var column = Column(children: [
          if (_barAbove) ...[
            bar,
            if (!_collapsed) const SizedBox(height: _stripGap),
          ],
          ...rows,
          if (_barBelow) ...[
            if (!_collapsed) const SizedBox(height: _stripGap),
            bar,
          ],
        ]);
        if (tall <= box.maxHeight) return column;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: tall,
            maxHeight: tall,
            child: column,
          ),
        );
      }),
    );
  }

  /// _onKey is the transport's keyboard, matching the canvas's: focus lands
  /// here as soon as one of these controls is pressed, and the space bar has
  /// to keep working. The arrows are claimed too, or Flutter spends them on
  /// directional focus traversal between the buttons.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // A game playing has the keys: Space jumps and the arrows run, rather
    // than playing the timeline or walking its frames. See gameKey.
    if (controller.gaming) return KeyEventResult.handled;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Never while somebody is typing (see isTypingInAField): this runs
    // before the app's text-editing shortcuts, so the arrows and space
    // would otherwise scrub and play.
    if (isTypingInAField()) return KeyEventResult.ignored;
    // Delete on a selected mark removes the keyframe, not the element the
    // canvas's own Delete would take.
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_selectedKeys.isEmpty) return KeyEventResult.ignored;
      // Highest first, so removing one does not move the next.
      for (var at in _selectedKeys.toList()..sort((a, b) => b - a)) {
        _removeTargetKey(at);
      }
      setState(_selectedKeys.clear);
      return KeyEventResult.handled;
    }

    // Copy and paste, on the strip's own selection. The canvas has its own
    // pair for elements; which answers depends on where the focus is.
    var meta = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    // Only with marks to copy, and marks to paste onto something that takes
    // them: otherwise the keys go on to the page, which copies what is
    // selected (a sound clicked on the timeline, say).
    var clipChosen = controller.selectedElements
            .any((e) => e is AudioElement && e.clip.timed) ||
        // A clip picked on another canvas: the master's, from a scene.
        controller.clipSelection.length > controller.selection.length;
    if (meta &&
        event.logicalKey == LogicalKeyboardKey.keyC &&
        _selectedKeys.isNotEmpty) {
      _copyKeys();
      return KeyEventResult.handled;
    }
    if (meta &&
        event.logicalKey == LogicalKeyboardKey.keyV &&
        _copied.isNotEmpty &&
        !clipChosen) {
      _pasteKeys();
      return KeyEventResult.handled;
    }

    return transportKey(controller, event) ?? KeyEventResult.ignored;
  }

  /// _keyframeAt is the mark under [local], or null. Only in the keyframe
  /// row's own band (see _markRow): a drag starting on the ruler's numbers
  /// is a scrub, since that is where the playhead is grabbed.
  int? _keyframeAt(Offset local, double width) {
    var keys = _targetTrack?.keys ?? const <Keyframe>[];
    if (keys.isEmpty || !_keysShown) return null;
    if ((local.dy - _markRow).abs() > _markGrabHeight) return null;

    int? best;
    var nearest = _markGrabWidth;
    for (var key in keys) {
      var distance = (local.dx - _xFor(key.frame, width)).abs();
      if (distance > nearest) continue;
      nearest = distance;
      best = key.frame;
    }
    return best;
  }

  /// _loopBar is the selected element's loop on the timeline (where it starts
  /// and stops, its cycle and its gap), or null where it has none.
  (int, int, int, int)? get _loopBar {
    if (controller.focusedPlayer != null || _selectedPath != null) return null;
    var element = controller.selected;
    if (element == null || !CanvasController.loops(element)) return null;
    var loop = CanvasController.elementLoopOf(element);
    if (!loop.on) return null;
    var (start, end) = loop.span(
        arrived: arrivalEnd(element, controller.document.frameRate),
        last: controller.document.frames - 1);
    return (start, end, loop.cycle, loop.gap);
  }

  /// _braceAt is which part of the loop brace is under [local]: an end, which
  /// moves that end, or the middle, which moves the whole; null off it. The
  /// brace is the top few pixels of the ruler, only while the loop is on.
  _BracePart? _braceAt(Offset local, double width) {
    if (!controller.looping || local.dy > _braceHeight + 2) return null;
    var (from, length) = controller.loopRange;
    var a = _xFor(from, width), b = _xFor(from + length, width);
    if ((local.dx - a).abs() <= 5) return _BracePart.start;
    if ((local.dx - b).abs() <= 5) return _BracePart.end;
    if (local.dx > a && local.dx < b) return _BracePart.whole;
    return null;
  }

  /// _moveBrace drags the part of the brace taken hold of to [frame], onto
  /// the quantise grid in a piece of sound.
  void _moveBrace(_BracePart part, int frame) {
    var document = controller.document;
    var rate = math.max(1, document.frameRate);
    int snap(int f) {
      if (!document.kind.isAudio) return f;
      var a = document.audio;
      var step = (a.gridSeconds() ?? a.secondsPerBeat) * rate;
      return step <= 0 ? f : ((f / step).round() * step).round();
    }

    var (from, length) = _braceWas;
    var end = from + length;
    switch (part) {
      case _BracePart.start:
        var at = math.min(snap(frame), end - 1);
        controller.setLoop(at, end - at);
      case _BracePart.end:
        var at = math.max(snap(frame), from + 1);
        controller.setLoop(from, at - from);
      case _BracePart.whole:
        var at = snap(from + frame - _braceFrom);
        controller.setLoop(
            at.clamp(0, math.max(0, document.frames - length)).toInt(), length);
    }
  }

  /// _loopEndAt is which end of the loop's bar is under [local] (false its
  /// start, true its end), or null for neither.
  bool? _loopEndAt(Offset local, double width) {
    var bar = _loopBar;
    if (bar == null || !_keysShown) return null;
    if ((local.dy - _markRow - _loopBelow).abs() > 6) return null;
    var (start, end, _, _) = bar;
    if ((local.dx - _xFor(end + 1, width)).abs() <= 7) return true;
    if ((local.dx - _xFor(start, width)).abs() <= 7) return false;
    return null;
  }

  /// _moveLoopEnd puts the end of the loop's bar being dragged on [frame]:
  /// its start, or where it stops, never past each other.
  void _moveLoopEnd(bool end, int frame) {
    var element = controller.selected;
    var bar = _loopBar;
    if (element == null || bar == null) return;
    var loop = CanvasController.elementLoopOf(element);
    var (start, stop, _, _) = bar;
    controller.setElementLoop(
        element,
        end
            ? loop.copyWith(to: math.max(start, frame - 1), repeats: 0)
            : loop.copyWith(from: math.min(stop, frame)),
        transient: true);
  }

  /// _bands is the pairs of keyframes on the target that belong together:
  /// only an element's own, since a player's track has no channel with two
  /// ends and a path's marks are its points.
  List<KeyframeBand> get _bands {
    if (controller.focusedPlayer != null) return const [];
    if (_selectedPath != null) return const [];
    return bandsIn(controller.selected?.track);
  }

  /// _bandAt is the band under [local], or null: on the keyframe row, and
  /// only between the two marks, so an end can still be dragged alone.
  List<int>? _bandAt(Offset local, double width) {
    if (!_keysShown) return null;
    if ((local.dy - _markRow).abs() > _markGrabHeight) return null;
    for (var band in _bands) {
      if (!band.real) continue;
      var from = _xFor(band.from, width);
      var to = _xFor(band.to, width);
      if (local.dx < from + _markGrabWidth) continue;
      if (local.dx > to - _markGrabWidth) continue;
      return [band.from, band.to];
    }
    return null;
  }

  /// _shiftBand moves both ends of the band being dragged.
  void _shiftBand(int to) {
    var band = _dragBand;
    var element = controller.selected;
    if (band == null || element == null) return;

    var delta = to - _bandAnchor;
    if (delta == 0) return;
    // Clamped rather than refused, so a band dragged at the end of the
    // timeline slides up against it.
    var last = controller.document.frames - 1;
    var lowest = band.reduce(math.min);
    var highest = band.reduce(math.max);
    if (lowest + delta < 0) delta = -lowest;
    if (highest + delta > last) delta = last - highest;
    if (delta == 0) return;

    controller.shiftKeyframes(element.id, band, delta);
    setState(() {
      _dragBand = [for (var f in band) f + delta];
      _bandAnchor += delta;
      // What was selected and moved is still selected, where it went.
      if (band.every(_selectedKeys.contains)) {
        _selectedKeys
          ..removeAll(band)
          ..addAll(_dragBand!);
      }
    });
  }

  /// _selectWithin selects every keyframe between two x positions: the box
  /// dragged out over the strip.
  void _selectWithin(double from, double to, double width) {
    var track = _targetTrack;
    if (track == null) return;
    var a = _frameAt(math.min(from, to), width);
    var b = _frameAt(math.max(from, to), width);
    setState(() {
      _marquee = (from, to);
      if (!_shiftHeld) _selectedKeys.clear();
      for (var k in track.keys) {
        if (k.frame >= a && k.frame <= b) _selectedKeys.add(k.frame);
      }
    });
  }
}

/// rulerSteps is how far apart, in frames, the ruler's three sizes of tick
/// are at [pixelsPerFrame]: a number and a line every so many whole seconds
/// (as many as fit with room round them), a mid tick that divides it, and a
/// small one that divides that. Null where a size would be too close to see.
(int, int?, int?) rulerSteps(double pixelsPerFrame, int frameRate) {
  var second = math.max(1, frameRate);

  /// first is the first of [ladder] that is at least [least] pixels apart
  /// and, where [within] is given, divides it and is smaller.
  int? first(List<int> ladder, double least, [int? within]) {
    for (var n in ladder) {
      if (n <= 0) continue;
      if (within != null && (n >= within || within % n != 0)) continue;
      if (n * pixelsPerFrame >= least) return n;
    }
    return null;
  }

  var seconds = [
    for (var n in [1, 2, 5, 10, 30, 60, 120, 300, 600]) second * n
  ];
  var frameSteps = [1, 2, 5, 10, ...seconds];
  var major = first(seconds, 90) ?? seconds.last;
  var medium = first(frameSteps, 22, major);
  var minor = first(frameSteps, 7, medium ?? major);
  return (major, medium, minor);
}

/// rulerNumber is what the ruler writes at [frame] of a scene starting
/// [origin] frames into what is laid out: the frame of the whole run while
/// the timeline runs along every scene, counted from one, as the Frame box
/// counts.
int rulerNumber(int frame, int origin) => frame + origin + 1;

/// _TimelinePainter draws the ruler, its markers and cues, the keyframe row
/// and the playhead.
class _TimelinePainter extends CustomPainter {
  final TimelineView view;
  final int frames;

  /// scene is how many frames the scene has; [frames] runs on past it where
  /// a clip does, and that stretch is shaded.
  final int scene;

  /// origin is where the scene starts in what is laid out (the run, while the
  /// timeline runs), so the ruler is ticked from the run's start. Nought
  /// otherwise.
  final int origin;

  /// marks is how far down the keyframes are drawn: under the scene strip,
  /// where it shows.
  final double marks;

  /// sceneStarts is where each scene starts, in this painter's frames: just
  /// the one, at nought, unless the timeline runs along every scene. Each
  /// later one is marked on the ruler, over its join in the scene strip.
  final List<int> sceneStarts;
  final int frame;
  final int frameRate;
  final List<Keyframe> keyframes;

  /// bands are the pairs that belong together, drawn as a bar joining them.
  /// See KeyframeBand.
  final List<KeyframeBand> bands;

  /// selected is the frames of the marks that have been clicked, drawn
  /// with a ring so it is obvious which one Delete will take.
  final Set<int> selected;
  final List<TimelineAction> actions;

  /// cues are the run's cues, each at its frame in this painter's frames,
  /// with its name: see canvas_cues.dart.
  final List<(int, String)> cues;
  final ColorScheme colors;
  final double Function(int) xFor;

  /// loop is the selected element's loop, where it has one: the frame it
  /// starts on, the one it stops on, its cycle and its gap. Drawn as a thin
  /// bar under the keyframes, ticked where each go round starts.
  final (int, int, int, int)? loop;

  /// marquee is the box being dragged out to select keyframes, as two x
  /// positions, or null.
  final (double, double)? marquee;

  /// bars is a piece of sound's tempo, metre and structure: its ruler is
  /// counted in bars and beats, with its sections laid along it. Null for
  /// a ruler of frames.
  final AudioSettings? bars;

  /// brace is the control bar's loop, as where it starts and how long it is,
  /// drawn along the top of the ruler, lit while [looping].
  final (int, int)? brace;
  final bool looping;

  const _TimelinePainter({
    this.bars,
    this.brace,
    this.looping = false,
    this.loop,
    this.marquee,
    required this.view,
    required this.frames,
    required this.scene,
    this.origin = 0,
    this.marks = _markRow,
    this.sceneStarts = const [0],
    required this.frame,
    required this.frameRate,
    required this.bands,
    required this.keyframes,
    required this.selected,
    required this.actions,
    this.cues = const [],
    required this.colors,
    required this.xFor,
  });

  /// _paintBars is the ruler of a piece of sound: its sections as coloured
  /// bands with their names, a line and a number at every bar (fewer, zoomed
  /// out), and a tick at every beat where there is room.
  void _paintBars(Canvas canvas, Size size, AudioSettings a) {
    var perBar = a.secondsPerBar * frameRate;
    if (perBar <= 0) return;
    double xAt(double f) => xFor(f.round());
    // The sections, behind everything else on the ruler.
    for (var (i, section) in a.sections.indexed) {
      var from = xAt(a.startBar(i) * perBar);
      var to = xAt((a.startBar(i) + section.bars) * perBar);
      if (to < 0 || from > size.width) continue;
      var colour = Color(sectionColors[section.color % sectionColors.length]);
      canvas.drawRect(Rect.fromLTRB(from, 0, to, _rulerHeight),
          Paint()..color = colour.withValues(alpha: 0.22));
      canvas.drawRect(Rect.fromLTRB(from, 0, to, 3), Paint()..color = colour);
      var name = TextPainter(
        text: TextSpan(
            text: section.name,
            style: TextStyle(
                fontSize: 10,
                height: 1,
                fontWeight: FontWeight.w600,
                color: colors.onSurface)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: "…",
      )..layout(maxWidth: (to - from - 8).clamp(0.0, 400.0));
      name.paint(canvas, Offset(from + 4, 5));
    }
    var pxPerBar = xAt(perBar) - xAt(0);
    // A number on every bar where they fit, else every second, fourth...
    var every = 1;
    while (pxPerBar * every < 34 && every < 1024) {
      every *= 2;
    }
    var first = (view.first / perBar).floor() - 1;
    var last = ((view.first + view.span) / perBar).ceil() + 1;
    var line = Paint()
      ..color = colors.onSurfaceVariant.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    var tick = Paint()
      ..color = colors.onSurfaceVariant.withValues(alpha: 0.32)
      ..strokeWidth = 1;
    var numbers = TextStyle(
        fontSize: 11,
        height: 1,
        color: colors.onSurfaceVariant.withValues(alpha: 0.95));
    var perBeat = perBar / a.beatsPerBar;
    var beats = pxPerBar / a.beatsPerBar >= 6;
    for (var bar = math.max(0, first); bar <= last; bar++) {
      var x = xAt(bar * perBar);
      if (bar % every == 0) {
        canvas.drawLine(Offset(x, 0), Offset(x, _rulerHeight), line);
        var label = TextPainter(
          text: TextSpan(text: "${bar + 1}", style: numbers),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(canvas, Offset(x + 4, _rulerHeight - label.height - 4));
      } else {
        canvas.drawLine(Offset(x, 0), Offset(x, 9), tick);
      }
      if (beats) {
        for (var b = 1; b < a.beatsPerBar; b++) {
          var bx = xAt(bar * perBar + b * perBeat);
          canvas.drawLine(Offset(bx, 0), Offset(bx, 5), tick);
        }
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Zoomed in, marks and bars run past either edge: drawn, and cut there.
    canvas.clipRect(Offset.zero & size);
    var track = Rect.fromLTWH(0, 0, size.width, _rulerHeight);
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, const Radius.circular(4)),
      Paint()..color = colors.surfaceContainerHighest,
    );

    // Ticks hang from the top edge in three sizes (frames, seconds, and a
    // line through the ruler where a number is written), with the numbers
    // under them. Counted along the whole run where the timeline runs, and
    // from one, as the Frame box counts.
    if (bars case var a?) {
      _paintBars(canvas, size, a);
    } else {
      var step = size.width / math.max(1.0, view.span);
      var (major, medium, minor) = rulerSteps(step, frameRate);

      var from = math.max(-origin, view.first.floor());
      var to = math.min(frames - 1, (view.first + view.span).ceil());
      var line = Paint()
        ..color = colors.onSurfaceVariant.withValues(alpha: 0.45)
        ..strokeWidth = 1;
      var mid = Paint()
        ..color = colors.onSurfaceVariant.withValues(alpha: 0.55)
        ..strokeWidth = 1;
      var small = Paint()
        ..color = colors.onSurfaceVariant.withValues(alpha: 0.32)
        ..strokeWidth = 1;
      var numbers = TextStyle(
          fontSize: 11,
          height: 1,
          color: colors.onSurfaceVariant.withValues(alpha: 0.95));

      for (var f = from; f <= to; f++) {
        var run = f + origin;
        var x = xFor(f);
        if (run % major == 0) {
          canvas.drawLine(Offset(x, 0), Offset(x, _rulerHeight), line);
          var label = TextPainter(
            text: TextSpan(text: "${rulerNumber(f, origin)}", style: numbers),
            textDirection: TextDirection.ltr,
          )..layout();
          label.paint(canvas, Offset(x + 5, _rulerHeight - label.height - 4));
        } else if (medium != null && run % medium == 0) {
          canvas.drawLine(Offset(x, 0), Offset(x, 9), mid);
        } else if (minor != null && run % minor == 0) {
          canvas.drawLine(Offset(x, 0), Offset(x, 5), small);
        }
      }
    }

    // Where each scene begins, firmer than any tick: over the joins in the
    // scene strip under it.
    if (sceneStarts.length > 1) {
      var join = Paint()
        ..color = colors.primary.withValues(alpha: 0.55)
        ..strokeWidth = 1.5;
      for (var start in sceneStarts.skip(1)) {
        var x = xFor(start);
        if (x < 0 || x > size.width) continue;
        canvas.drawLine(Offset(x, 0), Offset(x, _rulerHeight), join);
      }
    }
    paintPastScene(canvas, Size(size.width, _rulerHeight), view, scene, colors);

    if (brace case (var from, var length)) {
      var rect =
          Rect.fromLTRB(xFor(from), 1, xFor(from + length), _braceHeight);
      var lit = looping ? colors.primary : colors.onSurfaceVariant;
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          Paint()..color = lit.withValues(alpha: looping ? 0.55 : 0.18));
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = lit.withValues(alpha: looping ? 1 : 0.4));
    }

    // The bars first, under the marks they join: a chart's entrance and exit
    // are each two keyframes that mean nothing apart. See _shiftBand.
    _paintBands(canvas, y: marks);
    _paintLoop(canvas, y: marks + _loopBelow);

    _paintMarks(
      canvas,
      size,
      y: marks,
      frames: [for (var k in keyframes) k.frame],
      // Muted, the weight of the transport's icons: the accent is kept for
      // the selected mark.
      color: colors.onSurfaceVariant.withValues(alpha: 0.65),
      diamond: true,
      selected: selected,
      selectedColor: colors.primary,
    );
    _paintMarkers(canvas);
    _paintCues(canvas);
    if (marquee case (var a, var b)) {
      var box = Rect.fromLTRB(
          math.min(a, b), _rulerHeight + 1, math.max(a, b), size.height - 1);
      canvas.drawRect(
          box, Paint()..color = colors.primary.withValues(alpha: 0.12));
      canvas.drawRect(
          box,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = colors.primary.withValues(alpha: 0.6));
    }

    // The playhead last, over everything, so it can be found at a glance.
    var x = xFor(frame);
    canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = colors.primary
          ..strokeWidth = 2);
    canvas.drawPath(
      Path()
        ..moveTo(x - 5, 0)
        ..lineTo(x + 5, 0)
        ..lineTo(x, 8)
        ..close(),
      Paint()..color = colors.primary,
    );
  }

  /// _paintMarkers draws each marker as a flag on the ruler: a staff down
  /// through the ticks, and a pennant at the top. Not in tertiary, which is a
  /// panel background.
  void _paintMarkers(Canvas canvas) {
    var ink = Paint()..color = colors.secondary;
    var staff = Paint()
      ..color = colors.secondary
      ..strokeWidth = 2;
    for (var a in actions) {
      var x = xFor(a.frame);
      canvas.drawLine(Offset(x, 1), Offset(x, _rulerHeight - 1), staff);
      canvas.drawPath(
        Path()
          ..moveTo(x, 1)
          ..lineTo(x + _flagWidth, 6.5)
          ..lineTo(x, 12)
          ..close(),
        ink,
      );
      // Its label beside it, where it has one and it is to be shown.
      if (a.label.isNotEmpty && a.showLabel) {
        var text = TextPainter(
          text: TextSpan(
              text: a.label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: colors.secondary)),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: "…",
        )..layout(maxWidth: 140);
        text.paint(canvas, Offset(x + _flagWidth + 3, 1));
      }
    }
  }

  /// _paintCues draws each cue as a pennant hanging from the bottom of the
  /// ruler, as a marker's flies from the top: a marker is something the scene
  /// does, a cue a moment of the whole run that things are timed against, told
  /// apart by end and by colour.
  void _paintCues(Canvas canvas) {
    var ink = Paint()..color = colors.primary;
    var staff = Paint()
      ..color = colors.primary.withValues(alpha: 0.7)
      ..strokeWidth = 1.5;
    const bottom = _rulerHeight - 1;
    for (var (frame, name) in cues) {
      var x = xFor(frame);
      canvas.drawLine(Offset(x, 1), Offset(x, bottom), staff);
      canvas.drawPath(
        Path()
          ..moveTo(x, bottom)
          ..lineTo(x + _flagWidth, bottom - 5.5)
          ..lineTo(x, bottom - 11)
          ..close(),
        ink,
      );
      if (name.isEmpty) continue;
      var text = TextPainter(
        text: TextSpan(
            text: name,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: colors.primary)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: "…",
      )..layout(maxWidth: 120);
      text.paint(canvas, Offset(x + _flagWidth + 3, bottom - 12));
    }
  }

  /// _paintLoop draws the loop's bar: from where it starts to where it
  /// stops, a tick where each go round starts, and a grip at each end.
  void _paintLoop(Canvas canvas, {required double y}) {
    var span = loop;
    if (span == null) return;
    var (start, end, cycle, gap) = span;
    var from = xFor(start), to = xFor(end + 1);
    var ink = colors.primary;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTRB(from, y - 2, to, y + 2), const Radius.circular(2)),
      Paint()..color = ink.withValues(alpha: 0.35),
    );
    var tick = Paint()
      ..color = ink.withValues(alpha: 0.8)
      ..strokeWidth = 1;
    var period = math.max(1, cycle + gap);
    // No closer than four pixels apart, on a loop zoomed out a long way.
    var every =
        math.max(1, (4 / math.max(0.0001, xFor(1) - xFor(0)) / period).ceil());
    for (var f = start, i = 0; f <= end; f += period, i++) {
      if (i % every != 0) continue;
      var x = xFor(f);
      canvas.drawLine(Offset(x, y - 3), Offset(x, y + 3), tick);
    }
    for (var x in [from, to]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(x, y), width: 4, height: 9),
            const Radius.circular(1.5)),
        Paint()..color = ink,
      );
    }
  }

  /// _paintBands draws the bar between each pair: translucent, so the ruler's
  /// ticks under it still show where the animation starts.
  void _paintBands(Canvas canvas, {required double y}) {
    var colour = colors.primary;
    for (var band in bands) {
      if (!band.real) continue;
      var from = xFor(band.from);
      var to = xFor(band.to);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTRB(from, y - 5, to, y + 5), const Radius.circular(5)),
        Paint()..color = colour.withValues(alpha: 0.22),
      );
    }
  }

  void _paintMarks(
    Canvas canvas,
    Size size, {
    required double y,
    required List<int> frames,
    required Color color,
    required bool diamond,

    /// selected is drawn in [selectedColor] instead of [color]: the colour is
    /// the whole signal.
    Set<int> selected = const {},
    Color? selectedColor,
  }) {
    if (y > size.height) return;
    var paint = Paint()..color = color;
    var chosen = Paint()..color = selectedColor ?? color;
    for (var f in frames) {
      var x = xFor(f);
      var ink = selected.contains(f) ? chosen : paint;
      if (diamond) {
        canvas.drawPath(
          Path()
            ..moveTo(x, y - 5)
            ..lineTo(x + 5, y)
            ..lineTo(x, y + 5)
            ..lineTo(x - 5, y)
            ..close(),
          ink,
        );
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset(x, y), width: 9, height: 9),
              const Radius.circular(2)),
          ink,
        );
      }
    }
  }

  /// _sameBands compares two lists of pairs by what is in them: they are made
  /// fresh on every build, so identity would repaint the strip every frame.
  static bool _sameBands(List<KeyframeBand> a, List<KeyframeBand> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].from != b[i].from || a[i].to != b[i].to) return false;
    }
    return true;
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.bars?.toJson().toString() != bars?.toJson().toString() ||
      old.frames != frames ||
      old.scene != scene ||
      old.origin != origin ||
      !listEquals(old.sceneStarts, sceneStarts) ||
      old.marks != marks ||
      old.view != view ||
      old.frame != frame ||
      old.frameRate != frameRate ||
      old.keyframes != keyframes ||
      !_sameBands(old.bands, bands) ||
      !setEquals(old.selected, selected) ||
      old.actions != actions ||
      !listEquals(old.cues, cues) ||
      old.marquee != marquee ||
      old.brace != brace ||
      old.looping != looping ||
      old.loop != loop;
}

/// _TimelineScrollbar shows which stretch of the timeline is on screen, and
/// is dragged to move it, or clicked to jump there.
class _TimelineScrollbar extends StatelessWidget {
  final TimelineView view;
  final int frames;
  final ColorScheme colors;
  final ValueChanged<TimelineView> onView;

  const _TimelineScrollbar({
    required this.view,
    required this.frames,
    required this.colors,
    required this.onView,
    super.key,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        var w = box.maxWidth;
        var total = math.max(1, frames).toDouble();
        return GestureDetector(
          supportedDevices: timelinePointers,
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => onView(TimelineView(
              d.localPosition.dx / w * total - view.span / 2, view.span)),
          onHorizontalDragUpdate: (d) =>
              onView(view.scrolled(d.delta.dx / w * total, frames)),
          child: CustomPaint(
            size: Size(w, box.maxHeight),
            painter: _ScrollbarPainter(view, total, colors),
          ),
        );
      });
}

class _ScrollbarPainter extends CustomPainter {
  final TimelineView view;
  final double total;
  final ColorScheme colors;
  _ScrollbarPainter(this.view, this.total, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    var y = size.height / 2;
    canvas.drawRRect(
        RRect.fromLTRBR(0, y - 2, size.width, y + 2, const Radius.circular(2)),
        Paint()..color = colors.surfaceContainerHighest);
    var left = view.first / total * size.width;
    var width = math.max(16.0, view.span / total * size.width);
    var whole = width >= size.width - 0.5;
    canvas.drawRRect(
        RRect.fromLTRBR(left, y - 3, math.min(size.width, left + width), y + 3,
            const Radius.circular(3)),
        Paint()
          ..color =
              colors.onSurfaceVariant.withValues(alpha: whole ? 0.2 : 0.55));
  }

  @override
  bool shouldRepaint(_ScrollbarPainter old) =>
      old.view != view || old.total != total || old.colors != colors;
}
