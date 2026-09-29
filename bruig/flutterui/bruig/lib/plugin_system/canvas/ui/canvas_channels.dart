import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/ui/asset_elements.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/media_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_view.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

// canvas_channels.dart is the sound on the timeline, a lane for each channel,
// laid out against the same frames as the keyframe strip above it.
//
// A channel is the sounds on it -- see TimelineChannel. There is always one
// lane more than there are channels, empty, at the bottom: a sound dropped
// there, or chosen by clicking it, starts a channel, and when that one fills a
// new empty lane is under it. A channel with nothing left on it is simply not
// there any more.
//
// Each sound is a bar from the frame it starts on to the frame it ends on:
// one block per file, the fades as slopes, a repeat drawn fainter to the end.
// A bar is dragged along to move it and onto another lane to move it there;
// its ends are dragged to trim it, and the handles at its top corners to fade
// it in and out. With the knife, a click cuts it in two. Taller than a line of
// text, a lane draws each file's waveform.

/// channelsLaneHeight is a lane as it starts: tall enough for its strip on
/// the left -- the name with mute and solo, and the level under them.
const double channelsLaneHeight = 34;

/// _laneMin and _laneMax bound a lane dragged taller or shorter.
const double _laneMin = 26;
const double _laneMax = 180;

/// _waveformFrom is how tall a lane has to be before it shows its waveform.
const double _waveformFrom = 46;

const double _edgeGrab = 7;

/// _fadeGrab is how far down from the top of a bar its fade handles reach.
const double _fadeGrab = 10;

/// timelineHeaderWidth is the channel strips' column as it starts. The reader
/// drags it -- see CanvasController.headerWidth.
const double timelineHeaderWidth = 150;

/// _showsControls and _showsName are the widths at which a strip has room
/// for mute, solo and its reading; and for its name and its level. Narrower
/// than both, it is its icon.
const double _showsControls = 128;
const double _showsName = 64;

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

enum _Grip { move, start, end, fadeIn, fadeOut }

class _CanvasChannelsState extends State<CanvasChannels> {
  CanvasController get controller => widget.controller;
  TimelineView get _view => widget.view;

  // What a press took hold of, and the clip as it was when it did.
  TimedLane? _held;
  _Grip _grip = _Grip.move;
  MediaClip? _was;
  bool _dragging = false;

  /// _pressedX is where the press was, on screen. A drag is measured from
  /// it rather than by adding up the drag's own steps, because a drag is
  /// only recognised once the pointer has already moved some way -- and
  /// that first stretch never arrives as a step, so a clip dragged twenty
  /// frames moved sixteen.
  double _pressedX = 0;

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

  void _press(TimelineChannel channel, Offset at, Offset global, double width) {
    var lane = _clipAt(channel, at.dx, width);
    _held = lane;
    _dragging = false;
    if (lane == null || !lane.editable) return;
    var span = _span(lane);
    var clip = lane.clip;
    var rate = controller.document.frameRate.toDouble();
    var left = _view.xOf(span.from, width);
    var right = _view.xOf(span.to, width);
    var fadeInX = _view.xOf(span.from + clip.fadeIn * rate, width);
    var fadeOutX = _view.xOf(span.to - clip.fadeOut * rate, width);
    // The fade handles first: they sit on the top edge, at the corners until
    // a fade is drawn, and on the ends of the slopes after.
    _grip = at.dy <= _fadeGrab && (at.dx - fadeInX).abs() <= _edgeGrab
        ? _Grip.fadeIn
        : at.dy <= _fadeGrab && (at.dx - fadeOutX).abs() <= _edgeGrab
            ? _Grip.fadeOut
            : (at.dx - left).abs() <= _edgeGrab
                ? _Grip.start
                : (at.dx - right).abs() <= _edgeGrab
                    ? _Grip.end
                    : _Grip.move;
    _was = clip;
    _pressedX = global.dx;
  }

  void _tap(TimelineChannel channel, Offset at, double width) {
    var lane = _held ?? _clipAt(channel, at.dx, width);
    _held = null;
    if (lane == null) {
      controller.clearSelection();
      return;
    }
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

  void _drag(Offset global, double width) {
    var lane = _held, was = _was;
    if (lane == null || was == null || !lane.editable) return;
    if (controller.timelineTool == TimelineTool.knife) return;
    if (!_dragging) {
      _dragging = true;
      controller.pause();
      controller.beginInteraction();
      _pick(lane);
    }
    var frames = _view.framesPer(global.dx - _pressedX, width);
    var rate = controller.document.frameRate.toDouble();
    var seconds = frames / (rate <= 0 ? 1 : rate);
    MediaClip next;
    switch (_grip) {
      case _Grip.move:
        next = was.copyWith(at: math.max(0, was.at + frames.round()));
        // And onto another lane, where it is let go over one. Audio only: a
        // video's lane is its own.
        if (lane.element is AudioElement) {
          var over = _laneUnder(global);
          var own = lane.channelKey;
          _over = over == own ? null : over;
        }
      case _Grip.start:
        // Trimming the front moves the start of the first file's range and
        // the clip with it, so what is left stays where it was on the
        // timeline -- the way an editor trims.
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
            fadeIn:
                (was.fadeIn + seconds).clamp(0.0, _shortest(was)).toDouble());
      case _Grip.fadeOut:
        next = was.copyWith(
            fadeOut:
                (was.fadeOut - seconds).clamp(0.0, _shortest(was)).toDouble());
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

  void _release() {
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
        if (now != null) {
          controller.moveClipToChannel(now, over == _newLane ? null : to,
              transient: true);
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
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            for (var channel in channels)
              _row(channel.key, _heightOf(channel.key), width,
                  header: _ChannelHeader(
                    key: ValueKey("channelStrip-${channel.key}"),
                    channel: channel,
                    width: width,
                    height: _heightOf(channel.key),
                    soloed: controller.solo.contains(channel.key),
                    theme: theme,
                    onPick: () => _pick(channel.first),
                    onMix: (mix, {transient = false}) {
                      controller.beginInteraction();
                      controller.setChannelMix(channel, mix, transient: true);
                      if (!transient) controller.endInteraction();
                    },
                    onCommit: controller.endInteraction,
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
        );
      },
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
    controller.addElement(channelClip(controller.document, frame,
        source: source,
        channel: channel?.key ?? controller.newChannelId(),
        channelName: channel?.name ?? controller.newChannelName(),
        mix: channel?.mix ?? const ChannelMix()));
  }

  Widget _lane(TimelineChannel channel, ThemeNotifier theme) {
    var tall = _heightOf(channel.key) >= _waveformFrom;
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
          droppedKind(d.data) == AssetKind.audio && channel.editable,
      onAcceptWithDetails: (d) async {
        var at = _frameIn(channel.key, d.offset);
        var asset = await droppedAsset(d.data);
        if (asset != null) _addAt(asset.source, at, channel);
      },
      builder: (context, candidate, _) => LayoutBuilder(
        builder: (context, box) => GestureDetector(
          supportedDevices: timelinePointers,
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) =>
              _press(channel, d.localPosition, d.globalPosition, box.maxWidth),
          // The start is a move too: a pan is only recognised once the
          // pointer has gone some way, and a short drag can end on the step
          // that is recognised, with no update after it.
          onPanStart: (d) => _drag(d.globalPosition, box.maxWidth),
          onPanUpdate: (d) => _drag(d.globalPosition, box.maxWidth),
          onPanEnd: (_) => _release(),
          onPanCancel: () {
            // A tap cancels the pan before it lands; only a drag in progress
            // is let go here.
            if (_dragging) _release();
          },
          onTapUp: (d) => _tap(channel, d.localPosition, box.maxWidth),
          child: MouseRegion(
            cursor: knife
                ? SystemMouseCursors.precise
                : SystemMouseCursors.resizeLeftRight,
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
                held: _dragging ? _held?.element.id : null,
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

class _LanePainter extends CustomPainter {
  final TimelineChannel channel;
  final List<({double from, double to, List<double> cuts})> spans;
  final TimelineView view;
  final int frame;
  final int frameRate;
  final ColorScheme colors;
  final Set<String> selected;
  final String? held;
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
    required this.held,
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

    // A lane something is being dropped on, or dragged onto.
    if (target) {
      canvas.drawRect(Offset.zero & size,
          Paint()..color = colors.primary.withValues(alpha: 0.08));
    }
    // The line between this lane and the next.
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(w, size.height - 0.5),
        Paint()..color = colors.outlineVariant.withValues(alpha: 0.4));

    // A faint line at every second, as the strip above ticks them, so the
    // strip and the lanes read as one timeline rather than two.
    var rate = math.max(1, frameRate);
    var grid = Paint()
      ..color = colors.outlineVariant.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    if (w / view.span * rate > 8) {
      var s = (view.first / rate).ceil();
      for (var f = s * rate; f <= view.first + view.span; f += rate) {
        var x = _x(f, w);
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      }
    }

    for (var (i, lane) in channel.lanes.indexed) {
      _paintClip(canvas, size, lane, spans[i], top, bottom);
    }

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
    var fill = (video ? const Color(0xFF7B5CC4) : const Color(0xFF2A9D8F))
        .withValues(alpha: lane.editable ? 1 : 0.45);

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

    var rate = frameRate <= 0 ? 1 : frameRate;

    // The shape of the sound, where the lane is tall enough to read one.
    if (size.height >= _waveformFrom) {
      var ink = Paint()
        ..color = const Color(0x99FFFFFF)
        ..strokeWidth = 1;
      var mid = (top + bottom) / 2 + 5;
      var reach = (bottom - top) / 2 - 7;
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
          var h = peaks[at] * reach;
          canvas.drawLine(Offset(x, mid - h), Offset(x, mid + h), ink);
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
    if (lane.editable && to - from > 24) {
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

    // The name, inside the bar where it fits and after it where it does not.
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
    )..layout(maxWidth: math.max(0, w - from - 8));
    var inside = text.width + 12 < to - from;
    if (!inside) {
      text = TextPainter(
        text: TextSpan(
            text: name,
            style: TextStyle(fontSize: 10.5, color: colors.onSurfaceVariant)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: "…",
      )..layout(maxWidth: math.max(0, w - to - 8));
    }
    // Along the top of a tall lane, so the waveform has the rest.
    var y = size.height >= _waveformFrom
        ? top + 2
        : (size.height - text.height) / 2;
    text.paint(canvas, Offset(inside ? math.max(from, 0) + 6 : to + 6, y));
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

/// _ChannelHeader is a channel's strip at the left of its lane: what it is
/// called, mute and solo, and its level -- the same settings as its strip in
/// the mixer, where a channel is found by the thing it is next to. Narrowed,
/// it gives up its buttons and reading, then its name and level, and is its
/// icon. Its bottom edge is dragged to make the lane taller.
class _ChannelHeader extends StatelessWidget {
  final TimelineChannel channel;
  final double width;
  final double height;
  final bool soloed;
  final ThemeNotifier theme;
  final VoidCallback onPick;
  final void Function(ChannelMix mix, {bool transient}) onMix;
  final VoidCallback onCommit;
  final VoidCallback onSolo;
  final ValueChanged<double> onGripStart;
  final ValueChanged<double> onGripMove;

  const _ChannelHeader({
    required this.channel,
    required this.width,
    required this.height,
    required this.soloed,
    required this.theme,
    required this.onPick,
    required this.onMix,
    required this.onCommit,
    required this.onSolo,
    required this.onGripStart,
    required this.onGripMove,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    var mix = channel.mix;
    var named = width >= _showsName;
    var controls = width >= _showsControls;
    var icon = Icon(
        channel.video ? Icons.movie_outlined : Icons.music_note_outlined,
        size: 12,
        color: colors.onSurfaceVariant);
    var body = Container(
      padding: EdgeInsets.fromLTRB(4, 3, named ? 8 : 2, 3),
      decoration: BoxDecoration(
        border: Border(
            right: BorderSide(color: colors.outlineVariant),
            bottom: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.4))),
      ),
      child: !named
          ? Align(alignment: Alignment.topLeft, child: icon)
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Heights given, and the text's own line height pinned: the
              // app's text theme is generous with both, and a lane can be
              // thirty-four pixels.
              SizedBox(
                height: 14,
                child: Row(children: [
                  icon,
                  const SizedBox(width: 3),
                  Expanded(
                    child: GestureDetector(
                      supportedDevices: timelinePointers,
                      behavior: HitTestBehavior.opaque,
                      onTap: onPick,
                      child: Text(channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10.5,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface)),
                    ),
                  ),
                  if (controls) ...[
                    _MiniToggle(
                      key: const ValueKey("channelMute"),
                      label: "M",
                      on: mix.mute,
                      onColor: const Color(0xFFB23B3B),
                      theme: theme,
                      onTap: () => onMix(mix.copyWith(mute: !mix.mute)),
                    ),
                    const SizedBox(width: 2),
                    _MiniToggle(
                      key: const ValueKey("channelSolo"),
                      label: "S",
                      on: soloed,
                      onColor: const Color(0xFFB28A1F),
                      theme: theme,
                      onTap: onSolo,
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 1),
              SizedBox(
                height: 12,
                child: Row(children: [
                  Expanded(
                    child: _GainBar(
                      key: const ValueKey("channelGain"),
                      db: mix.gainDb,
                      theme: theme,
                      onChanged: (db, {transient = false}) =>
                          onMix(mix.copyWith(gainDb: db), transient: transient),
                      onCommit: onCommit,
                    ),
                  ),
                  if (controls) ...[
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 44,
                      child: DbReading(
                        key: const ValueKey("channelDb"),
                        db: mix.gainDb,
                        fieldHeight: 12,
                        onSet: (db) => onMix(mix.copyWith(gainDb: db)),
                        style: TextStyle(
                            fontSize: 9.5,
                            height: 1.2,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: colors.onSurfaceVariant),
                      ),
                    ),
                  ],
                ]),
              ),
            ]),
    );
    return Stack(children: [
      Positioned.fill(
        // A channel from the master is changed there, as in the mixer.
        child: channel.editable
            ? body
            : IgnorePointer(child: Opacity(opacity: 0.55, child: body)),
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
            supportedDevices: timelinePointers,
            key: ValueKey("laneGrip-${channel.key}"),
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
      padding: const EdgeInsets.fromLTRB(4, 3, 8, 3),
      decoration: BoxDecoration(
          border: Border(right: BorderSide(color: colors.outlineVariant))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.add, size: 12, color: colors.onSurfaceVariant),
        if (width >= _showsName) ...[
          const SizedBox(width: 3),
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

class _MiniToggle extends StatelessWidget {
  final String label;
  final bool on;
  final Color onColor;
  final ThemeNotifier theme;
  final VoidCallback onTap;

  const _MiniToggle({
    required this.label,
    required this.on,
    required this.onColor,
    required this.theme,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        supportedDevices: timelinePointers,
        onTap: onTap,
        child: Container(
          width: 16,
          height: 14,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? onColor : null,
            borderRadius: BorderRadius.circular(3),
            border:
                Border.all(color: on ? onColor : theme.colors.outlineVariant),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 9,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: on
                      ? const Color(0xFFFFFFFF)
                      : theme.colors.onSurfaceVariant)),
        ),
      );
}

/// _GainBar is a channel's level laid on its side: dragged along to set it,
/// double-clicked for nought decibels. The same curve as the mixer's fader,
/// so a level reads the same in either place.
class _GainBar extends StatelessWidget {
  final double db;
  final ThemeNotifier theme;
  final void Function(double db, {bool transient}) onChanged;
  final VoidCallback onCommit;

  const _GainBar({
    required this.db,
    required this.theme,
    required this.onChanged,
    required this.onCommit,
    super.key,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        var w = box.maxWidth;
        void at(double x) =>
            onChanged(faderDb(1 - (x / (w <= 0 ? 1 : w)).clamp(0.0, 1.0)),
                transient: true);
        var share = 1 - faderPosition(db);
        return GestureDetector(
          supportedDevices: timelinePointers,
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => at(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => at(d.localPosition.dx),
          onHorizontalDragEnd: (_) => onCommit(),
          onDoubleTap: () => onChanged(0),
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: SizedBox(
              height: 12,
              child: CustomPaint(
                painter: _GainBarPainter(share, theme.colors),
              ),
            ),
          ),
        );
      });
}

class _GainBarPainter extends CustomPainter {
  final double share;
  final ColorScheme colors;
  _GainBarPainter(this.share, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    var y = size.height / 2;
    var track =
        RRect.fromLTRBR(0, y - 2, size.width, y + 2, const Radius.circular(2));
    canvas.drawRRect(track, Paint()..color = colors.surfaceContainerHighest);
    var x = share.clamp(0.0, 1.0) * size.width;
    canvas.drawRRect(
        RRect.fromLTRBR(0, y - 2, x, y + 2, const Radius.circular(2)),
        Paint()..color = colors.primary.withValues(alpha: 0.7));
    // Where nought decibels is, so the unity position can be found by eye.
    var unity = (1 - faderPosition(0)) * size.width;
    canvas.drawLine(
        Offset(unity, y - 4),
        Offset(unity, y + 4),
        Paint()
          ..color = colors.onSurfaceVariant.withValues(alpha: 0.6)
          ..strokeWidth = 1);
    canvas.drawCircle(Offset(x, y), 4, Paint()..color = colors.onSurface);
  }

  @override
  bool shouldRepaint(_GainBarPainter old) =>
      old.share != share || old.colors != colors;
}
