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
// Other motions are a transform and an opacity, drawn once. These draw the
// thing once per tile or slice, so they take the drawing as a closure, which
// lets one implementation serve shapes, pictures and text.

/// paintCutEffect draws [what], [p] of the way through a cutting motion.
///
/// [box] is the rectangle being cut, in the coordinates [what] draws in.
/// Returns false where the motion is not a cutting one, so a caller can fall
/// through to the ordinary transform.
bool paintCutEffect(ui.Canvas canvas, Rect box, TextMotion motion,
    EffectSpec effect, double p, void Function() what) {
  if (!motion.cuts || box.isEmpty) return false;
  // No overshoot: a tile past its place is in the next one's.
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
/// A canvas cannot be read back mid-paint, so the drawing is drawn small and
/// magnified back up with nearest-neighbour sampling: each small pixel
/// becomes a block.
void _paintMosaic(ui.Canvas canvas, Rect box, EffectSpec effect, double p,
    void Function() what) {
  // From [pieces] blocks across down to one design unit, where it is simply
  // drawn.
  var coarsest = box.width / math.max(1, effect.pieces);
  var cell = coarsest * (1 - p);
  if (cell <= 1.05) {
    what();
    return;
  }

  var k = 1 / cell;

  // Shrunk by a canvas transform, magnified by the layer's filter: two
  // composed filters cancel out and nothing is resampled. Both scale about
  // the box's corner, so the blocks stay put as the element moves.
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
/// It jumps rather than slides: progress is chopped into ticks and everything
/// is worked out from the tick, so bands hold still and then snap somewhere
/// new. The damage thins out tick by tick.
void _paintGlitch(ui.Canvas canvas, Rect box, EffectSpec effect, double p,
    void Function() what) {
  var slices = math.max(3, effect.pieces);
  var height = box.height / slices;

  // About two a second at the usual arrival length.
  const ticks = 12;
  var tick = (p * ticks).floor();
  var moment = effect.seed * 7919 + tick * 104729;

  // Stepped too: taken from the progress, torn bands would creep back.
  var strength = 1 - tick / ticks;

  // Whole steps: a continuous displacement reads as a wobble.
  var step = box.width * 0.04;
  var reach = (box.width * 0.4 * strength / step).ceil();

  /// tearOf is what happens to band [i] this tick: how far sideways, how far
  /// the rows inside it are taken from, and whether it is shown.
  (double, double, bool) tearOf(int i) {
    var roll = _noise(moment, i);
    // Most bands are untouched at any moment.
    if (roll > 0.30 + 0.35 * strength) return (0, 0, true);
    var away =
        ((_noise(moment + 11, i) - 0.5) * 2 * reach).roundToDouble() * step;
    // A band showing another band's rows, by whole bands.
    var wrong = _noise(moment + 23, i) < 0.35 * strength
        ? ((_noise(moment + 29, i) - 0.5) * 6).roundToDouble() * height
        : 0.0;
    // Occasionally the band drops out.
    var shown = _noise(moment + 37, i) > 0.12 * strength;
    return (away, wrong, shown);
  }

  /// torn draws every band where this tick puts it, [shift] further over.
  void torn(double shift) {
    for (var i = 0; i < slices; i++) {
      var (away, wrong, shown) = tearOf(i);
      if (!shown) continue;
      var top = box.top + i * height;
      canvas.save();
      // Clipped to the band, then the drawing moved under it.
      canvas.clipRect(
          Rect.fromLTRB(box.left, top, box.right, top + height + 0.5));
      canvas.translate(away + shift, wrong);
      what();
      canvas.restore();
    }
  }

  // Red and cyan fringes first, behind the picture.
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
/// The tiles are roughly square whatever the element's shape.
void _paintPieces(ui.Canvas canvas, Rect box, EffectSpec effect, double p,
    void Function() what) {
  var across = math.max(1, effect.pieces);
  var wide = box.width / across;
  var down = (box.height / math.max(0.5, wide)).round().clamp(1, 64);
  var tall = box.height / down;
  var count = across * down;

  for (var i = 0; i < count; i++) {
    var col = i % across;
    var row = i ~/ across;
    var tile = Rect.fromLTWH(
        box.left + col * wide, box.top + row * tall, wide + 0.5, tall + 0.5);

    // Shuffled order: reading order would look like a wipe.
    var slot = _shuffled(effect.seed, i, count);
    var at = _stagger(p, slot, count, effect.stagger);
    if (at <= 0) continue;

    canvas.save();
    if (at < 1) {
      var centre = tile.center;
      // Thrown outwards from the element's middle.
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
/// The short side, or a quarter of the long side if larger, so thin things
/// such as lines still throw their pieces visibly.
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
/// A hash rather than a random generator, so a frame draws the same on every
/// paint, machine and export.
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
/// Shared by shapes and pictures: the element is drawn by a closure, and
/// everything here works on its rectangle. It reads the pose's reveal and
/// close channels (as charts and text do); missing, they are 1 and 0 and the
/// element is drawn as if not animated.
void paintArriving(ui.Canvas canvas, Rect box, ElementAnimation animation,
    Keyframe pose, void Function() what,
    {Offset? pivot}) {
  // A flat line has a box with no height, and every motion here is a
  // fraction of the box, so it is given at least one unit each way.
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

  // Leaving is the exit preset played backwards. See ElementAnimation.exit.
  var playing = closing && animation.closes ? animation.leaving : animation;
  var at = closing && animation.closes
      ? 1 - (pose.values[KeyframeChannel.close] ?? 0)
      : (pose.values[KeyframeChannel.reveal] ?? 1);
  // Finished is decided by the playhead, not the eased value: an overshoot
  // or spring passes 1 before it settles.
  var settled = at >= 1;
  if (settled) {
    what();
    return;
  }
  if (at <= 0) return;
  var p = playing.progressAt(at.clamp(0.0, 1.0).toDouble());

  // A cutting preset with nothing to cut falls through to the transform.
  if (playing.preset.cuts &&
      paintCutEffect(
          canvas, bounds, playing.preset.motion, playing.effect, p, what)) {
    return;
  }

  var spec = playing.spec;
  var frame =
      applyMotionSpec(canvas, bounds, spec, p, from: spec.from, pivot: pivot);
  if (frame.alpha >= 0.999) {
    what();
  } else if (frame.alpha > 0.002) {
    // A generous layer: shadows and outlines reach outside the bounds.
    canvas.saveLayer(bounds.inflate(math.max(bounds.width, bounds.height)),
        Paint()..color = Color.fromRGBO(0, 0, 0, frame.alpha));
    what();
    canvas.restore();
  }
  for (var i = 0; i < frame.depth; i++) {
    canvas.restore();
  }
}
