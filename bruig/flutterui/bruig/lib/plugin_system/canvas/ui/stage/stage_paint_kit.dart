import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';

// stage_paint_kit.dart is the stage's drawing kit: the blue of its marks
// and the small pieces they are drawn from (a square handle, a round knob,
// a dashed line, a line dark under light, a rectangle or a line put on
// screen), each said once so every mark draws them alike. Stage pixels:
// [scale] pixels to a document unit, the document's top-left at [origin].

/// stageBlue is the blue of the stage's handles, boxes and marks. A
/// picture's layers are marked in defaultHandleColor (vector_element.dart),
/// a blue of their own.
const Color stageBlue = Color(0xFF3D7EFF);

/// darkUnderLight is the pair of strokes a mark over a picture is drawn
/// with, the dark one first and the light one over it, so it shows on
/// anything: each its width and colour.
const List<(double, Color)> darkUnderLight = [
  (3.0, Color(0xAA000000)),
  (1.2, Color(0xFFFFFFFF)),
];

/// onScreen is [r], in document units, on screen.
Rect onScreen(Rect r, double scale, Offset origin) =>
    Rect.fromPoints(r.topLeft * scale + origin, r.bottomRight * scale + origin);

/// lineOnScreen is a path through [points], in document units, on screen.
Path lineOnScreen(List<Offset> points, double scale, Offset origin) {
  var path = Path()
    ..moveTo(points.first.dx * scale + origin.dx,
        points.first.dy * scale + origin.dy);
  for (var p in points.skip(1)) {
    path.lineTo(p.dx * scale + origin.dx, p.dy * scale + origin.dy);
  }
  return path;
}

/// saveInDocument saves [canvas] and draws on it in document units until
/// it is restored.
void saveInDocument(Canvas canvas, double scale, Offset origin) {
  canvas.save();
  canvas.translate(origin.dx, origin.dy);
  canvas.scale(scale);
}

/// drawDashedLine draws from [from] to [to] in dashes [dash] long with
/// [gap] between, starting with a dash at [from].
void drawDashedLine(Canvas canvas, Offset from, Offset to, Paint paint,
    {required double dash, required double gap}) {
  var length = (to - from).distance;
  if (length <= 0) return;
  var step = (to - from) / length;
  for (var at = 0.0; at < length; at += dash + gap) {
    canvas.drawLine(
        from + step * at, from + step * math.min(at + dash, length), paint);
  }
}

/// drawDarkUnderLight calls [draw] once for each of [strokes] in turn,
/// with a stroke paint of that width and colour, joined by [join] when
/// given.
void drawDarkUnderLight(void Function(Paint paint) draw,
    {List<(double, Color)> strokes = darkUnderLight, StrokeJoin? join}) {
  for (var (width, colour) in strokes) {
    var paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = colour;
    if (join != null) paint.strokeJoin = join;
    draw(paint);
  }
}

/// drawSquareHandle draws a square handle [size] across at [at]: filled
/// with [fill], edged with [edge] [width] wide.
void drawSquareHandle(Canvas canvas, Offset at,
    {double size = handleSize,
    Color fill = const Color(0xFFFFFFFF),
    Color edge = stageBlue,
    double width = 1.5}) {
  var square = Rect.fromCenter(center: at, width: size, height: size);
  canvas.drawRect(square, Paint()..color = fill);
  canvas.drawRect(
      square,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = edge);
}

/// drawRoundKnob draws a round knob of [radius] at [at]: filled with
/// [fill], ringed with [edge] [width] wide.
void drawRoundKnob(Canvas canvas, Offset at, double radius,
    {Color fill = const Color(0xFFFFFFFF),
    Color edge = stageBlue,
    double width = 1.5}) {
  canvas.drawCircle(at, radius, Paint()..color = fill);
  canvas.drawCircle(
      at,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = edge);
}
