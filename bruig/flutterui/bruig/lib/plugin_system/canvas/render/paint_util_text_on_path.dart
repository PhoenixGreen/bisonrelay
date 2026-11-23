part of 'paint_util.dart';

// Text laid along a curve letter by letter: placing each glyph, its bounds, and
// drawing it with its marks, copies and arrival. Part of paint_util.dart.

/// PlacedGlyph is one letter of text on a curve, placed by placeTextOnPath.
class PlacedGlyph {
  final String glyph;

  /// at is the glyph's baseline centre, and angle the curve's heading there.
  final Offset at;
  final double angle;
  final Size size;

  /// index is where this glyph starts in its text, to find its parts.
  final int index;

  /// part is the part over this glyph, or null: carried so the letter
  /// measured is the letter drawn (layOutGlyph).
  final TextPart? part;

  const PlacedGlyph(this.glyph, this.at, this.angle, this.size,
      {this.index = 0, this.part});
}

/// placeTextOnPath works out where every letter of [text] goes along [curve],
/// apart from drawing so the selection box and the painter agree. [curve] is a
/// polyline in document space, sampled finely enough to walk in straight steps.
List<PlacedGlyph> placeTextOnPath(
  String text,
  TextSpec spec,
  List<Offset> curve,
  TextOnCurve on, {
  double scale = 1,

  /// parts colour, size, embolden or italicise some letters, or set them in
  /// another face (TextPart); needed here because they change letter widths.
  required List<TextPart> parts,
}) {
  if (text.isEmpty || curve.length < 2) return const [];

  // Distance along the polyline, to turn a length into a point and heading.
  var lengths = <double>[0];
  var total = 0.0;
  for (var i = 1; i < curve.length; i++) {
    total += (curve[i] - curve[i - 1]).distance;
    lengths.add(total);
  }
  if (total <= 0) return const [];

  var glyphs = <String>[];
  var at0 = <int>[];
  var offset = 0;
  for (var rune in text.runes) {
    var g = String.fromCharCode(rune);
    glyphs.add(g);
    at0.add(offset);
    offset += g.length;
  }
  var over = [
    for (var i = 0; i < glyphs.length; i++) partAt(text, parts, at0[i]),
  ];
  var laid = [
    for (var i = 0; i < glyphs.length; i++)
      layOutGlyph(glyphs[i], spec, part: over[i], scale: scale),
  ];
  var widths = [for (var p in laid) p.width + on.spacing * scale];
  var runLength = widths.fold(0.0, (sum, w) => sum + w);

  // Where the run starts, from the spec's own alignment plus the slide.
  var at = switch (spec.align) {
        TextAlignSpec.left => 0.0,
        TextAlignSpec.center => (total - runLength) / 2,
        TextAlignSpec.right => total - runLength,
        TextAlignSpec.justify => 0.0,
      } +
      on.offset * total;

  var out = <PlacedGlyph>[];
  for (var i = 0; i < glyphs.length; i++) {
    var centre = at + widths[i] / 2;
    at += widths[i];
    // Past the ends the letters carry straight on rather than being dropped,
    // so a slide travels off the line (see _alongPolyline).
    var (point, angle) = _alongPolyline(curve, lengths, centre);
    out.add(PlacedGlyph(glyphs[i], point, angle, laid[i].size,
        index: at0[i], part: over[i]));
  }
  return out;
}

/// _animatedPartAt is the part arriving alone over [index], or -1 for none.
int _animatedPartAt(String text, List<TextPart> parts, int index) {
  var found = -1;
  for (var (i, part) in parts.indexed) {
    if (!part.animation.on) continue;
    var range = rangeOf(text, part);
    if (range == null) continue;
    if (index >= range.start && index < range.end) found = i;
  }
  return found;
}

/// textOnPathBounds is the placed letters' box, round every turned corner.
Rect? textOnPathBounds(List<PlacedGlyph> glyphs, TextOnCurve on) {
  if (glyphs.isEmpty) return null;
  double? left, top, right, bottom;

  for (var g in glyphs) {
    var dy = on.away ? 0.0 : -g.size.height;
    var cos = math.cos(g.angle);
    var sin = math.sin(g.angle);
    for (var corner in [
      Offset(-g.size.width / 2, dy),
      Offset(g.size.width / 2, dy),
      Offset(-g.size.width / 2, dy + g.size.height),
      Offset(g.size.width / 2, dy + g.size.height),
    ]) {
      var x = g.at.dx + corner.dx * cos - corner.dy * sin;
      var y = g.at.dy + corner.dx * sin + corner.dy * cos;
      left = left == null ? x : math.min(left, x);
      right = right == null ? x : math.max(right, x);
      top = top == null ? y : math.min(top, y);
      bottom = bottom == null ? y : math.max(bottom, y);
    }
  }
  return Rect.fromLTRB(left!, top!, right!, bottom!);
}

/// paintTextOnPath lays [text] along [curve] glyph by glyph, so each letter
/// turns with the line. [animation] and [reveal] apply the motions in each
/// glyph's turned frame, so a letter on a bend rises along the line.
void paintTextOnPath(
  ui.Canvas canvas,
  String text,
  TextSpec spec,
  List<Offset> curve,
  TextOnCurve on, {
  double scale = 1,
  TextAnimation? animation,
  double reveal = 1,
  required List<TextPart> parts,
  List<PartTiming> timings = const [],
  bool asOne = false,
  CanvasImageSource? images,

  /// outlineOnly and fillOnly are the two passes for a filled run: the
  /// outlines in their own colour, then the letters inside the fill's layer.
  bool outlineOnly = false,
  bool fillOnly = false,
}) {
  var glyphs =
      placeTextOnPath(text, spec, curve, on, scale: scale, parts: parts);
  if (glyphs.isEmpty) return;

  // The line as a window: whatever slides off its ends is cut off by a
  // ribbon round the polyline, so a bend masks along the bend.
  var masked = on.mask;
  if (masked) {
    canvas.save();
    canvas.clipPath(_curveRibbon(curve, spec.fontSize * scale * 3));
  }
  if (masked) {
    // The mask is this call's own; the two passes a fill makes are inside it.
    paintTextOnPath(canvas, text, spec, curve, on.copyWith(mask: false),
        scale: scale,
        animation: animation,
        reveal: reveal,
        parts: parts,
        timings: timings,
        asOne: asOne,
        images: images,
        outlineOnly: outlineOnly,
        fillOnly: fillOnly);
    canvas.restore();
    return;
  }

  if (spec.fill.on && !outlineOnly && !fillOnly) {
    var box = textOnPathBounds(glyphs, on) ?? _boundsOf(curve);
    paintTextOnPath(canvas, text, spec, curve, on,
        scale: scale,
        animation: animation,
        reveal: reveal,
        parts: parts,
        timings: timings,
        asOne: asOne,
        outlineOnly: true);
    paintThroughText(
        canvas,
        box,
        spec.fill,
        images,
        () => paintTextOnPath(canvas, text, spec, curve, on,
            scale: scale,
            animation: animation,
            reveal: reveal,
            parts: parts,
            timings: timings,
            asOne: asOne,
            fillOnly: true));
    return;
  }

  var moving =
      animation != null && animation.on && (reveal < 1 || animation.keeps);

  // Which layer each letter belongs to: the index of a part arriving on its
  // own account, or -1 for the paragraph's arrival.
  var layer = <int>[
    for (var g in glyphs) asOne ? -1 : _animatedPartAt(text, parts, g.index),
  ];

  // animationOf is what moves a layer and revealOf how far through it is.
  TextAnimation? animationOf(int of) =>
      of < 0 ? (moving ? animation : null) : parts[of].animation.asAnimation;
  double revealOf(int of) =>
      of < 0 ? reveal : (of < timings.length ? timings[of].words : 1);

  // Each letter's place in its layer's order, and how many places the layer
  // has: words for a word scope, letters for a letter scope, one for a block.
  var place = List<int>.filled(glyphs.length, 0);
  var places = <int, int>{};
  for (var of in layer.toSet()) {
    var mine = [
      for (var i = 0; i < glyphs.length; i++)
        if (layer[i] == of) i,
    ];
    var scope = animationOf(of)?.preset.scope ?? TextAnimationScope.block;
    if (scope == TextAnimationScope.word) {
      var word = -1;
      var inWord = false;
      for (var i in mine) {
        var space = isWordSpace(glyphs[i].glyph);
        if (!space && !inWord) word++;
        inWord = !space;
        place[i] = math.max(0, word);
      }
      places[of] = math.max(1, word + 1);
    } else if (scope == TextAnimationScope.letter) {
      for (var (n, i) in mine.indexed) {
        place[i] = n;
      }
      places[of] = math.max(1, mine.length);
    } else {
      for (var i in mine) {
        place[i] = 0;
      }
      places[of] = 1;
    }
  }

  for (var (i, g) in glyphs.indexed) {
    var dy = on.away ? 0.0 : -g.size.height;
    // The glyph's rectangle in its own frame, origin at its baseline centre.
    var local = Rect.fromLTWH(
        -g.size.width / 2, dy, g.size.width, math.max(1, g.size.height));

    // anim is null exactly when this letter is not moving.
    var mine = layer[i];
    var anim = animationOf(mine);
    var over = revealOf(mine);
    if (anim != null && !anim.on) anim = null;
    if (anim != null && over >= 1 && !anim.keeps) anim = null;
    var p =
        anim == null ? 1.0 : anim.progressAt(over, place[i], places[mine] ?? 1);
    if (p <= 0 && anim != null && !anim.keeps) continue;

    canvas.save();
    canvas.translate(g.at.dx, g.at.dy);
    canvas.rotate(g.angle);

    var frame = anim == null
        ? const MotionFrame(1, 0, false)
        : applyMotionSpec(canvas, local, anim.spec, p,
            from: anim.spec.from, seed: g.index);

    // A mark is drawn a letter at a time in each letter's frame, so it
    // follows the curve, sweeping in letter order whatever the scope, or a
    // block underline would grow under every letter at once.
    var sweep =
        anim == null ? 1.0 : (p * glyphs.length - i).clamp(0.0, 1.0).toDouble();
    // Only on the pass outside the fill's layer: a band laid once, own colour.
    if (anim != null &&
        anim.preset.motion == TextMotion.highlight &&
        !fillOnly) {
      _paintCurveMark(canvas, local, anim.draw, spec, sweep, under: false);
    }
    // The parts' own highlights, behind the letter, as the letter moves.
    var advance = g.size.width + on.spacing * scale;
    if (!fillOnly) {
      _paintCurvePartMarks(
          canvas, local, advance, text, g, parts, timings, frame.alpha, spec,
          behind: true);
    }

    // An echo's or trail's copies, in the turned frame so they fan along the
    // line, and before the letter so they sit behind it.
    if (anim != null &&
        (anim.preset.motion == TextMotion.echo ||
            anim.preset.motion == TextMotion.trail)) {
      _paintCurveCopies(canvas, g, spec, dy, scale, local, anim, p,
          outlineOnly: outlineOnly, fillOnly: fillOnly);
    }

    // Stroke-on: the outline is written letter after letter (applyMotionSpec
    // leaves opacity alone). The letters are already there unless
    // TextDrawStart.fadeText brings them in with it.
    var strokeOn = anim != null && anim.preset.motion == TextMotion.strokeOn;
    double? outlineAlpha, fillAlpha;
    if (strokeOn) {
      outlineAlpha = ((p * glyphs.length) - i).clamp(0.0, 1.0).toDouble();
      fillAlpha = anim.draw.start == TextDrawStart.fadeText ? p : null;
    }
    _paintGlyph(canvas, g, spec, dy, scale, frame.alpha,
        outlineOnly: outlineOnly,
        fillOnly: fillOnly,
        outlineAlpha: outlineAlpha,
        fillAlpha: fillAlpha);

    if (anim != null &&
        anim.preset.motion == TextMotion.underline &&
        !fillOnly) {
      _paintCurveMark(canvas, local, anim.draw, spec, sweep, under: true);
    }
    if (!fillOnly) {
      _paintCurvePartMarks(
          canvas, local, advance, text, g, parts, timings, frame.alpha, spec,
          behind: false);
    }

    for (var r = 0; r < frame.depth; r++) {
      canvas.restore();
    }
    canvas.restore();
  }
}

/// _curveRibbon is a band [thick] wide along [curve], masking a sliding
/// caption to its line. Self-crossing is harmless under the non-zero rule.
Path _curveRibbon(List<Offset> curve, double thick) {
  var path = Path();
  if (curve.length < 2) return path;
  var half = math.max(1.0, thick) / 2;

  Offset normalAt(int i) {
    var a = curve[i == 0 ? 0 : i - 1];
    var b = curve[i == curve.length - 1 ? i : i + 1];
    var d = b - a;
    var length = d.distance;
    if (length <= 0) return const Offset(0, -1);
    return Offset(-d.dy / length, d.dx / length);
  }

  var left = <Offset>[];
  var right = <Offset>[];
  for (var i = 0; i < curve.length; i++) {
    var n = normalAt(i) * half;
    left.add(curve[i] + n);
    right.add(curve[i] - n);
  }

  path.moveTo(left.first.dx, left.first.dy);
  for (var p in left.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  for (var p in right.reversed) {
    path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

/// _boundsOf is a box round a polyline, for a run with nothing placed on it.
Rect _boundsOf(List<Offset> curve) {
  var box = Rect.fromLTWH(curve.first.dx, curve.first.dy, 1, 1);
  for (var p in curve.skip(1)) {
    box = box.expandToInclude(Rect.fromLTWH(p.dx, p.dy, 1, 1));
  }
  return box;
}

/// _paintGlyph draws one placed letter in [spec] and its part, and its
/// outline where it has one. [outlineAlpha] and [fillAlpha] fade the stroke
/// and the fill separately, for stroke-on; null for every other preset.
void _paintGlyph(ui.Canvas canvas, PlacedGlyph g, TextSpec spec, double dy,
    double scale, double alpha,
    {bool outlineOnly = false,
    bool fillOnly = false,
    double? outlineAlpha,
    double? fillAlpha}) {
  var at = Offset(-g.size.width / 2, dy);
  var room = Rect.fromLTWH(at.dx, at.dy, g.size.width, g.size.height)
      .inflate(g.size.height * 2);

  // half draws one of the two at its own opacity, through a layer if needed.
  void half(double at2, void Function() what) {
    if (at2 <= 0) return;
    if (at2 >= 1) {
      what();
      return;
    }
    canvas.saveLayer(room, Paint()..color = Color.fromRGBO(0, 0, 0, at2));
    what();
    canvas.restore();
  }

  var faded = alpha < 1;
  if (faded) {
    if (alpha <= 0) return;
    canvas.saveLayer(
        room, Paint()..color = Color.fromRGBO(0, 0, 0, alpha.clamp(0.0, 1.0)));
  }
  if (!fillOnly && spec.softPasses) {
    layOutGlyph(g.glyph, spec, part: g.part, scale: scale, pass: WordsPass.soft)
        .paint(canvas, at);
  }
  if ((g.part?.outlineWidth ?? spec.outlineWidth) > 0 && !fillOnly) {
    half(
        outlineAlpha ?? 1,
        () => layOutGlyph(g.glyph, spec,
                part: g.part, scale: scale, pass: WordsPass.outline)
            .paint(canvas, at));
  }
  if (!outlineOnly) {
    half(
        fillAlpha ?? 1,
        () => layOutGlyph(g.glyph, spec, part: g.part, scale: scale)
            .paint(canvas, at));
  }
  if (faded) canvas.restore();
}

/// _paintCurveMark is a mark under one letter of a curve, [sweep] drawn.
void _paintCurveMark(ui.Canvas canvas, Rect local, TextDrawSpec mark,
    TextSpec spec, double sweep,
    {required bool under}) {
  if (sweep <= 0) return;
  // The letter's share of the mark, widened by the mark's padding.
  var left = local.left - mark.padLeft;
  var right = local.right + mark.padRight;
  var width = (right - left) * sweep;
  if (under) {
    var y = local.bottom + mark.padBottom;
    canvas.drawRect(
        Rect.fromLTWH(left, y, width, math.max(1, local.height * 0.06)),
        Paint()..color = mark.color ?? spec.color);
    return;
  }
  var band = Rect.fromLTWH(left, local.top - mark.padTop, width,
      local.height + mark.padTop + mark.padBottom);
  var paint = Paint()..color = mark.color ?? spec.color.withValues(alpha: 0.25);
  if (mark.radius <= 0) {
    canvas.drawRect(band, paint);
    return;
  }
  canvas.drawRRect(
      RRect.fromRectAndRadius(band, Radius.circular(mark.radius)), paint);
}

/// _paintCurvePartMarks draws the parts' own highlights ([behind]) or
/// underlines over one letter on a line: the letter's share, [advance] wide,
/// in its turned frame, so the mark bends with the line. The ends of a run
/// take its padding and corners. A mark drawn on comes letter by letter.
void _paintCurvePartMarks(
    ui.Canvas canvas,
    Rect local,
    double advance,
    String text,
    PlacedGlyph g,
    List<TextPart> parts,
    List<PartTiming> timings,
    double alpha,
    TextSpec spec,
    {required bool behind}) {
  for (var (n, part) in parts.indexed) {
    if ((behind ? part.highlight : part.underline) == null) continue;
    var range = rangeOf(text, part);
    if (range == null || g.index < range.start || g.index >= range.end) {
      continue;
    }
    var drawn = n < timings.length ? timings[n].mark : 1.0;
    if (g.index - range.start >= drawn * (range.end - range.start)) continue;
    var box = Rect.fromCenter(
        center: local.center, width: advance, height: local.height);
    var first = g.index == range.start;
    var last = g.index + g.glyph.length >= range.end;
    _fadeInto(canvas, box, alpha, () {
      if (!behind) {
        _paintPartUnderline(
            canvas, box, part.underline!, part.color ?? spec.color);
        return;
      }
      _paintPartHighlight(canvas, box, part.highlight!,
          first: first, last: last);
    });
  }
}

/// _paintCurveCopies draws an echo's or a trail's copies of one letter.
void _paintCurveCopies(ui.Canvas canvas, PlacedGlyph g, TextSpec spec,
    double dy, double scale, Rect local, TextAnimation animation, double p,
    {bool outlineOnly = false, bool fillOnly = false}) {
  var echo = animation.echo;
  var preset = animation.preset;
  var trail = preset.motion == TextMotion.trail;
  // A trail comes the way the letters do, turned to a chosen direction; an
  // echo's fan is its preset's own (see _paintPiece).
  var way = trail ? animation.spec : preset.spec;
  var step = trail
      ? Offset(
              local.width * way.dx * (1 - p), local.height * way.dy * (1 - p)) *
          (echo.spacing / math.max(1, echo.copies))
      : Offset(
          way.dx * local.height * echo.spacing,
          way.dy == 0
              ? local.height * echo.spacing
              : way.dy * local.height * echo.spacing,
        );
  var ways = preset.turns > 0 && !trail ? const [1.0, -1.0] : const [1.0];

  // See the same two halves in _paintPiece: fan out, then go.
  var resolving = echo.resolve && !trail;
  var fanning = resolving ? (p * 2).clamp(0.0, 1.0) : p;
  var going = resolving ? (p * 2 - 1).clamp(0.0, 1.0) : 0.0;

  for (var way in ways) {
    for (var c = echo.copies; c >= 1; c--) {
      var arrived =
          trail ? 1.0 : (fanning * (echo.copies + 1) - (c - 1)).clamp(0.0, 1.0);
      if (arrived <= 0) continue;
      var strength = echo.fade;
      for (var i = 1; i < c; i++) {
        strength *= echo.fade;
      }
      if (trail) strength *= (1 - p);
      if (going > 0) strength *= (1 - going) * (1 - going);
      if (strength <= 0.002) continue;

      var away = step * (c * arrived * (1 + going * 2.5)) * way;
      var size = math.pow(echo.shrink, c).toDouble();
      canvas.save();
      canvas.translate(away.dx, away.dy);
      if (size != 1) canvas.scale(size, size);
      _paintGlyph(
          canvas, g, spec, dy, scale, (strength * arrived).clamp(0.0, 1.0),
          outlineOnly: outlineOnly, fillOnly: fillOnly);
      canvas.restore();
    }
  }
}

/// _alongPolyline is the point and heading at [distance] along [curve],
/// carrying on past either end, so a caption slid off keeps travelling.
(Offset, double) _alongPolyline(
    List<Offset> curve, List<double> lengths, double distance) {
  for (var i = 1; i < lengths.length; i++) {
    if (lengths[i] < distance) continue;
    var span = lengths[i] - lengths[i - 1];
    var t = span <= 0 ? 0.0 : (distance - lengths[i - 1]) / span;
    var a = curve[i - 1], b = curve[i];
    var direction = b - a;
    return (
      Offset(a.dx + direction.dx * t, a.dy + direction.dy * t),
      math.atan2(direction.dy, direction.dx),
    );
  }
  var last = curve.last - curve[curve.length - 2];
  var length = last.distance;
  var beyond = distance - lengths.last;
  var heading = math.atan2(last.dy, last.dx);
  if (length <= 0) return (curve.last, heading);
  return (curve.last + last / length * beyond, heading);
}
