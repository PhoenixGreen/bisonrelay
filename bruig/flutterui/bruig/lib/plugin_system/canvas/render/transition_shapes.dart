import 'dart:math' as math;
import 'dart:typed_data' show Float64List;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/painting.dart';

// transition_shapes.dart is what an overlay transition actually draws.
//
// One idea, applied eight ways: a shape in the transition's own colour grows
// until it covers the page, the scenes change behind it, and it goes away
// again. Everything here returns that shape for a given moment, and nothing
// here knows about scenes -- which is what makes each of them something that
// can be looked at on its own and got right.
//
// They were masks before: the next scene was drawn *through* the shape. That
// is a wipe, and it is the wrong tool for this job -- what arrived through a
// splatter was the next scene's backdrop rather than paint, which is why they
// looked like holes rather than like something landing on the page.
//
// Every shape here is worked out from the transition's own numbers and a seed
// taken from its kind. Nothing consults a random number at drawing time: an
// export renders each frame separately, and paint that landed somewhere else
// on every frame would be a different picture each time.

/// cover is how much of the page the overlay has taken at [t].
///
/// Up over the first half and back down over the second, so the scenes can
/// change underneath it at the moment it is complete.
double coverAt(double t) => t <= 0.5 ? t * 2 : (1 - t) * 2;

/// leaves is whether the overlay is on its way out, which is what tells a
/// shape which side to retreat towards.
bool leavesAt(double t) => t > 0.5;

/// overlayPath is the shape [over] draws at [t], in the page's coordinates.
ui.Path overlayPath(SceneTransition over, Rect page, double t) {
  var grown = coverAt(t).clamp(0.0, 1.0);
  var going = leavesAt(t);

  return switch (over.kind) {
    SceneTransitionKind.band => _band(over, page, t),
    SceneTransitionKind.blinds => _blinds(over, page, grown, going),
    SceneTransitionKind.barn => _barn(over, page, grown),
    SceneTransitionKind.shapeWipe => _shapes(over, page, grown, going),
    SceneTransitionKind.clock => _clock(over, page, t),
    SceneTransitionKind.arrow => _arrows(over, page, t),
    SceneTransitionKind.splatter => _splatter(over, page, grown, going),
    SceneTransitionKind.brush => _brush(over, page, grown, going),
    SceneTransitionKind.tiles => _tiles(over, page, grown, going),
    SceneTransitionKind.halftone => _halftone(over, page, grown),
    SceneTransitionKind.burst => _burst(over, page, t),
    SceneTransitionKind.rays => _rays(over, page, t),
    _ => ui.Path()..addRect(page),
  };
}

/// _turned turns a path about the page's middle, for the arrangements that
/// can be set at an angle.
ui.Path _turned(ui.Path path, Rect page, double degrees) {
  if (degrees == 0) return path;
  var r = degrees * math.pi / 180;
  var cos = math.cos(r);
  var sin = math.sin(r);
  var c = page.center;
  return path.transform(Float64List.fromList([
    cos, sin, 0, 0, //
    -sin, cos, 0, 0, //
    0, 0, 1, 0, //
    c.dx - cos * c.dx + sin * c.dy,
    c.dy - sin * c.dx - cos * c.dy,
    0,
    1,
  ]));
}

/// _closed is [path] with the last of the page filled in as the cover
/// completes.
///
/// A cover made of pieces leaves gaps between them by construction -- that is
/// what makes it a set of arrows rather than a rectangle -- but the scenes
/// change at the moment it is complete, and a gap at that moment is the cut
/// it was put there to hide. So over the last of its travel the gaps close.
ui.Path _closed(ui.Path path, Rect page, double grown, {bool round = false}) {
  // Late enough to be a safety net rather than a stage of the transition. At
  // 0.86 of the cover -- which is 43 out of every 100 frames -- most of what
  // anybody saw was this shape growing, so a splatter was a blob and then a
  // wipe.
  const from = 0.96;
  if (grown <= from) return path;
  var last = ((grown - from) / (1 - from)).clamp(0.0, 1.0);
  // Round for the covers made of round things. A rectangle growing out of the
  // middle of a splatter is a square appearing in the paint, which is exactly
  // what it looked like.
  // Joined to the shape rather than added to it. Added, the fill rule
  // decides what the overlap means, and a shape wound the other way round to
  // this one cut holes in itself: arrows going right were a rectangle with
  // arrow-shaped gaps in it, and the same arrows going left were solid.
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

/// _blinds is a set of slats closing across the page.
///
/// They used to be bars growing lengthwise from one edge, all at the same
/// rate and with no daylight between them, which is a block crossing the
/// page with a comb for a leading edge. A blind does not do that: every slat
/// spans the page already and what changes is how much of it is turned to
/// you. So each one spans the page and thickens from its own edge until they
/// meet.
ui.Path _blinds(SceneTransition over, Rect page, double grown, bool going) {
  var path = ui.Path();
  var bars = over.count.clamp(1, 40);
  // Slats across the way it points: told left or right they stand upright
  // and close sideways, told up or down they lie flat.
  var horizontal = over.way.horizontal;
  var span = (horizontal ? page.width : page.height) / bars;
  // A little over its own share, so the slats have met by the time the page
  // is covered rather than leaving a hairline between each pair.
  var thick = span * grown * 1.02;
  if (thick <= 0) return path;

  var back =
      over.way == SceneTransitionWay.left || over.way == SceneTransitionWay.up;
  for (var i = 0; i < bars; i++) {
    var edge = (horizontal ? page.left : page.top) + span * i;
    // Every slat turns the same way, and turning the other way is what the
    // direction setting means here.
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

/// _shapes is a field of shapes arriving until they cover everything.
///
/// It was a single row of them across the middle of the page, which never
/// covered anything: what covered the page was the safety net in _closed
/// snapping shut over the last fiftieth of the transition, so a dozen shapes
/// grew politely in a line and then the whole page went solid at once. These
/// are laid out over the page, so the moment they cover it is the moment
/// they have grown into each other.
ui.Path _shapes(SceneTransition over, Rect page, double grown, bool going) {
  var path = ui.Path();
  var across = over.count.clamp(1, 40);
  var cell = page.width / across;
  // Rows near enough square. Rounded rather than rounded up: two across on a
  // wide page was two rows of squat cells, so the shapes in them were half
  // as tall as they were wide apart and the field read as one block.
  var down = math.max(1, (page.height / cell).round());
  var tall = page.height / down;

  // One shape to a cell rather than half again as big as one. Oversized,
  // every shape ran into its neighbours from the moment it arrived, and two
  // squares crossing the page were one big square.
  var size = math.max(cell, tall) *
      (0.78 + over.radius * 0.45) *
      (1 - over.spacing.clamp(0.0, 1.0) * 0.2);
  // And they swell into each other over the last of the cover, which is what
  // closes the page: shapes that only ever meet at their edges leave the
  // corners between them, and filling those in with a rectangle is the
  // square that used to appear at the end.
  size *= 1 + 0.55 * ((grown - 0.72) / 0.28).clamp(0.0, 1.0);

  var way = switch (over.way) {
    SceneTransitionWay.inPlace => Offset.zero,
    SceneTransitionWay.right => const Offset(1, 0),
    SceneTransitionWay.left => const Offset(-1, 0),
    SceneTransitionWay.down => const Offset(0, 1),
    SceneTransitionWay.up => const Offset(0, -1),
  };
  // In from one side and out of the other, rather than swelling and
  // shrinking where they stand: going, they carry on the way they came, so
  // the last thing seen is them leaving rather than a shape sitting in the
  // middle of the page getting smaller. Far enough to clear the page and
  // themselves -- nine tenths of the diagonal left a big one still standing
  // there when the transition ended.
  // Far enough to clear the page and itself -- nine tenths of the diagonal
  // left a big one still standing there when the transition ended.
  var travel = (way.dx != 0 ? page.width : page.height) + size * 0.7;

  for (var x = 0; x < across; x++) {
    for (var y = 0; y < down; y++) {
      var at =
          Offset(page.left + cell * (x + 0.5), page.top + tall * (y + 0.5));
      // Arriving in a wave the way the transition points, and growing where
      // they land. Standing still, that wave is all there is to see;
      // travelling, it is what keeps the field from being one solid block
      // sliding across.
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
      // Travelling, they arrive at full size and the wave is in where they
      // are rather than in how big they are: a shape that grows *and* slides
      // is two things happening to it at once, and reads as neither.
      //
      // Each one travels its own way home rather than the whole field
      // sliding across as a block. As a block it was off the page for the
      // first half of its travel and then arrived all at once; like this the
      // leading shapes are on the page from the start and the ones behind
      // catch up.
      var wide = size * (way == Offset.zero ? on : 1);
      // Quick in and slow to settle, rather than an even slide: at an even
      // rate a shape with a page and a half to travel spends the first half
      // of the transition off the edge of the screen.
      var eased = 1 - math.pow(1 - on, 2.2).toDouble();
      var from = way * ((1 - eased) * travel * (going ? 1 : -1));

      var box = Rect.fromCenter(center: at + from, width: wide, height: wide);
      // The shapes that have a front end point the way they are going. They
      // are drawn pointing right whatever they are told, so an arrow moving
      // left was an arrow flying backwards.
      path.addPath(
          _pointed(
              shapePath(over.shape, box, points: 5), over.shape, box, over.way),
          Offset.zero);
    }
  }
  return _closed(_turned(path, page, over.angle), page, grown);
}

/// _pointed turns a shape that has a front end to face the way it travels.
///
/// Only the ones with a front: an arrow, a chevron and a triangle all say
/// which way they are going, and a circle does not. Turned about its own
/// middle rather than the page's, so a shape in the corner stays in the
/// corner.
ui.Path _pointed(
    ui.Path path, ShapeKind shape, Rect box, SceneTransitionWay way) {
  if (shape != ShapeKind.arrow &&
      shape != ShapeKind.chevron &&
      shape != ShapeKind.triangle) {
    return path;
  }
  // A triangle is drawn pointing up and the other two point right, so what
  // each has to turn by to face the same way is not the same number.
  var facing = shape == ShapeKind.triangle ? -math.pi / 2 : 0.0;
  var wanted = switch (way) {
    SceneTransitionWay.inPlace || SceneTransitionWay.right => 0.0,
    SceneTransitionWay.left => math.pi,
    SceneTransitionWay.down => math.pi / 2,
    SceneTransitionWay.up => -math.pi / 2,
  };
  var r = wanted - facing;
  if (r == 0) return path;
  var cos = math.cos(r);
  var sin = math.sin(r);
  var c = box.center;
  return path.transform(Float64List.fromList([
    cos, sin, 0, 0, //
    -sin, cos, 0, 0, //
    0, 0, 1, 0, //
    c.dx - cos * c.dx + sin * c.dy,
    c.dy - sin * c.dx - cos * c.dy,
    0,
    1,
  ]));
}

/// _clock is a sector sweeping round like a hand.
ui.Path _clock(SceneTransition over, Rect page, double t) {
  var grown = coverAt(t);
  if (grown >= 1) return ui.Path()..addRect(page);
  if (grown <= 0) return ui.Path();

  var box = Rect.fromCircle(center: page.center, radius: _reach(page));
  // Leaving, the hand carries on from where it stopped rather than unwinding
  // -- a clock that ran backwards would read as the transition being undone.
  var from =
      leavesAt(t) ? -math.pi / 2 + 2 * math.pi * (1 - grown) : -math.pi / 2;
  return ui.Path()
    ..moveTo(page.center.dx, page.center.dy)
    ..arcTo(box, from, 2 * math.pi * grown, false)
    ..close();
}

/// _field is the area an arrangement is laid out over.
///
/// The page itself, until it is turned. A set of strokes laid across the page
/// and then turned about its middle has its ends inside the picture -- the
/// corner of a square is further from the middle than the middle of its side
/// -- so the strokes began in mid-air rather than off the edge. Turned, they
/// are laid out over the square that contains the page at any angle.
Rect _field(Rect page, double angle) {
  if (angle == 0) return page;
  var reach = _reach(page);
  return Rect.fromCenter(center: page.center, width: reach, height: reach);
}

/// _along makes a point from a distance travelled and a distance across.
///
/// Every arrangement that runs one way across the page is easier to write
/// this way round: how far along the travel, how far across the lanes -- and
/// the four directions become four ways of reading those two numbers rather
/// than four copies of the same shape written out by hand, or a matrix that
/// turned the shape and everything else with it.
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

/// _arrows is a train of chevrons sweeping across the page.
///
/// Rewritten twice. First they were bands the length of the page with a point
/// on the front, so what crossed the screen was stripes with a notch in.
/// Then they were small arrows several to a lane, which is a picture of
/// arrows and not a transition -- at any moment half the page was showing
/// through the gaps between them.
///
/// What this is now is the thing people mean by an arrow wipe: chevrons as
/// tall as the page, nested one behind another, driving across. The page
/// between two of them is the scene underneath, which is what makes it a
/// sweep rather than a shape growing.
ui.Path _arrows(SceneTransition over, Rect page, double t) {
  var path = ui.Path();
  var many = over.count.clamp(1, 40);
  var grown = coverAt(t).clamp(0.0, 1.0);
  var horizontal = over.way.horizontal;
  var at = _along(over.way, page);

  var across = horizontal ? page.width : page.height;
  var cross = horizontal ? page.height : page.width;
  var mid = cross / 2;
  // How far the point runs ahead of the corners. Half the page across is a
  // right angle at the tip, which is the shape of the thing.
  var depth = mid * (0.55 + over.radius.clamp(0.05, 1.0) * 0.9);

  // How wide one chevron is, and the daylight behind it. The gap closes as
  // the cover completes: what covers the page at the moment the scenes
  // change is the chevrons run together.
  var wide = across / many;
  var gap = wide * over.spacing.clamp(0.0, 1.5) * 0.5 * (1 - grown);
  var step = wide + gap;

  // Long enough that the page is covered when the train is over it. The
  // point runs ahead of the corners by depth at the front and the back, so a
  // train exactly as long as the page covers the middle of it and leaves two
  // triangles at the far corners.
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

/// _blob is one splat of paint: a round body with arms of different lengths
/// and a ragged edge.
///
/// Drawn with curves rather than by adding circles together. A blob made of
/// overlapping discs looks like overlapping discs, which is what the first
/// splatter did.
ui.Path _blob(Offset at, double size, math.Random random) {
  var path = ui.Path();
  var arms = 9 + random.nextInt(4);
  var points = <Offset>[];
  for (var i = 0; i < arms; i++) {
    var angle = i / arms * 2 * math.pi;
    // Every few arms a long one, which is what makes a splat a splat rather
    // than a circle with a wobble.
    var out = size * (0.62 + random.nextDouble() * 0.5);
    if (random.nextDouble() < 0.28) out = size * (1.15 + random.nextDouble());
    points.add(at + Offset(math.cos(angle) * out, math.sin(angle) * out));
  }

  path.moveTo(points.first.dx, points.first.dy);
  for (var i = 0; i < points.length; i++) {
    var here = points[i];
    var next = points[(i + 1) % points.length];
    // Bulging out between the arms, so the outline is paint rather than a
    // polygon.
    var mid = (here + next) / 2;
    var push = (mid - at);
    var control = at + push * 1.25;
    path.quadraticBezierTo(control.dx, control.dy, next.dx, next.dy);
  }
  return path..close();
}

/// _splatter is paint thrown at the page, and then washed off it.
///
/// Two halves rather than one played backwards. Going on, splats land in
/// order across the page until the paint covers it. Coming off, the paint
/// stays where it is and holes open through it -- which is what paint does,
/// and the alternative, every splat shrinking back into the spot it came
/// from, read as the page sucking the paint in again.
ui.Path _splatter(SceneTransition over, Rect page, double grown, bool going) {
  var blobs = over.count.clamp(1, 40);
  var random = math.Random(over.kind.seed + blobs);
  var reach = _reach(page);

  // Where the paint lands, and where the holes open. Drawn from the same
  // sequence so that both halves are the same throw of paint.
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
    // Thrown across the page the way the transition points: the splats on
    // the side it comes from land first. The direction turned the drips and
    // nothing else before, which is most of a setting doing nothing.
    var along = switch (over.way) {
      SceneTransitionWay.inPlace ||
      SceneTransitionWay.right =>
        (at.dx - page.left) / page.width,
      SceneTransitionWay.left => 1 - (at.dx - page.left) / page.width,
      SceneTransitionWay.down => (at.dy - page.top) / page.height,
      SceneTransitionWay.up => 1 - (at.dy - page.top) / page.height,
    };
    // Mostly where it is and a little of its own throw, so the paint
    // crosses the page the way the transition points without landing in a
    // line. Half and half, as it was, is a throw that lands wherever it
    // likes -- with a dozen splats the direction was not visible at all.
    var lands = (along * 0.72 + order[i] * 0.18) *
        (1 - over.spacing * 0.3) *
        // A handful of splats have nothing to wait for: spread over the same
        // half of the transition, one splat left the page empty until it
        // landed and then the safety net finished the job.
        math.min(1.0, blobs / 3);
    var on = ((grown - lands) / math.max(0.05, 1 - lands)).clamp(0.0, 1.0);
    if (on <= 0) continue;

    // Big enough to close the page between them. Splats a tenth of the page
    // across never met, so the last of the cover was the safety net filling
    // in a screen of spots -- which is the round shape that appeared in the
    // middle of the paint.
    // Bigger when there are fewer of them, so that any number of splats
    // covers the page between them rather than one lonely blob in the
    // middle of it.
    var size = reach *
        (0.7 / math.sqrt(blobs)) *
        (0.55 + over.radius) *
        sizes[i] *
        // Landing is quick and the spread after it is slow, the way a thrown
        // thing hits: a splat that grew at an even rate was a balloon.
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

    // And a drip: paint that has landed and is running. It runs the way the
    // transition points, and only once the splat is fully there.
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
      // The bead of paint at the end of a run.
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
    // Each hole opens at its own moment, and in the order the transition
    // points, so the paint comes off the way it went on rather than all at
    // once.
    var at = spots[i];
    var along = switch (over.way) {
      SceneTransitionWay.inPlace ||
      SceneTransitionWay.right =>
        (at.dx - page.left) / page.width,
      SceneTransitionWay.left => 1 - (at.dx - page.left) / page.width,
      SceneTransitionWay.down => (at.dy - page.top) / page.height,
      SceneTransitionWay.up => 1 - (at.dy - page.top) / page.height,
    };
    var opens = along * 0.4 + order[i] * 0.12;
    var on = ((off - opens) / math.max(0.05, 1 - opens)).clamp(0.0, 1.0);
    if (on <= 0) continue;
    // Grown so that the last of the paint is gone as the transition ends
    // rather than a frame or two before it. It used to give up and return
    // nothing once most of it was off, which is the cut to the next scene
    // that was showing at the end of every splatter.
    holes.addPath(
        _blob(at, reach * 0.85 * math.pow(on, 0.7).toDouble(),
            math.Random(over.kind.seed + i * 31)),
        Offset.zero);
  }
  // And the last of it taken off in one wipe, for the corners no thrown
  // blob happened to land near.
  if (off > 0.88) {
    holes.addRect(Rect.fromCenter(
        center: page.center,
        width: page.width * ((off - 0.88) / 0.12) * 1.05,
        height: page.height * ((off - 0.88) / 0.12) * 1.05));
  }
  return ui.Path.combine(
      ui.PathOperation.difference, ui.Path()..addRect(page), holes);
}

/// _brush is strokes dragged across the page.
///
/// Rewritten twice. They were built in a box round the page and flipped with
/// a matrix to run the other way, which turned their ragged ends inside out.
/// Then they were built where they are drawn, but they grew from nothing on
/// the way in and shrank back into nothing on the way out -- a stroke going
/// back the way it came, which is the one thing a brush stroke never does,
/// and the width breathing with them on top of that.
///
/// Now a stroke is laid down from its start and dragged off the far side:
/// going on, its head runs ahead and its tail stays; going off, the whole
/// stroke carries on along the same line until it has left. Its width is
/// its own -- thick in the body and lifting at the end -- and does not
/// change as the transition runs.
ui.Path _brush(SceneTransition over, Rect page, double grown, bool going) {
  var path = ui.Path();
  var strokes = over.count.clamp(1, 40);
  var horizontal = over.way.horizontal;
  // Over the square that holds the page when the strokes are turned, so that
  // a stroke at an angle still starts off the picture rather than in the
  // middle of it.
  var box = _field(page, over.angle);
  var at = _along(over.way, box);

  // The stroke starts before the page and comes off the far side, so
  // neither end of it is ever sitting on the picture. Started at the edge,
  // as it was, the brush going down -- which is the narrow bit at the start
  // of a stroke -- left a wedge of the old scene along the near edge.
  var extent = horizontal ? box.width : box.height;
  var back = extent * 0.22;
  var run = extent * 1.5;
  // Over a field a little wider than the page, because the strokes waver as
  // they go and the outermost ones wavered off the edge -- which is a line
  // of the old scene down the side of the page at the moment they swap.
  var cross = horizontal ? box.height : box.width;
  var edging = cross * 0.05;
  var lanes = (cross + edging * 2) / strokes;
  // Wider than its lane, so the strokes overlap rather than meeting exactly:
  // two wavering edges that meet exactly leave a line of page between them
  // wherever they waver apart.
  var thick = lanes * 2.1 * (1 - over.spacing.clamp(0.0, 0.8) * 0.35);
  var random = math.Random(over.kind.seed + strokes);

  for (var i = 0; i < strokes; i++) {
    // Laid on in order but not in step: a set of strokes put down at exactly
    // the same moment is a wipe with a texture.
    var starts = (i / strokes) * 0.35 * (0.4 + random.nextDouble());
    var on = ((grown - starts) / math.max(0.05, 1 - starts)).clamp(0.0, 1.0);
    var lane = -edging + lanes * i + (lanes - thick) / 2;
    var waver = lanes * 0.11;
    var phase = random.nextDouble() * math.pi * 2;
    var beats = 1.5 + random.nextDouble() * 1.5;
    // How hard this one was pressed, and where it was pressed hardest. A set
    // of strokes all the same width is a set of rectangles.
    var press = 0.82 + random.nextDouble() * 0.3;
    var heavy = 0.2 + random.nextDouble() * 0.5;
    var bristles = 3 + random.nextInt(3);
    var splay = random.nextDouble();
    // The streaks close over the last of the cover. They are bare page, and
    // bare page at the moment the scenes change is the cut the cover is
    // there to hide -- so they are there for the sweep and gone by the time
    // it has the page.
    var dries = 1 - ((grown - 0.78) / 0.22).clamp(0.0, 1.0);
    if (on <= 0 && !going) continue;

    // Where the two ends of the stroke are. Going on, the tail is at the
    // start and the head runs away from it; going off, both carry on down
    // the same line until the tail is past the far edge too.
    var tail = -back + (going ? run * (1 - on) * 1.05 : 0.0);
    var head = -back + (going ? run * (1 + (1 - on) * 0.6) : run * on);
    if (head - tail <= 0) continue;

    // The line the stroke is dragged along, and how wide it is at each point
    // of it. Both are wanted twice -- once for the body and once for the
    // bristles running through it -- so they are worked out once.
    var steps = 20;
    var line = <Offset>[];
    var wides = <double>[];
    for (var k = 0; k <= steps; k++) {
      var f = k / steps;
      var d = tail + (head - tail) * f;
      var wave = math.sin(phase + (d / run) * beats * math.pi) * waver;
      // Loaded at the start, heaviest a little way in, and lifting at the
      // end -- which is a brush being put down, dragged and taken off, and
      // is most of what makes a stroke read as paint rather than as a bar.
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

    // The bristles: streaks of bare page the brush drags through the end of
    // its own stroke. Only towards the end, where the paint is running out
    // -- a stroke split from top to bottom is a comb, and streaks across the
    // middle of the page would be the old scene showing through the cover.
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
        // Opening as the paint runs out and closing again if the stroke has
        // more in it than this bristle does.
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
    path.addPath(ui.Path.combine(ui.PathOperation.difference, stroke, slits),
        Offset.zero);
  }
  // No closing rectangle: the strokes butt together on their own, and a
  // square growing out of the middle of a set of brush strokes is the
  // artefact it looked like.
  return _turned(path, page, over.angle);
}

/// _tiles breaks the page into squares that arrive in a wave.
ui.Path _tiles(SceneTransition over, Rect page, double grown, bool going) {
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
      // The wave runs out from one corner, which is how a printed screen is
      // laid on: nearest first, furthest last.
      var away = (at - page.topLeft).distance / reach;
      var on = (grown * 1.6 - away * 0.7).clamp(0.0, 1.0);
      if (on <= 0) continue;
      // Past a full dot they run together and the page goes solid, which is
      // what takes a halftone from a pattern to a cover.
      path.addOval(Rect.fromCircle(
          center: at, radius: step * (0.15 + over.radius) * on * 1.5));
    }
  }
  return path;
}

/// _burst is a comic's speed lines, thrown out of the middle.
///
/// It never shrinks. Every other cover grows on the way in and shrinks on the
/// way out; on this one that read as the burst being taken back. What a burst
/// does is carry on out of the frame, so on the way out the rays keep going
/// and their inner ends run out after them, leaving the page through a hole
/// shaped like the burst that made it.
///
/// Nothing round in it. The wedges used to be closed off with a growing disc
/// and the hole they left was another one, so a burst began as a circle and
/// ended as a circle and the spikes were what happened in between.
ui.Path _burst(SceneTransition over, Rect page, double t) {
  var path = ui.Path();
  var rays = over.count.clamp(1, 40);
  var full = _reach(page);
  var grown = t <= 0.5 ? t * 2 : 1.0;
  var leaving = t <= 0.5 ? 0.0 : ((t - 0.5) * 2).clamp(0.0, 1.0);
  // Out to the page by the half way point, and on out of it after that.
  var reach = full * (t <= 0.5 ? t * 2 * 1.15 : 1.15 + leaving * 1.6);
  if (reach <= 0) return path;
  var random = math.Random(over.kind.seed + rays);
  var centre = page.center;

  // How much of the turn each wedge is worth, and how long each one is.
  // Widening as the burst grows is what closes the gaps: by the time the
  // scenes change behind it the wedges have met, and what covers the page is
  // the burst rather than a disc drawn over it.
  var lengths = <double>[];
  var spreads = <double>[];
  for (var i = 0; i < rays; i++) {
    spreads.add((math.pi / rays) * (0.45 + random.nextDouble() * 1.1));
    lengths.add(0.75 + random.nextDouble() * 0.5);
  }

  for (var i = 0; i < rays; i++) {
    var angle = i / rays * 2 * math.pi;
    // Wedges of different widths, pointed at the middle: even wedges are a
    // pie chart, and a comic's lines are never even.
    // Held short of a half turn, and short of its own share of the circle
    // however wide the burst is told to be. A wedge wider than that wraps
    // past its neighbour and past itself, and a shape wound round twice
    // cancels itself out -- which is a burst of three rays still standing on
    // the page at the end of the transition.
    var spread = math.min(spreads[i] * (1 + grown * 1.7),
        math.min((math.pi / rays) * 1.8, math.pi * 0.9));
    var length = reach * lengths[i];
    // Where this ray's inner end is. Nothing while it is coming in, and
    // running out after the ray once it is going: each at its own rate, so
    // what opens in the middle is ragged rather than round.
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
    // The inner end walked round rather than cut straight across. A chord
    // between the two inner corners of a wide wedge passes behind the middle
    // of the page and fills in the very hole the ray is supposed to be
    // leaving behind it.
    for (var k = 6; k >= 0; k--) {
      var a = angle - spread + (2 * spread) * k / 6;
      path.lineTo(
          centre.dx + math.cos(a) * inner, centre.dy + math.sin(a) * inner);
    }
    path.close();
  }

  if (leaving > 0) return path;

  // The star in the middle they all come out of.
  path = ui.Path.combine(ui.PathOperation.union, path,
      _star(centre, reach * 0.42, reach * 0.24, math.max(5, rays)));

  // And the last of the cover closed with a bigger one, because between a
  // handful of wedges there is page left however wide they are made, and at
  // the moment the scenes change a gap is the cut this is here to hide. A
  // star rather than the disc that used to do it: what fills in a burst
  // should be the burst.
  if (grown > 0.9) {
    var last = (grown - 0.9) / 0.1;
    path = ui.Path.combine(
        ui.PathOperation.union,
        path,
        _star(centre, reach * 1.3 * last, reach * 1.05 * last,
            math.max(5, rays)));
  }
  return path;
}

/// _rays is the same lines swinging shut like a fan and open again.
///
/// The other half of what a burst can do, and its own kind rather than the
/// second half of one: a burst that grows out of the middle and then comes
/// apart into rays is two ideas in one transition, each good on its own and
/// strange together. Here the daylight between the rays narrows until there
/// is none, and then widens again -- the same thing happening at both ends.
ui.Path _rays(SceneTransition over, Rect page, double t) {
  var grown = coverAt(t).clamp(0.0, 1.0);
  var full = _reach(page);
  var centre = page.center;
  // Two at the least. One gap wide enough to take the whole turn is a wedge
  // that wraps past itself, and a shape wound round twice cancels itself
  // out -- which leaves the page covered when it should be clear.
  var between = math.max(2, over.count.clamp(1, 40));
  var random = math.Random(over.kind.seed + between);

  var gaps = ui.Path();
  var far = full * 1.4;
  for (var i = 0; i < between; i++) {
    var angle = (i + 0.5) / between * 2 * math.pi;
    // Wide enough between them at each end to have taken the whole turn, and
    // none of them the same width, so it is a comic's lines rather than a
    // pie chart.
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

/// _star is a spiked outline: [points] long spikes with short ones between.
ui.Path _star(Offset centre, double out, double into, int points) {
  var path = ui.Path();
  for (var i = 0; i < points * 2; i++) {
    var angle = i / (points * 2) * 2 * math.pi - math.pi / 2;
    var away = i.isEven ? out : into;
    var p = centre + Offset(math.cos(angle) * away, math.sin(angle) * away);
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  return path..close();
}
