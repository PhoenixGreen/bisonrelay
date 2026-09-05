import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
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
typedef _LayoutKey = (String, TextSpec, double, double, Color?, bool, bool);

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
}) {
  var key = (text, spec, maxWidth, scale, colorOverride, outline, fillWidth);
  var hit = _layouts[key];
  if (hit != null) return hit;
  var painter = _layoutText(text, spec,
      maxWidth: maxWidth,
      scale: scale,
      colorOverride: colorOverride,
      outline: outline,
      fillWidth: fillWidth);
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

  var painter = TextPainter(
    text: TextSpan(
      text: text,
      style: textStyleOf(spec,
          scale: scale, colorOverride: colorOverride, outline: outline),
    ),
    textAlign: spec.align.flutter,
    textDirection: TextDirection.ltr,
    maxLines: null,
  );
  var width = math.max(0.0, maxWidth);
  painter.layout(
      minWidth: fillWidth && width.isFinite ? width : 0, maxWidth: width);
  return painter;
}

/// paintTextInBox lays [text] out inside [box] and draws it, honouring both
/// alignments and the outline.
///
/// Returns the height the text actually took, which the chart and the table
/// use to decide how much room is left for everything else.
double paintTextInBox(
  ui.Canvas canvas,
  String text,
  TextSpec spec,
  Rect box, {
  double scale = 1,
  Color? colorOverride,
  bool clip = false,
}) {
  if (text.isEmpty || box.width <= 0) return 0;

  var painter = layoutText(text, spec,
      maxWidth: box.width,
      scale: scale,
      colorOverride: colorOverride,
      fillWidth: true);

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

  if (spec.outlineWidth > 0) {
    layoutText(text, spec,
            maxWidth: box.width, scale: scale, outline: true, fillWidth: true)
        .paint(canvas, offset);
  }
  painter.paint(canvas, offset);

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
double fitFontSize(String text, TextSpec spec, Size box) {
  if (text.isEmpty || box.width <= 0 || box.height <= 0) return spec.fontSize;
  var low = 4.0, high = box.height * 2;
  for (var i = 0; i < 12; i++) {
    var mid = (low + high) / 2;
    var p = layoutText(text, spec.copyWith(fontSize: mid), maxWidth: box.width);
    if (p.height <= box.height && p.width <= box.width + 0.5) {
      low = mid;
    } else {
      high = mid;
    }
  }
  return low;
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
void paintTextInColumns(
  ui.Canvas canvas,
  String text,
  TextSpec spec,
  Rect box,
  TextColumns columns, {
  double scale = 1,
}) {
  if (text.isEmpty || box.width <= 0 || box.height <= 0) return;

  var width = columns.columnWidth(box.width);
  if (width <= 0) return;

  var painter =
      layoutText(text, spec, maxWidth: width, scale: scale, fillWidth: true);
  var metrics = painter.computeLineMetrics();
  if (metrics.isEmpty) return;

  // How many whole lines fit in a column. At least one, or a box shorter than
  // a single line would take no lines at all and draw nothing.
  var lineHeight = metrics.first.height;
  var perColumn = lineHeight <= 0
      ? metrics.length
      : math.max(1, (box.height / lineHeight).floor());

  var outline = spec.outlineWidth > 0
      ? layoutText(text, spec,
          maxWidth: width, scale: scale, outline: true, fillWidth: true)
      : null;

  for (var i = 0; i < columns.count; i++) {
    var used = perColumn * i;
    if (used >= metrics.length) break;

    var left = box.left + i * (width + columns.gap);
    var column = Rect.fromLTWH(left, box.top, width, box.height);

    // Vertical alignment applies to the column that is actually full, so a
    // short last column sits under the others rather than floating in the
    // middle of its own.
    var lines = math.min(perColumn, metrics.length - used);
    var height = lines * lineHeight;
    var dy = switch (spec.verticalAlign) {
      VerticalAlignSpec.top => 0.0,
      VerticalAlignSpec.middle => (box.height - height) / 2,
      VerticalAlignSpec.bottom => box.height - height,
    };

    canvas.save();
    canvas.clipRect(column);
    var at = Offset(left, box.top + dy - used * lineHeight);
    outline?.paint(canvas, at);
    painter.paint(canvas, at);
    canvas.restore();
  }

  _paintColumnRules(canvas, box, columns, width);
}

/// _paintColumnRules draws the line down the middle of each gutter.
void _paintColumnRules(
    ui.Canvas canvas, Rect box, TextColumns columns, double width) {
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

  for (var i = 1; i < columns.count; i++) {
    var x = box.left + i * (width + columns.gap) - columns.gap / 2;
    var line = ui.Path()
      ..moveTo(x, box.top)
      ..lineTo(x, box.bottom);
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

  const PlacedGlyph(this.glyph, this.at, this.angle, this.size);
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

  var glyphs = [for (var rune in text.runes) String.fromCharCode(rune)];
  var painters = [
    for (var g in glyphs)
      layoutText(g, spec, maxWidth: double.infinity, scale: scale),
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
    if (centre < 0 || centre > total) continue;
    var (point, angle) = _alongPolyline(curve, lengths, centre);
    out.add(PlacedGlyph(
        glyphs[i], point, angle, Size(painters[i].width, painters[i].height)));
  }
  return out;
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
void paintTextOnPath(
  ui.Canvas canvas,
  String text,
  TextSpec spec,
  List<Offset> curve,
  TextOnCurve on, {
  double scale = 1,
}) {
  for (var g in placeTextOnPath(text, spec, curve, on, scale: scale)) {
    canvas.save();
    canvas.translate(g.at.dx, g.at.dy);
    canvas.rotate(g.angle);
    // Sat on the line, or hung beneath it. The glyph is drawn from its own
    // top-left, so it is shifted by half its width and by a whole line height
    // to put the baseline where the curve is.
    var dy = on.away ? 0.0 : -g.size.height;
    if (spec.outlineWidth > 0) {
      layoutText(g.glyph, spec,
              maxWidth: double.infinity, scale: scale, outline: true)
          .paint(canvas, Offset(-g.size.width / 2, dy));
    }
    layoutText(g.glyph, spec, maxWidth: double.infinity, scale: scale)
        .paint(canvas, Offset(-g.size.width / 2, dy));
    canvas.restore();
  }
}

/// _alongPolyline is the point and heading at [distance] along [curve].
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
  return (curve.last, math.atan2(last.dy, last.dx));
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
