import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';

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

/// flowGripGap is how far in from the corner a text box's flow grips sit.
///
/// Inside the corner rather than on it, because the corner is a resize grip
/// and the two must never be aimed at with the same click. Below the top-left
/// one and above the bottom-right one, which is where the words start and
/// where they run out.
const double flowGripGap = 18;

/// TextFlowGrips is what a selected text box shows about its overflow: where
/// the two dots are, and what they have to say.
class TextFlowGrips {
  /// inAt is the dot below the top-left corner, which says whether words are
  /// arriving from another box. outAt is the one above the bottom-right,
  /// which is dragged to send them on.
  final Offset inAt;
  final Offset outAt;

  /// overflowing is whether there are words this box is not showing, which is
  /// what makes the out grip red. Hidden text with nothing saying it is
  /// hidden is the thing people lose work to.
  final bool overflowing;

  /// receiving is whether something flows into this box, and linked whether
  /// it flows out of it.
  final bool receiving;
  final bool linked;

  /// to is where the link lands, for the line drawn between the two boxes.
  final Offset? to;

  const TextFlowGrips({
    required this.inAt,
    required this.outAt,
    this.overflowing = false,
    this.receiving = false,
    this.linked = false,
    this.to,
  });
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

/// rulerStep picks the gap between numbered ticks.
///
/// Always a whole multiple of [every] -- the grid's own spacing -- so that
/// every number on the ruler has a grid line under it. A ruler and a grid
/// that disagree are two rulers, and reading a position off one of them then
/// means counting squares on the other.
///
/// Which multiple is decided by the zoom: the smallest of one, two, five, ten
/// and so on that leaves the numbers about [wanted] pixels apart, so a fine
/// grid on a canvas zoomed out is numbered every tenth line rather than every
/// line.
double rulerStep(double scale, double every, {double wanted = 80}) {
  if (!every.isFinite || every <= 0) every = 100;
  if (!scale.isFinite || scale <= 0) return every;

  var want = wanted / scale / every;
  if (want <= 1) return every;

  // One, two, five, ten, twenty ... of the grid, which is how anybody counts
  // squares.
  var magnitude = math.pow(10, (math.log(want) / math.ln10).floor()).toDouble();
  var norm = want / magnitude;
  var step = norm <= 1
      ? 1
      : norm <= 2
          ? 2
          : norm <= 5
              ? 5
              : 10;
  return every * step * magnitude;
}

/// RulerBands is where the four strips are drawn, and hit-tested.
///
/// Nullable rather than a flag apiece: an edge that is switched off has no
/// band, and everything that reads this cares about the rectangle rather than
/// the switch.
class RulerBands {
  final Rect? top;
  final Rect? left;
  final Rect? right;
  final Rect? bottom;

  const RulerBands({this.top, this.left, this.right, this.bottom});

  bool get any =>
      top != null || left != null || right != null || bottom != null;

  /// axisAt is the guide a press at [at] would make, or null for anywhere
  /// that is not a ruler. The side strips make upright lines and the top and
  /// bottom ones make level lines, which is what every editor with rulers
  /// does.
  GuideAxis? axisAt(Offset at) {
    if (left?.contains(at) ?? false) return GuideAxis.vertical;
    if (right?.contains(at) ?? false) return GuideAxis.vertical;
    if (top?.contains(at) ?? false) return GuideAxis.horizontal;
    if (bottom?.contains(at) ?? false) return GuideAxis.horizontal;
    return null;
  }
}

/// rulerBandsFor lays the strips against the edges of the *page* rather than
/// the edges of the window.
///
/// Which is what makes the numbers mean anything: the ruler is measuring the
/// canvas, so it belongs beside the canvas, at the same place whatever the
/// size of the window and whatever export width is set. Drawn out at the
/// window's edges, as they first were, the strips sat an inch away from the
/// thing they were numbering and moved whenever the window was resized.
///
/// Clamped back inside the viewport, because a page zoomed to fill the window
/// leaves nothing outside it to draw in and a ruler off the screen is no
/// ruler at all.
RulerBands rulerBandsFor(Rect page, Size viewport, CanvasRulers rulers) {
  const t = rulerThickness;
  double x0 = page.left.clamp(0.0, math.max(0.0, viewport.width));
  double x1 = page.right.clamp(0.0, math.max(0.0, viewport.width));
  double y0 = page.top.clamp(0.0, math.max(0.0, viewport.height));
  double y1 = page.bottom.clamp(0.0, math.max(0.0, viewport.height));

  double down(double at) =>
      at.clamp(0.0, math.max(0.0, viewport.height - t)).toDouble();
  double across(double at) =>
      at.clamp(0.0, math.max(0.0, viewport.width - t)).toDouble();

  return RulerBands(
    top: rulers.top
        ? Rect.fromLTWH(x0, down(page.top - t), math.max(0.0, x1 - x0), t)
        : null,
    bottom: rulers.bottom
        ? Rect.fromLTWH(x0, down(page.bottom), math.max(0.0, x1 - x0), t)
        : null,
    left: rulers.left
        ? Rect.fromLTWH(across(page.left - t), y0, t, math.max(0.0, y1 - y0))
        : null,
    right: rulers.right
        ? Rect.fromLTWH(across(page.right), y0, t, math.max(0.0, y1 - y0))
        : null,
  );
}
