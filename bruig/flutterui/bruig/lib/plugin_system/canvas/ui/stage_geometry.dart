// stage_geometry.dart is how big the things you grab on the stage are, and
// what the eight of them are called.
//
// Small enough to look like it belongs at the top of canvas_stage.dart, and
// it was there. It is here because the painter and the hit-testing both need
// it and neither owns it: a handle drawn one size and hit-tested at another
// is a control that appears to be somewhere it is not, and the only way to be
// sure of that is for both halves to read the same numbers.
//
// All of these are screen pixels rather than document units. A handle has to
// stay the same size on screen at every zoom or it is unusable at one end of
// the range or the other.

/// handleSize is a resize handle's side, in screen pixels.
const double handleSize = 9;

/// handleHitSlop grows the target past what is drawn.
///
/// A 9px square is a fifth of a fingertip and a tenth of the distance most
/// people can hold a mouse still, and the whole target is on the edge of the
/// selection -- so half of what this buys is outside the element, where there
/// is nothing else to hit anyway. Undersized, the miss does not do nothing: it
/// falls through to the element underneath and *moves* it, which is the
/// reported "more often than not I end up moving the element".
const double handleHitSlop = 13;

/// strokeHitSlop is the same allowance for a *line*, and is deliberately not
/// the same number.
///
/// A handle can afford to be generous because it sits on the edge of the
/// selection with nothing else nearby. A line cannot: its tolerance decides
/// how much empty canvas beside it counts as "on the line", and too much of
/// that steals clicks meant for whatever is behind it. They were one constant
/// until widening the handles quietly widened this too.
const double strokeHitSlop = 7;

/// rotateHandleGap is how far above the selection the rotate ring sits.
const double rotateHandleGap = 26;

/// StageHandle names the eight resize grips and the rotate one.
enum StageHandle {
  topLeft,
  topCenter,
  topRight,
  centerLeft,
  centerRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
  rotate;

  bool get movesLeft =>
      this == topLeft || this == centerLeft || this == bottomLeft;
  bool get movesRight =>
      this == topRight || this == centerRight || this == bottomRight;
  bool get movesTop => this == topLeft || this == topCenter || this == topRight;
  bool get movesBottom =>
      this == bottomLeft || this == bottomCenter || this == bottomRight;
}
