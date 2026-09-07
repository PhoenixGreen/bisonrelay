import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';

// canvas_snap.dart decides where a dragged element actually lands.
//
// Pure arithmetic, deliberately: what makes snapping feel right or wrong is
// entirely in these few rules, and they are far easier to be sure of against a
// handful of numbers than against a pointer. The stage does the dragging; this
// says where the drag ends up.
//
// The rule in one sentence: of everything on the element that is allowed to
// snap, whichever is nearest a line wins, and only if it is near enough.

/// SnapResult is where an element should go, and which lines it caught.
///
/// The lines come back so they can be drawn. A snap nobody can see is a
/// mysterious jump; the line lighting up as an edge lands on it is the whole
/// of the feedback.
class SnapResult {
  final Offset at;
  final double? onVertical;
  final double? onHorizontal;

  const SnapResult(this.at, {this.onVertical, this.onHorizontal});

  bool get caught => onVertical != null || onHorizontal != null;
}

/// snapTopLeft nudges a moving element's top-left so that one of its own
/// interesting points lands on a line.
///
/// [within] is in document units -- the caller converts the reader's
/// screen-pixel allowance through the zoom, so that snapping feels the same
/// distance away however far in the canvas is.
SnapResult snapTopLeft(
  Offset topLeft,
  Size size,
  CanvasGuides guides,
  Size canvas, {
  required double within,
}) {
  if (!guides.snap || !guides.snapTo.any) return SnapResult(topLeft);
  var (vertical, horizontal) = guides.linesFor(canvas);

  // What on the element is allowed to land on a line. An edge and a vertex are
  // the same x -- a corner is where two edges meet -- so the two switches only
  // differ in the axis they contribute, and asking for both is not asking
  // twice.
  var xs = <double>[
    if (guides.snapTo.edges || guides.snapTo.vertices) topLeft.dx,
    if (guides.snapTo.edges || guides.snapTo.vertices) topLeft.dx + size.width,
    if (guides.snapTo.centres) topLeft.dx + size.width / 2,
  ];
  var ys = <double>[
    if (guides.snapTo.edges || guides.snapTo.vertices) topLeft.dy,
    if (guides.snapTo.edges || guides.snapTo.vertices) topLeft.dy + size.height,
    if (guides.snapTo.centres) topLeft.dy + size.height / 2,
  ];

  var x = _nearest(xs, vertical, within);
  var y = _nearest(ys, horizontal, within);

  return SnapResult(
    Offset(topLeft.dx + (x?.shift ?? 0), topLeft.dy + (y?.shift ?? 0)),
    onVertical: x?.line,
    onHorizontal: y?.line,
  );
}

/// snapEdge nudges one edge -- what a resize drags -- onto a line.
///
/// Its own function rather than a flag on the one above, because a resize
/// moves one side and leaves the other where it is: the whole point is that
/// the opposite edge must not be dragged along by a snap meant for this one.
double? snapEdgeTo(
  double edge,
  CanvasGuides guides,
  Size canvas, {
  required bool vertical,
  required double within,
}) {
  if (!guides.snap || !guides.snapTo.any) return null;
  var (xs, ys) = guides.linesFor(canvas);
  var found = _nearest([edge], vertical ? xs : ys, within);
  return found?.line;
}

/// _Catch is one snap: the line caught, and how far the element has to move.
class _Catch {
  final double line;
  final double shift;
  const _Catch(this.line, this.shift);
}

/// _nearest is the closest pairing of anything on the element with anything on
/// the canvas, if one of them is near enough.
///
/// Nearest wins rather than first, and that matters where lines are close
/// together: on a fine grid an element is always within reach of several, and
/// taking the first would make it jump backwards past the one it was nearly
/// touching.
_Catch? _nearest(List<double> points, List<double> lines, double within) {
  _Catch? best;
  var closest = within;
  for (var point in points) {
    for (var line in lines) {
      var gap = (line - point).abs();
      if (gap > closest) continue;
      closest = gap;
      best = _Catch(line, line - point);
    }
  }
  return best;
}

/// gridLines is every line a grid draws, for painting it.
///
/// Returned as majors and minors so the two can be drawn differently: the
/// strong lines are for counting and the faint ones are for landing on, and a
/// grid drawn all one weight is a grid nobody can count.
(List<double>, List<double>) gridLines(
    double extent, double size, int subdivisions) {
  var majors = <double>[];
  var minors = <double>[];
  if (size <= 0 || extent <= 0) return (majors, minors);

  var step = size / math.max(1, subdivisions);
  // Bounded, so a grid of one document unit on a four-thousand-pixel canvas
  // cannot ask for four thousand lines and take the frame with it.
  if (extent / step > 2000) return (majors, minors);

  for (var i = 0; i * step <= extent; i++) {
    var at = i * step;
    (i % math.max(1, subdivisions) == 0 ? majors : minors).add(at);
  }
  return (majors, minors);
}
