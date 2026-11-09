import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/ui/asset_elements.dart';
import 'package:bruig/plugin_system/canvas/ui/automation_lanes.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart'
    show isMidiId;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart'
    show sectionColors;
import 'package:bruig/plugin_system/canvas/ui/motion_lanes.dart'
    show MotionLanes;
import 'package:bruig/plugin_system/canvas/ui/canvas_rows.dart';
import 'package:bruig/plugin_system/canvas/ui/row_header.dart';
import 'package:bruig/plugin_system/canvas/ui/scene_strip.dart'
    show sceneBoxHeight, sceneStripHeight, sceneStripLead;
import 'package:bruig/plugin_system/canvas/ui/element_sound.dart'
    show soundOwnerOf;
import 'package:bruig/plugin_system/canvas/model/session.dart'
    show SessionSlotDrag;
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart' show DbReading;
import 'package:bruig/plugin_system/canvas/ui/media_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_view.dart';
import 'package:bruig/plugin_system/canvas/ui/slots_window.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_columns.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// canvas_channels.dart is the sound on the timeline, a lane for each channel,
// laid out against the same frames as the rows above it.
//
// A channel is the sounds on it (see TimelineChannel). There is always one
// empty lane more than there are channels, at the bottom: a sound dropped
// there, or chosen by clicking it, starts a channel. A channel with nothing
// left on it is gone.
//
// Each channel has a strip at the left: a coloured edge for its kind (green
// for sound, yellow for a video's), its short name (A1, V1) and its full one
// when tall enough, its level as a number, and lock, solo and mute.
//
// Each sound is a bar from the frame it starts on to the frame it ends on:
// one block per file, the fades as slopes, a repeat drawn fainter to the end,
// and a line across it at its own volume. A bar is dragged along to move it
// and onto another lane to move it there; its ends are dragged to trim it,
// the handles at its top corners to fade it, and its line up and down to
// set its volume. With the knife, a click cuts it in two. Taller than a line
// of text, a lane draws each file's waveform.

/// channelsLaneHeight is a lane as it starts, and the shortest it goes to
/// while its strip keeps everything on one line.
const double channelsLaneHeight = 32;

/// laneSizeHeights are the heights the timeline's channel-height button
/// steps every channel through: the least, the height at which a strip
/// spreads over two lines (its name and lock, then S and M), and twice that.
const laneSizeHeights = [channelsLaneHeight, _tall, _tall * 2];

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

/// channelColour is the edge of a channel's strip: green for sound, yellow
/// for the sound of a video.
Color channelColour(bool video) =>
    video ? const Color(0xFFD9A93A) : const Color(0xFF3AA66A);

class CanvasChannels extends StatefulWidget {
  final CanvasController controller;

  /// view is the frames on screen: the rows', so a sound and a key on the
  /// same frame line up. See TimelineView.
  final TimelineView view;

  /// motionRows is whether the elements' rows are here -- each with its own
  /// sound's channel under it -- above the canvas's other channels.
  final bool motionRows;

  /// leading is rows above the channels that scroll with them: a drawing's
  /// shapes, where they are shown. See VectorShapeLanes.
  final Widget? leading;

  /// scenesLane is the scenes' strip, while every scene plays: the first
  /// row, "Scenes", with the transitions' sounds as its sound under it --
  /// the scenes and their transitions one channel (Ken, 2026-11-08).
  final Widget? scenesLane;

  const CanvasChannels(
      {this.scenesLane,
      required this.controller,
      required this.view,
      this.leading,
      this.motionRows = false,
      super.key});

  /// hint is what the empty lane says after its name.
  static const String hint =
      "+ for an audio or a MIDI channel, or drop a sound or video here";

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
  /// measured from them rather than by adding up its steps, because the
  /// stretch before a drag is recognised never arrives as a step.
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
      controller.laneHeights[channel] ?? laneSizeHeights[controller.laneSize];

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
                    : (at.dy - line).abs() <= _volumeGrab
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
        _boxBase = adding ? {...controller.clipSelection} : {};
        _boxChannels = adding ? {...controller.selectedChannels} : {};
      }
      return;
    }
    var (lane, grip) = hit;
    if (!_canEdit(lane)) return;
    _grip = grip;
    _was = lane.clip;
    _wasRun = controller.clipRunStart(lane.element.id);
  }

  /// _wasRun is where the held clip started on the run's clock when it was
  /// taken hold of: what a move is measured from, so it can cross into
  /// another scene. Null for one on the backdrop, which moves as it did.
  int? _wasRun;

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
      // Nothing on an interactive lane to pick: it plays when pressed.
      if (channel.interactive) continue;
      var row = _keyFor(channel.key).currentContext?.findRenderObject();
      if (row is! RenderBox || !row.attached) continue;
      var origin = row.localToGlobal(Offset.zero);
      var top = origin.dy, bottom = origin.dy + row.size.height;
      if (bottom < box.top || top > box.bottom) continue;
      var left = origin.dx + leftWidthNow(context, controller);
      var width = row.size.width - leftWidthNow(context, controller);
      for (var lane in channel.lanes) {
        var span = _span(lane);
        var a = left + _view.xOf(span.from, width);
        var b = left + _view.xOf(span.to, width);
        if (b < box.left || a > box.right) continue;
        if (_canPick(lane)) ids.add(lane.element.id);
        keys.add(channel.key);
      }
    }
    controller.pickClips(ids);
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
      if (_canPick(lane)) controller.pickClip(lane.element.id, toggle: true);
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
    // Twice on a sound or a MIDI part: its channel's chain opened, it
    // picked (Ken, 2026-11-08, as a double-click opens an element's clip
    // in the Chain).
    var now = DateTime.now();
    var twice = _tappedClip == lane.element.id &&
        now.difference(_tappedAt) < const Duration(milliseconds: 400);
    _tappedClip = lane.element.id;
    _tappedAt = now;
    if (twice) {
      _tappedClip = null;
      controller.openEffects(channel.key);
    }
  }

  /// The sound last pressed and when, for a double-click opening it.
  String? _tappedClip;
  DateTime _tappedAt = DateTime(0);

  /// _pick selects [lane]'s sound, so its settings are the ones on screen.
  /// While every scene plays, a clip on another canvas is lit as picked
  /// too, though its settings stay on its own canvas.
  void _pick(TimedLane lane) {
    if (_canPick(lane)) controller.pickClip(lane.element.id);
  }

  bool _canPick(TimedLane lane) =>
      controller.allChannels ||
      controller.document.elements.any((e) => e.id == lane.element.id);

  /// _snapped is [frames] nudged so that [edge] + frames lands on a second
  /// or on the playhead, where one is within reach -- or [frames] as it is.
  double _snapped(double edge, double frames, double width) {
    var rate = math.max(1, controller.document.frameRate);
    var wanted = edge + frames;
    // A piece of sound always lands on its grid (the nearest bar, beat or
    // note the quantise says), as a sequencer's does. Quantise has its own
    // Off, so the snapping magnet is not asked.
    var doc = controller.document;
    if (doc.kind.isAudio) {
      if (doc.audio.gridSeconds() case var grid?) {
        var step = grid * rate;
        return frames + ((wanted / step).round() * step - wanted);
      }
    }
    if (!controller.snapping) return frames;
    var reach = _view.framesPer(_snapReach, width);
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
      var picked = controller.clipSelection;
      _group = picked.length > 1 &&
              picked.contains(lane.element.id) &&
              _grip == _Grip.move
          ? {
              for (var l in controller.timedLanes)
                if (picked.contains(l.element.id) &&
                    l.element.id != lane.element.id &&
                    _canEdit(l))
                  l.element.id: (
                    l.element,
                    l.clip,
                    controller.clipRunStart(l.element.id)
                  ),
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
        // Measured on the run's clock, so a clip goes on into the next scene
        // rather than stopping at the end of its own -- see placeTimedClip.
        for (var (e, clip, run) in _group.values) {
          if (run == null) {
            controller.setTimedClip(
                e, clip.copyWith(at: math.max(0, clip.at + frames.round())),
                transient: true);
          } else {
            controller.placeTimedClip(e, clip, run + frames.round(),
                transient: true);
          }
        }
        if (_wasRun case var run?) {
          controller.placeTimedClip(lane.element, was, run + frames.round(),
              transient: true);
          if (_group.isEmpty) _trackOver(lane, global);
          setState(() {});
          return;
        }
        if (_group.isEmpty) _trackOver(lane, global);
      case _Grip.start:
        // Trimming the front moves the start of the first file's range and
        // the clip with it, so what is left stays where it was, as an editor
        // trims.
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

  /// _group is the other sounds picked, as they were and where each started
  /// on the run's clock, while one of them is dragged along -- see _drag.
  Map<String, (CanvasElement, MediaClip, int?)> _group = const {};

  /// _trackOver notes the lane [lane]'s clip would be let go onto, for a
  /// move onto another channel -- one clip, not several. A video's
  /// soundtrack goes with it, so a channel can hold sounds and videos one
  /// after another.
  void _trackOver(TimedLane lane, Offset global) {
    var over = _laneUnder(global);
    var own = lane.channelKey;
    // Only onto a channel of the same canvas -- see moveClipToChannel.
    var to =
        controller.timelineChannels.where((c) => c.key == over).firstOrNull;
    _over = over == own || (to != null && to.first.scene != lane.scene)
        ? null
        : over;
  }

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
    _wasRun = null;
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
        var show = controller.timelineShow;
        // The rows every panel shows (see canvas_rows.dart): each element
        // with its own sound, then the sounds that are nobody's. Without the
        // elements' rows, every channel is listed on its own.
        var rows = canvasRowsOf(controller);
        var grouped = widget.motionRows
            ? [
                for (var r in rows)
                  if (r.element case var e?) e
              ]
            : const <CanvasElement>[];
        var owned = <String, List<TimelineChannel>>{
          if (widget.motionRows)
            for (var r in rows)
              if (r.element case var e?) e.id: r.channels,
        };
        // The transitions' sounds: the Scenes row's own, where it is.
        var transitions = widget.scenesLane == null
            ? const <TimelineChannel>[]
            : [
                for (var r in rows)
                  if (r.transitions) ...r.channels
              ];
        // The others: the ones whose strips move among themselves.
        var channels = _withMoving([
          for (var ch in widget.motionRows
              ? [
                  for (var r in rows)
                    if (r.element == null) ...r.channels
                ]
              : controller.timelineChannels)
            if (!transitions.contains(ch)) ch
        ]);
        var width = controller.headerWidth;
        return Stack(key: _stack, children: [
          ListView(
            padding: EdgeInsets.zero,
            children: [
              // The scenes, first: their strip with its header, and the
              // transitions' sounds under it as the same row, from M up.
              if (widget.scenesLane case var lane?) ...[
                _row("scenes", sceneStripHeight, width,
                    header: _scenesHeader(theme, width, transitions),
                    lane: Padding(
                      padding: const EdgeInsets.only(top: sceneStripLead),
                      child: Align(
                          alignment: Alignment.topLeft,
                          child: SizedBox(height: sceneBoxHeight, child: lane)),
                    )),
                if (show != TimelineShow.animation && controller.laneSize > 0)
                  for (var channel in transitions)
                    ..._channelRows(channel, width, theme, channels,
                        movable: false, owned: true, accent: sceneColour),
              ],
              if (widget.leading case var leading?) leading,
              // Each element's rows, with its own sound's channel under
              // them; then the canvas's other channels.
              for (var e in grouped) ...[
                if (show != TimelineShow.sound)
                  MotionLanes(controller: controller, view: _view, only: e.id),
                // At the channel height S, an element's row is its motion
                // alone (Ken, 2026-11-08); its sound from M up.
                if (show != TimelineShow.animation &&
                    (controller.laneSize > 0 || show == TimelineShow.sound))
                  for (var channel in owned[e.id] ?? const <TimelineChannel>[])
                    ..._channelRows(channel, width, theme, channels,
                        movable: false, owned: true),
              ],
              if (show != TimelineShow.animation)
                for (var channel in channels)
                  ..._channelRows(channel, width, theme, channels),
              _row(_newLane, channelsLaneHeight, width,
                  header: _EmptyHeader(
                      width: width,
                      name: "Add a channel",
                      theme: theme,
                      onAudio: () async {
                        var chosen = await pickCanvasAudio(context, controller);
                        if (chosen != null && mounted) {
                          _addAt(chosen, controller.frame, null);
                        }
                      },
                      onMidi: () => controller.addMidiChannel(),
                      onEmptyAudio: () => controller.addEmptyAudioChannel(),
                      onEmptyMidi: () =>
                          controller.addMidiChannel(onCanvas: false)),
                  lane: _emptyLane(theme)),
            ],
          ),
          // The box being dragged across the lanes.
          if (_boxFrom != null && _boxTo != null) _boxOverlay(theme),
        ]);
      },
    );
  }

  /// _channelRows is [channel]'s row and, opened under it, its automation.
  /// [movable] is whether its strip is dragged to move it among the others:
  /// not an element's own sound, which stays under the element.
  /// _scenesHeader is the Scenes row's header (row_header.dart): its
  /// count, the scene's motion (its camera and transitions) shown, and its
  /// sound button the transitions' sounds'.
  Widget _scenesHeader(
      ThemeNotifier theme, double width, List<TimelineChannel> transitions) {
    var colors = theme.colors;
    var heard = transitions.isNotEmpty &&
        controller.laneSize > 0 &&
        controller.timelineShow != TimelineShow.animation;
    var scenes = controller.document.allScenes.length;
    void mute(TimelineChannel ch) {
      var now = controller.mixNow(ch);
      controller.beginInteraction();
      controller.changeChannelMix(ch, now, now.copyWith(mute: !now.mute),
          transient: true);
      controller.endInteraction();
    }

    return RowHeader(
      key: const ValueKey("scenesHeader"),
      colour: sceneColour,
      width: width,
      height: sceneStripHeight,
      joinsBelow: heard,
      name: Text("Scenes",
          key: const ValueKey("sceneStripLabel"),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.onSurface)),

      motion: const RowToggle(ValueKey("rowMotion-scenes"), on: true),
      // The transitions' sounds are made from the transitions, not kept as
      // a channel to change: their button shows them heard, and switches
      // them only where they can be.
      sound: transitions.isEmpty
          ? null
          : RowToggle(const ValueKey("rowMute-scenes"),
              on: !controller.mixNow(transitions.first).mute,
              onTap: transitions.first.editable
                  ? () => mute(transitions.first)
                  : null),
      // How many, beside the row, so the name keeps its room.
      bands: [
        RowBand(0, sceneStripHeight, "$scenes scene${scenes == 1 ? "" : "s"}",
            sceneColour)
      ],
    );
  }

  List<Widget> _channelRows(TimelineChannel channel, double width,
          ThemeNotifier theme, List<TimelineChannel> channels,
          {bool movable = true, bool owned = false, Color? accent}) =>
      [
        _row(channel.key, _heightOf(channel.key), width,
            moving: channel.key == _moving,
            accent: owned ? accent ?? theme.colors.primary : null,
            beside: controller.slotsBeside
                ? SessionRowSlots(controller: controller, channel: channel.key)
                : null,
            header: _ChannelHeader(
              key: ValueKey("channelStrip-${channel.key}"),
              controller: controller,
              owned: owned && controller.timelineShow != TimelineShow.sound,
              channel: channel,
              mix: controller.mixNow(channel),
              automation: controller.automationShown.contains(channel.key),
              onAutomation: () => controller.toggleAutomation(channel.key),
              // Which canvas its clips are on -- M for the master,
              // S1 for the first scene -- beside the band whose
              // colour says sound or video.
              label: channel.sceneLabel,
              width: width,
              height: _heightOf(channel.key),
              selected: controller.selectedChannels.contains(channel.key),
              soloed: controller.solo.contains(channel.key),
              theme: theme,
              // Shift picks it as well as the others, or leaves it.
              onSelect: () => HardwareKeyboard.instance.isShiftPressed
                  ? controller.toggleChannel(channel.key)
                  : controller.selectedChannel = channel.key,
              onRename: (name) => controller.renameChannel(channel, name),
              // As the mixer's fader: a level typed over a lane is
              // held by hand -- see changeChannelMix.
              onMix: (mix) {
                controller.beginInteraction();
                controller.changeChannelMix(
                    channel, controller.mixNow(channel), mix,
                    transient: true);
                controller.endInteraction();
              },
              onLock: () => controller.lockChannel(channel, !channel.locked),
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
              onMoveStart: (_) {
                if (movable) _startMove(channels, channel.key);
              },
              onMove: (y) {
                var to = _slotAt(y);
                if (to != _moveTo) setState(() => _moveTo = to);
              },
              onMoveEnd: _endMove,
            ),
            lane: _lane(channel, theme)),
        // Its automation, opened under it: a lane for each setting
        // shown, and a row to show another.
        if (controller.automationShown.contains(channel.key) &&
            channel.editable &&
            channel.key != _moving) ...[
          for (var (i, target) in controller.automationRows(channel).indexed)
            SizedBox(
              key: ValueKey("autoRow-${channel.key}-$i"),
              height: automationLaneHeight,
              child: Row(children: [
                SizedBox(
                    width: leftWidthIn(context, controller),
                    child: AutomationLaneHeader(
                        controller: controller,
                        channel: channel,
                        index: i,
                        width: width)),
                Expanded(
                    child: AutomationLaneBody(
                        key: ValueKey("autoBody-${channel.key}-$target"),
                        controller: controller,
                        channel: channel,
                        target: target,
                        view: _view)),
              ]),
            ),
          SizedBox(
            height: automationAddHeight,
            child: Row(children: [
              SizedBox(
                  width: leftWidthIn(context, controller),
                  child: AutomationAddRow(
                      controller: controller, channel: channel)),
              const Expanded(child: SizedBox()),
            ]),
          ),
        ],
      ];

  /// _moving is the channel whose strip is being dragged up or down, and
  /// _moveTo where in the list it would go. The list is shown in that order
  /// while it is dragged -- see _withMoving -- so the channel is seen going
  /// where it will be put.
  String? _moving;
  int? _moveTo;

  /// _rowsAtStart is the middle of each other channel's row when the drag
  /// began, by which the pointer is placed. Measured once: the rows move as
  /// the list is shown in its new order, and measuring them as they moved
  /// would have the channel chase its own reflection.
  List<double> _rowsAtStart = const [];

  void _startMove(List<TimelineChannel> channels, String key) {
    var mids = <double>[];
    var at = 0;
    for (var (i, c) in channels.indexed) {
      if (c.key == key) {
        at = i;
        continue;
      }
      var box = _keyFor(c.key).currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      mids.add(box.localToGlobal(Offset.zero).dy + box.size.height / 2);
    }
    setState(() {
      _moving = key;
      _moveTo = at;
      _rowsAtStart = mids;
    });
  }

  /// _slotAt is where in the list, without the channel being moved, a
  /// pointer at [y] would put it: after every row whose middle it is below.
  int _slotAt(double y) => _rowsAtStart.where((mid) => y > mid).length;

  /// _withMoving is [channels] in the order the drag would leave them.
  List<TimelineChannel> _withMoving(List<TimelineChannel> channels) {
    var key = _moving, to = _moveTo;
    if (key == null || to == null) return channels;
    var moving = channels.where((c) => c.key == key).firstOrNull;
    if (moving == null) return channels;
    var rest = [
      for (var c in channels)
        if (c.key != key) c
    ];
    rest.insert(to.clamp(0, rest.length).toInt(), moving);
    return rest;
  }

  void _endMove() {
    var key = _moving, to = _moveTo;
    setState(() {
      _moving = null;
      _moveTo = null;
      _rowsAtStart = const [];
    });
    if (key == null || to == null) return;
    // Its place among the others moved, in the list of every channel --
    // an element's own among them, which stay under their elements.
    var all = [
      for (var c in controller.timelineChannels)
        if (c.key != key) c.key
    ];
    var free = [
      for (var k in all)
        if (soundOwnerOf(controller.document, k) == null) k
    ];
    controller.moveChannel(
        key, to >= free.length ? all.length : all.indexOf(free[to]));
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
      {required Widget header,
      required Widget lane,
      bool moving = false,
      Color? accent,
      Widget? beside}) {
    // The strip and the slots at most as wide as the row: shown alone, the
    // slots fill to the edge, and a scaled text size can leave them a
    // fraction of a pixel over it (Ken's 0.109 px).
    var row = LayoutBuilder(builder: (context, box) {
      var head = math.min(width, box.maxWidth);
      var slots = math.min(slotsWidthIn(context, controller),
          math.max(0.0, box.maxWidth - head));
      return Row(children: [
        // An element's own sound: the element's stripe down its left, drawn
        // over the strip so nothing in it moves.
        SizedBox(
            width: head,
            child: accent == null
                ? header
                : DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                        border:
                            Border(left: BorderSide(color: accent, width: 3))),
                    child: header)),
        // The slots beside the rows, when they are: a channel's, or room.
        if (slots > 0)
          SizedBox(width: slots, child: beside ?? const SizedBox()),
        // The frames, unless this is the slots shown alone.
        Expanded(child: lanesIn(context) ? lane : const SizedBox()),
      ]);
    });
    var colors = ThemeNotifier.of(context).colors;
    return SizedBox(
      key: _keyFor(channel),
      height: height,
      // The channel being moved, lit across its strip and its lane. Always
      // in a Stack, lit or not: changing what the row is built from as the
      // drag began would throw away the strip the drag started on.
      child: Stack(children: [
        Positioned.fill(child: row),
        if (moving)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey("channelMoving"),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.16),
                  border: Border.all(color: colors.primary, width: 1.5),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  /// _playedIn is the frames of this view [channel]'s clips are played in:
  /// while every scene plays, its own scene's (the master's, the whole run),
  /// so a clip running on past its scene is shaded where it does; one scene
  /// at a time, the scene's.
  (int?, int?) _playedIn(TimelineChannel channel) {
    var document = controller.document;
    if (!controller.allChannels || !document.hasScenes) {
      return (null, document.frames);
    }
    var lane = channel.first;
    var from = -lane.offset;
    var scenes = document.allScenes;
    var long = lane.scene >= 0 && lane.scene < scenes.length
        ? scenes[lane.scene].frames
        : document.sequenceFrames;
    return (from, from + long);
  }

  /// _placeSlot puts the clip dragged from a slot onto [channel]'s lane at
  /// [frame]: its own channel's, or another of its kind.
  void _placeSlot(SessionSlotDrag from, int frame, TimelineChannel channel) =>
      controller.placeSessionClip(from.channel, from.row, frame,
          onto: channel.key);

  /// _addAt makes a new sound from [source] at [frame] on [channel], or on a
  /// channel of its own.
  void _addAt(MediaSource source, int frame, TimelineChannel? channel) {
    // A MIDI file: its notes onto a MIDI channel, or a MIDI channel of its
    // own -- never a silent sound on an audio one.
    if (isMidiId(source.assetId)) {
      if (channel != null && controller.instrumentChannel(channel.key)) {
        controller.putMidiOn(channel.key, source.assetId, frame);
      } else if (channel == null) {
        controller.addMidiChannelFrom(source, frame: frame, onCanvas: false);
      }
      return;
    }
    var key = channel?.key ?? controller.newChannelId();
    controller.addElement(channelClip(controller.document, frame,
        source: source,
        channel: key,
        channelName: channel?.name ?? controller.newChannelName(),
        mix: channel?.mix ?? const ChannelMix()));
    controller.selectedChannel = key;
  }

  /// _addVideoAt puts the video [asset] on the canvas, in the middle at its
  /// own shape, and on the timeline from [frame], its soundtrack on a lane of
  /// its own: what "On the timeline" in its settings does.
  void _addVideoAt(LibraryAsset asset, int frame, TimelineChannel? channel) {
    var made = elementForAsset(asset, controller.document);
    if (made is! VideoElement) return;
    var key = channel?.key ?? controller.newChannelId();
    controller.addElement(made.copyWith(
        clip: made.clip.copyWith(
            timed: true,
            at: frame,
            channel: key,
            channelName: channel?.name ?? controller.newChannelName(),
            mix: channel?.mix ?? const ChannelMix())));
    controller.selectedChannel = key;
  }

  /// _slotsOnly is whether [channel] plays from its sample slots and has
  /// nothing on the timeline: its lane greyed, saying so, but still a lane a
  /// sound can be dropped on.
  bool _slotsOnly(TimelineChannel channel) =>
      (controller.session.slots[channel.key]?.any((c) => c != null) ?? false) &&
      channel.lanes.every((l) => l.clip.isEmpty || !l.clip.timed);

  Widget _lane(TimelineChannel channel, ThemeNotifier theme) {
    if (channel.interactive) return _interactiveLane(channel, theme);
    var slotsOnly = _slotsOnly(channel);
    var height = _heightOf(channel.key);
    var tall = height >= _waveformFrom;
    // A sound's shape from its file, and a video's from the soundtrack that
    // was taken out of it when it was added.
    var shapes = <String, Float32List?>{
      if (tall)
        for (var lane in channel.lanes)
          for (var s in lane.clip.playlist)
            if (_shapeOf(lane, s).isNotEmpty)
              _shapeOf(lane, s): controller.waveformOf(_shapeOf(lane, s)),
    };
    var knife = controller.timelineTool == TimelineTool.knife;
    return DragTarget<Object>(
      key: ValueKey("lane-${channel.key}"),
      // A sound or a video joins the channel it is let go on.
      onWillAcceptWithDetails: (d) => switch (d.data) {
        // A clip from a slot, onto its own kind of channel: placed there,
        // once through.
        SessionSlotDrag from =>
          controller.canMoveClip(from.clip, channel.key) &&
              channel.editable &&
              !channel.locked,
        _ => (droppedKind(d.data) == AssetKind.video ||
                droppedKind(d.data) == AssetKind.audio) &&
            // A MIDI file only onto a MIDI channel; a sound only onto one
            // that is not.
            (d.data is LibraryAsset && isMidiId((d.data as LibraryAsset).id)) ==
                controller.instrumentChannel(channel.key) &&
            channel.editable &&
            !channel.locked,
      },
      onAcceptWithDetails: (d) async {
        var at = _frameIn(channel.key, d.offset);
        if (d.data case SessionSlotDrag from) {
          _placeSlot(from, at, channel);
          return;
        }
        var asset = await droppedAsset(d.data);
        if (asset == null) return;
        asset.kind == AssetKind.video
            ? _addVideoAt(asset, at, channel)
            : _addAt(asset.source, at, channel);
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
              foregroundPainter: slotsOnly
                  ? _InteractiveLanePainter(
                      label: "Sample slots in use",
                      colors: theme.colors,
                      chosen: controller.selectedChannels.contains(channel.key),
                      frame: controller.frame,
                      view: _view)
                  : null,
              painter: _LanePainter(
                onMaster: controller.document.editingMaster,
                channel: channel,
                spans: [for (var lane in channel.lanes) _span(lane)],
                view: _view,
                frame: controller.frame,
                frameRate: controller.document.frameRate,
                colors: theme.colors,
                selected: controller.clipSelection,
                chosenChannel:
                    controller.selectedChannels.contains(channel.key),
                held: _dragging ? _held?.element.id : null,
                showVolume: _dragging && _grip == _Grip.volume,
                target: candidate.isNotEmpty || _over == channel.key,
                shapes: shapes,
                sceneFrom: _playedIn(channel).$1,
                sceneTo: _playedIn(channel).$2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// _interactiveLane is the lane of sounds played by pressing them on the
  /// canvas: greyed, with nothing on it to move, cut or drop onto. Pressed,
  /// it picks the channel, so its strip and effects can be opened.
  Widget _interactiveLane(TimelineChannel channel, ThemeNotifier theme) =>
      GestureDetector(
        key: ValueKey("lane-${channel.key}"),
        supportedDevices: timelinePointers,
        behavior: HitTestBehavior.opaque,
        onTapUp: (_) {
          controller.clearSelection();
          controller.selectedChannel = channel.key;
        },
        child: CustomPaint(
          size: Size.infinite,
          painter: _InteractiveLanePainter(
            label: _slotsOnly(channel)
                ? "Sample slots in use"
                : channel.lanes.length > 1
                    ? "${channel.lanes.length} sounds that play when pressed"
                    : channel.video
                        ? "A video that plays when pressed on the canvas"
                        : "Plays when pressed on the canvas",
            colors: theme.colors,
            chosen: controller.selectedChannels.contains(channel.key),
            frame: controller.frame,
            view: _view,
          ),
        ),
      );

  /// _emptyLane is the lane under the last channel: a sound dropped on it,
  /// or chosen by clicking it, starts a channel.
  Widget _emptyLane(ThemeNotifier theme) => DragTarget<Object>(
        key: const ValueKey("lane-new"),
        onWillAcceptWithDetails: (d) =>
            droppedKind(d.data) == AssetKind.audio ||
            droppedKind(d.data) == AssetKind.video,
        onAcceptWithDetails: (d) async {
          var at = _frameIn(_newLane, d.offset);
          var asset = await droppedAsset(d.data);
          if (asset == null) return;
          asset.kind == AssetKind.video
              ? _addVideoAt(asset, at, null)
              : _addAt(asset.source, at, null);
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
              label: CanvasChannels.hint,
              colors: theme.colors,
              lit: candidate.isNotEmpty || _over == _newLane,
            ),
          ),
        ),
      );

  /// _frameIn is the frame under [global] across lane [channel]'s frames.
  int _frameIn(String channel, Offset global) {
    var box = _keyFor(channel).currentContext?.findRenderObject();
    var width = leftWidthNow(context, controller);
    if (box is! RenderBox || box.size.width <= width) return controller.frame;
    var x = box.globalToLocal(global).dx - width;
    return _view.frameAt(x, box.size.width - width, controller.timelineReach);
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

/// _shapeOf is the stored sound whose waveform a clip's file is drawn with:
/// the file itself for a sound, its soundtrack for a video.
String _shapeOf(TimedLane lane, MediaSource source) =>
    lane.element is VideoElement ? source.soundId : source.assetId;

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

/// paintPastScene marks the frames from [scene] on as outside the scene:
/// shaded and hatched, with a line where the scene ends. The timeline runs on
/// past the scene where a clip does -- see CanvasController.timelineReach --
/// and what is drawn out there is not played.
void paintPastScene(Canvas canvas, Size size, TimelineView view, int scene,
        ColorScheme colors) =>
    paintOutsideScene(canvas, size, view, null, scene, colors);

/// paintOutsideScene shades and hatches everything before [from] and from
/// [to] on -- either left open with null -- with a line at each edge: the
/// frames a lane's clips are not played in. A scene's clip that runs on past
/// its scene is shaded where it does, so it does not look as if it plays in
/// the next scene too.
void paintOutsideScene(Canvas canvas, Size size, TimelineView view, int? from,
    int? to, ColorScheme colors) {
  var hatch = Paint()
    ..color = colors.onSurfaceVariant.withValues(alpha: 0.18)
    ..strokeWidth = 1;
  var edge = Paint()
    ..color = colors.onSurfaceVariant.withValues(alpha: 0.6)
    ..strokeWidth = 1;
  void shade(double a, double b, double edgeAt) {
    a = math.max(0.0, a);
    b = math.min(size.width, b);
    if (b <= a) return;
    var out = Rect.fromLTRB(a, 0, b, size.height);
    canvas.save();
    canvas.clipRect(out);
    canvas.drawRect(out, Paint()..color = const Color(0x66000000));
    // Pinned to the frames rather than the screen, so the hatching moves
    // with the timeline as it scrolls.
    // The first line on the same eight-pixel step as the edge that reaches
    // the shaded part's left end.
    var start = edgeAt - 8 * ((edgeAt - (a - size.height)) / 8).ceilToDouble();
    for (var x = start; x < b; x += 8) {
      canvas.drawLine(
          Offset(x, size.height), Offset(x + size.height, 0), hatch);
    }
    canvas.restore();
    if (edgeAt >= 0 && edgeAt <= size.width) {
      canvas.drawLine(Offset(edgeAt, 0), Offset(edgeAt, size.height), edge);
    }
  }

  if (from != null) {
    var x = view.xOf(from, size.width);
    shade(0, x, x);
  }
  if (to != null) {
    var x = view.xOf(to, size.width);
    shade(x, size.width, x);
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

  /// sceneFrom and sceneTo are the frames, in this lane's view, its clips
  /// are played in: their scene's, or the whole run's for the master's.
  /// Outside them is shaded. Null is open on that side.
  final int? sceneFrom;
  final int? sceneTo;

  /// onMaster is whether the master is being edited: seen from a scene, a
  /// clip of the master's says so.
  final bool onMaster;

  _LanePainter({
    required this.onMaster,
    required this.sceneFrom,
    required this.sceneTo,
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
    // Over the clips, so the part of one that runs on past the scene reads
    // as not played.
    paintOutsideScene(canvas, size, view, sceneFrom, sceneTo, colors);

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
    // A video's clips violet, a sound's teal, an instrument's part -- notes,
    // not a recording -- blue, as a MIDI clip is told from audio.
    var instrument = lane.element is AudioElement &&
        (lane.element as AudioElement).isInstrument;
    // A sound made a clip (see timeline_clips.dart) in its clip's colour.
    var asClip = lane.element is AudioElement && clip.playlist.isNotEmpty
        ? clip.playlist.first.clip
        : null;
    var fill = (video
            ? const Color(0xFF7B5CC4)
            : instrument
                ? const Color(0xFF3D6FD9)
                : asClip != null && asClip.color != timelineClipColour
                    ? Color(sectionColors[asClip.color % sectionColors.length])
                    : const Color(0xFF2A9D8F))
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

    // An instrument's part: its notes, each where it is played and as high
    // as its key -- a piano roll in small -- rather than the shape of the
    // file they were played into.
    var part = switch (lane.element) {
      AudioElement a => a.instrument,
      _ => null,
    };
    if (part != null && part.notes.isNotEmpty) {
      var lo = part.notes.map((n) => n.key).reduce(math.min) - 1;
      var hi = part.notes.map((n) => n.key).reduce(math.max) + 1;
      var row = (bottom - top - 4) / math.max(1, hi - lo + 1);
      var ink = Paint()..color = const Color(0xDDFFFFFF);
      for (var n in part.notes) {
        var a = _x(span.from + n.start * rate, w);
        var b = _x(span.from + n.end * rate, w);
        if (b < 0 || a > w) continue;
        var y = bottom - 2 - (n.key - lo + 1) * row;
        canvas.drawRRect(
            RRect.fromLTRBR(a, y, math.max(a + 1.5, b),
                y + math.max(1.5, row - 0.5), const Radius.circular(1)),
            ink);
      }
    } else if (size.height >= _waveformFrom) {
      // The shape of the sound as it will come out -- its peaks times its own
      // volume -- where the lane is tall enough to read one. Turned up, it
      // grows; where a peak would go past full it stops at the edge, in red,
      // which is where it would clip.
      var ink = Paint()
        ..color = const Color(0x99FFFFFF)
        ..strokeWidth = 1;
      var over = Paint()
        ..color = const Color(0xFFE05050)
        ..strokeWidth = 1;
      var mid = (top + bottom) / 2 + 5;
      var reach = (bottom - top) / 2 - 7;
      var gain = clip.volume;
      for (var (i, cut) in span.cuts.indexed) {
        var source = clip.playlist[i];
        var peaks = shapes[_shapeOf(lane, source)];
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

    // The volume line: this clip's own level, dragged up or down -- a
    // video's soundtrack the same as a sound.
    {
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
      // Said where it lives, seen from a scene: changed from here, it is
      // the master's that changes.
      var name = lane.scene < 0 && !onMaster
          ? "${lane.element.name} (master)"
          : lane.element.name;
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

/// _InteractiveLanePainter draws a lane with no time on it: hatched grey,
/// saying why, with the playhead going through it like every other lane.
class _InteractiveLanePainter extends CustomPainter {
  final String label;
  final ColorScheme colors;
  final bool chosen;
  final int frame;
  final TimelineView view;

  _InteractiveLanePainter({
    required this.label,
    required this.colors,
    required this.chosen,
    required this.frame,
    required this.view,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    var body = Rect.fromLTRB(0, 3, size.width, size.height - 3);
    canvas.drawRect(
        body,
        Paint()
          ..color = colors.onSurface.withValues(alpha: chosen ? 0.10 : 0.06));
    var hatch = Paint()
      ..color = colors.onSurface.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (var x = -size.height; x < size.width; x += 9) {
      canvas.drawLine(
          Offset(x, body.bottom), Offset(x + body.height, body.top), hatch);
    }
    var text = TextPainter(
      text: TextSpan(
          text: label,
          style: TextStyle(
              fontSize: 11,
              height: 1.2,
              color: colors.onSurfaceVariant.withValues(alpha: 0.9))),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: "…",
    )..layout(maxWidth: math.max(0, size.width - 16));
    if (size.height >= text.height + 4) {
      text.paint(canvas, Offset(8, (size.height - text.height) / 2));
    }
    var head = view.centreOf(frame, size.width);
    canvas.drawLine(Offset(head, 0), Offset(head, size.height),
        Paint()..color = colors.primary.withValues(alpha: 0.5));
  }

  @override
  bool shouldRepaint(_InteractiveLanePainter old) =>
      old.label != label ||
      old.chosen != chosen ||
      old.frame != frame ||
      old.colors != colors;
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

/// _ChannelHeader is a channel's strip at the left of its lane: a coloured
/// edge for its kind; its short name (A1, V1); its whole name once the lane
/// is tall enough, double-clicked to rename it; its level in decibels,
/// clicked to type one; and lock, solo and mute. Narrowed, it gives up the
/// reading, then the buttons one at a time. Its bottom edge is dragged to
/// make the lane taller, and a click picks the channel.
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

  /// onMoveStart, onMove and onMoveEnd are the strip pressed and dragged up
  /// or down, to put the channel somewhere else in the list.
  final ValueChanged<double> onMoveStart;
  final ValueChanged<double> onMove;
  final VoidCallback onMoveEnd;

  /// mix is the channel's as it plays now, its lanes' settings put in --
  /// what its level reads. See CanvasController.mixNow.
  final ChannelMix mix;

  /// automation is whether its lanes are open under it, and onAutomation
  /// its A button, opening or shutting them.
  final bool automation;
  final VoidCallback onAutomation;

  /// controller reads its level, for the meter beside its lane.
  final CanvasController? controller;

  /// owned is an element's own sound, under the element's header as the
  /// same row: only its band's label and meter, the name being above.
  final bool owned;

  const _ChannelHeader({
    this.controller,
    this.owned = false,
    required this.mix,
    required this.automation,
    required this.onAutomation,
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
    required this.onMoveStart,
    required this.onMove,
    required this.onMoveEnd,
    super.key,
  });

  /// kind is what the channel is, said small under its name.
  String get kind {
    if (channel.video) return "Video";
    if (channel.interactive) return "Played when pressed";
    var e = channel.first.element;
    if (e is AudioElement && e.instrument != null) return "MIDI instrument";
    return "Audio";
  }

  /// _menu is the strip's right-click menu: what a short row has no room
  /// for -- the lock and the automation's lanes.
  Future<void> _menu(BuildContext context, Offset at) async {
    var choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        PopupMenuItem(
            key: const ValueKey("channelMenuLock"),
            value: "lock",
            height: 32,
            child: Text(channel.locked ? "Unlock its clips" : "Lock its clips",
                style: const TextStyle(fontSize: 12.5))),
        if (channel.editable)
          PopupMenuItem(
              key: const ValueKey("channelMenuAutomation"),
              value: "automation",
              height: 32,
              child: Text(
                  automation ? "Hide its automation" : "Show its automation",
                  style: const TextStyle(fontSize: 12.5))),
      ],
    );
    if (choice == "lock") onLock();
    if (choice == "automation") onAutomation();
  }

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    var locked = channel.locked;

    // Which canvas its clips are on -- M the master, S1 the first scene.
    Widget code = Container(
      key: const ValueKey("channelCode"),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
          color: colors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(6)),
      child: Text(label,
          maxLines: 1,
          style: TextStyle(
              fontSize: 9,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant)),
    );

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

    var strip = GestureDetector(
      supportedDevices: timelinePointers,
      behavior: HitTestBehavior.opaque,
      onTap: onSelect,
      onSecondaryTapUp: (d) => _menu(context, d.globalPosition),
      child: RowHeader(
        colour: channelColour(channel.video),
        width: width,
        height: height,
        selected: selected,
        name: ChannelNameEditor(
            name: channel.name, theme: theme, onRename: onRename),
        kind: kind,
        badges: [code],
        // A tall row's own: its automation's lanes, the lock, the level.
        tools: [
          if (channel.editable)
            _StripButton(
              key: const ValueKey("channelAutomation"),
              text: "A",
              on: automation,
              onColor: automationColour,
              theme: theme,
              onTap: onAutomation,
            ),
          _StripButton(
            key: const ValueKey("channelLock"),
            icon: locked ? Icons.lock : Icons.lock_open,
            on: locked,
            onColor: colors.onSurface,
            theme: theme,
            onTap: onLock,
          ),
          // The level typed, as the mixer's fader: on the widest strip.
          if (width >= 230) reading,
        ],
        sound: RowToggle(const ValueKey("channelMute"),
            on: !mix.mute, onTap: () => onMix(mix.copyWith(mute: !mix.mute))),
        solo:
            RowToggle(const ValueKey("channelSolo"), on: soloed, onTap: onSolo),
        bands: [
          RowBand(0, height, channel.video ? "Video" : "Sound", soundColour)
        ],
        meter: channel.key,
        controller: controller,
        continued: owned,
      ),
    );

    return Stack(children: [
      Positioned.fill(
        // Pressed and dragged up or down, the channel moves in the list --
        // any channel, the master's and another scene's too, so this is
        // round the strip rather than in it.
        child: GestureDetector(
          key: ValueKey("channelMove-${channel.key}"),
          supportedDevices: timelinePointers,
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: (d) => onMoveStart(d.globalPosition.dy),
          onVerticalDragUpdate: (d) => onMove(d.globalPosition.dy),
          onVerticalDragEnd: (_) => onMoveEnd(),
          onVerticalDragCancel: onMoveEnd,
          // A channel from the master is changed there, as in the mixer.
          child: channel.editable
              ? strip
              : IgnorePointer(child: Opacity(opacity: 0.55, child: strip)),
        ),
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

/// ChannelNameEditor is a channel's whole name, double-clicked to rename it:
/// on its strip beside the timeline, and in the mixer.
class ChannelNameEditor extends StatefulWidget {
  final String name;
  final ThemeNotifier theme;
  final ValueChanged<String> onRename;
  final double fontSize;
  final FontWeight weight;

  /// textKey and fieldKey are the name's and, while it is typed, the
  /// field's.
  final Key textKey;
  final Key fieldKey;

  /// color is the name's, where it is drawn on something other than the
  /// app's own surface -- the mixer's studio strip.
  final Color? color;
  const ChannelNameEditor(
      {required this.name,
      required this.theme,
      required this.onRename,
      this.fontSize = 11,
      this.weight = FontWeight.w500,
      this.textKey = const ValueKey("channelName"),
      this.fieldKey = const ValueKey("channelNameField"),
      this.color,
      super.key});

  @override
  State<ChannelNameEditor> createState() => ChannelNameEditorState();
}

class ChannelNameEditorState extends State<ChannelNameEditor> {
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
        fontSize: widget.fontSize,
        height: 1.2,
        fontWeight: widget.weight,
        color: widget.color ?? widget.theme.colors.onSurface);
    if (_typing) {
      return TextField(
        key: widget.fieldKey,
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
          key: widget.textKey,
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

  /// onAudio and onMidi add a channel of either kind: a sound chosen, or an
  /// instrument to play into.
  final VoidCallback onAudio;
  final VoidCallback onMidi;

  /// onEmptyAudio and onEmptyMidi add one of either with nothing on it: an
  /// audio channel waiting for a sound, a MIDI channel on the timeline alone.
  final VoidCallback onEmptyAudio;
  final VoidCallback onEmptyMidi;
  const _EmptyHeader(
      {required this.width,
      required this.name,
      required this.theme,
      required this.onAudio,
      required this.onMidi,
      required this.onEmptyAudio,
      required this.onEmptyMidi});

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    // The + is a menu of the two kinds of channel there are.
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          key: const ValueKey("addAudioChannel"),
          leadingIcon: const Icon(Icons.graphic_eq, size: 16),
          onPressed: onAudio,
          child: const Text("Audio channel: choose a sound",
              style: TextStyle(fontSize: 12)),
        ),
        MenuItemButton(
          key: const ValueKey("addEmptyAudioChannel"),
          leadingIcon: const Icon(Icons.graphic_eq, size: 16),
          onPressed: onEmptyAudio,
          child:
              const Text("Empty audio channel", style: TextStyle(fontSize: 12)),
        ),
        const Divider(height: 1),
        MenuItemButton(
          key: const ValueKey("addMidiChannel"),
          leadingIcon: const Icon(Icons.piano, size: 16),
          onPressed: onMidi,
          child: const Text("MIDI channel: an instrument to play",
              style: TextStyle(fontSize: 12)),
        ),
        MenuItemButton(
          key: const ValueKey("addEmptyMidiChannel"),
          leadingIcon: const Icon(Icons.piano_outlined, size: 16),
          onPressed: onEmptyMidi,
          child: const Text("Empty MIDI channel: on the timeline only",
              style: TextStyle(fontSize: 12)),
        ),
      ],
      builder: (context, menu, _) => Tooltip(
        message: "Add an audio or a MIDI channel",
        child: InkWell(
          key: const ValueKey("addChannel"),
          onTap: () => menu.isOpen ? menu.close() : menu.open(),
          child: Container(
            // Less to either side when the column is narrow, so the icon
            // alone fits.
            padding: width < 64
                ? const EdgeInsets.fromLTRB(4, 3, 2, 3)
                : const EdgeInsets.fromLTRB(8, 3, 8, 3),
            decoration: BoxDecoration(
                border:
                    Border(right: BorderSide(color: colors.outlineVariant))),
            child: Row(children: [
              Icon(Icons.add, size: 14, color: colors.primary),
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
          ),
        ),
      ),
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

/// SessionRowSlots are a channel's clip slots beside its row on the
/// timeline, a cue each, as on its strip in the mixer: its triangle
/// launches it -- an empty one's square stops the channel; its name clicked
/// picks it (Delete then empties it), double-clicked opens it; an empty one
/// double-clicked has a clip made in it; dragged, onto a lane.
class SessionRowSlots extends StatelessWidget {
  final CanvasController controller;
  final String channel;
  const SessionRowSlots(
      {required this.controller, required this.channel, super.key});

  @override
  Widget build(BuildContext context) {
    var c = controller;
    var colors = ThemeNotifier.of(context).colors;
    return SlotsWindow(controller: c, cell: (i) => _cell(c, colors, i));
  }

  Widget _cell(CanvasController c, ColorScheme colors, int row) {
    var clip = c.session.at(channel, row);
    var state = c.clipState(channel, row);
    var lit = state == ClipState.playing ||
        state == ClipState.stopping ||
        state == ClipState.queued;
    var ink = lit ? const Color(0xFF0E0F12) : colors.onSurface;
    var launch = Listener(
      key: ValueKey("rowClipLaunch-$channel-$row"),
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => c.pressClip(channel, row),
      onPointerUp: (_) => c.releaseClip(channel, row),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Icon(clip == null ? Icons.stop : Icons.play_arrow,
            size: 11, color: clip == null ? colors.onSurfaceVariant : ink),
      ),
    );
    var picked = c.selectedSlot == (channel, row);
    var cell = Container(
      key: ValueKey("rowClip-$channel-$row"),
      decoration: BoxDecoration(
        color: clip == null
            ? colors.surfaceContainerHigh
            : Color(sectionColors[clip.color % sectionColors.length])
                .withValues(alpha: lit ? 1 : 0.45),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
            color: picked && clip != null
                ? colors.onSurface
                : colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      padding: const EdgeInsets.only(left: 1, right: 3),
      child: Row(children: [
        launch,
        Expanded(
          child: clip == null
              // Double-clicked: a clip made in it (Ken).
              ? GestureDetector(
                  key: ValueKey("rowClipNew-$channel-$row"),
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: () => c.makeSessionClip(channel, row),
                )
              : SlotFocus(
                  key: ValueKey("rowClipKeys-$channel-$row"),
                  onDelete: () {
                    c.beginInteraction();
                    c.setSessionClip(channel, row, null);
                    c.endInteraction();
                  },
                  builder: (focus) => GestureDetector(
                    key: ValueKey("rowClipName-$channel-$row"),
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      c.selectSlot(channel, row);
                      focus.requestFocus();
                    },
                    onDoubleTap: () => c.openClipEditor(channel, row),
                    child: Text(clip.name.isEmpty ? "Clip" : clip.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: ink)),
                  ),
                ),
        ),
      ]),
    );
    if (clip == null) return cell;
    return Draggable<Object>(
      data: SessionSlotDrag(channel, row, clip),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Color(sectionColors[clip.color % sectionColors.length]),
        borderRadius: BorderRadius.circular(3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(clip.name.isEmpty ? "Clip" : clip.name,
              style: const TextStyle(fontSize: 10, color: Color(0xFF0E0F12))),
        ),
      ),
      child: cell,
    );
  }
}
