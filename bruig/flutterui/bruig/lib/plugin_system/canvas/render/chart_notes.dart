import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/chart_words.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/render/label_placer.dart';
import 'package:flutter/painting.dart';
import 'package:bruig/plugin_system/canvas/export/vector_canvas.dart';

// chart_notes.dart is notes bound to the data on the kinds without axes --
// a pie, a treemap, bubbles, a waffle (Ken, 2026-11-17: the improvements
// report's leftovers). Each finds its item where the chart drew it (its
// noted marks): a label as a pill on it, a callout or an arrow from words
// placed clear of the marks, a bracket as a curve between two items with
// the gap written on it. They draw on once the data has arrived, as the
// axis charts' do (chart_cartesian.dart _notes).

/// boundNotes is which of [e]'s notes the kinds without axes draw.
List<(int, ChartNote)> boundNotes(ChartElement e) => [
      for (var (k, n) in e.notes.indexed)
        if (!n.off &&
            (n.kind == ChartNoteKind.label ||
                n.kind == ChartNoteKind.callout ||
                n.kind == ChartNoteKind.arrow ||
                n.kind == ChartNoteKind.bracket))
          (k, n)
    ];

/// paintBoundNotes draws [e]'s bound notes over it in [area], each found in
/// [marks] -- where the chart drew its items -- [arrived] of the way on.
void paintBoundNotes(ui.Canvas canvas, Rect area, ChartElement e,
    List<ChartPart> marks, double arrived) {
  var notes = boundNotes(e);
  if (notes.isEmpty || arrived <= 0) return;
  var d = e.data;
  var size = math.max(9.0, e.labelSpec.fontSize * 0.85);
  Rect? markOf(String who) {
    var i = d.categories.indexOf(who);
    if (i < 0) return null;
    Rect? r;
    for (var p in marks) {
      if (p.kind != ChartPartKind.mark || p.index != i) continue;
      r = r == null ? p.rect : r.expandToInclude(p.rect);
    }
    return r;
  }

  TextPainter words(String text, Color colour) => TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w700,
              color: colour,
              fontFamily: e.labelSpec.fontFamily)),
      textDirection: TextDirection.ltr)
    ..layout();

  var placer = LabelPlacer(area, keepClear: [
    for (var p in marks)
      if (p.kind == ChartPartKind.mark)
        p.rect.deflate(p.rect.shortestSide * 0.2)
  ]);
  var line = (arrived / 0.6).clamp(0.0, 1.0);
  var shown = ((arrived - 0.4) / 0.6).clamp(0.0, 1.0);

  void pill(TextPainter tp, Rect at, Color colour) {
    if (shown <= 0) return;
    canvas.saveLayer(
        at.inflate(2), Paint()..color = Color.fromRGBO(0, 0, 0, shown));
    canvas.drawRRect(RRect.fromRectAndRadius(at, const Radius.circular(5)),
        Paint()..color = colour);
    paintTp(tp, canvas, Offset(at.left + 7, at.top + 4));
    canvas.restore();
  }

  void stroke(Path path, Color colour,
      {bool head = false, double width = 1.8}) {
    var paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..color = colour;
    for (var m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * line), paint);
      if (head && line >= 1) {
        var tip = m.getTangentForOffset(m.length);
        if (tip == null) continue;
        for (var side in [-0.45, 0.45]) {
          canvas.drawLine(
              tip.position,
              tip.position -
                  Offset(math.cos(-tip.angle + side),
                          math.sin(-tip.angle + side)) *
                      size *
                      0.7,
              paint);
        }
      }
    }
  }

  for (var (k, note) in notes) {
    var ink = note.colour.computeLuminance() > 0.45
        ? const Color(0xFF1D2127)
        : const Color(0xFFFFFFFF);
    switch (note.kind) {
      case ChartNoteKind.label:
        var r = markOf(note.who);
        if (r == null) continue;
        var tp =
            words(note.text.isEmpty ? note.who : liveWords(d, note.text), ink);
        var at = Rect.fromCenter(
            center: r.center, width: tp.width + 14, height: tp.height + 8);
        pill(tp, at, note.colour);
        notePart(ChartPartKind.note, at, index: k);
        tp.dispose();
      case ChartNoteKind.callout || ChartNoteKind.arrow:
        var r = markOf(note.who);
        if (r == null) continue;
        var to = r.center;
        var arrow = note.kind == ChartNoteKind.arrow;
        var tp =
            words(note.text.isEmpty ? note.who : liveWords(d, note.text), ink);
        var box = Size(tp.width + 14, tp.height + 8);
        var reach = r.shortestSide / 2 + size * (arrow ? 3.2 : 1.4);
        var at = placer.place(LabelPlacer.around(to, box, reach)) ??
            Rect.fromCenter(
                center: to.translate(0, -reach - box.height / 2),
                width: box.width,
                height: box.height);
        var from = Offset(
            to.dx.clamp(at.left, at.right), to.dy.clamp(at.top, at.bottom));
        var path = Path()..moveTo(from.dx, from.dy);
        if (arrow) {
          var mid = (from + to) / 2;
          var bend = Offset(-(to - from).dy, (to - from).dx) * 0.25;
          path.quadraticBezierTo(
              mid.dx + bend.dx, mid.dy + bend.dy, to.dx, to.dy);
        } else {
          path.lineTo(to.dx, to.dy);
        }
        stroke(path, note.colour, head: arrow, width: arrow ? 2.2 : 1.5);
        if (!arrow) canvas.drawCircle(to, 2.5, Paint()..color = note.colour);
        pill(tp, at, note.colour);
        notePart(ChartPartKind.note, at, index: k);
        tp.dispose();
      case ChartNoteKind.bracket:
        var a = markOf(note.who), b = markOf(note.whom);
        if (a == null || b == null) continue;
        var ia = d.categories.indexOf(note.who),
            ib = d.categories.indexOf(note.whom);
        var gap = d.valueAt(0, ib) - d.valueAt(0, ia);
        var said = note.text.isEmpty
            ? "${gap > 0 ? "+" : ""}${formatSeries(e, 0, gap)}"
            : liveWords(d, note.text);
        // A curve from one to the other, bowed away from the middle, the
        // gap on it.
        var p0 = a.center, p1 = b.center;
        var mid = (p0 + p1) / 2;
        var away = mid - area.center;
        var bow = away.distance < 1
            ? Offset(0, -size * 3)
            : away / away.distance * size * 3;
        var c = mid + bow;
        var path = Path()
          ..moveTo(p0.dx, p0.dy)
          ..quadraticBezierTo(c.dx, c.dy, p1.dx, p1.dy);
        stroke(path, note.colour);
        var tp = words(said, ink);
        var top = (p0 + p1) / 4 + c / 2;
        var at = Rect.fromCenter(
            center: top, width: tp.width + 14, height: tp.height + 8);
        pill(tp, at, note.colour);
        notePart(ChartPartKind.note, at, index: k);
        tp.dispose();
      default:
        break;
    }
  }
}
