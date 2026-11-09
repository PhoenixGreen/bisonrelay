import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/storage_manager.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/help_note.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart'
    show MotionEditing;
import 'package:bruig/plugin_system/canvas/ui/canvas_channels.dart';
import 'package:bruig/plugin_system/canvas/ui/scene_strip.dart';
import 'package:bruig/plugin_system/canvas/ui/slots_window.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_view.dart';
import 'package:bruig/plugin_system/canvas/ui/play_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_columns.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/image_timeline.dart';
import 'package:bruig/theming_system/theme_manager.dart';
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

/// _stripHeight is the strip: the ruler, with its markers and cues. The
/// keyframes are the Chain's (Ken, 2026-11-09: "I'd like keyframing done in
/// the chain"): see keyframes_card.dart.
const double _stripHeight = _rulerHeight + 2;

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

/// timelineHelp is the timeline's "?".
const timelineHelp = [
  "One row for each element: its motion over its sound. The channel height "
      "(S, M or L) says how much each row shows; at L each motion layer has "
      "its own band.",
  "Framing: the whole canvas, the loop, or the clip picked. Zoom with "
      "Command and the scroll wheel, or a pinch.",
  "Drag a clip to move it. Click a row's header to pick it for the Chain; "
      "its buttons switch its motion and its sound off, and solo it.",
  "Keyframes are made in the Chain: its Keyframes card, first in the "
      "Motion view, and their Curves.",
];

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

  const CanvasTimeline({
    required this.controller,
    this.height = timelineHeight,
    this.onResize,
    this.showBar = true,
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

  /// _pressedBrace and _dragBrace are the part of the loop brace (the control
  /// bar's Loop, along the top of the ruler) a press is on and the one being
  /// dragged; _braceFrom where the drag took hold, and _braceWas the loop
  /// then. See _braceAt.
  _BracePart? _pressedBrace;
  _BracePart? _dragBrace;
  int _braceFrom = 0;
  (int, int) _braceWas = (0, 1);

  /// _focus is what lets the transport's keys reach the timeline.
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
    var height = math.max(timelineCollapsedHeight, widget.height);
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

  /// _slotsW is the slots' column beside the rows, as the controller has it.
  /// (The Slots panel is a launcher of its own: see CanvasSlotsPanel.)
  double get _slotsW => controller.slotsWidth;

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
    setState(() {});
  }

  /// _frameAt turns a horizontal position into a frame number of the scene
  /// being edited.
  int _frameAt(double x, double width) =>
      _sceneView.frameAt(x, width, controller.document.frames);

  double _xFor(int frame, double width) => _sceneView.centreOf(frame, width);

  /// _pressX is where the pointer went down on the strip. A drag is only
  /// recognised some way past it, so a drag of the loop brace measures from
  /// here, not from where it was recognised.
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

  /// _sceneGap is the room the scene strip took under the keyframes: none,
  /// the scenes being the first of the rows now (Ken, 2026-11-08, "the scene
  /// channel part of the timeline rather than having a divider").
  double get _sceneGap => 0;

  /// _keysRoom is the strip's height: the ruler, with its playhead, markers
  /// and cues.
  double get _keysRoom => _stripHeight;

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

  @override
  // No hover tips on the timeline (the approved design): a "?" explains.
  Widget build(BuildContext context) =>
      TooltipVisibility(visible: false, child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var document = controller.document;
    var actionHere =
        document.actions.where((a) => a.frame == controller.frame).firstOrNull;

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
            return Listener(
              onPointerSignal: (e) => _onSignal(e, box.maxWidth),
              onPointerPanZoomStart: (_) => _pinch = 1,
              onPointerPanZoomUpdate: (e) => _onPanZoom(e, box.maxWidth),
              child: TimelineColumns(
                slotsWidth: _slotsW,
                headerWidth: controller.headerWidth,
                child: _body(context, theme, document, actionHere),
              ),
            );
          },
        ),
        // The line between the slots and the time, where the slots are out
        // beside the rows: dragged, the slots' column is wider or narrower,
        // the slots themselves one size.
        if (!_collapsed && _slotsW > 0)
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

  /// _pickedRange is the picked clip's stretch of the timeline, in the
  /// view's frames: a motion clip placed, or a sound picked on its lane.
  (double, double)? _pickedRange() {
    var rate = math.max(1, controller.document.frameRate);
    if (controller.pickedPlacement case var id?) {
      if (controller.spanOf(id) case var span?) {
        return (_origin + span.start * rate, math.max(1.0, span.length * rate));
      }
    }
    var picked = controller.selected;
    if (picked is AudioElement && picked.clip.timed) {
      return (
        (_origin + picked.clip.at).toDouble(),
        math.max(1.0, picked.clip.runLength * rate)
      );
    }
    return null;
  }

  /// _corner is the top of the header column: the framing -- the whole
  /// canvas, the loop, the clip picked -- and the channel height. Narrowed,
  /// it keeps the framing chosen and the height, then the height alone.
  /// (Each step is where what it shows fits at any text size.)
  Widget _corner(double width, ColorScheme colors) {
    var frames = _total;
    var view = _viewNow;
    bool same(double first, double span) =>
        (view.first - first).abs() < 0.5 && (view.span - span).abs() < 0.5;
    var (loopFrom, loopLength) = controller.loopRange;
    var loop = ((_origin + loopFrom).toDouble(), loopLength.toDouble());
    var picked = _pickedRange();
    var framings = [
      (
        "timelineFrameAll",
        Icons.fit_screen_outlined,
        view.isWhole(frames),
        () => _setView(TimelineView.whole(frames))
      ),
      (
        "timelineFrameLoop",
        Icons.repeat,
        same(loop.$1, loop.$2),
        () {
          if (!controller.looping) controller.looping = true;
          _setView(TimelineView(loop.$1, loop.$2));
        }
      ),
      (
        "timelineFramePicked",
        Icons.center_focus_strong_outlined,
        picked != null && same(picked.$1, picked.$2),
        picked == null
            ? null
            : () => _setView(TimelineView(picked.$1, picked.$2))
      ),
    ];
    Widget button(String key, IconData icon, bool on, VoidCallback? onTap) =>
        InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: on ? colors.primary : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(icon,
                size: 13,
                color: on
                    ? colors.onPrimary
                    : onTap == null
                        ? colors.onSurfaceVariant.withValues(alpha: 0.35)
                        : colors.onSurfaceVariant),
          ),
        );
    var size = controller.laneSize;
    return Row(children: [
      if (width >= 96)
        Container(
          padding: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            // Narrowed, the framing chosen -- or, with none, the whole.
            for (var (i, (key, icon, on, onTap)) in framings.indexed)
              if (width >= 140 || on || (i == 0 && !framings.any((f) => f.$3)))
                button(key, icon, on, onTap),
          ]),
        ),
      if (width >= 96) const SizedBox(width: 4),
      // Every channel a size taller, round to the least again: its bars and
      // its letter say which. At the column's very least, nothing.
      if (width >= 30)
        InkWell(
          key: const ValueKey("timelineLaneHeight"),
          borderRadius: BorderRadius.circular(5),
          onTap: controller.nextLaneSize,
          child: Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var k = 0; k < 3; k++) ...[
                if (k > 0) const SizedBox(width: 2),
                Container(
                  width: 3,
                  height: const [4.0, 7.0, 10.0][k],
                  color: colors.onSurfaceVariant
                      .withValues(alpha: k <= size ? 1 : 0.3),
                ),
              ],
              if (width >= 96) ...[
                const SizedBox(width: 4),
                Text(const ["S", "M", "L"][size],
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant)),
              ],
            ]),
          ),
        ),
      // A drawing's shapes (none, the one picked, or all of them) on lanes
      // of their own over the channels, and a picture's layers.
      if (width >= 60 &&
          (vectorLanesFor(controller) != null ||
              imageLanesFor(controller) != null)) ...[
        const SizedBox(width: 4),
        InkResponse(
          key: const ValueKey("vectorLanesToggle"),
          radius: 12,
          onTap: () => controller.vectorLanes = controller.vectorLanes.next,
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
        ),
      ],
      const Spacer(),
      if (width >= 140)
        const HelpNote(
            id: "timeline", title: "The timeline", paragraphs: timelineHelp),
      const SizedBox(width: 2),
    ]);
  }

  /// _stripHeader is the column beside the ruler, the width of the channels'
  /// strips under it: the framing and the channel height.
  Widget _stripHeader(ThemeNotifier theme) {
    var colors = theme.colors;
    return Container(
      width: controller.headerWidth,
      padding:
          EdgeInsets.only(left: 4, right: controller.headerWidth >= 64 ? 8 : 2),
      decoration: BoxDecoration(
          border: Border(right: BorderSide(color: colors.outlineVariant))),
      child: Stack(children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: _rulerHeight,
          // Ken, 2026-11-08: no zoom buttons -- zoom with Command and the
          // wheel, or a pinch -- and no keyframe button (keyframing is the
          // Chain's, 2026-11-09). The framing as three small icons and the
          // channel height as one button stepping S, M, L; inside the
          // header's width, whatever it is, never over the ruler.
          child: ClipRect(
            child: LayoutBuilder(
                builder: (context, box) => _corner(box.maxWidth, colors)),
          ),
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

  Widget _body(BuildContext context, ThemeNotifier theme,
      CanvasDocument document, TimelineAction? actionHere) {
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
              _stripHeader(theme),
              // Over the slots beside the rows: a launch for each cue.
              if (_slotsW > 0) _cueLaunches(theme),
              Expanded(
                  child: LayoutBuilder(
                builder: (context, constraints) => Stack(children: [
                  GestureDetector(
                    supportedDevices: timelinePointers,
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) {
                      // The brace is switched on the release, and leaves
                      // playing alone: a loop is set while listening.
                      if (_braceAt(
                              details.localPosition, constraints.maxWidth) !=
                          null) {
                        return;
                      }
                      controller.pause();
                    },
                    onTapUp: (details) {
                      // A click on the brace switches the loop off, as
                      // Ableton's does; the Loop button puts it back.
                      // Anywhere else scrubs.
                      if (_braceAt(
                              details.localPosition, constraints.maxWidth) !=
                          null) {
                        controller.looping = !controller.looping;
                        return;
                      }
                      _scrubTo(details.localPosition.dx, constraints.maxWidth);
                    },
                    // A drag that starts on the loop brace or a flag moves
                    // it; anywhere else it scrubs, decided once at the
                    // start, from where the press was.
                    onHorizontalDragDown: (details) {
                      _pressX = details.localPosition.dx;
                      _pressedBrace =
                          _braceAt(details.localPosition, constraints.maxWidth);
                      _pressedFlag =
                          _flagAt(details.localPosition, constraints.maxWidth);
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
                      _dragFlag = _pressedFlag;
                      if (_dragFlag != null) controller.beginInteraction();
                    },
                    onHorizontalDragUpdate: (details) {
                      var at = _frameAt(
                          details.localPosition.dx, constraints.maxWidth);
                      if (_dragBrace case var part?) {
                        _moveBrace(part, at);
                        return;
                      }
                      if (_dragFlag != null) {
                        if (_moveAction(_dragFlag!, at)) _dragFlag = at;
                        return;
                      }
                      _scrubTo(details.localPosition.dx, constraints.maxWidth);
                    },
                    onHorizontalDragEnd: (_) => _dragDone(),
                    onHorizontalDragCancel: _dragDone,
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
                        brace: controller.looping ? controller.loopRange : null,
                        looping: controller.looping,
                        actions: document.actions,
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
                // The scenes, the first row, on the ruler's own scale.
                scenesLane: _showScenes
                    ? CanvasSceneStrip(
                        controller: controller, view: _viewNow, origin: _origin)
                    : null,
                leading: Column(mainAxisSize: MainAxisSize.min, children: [
                  VectorShapeLanes(controller: controller, view: _sceneView),
                  ImageLayerLanes(controller: controller, view: _sceneView),
                ]))),
      // Which stretch of the timeline is on screen, and a handle to move
      // it: under the frames, not the strip column.
      if (!_collapsed)
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
      height: widget.showBar
          ? math.max(timelineCollapsedHeight, widget.height)
          : widget.height,
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
            (!_collapsed ? _scrollbarHeight : 0) +
            (_barAbove || _barBelow
                ? _transportHeight + (_collapsed ? 0 : _stripGap)
                : 0);
        var tall = math.max(box.maxHeight, least);
        Widget column = Column(children: [
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
        // The playhead: one line from the ruler down through every row
        // under it, unbroken (the approved design, 2026-11-08), over the
        // frames only. The rows draw none of their own.
        if (!_collapsed) {
          column = Stack(fit: StackFit.expand, children: [
            column,
            Positioned(
              left: 0,
              right: 0,
              top: _barAbove ? _transportHeight + _stripGap : 0,
              bottom: (_barBelow ? _transportHeight + _stripGap : 0) +
                  _scrollbarHeight,
              child: _PlayheadLine(
                  left: _leftW,
                  x: (w) => _xFor(controller.frame, w),
                  colour: theme.colors.primary),
            ),
          ]);
        }
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
    return transportKey(controller, event) ?? KeyEventResult.ignored;
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

  /// _dragDone ends a drag on the strip: a flag moved is one change.
  void _dragDone() {
    _dragBrace = null;
    _pressedBrace = null;
    if (_dragFlag != null) controller.endInteraction();
    _dragFlag = null;
    _pressedFlag = null;
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
/// _PlayheadLine is the playhead down the whole timeline body: from the
/// ruler through every row, over the frames right of [left], at [x] of the
/// frames' width.
class _PlayheadLine extends StatelessWidget {
  final double left;
  final double Function(double width) x;
  final Color colour;

  const _PlayheadLine(
      {required this.left, required this.x, required this.colour});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: LayoutBuilder(builder: (context, box) {
          var width = box.maxWidth - left;
          if (width <= 0) return const SizedBox.shrink();
          var at = x(width);
          if (at < 0 || at > width) return const SizedBox.shrink();
          return Stack(children: [
            Positioned(
              key: const ValueKey("timelinePlayhead"),
              left: left + at - 1,
              width: 2,
              top: 0,
              bottom: 0,
              child: ColoredBox(color: colour),
            ),
          ]);
        }),
      );
}

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

  /// sceneStarts is where each scene starts, in this painter's frames: just
  /// the one, at nought, unless the timeline runs along every scene. Each
  /// later one is marked on the ruler, over its join in the scene strip.
  final List<int> sceneStarts;
  final int frame;
  final int frameRate;
  final List<TimelineAction> actions;

  /// cues are the run's cues, each at its frame in this painter's frames,
  /// with its name: see canvas_cues.dart.
  final List<(int, String)> cues;
  final ColorScheme colors;
  final double Function(int) xFor;

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
    required this.view,
    required this.frames,
    required this.scene,
    this.origin = 0,
    this.sceneStarts = const [0],
    required this.frame,
    required this.frameRate,
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

    _paintMarkers(canvas);
    _paintCues(canvas);
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
  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.bars?.toJson().toString() != bars?.toJson().toString() ||
      old.frames != frames ||
      old.scene != scene ||
      old.origin != origin ||
      !listEquals(old.sceneStarts, sceneStarts) ||
      old.view != view ||
      old.frame != frame ||
      old.frameRate != frameRate ||
      old.actions != actions ||
      !listEquals(old.cues, cues) ||
      old.brace != brace ||
      old.looping != looping;
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
