import 'dart:math' as math;

import 'package:bruig/components/paint_spec.dart';
import 'package:flutter/material.dart';

// area_gradient.dart converts between how an area stores its gradient and the
// PaintSpec the app's colour picker speaks.
//
// The two are not the same shape and neither is wrong. An AreaStyle keeps a
// list of colours with a list of stops and a begin/end Alignment, because a
// BoxDecoration wants exactly that and because each colour carries a live
// binding to a palette slot beside it (see AreaStyle.gradientColorIndexes) --
// something a PaintSpec has no idea about. A PaintSpec keeps a first colour
// and a ramp with a compass angle, because that is what one picker can edit
// and every other gradient in the app is already written in.
//
// So they are converted at the edge rather than one of them being made to be
// the other.

/// areaPaintOf is the picker's view of an area's gradient.
///
/// An area with fewer than two colours has nothing to fade, so it comes back
/// as the one flat colour the picker will then offer to fade.
PaintSpec areaPaintOf(
  List<Color> colours,
  List<double>? stops,
  Alignment begin,
  Alignment end, {
  bool radial = false,
}) {
  if (colours.isEmpty) return const PaintSpec(Color(0xFF000000));
  if (colours.length < 2) return PaintSpec(colours.first);
  double at(int i) {
    if (stops != null && i < stops.length) return stops[i];
    // Spread evenly, which is what a BoxDecoration does with no stops.
    return colours.length == 1 ? 0 : i / (colours.length - 1);
  }

  return PaintSpec(
    colours.first,
    gradient: GradientSpec(
      start: at(0),
      to: colours[1],
      end: at(1),
      more: [
        for (var i = 2; i < colours.length; i++)
          GradientStop(colours[i], at(i)),
      ],
      angle: areaAngleOf(begin, end),
      radial: radial,
    ),
  );
}

/// areaGradientOf is the other direction: what an area should store to paint
/// what the picker was showing.
///
/// A flat colour comes back as that colour twice. An area in gradient mode
/// with one colour has nothing to paint, and the mode is the editor's to
/// change, not this function's.
({
  List<Color> colours,
  List<double> stops,
  Alignment begin,
  Alignment end,
  bool radial,
}) areaGradientOf(PaintSpec paint) {
  var g = paint.gradient;
  if (g == null) {
    return (
      colours: [paint.color, paint.color],
      stops: const [0.0, 1.0],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      radial: false,
    );
  }
  var (b, e) = areaEndsOf(g.angle);
  return (
    colours: [paint.color, for (var stop in g.ramp) stop.color],
    stops: g.positions,
    begin: b,
    end: e,
    radial: g.radial,
  );
}

/// areaEndsOf turns a compass angle into the begin/end pair a BoxDecoration
/// wants: 0 runs upwards, 90 to the right.
///
/// Corner to corner, so a gradient set to 135 runs top-left to bottom-right
/// the way the old four-way dropdown's "Top-left -> Bottom-right" did.
(Alignment, Alignment) areaEndsOf(double angle) {
  var radians = angle * math.pi / 180;
  var dx = math.sin(radians);
  // Screen coordinates have y going down and the angle is read off a compass,
  // so up is -y -- the same convention every other direction in the app uses.
  var dy = -math.cos(radians);
  // Scaled so the longer of the two reaches the edge: an Alignment runs -1 to
  // 1, and a gradient at 30 degrees that only reached 0.5 across would fade
  // out inside the area instead of at its edge.
  var longest = math.max(dx.abs(), dy.abs());
  if (longest == 0) return (Alignment.topCenter, Alignment.bottomCenter);
  // Snapped, because sin(135 degrees) divided by itself is not quite 1 and an
  // Alignment of -0.9999999999999999 is not Alignment.topLeft -- which is
  // what a saved theme holds and what the editor compares against.
  double tidy(double v) {
    var r = (v * 1000).roundToDouble() / 1000;
    return r == 0 ? 0 : r;
  }

  var x = tidy(dx / longest);
  var y = tidy(dy / longest);
  return (Alignment(-x, -y), Alignment(x, y));
}

/// areaAngleOf reads that pair back as a compass angle.
double areaAngleOf(Alignment begin, Alignment end) {
  var dx = end.x - begin.x;
  var dy = end.y - begin.y;
  if (dx == 0 && dy == 0) return 180;
  var degrees = math.atan2(dx, -dy) * 180 / math.pi;
  return degrees < 0 ? degrees + 360 : degrees;
}
