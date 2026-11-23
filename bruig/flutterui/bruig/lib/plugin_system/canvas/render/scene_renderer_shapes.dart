part of 'scene_renderer.dart';

// Shapes, lines and paths, and where a line's or a path's curve is on the
// page (curveOfElement), which the selection box, the press, text riding it
// and Follow path all ask. Part of scene_renderer.dart.

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
    var drawn = strokeOnPage(element, frame, doc, live);
    var box = _boundsOfPoints(drawn?.curve);
    if (drawn == null || box == null) return moved();
    // Room for the stroke, centred on the curve, and for the ends it draws
    // (LineEnd.reach), both as wide as the pose draws them.
    var stroke = element.drawnStroke;
    return box.inflate(math.max(stroke.strokeWidth, 1) *
        drawn.place.stretch *
        math.max(stroke.endReach, 1.5));
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

/// StrokeOnPage is a line or a path as paintElement draws it on a frame:
/// [shaped] by its pose (a line bowed as the pose keys it), its box laid on
/// the page by [place], and its curve there, as points along it, [curve].
typedef StrokeOnPage = ({
  StrokedElement shaped,
  ElementPlace place,
  List<Offset> curve,
});

/// strokeOnPage is where [element]'s stroke is drawn on [frame] of [doc]:
/// with everything that moves it then (its keys, clips and devices, about
/// its anchor, through its turn and slant), or as it rests with no frame
/// given. Null for anything not a stroke, or a stroke with no curve. The
/// selection box, the press, text set on a line and Follow path all ask it,
/// and the painter lays the element out by the same ElementPlace, so they
/// cannot part.
StrokeOnPage? strokeOnPage(CanvasElement? element,
    [int? frame, CanvasDocument? doc, LiveMotion? live]) {
  if (element is! StrokedElement) return null;
  // The stage asks at every move of the pointer and every paint, of the
  // same document on the same frame: kept for the stroke, the document and
  // the frame. Not while slots play, nor for a stroke following a sound,
  // which is read from outside the document; and only an answer asked from
  // outside any pose, which the guard below has not cut short.
  var keeps = live == null &&
      _riding == 0 &&
      !element.base.motion.devices
          .any((d) => d.kind == MotionDeviceKind.followSound);
  if (keeps) {
    if (_strokesKept[element] case (var d, var f, var known)
        when identical(d, doc) && f == frame) {
      return known;
    }
  }
  var drawn = _strokeOnPage(element, frame, doc, live);
  if (keeps) _strokesKept[element] = (doc, frame, drawn);
  return drawn;
}

/// _strokesKept is each stroke's last answer from strokeOnPage, with the
/// document and frame it was for.
final Expando<(CanvasDocument?, int?, StrokeOnPage?)> _strokesKept =
    Expando("strokeOnPage");

StrokeOnPage? _strokeOnPage(
    StrokedElement element, int? frame, CanvasDocument? doc, LiveMotion? live) {
  Keyframe pose;
  if (frame == null) {
    pose = Keyframe.rest;
  } else if (_riding > 3) {
    // A stroke posed by something that rides it in turn (a path following
    // what follows it, a line turned to face the text on it) is asked again
    // from inside its own pose: past a few rounds, its keys alone answer.
    pose = element.poseAt(frame);
  } else {
    _riding++;
    try {
      pose = element.drawnPoseAt(frame, doc, live: live);
    } finally {
      _riding--;
    }
  }
  var shaped = element.bowedBy(pose);
  var place = element.placedBy(pose);
  var curve = shaped.curvePlaced(place);
  if (curve.isEmpty) return null;
  return (shaped: shaped, place: place, curve: curve);
}

/// _riding is how deep strokeOnPage is in asking poses: see there.
var _riding = 0;

/// curveOfElement is [strokeOnPage]'s curve: where [element]'s curve is
/// drawn on the page on [frame], as points along it.
List<Offset>? curveOfElement(CanvasElement? element,
        [int? frame, CanvasDocument? doc, LiveMotion? live]) =>
    strokeOnPage(element, frame, doc, live)?.curve;

/// curveUnderText is the line a text element is riding, in document space.
List<Offset>? curveUnderText(TextElement e, CanvasDocument? doc, int frame) =>
    _curveFor(e, doc, frame);

/// _curveFor is the line text [e] rides, as document-space points, or null
/// where its words are not set on a line (TextElement.wordsSetIn). Found by
/// id, so the text follows it; if deleted, the text uses its box. Where the
/// line is drawn on [frame], however it moves there, by what plays on the
/// timeline and not from slots, so the text's painter, selection box and
/// press, which have no slots to hand alike, agree.
List<Offset>? _curveFor(TextElement e, CanvasDocument? doc, int frame) {
  if (e.wordsSetIn(doc) != WordsSet.onLine) return null;
  return curveOfElement(doc!.elementById(e.curve!.elementId), frame, doc);
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

/// _paintStroked draws a line's or a path's stroke along its curve, in its
/// box: the canvas is already turned and slanted as it is (paintElement). A
/// guide path (PathElement.guide) is scaffolding: drawn only while
/// [editing], never in anything published.
void _paintStroked(ui.Canvas canvas, StrokedElement e, bool editing) {
  if (e is PathElement && e.guide && !editing) return;
  paintStroke(canvas, e.curve, e.drawnStroke);
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
