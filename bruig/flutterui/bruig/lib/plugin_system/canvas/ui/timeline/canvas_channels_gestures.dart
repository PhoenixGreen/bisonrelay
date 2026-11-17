part of 'canvas_channels.dart';

// Pressing, dragging and letting go on the lanes: grips, the box dragged,
// snapping. Part of _CanvasChannelsState: its fields, lifecycle and build are
// in canvas_channels.dart.

extension _ChannelGestures on _CanvasChannelsState {
  CanvasController get controller => widget.controller;

  TimelineView get _view => widget.view;

  GlobalKey _keyFor(String channel) =>
      _laneKeys.putIfAbsent(channel, () => GlobalKey());

  /// _heightOf is channel [channel]'s row: as tall as it was dragged, or as
  /// the channel height says -- folded by its arrow, or its element's, as
  /// at S; opened by it at S, as at M.
  double _heightOf(String channel) {
    var folded = controller.rowFolded(_foldKeyOf(channel));
    var small = controller.laneSize == 0;
    if (folded && !small) return laneSizeHeights[0];
    if (!folded && small) return laneSizeHeights[1];
    return controller.laneHeights[channel] ??
        laneSizeHeights[controller.laneSize];
  }

  /// _foldKeyOf is whose fold arrow folds channel [channel]: its element's,
  /// for the element's own sound (the same row), else its own.
  String _foldKeyOf(String channel) =>
      soundOwnerOf(controller.document, channel)?.id ?? channel;

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
      if (controller.timelineTool == TimelineTool.select) _boxStart(global);
      return;
    }
    var (lane, grip) = hit;
    if (!_canEdit(lane)) return;
    _grip = grip;
    _was = lane.clip;
    _wasRun = controller.clipRunStart(lane.element.id);
  }

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

  /// _boxStart begins the box at [global] -- pressed on an empty sound lane,
  /// or an empty motion lane (see MotionLanes.onBoxStart).
  void _boxStart(Offset global) {
    _boxFrom = global;
    _boxTo = null;
    var adding = HardwareKeyboard.instance.isShiftPressed;
    _boxBase = adding ? {...controller.clipSelection} : {};
    _boxChannels = adding ? {...controller.selectedChannels} : {};
    _boxMotion = adding ? {...controller.motionPicks} : {};
  }

  void _boxEnd() {
    _boxFrom = null;
    _boxTo = null;
    setState(() {});
  }

  /// _box picks every sound the box touches, and the channels they are on,
  /// and every motion clip on the elements' rows.
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
    controller.pickMotions({..._boxMotion, ...motionPlacementsIn(box)});
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
    // Twice on a sound or a MIDI part: its channel's chain opened and it
    // picked, as a double-click opens an element's clip in the Chain.
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
      // The motion clips linked to it, and where each starts: moved with it
      // -- and, picked with it, the motion clips picked.
      _links = _grip == _Grip.move
          ? [
              for (var (el, id) in {
                ...controller.placementsLinkedTo(lane.element.id),
                if (picked.contains(lane.element.id)) ...controller.motionPicks,
              })
                if (controller.spanOf(id) case var s?) (el, id, s.start),
            ]
          : const [];
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
        // Linked: its motion moves by as much.
        for (var (el, id, start) in _links) {
          controller.movePlacement(
              el, id, math.max(0.0, start + frames.round() / rate),
              transient: true);
        }
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

  /// _trackOver notes the lane [lane]'s clip would be let go onto, for a
  /// move onto another channel (one clip, not several). A video's soundtrack
  /// goes with it, so a channel can hold sounds and videos in turn.
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
    _links = const [];
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
          controller.moveClipToChannel(
              now, over == _CanvasChannelsState._newLane ? null : to,
              transient: true);
          controller.selectedChannel = over == _CanvasChannelsState._newLane
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
}
