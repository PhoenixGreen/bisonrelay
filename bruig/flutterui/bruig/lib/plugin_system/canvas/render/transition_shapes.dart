import 'dart:math' as math;
import 'dart:typed_data' show Float64List;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
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

/// _blinds is a set of bars, each growing from its own side.
ui.Path _blinds(SceneTransition over, Rect page, double grown, bool going) {
  var path = ui.Path();
  var bars = over.count.clamp(1, 40);
  // Across the page. Measured against a box drawn well outside it, as this
  // was, five bars put one or two across the whole picture -- so what arrived
  // was a block, not blinds.
  var horizontal = over.way.horizontal;
  var box = page;
  var span = (horizontal ? box.height : box.width) / bars;
  var full = horizontal ? box.width : box.height;

  for (var i = 0; i < bars; i++) {
    var at = (horizontal ? box.top : box.left) + span * i;
    var length = full * grown;
    // On from one side and off the other: a bar that grew and shrank from the
    // same edge would look like a mistake being undone.
    var startAt = going
        ? (horizontal ? box.right - length : box.bottom - length)
        : (horizontal ? box.left : box.top);
    if (over.way == SceneTransitionWay.left ||
        over.way == SceneTransitionWay.up) {
      startAt = going
          ? (horizontal ? box.left : box.top)
          : (horizontal ? box.right - length : box.bottom - length);
    }
    path.addRect(horizontal
        ? Rect.fromLTWH(startAt, at, length, span)
        : Rect.fromLTWH(at, startAt, span, length));
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
  var down = math.max(1, (page.height / cell).ceil());
  var tall = page.height / down;

  // Big enough to cover its own square when it is fully grown -- the corner
  // of a square is further away than its side, so a shape the width of one
  // leaves four gaps.
  var size = math.max(cell, tall) *
      (1.5 + over.radius * 0.8) *
      (1 - over.spacing.clamp(0.0, 1.0) * 0.2);

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
      var from = way * ((1 - on) * travel * (going ? 1 : -1));

      path.addPath(
          shapePath(over.shape,
              Rect.fromCenter(center: at + from, width: wide, height: wide),
              points: 5),
          Offset.zero);
    }
  }
  return _closed(_turned(path, page, over.angle), page, grown);
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

/// _arrows is a train of arrows driving across the page.
///
/// Rewritten from a set of bands with a point on the end of them. Each arrow
/// was as long as the page, so what crossed the screen was stripes with a
/// notch in -- at no moment was there anything on the page that looked like
/// an arrow. These are arrows the length of a hand, several to a lane, with
/// gaps between them that close as the cover completes: what is seen is a
/// row of arrows driving across, and what covers the page is the same row
/// with the daylight taken out of it.
ui.Path _arrows(SceneTransition over, Rect page, double t) {
  var path = ui.Path();
  var lanes = over.count.clamp(1, 40);
  var grown = coverAt(t).clamp(0.0, 1.0);
  var horizontal = over.way.horizontal;
  var at = _along(over.way, page);

  var across = horizontal ? page.width : page.height;
  var band = (horizontal ? page.height : page.width) / lanes;
  // The lanes close up as the cover completes, so a gap between them is not
  // what is on the page at the moment the scenes change.
  var thick = band * (1 - over.spacing.clamp(0.0, 0.8) * 0.5 * (1 - grown));

  // One arrow, and the gap behind it. Both shrink to nothing as the page
  // fills: at the middle of the transition the arrows in a lane have run
  // together into one bar, which is what makes this a cover at all.
  var arrow = across * 0.22 * (0.5 + over.radius.clamp(0.05, 1.0));
  var gap = arrow * 0.5 * (1 - grown);
  var step = arrow + gap;
  // The train is as long as the page and one arrow more, however wide the
  // gaps in it are -- so it fills the page in the middle and is off the far
  // edge at the end. Run instead until an arrow had left the page, the train
  // had no back to it: at the end of the transition arrows were still
  // arriving.
  var train = across + arrow;
  var many = math.max(1, (train / step).ceil());
  var lead = t * (across + train);

  for (var i = 0; i < lanes; i++) {
    var lane = band * i + (band - thick) / 2;
    // Every other lane a little behind, so the points do not arrive in a
    // line -- a straight front is a wipe with arrowheads drawn on it.
    var offset = (i.isEven ? 0.0 : step * 0.4);
    var head = thick * (0.45 + over.radius * 0.4);
    // The shaft fattens as the cover completes, until the arrow is the whole
    // width of its lane and the train is solid.
    var waist = thick * 0.26 * (1 - grown);

    for (var k = 0; k < many; k++) {
      var front = lead - offset - step * k;
      if (front < -arrow) break;
      if (front - arrow > across) continue;

      var tail = front - arrow;
      var neck = front - head;
      var one = ui.Path();
      var p = at(front, lane + thick / 2);
      one.moveTo(p.dx, p.dy);
      for (var xy in [
        (neck, lane),
        (neck, lane + waist),
        (tail, lane + waist),
        (tail, lane + thick - waist),
        (neck, lane + thick - waist),
        (neck, lane + thick),
      ]) {
        var q = at(xy.$1, xy.$2);
        one.lineTo(q.dx, q.dy);
      }
      path.addPath(one..close(), Offset.zero);
    }
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
    // Half the order from where it is and half from its own throw, so the
    // paint crosses the page without landing in a line.
    var lands = (along * 0.5 + order[i] * 0.25) * (1 - over.spacing * 0.3);
    var on = ((grown - lands) / math.max(0.05, 1 - lands)).clamp(0.0, 1.0);
    if (on <= 0) continue;

    // Big enough to close the page between them. Splats a tenth of the page
    // across never met, so the last of the cover was the safety net filling
    // in a screen of spots -- which is the round shape that appeared in the
    // middle of the paint.
    var size = reach *
        0.3 *
        (0.55 + over.radius) *
        sizes[i] *
        // Landing is quick and the spread after it is slow, the way a thrown
        // thing hits: a splat that grew at an even rate was a balloon.
        math.pow(on, 0.45).toDouble();
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
  // Gone by the end, whatever the holes have managed between them.
  var off = (1 - grown).clamp(0.0, 1.0);
  if (off >= 0.92) return ui.Path();

  var holes = ui.Path();
  for (var i = 0; i < spots.length; i++) {
    // Each hole opens at its own moment, the ones that landed last going
    // first -- paint comes off the way it went on, in pieces.
    var opens = order[i] * 0.35;
    var on = ((off - opens) / math.max(0.05, 1 - opens)).clamp(0.0, 1.0);
    if (on <= 0) continue;
    holes.addPath(
        _blob(spots[i], reach * 0.55 * on * (0.7 + order[i] * 0.6),
            math.Random(over.kind.seed + i * 31)),
        Offset.zero);
  }
  return ui.Path.combine(
      ui.PathOperation.difference, ui.Path()..addRect(page), holes);
}

/// _brush is strokes dragged across the page.
///
/// Rewritten. The strokes were built in a box drawn round the page and then
/// flipped with a matrix to go the other way, and what came of that was
/// squares where a stroke's ragged end had been turned inside out. These are
/// built where they are drawn -- see _along -- so there is nothing to flip,
/// and each one is a ribbon that wavers as it goes, thins towards its end
/// and leaves the page at a slant, the way a loaded brush does.
ui.Path _brush(SceneTransition over, Rect page, double grown, bool going) {
  var path = ui.Path();
  var strokes = over.count.clamp(1, 40);
  var horizontal = over.way.horizontal;
  var at = _along(over.way, page);

  // The stroke crosses the page and comes off the far side, so the end of a
  // stroke is never sitting on the page as a straight edge.
  var run = (horizontal ? page.width : page.height) * 1.12;
  var lanes = (horizontal ? page.height : page.width) / strokes;
  // One stroke covers its lane at the end: with the gap wide open a single
  // stroke was a band down the middle of a page it was supposed to be
  // painting.
  // Wider than its lane as the cover completes, so the strokes overlap
  // rather than meeting exactly: two wavering edges that meet exactly leave
  // a line of page between them wherever they waver apart.
  var thick = lanes *
      (1 + 0.3 * grown) *
      (1 - over.spacing.clamp(0.0, 0.8) * 0.45 * (1 - grown));
  var random = math.Random(over.kind.seed + strokes);

  for (var i = 0; i < strokes; i++) {
    // Started in order but not in step: a set of strokes laid on at exactly
    // the same moment is a wipe with a texture.
    var starts = (i / strokes) * 0.35 * (0.4 + random.nextDouble());
    var on = ((grown - starts) / math.max(0.05, 1 - starts)).clamp(0.0, 1.0);
    if (on <= 0) continue;
    var length = run * on;

    var lane = lanes * i + (lanes - thick) / 2;
    var waver = lanes * 0.16;
    var phase = random.nextDouble() * math.pi * 2;
    var beats = 1.5 + random.nextDouble() * 1.5;

    // Drawn down one side and back up the other. The two edges waver
    // together and the width tapers towards the end, which is a brush
    // running out rather than a rectangle with a rough edge on it.
    var steps = 14;
    var edge = <Offset>[];
    var back = <Offset>[];
    for (var k = 0; k <= steps; k++) {
      var f = k / steps;
      var d = length * f;
      var wave = math.sin(phase + f * beats * math.pi) * waver;
      // Full width for most of it and then narrowing, and the very tip a
      // point rather than a cut end.
      // The taper goes as the page fills: a stroke that runs out towards its
      // end is a brush, and forty of them running out at once is a page with
      // a pale stripe down one side of it at the moment the scenes change.
      var taper = 1 - grown;
      var wide = thick * (1 - 0.35 * taper * math.pow(f, 2.5).toDouble());
      if (f > 0.93) wide *= 1 - taper * (1 - (1 - f) / 0.07);
      edge.add(at(d, lane + wave + (thick - wide) / 2));
      back.add(at(d, lane + wave + (thick + wide) / 2));
    }

    var stroke = ui.Path()..moveTo(edge.first.dx, edge.first.dy);
    for (var p in edge.skip(1)) {
      stroke.lineTo(p.dx, p.dy);
    }
    for (var p in back.reversed) {
      stroke.lineTo(p.dx, p.dy);
    }
    path.addPath(stroke..close(), Offset.zero);
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
/// does is carry on out of the frame, so on the way out it keeps growing and
/// the middle of it opens instead -- the new scene arriving through the hole
/// the lines leave behind them.
///
/// Nothing round in it. The wedges used to be closed off with a growing disc
/// and the hole they left was another one, so a burst began as a circle and
/// ended as a circle and the spikes were what happened in between. Now the
/// wedges widen until they meet each other, and the hole is cut in the shape
/// of the burst itself.
ui.Path _burst(SceneTransition over, Rect page, double t) {
  var path = ui.Path();
  var rays = over.count.clamp(1, 40);
  var full = _reach(page);
  var grown = t <= 0.5 ? t * 2 : 1.0;
  // Out to the page by the half way point, and on out of it after that.
  var reach = full * (t <= 0.5 ? t * 2 * 1.15 : 1.15 + (t - 0.5) * 2.2);
  if (reach <= 0) return path;
  var random = math.Random(over.kind.seed + rays);
  var centre = page.center;

  // How much of the turn each wedge is worth. Widening as the burst grows is
  // what closes the gaps: by the time the scenes change behind it the wedges
  // have met, and what covers the page is the burst rather than a disc drawn
  // over it.
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
    var spread = spreads[i] * (1 + grown * 1.7);
    var length = reach * lengths[i];
    path.moveTo(centre.dx, centre.dy);
    path.lineTo(centre.dx + math.cos(angle - spread) * length,
        centre.dy + math.sin(angle - spread) * length);
    path.lineTo(centre.dx + math.cos(angle) * length * 1.1,
        centre.dy + math.sin(angle) * length * 1.1);
    path.lineTo(centre.dx + math.cos(angle + spread) * length,
        centre.dy + math.sin(angle + spread) * length);
    path.close();
  }

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

  // And the hole it leaves, opening from the middle once it is past the page.
  if (t <= 0.5) return path;
  // Cut in the burst's own shape, and reaching the corners of the page as
  // the transition ends: half the diagonal is the furthest corner, and a
  // hole measured by the whole diagonal had swallowed the page before the
  // lines were out of it.
  // Wide enough at the end to have taken the corners with it: measured to
  // the spikes rather than to the notches between them, the hole reached the
  // end of the transition with paint still standing in the corners.
  var opening = full / 2 * ((t - 0.5) * 2);
  var hole = _star(centre, opening * 1.9, opening * 1.15, math.max(5, rays));
  return ui.Path.combine(ui.PathOperation.difference, path, hole);
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
