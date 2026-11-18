import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/vector_canvas.dart';
import 'package:bruig/plugin_system/canvas/model/elements/play_task_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart'
    show CanvasImageSource;
import 'package:flutter/painting.dart';

// play_task_painter.dart draws a play task card (play_task_element.dart):
// its box, its title, and a row for each step with its number, which turns
// into a tick once the step is done; a step the student ticks has its number
// in a box to press. Once all are done, what it says then. playTaskLayout is
// where everything is, in the card's own units: the stage presses from it,
// and a card is sized to it.

const _done = Color(0xFF1E9E6A);
const _white = Color(0xFFFFFFFF);

/// PlayTaskShow is how far the student has got: which steps are done.
class PlayTaskShow {
  final List<bool> done;
  const PlayTaskShow([this.done = const []]);

  bool doneAt(int i) => i < done.length && done[i];
  bool get any => done.any((d) => d);
}

/// playTaskShowOf is how the stage shows each card, set by the controller;
/// null in an export, where nothing is done.
PlayTaskShow Function(PlayTaskElement e)? playTaskShowOf;

/// PlayTaskLayout is where a card's parts are, from its top left.
class PlayTaskLayout {
  final double height;

  /// rows are each step's line, number and words; marks each number's.
  final List<Rect> rows, marks;

  /// again is the Start again button, or null where nothing is done yet.
  final Rect? again;

  /// banner is where the words for having done it all go, or null.
  final Rect? banner;

  const PlayTaskLayout(
      this.height, this.rows, this.marks, this.again, this.banner);
}

TextPainter _laid(String text, TextSpec spec, double width) =>
    layoutText(text, spec, maxWidth: math.max(1.0, width));

/// _againSpec is the Start again button's type: small, in the accent.
TextSpec _againSpec(PlayTaskElement e) => e.spec
    .copyWith(fontSize: e.spec.fontSize * 0.72, weight: 700, color: e.accent);

/// _titleGap is the room under the title, and _rowGap between steps: a
/// line's worth, and most of a line's leading.
double _titleGap(PlayTaskElement e) => e.spec.fontSize;
double _rowGap(PlayTaskElement e) => e.spec.fontSize * 0.6;

/// _passedSpec is the words for having done it all.
TextSpec _passedSpec(PlayTaskElement e) =>
    e.spec.copyWith(weight: 700, color: _done);

/// playTaskLayout lays [e] out [width] wide; [again] gives room to its Start
/// again button and [banner] to its last words.
PlayTaskLayout playTaskLayout(PlayTaskElement e, double width,
    {bool again = false, bool banner = false}) {
  var inner = e.box.inner(Rect.fromLTWH(0, 0, width, 1e6));
  var ts = e.spec.fontSize;
  var y = inner.top;
  var title = _laid(e.title, e.titleSpec, inner.width);
  Rect? againAt;
  if (again) {
    var a = _laid("Start again", _againSpec(e), inner.width / 2);
    // On the title's first line, at the right.
    var line = e.titleSpec.fontSize * e.titleSpec.lineHeight;
    againAt = Rect.fromLTWH(
        inner.right - a.width, y + (line - a.height) / 2, a.width, a.height);
  }
  y += title.height + _titleGap(e);
  if (e.text.isNotEmpty) {
    y += _laid(e.text, e.spec, inner.width).height + _rowGap(e);
  }

  var column = ts * 1.9;
  var line = ts * e.spec.lineHeight;
  var rows = <Rect>[], marks = <Rect>[];
  for (var c in e.checks) {
    var words = _laid(c.label, e.spec, inner.width - column);
    var h = math.max(words.height, line);
    rows.add(Rect.fromLTWH(inner.left, y, inner.width, h));
    // About a figure's middle: the number is set at the column's edge,
    // as a list's numbers are.
    var side = ts * 1.35;
    marks.add(Rect.fromCenter(
        center: Offset(inner.left + ts * 0.32, y + line / 2),
        width: side,
        height: side));
    y += h + _rowGap(e);
  }
  Rect? bannerAt;
  if (banner && e.passed.isNotEmpty) {
    y += ts * 0.2;
    var b = _laid(e.passed, _passedSpec(e), inner.width - ts * 0.9);
    bannerAt = Rect.fromLTWH(inner.left, y, inner.width, b.height);
    y += b.height + _rowGap(e);
  }
  // The last gap is the box's padding's to give, not a row's.
  y -= _rowGap(e);
  return PlayTaskLayout(y + e.box.pad.bottom, rows, marks, againAt, bannerAt);
}

/// playTaskFitHeight is how tall [e] has to be [width] wide to show what it
/// says, done or not, so it never grows as it is done.
double playTaskFitHeight(PlayTaskElement e, double width) =>
    playTaskLayout(e, width, banner: true).height;

/// playTaskRowAt is the step whose number box is at [point] (in the card's
/// units, from its top left), for a step the student ticks, or null.
int? playTaskMarkAt(PlayTaskElement e, Offset point, PlayTaskShow show) {
  var l = playTaskLayout(e, e.width, again: show.any);
  for (var (i, c) in e.checks.indexed) {
    if (c.kind != PlayCheckKind.self) continue;
    // The whole line answers: a number is a small thing to hit.
    if (l.rows[i].contains(point) || l.marks[i].inflate(4).contains(point)) {
      return i;
    }
  }
  return null;
}

/// playTaskAgainAt is whether [point] is on the Start again button.
bool playTaskAgainAt(PlayTaskElement e, Offset point, PlayTaskShow show) =>
    show.any &&
    (playTaskLayout(e, e.width, again: true)
            .again
            ?.inflate(6)
            .contains(point) ??
        false);

void paintPlayTask(ui.Canvas canvas, Rect box, PlayTaskElement e,
    {PlayTaskShow show = const PlayTaskShow(), CanvasImageSource? images}) {
  var all = e.checks.isNotEmpty &&
      [for (var i = 0; i < e.checks.length; i++) show.doneAt(i)]
          .every((d) => d);
  var l = playTaskLayout(e, box.width, again: show.any, banner: all);
  paintBox(canvas, box, e.box, images);
  var inner = e.box.inner(Rect.fromLTWH(0, 0, box.width, box.height));
  canvas.save();
  canvas.translate(box.left, box.top);

  var title = _laid(e.title, e.titleSpec, inner.width);
  paintTp(title, canvas, inner.topLeft);
  if (l.again case var a?) {
    paintTp(_laid("Start again", _againSpec(e), inner.width / 2), canvas,
        a.topLeft);
  }
  if (e.text.isNotEmpty) {
    var t = _laid(e.text, e.spec, inner.width);
    paintTp(
        t, canvas, Offset(inner.left, inner.top + title.height + _titleGap(e)));
  }

  var ts = e.spec.fontSize;
  var column = ts * 1.9;
  for (var (i, c) in e.checks.indexed) {
    var row = l.rows[i], mark = l.marks[i];
    var done = show.doneAt(i);
    if (done) {
      // A tick in a filled circle, where the number was.
      var r = mark.width / 2 * 0.95;
      var centre = mark.center;
      canvas.drawCircle(centre, r, Paint()..color = e.accent);
      canvas.drawPath(
          Path()
            ..moveTo(centre.dx - r * 0.45, centre.dy + r * 0.02)
            ..lineTo(centre.dx - r * 0.1, centre.dy + r * 0.36)
            ..lineTo(centre.dx + r * 0.48, centre.dy - r * 0.34),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.5, ts * 0.13)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = _white);
    } else {
      var number = _laid("${i + 1}",
          e.spec.copyWith(weight: 800, color: e.accent, lineHeight: 1), ts * 3);
      if (c.kind == PlayCheckKind.self) {
        // A box to tick: its number in it.
        canvas.drawRRect(
            RRect.fromRectAndRadius(mark, Radius.circular(ts * 0.25)),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(1, ts * 0.09)
              ..color = e.accent);
      }
      paintTp(number, canvas,
          mark.center - Offset(number.width / 2, number.height / 2));
    }
    paintTp(_laid(c.label, e.spec, inner.width - column), canvas,
        Offset(row.left + column, row.top));
  }

  if (l.banner case var b?) {
    var words = _laid(e.passed, _passedSpec(e), inner.width - ts * 0.9);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(b.left, b.top, ts * 0.22, b.height),
            Radius.circular(ts * 0.11)),
        Paint()..color = _done);
    paintTp(words, canvas, Offset(b.left + ts * 0.9, b.top));
  }
  canvas.restore();
}
