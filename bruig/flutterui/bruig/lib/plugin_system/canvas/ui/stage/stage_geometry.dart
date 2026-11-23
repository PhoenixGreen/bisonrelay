import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:flutter/painting.dart';

// stage_geometry.dart is the sizes and places of what is grabbed on the
// stage, the names of the handles, and the steps a turn takes with Shift,
// shared so the painter and the hit-testing agree. Sizes are screen pixels,
// so handles keep their size at every zoom.

/// handleSize is a resize handle's side.
const double handleSize = 9;

/// handleHitSlop grows the target past what is drawn. Kept modest: a press
/// moves nothing until it has travelled (CanvasStageState._dragThreshold), so
/// a miss costs only a click, while a larger slop steals presses meant for
/// elements nearby.
const double handleHitSlop = 6;

/// handleReach is how near, in screen pixels, a press must be to a handle
/// [size] across to take it: half the handle, and the slop past it.
double handleReach([double size = handleSize]) => size / 2 + handleHitSlop;

/// strokeHitSlop is how much empty canvas beside a line counts as on it; too
/// much steals clicks meant for what is behind.
const double strokeHitSlop = 7;

/// rotateHandleGap is how far above the selection the rotate ring sits.
const double rotateHandleGap = 26;

/// shapeTurnReach is how far above a shape's box its turn handle sits.
const double shapeTurnReach = 22;

/// shapeTurnKnob is where the turn handle of a box whose top middle is at
/// [top] sits, both on screen.
Offset shapeTurnKnob(Offset top) => top - const Offset(0, shapeTurnReach);

/// anchorReach is how long each arm of an anchor's cross is drawn, and so
/// how near it a press takes the anchor.
const double anchorReach = 10;

/// tableColumnGrips is where the two grips of a table's column rule are
/// drawn, for a rule from [top] to [bottom], all on screen: a short bar
/// just inside each end.
List<Rect> tableColumnGrips(Offset top, Offset bottom) => [
      Rect.fromCenter(center: top + const Offset(0, 5), width: 4, height: 12),
      Rect.fromCenter(
          center: bottom - const Offset(0, 5), width: 4, height: 12),
    ];

/// turnStepDegrees is the step a turn takes with Shift held.
const double turnStepDegrees = 15;

/// steppedTurn is [angle] put on the nearest turn step: degrees, or
/// [radians].
double steppedTurn(double angle, {bool radians = false}) {
  var step = radians ? turnStepDegrees * math.pi / 180 : turnStepDegrees;
  return (angle / step).round() * step;
}

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

/// stageHandleAt is where [handle] of the selection box [bounds] (document
/// units), laid out by [frame] about its middle, is drawn and taken, in
/// stage space: [scale] stage pixels to a unit, the document's top-left at
/// [origin]. The painter and the hit test both ask this.
Offset stageHandleAt(StageHandle handle, Rect bounds, BoxFrame frame,
    {required double scale, required Offset origin}) {
  var centre = bounds.center * scale + origin;
  var half = Offset(bounds.width, bounds.height) * scale / 2;

  var local = switch (handle) {
    StageHandle.topLeft => Offset(-half.dx, -half.dy),
    StageHandle.topCenter => Offset(0, -half.dy),
    StageHandle.topRight => Offset(half.dx, -half.dy),
    StageHandle.centerLeft => Offset(-half.dx, 0),
    StageHandle.centerRight => Offset(half.dx, 0),
    StageHandle.bottomLeft => Offset(-half.dx, half.dy),
    StageHandle.bottomCenter => Offset(0, half.dy),
    StageHandle.bottomRight => Offset(half.dx, half.dy),
    StageHandle.rotate => Offset(0, -half.dy - rotateHandleGap),
  };
  return centre + frame.apply(local);
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

/// guideGrabSlop is how near a guide a press must be to take it: tighter
/// than a handle's, since a guide lies over things that may be aimed at.
const double guideGrabSlop = 4;

/// cameraTab is where [cam]'s name tab is on the page: in the top-left of
/// [frame], a fixed size on screen at any [scale]. Shared by painter and
/// stage so drawing and hit-testing agree.
Rect cameraTab(CameraElement cam, Rect frame, double scale) {
  var label = TextPainter(
    text: TextSpan(
        text: cam.name,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
    textDirection: TextDirection.ltr,
  )..layout();
  var w = math.min(label.width + 26, 220.0) / scale;
  var h = 20 / scale;
  var inset = 4 / scale;
  return Rect.fromLTWH(frame.left + inset, frame.top + inset,
      math.min(w, frame.width - inset * 2), math.min(h, frame.height / 3));
}
