import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
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

/// timelineHeight is the strip's height, and it never changes.
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
/// Seventy-two is everything below the transport row: the ruler, the two rows
/// of marks and the air around them. It was 110 all in, of which the transport
/// row was 38.
const double timelineHeight = controlWithLabelHeight + 72;

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

/// _rulerHeight is the frame numbers and the playhead.
const double _rulerHeight = 22;

/// _markGrabWidth and _markGrabHeight are how close the pointer has to be to a
/// keyframe mark to take hold of it rather than scrub.
///
/// Generous horizontally, because a mark is a few pixels wide and a timeline
/// squeezed to a hundred frames puts them close together; tight vertically, so
/// a drag anywhere else on the strip is still a scrub.
const double _markGrabWidth = 9;
const double _markGrabHeight = 11;

class CanvasTimeline extends StatefulWidget {
  final CanvasController controller;

  /// keyframesOpen and onToggleKeyframes drive the pose bar the screen floats
  /// over the canvas. Held there rather than here because the bar is not part
  /// of this widget -- growing this strip to hold it pushed the canvas up.
  final bool keyframesOpen;
  final VoidCallback onToggleKeyframes;

  const CanvasTimeline({
    required this.controller,
    this.keyframesOpen = false,
    this.onToggleKeyframes = _noop,
    super.key,
  });

  static void _noop() {}

  @override
  State<CanvasTimeline> createState() => _CanvasTimelineState();
}

class _CanvasTimelineState extends State<CanvasTimeline> {
  CanvasController get controller => widget.controller;

  /// _dragKey is the frame of the mark being dragged along the ruler, or null
  /// while the drag is an ordinary scrub.
  int? _dragKey;

  /// _pressedFrame is the mark under the pointer when it went down, before any
  /// drag was recognised. See onHorizontalDragDown.
  int? _pressedFrame;

  /// _selectedKey is the frame of the mark that has been clicked, or null.
  ///
  /// Cleared whenever the row changes underneath it -- a frame number means
  /// nothing once the strip is showing somebody else's keyframes, and a stale
  /// one would put Delete on a mark that is not there.
  int? _selectedKey;

  /// _focus is what lets Delete reach this strip. Requested when a mark is
  /// clicked, because a mark is not a widget and cannot take focus itself.
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    controller.addListener(_onChanged);
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
    var at = _selectedKey;
    if (at != null && _targetTrack?.keyAt(at) == null) _selectedKey = null;
    setState(() {});
  }

  /// _frameAt turns a horizontal position into a frame number.
  int _frameAt(double x, double width) {
    var frames = controller.document.frames;
    if (frames <= 1 || width <= 0) return 0;
    return ((x / width) * frames).floor().clamp(0, frames - 1);
  }

  double _xFor(int frame, double width) {
    var frames = controller.document.frames;
    if (frames <= 0) return 0;
    return (frame + 0.5) / frames * width;
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

  /// _drivingPath is the path that owns this row's keyframes, if one does.
  ///
  /// A followed element's track is written by the path and rewritten whenever
  /// a point moves, so keyframes shown on its own row would be marks the
  /// reader could drag and then watch disappear. The strip shows nothing for
  /// it and says where the timing lives instead -- which is also the answer to
  /// "why do I get keyframes on the player *and* on the path".
  PathElement? get _drivingPath {
    var team = controller.focusedTeam;
    var index = controller.focusedPlayer;
    if (team != null && index != null) {
      return controller.pathDriving(team.id, playerIndex: index);
    }
    var element = controller.selected;
    if (element == null || element is PathElement) return null;
    return controller.pathDriving(element.id);
  }

  /// _retime moves a mark from one frame to another.
  ///
  /// One entry point for the three things a mark can belong to, because the
  /// ruler that drags them does not know or care which it is holding.
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

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Container(
        height: timelineHeight,
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 6 + _notesGutter),
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
          SizedBox(
            height: controlWithLabelHeight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                CanvasIconButton(
                  icon: Icons.skip_previous,
                  tooltip: "Back to the first frame",
                  onPressed: controller.stop,
                ),
                CanvasIconButton(
                  icon: controller.playing ? Icons.pause : Icons.play_arrow,
                  tooltip: controller.playing ? "Pause" : "Play",
                  active: controller.playing,
                  onPressed: document.frames > 1 ? controller.togglePlay : null,
                ),
                CanvasIconButton(
                  icon: Icons.chevron_left,
                  tooltip: "Previous frame",
                  onPressed: () => controller.frame = controller.frame - 1,
                ),
                CanvasIconButton(
                  icon: Icons.chevron_right,
                  tooltip: "Next frame",
                  onPressed: () => controller.frame = controller.frame + 1,
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
                  onChanged: (v) =>
                      controller.stepFrame(v.round() - 1 - controller.frame),
                ),
                Padding(
                  padding:
                      const EdgeInsets.only(top: controlLabelHeight, right: 2),
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
                    controller.apply(document.copyWith(frameRate: v.round()),
                        transient: true);
                  },
                  onCommit: controller.endInteraction,
                ),
                SizedBox(
                  // Room for the longest duration a canvas can have: an hour of
                  // frames at one a second.
                  width: 62,
                  child: Padding(
                    padding: const EdgeInsets.only(top: controlLabelHeight),
                    child: Text(
                      document.isAnimated
                          ? "${document.durationSeconds.toStringAsFixed(1)}s"
                          : "Still",
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: theme.colors.onSurfaceVariant),
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
                  tooltip: controller.autoKeyframe
                      ? "Auto-keyframe is on — dragging records a keyframe here"
                      : "Auto-keyframe: record a keyframe whenever something moves",
                  active: controller.autoKeyframe,
                  onPressed: () =>
                      controller.autoKeyframe = !controller.autoKeyframe,
                ),
                CanvasIconButton(
                  icon:
                      keyHere != null ? Icons.diamond : Icons.diamond_outlined,
                  tooltip: _drivingPath != null
                      ? "$target is following ${_drivingPath!.name} — "
                          "its timing is that path's points"
                      : target == null
                          ? "Select an element, or click a player, to give it a "
                              "keyframe"
                          : keyHere != null
                              ? "Remove this keyframe from $target"
                              : "Add a keyframe for $target here",
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
                  tooltip: _selectedPath != null
                      ? "A path's marks are its points — remove them in its settings"
                      : _drivingPath != null
                          ? "$target is following ${_drivingPath!.name} — clear it "
                              "by unlinking the path"
                          : target == null
                              ? "Select an element, or click a player, to clear its "
                                  "keyframes"
                              : "Clear every keyframe on $target",
                  onPressed: _canClearChannel ? _clearChannel : null,
                ),
                CanvasIconButton(
                  icon: Icons.delete_sweep_outlined,
                  tooltip: "Clear every keyframe in the whole canvas",
                  onPressed: document.hasKeyframes
                      ? controller.clearAllKeyframes
                      : null,
                ),
                _keyframeToggle(theme, target, keyHere != null),
                // A fixed gap rather than a Spacer: the row scrolls, so it has no
                // width to divide up and a Spacer inside it is an unbounded
                // constraint rather than a space.
                const SizedBox(width: 24),
                if (actionHere == null)
                  for (var kind in TimelineActionKind.values)
                    CanvasIconButton(
                      icon: switch (kind) {
                        TimelineActionKind.stop => Icons.stop_circle_outlined,
                        TimelineActionKind.loop => Icons.loop,
                        TimelineActionKind.jump =>
                          Icons.subdirectory_arrow_right,
                        TimelineActionKind.pause => Icons.pause_circle_outline,
                      },
                      tooltip: "${kind.label} — ${kind.description}",
                      onPressed: () => _addAction(kind),
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
          const SizedBox(height: 3),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  controller.pause();
                  // A tap on a mark selects it *and* moves the playhead to it,
                  // which is the same thing anybody wants from clicking a
                  // keyframe: to be looking at the pose they are about to change.
                  var mark =
                      _keyframeAt(details.localPosition, constraints.maxWidth);
                  setState(() => _selectedKey = mark);
                  if (mark != null) _focus.requestFocus();
                  controller.frame = mark ??
                      _frameAt(details.localPosition.dx, constraints.maxWidth);
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
                  _pressedFrame =
                      _keyframeAt(details.localPosition, constraints.maxWidth);
                },
                onHorizontalDragStart: (_) {
                  controller.pause();
                  _dragKey = _pressedFrame;
                },
                onHorizontalDragUpdate: (details) {
                  var at =
                      _frameAt(details.localPosition.dx, constraints.maxWidth);
                  if (_dragKey == null) {
                    controller.frame = at;
                    return;
                  }
                  _retime(_dragKey!, at);
                  _dragKey = at;
                },
                onHorizontalDragEnd: (_) {
                  _dragKey = null;
                  _pressedFrame = null;
                },
                onHorizontalDragCancel: () {
                  _dragKey = null;
                  _pressedFrame = null;
                },
                child: CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: _TimelinePainter(
                    frames: document.frames,
                    frame: controller.frame,
                    frameRate: document.frameRate,
                    // The focused player's, when one is focused -- see
                    // _targetTrack. The marks on the ruler have to be the same
                    // keyframes the diamond button adds and removes, or the
                    // strip shows one player's run while the button edits
                    // another's.
                    keyframes: _targetTrack?.keys ?? const [],
                    selectedKeyframe: _selectedKey,
                    actions: document.actions,
                    colors: theme.colors,
                    xFor: (f) => _xFor(f, constraints.maxWidth),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
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
      var at = _selectedKey;
      if (at == null) return KeyEventResult.ignored;
      _removeTargetKey(at);
      setState(() => _selectedKey = null);
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
    if ((local.dy - (_rulerHeight + 14)).abs() > _markGrabHeight) return null;

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

  void _replaceAction(TimelineAction action) {
    var document = controller.document;
    controller.apply(document.copyWith(actions: [
      ...document.actions.where((a) => a.frame != action.frame),
      action,
    ]));
  }
}

/// _TimelinePainter draws the ruler, the two rows of marks and the playhead.
class _TimelinePainter extends CustomPainter {
  final int frames;
  final int frame;
  final int frameRate;
  final List<Keyframe> keyframes;

  /// selectedKeyframe is the frame of the mark that has been clicked, drawn
  /// with a ring so it is obvious which one Delete will take.
  final int? selectedKeyframe;
  final List<TimelineAction> actions;
  final ColorScheme colors;
  final double Function(int) xFor;

  const _TimelinePainter({
    required this.frames,
    required this.frame,
    required this.frameRate,
    required this.keyframes,
    required this.selectedKeyframe,
    required this.actions,
    required this.colors,
    required this.xFor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    var track = Rect.fromLTWH(0, 0, size.width, _rulerHeight);
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, const Radius.circular(4)),
      Paint()..color = colors.surfaceContainerHighest,
    );

    // A tick every frame while they are far enough apart to see, and every
    // second otherwise. Ticks closer together than a couple of pixels are a
    // grey smear that says nothing about where anything is.
    var step = size.width / math.max(1, frames);
    var everyFrame = step > 6;
    var secondStep = math.max(1, frameRate);

    var tick = Paint()
      ..color = colors.onSurfaceVariant.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    var strongTick = Paint()
      ..color = colors.onSurfaceVariant.withValues(alpha: 0.7)
      ..strokeWidth = 1;

    for (var f = 0; f < frames; f++) {
      var strong = f % secondStep == 0;
      if (!everyFrame && !strong) continue;
      var x = xFor(f);
      canvas.drawLine(Offset(x, strong ? 4 : 9), Offset(x, _rulerHeight - 3),
          strong ? strongTick : tick);
    }

    _paintMarks(
      canvas,
      size,
      y: _rulerHeight + 14,
      frames: [for (var k in keyframes) k.frame],
      // Muted, the same weight as the transport's own icons. They were all
      // drawn in the accent, which is the colour that means "this one" -- so
      // with every mark shouting, the selected one had nothing left to say
      // with and needed a ring drawn round it to be picked out at all.
      color: colors.onSurfaceVariant.withValues(alpha: 0.65),
      diamond: true,
      selected: selectedKeyframe,
      selectedColor: colors.primary,
    );
    _paintMarks(
      canvas,
      size,
      y: _rulerHeight + 34,
      frames: [for (var a in actions) a.frame],
      // A different colour from the keyframes above, which is the whole job of
      // this row -- but not tertiary, which is a panel background in this app
      // and drew these marks in near-black on a near-black ruler.
      color: colors.secondary,
      diamond: false,
    );

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
    int? selected,
    Color? selectedColor,
  }) {
    if (y > size.height) return;
    var paint = Paint()..color = color;
    var chosen = Paint()..color = selectedColor ?? color;
    for (var f in frames) {
      var x = xFor(f);
      var ink = f == selected ? chosen : paint;
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

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.frames != frames ||
      old.frame != frame ||
      old.frameRate != frameRate ||
      old.keyframes != keyframes ||
      old.selectedKeyframe != selectedKeyframe ||
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

  /// _drivingPath is the path that owns this row's keyframes, if one does.
  /// The same question the strip asks -- see _CanvasTimelineState._drivingPath.
  PathElement? get _drivingPath {
    var team = controller.focusedTeam;
    var index = controller.focusedPlayer;
    if (team != null && index != null) {
      return controller.pathDriving(team.id, playerIndex: index);
    }
    var element = controller.selected;
    if (element == null || element is PathElement) return null;
    return controller.pathDriving(element.id);
  }

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
