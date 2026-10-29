import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/notation.dart';
import 'package:flutter/painting.dart';

// sheet_painter.dart engraves a Score -- see notation.dart -- in Bravura,
// the SMuFL music font: staves, clefs, the time, notes with their stems,
// flags, dots, sharps and ties, rests, barlines and bar numbers.
//
// A score is laid out in systems as wide as the element, bars spaced by how
// long their notes are, and shown two systems at a time: the one the
// playhead is in, and the next -- turning as it plays, as a page does.
//
// Measures are in staff spaces: the gap between two lines. Bravura's em is
// four of them, a staff's height, so a glyph drawn at four spaces' size is
// the size it was drawn to be.

/// NoteMark is how a note went when it was practised.
enum NoteMark { right, wrong, missed }

/// SheetMarks is what practising has to show on a score: each note's mark,
/// the notes being waited for, and the wrong keys played at each note.
class SheetMarks {
  final Map<int, NoteMark> marks;
  final Set<int> waiting;
  final Map<int, int> wrongKeys;
  const SheetMarks(
      {this.marks = const {},
      this.waiting = const {},
      this.wrongKeys = const {}});
}

/// SheetLook is the score's colours and title.
class SheetLook {
  final Color paper, ink;
  final String title;
  const SheetLook(
      {this.paper = const Color(0xFFFBFAF6),
      this.ink = const Color(0xFF1B1B1B),
      this.title = ""});
}

const _right = Color(0xFF30A46C);
const _wrong = Color(0xFFE5484D);
const _next = Color(0xFF3D7EFF);
const _missed = Color(0xFF9AA0AA);

/// _System is one line of bars.
class _System {
  final List<int> bars;
  final List<double> widths;
  _System(this.bars, this.widths);
}

/// _xs is where each moment of a bar is across it, from its start: every
/// time any staff has something, spaced by how long until the next.
List<(double, double)> _xs(Bar bar, double space) {
  var times = <double>{};
  for (var items in bar.staves.values) {
    for (var w in items) {
      times.add(w.at);
    }
  }
  var sorted = times.toList()..sort();
  var out = <(double, double)>[];
  var x = space * 1.6;
  for (var (i, t) in sorted.indexed) {
    out.add((t, x));
    var next = i + 1 < sorted.length ? sorted[i + 1] : null;
    var dt = next == null ? 1.0 : next - t;
    x += space * (2.4 + 2.6 * math.sqrt(math.max(0.25, dt)));
  }
  return out;
}

double _barWidth(Bar bar, double space) {
  var xs = _xs(bar, space);
  if (xs.isEmpty) return space * 8;
  var last = xs.last.$2;
  return last + space * 4;
}

/// paintSheet engraves [score] inside [bounds], the playhead [at] quarters
/// in -- or null for none -- with [marks] from practising.
void paintSheet(ui.Canvas canvas, Rect bounds, Score score,
    {double? at,
    SheetMarks marks = const SheetMarks(),
    SheetLook look = const SheetLook()}) {
  canvas.save();
  canvas.clipRRect(RRect.fromRectAndRadius(bounds, const Radius.circular(6)));
  canvas.drawRect(bounds, Paint()..color = look.paper);
  var grand = score.staves.length > 1;
  var titleHeight = look.title.isEmpty ? 0.0 : bounds.height * 0.1;
  // Two systems to the height: each 22 spaces for two staves, 13 for one.
  var systemSpaces = grand ? 22.0 : 13.0;
  var space = ((bounds.height - titleHeight) / (2 * systemSpaces))
      .clamp(3.0, 18.0);
  var left = bounds.left + space * 1.5, right = bounds.right - space * 1.5;
  var width = right - left;

  if (look.title.isNotEmpty) {
    var t = TextPainter(
      text: TextSpan(
          text: look.title,
          style: TextStyle(
              fontSize: titleHeight * 0.6,
              fontWeight: FontWeight.w600,
              fontFamily: "PTSerif",
              color: look.ink)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: "…",
    )..layout(maxWidth: width);
    t.paint(canvas, Offset(bounds.center.dx - t.width / 2,
        bounds.top + (titleHeight - t.height) / 2 + space * 0.5));
  }

  // Bars into systems: as many as fit, then stretched to the width.
  var header = space * 5.5;
  var systems = <_System>[];
  var current = <int>[], widths = <double>[];
  var used = header + space * 3; // the first: its time too
  for (var (i, bar) in score.bars.indexed) {
    var w = _barWidth(bar, space);
    if (current.isNotEmpty && used + w > width) {
      systems.add(_System(current, widths));
      current = [];
      widths = [];
      used = header;
    }
    current.add(i);
    widths.add(w);
    used += w;
  }
  if (current.isNotEmpty) systems.add(_System(current, widths));

  // Which two to show: the one the playhead is in, and the next -- turned
  // a system at a time.
  var barAt = at == null ? 0 : (at / score.barQuarters).floor();
  var shownFrom = 0;
  for (var (i, s) in systems.indexed) {
    if (s.bars.contains(barAt.clamp(0, score.bars.length - 1))) {
      shownFrom = i;
      break;
    }
  }
  var top = bounds.top + titleHeight;
  for (var k = 0; k < 2 && shownFrom + k < systems.length; k++) {
    var index = shownFrom + k;
    var s = systems[index];
    var y = top + k * systemSpaces * space + space * 4;
    _paintSystem(canvas, score, s, index == 0, left, right, y, space,
        last: index == systems.length - 1, at: at, marks: marks, ink: look.ink);
  }
  canvas.restore();
}

/// _glyph draws Bravura's [code] with its baseline at [x], [y], [space] to
/// a staff space, in [colour].
void _glyph(ui.Canvas canvas, int code, double x, double y, double space,
    Color colour,
    {double scale = 1}) {
  var p = TextPainter(
    text: TextSpan(
        text: String.fromCharCode(code),
        style: TextStyle(
            fontFamily: "Bravura",
            fontSize: space * 4 * scale,
            height: 1,
            color: colour)),
    textDirection: TextDirection.ltr,
  )..layout();
  var baseline = p.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  p.paint(canvas, Offset(x, y - baseline));
}

void _paintSystem(ui.Canvas canvas, Score score, _System system, bool first,
    double left, double right, double y, double space,
    {required bool last,
    required double? at,
    required SheetMarks marks,
    required Color ink}) {
  var line = Paint()
    ..color = ink
    ..strokeWidth = math.max(1, space * 0.13);
  var thin = Paint()
    ..color = ink
    ..strokeWidth = math.max(1, space * 0.16);
  // Each staff's bottom line.
  var bottoms = <Staff, double>{};
  for (var (i, staff) in score.staves.indexed) {
    bottoms[staff] = y + 4 * space + i * 10 * space;
  }
  var systemTop = y, systemBottom = bottoms.values.reduce(math.max);
  for (var b in bottoms.values) {
    for (var l = 0; l < 5; l++) {
      canvas.drawLine(Offset(left, b - l * space), Offset(right, b - l * space),
          line);
    }
  }
  // The brace, or the line, joining the staves.
  canvas.drawLine(Offset(left, systemTop), Offset(left, systemBottom), thin);
  if (score.staves.length > 1) {
    _glyph(canvas, 0xE000, left - space * 1.3, systemBottom, space, ink,
        scale: (systemBottom - systemTop) / (4 * space));
  }
  // Clefs, and on the first system the time.
  var x = left + space * 0.8;
  for (var staff in score.staves) {
    var b = bottoms[staff]!;
    if (staff == Staff.treble) {
      _glyph(canvas, 0xE050, x, b - 1 * space, space, ink);
    } else {
      _glyph(canvas, 0xE062, x, b - 3 * space, space, ink);
    }
  }
  x += space * 4;
  if (first) {
    for (var staff in score.staves) {
      var b = bottoms[staff]!;
      _digits(canvas, score.beatsPerBar, x, b - 3 * space, space, ink);
      _digits(canvas, score.beatUnit, x, b - 1 * space, space, ink);
    }
    x += space * 3;
  }
  // Stretched to the width, but for the last, which keeps its spacing.
  var natural = system.widths.reduce((a, b) => a + b);
  var stretch = last ? 1.0 : math.max(1.0, (right - x) / natural);

  for (var (k, index) in system.bars.indexed) {
    var bar = score.bars[index];
    var w = system.widths[k] * stretch;
    var xs = {
      for (var (t, px) in _xs(bar, space)) t: x + px * stretch,
    };
    // Its number, over the first bar of the system.
    if (k == 0) {
      var n = TextPainter(
        text: TextSpan(
            text: "${bar.number}",
            style: TextStyle(
                fontSize: space * 1.2,
                fontFamily: "PTSerif",
                fontStyle: FontStyle.italic,
                color: ink.withValues(alpha: 0.6))),
        textDirection: TextDirection.ltr,
      )..layout();
      n.paint(canvas, Offset(x, systemTop - space * 2.2));
    }
    for (var staff in score.staves) {
      var items = bar.staves[staff] ?? const <Written>[];
      for (var (i, item) in items.indexed) {
        var px = xs[item.at] ?? x;
        double? nextX;
        if (i + 1 < items.length) {
          nextX = xs[items[i + 1].at];
        } else {
          nextX = x + w;
        }
        _paintWritten(canvas, item, staff, px, bottoms[staff]!, space, ink,
            marks, nextX);
      }
    }
    x += w;
    var end = Paint()
      ..color = ink
      ..strokeWidth = math.max(1, space * 0.16);
    canvas.drawLine(Offset(x, systemTop), Offset(x, systemBottom), end);
    if (last && k == system.bars.length - 1) {
      canvas.drawRect(
          Rect.fromLTRB(x + space * 0.4, systemTop, x + space * 0.9,
              systemBottom),
          Paint()..color = ink);
    }
    // The playhead, where it is in this bar.
    if (at case var t? when t >= bar.start && t < bar.start + score.barQuarters) {
      var into = t - bar.start;
      var times = xs.keys.toList()..sort();
      var px = x - w + space * 1.6;
      for (var (j, tt) in times.indexed) {
        var nx = j + 1 < times.length ? xs[times[j + 1]]! : x;
        var nt = j + 1 < times.length ? times[j + 1] : score.barQuarters;
        if (into >= tt && into < nt) {
          px = xs[tt]! + (nx - xs[tt]!) * ((into - tt) / (nt - tt));
          break;
        }
      }
      canvas.drawLine(
          Offset(px - space * 0.6, systemTop - space * 1.2),
          Offset(px - space * 0.6, systemBottom + space * 1.2),
          Paint()
            ..color = _next
            ..strokeWidth = math.max(1.5, space * 0.22));
    }
  }
}

void _digits(ui.Canvas canvas, int n, double x, double y, double space,
    Color ink) {
  var dx = x;
  for (var c in "$n".codeUnits) {
    _glyph(canvas, 0xE080 + (c - 48), dx, y, space, ink);
    dx += space * 1.8;
  }
}

void _paintWritten(ui.Canvas canvas, Written item, Staff staff, double x,
    double bottom, double space, Color ink, SheetMarks marks, double? nextX) {
  double yOf(int step) => bottom - step * space / 2;
  if (item.isRest) {
    var code = switch (item.base) {
      >= 4 => 0xE4E3,
      >= 2 => 0xE4E4,
      >= 1 => 0xE4E5,
      >= 0.5 => 0xE4E6,
      _ => 0xE4E7,
    };
    // A whole rest hangs from the fourth line; the rest sit on the middle.
    var step = item.base >= 4 ? 6 : 4;
    _glyph(canvas, code, x, yOf(step), space, ink.withValues(alpha: 0.85));
    return;
  }
  var colour = ink;
  NoteMark? mark;
  for (var n in item.notes) {
    mark ??= marks.marks[n];
  }
  if (item.notes.any(marks.waiting.contains)) {
    colour = _next;
  } else if (mark == NoteMark.right) {
    colour = _right;
  } else if (mark == NoteMark.wrong) {
    colour = _wrong;
  } else if (mark == NoteMark.missed) {
    colour = _missed;
  }
  var head = item.base >= 4
      ? 0xE0A2
      : item.base >= 2
          ? 0xE0A3
          : 0xE0A4;
  var headWidth = space * (item.base >= 4 ? 1.69 : 1.18);
  var steps = [for (var k in item.keys) staffStep(k, staff)];
  var low = steps.map((s) => s.$1).reduce(math.min);
  var high = steps.map((s) => s.$1).reduce(math.max);
  var ledger = Paint()
    ..color = ink
    ..strokeWidth = math.max(1, space * 0.16);
  for (var s = -2; s >= low; s -= 2) {
    canvas.drawLine(Offset(x - space * 0.4, yOf(s)),
        Offset(x + headWidth + space * 0.4, yOf(s)), ledger);
  }
  for (var s = 10; s <= high; s += 2) {
    canvas.drawLine(Offset(x - space * 0.4, yOf(s)),
        Offset(x + headWidth + space * 0.4, yOf(s)), ledger);
  }
  for (var (step, sharp) in steps) {
    _glyph(canvas, head, x, yOf(step), space, colour);
    if (sharp) {
      _glyph(canvas, 0xE262, x - space * 1.3, yOf(step), space, colour);
    }
    if (item.dots > 0) {
      var dotStep = step.isEven ? step + 1 : step;
      _glyph(canvas, 0xE1E7, x + headWidth + space * 0.4, yOf(dotStep), space,
          colour);
    }
  }
  // A wrong key played here, faintly, where it would be written.
  for (var n in item.notes) {
    if (marks.wrongKeys[n] case var key?) {
      var (step, _) = staffStep(key, staff);
      _glyph(canvas, 0xE0A4, x + space * 1.6, yOf(step), space,
          _wrong.withValues(alpha: 0.55));
    }
  }
  // The stem: up from below the middle line, down from above it.
  if (item.base < 4) {
    var up = (low + high) / 2 < 4;
    var stem = Paint()
      ..color = colour
      ..strokeWidth = math.max(1, space * 0.12);
    double sx, from, to;
    if (up) {
      sx = x + headWidth - stem.strokeWidth / 2;
      from = yOf(low) - space * 0.15;
      to = yOf(high) - space * 3.5;
    } else {
      sx = x + stem.strokeWidth / 2;
      from = yOf(high) + space * 0.15;
      to = yOf(low) + space * 3.5;
    }
    canvas.drawLine(Offset(sx, from), Offset(sx, to), stem);
    if (item.base <= 0.5) {
      var flag = item.base <= 0.25
          ? (up ? 0xE242 : 0xE243)
          : (up ? 0xE240 : 0xE241);
      _glyph(canvas, flag, sx - stem.strokeWidth / 2, to, space, colour);
    }
  }
  // A tie on, to the next: an arc under the notes, or over them.
  if (item.tiedOn && nextX != null) {
    for (var (step, _) in steps) {
      var y = yOf(step) + (step < 4 ? space * 0.8 : -space * 0.8);
      var a = x + headWidth, b = nextX - space * 0.2;
      var bend = step < 4 ? space * 0.9 : -space * 0.9;
      canvas.drawPath(
          Path()
            ..moveTo(a, y)
            ..quadraticBezierTo((a + b) / 2, y + bend, b, y),
          Paint()
            ..style = PaintingStyle.stroke
            ..color = colour
            ..strokeWidth = math.max(1, space * 0.14));
    }
  }
}

/// sheetMarksOf is what practising has marked on [e], where something is
/// being practised: set by the editor, as vectorSoloOf is. Null -- an
/// export, a thumbnail -- is a clean score.
SheetMarks Function(SheetElement e)? sheetMarksOf;

Score? _score;
(List<MidiNote>, String)? _scoreFor;

/// sheetScore is [part] written out in [audio]'s tempo and metre --
/// remembered, since the same part is drawn on every frame it plays.
Score sheetScore(InstrumentPart part, AudioSettings audio) {
  var metre = "${audio.tempo}|${audio.beatsPerBar}|${audio.beatUnit}";
  if (_score case var s?
      when identical(_scoreFor?.$1, part.notes) && _scoreFor?.$2 == metre) {
    return s;
  }
  _scoreFor = (part.notes, metre);
  return _score = writeScore(part.notes,
      tempo: audio.tempo,
      beatsPerBar: audio.beatsPerBar,
      beatUnit: audio.beatUnit);
}

/// paintSheetElement draws Sheet music [e] on [frame]: the part of the
/// instrument it follows, the playhead where that part has got to.
void paintSheetElement(ui.Canvas canvas, Rect bounds, SheetElement e,
    CanvasDocument? document, int frame) {
  var look = SheetLook(paper: e.paper, ink: e.ink, title: e.title);
  var followed = document?.elementById(e.follows);
  var part = followed is AudioElement ? followed.instrument : null;
  if (document == null || followed is! AudioElement || part == null) {
    canvas.drawRRect(RRect.fromRectAndRadius(bounds, const Radius.circular(6)),
        Paint()..color = e.paper);
    var t = TextPainter(
      text: TextSpan(
          text: "Sheet music: choose the instrument it shows",
          style: TextStyle(
              fontSize: math.max(10, bounds.height * 0.06),
              fontFamily: "PTSerif",
              fontStyle: FontStyle.italic,
              color: e.ink.withValues(alpha: 0.6))),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: bounds.width * 0.9);
    t.paint(canvas, bounds.center - Offset(t.width / 2, t.height / 2));
    // An empty staff under it, so it reads as what it is.
    paintSheet(canvas, bounds.deflate(bounds.height * 0.3),
        writeScore(const []), look: SheetLook(paper: e.paper, ink: e.ink));
    return;
  }
  var audio = document.audio;
  var score = sheetScore(part, audio);
  var rate = math.max(1, document.frameRate);
  var seconds = (frame - followed.clip.at) / rate;
  var at = seconds * audio.tempo / 60;
  var end = score.bars.length * score.barQuarters;
  paintSheet(canvas, bounds, score,
      at: at < 0 || at >= end ? null : at,
      marks: sheetMarksOf?.call(e) ?? const SheetMarks(),
      look: look);
}
