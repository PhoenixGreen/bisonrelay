import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/ui/asset_elements.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// canvas_channels.dart is the media on the timeline, one lane each, laid out
// against the same frames as the keyframe strip above it.
//
// Part of the timeline, under the keyframe strip, in the room the timeline is
// dragged open to -- see CanvasTimeline. The lanes scroll there rather than
// the timeline growing to hold them, which would re-fit the canvas and move
// the design every time a channel was added.
//
// A lane is its clip drawn as a bar from the frame it starts on to the frame
// it ends on: one block per file, the fades as slopes, a repeat drawn fainter
// to the end of the timeline. The bar is dragged to move the clip, and its
// ends to trim it -- the first file's start and the last file's end, which
// is the play range, the same numbers the settings panel shows.

/// channelsLaneHeight is one lane.
const double channelsLaneHeight = 26;
const double _edgeGrab = 7;

class CanvasChannels extends StatefulWidget {
  final CanvasController controller;
  const CanvasChannels({required this.controller, super.key});

  /// hint is what an empty set of channels says.
  static const String hint = "Add audio for a channel to drop a sound on, or "
      "put a video or a background's video or sound on the timeline in its "
      "settings.";

  @override
  State<CanvasChannels> createState() => _CanvasChannelsState();
}

enum _Grip { move, start, end }

class _CanvasChannelsState extends State<CanvasChannels> {
  CanvasController get controller => widget.controller;

  // What a drag took hold of, and the clip as it was when it did.
  TimedLane? _held;
  _Grip _grip = _Grip.move;
  MediaClip? _was;

  /// _pressedX is where the press was, on screen. A drag is measured from
  /// it rather than by adding up the drag's own steps, because a drag is
  /// only recognised once the pointer has already moved some way -- and
  /// that first stretch never arrives as a step, so a clip dragged twenty
  /// frames moved sixteen.
  double _pressedX = 0;

  double _framesPerPixel(double width) {
    var frames = controller.document.frames;
    return width <= 0 ? 0 : frames / width;
  }

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

  void _press(TimedLane lane, Offset at, Offset global, double width) {
    if (!lane.editable || lane.clip.isEmpty) return;
    var span = _span(lane);
    // The bar is drawn from the start of its first frame to the end of its
    // last -- see _LanePainter -- and the ends are pressed where they are drawn.
    var frames = controller.document.frames;
    var left = frames <= 0 ? 0.0 : span.from / frames * width;
    var right = frames <= 0 ? 0.0 : span.to / frames * width;
    _grip = (at.dx - left).abs() <= _edgeGrab
        ? _Grip.start
        : (at.dx - right).abs() <= _edgeGrab
            ? _Grip.end
            : _Grip.move;
    _held = lane;
    _was = lane.clip;
    _pressedX = global.dx;
    controller.pause();
    controller.beginInteraction();
    // Pressing a lane picks its element, where it is one: the settings for
    // what is being moved should be the ones on screen.
    if (controller.document.elements.any((e) => e.id == lane.element.id)) {
      controller.selectOnly(lane.element.id);
    }
  }

  void _drag(double globalX, double width) {
    var lane = _held, was = _was;
    if (lane == null || was == null) return;
    var frames = (globalX - _pressedX) * _framesPerPixel(width);
    var rate = controller.document.frameRate.toDouble();
    var seconds = frames / (rate <= 0 ? 1 : rate);
    MediaClip next;
    switch (_grip) {
      case _Grip.move:
        next = was.copyWith(at: math.max(0, was.at + frames.round()));
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
    }
    controller.setTimedClip(lane.element, next, transient: true);
    setState(() {});
  }

  void _release() {
    if (_held == null) return;
    _held = null;
    _was = null;
    controller.endInteraction();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        var lanes = controller.timedLanes;
        // A sound dropped anywhere that is not a lane is a new channel, from
        // the frame it was dropped on.
        return DragTarget<Object>(
          key: _area,
          onWillAcceptWithDetails: (d) =>
              droppedKind(d.data) == AssetKind.audio,
          onAcceptWithDetails: (d) async {
            var at = _frameAt(d.offset);
            var asset = await droppedAsset(d.data);
            if (asset == null) return;
            controller.addElement(
                audioChannel(controller.document, at, asset: asset));
          },
          builder: (context, candidate, _) => Container(
            decoration: BoxDecoration(
              color: candidate.isEmpty
                  ? null
                  : theme.colors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(4),
            ),
            child: lanes.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(CanvasChannels.hint,
                        style: TextStyle(
                            fontSize: 11,
                            color: theme.colors.onSurfaceVariant)),
                  )
                : _lanes(lanes, theme),
          ),
        );
      },
    );
  }

  /// _area is the channels' whole room, for the frame a drop landed on.
  final GlobalKey _area = GlobalKey();

  /// _frameAt is the frame under [global], across the channels' width.
  int _frameAt(Offset global) {
    var box = _area.currentContext?.findRenderObject();
    if (box is! RenderBox || box.size.width <= 0) return controller.frame;
    var x = box.globalToLocal(global).dx / box.size.width;
    var frames = controller.document.frames;
    return (x * frames).floor().clamp(0, frames - 1).toInt();
  }

  /// _fill puts [asset] in [lane]'s channel: as its sound, where it has
  /// none, and after what it has, where it has -- a channel plays its files
  /// one after another.
  void _fill(TimedLane lane, LibraryAsset asset) {
    var clip = lane.clip;
    controller.setTimedClip(lane.element,
        clip.copyWith(playlist: [...clip.playlist, asset.source]));
    if (controller.document.elements.any((e) => e.id == lane.element.id)) {
      controller.selectOnly(lane.element.id);
    }
  }

  Widget _lanes(List<TimedLane> lanes, ThemeNotifier theme) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (var lane in lanes)
          SizedBox(
            key: ValueKey("lane-${lane.element.id}"),
            height: channelsLaneHeight,
            child: DragTarget<Object>(
              onWillAcceptWithDetails: (d) =>
                  droppedKind(d.data) == AssetKind.audio &&
                  lane.editable &&
                  lane.element is AudioElement,
              onAcceptWithDetails: (d) async {
                var asset = await droppedAsset(d.data);
                if (asset != null) _fill(lane, asset);
              },
              builder: (context, candidate, _) => LayoutBuilder(
                builder: (context, box) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragDown: (d) => _press(
                      lane, d.localPosition, d.globalPosition, box.maxWidth),
                  onHorizontalDragUpdate: (d) =>
                      _drag(d.globalPosition.dx, box.maxWidth),
                  onHorizontalDragEnd: (_) => _release(),
                  onHorizontalDragCancel: _release,
                  // A tap on an empty channel picks it, so its settings --
                  // where a file can be chosen -- are the ones on screen.
                  onTap: () {
                    if (controller.document.elements
                        .any((e) => e.id == lane.element.id)) {
                      controller.selectOnly(lane.element.id);
                    }
                  },
                  child: MouseRegion(
                    cursor: lane.editable && !lane.clip.isEmpty
                        ? SystemMouseCursors.resizeLeftRight
                        : SystemMouseCursors.basic,
                    child: CustomPaint(
                      size: Size(box.maxWidth, channelsLaneHeight),
                      painter: _LanePainter(
                        lane: lane,
                        span: _span(lane),
                        frames: controller.document.frames,
                        frame: controller.frame,
                        frameRate: controller.document.frameRate,
                        colors: theme.colors,
                        held: _held?.element.id == lane.element.id ||
                            candidate.isNotEmpty,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LanePainter extends CustomPainter {
  final TimedLane lane;
  final ({double from, double to, List<double> cuts}) span;
  final int frames;
  final int frame;
  final int frameRate;
  final ColorScheme colors;
  final bool held;

  _LanePainter({
    required this.lane,
    required this.span,
    required this.frames,
    required this.frame,
    required this.frameRate,
    required this.colors,
    required this.held,
  });

  double _x(num f, double width) => frames <= 0 ? 0 : f / frames * width;

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width;
    var top = 3.0, bottom = size.height - 3;

    // An empty channel: its outline across the lane, and what to do with it.
    if (lane.clip.isEmpty) {
      var box =
          RRect.fromLTRBR(0.5, top, w - 0.5, bottom, const Radius.circular(4));
      canvas.drawRRect(
          box,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = held ? colors.primary : colors.outlineVariant);
      var text = TextPainter(
        text: TextSpan(
            text: "${lane.element.name} — drop a sound here",
            style: TextStyle(fontSize: 10.5, color: colors.onSurfaceVariant)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: "…",
      )..layout(maxWidth: math.max(0, w - 12));
      text.paint(canvas, Offset(6, (size.height - text.height) / 2));
      return;
    }
    var video = lane.element is VideoElement;
    var fill = (video ? const Color(0xFF7B5CC4) : const Color(0xFF2A9D8F))
        .withValues(alpha: lane.editable ? 1 : 0.45);

    var from = _x(span.from, w), to = _x(span.to, w);
    var clip = lane.clip;

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
    if (held) {
      canvas.drawRRect(
          bar,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = colors.primary);
    }

    // Where each file begins, after the first.
    for (var cut in span.cuts.skip(1)) {
      var x = _x(cut, w);
      canvas.drawLine(Offset(x, top), Offset(x, bottom),
          Paint()..color = const Color(0x88FFFFFF));
    }

    // The fades, as slopes at the ends of each file.
    var rate = frameRate <= 0 ? 1 : frameRate;
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
    text.paint(canvas,
        Offset(inside ? from + 6 : to + 6, (size.height - text.height) / 2));

    // The playhead, through every lane, as on the strip below.
    var head = (frame + 0.5) / (frames <= 0 ? 1 : frames) * w;
    canvas.drawLine(
        Offset(head, 0),
        Offset(head, size.height),
        Paint()
          ..color = colors.primary
          ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_LanePainter old) =>
      old.span != span ||
      old.frame != frame ||
      old.frames != frames ||
      old.held != held ||
      old.lane.clip != lane.clip ||
      old.colors != colors;
}
