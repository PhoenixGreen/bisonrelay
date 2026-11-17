part of 'scene_renderer.dart';

// Elements drawn a piece at a time (a table by row or column, a drawing by
// shape) and the loop pose and outline that loops run along. Part of
// scene_renderer.dart.

/// _ownShapes is whether any of [e]'s shapes has an animation of its own.
bool _ownShapes(VectorElement e) => vectorDrawn(e.shapes ?? const [])
    .any((d) => d.style.animation != null && d.style.owns.isNotEmpty);

/// wholeLoopOf is [element]'s loop where it loops as one -- for a drawing
/// with shapes of their own, each shape loops on its own instead, those
/// left as the drawing with the drawing's loop. See _paintVectorInTurn.
ElementLoop? wholeLoopOf(CanvasElement element) {
  if (element is VectorElement && _ownShapes(element)) return null;
  // The words' and a chart's are in animations of their own.
  if (element is TextElement) return element.animation.loop;
  if (element is ChartElement) return element.animation.loop;
  return _animationOf(element)?.loop;
}

/// _tableInTurn is whether a table comes in a row or column at a time:
/// asked to, arriving and not leaving (that is whole). See TableTurn.
bool _tableInTurn(TableElement e, Keyframe pose) =>
    e.turn != TableTurn.together &&
    e.animation.on &&
    e.rows.isNotEmpty &&
    (pose.values[KeyframeChannel.close] ?? 0) <= 0 &&
    (pose.values[KeyframeChannel.reveal] ?? 1) < 1;

/// paintTableInTurn draws a table a row or column at a time, each band its
/// arrival a share behind the last (TableTurn.revealOf) and the whole table
/// clipped to it, so fills, rules and corners are unbroken at the joins.
void paintTableInTurn(ui.Canvas canvas, Rect bounds, TableElement e,
    Keyframe pose, CanvasImageSource? images) {
  var through = pose.values[KeyframeChannel.reveal] ?? 1;
  var byRow = e.turn == TableTurn.rows;
  var sizes = byRow ? tableRowHeights(e, bounds) : tableColumnWidths(e, bounds);
  var at = byRow ? bounds.top : bounds.left;
  for (var (i, size) in sizes.indexed) {
    var band = byRow
        ? Rect.fromLTWH(bounds.left, at, bounds.width, size)
        : Rect.fromLTWH(at, bounds.top, size, bounds.height);
    at += size;
    var reveal = TableTurn.revealOf(through, i, sizes.length);
    if (reveal <= 0) continue;
    paintArriving(canvas, band, e.animation,
        pose.copyWith(values: {...pose.values, KeyframeChannel.reveal: reveal}),
        () {
      canvas.save();
      // Out to the outline's own edge, which is drawn over the table's.
      canvas.clipRect(band);
      paintTable(canvas, bounds, e, images: images);
      canvas.restore();
    });
  }
}

/// _shapeByShape is whether a drawing is drawn a shape at a time: a shape
/// has an animation of its own, or the drawing's arrival brings its shapes
/// in one after another, and it is not leaving. See VectorCue.
bool _shapeByShape(VectorElement e, Keyframe pose) {
  var shapes = e.shapes;
  if (shapes == null || shapes.isEmpty) return false;
  if (_ownShapes(e)) return true;
  if ((pose.values[KeyframeChannel.close] ?? 0) > 0) return false;
  return e.animation.on && sequenced(shapes) && _vectorArrival(e, pose) != null;
}

/// _paintVectorInTurn draws a drawing a shape at a time, each animated by
/// its own animation or the drawing's: coming in at its cue, in its box;
/// looping once in; leaving with the drawing. Shapes left as the drawing do
/// so about the whole. [last] is the scene's last frame.
void _paintVectorInTurn(ui.Canvas canvas, Rect bounds, VectorElement e,
    Keyframe pose, int frame, int last) {
  var shapes = e.shapes!;
  var arrival = _vectorArrival(e, pose);
  var times = arrival == null ? null : cueTimes(shapes, arrival.$2);
  var own = _ownShapes(e);
  var leaving = (pose.values[KeyframeChannel.close] ?? 0) > 0;
  // How far through its arrival the drawing is, easing included: the clock
  // every shape's turn is read off.
  var through = pose.values[KeyframeChannel.reveal] ?? 1;
  for (var (i, d) in vectorDrawn(shapes).indexed) {
    var box = vectorGroupBox(bounds, e, d);
    var owns =
        d.style.animation == null ? const <ShapeAnimationPart>{} : d.style.owns;
    var animation = animatedAs(e.animation, d.style.animation, owns);
    // How far in it is, and when it is all in: with no arrival on the
    // drawing, it is there from the start.
    var reveal = 1.0;
    int? arrived;
    var loopsOwn = owns.contains(ShapeAnimationPart.looping);
    if (arrival != null && times != null) {
      var (at, span) = arrival;
      var (start, length) = times[i];
      reveal = ((through * span - start) / length).clamp(0.0, 1.0);
      arrived = loopsOwn ? (at + start + length).round() : at + span;
    }
    // A loop of its own about its own box; the drawing's, where the drawing
    // is not looping as one, about the drawing's.
    var loop = loopsOwn
        ? animation.loop
        : (own ? e.animation.loop : const ElementLoop());
    void draw() => _paintGroupLooped(canvas, bounds, loopsOwn ? box : bounds, e,
        d, i, loop, frame, arrived, last);
    if (leaving) {
      paintArriving(
          canvas,
          owns.contains(ShapeAnimationPart.leaving) ? box : bounds,
          animation,
          pose,
          draw);
      continue;
    }
    if (!animation.on) {
      // Nothing to play coming in: there from its turn.
      if (reveal > 0) draw();
      continue;
    }
    paintArriving(
        canvas,
        box,
        animation,
        pose.copyWith(values: {...pose.values, KeyframeChannel.reveal: reveal}),
        draw);
  }
}

/// _paintGroupLooped draws one shape with [loop] about [box] and along its
/// outline, from [arrived] (when it came in) or the loop's start.
void _paintGroupLooped(
    ui.Canvas canvas,
    Rect bounds,
    Rect box,
    VectorElement e,
    VectorDrawn d,
    int index,
    ElementLoop loop,
    int frame,
    int? arrived,
    int last) {
  void plain() => paintVectorGroup(canvas, bounds, e, d);
  if (!loop.on) return plain();
  if (loop.preset.moves) {
    var swing = loop.poseAt(frame, arrived: arrived, last: last);
    if (swing == null) return plain();
    canvas.save();
    _applyLoopPose(canvas, box, swing);
    var faded = swing.opacity < 0.999;
    if (faded) {
      canvas.saveLayer(box.inflate(box.longestSide),
          Paint()..color = Color.fromRGBO(0, 0, 0, swing.opacity));
    }
    plain();
    if (faded) canvas.restore();
    canvas.restore();
    return;
  }
  var phase = loop.phaseAt(frame, arrived: arrived, last: last);
  if (phase == null) return plain();
  var p = e.placement(bounds, e.viewBox);
  var outline = d.outline.transform(Float64List.fromList([
    p.sx, 0, 0, 0, //
    0, p.sy, 0, 0, //
    0, 0, 1, 0, //
    p.dx, p.dy, 0, 1,
  ]));
  paintLoopEffect(canvas, box, loop, phase.$1, phase.$2,
      Object.hash(e.id, index), outline, plain);
}

/// _applyLoopPose moves, turns and sizes the canvas as [swing] says: shifted
/// by shares of [box], turned and sized about its pivot or [anchor] (shares
/// of [box]). Its fading is the caller's.
void _applyLoopPose(ui.Canvas canvas, Rect box, LoopPose swing,
    {Offset? anchor}) {
  canvas.translate(swing.dx * box.width, swing.dy * box.height);
  if (swing.turn != 0 || swing.sx != 1 || swing.sy != 1) {
    // About the element's anchor where it has been moved; otherwise where
    // the loop itself turns -- a swing hangs from its top.
    var at = anchor ?? swing.pivot;
    var pivot =
        Offset(box.left + box.width * at.dx, box.top + box.height * at.dy);
    canvas.translate(pivot.dx, pivot.dy);
    if (swing.turn != 0) canvas.rotate(swing.turn * math.pi / 180);
    if (swing.sx != 1 || swing.sy != 1) canvas.scale(swing.sx, swing.sy);
    canvas.translate(-pivot.dx, -pivot.dy);
  }
}

/// _animationOf is [element]'s arrival, exit and loop, or null (see animates).
ElementAnimation? _animationOf(CanvasElement element) => switch (element) {
      ShapeElement e => e.animation,
      ImageElement e => e.animation,
      VectorElement e => e.animation,
      LineElement e => e.animation,
      PathElement e => e.animation,
      TableElement e => e.animation,
      CounterElement e => e.animation,
      ButtonElement e => e.animation,
      AudioElement e => e.animation,
      VideoElement e => e.animation,
      Character3dElement e => e.animation,
      _ => null,
    };

/// _loopOutline is [element]'s drawn outline for loops that run along it (a
/// shape's, a drawing's shapes', a line's), or else its box.
Path _loopOutline(CanvasElement element, Rect bounds, int frame) {
  switch (element) {
    case ShapeElement e:
      var rect = bounds;
      if (e.shape.isRegular) {
        var side = rect.shortestSide;
        rect = Rect.fromCenter(center: rect.center, width: side, height: side);
      }
      return shapePath(e.shape, rect,
          points: e.points,
          inner: e.innerRatio,
          cornerRadius: e.cornerRadius,
          corners: e.corners,
          bubble: e.bubble);
    case VectorElement e when e.shapes != null:
      var p = e.placement(bounds, e.viewBox);
      var matrix = Float64List.fromList([
        p.sx, 0, 0, 0, //
        0, p.sy, 0, 0, //
        0, 0, 1, 0, //
        p.dx, p.dy, 0, 1,
      ]);
      var out = Path();
      for (var d in vectorDrawn(e.shapes!)) {
        out.addPath(d.outline.transform(matrix), Offset.zero);
      }
      return out;
    case LineElement e:
      var points = _curvePoints(lineWithPose(e, frame));
      if (points != null && points.length > 1) return _polyline(points);
    case PathElement e:
      var points = _curvePoints(e);
      if (points != null && points.length > 1) return _polyline(points);
    default:
      break;
  }
  return Path()..addRect(bounds);
}

Path _polyline(List<Offset> points) {
  var out = Path()..moveTo(points.first.dx, points.first.dy);
  for (var q in points.skip(1)) {
    out.lineTo(q.dx, q.dy);
  }
  return out;
}

/// _vectorArrival is a drawing's arrival start and length (_arrivalFrames).
(int, int)? _vectorArrival(VectorElement e, Keyframe pose) {
  var (from, to) = _arrivalFrames(e, pose);
  if (from == null || to == null || to <= from) return null;
  return (from, to - from);
}
