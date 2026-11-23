part of 'paint_util.dart';

// A shape's outline (the shape element's, and a kind of shape borrowed by a
// picture's frame, the shapes transition and the panel's tiles), the speech
// bubble's body and tail, a star, and the dash any stroke is broken into.
// Part of paint_util.dart.

/// shapeOutline is [e]'s outline in its box [bounds], before the box is
/// turned or slanted onto the page: what is filled and stroked, what a loop
/// runs round, what wrapped words go round and what a press lands on, so
/// none of them can disagree about a shape's edge. Each outline built is
/// kept by what it is made from (_outlines), so they share one, and the
/// paint after asks for it again without building it again. What is handed
/// back is shared: nothing asking may change it.
Path shapeOutline(ShapeElement e, Rect bounds) {
  var box = shapeBox(e, bounds);
  var c = e.corners, b = e.bubble;
  var key = (
    e.shape,
    box,
    e.points,
    e.innerRatio,
    (c.all, c.tl, c.tr, c.br, c.bl),
    (b.body, b.tail, b.tailAngle, b.tailLength, b.tailWidth, b.curl),
  );
  // Taken out and put back, so the map's order is the order last asked.
  var kept = _outlines.remove(key);
  if (kept == null && _outlines.length >= _outlinesKept) {
    _outlines.remove(_outlines.keys.first);
  }
  return _outlines[key] = kept ??
      shapePath(e.shape, box,
          points: e.points,
          inner: e.innerRatio,
          cornerRadius: e.cornerRadius,
          corners: c,
          bubble: e.bubble);
}

/// _outlines is every outline shapeOutline has built and not yet let go,
/// the least lately asked first: a cloud bubble is a dozen unions of
/// circles, and twenty of them took a third of a frame to build on every
/// paint. A shape whose box moves on every frame makes a new one each
/// time, so they are let go past [_outlinesKept].
final Map<Object, Path> _outlines = {};
const int _outlinesKept = 512;

/// clearShapeOutlines lets go of every outline shapeOutline has kept
/// (clearRenderCaches).
void clearShapeOutlines() => _outlines.clear();

/// shapeBox is the part of [bounds] [e]'s outline is drawn in: the whole
/// box, or for a square or a circle the square in its middle, so one in an
/// oblong box is still square or round.
Rect shapeBox(ShapeElement e, Rect bounds) {
  if (!e.shape.isRegular) return bounds;
  var side = bounds.shortestSide;
  return Rect.fromCenter(center: bounds.center, width: side, height: side);
}

/// shapePath turns a [ShapeKind] into a path filling [rect], built in [rect]
/// itself rather than a scaled unit square, so a stretched stroke stays even.
Path shapePath(ShapeKind kind, Rect rect,
    {int points = 5,
    double inner = 0.42,
    double cornerRadius = 0,

    /// corners rounds each corner alone; null means [cornerRadius] for all.
    Corners? corners,
    SpeechBubbleSpec bubble = const SpeechBubbleSpec()}) {
  var path = Path();
  var c = rect.center;
  var rx = rect.width / 2, ry = rect.height / 2;

  switch (kind) {
    case ShapeKind.rectangle:
    case ShapeKind.square:
      var round = corners ?? Corners(all: cornerRadius);
      if (round.isRounded) {
        path.addRRect(round.rrect(rect));
      } else {
        path.addRect(rect);
      }

    case ShapeKind.ellipse:
    case ShapeKind.circle:
      path.addOval(rect);

    case ShapeKind.triangle:
      path.moveTo(c.dx, rect.top);
      path.lineTo(rect.right, rect.bottom);
      path.lineTo(rect.left, rect.bottom);
      path.close();

    case ShapeKind.diamond:
      path.moveTo(c.dx, rect.top);
      path.lineTo(rect.right, c.dy);
      path.lineTo(c.dx, rect.bottom);
      path.lineTo(rect.left, c.dy);
      path.close();

    case ShapeKind.pentagon:
      _regular(path, c, rx, ry, 5);
    case ShapeKind.hexagon:
      _regular(path, c, rx, ry, 6);

    case ShapeKind.star:
      return starPath(c, rx, ry, points.clamp(minStarPoints, maxStarPoints),
          inner.clamp(minStarDepth, maxStarDepth).toDouble());

    case ShapeKind.arrow:
      // A shaft along the middle third with a head taking the last quarter.
      var headStart = rect.left + rect.width * 0.72;
      var shaft = rect.height * 0.34;
      path.moveTo(rect.left, c.dy - shaft / 2);
      path.lineTo(headStart, c.dy - shaft / 2);
      path.lineTo(headStart, rect.top);
      path.lineTo(rect.right, c.dy);
      path.lineTo(headStart, rect.bottom);
      path.lineTo(headStart, c.dy + shaft / 2);
      path.lineTo(rect.left, c.dy + shaft / 2);
      path.close();

    case ShapeKind.chevron:
      var notch = rect.width * 0.28;
      path.moveTo(rect.left, rect.top);
      path.lineTo(rect.right - notch, rect.top);
      path.lineTo(rect.right, c.dy);
      path.lineTo(rect.right - notch, rect.bottom);
      path.lineTo(rect.left, rect.bottom);
      path.lineTo(rect.left + notch, c.dy);
      path.close();

    case ShapeKind.cross:
      // A plus, as one outline of twelve corners round both bars: two bars
      // laid over each other fill the same, but an outline would run
      // through the middle where they cross.
      var t = math.min(rx, ry) * 0.42;
      var (l, r) = (c.dx - t, c.dx + t);
      var (u, d) = (c.dy - t, c.dy + t);
      path
        ..moveTo(l, rect.top)
        ..lineTo(r, rect.top)
        ..lineTo(r, u)
        ..lineTo(rect.right, u)
        ..lineTo(rect.right, d)
        ..lineTo(r, d)
        ..lineTo(r, rect.bottom)
        ..lineTo(l, rect.bottom)
        ..lineTo(l, d)
        ..lineTo(rect.left, d)
        ..lineTo(rect.left, u)
        ..lineTo(l, u)
        ..close();

    case ShapeKind.speechBubble:
      return bubblePath(rect, bubble, corners ?? Corners(all: cornerRadius));
  }
  return path;
}

/// starPath is a star of [points] spikes about [centre], reaching [rx]
/// across and [ry] down, cut between the spikes to [inner] of that reach,
/// its first spike straight up: a star shape, a burst bubble's body and a
/// burst transition's middle.
Path starPath(Offset centre, double rx, double ry, int points, double inner) {
  var path = Path();
  for (var i = 0; i < points * 2; i++) {
    var a = -math.pi / 2 + i * math.pi / points;
    var r = i.isEven ? 1.0 : inner;
    var p = Offset(
        centre.dx + math.cos(a) * rx * r, centre.dy + math.sin(a) * ry * r);
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

void _regular(Path path, Offset c, double rx, double ry, int sides) {
  for (var i = 0; i < sides; i++) {
    var a = -math.pi / 2 + i * 2 * math.pi / sides;
    var p = Offset(c.dx + math.cos(a) * rx, c.dy + math.sin(a) * ry);
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  path.close();
}

/// _dashPath breaks [source] into dashes of [on] followed by gaps of [off].
Path _dashPath(Path source, double on, double off) {
  if (!(on > 0) || !off.isFinite) return source;
  off = math.max(0.0, off);
  // Past this many dashes the line is drawn whole, so a tiny dash from a
  // received document cannot hang the paint.
  const most = 20000;
  var metrics = source.computeMetrics().toList();
  var total = metrics.fold(0.0, (n, m) => n + m.length);
  if (total / (on + off) > most) return source;
  var out = Path();
  for (var metric in metrics) {
    var d = 0.0;
    while (d < metric.length) {
      var next = math.min(d + on, metric.length);
      out.addPath(metric.extractPath(d, next), Offset.zero);
      d = next + off;
    }
  }
  return out;
}

/// bubbleBodyRect is the part of a speech bubble the words go in. The box
/// holds the tail too, so the body gives up room only on the tail's side:
/// as far as the tail reaches past it (_tailReach).
Rect bubbleBodyRect(Rect rect, SpeechBubbleSpec bubble) {
  if (bubble.tail == BubbleTail.none) return rect;
  var radians = bubble.tailAngle * math.pi / 180;
  var dx = math.cos(radians);
  var dy = math.sin(radians);
  var reach = _tailReach(rect, bubble);
  return Rect.fromLTRB(
    rect.left + (dx < 0 ? -dx * reach : 0),
    rect.top + (dy < 0 ? -dy * reach : 0),
    rect.right - (dx > 0 ? dx * reach : 0),
    rect.bottom - (dy > 0 ? dy * reach : 0),
  );
}

/// _tailReach is how far a bubble's tail reaches past its body, the way it
/// points: a pointer's or a curve's length, or the whole of a thought's
/// trail of circles, which is longer than its length by the circles'
/// size. Never more than the box's shorter side, the most a length can
/// reach, so a broad trail leaves the body some room.
double _tailReach(Rect rect, SpeechBubbleSpec bubble) {
  var length = rect.shortestSide / 2 * bubble.tailLength;
  if (bubble.tail != BubbleTail.thought) return length;
  var (along, radius) = _trail(rect, bubble).last;
  return math.min(along + radius, rect.shortestSide);
}

/// _trail is a thought's trail of shrinking circles, each as how far its
/// middle is from the body's edge and its radius, before it is fitted into
/// the box (bubblePath).
List<(double, double)> _trail(Rect rect, SpeechBubbleSpec bubble) {
  const count = 3;
  var unit = rect.shortestSide / 2 * bubble.tailWidth * 0.5;
  var length = rect.shortestSide / 2 * bubble.tailLength;
  return [
    for (var i = 0; i < count; i++)
      (
        unit * 1.6 + length * 0.9 * (i / (count - 1)),
        unit * (1 - i / (count - 1) * 0.4)
      ),
  ];
}

/// bubblePath is a speech bubble as one outline: body and tail unioned, so
/// a stroke draws one boundary with no line across the join. All of it is
/// inside [rect], the element's box, whatever the tail does: what the
/// selection box, a press and wrapped words take the bubble to be.
Path bubblePath(Rect rect, SpeechBubbleSpec bubble, Corners corners) {
  var body = bubbleBodyRect(rect, bubble);
  var shape = _bubbleBody(body, bubble.body, corners);
  if (bubble.tail == BubbleTail.none) return shape;

  var radians = bubble.tailAngle * math.pi / 180;
  var out = Offset(math.cos(radians), math.sin(radians));

  // A thought bubble's tail is a trail of separate shrinking circles.
  if (bubble.tail == BubbleTail.thought) {
    return Path.combine(
        PathOperation.union, shape, _thoughtTrail(rect, body, bubble, out));
  }

  // Where the tail leaves the body: on the body's ellipse in that direction,
  // so a tail at 45 degrees leaves from the corner.
  var anchor = Offset(body.center.dx + out.dx * body.width / 2,
      body.center.dy + out.dy * body.height / 2);
  var reach = _tailReach(rect, bubble);
  var tip = anchor + out * reach;
  var across =
      Offset(-out.dy, out.dx) * (rect.shortestSide / 2 * bubble.tailWidth / 2);
  // Started inside the body so the union leaves no hairline at the join.
  var root = anchor - out * (reach * 0.35);
  var tail = Path()..moveTo(root.dx + across.dx, root.dy + across.dy);

  if (bubble.tail == BubbleTail.curved) {
    // A hooked tail: it leaves the body square and bends as it narrows.
    var bend = Offset(-out.dy, out.dx) * (reach * bubble.curl);
    tail
      ..quadraticBezierTo(
          anchor.dx + bend.dx, anchor.dy + bend.dy, tip.dx, tip.dy)
      ..quadraticBezierTo(anchor.dx + bend.dx * 0.35,
          anchor.dy + bend.dy * 0.35, root.dx - across.dx, root.dy - across.dy);
  } else {
    tail
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(root.dx - across.dx, root.dy - across.dy);
  }
  tail.close();
  // A tail far broader than it is long, bent far round, or longer than the
  // body has room to give up can still reach past the box: what is past it
  // is cut off at the box's edge.
  var reached = tail.getBounds();
  if (reached.left < rect.left ||
      reached.top < rect.top ||
      reached.right > rect.right ||
      reached.bottom > rect.bottom) {
    tail = Path.combine(PathOperation.intersect, tail, Path()..addRect(rect));
  }

  return Path.combine(PathOperation.union, shape, tail);
}

/// _thoughtTrail is a thought's circles laid out from [body]'s edge along
/// [out], inside [rect]. The body has given up room for the whole trail;
/// pointing between the sides, where the circles' own width can carry them
/// past an edge, the trail is drawn smaller about where it leaves the body,
/// enough to stay inside.
Path _thoughtTrail(Rect rect, Rect body, SpeechBubbleSpec bubble, Offset out) {
  var circles = _trail(rect, bubble);
  var (along, radius) = circles.last;
  var reach = along + radius;
  var size = reach > 0 ? _tailReach(rect, bubble) / reach : 1.0;
  // From the body's rectangle edge, not the ellipse, so dots do not weld.
  var edge = _rayToRect(body, out);
  // The most each circle may grow, side by side: what is left between the
  // edge and that side of the box over how far it would reach that way.
  double fit(double room, double reach) => reach > 0 ? room / reach : 1;
  for (var (along, radius) in circles) {
    size = [
      size,
      fit(rect.right - edge.dx, out.dx * along + radius),
      fit(edge.dx - rect.left, radius - out.dx * along),
      fit(rect.bottom - edge.dy, out.dy * along + radius),
      fit(edge.dy - rect.top, radius - out.dy * along),
    ].reduce(math.min);
  }
  size = math.max(size, 0);
  var trail = Path();
  for (var (along, radius) in circles) {
    trail.addOval(Rect.fromCircle(
        center: edge + out * (along * size), radius: radius * size));
  }
  return trail;
}

/// _rayToRect is where a ray from [rect]'s centre along [out] meets its edge.
Offset _rayToRect(Rect rect, Offset out) {
  var half = Offset(rect.width / 2, rect.height / 2);
  var scaleX = out.dx == 0 ? double.infinity : (half.dx / out.dx).abs();
  var scaleY = out.dy == 0 ? double.infinity : (half.dy / out.dy).abs();
  var scale = math.min(scaleX, scaleY);
  if (!scale.isFinite) return rect.center;
  return rect.center + out * scale;
}

/// _bubbleBody is a bubble's body filling [body]. A rounded one takes
/// [corners] where they are set, and its own rounding where they are not.
Path _bubbleBody(Rect body, BubbleBody kind, Corners corners) {
  var path = Path();
  switch (kind) {
    case BubbleBody.rounded:
      var even = corners.all > 0 ? corners.all : body.shortestSide * 0.22;
      double round(double? own) => math.min(own ?? even, body.shortestSide / 2);
      var (tl, tr) = (round(corners.tl), round(corners.tr));
      var (br, bl) = (round(corners.br), round(corners.bl));
      if (tl == tr && tr == br && br == bl) {
        path.addRRect(RRect.fromRectAndRadius(body, Radius.circular(tl)));
      } else {
        path.addRRect(RRect.fromRectAndCorners(body,
            topLeft: Radius.circular(tl),
            topRight: Radius.circular(tr),
            bottomRight: Radius.circular(br),
            bottomLeft: Radius.circular(bl)));
      }
    case BubbleBody.oval:
      path.addOval(body);
    case BubbleBody.cloud:
      // Overlapping circles round the rim, unioned into one puffy outline.
      // The rim is drawn in from the body's edge by a lump's radius where
      // it must be, so the lumps reach the body's edge and no further: on
      // a short side always, on a long one only in a box near square.
      var radius = body.shortestSide * 0.19;
      var across = math.min(body.width * 0.36, body.width / 2 - radius);
      var down = math.min(body.height * 0.36, body.height / 2 - radius);
      var lumps = Path()..addOval(body.deflate(body.shortestSide * 0.14));
      const count = 11;
      for (var i = 0; i < count; i++) {
        var a = i * 2 * math.pi / count;
        var at = Offset(body.center.dx + math.cos(a) * across,
            body.center.dy + math.sin(a) * down);
        lumps = Path.combine(PathOperation.union, lumps,
            Path()..addOval(Rect.fromCircle(center: at, radius: radius)));
      }
      return lumps;
    case BubbleBody.burst:
      // A shout: alternating long and short points all the way round.
      return starPath(body.center, body.width / 2, body.height / 2, 12, 0.74);
  }
  return path;
}
