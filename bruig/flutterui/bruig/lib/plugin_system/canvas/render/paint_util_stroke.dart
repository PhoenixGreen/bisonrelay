part of 'paint_util.dart';

// A stroke along a curve, as a line and a path are both drawn: its body
// with its cap, dash and fade, cut back under each end, and what is drawn
// on each end at its size. Part of paint_util.dart.

/// paintStroke draws [stroke] along [along], a single curve: a line's or a
/// path's.
void paintStroke(ui.Canvas canvas, Path along, StrokeSpec stroke) {
  // Across the whole curve, so a fade runs end to end whichever way it
  // points.
  var paint = PaintSpec(stroke.color, gradient: stroke.fade).into(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = stroke.cap.flutter,
      along.getBounds());

  // A path metric gives the exact position and direction at each end, so the
  // ends sit square on a curve.
  var metrics = along.computeMetrics().toList();
  if (metrics.isEmpty) return;
  var metric = metrics.first;
  var length = metric.length;

  var startTangent = metric.getTangentForOffset(0);
  var endTangent = metric.getTangentForOffset(length);
  if (startTangent == null || endTangent == null) return;

  // An end is drawn on the stroke's end, so the stroke stops where the
  // end's ink begins (StrokeSpec.cutBack): no gap before it, and nothing
  // showing through a hollow one. Cut nowhere, it is the curve itself, so a
  // closed one joins where it closes.
  var startCut = stroke.cutBack(stroke.startEnd);
  var endCut = stroke.cutBack(stroke.endEnd);
  var body = along;
  if (startCut > 0 || endCut > 0) {
    var from = math.min(startCut, length * 0.45);
    var to = math.max(length - endCut, from + 0.01);
    body = metric.extractPath(from, to);
  }

  canvas.drawPath(
      stroke.dash > 0 ? dashPath(body, stroke.dash, stroke.dash * 0.8) : body,
      paint);

  // From the vector, never Tangent.angle: that is *minus* atan2(dy, dx), y
  // up, and flips every end on a diagonal in canvas space.
  double heading(ui.Tangent t) => math.atan2(t.vector.dy, t.vector.dx);

  // The ends in the stroke's own paint, its fade laid over the same curve,
  // so each is the colour the stroke has where it is.
  var fill = Paint()
    ..style = PaintingStyle.fill
    ..color = paint.color
    ..shader = paint.shader;
  var outline = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke.strokeWidth
    ..strokeJoin = StrokeJoin.miter
    ..color = paint.color
    ..shader = paint.shader;
  var w = stroke.strokeWidth * stroke.endSize;

  // The start's end points back out of the stroke: the curve reversed.
  _paintEnd(canvas, stroke.startEnd, startTangent.position,
      heading(startTangent) + math.pi, w, fill, outline);
  _paintEnd(canvas, stroke.endEnd, endTangent.position, heading(endTangent), w,
      fill, outline);
}

/// _paintEnd draws one end along [angle], the stroke's direction at that
/// end from the path metric, so it sits square however bent the curve. [w]
/// is its end width (EndShape); a solid end is drawn in [fill], a hollow one
/// or a bar in [outline].
void _paintEnd(ui.Canvas canvas, LineEnd end, Offset at, double angle, double w,
    Paint fill, Paint outline) {
  if (end == LineEnd.none) return;

  var along = Offset(math.cos(angle), math.sin(angle));
  var across = Offset(-along.dy, along.dx);
  var back = angle + math.pi;
  Offset barb(double length, double side) => at.translate(
      math.cos(back + side * EndShape.arrowSpread) * length,
      math.sin(back + side * EndShape.arrowSpread) * length);

  switch (end) {
    case LineEnd.none:
      return;
    case LineEnd.arrow:
    case LineEnd.hollowArrow:
      var length = w * EndShape.arrowBarb;
      var b1 = barb(length, -1), b2 = barb(length, 1);
      canvas.drawPath(
          Path()
            ..moveTo(at.dx, at.dy)
            ..lineTo(b1.dx, b1.dy)
            ..lineTo(b2.dx, b2.dy)
            ..close(),
          end == LineEnd.arrow ? fill : outline);
    case LineEnd.openArrow:
      // A filled chevron rather than two strokes: thickest at the tip and
      // pointed at each outer end, as an open arrow is drawn by hand.
      var length = w * EndShape.openArrowBarb;
      var b1 = barb(length, -1), b2 = barb(length, 1);
      // The notch behind the tip gives it its thickness.
      var notch = at - along * (length * EndShape.openArrowNotch);
      canvas.drawPath(
        Path()
          ..moveTo(at.dx, at.dy)
          ..lineTo(b1.dx, b1.dy)
          ..lineTo(notch.dx, notch.dy)
          ..lineTo(b2.dx, b2.dy)
          ..close(),
        fill,
      );
    case LineEnd.diamond:
    case LineEnd.hollowDiamond:
      // Centred on the end, like the circle and the square.
      var long = along * (w * EndShape.diamondLength);
      var wide = across * (w * EndShape.diamondWidth);
      canvas.drawPath(
        Path()
          ..moveTo(at.dx + long.dx, at.dy + long.dy)
          ..lineTo(at.dx + wide.dx, at.dy + wide.dy)
          ..lineTo(at.dx - long.dx, at.dy - long.dy)
          ..lineTo(at.dx - wide.dx, at.dy - wide.dy)
          ..close(),
        end == LineEnd.diamond ? fill : outline,
      );
    case LineEnd.circle:
      canvas.drawCircle(at, w * EndShape.circleRadius, fill);
    case LineEnd.hollowCircle:
      canvas.drawCircle(at, w * EndShape.circleRadius, outline);
    case LineEnd.square:
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(angle);
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset.zero,
              width: w * EndShape.squareSide,
              height: w * EndShape.squareSide),
          fill);
      canvas.restore();
    case LineEnd.bar:
      // A tick across the stroke, which is what a measurement wants at each
      // end.
      canvas.drawLine(at - across * (w * EndShape.barReach),
          at + across * (w * EndShape.barReach), outline);
  }
}
