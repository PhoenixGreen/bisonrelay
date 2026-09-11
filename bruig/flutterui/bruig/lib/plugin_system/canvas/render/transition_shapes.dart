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
  const from = 0.86;
  if (grown <= from) return path;
  var last = ((grown - from) / (1 - from)).clamp(0.0, 1.0);
  // Round for the covers made of round things. A rectangle growing out of the
  // middle of a splatter is a square appearing in the paint, which is exactly
  // what it looked like.
  if (round) {
    return path
      ..addOval(
          Rect.fromCircle(center: page.center, radius: _reach(page) * last));
  }
  return path
    ..addRect(Rect.fromCenter(
        center: page.center,
        width: page.width * last * 1.05,
        height: page.height * last * 1.05));
}

/// _reach is far enough to cover the page whatever angle it is turned to.
double _reach(Rect page) =>
    math.sqrt(page.width * page.width + page.height * page.height);

/// _band is a panel crossing the page: on from one side, off the other.
ui.Path _band(SceneTransition over, Rect page, double t) {
  var along = over.way.horizontal ? page.width : page.height;
  var travel = (t * 2 - 1) * along;
  var moved = switch (over.way) {
    SceneTransitionWay.right => Offset(travel, 0),
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
  var box = page.inflate(_reach(page) * 0.5);
  var horizontal = over.way.horizontal;
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

/// _shapes is a row of shapes growing until they cover everything.
ui.Path _shapes(SceneTransition over, Rect page, double grown, bool going) {
  var path = ui.Path();
  var many = over.count.clamp(1, 40);
  var reach = _reach(page);
  // Each shape has to be able to cover its own share of the page and then
  // some, or a row of them leaves gaps at the corners.
  var room = reach / many;
  var size = room * (1.6 + over.radius * 1.6) * grown;
  if (size <= 0) return path;

  var gap = room * (1 + over.spacing);
  var start = page.center.dx - gap * (many - 1) / 2;
  // Travelling as they grow, so a row of shapes reads as moving across the
  // page rather than as swelling in place.
  var drift = (going ? 1 - grown : grown - 1) * reach * 0.35;
  var way = switch (over.way) {
    SceneTransitionWay.right => const Offset(1, 0),
    SceneTransitionWay.left => const Offset(-1, 0),
    SceneTransitionWay.down => const Offset(0, 1),
    SceneTransitionWay.up => const Offset(0, -1),
  };

  for (var i = 0; i < many; i++) {
    var at = Offset(start + gap * i, page.center.dy) + way * drift;
    path.addPath(
        shapePath(
            over.shape, Rect.fromCenter(center: at, width: size, height: size),
            points: 5),
        Offset.zero);
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

/// _arrows is a set of arrowheads driving across the page.
ui.Path _arrows(SceneTransition over, Rect page, double t) {
  var path = ui.Path();
  var many = over.count.clamp(1, 40);
  var reach = _reach(page);
  var horizontal = over.way.horizontal;

  // Each arrow is a band of the page with a point on the front of it. They
  // travel right across: on over the first half, off over the second, so what
  // covers the page in the middle is the arrows themselves.
  var band = (horizontal ? page.height : page.width) / many;
  var head = band * (0.5 + over.radius);
  // Along the axis it is crossing, not along the diagonal: measured by the
  // diagonal, a set of arrows going down a page crossed it half way through
  // its first frame and read as stripes rather than as anything moving.
  var across = horizontal ? page.width : page.height;
  var travelled = (t * 2) * (across + head * 2 + reach * 0.15);

  for (var i = 0; i < many; i++) {
    var lane = (horizontal ? page.top : page.left) + band * i;
    var thick = band * (1 - over.spacing.clamp(0.0, 0.9));
    var lead = -head + travelled - (i.isEven ? 0 : band * 0.35);
    var tail = lead - across - head;

    var arrow = ui.Path();
    switch (over.way) {
      case SceneTransitionWay.right:
        arrow.moveTo(page.left + tail, lane);
        arrow.lineTo(page.left + lead, lane);
        arrow.lineTo(page.left + lead + head, lane + thick / 2);
        arrow.lineTo(page.left + lead, lane + thick);
        arrow.lineTo(page.left + tail, lane + thick);
        arrow.lineTo(page.left + tail + head, lane + thick / 2);
      case SceneTransitionWay.left:
        arrow.moveTo(page.right - tail, lane);
        arrow.lineTo(page.right - lead, lane);
        arrow.lineTo(page.right - lead - head, lane + thick / 2);
        arrow.lineTo(page.right - lead, lane + thick);
        arrow.lineTo(page.right - tail, lane + thick);
        arrow.lineTo(page.right - tail - head, lane + thick / 2);
      case SceneTransitionWay.down:
        arrow.moveTo(lane, page.top + tail);
        arrow.lineTo(lane, page.top + lead);
        arrow.lineTo(lane + thick / 2, page.top + lead + head);
        arrow.lineTo(lane + thick, page.top + lead);
        arrow.lineTo(lane + thick, page.top + tail);
        arrow.lineTo(lane + thick / 2, page.top + tail + head);
      case SceneTransitionWay.up:
        arrow.moveTo(lane, page.bottom - tail);
        arrow.lineTo(lane, page.bottom - lead);
        arrow.lineTo(lane + thick / 2, page.bottom - lead - head);
        arrow.lineTo(lane + thick, page.bottom - lead);
        arrow.lineTo(lane + thick, page.bottom - tail);
        arrow.lineTo(lane + thick / 2, page.bottom - tail + head);
    }
    path.addPath(arrow..close(), Offset.zero);
  }
  // The lanes run together as the cover completes, so the page is behind it
  // at the moment the scenes change.
  return _closed(_turned(path, page, over.angle), page, coverAt(t));
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

/// _splatter is paint thrown at the page: splats, satellites and drips.
ui.Path _splatter(SceneTransition over, Rect page, double grown, bool going) {
  var path = ui.Path();
  var blobs = over.count.clamp(1, 40);
  var random = math.Random(over.kind.seed + blobs);
  var reach = _reach(page);

  for (var i = 0; i < blobs; i++) {
    var at = Offset(page.left + random.nextDouble() * page.width,
        page.top + random.nextDouble() * page.height);
    // Thrown across the page the way the transition points: the splats on the
    // side it comes from land first. The direction turned the drips and
    // nothing else before, which is most of a setting doing nothing.
    var along = switch (over.way) {
      SceneTransitionWay.right => (at.dx - page.left) / page.width,
      SceneTransitionWay.left => 1 - (at.dx - page.left) / page.width,
      SceneTransitionWay.down => (at.dy - page.top) / page.height,
      SceneTransitionWay.up => 1 - (at.dy - page.top) / page.height,
    };
    // Half the order from where it is and half from its own throw, so the
    // paint crosses the page without landing in a line.
    var lands =
        (along * 0.5 + random.nextDouble() * 0.25) * (1 - over.spacing * 0.3);
    var on = ((grown - lands) / math.max(0.05, 1 - lands)).clamp(0.0, 1.0);
    if (on <= 0) continue;

    var size = reach *
        0.13 *
        (0.55 + over.radius) *
        on *
        (0.6 + random.nextDouble() * 0.9);
    path.addPath(_blob(at, size, random), Offset.zero);

    // Satellites: the small spots that land around a splat.
    var spots = 2 + random.nextInt(3);
    for (var d = 0; d < spots; d++) {
      var angle = random.nextDouble() * 2 * math.pi;
      var away = size * (1.2 + random.nextDouble() * 1.4);
      path.addOval(Rect.fromCircle(
          center: at + Offset(math.cos(angle) * away, math.sin(angle) * away),
          radius: size * (0.08 + random.nextDouble() * 0.14)));
    }

    // And a drip: paint that has landed and is running. It runs the way the
    // transition points, and only once the splat is fully there.
    if (on > 0.75 && random.nextDouble() < 0.6) {
      var run = size * (0.8 + random.nextDouble() * 2.2) * ((on - 0.75) / 0.25);
      var wide = size * (0.16 + random.nextDouble() * 0.16);
      var way = switch (over.way) {
        SceneTransitionWay.right => const Offset(1, 0),
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

/// _brush is strokes dragged across the page, each with bristles in it.
ui.Path _brush(SceneTransition over, Rect page, double grown, bool going) {
  var path = ui.Path();
  var strokes = over.count.clamp(1, 40);
  var horizontal = over.way.horizontal;
  // Lanes across the page rather than across a box drawn round it: measured
  // against that larger box, one stroke was wider than the page and covered
  // it before it had been drawn anywhere.
  var lane = (horizontal ? page.height : page.width) / strokes;
  var box = horizontal
      ? Rect.fromLTRB(page.left - page.width * 0.25, page.top,
          page.right + page.width * 0.25, page.bottom)
      : Rect.fromLTRB(page.left, page.top - page.height * 0.25, page.right,
          page.bottom + page.height * 0.25);
  // The gaps between strokes close as the cover completes, so the page is
  // painted rather than striped by the time the scenes change behind it.
  var thick = lane * (1 - over.spacing.clamp(0.0, 0.8) * (1 - grown)) + 1;
  var random = math.Random(over.kind.seed + strokes);
  var full = horizontal ? box.width : box.height;

  for (var i = 0; i < strokes; i++) {
    var starts = i / strokes * 0.4;
    var run = ((grown - starts) / math.max(0.05, 1 - starts)).clamp(0.0, 1.0);
    if (run <= 0) continue;
    var length = full * run;
    var at =
        (horizontal ? page.top : page.left) + lane * i + (lane - thick) / 2;

    // The body of the stroke, with a ragged leading edge: a brush does not
    // stop in a straight line, and the wobble is fixed by the seed so the
    // same stroke is the same stroke on every frame.
    var steps = 8;
    var stroke = ui.Path();
    var lead = <Offset>[];
    for (var s = 0; s <= steps; s++) {
      var across = thick * s / steps;
      var ragged = (random.nextDouble() - 0.5) * thick * 0.5;
      lead.add(horizontal
          ? Offset(box.left + length + ragged, at + across)
          : Offset(at + across, box.top + length + ragged));
    }

    if (horizontal) {
      stroke.moveTo(box.left, at);
      for (var p in lead) {
        stroke.lineTo(p.dx, p.dy);
      }
      stroke.lineTo(box.left, at + thick);
    } else {
      stroke.moveTo(at, box.top);
      for (var p in lead) {
        stroke.lineTo(p.dx, p.dy);
      }
      stroke.lineTo(at + thick, box.top);
    }
    stroke.close();

    // Turned round for the ways that run the other direction.
    if (over.way == SceneTransitionWay.left ||
        over.way == SceneTransitionWay.up) {
      stroke = stroke.transform(Float64List.fromList([
        over.way == SceneTransitionWay.left ? -1 : 1, 0, 0, 0, //
        0, over.way == SceneTransitionWay.up ? -1 : 1, 0, 0, //
        0, 0, 1, 0, //
        over.way == SceneTransitionWay.left ? box.left + box.right : 0,
        over.way == SceneTransitionWay.up ? box.top + box.bottom : 0,
        0,
        1,
      ]));
    }
    path.addPath(stroke, Offset.zero);
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
        SceneTransitionWay.right => x / across,
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
ui.Path _burst(SceneTransition over, Rect page, double t) {
  var path = ui.Path();
  var rays = over.count.clamp(1, 40);
  var full = _reach(page);
  // Out to the page by the half way point, and on out of it after that.
  var reach = full * (t <= 0.5 ? t * 2 * 1.15 : 1.15 + (t - 0.5) * 2.2);
  if (reach <= 0) return path;
  var random = math.Random(over.kind.seed + rays);
  var centre = page.center;

  for (var i = 0; i < rays; i++) {
    var angle = i / rays * 2 * math.pi;
    // Wedges of different widths, pointed at the middle: even wedges are a
    // pie chart, and a comic's lines are never even.
    var spread = (math.pi / rays) * (0.45 + random.nextDouble() * 1.1);
    var length = reach * (0.75 + random.nextDouble() * 0.5);
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
  var star = ui.Path();
  var spikes = math.max(5, rays);
  for (var i = 0; i < spikes * 2; i++) {
    var angle = i / (spikes * 2) * 2 * math.pi - math.pi / 2;
    var out = reach * (i.isEven ? 0.42 : 0.24);
    var p = centre + Offset(math.cos(angle) * out, math.sin(angle) * out);
    i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
  }
  path.addPath(star..close(), Offset.zero);
  path = _closed(path, page, t <= 0.5 ? t * 2 : 1, round: true);

  // And the hole it leaves, opening from the middle once it is past the page.
  if (t <= 0.5) return path;
  // Reaching the corners of the page exactly as the transition ends: half
  // the diagonal is the furthest corner, and a hole measured by the whole
  // diagonal had swallowed the page before the lines were out of it.
  var hole = ui.Path()
    ..addOval(Rect.fromCircle(
        center: page.center, radius: full / 2 * ((t - 0.5) * 2)));
  return ui.Path.combine(ui.PathOperation.difference, path, hole);
}
