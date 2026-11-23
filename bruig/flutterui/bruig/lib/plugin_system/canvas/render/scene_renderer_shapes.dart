part of 'scene_renderer.dart';

// Shapes, lines, paths and their arrow heads, and the geometry of a drawn line
// or curve (its bow, text riding it, where it is really drawn) that the stage
// hit-tests against. Part of scene_renderer.dart.

/// lineWithPose is [e] with its track's bow on [frame], for the hit test.
LineElement lineWithPose(LineElement e, int frame) =>
    _bowed(e, e.poseAt(frame));

/// _bowed applies a keyed curvature to a line. See KeyframeChannel.bow.
LineElement _bowed(LineElement e, Keyframe pose) {
  var bow = pose.values[KeyframeChannel.bow];
  return bow == null ? e : e.copyWith(curvature: bow);
}

/// visualBoundsOf is where [element] is drawn, which differs from its moved
/// box on a stage, for a bowed line or path, and for text on a line. The
/// selection outline, handles and on-canvas text editor use it.
Rect visualBoundsOf(CanvasElement element, CanvasDocument? doc, int frame,
    {LiveMotion? live}) {
  // With its clips' moves on it: see movedBoundsAt.
  Rect moved() => doc == null
      ? element.boundsAt(frame)
      : element.movedBoundsAt(frame, doc, live: live);
  if (element.base.spot != null && doc != null) {
    if (stagedIn(doc, element, frame) case var at?) return at.box;
  }
  if (element is TextElement) {
    var curve = _curveFor(element, doc, frame);
    if (curve != null) {
      var glyphs = placeTextOnPath(
          element.displayText, element.textSpec, curve, element.curve!,
          parts: element.drawnParts);
      var box = textOnPathBounds(glyphs, element.curve!);
      // No letters placed (empty, or slid off the end): the line itself.
      return box ?? _boundsOfPoints(curve) ?? moved();
    }
    return moved();
  }

  if (element is LineElement || element is PathElement) {
    var host = element is LineElement ? lineWithPose(element, frame) : element;
    var curve = curveOfElement(host);
    var box = _boundsOfPoints(curve);
    if (box == null) return moved();
    // Room for the stroke, centred on the path, and for the ends: an
    // arrowhead reaches 3.5 stroke widths past the end point.
    var width = element is LineElement
        ? element.strokeWidth
        : (element as PathElement).strokeWidth;
    var ends = element is LineElement
        ? math.max(element.startEnd.reach, element.endEnd.reach) *
            element.endSize
        : math.max(
                (element as PathElement).startEnd.reach, element.endEnd.reach) *
            element.endSize;
    return box.inflate(math.max(width, 1) * math.max(ends, 1.5));
  }

  return moved();
}

Rect? _boundsOfPoints(List<Offset>? points) {
  if (points == null || points.isEmpty) return null;
  var left = points.first.dx, right = points.first.dx;
  var top = points.first.dy, bottom = points.first.dy;
  for (var p in points) {
    left = math.min(left, p.dx);
    right = math.max(right, p.dx);
    top = math.min(top, p.dy);
    bottom = math.max(bottom, p.dy);
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

/// hasOwnGeometry is whether an element's size and angle are its own: not
/// for text riding a line, whose place, size and turn are the line's.
bool hasOwnGeometry(CanvasElement element, CanvasDocument? doc, int frame) =>
    !(element is TextElement && _curveFor(element, doc, frame) != null) &&
    // Nor for something standing on a stage: the camera sizes and turns it.
    !(element.base.spot != null &&
        doc != null &&
        stagedIn(doc, element, frame) != null);

/// curveOfElement is [element]'s own line as a polyline in document space,
/// or null; the stage hit-tests against it, as a curve bows out of its box.
List<Offset>? curveOfElement(CanvasElement element) {
  var points = _curvePoints(element);
  if (points == null) return null;
  return _rotatedWith(element, points);
}

/// curveUnderText is the line a text element is riding, in document space.
List<Offset>? curveUnderText(TextElement e, CanvasDocument? doc, int frame) =>
    _curveFor(e, doc, frame);

/// _rotatedWith turns [points] about [host]'s centre, as the painter does.
List<Offset> _rotatedWith(CanvasElement host, List<Offset> points) {
  if (host.rotation == 0) return points;
  var centre = host.center;
  var cos = math.cos(host.rotationRadians);
  var sin = math.sin(host.rotationRadians);
  return [
    for (var p in points)
      Offset(
        centre.dx + (p.dx - centre.dx) * cos - (p.dy - centre.dy) * sin,
        centre.dy + (p.dx - centre.dx) * sin + (p.dy - centre.dy) * cos,
      ),
  ];
}

/// pathPointsOf is [host] -- a path or a line -- as points along it on the
/// page, turned as it is drawn; null for anything else. For Follow path.
List<Offset>? pathPointsOf(CanvasElement host, int frame) {
  var drawn = host is LineElement ? _bowed(host, host.poseAt(frame)) : host;
  var points = _curvePoints(drawn);
  return points == null ? null : _rotatedWith(drawn, points);
}

/// _curveFor is the line text [e] rides, as document-space points, or null.
/// Found by id, so the text follows it; if deleted, the text uses its box.
List<Offset>? _curveFor(TextElement e, CanvasDocument? doc, int frame) {
  var on = e.curve;
  if (on == null || doc == null) return null;
  var host = doc.elementById(on.elementId);
  // The host's animated bow counts (its track only; clips' bows do not).
  if (host is LineElement) host = _bowed(host, host.poseAt(frame));
  var points = _curvePoints(host);
  if (points == null) return null;

  return _rotatedWith(host!, points);
}

/// _curvePoints is the host's line as a polyline, unrotated.
List<Offset>? _curvePoints(CanvasElement? host) {
  if (host is PathElement && host.nodes.length >= 2) {
    return [
      for (var i = 0; i < host.segments; i++)
        for (var step = 0; step <= _curveSamplesPerSegment; step++)
          if (i == 0 || step > 0)
            host.pointOnSegment(i, step / _curveSamplesPerSegment),
    ];
  }
  if (host is LineElement) {
    // A bowed line is a quadratic between its ends, so it is sampled, with
    // the painter's own control point (lineControlPoint).
    var a = host.start, b = host.end;
    if (host.curvature == 0) return [a, b];
    var control = lineControlPoint(host);
    return [
      for (var i = 0; i <= _curveSamplesPerSegment * 2; i++)
        _quadratic(a, control, b, i / (_curveSamplesPerSegment * 2)),
    ];
  }
  return null;
}

/// _curveSamplesPerSegment is how finely a curve is walked when text is placed
/// along it: enough to keep letters on the line at any export size.
const int _curveSamplesPerSegment = 16;

Offset _quadratic(Offset a, Offset control, Offset b, double t) {
  var u = 1 - t;
  return Offset(
    u * u * a.dx + 2 * u * t * control.dx + t * t * b.dx,
    u * u * a.dy + 2 * u * t * control.dy + t * t * b.dy,
  );
}

void _paintShape(ui.Canvas canvas, Rect bounds, ShapeElement e,
    [CanvasImageSource? images]) {
  var rect = bounds;
  if (e.shape.isRegular) {
    var side = rect.shortestSide;
    rect = Rect.fromCenter(center: rect.center, width: side, height: side);
  }

  var path = shapePath(e.shape, rect,
      points: e.points,
      inner: e.innerRatio,
      cornerRadius: e.cornerRadius,
      corners: e.corners,
      bubble: e.bubble);

  // Across the shape's own bounds, so a gradient runs the shape's length.
  var area = path.getBounds();
  // A fade of its own counts as a fill: the flat colour may have been turned
  // all the way down on the way to setting one. See PaintSpec.shows.
  var filled = PaintSpec(e.fill, gradient: e.fillFade);
  if (filled.shows) {
    canvas.drawPath(path, filled.into(Paint(), area));
  }
  // A picture or a pattern inside it, cut to the outline. See TextFill.
  if (e.painted.on) {
    paintThroughText(
        canvas, area, e.painted, images, () => canvas.drawPath(path, Paint()));
  }
  var stroked = PaintSpec(e.strokeColor, gradient: e.strokeFade);
  if (e.strokeWidth > 0 && stroked.shows) {
    canvas.drawPath(
        path,
        stroked.into(
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = e.strokeWidth
              ..strokeJoin = StrokeJoin.round,
            area));
  }

  if (e.text.isNotEmpty) {
    paintTextInBox(canvas, e.textSpec.textCase.apply(e.text), e.textSpec,
        labelRoom(e, rect));
  }
}

/// labelRoom is where a shape's label is set: its padding, or else the
/// shape's own crude inset (not the inscribed rectangle of an arbitrary
/// path), enough to keep a label in a circle or triangle off the edge.
Rect labelRoom(ShapeElement e, Rect rect) {
  // A bubble's words go in its body: the box less whatever the tail took.
  if (e.shape == ShapeKind.speechBubble) {
    var body = bubbleBodyRect(rect, e.bubble);
    if (e.padded) return e.pad.inner(body);
    var margin = e.bubble.body == BubbleBody.burst ? 0.22 : 0.1;
    return body.deflate(body.shortestSide * margin);
  }
  if (e.padded) return e.pad.inner(rect);

  var inset = switch (e.shape) {
    ShapeKind.circle || ShapeKind.ellipse => 0.15,
    ShapeKind.triangle => 0.24,
    ShapeKind.diamond || ShapeKind.star => 0.26,
    ShapeKind.pentagon || ShapeKind.hexagon => 0.16,
    _ => 0.06,
  };
  var box = rect.deflate(rect.shortestSide * inset);
  // A triangle's room is not centred in its box: the top is a point.
  if (e.shape == ShapeKind.triangle) {
    box = box.translate(0, rect.height * 0.1);
  }
  return box;
}

/// lineControlPoint is the control point of a bowed line's quadratic, in its
/// unrotated coordinates, shared by painter, hit test and text on the line.
/// Pushed out square to the chord, so the bow is the same either way round.
Offset lineControlPoint(LineElement e) {
  var a = e.start, b = e.end;
  var mid = (a + b) / 2;
  var d = b - a;
  var length = d.distance;
  if (length == 0 || e.curvature == 0) return mid;
  return mid + Offset(-d.dy / length, d.dx / length) * (length * e.curvature);
}

void _paintLine(ui.Canvas canvas, LineElement e) {
  var control = lineControlPoint(e);
  var path = Path()..moveTo(e.start.dx, e.start.dy);
  if (e.curvature == 0) {
    path.lineTo(e.end.dx, e.end.dy);
  } else {
    path.quadraticBezierTo(control.dx, control.dy, e.end.dx, e.end.dy);
  }

  // Across the whole line, so a fade runs end to end whichever way it points.
  var paint = PaintSpec(e.color, gradient: e.fade).into(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = e.strokeWidth
        ..strokeCap = e.cap.flutter,
      path.getBounds());

  // A path metric gives the exact position and direction at each end, so the
  // decorations sit square on a bowed line.
  var metrics = path.computeMetrics().toList();
  if (metrics.isEmpty) return;
  var metric = metrics.first;
  var length = metric.length;

  var startTangent = metric.getTangentForOffset(0);
  var endTangent = metric.getTangentForOffset(length);
  if (startTangent == null || endTangent == null) return;

  // A decoration is drawn on the line's end, so the stroke is cut back to its
  // base, or a thick stroke pokes out of the sides of the barb.
  var trimStart = _trimFor(e.startEnd, e.strokeWidth, e.endSize);
  var trimEnd = _trimFor(e.endEnd, e.strokeWidth, e.endSize);
  var from = math.min(trimStart, length * 0.45);
  var to = math.max(length - trimEnd, from + 0.01);
  var stroke = metric.extractPath(from, to);

  canvas.drawPath(
      e.dash > 0 ? dashPath(stroke, e.dash, e.dash * 0.8) : stroke, paint);

  // From the vector, never Tangent.angle: that is *minus* atan2(dy, dx), y
  // up, and flips every decoration on a diagonal line in canvas space.
  double heading(ui.Tangent t) => math.atan2(t.vector.dy, t.vector.dx);

  // The start decoration points back out of the line: the curve reversed.
  _paintLineEnd(canvas, e.startEnd, startTangent.position,
      heading(startTangent) + math.pi, e);
  _paintLineEnd(canvas, e.endEnd, endTangent.position, heading(endTangent), e);
}

/// _trimFor is how far back from a line's end its decoration begins: every
/// one, so the stroke does not show through a hollow one (LineEnd.cover).
double _trimFor(LineEnd end, double strokeWidth, double endSize) =>
    end.cover * strokeWidth * endSize;

/// _paintLineEnd draws one decoration along [angle], the line's direction at
/// that end from the path metric, so it sits square however bent the curve.
void _paintLineEnd(
    ui.Canvas canvas, LineEnd end, Offset at, double angle, LineElement e) {
  if (end == LineEnd.none) return;
  var w = e.strokeWidth * e.endSize;
  var fill = Paint()
    ..style = PaintingStyle.fill
    ..color = e.color;
  var stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = e.strokeWidth
    ..strokeJoin = StrokeJoin.miter
    ..color = e.color;

  var along = Offset(math.cos(angle), math.sin(angle));
  var across = Offset(-along.dy, along.dx);

  switch (end) {
    case LineEnd.none:
      return;
    case LineEnd.arrow:
      arrowHead(canvas, at, angle, w * 3.5, fill);
    case LineEnd.hollowArrow:
      arrowHead(canvas, at, angle, w * 3.5, stroke, filled: false);
    case LineEnd.openArrow:
      // A filled chevron rather than two strokes: thickest at the tip and
      // pointed at each outer end, as an open arrow is drawn by hand.
      var size = w * 4.2;
      var back = angle + math.pi;
      var b1 = at.translate(math.cos(back - arrowSpread) * size,
          math.sin(back - arrowSpread) * size);
      var b2 = at.translate(math.cos(back + arrowSpread) * size,
          math.sin(back + arrowSpread) * size);
      // The notch behind the tip gives it its thickness, as a fraction of
      // the barb so the proportions hold at any end size.
      var notch = at - along * (size * 0.58);
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
      // Centred on the line's end, like the circle and the square.
      var long = w * 1.7;
      var wide = w * 1.0;
      canvas.drawPath(
        Path()
          ..moveTo(at.dx + along.dx * long, at.dy + along.dy * long)
          ..lineTo(at.dx + across.dx * wide, at.dy + across.dy * wide)
          ..lineTo(at.dx - along.dx * long, at.dy - along.dy * long)
          ..lineTo(at.dx - across.dx * wide, at.dy - across.dy * wide)
          ..close(),
        end == LineEnd.diamond ? fill : stroke,
      );
    case LineEnd.circle:
      canvas.drawCircle(at, w * 1.2, fill);
    case LineEnd.hollowCircle:
      canvas.drawCircle(at, w * 1.2, stroke);
    case LineEnd.square:
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(angle);
      canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: w * 2.2, height: w * 2.2),
          fill);
      canvas.restore();
    case LineEnd.bar:
      // A tick across the line, which is what a measurement wants at each end.
      canvas.drawLine(at - across * (w * 1.6), at + across * (w * 1.6), stroke);
  }
}

void _paintButton(ui.Canvas canvas, Rect bounds, ButtonElement e, bool hovered,
    CanvasImageSource? images) {
  var box = e.box;
  if (hovered && e.hoverFill.a > 0) box = box.copyWith(fill: e.hoverFill);
  paintBox(canvas, bounds, box, images);

  var spec = e.textSpec;
  if (hovered && e.hoverTextColor.a > 0) {
    spec = spec.copyWith(color: e.hoverTextColor);
  }
  var inner = e.box.inner(bounds);
  if (inner.width <= 0 || inner.height <= 0) return;
  paintTextInBox(canvas, spec.textCase.apply(e.label), spec, inner, clip: true);
}

/// _paintPath draws a bezier curve. A guide path (PathElement.guide) is
/// scaffolding: drawn only while [editing], never in anything published.
void _paintPath(ui.Canvas canvas, Rect bounds, PathElement e, bool editing) {
  if (e.nodes.length < 2) return;
  if (e.guide && !editing) return;

  var path = ui.Path();
  Offset at(PathNode n) => Offset(
      bounds.left + n.x * bounds.width, bounds.top + n.y * bounds.height);
  Offset handle(PathNode n, double dx, double dy) => Offset(
      bounds.left + (n.x + dx) * bounds.width,
      bounds.top + (n.y + dy) * bounds.height);

  path.moveTo(at(e.nodes.first).dx, at(e.nodes.first).dy);
  for (var i = 0; i < e.segments; i++) {
    var a = e.nodes[i % e.nodes.length];
    var b = e.nodes[(i + 1) % e.nodes.length];
    var c1 = a.outDx == 0 && a.outDy == 0 ? at(a) : handle(a, a.outDx, a.outDy);
    var c2 = b.inDx == 0 && b.inDy == 0 ? at(b) : handle(b, b.inDx, b.inDy);
    var end = at(b);
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
  }
  if (e.closed) path.close();

  // Across the whole path, so a fade runs along its length.
  var paint = PaintSpec(e.color, gradient: e.fade).into(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = e.strokeWidth
        ..strokeCap = e.cap.flutter,
      path.getBounds());

  canvas.drawPath(e.dash > 0 ? dashPath(path, e.dash, e.dash) : path, paint);

  // The arrowhead points along the last segment's own direction, not the
  // chord between the last two nodes, which can point backwards.
  if (e.endEnd != LineEnd.none && !e.closed) {
    var last = e.segments - 1;
    var tip = e.pointOnSegment(last, 1);
    var just = e.pointOnSegment(last, 0.94);
    var shift = Offset(bounds.left - e.x, bounds.top - e.y);
    _paintArrowHead(canvas, just + shift, tip + shift, e.strokeWidth, e.color);
  }
  if (e.startEnd != LineEnd.none && !e.closed) {
    var tip = e.pointOnSegment(0, 0);
    var just = e.pointOnSegment(0, 0.06);
    var shift = Offset(bounds.left - e.x, bounds.top - e.y);
    _paintArrowHead(canvas, just + shift, tip + shift, e.strokeWidth, e.color);
  }
}

/// _paintArrowHead draws a solid head at [tip], pointing away from [from].
void _paintArrowHead(
    ui.Canvas canvas, Offset from, Offset tip, double width, Color color) {
  var direction = tip - from;
  if (direction.distance < 0.001) return;
  var angle = math.atan2(direction.dy, direction.dx);
  var size = math.max(6.0, width * 3);
  var head = ui.Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(tip.dx - size * math.cos(angle - 0.4),
        tip.dy - size * math.sin(angle - 0.4))
    ..lineTo(tip.dx - size * math.cos(angle + 0.4),
        tip.dy - size * math.sin(angle + 0.4))
    ..close();
  canvas.drawPath(head, Paint()..color = color);
}
