part of 'paint_util.dart';

// Boxes and their fills and borders, shape outlines, dashes, arrow heads and
// speech bubbles. Part of paint_util.dart.

/// paintBox draws a [BoxSpec]: the fill, then the border, both rounded.
void paintBox(ui.Canvas canvas, Rect rect, BoxSpec box,
    [CanvasImageSource? images]) {
  paintBoxFill(canvas, rect, box, images);
  paintBoxBorder(canvas, rect, box);
}

/// paintBoxFill is the inside of a box (its colour, and a picture or pattern
/// over that) without its border, for an element drawing between the two.
void paintBoxFill(ui.Canvas canvas, Rect rect, BoxSpec box,
    [CanvasImageSource? images]) {
  if (rect.width <= 0 || rect.height <= 0) return;
  var filled = PaintSpec(box.fill, gradient: box.fillFade);
  if (filled.shows) {
    canvas.drawRRect(box.rounded(rect), filled.into(Paint(), rect));
  }
  // A picture or pattern over that, cut to the box as paintThroughText does.
  if (box.painted.on) {
    paintThroughText(canvas, rect, box.painted, images,
        () => canvas.drawRRect(box.rounded(rect), Paint()));
  }
}

/// paintBoxBorder is a box's border alone, inside its edge.
void paintBoxBorder(ui.Canvas canvas, Rect rect, BoxSpec box) {
  if (rect.width <= 0 || rect.height <= 0) return;
  if (!box.hasBorder) return;
  var inset = box.borderInset;

  var paint =
      PaintSpec(box.borderColor, gradient: box.borderFade).into(Paint(), rect);

  var even = box.evenBorder;
  if (even != null) {
    // Inset by half the stroke so the border sits inside the bounds and is
    // not half cut off on a full-bleed element.
    canvas.drawRRect(
      // Inset, with the box's own rounding rather than concentric corners,
      // which a deep inset would square off.
      box.rounded(inset > 0 ? rect.deflate(inset) : rect, by: even / 2),
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = even,
    );
    return;
  }

  // Uneven sides are four strips inside the bounds, square where they meet:
  // two widths at a rounded corner have no agreed shape.
  var sides = box.borders;
  paint.style = PaintingStyle.fill;
  if (inset > 0) rect = rect.deflate(inset);
  if (sides.top > 0) {
    canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top, rect.width, sides.top), paint);
  }
  if (sides.bottom > 0) {
    canvas.drawRect(
        Rect.fromLTWH(
            rect.left, rect.bottom - sides.bottom, rect.width, sides.bottom),
        paint);
  }
  if (sides.left > 0) {
    canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top, sides.left, rect.height), paint);
  }
  if (sides.right > 0) {
    canvas.drawRect(
        Rect.fromLTWH(
            rect.right - sides.right, rect.top, sides.right, rect.height),
        paint);
  }
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
      var n = points.clamp(minStarPoints, maxStarPoints);
      var ratio = inner.clamp(minStarDepth, maxStarDepth).toDouble();
      for (var i = 0; i < n * 2; i++) {
        var a = -math.pi / 2 + i * math.pi / n;
        var r = i.isEven ? 1.0 : ratio;
        var p =
            Offset(c.dx + math.cos(a) * rx * r, c.dy + math.sin(a) * ry * r);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();

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
      var t = math.min(rx, ry) * 0.42;
      path.addRect(Rect.fromLTRB(c.dx - t, rect.top, c.dx + t, rect.bottom));
      path.addRect(Rect.fromLTRB(rect.left, c.dy - t, rect.right, c.dy + t));

    case ShapeKind.speechBubble:
      return bubblePath(rect, bubble, cornerRadius);
  }
  return path;
}

void _regular(Path path, Offset c, double rx, double ry, int sides) {
  for (var i = 0; i < sides; i++) {
    var a = -math.pi / 2 + i * 2 * math.pi / sides;
    var p = Offset(c.dx + math.cos(a) * rx, c.dy + math.sin(a) * ry);
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  path.close();
}

/// dashPath breaks [source] into dashes of [on] followed by gaps of [off].
Path dashPath(Path source, double on, double off) {
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

/// arrowSpread is the half-angle between an arrowhead's axis and each barb
/// (radians), shared with scene_renderer.dart's line ends: LineEnd.cover
/// trims the stroke back to where the barbs meet, assuming this value.
const double arrowSpread = 0.42;

/// arrowHead is a triangle at [tip] along [angle], stroked if not [filled].
void arrowHead(
    ui.Canvas canvas, Offset tip, double angle, double size, Paint paint,
    {bool filled = true}) {
  var back = angle + math.pi;
  var spread = arrowSpread;
  var path = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(tip.dx + math.cos(back - spread) * size,
        tip.dy + math.sin(back - spread) * size)
    ..lineTo(tip.dx + math.cos(back + spread) * size,
        tip.dy + math.sin(back + spread) * size)
    ..close();
  canvas.drawPath(
      path,
      Paint()
        ..color = paint.color
        ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = paint.strokeWidth
        ..strokeJoin = StrokeJoin.miter);
}

/// bubbleBodyRect is the part of a speech bubble the words go in. The box
/// holds the tail too, so the body gives up room only on the tail's side.
Rect bubbleBodyRect(Rect rect, SpeechBubbleSpec bubble) {
  if (bubble.tail == BubbleTail.none) return rect;
  var radians = bubble.tailAngle * math.pi / 180;
  var dx = math.cos(radians);
  var dy = math.sin(radians);
  var reach = rect.shortestSide / 2 * bubble.tailLength;
  return Rect.fromLTRB(
    rect.left + (dx < 0 ? -dx * reach : 0),
    rect.top + (dy < 0 ? -dy * reach : 0),
    rect.right - (dx > 0 ? dx * reach : 0),
    rect.bottom - (dy > 0 ? dy * reach : 0),
  );
}

/// bubblePath is a speech bubble as one outline: body and tail unioned, so
/// a stroke draws one boundary with no line across the join.
Path bubblePath(Rect rect, SpeechBubbleSpec bubble, double cornerRadius) {
  var body = bubbleBodyRect(rect, bubble);
  var shape = _bubbleBody(body, bubble.body, cornerRadius);
  if (bubble.tail == BubbleTail.none) return shape;

  var radians = bubble.tailAngle * math.pi / 180;
  var out = Offset(math.cos(radians), math.sin(radians));
  // Where the tail leaves the body: on the body's ellipse in that direction,
  // so a tail at 45 degrees leaves from the corner.
  var anchor = Offset(body.center.dx + out.dx * body.width / 2,
      body.center.dy + out.dy * body.height / 2);
  var reach = rect.shortestSide / 2 * bubble.tailLength;
  var tip = anchor + out * reach;

  // A thought bubble's tail is a trail of separate shrinking circles.
  if (bubble.tail == BubbleTail.thought) {
    var trail = Path();
    var count = 3;
    var unit = rect.shortestSide / 2 * bubble.tailWidth * 0.5;
    // From the body's rectangle edge, not the ellipse, so dots do not weld.
    var edge = _rayToRect(body, out);
    for (var i = 0; i < count; i++) {
      var t = i / (count - 1);
      var at = edge + out * (unit * 1.6 + reach * 0.9 * t);
      trail.addOval(Rect.fromCircle(center: at, radius: unit * (1 - t * 0.4)));
    }
    return Path.combine(PathOperation.union, shape, trail);
  }

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

  return Path.combine(PathOperation.union, shape, tail);
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

Path _bubbleBody(Rect body, BubbleBody kind, double cornerRadius) {
  var path = Path();
  switch (kind) {
    case BubbleBody.rounded:
      var r = math.min(
          cornerRadius > 0 ? cornerRadius : body.shortestSide * 0.22,
          body.shortestSide / 2);
      path.addRRect(RRect.fromRectAndRadius(body, Radius.circular(r)));
    case BubbleBody.oval:
      path.addOval(body);
    case BubbleBody.cloud:
      // Overlapping circles round the rim, unioned into one puffy outline.
      var lumps = Path()..addOval(body.deflate(body.shortestSide * 0.14));
      const count = 11;
      for (var i = 0; i < count; i++) {
        var a = i * 2 * math.pi / count;
        var at = Offset(body.center.dx + math.cos(a) * body.width * 0.36,
            body.center.dy + math.sin(a) * body.height * 0.36);
        lumps = Path.combine(
            PathOperation.union,
            lumps,
            Path()
              ..addOval(Rect.fromCircle(
                  center: at, radius: body.shortestSide * 0.19)));
      }
      return lumps;
    case BubbleBody.burst:
      // A shout: alternating long and short points all the way round.
      const spikes = 12;
      for (var i = 0; i < spikes * 2; i++) {
        var a = -math.pi / 2 + i * math.pi / spikes;
        var far = i.isEven ? 1.0 : 0.74;
        var p = Offset(body.center.dx + math.cos(a) * body.width / 2 * far,
            body.center.dy + math.sin(a) * body.height / 2 * far);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
  }
  return path;
}
