import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';

// canvas_snap.dart decides where a dragged thing actually lands. Pure
// arithmetic, so it can be tested without a pointer: of everything on the
// dragged thing allowed to snap, whichever is nearest a line wins, if near
// enough. A drag makes one Snapper as it begins and asks it at every step.

/// SnapLines is the lines a drag is caught on, so the stage can draw them:
/// an x for an upright line and a y for a level one, each null when
/// nothing is caught that way.
class SnapLines {
  final double? vertical;
  final double? horizontal;

  const SnapLines({this.vertical, this.horizontal});

  /// none is nothing caught.
  static const none = SnapLines();

  bool get caught => vertical != null || horizontal != null;

  @override
  bool operator ==(Object other) =>
      other is SnapLines &&
      other.vertical == vertical &&
      other.horizontal == horizontal;

  @override
  int get hashCode => Object.hash(vertical, horizontal);
}

/// Snap is one step of a drag snapped: [nudge] is how much further than
/// the pointer the dragged thing goes to land on [lines], zero when nothing
/// caught it.
typedef Snap = ({Offset nudge, SnapLines lines});

/// Snapper is what a drag can land on, worked out once as it begins: the
/// page's edges and middle, the grid while it is shown, the shown guides,
/// and, with Other elements on, the sides and middles of [others], the
/// boxes of what is not dragged. A guide dragged is [leaving]: its own last
/// place is always in reach of a small step and would hold it back.
///
/// Each question takes the reach for that step in document units, so a
/// zoom partway through a drag is felt at once: the stage works it out
/// from the guides' snapWithin, in screen pixels, and the zoom.
class Snapper {
  Snapper(this._guides, this._page,
      {List<Rect> others = const [], int? leaving})
      : _others = others,
        _leaving = leaving;

  final CanvasGuides _guides;
  final Size _page;
  final List<Rect> _others;
  final int? _leaving;

  bool get _on => _guides.snap && _guides.snapTo.any;

  /// _lines is every line, down and across: worked out at the first step
  /// that asks, and kept for the rest of the drag.
  late final (List<double>, List<double>) _lines = _allLines();

  /// move is a box moved to [box] snapped: one of its sides or its middle,
  /// as the switches allow, on the nearest line in [reach] on each axis.
  Snap move(Rect box, {required double reach}) {
    if (!_on) return (nudge: Offset.zero, lines: SnapLines.none);
    var to = _guides.snapTo;
    var xs = <double>[
      if (to.edges) box.left,
      if (to.edges) box.right,
      if (to.centres) box.center.dx,
    ];
    var ys = <double>[
      if (to.edges) box.top,
      if (to.edges) box.bottom,
      if (to.centres) box.center.dy,
    ];
    var (vertical, horizontal) = _lines;
    var x = _nearest(xs, vertical, reach);
    var y = _nearest(ys, horizontal, reach);
    return (
      nudge: Offset(x?.shift ?? 0, y?.shift ?? 0),
      lines: SnapLines(vertical: x?.line, horizontal: y?.line),
    );
  }

  /// edges is a box being resized, now [box], snapped by the sides dragged
  /// alone, so the sides held stay put: a dragged side on the nearest line
  /// in [reach], down and across.
  Snap edges(Rect box,
      {bool left = false,
      bool top = false,
      bool right = false,
      bool bottom = false,
      required double reach}) {
    if (!_on) return (nudge: Offset.zero, lines: SnapLines.none);
    var (vertical, horizontal) = _lines;
    var x = left || right
        ? _nearest([left ? box.left : box.right], vertical, reach)
        : null;
    var y = top || bottom
        ? _nearest([top ? box.top : box.bottom], horizontal, reach)
        : null;
    return (
      nudge: Offset(x?.shift ?? 0, y?.shift ?? 0),
      lines: SnapLines(vertical: x?.line, horizontal: y?.line),
    );
  }

  /// line is where a line running along [axis], dragged to [at], lands: on
  /// the nearest line in [reach] that way, or at [at].
  double line(GuideAxis axis, double at, {required double reach}) {
    if (!_on) return at;
    var (vertical, horizontal) = _lines;
    var lines = axis == GuideAxis.vertical ? vertical : horizontal;
    return _nearest([at], lines, reach)?.line ?? at;
  }

  (List<double>, List<double>) _allLines() {
    var vertical = <double>[0, _page.width / 2, _page.width];
    var horizontal = <double>[0, _page.height / 2, _page.height];
    var guides = _guides;
    // The grid's lines as the painter draws them, so a grid too fine to
    // draw is not snapped to either.
    if (guides.showGrid) {
      for (var (lines, extent) in [
        (vertical, _page.width),
        (horizontal, _page.height)
      ]) {
        var (majors, minors) =
            gridLines(extent, guides.gridSize, guides.subdivisions);
        lines
          ..addAll(majors)
          ..addAll(minors);
      }
    }
    if (guides.showGuides) {
      for (var (i, guide) in guides.guides.indexed) {
        if (i == _leaving) continue;
        (guide.axis == GuideAxis.vertical ? vertical : horizontal)
            .add(guide.at);
      }
    }
    _addTheirs(vertical, horizontal);
    return (vertical, horizontal);
  }

  /// _addTheirs adds what the other elements offer to land on: their sides
  /// and their middles, down and across. What they offer follows the same
  /// switches as what the dragged box may land with: with centres off,
  /// nothing lines up on a middle, theirs or its own.
  void _addTheirs(List<double> xs, List<double> ys) {
    var to = _guides.snapTo;
    if (!to.objects) return;
    for (var other in _others) {
      if (other.isEmpty) continue;
      if (to.edges) {
        xs.add(other.left);
        xs.add(other.right);
        ys.add(other.top);
        ys.add(other.bottom);
      }
      if (to.centres) {
        xs.add(other.center.dx);
        ys.add(other.center.dy);
      }
    }
  }
}

/// _Catch is one snap: the line caught, and how far the element has to move.
class _Catch {
  final double line;
  final double shift;
  const _Catch(this.line, this.shift);
}

/// _nearest is the closest pairing of anything on the element with anything
/// on the canvas, if near enough. Nearest wins rather than first: on a fine
/// grid several lines are in reach, and the first could jump past the one
/// it was nearly touching.
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
