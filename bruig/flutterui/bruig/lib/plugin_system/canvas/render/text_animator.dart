import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/element_effects.dart';
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

/// TextDrawPhase is which half of an animated paragraph a pass draws.
///
/// A paragraph with a picture or a pattern showing through it cannot be drawn
/// in one pass: the letters are cut out of a layer the fill is composited
/// into, and the outline and the drawn marks must stay *outside* that layer
/// or the picture would cover them -- an outlined headline with no outline,
/// and a highlighter band in the colour of the pattern rather than its own.
///
/// So it is drawn twice, and this says which half each pass is for. Before
/// there was such a thing, the second pass was the whole animation run again
/// with the outline handed in as though it were the words -- which is why
/// Draw the outline did nothing at all over a pattern (each pass had only one
/// paragraph, and the preset needs both), why the outline it invents appeared
/// at full strength for the whole animation, and why a highlight band ended
/// up with the pattern painted over it.
enum TextDrawPhase {
  /// all is one pass: the outline behind the letters, the marks, the words.
  /// Everything painted with a plain colour.
  all,

  /// behind is what is drawn outside the layer a fill is cut to: the outline
  /// in its own colour and the marks in theirs.
  behind,

  /// letters is the words alone, which is what the fill is cut to.
  letters;

  bool get drawsOutline => this != TextDrawPhase.letters;
  bool get drawsMarks => this != TextDrawPhase.letters;
  bool get drawsLetters => this != TextDrawPhase.behind;
}

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
      // Only the lines the range touches, where there is one -- and only the
      // part of the line the range covers. The whole line, as this was, is
      // why "rise behind a mask" pointed at one word raised the line it was
      // in rather than the word.
      if (range != null) {
        Rect? mine;
        for (var b in painter.getBoxesForSelection(
            TextSelection(baseOffset: range.$1, extentOffset: range.$2))) {
          var r = b.toRect();
          if (r.center.dy < box.top || r.center.dy > box.bottom) continue;
          mine = mine == null ? r : mine.expandToInclude(r);
        }
        if (mine == null) continue;
        out.add(TextPiece(
            Rect.fromLTRB(mine.left, box.top, mine.right, box.bottom),
            range.$1,
            range.$2));
        continue;
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

/// _Layer is one part of the text arriving on its own account: which
/// characters, how, and how far through it is.
class _Layer {
  final (int, int) range;
  final TextAnimation animation;
  final double reveal;
  const _Layer(this.range, this.animation, this.reveal);
}

/// layersFor is the parts that are arriving on their own account.
///
/// A part without an animation of its own is not a layer: it is drawn with
/// the rest of the paragraph, in whatever colour and weight it asked for.
List<_Layer> _layersFor(TextPainter painter, String text, List<TextPart> parts,
    List<PartTiming> timings) {
  var out = <_Layer>[];
  for (var (i, part) in parts.indexed) {
    if (!part.animation.on) continue;
    var range = rangeOf(text, part);
    if (range == null) continue;
    out.add(_Layer(range, part.animation.asAnimation,
        i < timings.length ? timings[i].words : 1));
  }
  return out;
}

/// _boxesOf is the rectangles some characters occupy, at [offset].
List<Rect> _boxesOf(TextPainter painter, (int, int) range, Offset offset) => [
      for (var b in painter.getBoxesForSelection(
          TextSelection(baseOffset: range.$1, extentOffset: range.$2)))
        b.toRect().shift(offset).inflate(1),
    ];

/// paintAnimatedText draws [painter] at [offset] with [animation] applied,
/// [reveal] of the way through -- and each part that has an animation of its
/// own at its own moment.
///
/// [painter] is the paragraph already laid out -- the same one the still
/// drawing uses -- so what arrives is exactly what will be there when it has
/// arrived. An animation that laid its own text out would be a second
/// opinion about where every word goes.
/// [outline] is the same paragraph laid out as an outline, where the text has
/// one. It moves with the fill rather than being drawn once and left behind,
/// which is what an outlined headline sliding out from under its own outline
/// looked like.
///
/// The paragraph is drawn in layers: the words nobody has singled out, with
/// the singled-out ones cut out of it, and then each of those with its own
/// preset and its own progress. That is what lets a line arrive and one word
/// in it land two frames later -- and it is why the cut-out is done with a
/// clip rather than by drawing the rest of the sentence twice.
/// [soft] is the shadow and the glow, laid out as a paragraph of their own.
/// It travels with the words like the outline does, and unlike the outline it
/// is never written on by a pen: what falls behind the letters is there
/// because the letters are, from the first frame.
/// [keep] draws only some of the pieces, which is what a column is: the same
/// paragraph, drawn a few lines at a time at different places, with the
/// stagger still counted across the whole of it.
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
  TextPainter? soft,
  List<TextPart> parts = const [],
  List<PartTiming> timings = const [],
  bool Function(TextPiece)? keep,

  /// phase is which half of the drawing this pass is for -- see
  /// TextDrawPhase. Everything but a paragraph with a fill draws all of it.
  TextDrawPhase phase = TextDrawPhase.all,

  /// asOne draws the paragraph without layers, however many of its parts
  /// arrive on their own account.
  ///
  /// What the way out is: a part has a moment of its own on the way *in* --
  /// it lands after the line it is in -- and on the way out the whole
  /// paragraph goes together. A part that sat still while the line it
  /// belongs to left would be an exit with a word left behind in mid-air.
  bool asOne = false,
}) {
  var layers =
      asOne ? const <_Layer>[] : _layersFor(painter, text, parts, timings);
  var holes = <Rect>[
    for (var layer in layers) ..._boxesOf(painter, layer.range, offset),
  ];

  _paintBase(canvas, painter, text, spec, offset, animation, reveal,
      outline: outline,
      soft: soft,
      maxWidth: maxWidth,
      holes: holes,
      layers: layers,
      keep: keep,
      phase: phase);

  for (var layer in layers) {
    _paintLayer(canvas, painter, text, spec, offset, layer,
        outline: outline,
        soft: soft,
        maxWidth: maxWidth,
        keep: keep,
        phase: phase);
  }
}

/// _paintBase draws the words that are not singled out, with the ones that
/// are cut out of them.
void _paintBase(
  ui.Canvas canvas,
  TextPainter painter,
  String text,
  TextSpec spec,
  Offset offset,
  TextAnimation animation,
  double reveal, {
  TextPainter? outline,
  TextPainter? soft,
  double maxWidth = 0,
  List<Rect> holes = const [],
  List<_Layer> layers = const [],
  bool Function(TextPiece)? keep,
  TextDrawPhase phase = TextDrawPhase.all,
}) {
  var preset = animation.preset;

  /// still draws the paragraph as it stands, minus the holes.
  ///
  /// [withOutline] is false for the one frame before a stroke has begun to be
  /// drawn: the words are there from the start -- that is the whole of what a
  /// mark drawn on them means -- but the stroke has not been written yet.
  void still({bool withOutline = true}) {
    canvas.save();
    for (var hole in holes) {
      canvas.clipRect(hole, clipOp: ui.ClipOp.difference);
    }
    if (phase.drawsOutline) soft?.paint(canvas, offset);
    if (withOutline && phase.drawsOutline) outline?.paint(canvas, offset);
    if (phase.drawsLetters) painter.paint(canvas, offset);
    canvas.restore();
  }

  if (!animation.on) {
    still();
    return;
  }
  // A drawn decoration stays. An underline taken away the moment it finishes
  // being drawn is not an underline, it is a flicker -- these motions put
  // something under or behind the words and leave it there.
  if (reveal >= 1 && !animation.keeps) {
    still();
    return;
  }
  // Nothing has happened yet -- unless what is being animated is a mark
  // drawn *on* the words, in which case the words are already there and it
  // is only the mark that is on its way. A draw preset used to hide the
  // headline until the first frame was over.
  if (reveal <= 0) {
    if (animation.keeps && animation.draw.start == TextDrawStart.showText) {
      still(withOutline: preset.motion != TextMotion.strokeOn);
    }
    return;
  }

  // Scramble is the one motion that changes the letters rather than moving
  // them, so it is drawn from its own text rather than from the paragraph.
  if (preset.motion == TextMotion.scramble) {
    // The letters it invents are the words themselves, so there is nothing
    // for the outline pass to draw: a scrambled paragraph is not outlined
    // while it settles.
    if (!phase.drawsLetters) return;
    canvas.save();
    for (var hole in holes) {
      canvas.clipRect(hole, clipOp: ui.ClipOp.difference);
    }
    _paintScramble(canvas, text, spec, offset, animation, reveal,
        maxWidth: maxWidth <= 0 ? painter.width : maxWidth);
    canvas.restore();
    return;
  }

  var pieces = piecesFor(painter, text, preset.scope);
  var mine = <int>[];
  for (var (i, piece) in pieces.indexed) {
    // A piece that is one of the singled-out parts belongs to that part's own
    // layer, not to this one. Anything bigger than a part -- a whole line, a
    // whole paragraph -- stays here and has the part clipped out of it.
    var inside = false;
    for (var layer in layers) {
      if (piece.start >= layer.range.$1 && piece.end <= layer.range.$2) {
        inside = true;
        break;
      }
    }
    if (inside) continue;
    if (keep != null && !keep(piece)) continue;
    mine.add(i);
  }

  paintAnimatedPieces(
      canvas, painter, offset, pieces, mine, spec, animation, reveal,
      outline: outline, soft: soft, holes: holes, phase: phase);
}

/// _paintLayer draws one part of the text arriving on its own account.
void _paintLayer(
  ui.Canvas canvas,
  TextPainter painter,
  String text,
  TextSpec spec,
  Offset offset,
  _Layer layer, {
  TextPainter? outline,
  TextPainter? soft,
  double maxWidth = 0,
  bool Function(TextPiece)? keep,
  TextDrawPhase phase = TextDrawPhase.all,
}) {
  var animation = layer.animation;
  var preset = animation.preset;
  var boxes = _boxesOf(painter, layer.range, offset);
  if (boxes.isEmpty) return;

  /// inside draws [what] clipped to the part's own letters, so nothing it
  /// does can spill over the words either side of it.
  void inside(void Function() what) {
    canvas.save();
    var clip = boxes.first;
    for (var b in boxes.skip(1)) {
      clip = clip.expandToInclude(b);
    }
    canvas.clipRect(clip.inflate(clip.height));
    what();
    canvas.restore();
  }

  // Not yet: the part is simply not there. The rest of the line is, which is
  // the whole point of a part having a moment of its own.
  if (layer.reveal <= 0 && !animation.keeps) return;

  if (layer.reveal >= 1 && !animation.keeps) {
    // Arrived: drawn as it stands, in the hole the base left for it.
    inside(() {
      if (phase.drawsOutline) soft?.paint(canvas, offset);
      if (phase.drawsOutline) outline?.paint(canvas, offset);
      if (phase.drawsLetters) painter.paint(canvas, offset);
    });
    return;
  }

  if (preset.motion == TextMotion.scramble && !phase.drawsLetters) return;
  if (preset.motion == TextMotion.scramble) {
    inside(() => _paintScramble(
        canvas, text, spec, offset, animation, layer.reveal,
        maxWidth: maxWidth <= 0 ? painter.width : maxWidth,
        range: layer.range));
    return;
  }

  var pieces = piecesFor(painter, text, preset.scope, range: layer.range);
  var mine = [
    for (var (i, piece) in pieces.indexed)
      if (keep == null || keep(piece)) i,
  ];
  paintAnimatedPieces(
      canvas, painter, offset, pieces, mine, spec, animation, layer.reveal,
      outline: outline, soft: soft, restricted: true, phase: phase);
}

/// wholeBlockMotion is whether [motion] is one that applyMotion carries out
/// on its own, with nothing left for the caller to draw.
///
/// The six it is not are the ones that draw something besides the words --
/// the copies of an echo or a trail, the outline a strokeOn fills in, the
/// mark an underline or a highlight leaves, the letters a scramble invents.
/// Those have to go through _paintPiece, which has the paragraph in its hand.
/// The rest are a transform and an opacity, which means they can be applied
/// once to a whole group -- a paragraph in columns, an icon beside the words
/// -- instead of piece by piece. See paintTextInColumns.
bool wholeBlockMotion(TextMotion motion) =>
    // A cutting motion draws the thing a tile at a time, so there is nothing
    // applyMotion can do around a group on its behalf.
    !motion.cuts &&
    motion != TextMotion.echo &&
    motion != TextMotion.trail &&
    motion != TextMotion.strokeOn &&
    motion != TextMotion.underline &&
    motion != TextMotion.highlight &&
    motion != TextMotion.scramble;

/// movesAsOneBlock is whether [animation] can be applied to a group of things
/// as a single transform: the whole paragraph moves together, and the motion
/// has nothing of its own to draw.
bool movesAsOneBlock(TextAnimation animation) =>
    animation.on &&
    animation.preset.scope == TextAnimationScope.block &&
    wholeBlockMotion(animation.preset.motion);

/// motionRoom is the rectangle a piece of text can be in while [animation]
/// plays, given that it rests in [box].
///
/// Anything that has to cover the words has to cover them where they are on
/// the way in, not only where they stop: a paragraph sliding in from the
/// right spends the animation outside its own box, and a picture drawn across
/// the box alone left the letters out there hollow -- an outline round
/// nothing -- until they arrived. Generous on purpose: it sizes a layer, so
/// too much costs a little memory and too little cuts the drawing.
Rect motionRoom(Rect box, TextAnimation animation) {
  if (!animation.on || box.isEmpty) return box;
  var preset = animation.preset;

  // Where it comes in from, both ways: the same preset is played backwards on
  // the way out.
  var dx = box.width * preset.dx.abs();
  var dy = box.height * preset.dy.abs();

  // And how far the copies of an echo or a trail are strung out.
  if (preset.motion == TextMotion.echo || preset.motion == TextMotion.trail) {
    var spread =
        animation.echo.copies * animation.echo.spacing * box.height * 3;
    dx += preset.dx.abs() * spread;
    dy += preset.dy == 0 ? spread : preset.dy.abs() * spread;
  }

  var room = Rect.fromLTRB(
      box.left - dx, box.top - dy, box.right + dx, box.bottom + dy);

  // A piece that arrives too large and settles is at its largest on the first
  // frame, which is the frame that needs the room.
  if (preset.motion == TextMotion.grow) {
    var scale = math.max(1.0, animation.scaleFor(preset));
    room = Rect.fromCenter(
        center: box.center,
        width: room.width * scale,
        height: room.height * scale);
  }

  // Tiles thrown out of the box need room where they are thrown to, which is
  // as far as the scatter allows.
  if (preset.motion == TextMotion.pieces) {
    var reach = math.max(box.shortestSide, box.longestSide * 0.25);
    var thrown = reach * animation.effect.scatter;
    room = room.inflate(thrown + reach * 0.1);
  }

  // A turning rectangle sweeps out its own diagonal.
  if (preset.motion == TextMotion.spin && preset.turns != 0) {
    var reach = math.sqrt(room.width * room.width + room.height * room.height);
    room = Rect.fromCenter(center: room.center, width: reach, height: reach);
  }

  return room;
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
}) =>
    applyMotionSpec(canvas, box, preset.spec, p, from: from, seed: seed);

/// applyMotionSpec is [applyMotion] for something that is not a text preset:
/// a shape or a picture arriving, which has a motion and its numbers and no
/// paragraph at all. See MotionSpec.
MotionFrame applyMotionSpec(
  ui.Canvas canvas,
  Rect box,
  MotionSpec preset,
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
      // The outline arrives and the fill follows it. Drawn by the caller,
      // which has both paragraphs; here it is only "leave the opacity alone".
      alpha = 1;

    case TextMotion.scramble:
      break;

    case TextMotion.mosaic:
    case TextMotion.glitch:
    case TextMotion.pieces:
      // Drawn by the caller, which can draw the thing again and again -- a
      // tile at a time, a slice at a time. See paintCutEffect. Here it is
      // only "leave the opacity alone", or every tile would be faded twice.
      alpha = 1;
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
  TextPainter? soft,

  /// restricted says the pieces are some of the words rather than all of
  /// them, so even a whole-paragraph motion has to be clipped to its piece.
  /// Without it, an echo pointed at one word echoed the entire line.
  bool restricted = false,

  /// holes are the words some other layer is drawing, cut out of these so
  /// nothing is drawn twice.
  List<Rect> holes = const [],

  /// phase is which half of the drawing this pass is for. See TextDrawPhase.
  TextDrawPhase phase = TextDrawPhase.all,
}) {
  for (var i in which) {
    if (i < 0 || i >= all.length) continue;
    var p = animation.progressAt(reveal, i, all.length);
    if (p <= 0) continue;
    _paintPiece(canvas, painter, offset, all[i], animation.preset, p, spec,
        outline: outline,
        soft: soft,
        effect: animation.effect,
        from: animation.scaleFor(animation.preset),
        draw: animation.draw,
        echo: animation.echo,
        restricted: restricted,
        holes: holes,
        phase: phase);
  }
}

/// _paintPiece draws one piece of the paragraph, part way through its own
/// movement.
/// [from] is where a growing piece starts, which is the animation's own
/// setting where it has one and the preset's number otherwise.
void _paintPiece(ui.Canvas canvas, TextPainter painter, Offset offset,
    TextPiece piece, TextAnimationPreset preset, double p, TextSpec spec,
    {TextPainter? outline,
    TextPainter? soft,
    double? from,
    TextDrawSpec? draw,
    TextEchoSpec? echo,
    EffectSpec? effect,
    bool restricted = false,
    List<Rect> holes = const [],
    TextDrawPhase phase = TextDrawPhase.all}) {
  var start = (draw ?? const TextDrawSpec()).start;
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

  // The words another layer is drawing, cut out of this one. Inside the
  // motion's own frame, so they travel with it: a line rising with one word
  // animated separately keeps the gap under that word wherever the line is.
  for (var hole in holes) {
    canvas.clipRect(hole, clipOp: ui.ClipOp.difference);
  }

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

    // A resolved echo happens in two halves: the copies fan out over the
    // first, then carry on the way they were going and fade out over the
    // second, so the words are left alone at the end. Unresolved, the fan is
    // the whole animation and the copies stay.
    var resolving = spec2.resolve && !trail;
    var fanning = resolving ? (p * 2).clamp(0.0, 1.0) : p;
    var going = resolving ? (p * 2 - 1).clamp(0.0, 1.0) : 0.0;

    for (var way in ways) {
      for (var c = spec2.copies; c >= 1; c--) {
        // Each copy arrives after the one before it, so the trail fans out
        // from the words rather than appearing whole. A trail behaves the
        // other way round: the copies are already there and thin out as the
        // piece settles, which is what makes it read as speed.
        var arrived = trail
            ? 1.0
            : (fanning * (spec2.copies + 1) - (c - 1)).clamp(0.0, 1.0);
        if (arrived <= 0) continue;

        var strength = spec2.fade;
        for (var i = 1; i < c; i++) {
          strength *= spec2.fade;
        }
        if (trail) strength *= (1 - p);
        // On the way out: further off with every frame and quieter with it,
        // so the last thing that happens is the furthest copy disappearing.
        if (going > 0) strength *= (1 - going) * (1 - going);
        if (strength <= 0.002) continue;

        var away = step * (c * arrived * (1 + going * 2.5)) * way;
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
        // The copies carry the outline too: a copy of an outlined headline
        // without its outline is a copy of a different headline. The same
        // goes for what falls behind them.
        if (phase.drawsOutline) soft?.paint(canvas, offset);
        if (phase.drawsOutline) outline?.paint(canvas, offset);
        if (phase.drawsLetters) painter.paint(canvas, offset);
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
  if (preset.motion == TextMotion.highlight && phase.drawsMarks) {
    // Padded, because a band tight around the letters reads as a mistake
    // where one with a little air reads as a highlighter.
    var band = Rect.fromLTRB(
      box.left - mark.padLeft,
      box.top - mark.padTop,
      box.left - mark.padLeft + (box.width + mark.padLeft + mark.padRight) * p,
      box.bottom + mark.padBottom,
    );
    var paint = Paint()..color = markColor;
    if (mark.radius <= 0) {
      canvas.drawRect(band, paint);
    } else {
      canvas.drawRRect(
          RRect.fromRectAndRadius(band, Radius.circular(mark.radius)), paint);
    }
  }

  canvas.save();
  if (clipped) canvas.clipRect(pieceClip());
  if (preset.cuts) {
    // Cut up rather than moved: the tiles, the slices, the blocks. Drawn
    // here, where the paragraph can be drawn over and over, which is the one
    // thing applyMotion cannot do for it. The outline goes with the letters
    // -- a tile of an outlined headline without its outline is a tile of a
    // different headline -- and what falls behind them goes with them too.
    paintCutEffect(canvas, box, preset.motion, effect ?? const EffectSpec(), p,
        () {
      if (phase.drawsOutline) soft?.paint(canvas, offset);
      if (phase.drawsOutline) outline?.paint(canvas, offset);
      if (phase.drawsLetters) painter.paint(canvas, offset);
    });
  } else if (preset.motion == TextMotion.strokeOn) {
    // The pen. Where the type has an outline, it is written along the words
    // over the first half and the letters fill in behind it over the second;
    // where it has none there is no stroke to write, so the letters
    // themselves are what is written -- over the whole of it, once, with
    // nothing invented to draw first. Every colour that could be invented
    // for that stroke came from somewhere else and read as an Outline
    // setting that had turned itself on. See outlineSpecFor.
    //
    // Each pass draws its own half. Handled as one branch that needed both
    // paragraphs, the preset fell through to the plain draw below whenever a
    // pass had only one of them -- which is every paragraph with a picture or
    // a pattern showing through it, and which is why it did nothing there:
    // the motion leaves the opacity alone, so everything was drawn solid from
    // the first frame.
    // The words are already there and the stroke is drawn onto them, which
    // is what a mark drawn on words means and what every other drawn preset
    // does. Hiding them and writing them on -- as this did -- turned the
    // whole element into a wipe: the words, and the marks under them, and
    // the box behind them, all uncovering together, which is not an outline
    // being drawn on anything.
    //
    // Unless they have been told to arrive with it, which is the other half
    // of TextDrawStart and the same choice an underline offers.
    // What falls behind the words is there because the words are: drawn
    // whole, whatever the pen has got to.
    if (phase.drawsOutline) soft?.paint(canvas, offset);
    if (phase.drawsLetters) {
      if (start == TextDrawStart.fadeText) {
        _fade(canvas, box, p, () => painter.paint(canvas, offset));
      } else {
        painter.paint(canvas, offset);
      }
    }
    if (phase.drawsOutline && outline != null) {
      _writeOutline(canvas, painter, outline, offset, box, p, restricted);
    }
  } else if (alpha >= 1) {
    if (phase.drawsOutline) soft?.paint(canvas, offset);
    if (phase.drawsOutline) outline?.paint(canvas, offset);
    if (phase.drawsLetters) painter.paint(canvas, offset);
  } else {
    canvas.saveLayer(box.inflate(box.height * 2),
        Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    if (phase.drawsOutline) soft?.paint(canvas, offset);
    if (phase.drawsOutline) outline?.paint(canvas, offset);
    if (phase.drawsLetters) painter.paint(canvas, offset);
    canvas.restore();
  }
  canvas.restore();

  if (preset.motion == TextMotion.underline && phase.drawsMarks) {
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

/// _writeOutline draws as much of [ink] as has been written: line by line,
/// left to right, like a pen going along them.
///
/// A fade was not "drawing" anything -- the whole stroke simply appeared,
/// quietly, which is the same thing every other fade preset does. What reads
/// as writing is the stroke arriving *along* the words, and a moving clip is
/// the way to have that without glyph outlines: Flutter will not hand out the
/// path of a letter, so the stroke cannot be traced, but it can be uncovered.
///
/// The lines come from the paragraph's own metrics and each gets its share of
/// the time, so a second line starts when the first is finished rather than
/// every line being written at once. Each line's clip stops half way to its
/// neighbour, so the sweep never uncovers a piece of the line below.
/// [restricted] is a piece that is some of the words rather than a whole
/// paragraph -- a rectangle round a few letters, with no lines of its own --
/// which is written as one sweep.
void _writeOutline(ui.Canvas canvas, TextPainter painter, TextPainter ink,
    Offset offset, Rect box, double at, bool restricted) {
  if (at <= 0) return;
  if (at >= 1) {
    ink.paint(canvas, offset);
    return;
  }

  var rows = <Rect>[];
  if (!restricted) {
    for (var line in painter.computeLineMetrics()) {
      var top = offset.dy + line.baseline - line.ascent;
      var row = Rect.fromLTWH(offset.dx + line.left, top,
          math.max(1, line.width), math.max(1, line.height));
      // Only the lines this piece actually holds, which is what makes a
      // column write its own lines rather than all of them.
      if (row.bottom < box.top - 0.5 || row.top > box.bottom + 0.5) continue;
      rows.add(row);
    }
  }
  if (rows.isEmpty) rows.add(box);

  for (var (i, row) in rows.indexed) {
    var written = (at * rows.length - i).clamp(0.0, 1.0);
    if (written <= 0) continue;
    // Room above and below for what the stroke does outside the line's own
    // box, but never past half way to the next line: the outline painter
    // holds the whole paragraph, so a clip that reached into its neighbour
    // would uncover a slice of a line that has not been written yet.
    var above = i == 0
        ? row.height * 0.4
        : math.max(0.0, (row.top - rows[i - 1].bottom) / 2);
    var below = i == rows.length - 1
        ? row.height * 0.4
        : math.max(0.0, (rows[i + 1].top - row.bottom) / 2);
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(
        row.left - row.height * 0.5,
        row.top - above,
        row.left + (row.width + row.height * 0.3) * written,
        row.bottom + below));
    ink.paint(canvas, offset);
    canvas.restore();
  }
}

/// _fade draws [what] at [alpha], through a layer where it has to be.
void _fade(ui.Canvas canvas, Rect box, double alpha, void Function() what) {
  if (alpha <= 0) return;
  if (alpha >= 1) {
    what();
    return;
  }
  canvas.saveLayer(box.inflate(box.height * 2),
      Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
  what();
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
    {required double maxWidth,

    /// range scrambles some of the letters and leaves the rest as they are,
    /// which is what a part animated on its own account needs -- the letters
    /// around it belong to another layer and are not this one's to churn.
    (int, int)? range}) {
  const pool = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#\$%&@";
  var letters = 0;
  for (var i = 0; i < text.length; i++) {
    if (!_isSpace(text[i])) letters++;
  }

  if (range != null) {
    letters = 0;
    for (var i = range.$1; i < range.$2 && i < text.length; i++) {
      if (!_isSpace(text[i])) letters++;
    }
  }

  var resolved = 0;
  var buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    var c = text[i];
    if (_isSpace(c) || (range != null && (i < range.$1 || i >= range.$2))) {
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
