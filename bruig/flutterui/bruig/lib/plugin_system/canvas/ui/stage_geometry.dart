import 'dart:math' as math;

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

/// rulerThickness is how deep a ruler strip is, in screen pixels.
///
/// Shared, because the painter draws the strip and the stage hit-tests it: a
/// ruler you can see and cannot drag out of, or drag out of where nothing is
/// drawn, is the same bug twice.
const double rulerThickness = 18;

/// guideGrabSlop is how near a guide the pointer has to be to take hold of it.
///
/// Tight, and deliberately tighter than a handle's. A guide is drawn as a
/// hairline over the design, and everything underneath it is something the
/// reader might have been aiming at instead -- so the line has to be nearly
/// hit rather than merely approached.
const double guideGrabSlop = 4;

/// rulerStep picks the gap between numbered ticks so they land on round
/// numbers and stay about [wanted] pixels apart on screen.
///
/// The same "nice numbers" walk a chart's axis uses, and for the same reason:
/// a ruler ticking every 37 units is a ruler nobody can read a position off.
double rulerStep(double scale, {double wanted = 80}) {
  if (!scale.isFinite || scale <= 0) return 100;
  var rough = wanted / scale;
  var magnitude =
      math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
  var norm = rough / magnitude;
  var step = norm <= 1
      ? 1
      : norm <= 2
          ? 2
          : norm <= 5
              ? 5
              : 10;
  return step * magnitude;
}
