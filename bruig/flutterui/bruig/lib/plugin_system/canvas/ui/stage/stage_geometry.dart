import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';

// stage_geometry.dart is how big the things grabbed on the stage are, and the
// names of the handles. Shared so the painter and the hit-testing read the same
// numbers: a handle drawn at one size and hit-tested at another is somewhere
// it appears not to be. All are screen pixels, so handles keep their size at
// every zoom.

/// handleSize is a resize handle's side, in screen pixels.
const double handleSize = 9;

/// handleHitSlop grows the target past what is drawn (a 9px square is a fifth
/// of a fingertip). Kept modest: a press moves nothing until it has travelled
/// (CanvasStageState._dragThreshold), so a miss costs only a click, while a
/// larger slop steals presses meant for elements a few pixels away.
const double handleHitSlop = 6;

/// strokeHitSlop is the same allowance for a line, kept separate: it decides
/// how much empty canvas beside a line counts as on it, and too much steals
/// clicks meant for what is behind.
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

/// flowGripSize is how big a text box's flow grips are drawn: smaller than a
/// resize grip, which is reached for more often and sits on the same outline.
const double flowGripSize = 4;

/// flowGripHitSlop grows a flow grip's target past what is drawn, as
/// handleHitSlop does, but less: its neighbour is a resize handle, which is
/// the one being reached for.
const double flowGripHitSlop = 8;

/// TextFlowGrips is what a selected text box shows about its overflow: where
/// the two dots are, and what they have to say.
class TextFlowGrips {
  /// inAt is the incoming dot, which says whether words arrive from another box;
  /// outAt is the outgoing one, dragged to send them on. Each sits half way
  /// between two resize handles (top-left and middle-left; middle-right and
  /// bottom-right), away from the corners.
  final Offset inAt;
  final Offset outAt;

  /// overflowing is whether there are words this box is not showing, which
  /// makes the out grip red so hidden text is never silent.
  final bool overflowing;

  /// receiving is whether something flows into this box, and linked whether
  /// it flows out of it.
  final bool receiving;
  final bool linked;

  const TextFlowGrips({
    required this.inAt,
    required this.outAt,
    this.overflowing = false,
    this.receiving = false,
    this.linked = false,
  });

  // By value: made again each build, the same grips must not repaint.
  @override
  bool operator ==(Object other) =>
      other is TextFlowGrips &&
      other.inAt == inAt &&
      other.outAt == outAt &&
      other.overflowing == overflowing &&
      other.receiving == receiving &&
      other.linked == linked;

  @override
  int get hashCode => Object.hash(inAt, outAt, overflowing, receiving, linked);
}

/// FlowLine is one link between two text boxes, as drawn. Its own thing
/// rather than part of a box's grips, because either end's box being selected
/// (or kept in sight) is reason to draw it.
class FlowLine {
  final Offset from;
  final Offset to;

  /// overflowing is whether the box the words leave has more than it can show,
  /// which draws the line red.
  final bool overflowing;

  const FlowLine(this.from, this.to, {this.overflowing = false});

  @override
  bool operator ==(Object other) =>
      other is FlowLine &&
      other.from == from &&
      other.to == to &&
      other.overflowing == overflowing;

  @override
  int get hashCode => Object.hash(from, to, overflowing);
}

/// rulerThickness is how deep a ruler strip is, in screen pixels, shared by
/// the painter and the stage's hit-testing.
const double rulerThickness = 18;

/// guideGrabSlop is how near a guide the pointer has to be to take hold of
/// it: tighter than a handle's, since a hairline guide lies over things the
/// reader may be aiming at instead.
const double guideGrabSlop = 4;

/// rulerStep picks the gap between numbered ticks: always a whole multiple of
/// [every] (the grid's spacing), so each number has a grid line under it, and
/// the smallest of 1, 2, 5, 10 ... multiples that leaves the numbers about
/// [wanted] pixels apart at this zoom.
double rulerStep(double scale, double every, {double wanted = 80}) {
  if (!every.isFinite || every <= 0) every = 100;
  if (!scale.isFinite || scale <= 0) return every;

  var want = wanted / scale / every;
  if (want <= 1) return every;

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

/// RulerBands is where the four strips are drawn and hit-tested; null for an
/// edge that is switched off.
class RulerBands {
  final Rect? top;
  final Rect? left;
  final Rect? right;
  final Rect? bottom;

  const RulerBands({this.top, this.left, this.right, this.bottom});

  bool get any =>
      top != null || left != null || right != null || bottom != null;

  /// axisAt is the guide a press at [at] would make, or null off the rulers:
  /// side strips make upright lines, top and bottom ones level lines.
  GuideAxis? axisAt(Offset at) {
    if (left?.contains(at) ?? false) return GuideAxis.vertical;
    if (right?.contains(at) ?? false) return GuideAxis.vertical;
    if (top?.contains(at) ?? false) return GuideAxis.horizontal;
    if (bottom?.contains(at) ?? false) return GuideAxis.horizontal;
    return null;
  }
}

/// rulerBandsFor lays the strips against the edges of the page, not the
/// window, so the ruler sits beside what it measures whatever the window
/// size. Clamped inside the viewport, for a page zoomed to fill it.
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
