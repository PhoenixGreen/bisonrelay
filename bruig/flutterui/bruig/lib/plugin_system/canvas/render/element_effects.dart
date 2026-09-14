import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/render/text_animator.dart';
import 'package:flutter/material.dart';

// element_effects.dart is the motions that cut a thing up instead of moving
// it: a mosaic, a glitch, and a grid of tiles thrown about.
//
// Every other motion is a transform and an opacity -- applyMotion sets the
// canvas up, hands back, and the caller draws once. These cannot be: they
// need whatever is being animated drawn *again and again*, once per tile or
// per slice. So they take the drawing as a closure, which is what lets one
// implementation serve a shape, a picture and a paragraph. A photograph
// breaking into tiles and a headline breaking into tiles are the same effect,
// and writing it twice would have been two effects that drift apart.

/// paintCutEffect draws [what], [p] of the way through a cutting motion.
///
/// [box] is the rectangle being cut, in the coordinates [what] draws in.
/// Returns false where the motion is not a cutting one, so a caller can fall
/// through to the ordinary transform.
bool paintCutEffect(ui.Canvas canvas, Rect box, TextMotion motion,
    EffectSpec effect, double p, void Function() what) {
  if (!motion.cuts || box.isEmpty) return false;
  // Cutting is the one place an overshoot has nothing to say: a block cannot
  // be more than resolved, and a tile past its own place is a tile in the
  // next one's. The curve still shapes how it gets there.
  p = p.clamp(0.0, 1.0);
  if (p >= 1) {
    what();
    return true;
  }
  if (p <= 0) return true;
  switch (motion) {
    case TextMotion.mosaic:
      _paintMosaic(canvas, box, effect, p, what);
    case TextMotion.glitch:
      _paintGlitch(canvas, box, effect, p, what);
    case TextMotion.pieces:
      _paintPieces(canvas, box, effect, p, what);
    default:
      return false;
  }
  return true;
}

/// _paintMosaic draws the thing coarse and lets it resolve.
///
/// Not tiles of a flat colour worked out by hand -- there is no way to ask a
/// canvas what colour it just drew without going through an image, and an
/// image cannot be made in the middle of a paint. What does it instead is a
/// pair of matrix filters on one layer: the drawing is scaled *down* with
/// nearest-neighbour sampling, so each block keeps one pixel's worth of
/// colour, and then straight back up with nearest again, so that pixel is a
/// block. Real averaging, done by the sampler, at whatever resolution the
/// canvas happens to be.
void _paintMosaic(ui.Canvas canvas, Rect box, EffectSpec effect, double p,
    void Function() what) {
  // The coarsest block is the element cut into [pieces] across; the finest is
  // one design unit, at which point there is nothing left to see and the
  // thing is simply drawn.
  var coarsest = box.width / math.max(1, effect.pieces);
  var cell = coarsest * (1 - p);
  if (cell <= 1.05) {
    what();
    return;
  }

  // About the box's own corner rather than the origin, or the grid would
  // crawl as the element moved and the blocks would not line up with it.
  var k = 1 / cell;

  // The shrinking is a *canvas transform* and the magnifying is the layer's
  // filter, rather than two filters composed. Composed, the two matrices
  // multiply out to nothing before anything is drawn, no resampling happens
  // and the picture comes back exactly as it went in -- which is what the
  // first version of this did. Drawn small and then magnified, the small
  // drawing is what gets rasterised, and nearest-neighbour magnification
  // turns each of its pixels into a block.
  canvas.saveLayer(
      box.inflate(cell * 2),
      Paint()
        ..imageFilter = ui.ImageFilter.matrix(_about(box.left, box.top, cell),
            filterQuality: FilterQuality.none));
  canvas.save();
  canvas.translate(box.left, box.top);
  canvas.scale(k, k);
  canvas.translate(-box.left, -box.top);
  what();
  canvas.restore();
  canvas.restore();
}

/// _paintGlitch is a picture on a broken signal: bands torn sideways, rows
/// showing the wrong part of the picture, dropouts, and the colour channels
/// coming apart.
///
/// The thing that makes it read as a glitch rather than as a slide is that it
/// **jumps**. A displacement worked out from the progress alone slides
/// smoothly from far to near, which is a transform with a torn edge -- the
/// eye reads it as the element sliding in slices. So the progress is chopped
/// into ticks and everything is worked out from the tick: within one tick
/// nothing moves at all, and at the next every band is somewhere new. The
/// tears hold and snap the way a dropped frame does.
///
/// Everything else is tied to how far through it is, so the damage thins out
/// rather than stopping dead: fewer bands tear, they tear less far, the
/// dropouts stop, and the colour channels come back together.
void _paintGlitch(ui.Canvas canvas, Rect box, EffectSpec effect, double p,
    void Function() what) {
  var slices = math.max(3, effect.pieces);
  var height = box.height / slices;

  // Held for a tick and then somewhere else. Twelve over the whole arrival is
  // about two a second at the usual length, which is the rate a broken signal
  // actually stutters at -- fast enough to be damage, slow enough to see.
  const ticks = 12;
  var tick = (p * ticks).floor();
  var moment = effect.seed * 7919 + tick * 104729;

  // How much damage, held for the tick as well. Taken from the progress
  // itself it creeps down between jumps, and every band that was torn creeps
  // back towards its place -- which is the sliding this is meant not to do.
  // Stepped, a tick is a state: it holds completely still and then the whole
  // picture is somewhere else. The last tick still has damage in it and the
  // frame after it is clean, which is how a signal recovers.
  var strength = 1 - tick / ticks;

  // Steps rather than any number, because the displacement of a broken
  // picture is a whole number of blocks. A continuous one reads as a wobble.
  var step = box.width * 0.04;
  var reach = (box.width * 0.4 * strength / step).ceil();

  /// _tear is what happens to band [i] this tick: how far sideways, how far
  /// the rows inside it are taken from, and whether it is there at all.
  (double, double, bool) tearOf(int i) {
    var roll = _noise(moment, i);
    // Most bands are untouched at any one moment. All of them moving is a
    // wobble; a few of them moving is damage.
    if (roll > 0.30 + 0.35 * strength) return (0, 0, true);
    var away =
        ((_noise(moment + 11, i) - 0.5) * 2 * reach).roundToDouble() * step;
    // A row showing a piece of the picture from somewhere else, which is what
    // a signal losing its place looks like. Whole bands, so it reads as the
    // wrong row rather than as a smear.
    var wrong = _noise(moment + 23, i) < 0.35 * strength
        ? ((_noise(moment + 29, i) - 0.5) * 6).roundToDouble() * height
        : 0.0;
    // And occasionally nothing at all: the band drops out.
    var shown = _noise(moment + 37, i) > 0.12 * strength;
    return (away, wrong, shown);
  }

  /// _torn draws every band where this tick puts it, [shift] further over.
  void torn(double shift) {
    for (var i = 0; i < slices; i++) {
      var (away, wrong, shown) = tearOf(i);
      if (!shown) continue;
      var top = box.top + i * height;
      canvas.save();
      // Clipped to the band in the finished picture, then the drawing moved
      // underneath it -- so what shows through the band is whatever part of
      // the element the offset brings there.
      canvas.clipRect(
          Rect.fromLTRB(box.left, top, box.right, top + height + 0.5));
      canvas.translate(away + shift, wrong);
      what();
      canvas.restore();
    }
  }

  // The colour channels first and behind, so the picture sits on its own
  // fringe rather than under it. Red one way and cyan the other is the
  // separation a mistimed signal has, and it is what says "broken" rather
  // than "cut up".
  if (strength > 0.02) {
    var fringe = box.width * 0.03 * strength;
    for (var (colour, side) in [
      (const Color(0xFFFF0040), -fringe),
      (const Color(0xFF00FFE0), fringe),
    ]) {
      canvas.saveLayer(
          box.inflate(box.width),
          Paint()
            ..colorFilter = ui.ColorFilter.mode(colour, BlendMode.srcATop)
            ..color = Color.fromRGBO(0, 0, 0, 0.6 * strength)
            ..blendMode = BlendMode.plus);
      torn(side);
      canvas.restore();
    }
  }
  torn(0);
}

/// _paintPieces cuts the thing into a grid and gives every tile its own
/// arrival: thrown out from the middle, turned, and faded.
///
/// The tiles are roughly square whatever shape the element is, so a wide
/// banner is cut into a long row of squares rather than into slivers.
void _paintPieces(ui.Canvas canvas, Rect box, EffectSpec effect, double p,
    void Function() what) {
  var across = math.max(1, effect.pieces);
  var wide = box.width / across;
  var down = math.max(1, (box.height / math.max(0.5, wide)).round());
  var tall = box.height / down;
  var count = across * down;

  for (var i = 0; i < count; i++) {
    var col = i % across;
    var row = i ~/ across;
    var tile = Rect.fromLTWH(
        box.left + col * wide, box.top + row * tall, wide + 0.5, tall + 0.5);

    // Each tile's own moment. The order is the shuffle, not the reading
    // order: tiles arriving left to right is a wipe, and what this is meant
    // to look like is a thing coming together from everywhere at once.
    var slot = _shuffled(effect.seed, i, count);
    var at = _stagger(p, slot, count, effect.stagger);
    if (at <= 0) continue;

    canvas.save();
    if (at < 1) {
      var centre = tile.center;
      // Thrown outwards from the middle of the element, so the pieces open
      // like something breaking rather than drifting one way.
      var away = centre - box.center;
      var reach = math.max(1.0, away.distance);
      var throwBy = _throwFrom(box) * effect.scatter * (1 - at);
      var jitter = _noise(effect.seed + 7, i) - 0.5;
      canvas.translate(away.dx / reach * throwBy + jitter * throwBy * 0.6,
          away.dy / reach * throwBy + (1 - at) * (1 - at) * tall * 2 * jitter);
      if (effect.spin != 0) {
        canvas.translate(centre.dx, centre.dy);
        canvas.rotate(effect.spin *
            2 *
            math.pi *
            (1 - at) *
            (_noise(effect.seed + 13, i) - 0.5) *
            2);
        canvas.translate(-centre.dx, -centre.dy);
      }
      canvas.saveLayer(tile.inflate(math.max(wide, tall) * 2),
          Paint()..color = Color.fromRGBO(0, 0, 0, at));
    }
    canvas.clipRect(tile);
    what();
    if (at < 1) canvas.restore();
    canvas.restore();
  }
}

/// _throwFrom is the distance a scatter of 1 throws a piece.
///
/// The short side, except on something long and thin, where the short side is
/// a couple of units and every piece would stay exactly where it was: a line
/// coming apart looked like a line dissolving. A quarter of the long side is
/// what a line has instead, and on anything squarer the short side is still
/// the larger of the two and nothing changes.
double _throwFrom(Rect box) =>
    math.max(box.shortestSide, box.longestSide * 0.25);

/// _stagger is how far piece [slot] of [count] has got when the whole thing is
/// [p] through, with [spread] of the time given over to the stagger.
double _stagger(double p, int slot, int count, double spread) {
  if (count <= 1 || spread <= 0) return p.clamp(0.0, 1.0);
  var each = 1 - spread;
  if (each <= 0.01) each = 0.01;
  var start = (slot / math.max(1, count - 1)) * spread;
  return ((p - start) / each).clamp(0.0, 1.0);
}

/// _noise is a repeatable 0..1 from two whole numbers.
///
/// Worked out rather than drawn from a random number generator, so the same
/// document scatters the same way on every machine and on every frame of an
/// export. A generator consulted during a paint would give a different answer
/// each time the same frame was drawn.
double _noise(int seed, int i) {
  var n = (seed * 374761393 + i * 668265263) & 0x7FFFFFFF;
  n = (n ^ (n >> 13)) * 1274126177 & 0x7FFFFFFF;
  return ((n ^ (n >> 16)) & 0xFFFF) / 0xFFFF;
}

/// _shuffled is where piece [i] comes in the order, which is a shuffle of
/// 0..count rather than the reading order.
int _shuffled(int seed, int i, int count) =>
    (_noise(seed + 3, i) * count).floor().clamp(0, math.max(0, count - 1));

/// _about is a scale about a point, as the flat column-major list
/// ImageFilter.matrix wants.
Float64List _about(double x, double y, double by) => Float64List.fromList([
      by, 0, 0, 0, //
      0, by, 0, 0, //
      0, 0, 1, 0, //
      x - x * by, y - y * by, 0, 1, //
    ]);

/// paintArriving draws [what] part way through [animation], wherever [pose]
/// says it has got to.
///
/// The whole of what a shape or a picture needs to animate. One function
/// rather than a branch in every element's painter: an element is drawn by a
/// closure, and everything here is about the rectangle it is drawn in.
///
/// The two channels are the ones a chart and a headline already use -- reveal
/// on the way in and close on the way out -- so an element with no keyframes
/// gets 1 and 0, which is "all of it, and not leaving", and is drawn exactly
/// as it was before any of this existed.
void paintArriving(ui.Canvas canvas, Rect box, ElementAnimation animation,
    Keyframe pose, void Function() what) {
  // A line drawn flat has a box with no height at all, and every motion here
  // is a fraction of the box: a slide would travel nothing and a grid of
  // tiles would have no rows. Given some, they behave like anything else.
  var bounds = box.width < 1 || box.height < 1
      ? Rect.fromCenter(
          center: box.center,
          width: math.max(box.width, 1),
          height: math.max(box.height, 1))
      : box;
  var closing = (pose.values[KeyframeChannel.close] ?? 0) > 0;
  if (!animation.on && !(closing && animation.closes)) {
    what();
    return;
  }

  // Leaving is the arrival played backwards, which is where a destruction
  // comes from: the tiles of Build up, run the other way, are a thing coming
  // apart. See ElementAnimation.exit.
  var playing = closing && animation.closes ? animation.leaving : animation;
  var at = closing && animation.closes
      ? 1 - (pose.values[KeyframeChannel.close] ?? 0)
      : (pose.values[KeyframeChannel.reveal] ?? 1);
  // Finished is decided by where the playhead is, never by the eased number.
  // An overshoot and a spring both pass 1 and come back -- that is the whole
  // of what they are -- so a check on the eased value drew the element as
  // arrived the moment it first went past its place, and the overshoot, the
  // wobble and the settle were all thrown away. The two curves looked like
  // ease-out with a longer name.
  var settled = at >= 1;
  if (settled) {
    what();
    return;
  }
  if (at <= 0) return;
  var p = playing.progressAt(at.clamp(0.0, 1.0).toDouble());

  // Cut up where the preset cuts, unless there is nothing to cut -- in which
  // case it falls through and arrives as an ordinary fade rather than not
  // arriving at all.
  if (playing.preset.cuts &&
      paintCutEffect(
          canvas, bounds, playing.preset.motion, playing.effect, p, what)) {
    return;
  }

  var frame = applyMotionSpec(canvas, bounds, playing.preset.spec, p,
      from: playing.scaleFor(playing.preset));
  if (frame.alpha >= 0.999) {
    what();
  } else if (frame.alpha > 0.002) {
    // Through a layer, and a generous one: a shape's shadow or a picture's
    // outline reaches outside its own bounds, and a layer cut to them is a
    // glow that disappears the moment the element is half way in.
    canvas.saveLayer(bounds.inflate(math.max(bounds.width, bounds.height)),
        Paint()..color = Color.fromRGBO(0, 0, 0, frame.alpha));
    what();
    canvas.restore();
  }
  for (var i = 0; i < frame.depth; i++) {
    canvas.restore();
  }
}
