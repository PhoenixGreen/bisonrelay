import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/render/vector_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_view.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:flutter/material.dart';

// vector_timeline.dart is a drawing's shapes on the timeline: a lane for
// each, under the drawing's own keyframes, with a bar from where it starts
// coming in to where it has, and a diamond at each end. Shown as the
// keyframe row's toggle says -- none, the shape picked, every shape -- and
// scrolled with the channels, never holding the timeline open. Dragging an
// end or a bar retimes that shape; see VectorCue and retimeShapes.

/// vectorLaneHeight is one shape's lane.
const double vectorLaneHeight = 18;

/// vectorLanesFor is the drawing whose shapes can have lanes on the
/// timeline -- the one element selected, a drawing with shapes and an
/// arrival -- or null.
VectorElement? vectorLanesFor(CanvasController controller) {
  var e = controller.selected;
  if (e is! VectorElement || !e.edited || !e.animation.on) return null;
  if ((e.shapes ?? const []).isEmpty) return null;
  if (vectorArrivalSpan(e) == null) return null;
  return e;
}

/// vectorLanesShown is which of the drawing's groups have a lane now: none,
/// the one picked, or all of them, as the toggle says.
List<int> vectorLanesShown(CanvasController controller, VectorElement e) {
  var count = vectorDrawn(e.shapes!).length;
  return switch (controller.vectorLanes) {
    VectorLanes.none => const [],
    VectorLanes.all => [for (var i = 0; i < count; i++) i],
    VectorLanes.picked => [
        if (_pickedGroup(controller, e) case var g when g >= 0) g,
      ],
  };
}

/// _pickedGroup is the group of the shape picked, or -1.
int _pickedGroup(CanvasController controller, VectorElement e) =>
    controller.vectorShape < 0
        ? -1
        : groupStarts(e).indexOf(groupOf(e, controller.vectorShape));

/// VectorShapeLanes is the lanes, at the top of the channels, on the same
/// scale as the keyframe strip.
class VectorShapeLanes extends StatefulWidget {
  final CanvasController controller;
  final TimelineView view;

  const VectorShapeLanes(
      {required this.controller, required this.view, super.key});

  @override
  State<VectorShapeLanes> createState() => _VectorShapeLanesState();
}

/// _Grip is what a press on a lane took hold of.
enum _Grip { start, end, bar }

class _VectorShapeLanesState extends State<VectorShapeLanes> {
  CanvasController get controller => widget.controller;

  /// _group and _grip are what the drag in hand is moving; _offset where on
  /// the bar it was taken, in frames from its start; _was the frame the
  /// first shape's bar was at when the drag last moved it.
  int? _group;
  _Grip? _grip;
  int _offset = 0;
  int _was = 0;

  double _x(num frame, double width) => widget.view.xOf(frame, width);
  int _frame(double x, double width) =>
      widget.view.frameAt(x, width, controller.document.frames);

  /// _hit is the group, and the part of its bar, under [local], on the
  /// lanes [shown].
  (int, _Grip?)? _hit(
      VectorElement e, List<int> shown, Offset local, double width) {
    var row = local.dy ~/ vectorLaneHeight;
    if (row < 0 || row >= shown.length) return null;
    var group = shown[row];
    var (at, span) = vectorArrivalSpan(e)!;
    var (start, length) = cueTimes(e.shapes!, span)[group];
    var from = _x(at + start, width), to = _x(at + start + length, width);
    const reach = 7.0;
    if ((local.dx - to).abs() <= reach) return (group, _Grip.end);
    if ((local.dx - from).abs() <= reach) return (group, _Grip.start);
    if (local.dx > from && local.dx < to) return (group, _Grip.bar);
    return (group, null);
  }

  void _drag(VectorElement e, double x, double width) {
    var group = _group, grip = _grip;
    if (group == null || grip == null) return;
    var (at, span) = vectorArrivalSpan(e)!;
    var f = _frame(x, width);
    if (group == 0 && grip != _Grip.end) {
      // The first shape starts as the drawing's arrival does: moving it
      // moves the arrival, and every shape after it with it.
      var delta = f - (grip == _Grip.bar ? _offset : 0) - _was;
      if (delta == 0) return;
      controller.shiftKeyframes(e.id, [at, at + span], delta);
      _was += delta;
      return;
    }
    // In the timeline's own frames: the shapes' timing written out as it
    // plays first, as retimeShapes does, so the drag lands where it shows.
    var baked = withTimingBaked(e);
    var (start, _) = naturalTimes(baked.shapes!, span)[group];
    controller.retimeShapes(
        e,
        (b) => switch (grip) {
              _Grip.end => withCueLength(b, group, f - at - start.round()),
              _ => withStartAt(b, group, f - _offset - at, span),
            },
        transient: true);
  }

  @override
  Widget build(BuildContext context) {
    var e = vectorLanesFor(controller);
    if (e == null) return const SizedBox.shrink();
    var shown = vectorLanesShown(controller, e);
    if (shown.isEmpty) return const SizedBox.shrink();
    var theme = Theme.of(context);
    var picked = _pickedGroup(controller, e);
    var height = shown.length * vectorLaneHeight;
    return SizedBox(
      key: const ValueKey("vectorShapeLanes"),
      height: height,
      child: Row(children: [
        SizedBox(
          width: controller.headerWidth,
          child: Column(children: [
            for (var g in shown)
              SizedBox(
                height: vectorLaneHeight,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text("Shape ${g + 1}",
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: g == picked
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant)),
                  ),
                ),
              ),
          ]),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              var width = constraints.maxWidth;
              return GestureDetector(
                supportedDevices: timelinePointers,
                behavior: HitTestBehavior.opaque,
                // A click picks the shape -- the same as its playlist row.
                onTapDown: (d) {
                  if (_hit(e, shown, d.localPosition, width)
                      case (var group, _)) {
                    controller.pickVectorShape(groupStarts(e)[group]);
                  }
                },
                onHorizontalDragDown: (d) {
                  var hit = _hit(e, shown, d.localPosition, width);
                  _group = hit?.$1;
                  _grip = hit?.$2;
                  if (hit == null || hit.$2 == null) return;
                  var (at, span) = vectorArrivalSpan(e)!;
                  var (start, _) = cueTimes(e.shapes!, span)[hit.$1];
                  var begins = at + start.round();
                  _offset = hit.$2 == _Grip.bar
                      ? _frame(d.localPosition.dx, width) - begins
                      : 0;
                  _was = begins;
                },
                onHorizontalDragStart: (_) {
                  if (_grip == null) return;
                  controller.pause();
                  controller.beginInteraction();
                  if (_group case var group?) {
                    controller.pickVectorShape(groupStarts(e)[group]);
                  }
                },
                onHorizontalDragUpdate: (d) {
                  var now = vectorLanesFor(controller);
                  if (now != null) _drag(now, d.localPosition.dx, width);
                },
                onHorizontalDragEnd: (_) => _finish(),
                onHorizontalDragCancel: _finish,
                child: CustomPaint(
                  size: Size(width, height),
                  painter: _LanesPainter(
                    element: e,
                    shown: shown,
                    picked: picked,
                    colors: theme.colorScheme,
                    xFor: (f) => _x(f, width),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  void _finish() {
    if (_grip != null) controller.endInteraction();
    _group = null;
    _grip = null;
  }
}

/// _LanesPainter draws each lane's bar and its two diamonds.
class _LanesPainter extends CustomPainter {
  final VectorElement element;
  final List<int> shown;
  final int picked;
  final ColorScheme colors;
  final double Function(num) xFor;

  _LanesPainter(
      {required this.element,
      required this.shown,
      required this.picked,
      required this.colors,
      required this.xFor});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    var (at, span) = vectorArrivalSpan(element)!;
    var times = cueTimes(element.shapes!, span);
    for (var (row, g) in shown.indexed) {
      var (start, length) = times[g];
      var y = row * vectorLaneHeight + vectorLaneHeight / 2;
      var lit = g == picked;
      var ink = lit ? colors.primary : colors.onSurfaceVariant;
      // A faint line along every lane, so the lanes read as rows.
      canvas.drawLine(
          Offset(0, (row + 1) * vectorLaneHeight - 0.5),
          Offset(size.width, (row + 1) * vectorLaneHeight - 0.5),
          Paint()
            ..color = colors.outline.withValues(alpha: 0.18)
            ..strokeWidth = 1);
      var from = xFor(at + start), to = xFor(at + start + length);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTRB(from, y - 4, to, y + 4), const Radius.circular(4)),
        Paint()..color = ink.withValues(alpha: lit ? 0.35 : 0.18),
      );
      for (var x in [from, to]) {
        canvas.drawPath(
          Path()
            ..moveTo(x, y - 5)
            ..lineTo(x + 5, y)
            ..lineTo(x, y + 5)
            ..lineTo(x - 5, y)
            ..close(),
          Paint()..color = ink.withValues(alpha: lit ? 1 : 0.7),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_LanesPainter old) =>
      !identical(old.element, element) ||
      old.picked != picked ||
      old.shown.length != shown.length ||
      old.colors != colors ||
      old.xFor != xFor;
}
