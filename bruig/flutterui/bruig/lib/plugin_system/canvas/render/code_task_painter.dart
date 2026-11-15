import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_task_element.dart';
import 'package:flutter/painting.dart';

// code_task_painter.dart draws a Code task card (code_task_element.dart):
// its title over a rule in its accent, what to do, a row for each check --
// ticked as the code meets it, looked at as it is typed -- its Check
// button, and once checked, whether it passed.
//
// codeTaskLayout is where everything is, in page units: the stage presses
// the button from it, and a card is sized to it.

const _ui = "Inter";
const _card = Color(0xFFFFFFFF);
const _ink = Color(0xFF1C1F24);
const _soft = Color(0xFF59606B);
const _line = Color(0xFFDDE1E6);
const _pass = Color(0xFF1E9E6A);
const _wait = Color(0xFFC98A12);
const _fail = Color(0xFFD0453A);

/// CodeTaskShow is what the stage knows of a card: whether it has been
/// checked against the code as it is now, and whether that built.
class CodeTaskShow {
  final bool checked;
  final bool? built;
  final bool checking;
  const CodeTaskShow({this.checked = false, this.built, this.checking = false});
}

/// codeTaskShowOf is how the stage shows each card, set by the controller;
/// null -- in an export -- each is unchecked.
CodeTaskShow Function(CodeTaskElement e)? codeTaskShowOf;

/// CodeTaskLayout is where a card's parts are, from its top left, in page
/// units.
class CodeTaskLayout {
  final double height;
  final Rect button;
  final List<double> rows;
  const CodeTaskLayout(this.height, this.button, this.rows);
}

TextPainter _words(String t, double size, Color c, double width,
    {FontWeight weight = FontWeight.w400, double line = 1.4}) {
  var tp = TextPainter(
      text: TextSpan(
          text: t,
          style: TextStyle(
              fontFamily: _ui,
              fontSize: size,
              fontWeight: weight,
              height: line,
              color: c)),
      textDirection: TextDirection.ltr)
    ..layout(maxWidth: math.max(1, width));
  return tp;
}

/// codeTaskLayout lays [e] out [width] wide; [banner] is the result line's
/// words, where one shows.
CodeTaskLayout codeTaskLayout(CodeTaskElement e, double width,
    {String? banner}) {
  var ts = e.textSize, pad = ts * 1.2, inner = width - pad * 2;
  var y = pad;
  var title = _words(e.title, ts * 1.3, _ink, inner, weight: FontWeight.w800);
  y += title.height + ts * 0.5 + 3 + ts * 0.7;
  title.dispose();
  if (e.text.isNotEmpty) {
    var t = _words(e.text, ts, _soft, inner);
    y += t.height + ts * 0.9;
    t.dispose();
  }
  var rows = <double>[];
  for (var c in e.checks) {
    rows.add(y);
    var t = _words(c.label, ts, _ink, inner - ts * 1.8);
    y += math.max(t.height, ts * 1.3) + ts * 0.5;
    t.dispose();
  }
  y += ts * 0.5;
  var button = Rect.fromLTWH(pad, y, math.min(inner, ts * 10), ts * 2.5);
  y = button.bottom;
  if (banner != null) {
    var t = _words(banner, ts, _ink, inner - ts * 1.6, weight: FontWeight.w600);
    y += ts * 0.9 + t.height + ts * 1.2;
    t.dispose();
  }
  return CodeTaskLayout(y + pad, button, rows);
}

/// codeTaskButtonAt is whether [point] on the page is on [e]'s button.
bool codeTaskButtonAt(CodeTaskElement e, Offset point) =>
    codeTaskLayout(e, e.width).button.shift(e.bounds.topLeft).contains(point);

/// codeTaskResult is what a checked card says, and whether it passed:
/// null while it is not checked.
(String, bool)? codeTaskResult(
    CodeTaskElement e, CanvasDocument? doc, CodeTaskShow show) {
  if (!show.checked) return null;
  var (code, run) = e.codeIn(doc);
  var met = 0;
  for (var c in e.checks) {
    var m = c.kind == CodeCheckKind.builds ? show.built : c.metBy(code, run);
    if (m == true) met++;
  }
  var all = met == e.checks.length;
  return all
      ? (e.passed, true)
      : (
          "${e.notYet} (${e.checks.length - met} of ${e.checks.length} to "
              "go)",
          false
        );
}

/// paintCodeTask draws [e] in [box].
void paintCodeTask(
    Canvas canvas, Rect box, CodeTaskElement e, CanvasDocument? doc,
    {CodeTaskShow show = const CodeTaskShow()}) {
  var ts = e.textSize, pad = ts * 1.2, inner = box.width - pad * 2;
  var result = show.checking ? null : codeTaskResult(e, doc, show);
  var l = codeTaskLayout(e, box.width, banner: result?.$1);
  var r = RRect.fromRectAndRadius(box, Radius.circular(ts * 0.9));
  canvas.drawRRect(
      r.shift(Offset(0, ts * 0.15)),
      Paint()
        ..color = const Color(0x22000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, ts * 0.5));
  canvas.drawRRect(r, Paint()..color = _card);
  canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, ts * 0.08)
        ..color = _line);
  canvas.save();
  canvas.clipRRect(r);
  canvas.translate(box.left, box.top);

  var y = pad;
  var title = _words(e.title, ts * 1.3, _ink, inner, weight: FontWeight.w800);
  title.paint(canvas, Offset(pad, y));
  y += title.height + ts * 0.5;
  canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(pad, y, math.min(inner, ts * 3.5), 3),
          const Radius.circular(1.5)),
      Paint()..color = e.accent);
  y += 3 + ts * 0.7;
  title.dispose();
  if (e.text.isNotEmpty) {
    var t = _words(e.text, ts, _soft, inner);
    t.paint(canvas, Offset(pad, y));
    t.dispose();
  }

  // The checks, each ticked as it is met.
  var (code, run) = e.codeIn(doc);
  for (var (i, c) in e.checks.indexed) {
    var top = l.rows[i];
    var met = c.kind == CodeCheckKind.builds
        ? (show.checked ? show.built : null)
        : c.metBy(code, run);
    var centre = Offset(pad + ts * 0.6, top + ts * 0.7);
    var radius = ts * 0.55;
    if (met == true) {
      canvas.drawCircle(centre, radius, Paint()..color = _pass);
      canvas.drawPath(
          Path()
            ..moveTo(centre.dx - radius * 0.45, centre.dy)
            ..lineTo(centre.dx - radius * 0.1, centre.dy + radius * 0.35)
            ..lineTo(centre.dx + radius * 0.5, centre.dy - radius * 0.35),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.5, ts * 0.12)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = _card);
    } else {
      canvas.drawCircle(
          centre,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, ts * 0.1)
            ..color = met == false && show.checked ? _fail : _line);
    }
    var t = _words(c.label, ts, met == true ? _ink : _soft, inner - ts * 1.8);
    t.paint(
        canvas,
        Offset(
            pad + ts * 1.6, top + ts * 0.7 - math.min(t.height, ts * 1.4) / 2));
    t.dispose();
  }

  // The button.
  var b = RRect.fromRectAndRadius(l.button, Radius.circular(ts * 0.6));
  canvas.drawRRect(
      b,
      Paint()
        ..color = show.checking ? e.accent.withValues(alpha: 0.5) : e.accent);
  var label = _words(show.checking ? "Checking…" : "Check my code", ts,
      const Color(0xFF0B1F18), l.button.width,
      weight: FontWeight.w700, line: 1.1);
  label.paint(
      canvas, l.button.center - Offset(label.width / 2, label.height / 2));
  label.dispose();

  // Whether it passed.
  if (result case (var words, var passed)) {
    var top = l.button.bottom + ts * 0.9;
    var t = _words(words, ts, _ink, inner - ts * 1.6, weight: FontWeight.w600);
    var banner = Rect.fromLTWH(pad, top, inner, t.height + ts * 1.2);
    var colour = passed ? _pass : _wait;
    canvas.drawRRect(RRect.fromRectAndRadius(banner, Radius.circular(ts * 0.5)),
        Paint()..color = colour.withValues(alpha: 0.12));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(banner.left, banner.top, ts * 0.25, banner.height),
            Radius.circular(ts * 0.12)),
        Paint()..color = colour);
    t.paint(canvas, Offset(pad + ts * 0.9, top + ts * 0.6));
    t.dispose();
  }
  canvas.restore();
}

/// codeTaskFitHeight is how tall [e] has to be [width] wide to show what
/// it says, whichever way its check goes.
double codeTaskFitHeight(CodeTaskElement e, double width) => math.max(
    codeTaskLayout(e, width, banner: e.passed).height,
    codeTaskLayout(e, width,
            banner: "${e.notYet} (${e.checks.length} of ${e.checks.length} "
                "to go)")
        .height);
