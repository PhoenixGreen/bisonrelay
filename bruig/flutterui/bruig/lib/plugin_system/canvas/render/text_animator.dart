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
// The paragraph is laid out once; each piece (line, word, letter) is that
// layout clipped to the piece's rectangle and moved. A preset is a scope
// and a motion (TextAnimationPreset), so a new preset is a table row and
// only a new motion reaches this file.

/// TextDrawPhase is which half of an animated paragraph a pass draws. With a
/// picture or pattern fill, the letters are cut out of a layer the fill is
/// composited into, and the outline and marks must stay outside it or the
/// fill covers them.
enum TextDrawPhase {
  /// all is one pass: outline, marks and words, for a plain-colour fill.
  all,

  /// behind is the outline and marks, drawn outside the fill's layer.
  behind,

  /// letters is the words alone, which the fill is cut to.
  letters;

  bool get drawsOutline => this != TextDrawPhase.letters;
  bool get drawsMarks => this != TextDrawPhase.letters;
  bool get drawsLetters => this != TextDrawPhase.behind;
}

/// TextPiece is one thing that moves on its own, and its place in the order.
class TextPiece {
  final Rect box;
  final int start;
  final int end;
  const TextPiece(this.box, this.start, this.end);
}

/// piecesFor cuts a laid-out paragraph into the things that move. The
/// rectangles come from the paragraph's own boxes, so centred and indented
/// lines are right. [range] restricts it to some words (see TextPart); a
/// block-scoped animation given one moves that range alone.
List<TextPiece> piecesFor(LaidOutWords words, TextAnimationScope scope,
    {(int, int)? range}) {
  var text = words.text;
  if (text.isEmpty) {
    return [TextPiece(Offset.zero & words.size, 0, text.length)];
  }

  if (scope == TextAnimationScope.block) {
    if (range == null) {
      return [TextPiece(Offset.zero & words.size, 0, text.length)];
    }
    // The range as one piece: the box round the letters it covers.
    var box = words.boxOf(range.$1, range.$2);
    if (box == null) {
      return [TextPiece(Offset.zero & words.size, 0, text.length)];
    }
    return [TextPiece(box, range.$1, range.$2)];
  }

  if (scope == TextAnimationScope.line) {
    var out = <TextPiece>[];
    for (var line in words.lines) {
      var top = line.baseline - line.ascent;
      var box =
          Rect.fromLTWH(line.left, top, math.max(1, line.width), line.height);
      // With a range: only the part of each line it covers, so a line
      // motion aimed at one word moves that word.
      if (range != null) {
        Rect? mine;
        for (var r in words.boxesOf(range.$1, range.$2)) {
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
        ? [TextPiece(Offset.zero & words.size, 0, text.length)]
        : out;
  }

  var ranges = <(int, int)>[];
  if (scope == TextAnimationScope.word) {
    ranges = [for (var w in wordRanges(text)) (w.start, w.end)];
  } else {
    for (var i = 0; i < text.length; i++) {
      if (!isWordSpace(text[i])) ranges.add((i, i + 1));
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
    var box = words.boxOf(from, to);
    if (box == null) continue;
    out.add(TextPiece(box, from, to));
  }
  return out.isEmpty
      ? [TextPiece(Offset.zero & words.size, 0, text.length)]
      : out;
}

/// _Layer is one part of the text arriving on its own, and how far through.
class _Layer {
  final (int, int) range;
  final TextAnimation animation;
  final double reveal;
  const _Layer(this.range, this.animation, this.reveal);
}

/// _layersFor is the parts arriving on their own. A part without its own
/// animation is drawn with the rest of the paragraph.
List<_Layer> _layersFor(LaidOutWords words, List<PartTiming> timings) {
  var out = <_Layer>[];
  for (var (i, part) in words.parts.indexed) {
    if (!part.animation.on) continue;
    var range = rangeOf(words.text, part);
    if (range == null) continue;
    out.add(_Layer((range.start, range.end), part.animation.arrival,
        i < timings.length ? timings[i].words : 1));
  }
  return out;
}

/// _boxesOf is the rectangles some characters occupy, at [offset].
List<Rect> _boxesOf(LaidOutWords words, (int, int) range, Offset offset) => [
      for (var b in words.boxesOf(range.$1, range.$2))
        b.shift(offset).inflate(1),
    ];

/// paintAnimatedText draws [words] at [offset] with [animation] [reveal]
/// of the way through, and each of its parts with its own animation at its
/// own moment.
///
/// [words] is the layout the still drawing uses, so what arrives is
/// exactly what is there after. [outline], where there is one, moves with
/// the fill. [soft] is the shadow and glow: it moves with the words but no
/// pen writes it, so it is there from the first frame. [keep] draws only
/// some pieces (a column); the stagger still counts the whole paragraph.
///
/// The words nobody singled out are drawn with the singled-out parts
/// clipped out, then each part with its own preset and progress.
void paintAnimatedText(
  ui.Canvas canvas,
  LaidOutWords words,
  TextSpec spec,
  Offset offset,
  TextAnimation animation,
  double reveal, {
  double maxWidth = 0,
  LaidOutWords? outline,
  LaidOutWords? soft,
  List<PartTiming> timings = const [],
  bool Function(TextPiece)? keep,

  /// phase is which half of the drawing this pass is for. See TextDrawPhase.
  TextDrawPhase phase = TextDrawPhase.all,

  /// asOne ignores parts' animations: on the way out all leaves together.
  bool asOne = false,
}) {
  var layers = asOne ? const <_Layer>[] : _layersFor(words, timings);
  var holes = <Rect>[
    for (var layer in layers) ..._boxesOf(words, layer.range, offset),
  ];

  _paintBase(canvas, words, spec, offset, animation, reveal,
      outline: outline,
      soft: soft,
      maxWidth: maxWidth,
      holes: holes,
      layers: layers,
      keep: keep,
      phase: phase);

  for (var layer in layers) {
    _paintLayer(canvas, words, spec, offset, layer,
        outline: outline,
        soft: soft,
        maxWidth: maxWidth,
        keep: keep,
        phase: phase);
  }
}

/// _paintBase draws the words not singled out, with the singled-out cut out.
void _paintBase(
  ui.Canvas canvas,
  LaidOutWords words,
  TextSpec spec,
  Offset offset,
  TextAnimation animation,
  double reveal, {
  LaidOutWords? outline,
  LaidOutWords? soft,
  double maxWidth = 0,
  List<Rect> holes = const [],
  List<_Layer> layers = const [],
  bool Function(TextPiece)? keep,
  TextDrawPhase phase = TextDrawPhase.all,
}) {
  var preset = animation.preset;

  // still draws the paragraph as it stands, minus the holes. [withOutline]
  // is false before a stroke-on has started.
  void still({bool withOutline = true}) {
    canvas.save();
    for (var hole in holes) {
      canvas.clipRect(hole, clipOp: ui.ClipOp.difference);
    }
    if (phase.drawsOutline) soft?.paint(canvas, offset);
    if (withOutline && phase.drawsOutline) outline?.paint(canvas, offset);
    if (phase.drawsLetters) words.paint(canvas, offset);
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
  // Nothing yet, unless a mark is drawn on words already there.
  if (reveal <= 0) {
    if (animation.keeps && animation.draw.start == TextDrawStart.showText) {
      still(withOutline: preset.motion != TextMotion.strokeOn);
    }
    return;
  }

  // Scramble changes the letters, so it is drawn from its own text, without
  // an outline while it settles.
  if (preset.motion == TextMotion.scramble) {
    if (!phase.drawsLetters) return;
    canvas.save();
    for (var hole in holes) {
      canvas.clipRect(hole, clipOp: ui.ClipOp.difference);
    }
    _paintScramble(canvas, words, spec, offset, animation, reveal,
        maxWidth: maxWidth <= 0 ? words.width : maxWidth);
    canvas.restore();
    return;
  }

  var pieces = piecesFor(words, preset.scope);
  var mine = <int>[];
  for (var (i, piece) in pieces.indexed) {
    // A piece inside a singled-out part belongs to that part's layer; a
    // bigger piece stays here with the part clipped out.
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

  _paintAnimatedPieces(
      canvas, words, offset, pieces, mine, spec, animation, reveal,
      outline: outline, soft: soft, holes: holes, phase: phase);
}

/// _paintLayer draws one part of the text arriving on its own account.
void _paintLayer(
  ui.Canvas canvas,
  LaidOutWords words,
  TextSpec spec,
  Offset offset,
  _Layer layer, {
  LaidOutWords? outline,
  LaidOutWords? soft,
  double maxWidth = 0,
  bool Function(TextPiece)? keep,
  TextDrawPhase phase = TextDrawPhase.all,
}) {
  var animation = layer.animation;
  var preset = animation.preset;
  var boxes = _boxesOf(words, layer.range, offset);
  if (boxes.isEmpty) return;

  // inside clips [what] to the part's own letters inflated by a line height,
  // so it cannot spill far over its neighbours.
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
    inside(() {
      if (phase.drawsOutline) soft?.paint(canvas, offset);
      if (phase.drawsOutline) outline?.paint(canvas, offset);
      if (phase.drawsLetters) words.paint(canvas, offset);
    });
    return;
  }

  if (preset.motion == TextMotion.scramble && !phase.drawsLetters) return;
  if (preset.motion == TextMotion.scramble) {
    inside(() => _paintScramble(
        canvas, words, spec, offset, animation, layer.reveal,
        maxWidth: maxWidth <= 0 ? words.width : maxWidth, range: layer.range));
    return;
  }

  var pieces = piecesFor(words, preset.scope, range: layer.range);
  var mine = [
    for (var (i, piece) in pieces.indexed)
      if (keep == null || keep(piece)) i,
  ];
  _paintAnimatedPieces(
      canvas, words, offset, pieces, mine, spec, animation, layer.reveal,
      outline: outline, soft: soft, restricted: true, phase: phase);
}

/// wholeBlockMotion is whether applyMotionSpec carries out [motion] alone. The
/// others draw something besides a transform and opacity (echo and trail
/// copies, a strokeOn outline, an underline or highlight, scramble's
/// letters, a cutting motion's tiles), so they go through _paintPiece. The
/// rest can be applied once to a whole group, such as a paragraph in
/// columns (paintTextInColumns).
bool wholeBlockMotion(TextMotion motion) =>
    !motion.cuts &&
    motion != TextMotion.echo &&
    motion != TextMotion.trail &&
    motion != TextMotion.strokeOn &&
    motion != TextMotion.underline &&
    motion != TextMotion.highlight &&
    motion != TextMotion.scramble;

/// movesAsOneBlock is whether [animation] can be applied to a group as one
/// transform: the whole paragraph moves together, with nothing of its own to
/// draw.
bool movesAsOneBlock(TextAnimation animation) =>
    animation.on &&
    animation.preset.scope == TextAnimationScope.block &&
    wholeBlockMotion(animation.preset.motion);

/// motionRoom is the rectangle text resting in [box] can occupy while
/// [animation] plays, so a fill layer covers the words on the way in.
/// Generous on purpose: too much costs a little memory, too little cuts the
/// drawing.
Rect motionRoom(Rect box, TextAnimation animation) {
  if (!animation.on || box.isEmpty) return box;
  var preset = animation.preset;
  // The way it comes, turned to a chosen direction (TextAnimation.spec).
  var way = animation.spec;

  // Where it comes in from, both sides: the exit plays the preset backwards.
  var dx = box.width * way.dx.abs();
  var dy = box.height * way.dy.abs();

  // And how far an echo's or a trail's copies are strung out: a trail's the
  // way it comes, an echo's its preset's own (see _paintPiece).
  if (preset.motion == TextMotion.echo || preset.motion == TextMotion.trail) {
    var fan = preset.motion == TextMotion.trail ? way : preset.spec;
    var spread =
        animation.echo.copies * animation.echo.spacing * box.height * 3;
    dx += fan.dx.abs() * spread;
    dy += fan.dy == 0 ? spread : fan.dy.abs() * spread;
  }

  var room = Rect.fromLTRB(
      box.left - dx, box.top - dy, box.right + dx, box.bottom + dy);

  // A grow is at its largest on the first frame, as large as its strength
  // makes it.
  if (preset.motion == TextMotion.grow) {
    var scale = math.max(1.0, way.from);
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

/// MotionFrame is what applyMotionSpec did: how opaque to draw, how many saves
/// it owes the canvas, and whether it has already clipped to its own shape.
class MotionFrame {
  final double alpha;
  final int depth;
  final bool clipped;
  const MotionFrame(this.alpha, this.depth, this.clipped);
}

/// MotionCall is one motion as the renderer applied it, for motionProbe.
class MotionCall {
  /// box is the thing moved, in canvas units; [before] and [after] are the
  /// canvas transform either side, so after times before's inverse is the
  /// motion alone.
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

/// motionProbe, when set, is told of every motion as it is applied. The
/// interactive EPUB uses it to read each element's motion from the renderer
/// frame by frame instead of working it out twice. Null elsewhere.
void Function(MotionCall call)? motionProbe;

/// applyMotionSpec sets [canvas] up to draw something [p] of the way through
/// [preset]'s motion, and returns how opaque to draw it. It knows only "move
/// this box", so the same motions drive a paragraph piece, a letter on a
/// curve, and a shape or a picture arriving.
///
/// [box] is the piece's rectangle in the caller's frame; [seed] keeps a
/// shake's jitter the same each frame. The caller restores
/// [MotionFrame.depth] times when done.
MotionFrame applyMotionSpec(
  ui.Canvas canvas,
  Rect box,
  MotionSpec preset,
  double p, {
  double? from,
  int seed = 0,

  /// pivot is what it grows, spins and flips about: its centre unless it
  /// has its own anchor.
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
      // A masked rise is clipped to where the piece will be, so it rises out
      // of nothing rather than sliding over its neighbour.
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
      // Through nothing and out the other side; never exactly zero, as Skia
      // will not draw through a scale that cannot be inverted.
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
      // shape's wipe does (Arrival.specFor).
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
      // A decaying jitter from p and the seed, not random, so an export draws
      // each frame the same way.
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
      // Drawn by the caller tile by tile (paintCutEffect); full opacity
      // here, or every tile is faded twice.
      alpha = 1;
  }

  var frame = MotionFrame(alpha, depth, clipped);
  if (probe != null) {
    probe(MotionCall(box, before!, canvas.getTransform(), clip, preset.motion,
        p, blur, frame));
  }
  return frame;
}

/// _paintAnimatedPieces draws [which] of [all] a paragraph's pieces. Progress
/// comes from each piece's place in [all], so columns stagger across the
/// paragraph rather than restarting in each.
void _paintAnimatedPieces(
  ui.Canvas canvas,
  LaidOutWords words,
  Offset offset,
  List<TextPiece> all,
  Iterable<int> which,
  TextSpec spec,
  TextAnimation animation,
  double reveal, {
  LaidOutWords? outline,
  LaidOutWords? soft,

  /// restricted clips even a whole-paragraph motion to its piece.
  bool restricted = false,

  /// holes are words another layer draws, cut out so none is drawn twice.
  List<Rect> holes = const [],

  /// phase is which half of the drawing this pass is for. See TextDrawPhase.
  TextDrawPhase phase = TextDrawPhase.all,
}) {
  for (var i in which) {
    if (i < 0 || i >= all.length) continue;
    var p = animation.progressAt(reveal, i, all.length);
    if (p <= 0) continue;
    _paintPiece(canvas, words, offset, all[i], animation.preset, p, spec,
        motion: animation.spec,
        outline: outline,
        soft: soft,
        effect: animation.effect,
        draw: animation.draw,
        echo: animation.echo,
        restricted: restricted,
        holes: holes,
        phase: phase);
  }
}

/// _paintPiece draws one piece part way through its movement: [motion] is
/// [preset] with the animation's own settings (TextAnimation.spec).
void _paintPiece(ui.Canvas canvas, LaidOutWords words, Offset offset,
    TextPiece piece, TextAnimationPreset preset, double p, TextSpec spec,
    {required MotionSpec motion,
    LaidOutWords? outline,
    LaidOutWords? soft,
    TextDrawSpec? draw,
    TextEchoSpec? echo,
    EffectSpec? effect,
    bool restricted = false,
    List<Rect> holes = const [],
    TextDrawPhase phase = TextDrawPhase.all}) {
  var start = (draw ?? const TextDrawSpec()).start;
  var box = piece.box.shift(offset);
  var centre = box.center;

  var frame = applyMotionSpec(canvas, box, motion, p,
      from: motion.from, seed: piece.start);
  var alpha = frame.alpha;

  // Every piece but an unrestricted whole paragraph is the layout clipped to
  // the piece.
  var clipped = (preset.scope != TextAnimationScope.block || restricted) &&
      !frame.clipped;

  // Words another layer draws, cut out inside the motion's frame so the gap
  // travels with the piece.
  for (var hole in holes) {
    canvas.clipRect(hole, clipOp: ui.ClipOp.difference);
  }

  // Room above and below for ascenders and descenders, none to the sides, or
  // a moving letter drags its neighbours.
  Rect pieceClip() => Rect.fromLTRB(box.left, box.top - box.height * 0.3,
      box.right, box.bottom + box.height * 0.3);

  // The copies, behind the words, nearest last, each clipped in its own
  // moved frame: the words' clip would hide a copy a line away.
  if (preset.motion == TextMotion.echo || preset.motion == TextMotion.trail) {
    var spec2 = echo ?? const TextEchoSpec();
    var trail = preset.motion == TextMotion.trail;
    // A trail comes the way the words do, turned to a chosen direction; an
    // echo's fan is its preset's own, a direction meaning nothing to it
    // (Arrival.arrivalDirected).
    var dx = trail ? motion.dx : preset.dx;
    var dy = trail ? motion.dy : preset.dy;
    // A trail's copies lie back along its path, so its step is the distance
    // travelled; an echo's is a fixed fan.
    var step = trail
        ? Offset(piece.box.width * dx * (1 - p),
                piece.box.height * dy * (1 - p)) *
            (spec2.spacing / math.max(1, spec2.copies))
        : Offset(
            dx * box.height * spec2.spacing,
            dy == 0
                ? box.height * spec2.spacing
                : dy * box.height * spec2.spacing,
          );
    var ways = preset.bothWays ? const [1.0, -1.0] : const [1.0];

    // A resolved echo fans out over the first half, then carries on and
    // fades, leaving the words alone. Unresolved, the copies stay.
    var resolving = spec2.resolve && !trail;
    var fanning = resolving ? (p * 2).clamp(0.0, 1.0) : p;
    var going = resolving ? (p * 2 - 1).clamp(0.0, 1.0) : 0.0;

    for (var way in ways) {
      for (var c = spec2.copies; c >= 1; c--) {
        // An echo's copies arrive one by one; a trail's are there from the
        // start and thin out as it settles.
        var arrived = trail
            ? 1.0
            : (fanning * (spec2.copies + 1) - (c - 1)).clamp(0.0, 1.0);
        if (arrived <= 0) continue;

        var strength = spec2.fade;
        for (var i = 1; i < c; i++) {
          strength *= spec2.fade;
        }
        if (trail) strength *= (1 - p);
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
        if (phase.drawsLetters) words.paint(canvas, offset);
        canvas.restore();
        canvas.restore();
      }
    }
  }

  var mark = draw ?? const TextDrawSpec();
  // Its own colour, or the words' faintly, so a highlight is not a block.
  var markColor = mark.color ?? spec.color.withValues(alpha: 0.25);

  // Marks go outside the piece's clip, which would cut their side padding.
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
    // Cut up rather than moved: drawn here, so the paragraph with its
    // outline and shadow can be drawn once per tile.
    paintCutEffect(canvas, box, preset.motion, effect ?? const EffectSpec(), p,
        () {
      if (phase.drawsOutline) soft?.paint(canvas, offset);
      if (phase.drawsOutline) outline?.paint(canvas, offset);
      if (phase.drawsLetters) words.paint(canvas, offset);
    });
  } else if (preset.motion == TextMotion.strokeOn) {
    // The pen writes the outline along words already there, or fading in
    // with it (TextDrawStart.fadeText). With no outline nothing is written
    // (see outlineSpecFor). Each phase draws its half; the shadow is whole.
    if (phase.drawsOutline) soft?.paint(canvas, offset);
    if (phase.drawsLetters) {
      if (start == TextDrawStart.fadeText) {
        _fade(canvas, box, p, () => words.paint(canvas, offset));
      } else {
        words.paint(canvas, offset);
      }
    }
    if (phase.drawsOutline && outline != null) {
      _writeOutline(canvas, words, outline, offset, box, p, restricted);
    }
  } else if (alpha >= 1) {
    if (phase.drawsOutline) soft?.paint(canvas, offset);
    if (phase.drawsOutline) outline?.paint(canvas, offset);
    if (phase.drawsLetters) words.paint(canvas, offset);
  } else {
    canvas.saveLayer(box.inflate(box.height * 2),
        Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    if (phase.drawsOutline) soft?.paint(canvas, offset);
    if (phase.drawsOutline) outline?.paint(canvas, offset);
    if (phase.drawsLetters) words.paint(canvas, offset);
    canvas.restore();
  }
  canvas.restore();

  if (preset.motion == TextMotion.underline && phase.drawsMarks) {
    // Bottom padding moves the line off the letters; the ends resize it.
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

/// _writeOutline draws as much of [ink] as has been written, line by line,
/// left to right. Flutter gives no letter paths, so the stroke is uncovered
/// by a moving clip, each line taking its share of time in turn.
/// [restricted] (some of the words) is written as one sweep.
void _writeOutline(ui.Canvas canvas, LaidOutWords words, LaidOutWords ink,
    Offset offset, Rect box, double at, bool restricted) {
  if (at <= 0) return;
  if (at >= 1) {
    ink.paint(canvas, offset);
    return;
  }

  var rows = <Rect>[];
  if (!restricted) {
    for (var line in words.lines) {
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
    // Room for the stroke, but never past half way to the next line: [ink]
    // holds the whole paragraph, so a deeper clip uncovers an unwritten line.
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

/// _paintScramble resolves each letter of [words] from a random one. The
/// only motion that lays its text out again: same length and spaces, so the
/// words do not jump while they settle, and in the same parts, counted in
/// the words themselves.
void _paintScramble(ui.Canvas canvas, LaidOutWords words, TextSpec spec,
    Offset offset, TextAnimation animation, double reveal,
    {required double maxWidth,

    /// range scrambles only those letters, for a part animated on its own.
    (int, int)? range}) {
  var text = words.text;
  const pool = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#\$%&@";
  var letters = 0;
  for (var i = 0; i < text.length; i++) {
    if (!isWordSpace(text[i])) letters++;
  }

  if (range != null) {
    letters = 0;
    for (var i = range.$1; i < range.$2 && i < text.length; i++) {
      if (!isWordSpace(text[i])) letters++;
    }
  }

  var resolved = 0;
  var buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    var c = text[i];
    if (isWordSpace(c) || (range != null && (i < range.$1 || i >= range.$2))) {
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
      // Stepped, so a letter flickers through a few characters, not dozens.
      var step = (reveal * 12).floor() + i;
      buffer.write(pool[step % pool.length]);
    }
  }

  layOutWords(buffer.toString(), spec,
          parts: words.parts,
          partsIn: text,
          maxWidth: maxWidth,
          fillWidth: true)
      .paint(canvas, offset);
}
