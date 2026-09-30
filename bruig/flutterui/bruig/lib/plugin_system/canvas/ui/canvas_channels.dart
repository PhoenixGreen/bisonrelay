import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/ui/asset_elements.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart' show DbReading;
import 'package:bruig/plugin_system/canvas/ui/media_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_view.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// canvas_channels.dart is the sound on the timeline, a lane for each channel,
// laid out against the same frames as the keyframe strip above it.
//
// A channel is the sounds on it -- see TimelineChannel. There is always one
// lane more than there are channels, empty, at the bottom: a sound dropped
// there, or chosen by clicking it, starts a channel, and when that one fills a
// new empty lane is under it. A channel with nothing left on it is simply not
// there any more.
//
// Each channel has a strip at the left: a coloured edge that says what kind
// of channel it is (green for sound, yellow for a video's), its short name --
// A1, V1 -- and its full one when it is tall enough, its level as a number,
// and lock, solo and mute.
//
// Each sound is a bar from the frame it starts on to the frame it ends on:
// one block per file, the fades as slopes, a repeat drawn fainter to the end,
// and a line across it at its own volume. A bar is dragged along to move it
// and onto another lane to move it there; its ends are dragged to trim it,
// the handles at its top corners to fade it, and its line up and down to turn
// it up or down on its own. With the knife, a click cuts it in two. Taller
// than a line of text, a lane draws each file's waveform.

/// channelsLaneHeight is a lane as it starts, and the shortest it goes to
/// while its strip keeps everything on one line.
const double channelsLaneHeight = 32;

/// _laneMin and _laneMax bound a lane dragged taller or shorter.
const double _laneMin = 26;
const double _laneMax = 180;

/// _tall is how tall a lane is before its strip spreads over two lines and
/// shows the channel's name.
const double _tall = 52;

/// _waveformFrom is how tall a lane has to be before it shows its waveform.
const double _waveformFrom = 46;

const double _edgeGrab = 7;

/// _fadeGrab is how far down from the top of a bar its fade handles reach.
const double _fadeGrab = 10;

/// _volumeGrab is how near the volume line a press has to be to take it.
const double _volumeGrab = 4;

/// _snapReach is how near, on screen, a dragged edge has to come to a second
/// or the playhead to land on it.
const double _snapReach = 8;

/// timelineHeaderWidth is the channel strips' column as it starts. The reader
/// drags it -- see CanvasController.headerWidth.
const double timelineHeaderWidth = 150;

/// channelColour is the edge of a channel's strip: green for sound, yellow
/// for the sound of a video.
Color channelColour(bool video) =>
    video ? const Color(0xFFD9A93A) : const Color(0xFF3AA66A);

class CanvasChannels extends StatefulWidget {
  final CanvasController controller;

  /// view is the frames on screen -- the keyframe strip's, so a sound and a
  /// keyframe on the same frame are on the same line. See TimelineView.
  final TimelineView view;

  const CanvasChannels(
      {required this.controller, required this.view, super.key});

  /// hint is what the empty lane says after its name.
  static const String hint = "drop a sound here";

  @override
  State<CanvasChannels> createState() => _CanvasChannelsState();
}

enum _Grip { move, start, end, fadeIn, fadeOut, volume }

class _CanvasChannelsState extends State<CanvasChannels> {
  CanvasController get controller => widget.controller;
  TimelineView get _view => widget.view;

  // What a press took hold of, and the clip as it was when it did.
  TimedLane? _held;
  _Grip _grip = _Grip.move;
  MediaClip? _was;
  bool _dragging = false;

  /// _pressedX and _pressedY are where the press was, on screen. A drag is
  /// measured from them rather than by adding up the drag's own steps,
  /// because a drag is only recognised once the pointer has already moved
  /// some way -- and that first stretch never arrives as a step, so a clip
  /// dragged twenty frames moved sixteen.
  double _pressedX = 0, _pressedY = 0;

  /// _over is the lane a sound being dragged is over, by channel key --
  /// [_newLane] for the empty one -- while it is off its own.
  String? _over;
  static const String _newLane = "\u0000new";

  /// _laneKeys find each lane on screen, for which one a drag is over.
  final Map<String, GlobalKey> _laneKeys = {};
  GlobalKey _keyFor(String channel) =>
      _laneKeys.putIfAbsent(channel, () => GlobalKey());

  /// _gripFrom and _gripHeight are where a lane's bottom edge was taken hold
  /// of and how tall the lane was then. Measured from there rather than by
  /// adding up the drag's steps: the first few pixels never arrive as one.
  double _gripFrom = 0, _gripHeight = channelsLaneHeight;

  double _heightOf(String channel) =>
      controller.laneHeights[channel] ?? channelsLaneHeight;

  /// _span is where [lane]'s clip is on the scene's frames: from, to, and the
  /// frame each file begins on.
  ({double from, double to, List<double> cuts}) _span(TimedLane lane) {
    var clip = lane.clip;
    var rate = controller.document.frameRate.toDouble();
    var from = (clip.at - lane.offset).toDouble();
    var cuts = <double>[];
    var t = from;
    for (var s in clip.playlist) {
      cuts.add(t);
      t += s.span * rate;
    }
    return (from: from, to: t, cuts: cuts);
  }

  /// _clipAt is the sound on [channel] under [x], the one drawn last where
  /// two overlap.
  TimedLane? _clipAt(TimelineChannel channel, double x, double width) {
    for (var lane in channel.lanes.reversed) {
      if (lane.clip.isEmpty) continue;
      var span = _span(lane);
      var left = _view.xOf(span.from, width) - _edgeGrab;
      var right = _view.xOf(span.to, width) + _edgeGrab;
      if (x >= left && x <= right) return lane;
    }
    return null;
  }

  bool _canEdit(TimedLane lane) => lane.editable && !lane.element.locked;

  /// _gripAt is the sound under [at] on [channel] and which part of it: an
  /// end, a fade handle, its volume line, or the rest of it. Null for no
  /// sound. What a press takes hold of, and what the pointer shows.
  (TimedLane, _Grip)? _gripAt(
      TimelineChannel channel, Offset at, double width, double height) {
    var lane = _clipAt(channel, at.dx, width);
    if (lane == null) return null;
    var span = _span(lane);
    var clip = lane.clip;
    var rate = controller.document.frameRate.toDouble();
    var left = _view.xOf(span.from, width);
    var right = _view.xOf(span.to, width);
    var fadeInX = _view.xOf(span.from + clip.fadeIn * rate, width);
    var fadeOutX = _view.xOf(span.to - clip.fadeOut * rate, width);
    var line = _volumeY(clip.volume, height);
    // The fade handles first: they sit on the top edge, at the corners until
    // a fade is drawn, and on the ends of the slopes after. Then the ends;
    // then the volume line; and anywhere else moves it.
    var grip = at.dy <= _fadeGrab && (at.dx - fadeInX).abs() <= _edgeGrab
        ? _Grip.fadeIn
        : at.dy <= _fadeGrab && (at.dx - fadeOutX).abs() <= _edgeGrab
            ? _Grip.fadeOut
            : (at.dx - left).abs() <= _edgeGrab
                ? _Grip.start
                : (at.dx - right).abs() <= _edgeGrab
                    ? _Grip.end
                    : lane.element is AudioElement &&
                            (at.dy - line).abs() <= _volumeGrab
                        ? _Grip.volume
                        : _Grip.move;
    return (lane, grip);
  }

  void _press(TimelineChannel channel, Offset at, Offset global, double width,
      double height) {
    _dragging = false;
    _pressedX = global.dx;
    _pressedY = global.dy;
    var hit = _gripAt(channel, at, width, height);
    _held = hit?.$1;
    if (hit == null) {
      // Empty lane: a box, dragged, picks what it touches.
      if (controller.timelineTool == TimelineTool.select) {
        _boxFrom = global;
        _boxTo = null;
        var adding = HardwareKeyboard.instance.isShiftPressed;
        _boxBase = adding ? {...controller.selection} : {};
        _boxChannels = adding ? {...controller.selectedChannels} : {};
      }
      return;
    }
    var (lane, grip) = hit;
    if (!_canEdit(lane)) return;
    _grip = grip;
    _was = lane.clip;
  }

  /// _cursors is the pointer each lane shows, from what is under it.
  final Map<String, MouseCursor> _cursors = {};

  void _hover(TimelineChannel channel, Offset at, double width, double height) {
    MouseCursor cursor;
    if (controller.timelineTool == TimelineTool.knife) {
      cursor = SystemMouseCursors.precise;
    } else {
      var hit = _gripAt(channel, at, width, height);
      cursor = hit == null || !_canEdit(hit.$1)
          ? SystemMouseCursors.basic
          : switch (hit.$2) {
              _Grip.start ||
              _Grip.end ||
              _Grip.fadeIn ||
              _Grip.fadeOut =>
                SystemMouseCursors.resizeLeftRight,
              _Grip.volume => SystemMouseCursors.resizeUpDown,
              _Grip.move => SystemMouseCursors.basic,
            };
    }
    if (_cursors[channel.key] != cursor) {
      setState(() => _cursors[channel.key] = cursor);
    }
  }

  // The box dragged across empty lanes: where it began and has got to, on
  // screen, and what was picked before it when Shift was held.
  Offset? _boxFrom, _boxTo;
  Set<String> _boxBase = {};
  Set<String> _boxChannels = {};
  final GlobalKey _stack = GlobalKey();

  /// _box picks every sound the box touches, and the channels they are on.
  void _box(Offset global) {
    var from = _boxFrom;
    if (from == null) return;
    _boxTo = global;
    var box = Rect.fromPoints(from, global);
    var ids = {..._boxBase};
    var keys = {..._boxChannels};
    for (var channel in controller.timelineChannels) {
      var row = _keyFor(channel.key).currentContext?.findRenderObject();
      if (row is! RenderBox || !row.attached) continue;
      var origin = row.localToGlobal(Offset.zero);
      var top = origin.dy, bottom = origin.dy + row.size.height;
      if (bottom < box.top || top > box.bottom) continue;
      var left = origin.dx + controller.headerWidth;
      var width = row.size.width - controller.headerWidth;
      for (var lane in channel.lanes) {
        var span = _span(lane);
        var a = left + _view.xOf(span.from, width);
        var b = left + _view.xOf(span.to, width);
        if (b < box.left || a > box.right) continue;
        if (controller.document.elements.any((e) => e.id == lane.element.id)) {
          ids.add(lane.element.id);
        }
        keys.add(channel.key);
      }
    }
    controller.selectMany(ids);
    controller.selectChannels(keys);
    setState(() {});
  }

  void _tap(TimelineChannel channel, Offset at, double width) {
    _boxFrom = null;
    var shift = HardwareKeyboard.instance.isShiftPressed;
    var lane = _held ?? _clipAt(channel, at.dx, width);
    _held = null;
    if (lane == null) {
      if (!shift) {
        controller.clearSelection();
        controller.selectedChannel = channel.key;
      }
      return;
    }
    // Shift adds a sound to what is picked, or takes it out, and its
    // channel with it.
    if (shift && controller.timelineTool == TimelineTool.select) {
      controller.toggleSelected(lane.element.id);
      controller.toggleChannel(channel.key);
      return;
    }
    controller.selectedChannel = channel.key;
    if (controller.timelineTool == TimelineTool.knife) {
      controller.pause();
      var frame = (_view.first + _view.framesPer(at.dx, width)).round();
      controller.splitClip(lane, frame);
      return;
    }
    _pick(lane);
  }

  /// _pick selects [lane]'s sound, where it is one on this canvas, so its
  /// settings are the ones on screen.
  void _pick(TimedLane lane) {
    if (controller.document.elements.any((e) => e.id == lane.element.id)) {
      controller.selectOnly(lane.element.id);
    }
  }

  /// _snapped is [frames] nudged so that [edge] + frames lands on a second
  /// or on the playhead, where one is within reach -- or [frames] as it is.
  double _snapped(double edge, double frames, double width) {
    if (!controller.snapping) return frames;
    var reach = _view.framesPer(_snapReach, width);
    var rate = math.max(1, controller.document.frameRate);
    var wanted = edge + frames;
    var marks = [
      controller.frame.toDouble(),
      (wanted / rate).roundToDouble() * rate,
    ];
    double? best;
    for (var m in marks) {
      var off = m - wanted;
      if (off.abs() <= reach && (best == null || off.abs() < best.abs())) {
        best = off;
      }
    }
    return best == null ? frames : frames + best;
  }

  void _drag(Offset global, double width, double height) {
    if (_boxFrom != null) {
      _box(global);
      return;
    }
    var lane = _held, was = _was;
    if (lane == null || was == null || !_canEdit(lane)) return;
    if (controller.timelineTool == TimelineTool.knife) return;
    if (!_dragging) {
      _dragging = true;
      controller.pause();
      controller.beginInteraction();
      // One of several picked, moved: all of them go, together.
      var picked = controller.selection;
      _group = picked.length > 1 &&
              picked.contains(lane.element.id) &&
              _grip == _Grip.move
          ? {
              for (var l in controller.timedLanes)
                if (picked.contains(l.element.id) &&
                    l.element.id != lane.element.id &&
                    _canEdit(l))
                  l.element.id: (l.element, l.clip),
            }
          : const {};
      if (_group.isEmpty) {
        _pick(lane);
        controller.selectedChannel = lane.channelKey;
      }
    }
    var frames = _view.framesPer(global.dx - _pressedX, width);
    var rate = controller.document.frameRate.toDouble();
    if (rate <= 0) rate = 1;
    var span = (from: (was.at - lane.offset).toDouble(), length: 0.0);
    var length = was.runLength * rate;
    MediaClip next;
    switch (_grip) {
      case _Grip.move:
        // Whichever end is nearer something to land on, lands on it.
        var byStart = _snapped(span.from, frames, width);
        var byEnd = _snapped(span.from + length, frames, width);
        // Whichever end snapped -- the nearer, if both did.
        var a = byStart - frames, b = byEnd - frames;
        if (a != 0 && (b == 0 || a.abs() <= b.abs())) {
          frames = byStart;
        } else if (b != 0) {
          frames = byEnd;
        }
        next = was.copyWith(at: math.max(0, was.at + frames.round()));
        for (var (e, clip) in _group.values) {
          controller.setTimedClip(
              e, clip.copyWith(at: math.max(0, clip.at + frames.round())),
              transient: true);
        }
        // And onto another lane, where it is let go over one -- one sound,
        // not several. Audio only: a video's lane is its own.
        if (lane.element is AudioElement && _group.isEmpty) {
          var over = _laneUnder(global);
          var own = lane.channelKey;
          _over = over == own ? null : over;
        }
      case _Grip.start:
        // Trimming the front moves the start of the first file's range and
        // the clip with it, so what is left stays where it was on the
        // timeline -- the way an editor trims.
        frames = _snapped(span.from, frames, width);
        var seconds = frames / rate;
        var first = was.playlist.first;
        var stop = first.endOr(first.length) - 0.1;
        var start =
            (first.start + seconds).clamp(0.0, math.max(0.0, stop)).toDouble();
        var moved = start - first.start;
        next = was.copyWith(
          at: math.max(0, was.at + (moved * rate).round()),
          playlist: [first.copyWith(start: start), ...was.playlist.skip(1)],
        );
      case _Grip.end:
        frames = _snapped(span.from + length, frames, width);
        var seconds = frames / rate;
        var last = was.playlist.last;
        var end = last.endOr(last.length) + seconds;
        var most = last.length > 0 ? last.length : double.infinity;
        end = end.clamp(last.start + 0.1, most).toDouble();
        next = was.copyWith(playlist: [
          ...was.playlist.take(was.playlist.length - 1),
          // Right at the end is written as "to the end", as the settings do.
          last.copyWith(end: last.length > 0 && end >= last.length ? 0 : end),
        ]);
      case _Grip.fadeIn:
        // No longer than the shortest file, which is where each fade runs.
        next = was.copyWith(
            fadeIn: (was.fadeIn + frames / rate)
                .clamp(0.0, _shortest(was))
                .toDouble());
      case _Grip.fadeOut:
        next = was.copyWith(
            fadeOut: (was.fadeOut - frames / rate)
                .clamp(0.0, _shortest(was))
                .toDouble());
      case _Grip.volume:
        // This sound only, not the channel: up is louder, to six decibels
        // over, and down is quieter, to nothing.
        var room = math.max(1.0, height - 16);
        var at = _volumeShare(was.volume) + (global.dy - _pressedY) / room;
        next = was.copyWith(volume: _volumeAt(at));
    }
    controller.setTimedClip(lane.element, next, transient: true);
    setState(() {});
  }

  double _shortest(MediaClip clip) {
    var least = 3600.0;
    for (var s in clip.playlist) {
      if (s.span > 0 && s.span < least) least = s.span;
    }
    return least;
  }

  /// _group is the other sounds picked, as they were, while one of them is
  /// dragged along -- see _drag.
  Map<String, (CanvasElement, MediaClip)> _group = const {};

  void _release() {
    if (_boxFrom != null) {
      _boxFrom = null;
      _boxTo = null;
      setState(() {});
      return;
    }
    _group = const {};
    var held = _held;
    var over = _over;
    _held = null;
    _was = null;
    _over = null;
    if (held != null && _dragging) {
      if (over != null) {
        // The clip as it now is, after the drag along.
        var now = controller.timedLanes
            .where((l) => l.element.id == held.element.id)
            .firstOrNull;
        var to =
            controller.timelineChannels.where((c) => c.key == over).firstOrNull;
        if (now != null && !(to?.locked ?? false)) {
          controller.moveClipToChannel(now, over == _newLane ? null : to,
              transient: true);
          controller.selectedChannel = over == _newLane
              ? controller.timedLanes
                  .where((l) => l.element.id == held.element.id)
                  .firstOrNull
                  ?.channelKey
              : over;
        }
      }
      controller.endInteraction();
    }
    _dragging = false;
    setState(() {});
  }

  /// _laneUnder is the lane at [global]'s height: a channel's key, the new
  /// lane, or null for neither.
  String? _laneUnder(Offset global) {
    for (var entry in _laneKeys.entries) {
      var box = entry.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      var top = box.localToGlobal(Offset.zero).dy;
      if (global.dy >= top && global.dy < top + box.size.height) {
        return entry.key;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        var channels = controller.timelineChannels;
        var width = controller.headerWidth;
        var audio = 0, video = 0;
        return Stack(key: _stack, children: [
          ListView(
            padding: EdgeInsets.zero,
            children: [
              for (var channel in channels)
                _row(channel.key, _heightOf(channel.key), width,
                    header: _ChannelHeader(
                      key: ValueKey("channelStrip-${channel.key}"),
                      channel: channel,
                      label: channel.video ? "V${++video}" : "A${++audio}",
                      width: width,
                      height: _heightOf(channel.key),
                      selected:
                          controller.selectedChannels.contains(channel.key),
                      soloed: controller.solo.contains(channel.key),
                      theme: theme,
                      // Shift picks it as well as the others, or leaves it.
                      onSelect: () => HardwareKeyboard.instance.isShiftPressed
                          ? controller.toggleChannel(channel.key)
                          : controller.selectedChannel = channel.key,
                      onRename: (name) =>
                          controller.renameChannel(channel, name),
                      onMix: (mix) {
                        controller.beginInteraction();
                        controller.setChannelMix(channel, mix, transient: true);
                        controller.endInteraction();
                      },
                      onLock: () =>
                          controller.lockChannel(channel, !channel.locked),
                      onSolo: () => controller.toggleSolo(channel.key),
                      onGripStart: (y) {
                        _gripFrom = y;
                        _gripHeight = _heightOf(channel.key);
                      },
                      onGripMove: (y) => controller.setLaneHeight(
                          channel.key,
                          (_gripHeight + y - _gripFrom)
                              .clamp(_laneMin, _laneMax)
                              .toDouble()),
                    ),
                    lane: _lane(channel, theme)),
              _row(_newLane, channelsLaneHeight, width,
                  header: _EmptyHeader(
                      width: width,
                      name: controller.newChannelName(),
                      theme: theme),
                  lane: _emptyLane(theme)),
            ],
          ),
          // The box being dragged across the lanes.
          if (_boxFrom != null && _boxTo != null) _boxOverlay(theme),
        ]);
      },
    );
  }

  Widget _boxOverlay(ThemeNotifier theme) {
    var stack = _stack.currentContext?.findRenderObject();
    if (stack is! RenderBox) return const SizedBox.shrink();
    var rect = Rect.fromPoints(
        stack.globalToLocal(_boxFrom!), stack.globalToLocal(_boxTo!));
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: Container(
          key: const ValueKey("channelsBox"),
          decoration: BoxDecoration(
            color: theme.colors.primary.withValues(alpha: 0.08),
            border: Border.all(color: theme.colors.primary),
          ),
        ),
      ),
    );
  }

  Widget _row(String channel, double height, double width,
          {required Widget header, required Widget lane}) =>
      SizedBox(
        key: _keyFor(channel),
        height: height,
        child: Row(children: [
          SizedBox(width: width, child: header),
          Expanded(child: lane),
        ]),
      );

  /// _addAt makes a new sound from [source] at [frame] on [channel], or on a
  /// channel of its own.
  void _addAt(MediaSource source, int frame, TimelineChannel? channel) {
    var key = channel?.key ?? controller.newChannelId();
    controller.addElement(channelClip(controller.document, frame,
        source: source,
        channel: key,
        channelName: channel?.name ?? controller.newChannelName(),
        mix: channel?.mix ?? const ChannelMix()));
    controller.selectedChannel = key;
  }

  Widget _lane(TimelineChannel channel, ThemeNotifier theme) {
    var height = _heightOf(channel.key);
    var tall = height >= _waveformFrom;
    var shapes = <String, Float32List?>{
      if (tall)
        for (var lane in channel.lanes)
          if (lane.element is AudioElement)
            for (var s in lane.clip.playlist)
              if (s.assetId.isNotEmpty)
                s.assetId: controller.waveformOf(s.assetId),
    };
    var knife = controller.timelineTool == TimelineTool.knife;
    return DragTarget<Object>(
      key: ValueKey("lane-${channel.key}"),
      onWillAcceptWithDetails: (d) =>
          droppedKind(d.data) == AssetKind.audio &&
          channel.editable &&
          !channel.locked,
      onAcceptWithDetails: (d) async {
        var at = _frameIn(channel.key, d.offset);
        var asset = await droppedAsset(d.data);
        if (asset != null) _addAt(asset.source, at, channel);
      },
      builder: (context, candidate, _) => LayoutBuilder(
        builder: (context, box) => GestureDetector(
          supportedDevices: timelinePointers,
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => _press(channel, d.localPosition, d.globalPosition,
              box.maxWidth, box.maxHeight),
          // The start is a move too: a pan is only recognised once the
          // pointer has gone some way, and a short drag can end on the step
          // that is recognised, with no update after it.
          onPanStart: (d) =>
              _drag(d.globalPosition, box.maxWidth, box.maxHeight),
          onPanUpdate: (d) =>
              _drag(d.globalPosition, box.maxWidth, box.maxHeight),
          onPanEnd: (_) => _release(),
          onPanCancel: () {
            // A tap cancels the pan before it lands; only a drag in progress
            // is let go here.
            if (_dragging) _release();
          },
          onTapUp: (d) => _tap(channel, d.localPosition, box.maxWidth),
          child: MouseRegion(
            // From what is under the pointer: the arrow to move a sound,
            // left and right for its ends and fades, up and down for its
            // volume, and the knife's crosshair.
            cursor: knife
                ? SystemMouseCursors.precise
                : _cursors[channel.key] ?? SystemMouseCursors.basic,
            onHover: (e) =>
                _hover(channel, e.localPosition, box.maxWidth, box.maxHeight),
            child: CustomPaint(
              size: Size(box.maxWidth, box.maxHeight),
              painter: _LanePainter(
                channel: channel,
                spans: [for (var lane in channel.lanes) _span(lane)],
                view: _view,
                frame: controller.frame,
                frameRate: controller.document.frameRate,
                colors: theme.colors,
                selected: controller.selection,
                chosenChannel:
                    controller.selectedChannels.contains(channel.key),
                held: _dragging ? _held?.element.id : null,
                showVolume: _dragging && _grip == _Grip.volume,
                target: candidate.isNotEmpty || _over == channel.key,
                shapes: shapes,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// _emptyLane is the lane under the last channel: a sound dropped on it,
  /// or chosen by clicking it, starts a channel.
  Widget _emptyLane(ThemeNotifier theme) => DragTarget<Object>(
        key: const ValueKey("lane-new"),
        onWillAcceptWithDetails: (d) => droppedKind(d.data) == AssetKind.audio,
        onAcceptWithDetails: (d) async {
          var at = _frameIn(_newLane, d.offset);
          var asset = await droppedAsset(d.data);
          if (asset != null) _addAt(asset.source, at, null);
        },
        builder: (context, candidate, _) => GestureDetector(
          supportedDevices: timelinePointers,
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) async {
            var at = _frameIn(_newLane, d.globalPosition);
            var chosen = await pickCanvasAudio(context, controller);
            if (chosen != null && mounted) _addAt(chosen, at, null);
          },
          child: CustomPaint(
            size: Size.infinite,
            painter: _EmptyLanePainter(
              label: "${controller.newChannelName()} — ${CanvasChannels.hint}",
              colors: theme.colors,
              lit: candidate.isNotEmpty || _over == _newLane,
            ),
          ),
        ),
      );

  /// _frameIn is the frame under [global] across lane [channel]'s frames.
  int _frameIn(String channel, Offset global) {
    var box = _keyFor(channel).currentContext?.findRenderObject();
    var width = controller.headerWidth;
    if (box is! RenderBox || box.size.width <= width) return controller.frame;
    var x = box.globalToLocal(global).dx - width;
    return _view.frameAt(x, box.size.width - width, controller.document.frames);
  }
}

/// _unityShare is how far down a clip nought decibels sits: a little above
/// the middle, so a sound that is too quiet has room to be turned up.
const double _unityShare = 0.45;

/// _mostDb is as far up as a sound goes: six decibels, twice as loud, which
/// is generally as much as turning one up will stand.
const double _mostDb = 6.0206;

/// _volumeShare is how far down the clip [volume]'s line is, nought at the
/// top to one at the bottom: decibels above nought -- up to six at the top --
/// and a straight fade to silence below.
double _volumeShare(double volume) {
  if (volume >= 1) {
    var db = math.min(_mostDb, 20 * math.log(volume) / math.ln10);
    return _unityShare * (1 - db / _mostDb);
  }
  return _unityShare + (1 - volume.clamp(0.0, 1.0)) * (1 - _unityShare);
}

/// _volumeAt is the volume whose line is [share] of the way down.
double _volumeAt(double share) {
  var p = share.clamp(0.0, 1.0);
  if (p <= _unityShare) {
    var db = _mostDb * (1 - p / _unityShare);
    return math.pow(10, db / 20).toDouble();
  }
  return 1 - (p - _unityShare) / (1 - _unityShare);
}

/// _volumeY is where a clip's volume line sits in a lane [height] tall.
double _volumeY(double volume, double height) {
  // Inset from the clip's edges, so the line is never the edge itself.
  var top = 3.0 + 5, bottom = height - 3 - 5;
  return top + _volumeShare(volume) * (bottom - top);
}

/// gainToDb is a level as decibels, -90 standing for silence.
double gainToDb(double gain) =>
    gain <= 0.0000316 ? -90 : 20 * math.log(gain) / math.ln10;

/// _paintSeconds draws a faint line at every second across [size], as the
/// strip above ticks them: the lanes and the strip are one timeline. In each
/// lane and not under the empty one, so the lines stop where the channels do.
void _paintSeconds(Canvas canvas, Size size, TimelineView view, int frameRate,
    ColorScheme colors) {
  var w = size.width;
  var rate = math.max(1, frameRate);
  if (w / view.span * rate <= 8) return;
  var grid = Paint()
    ..color = colors.outlineVariant.withValues(alpha: 0.35)
    ..strokeWidth = 1;
  var s = (view.first / rate).ceil();
  for (var f = s * rate; f <= view.first + view.span; f += rate) {
    var x = view.xOf(f, w);
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
  }
}

class _LanePainter extends CustomPainter {
  final TimelineChannel channel;
  final List<({double from, double to, List<double> cuts})> spans;
  final TimelineView view;
  final int frame;
  final int frameRate;
  final ColorScheme colors;
  final Set<String> selected;
  final bool chosenChannel;
  final String? held;
  final bool showVolume;
  final bool target;
  final Map<String, Float32List?> shapes;

  _LanePainter({
    required this.channel,
    required this.spans,
    required this.view,
    required this.frame,
    required this.frameRate,
    required this.colors,
    required this.selected,
    required this.chosenChannel,
    required this.held,
    required this.showVolume,
    required this.target,
    required this.shapes,
  });

  double _x(num f, double width) => view.xOf(f, width);

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width;
    var top = 3.0, bottom = size.height - 3;
    // Zoomed in, a clip reaches past either edge: drawn, and cut off there.
    canvas.clipRect(Offset.zero & size);

    // The channel picked, which a cut at the playhead is made on; and a lane
    // something is being dropped on, or dragged onto.
    if (chosenChannel || target) {
      canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..color = colors.primary.withValues(alpha: target ? 0.10 : 0.05));
    }

    _paintSeconds(canvas, size, view, frameRate, colors);

    for (var (i, lane) in channel.lanes.indexed) {
      _paintClip(canvas, size, lane, spans[i], top, bottom);
    }

    // No line under the lane: the channels' lines are their strips', and the
    // one across the whole timeline is the keyframes' -- see CanvasTimeline.

    // The playhead, through every lane, as on the strip above.
    var head = view.centreOf(frame, w);
    canvas.drawLine(
        Offset(head, 0),
        Offset(head, size.height),
        Paint()
          ..color = colors.primary
          ..strokeWidth = 1.5);
  }

  void _paintClip(
      Canvas canvas,
      Size size,
      TimedLane lane,
      ({double from, double to, List<double> cuts}) span,
      double top,
      double bottom) {
    var w = size.width;
    var clip = lane.clip;
    if (clip.isEmpty) return;
    var video = lane.element is VideoElement;
    var locked = lane.element.locked;
    var fill = (video ? const Color(0xFF7B5CC4) : const Color(0xFF2A9D8F))
        .withValues(alpha: lane.editable && !locked ? 1 : 0.5);

    var from = _x(span.from, w), to = _x(span.to, w);

    // A repeat carries on to the end, drawn fainter: it is the same file again,
    // not more of the clip.
    if (clip.loop != MediaLoop.none && span.to > span.from) {
      canvas.drawRRect(
          RRect.fromLTRBR(to, top, w, bottom, const Radius.circular(3)),
          Paint()..color = fill.withValues(alpha: fill.a * 0.35));
    }

    var bar = RRect.fromLTRBR(
        from, top, math.max(from + 2, to), bottom, const Radius.circular(4));
    canvas.drawRRect(bar, Paint()..color = fill);

    canvas.save();
    // Everything of the clip's is inside the clip: the waveform, the lines
    // and its name.
    canvas.clipRRect(bar);

    var rate = frameRate <= 0 ? 1 : frameRate;
    var audio = lane.element is AudioElement;

    // The shape of the sound as it will come out -- its peaks times its own
    // volume -- where the lane is tall enough to read one. Turned up, it
    // grows; where a peak would go past full it stops at the edge, in red,
    // which is where it would clip.
    if (size.height >= _waveformFrom) {
      var ink = Paint()
        ..color = const Color(0x99FFFFFF)
        ..strokeWidth = 1;
      var over = Paint()
        ..color = const Color(0xFFE05050)
        ..strokeWidth = 1;
      var mid = (top + bottom) / 2 + 5;
      var reach = (bottom - top) / 2 - 7;
      var gain = audio ? clip.volume : 1.0;
      for (var (i, cut) in span.cuts.indexed) {
        var source = clip.playlist[i];
        var peaks = shapes[source.assetId];
        if (peaks == null || peaks.isEmpty || source.length <= 0) continue;
        var a = math.max(0.0, _x(cut, w));
        var b = math.min(w, _x(cut + source.span * rate, w));
        for (var x = a; x < b; x += 2) {
          var t = source.start + (view.first + x / w * view.span - cut) / rate;
          var at = (t / source.length * peaks.length).floor();
          if (at < 0 || at >= peaks.length) continue;
          var level = peaks[at] * gain;
          var h = math.min(1.0, level) * reach;
          canvas.drawLine(
              Offset(x, mid - h), Offset(x, mid + h), level >= 1 ? over : ink);
        }
      }
    }

    // Where each file begins, after the first.
    for (var cut in span.cuts.skip(1)) {
      var x = _x(cut, w);
      canvas.drawLine(Offset(x, top), Offset(x, bottom),
          Paint()..color = const Color(0x88FFFFFF));
    }

    // The fades, as slopes at the ends of each file.
    var shade = Paint()..color = const Color(0x55000000);
    for (var (i, cut) in span.cuts.indexed) {
      var length = clip.playlist[i].span * rate;
      var a = _x(cut, w), b = _x(cut + length, w);
      if (clip.fadeIn > 0) {
        var x = _x(cut + clip.fadeIn * rate, w).clamp(a, b);
        canvas.drawPath(
            Path()
              ..moveTo(a, top)
              ..lineTo(x, top)
              ..lineTo(a, bottom)
              ..close(),
            shade);
      }
      if (clip.fadeOut > 0) {
        var x = _x(cut + length - clip.fadeOut * rate, w).clamp(a, b);
        canvas.drawPath(
            Path()
              ..moveTo(b, top)
              ..lineTo(x, top)
              ..lineTo(b, bottom)
              ..close(),
            shade);
      }
    }

    // The volume line: this sound's own level, dragged up or down.
    if (audio) {
      var y = _volumeY(clip.volume, size.height);
      canvas.drawLine(
          Offset(from, y),
          Offset(to, y),
          Paint()
            ..color = const Color(0xCCFFFFFF)
            ..strokeWidth = 1.2);
      if (showVolume && held == lane.element.id) {
        var reading = TextPainter(
          text: TextSpan(
              text: clip.volume <= 0
                  ? "−∞ dB"
                  : "${clip.volume > 1.0001 ? "+" : ""}"
                      "${gainToDb(clip.volume).toStringAsFixed(1)} dB",
              style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFFFFFFFF),
                  fontWeight: FontWeight.w600)),
          textDirection: TextDirection.ltr,
        )..layout();
        reading.paint(
            canvas,
            Offset(math.max(from, 0) + 6,
                (y - reading.height - 2).clamp(top, bottom - reading.height)));
      }
    }

    // The name, inside the bar, and not at all where the bar is too short
    // for any of it.
    var room = to - math.max(from, 0) - 12;
    if (room >= 24) {
      var name =
          lane.editable ? lane.element.name : "${lane.element.name} (master)";
      var text = TextPainter(
        text: TextSpan(
            text: name,
            style: const TextStyle(
                fontSize: 10.5,
                color: Color(0xFFFFFFFF),
                fontWeight: FontWeight.w500)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: "…",
      )..layout(maxWidth: room);
      // Along the bottom of a tall lane, so the waveform and the volume line
      // have the rest; in the middle of a short one.
      var y = size.height >= _waveformFrom
          ? bottom - text.height - 2
          : (size.height - text.height) / 2;
      text.paint(canvas, Offset(math.max(from, 0) + 6, y));
    }
    canvas.restore();

    // Chosen, it keeps an outline for as long as it is: its settings are
    // the ones on screen.
    var chosen = selected.contains(lane.element.id);
    if (chosen || held == lane.element.id) {
      canvas.drawRRect(
          bar,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = chosen ? 2 : 1.5
            ..color = chosen ? colors.onSurface : colors.primary);
    }

    // The fade handles, on the top edge: at the corners until a fade is
    // drawn, and at the end of each slope after.
    if (lane.editable && !locked && to - from > 24) {
      var handle = Paint()..color = const Color(0xFFFFFFFF);
      var inX = _x(span.from + clip.fadeIn * rate, w).clamp(from, to);
      var outX = _x(span.to - clip.fadeOut * rate, w).clamp(from, to);
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset(inX + 3, top + 3), width: 6, height: 6),
          handle);
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset(outX - 3, top + 3), width: 6, height: 6),
          handle);
    }
  }

  @override
  bool shouldRepaint(_LanePainter old) => true;
}

class _EmptyLanePainter extends CustomPainter {
  final String label;
  final ColorScheme colors;
  final bool lit;
  _EmptyLanePainter(
      {required this.label, required this.colors, required this.lit});

  @override
  void paint(Canvas canvas, Size size) {
    var box = RRect.fromLTRBR(
        0.5, 3, size.width - 0.5, size.height - 3, const Radius.circular(4));
    if (lit) {
      canvas.drawRRect(
          box, Paint()..color = colors.primary.withValues(alpha: 0.08));
    }
    canvas.drawRRect(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = lit ? colors.primary : colors.outlineVariant);
    var text = TextPainter(
      text: TextSpan(
          text: label,
          style: TextStyle(fontSize: 10.5, color: colors.onSurfaceVariant)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: "…",
    )..layout(maxWidth: math.max(0, size.width - 12));
    text.paint(canvas, Offset(6, (size.height - text.height) / 2));
  }

  @override
  bool shouldRepaint(_EmptyLanePainter old) =>
      old.label != label || old.lit != lit || old.colors != colors;
}

/// _ChannelHeader is a channel's strip at the left of its lane.
///
/// A coloured edge for what kind of channel it is; its short name, A1 or V1;
/// its whole name, once the lane is tall enough to give it a line --
/// double-clicked to rename it; its level, in decibels, clicked to type one;
/// and lock, solo and mute. Narrowed, it gives up the reading, then the buttons
/// one at a time, and is its edge and its short name. Its bottom edge is
/// dragged to make the lane taller, and a click picks the channel.
class _ChannelHeader extends StatelessWidget {
  final TimelineChannel channel;
  final String label;
  final double width;
  final double height;
  final bool selected;
  final bool soloed;
  final ThemeNotifier theme;
  final VoidCallback onSelect;
  final ValueChanged<String> onRename;
  final ValueChanged<ChannelMix> onMix;
  final VoidCallback onLock;
  final VoidCallback onSolo;
  final ValueChanged<double> onGripStart;
  final ValueChanged<double> onGripMove;

  const _ChannelHeader({
    required this.channel,
    required this.label,
    required this.width,
    required this.height,
    required this.selected,
    required this.soloed,
    required this.theme,
    required this.onSelect,
    required this.onRename,
    required this.onMix,
    required this.onLock,
    required this.onSolo,
    required this.onGripStart,
    required this.onGripMove,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    var mix = channel.mix;
    var tall = height >= _tall && width >= 110;
    var locked = channel.locked;

    Widget code = Text(label,
        key: const ValueKey("channelCode"),
        maxLines: 1,
        style: TextStyle(
            fontSize: 12.5,
            height: 1.1,
            fontWeight: FontWeight.w700,
            color: colors.onSurface));

    // The channel's level, as a number: clicked, it takes a typed one --
    // the same level as its fader in the mixer.
    var reading = SizedBox(
      width: 32,
      child: DbReading(
        key: const ValueKey("channelLevel"),
        db: mix.gainDb,
        fieldHeight: 14,
        unit: "",
        onSet: (db) => onMix(mix.copyWith(gainDb: db)),
        style: TextStyle(
            fontSize: 10,
            height: 1.1,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: colors.onSurfaceVariant),
      ),
    );

    // What there is room for, the reading going first and then the buttons.
    var buttons = [
      if (width >= 128)
        _StripButton(
          key: const ValueKey("channelLock"),
          icon: locked ? Icons.lock : Icons.lock_open,
          on: locked,
          onColor: colors.onSurface,
          theme: theme,
          onTap: onLock,
        ),
      if (width >= 104)
        _StripButton(
          key: const ValueKey("channelSolo"),
          text: "S",
          on: soloed,
          onColor: const Color(0xFFB28A1F),
          theme: theme,
          onTap: onSolo,
        ),
      if (width >= 80)
        _StripButton(
          key: const ValueKey("channelMute"),
          text: "M",
          on: mix.mute,
          onColor: const Color(0xFFB23B3B),
          theme: theme,
          onTap: () => onMix(mix.copyWith(mute: !mix.mute)),
        ),
    ];
    var gap = const SizedBox(width: 4);

    Widget body;
    if (tall) {
      body = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 16,
              child: Row(children: [
                code,
                const SizedBox(width: 8),
                Expanded(
                    child: _ChannelName(
                        name: channel.name, theme: theme, onRename: onRename)),
                if (width >= 150) reading,
              ]),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 18,
              child: Row(children: [
                for (var b in buttons) ...[b, gap],
              ]),
            ),
          ]);
    } else {
      body = Row(children: [
        code,
        const Spacer(),
        for (var b in buttons) ...[b, gap],
        if (width >= 150) reading,
      ]);
    }

    var strip = GestureDetector(
      supportedDevices: timelinePointers,
      behavior: HitTestBehavior.opaque,
      onTap: onSelect,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? colors.surfaceContainerHighest : null,
          border: Border(
              right: BorderSide(color: colors.outlineVariant),
              // The line under each channel, drawn strongly: the channels are
              // rows, and they read as rows only with a line between them.
              bottom: BorderSide(color: colors.outline.withValues(alpha: 0.7))),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Green for sound, yellow for a video's.
          Container(width: 4, color: channelColour(channel.video)),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(width < 44 ? 3 : 6, 2, 4, 2),
              child: ClipRect(child: body),
            ),
          ),
        ]),
      ),
    );

    return Stack(children: [
      Positioned.fill(
        // A channel from the master is changed there, as in the mixer.
        child: channel.editable
            ? strip
            : IgnorePointer(child: Opacity(opacity: 0.55, child: strip)),
      ),
      // The bottom edge: dragged, the lane is taller or shorter.
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: 5,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          child: GestureDetector(
            key: ValueKey("laneGrip-${channel.key}"),
            supportedDevices: timelinePointers,
            behavior: HitTestBehavior.opaque,
            // Measured from the press, not from where the drag was noticed.
            dragStartBehavior: DragStartBehavior.down,
            onVerticalDragStart: (d) => onGripStart(d.globalPosition.dy),
            onVerticalDragUpdate: (d) => onGripMove(d.globalPosition.dy),
          ),
        ),
      ),
    ]);
  }
}

/// _ChannelName is a channel's whole name, double-clicked to rename it.
class _ChannelName extends StatefulWidget {
  final String name;
  final ThemeNotifier theme;
  final ValueChanged<String> onRename;
  const _ChannelName(
      {required this.name, required this.theme, required this.onRename});

  @override
  State<_ChannelName> createState() => _ChannelNameState();
}

class _ChannelNameState extends State<_ChannelName> {
  bool _typing = false;
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _commit() {
    if (!_typing) return;
    setState(() => _typing = false);
    var named = _text.text.trim();
    if (named.isNotEmpty && named != widget.name) widget.onRename(named);
  }

  @override
  Widget build(BuildContext context) {
    var style = TextStyle(
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w500,
        color: widget.theme.colors.onSurface);
    if (_typing) {
      return TextField(
        key: const ValueKey("channelNameField"),
        controller: _text,
        autofocus: true,
        style: style,
        decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none),
        onSubmitted: (_) => _commit(),
        onTapOutside: (_) => _commit(),
      );
    }
    return GestureDetector(
      onDoubleTap: () => setState(() {
        _typing = true;
        _text.text = widget.name;
        _text.selection =
            TextSelection(baseOffset: 0, extentOffset: _text.text.length);
      }),
      child: Text(widget.name,
          key: const ValueKey("channelName"),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style),
    );
  }
}

/// _EmptyHeader is the strip beside the empty lane: the channel it would be.
class _EmptyHeader extends StatelessWidget {
  final double width;
  final String name;
  final ThemeNotifier theme;
  const _EmptyHeader(
      {required this.width, required this.name, required this.theme});

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
      decoration: BoxDecoration(
          border: Border(right: BorderSide(color: colors.outlineVariant))),
      child: Row(children: [
        Icon(Icons.add, size: 12, color: colors.onSurfaceVariant),
        if (width >= 64) ...[
          const SizedBox(width: 4),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10.5,
                    height: 1.2,
                    color: colors.onSurfaceVariant)),
          ),
        ],
      ]),
    );
  }
}

/// _StripButton is one of a strip's small square buttons: lock, solo, mute.
class _StripButton extends StatelessWidget {
  final String? text;
  final IconData? icon;
  final bool on;
  final Color onColor;
  final ThemeNotifier theme;
  final VoidCallback onTap;

  const _StripButton({
    this.text,
    this.icon,
    required this.on,
    required this.onColor,
    required this.theme,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    var ink = on
        ? (onColor == colors.onSurface ? colors.surface : Colors.white)
        : colors.onSurfaceVariant;
    return GestureDetector(
      supportedDevices: timelinePointers,
      onTap: onTap,
      child: Container(
        width: 20,
        height: 17,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? onColor : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(3),
        ),
        child: icon != null
            ? Icon(icon, size: 11, color: ink)
            : Text(text!,
                style: TextStyle(
                    fontSize: 9.5,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    color: ink)),
      ),
    );
  }
}
