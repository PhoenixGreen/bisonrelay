import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';

// canvas_snap.dart decides where a dragged element actually lands. Pure
// arithmetic, so it can be tested without a pointer: of everything on the
// element allowed to snap, whichever is nearest a line wins, if near enough.

/// SnapResult is where an element should go, and which lines it caught, so
/// the stage can draw them.
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
/// [within] is in document units: the caller converts
/// CanvasGuides.snapWithin, in screen pixels, through the zoom.
SnapResult snapTopLeft(
  Offset topLeft,
  Size size,
  CanvasGuides guides,
  Size canvas, {
  required double within,
  List<Rect> others = const [],
}) {
  if (!guides.snap || !guides.snapTo.any) return SnapResult(topLeft);
  var (vertical, horizontal) = guides.linesFor(canvas);
  var (theirX, theirY) = objectLines(others, guides);
  vertical = [...vertical, ...theirX];
  horizontal = [...horizontal, ...theirY];

  // A corner lies on two edges, so on one axis edges and vertices offer the
  // same points.
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

/// snapEdgeTo is the line one edge -- what a resize drags -- should land on,
/// or null. Only that edge is considered, so the opposite edge stays put.
double? snapEdgeTo(
  double edge,
  CanvasGuides guides,
  Size canvas, {
  required bool vertical,
  required double within,
  List<Rect> others = const [],
}) {
  if (!guides.snap || !guides.snapTo.any) return null;
  var (xs, ys) = guides.linesFor(canvas);
  var (theirX, theirY) = objectLines(others, guides);
  var lines = vertical ? [...xs, ...theirX] : [...ys, ...theirY];
  var found = _nearest([edge], lines, within);
  return found?.line;
}

/// objectLines is what the other elements on the canvas offer to land on:
/// their sides and their middles, down and across. What they offer follows
/// the same switches as what the moving element may land with: with centres
/// off, nothing lines up on a middle, theirs or its own.
(List<double>, List<double>) objectLines(
    List<Rect> others, CanvasGuides guides) {
  if (!guides.snapTo.objects || others.isEmpty) {
    return (const [], const []);
  }
  var sides = guides.snapTo.edges || guides.snapTo.vertices;
  var middles = guides.snapTo.centres;
  var xs = <double>[];
  var ys = <double>[];
  for (var other in others) {
    if (other.isEmpty) continue;
    if (sides) {
      xs.add(other.left);
      xs.add(other.right);
      ys.add(other.top);
      ys.add(other.bottom);
    }
    if (middles) {
      xs.add(other.center.dx);
      ys.add(other.center.dy);
    }
  }
  return (xs, ys);
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
/// Nearest wins rather than first: on a fine grid several lines are in
/// reach, and the first could jump past the one it was nearly touching.
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

/// gridLines is every line a grid draws, for painting it, as majors and
/// minors so the two can be drawn at different weights.
(List<double>, List<double>) gridLines(
    double extent, double size, int subdivisions) {
  var majors = <double>[];
  var minors = <double>[];
  if (size <= 0 || extent <= 0) return (majors, minors);

  var step = size / math.max(1, subdivisions);
  // Bounded, so a tiny grid on a large canvas cannot stall the frame.
  if (extent / step > 2000) return (majors, minors);

  for (var i = 0; i * step <= extent; i++) {
    var at = i * step;
    (i % math.max(1, subdivisions) == 0 ? majors : minors).add(at);
  }
  return (majors, minors);
}
