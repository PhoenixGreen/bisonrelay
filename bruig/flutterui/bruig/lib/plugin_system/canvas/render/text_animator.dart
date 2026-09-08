import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/painting.dart';

// text_animator.dart draws a paragraph part way through arriving.
//
// The idea that makes it small: a paragraph is laid out *once*, and every
// piece of it -- a line, a word, a letter -- is drawn by taking that same
// laid-out paragraph, clipping to the piece's own rectangle, and moving it.
// Nothing is measured twice and nothing is laid out per piece, so a headline
// animating letter by letter costs one layout and a transform each.
//
// The presets are a scope and a motion (see TextAnimationPreset), so what is
// here is one loop over the pieces and one switch over the motions -- not
// thirty animations. A new name in the list is a row in that table; it is
// only a new mechanism that reaches this file.

/// TextPiece is one thing that moves on its own: where it is, and where it
/// sits in the order.
class TextPiece {
  final Rect box;
  final int start;
  final int end;
  const TextPiece(this.box, this.start, this.end);
}

/// piecesFor cuts a laid-out paragraph into the things that move.
///
/// The rectangles come from the paragraph's own boxes, so a letter's box is
/// where that letter actually is -- including the bit of a line that a
/// centred paragraph indents by, which is the sort of thing that is wrong by
/// half a word if it is worked out by counting characters.
List<TextPiece> piecesFor(
    TextPainter painter, String text, TextAnimationScope scope) {
  if (scope == TextAnimationScope.block || text.isEmpty) {
    return [TextPiece(Offset.zero & painter.size, 0, text.length)];
  }

  if (scope == TextAnimationScope.line) {
    var out = <TextPiece>[];
    for (var line in painter.computeLineMetrics()) {
      var top = line.baseline - line.ascent;
      out.add(TextPiece(
        Rect.fromLTWH(line.left, top, math.max(1, line.width), line.height),
        0,
        text.length,
      ));
    }
    return out.isEmpty
        ? [TextPiece(Offset.zero & painter.size, 0, text.length)]
        : out;
  }

  // Words and letters, from the ranges of the text itself.
  var ranges = <(int, int)>[];
  if (scope == TextAnimationScope.word) {
    var at = 0;
    while (at < text.length) {
      while (at < text.length && _isSpace(text[at])) {
        at++;
      }
      var from = at;
      while (at < text.length && !_isSpace(text[at])) {
        at++;
      }
      if (at > from) ranges.add((from, at));
    }
  } else {
    for (var i = 0; i < text.length; i++) {
      if (!_isSpace(text[i])) ranges.add((i, i + 1));
    }
  }

  var out = <TextPiece>[];
  for (var (from, to) in ranges) {
    var boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: from, extentOffset: to));
    if (boxes.isEmpty) continue;
    var box = boxes.first.toRect();
    for (var b in boxes.skip(1)) {
      box = box.expandToInclude(b.toRect());
    }
    out.add(TextPiece(box, from, to));
  }
  return out.isEmpty
      ? [TextPiece(Offset.zero & painter.size, 0, text.length)]
      : out;
}

bool _isSpace(String c) => c.trim().isEmpty;

/// paintAnimatedText draws [painter] at [offset] with [animation] applied,
/// [reveal] of the way through.
///
/// [painter] is the paragraph already laid out -- the same one the still
/// drawing uses -- so what arrives is exactly what will be there when it has
/// arrived. An animation that laid its own text out would be a second
/// opinion about where every word goes.
/// [outline] is the same paragraph laid out as an outline, where the text has
/// one. It moves with the fill rather than being drawn once and left behind,
/// which is what an outlined headline sliding out from under its own outline
/// looked like.
void paintAnimatedText(
  ui.Canvas canvas,
  TextPainter painter,
  String text,
  TextSpec spec,
  Offset offset,
  TextAnimation animation,
  double reveal, {
  double maxWidth = 0,
  TextPainter? outline,
}) {
  var preset = animation.preset;
  if (!animation.on) {
    painter.paint(canvas, offset);
    return;
  }
  // A drawn decoration stays. An underline taken away the moment it finishes
  // being drawn is not an underline, it is a flicker -- these motions put
  // something under or behind the words and leave it there.
  if (reveal >= 1 && !preset.motion.keeps) {
    painter.paint(canvas, offset);
    return;
  }
  if (reveal <= 0) return;

  // Scramble is the one motion that changes the letters rather than moving
  // them, so it is drawn from its own text rather than from the paragraph.
  if (preset.motion == TextMotion.scramble) {
    _paintScramble(canvas, text, spec, offset, animation, reveal,
        maxWidth: maxWidth <= 0 ? painter.width : maxWidth);
    return;
  }

  var pieces = piecesFor(painter, text, preset.scope);
  for (var (i, piece) in pieces.indexed) {
    var p = animation.progressAt(reveal, i, pieces.length);
    if (p <= 0) continue;
    _paintPiece(canvas, painter, offset, piece, preset, p, spec,
        outline: outline);
  }
}

/// _paintPiece draws one piece of the paragraph, part way through its own
/// movement.
void _paintPiece(ui.Canvas canvas, TextPainter painter, Offset offset,
    TextPiece piece, TextAnimationPreset preset, double p, TextSpec spec,
    {TextPainter? outline}) {
  var box = piece.box.shift(offset);
  var centre = box.center;
  var alpha = p.clamp(0.0, 1.0);

  canvas.save();

  // Everything but the block scope is drawn by clipping the whole paragraph
  // to this piece, which is what lets one layout serve every letter.
  var clipped = preset.scope != TextAnimationScope.block;
  switch (preset.motion) {
    case TextMotion.fade:
      break;

    case TextMotion.rise:
      var dx = piece.box.width * preset.dx * (1 - p);
      var dy = piece.box.height * preset.dy * (1 - p);
      // A masked rise is clipped to where the piece will be, so it comes up
      // out of nothing rather than sliding over its neighbour.
      if (preset.clipped) {
        canvas.clipRect(box);
        clipped = false;
      }
      canvas.translate(dx, dy);

    case TextMotion.grow:
      var scale = preset.from + (1 - preset.from) * p;
      canvas.translate(centre.dx, centre.dy);
      canvas.scale(scale, preset.stretch ? 1 / math.max(0.05, scale) : scale);
      canvas.translate(-centre.dx, -centre.dy);

    case TextMotion.spin:
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(preset.turns * 2 * math.pi * (1 - p));
      canvas.translate(-centre.dx, -centre.dy);

    case TextMotion.flip:
      canvas.translate(centre.dx, centre.dy);
      // Through nothing and out the other side, which is what a card turning
      // over does. Never exactly zero: a zero scale is a matrix that cannot
      // be inverted and Skia declines to draw through it.
      canvas.scale(math.max(0.02, (p * 2 - 1).abs()), 1);
      canvas.translate(-centre.dx, -centre.dy);

    case TextMotion.blur:
      canvas.saveLayer(
          box.inflate(box.height),
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
                sigmaX: box.height * 0.25 * (1 - p),
                sigmaY: box.height * 0.25 * (1 - p),
                tileMode: TileMode.decal));

    case TextMotion.wipe:
      canvas.clipRect(
          Rect.fromLTWH(box.left, box.top, box.width * p, box.height));
      clipped = false;
      alpha = 1;

    case TextMotion.split:
      var half = box.width / 2 * p;
      canvas.clipRect(Rect.fromLTRB(
          centre.dx - half, box.top, centre.dx + half, box.bottom));
      clipped = false;
      alpha = 1;

    case TextMotion.shake:
      // A decaying jitter, worked out from the piece's place rather than from
      // a random number: a drawing routine that consulted one would jitter
      // differently on every frame of an export.
      var away = (1 - p) * box.height * 0.25;
      canvas.translate(math.sin(p * 40 + piece.start) * away,
          math.cos(p * 33 + piece.start) * away * 0.5);
      alpha = 1;

    case TextMotion.snap:
      // No tween at all: not there, then there.
      alpha = p < 0.5 ? 0 : 1;

    case TextMotion.underline:
      alpha = 1;

    case TextMotion.highlight:
      alpha = 1;

    case TextMotion.strokeOn:
      break;

    case TextMotion.scramble:
      break;
  }

  // The piece and nothing else. Inflated by a line height, as this was, the
  // clip took in whatever was beside it -- so a letter rising brought its
  // neighbours up with it, which is why "letter by letter" looked like whole
  // words moving and left a ghost of the next ones trailing behind it.
  //
  // A little room above and below for ascenders and descenders, which a
  // glyph box does not always take in, and none at all to the sides.
  if (clipped) {
    canvas.clipRect(Rect.fromLTRB(box.left, box.top - box.height * 0.3,
        box.right, box.bottom + box.height * 0.3));
  }

  // The two draw-on motions put something behind or under the words rather
  // than moving them.
  if (preset.motion == TextMotion.highlight) {
    canvas.drawRect(Rect.fromLTWH(box.left, box.top, box.width * p, box.height),
        Paint()..color = spec.color.withValues(alpha: 0.25));
  }

  if (alpha >= 1) {
    outline?.paint(canvas, offset);
    painter.paint(canvas, offset);
  } else {
    canvas.saveLayer(box.inflate(box.height * 2),
        Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    outline?.paint(canvas, offset);
    painter.paint(canvas, offset);
    canvas.restore();
  }

  if (preset.motion == TextMotion.underline) {
    var y = box.bottom - box.height * 0.08;
    canvas.drawRect(
        Rect.fromLTWH(
            box.left, y, box.width * p, math.max(1, box.height * 0.06)),
        Paint()..color = spec.color);
  }

  if (preset.motion == TextMotion.blur) canvas.restore();
  canvas.restore();
}

/// _paintScramble resolves each letter from a random one.
///
/// The letters it has not resolved yet are drawn as something else, so the
/// paragraph has to be laid out again -- the one motion that cannot use the
/// paragraph it is animating. Kept to the same length and the same spaces so
/// the words do not jump about while they settle.
void _paintScramble(ui.Canvas canvas, String text, TextSpec spec, Offset offset,
    TextAnimation animation, double reveal,
    {required double maxWidth}) {
  const pool = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#\$%&@";
  var letters = 0;
  for (var i = 0; i < text.length; i++) {
    if (!_isSpace(text[i])) letters++;
  }

  var resolved = 0;
  var buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    var c = text[i];
    if (_isSpace(c)) {
      buffer.write(c);
      continue;
    }
    var p = animation.progressAt(reveal, resolved, math.max(1, letters));
    resolved++;
    if (p >= 1) {
      buffer.write(c);
    } else if (p <= 0) {
      buffer.write(" ");
    } else {
      // Stepped rather than continuous, so a letter flickers through a few
      // characters instead of changing sixty times a second.
      var step = (reveal * 12).floor() + i;
      buffer.write(pool[step % pool.length]);
    }
  }

  var painter =
      layoutText(buffer.toString(), spec, maxWidth: maxWidth, fillWidth: true);
  painter.paint(canvas, offset);
}
