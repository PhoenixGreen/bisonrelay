part of 'paint_util.dart';

// A stroke along a curve, as a line and a path are both drawn: its body
// with its cap, dash and fade, cut back under each end, and what is drawn
// on each end at its size. Part of paint_util.dart.

/// paintStroke draws [stroke] along [along], a single curve: a line's or a
/// path's.
void paintStroke(ui.Canvas canvas, Path along, StrokeSpec stroke) {
  // Across the stroke as drawn, the curve's bounds grown by half its width,
  // so a fade runs end to end whichever way it points, and across the
  // thickness of a level or upright stroke, whose curve has no height or
  // no width to lay it over.
  var paint = PaintSpec(stroke.color, gradient: stroke.fade).into(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = stroke.cap.flutter,
      along.getBounds().inflate(stroke.strokeWidth / 2));

  // A path metric gives the exact position and direction at each end, so the
  // ends sit square on a curve.
  var metric = _strokeMetric(along);
  if (metric == null) return;
  var length = metric.length;

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
      stroke.dash > 0 ? _dashPath(body, stroke.dash, stroke.dash * 0.8) : body,
      paint);

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
  for (var mark in _marksOn(metric, stroke)) {
    _paintEnd(canvas, mark, fill, outline);
  }
}

/// _strokeMetric is [along]'s first contour measured, with a direction at
/// each end; null where it has none (no curve, or one of no length).
ui.PathMetric? _strokeMetric(Path along) {
  var metrics = along.computeMetrics().iterator;
  if (!metrics.moveNext()) return null;
  var metric = metrics.current;
  if (metric.getTangentForOffset(0) == null ||
      metric.getTangentForOffset(metric.length) == null) {
    return null;
  }
  return metric;
}

/// strokeEndMarks is what [stroke] draws on each end of [along], where it
/// is drawn in the curve's own space: what the stage presses, so a large
/// end is taken wherever its ink is.
List<EndMark> strokeEndMarks(Path along, StrokeSpec stroke) {
  if (stroke.startEnd == LineEnd.none && stroke.endEnd == LineEnd.none) {
    return const [];
  }
  var metric = _strokeMetric(along);
  return metric == null ? const [] : _marksOn(metric, stroke);
}

List<EndMark> _marksOn(ui.PathMetric metric, StrokeSpec stroke) {
  // From the vector, never Tangent.angle: that is *minus* atan2(dy, dx), y
  // up, and flips every end on a diagonal in canvas space.
  double heading(ui.Tangent t) => math.atan2(t.vector.dy, t.vector.dx);
  var startTangent = metric.getTangentForOffset(0)!;
  var endTangent = metric.getTangentForOffset(metric.length)!;
  var w = stroke.strokeWidth * stroke.endSize;
  return [
    // The start's end points back out of the stroke: the curve reversed.
    if (EndMark.of(stroke.startEnd, startTangent.position,
            heading(startTangent) + math.pi, w)
        case var mark?)
      mark,
    if (EndMark.of(stroke.endEnd, endTangent.position, heading(endTangent), w)
        case var mark?)
      mark,
  ];
}

/// EndMark is one end's mark where it is drawn: on [at], heading along
/// [angle] (the stroke's direction there, from the path metric, so it sits
/// square however bent the curve), [w] its end width (EndShape). Its
/// outline is [corners], closed but for a bar's two ends, or a circle of
/// [radius] about [at]. A [solid] one is filled; the rest are drawn as an
/// edge the stroke's width.
class EndMark {
  final LineEnd end;
  final Offset at;
  final double angle;
  final double w;
  final List<Offset> corners;
  final double radius;

  EndMark._(this.end, this.at, this.angle, this.w, this.corners,
      {this.radius = 0});

  /// of is [end]'s mark on [at] heading along [angle], [w] wide; null for
  /// no end.
  static EndMark? of(LineEnd end, Offset at, double angle, double w) {
    var along = Offset(math.cos(angle), math.sin(angle));
    var across = Offset(-along.dy, along.dx);
    var back = angle + math.pi;
    Offset barb(double length, double side) => at.translate(
        math.cos(back + side * EndShape.arrowSpread) * length,
        math.sin(back + side * EndShape.arrowSpread) * length);
    EndMark mark(List<Offset> corners, {double radius = 0}) =>
        EndMark._(end, at, angle, w, corners, radius: radius);

    switch (end) {
      case LineEnd.none:
        return null;
      case LineEnd.arrow:
      case LineEnd.hollowArrow:
        var length = w * EndShape.arrowBarb;
        return mark([at, barb(length, -1), barb(length, 1)]);
      case LineEnd.openArrow:
        // A filled chevron rather than two strokes: thickest at the tip and
        // pointed at each outer end, as an open arrow is drawn by hand. The
        // notch behind the tip gives it its thickness.
        var length = w * EndShape.openArrowBarb;
        var notch = at - along * (length * EndShape.openArrowNotch);
        return mark([at, barb(length, -1), notch, barb(length, 1)]);
      case LineEnd.diamond:
      case LineEnd.hollowDiamond:
        // Centred on the end, like the circle and the square.
        var long = along * (w * EndShape.diamondLength);
        var wide = across * (w * EndShape.diamondWidth);
        return mark([
          Offset(at.dx + long.dx, at.dy + long.dy),
          Offset(at.dx + wide.dx, at.dy + wide.dy),
          Offset(at.dx - long.dx, at.dy - long.dy),
          Offset(at.dx - wide.dx, at.dy - wide.dy),
        ]);
      case LineEnd.circle:
      case LineEnd.hollowCircle:
        return mark(const [], radius: w * EndShape.circleRadius);
      case LineEnd.square:
        var half = w * EndShape.squareSide / 2;
        return mark([
          for (var (a, b) in const [(1, 1), (-1, 1), (-1, -1), (1, -1)])
            at + along * (half * a) + across * (half * b),
        ]);
      case LineEnd.bar:
        // A tick across the stroke, which is what a measurement wants at
        // each end.
        return mark([
          at - across * (w * EndShape.barReach),
          at + across * (w * EndShape.barReach),
        ]);
    }
  }

  /// solid is whether it is filled, not drawn as an edge.
  bool get solid => switch (end) {
        LineEnd.arrow ||
        LineEnd.openArrow ||
        LineEnd.diamond ||
        LineEnd.circle ||
        LineEnd.square =>
          true,
        LineEnd.none ||
        LineEnd.hollowArrow ||
        LineEnd.hollowDiamond ||
        LineEnd.hollowCircle ||
        LineEnd.bar =>
          false,
      };

  /// outline is [corners] as a path, closed but for a bar.
  Path get outline {
    var path = Path()..moveTo(corners.first.dx, corners.first.dy);
    for (var c in corners.skip(1)) {
      path.lineTo(c.dx, c.dy);
    }
    return end == LineEnd.bar ? path : (path..close());
  }
}

/// _paintEnd draws one end's [mark]: a solid one in [fill], a hollow one or
/// a bar in [outline].
void _paintEnd(ui.Canvas canvas, EndMark mark, Paint fill, Paint outline) {
  var paint = mark.solid ? fill : outline;
  switch (mark.end) {
    case LineEnd.none:
      return;
    case LineEnd.circle:
    case LineEnd.hollowCircle:
      canvas.drawCircle(mark.at, mark.radius, paint);
    case LineEnd.square:
      // Turned onto the stroke and drawn as a rectangle, which lands on the
      // pixels as its outline's corners say.
      canvas.save();
      canvas.translate(mark.at.dx, mark.at.dy);
      canvas.rotate(mark.angle);
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset.zero,
              width: mark.w * EndShape.squareSide,
              height: mark.w * EndShape.squareSide),
          paint);
      canvas.restore();
    case LineEnd.bar:
      canvas.drawLine(mark.corners.first, mark.corners.last, paint);
    case LineEnd.arrow:
    case LineEnd.hollowArrow:
    case LineEnd.openArrow:
    case LineEnd.diamond:
    case LineEnd.hollowDiamond:
      canvas.drawPath(mark.outline, paint);
  }
}
