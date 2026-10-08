import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/painting.dart';

// vector_painter.dart draws a Vector element: the file it came from, exactly,
// until it has been taken apart for editing -- and its shapes after that.

/// _paths remembers each shape's outline. A shape is never changed in place
/// -- an edit makes a new one -- so its outline is worked out once, rather
/// than on every frame for every one of what can be thousands of points.
final Expando<Path> _paths = Expando<Path>();

Path vectorShapePath(VectorShape shape) => _paths[shape] ??= shape.path;

/// paintVector draws [e] fitted into [box].
void paintVector(
    ui.Canvas canvas, Rect box, VectorElement e, CanvasImageSource? images) {
  if (box.width <= 0 || box.height <= 0) return;
  var shapes = e.shapes;
  if (shapes == null) {
    // As the file draws itself, which is the only way to be exact about a
    // drawing nobody has taken apart yet.
    var drawn = images?.resolveVector(e.assetId);
    if (drawn == null) {
      _placeholder(canvas, box);
      return;
    }
    var p = e.placement(box, Offset.zero & drawn.size);
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.scale(p.sx, p.sy);
    canvas.drawPicture(drawn.picture);
    canvas.restore();
    return;
  }

  var p = e.placement(box, e.viewBox);
  canvas.save();
  canvas.translate(p.dx, p.dy);
  canvas.scale(p.sx, p.sy);
  for (var shape in shapes) {
    var path = vectorShapePath(shape);
    if (shape.fill case var fill? when fill.a > 0) {
      canvas.drawPath(
          path,
          Paint()
            ..color = fill
            ..isAntiAlias = true);
    }
    if (shape.stroke case var stroke?
        when stroke.a > 0 && shape.strokeWidth > 0) {
      canvas.drawPath(
          path,
          Paint()
            ..color = stroke
            ..style = PaintingStyle.stroke
            ..strokeWidth = shape.strokeWidth
            ..strokeCap = shape.cap
            ..strokeJoin = shape.join
            ..isAntiAlias = true);
    }
  }
  canvas.restore();
}

/// _placeholder is a Vector element with nothing in it yet: a dashed box
/// with a pen in it, so it can be found, picked and given a drawing.
void _placeholder(ui.Canvas canvas, Rect box) {
  var ink = Paint()
    ..color = const Color(0x99888888)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  var r = RRect.fromRectAndRadius(box.deflate(1), const Radius.circular(6));
  canvas.drawRRect(r, Paint()..color = const Color(0x22888888));
  // Dashed by hand: a path drawn in short pieces round the box.
  var metric = (Path()..addRRect(r)).computeMetrics();
  for (var m in metric) {
    for (var d = 0.0; d < m.length; d += 10) {
      canvas.drawPath(m.extractPath(d, d + 5), ink);
    }
  }
  // A curve and its two handles: what a drawing is made of.
  var c = box.center;
  var s = box.shortestSide * 0.18;
  var curve = Path()
    ..moveTo(c.dx - s, c.dy + s * 0.4)
    ..cubicTo(c.dx - s * 0.4, c.dy - s * 1.2, c.dx + s * 0.4, c.dy + s * 1.2,
        c.dx + s, c.dy - s * 0.4);
  canvas.drawPath(curve, ink..strokeWidth = 2);
  var dot = Paint()..color = const Color(0xCC888888);
  canvas.drawCircle(Offset(c.dx - s, c.dy + s * 0.4), 3, dot);
  canvas.drawCircle(Offset(c.dx + s, c.dy - s * 0.4), 3, dot);
}
