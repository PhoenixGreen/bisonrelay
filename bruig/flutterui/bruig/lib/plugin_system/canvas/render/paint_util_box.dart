part of 'paint_util.dart';

// A box drawn round or behind an element: its fill (a colour, a picture or a
// pattern) and its border, even or side by side, rounded and inset as its
// BoxSpec says. Part of paint_util.dart.

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
