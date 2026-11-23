part of 'scene_renderer.dart';

// Shapes, lines and paths, and the geometry of a drawn line or curve (its
// bow, text riding it, where it is really drawn) that the stage hit-tests
// against. Part of scene_renderer.dart.

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
      // Slid along the line where the pose says, as the painter places them
      // (_paintTextBody).
      var on = element.curve!;
      var slide = poseWithMotion(element, frame, doc, live: live)
          .values[KeyframeChannel.slide];
      var glyphs = placeTextOnPath(element.displayText, element.textSpec, curve,
          slide == null ? on : on.copyWith(offset: slide),
          parts: element.drawnParts);
      var box = textOnPathBounds(glyphs, element.curve!);
      // No letters placed (empty, or slid off the end): the line itself.
      return box ?? _boundsOfPoints(curve) ?? moved();
    }
    return moved();
  }

  if (element is StrokedElement) {
    var host = element is LineElement ? lineWithPose(element, frame) : element;
    var curve = curveOfElement(host);
    var box = _boundsOfPoints(curve);
    if (box == null) return moved();
    // Room for the stroke, centred on the curve, and for the ends it draws
    // (LineEnd.reach).
    var stroke = element.drawnStroke;
    return box.inflate(
        math.max(stroke.strokeWidth, 1) * math.max(stroke.endReach, 1.5));
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

/// _curveFor is the line text [e] rides, as document-space points, or null
/// where its words are not set on a line (TextElement.wordsSetIn). Found by
/// id, so the text follows it; if deleted, the text uses its box.
List<Offset>? _curveFor(TextElement e, CanvasDocument? doc, int frame) {
  if (e.wordsSetIn(doc) != WordsSet.onLine) return null;
  var host = doc!.elementById(e.curve!.elementId);
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
  var rect = shapeBox(e, bounds);
  var path = shapeOutline(e, bounds);

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

  // As typed: the layout puts the words in their case.
  if (e.text.isNotEmpty) {
    paintTextInBox(canvas, e.text, e.textSpec, labelRoom(e, rect));
  }
}

/// labelRoom is where a shape's label is set in [rect], the box its outline
/// is drawn in (shapeBox): its padding, or else its kind's own inset
/// (ShapeKind.labelInsetWith, labelDrop).
Rect labelRoom(ShapeElement e, Rect rect) {
  // A bubble's words go in its body: the box less whatever the tail took.
  var room =
      e.shape == ShapeKind.speechBubble ? bubbleBodyRect(rect, e.bubble) : rect;
  if (e.padded) return e.pad.inner(room);
  var box = room.deflate(room.shortestSide * e.labelInset);
  var drop = e.shape.labelDrop;
  return drop == 0 ? box : box.translate(0, rect.height * drop);
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

/// _paintLine draws a line as a stroke from its start to its end, bowed
/// through its control point.
void _paintLine(ui.Canvas canvas, LineElement e) {
  var control = lineControlPoint(e);
  var path = Path()..moveTo(e.start.dx, e.start.dy);
  if (e.curvature == 0) {
    path.lineTo(e.end.dx, e.end.dy);
  } else {
    path.quadraticBezierTo(control.dx, control.dy, e.end.dx, e.end.dy);
  }
  paintStroke(canvas, path, e.drawnStroke);
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
  // As typed: the layout puts the words in their case.
  paintTextInBox(canvas, e.label, spec, inner, clip: true);
}

/// _paintPath draws a path's stroke along the bezier curve through its
/// nodes. A guide path (PathElement.guide) is scaffolding: drawn only while
/// [editing], never in anything published.
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

  paintStroke(canvas, path, e.drawnStroke);
}
