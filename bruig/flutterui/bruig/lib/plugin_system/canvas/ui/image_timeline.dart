import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_view.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:flutter/material.dart';

// image_timeline.dart is a picture's layers on the timeline, as a drawing's
// shapes are -- see vector_timeline.dart: a lane for each, bottom layer
// first, under the picture's own keyframes, with a bar from where it starts
// coming in to where it has. Shown as the keyframe row's toggle says (none,
// the layer picked, every layer), and scrolled with the channels. Dragging
// an end or a bar retimes that layer; see layerTimes and retimeLayers.

/// imageLaneHeight is one layer's lane.
const double imageLaneHeight = 18;

/// imageLanesFor is the picture whose layers can have lanes on the timeline
/// -- the one element selected, a picture of layers with an arrival -- or
/// null. Not only once the layers come in one after another: dragging a
/// lane is one way to start them doing so.
ImageElement? imageLanesFor(CanvasController controller) {
  var e = controller.selected;
  if (e is! ImageElement || !e.layered || !e.animation.on) return null;
  if (imageArrivalSpan(e) == null) return null;
  return e;
}

/// imageLanesLabel is what the lanes toggle says it will show next.
String imageLanesLabel(VectorLanes next) => switch (next) {
      VectorLanes.none => "Picture only",
      VectorLanes.picked => "Layer picked",
      VectorLanes.all => "Every layer",
    };

/// _picked is the index of the layer picked, or -1.
int _picked(CanvasController controller, ImageElement e) =>
    controller.imageEditing == e.id
        ? e.stack.indexWhere((l) => l.id == controller.imageLayer)
        : -1;

/// imageLanesShown is which layers have a lane now.
List<int> imageLanesShown(CanvasController controller, ImageElement e) =>
    switch (controller.vectorLanes) {
      VectorLanes.none => const [],
      VectorLanes.all => [for (var i = 0; i < e.stack.length; i++) i],
      VectorLanes.picked => [
          if (_picked(controller, e) case var i when i >= 0) i,
        ],
    };

/// ImageLayerLanes is the lanes, at the top of the channels, on the same
/// scale as the keyframe strip.
class ImageLayerLanes extends StatefulWidget {
  final CanvasController controller;
  final TimelineView view;

  const ImageLayerLanes(
      {required this.controller, required this.view, super.key});

  @override
  State<ImageLayerLanes> createState() => _ImageLayerLanesState();
}

enum _Grip { start, end, bar }

class _ImageLayerLanesState extends State<ImageLayerLanes> {
  CanvasController get controller => widget.controller;

  int? _index;
  _Grip? _grip;
  int _offset = 0;
  int _was = 0;

  double _x(num frame, double width) => widget.view.xOf(frame, width);
  int _frame(double x, double width) =>
      widget.view.frameAt(x, width, controller.document.frames);

  (int, _Grip?)? _hit(
      ImageElement e, List<int> shown, Offset local, double width) {
    var row = local.dy ~/ imageLaneHeight;
    if (row < 0 || row >= shown.length) return null;
    var index = shown[row];
    var (at, span) = imageArrivalSpan(e)!;
    var (start, length) = layerTimes(e.stack, span)[index];
    var from = _x(at + start, width), to = _x(at + start + length, width);
    const reach = 7.0;
    if ((local.dx - to).abs() <= reach) return (index, _Grip.end);
    if ((local.dx - from).abs() <= reach) return (index, _Grip.start);
    if (local.dx > from && local.dx < to) return (index, _Grip.bar);
    return (index, null);
  }

  void _drag(ImageElement e, double x, double width) {
    var index = _index, grip = _grip;
    if (index == null || grip == null) return;
    var (at, span) = imageArrivalSpan(e)!;
    var f = _frame(x, width);
    if (index == 0 && grip != _Grip.end) {
      // The bottom layer starts as the picture's arrival does: moving it
      // moves the arrival, and every layer after it with it.
      var delta = f - (grip == _Grip.bar ? _offset : 0) - _was;
      if (delta == 0) return;
      controller.shiftKeyframes(e.id, [at, at + span], delta);
      _was += delta;
      return;
    }
    var baked = withLayerTimingBaked(e);
    var (start, _) = layerNaturalTimes(baked.stack, span)[index];
    controller.retimeLayers(
        e,
        (b) => switch (grip) {
              _Grip.end => withLayerLength(b, index, f - at - start.round()),
              _ => withLayerStartAt(b, index, f - _offset - at, span),
            },
        transient: true);
  }

  void _pick(ImageElement e, int index) {
    var id = e.stack[index].id;
    if (controller.imageEditing == e.id) {
      controller.pickImageLayer(id);
    } else {
      controller.editImage(e.id, layer: id);
    }
  }

  @override
  Widget build(BuildContext context) {
    var e = imageLanesFor(controller);
    if (e == null) return const SizedBox.shrink();
    var shown = imageLanesShown(controller, e);
    if (shown.isEmpty) return const SizedBox.shrink();
    var theme = Theme.of(context);
    var picked = _picked(controller, e);
    var height = shown.length * imageLaneHeight;
    return SizedBox(
      key: const ValueKey("imageLayerLanes"),
      height: height,
      child: Row(children: [
        SizedBox(
          width: controller.headerWidth,
          child: Column(children: [
            for (var i in shown)
              SizedBox(
                height: imageLaneHeight,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(layerName(e.stack[i], i),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: i == picked
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant)),
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
              // A click picks the layer -- the same as its row in the list.
              onTapDown: (d) {
                if (_hit(e, shown, d.localPosition, width) case (var i, _)) {
                  _pick(e, i);
                }
              },
              onHorizontalDragDown: (d) {
                var hit = _hit(e, shown, d.localPosition, width);
                _index = hit?.$1;
                _grip = hit?.$2;
                if (hit == null || hit.$2 == null) return;
                var (at, span) = imageArrivalSpan(e)!;
                var (start, _) = layerTimes(e.stack, span)[hit.$1];
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
                if (_index case var i?) _pick(e, i);
              },
              onHorizontalDragUpdate: (d) {
                var now = imageLanesFor(controller);
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
          }),
        ),
      ]),
    );
  }

  void _finish() {
    if (_grip != null) controller.endInteraction();
    _index = null;
    _grip = null;
  }
}

class _LanesPainter extends CustomPainter {
  final ImageElement element;
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
    var (at, span) = imageArrivalSpan(element)!;
    var times = layerTimes(element.stack, span);
    for (var (row, i) in shown.indexed) {
      var (start, length) = times[i];
      var y = row * imageLaneHeight + imageLaneHeight / 2;
      var lit = i == picked;
      var ink = lit ? colors.primary : colors.onSurfaceVariant;
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
