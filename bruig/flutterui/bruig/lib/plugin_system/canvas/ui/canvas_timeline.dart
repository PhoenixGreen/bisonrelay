import 'dart:math' as math;

import 'package:bruig/storage_manager.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_sequence.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_channels.dart';
import 'package:bruig/plugin_system/canvas/ui/scene_strip.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_view.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// canvas_timeline.dart is the strip along the bottom of the canvas: the
// transport, the frames, the playhead, and the markers on it.
//
// The animation settings live here too -- how many frames, and how many a
// second. They were in the settings band above the canvas, which is where a
// document-wide setting nominally belongs, but they describe the strip they
// are now on: "24 frames" means something you can see the length of, right
// beside it, and nothing about the canvas's shape or its background is any
// help in choosing it.
//
// It shows exactly two rows of marks and no more. The upper row is the
// selected element's keyframes -- or the focused player's, when a player of a
// selected team has been clicked. One track at a time either way, because a
// down the side is a timeline for a tool where fifty things move, and this is
// a tool where three do. The lower row is the document's own timeline actions:
// stop here, loop back to there.
//
// A pose rather than a curve per property (see canvas_animation.dart) is what
// makes that possible. One diamond on the timeline is everything about where
// this element is at this frame, so a whole animation is legible in one line
// instead of four.

/// timelineHeight is the strip's height with no channels showing -- the
/// least it can be dragged down to. The room above it is the channels', and
/// is whatever the timeline is dragged open to: see CanvasTimeline.height.
///
/// The pose controls open in a bar that floats over the bottom of the canvas
/// area rather than in a row that makes this taller -- see CanvasKeyframeBar.
/// Growing the strip pushed the canvas up and re-fitted it, so opening a panel
/// moved the design; the same reason the canvas settings float.
///
/// Added up rather than written down. It was 110, and the transport row above
/// the ruler grew by three pixels the day a caption was given room to breathe
/// -- which took those three off the ruler, and the keyframe marks with them,
/// because the marks sit a fixed distance down a box that had quietly become
/// shorter. A total that is the sum of its parts cannot do that.
/// Added up, and it has to add up to what is actually drawn. Seventy-two was
/// meant to be everything below the transport row, but the strip's own padding
/// comes out of the same box -- so the drawing had thirty-nine pixels for the
/// sixty-two it needed. The lower half of every keyframe was painted outside
/// the widget, which is why a mark could only be clicked along its top edge,
/// and the row of timeline markers under it was never drawn at all.
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
const double _transportHeight = controlHeight;

/// _stripPadTop is the room above the play bar: enough that its buttons do
/// not sit hard against the timeline's top edge, now there is no line of
/// captions over them to keep it off.
const double _stripPadTop = 8;
const double _stripPadBottom = 6;

/// _stripGap is the room between the play bar and the ruler under it: enough
/// that the two read as two things rather than one run of controls.
const double _stripGap = 10;

/// _markRow is where the keyframes sit inside the strip, and _stripHeight is
/// tall enough for them with air under. Every hit test and the painter read
/// these, so a mark cannot be drawn somewhere the pointer is not looking for
/// it.
///
/// The markers have no row of their own. They were a second row under the
/// keyframes, labelled, and empty on nearly every canvas; they are flags on
/// the ruler now, over the frames they are on -- see _paintMarkers.
const double _markRow = _rulerHeight + 14;
const double _stripHeight = _markRow + 12;

/// keyframeBarHeight is the floating pose bar's height.
const double keyframeBarHeight = controlWithLabelHeight + 10;

/// _notesGutter is the empty band kept along the bottom of the strip.
///
/// The notes button is a 24px wedge in the bottom-left corner of the content
/// area, drawn over whatever is under it -- and what is under it here is the
/// timeline, where a keyframe on frame 1 sits exactly beneath it. Rather than
/// indent the marks from the left, which would put frame 1 somewhere other
/// than the start of the strip, the whole strip lifts clear of the corner.
const double _notesGutter = 20;

/// _flagWidth is how far a marker's pennant reaches from its staff.
const double _flagWidth = 12;

/// _scrollbarHeight is the bar along the bottom that shows, and moves, the
/// stretch of frames on screen. Taken out of the notes gutter, so the total
/// does not change.
const double _scrollbarHeight = 10;

/// _rulerHeight is the frame numbers and the playhead.
const double _rulerHeight = 30;

/// _markGrabWidth and _markGrabHeight are how close the pointer has to be to a
/// keyframe mark to take hold of it rather than scrub.
///
/// Generous horizontally, because a mark is a few pixels wide and a timeline
/// squeezed to a hundred frames puts them close together; and far enough
/// vertically to cover the whole mark and the air either side of it. It was
/// eleven, which would have been enough -- except that the strip was shorter
/// than the drawing, so half the target was off the end of the widget and the
/// pointer never reached it.
const double _markGrabWidth = 9;
const double _markGrabHeight = 12;

/// _pathDriving is the path that owns a row's keyframes, if one does.
///
/// A followed element's track is written by the path and rewritten whenever
/// a point moves, so keyframes shown on its own row would be marks the
/// reader could drag and then watch disappear. The strip shows nothing for
/// it and says where the timing lives instead -- which is also the answer to
/// "why do I get keyframes on the player *and* on the path".
///
/// A function rather than a getter on each of the two widgets that ask it:
/// the strip and the ruler under it were carrying the same eight lines, and
/// two copies of "what is being timed here" is the sort of thing that stays
/// in step until the day it does not.
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

  /// keyframesOpen and onToggleKeyframes drive the pose bar the screen floats
  /// over the canvas. Held there rather than here because the bar is not part
  /// of this widget -- growing this strip to hold it pushed the canvas up.
  final bool keyframesOpen;

  final VoidCallback onToggleKeyframes;

  /// height is how tall the timeline is, at least timelineHeight: whatever
  /// it has over that is the channels', under the keyframe strip. Dragged
  /// from its top edge, through onResize. See CanvasChannels.
  final double height;
  final ValueChanged<double>? onResize;

  const CanvasTimeline({
    required this.controller,
    this.keyframesOpen = false,
    this.onToggleKeyframes = _noop,
    this.height = timelineHeight,
    this.onResize,
    super.key,
  });

  static void _noop() {}

  @override
  State<CanvasTimeline> createState() => _CanvasTimelineState();
}

class _CanvasTimelineState extends State<CanvasTimeline> {
  CanvasController get controller => widget.controller;

  /// _dragBand is the pair of frames being dragged as one, or null.
  ///
  /// A chart's entrance is two keyframes that are meaningless apart, so the
  /// bar joining them is draggable and moves both. See KeyframeBand.
  List<int>? _dragBand;

  /// _pressedBand is the band the pointer went down on, found on the press
  /// for the same reason _pressedFrame is: a horizontal drag is not
  /// recognised until the pointer has travelled, by which time its reported
  /// start is well past what it was aimed at.
  List<int>? _pressedBand;

  /// _bandAnchor is the frame the band drag last acted from.
  int _bandAnchor = 0;

  /// _dragKey is the frame of the mark being dragged along the ruler, or null
  /// while the drag is an ordinary scrub.
  int? _dragKey;

  /// _pressedFrame is the mark under the pointer when it went down, before any
  /// drag was recognised. See onHorizontalDragDown.
  int? _pressedFrame;

  /// _selectedKeys are the frames of the marks that have been clicked.
  ///
  /// A set rather than one frame, because the things somebody wants to do to
  /// keyframes -- move them, copy them, take them away -- are as often about
  /// several as about one. Shift picks up another; clicking the bar between a
  /// pair picks up both ends, since a pair is what that bar means.
  ///
  /// Cleared whenever the row changes underneath it -- a frame number means
  /// nothing once the strip is showing somebody else's keyframes, and a stale
  /// one would put Delete on a mark that is not there.
  final Set<int> _selectedKeys = {};

  /// _copied is what was last copied: each keyframe, and how far it sits after
  /// the first of them. Relative, so a paste lands wherever the playhead is
  /// with the shape of the run preserved.
  List<(int, Keyframe)> _copied = const [];

  /// _shiftHeld is whether a click adds to the selection rather than starting
  /// a new one, which is what shift means on every list in the app.
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

  /// _trackpadScrolls is whether a sideways swipe or the wheel moves the
  /// timeline along. Off unless asked for: somebody who swipes up and down to
  /// move through the channels finds the frames sliding under them.
  bool _trackpadScrolls = false;

  static const _trackpadKey = "canvasTimelineTrackpad";
  static const _headerKey = "canvasTimelineHeader";

  Future<void> _readSettings() async {
    var scrolls = await StorageManager.readBool(_trackpadKey);
    var snaps = await StorageManager.readBool(_snapKey);
    var header = double.tryParse(await StorageManager.readString(_headerKey));
    if (!mounted) return;
    setState(() => _trackpadScrolls = scrolls);
    controller.snapping = snaps;
    if (header != null) controller.headerWidth = header;
  }

  static const _snapKey = "canvasTimelineSnap";

  void _setSnapping(bool value) {
    controller.snapping = value;
    StorageManager.saveBool(_snapKey, value);
  }

  void _setTrackpadScrolls(bool value) {
    setState(() => _trackpadScrolls = value);
    StorageManager.saveBool(_trackpadKey, value);
  }

  @override
  void dispose() {
    _focus.dispose();
    controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    // A mark that is no longer on this row cannot stay selected: the frame
    // number would still be a number, and Delete would take a keyframe the
    // reader never picked.
    _selectedKeys.removeWhere((at) => _targetTrack?.keyAt(at) == null);
    setState(() {});
  }

  /// _frameAt turns a horizontal position into a frame number of the scene
  /// being edited.
  int _frameAt(double x, double width) =>
      _sceneView.frameAt(x, width, controller.document.frames);

  double _xFor(int frame, double width) => _sceneView.centreOf(frame, width);

  /// _scrubTo puts the playhead under [x]. Where the timeline runs along
  /// every scene, a point over another scene goes to that scene, at the frame
  /// of it the ruler says -- the ruler is the run's, so it has to.
  void _scrubTo(double x, double width) {
    var document = controller.document;
    if (_runs && !document.editingMaster) {
      var place = placeInSequence(document, _viewNow.frameAt(x, width, _total));
      if (place.scene != document.at) controller.goToScene(place.scene);
      controller.frame = place.frame;
      return;
    }
    controller.frame = _frameAt(x, width);
  }

  /// _runs is whether the timeline is laid along the whole run rather than
  /// the one scene: while Play runs every scene. The ruler and the scene
  /// strip are then one scale -- each scene's frames run along the ruler
  /// over its box, and zooming zooms both -- and the scene being edited is
  /// its stretch of that run. See CanvasSceneStrip.
  bool get _runs => controller.playAll && controller.document.hasScenes;

  /// _origin is where the scene being edited starts in the run, in frames:
  /// nought unless the timeline runs, and on the master, whose frames are
  /// the run's already.
  int get _origin {
    var document = controller.document;
    if (!_runs || document.editingMaster) return 0;
    return document.startOfScene(document.at);
  }

  /// _total is how many frames the timeline is laid along: the run where it
  /// runs, and otherwise the scene -- and past either to the end of a clip
  /// that goes on longer. See CanvasController.timelineReach.
  int get _total => _runs
      ? math.max(controller.document.sequenceFrames,
          _origin + controller.timelineReach)
      : controller.timelineReach;

  /// _sceneView is the view in the scene's own frames: the run's, moved back
  /// by where the scene starts. What the keyframes, the markers and the
  /// channels are drawn with, so they sit under their stretch of the ruler.
  TimelineView get _sceneView =>
      TimelineView(_viewNow.first - _origin, _viewNow.span);

  /// _sceneGap is the room the scene strip takes between the ruler and the
  /// keyframes, while it shows.
  double get _sceneGap => _showScenes ? sceneStripHeight : 0;

  /// _ranRun is whether the last build ran along the whole run, so a view
  /// zoomed in one way of counting is not kept for the other.
  bool _ranRun = false;

  /// _view is the stretch of frames zoomed to, or null for all of them --
  /// which then follows the timeline's length as it changes. _viewNow is the
  /// one this build is drawn with. See TimelineView.
  TimelineView? _view;
  TimelineView _viewNow = const TimelineView(0, 1);

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
  double _laneWidth(double bodyWidth) =>
      math.max(1, bodyWidth - 20 - controller.headerWidth);

  /// _onSignal is the wheel: with Ctrl or Cmd it zooms about the pointer;
  /// sideways -- or with Shift, or anywhere over the keyframe strip -- it
  /// scrolls along the frames; plainly, over the channels, it is left to
  /// them, which scroll up and down.
  void _onSignal(PointerSignalEvent event, double bodyWidth) {
    if (event is! PointerScrollEvent) return;
    var keys = HardwareKeyboard.instance;
    var zoom = keys.isControlPressed || keys.isMetaPressed;
    var local = event.localPosition;
    var stripTop = _stripPadTop + _transportHeight + _stripGap;
    var overStrip =
        local.dy >= stripTop && local.dy <= stripTop + _stripHeight + _sceneGap;
    // Not over the play bar: it scrolls sideways itself, to reach what is
    // along it, and that is not the frames being scrolled.
    if (local.dy < stripTop) return;
    var delta = event.scrollDelta;
    var sideways = keys.isShiftPressed || delta.dx.abs() > delta.dy.abs();
    if (!zoom && !sideways && !overStrip) return;
    // Scrolling along is the reader's choice -- see _trackpadScrolls. Zooming
    // asks for a key held down, so it is never done by accident.
    if (!zoom && !_trackpadScrolls) return;
    var frames = _total;
    var width = _laneWidth(bodyWidth);
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      var d = (e as PointerScrollEvent).scrollDelta;
      if (zoom) {
        var x = local.dx - 10 - controller.headerWidth;
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
    // Not over the play bar -- see _onSignal.
    if (event.localPosition.dy < _stripPadTop + _transportHeight + _stripGap) {
      return;
    }
    var frames = _total;
    var width = _laneWidth(bodyWidth);
    var next = _viewNow;
    if ((event.scale - _pinch).abs() > 0.001) {
      var x = event.localPosition.dx - 10 - controller.headerWidth;
      var around = next.first + next.framesPer(x, width);
      next = next.zoomed(event.scale / _pinch, around, frames);
      _pinch = event.scale;
    }
    var pan = event.panDelta;
    // Sideways only: up and down belong to the channels' own list. And only
    // when asked for -- see _trackpadScrolls.
    if (_trackpadScrolls && pan.dx.abs() > pan.dy.abs()) {
      next = next.scrolled(-next.framesPer(pan.dx, width), frames);
    }
    if (next != _viewNow) _setView(next);
  }

  /// _targetName is what the keyframe controls are pointed at, for the
  /// tooltips -- a player when one has been clicked, otherwise the element.
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

  /// _targetTrack is the track the keyframe controls read and write.
  ///
  /// A player has no id and cannot be selected, so the focused player is the
  /// only thing that says the controls are about them rather than about the
  /// team they are in. Everything below goes through this pair rather than
  /// reaching for controller.selected, so a player's keyframes behave exactly
  /// as an element's do.
  ElementTrack? get _targetTrack {
    var team = controller.focusedTeam;
    var index = controller.focusedPlayer;
    if (team != null && index != null && index < team.players.length) {
      return team.players[index].track;
    }
    // A path's marks are its points. Its own track is empty -- what moves is
    // the follower, whose keyframes the path writes -- so without this a
    // selected path showed a bare strip and the one thing worth retiming from
    // the timeline could not be reached from it.
    var path = _selectedPath;
    if (path != null) {
      return ElementTrack([for (var n in path.nodes) Keyframe(frame: n.frame)]);
    }
    // And nothing at all for whatever a path is driving: those marks belong to
    // the route, and showing them twice invited editing the copy that gets
    // overwritten.
    if (_drivingPath != null) return null;
    return controller.selected?.track;
  }

  /// _selectedPath is the selected element when it is a path.
  PathElement? get _selectedPath {
    var element = controller.selected;
    return element is PathElement ? element : null;
  }

  PathElement? get _drivingPath => _pathDriving(controller);

  /// _retime moves a mark from one frame to another.
  ///
  /// One entry point for the three things a mark can belong to, because the
  /// ruler that drags them does not know or care which it is holding.
  /// _pressedFlag and _dragFlag are the frame of the flag pressed on the
  /// ruler, and of the one being dragged -- see _flagAt.
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

  void _retime(int from, int to) {
    if (from == to) return;

    var path = _selectedPath;
    if (path != null) {
      var index = path.nodes.indexWhere((n) => n.frame == from);
      if (index < 0) return;
      var next = path.retimeNode(index, to);
      controller.replaceElement(next);
      // Re-baked, or the follower goes on running the old timing while the
      // point sits somewhere else -- the route and the movement are meant to
      // be the same thing.
      controller.applyPathFollow(next);
      return;
    }

    var track = _targetTrack;
    var key = track?.keyAt(from);
    if (track == null || key == null) return;
    // Not through _setTargetKey/_removeTargetKey, which route a path to its
    // points; a path has already been dealt with above.
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

  /// _copyKeys puts the selected keyframes on this strip's own clipboard.
  ///
  /// Kept here rather than on the system clipboard: these are keyframes, and
  /// the thing anybody does with them is paste them somewhere else on this
  /// timeline a moment later. Relative to the first of them, so the run keeps
  /// its shape wherever it lands.
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
  /// playhead.
  ///
  /// Refused rather than merged where it would land on what is already there.
  /// Two keyframes on one frame is one keyframe, so a paste that overlapped
  /// would quietly eat whatever it landed on -- and an animation is a pair,
  /// so eating one end of one leaves half an animation behind.
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

  /// _keyframeFrames is every frame this strip has a mark on, in order. What
  /// the next and previous buttons walk.
  List<int> get _keyframeFrames {
    var path = _selectedPath;
    if (path != null) {
      return [for (var node in path.nodes) node.frame]..sort();
    }
    return [for (var key in _targetTrack?.keys ?? const <Keyframe>[]) key.frame]
      ..sort();
  }

  /// _goToKeyframe moves the playhead to the next mark in [direction], or
  /// leaves it where it is when there is not one that way.
  void _goToKeyframe(int direction) {
    var frames = _keyframeFrames;
    if (frames.isEmpty) return;
    controller.pause();
    var at = controller.frame;
    if (direction > 0) {
      for (var frame in frames) {
        if (frame > at) {
          controller.frame = frame;
          return;
        }
      }
      return;
    }
    for (var frame in frames.reversed) {
      if (frame < at) {
        controller.frame = frame;
        return;
      }
    }
  }

  bool get _hasTarget =>
      _drivingPath == null &&
      ((controller.focusedTeam != null && controller.focusedPlayer != null) ||
          controller.selected != null);

  /// _pathKeyframe adds or removes a *point* when a path is selected.
  ///
  /// The diamond means the same thing it always does -- "there is something
  /// here" -- and for a path the something is a point. Routed here rather than
  /// through setKeyframe, which would write a pose onto the path's own track,
  /// where nothing reads it: what moves is the follower.
  bool _pathKeyframe({required bool add}) {
    var path = _selectedPath;
    if (path == null) return false;
    PathElement next;
    if (add) {
      next = path.insertAtFrame(controller.frame);
    } else {
      var index = path.nodeIndexAtFrame(controller.frame);
      next = index == null ? path : path.withoutNode(index);
    }
    if (identical(next, path)) return true;
    controller.replaceElement(next);
    controller.applyPathFollow(next);
    return true;
  }

  void _setTargetKey(Keyframe key) {
    if (_pathKeyframe(add: true)) return;
    var team = controller.focusedTeam;
    var index = controller.focusedPlayer;
    if (team != null && index != null) {
      controller.setPlayerKeyframe(team.id, index, key);
      return;
    }
    var element = controller.selected;
    if (element != null) controller.setKeyframe(element.id, key);
  }

  void _removeTargetKey(int frame) {
    if (_pathKeyframe(add: false)) return;
    var team = controller.focusedTeam;
    var index = controller.focusedPlayer;
    if (team != null && index != null) {
      controller.removePlayerKeyframe(team.id, index, frame);
      return;
    }
    var element = controller.selected;
    if (element != null) controller.removeKeyframe(element.id, frame);
  }

  /// _clearChannel takes every keyframe off whatever the strip is showing.
  ///
  /// "Channel" rather than "element" because that is what the strip is: one
  /// row of marks belonging to one thing, which may be an element or one
  /// player of a team. It is the row you are looking at, cleared.
  void _clearChannel() {
    var team = controller.focusedTeam;
    var index = controller.focusedPlayer;
    if (team != null && index != null) {
      controller.clearPlayerKeyframes(team.id, index);
      return;
    }
    var element = controller.selected;
    if (element != null) controller.clearElementKeyframes(element.id);
  }

  /// _canClearChannel is whether there is anything on this row to clear.
  ///
  /// Never for a path. A path's marks are its points -- where the curve goes,
  /// not a pose -- so clearing them would delete the route rather than its
  /// timing, and a path with no points is not a path. Its own row buttons are
  /// where a point is removed.
  bool get _canClearChannel {
    if (_selectedPath != null || _drivingPath != null) return false;
    var track = _targetTrack;
    return track != null && !track.isEmpty;
  }

  /// _addKeyframe writes the selected element's current pose at the playhead.
  ///
  /// The pose it writes is whatever the element is showing *now*, which is the
  /// pose interpolated from the surrounding keyframes. So pressing it on an
  /// empty frame pins the element where it currently appears rather than
  /// snapping it back to its resting position -- which is what "add a
  /// keyframe here" has to mean if it is to be usable for holding something
  /// still between two moves.
  void _addKeyframe() {
    if (!_hasTarget) return;
    var pose = (_targetTrack ?? ElementTrack.empty).at(controller.frame);
    _setTargetKey(pose.copyWith(frame: controller.frame));
  }

  void _addAction(TimelineActionKind kind) {
    var document = controller.document;
    var actions = [
      ...document.actions.where((a) => a.frame != controller.frame),
      TimelineAction(
        frame: controller.frame,
        kind: kind,
        // A loop with nothing to loop back to is useless, so it defaults to
        // the start -- which is what almost every loop marker means anyway.
        target: 0,
      ),
    ];
    controller.apply(document.copyWith(actions: actions));
  }

  void _removeAction(int frame) {
    var document = controller.document;
    controller.apply(document.copyWith(
        actions: document.actions.where((a) => a.frame != frame).toList()));
  }

  /// _keyframeToggle opens and closes the pose line.
  ///
  /// It sits immediately after the two keyframe buttons, because it is the
  /// rest of the same subject: they say *whether* there is a keyframe here,
  /// and the line behind this says what that keyframe does.
  Widget _keyframeToggle(ThemeNotifier theme, String? target, bool onAKey) =>
      CanvasIconButton(
        // A disclosure chevron rather than a diamond: the diamond next door is
        // what adds and removes a keyframe, and two diamonds side by side
        // doing different things is a coin toss. Which way it points says
        // where the line will appear.
        icon: widget.keyframesOpen ? Icons.expand_more : Icons.expand_less,
        tooltip: widget.keyframesOpen
            ? "Close the keyframe settings"
            : target == null
                ? "Keyframe settings"
                : "Keyframe settings for $target",
        active: widget.keyframesOpen,
        onPressed: widget.onToggleKeyframes,
      );

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var document = controller.document;
    var actionHere =
        document.actions.where((a) => a.frame == controller.frame).firstOrNull;
    var keyHere = _targetTrack?.keyAt(controller.frame);
    var target = _targetName;

    // The frames on screen: all of them, or the stretch zoomed to -- kept
    // up with the playhead while it plays, a page at a time.
    // To the end of the longest clip, where one runs on past the scene --
    // and along every scene while Play runs them all.
    if (_runs != _ranRun) {
      _ranRun = _runs;
      _view = null;
    }
    var frames = _total;
    var view = _view?.fitted(frames) ?? TimelineView.whole(frames);
    if (_view != null && controller.playing) {
      view = view.following(_origin + controller.frame, frames);
      _view = view;
    }
    _viewNow = view;

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Stack(children: [
        LayoutBuilder(
          builder: (context, box) => Listener(
            onPointerSignal: (e) => _onSignal(e, box.maxWidth),
            onPointerPanZoomStart: (_) => _pinch = 1,
            onPointerPanZoomUpdate: (e) => _onPanZoom(e, box.maxWidth),
            child: _body(context, theme, document, actionHere, keyHere, target),
          ),
        ),
        // The top edge is a grip: dragged up, the timeline opens room for the
        // channels under the keyframe strip; dragged down, it closes it.
        // The line between the strips and the frames: dragged, the column
        // of channel strips is wider or narrower, down to icons.
        if (!_collapsed)
          Positioned(
            // On the strips' side of the line only: over the lanes it covered
            // the fade handle of a sound starting on frame one.
            left: 10 + controller.headerWidth - 5,
            top: _stripPadTop + _transportHeight + _stripGap,
            bottom: 0,
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

  /// _gripFrom and _gripHeight are where a drag of the top edge began and
  /// how tall the timeline was then. Measured from there rather than by adding
  /// up the drag's steps: the first few pixels of a drag never arrive as one.
  double _gripFrom = 0, _gripHeight = timelineHeight;

  /// _stripHeader is the column beside the keyframe strip, the width of the
  /// channels' strips under it: the zoom, and what each row of marks is.
  Widget _stripHeader(ThemeNotifier theme, String? target) {
    var colors = theme.colors;
    var muted = TextStyle(fontSize: 10, color: colors.onSurfaceVariant);
    var frames = _total;
    var whole = _viewNow.isWhole(frames);
    // Big enough to hit: they were fifteen-pixel icons with a pixel round
    // them, which is a target to aim at rather than a button to press.
    Widget zoom(String key, IconData icon, VoidCallback? onTap) => InkResponse(
          key: ValueKey(key),
          radius: 14,
          onTap: onTap,
          child: SizedBox(
            width: 24,
            height: 24,
            child: Icon(icon,
                size: 19,
                color: onTap == null
                    ? colors.onSurfaceVariant.withValues(alpha: 0.35)
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
          // Narrowed, it keeps what it has room for: the zoom out and in
          // first, then the one button.
          child: Row(children: [
            if (controller.headerWidth >= 60)
              zoom("timelineZoomOut", Icons.zoom_out,
                  whole ? null : () => _zoomBy(0.5)),
            if (controller.headerWidth >= 100 ||
                (controller.headerWidth < 60 && controller.headerWidth >= 34))
              zoom("timelineZoomFit", Icons.fit_screen_outlined,
                  whole ? null : () => _setView(TimelineView.whole(frames))),
            if (controller.headerWidth >= 60)
              zoom(
                  "timelineZoomIn",
                  Icons.zoom_in,
                  _viewNow.span <= math.min(timelineMinSpan, frames) + 0.01
                      ? null
                      : () => _zoomBy(2)),
            const Spacer(),
            if (!whole && controller.headerWidth >= 170)
              Text(
                  "${(frames / _viewNow.span).toStringAsFixed(frames / _viewNow.span < 10 ? 1 : 0)}×",
                  style: muted),
          ]),
        ),
        if (_showScenes)
          Positioned(
            left: 0,
            right: 0,
            top: _rulerHeight + sceneStripLead,
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
        Positioned(
          left: 0,
          right: 0,
          top: _markRow - 8 + _sceneGap,
          height: 16,
          child: Row(children: [
            Icon(Icons.diamond_outlined,
                size: 11, color: colors.onSurfaceVariant),
            if (named) ...[
              const SizedBox(width: 4),
              Expanded(
                child: Text(target ?? "Keyframes",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted.copyWith(
                        fontWeight: FontWeight.w600, color: colors.onSurface)),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  /// _collapsed is the timeline dragged down to its play bar.
  bool get _collapsed => widget.height < timelineHeight - 0.5;

  /// _showScenes is whether the scene strip is under the ruler: while Play
  /// runs every scene, so what is playing, and how long each scene is, can
  /// be seen -- and changed -- as it plays. The timeline grows by the strip
  /// rather than taking it from the channels. See CanvasSceneStrip.
  bool get _showScenes => _runs && !_collapsed;

  Widget _body(
      BuildContext context,
      ThemeNotifier theme,
      CanvasDocument document,
      TimelineAction? actionHere,
      Keyframe? keyHere,
      String? target) {
    return Container(
      height: math.max(timelineCollapsedHeight, widget.height) +
          (_showScenes ? sceneStripHeight : 0),
      padding: const EdgeInsets.fromLTRB(10, _stripPadTop, 10,
          _stripPadBottom + _notesGutter - _scrollbarHeight),
      decoration: BoxDecoration(
        color: theme.colors.surfaceContainerLow,
        border: Border(
            top: BorderSide(color: theme.colors.outlineVariant, width: 1)),
      ),
      child: Column(children: [
        // Scrolls sideways rather than overflowing. The row grew when the
        // animation settings moved here from the band above, and on a narrow
        // window a Row that cannot break is a red-and-yellow stripe rather
        // than a control anybody can reach.
        // Captions as hover text: "Frame", "Length", "Per second" were a
        // line of grey words over the play bar, a line of the timeline's
        // height, for controls known by what is in them.
        SizedBox(
          height: _transportHeight,
          child: CanvasControlScope(
            maxWidth: 400,
            hoverCaptions: true,
            child: Row(children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    CanvasIconButton(
                      key: const ValueKey("toFirstFrame"),
                      icon: Icons.skip_previous,
                      tooltip: "",
                      onPressed: controller.rewind,
                    ),
                    CanvasIconButton(
                      icon: controller.playing ? Icons.pause : Icons.play_arrow,
                      key: const ValueKey("play"),
                      tooltip: controller.playing ? "Pause" : "",
                      active: controller.playing,
                      onPressed: (controller.playAll && document.hasScenes
                                  ? document.playFrames
                                  : document.frames) >
                              1
                          ? controller.togglePlay
                          : null,
                    ),
                    // Which of the two Play means. Only where there is more than
                    // one canvas: on a single scene the two are the same thing.
                    if (document.hasScenes)
                      CanvasIconButton(
                        key: const ValueKey("playAll"),
                        icon: controller.playAll
                            ? Icons.playlist_play
                            : Icons.filter_1,
                        tooltip: "Play all scenes",
                        active: controller.playAll,
                        onPressed: () =>
                            controller.playAll = !controller.playAll,
                      ),
                    CanvasIconButton(
                      icon: Icons.chevron_left,
                      key: const ValueKey("previousFrame"),
                      tooltip: "Previous frame",
                      onPressed: () => controller.stepFrame(-1),
                    ),
                    CanvasIconButton(
                      icon: Icons.chevron_right,
                      key: const ValueKey("nextFrame"),
                      tooltip: "Next frame",
                      onPressed: () => controller.stepFrame(1),
                    ),
                    // And to the next mark rather than the next frame. Stepping a
                    // frame at a time to reach a keyframe eighty frames away is
                    // eighty presses, and dragging the playhead there lands one
                    // frame off as often as on -- which is the difference between
                    // editing the pose that is there and laying a new one beside
                    // it.
                    CanvasIconButton(
                      key: const ValueKey("prevKeyframe"),
                      icon: Icons.keyboard_double_arrow_left,
                      tooltip: _keyframeFrames.isEmpty
                          ? "No keyframes"
                          : "Back to the previous keyframe",
                      onPressed: _keyframeFrames.isEmpty
                          ? null
                          : () => _goToKeyframe(-1),
                    ),
                    CanvasIconButton(
                      key: const ValueKey("nextKeyframe"),
                      icon: Icons.keyboard_double_arrow_right,
                      tooltip: _keyframeFrames.isEmpty
                          ? "No keyframes"
                          : "On to the next keyframe",
                      onPressed: _keyframeFrames.isEmpty
                          ? null
                          : () => _goToKeyframe(1),
                    ),
                    const SizedBox(width: 6),
                    // The playhead and the document's length, as one control reading
                    // "frame 288 of 600". They were a readout and a separate Frames
                    // field a few pixels apart, saying the same number twice -- and the
                    // field was too narrow for four digits, so a long document showed
                    // "10000" clipped to "1000".
                    CanvasNumberField(
                      key: const ValueKey("canvasFrame"),
                      label: "Frame",
                      // One-based on screen and zero-based underneath, because the first
                      // frame of an animation is frame 1 to everybody except a computer.
                      value: (controller.frame + 1).toDouble(),
                      min: 1,
                      max: document.frames.toDouble(),
                      width: 68,
                      onChanged: (v) => controller
                          .stepFrame(v.round() - 1 - controller.frame),
                    ),
                    Padding(
                      // Level with the fields: there is no caption over them
                      // to sit under any more.
                      padding: const EdgeInsets.only(right: 2),
                      child: SizedBox(
                        height: controlHeight,
                        child: Center(
                          child: Text("/",
                              style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colors.onSurfaceVariant)),
                        ),
                      ),
                    ),
                    // The master canvas is as long as the scenes it covers, so
                    // there is nothing here to set: it was a field that took a
                    // number and put the old one back, which reads as the field
                    // being broken rather than as the length not being its own.
                    if (document.editingMaster)
                      Tooltip(
                        message:
                            "How long the whole sequence runs: every scene "
                            "end to end. The master canvas is as long as what it "
                            "covers, so this follows the scenes rather than being "
                            "set here.",
                        child: CanvasReadout(
                          key: const ValueKey("canvasFramesMaster"),
                          label: "Length",
                          width: 68,
                          value: "${document.frames}",
                        ),
                      )
                    else
                      CanvasNumberField(
                        key: const ValueKey("canvasFrames"),
                        label: "Length",
                        value: document.frames.toDouble(),
                        min: 1,
                        max: maxFrameCount.toDouble(),
                        width: 68,
                        onChanged: (v) {
                          controller.beginInteraction();
                          controller.apply(document.copyWith(frames: v.round()),
                              transient: true);
                        },
                        onCommit: controller.endInteraction,
                      ),
                    CanvasNumberField(
                      key: const ValueKey("canvasFrameRate"),
                      label: "Per second",
                      value: document.frameRate.toDouble(),
                      min: 1,
                      max: 60,
                      width: 60,
                      onChanged: (v) {
                        controller.beginInteraction();
                        controller.apply(
                            document.copyWith(frameRate: v.round()),
                            transient: true);
                      },
                      onCommit: controller.endInteraction,
                    ),
                    SizedBox(
                      // Room for the longest duration a canvas can have: an hour of
                      // frames at one a second.
                      width: 62,
                      height: controlHeight,
                      // Level with the rate it is worked out from.
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          document.isAnimated
                              ? "${document.durationSeconds.toStringAsFixed(1)}s"
                              : "Still",
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              color: theme.colors.onSurfaceVariant),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // The two keyframe buttons stay on the transport row: they are
                    // pressed constantly while animating, and neither changes width, so
                    // neither can shift the row. What moved off is the *pose* controls
                    // -- easing, fade, scale, turn -- which appeared and vanished as the
                    // playhead crossed a keyframe and took the play buttons with them.
                    CanvasIconButton(
                      icon: Icons.fiber_manual_record,
                      tooltip: "Auto Keyframe",
                      active: controller.autoKeyframe,
                      onPressed: () =>
                          controller.autoKeyframe = !controller.autoKeyframe,
                    ),
                    CanvasIconButton(
                      icon: keyHere != null
                          ? Icons.diamond
                          : Icons.diamond_outlined,
                      // Short, but not wrong: a player following a path has
                      // its timing on the path's points, not here.
                      tooltip: _drivingPath != null
                          ? "Following a path"
                          : keyHere != null
                              ? "Remove Keyframe"
                              : "Add Keyframe",
                      active: keyHere != null,
                      onPressed: !_hasTarget
                          ? null
                          : keyHere != null
                              ? () => _removeTargetKey(controller.frame)
                              : _addKeyframe,
                    ),
                    // Clearing, beside the diamond that adds and removes one. The wider
                    // of the two is guarded by needing something to clear rather than by
                    // a dialog: both are one undo step, and a confirmation on every
                    // press is worse than an undo on the rare one.
                    CanvasIconButton(
                      icon: Icons.layers_clear_outlined,
                      tooltip: _drivingPath != null
                          ? "Following a path"
                          : "Clear Channel Keyframes",
                      onPressed: _canClearChannel ? _clearChannel : null,
                    ),
                    CanvasIconButton(
                      icon: Icons.delete_sweep_outlined,
                      tooltip: "Clear all keyframes",
                      onPressed: document.hasKeyframes
                          ? controller.clearAllKeyframes
                          : null,
                    ),
                    _keyframeToggle(theme, target, keyHere != null),
                    // A fixed gap rather than a Spacer: the row scrolls, so it has no
                    // width to divide up and a Spacer inside it is an unbounded
                    // constraint rather than a space.
                    const SizedBox(width: 24),
                    // One button for an action here, which is a stop until
                    // "At this frame" says otherwise: four buttons for four
                    // kinds was a row of look-alikes for one thing.
                    if (actionHere == null)
                      CanvasIconButton(
                        key: const ValueKey("addAction"),
                        icon: Icons.flag_outlined,
                        tooltip: "Add Timeline Action",
                        onPressed: () => _addAction(TimelineActionKind.stop),
                      )
                    else ...[
                      CanvasDropdown<TimelineActionKind>(
                        label: "At this frame",
                        value: actionHere.kind,
                        width: 116,
                        options: [
                          for (var k in TimelineActionKind.values) (k, k.label)
                        ],
                        onChanged: (v) =>
                            _replaceAction(actionHere.copyWith(kind: v)),
                      ),
                      // A word or two beside the flag, and whether it shows.
                      CanvasTextField(
                        key: const ValueKey("actionLabel"),
                        label: "Label",
                        value: actionHere.label,
                        width: 110,
                        grow: false,
                        onChanged: (v) {
                          controller.beginInteraction();
                          var document = controller.document;
                          controller.apply(
                              document.copyWith(actions: [
                                for (var a in document.actions)
                                  a.frame == actionHere.frame
                                      ? a.copyWith(label: v)
                                      : a,
                              ]),
                              transient: true);
                        },
                        onCommit: controller.endInteraction,
                      ),
                      CanvasToggle(
                        key: const ValueKey("actionShowLabel"),
                        label: "Show label",
                        value: actionHere.showLabel,
                        onChanged: (v) =>
                            _replaceAction(actionHere.copyWith(showLabel: v)),
                      ),
                      if (actionHere.kind == TimelineActionKind.loop ||
                          actionHere.kind == TimelineActionKind.jump)
                        CanvasNumberField(
                          label: "To frame",
                          value: actionHere.target.toDouble(),
                          min: 0,
                          max: (document.frames - 1).toDouble(),
                          width: 56,
                          onChanged: (v) => _replaceAction(
                              actionHere.copyWith(target: v.round())),
                        ),
                      if (actionHere.kind == TimelineActionKind.loop)
                        CanvasNumberField(
                          label: "Times (0 = ∞)",
                          value: actionHere.repeats.toDouble(),
                          min: 0,
                          max: 999,
                          width: 56,
                          onChanged: (v) => _replaceAction(
                              actionHere.copyWith(repeats: v.round())),
                        ),
                      CanvasIconButton(
                        icon: Icons.close,
                        tooltip: "Remove this marker",
                        onPressed: () => _removeAction(actionHere.frame),
                      ),
                    ],
                  ]),
                ),
              ),
              // Pinned at the far end, outside the part that scrolls, so they
              // are always in the same place: what a press on a sound does,
              // whether the trackpad moves the timeline, and the mixer.
              CanvasIconButton(
                key: const ValueKey("toolSelect"),
                icon: Icons.near_me_outlined,
                tooltip: "Select",
                active: controller.timelineTool == TimelineTool.select,
                onPressed: () => controller.timelineTool = TimelineTool.select,
              ),
              CanvasIconButton(
                key: const ValueKey("toolKnife"),
                icon: Icons.content_cut,
                tooltip: "Knife (K)",
                active: controller.timelineTool == TimelineTool.knife,
                onPressed: () => controller.timelineTool = TimelineTool.knife,
              ),
              CanvasIconButton(
                key: const ValueKey("snap"),
                icon: Icons.grid_4x4,
                tooltip: "Timeline snapping",
                active: controller.snapping,
                onPressed: () => _setSnapping(!controller.snapping),
              ),
              CanvasIconButton(
                key: const ValueKey("trackpadScrolls"),
                icon: Icons.swipe_outlined,
                tooltip: "Scrubbing",
                active: _trackpadScrolls,
                onPressed: () => _setTrackpadScrolls(!_trackpadScrolls),
              ),
            ]),
          ),
        ),
        if (!_collapsed) const SizedBox(height: _stripGap),
        if (!_collapsed)
          SizedBox(
            // Less the border along the timeline's top, which comes out of the
            // same height: the height the strip always had, when it filled
            // what was left.
            height: _stripHeight - 1 + _sceneGap,
            // A firm line under the keyframes: the channels scroll up under
            // it, and without one they seemed to vanish into the strip.
            child: Container(
              foregroundDecoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(
                          color: theme.colors.outline.withValues(alpha: 0.8)))),
              child: Row(children: [
                _stripHeader(theme, target),
                Expanded(
                    child: LayoutBuilder(
                  builder: (context, constraints) => Stack(children: [
                    GestureDetector(
                      supportedDevices: timelinePointers,
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        controller.pause();
                        // Selected on the press and the playhead moved on the
                        // release. Moving it here moved it the instant a mark was
                        // touched -- including at the start of a drag, so the frame
                        // somebody had lined the playhead up with as a guide was
                        // gone before they had dragged anywhere. A drag never
                        // reaches onTapUp, which is exactly the distinction wanted.
                        var mark = _keyframeAt(
                            details.localPosition, constraints.maxWidth);
                        var band = mark != null
                            ? null
                            : _bandAt(
                                details.localPosition, constraints.maxWidth);
                        setState(() {
                          if (mark != null) {
                            // Shift adds to the selection; an ordinary click starts
                            // a new one.
                            if (!_shiftHeld) _selectedKeys.clear();
                            if (!_selectedKeys.add(mark) && _shiftHeld) {
                              _selectedKeys.remove(mark);
                            }
                          } else if (band != null) {
                            // Both ends. The bar is what says the two belong
                            // together, so picking it up picks up the pair.
                            if (!_shiftHeld) _selectedKeys.clear();
                            _selectedKeys.addAll(band);
                          } else {
                            _selectedKeys.clear();
                          }
                        });
                      },
                      onTapUp: (details) {
                        // Focus is asked for here rather than on the press: the
                        // press is followed by the framework handing focus to the
                        // enclosing scope, so a request made before that is undone
                        // by it -- and without focus the strip never sees Delete,
                        // copy or paste.
                        if (_selectedKeys.isNotEmpty) {
                          FocusScope.of(context).requestFocus(_focus);
                        }
                        // The click has turned out to be a click. A mark puts the
                        // playhead on itself, which is what anybody wants from
                        // clicking a keyframe -- to be looking at the pose they are
                        // about to change -- and anywhere else scrubs.
                        var mark = _keyframeAt(
                            details.localPosition, constraints.maxWidth);
                        if (mark != null) {
                          controller.frame = mark;
                        } else {
                          _scrubTo(
                              details.localPosition.dx, constraints.maxWidth);
                        }
                      },
                      // A drag that starts on a mark retimes that mark; anywhere else
                      // it scrubs. Deciding once, at the start, rather than on every
                      // update: a mark dragged past the pointer's own starting row
                      // would otherwise stop being dragged half way through.
                      // The mark is found on the *press*, not on the drag start.
                      // A horizontal drag is not recognised until the pointer has
                      // moved about eighteen pixels, by which time its reported start
                      // is well past whatever it was aimed at -- so looking for a mark
                      // there finds nothing, and every attempt to retime one scrubbed
                      // instead.
                      onHorizontalDragDown: (details) {
                        // A flag on the ruler first: it is what the press is
                        // on, and dragged, it moves.
                        _pressedFlag = _flagAt(
                            details.localPosition, constraints.maxWidth);
                        _pressedFrame = _pressedFlag != null
                            ? null
                            : _keyframeAt(
                                details.localPosition, constraints.maxWidth);
                        // The bar between a pair, when the press was not on either
                        // end of it. A mark wins: dragging one end is how the
                        // length of an animation is changed, and dragging the
                        // middle is how it is moved without changing it.
                        _pressedBand = _pressedFrame != null
                            ? null
                            : _bandAt(
                                details.localPosition, constraints.maxWidth);
                      },
                      onHorizontalDragStart: (details) {
                        controller.pause();
                        _dragFlag = _pressedFlag;
                        if (_dragFlag != null) controller.beginInteraction();
                        _dragKey = _pressedFrame;
                        _dragBand = _pressedBand;
                        _bandAnchor = _frameAt(
                            details.localPosition.dx, constraints.maxWidth);
                      },
                      onHorizontalDragUpdate: (details) {
                        var at = _frameAt(
                            details.localPosition.dx, constraints.maxWidth);
                        if (_dragFlag != null) {
                          if (_moveAction(_dragFlag!, at)) _dragFlag = at;
                          return;
                        }
                        if (_dragBand != null) {
                          _shiftBand(at);
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
                        if (_dragFlag != null) controller.endInteraction();
                        _dragFlag = null;
                        _pressedFlag = null;
                        _dragKey = null;
                        _dragBand = null;
                        _pressedFrame = null;
                        _pressedBand = null;
                      },
                      onHorizontalDragCancel: () {
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
                          // Ticks along the whole of what is laid out: the
                          // run, where the timeline runs, counted from the
                          // scene's own start.
                          origin: _origin,
                          frames: _total - _origin,
                          scene: _runs ? _total - _origin : document.frames,
                          marks: _markRow + _sceneGap,
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
                          // The focused player's, when one is focused -- see
                          // _targetTrack. The marks on the ruler have to be the same
                          // keyframes the diamond button adds and removes, or the
                          // strip shows one player's run while the button edits
                          // another's.
                          keyframes: _targetTrack?.keys ?? const [],
                          bands: _bands,
                          selected: _selectedKeys,
                          actions: document.actions,
                          colors: theme.colors,
                          xFor: (f) => _xFor(f, constraints.maxWidth),
                        ),
                      ),
                    ),
                    // The scenes, under the ruler and over the keyframes,
                    // on the ruler's own scale.
                    if (_showScenes)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: _rulerHeight + sceneStripLead,
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
        // The channels: the media on the timeline, one lane each, in
        // whatever room the timeline has been dragged open to.
        if (widget.height > timelineHeight + 4)
          Expanded(
              child: CanvasChannels(controller: controller, view: _sceneView)),
        // Which stretch of the timeline is on screen, and a handle to move
        // it: under the frames, not the strip column.
        if (!_collapsed)
          SizedBox(
            height: _scrollbarHeight,
            child: Row(children: [
              SizedBox(width: controller.headerWidth),
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
      ]),
    );
  }

  /// _onKey is the transport's keyboard, matching the canvas's exactly.
  ///
  /// Needed as well as the canvas's because focus lands in here the moment any
  /// of these controls is pressed -- and a space bar that plays until you touch
  /// the timeline, then stops working, is worse than no shortcut at all. The
  /// arrows are claimed for the same reason: unclaimed, Flutter spends them on
  /// directional focus traversal between the buttons.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Never while somebody is typing. See isTypingInAField: this handler runs
    // before the app's text-editing shortcuts do, so without this the arrow
    // keys scrubbed instead of moving the caret and the space bar started
    // playback instead of typing a space.
    if (isTypingInAField()) return KeyEventResult.ignored;
    // Delete on a selected mark removes the keyframe, not the element. The
    // canvas's own Delete deletes what is selected there, and with a keyframe
    // picked out on the strip that is the wrong thing by a long way: one is a
    // pose, the other is the whole element and everything on it.
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
    // pair for elements; which of the two answers is decided by where the
    // focus is, which is where the last click was.
    var meta = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    // Only with marks to copy, and marks to paste onto something that takes
    // them: otherwise the keys go on to the page, which copies and pastes
    // what is selected -- a sound clicked on the timeline, say.
    var clipChosen = controller.selectedElements
        .any((e) => e is AudioElement && e.clip.timed);
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

    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
        controller.togglePlay();
      case LogicalKeyboardKey.arrowLeft:
        controller.stepFrame(-1);
      case LogicalKeyboardKey.arrowRight:
        controller.stepFrame(1);
      case LogicalKeyboardKey.arrowUp:
        controller.stepFrame(-10);
      case LogicalKeyboardKey.arrowDown:
        controller.stepFrame(10);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// _keyframeAt is the mark under [local], or null.
  ///
  /// Only in the keyframe row's own band -- see _TimelinePainter, which draws
  /// them at _rulerHeight + 14. A drag that starts on the ruler's numbers is a
  /// scrub even if it happens to begin above a mark, because that is where the
  /// playhead is grabbed.
  int? _keyframeAt(Offset local, double width) {
    var keys = _targetTrack?.keys ?? const <Keyframe>[];
    if (keys.isEmpty) return null;
    if ((local.dy - _markRow - _sceneGap).abs() > _markGrabHeight) return null;

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

  /// _bands is the pairs of keyframes on the target that belong together.
  ///
  /// Only an element's own: a player's track has no channel with two ends,
  /// and a path's marks are its points.
  List<KeyframeBand> get _bands {
    if (controller.focusedPlayer != null) return const [];
    if (_selectedPath != null) return const [];
    return bandsIn(controller.selected?.track);
  }

  /// _bandAt is the band under [local], or null.
  ///
  /// The bar is drawn on the keyframe row, so it is grabbed there -- and only
  /// between the two marks rather than on them, because dragging one end to
  /// change the length has to stay possible.
  List<int>? _bandAt(Offset local, double width) {
    if ((local.dy - _markRow - _sceneGap).abs() > _markGrabHeight) return null;
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
    // timeline slides up against it instead of stopping dead half a frame
    // early.
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
    });
  }

  void _replaceAction(TimelineAction action) {
    var document = controller.document;
    controller.apply(document.copyWith(actions: [
      ...document.actions.where((a) => a.frame != action.frame),
      action,
    ]));
  }
}

/// rulerSteps is how far apart, in frames, the ruler's three sizes of tick
/// are at [pixelsPerFrame]: a number and a line through the ruler every so
/// many whole seconds -- as many as fit with room around them -- a mid tick
/// that divides it, and a small one that divides that. Null where a size
/// would be too close together to see.
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
/// the timeline runs along every scene, so the numbers go on through them,
/// and counted from one, as the Frame box counts.
int rulerNumber(int frame, int origin) => frame + origin + 1;

/// _TimelinePainter draws the ruler, the two rows of marks and the playhead.
class _TimelinePainter extends CustomPainter {
  final TimelineView view;
  final int frames;

  /// scene is how many frames the scene has; [frames] runs on past it where
  /// a clip does, and that stretch is shaded.
  final int scene;

  /// origin is where the scene starts in what is laid out -- the run, while
  /// the timeline runs -- so the ruler is ticked from the run's own start
  /// rather than the scene's. Nought otherwise.
  final int origin;

  /// marks is how far down the keyframes are drawn: under the scene strip,
  /// where it shows.
  final double marks;

  /// sceneStarts is where each scene starts, in this painter's frames --
  /// just the one, at nought, unless the timeline runs along every scene.
  /// Each later one is marked on the ruler, over its join in the scene strip.
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
  final ColorScheme colors;
  final double Function(int) xFor;

  const _TimelinePainter({
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
    required this.colors,
    required this.xFor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Zoomed in, marks and bars run past either edge: drawn, and cut there.
    canvas.clipRect(Offset.zero & size);
    var track = Rect.fromLTWH(0, 0, size.width, _rulerHeight);
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, const Radius.circular(4)),
      Paint()..color = colors.surfaceContainerHighest,
    );

    // Ticks hang from the top edge in three sizes -- frames, seconds, and a
    // line through the whole ruler where a number is written -- and the
    // numbers sit under the ticks, beside their line, big enough to read.
    // Counted along the whole run where the timeline runs, so the numbers go
    // on through every scene rather than starting again at each; and from
    // one, the way the Frame box counts.
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

    // The bars first, under the marks they join: a chart's entrance and its
    // exit are each two keyframes that mean nothing apart, and two marks with
    // nothing between them are two marks somebody will separate by accident.
    // Dragging the bar moves both -- see _shiftBand.
    _paintBands(canvas, y: marks);

    _paintMarks(
      canvas,
      size,
      y: marks,
      frames: [for (var k in keyframes) k.frame],
      // Muted, the same weight as the transport's own icons. They were all
      // drawn in the accent, which is the colour that means "this one" -- so
      // with every mark shouting, the selected one had nothing left to say
      // with and needed a ring drawn round it to be picked out at all.
      color: colors.onSurfaceVariant.withValues(alpha: 0.65),
      diamond: true,
      selected: selected,
      selectedColor: colors.primary,
    );
    _paintMarkers(canvas);

    // The playhead last, over everything, because it is the one mark that has
    // to be findable at a glance in a timeline covered in others.
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
  /// through the ticks, and a pennant at the top.
  ///
  /// A different colour from the keyframes, which is the whole job of it --
  /// but not tertiary, which is a panel background in this app and drew these
  /// marks in near-black on a near-black ruler.
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

  /// _paintBands draws the bar between each pair.
  ///
  /// Translucent rather than solid, because it lies over the ruler's own ticks
  /// and the second it hides them it stops being possible to see where the
  /// animation starts. The entrance and the exit are different colours for
  /// the same reason the two rows of marks are: they are different things and
  /// a strip with two identical bars on it says they are the same.
  void _paintBands(Canvas canvas, {required double y}) {
    for (var band in bands) {
      if (!band.real) continue;
      var from = xFor(band.from);
      var to = xFor(band.to);
      var colour = band.channel == KeyframeChannel.close
          ? colors.secondary
          : colors.primary;
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

    /// selected is drawn in [selectedColor] instead of [color]. The colour is
    /// the whole signal -- a ring as well was belt and braces on a mark nine
    /// pixels wide.
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

  /// _sameBands compares two lists of pairs by what is in them.
  ///
  /// Worked out fresh on every build, so the lists are never the same object
  /// and identity would repaint the strip sixty times a second.
  static bool _sameBands(List<KeyframeBand> a, List<KeyframeBand> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].from != b[i].from ||
          a[i].to != b[i].to ||
          a[i].channel != b[i].channel) {
        return false;
      }
    }
    return true;
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
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
      old.actions != actions;
}

/// CanvasKeyframeBar is what the keyframe at the playhead actually does:
/// easing, fade, scale and turn.
///
/// Floated over the bottom of the canvas area by the screen, above the
/// timeline, rather than being a row inside it. As a row it made the strip
/// taller, which took height from the canvas area and re-fitted the canvas --
/// so opening a panel moved the design. The canvas settings float for the same
/// reason; see CanvasSettingsPanel.
///
/// It is not shown during playback: none of it can be used then, and it is the
/// last thing the eye should be on when what is being watched is the canvas.
class CanvasKeyframeBar extends StatefulWidget {
  final CanvasController controller;
  const CanvasKeyframeBar({required this.controller, super.key});

  @override
  State<CanvasKeyframeBar> createState() => _CanvasKeyframeBarState();
}

class _CanvasKeyframeBarState extends State<CanvasKeyframeBar> {
  CanvasController get controller => widget.controller;

  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_onChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// _target and _track answer "whose keyframe is this", and are the same
  /// question the timeline asks -- a focused player when one has been clicked,
  /// otherwise the selected element. See CanvasController.focusedPlayer.
  String? get _target {
    var team = controller.focusedTeam;
    var index = controller.focusedPlayer;
    if (team != null && index != null && index < team.players.length) {
      var spot = team.players[index];
      var who = spot.name.isNotEmpty ? spot.name : "#${spot.number}";
      return "$who (${team.name})";
    }
    return controller.selected?.name;
  }

  PathElement? get _drivingPath => _pathDriving(controller);

  ElementTrack? get _trackHere {
    var team = controller.focusedTeam;
    var index = controller.focusedPlayer;
    if (team != null && index != null && index < team.players.length) {
      return team.players[index].track;
    }
    var path = controller.selected;
    if (path is PathElement) {
      return ElementTrack([for (var n in path.nodes) Keyframe(frame: n.frame)]);
    }
    return controller.selected?.track;
  }

  void _setTargetKey(Keyframe key) {
    var team = controller.focusedTeam;
    var index = controller.focusedPlayer;
    if (team != null && index != null) {
      controller.setPlayerKeyframe(team.id, index, key);
      return;
    }
    var element = controller.selected;
    if (element != null) controller.setKeyframe(element.id, key);
  }

  /// _message is the bar showing one line of text instead of controls.
  Widget _message(ThemeNotifier theme, String text) => Material(
        color: theme.colors.surfaceContainerLow,
        elevation: 6,
        child: Container(
          height: keyframeBarHeight,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            border: Border(
                top: BorderSide(color: theme.colors.outlineVariant, width: 1)),
          ),
          child: Text(text,
              style: TextStyle(
                  fontSize: 11, color: theme.colors.onSurfaceVariant)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var keyHere = _trackHere?.keyAt(controller.frame);
    var target = _target;
    var path = controller.selected;

    // Whatever a path is driving has no poses of its own to show: they are the
    // route's, rewritten every time a point moves.
    var driver = _drivingPath;
    if (driver != null) {
      return _message(
        theme,
        "$target is following ${driver.name}. Its timing is that path's "
        "points — select the path to change when it gets where.",
      );
    }

    // A path's marks are points on a route, not poses. Easing, fade, scale and
    // turn all belong to the follower rather than to the point, so offering
    // them here would be four controls that quietly do nothing.
    if (path is PathElement) {
      return _message(
        theme,
        keyHere == null
            ? "No point on this frame. The diamond adds one, "
                "and points drag along the strip to retime the run."
            : "Point ${(path.nodeIndexAtFrame(controller.frame) ?? 0) + 1} "
                "of ${path.nodes.length}. Drag it along the strip to change "
                "when ${controller.followerLabel(path.follow)} reaches it.",
      );
    }

    return Material(
      // Opaque and raised: it sits on top of the design rather than above it,
      // so it has to read as a thing in front.
      color: theme.colors.surfaceContainerLow,
      elevation: 6,
      child: Container(
        height: keyframeBarHeight,
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
        decoration: BoxDecoration(
          border: Border(
              top: BorderSide(color: theme.colors.outlineVariant, width: 1)),
        ),
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            // Opened on a frame with no keyframe on it, the line would
            // otherwise be blank, which reads as broken rather than as empty.
            if (keyHere == null)
              Padding(
                padding: const EdgeInsets.only(top: controlLabelHeight),
                child: SizedBox(
                  height: controlHeight,
                  child: Center(
                    child: Text(
                      target == null
                          ? "Select an element, or click a player, to give it "
                              "a keyframe."
                          : "No keyframe on this frame. Add one to set how "
                              "$target eases, fades, scales and turns.",
                      style: TextStyle(
                          fontSize: 11, color: theme.colors.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
            if (keyHere != null) ...[
              CanvasDropdown<KeyframeEasing>(
                label: "Easing",
                value: keyHere.easing,
                width: 108,
                options: [for (var e in KeyframeEasing.values) (e, e.label)],
                onChanged: (v) => _setTargetKey(keyHere.copyWith(easing: v)),
              ),
              CanvasSlider(
                label: "Fade",
                value: keyHere.opacity,
                onChanged: (v) {
                  controller.beginInteraction();
                  _setTargetKey(keyHere.copyWith(opacity: v));
                },
                onCommit: controller.endInteraction,
              ),
              CanvasSlider(
                label: "Scale",
                value: keyHere.scale,
                min: 0.05,
                max: 4,
                onChanged: (v) {
                  controller.beginInteraction();
                  _setTargetKey(keyHere.copyWith(scale: v));
                },
                onCommit: controller.endInteraction,
              ),
              CanvasNumberField(
                label: "Turn",
                value: keyHere.rotate,
                min: -1440,
                max: 1440,
                width: 56,
                suffix: "°",
                onChanged: (v) => _setTargetKey(keyHere.copyWith(rotate: v)),
                onCommit: controller.endInteraction,
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// _TimelineScrollbar shows which stretch of the timeline is on screen, and is
/// dragged to move it -- or clicked, to jump there.
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
