import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/element_effects.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/painting.dart';

// text_animator.dart draws a paragraph part way through arriving.
//
// A paragraph is laid out once, and every piece of it (line, word, letter)
// is drawn by clipping that same layout to the piece's rectangle and moving
// it: one layout and a transform per piece.
//
// A preset is a scope and a motion (see TextAnimationPreset), so this file is
// one loop over the pieces and one switch over the motions. A new preset is a
// row in that table; only a new motion reaches this file.

/// TextDrawPhase is which half of an animated paragraph a pass draws.
///
/// A paragraph with a picture or a pattern showing through it is drawn in two
/// passes: the letters are cut out of a layer the fill is composited into,
/// and the outline and drawn marks must stay outside that layer or the fill
/// covers them.
enum TextDrawPhase {
  /// all is one pass: outline, marks and words, for a plain-colour fill.
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
/// The rectangles come from the paragraph's own boxes, not from counting
/// characters, so centred and indented lines are right.
/// [range] restricts it to some of the words (see TextPart); a block-scoped
/// animation given one moves that range rather than the whole paragraph.
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
      // With a range: only the lines it touches, and only the part of each
      // line it covers, so a line motion aimed at one word moves that word.
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

/// _layersFor is the parts that are arriving on their own account.
///
/// A part without an animation of its own is not a layer: it is drawn with
/// the rest of the paragraph.
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
/// [reveal] of the way through, and each part with an animation of its own at
/// its own moment.
///
/// [painter] is the same layout the still drawing uses, so what arrives is
/// exactly what is there once it has arrived.
/// [outline] is the same paragraph laid out as an outline, where there is
/// one; it moves with the fill.
/// [soft] is the shadow and glow, laid out on their own. It moves with the
/// words but is never written on by a pen: it is there from the first frame.
/// [keep] draws only some of the pieces, which is what a column is; the
/// stagger is still counted across the whole paragraph.
///
/// The paragraph is drawn in layers: the words nobody has singled out, with
/// the singled-out parts clipped out, then each part with its own preset and
/// progress.
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

  /// phase is which half of the drawing this pass is for. See TextDrawPhase.
  TextDrawPhase phase = TextDrawPhase.all,

  /// asOne draws the paragraph without layers, ignoring parts' own
  /// animations. Used on the way out, where the whole paragraph leaves
  /// together and no word is left behind.
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

  // still draws the paragraph as it stands, minus the holes. [withOutline] is
  // false before a stroke-on has started: the words are there, the stroke is
  // not yet.
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
  // A drawn decoration (animation.keeps) stays once drawn, so it still goes
  // through the motion at reveal 1.
  if (reveal >= 1 && !animation.keeps) {
    still();
    return;
  }
  // Nothing yet, unless it is a mark drawn on the words: then the words are
  // already there and only the mark is on its way.
  if (reveal <= 0) {
    if (animation.keeps && animation.draw.start == TextDrawStart.showText) {
      still(withOutline: preset.motion != TextMotion.strokeOn);
    }
    return;
  }

  // Scramble changes the letters rather than moving them, so it is drawn
  // from its own text. It has no outline while it settles.
  if (preset.motion == TextMotion.scramble) {
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
    // A piece inside a singled-out part belongs to that part's layer. A
    // bigger piece (a line, the paragraph) stays here with the part clipped
    // out of it.
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

  // inside draws [what] clipped round the part's own letters (inflated by a
  // line height), so it cannot spill far over the words either side.
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

  // Not yet: the part is not there, though the rest of the line may be.
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
/// The motions excluded draw something besides a transform and an opacity
/// (echo and trail copies, a strokeOn outline, an underline or highlight
/// mark, scramble's letters, a cutting motion's tiles), so they go through
/// _paintPiece. The rest can be applied once to a whole group, such as a
/// paragraph in columns. See paintTextInColumns.
bool wholeBlockMotion(TextMotion motion) =>
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
/// A fill layer has to cover the words on the way in, not only where they
/// stop. Generous on purpose: it sizes a layer, so too much costs a little
/// memory and too little cuts the drawing.
Rect motionRoom(Rect box, TextAnimation animation) {
  if (!animation.on || box.isEmpty) return box;
  var preset = animation.preset;

  // Where it comes in from, on both sides: the exit plays the preset
  // backwards.
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

  // A grow is at its largest on the first frame.
  if (preset.motion == TextMotion.grow) {
    var scale = math.max(1.0, animation.scaleFor(preset));
    room = Rect.fromCenter(
        center: box.center,
        width: room.width * scale,
        height: room.height * scale);
  }

  // Thrown tiles go as far as the scatter allows.
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
/// It knows nothing of text, only "move this box", so the same motions drive
/// a paragraph piece and a letter riding a curve.
///
/// [box] is the piece's rectangle in whatever frame the caller is drawing in.
/// [seed] keeps a shake's jitter the same from frame to frame.
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

/// MotionCall is one motion as the renderer applied it, for motionProbe.
class MotionCall {
  /// box is the thing being moved, in the canvas's own units; [before] and
  /// [after] are the canvas transform either side of the motion, so after
  /// times before's inverse is the motion alone.
  final Rect box;
  final Float64List before;
  final Float64List after;

  /// clip is the rectangle the motion clipped to, in [box]'s units, drawn
  /// with [before]; null where it did not clip.
  final Rect? clip;

  final TextMotion motion;
  final double p;

  /// blur is how far out of focus, in [box]'s units; nought for none.
  final double blur;
  final MotionFrame frame;

  const MotionCall(this.box, this.before, this.after, this.clip, this.motion,
      this.p, this.blur, this.frame);
}

/// motionProbe, when set, is told of every motion applied, as it is applied.
///
/// For the interactive EPUB, which draws each element once and has the
/// reader move it: the motion is read from the renderer frame by frame rather
/// than worked out a second time. Null everywhere else.
void Function(MotionCall call)? motionProbe;

/// applyMotionSpec is [applyMotion] for a [MotionSpec] rather than a text
/// preset: a shape or a picture arriving, or text with its own settings.
MotionFrame applyMotionSpec(
  ui.Canvas canvas,
  Rect box,
  MotionSpec preset,
  double p, {
  double? from,
  int seed = 0,

  /// pivot is what it grows, spins and flips about: its centre unless it
  /// has an anchor of its own.
  Offset? pivot,
}) {
  var centre = pivot ?? box.center;
  var alpha = p.clamp(0.0, 1.0);
  var depth = 1;
  var clipped = false;
  var probe = motionProbe;
  var before = probe == null ? null : canvas.getTransform();
  Rect? clip;
  var blur = 0.0;
  canvas.save();

  switch (preset.motion) {
    case TextMotion.fade:
      break;

    case TextMotion.rise:
      // A masked rise is clipped to where the piece will be, so it comes up
      // out of nothing rather than sliding over its neighbour.
      if (preset.clipped) {
        canvas.clipRect(clip = box);
        clipped = true;
      }
      canvas.translate(
          box.width * preset.dx * (1 - p), box.height * preset.dy * (1 - p));

    case TextMotion.trail:
      // Moves like a rise; the caller draws the trail of copies.
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
      // Through nothing and out the other side. Never exactly zero: a zero
      // scale cannot be inverted and Skia will not draw through it.
      canvas.scale(math.max(0.02, (p * 2 - 1).abs()), 1);
      canvas.translate(-centre.dx, -centre.dy);

    case TextMotion.blur:
      blur = box.height * 0.25 * (1 - p);
      canvas.saveLayer(
          box.inflate(box.height),
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
                sigmaX: box.height * 0.25 * (1 - p),
                sigmaY: box.height * 0.25 * (1 - p),
                tileMode: TileMode.decal));
      depth = 2;

    case TextMotion.wipe:
      // From the left unless dx and dy name another edge or corner, as a
      // shape's wipe does. See ElementAnimation.specFor.
      var w = preset.dx == 0 && preset.dy != 0 ? box.width : box.width * p;
      var h = preset.dy == 0 ? box.height : box.height * p;
      clip = Rect.fromLTWH(preset.dx > 0 ? box.right - w : box.left,
          preset.dy > 0 ? box.bottom - h : box.top, w, h);
      canvas.clipRect(clip);
      clipped = true;
      alpha = 1;

    case TextMotion.split:
      var half = box.width / 2 * p;
      canvas.clipRect(clip = Rect.fromLTRB(
          centre.dx - half, box.top, centre.dx + half, box.bottom));
      clipped = true;
      alpha = 1;

    case TextMotion.shake:
      // A decaying jitter from p and the seed, not a random number, so an
      // export draws the same frame the same way.
      var away = (1 - p) * box.height * 0.25;
      canvas.translate(
          math.sin(p * 40 + seed) * away, math.cos(p * 33 + seed) * away * 0.5);
      alpha = 1;

    case TextMotion.snap:
      alpha = p < 0.5 ? 0 : 1;

    case TextMotion.underline:
    case TextMotion.highlight:
    case TextMotion.echo:
      // The caller draws the mark or the copies; the words stay put.
      alpha = 1;

    case TextMotion.strokeOn:
      // The caller writes the outline and fills in behind it.
      alpha = 1;

    case TextMotion.scramble:
      break;

    case TextMotion.mosaic:
    case TextMotion.glitch:
    case TextMotion.pieces:
      // Drawn by the caller a tile or slice at a time (paintCutEffect). Full
      // opacity here, or every tile would be faded twice.
      alpha = 1;
  }

  var frame = MotionFrame(alpha, depth, clipped);
  if (probe != null) {
    probe(MotionCall(box, before!, canvas.getTransform(), clip, preset.motion,
        p, blur, frame));
  }
  return frame;
}

/// paintAnimatedPieces draws some of a paragraph's pieces.
///
/// [which] is which of [all] to draw. Each piece's progress comes from its
/// place in all of them, so a paragraph flowed into columns staggers across
/// the columns rather than restarting in each.
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
  /// them, so even a whole-paragraph motion is clipped to its piece.
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
        motion: animation.spec,
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
    {MotionSpec? motion,
    TextPainter? outline,
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

  // The animation's own spec where given one, the preset's otherwise.
  var frame = motion != null
      ? applyMotionSpec(canvas, box, motion, p,
          from: motion.from, seed: piece.start)
      : applyMotion(canvas, box, preset, p, from: from, seed: piece.start);
  var alpha = frame.alpha;

  // Every piece but an unrestricted whole paragraph is the same layout
  // clipped to the piece.
  var clipped = (preset.scope != TextAnimationScope.block || restricted) &&
      !frame.clipped;

  // The words another layer is drawing, cut out inside the motion's frame
  // so the gap travels with the piece.
  for (var hole in holes) {
    canvas.clipRect(hole, clipOp: ui.ClipOp.difference);
  }

  // The piece and nothing else: room above and below for ascenders and
  // descenders, none to the sides, or a moving letter drags its neighbours.
  Rect pieceClip() => Rect.fromLTRB(box.left, box.top - box.height * 0.3,
      box.right, box.bottom + box.height * 0.3);

  // The copies, behind the words, nearest drawn last. Each is clipped in its
  // own moved frame: the words' clip would hide a copy a line away.
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
    // An echo's turns flag means copies on both sides ("Both ways").
    var ways = preset.turns > 0 && !trail ? const [1.0, -1.0] : const [1.0];

    // A resolved echo fans out over the first half and carries on and fades
    // over the second, leaving the words alone. Unresolved, the copies stay.
    var resolving = spec2.resolve && !trail;
    var fanning = resolving ? (p * 2).clamp(0.0, 1.0) : p;
    var going = resolving ? (p * 2 - 1).clamp(0.0, 1.0) : 0.0;

    for (var way in ways) {
      for (var c = spec2.copies; c >= 1; c--) {
        // An echo's copies arrive one after another; a trail's are there
        // from the start and thin out as the piece settles.
        var arrived = trail
            ? 1.0
            : (fanning * (spec2.copies + 1) - (c - 1)).clamp(0.0, 1.0);
        if (arrived <= 0) continue;

        var strength = spec2.fade;
        for (var i = 1; i < c; i++) {
          strength *= spec2.fade;
        }
        if (trail) strength *= (1 - p);
        // Resolving: further off and quieter with every frame.
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
        // Copies carry the outline and shadow too.
        if (phase.drawsOutline) soft?.paint(canvas, offset);
        if (phase.drawsOutline) outline?.paint(canvas, offset);
        if (phase.drawsLetters) painter.paint(canvas, offset);
        canvas.restore();
        canvas.restore();
      }
    }
  }

  var mark = draw ?? const TextDrawSpec();
  // Its own colour where given one; otherwise the words' colour, faint, so a
  // highlight is not a solid block.
  var markColor = mark.color ?? spec.color.withValues(alpha: 0.25);

  // The drawn marks are painted outside the piece's clip, which would cut
  // off their side padding.
  if (preset.motion == TextMotion.highlight && phase.drawsMarks) {
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
    // Cut up rather than moved: drawn here, where the paragraph (with its
    // outline and shadow) can be drawn once per tile.
    paintCutEffect(canvas, box, preset.motion, effect ?? const EffectSpec(), p,
        () {
      if (phase.drawsOutline) soft?.paint(canvas, offset);
      if (phase.drawsOutline) outline?.paint(canvas, offset);
      if (phase.drawsLetters) painter.paint(canvas, offset);
    });
  } else if (preset.motion == TextMotion.strokeOn) {
    // The pen writes the outline along the words (_writeOutline) over words
    // that are already there, or that fade in with it under
    // TextDrawStart.fadeText. With no outline there is nothing to write and
    // no stroke is invented (see outlineSpecFor). Each phase draws its own
    // half; the shadow is drawn whole throughout.
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
/// Flutter will not hand out a letter's path, so the stroke cannot be traced;
/// it is uncovered by a moving clip instead. Each line gets its share of the
/// time, in turn. [restricted] (a piece that is some of the words) is written
/// as one sweep.
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
      // Only the lines this piece holds, so a column writes only its own.
      if (row.bottom < box.top - 0.5 || row.top > box.bottom + 0.5) continue;
      rows.add(row);
    }
  }
  if (rows.isEmpty) rows.add(box);

  for (var (i, row) in rows.indexed) {
    var written = (at * rows.length - i).clamp(0.0, 1.0);
    if (written <= 0) continue;
    // Room above and below for the stroke, but never past half way to the
    // next line: [ink] holds the whole paragraph, so a deeper clip would
    // uncover part of a line not yet written.
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
/// The only motion that lays its text out again. Same length and spaces, so
/// the words do not jump about while they settle.
void _paintScramble(ui.Canvas canvas, String text, TextSpec spec, Offset offset,
    TextAnimation animation, double reveal,
    {required double maxWidth,

    /// range scrambles only those letters, for a part with its own
    /// animation; the rest belong to another layer.
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
