import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
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
/// [range] restricts it to some of the words -- see TextPart. A block-scoped
/// animation given one moves that range rather than the whole paragraph,
/// which is what "echo this word and leave the line alone" needs.
List<TextPiece> piecesFor(
    TextPainter painter, String text, TextAnimationScope scope,
    {(int, int)? range}) {
  if (text.isEmpty) {
    return [TextPiece(Offset.zero & painter.size, 0, text.length)];
  }

  if (scope == TextAnimationScope.block) {
    if (range == null) {
      return [TextPiece(Offset.zero & painter.size, 0, text.length)];
    }
    // The range as one piece: the box round the letters it covers.
    var boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: range.$1, extentOffset: range.$2));
    if (boxes.isEmpty) {
      return [TextPiece(Offset.zero & painter.size, 0, text.length)];
    }
    var box = boxes.first.toRect();
    for (var b in boxes.skip(1)) {
      box = box.expandToInclude(b.toRect());
    }
    return [TextPiece(box, range.$1, range.$2)];
  }

  if (scope == TextAnimationScope.line) {
    var out = <TextPiece>[];
    for (var line in painter.computeLineMetrics()) {
      var top = line.baseline - line.ascent;
      var box =
          Rect.fromLTWH(line.left, top, math.max(1, line.width), line.height);
      // Only the lines the range touches, where there is one.
      if (range != null) {
        var boxes = painter.getBoxesForSelection(
            TextSelection(baseOffset: range.$1, extentOffset: range.$2));
        var touches = boxes.any((b) {
          var r = b.toRect();
          return r.center.dy >= box.top && r.center.dy <= box.bottom;
        });
        if (!touches) continue;
      }
      out.add(TextPiece(box, 0, text.length));
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
  if (range != null) {
    ranges = [
      for (var (from, to) in ranges)
        if (from >= range.$1 && to <= range.$2) (from, to),
    ];
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

  /// parts are the element's own, so an animation pointed at one of them can
  /// find it. See TextAnimation.part.
  List<TextPart> parts = const [],
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
  // Nothing has happened yet -- unless what is being animated is a mark
  // drawn *on* the words, in which case the words are already there and it
  // is only the mark that is on its way. A draw preset used to hide the
  // headline until the first frame was over.
  if (reveal <= 0) {
    if (preset.motion.keeps && animation.draw.start == TextDrawStart.showText) {
      outline?.paint(canvas, offset);
      painter.paint(canvas, offset);
    } else if (animation.toSome) {
      // The words this is *not* happening to are there whatever it is doing
      // to the ones it is.
      var range = animation.part < parts.length
          ? rangeOf(text, parts[animation.part])
          : null;
      if (range != null) {
        canvas.save();
        for (var piece
            in piecesFor(painter, text, preset.scope, range: range)) {
          canvas.clipRect(piece.box.shift(offset).inflate(1),
              clipOp: ui.ClipOp.difference);
        }
        outline?.paint(canvas, offset);
        painter.paint(canvas, offset);
        canvas.restore();
      }
    }
    return;
  }

  // Scramble is the one motion that changes the letters rather than moving
  // them, so it is drawn from its own text rather than from the paragraph.
  if (preset.motion == TextMotion.scramble) {
    _paintScramble(canvas, text, spec, offset, animation, reveal,
        maxWidth: maxWidth <= 0 ? painter.width : maxWidth);
    return;
  }

  // Which words this happens to. Named, the rest of the paragraph is drawn
  // as it stands and only the part moves -- a headline where one word echoes
  // and the line it is in sits still.
  var range = animation.toSome && animation.part < parts.length
      ? rangeOf(text, parts[animation.part])
      : null;

  var pieces = piecesFor(painter, text, preset.scope, range: range);
  if (range != null) {
    canvas.save();
    // The rest of the words, at rest: the paragraph with the moving pieces
    // cut out of it, so nothing is drawn twice.
    for (var piece in pieces) {
      canvas.clipRect(piece.box.shift(offset).inflate(1),
          clipOp: ui.ClipOp.difference);
    }
    outline?.paint(canvas, offset);
    painter.paint(canvas, offset);
    canvas.restore();
  }

  paintAnimatedPieces(canvas, painter, offset, pieces,
      [for (var i = 0; i < pieces.length; i++) i], spec, animation, reveal,
      outline: outline, restricted: range != null);
}

/// MotionFrame is what applyMotion did: how opaque to draw, how many saves
/// it owes the canvas, and whether it has already clipped to its own shape.
class MotionFrame {
  final double alpha;
  final int depth;
  final bool clipped;
  const MotionFrame(this.alpha, this.depth, this.clipped);
}

/// applyMotion sets [canvas] up to draw something [p] of the way through
/// [preset]'s motion, and says how opaque to draw it.
///
/// The motions and nothing else -- no text, no paragraph, no glyph. That is
/// what lets the same eighteen movements drive a paragraph clipped to its
/// words *and* a letter riding a curve, which have nothing else in common:
/// one is a rectangle of a laid-out block, the other is a single glyph in a
/// rotated frame, and both are "move this box".
///
/// [box] is the piece's rectangle in whatever frame the caller is drawing in.
/// [seed] keeps a jitter still from frame to frame -- see the shake.
///
/// The caller restores [MotionFrame.depth] times when it has drawn.
MotionFrame applyMotion(
  ui.Canvas canvas,
  Rect box,
  TextAnimationPreset preset,
  double p, {
  double? from,
  int seed = 0,
}) {
  var centre = box.center;
  var alpha = p.clamp(0.0, 1.0);
  var depth = 1;
  var clipped = false;
  canvas.save();

  switch (preset.motion) {
    case TextMotion.fade:
      break;

    case TextMotion.rise:
      // A masked rise is clipped to where the piece will be, so it comes up
      // out of nothing rather than sliding over its neighbour.
      if (preset.clipped) {
        canvas.clipRect(box);
        clipped = true;
      }
      canvas.translate(
          box.width * preset.dx * (1 - p), box.height * preset.dy * (1 - p));

    case TextMotion.trail:
      // The piece arrives the way a rise does, and leaves a fading trail of
      // itself along the way -- the copies are drawn by the caller, at the
      // places it has already been.
      canvas.translate(
          box.width * preset.dx * (1 - p), box.height * preset.dy * (1 - p));

    case TextMotion.grow:
      var start = from ?? preset.from;
      var scale = start + (1 - start) * p;
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
      depth = 2;

    case TextMotion.wipe:
      canvas.clipRect(
          Rect.fromLTWH(box.left, box.top, box.width * p, box.height));
      clipped = true;
      alpha = 1;

    case TextMotion.split:
      var half = box.width / 2 * p;
      canvas.clipRect(Rect.fromLTRB(
          centre.dx - half, box.top, centre.dx + half, box.bottom));
      clipped = true;
      alpha = 1;

    case TextMotion.shake:
      // A decaying jitter, worked out from the piece's place rather than from
      // a random number: a drawing routine that consulted one would jitter
      // differently on every frame of an export.
      var away = (1 - p) * box.height * 0.25;
      canvas.translate(
          math.sin(p * 40 + seed) * away, math.cos(p * 33 + seed) * away * 0.5);
      alpha = 1;

    case TextMotion.snap:
      // No tween at all: not there, then there.
      alpha = p < 0.5 ? 0 : 1;

    case TextMotion.underline:
    case TextMotion.highlight:
    case TextMotion.echo:
      // The mark and the copies are the caller's: nothing happens to the
      // words themselves.
      alpha = 1;

    case TextMotion.strokeOn:
    case TextMotion.scramble:
      break;
  }

  return MotionFrame(alpha, depth, clipped);
}

/// paintAnimatedPieces draws some of a paragraph's pieces.
///
/// [which] is which of [all] to draw, and the progress of each is worked out
/// from its place in *all* of them -- so a paragraph flowed into three
/// columns staggers from the first word of the first column to the last word
/// of the last, rather than restarting in each.
///
/// Its own entry point because columns cannot go through the one above: each
/// column is a different slice of the same paragraph at a different offset,
/// and what it draws is the pieces whose lines belong to it.
void paintAnimatedPieces(
  ui.Canvas canvas,
  TextPainter painter,
  Offset offset,
  List<TextPiece> all,
  Iterable<int> which,
  TextSpec spec,
  TextAnimation animation,
  double reveal, {
  TextPainter? outline,

  /// restricted says the pieces are some of the words rather than all of
  /// them, so even a whole-paragraph motion has to be clipped to its piece.
  /// Without it, an echo pointed at one word echoed the entire line.
  bool restricted = false,
}) {
  for (var i in which) {
    if (i < 0 || i >= all.length) continue;
    var p = animation.progressAt(reveal, i, all.length);
    if (p <= 0) continue;
    _paintPiece(canvas, painter, offset, all[i], animation.preset, p, spec,
        outline: outline,
        from: animation.scaleFor(animation.preset),
        draw: animation.draw,
        echo: animation.echo,
        restricted: restricted);
  }
}

/// _paintPiece draws one piece of the paragraph, part way through its own
/// movement.
/// [from] is where a growing piece starts, which is the animation's own
/// setting where it has one and the preset's number otherwise.
void _paintPiece(ui.Canvas canvas, TextPainter painter, Offset offset,
    TextPiece piece, TextAnimationPreset preset, double p, TextSpec spec,
    {TextPainter? outline,
    double? from,
    TextDrawSpec? draw,
    TextEchoSpec? echo,
    bool restricted = false}) {
  var box = piece.box.shift(offset);
  var centre = box.center;

  // The motions themselves are shared with the curve -- see applyMotion --
  // so a preset moves a paragraph and a letter riding a line the same way,
  // rather than by two switches that agree until one of them is edited.
  var frame =
      applyMotion(canvas, box, preset, p, from: from, seed: piece.start);
  var alpha = frame.alpha;

  // Everything but a whole-paragraph piece is drawn by clipping the same
  // paragraph to this piece, which is what lets one layout serve every
  // letter -- and a whole-paragraph piece that has been narrowed to a part
  // is clipped too, or the piece it is meant to be moving is the whole line.
  var clipped = (preset.scope != TextAnimationScope.block || restricted) &&
      !frame.clipped;

  // The piece and nothing else. Inflated by a line height, as this was, the
  // clip took in whatever was beside it -- so a letter rising brought its
  // neighbours up with it, which is why "letter by letter" looked like whole
  // words moving and left a ghost of the next ones trailing behind it.
  //
  // A little room above and below for ascenders and descenders, which a
  // glyph box does not always take in, and none at all to the sides.
  Rect pieceClip() => Rect.fromLTRB(box.left, box.top - box.height * 0.3,
      box.right, box.bottom + box.height * 0.3);

  // The copies, under everything else: they are behind the words, and the
  // nearest is drawn last so it sits over the ones further away.
  //
  // Each copy is clipped inside its *own* moved frame rather than by the clip
  // the words use. Clipped by that one, a copy a line away from the words
  // fell entirely outside it and nothing was drawn -- which is what "echo
  // each word" did.
  if (preset.motion == TextMotion.echo || preset.motion == TextMotion.trail) {
    var spec2 = echo ?? const TextEchoSpec();
    var trail = preset.motion == TextMotion.trail;
    // A trail's copies lie back along the way the piece came, so its step is
    // the distance it is travelling; an echo's is a fixed fan.
    var step = trail
        ? Offset(piece.box.width * preset.dx * (1 - p),
                piece.box.height * preset.dy * (1 - p)) *
            (spec2.spacing / math.max(1, spec2.copies))
        : Offset(
            preset.dx * box.height * spec2.spacing,
            preset.dy == 0
                ? box.height * spec2.spacing
                : preset.dy * box.height * spec2.spacing,
          );
    // "Both ways" is the one preset that puts copies on either side, which is
    // what its turns flag says -- there being nothing to turn in an echo.
    var ways = preset.turns > 0 && !trail ? const [1.0, -1.0] : const [1.0];

    for (var way in ways) {
      for (var c = spec2.copies; c >= 1; c--) {
        // Each copy arrives after the one before it, so the trail fans out
        // from the words rather than appearing whole. A trail behaves the
        // other way round: the copies are already there and thin out as the
        // piece settles, which is what makes it read as speed.
        var arrived =
            trail ? 1.0 : (p * (spec2.copies + 1) - (c - 1)).clamp(0.0, 1.0);
        if (arrived <= 0) continue;

        var strength = spec2.fade;
        for (var i = 1; i < c; i++) {
          strength *= spec2.fade;
        }
        if (trail) strength *= (1 - p);
        if (strength <= 0.002) continue;

        var away = step * (c * arrived) * way;
        var size = math.pow(spec2.shrink, c).toDouble();

        canvas.save();
        canvas.translate(away.dx, away.dy);
        if (size != 1) {
          canvas.translate(centre.dx, centre.dy);
          canvas.scale(size, size);
          canvas.translate(-centre.dx, -centre.dy);
        }
        if (clipped) canvas.clipRect(pieceClip());
        canvas.saveLayer(
            box.inflate(box.height * 4),
            Paint()
              ..color = Color.fromRGBO(
                  0, 0, 0, (strength * arrived).clamp(0.0, 1.0)));
        painter.paint(canvas, offset);
        canvas.restore();
        canvas.restore();
      }
    }
  }

  var mark = draw ?? const TextDrawSpec();
  // Its own colour where it has been given one: a highlight in the colour of
  // the words it sits behind is a solid block.
  var markColor = mark.color ?? spec.color.withValues(alpha: 0.25);

  // The two drawn marks are painted outside the piece's own clip. Inside it,
  // the clip is the letters' box and the padding at the two ends was cut
  // straight off -- which is why the left and right padding appeared to do
  // nothing while the top and bottom worked.
  if (preset.motion == TextMotion.highlight) {
    // Padded, because a band tight around the letters reads as a mistake
    // where one with a little air reads as a highlighter.
    var band = Rect.fromLTRB(
      box.left - mark.padLeft,
      box.top - mark.padTop,
      box.left - mark.padLeft + (box.width + mark.padLeft + mark.padRight) * p,
      box.bottom + mark.padBottom,
    );
    canvas.drawRect(band, Paint()..color = markColor);
  }

  canvas.save();
  if (clipped) canvas.clipRect(pieceClip());
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
  canvas.restore();

  if (preset.motion == TextMotion.underline) {
    // The bottom padding pushes the line away from the letters; the two ends
    // shorten or lengthen it.
    var y = box.bottom - box.height * 0.08 + mark.padBottom;
    canvas.drawRect(
        Rect.fromLTWH(
            box.left - mark.padLeft,
            y,
            (box.width + mark.padLeft + mark.padRight) * p,
            math.max(1, box.height * 0.06)),
        Paint()..color = mark.color ?? spec.color);
  }

  for (var i = 0; i < frame.depth; i++) {
    canvas.restore();
  }
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
