import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/text_animator.dart';
import 'package:flutter/painting.dart';

// paint_util.dart is the drawing every element does the same way: laying out
// a string, filling a box, and turning a shape's name into a path.
//
// It is the reason the painters below it are short. A text element, a shape's
// label, a button, a chart axis, a table cell and a player's name all reach
// the screen through layoutText here, so they all get the outline, the shadow,
// the letter spacing and the line height without any of them implementing it
// -- and a fix to any of that is one fix.
//
// Everything takes plain values and a ui.Canvas. Nothing here touches a
// BuildContext or a theme: the same code paints the on-screen stage and the
// off-screen export, and an export that reached for the app's theme would
// produce a picture that changed depending on what the sender's app looked
// like.

// _layouts memoises laid-out paragraphs.
//
// Laying text out is by a wide margin the most expensive thing this file
// does, and the same string is laid out over and over: a table redraws every
// cell on every frame of an animation that only moves a chart, an axis label
// is measured once to decide the plot area and laid out again to draw it, and
// a scrubbed timeline repaints the whole scene per pointer move. None of that
// text changed, but each pass built a fresh ui.Paragraph for it.
//
// The key is every input that can change the result, so a different colour,
// scale or box width is a different entry and a theme or font change misses
// the cache by construction rather than by anyone remembering to clear it.
//
// A returned painter is only ever read from -- paint, width, height,
// getBoxesForSelection -- so handing the same one to two callers is safe.
// Evicted painters are dropped rather than disposed: a caller may still be
// holding one from an earlier frame, and letting them be collected is exactly
// what happened before there was a cache here.
typedef _LayoutKey = (
  String,
  TextSpec,
  double,
  double,
  Color?,
  bool,
  bool,
  // The parts, as the text of their own settings: two paragraphs of the
  // same words with a different word coloured are two paragraphs.
  String,
);

final _layouts = <_LayoutKey, TextPainter>{};

/// _layoutCap is the number of paragraphs kept. A busy league table is a few
/// hundred cells, so this holds a whole scene with room over, and the oldest
/// entries go first when it doesn't.
const _layoutCap = 512;

/// layoutText builds a laid-out paragraph from a [TextSpec].
///
/// The outline is drawn as a second painter behind the first rather than as a
/// foreground stroke, because a stroked glyph centres its stroke on the
/// outline and eats half its width out of the letterform -- so a 6px outline
/// on a thin face makes the letters visibly thinner, which is the opposite of
/// what somebody asking for an outline wants.
TextPainter layoutText(
  String text,
  TextSpec spec, {
  required double maxWidth,
  double scale = 1,
  Color? colorOverride,
  bool outline = false,

  /// fillWidth lays the paragraph out at exactly [maxWidth] rather than at the
  /// width its longest line happens to need.
  ///
  /// This is what makes textAlign do anything. A TextPainter aligns within its
  /// own width, and by default that width shrinks to the text -- so a centred
  /// line was centred inside a box exactly its own size, drawn at the left
  /// edge of the element, and every alignment looked like "left". Measuring
  /// still wants the intrinsic width, which is why this is a flag and not the
  /// only behaviour.
  bool fillWidth = false,

  /// parts are the runs of the text that are drawn differently -- a word in
  /// another colour, a phrase in bold. Empty for almost every paragraph.
  List<TextPart> parts = const [],
}) {
  var key = (
    text,
    spec,
    maxWidth,
    scale,
    colorOverride,
    outline,
    fillWidth,
    // The parts are part of what makes a layout what it is: two paragraphs
    // of the same words with a different word coloured are two paragraphs.
    parts.isEmpty ? "" : [for (var p in parts) p.toJson()].toString(),
  );
  var hit = _layouts[key];
  if (hit != null) return hit;
  var painter = _layoutText(text, spec,
      maxWidth: maxWidth,
      scale: scale,
      colorOverride: colorOverride,
      outline: outline,
      fillWidth: fillWidth,
      parts: parts);
  if (_layouts.length >= _layoutCap) {
    _layouts.remove(_layouts.keys.first);
  }
  _layouts[key] = painter;
  return painter;
}

TextPainter _layoutText(
  String text,
  TextSpec spec, {
  required double maxWidth,
  double scale = 1,
  Color? colorOverride,
  bool outline = false,
  bool fillWidth = false,
  List<TextPart> parts = const [],
}) {
  // The case transform belongs here rather than at every call site.
  //
  // It was applied by the callers -- five of them, each remembering to write
  // spec.textCase.apply(text) -- so every painter written afterwards forgot,
  // and Case was a setting that did nothing on a table, a chart or a shape's
  // label. Applying it where the words are measured and drawn means there is
  // nowhere left to forget it. It is idempotent, so a caller that still does
  // it does no harm.
  text = spec.textCase.apply(text);

  var style = textStyleOf(spec,
      scale: scale, colorOverride: colorOverride, outline: outline);

  var painter = TextPainter(
    text: parts.isEmpty
        ? TextSpan(text: text, style: style)
        : _partedSpan(text, spec, parts, style, colorOverride, scale),
    textAlign: spec.align.flutter,
    textDirection: TextDirection.ltr,
    maxLines: null,
  );
  var width = math.max(0.0, maxWidth);
  painter.layout(
      minWidth: fillWidth && width.isFinite ? width : 0, maxWidth: width);
  return painter;
}

/// paintPartMarks draws the highlights behind, or the underlines under, the
/// element's parts.
///
/// Two passes rather than one, because the two marks belong on opposite sides
/// of the words: a highlight behind them and a line under them, and a line
/// drawn before the letters is a line with the letters sitting on top of it,
/// which is not what an underline looks like where a descender crosses it.
///
/// The rectangles come from the paragraph's own selection boxes, so a part
/// spanning a line break is marked as two lines rather than as one box round
/// both -- which would be a highlighter that had coloured in the margin.
/// [timings] says how much of each mark has been drawn, where the part has
/// asked for its mark to be drawn on rather than simply be there. A mark is
/// drawn from its start to whatever share of it has arrived -- a highlighter
/// crossing the words, a line being pulled under them -- which is the whole
/// reason a mark has a timing of its own: a word arrives and *then* gets
/// underlined.
/// [moving] and [at] are the element's own animation and how far through it
/// is, where it is running. A mark belongs to the words it is on: if they are
/// arriving it arrives with them, and if they are leaving it goes with them.
/// Drawn outside all that, as it was, an underline stayed behind on an empty
/// canvas after the sentence it belonged to had left.
void paintPartMarks(
  ui.Canvas canvas,
  TextPainter painter,
  String text,
  List<TextPart> parts,
  TextSpec spec,
  Offset offset, {
  required bool behind,
  List<PartTiming> timings = const [],
  TextAnimation? moving,
  double at = 1,
}) {
  if (parts.isEmpty || text.isEmpty) return;

  for (var (i, part) in parts.indexed) {
    var mark = behind ? part.highlight : part.underline;
    if (mark == null) continue;
    var range = rangeOf(text, part);
    if (range == null) continue;
    var drawn = i < timings.length ? timings[i].mark : 1.0;
    if (drawn <= 0) continue;

    var boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: range.$1, extentOffset: range.$2));
    // Across all of the lines it covers rather than each on its own, so a
    // mark under two lines is drawn along the first and then along the
    // second instead of both at once.
    var total = 0.0;
    for (var b in boxes) {
      total += b.toRect().width;
    }
    var reached = total * drawn;
    for (var b in boxes) {
      var box = b.toRect().shift(offset);
      if (box.width <= 0) continue;
      if (reached < box.width) {
        if (reached <= 0) break;
        box = Rect.fromLTWH(box.left, box.top, reached, box.height);
      }
      reached -= b.toRect().width;

      // Carried by whatever the words are doing. One piece rather than one
      // per letter: a highlight is a band behind a phrase, and a band that
      // came apart into a letter's worth of stripes would not be one.
      var frame = moving == null || !moving.on
          ? const MotionFrame(1, 0, false)
          : applyMotion(canvas, box, moving.preset, moving.progressAt(at, 0, 1),
              from: moving.scaleFor(moving.preset));
      _fadeInto(canvas, box, frame.alpha, () {
        if (behind) {
          _paintPartHighlight(canvas, box, part.highlight!);
        } else {
          _paintPartUnderline(
              canvas, box, part.underline!, part.color ?? spec.color);
        }
      });
      for (var r = 0; r < frame.depth; r++) {
        canvas.restore();
      }
      if (reached <= 0) break;
    }
  }
}

/// _fadeInto draws [what] at [alpha], through a layer where it has to be.
void _fadeInto(ui.Canvas canvas, Rect box, double alpha, void Function() what) {
  if (alpha <= 0) return;
  if (alpha >= 1) {
    what();
    return;
  }
  canvas.saveLayer(box.inflate(box.height * 2),
      Paint()..color = Color.fromRGBO(0, 0, 0, alpha.clamp(0.0, 1.0)));
  what();
  canvas.restore();
}

void _paintPartHighlight(ui.Canvas canvas, Rect box, PartHighlight mark) {
  var band = Rect.fromLTRB(
    box.left - mark.padLeft,
    box.top - mark.padTop,
    box.right + mark.padRight,
    box.bottom + mark.padBottom,
  );
  var paint = Paint()..color = mark.color;
  if (mark.radius <= 0) {
    canvas.drawRect(band, paint);
    return;
  }
  canvas.drawRRect(
      RRect.fromRectAndRadius(band, Radius.circular(mark.radius)), paint);
}

void _paintPartUnderline(
    ui.Canvas canvas, Rect box, PartUnderline mark, Color fallback) {
  var width = math.max(0.1, mark.width);
  var y = box.bottom + mark.away;
  var paint = Paint()
    ..color = mark.color ?? fallback
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  // The phase is taken from where the line is, so the same word underlined
  // twice on one canvas wobbles the same way both times and an exported
  // frame is the same frame however many times it is drawn.
  var phase = (box.left * 0.7 + box.top * 1.3) % (2 * math.pi);

  switch (mark.style) {
    case PartLineStyle.solid:
      paint.strokeCap = StrokeCap.butt;
      canvas.drawRect(Rect.fromLTWH(box.left, y - width / 2, box.width, width),
          paint..style = PaintingStyle.fill);

    case PartLineStyle.dashed:
      paint.strokeCap = StrokeCap.butt;
      canvas.drawPath(
          dashPath(_straight(box.left, box.right, y), width * 4, width * 3),
          paint);

    case PartLineStyle.dotted:
      canvas.drawPath(
          dashPath(_straight(box.left, box.right, y), 0.01, width * 3), paint);

    case PartLineStyle.twin:
      paint
        ..strokeWidth = width * 0.55
        ..strokeCap = StrokeCap.butt;
      canvas.drawPath(_straight(box.left, box.right, y - width * 0.7), paint);
      canvas.drawPath(_straight(box.left, box.right, y + width * 0.7), paint);

    case PartLineStyle.wavy:
      canvas.drawPath(
          _wobble(box.left, box.right, y,
              amplitude: width * 1.1, wavelength: width * 7, phase: 0),
          paint);

    case PartLineStyle.hand:
      // One pass, barely off straight, and running a little past the last
      // letter: a rule that stops dead on the final glyph is a rule, and a
      // hand-drawn line overshoots.
      canvas.drawPath(
          _wobble(
              box.left - width * 0.4, box.right + width * 1.2, y + width * 0.2,
              amplitude: width * 0.45,
              wavelength: box.width / 1.7 + width * 8,
              phase: phase,
              tilt: -width * 0.5),
          paint);

    case PartLineStyle.marker:
      // A brush rather than a stroke: the thickness varies along the line and
      // the ends taper, which is what a marker pen does and what a stroke of
      // one width cannot.
      canvas.drawPath(
          _brush(box.left - width * 0.5, box.right + width * 1.5,
              y + width * 0.3, width * 1.6, phase),
          Paint()..color = mark.color ?? fallback);

    case PartLineStyle.sketch:
      // Two passes that do not quite agree, which is what makes it read as
      // drawn rather than as printed.
      paint.strokeWidth = width * 0.8;
      canvas.drawPath(
          _wobble(box.left - width * 0.3, box.right + width, y,
              amplitude: width * 0.5,
              wavelength: box.width / 1.4 + width * 6,
              phase: phase,
              tilt: -width * 0.6),
          paint);
      canvas.drawPath(
          _wobble(
              box.left + width * 0.6, box.right + width * 0.4, y + width * 0.9,
              amplitude: width * 0.6,
              wavelength: box.width / 2.1 + width * 5,
              phase: phase + 2.1,
              tilt: width * 0.7),
          paint);
  }
}

Path _straight(double from, double to, double y) => Path()
  ..moveTo(from, y)
  ..lineTo(to, y);

/// _wobble is a line that is not quite straight.
///
/// Two sines of different lengths rather than one, so it wanders instead of
/// waving -- one sine at a long wavelength is a wave, and a wave under a word
/// is a spellchecker. [tilt] leans the whole line, which is the other half of
/// looking hand-made: nobody draws a line level.
Path _wobble(double from, double to, double y,
    {required double amplitude,
    required double wavelength,
    required double phase,
    double tilt = 0}) {
  var path = Path();
  var span = to - from;
  if (span <= 0) {
    return path
      ..moveTo(from, y)
      ..lineTo(from, y);
  }
  var steps = math.max(6, (span / 6).round());
  var length = math.max(1.0, wavelength);
  for (var i = 0; i <= steps; i++) {
    var t = i / steps;
    var x = from + span * t;
    var wave = math.sin(phase + t * span / length * 2 * math.pi) +
        math.sin(phase * 1.7 + t * span / (length * 0.37) * 2 * math.pi) * 0.35;
    var dy = y + wave * amplitude + tilt * (t - 0.5) * 2;
    i == 0 ? path.moveTo(x, dy) : path.lineTo(x, dy);
  }
  return path;
}

/// _brush is a marker stroke: a filled shape whose thickness varies and whose
/// ends taper away to nothing.
Path _brush(double from, double to, double y, double thick, double phase) {
  var span = to - from;
  if (span <= 0) return Path();
  var steps = math.max(8, (span / 5).round());
  var top = <Offset>[];
  var bottom = <Offset>[];
  for (var i = 0; i <= steps; i++) {
    var t = i / steps;
    var x = from + span * t;
    // Thick in the middle, thin at both ends, and never quite even along the
    // way -- a pen leaves more ink where it slows down.
    var taper = math.sin(t * math.pi);
    var vary = 0.8 + 0.2 * math.sin(phase + t * 9);
    var half = thick / 2 * math.pow(taper, 0.45).toDouble() * vary;
    var drift = math.sin(phase * 1.3 + t * 4) * thick * 0.12;
    top.add(Offset(x, y + drift - half));
    bottom.add(Offset(x, y + drift + half));
  }
  var path = Path()..moveTo(top.first.dx, top.first.dy);
  for (var p in top.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  for (var p in bottom.reversed) {
    path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

/// paintTextInBox lays [text] out inside [box] and draws it, honouring both
/// alignments and the outline.
///
/// Returns the height the text actually took, which the chart and the table
/// use to decide how much room is left for everything else.
/// [animation] and [reveal] draw it part way through arriving, which is what
/// a text element's keyframes ask for. See text_animator.dart.
double paintTextInBox(
  ui.Canvas canvas,
  String text,
  TextSpec spec,
  Rect box, {
  double scale = 1,
  Color? colorOverride,
  bool clip = false,
  TextAnimation? animation,
  double reveal = 1,
  List<TextPart> parts = const [],

  /// timings are where each part has got to, for the parts that arrive on
  /// their own account. See TextPartAnimation.
  List<PartTiming> timings = const [],

  /// asOne leaves the parts to arrive with everything else, which is what the
  /// way out is. See paintAnimatedText.
  bool asOne = false,
}) {
  if (text.isEmpty || box.width <= 0) return 0;

  var painter = layoutText(text, spec,
      maxWidth: box.width,
      scale: scale,
      colorOverride: colorOverride,
      fillWidth: true,
      parts: parts);

  var dy = switch (spec.verticalAlign) {
    VerticalAlignSpec.top => box.top,
    VerticalAlignSpec.middle => box.top + (box.height - painter.height) / 2,
    VerticalAlignSpec.bottom => box.bottom - painter.height,
  };

  // The horizontal position comes from the painter's own alignment, applied
  // over the full box width -- so the offset is always the box's left edge
  // and TextPainter has done the aligning. Computing it here as well would
  // align it twice, which puts centred text at three quarters across.
  var offset = Offset(box.left, dy);

  if (clip) {
    canvas.save();
    canvas.clipRect(box);
  }

  // The outline is laid out with the parts as well: bold and italic change
  // how wide a word is, so an outline built without them is an outline of a
  // different paragraph -- which is what "the outline does not work with
  // bold" looked like.
  //
  // And a preset that draws the outline needs one whether or not the type has
  // any, since it is the whole animation: the words are written in outline
  // and then filled in.
  var strokeOn = animation != null &&
      animation.on &&
      animation.preset.motion == TextMotion.strokeOn;
  var outlineSpec = spec.outlineWidth > 0
      ? spec
      : (strokeOn
          ? spec.copyWith(
              outlineWidth: math.max(1, spec.fontSize * 0.03),
              outlineColor: spec.color)
          // A part may want an outline in a paragraph that has none, in
          // which case the paragraph is stroked with nothing and only the
          // part's own run has a width to draw.
          : (partsOutline(parts) ? spec : null));
  var outline = outlineSpec == null
      ? null
      : layoutText(text, outlineSpec,
          maxWidth: box.width,
          scale: scale,
          outline: true,
          fillWidth: true,
          parts: parts);

  // A part's own highlight goes behind the words and its own underline under
  // them. Drawn whatever the animation is doing, because they are a fact
  // about the words rather than an arrival -- see TextPart.highlight.
  var marksMove = animation != null && animation.on && reveal < 1;
  paintPartMarks(canvas, painter, text, parts, spec, offset,
      behind: true,
      timings: timings,
      moving: marksMove ? animation : null,
      at: reveal);

  // Part way through arriving, if it is arriving. The animator is handed the
  // paragraph that has already been laid out -- and its outline, which moves
  // with it rather than being drawn once and left behind.
  // Once it has arrived there is nothing to animate -- unless the motion is
  // one that leaves something behind, which still has to be drawn.
  // Through the animator whenever anything at all is moving -- the arrival,
  // or one of the parts on its own account. It draws a still paragraph too,
  // so there is one path rather than two that have to agree about the holes
  // a part's own layer leaves behind it.
  if (animation != null &&
      ((animation.on && (reveal < 1 || animation.keeps)) ||
          (!asOne && partsAnimate(parts)))) {
    paintAnimatedText(canvas, painter, text, spec, offset, animation, reveal,
        maxWidth: box.width,
        outline: outline,
        parts: parts,
        timings: timings,
        asOne: asOne);
  } else {
    outline?.paint(canvas, offset);
    painter.paint(canvas, offset);
  }

  paintPartMarks(canvas, painter, text, parts, spec, offset,
      behind: false,
      timings: timings,
      moving: marksMove ? animation : null,
      at: reveal);

  if (clip) canvas.restore();
  return painter.height;
}

/// fitFontSize is the largest size at which [text] fits inside [box], for a
/// text element with autoSize on.
///
/// A bisection rather than a formula: the height of wrapped text is not a
/// smooth function of the font size -- it steps every time a word moves to
/// another line -- so there is nothing to solve, only something to search.
/// Twelve iterations gets within a twentieth of a point over any range worth
/// having, and it runs once per paint of one element.
/// [columns] is how many columns the text will be flowed into. Fitting
/// against one column's box when there are three of them is why the type came
/// out a third of the size it could be -- and since all the text then fitted
/// in the first column, the other two were empty, which read as columns not
/// working with Fit to box at all.
double fitFontSize(String text, TextSpec spec, Size box, {int columns = 1}) {
  if (text.isEmpty || box.width <= 0 || box.height <= 0) return spec.fontSize;
  var count = math.max(1, columns);
  var low = 4.0, high = box.height * 2 * count;
  for (var i = 0; i < 14; i++) {
    var mid = (low + high) / 2;
    var p = layoutText(text, spec.copyWith(fontSize: mid), maxWidth: box.width);
    if (p.width > box.width + 0.5) {
      high = mid;
      continue;
    }
    if (count == 1) {
      p.height <= box.height ? low = mid : high = mid;
      continue;
    }
    // Against the packing rather than against the height times the number of
    // columns: a line cannot be split between two of them, so the room a
    // column really holds is a whole number of lines and is always a little
    // less than its height.
    var runs = columnRuns(p.computeLineMetrics(), box.height, count);
    var carried = runs.isEmpty ? 0 : runs.last.$2;
    carried >= p.computeLineMetrics().length ? low = mid : high = mid;
  }
  return low;
}

/// _partedSpan builds the paragraph out of runs, so a few words in it can be
/// a different colour or weight from the rest.
///
/// One span per run of characters that share an answer, which is what makes
/// this cheap: a sentence with one word coloured is three spans, not one per
/// letter. The runs come from the parts themselves -- see partAt -- so the
/// same rule decides what is drawn and what a settings panel says is drawn.
TextSpan _partedSpan(String text, TextSpec spec, List<TextPart> parts,
    TextStyle style, Color? colorOverride, double scale) {
  var children = <TextSpan>[];
  var from = 0;
  TextPart? current = partAt(text, parts, 0);

  TextStyle styleFor(TextPart? part) {
    // An outline run is drawn by a stroke paint, and a style cannot carry
    // both that and a colour -- so an outline takes the part's weight and
    // slant, and its own width and colour where it has asked for them, and
    // leaves the fill colour alone. Setting both threw, which is why the
    // outline setting appeared not to work at all on an element with parts:
    // the paragraph it belongs to could not be built.
    if (style.foreground != null) {
      var width = part?.outlineWidth ?? spec.outlineWidth;
      var out = part == null
          ? style
          : style.copyWith(
              fontWeight: part.weight == null
                  ? style.fontWeight
                  : FontWeight.values[((part.weight! ~/ 100) - 1)
                      .clamp(0, FontWeight.values.length - 1)],
              fontStyle: part.italic == null
                  ? style.fontStyle
                  : (part.italic! ? FontStyle.italic : FontStyle.normal),
            );
      // Its own stroke paint rather than a second paragraph, so one layout
      // still serves the lot. A width of nothing is drawn in nothing rather
      // than left to the stroke: a zero-width stroke is a hairline, so the
      // words with no outline would have got a thin one.
      return out.copyWith(
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = width * 2 * scale
          ..color = width <= 0
              ? const Color(0x00000000)
              : (part?.outlineColor ?? spec.outlineColor),
      );
    }
    if (part == null) return style;
    return style.copyWith(
      // colorOverride wins: it is how a preview draws the whole paragraph in
      // one colour, and a part that ignored it would be a word that stayed
      // its own colour in a ghost.
      color: colorOverride ?? part.color ?? style.color,
      fontWeight: part.weight == null
          ? style.fontWeight
          : FontWeight.values[((part.weight! ~/ 100) - 1)
              .clamp(0, FontWeight.values.length - 1)],
      fontStyle: part.italic == null
          ? style.fontStyle
          : (part.italic! ? FontStyle.italic : FontStyle.normal),
    );
  }

  for (var i = 1; i <= text.length; i++) {
    var here = i == text.length ? null : partAt(text, parts, i);
    if (i == text.length || !identical(here, current)) {
      children.add(
          TextSpan(text: text.substring(from, i), style: styleFor(current)));
      from = i;
      current = here;
    }
  }
  return TextSpan(children: children, style: style);
}

/// paintBox draws a [BoxSpec]: the fill, then the border, both rounded.
void paintBox(ui.Canvas canvas, Rect rect, BoxSpec box) {
  if (rect.width <= 0 || rect.height <= 0) return;
  var rrect = RRect.fromRectAndRadius(rect, Radius.circular(box.borderRadius));

  if (box.fill.a > 0) {
    canvas.drawRRect(rrect, Paint()..color = box.fill);
  }
  if (box.borderWidth > 0 && box.borderColor.a > 0) {
    // Inset by half the stroke so the border sits inside the element's
    // bounds. Drawn centred, a thick border on a full-bleed element is half
    // cut off by the edge of the canvas -- and it is exactly the elements
    // pushed against an edge that get thick borders.
    var inset = box.borderWidth / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(inset),
          Radius.circular(math.max(0, box.borderRadius - inset))),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = box.borderWidth
        ..color = box.borderColor,
    );
  }
}

/// shapePath turns a [ShapeKind] into a path filling [rect].
///
/// Every shape is written in the rectangle it is given rather than in a unit
/// square and scaled, because scaling a unit square scales the stroke with it
/// -- a 2px outline on a shape stretched to twice as wide comes out 2px on one
/// axis and 4px on the other, which looks like a bug and is very hard to see
/// as one.
Path shapePath(ShapeKind kind, Rect rect,
    {int points = 5,
    double inner = 0.42,
    double cornerRadius = 0,
    SpeechBubbleSpec bubble = const SpeechBubbleSpec()}) {
  var path = Path();
  var c = rect.center;
  var rx = rect.width / 2, ry = rect.height / 2;

  switch (kind) {
    case ShapeKind.rectangle:
    case ShapeKind.square:
      if (cornerRadius > 0) {
        path.addRRect(
            RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius)));
      } else {
        path.addRect(rect);
      }

    case ShapeKind.ellipse:
    case ShapeKind.circle:
      path.addOval(rect);

    case ShapeKind.triangle:
      path.moveTo(c.dx, rect.top);
      path.lineTo(rect.right, rect.bottom);
      path.lineTo(rect.left, rect.bottom);
      path.close();

    case ShapeKind.diamond:
      path.moveTo(c.dx, rect.top);
      path.lineTo(rect.right, c.dy);
      path.lineTo(c.dx, rect.bottom);
      path.lineTo(rect.left, c.dy);
      path.close();

    case ShapeKind.pentagon:
      _regular(path, c, rx, ry, 5);
    case ShapeKind.hexagon:
      _regular(path, c, rx, ry, 6);

    case ShapeKind.star:
      var n = points.clamp(3, 24);
      var ratio = inner.clamp(0.05, 0.95).toDouble();
      for (var i = 0; i < n * 2; i++) {
        var a = -math.pi / 2 + i * math.pi / n;
        var r = i.isEven ? 1.0 : ratio;
        var p =
            Offset(c.dx + math.cos(a) * rx * r, c.dy + math.sin(a) * ry * r);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();

    case ShapeKind.arrow:
      // A shaft along the middle third with a head taking the last quarter.
      var headStart = rect.left + rect.width * 0.72;
      var shaft = rect.height * 0.34;
      path.moveTo(rect.left, c.dy - shaft / 2);
      path.lineTo(headStart, c.dy - shaft / 2);
      path.lineTo(headStart, rect.top);
      path.lineTo(rect.right, c.dy);
      path.lineTo(headStart, rect.bottom);
      path.lineTo(headStart, c.dy + shaft / 2);
      path.lineTo(rect.left, c.dy + shaft / 2);
      path.close();

    case ShapeKind.chevron:
      var notch = rect.width * 0.28;
      path.moveTo(rect.left, rect.top);
      path.lineTo(rect.right - notch, rect.top);
      path.lineTo(rect.right, c.dy);
      path.lineTo(rect.right - notch, rect.bottom);
      path.lineTo(rect.left, rect.bottom);
      path.lineTo(rect.left + notch, c.dy);
      path.close();

    case ShapeKind.cross:
      var t = math.min(rx, ry) * 0.42;
      path.addRect(Rect.fromLTRB(c.dx - t, rect.top, c.dx + t, rect.bottom));
      path.addRect(Rect.fromLTRB(rect.left, c.dy - t, rect.right, c.dy + t));

    case ShapeKind.speechBubble:
      return bubblePath(rect, bubble, cornerRadius);
  }
  return path;
}

void _regular(Path path, Offset c, double rx, double ry, int sides) {
  for (var i = 0; i < sides; i++) {
    var a = -math.pi / 2 + i * 2 * math.pi / sides;
    var p = Offset(c.dx + math.cos(a) * rx, c.dy + math.sin(a) * ry);
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  path.close();
}

/// dashPath breaks [source] into dashes of [on] followed by gaps of [off].
///
/// Written out rather than reached for from a package, because it is fifteen
/// lines over PathMetrics and it is wanted by exactly two things -- a dashed
/// line element and a chart's grid.
Path dashPath(Path source, double on, double off) {
  if (on <= 0) return source;
  var out = Path();
  for (var metric in source.computeMetrics()) {
    var d = 0.0;
    while (d < metric.length) {
      var next = math.min(d + on, metric.length);
      out.addPath(metric.extractPath(d, next), Offset.zero);
      d = next + off;
    }
  }
  return out;
}

/// arrowHead is a filled triangle at [tip], pointing along [angle].
/// arrowSpread is the half-angle between an arrowhead's axis and each barb.
///
/// Shared, because the stroke has to be cut back to exactly where the barbs
/// meet -- see _trimFor -- and a second copy of this number would put the cut
/// somewhere the arrow is not.
const double arrowSpread = 0.42;

void arrowHead(
    ui.Canvas canvas, Offset tip, double angle, double size, Paint paint,
    {bool filled = true}) {
  var back = angle + math.pi;
  var spread = arrowSpread;
  var path = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(tip.dx + math.cos(back - spread) * size,
        tip.dy + math.sin(back - spread) * size)
    ..lineTo(tip.dx + math.cos(back + spread) * size,
        tip.dy + math.sin(back + spread) * size)
    ..close();
  canvas.drawPath(
      path,
      Paint()
        ..color = paint.color
        ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = paint.strokeWidth
        ..strokeJoin = StrokeJoin.miter);
}

/// _capHeightRatio is how much of a font's size the capitals and digits
/// actually occupy, measured from the baseline.
///
/// A constant rather than a measurement because Flutter does not expose a
/// font's cap height, and the value is remarkably consistent across the faces
/// this offers -- 0.70 to 0.73 for all of them. Being a few thousandths out
/// moves a squad number by well under half a pixel at any size a dot is drawn
/// at, which is why an approximation is good enough here and would not be for
/// laying out a paragraph.
const double _capHeightRatio = 0.71;

/// paintCentredGlyphs draws [text] with its *ink* centred on [center].
///
/// Not the same as centring the laid-out box, which is what every other text
/// in this file does and what a squad number had before. A line box is tall
/// enough for ascenders and descenders whether or not the string has any, and
/// it grows with the line height on top of that -- so where the box sits and
/// where the digit *looks* like it sits are two different questions.
///
/// On the default line height the two answers are only about a pixel apart at
/// a 40px number, which would not be worth a function. What makes it worth one
/// is that a team's numbers and names share a single TextSpec (see
/// TeamElement.labelSpec): the line height gets set for the names, and centred
/// by its box the number then slides out of its dot as the leading grows.
/// Centred by its ink it does not move at all.
///
/// Digits and capitals sit between the baseline and one cap height above it,
/// so their true middle is `baseline - capHeight / 2`, and that is what is put
/// on the centre.
void paintCentredGlyphs(
  ui.Canvas canvas,
  String text,
  TextSpec spec,
  Offset center, {
  double scale = 1,
}) {
  if (text.isEmpty) return;

  // A number is one short token, so it is laid out unconstrained: wrapping a
  // squad number is never what was wanted, and an unbounded line keeps "10"
  // on one line inside a dot barely wider than it.
  var painter = layoutText(text, spec, maxWidth: double.infinity, scale: scale);
  var baseline =
      painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  if (!baseline.isFinite) baseline = painter.height;

  var capHeight = spec.fontSize * scale * _capHeightRatio;
  var at = Offset(
    center.dx - painter.width / 2,
    center.dy - (baseline - capHeight / 2),
  );

  if (spec.outlineWidth > 0) {
    layoutText(text, spec,
            maxWidth: double.infinity, scale: scale, outline: true)
        .paint(canvas, at);
  }
  painter.paint(canvas, at);
}

/// paintTextInColumns flows one paragraph across [columns] columns of [box].
///
/// The paragraph is laid out **once**, at a column's width, and then drawn once
/// per column clipped to that column and shifted up by the lines already used.
/// One layout rather than one per column, because splitting the text into
/// pieces and laying each out separately would need the split to be decided
/// before the lines are known -- which is the thing being worked out.
///
/// Lines are kept whole. A column break falls between two lines, never through
/// one, which is what a column of text is; the alternative slices letters in
/// half across the gutter.
/// columnRuns is which lines of a laid-out paragraph go in which column.
///
/// Whole lines only, which is the whole of it: a column that shows fifteen and
/// three quarters of a line is a column with a row of half-letters along the
/// bottom, and the quarter that was cut off appears again at the top of the
/// next one. A line that does not fit in what is left of a column goes to the
/// next column entire.
///
/// Measured from the paragraph's own line metrics rather than from a line
/// height multiplied out, because lines are not all the same height -- a line
/// with nothing tall on it is shorter -- and fifteen lines of "about the same"
/// is a cut line by the bottom of the column.
List<(int, int)> columnRuns(
    List<ui.LineMetrics> metrics, double height, int columns) {
  if (metrics.isEmpty || columns <= 0) return const [];

  /// top is where a line starts, measured from the top of the paragraph.
  double top(int line) => line >= metrics.length
      ? metrics.last.baseline + metrics.last.descent
      : metrics[line].baseline - metrics[line].ascent;

  var runs = <(int, int)>[];
  var at = 0;
  for (var c = 0; c < columns && at < metrics.length; c++) {
    var end = at;
    // At least one line per column even where it does not fit: a box shorter
    // than a single line would otherwise take no lines at all and draw
    // nothing, which reads as the text having been lost.
    while (end < metrics.length &&
        (end == at || top(end + 1) - top(at) <= height + 0.5)) {
      end++;
    }
    runs.add((at, end));
    at = end;
  }
  return runs;
}

/// [animation] and [reveal] draw it part way through arriving. The pieces are
/// worked out once for the whole paragraph and then drawn column by column,
/// so a stagger runs from the first word of the first column to the last word
/// of the last rather than restarting in each.
void paintTextInColumns(
  ui.Canvas canvas,
  String text,
  TextSpec spec,
  Rect box,
  TextColumns columns, {
  double scale = 1,
  TextAnimation? animation,
  double reveal = 1,
  List<TextPart> parts = const [],
  List<PartTiming> timings = const [],
  bool asOne = false,
}) {
  if (text.isEmpty || box.width <= 0 || box.height <= 0) return;

  var width = columns.columnWidth(box.width);
  if (width <= 0) return;

  var painter = layoutText(text, spec,
      maxWidth: width, scale: scale, fillWidth: true, parts: parts);
  var metrics = painter.computeLineMetrics();
  if (metrics.isEmpty) return;

  var runs = columnRuns(metrics, box.height, columns.count);

  var outline = spec.outlineWidth > 0 || partsOutline(parts)
      ? layoutText(text, spec,
          maxWidth: width,
          scale: scale,
          outline: true,
          fillWidth: true,
          parts: parts)
      : null;

  double top(int line) => line >= metrics.length
      ? metrics.last.baseline + metrics.last.descent
      : metrics[line].baseline - metrics[line].ascent;

  for (var i = 0; i < runs.length; i++) {
    var (from, to) = runs[i];
    var left = box.left + i * (width + columns.gap);

    // The lines this column actually holds, which is what it is clipped to.
    // Clipped to the whole box instead, a sixteenth line three quarters
    // taller than the room left over showed three quarters of itself along
    // the bottom -- and the same three quarters appeared again at the top of
    // the next column, which is what "the columns cut the text" was.
    var used = top(to) - top(from);
    var dy = switch (spec.verticalAlign) {
      VerticalAlignSpec.top => 0.0,
      VerticalAlignSpec.middle => (box.height - used) / 2,
      VerticalAlignSpec.bottom => box.height - used,
    };

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(left, box.top + dy, width, used));
    var at = Offset(left, box.top + dy - top(from));

    // The marks are drawn per column against the whole paragraph, and the
    // column's clip keeps each one to its own lines: a part that runs from
    // the bottom of one column into the top of the next is marked in both,
    // which is what it looks like on the page.
    var marksMove = animation != null && animation.on && reveal < 1;
    paintPartMarks(canvas, painter, text, parts, spec, at,
        behind: true,
        timings: timings,
        moving: marksMove ? animation : null,
        at: reveal);

    var moving = (animation != null &&
            animation.on &&
            (reveal < 1 || animation.keeps)) ||
        (!asOne && partsAnimate(parts));
    if (moving) {
      // The pieces this column holds: the ones whose lines fall in its run.
      // Their places in the whole paragraph decide their progress, which is
      // what makes the stagger carry on from one column into the next.
      paintAnimatedText(canvas, painter, text, spec, at,
          animation ?? const TextAnimation(), reveal,
          maxWidth: width,
          outline: outline,
          parts: parts,
          timings: timings,
          asOne: asOne, keep: (piece) {
        // A block-scoped piece covers the paragraph, which every column
        // shares: it moves or uncovers the same way in each.
        if (piece.box.height >= painter.height - 0.5) return true;
        var middle = piece.box.center.dy;
        return middle >= top(from) - 0.5 && middle < top(to) + 0.5;
      });
    } else {
      outline?.paint(canvas, at);
      painter.paint(canvas, at);
    }
    paintPartMarks(canvas, painter, text, parts, spec, at,
        behind: false,
        timings: timings,
        moving: marksMove ? animation : null,
        at: reveal);
    canvas.restore();
  }

  // Down the text rather than down the box. The columns hold a whole number
  // of lines, so the room left under the last one is not text and a rule
  // drawn through it is a line beside a row that is not there.
  var tallest = 0.0;
  for (var (from, to) in runs) {
    tallest = math.max(tallest, top(to) - top(from));
  }
  // Where that column's text starts, which is where the rule starts: the
  // alignment moves the whole block, and a rule pinned to the top of the box
  // beside text sitting at the bottom of it is a line beside nothing.
  var above = switch (spec.verticalAlign) {
    VerticalAlignSpec.top => 0.0,
    VerticalAlignSpec.middle => (box.height - tallest) / 2,
    VerticalAlignSpec.bottom => box.height - tallest,
  };
  _paintColumnRules(canvas, box, columns, width, above, tallest);
}

/// _paintColumnRules draws the line down the middle of each gutter.
/// [textHeight] is how far the text actually reaches, which is what the rule
/// is drawn beside. The box is taller than that by whatever was left over
/// after the last whole line, and a rule down all of it is a line beside a row
/// that is not there.
void _paintColumnRules(ui.Canvas canvas, Rect box, TextColumns columns,
    double width, double above, double textHeight) {
  if (columns.ruleStyle == ColumnRuleStyle.none ||
      columns.ruleWidth <= 0 ||
      columns.gap <= 0) {
    return;
  }

  var paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = columns.ruleWidth
    ..strokeCap = columns.ruleStyle == ColumnRuleStyle.dotted
        ? StrokeCap.round
        : StrokeCap.butt
    ..color = columns.ruleColor;

  // A little past the last line rather than exactly to it: a rule stopping
  // dead on the baseline of the bottom row reads as too short, and the
  // descenders hang below it anyway.
  var from = box.top + (textHeight <= 0 ? 0 : above.clamp(0, box.height));
  var reach = textHeight <= 0
      ? box.height
      : math.min(box.bottom - from, textHeight * 1.02 + columns.ruleWidth * 2);

  for (var i = 1; i < columns.count; i++) {
    var x = box.left + i * (width + columns.gap) - columns.gap / 2;
    var line = ui.Path()
      ..moveTo(x, from)
      ..lineTo(x, from + reach);
    canvas.drawPath(
      switch (columns.ruleStyle) {
        ColumnRuleStyle.dashed =>
          dashPath(line, columns.ruleWidth * 4, columns.ruleWidth * 3),
        // A dotted rule is a dashed one whose dashes are nothing and whose cap
        // is round -- a zero-length stroke with a round cap is a dot.
        ColumnRuleStyle.dotted => dashPath(line, 0.01, columns.ruleWidth * 3),
        _ => line,
      },
      paint,
    );
  }
}

/// paintTextOnPath lays [text] out along [curve], one glyph at a time.
///
/// Glyph by glyph because that is the only way letters can turn with the line:
/// a paragraph is one rectangle of pixels and rotating it puts the whole
/// sentence at an angle rather than bending it.
///
/// [curve] is a polyline in document space, already sampled finely enough that
/// walking it in straight steps is indistinguishable from following the curve
/// -- see _curveSamplesPerSegment.
class PlacedGlyph {
  final String glyph;

  /// at is where the glyph's baseline centre sits, and angle is the heading of
  /// the curve there.
  final Offset at;
  final double angle;
  final Size size;

  /// index is where this glyph starts in the text it came from, so a part --
  /// "words three to four" -- can be found again once the letters have been
  /// scattered along a line. Without it there is no way back from a glyph to
  /// the sentence, and a curve could not be told which of its words to
  /// colour or to animate.
  final int index;

  /// spec is what this glyph is drawn in, which is the element's own unless
  /// a part says otherwise. Carried rather than looked up again at drawing
  /// time so that the letter that was measured is the letter that is drawn.
  final TextSpec spec;

  const PlacedGlyph(this.glyph, this.at, this.angle, this.size,
      {this.index = 0, this.spec = const TextSpec()});
}

/// placeTextOnPath works out where every letter of [text] goes along [curve].
///
/// Separated from the drawing so that the selection box and the painter cannot
/// disagree about where the words are. They did: the box was drawn from the
/// element's own rectangle, which for text riding a line is wherever the box
/// happened to be dropped and nowhere near the letters -- so clicking the text
/// put a selection box in an empty part of the canvas.
///
/// [curve] is a polyline in document space, already sampled finely enough that
/// walking it in straight steps is indistinguishable from following the curve.
List<PlacedGlyph> placeTextOnPath(
  String text,
  TextSpec spec,
  List<Offset> curve,
  TextOnCurve on, {
  double scale = 1,

  /// parts colour, embolden or italicise some of the letters -- see TextPart.
  /// A part changes how wide a letter is, so it has to be known here, where
  /// the letters are measured, and not only where they are drawn.
  List<TextPart> parts = const [],
}) {
  if (text.isEmpty || curve.length < 2) return const [];

  // Cumulative distance along the polyline, so a position in length can be
  // turned into a point and a direction.
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
  var specs = [
    for (var i = 0; i < glyphs.length; i++)
      _specForPart(spec, partAt(text, parts, at0[i])),
  ];
  var painters = [
    for (var i = 0; i < glyphs.length; i++)
      layoutText(glyphs[i], specs[i], maxWidth: double.infinity, scale: scale),
  ];
  var widths = [for (var p in painters) p.width + on.spacing * scale];
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
    // Past the ends of the line the letters carry straight on rather than
    // being dropped -- see _alongPolyline. Dropped, a caption slid along its
    // line did not travel off it: the letters disappeared one at a time at
    // the end of the line and reappeared at the other, which is not a slide.
    var (point, angle) = _alongPolyline(curve, lengths, centre);
    out.add(PlacedGlyph(
        glyphs[i], point, angle, Size(painters[i].width, painters[i].height),
        index: at0[i], spec: specs[i]));
  }
  return out;
}

/// _animatedPartAt is which part arriving on its own account covers the
/// character at [index], or -1 for none.
int _animatedPartAt(String text, List<TextPart> parts, int index) {
  var found = -1;
  for (var (i, part) in parts.indexed) {
    if (!part.animation.on) continue;
    var range = rangeOf(text, part);
    if (range == null) continue;
    if (index >= range.$1 && index < range.$2) found = i;
  }
  return found;
}

/// _specForPart is [spec] with whatever [part] says about these letters.
TextSpec _specForPart(TextSpec spec, TextPart? part) {
  if (part == null) return spec;
  return spec.copyWith(
    color: part.color ?? spec.color,
    weight: part.weight ?? spec.weight,
    italic: part.italic ?? spec.italic,
    outlineWidth: part.outlineWidth ?? spec.outlineWidth,
    outlineColor: part.outlineColor ?? spec.outlineColor,
  );
}

/// textOnPathBounds is the rectangle the placed letters occupy.
///
/// A box around every glyph's four corners once it has been turned, rather
/// than around the points they sit on -- a letter on a steep bend sticks well
/// out from the line it is riding, and a box that ignored that would clip the
/// thing it is supposed to be around.
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

/// paintTextOnPath lays [text] out along [curve], one glyph at a time.
///
/// Glyph by glyph because that is the only way letters can turn with the line:
/// a paragraph is one rectangle of pixels and rotating it puts the whole
/// sentence at an angle rather than bending it.
///
/// [animation] and [reveal] draw it part way through arriving. The motions
/// are the same ones a paragraph uses -- see applyMotion -- applied in each
/// glyph's own turned frame, so a letter on a bend rises along the line
/// rather than straight up the page. Text on a curve used to ignore the
/// animation settings entirely: the presets could be chosen and nothing
/// happened.
void paintTextOnPath(
  ui.Canvas canvas,
  String text,
  TextSpec spec,
  List<Offset> curve,
  TextOnCurve on, {
  double scale = 1,
  TextAnimation? animation,
  double reveal = 1,
  List<TextPart> parts = const [],
  List<PartTiming> timings = const [],
  bool asOne = false,
}) {
  var glyphs =
      placeTextOnPath(text, spec, curve, on, scale: scale, parts: parts);
  if (glyphs.isEmpty) return;

  var moving =
      animation != null && animation.on && (reveal < 1 || animation.keeps);

  // Which layer each letter belongs to: a part that arrives on its own
  // account, or the paragraph's own arrival. A curve has no lines and no
  // blocks to clip, so the layers are simply groups of letters -- which is
  // the one place this is easier than a box.
  var layer = <int>[
    for (var g in glyphs) asOne ? -1 : _animatedPartAt(text, parts, g.index),
  ];

  /// animationOf is what moves this letter, and revealOf how far through it
  /// is -- the part's own where it has one, the paragraph's otherwise.
  TextAnimation? animationOf(int of) =>
      of < 0 ? (moving ? animation : null) : parts[of].animation.asAnimation;
  double revealOf(int of) =>
      of < 0 ? reveal : (of < timings.length ? timings[of].words : 1);

  // Where each letter comes in the order of its own layer, and how many
  // places that layer has. A word-scoped preset counts words, so the letters
  // of one word move together; anything else counts letters, a whole-block
  // preset having one place that they all share.
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
        var space = glyphs[i].glyph.trim().isEmpty;
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
    // The glyph's own rectangle in the frame it is drawn in: its baseline
    // centre is the origin, so it reaches half its width either side.
    var local = Rect.fromLTWH(
        -g.size.width / 2, dy, g.size.width, math.max(1, g.size.height));

    // Null exactly when this letter is not moving, so the drawing below can
    // ask it things without asking whether it is there.
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
        : applyMotion(canvas, local, anim.preset, p,
            from: anim.scaleFor(anim.preset), seed: g.index);

    // A mark drawn along the words follows the curve because it is drawn a
    // letter at a time, each in its own frame: the band under a bend is a
    // band under a bend rather than a rectangle across the picture. It
    // sweeps in letter order whatever the preset's scope, or a whole-block
    // underline would grow under every letter at once.
    var sweep =
        anim == null ? 1.0 : (p * glyphs.length - i).clamp(0.0, 1.0).toDouble();
    if (anim != null && anim.preset.motion == TextMotion.highlight) {
      _paintCurveMark(canvas, local, anim.draw, spec, sweep, under: false);
    }

    // The copies of an echo or a trail, drawn in the same turned frame so
    // they fan out along the line rather than down the page -- and before the
    // letter, since they belong behind it.
    if (anim != null &&
        (anim.preset.motion == TextMotion.echo ||
            anim.preset.motion == TextMotion.trail)) {
      _paintCurveCopies(canvas, g, dy, scale, local, anim, p);
    }

    _paintGlyph(canvas, g, dy, scale, frame.alpha);

    if (anim != null && anim.preset.motion == TextMotion.underline) {
      _paintCurveMark(canvas, local, anim.draw, spec, sweep, under: true);
    }

    for (var r = 0; r < frame.depth; r++) {
      canvas.restore();
    }
    canvas.restore();
  }
}

/// _paintGlyph draws one placed letter, and its outline where it has one.
void _paintGlyph(
    ui.Canvas canvas, PlacedGlyph g, double dy, double scale, double alpha) {
  var at = Offset(-g.size.width / 2, dy);
  var faded = alpha < 1;
  if (faded) {
    if (alpha <= 0) return;
    canvas.saveLayer(
        Rect.fromLTWH(at.dx, at.dy, g.size.width, g.size.height)
            .inflate(g.size.height * 2),
        Paint()..color = Color.fromRGBO(0, 0, 0, alpha.clamp(0.0, 1.0)));
  }
  if (g.spec.outlineWidth > 0) {
    layoutText(g.glyph, g.spec,
            maxWidth: double.infinity, scale: scale, outline: true)
        .paint(canvas, at);
  }
  layoutText(g.glyph, g.spec, maxWidth: double.infinity, scale: scale)
      .paint(canvas, at);
  if (faded) canvas.restore();
}

/// _paintCurveMark is an underline or a highlight under one letter of a
/// curve, [sweep] of the way drawn.
void _paintCurveMark(ui.Canvas canvas, Rect local, TextDrawSpec mark,
    TextSpec spec, double sweep,
    {required bool under}) {
  if (sweep <= 0) return;
  // A letter's share of the mark reaches half the gap to its neighbours, or
  // the marks would be a row of separate tiles with the tracking showing
  // between them.
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
  canvas.drawRect(
      Rect.fromLTWH(left, local.top - mark.padTop, width,
          local.height + mark.padTop + mark.padBottom),
      Paint()..color = mark.color ?? spec.color.withValues(alpha: 0.25));
}

/// _paintCurveCopies draws an echo's or a trail's copies of one letter.
void _paintCurveCopies(ui.Canvas canvas, PlacedGlyph g, double dy, double scale,
    Rect local, TextAnimation animation, double p) {
  var echo = animation.echo;
  var preset = animation.preset;
  var trail = preset.motion == TextMotion.trail;
  var step = trail
      ? Offset(local.width * preset.dx * (1 - p),
              local.height * preset.dy * (1 - p)) *
          (echo.spacing / math.max(1, echo.copies))
      : Offset(
          preset.dx * local.height * echo.spacing,
          preset.dy == 0
              ? local.height * echo.spacing
              : preset.dy * local.height * echo.spacing,
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
      _paintGlyph(canvas, g, dy, scale, (strength * arrived).clamp(0.0, 1.0));
      canvas.restore();
    }
  }
}

/// _alongPolyline is the point and heading at [distance] along [curve].
/// Before the start and after the end it keeps going, along the heading the
/// line had there. A caption slid off the end of its line has to be somewhere,
/// and the somewhere that reads as "off the end" is further along the same
/// direction -- not piled up on the last point, which is what a clamp does.
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

/// bubbleBodyRect is the part of a speech bubble the words go in.
///
/// The bubble's box has to hold the tail as well, so the body gives up room on
/// the side the tail points at -- and only that side. Insetting all four
/// equally would shrink the bubble by the tail's length however short a tail
/// it had, and a bubble is mostly its body.
Rect bubbleBodyRect(Rect rect, SpeechBubbleSpec bubble) {
  if (bubble.tail == BubbleTail.none) return rect;
  var radians = bubble.tailAngle * math.pi / 180;
  var dx = math.cos(radians);
  var dy = math.sin(radians);
  var reach = rect.shortestSide / 2 * bubble.tailLength;
  return Rect.fromLTRB(
    rect.left + (dx < 0 ? -dx * reach : 0),
    rect.top + (dy < 0 ? -dy * reach : 0),
    rect.right - (dx > 0 ? dx * reach : 0),
    rect.bottom - (dy > 0 ? dy * reach : 0),
  );
}

/// bubblePath is a speech bubble as one outline.
///
/// One outline is the whole point. The tail used to be a second closed
/// sub-path laid over the body: filled they merged, but *stroked* each
/// sub-path drew its own boundary, so a line ran across the join and the tail
/// read as a separate shape stuck on the side. Path.combine unions them into a
/// single boundary, which is what a drawn bubble is.
Path bubblePath(Rect rect, SpeechBubbleSpec bubble, double cornerRadius) {
  var body = bubbleBodyRect(rect, bubble);
  var shape = _bubbleBody(body, bubble.body, cornerRadius);
  if (bubble.tail == BubbleTail.none) return shape;

  var radians = bubble.tailAngle * math.pi / 180;
  var out = Offset(math.cos(radians), math.sin(radians));
  // Where the tail leaves the body: the point on the body's own ellipse in
  // that direction. An ellipse rather than the rectangle, so a tail at 45
  // degrees comes out of the corner rather than off the end of a side.
  var anchor = Offset(body.center.dx + out.dx * body.width / 2,
      body.center.dy + out.dy * body.height / 2);
  var reach = rect.shortestSide / 2 * bubble.tailLength;
  var tip = anchor + out * reach;

  // A thought bubble is not attached at all: it is a trail of shrinking
  // circles, and unioning them would weld them into a sausage.
  if (bubble.tail == BubbleTail.thought) {
    var trail = Path();
    var count = 3;
    var unit = rect.shortestSide / 2 * bubble.tailWidth * 0.5;
    // From the body's own edge, not from the ellipse the pointer uses. Every
    // body except the oval reaches past that ellipse -- a rounded rectangle
    // is outside it everywhere but the middle of each side -- so dots placed
    // against the ellipse sat inside the bubble and welded to it, and a
    // thought bubble welded to its body is a badly drawn pointer.
    var edge = _rayToRect(body, out);
    for (var i = 0; i < count; i++) {
      var t = i / (count - 1);
      var at = edge + out * (unit * 1.6 + reach * 0.9 * t);
      trail.addOval(Rect.fromCircle(center: at, radius: unit * (1 - t * 0.4)));
    }
    return Path.combine(PathOperation.union, shape, trail);
  }

  var across =
      Offset(-out.dy, out.dx) * (rect.shortestSide / 2 * bubble.tailWidth / 2);
  // Started from inside the body so the union has something to bite on: a
  // triangle that merely touched the outline would leave a hairline where the
  // two boundaries met.
  var root = anchor - out * (reach * 0.35);
  var tail = Path()..moveTo(root.dx + across.dx, root.dy + across.dy);

  if (bubble.tail == BubbleTail.curved) {
    // A hooked tail, which is what almost every drawn bubble has: it leaves
    // the body square and bends as it narrows.
    var bend = Offset(-out.dy, out.dx) * (reach * bubble.curl);
    tail
      ..quadraticBezierTo(
          anchor.dx + bend.dx, anchor.dy + bend.dy, tip.dx, tip.dy)
      ..quadraticBezierTo(anchor.dx + bend.dx * 0.35,
          anchor.dy + bend.dy * 0.35, root.dx - across.dx, root.dy - across.dy);
  } else {
    tail
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(root.dx - across.dx, root.dy - across.dy);
  }
  tail.close();

  return Path.combine(PathOperation.union, shape, tail);
}

/// _rayToRect is where a ray from [rect]'s centre in direction [out] crosses
/// its edge.
Offset _rayToRect(Rect rect, Offset out) {
  var half = Offset(rect.width / 2, rect.height / 2);
  var scaleX = out.dx == 0 ? double.infinity : (half.dx / out.dx).abs();
  var scaleY = out.dy == 0 ? double.infinity : (half.dy / out.dy).abs();
  var scale = math.min(scaleX, scaleY);
  if (!scale.isFinite) return rect.center;
  return rect.center + out * scale;
}

Path _bubbleBody(Rect body, BubbleBody kind, double cornerRadius) {
  var path = Path();
  switch (kind) {
    case BubbleBody.rounded:
      var r = math.min(
          cornerRadius > 0 ? cornerRadius : body.shortestSide * 0.22,
          body.shortestSide / 2);
      path.addRRect(RRect.fromRectAndRadius(body, Radius.circular(r)));
    case BubbleBody.oval:
      path.addOval(body);
    case BubbleBody.cloud:
      // Overlapping circles round the rim, unioned into one puffy outline.
      var lumps = Path()..addOval(body.deflate(body.shortestSide * 0.14));
      const count = 11;
      for (var i = 0; i < count; i++) {
        var a = i * 2 * math.pi / count;
        var at = Offset(body.center.dx + math.cos(a) * body.width * 0.36,
            body.center.dy + math.sin(a) * body.height * 0.36);
        lumps = Path.combine(
            PathOperation.union,
            lumps,
            Path()
              ..addOval(Rect.fromCircle(
                  center: at, radius: body.shortestSide * 0.19)));
      }
      return lumps;
    case BubbleBody.burst:
      // A shout: alternating long and short points all the way round.
      const spikes = 12;
      for (var i = 0; i < spikes * 2; i++) {
        var a = -math.pi / 2 + i * math.pi / spikes;
        var far = i.isEven ? 1.0 : 0.74;
        var p = Offset(body.center.dx + math.cos(a) * body.width / 2 * far,
            body.center.dy + math.sin(a) * body.height / 2 * far);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
  }
  return path;
}

/// textRunBox is where a stretch of [text] lands inside [box], laid out and
/// aligned exactly as paintTextInBox would lay it out.
///
/// For drawing something behind part of a line -- a chip round the W in
/// "--- W" -- which needs the glyphs' own boxes rather than a guess from the
/// character count, since a W and a full stop are not the same width.
///
/// Null when the range is empty or falls outside the text.
Rect? textRunBox(String text, TextSpec spec, Rect box, int start, int end) {
  var shown = spec.textCase.apply(text);
  if (start < 0 || end > shown.length || end <= start || box.width <= 0) {
    return null;
  }

  var painter = layoutText(shown, spec, maxWidth: box.width, fillWidth: true);
  var boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end));
  if (boxes.isEmpty) return null;

  // The same vertical placement paintTextInBox uses, or the chip would sit
  // where the words are not.
  var dy = switch (spec.verticalAlign) {
    VerticalAlignSpec.top => 0.0,
    VerticalAlignSpec.bottom => box.height - painter.height,
    VerticalAlignSpec.middle => (box.height - painter.height) / 2,
  };

  var out = boxes.first.toRect();
  for (var b in boxes.skip(1)) {
    out = out.expandToInclude(b.toRect());
  }
  return out.translate(box.left, box.top + dy);
}

/// textStyleOf is one TextSpec as Flutter sees it.
///
/// Its own function because a paragraph of differently styled stretches needs
/// it once per stretch -- see paintRunsInBox -- and a second copy of this
/// list would be a second place for a setting to be forgotten.
TextStyle textStyleOf(
  TextSpec spec, {
  double scale = 1,
  Color? colorOverride,
  bool outline = false,
}) =>
    TextStyle(
      fontFamily: spec.fontFamily,
      fontSize: spec.fontSize * scale,
      fontWeight: spec.fontWeight,
      fontStyle: spec.italic ? FontStyle.italic : FontStyle.normal,
      decoration:
          spec.underline ? TextDecoration.underline : TextDecoration.none,
      decorationColor: colorOverride ?? spec.color,
      letterSpacing: spec.letterSpacing * scale,
      height: spec.lineHeight,
      color: outline ? null : (colorOverride ?? spec.color),
      foreground: outline
          ? (Paint()
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = spec.outlineWidth * 2 * scale
            ..color = spec.outlineColor)
          : null,
      shadows: spec.shadowBlur > 0 && !outline
          ? [
              Shadow(
                color: spec.shadowColor,
                blurRadius: spec.shadowBlur * scale,
                offset: spec.shadowOffset * scale,
              ),
            ]
          : null,
    );

/// paintRunsInBox draws one line made of stretches of differently styled
/// text, laid out and aligned as paintTextInBox would lay out one stretch.
///
/// For a cell whose rules describe parts of it: a form guide where the dashes
/// are one size and the letters another. Painted as a single paragraph of
/// spans rather than piece by piece, because pieces painted one after another
/// have to be positioned by adding up their widths, and a line laid out that
/// way is a line that will not centre.
double paintRunsInBox(
  ui.Canvas canvas,
  List<(String, TextSpec)> runs,
  TextSpec base,
  Rect box, {
  bool clip = false,
}) {
  if (runs.isEmpty || box.width <= 0) return 0;

  var painter = TextPainter(
    text: TextSpan(
      style: textStyleOf(base),
      children: [
        for (var (text, spec) in runs)
          TextSpan(text: spec.textCase.apply(text), style: textStyleOf(spec)),
      ],
    ),
    textAlign: base.align.flutter,
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(minWidth: box.width, maxWidth: box.width);

  var dy = switch (base.verticalAlign) {
    VerticalAlignSpec.top => 0.0,
    VerticalAlignSpec.bottom => box.height - painter.height,
    VerticalAlignSpec.middle => (box.height - painter.height) / 2,
  };

  if (clip) {
    canvas.save();
    canvas.clipRect(box);
  }
  painter.paint(canvas, Offset(box.left, box.top + dy));
  if (clip) canvas.restore();
  return painter.height;
}
