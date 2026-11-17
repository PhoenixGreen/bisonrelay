import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';

// stage_geometry.dart is the sizes of what is grabbed on the stage and the
// names of the handles, shared so the painter and the hit-testing agree. All
// are screen pixels, so handles keep their size at every zoom.

/// handleSize is a resize handle's side.
const double handleSize = 9;

/// handleHitSlop grows the target past what is drawn. Kept modest: a press
/// moves nothing until it has travelled (CanvasStageState._dragThreshold), so
/// a miss costs only a click, while a larger slop steals presses meant for
/// elements nearby.
const double handleHitSlop = 6;

/// strokeHitSlop is how much empty canvas beside a line counts as on it; too
/// much steals clicks meant for what is behind.
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

/// flowGripSize is a text box's flow grip size: smaller than a resize grip,
/// which is reached for more often and sits on the same outline.
const double flowGripSize = 4;

/// flowGripHitSlop grows a flow grip's target past what is drawn, as
/// handleHitSlop does for a resize handle.
const double flowGripHitSlop = 8;

/// TextFlowGrips is what a selected text box shows about its overflow.
class TextFlowGrips {
  /// inAt is the incoming dot; outAt the outgoing one, dragged to send words
  /// on. Each sits half way between two resize handles, off the corners.
  final Offset inAt;
  final Offset outAt;

  /// overflowing is whether this box hides words, which turns the out grip
  /// red so hidden text is never silent.
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

/// FlowLine is one drawn link between two text boxes. Not part of a box's
/// grips: either end's box being selected is reason to draw it.
class FlowLine {
  final Offset from;
  final Offset to;

  /// overflowing is whether the box the words leave overflows, which draws
  /// the line red.
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

/// rulerThickness is how deep a ruler strip is.
const double rulerThickness = 18;

/// guideGrabSlop is how near a guide a press must be to take it: tighter
/// than a handle's, since a guide lies over things that may be aimed at.
const double guideGrabSlop = 4;

/// rulerStep picks the gap between numbered ticks: the smallest 1, 2, 5, 10
/// ... multiple of [every] (the grid's spacing, so each number has a grid
/// line under it) that leaves numbers about [wanted] pixels apart.
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

/// rulerBandsFor lays the strips against the page's edges, not the window's,
/// so the ruler sits beside what it measures; clamped inside the viewport
/// for a page zoomed to fill it.
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
