import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_task_element.dart';
import 'package:flutter/painting.dart';

// synth_task_painter.dart draws a synth task card (see
// synth_task_element.dart) as the prototype's: warm paper, the task, two
// buttons -- ▶ Hear the target, Check my patch -- and its checks, each
// ticked green as the patch meets it or an amber ring while it doesn't.
//
// Laid out 300 units across (synthTaskLayout), scaled to the box's width;
// the stage's presses read the same layout.

const synthTaskWidth = 300.0;
const _pad = 14.0;
const _paper = Color(0xFFFFF8E6);
const _edge = Color(0xFFECD9A6);
const _ink = Color(0xFF3A2F12);
const _met = Color(0xFF1F7A49);
const _unmet = Color(0xFF7A5A12);

/// SynthTaskLayout is where everything on a card is, in card units.
class SynthTaskLayout {
  final TextPainter title, text;
  final Rect hear, check;
  final List<(TextPainter, Offset)> checks;
  final double height;
  const SynthTaskLayout(
      this.title, this.text, this.hear, this.check, this.checks, this.height);
}

TextPainter _lay(String t, double size, Color c,
        {FontWeight weight = FontWeight.w500, double height = 1.45}) =>
    TextPainter(
      text: TextSpan(
          text: t,
          style: TextStyle(
              fontFamily: "Inter",
              fontSize: size,
              fontWeight: weight,
              height: height,
              color: c)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: synthTaskWidth - 2 * _pad - 16);

/// synthTaskLayout lays [e] out, its checks as [doc]'s patch meets them
/// (or all unmet, with no document).
SynthTaskLayout synthTaskLayout(SynthTaskElement e, CanvasDocument? doc) {
  var y = _pad;
  var title = _lay(e.title, 14, _ink, weight: FontWeight.w800, height: 1.25);
  y += title.height + 6;
  var textY = y;
  var text = _lay(e.text, 12, _ink);
  y += text.height + 10;
  var hear = Rect.fromLTWH(_pad, y, 128, 26);
  var check = Rect.fromLTWH(hear.right + 6, y, 112, 26);
  y += 26 + 10;
  var checks = <(TextPainter, Offset)>[];
  for (var c in e.checks) {
    var ok = doc != null && c.met(doc);
    var tp = _lay(c.label, 11.5, ok ? _met : _unmet, height: 1.35);
    checks.add((tp, Offset(_pad + 16, y)));
    y += tp.height + 4;
  }
  y += _pad - 4;
  return SynthTaskLayout(
      title, text, hear, check, checks, math.max(y, textY + 40));
}

/// synthTaskScale is how big a card unit is in [box].
double synthTaskScale(Rect box) => box.width / synthTaskWidth;

/// paintSynthTask draws [e] in [box].
void paintSynthTask(
    ui.Canvas canvas, Rect box, SynthTaskElement e, CanvasDocument? doc) {
  var s = synthTaskScale(box);
  var l = synthTaskLayout(e, doc);
  canvas.save();
  canvas.translate(box.left, box.top);
  canvas.scale(s);
  var card = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, synthTaskWidth, box.height / s),
      const Radius.circular(12));
  canvas.drawRRect(
      card.shift(const Offset(0, 6)),
      Paint()
        ..color = const Color(0x1F000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
  canvas.drawRRect(card, Paint()..color = _paper);
  canvas.drawRRect(
      card,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _edge);
  canvas.clipRRect(card);
  var y = _pad;
  l.title.paint(canvas, Offset(_pad, y));
  y += l.title.height + 6;
  l.text.paint(canvas, Offset(_pad, y));
  _button(canvas, l.hear, "▶ Hear the target", e.target != null);
  _button(canvas, l.check, "Check my patch", e.checks.isNotEmpty);
  for (var (i, (tp, at)) in l.checks.indexed) {
    var ok = doc != null && e.checks[i].met(doc);
    var mark = Offset(_pad + 5, at.dy + 8);
    if (ok) {
      canvas.drawPath(
          Path()
            ..moveTo(mark.dx - 4, mark.dy)
            ..lineTo(mark.dx - 1, mark.dy + 3)
            ..lineTo(mark.dx + 4.5, mark.dy - 3.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..strokeCap = StrokeCap.round
            ..color = _met);
    } else {
      canvas.drawCircle(
          mark,
          4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = _unmet);
    }
    tp.paint(canvas, at);
  }
  canvas.restore();
}

void _button(ui.Canvas canvas, Rect r, String label, bool on) {
  var rr = RRect.fromRectAndRadius(r, const Radius.circular(7));
  canvas.drawRRect(rr,
      Paint()..color = on ? const Color(0xFFFFFFFF) : const Color(0x80FFFFFF));
  canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFE3CF96));
  var tp = TextPainter(
    text: TextSpan(
        text: label,
        style: TextStyle(
            fontFamily: "Inter",
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: on ? _ink : _ink.withValues(alpha: 0.4))),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
}

/// SynthTaskButton is a card's button.
enum SynthTaskButton { hear, check }

/// synthTaskButtonAt is the button of [e] under [point], in document
/// space.
SynthTaskButton? synthTaskButtonAt(SynthTaskElement e, Offset point) {
  var s = synthTaskScale(e.bounds);
  var q = (point - e.bounds.topLeft) / s;
  var l = synthTaskLayout(e, null);
  if (l.hear.contains(q)) return SynthTaskButton.hear;
  if (l.check.contains(q)) return SynthTaskButton.check;
  return null;
}
