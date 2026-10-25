import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_motion.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_view.dart';
import 'package:flutter/material.dart';

// character_timeline.dart is a character's mouths on the timeline: one lane
// under the keyframes, a block for each mouth from the frame it starts to
// the next, named by its letter. Clicking a block goes to it, so the Mouth
// tiles change it; dragging the start of one moves it between its
// neighbours. Shown for the one character selected, once it has mouths.

/// mouthLaneHeight is the lane's height.
const double mouthLaneHeight = 22;

/// mouthLaneFor is the character whose mouths have a lane -- the one
/// element selected, a character with mouths keyed -- or null.
CharacterElement? mouthLaneFor(CanvasController controller) {
  if (controller.selection.length != 1) return null;
  var e = controller.selected;
  if (e is! CharacterElement || e.mouthKeys.isEmpty) return null;
  return e;
}

class CharacterMouthLane extends StatefulWidget {
  final CanvasController controller;
  final TimelineView view;

  const CharacterMouthLane(
      {required this.controller, required this.view, super.key});

  @override
  State<CharacterMouthLane> createState() => _CharacterMouthLaneState();
}

class _CharacterMouthLaneState extends State<CharacterMouthLane> {
  CanvasController get controller => widget.controller;

  /// _moving is the frame of the mouth whose start is being dragged, as it
  /// is now.
  int? _moving;

  double _x(num frame, double width) => widget.view.xOf(frame, width);
  int _frame(double x, double width) =>
      widget.view.frameAt(x, width, controller.document.frames);

  /// _startUnder is the frame of the mouth whose start is within reach of
  /// [x], or null.
  int? _startUnder(CharacterElement e, double x, double width) {
    int? best;
    var nearest = 6.0;
    for (var k in e.mouthKeys) {
      var d = (_x(k.frame, width) - x).abs();
      if (d <= nearest) {
        nearest = d;
        best = k.frame;
      }
    }
    return best;
  }

  /// _blockUnder is the frame of the mouth whose block holds [x].
  int? _blockUnder(CharacterElement e, double x, double width) {
    var f = _frame(x, width);
    int? at;
    for (var k in e.mouthKeys) {
      if (k.frame > f) break;
      at = k.frame;
    }
    return at;
  }

  void _move(CharacterElement e, int to) {
    var from = _moving;
    if (from == null) return;
    var keys = e.mouthKeys;
    var i = keys.indexWhere((k) => k.frame == from);
    if (i < 0) return;
    // Between its neighbours, never onto them.
    var low = i > 0 ? keys[i - 1].frame + 1 : 0;
    var high =
        i + 1 < keys.length ? keys[i + 1].frame - 1 : controller.document.frames - 1;
    var f = to.clamp(low, math.max(low, high)).toInt();
    if (f == from) return;
    var moved = [
      for (var (j, k) in keys.indexed)
        j == i ? (frame: f, shape: k.shape) : k,
    ];
    controller.replaceElement(e.withMouths(moved), transient: true);
    _moving = f;
  }

  @override
  Widget build(BuildContext context) {
    var e = mouthLaneFor(controller);
    if (e == null) return const SizedBox.shrink();
    var theme = Theme.of(context);
    return SizedBox(
      key: const ValueKey("characterMouthLane"),
      height: mouthLaneHeight,
      child: Row(children: [
        SizedBox(
          width: controller.headerWidth,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text("Mouth",
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            var width = constraints.maxWidth;
            return GestureDetector(
              supportedDevices: timelinePointers,
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) {
                var at = _blockUnder(e, d.localPosition.dx, width);
                if (at != null) {
                  controller.pause();
                  controller.frame = at;
                }
              },
              onHorizontalDragDown: (d) =>
                  _moving = _startUnder(e, d.localPosition.dx, width),
              onHorizontalDragStart: (_) {
                if (_moving == null) return;
                controller.pause();
                controller.beginInteraction();
              },
              onHorizontalDragUpdate: (d) {
                var now = mouthLaneFor(controller);
                if (now != null) _move(now, _frame(d.localPosition.dx, width));
              },
              onHorizontalDragEnd: (_) => _finish(),
              onHorizontalDragCancel: _finish,
              child: CustomPaint(
                size: Size(width, mouthLaneHeight),
                painter: _MouthPainter(
                  keys: e.mouthKeys,
                  last: controller.document.frames,
                  current: e.faceAtFrame(controller.frame).mouth,
                  frame: controller.frame,
                  colors: theme.colorScheme,
                  text: theme.textTheme.labelSmall ?? const TextStyle(),
                  xFor: (f) => _x(f, width),
                ),
              ),
            );
          }),
        ),
      ]),
    );
  }

  void _finish() {
    if (_moving != null) controller.endInteraction();
    _moving = null;
  }
}

/// _MouthPainter draws a block for each mouth, its letter on it, the rests
/// faint.
class _MouthPainter extends CustomPainter {
  final List<({int frame, MouthShape shape})> keys;
  final int last;
  final MouthShape current;
  final int frame;
  final ColorScheme colors;
  final TextStyle text;
  final double Function(num) xFor;

  _MouthPainter(
      {required this.keys,
      required this.last,
      required this.current,
      required this.frame,
      required this.colors,
      required this.text,
      required this.xFor});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    for (var (i, k) in keys.indexed) {
      var end = i + 1 < keys.length ? keys[i + 1].frame : last;
      var from = xFor(k.frame), to = xFor(end);
      if (to < 0 || from > size.width) continue;
      var rest = k.shape == MouthShape.rest;
      var on = frame >= k.frame && frame < end;
      var box = Rect.fromLTRB(from + 0.5, 3, math.max(from + 2, to - 0.5),
          size.height - 3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(3)),
        Paint()
          ..color = (rest ? colors.onSurfaceVariant : colors.primary)
              .withValues(alpha: rest ? 0.12 : (on ? 0.6 : 0.32)),
      );
      if (box.width >= 9 && !rest) {
        var painter = TextPainter(
          text: TextSpan(
              text: k.shape.letter,
              style: text.copyWith(
                  color: colors.onSurface, fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(
            canvas,
            Offset(box.left + 3,
                box.center.dy - painter.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_MouthPainter old) =>
      !identical(old.keys, keys) ||
      old.frame != frame ||
      old.current != current ||
      old.last != last ||
      old.colors != colors ||
      old.xFor != xFor;
}

/// motionLaneHeight is one layer's lane.
const double motionLaneHeight = 20;

/// motionLanesFor is the character whose motion clips have lanes -- the one
/// element selected, a character with clips -- or null.
CharacterElement? motionLanesFor(CanvasController controller) {
  if (controller.selection.length != 1) return null;
  var e = controller.selected;
  if (e is! CharacterElement || e.motions.isEmpty) return null;
  return e;
}

/// CharacterMotionLanes is a character's motion clips on the timeline: a
/// lane for each layer in use, a bar for each clip. Dragging a bar moves
/// the clip; dragging its right end makes it longer or shorter.
class CharacterMotionLanes extends StatefulWidget {
  final CanvasController controller;
  final TimelineView view;

  const CharacterMotionLanes(
      {required this.controller, required this.view, super.key});

  @override
  State<CharacterMotionLanes> createState() => _CharacterMotionLanesState();
}

class _CharacterMotionLanesState extends State<CharacterMotionLanes> {
  CanvasController get controller => widget.controller;

  /// _clip is the clip being dragged, _end whether by its end, and _grab
  /// where on it it was taken, in frames from its start.
  String? _clip;
  bool _end = false;
  int _grab = 0;

  double _x(num frame, double width) => widget.view.xOf(frame, width);
  int _frame(double x, double width) =>
      widget.view.frameAt(x, width, controller.document.frames);

  List<MotionLayer> _layers(CharacterElement e) => [
        for (var l in MotionLayer.values)
          if (e.motions.any((m) => m.layer == l)) l,
      ];

  (MotionClip, bool)? _hit(CharacterElement e, Offset at, double width) {
    var layers = _layers(e);
    var row = at.dy ~/ motionLaneHeight;
    if (row < 0 || row >= layers.length) return null;
    for (var m in e.motions.reversed) {
      if (m.layer != layers[row]) continue;
      var from = _x(m.start, width), to = _x(m.end, width);
      if ((at.dx - to).abs() <= 6) return (m, true);
      if (at.dx >= from && at.dx <= to) return (m, false);
    }
    return null;
  }

  void _drag(CharacterElement e, double x, double width) {
    var clip = e.motions.where((m) => m.id == _clip).firstOrNull;
    if (clip == null) return;
    var f = _frame(x, width);
    var next = _end
        ? clip.copyWith(length: f - clip.start)
        : clip.copyWith(start: math.max(0, f - _grab));
    controller.setMotion(e, next, transient: true);
  }

  @override
  Widget build(BuildContext context) {
    var e = motionLanesFor(controller);
    if (e == null) return const SizedBox.shrink();
    var theme = Theme.of(context);
    var layers = _layers(e);
    var height = layers.length * motionLaneHeight;
    return SizedBox(
      key: const ValueKey("characterMotionLanes"),
      height: height,
      child: Row(children: [
        SizedBox(
          width: controller.headerWidth,
          child: Column(children: [
            for (var l in layers)
              SizedBox(
                height: motionLaneHeight,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(l.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ),
                ),
              ),
          ]),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            var width = constraints.maxWidth;
            return GestureDetector(
              supportedDevices: timelinePointers,
              behavior: HitTestBehavior.opaque,
              onHorizontalDragDown: (d) {
                var hit = _hit(e, d.localPosition, width);
                _clip = hit?.$1.id;
                _end = hit?.$2 ?? false;
                _grab = hit == null
                    ? 0
                    : _frame(d.localPosition.dx, width) - hit.$1.start;
              },
              onHorizontalDragStart: (_) {
                if (_clip == null) return;
                controller.pause();
                controller.beginInteraction();
              },
              onHorizontalDragUpdate: (d) {
                var now = motionLanesFor(controller);
                if (now != null) _drag(now, d.localPosition.dx, width);
              },
              onHorizontalDragEnd: (_) => _finish(),
              onHorizontalDragCancel: _finish,
              child: CustomPaint(
                size: Size(width, height),
                painter: _ClipPainter(
                  clips: e.motions,
                  layers: layers,
                  colors: theme.colorScheme,
                  text: theme.textTheme.labelSmall ?? const TextStyle(),
                  xFor: (f) => _x(f, width),
                ),
              ),
            );
          }),
        ),
      ]),
    );
  }

  void _finish() {
    if (_clip != null) controller.endInteraction();
    _clip = null;
  }
}

/// _ClipPainter draws each clip as a named bar on its layer's lane, its
/// blends in and out shaded at the ends.
class _ClipPainter extends CustomPainter {
  final List<MotionClip> clips;
  final List<MotionLayer> layers;
  final ColorScheme colors;
  final TextStyle text;
  final double Function(num) xFor;

  _ClipPainter(
      {required this.clips,
      required this.layers,
      required this.colors,
      required this.text,
      required this.xFor});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    for (var m in clips) {
      var row = layers.indexOf(m.layer);
      var top = row * motionLaneHeight + 2;
      var box = Rect.fromLTRB(xFor(m.start), top, xFor(m.end),
          top + motionLaneHeight - 4);
      if (box.right < 0 || box.left > size.width) continue;
      var bar = RRect.fromRectAndRadius(box, const Radius.circular(4));
      canvas.drawRRect(
          bar, Paint()..color = colors.primary.withValues(alpha: 0.35));
      canvas.drawRRect(
          bar,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = colors.primary.withValues(alpha: 0.8));
      var painter = TextPainter(
        text: TextSpan(
            text: m.kind.label,
            style: text.copyWith(
                color: colors.onSurface, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: "…",
      )..layout(maxWidth: math.max(0.0, box.width - 8));
      painter.paint(
          canvas, Offset(box.left + 4, box.center.dy - painter.height / 2));
    }
  }

  @override
  bool shouldRepaint(_ClipPainter old) =>
      !identical(old.clips, clips) ||
      old.colors != colors ||
      old.xFor != xFor;
}
