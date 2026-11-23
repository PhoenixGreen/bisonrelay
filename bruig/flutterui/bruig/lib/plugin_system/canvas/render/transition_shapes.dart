import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/painting.dart';

// transition_shapes.dart is what an overlay transition draws: a shape in the
// transition's colour grows over the page, the scenes change behind it, and
// it goes. A cover, not a mask: the next scene seen through a splatter would
// be a wipe. Shapes come from the transition's numbers and a seed from its
// kind, never a random number at draw time, so each separately rendered
// export frame lands the paint in the same place.

/// coverAt is how much of the page the overlay covers at [t]: up over the
/// first half and down over the second, so the scenes change when it is
/// complete.
double coverAt(double t) => t <= 0.5 ? t * 2 : (1 - t) * 2;

/// leavesAt is whether the overlay is on its way out, which tells a shape
/// which side to retreat to.
bool leavesAt(double t) => t > 0.5;

/// overlayPath is the shape [over] draws at [t], in the page's coordinates.
ui.Path overlayPath(SceneTransition over, Rect page, double t) {
  var grown = coverAt(t).clamp(0.0, 1.0);
  var going = leavesAt(t);

  return switch (over.kind) {
    SceneTransitionKind.band => _band(over, page, t),
    SceneTransitionKind.blinds => _blinds(over, page, grown),
    SceneTransitionKind.barn => _barn(over, page, grown),
    SceneTransitionKind.shapeWipe => _shapes(over, page, grown, going),
    SceneTransitionKind.clock => _clock(page, t),
    SceneTransitionKind.arrow => _arrows(over, page, t),
    SceneTransitionKind.splatter => _splatter(over, page, grown, going),
    SceneTransitionKind.brush => _brush(over, page, grown, going),
    SceneTransitionKind.tiles => _tiles(over, page, grown),
    SceneTransitionKind.halftone => _halftone(over, page, grown),
    SceneTransitionKind.burst => _burst(over, page, t),
    SceneTransitionKind.rays => _rays(over, page, t),
    _ => ui.Path()..addRect(page),
  };
}

/// _turned turns a path about the page's middle, for arrangements set at an
/// angle.
ui.Path _turned(ui.Path path, Rect page, double degrees) =>
    BoxFrame(degrees, 0, 0).placePath(path, page.center);

/// _closed fills in the last of the page as the cover completes: a cover of
/// pieces has gaps by design, but a gap when the scenes change shows the cut.
ui.Path _closed(ui.Path path, Rect page, double grown, {bool round = false}) {
  // Late enough to be a safety net, not a visible stage of the transition.
  const from = 0.96;
  if (grown <= from) return path;
  var last = ((grown - from) / (1 - from)).clamp(0.0, 1.0);
  // Round for round covers, or a square appears. Joined, not added: added,
  // the fill rule decides the overlap and a shape wound the other way cuts
  // holes in itself.
  var closer = round
      ? (ui.Path()
        ..addOval(
            Rect.fromCircle(center: page.center, radius: _reach(page) * last)))
      : (ui.Path()
        ..addRect(Rect.fromCenter(
            center: page.center,
            width: page.width * last * 1.05,
            height: page.height * last * 1.05)));
  return ui.Path.combine(ui.PathOperation.union, path, closer);
}

/// _reach is far enough to cover the page whatever angle it is turned to.
double _reach(Rect page) =>
    math.sqrt(page.width * page.width + page.height * page.height);

/// _band is a panel crossing the page: on from one side, off the other.
ui.Path _band(SceneTransition over, Rect page, double t) {
  var along = over.way.horizontal ? page.width : page.height;
  var travel = (t * 2 - 1) * along;
  var moved = switch (over.way) {
    SceneTransitionWay.inPlace || SceneTransitionWay.right => Offset(travel, 0),
    SceneTransitionWay.left => Offset(-travel, 0),
    SceneTransitionWay.down => Offset(0, travel),
    SceneTransitionWay.up => Offset(0, -travel),
  };
  return ui.Path()..addRect(page.shift(moved).inflate(1));
}

/// _blinds is slats closing across the page, each thickening from its own
/// edge until they meet.
ui.Path _blinds(SceneTransition over, Rect page, double grown) {
  var path = ui.Path();
  var bars = over.count.clamp(1, 40);
  // Told left or right the slats stand upright; up or down they lie flat.
  var horizontal = over.way.horizontal;
  var span = (horizontal ? page.width : page.height) / bars;
  // A little over their share, so no hairline is left between slats.
  var thick = span * grown * 1.02;
  if (thick <= 0) return path;

  var back =
      over.way == SceneTransitionWay.left || over.way == SceneTransitionWay.up;
  for (var i = 0; i < bars; i++) {
    var edge = (horizontal ? page.left : page.top) + span * i;
    // Every slat turns the same way; the direction setting reverses it.
    var from = back ? edge + span - thick : edge;
    path.addRect(horizontal
        ? Rect.fromLTRB(from, page.top, from + thick, page.bottom)
        : Rect.fromLTRB(page.left, from, page.right, from + thick));
  }
  return _turned(path, page, over.angle);
}

/// _barn is two doors meeting in the middle.
ui.Path _barn(SceneTransition over, Rect page, double grown) {
  var path = ui.Path();
  var horizontal = over.way.horizontal;
  var half = (horizontal ? page.width : page.height) / 2 * grown;
  if (half <= 0) return path;

  if (horizontal) {
    path.addRect(
        Rect.fromLTRB(page.left, page.top, page.left + half, page.bottom));
    path.addRect(
        Rect.fromLTRB(page.right - half, page.top, page.right, page.bottom));
  } else {
    path.addRect(
        Rect.fromLTRB(page.left, page.top, page.right, page.top + half));
    path.addRect(
        Rect.fromLTRB(page.left, page.bottom - half, page.right, page.bottom));
  }
  return path;
}

/// _shapes is a field of shapes arriving until they cover the page, which is
/// when they have grown into each other.
ui.Path _shapes(SceneTransition over, Rect page, double grown, bool going) {
  var path = ui.Path();
  var across = over.count.clamp(1, 40);
  var cell = page.width / across;
  // Rows near enough square; rounded, not rounded up, or a wide page gets
  // squat cells and reads as one block.
  var down = math.max(1, (page.height / cell).round());
  var tall = page.height / down;

  // Oversized, so every shape runs into its neighbours from the start.
  var size = math.max(cell, tall) *
      (0.78 + over.radius * 0.45) *
      (1 - over.spacing.clamp(0.0, 1.0) * 0.2);
  // They swell over the last of the cover: shapes that only meet at their
  // edges leave the corners between them.
  size *= 1 + 0.55 * ((grown - 0.72) / 0.28).clamp(0.0, 1.0);

  var way = switch (over.way) {
    SceneTransitionWay.inPlace => Offset.zero,
    SceneTransitionWay.right => const Offset(1, 0),
    SceneTransitionWay.left => const Offset(-1, 0),
    SceneTransitionWay.down => const Offset(0, 1),
    SceneTransitionWay.up => const Offset(0, -1),
  };
  // In from one side and out of the other, so the last thing seen is them
  // leaving; far enough to clear the page and themselves.
  var travel = (way.dx != 0 ? page.width : page.height) + size * 0.7;

  for (var x = 0; x < across; x++) {
    for (var y = 0; y < down; y++) {
      var at =
          Offset(page.left + cell * (x + 0.5), page.top + tall * (y + 0.5));
      // Arriving in a wave the way the transition points, so the field does
      // not slide across as one block.
      var along = switch (over.way) {
        SceneTransitionWay.inPlace => (x / across + y / down) / 2,
        SceneTransitionWay.right => x / across,
        SceneTransitionWay.left => 1 - x / across,
        SceneTransitionWay.down => y / down,
        SceneTransitionWay.up => 1 - y / down,
      };
      var starts = along * 0.45 * (0.4 + over.spacing.clamp(0.0, 1.0));
      var on = ((grown - starts) / math.max(0.05, 1 - starts)).clamp(0.0, 1.0);
      if (on <= 0) continue;
      // Travelling, they arrive full size and the wave is in where they are:
      // a shape that grows and slides reads as neither. Each travels its own
      // way home, so the leaders are on the page from the start.
      var wide = size * (way == Offset.zero ? on : 1);
      // Quick in, slow to settle: at an even rate a shape travelling a page
      // and a half spends the first half off screen.
      var eased = 1 - math.pow(1 - on, 2.2).toDouble();
      var from = way * ((1 - eased) * travel * (going ? 1 : -1));

      var box = Rect.fromCenter(center: at + from, width: wide, height: wide);
      // Shapes with a front end point the way they go (drawn pointing right).
      path.addPath(
          _pointed(
              shapePath(over.shape, box, points: 5), over.shape, box, over.way),
          Offset.zero);
    }
  }
  return _closed(_turned(path, page, over.angle), page, grown);
}

/// _pointed turns a shape with a front end (ShapeKind.facing) to face the
/// way it travels, about its own middle so a corner shape stays in the
/// corner.
ui.Path _pointed(
    ui.Path path, ShapeKind shape, Rect box, SceneTransitionWay way) {
  var facing = shape.facing;
  if (facing == null) return path;
  var wanted = switch (way) {
    SceneTransitionWay.inPlace || SceneTransitionWay.right => 0.0,
    SceneTransitionWay.left => 180.0,
    SceneTransitionWay.down => 90.0,
    SceneTransitionWay.up => -90.0,
  };
  var turn = wanted - facing;
  if (turn == 0) return path;
  return BoxFrame(turn, 0, 0).placePath(path, box.center);
}

/// _clock is a sector sweeping round like a hand.
ui.Path _clock(Rect page, double t) {
  var grown = coverAt(t);
  if (grown >= 1) return ui.Path()..addRect(page);
  if (grown <= 0) return ui.Path();

  var box = Rect.fromCircle(center: page.center, radius: _reach(page));
  // Leaving, the hand carries on rather than unwinding, which would read as
  // the transition undone.
  var from =
      leavesAt(t) ? -math.pi / 2 + 2 * math.pi * (1 - grown) : -math.pi / 2;
  return ui.Path()
    ..moveTo(page.center.dx, page.center.dy)
    ..arcTo(box, from, 2 * math.pi * grown, false)
    ..close();
}

/// _field is the area an arrangement is laid over: the page, or when turned
/// the square that holds the page at any angle, so strokes start off edge.
Rect _field(Rect page, double angle) {
  if (angle == 0) return page;
  var reach = _reach(page);
  return Rect.fromCenter(center: page.center, width: reach, height: reach);
}

/// _along makes a point from distance along and across, so the four
/// directions are four readings of two numbers, not four copies of a shape.
Offset Function(double along, double across) _along(
    SceneTransitionWay way, Rect page) {
  switch (way) {
    case SceneTransitionWay.left:
      return (a, c) => Offset(page.right - a, page.top + c);
    case SceneTransitionWay.down:
      return (a, c) => Offset(page.left + c, page.top + a);
    case SceneTransitionWay.up:
      return (a, c) => Offset(page.left + c, page.bottom - a);
    case SceneTransitionWay.inPlace:
    case SceneTransitionWay.right:
      return (a, c) => Offset(page.left + a, page.top + c);
  }
}

/// _arrows is a train of page-tall nested chevrons driving across, the scene
/// showing between them.
ui.Path _arrows(SceneTransition over, Rect page, double t) {
  var path = ui.Path();
  var many = over.count.clamp(1, 40);
  var grown = coverAt(t).clamp(0.0, 1.0);
  var horizontal = over.way.horizontal;
  var at = _along(over.way, page);

  var across = horizontal ? page.width : page.height;
  var cross = horizontal ? page.height : page.width;
  var mid = cross / 2;
  // How far the point leads the corners: half the page gives a right angle.
  var depth = mid * (0.55 + over.radius.clamp(0.05, 1.0) * 0.9);

  // One chevron's width and the gap behind it, closing as the cover
  // completes.
  var wide = across / many;
  var gap = wide * over.spacing.clamp(0.0, 1.5) * 0.5 * (1 - grown);
  var step = wide + gap;

  // Long enough to cover the page: the point leads the corners by depth at
  // both front and back.
  var train = math.max(1, ((across + depth * 1.15) / wide).ceil());
  var span = train * step + depth;
  var lead = t * (across + span);

  for (var i = 0; i < train; i++) {
    var front = lead - step * i;
    var back = front - wide;
    if (back - depth > across) continue;
    if (front < -depth) break;

    var one = ui.Path();
    var tip = at(front, mid);
    one.moveTo(tip.dx, tip.dy);
    for (var xy in [
      (front - depth, 0.0),
      (back - depth, 0.0),
      (back, mid),
      (back - depth, cross),
      (front - depth, cross),
    ]) {
      var p = at(xy.$1, xy.$2);
      one.lineTo(p.dx, p.dy);
    }
    path.addPath(one..close(), Offset.zero);
  }
  return _closed(_turned(path, page, over.angle), page, grown);
}

/// _blob is one splat: a round body, arms of different lengths and a ragged
/// edge, drawn with curves rather than overlapping discs.
ui.Path _blob(Offset at, double size, math.Random random) {
  var path = ui.Path();
  var arms = 9 + random.nextInt(4);
  var points = <Offset>[];
  for (var i = 0; i < arms; i++) {
    var angle = i / arms * 2 * math.pi;
    // Every few arms a long one, so it is a splat, not a wobbly circle.
    var out = size * (0.62 + random.nextDouble() * 0.5);
    if (random.nextDouble() < 0.28) out = size * (1.15 + random.nextDouble());
    points.add(at + Offset(math.cos(angle) * out, math.sin(angle) * out));
  }

  path.moveTo(points.first.dx, points.first.dy);
  for (var i = 0; i < points.length; i++) {
    var here = points[i];
    var next = points[(i + 1) % points.length];
    // Bulging between the arms, so the outline is paint, not a polygon.
    var mid = (here + next) / 2;
    var push = (mid - at);
    var control = at + push * 1.25;
    path.quadraticBezierTo(control.dx, control.dy, next.dx, next.dy);
  }
  return path..close();
}

/// _howFarAlong is where a point falls along the transition's direction: 0
/// at the side it comes from, 1 at the far side. Shared by paint going on
/// and coming off so the two agree.
double _howFarAlong(SceneTransitionWay way, Rect page, Offset at) =>
    switch (way) {
      SceneTransitionWay.inPlace ||
      SceneTransitionWay.right =>
        (at.dx - page.left) / page.width,
      SceneTransitionWay.left => 1 - (at.dx - page.left) / page.width,
      SceneTransitionWay.down => (at.dy - page.top) / page.height,
      SceneTransitionWay.up => 1 - (at.dy - page.top) / page.height,
    };

/// _splatter is paint thrown at the page and washed off: two halves, not one
/// played backwards. Splats land in order until the page is covered; then
/// holes open through the paint (see _washed).
ui.Path _splatter(SceneTransition over, Rect page, double grown, bool going) {
  var blobs = over.count.clamp(1, 40);
  var random = math.Random(over.kind.seed + blobs);
  var reach = _reach(page);

  // Landing spots and holes come from one sequence: the same throw of paint.
  var spots = <Offset>[];
  var order = <double>[];
  var sizes = <double>[];
  for (var i = 0; i < blobs; i++) {
    spots.add(Offset(page.left + random.nextDouble() * page.width,
        page.top + random.nextDouble() * page.height));
    order.add(random.nextDouble());
    sizes.add(0.6 + random.nextDouble() * 0.9);
  }

  if (going) return _washed(over, page, grown, spots, order, reach);

  var path = ui.Path();
  for (var i = 0; i < blobs; i++) {
    var at = spots[i];
    // Splats on the side the transition comes from land first.
    var along = _howFarAlong(over.way, page, at);
    // Mostly position, a little of its own throw, so the paint crosses the
    // page without landing in a line.
    var lands = (along * 0.72 + order[i] * 0.18) *
        (1 - over.spacing * 0.3) *
        // Few splats are spread over less time, so the page is not empty
        // until the last lands.
        math.min(1.0, blobs / 3);
    var on = ((grown - lands) / math.max(0.05, 1 - lands)).clamp(0.0, 1.0);
    if (on <= 0) continue;

    // Bigger when there are fewer, so any number of splats covers the page.
    var size = reach *
        (0.7 / math.sqrt(blobs)) *
        (0.55 + over.radius) *
        sizes[i] *
        // Landing quick, spreading slow, as a thrown thing hits.
        math.pow(on, 0.6).toDouble();
    var spread = math.Random(over.kind.seed + i * 31);
    path.addPath(_blob(at, size, spread), Offset.zero);

    // Satellites: the small spots that land around a splat.
    var around = 2 + spread.nextInt(3);
    for (var d = 0; d < around; d++) {
      var angle = spread.nextDouble() * 2 * math.pi;
      var away = size * (1.0 + spread.nextDouble() * 0.9);
      path.addOval(Rect.fromCircle(
          center: at + Offset(math.cos(angle) * away, math.sin(angle) * away),
          radius: size * (0.06 + spread.nextDouble() * 0.1)));
    }

    // A drip, running the way the transition points, once the splat is
    // fully there.
    if (on > 0.75 && spread.nextDouble() < 0.6) {
      var run = size * (0.5 + spread.nextDouble() * 1.2) * ((on - 0.75) / 0.25);
      var wide = size * (0.12 + spread.nextDouble() * 0.1);
      var way = switch (over.way) {
        SceneTransitionWay.inPlace ||
        SceneTransitionWay.right =>
          const Offset(1, 0),
        SceneTransitionWay.left => const Offset(-1, 0),
        SceneTransitionWay.up => const Offset(0, -1),
        SceneTransitionWay.down => const Offset(0, 1),
      };
      var end = at + way * (size * 0.5 + run);
      path.addRRect(RRect.fromRectAndRadius(
          Rect.fromPoints(at - Offset(wide, wide), end + Offset(wide, wide)),
          Radius.circular(wide)));
      path.addOval(Rect.fromCircle(center: end, radius: wide * 1.5));
    }
  }

  return _closed(path, page, grown, round: true);
}

/// _washed is the second half of a splatter: paint with holes opening in it.
ui.Path _washed(SceneTransition over, Rect page, double grown,
    List<Offset> spots, List<double> order, double reach) {
  var off = (1 - grown).clamp(0.0, 1.0);
  var holes = ui.Path();
  for (var i = 0; i < spots.length; i++) {
    // Holes open each at its own moment in the transition's direction, so
    // the paint comes off the way it went on.
    var at = spots[i];
    var along = _howFarAlong(over.way, page, at);
    var opens = along * 0.4 + order[i] * 0.12;
    var on = ((off - opens) / math.max(0.05, 1 - opens)).clamp(0.0, 1.0);
    if (on <= 0) continue;
    // The last paint goes as the transition ends, not before, which would
    // show as a cut.
    holes.addPath(
        _blob(at, reach * 0.85 * math.pow(on, 0.7).toDouble(),
            math.Random(over.kind.seed + i * 31)),
        Offset.zero);
  }
  // The rest wiped off at once, for corners no blob landed near.
  if (off > 0.88) {
    holes.addRect(Rect.fromCenter(
        center: page.center,
        width: page.width * ((off - 0.88) / 0.12) * 1.05,
        height: page.height * ((off - 0.88) / 0.12) * 1.05));
  }
  return ui.Path.combine(
      ui.PathOperation.difference, ui.Path()..addRect(page), holes);
}

/// _brush is strokes dragged across the page, built where drawn (a flipping
/// matrix would turn the ragged ends inside out). Going on, a stroke's head
/// runs ahead and its tail stays; going off, the whole stroke carries on
/// along its line. Its width, thick in the body and lifting at the end, does
/// not change as the transition runs.
ui.Path _brush(SceneTransition over, Rect page, double grown, bool going) {
  var path = ui.Path();
  var strokes = over.count.clamp(1, 40);
  var horizontal = over.way.horizontal;
  // Over the square holding the page when turned, so an angled stroke still
  // starts off the picture.
  var box = _field(page, over.angle);
  var at = _along(over.way, box);

  // Both narrow ends of the stroke stay off the picture.
  var extent = horizontal ? box.width : box.height;
  var back = extent * 0.22;
  var run = extent * 1.5;
  // A little wider than the page: the strokes waver, and the outermost would
  // leave a line of the old scene down the side.
  var cross = horizontal ? box.height : box.width;
  var edging = cross * 0.05;
  var lanes = (cross + edging * 2) / strokes;
  // Wider than its lane, so wavering strokes overlap.
  var thick = lanes * 2.1 * (1 - over.spacing.clamp(0.0, 0.8) * 0.35);
  var random = math.Random(over.kind.seed + strokes);

  for (var i = 0; i < strokes; i++) {
    // In order but not in step, or it is a wipe with a texture.
    var starts = (i / strokes) * 0.35 * (0.4 + random.nextDouble());
    var on = ((grown - starts) / math.max(0.05, 1 - starts)).clamp(0.0, 1.0);
    var lane = -edging + lanes * i + (lanes - thick) / 2;
    var waver = lanes * 0.11;
    var phase = random.nextDouble() * math.pi * 2;
    var beats = 1.5 + random.nextDouble() * 1.5;
    // How hard and where this one was pressed, so strokes differ in width.
    var press = 0.82 + random.nextDouble() * 0.3;
    var heavy = 0.2 + random.nextDouble() * 0.5;
    var bristles = 3 + random.nextInt(3);
    var splay = random.nextDouble();
    // The streaks close over the last of the cover: they are bare page, and
    // would show the cut.
    var dries = 1 - ((grown - 0.78) / 0.22).clamp(0.0, 1.0);
    if (on <= 0 && !going) continue;

    // Going on, the tail is at the start and the head runs away; going off,
    // both carry on until the tail is past the far edge too.
    var tail = -back + (going ? run * (1 - on) * 1.05 : 0.0);
    var head = -back + (going ? run * (1 + (1 - on) * 0.6) : run * on);
    if (head - tail <= 0) continue;

    // The stroke's line and width at each point, used by body and bristles.
    var steps = 20;
    var line = <Offset>[];
    var wides = <double>[];
    for (var k = 0; k <= steps; k++) {
      var f = k / steps;
      var d = tail + (head - tail) * f;
      var wave = math.sin(phase + (d / run) * beats * math.pi) * waver;
      // Loaded at the start, heaviest a little way in, lifting at the end.
      var weight =
          press * (1 - 0.22 * (f - heavy).abs() / math.max(heavy, 1 - heavy));
      var wide = thick * weight * (1 - 0.22 * math.pow(f, 3).toDouble());
      if (f < 0.06) wide *= 0.55 + f / 0.06 * 0.45;
      if (f > 0.9) wide *= (1 - f) / 0.1;
      line.add(at(d, lane + wave + thick / 2));
      wides.add(wide);
    }

    var stroke = ui.Path();
    var side = <Offset>[];
    for (var k = 0; k <= steps; k++) {
      var f = k / steps;
      var d = tail + (head - tail) * f;
      var wave = math.sin(phase + (d / run) * beats * math.pi) * waver;
      var half = wides[k] / 2;
      var top = at(d, lane + wave + thick / 2 - half);
      side.add(at(d, lane + wave + thick / 2 + half));
      k == 0 ? stroke.moveTo(top.dx, top.dy) : stroke.lineTo(top.dx, top.dy);
    }
    for (var p in side.reversed) {
      stroke.lineTo(p.dx, p.dy);
    }
    stroke.close();

    // The bristles: streaks of bare page through the end of the stroke only,
    // so the old scene does not show through the middle of the cover.
    var from = 0.55 + splay * 0.2;
    var slits = ui.Path();
    for (var b = 0; b < bristles; b++) {
      var lay = (b + 0.5) / bristles - 0.5 + (random.nextDouble() - 0.5) * 0.1;
      var ends = from + 0.25 + random.nextDouble() * 0.2;
      var slit = <Offset>[];
      var back = <Offset>[];
      for (var k = 0; k <= steps; k++) {
        var f = k / steps;
        if (f < from) continue;
        var d = tail + (head - tail) * f;
        var wave = math.sin(phase + (d / run) * beats * math.pi) * waver;
        // Opening as the paint runs out, closing again if the stroke has more
        // in it than this bristle.
        var open = ((f - from) / math.max(0.05, ends - from)).clamp(0.0, 1.4);
        var gap = wides[k] * 0.09 * math.min(open, 1.0) * dries;
        var mid = lane + wave + thick / 2 + lay * wides[k] * 0.8;
        slit.add(at(d, mid - gap));
        back.add(at(d, mid + gap));
      }
      if (slit.length < 2) continue;
      var one = ui.Path()..moveTo(slit.first.dx, slit.first.dy);
      for (var p in slit.skip(1)) {
        one.lineTo(p.dx, p.dy);
      }
      for (var p in back.reversed) {
        one.lineTo(p.dx, p.dy);
      }
      slits.addPath(one..close(), Offset.zero);
    }
    // Combined only when there is something to take out: a path operation
    // per stroke per frame is costly.
    path.addPath(
        dries <= 0
            ? stroke
            : ui.Path.combine(ui.PathOperation.difference, stroke, slits),
        Offset.zero);
  }
  // No closing rectangle: the strokes butt together, and a square growing
  // from the middle would show.
  return _turned(path, page, over.angle);
}

/// _tiles breaks the page into squares that arrive in a wave.
ui.Path _tiles(SceneTransition over, Rect page, double grown) {
  var path = ui.Path();
  var across = over.count.clamp(1, 40);
  var wide = page.width / across;
  var down = math.max(1, (page.height / math.max(1.0, wide)).round());
  var tall = page.height / down;
  var gap = over.spacing.clamp(0.0, 0.9);

  for (var x = 0; x < across; x++) {
    for (var y = 0; y < down; y++) {
      var along = switch (over.way) {
        SceneTransitionWay.inPlace || SceneTransitionWay.right => x / across,
        SceneTransitionWay.left => 1 - x / across,
        SceneTransitionWay.down => y / down,
        SceneTransitionWay.up => 1 - y / down,
      };
      var lean = (over.way.horizontal ? y / down : x / across) * 0.25;
      var starts = (along * 0.65 + lean).clamp(0.0, 0.95);
      var on = ((grown - starts) / math.max(0.05, 1 - starts)).clamp(0.0, 1.0);
      if (on <= 0) continue;

      var box =
          Rect.fromLTWH(page.left + wide * x, page.top + tall * y, wide, tall);
      // The gaps between tiles close as the cover completes.
      var apart = gap * 0.35 * (1 - grown);
      path.addRect(Rect.fromCenter(
          center: box.center,
          width: box.width * on * (1 - apart) + 1,
          height: box.height * on * (1 - apart) + 1));
    }
  }
  return _closed(path, page, grown);
}

/// _halftone is a comic's dots: a printed grid that grows until it fills in.
ui.Path _halftone(SceneTransition over, Rect page, double grown) {
  var path = ui.Path();
  var across = over.count.clamp(1, 40);
  var step = page.width / across * (1 + over.spacing * 0.5);
  var rows = math.max(1, (page.height / step).ceil()) + 2;
  var reach = _reach(page);

  for (var y = -1; y < rows; y++) {
    for (var x = -1; x <= across + 1; x++) {
      var at = Offset(
          page.left + step * (x + (y.isEven ? 0 : 0.5)), page.top + step * y);
      // The wave runs out from one corner, as a printed screen is laid on.
      var away = (at - page.topLeft).distance / reach;
      var on = (grown * 1.6 - away * 0.7).clamp(0.0, 1.0);
      if (on <= 0) continue;
      // Past a full dot they run together and the page goes solid.
      path.addOval(Rect.fromCircle(
          center: at, radius: step * (0.15 + over.radius) * on * 1.5));
    }
  }
  return path;
}

/// _burst is a comic's speed lines thrown out of the middle. It never
/// shrinks: leaving, the rays carry on out and their inner ends follow,
/// through a burst-shaped hole. Nothing round, so it never looks a circle.
ui.Path _burst(SceneTransition over, Rect page, double t) {
  var path = ui.Path();
  var rays = over.count.clamp(1, 40);
  var full = _reach(page);
  var grown = t <= 0.5 ? t * 2 : 1.0;
  var leaving = t <= 0.5 ? 0.0 : ((t - 0.5) * 2).clamp(0.0, 1.0);
  // Out to the page by half way, and on out of it after.
  var reach = full * (t <= 0.5 ? t * 2 * 1.15 : 1.15 + leaving * 1.6);
  if (reach <= 0) return path;
  var random = math.Random(over.kind.seed + rays);
  var centre = page.center;

  // Each wedge's share of the turn and its length; widening closes the gaps
  // by the time the scenes change.
  var lengths = <double>[];
  var spreads = <double>[];
  for (var i = 0; i < rays; i++) {
    spreads.add((math.pi / rays) * (0.45 + random.nextDouble() * 1.1));
    lengths.add(0.75 + random.nextDouble() * 0.5);
  }

  for (var i = 0; i < rays; i++) {
    var angle = i / rays * 2 * math.pi;
    // Wedges of different widths, so it is not a pie chart. Held short of a
    // half turn and of its share: a wedge wrapping past itself cancels out,
    // leaving rays at the end.
    var spread = math.min(spreads[i] * (1 + grown * 1.7),
        math.min((math.pi / rays) * 1.8, math.pi * 0.9));
    var length = reach * lengths[i];
    // The inner end: none coming in, running out after the ray going out,
    // each at its own rate so the hole is ragged.
    var inner = leaving <= 0
        ? 0.0
        : full *
            0.62 *
            math.pow(leaving, 0.85).toDouble() *
            (0.72 + lengths[i] * 0.5);
    if (inner >= length) continue;

    var from = Offset(centre.dx + math.cos(angle - spread) * inner,
        centre.dy + math.sin(angle - spread) * inner);
    path.moveTo(from.dx, from.dy);
    path.lineTo(centre.dx + math.cos(angle - spread) * length,
        centre.dy + math.sin(angle - spread) * length);
    path.lineTo(centre.dx + math.cos(angle) * length * 1.1,
        centre.dy + math.sin(angle) * length * 1.1);
    path.lineTo(centre.dx + math.cos(angle + spread) * length,
        centre.dy + math.sin(angle + spread) * length);
    // The inner end walked round, not cut straight: a chord across a wide
    // wedge passes behind the middle and fills the hole.
    for (var k = 6; k >= 0; k--) {
      var a = angle - spread + (2 * spread) * k / 6;
      path.lineTo(
          centre.dx + math.cos(a) * inner, centre.dy + math.sin(a) * inner);
    }
    path.close();
  }

  if (leaving > 0) return path;

  // The star in the middle they all come out of.
  path = ui.Path.combine(
      ui.PathOperation.union,
      path,
      starPath(
          centre, reach * 0.42, reach * 0.42, math.max(5, rays), 0.24 / 0.42));

  // A bigger star closes the last of the cover: a handful of wedges always
  // leave page between them, and a gap at the change shows the cut.
  if (grown > 0.9) {
    var last = (grown - 0.9) / 0.1;
    path = ui.Path.combine(
        ui.PathOperation.union,
        path,
        starPath(centre, reach * 1.3 * last, reach * 1.3 * last,
            math.max(5, rays), 1.05 / 1.3));
  }
  return path;
}

/// _rays is the lines swinging shut like a fan and open again (its own kind,
/// not half a burst): the gaps narrow to nothing, then widen.
ui.Path _rays(SceneTransition over, Rect page, double t) {
  var grown = coverAt(t).clamp(0.0, 1.0);
  var full = _reach(page);
  var centre = page.center;
  // At least two: one gap taking the whole turn wraps past itself, cancels
  // out, and leaves the page covered.
  var between = math.max(2, over.count.clamp(1, 40));
  var random = math.Random(over.kind.seed + between);

  var gaps = ui.Path();
  var far = full * 1.4;
  for (var i = 0; i < between; i++) {
    var angle = (i + 0.5) / between * 2 * math.pi;
    // Gaps that sum to the whole turn at each end, none the same width.
    var g = (math.pi / between) *
        math.pow(1 - grown, 0.8).toDouble() *
        1.3 *
        (0.75 + random.nextDouble() * 0.5);
    if (g <= 0) continue;
    gaps.moveTo(centre.dx, centre.dy);
    gaps.lineTo(centre.dx + math.cos(angle - g) * far,
        centre.dy + math.sin(angle - g) * far);
    gaps.lineTo(centre.dx + math.cos(angle) * far * 1.1,
        centre.dy + math.sin(angle) * far * 1.1);
    gaps.lineTo(centre.dx + math.cos(angle + g) * far,
        centre.dy + math.sin(angle + g) * far);
    gaps.close();
  }
  return ui.Path.combine(
      ui.PathOperation.difference, ui.Path()..addRect(page.inflate(1)), gaps);
}
