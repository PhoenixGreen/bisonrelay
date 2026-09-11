import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/render/transition_shapes.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_transition_shapes_test.dart is the shape an overlay transition draws
// at a given moment, measured rather than looked at.
//
// These are covers: a shape in the transition's own colour that grows until
// the page is behind it. What makes one of them right is not that it covers
// -- a rectangle does that -- but what it looks like on the way, and that is
// what is measured here: where the cover reaches, where the daylight is, and
// which way the thing is pointing.

const Rect _page = Rect.fromLTWH(0, 0, 960, 540);

SceneTransition _over(SceneTransitionKind kind,
        {int count = 6,
        SceneTransitionWay way = SceneTransitionWay.right,
        ShapeKind shape = ShapeKind.square}) =>
    SceneTransition(
        kind: kind,
        count: count,
        way: way,
        shape: shape,
        ease: SceneTransitionEase.straight);

/// _on is whether the cover reaches a point, given in fractions of the page.
bool _on(ui.Path path, double x, double y) => path.contains(
    Offset(_page.left + _page.width * x, _page.top + _page.height * y));

/// _bands counts the runs of cover along a line across the page.
int _bands(ui.Path path, {required bool across, double at = 0.5}) {
  var runs = 0;
  var was = false;
  for (var i = 0; i <= 400; i++) {
    var f = i / 400;
    var now = across ? _on(path, f, at) : _on(path, at, f);
    if (now && !was) runs++;
    was = now;
  }
  return runs;
}

void main() {
  test("a chevron crosses the whole page and leads with its point", () {
    // The arrows were bands a lane high with a point on the front, so what
    // crossed the page was stripes with a notch in. A chevron is as tall as
    // the page: its point is out in front at the middle and its corners
    // trail at the top and the bottom.
    var path =
        overlayPath(_over(SceneTransitionKind.arrow, count: 3), _page, 0.25);

    // Somewhere down the page the cover has reached further along than it has
    // at the edges -- that is the point being in front.
    var middle = 0.0;
    var edge = 0.0;
    for (var i = 0; i <= 200; i++) {
      var f = i / 200;
      if (_on(path, f, 0.5)) middle = f;
      if (_on(path, f, 0.02)) edge = f;
    }
    expect(middle, greaterThan(edge + 0.1),
        reason: "point at $middle, corner at $edge");

    // And it is the full height of the page, not a lane of it.
    expect(_on(path, 0.05, 0.02), isTrue);
    expect(_on(path, 0.05, 0.98), isTrue);
  });

  test("blinds are slats with daylight between them", () {
    // They were bars growing lengthwise from one edge, all at the same rate
    // and with no daylight between them, which is a block crossing the page
    // with a comb for a leading edge.
    var path =
        overlayPath(_over(SceneTransitionKind.blinds, count: 6), _page, 0.2);

    expect(_bands(path, across: true), 6,
        reason: "six slats across the page, each with a gap after it");
    // And every slat spans the page the other way from the start, which is
    // what makes it a slat rather than a bar on its way across.
    expect(_on(path, 0.01, 0.02), isTrue);
    expect(_on(path, 0.01, 0.98), isTrue);
  });

  test("brush strokes carry on the way they were going", () {
    // Going off, they used to shrink back into the point they started from,
    // which is the one thing a brush stroke never does.
    double reach(double t) {
      var path =
          overlayPath(_over(SceneTransitionKind.brush, count: 4), _page, t);
      var from = 1.0;
      for (var i = 0; i <= 200; i++) {
        var f = i / 200;
        if (_on(path, f, 0.5)) return from = f < from ? f : from;
      }
      return from;
    }

    // The near end of the stroke is further along the page each time, so
    // what is leaving is the start of the stroke and not its end.
    var early = reach(0.6);
    var later = reach(0.85);
    expect(later, greaterThan(early),
        reason: "stroke starts at $early, then at $later");
  });

  test("comic rays open from the middle out to the edge", () {
    // Rays is the fan: the daylight between the lines widens until there is
    // none of them left, which means the page shows through at its edges
    // while the rays are still crossing it.
    var path =
        overlayPath(_over(SceneTransitionKind.rays, count: 8), _page, 0.8);

    var open = 0;
    for (var i = 0; i <= 100; i++) {
      if (!_on(path, i / 100, 0.01)) open++;
    }
    expect(open, greaterThan(10),
        reason: "the top edge of the page is $open hundredths uncovered");
  });

  test("a shape with a front end points the way it travels", () {
    // They are drawn pointing right whatever they are told, so an arrow
    // going left was an arrow flying backwards.
    ui.Path at(SceneTransitionWay way) => overlayPath(
        _over(SceneTransitionKind.shapeWipe,
            count: 1, way: way, shape: ShapeKind.chevron),
        _page,
        0.32);

    // The point of a chevron is the furthest thing along the way it goes, so
    // the cover reaches further at the middle of the page than at its edges
    // -- on whichever side it is heading for.
    double furthest(ui.Path path,
        {required bool leftwards, required double y}) {
      var best = leftwards ? 1.0 : 0.0;
      for (var i = 0; i <= 200; i++) {
        var f = leftwards ? 1 - i / 200 : i / 200;
        if (_on(path, f, y)) best = f;
      }
      return best;
    }

    var right = at(SceneTransitionWay.right);
    expect(furthest(right, leftwards: false, y: 0.5),
        greaterThan(furthest(right, leftwards: false, y: 0.05)),
        reason: "going right, the point is on the right");

    var left = at(SceneTransitionWay.left);
    expect(furthest(left, leftwards: true, y: 0.5),
        lessThan(furthest(left, leftwards: true, y: 0.05)),
        reason: "going left, the point is on the left");
  });

  test("shapes are one to a cell, not one big one", () {
    // Half again as big as their cell, every shape ran into its neighbours
    // from the moment it arrived, and two squares crossing the page were one
    // big square.
    var path = overlayPath(
        _over(SceneTransitionKind.shapeWipe,
            count: 4, way: SceneTransitionWay.inPlace),
        _page,
        0.2);
    // Across the middle of the top row of cells: four across on a wide page
    // is two rows, so the middle of the page is the seam between them.
    expect(_bands(path, across: true, at: 0.25), greaterThan(1),
        reason: "four squares in a row, with the page between them");
  });

  test("a burst leaves through a hole of its own shape", () {
    // The way out was a star-shaped hole opening in the middle of the page,
    // so what people saw was a star; before that it was a disc. It is the
    // rays themselves now: they carry on outwards and their inner ends run
    // out after them, so the middle of the page is clear while the corners
    // are still covered.
    var path =
        overlayPath(_over(SceneTransitionKind.burst, count: 10), _page, 0.68);

    expect(_on(path, 0.5, 0.5), isFalse, reason: "the middle has opened");
    expect(_on(path, 0.01, 0.02), isTrue,
        reason: "and the corner of the page is still covered");
  });

  test("strokes at an angle still start off the picture", () {
    // Laid across the page and then turned about its middle, a stroke has
    // its ends inside the picture -- the corner of a square is further from
    // the middle than the middle of its side -- so the strokes began in
    // mid-air.
    var turned = const SceneTransition(
        kind: SceneTransitionKind.brush,
        count: 4,
        angle: 30,
        ease: SceneTransitionEase.straight);
    var path = overlayPath(turned, _page, 0.18);

    // Whatever it has covered by now runs off the edge of the page, rather
    // than sitting in the middle of it with clear page on every side.
    var touches = false;
    for (var i = 0; i <= 100; i++) {
      var f = i / 100;
      if (_on(path, 0.002, f) || _on(path, f, 0.002) || _on(path, f, 0.998)) {
        touches = true;
      }
    }
    expect(touches, isTrue,
        reason: "the strokes have started somewhere inside the picture");
  });
}
