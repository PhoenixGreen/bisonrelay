import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
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
}) {
  var painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
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
      ),
    ),
    textAlign: spec.align.flutter,
    textDirection: TextDirection.ltr,
    maxLines: null,
  );
  painter.layout(maxWidth: math.max(0, maxWidth));
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
      maxWidth: box.width, scale: scale, colorOverride: colorOverride);

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
    layoutText(text, spec, maxWidth: box.width, scale: scale, outline: true)
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
    var p = layoutText(text, spec.copyWith(fontSize: mid),
        maxWidth: box.width);
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
Path shapePath(ShapeKind kind, Rect rect, {int points = 5, double inner = 0.42, double cornerRadius = 0}) {
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
        var p = Offset(c.dx + math.cos(a) * rx * r, c.dy + math.sin(a) * ry * r);
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
      // The body keeps the bottom eighth clear for the tail, so the bubble's
      // text box and its outline agree about where the bubble stops.
      var bodyBottom = rect.bottom - rect.height * 0.16;
      var r = math.min(cornerRadius > 0 ? cornerRadius : 16.0,
          math.min(rect.width, bodyBottom - rect.top) / 2);
      path.addRRect(RRect.fromLTRBR(
          rect.left, rect.top, rect.right, bodyBottom, Radius.circular(r)));
      var tailX = rect.left + rect.width * 0.24;
      path.moveTo(tailX, bodyBottom - 1);
      path.lineTo(tailX + rect.width * 0.10, rect.bottom);
      path.lineTo(tailX + rect.width * 0.20, bodyBottom - 1);
      path.close();
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
void arrowHead(ui.Canvas canvas, Offset tip, double angle, double size,
    Paint paint) {
  var back = angle + math.pi;
  var spread = 0.42;
  var path = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(tip.dx + math.cos(back - spread) * size,
        tip.dy + math.sin(back - spread) * size)
    ..lineTo(tip.dx + math.cos(back + spread) * size,
        tip.dy + math.sin(back + spread) * size)
    ..close();
  canvas.drawPath(path, Paint()
    ..color = paint.color
    ..style = PaintingStyle.fill);
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
