import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/midi_effects.dart'
    show MidiEffectKind;
import 'package:bruig/plugin_system/canvas/model/notation.dart';
import 'package:flutter/painting.dart';

// sheet_painter.dart engraves a Score -- see notation.dart -- in Bravura,
// the SMuFL music font: staves, clefs, the time, notes with their stems,
// flags, dots, sharps and ties, rests, triplets, barlines and bar numbers.
//
// A score is laid out in systems as wide as the element, bars spaced by how
// long their notes are, and shown a page of them at a time -- as many lines
// as the element asks for -- turned as it plays: when the playhead comes to
// a page's last line, the lines above it are already the next page's, so
// the reader looks ahead, as a half-page turn does.
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

/// paintSheet engraves [score] inside [bounds], [lines] systems to a page,
/// the playhead [at] quarters in -- or null for none -- with [marks] from
/// practising.
void paintSheet(ui.Canvas canvas, Rect bounds, Score score,
    {double? at,
    int lines = 2,
    SheetMarks marks = const SheetMarks(),
    SheetLook look = const SheetLook()}) {
  lines = lines.clamp(1, 8);
  canvas.save();
  canvas.clipRRect(RRect.fromRectAndRadius(bounds, const Radius.circular(6)));
  canvas.drawRect(bounds, Paint()..color = look.paper);
  var grand = score.staves.length > 1;
  var titleHeight = look.title.isEmpty ? 0.0 : bounds.height * 0.1;
  // A page of systems to the height: each 22 spaces for two staves, 13 for
  // one.
  var systemSpaces = grand ? 22.0 : 13.0;
  var space = ((bounds.height - titleHeight) / (lines * systemSpaces))
      .clamp(2.0, 18.0);
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
    t.paint(
        canvas,
        Offset(bounds.center.dx - t.width / 2,
            bounds.top + (titleHeight - t.height) / 2 + space * 0.5));
  }

  // Bars into systems: as many as fit, then stretched to the width. Each
  // line starts with its clef and key signature.
  var header = space * 5.5 + _keyWidth(score.fifths, space);
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

  // The page the playhead is on -- and, at its last line, the lines above
  // already turned to the next page's. See pageLines.
  var barAt = at == null ? 0 : (at / score.barQuarters).floor();
  var playing = 0;
  for (var (i, s) in systems.indexed) {
    if (s.bars.contains(barAt.clamp(0, score.bars.length - 1))) {
      playing = i;
      break;
    }
  }
  var shown = pageLines(playing, lines, systems.length);
  var top = bounds.top + titleHeight;
  for (var (k, index) in shown.indexed) {
    if (index == null) continue;
    var s = systems[index];
    var y = top + k * systemSpaces * space + space * 4;
    _paintSystem(canvas, score, s, index == 0, left, right, y, space,
        last: index == systems.length - 1, at: at, marks: marks, ink: look.ink);
    // Where the turned lines meet the one still being played: a faint
    // rule under the last of the next page's.
    var below = k + 1 < shown.length ? shown[k + 1] : null;
    if (below != null && below < index) {
      var ruleY = y + (systemSpaces - 4.5) * space;
      canvas.drawLine(
          Offset(left, ruleY),
          Offset(right, ruleY),
          Paint()
            ..color = look.ink.withValues(alpha: 0.25)
            ..strokeWidth = math.max(1, space * 0.15));
    }
  }
  canvas.restore();
}

/// pageLines is which system each of a page's [lines] slots shows, top to
/// bottom, the playhead on system [playing] of [count] -- null where the
/// score has ended. A page at a time; on a page's last line, the slots
/// above it already the next page's.
List<int?> pageLines(int playing, int lines, int count) {
  var first = playing ~/ lines * lines;
  var turned =
      lines > 1 && playing == first + lines - 1 && first + lines < count;
  return [
    for (var k = 0; k < lines; k++)
      switch (turned && k < lines - 1 ? first + lines + k : first + k) {
        var i when i < count => i,
        _ => null,
      },
  ];
}

/// _glyph draws Bravura's [code] with its baseline at [x], [y], [space] to
/// a staff space, in [colour].
void _glyph(
    ui.Canvas canvas, int code, double x, double y, double space, Color colour,
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
  // The last line, kept at its own spacing, ends at its final barline:
  // the staff does not run on past the end of the piece.
  var lineEnd = right;
  if (last) {
    var head = space * 0.8 +
        space * 4 +
        _keyWidth(score.fifths, space) +
        (first ? space * 3 : 0);
    var natural = system.widths.reduce((a, b) => a + b);
    lineEnd = math.min(right, left + head + natural + space * 0.9);
  }
  for (var b in bottoms.values) {
    for (var l = 0; l < 5; l++) {
      canvas.drawLine(
          Offset(left, b - l * space), Offset(lineEnd, b - l * space), line);
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
  // The key signature, on every line.
  for (var staff in score.staves) {
    _paintKey(canvas, score.fifths, staff, x, bottoms[staff]!, space, ink);
  }
  x += _keyWidth(score.fifths, space);
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
      var all = bar.staves[staff] ?? const <Written>[];
      // Each voice on its own -- its ties, its beams -- and, two in the
      // bar, the upper's stems up and the lower's down.
      var voices = <int, List<Written>>{};
      for (var w in all) {
        (voices[w.voice] ??= []).add(w);
      }
      var two = voices.length > 1;
      for (var MapEntry(key: v, value: items) in voices.entries) {
        bool? up = two ? v == 0 : null;
        var groups = beamGroups(items, score);
        var beamed = {for (var g in groups) ...g};
        for (var (i, item) in items.indexed) {
          var px = xs[item.at] ?? x;
          var nextX = i + 1 < items.length ? xs[items[i + 1].at] : x + w;
          _paintWritten(canvas, item, staff, px, bottoms[staff]!, space, ink,
              marks, nextX,
              beamed: beamed.contains(i),
              up: up,
              restShift: two ? (v == 0 ? 2 : -2) : 0);
        }
        for (var g in groups) {
          _paintBeam(
              canvas,
              [for (var i in g) (items[i], xs[items[i].at] ?? x)],
              bottoms[staff]!,
              space,
              ink,
              marks,
              up: up);
        }
        for (var g in tupletGroups(items)) {
          _paintTuplet(
              canvas,
              [for (var i in g) (items[i], xs[items[i].at] ?? x)],
              bottoms[staff]!,
              space,
              ink,
              // Beamed together, the beam is bracket enough.
              beamed: groups.any(
                  (b) => b.length == g.length && b.every((i) => g.contains(i))),
              up: up);
        }
      }
    }
    x += w;
    var end = Paint()
      ..color = ink
      ..strokeWidth = math.max(1, space * 0.16);
    canvas.drawLine(Offset(x, systemTop), Offset(x, systemBottom), end);
    if (last && k == system.bars.length - 1) {
      canvas.drawRect(
          Rect.fromLTRB(
              x + space * 0.4, systemTop, x + space * 0.9, systemBottom),
          Paint()..color = ink);
    }
    // The playhead, where it is in this bar.
    if (at case var t?
        when t >= bar.start && t < bar.start + score.barQuarters) {
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

int _signGlyph(int alter) => switch (alter) {
      1 => 0xE262, // sharp
      -1 => 0xE260, // flat
      _ => 0xE261, // natural
    };

/// _keyWidth is how much room a key signature of [fifths] takes.
double _keyWidth(int fifths, double space) =>
    fifths == 0 ? 0 : fifths.abs() * space * 1.05 + space * 0.6;

/// _paintKey draws the key signature of [fifths] on [staff] from [x]: the
/// sharps F C G D A E B, or the flats B E A D G C F, each on its own line or
/// space -- the bass clef's a third lower.
void _paintKey(ui.Canvas canvas, int fifths, Staff staff, double x,
    double bottom, double space, Color ink) {
  if (fifths == 0) return;
  // In steps up from the treble staff's bottom line.
  const sharps = [8, 5, 9, 6, 3, 7, 4];
  const flats = [4, 7, 3, 6, 2, 5, 1];
  var places = fifths > 0 ? sharps : flats;
  var shift = staff == Staff.treble ? 0 : -2;
  for (var i = 0; i < fifths.abs(); i++) {
    var step = places[i] + shift;
    _glyph(canvas, fifths > 0 ? 0xE262 : 0xE260, x + i * space * 1.05,
        bottom - step * space / 2, space, ink);
  }
}

/// beamGroups are [items]' quavers and semiquavers that share a beat --
/// a dotted crotchet in a compound time -- two or more together, by index:
/// beamed rather than each flagged.
List<List<int>> beamGroups(List<Written> items, Score score) {
  var compound = score.beatUnit == 8 && score.beatsPerBar % 3 == 0;
  var beat = compound ? 1.5 : 4 / score.beatUnit;
  var groups = <List<int>>[];
  var current = <int>[];
  int? currentBeat;
  void close() {
    if (current.length >= 2) groups.add(current);
    current = [];
    currentBeat = null;
  }

  for (var (i, item) in items.indexed) {
    var short = !item.isRest && item.base <= 0.5;
    var b = (item.at / beat + 1e-9).floor();
    if (!short || (currentBeat != null && b != currentBeat)) close();
    if (short) {
      current.add(i);
      currentBeat = b;
    }
  }
  close();
  return groups;
}

/// _paintBeam draws a beamed group: each note's stem, all one way, to a
/// beam slanted with the tune -- by no more than a space -- and kept clear
/// of every head; a second beam between semiquavers, and a short one for a
/// semiquaver beside a quaver.
void _paintBeam(ui.Canvas canvas, List<(Written, double)> group, double bottom,
    double space, Color ink, SheetMarks marks,
    {bool? up}) {
  double yOf(int step) => bottom - step * space / 2;
  var headWidth = space * 1.18;
  var stemWidth = math.max(1.0, space * 0.12);
  var notes = [
    for (var (item, x) in group)
      (
        item: item,
        x: x,
        low: item.steps.isEmpty ? 4 : item.steps.reduce(math.min),
        high: item.steps.isEmpty ? 4 : item.steps.reduce(math.max),
      ),
  ];
  var middle = notes.map((n) => (n.low + n.high) / 2).reduce((a, b) => a + b) /
      notes.length;
  var stemUp = up ?? middle < 4;
  double stemX(double x) =>
      stemUp ? x + headWidth - stemWidth / 2 : x + stemWidth / 2;
  double tipOf(int low, int high) =>
      stemUp ? yOf(high) - space * 3.5 : yOf(low) + space * 3.5;
  var first = notes.first, last = notes.last;
  var x0 = stemX(first.x), x1 = stemX(last.x);
  var y0 = tipOf(first.low, first.high), y1 = tipOf(last.low, last.high);
  var rise = (y1 - y0).clamp(-space, space);
  var slope = x1 == x0 ? 0.0 : rise / (x1 - x0);
  double beamAt(double x) => y0 + slope * (x - x0);
  // Every stem at least two and a half spaces from its head.
  var shift = 0.0;
  for (var n in notes) {
    var x = stemX(n.x);
    if (stemUp) {
      var most = yOf(n.high) - space * 2.5;
      shift = math.min(shift, most - (beamAt(x) + shift));
    } else {
      var least = yOf(n.low) + space * 2.5;
      shift = math.max(shift, least - (beamAt(x) + shift));
    }
  }
  double tip(double x) => beamAt(x) + shift;
  for (var n in notes) {
    var x = stemX(n.x);
    canvas.drawLine(
        Offset(
            x, stemUp ? yOf(n.low) - space * 0.15 : yOf(n.high) + space * 0.15),
        Offset(x, tip(x)),
        Paint()
          ..color = _colourOf(n.item, ink, marks)
          ..strokeWidth = stemWidth);
  }
  var thick = space * 0.5;
  var beam = Paint()..color = ink;
  void bar(double a, double b, int level) {
    var off = (stemUp ? 1 : -1) * level * space * 0.75;
    var t = stemUp ? thick : -thick;
    canvas.drawPath(
        Path()
          ..moveTo(a, tip(a) + off)
          ..lineTo(b, tip(b) + off)
          ..lineTo(b, tip(b) + off + t)
          ..lineTo(a, tip(a) + off + t)
          ..close(),
        beam);
  }

  bar(x0, x1, 0);
  // The semiquavers' second beam: across each pair, or a stub.
  for (var i = 0; i < notes.length; i++) {
    if (notes[i].item.base > 0.25) continue;
    var x = stemX(notes[i].x);
    var nextShort = i + 1 < notes.length && notes[i + 1].item.base <= 0.25;
    var prevShort = i > 0 && notes[i - 1].item.base <= 0.25;
    if (nextShort) {
      bar(x, stemX(notes[i + 1].x), 1);
    } else if (!prevShort) {
      // Alone: a stub toward its neighbour.
      var toward = i + 1 < notes.length ? space : -space;
      bar(math.min(x, x + toward), math.max(x, x + toward), 1);
    }
  }
}

/// _paintTuplet draws a triplet's 3 on its stems' side -- by the beam,
/// where there is one -- clear of every head and stem, with a bracket where
/// they are not one beamed group.
void _paintTuplet(ui.Canvas canvas, List<(Written, double)> group,
    double bottom, double space, Color ink,
    {required bool beamed, bool? up}) {
  double yOf(int step) => bottom - step * space / 2;
  var sounded = [
    for (var (w, _) in group)
      if (!w.isRest && w.steps.isNotEmpty) w
  ];
  // The way the group's stems go, as _paintBeam has it: by its middle.
  var centre = sounded.isEmpty
      ? 0.0
      : sounded
              .map((w) =>
                  (w.steps.reduce(math.min) + w.steps.reduce(math.max)) / 2)
              .reduce((a, b) => a + b) /
          sounded.length;
  var groupUp = up ?? centre < 4;
  var below = !groupUp;
  var headWidth = space * 1.18;
  // Clear of the staff, and of every head and stem.
  var edge = below ? yOf(0) + space * 1.5 : yOf(8) - space * 1.5;
  for (var w in sounded) {
    var low = w.steps.reduce(math.min), high = w.steps.reduce(math.max);
    var stemUp = beamed ? groupUp : up ?? (low + high) / 2 < 4;
    var reach = below
        ? (stemUp ? yOf(low) + space : yOf(low) + space * 3.5)
        : (stemUp ? yOf(high) - space * 3.5 : yOf(high) - space);
    edge = below
        ? math.max(edge, reach + space * 1.0)
        : math.min(edge, reach - space * 1.0);
  }
  var x0 = group.first.$2, x1 = group.last.$2 + headWidth;
  var middle = (x0 + x1) / 2;
  const three = 0xE883; // tuplet3
  var width = _glyphWidth(three, space);
  _glyph(canvas, three, middle - width / 2, edge + space * 0.65, space, ink);
  if (beamed) return;
  var pen = Paint()
    ..color = ink
    ..strokeWidth = math.max(1, space * 0.12)
    ..style = PaintingStyle.stroke;
  var gap = width / 2 + space * 0.4;
  var hook = below ? -space * 0.7 : space * 0.7;
  canvas.drawPath(
      Path()
        ..moveTo(x0 - space * 0.2, edge + hook)
        ..lineTo(x0 - space * 0.2, edge)
        ..lineTo(middle - gap, edge)
        ..moveTo(middle + gap, edge)
        ..lineTo(x1 + space * 0.2, edge)
        ..lineTo(x1 + space * 0.2, edge + hook),
      pen);
}

/// _glyphWidth is how wide Bravura's [code] is drawn at [space].
double _glyphWidth(int code, double space) => (TextPainter(
      text: TextSpan(
          text: String.fromCharCode(code),
          style:
              TextStyle(fontFamily: "Bravura", fontSize: space * 4, height: 1)),
      textDirection: TextDirection.ltr,
    )..layout())
        .width;

void _digits(
    ui.Canvas canvas, int n, double x, double y, double space, Color ink) {
  var dx = x;
  for (var c in "$n".codeUnits) {
    _glyph(canvas, 0xE080 + (c - 48), dx, y, space, ink);
    dx += space * 1.8;
  }
}

/// _colourOf is how a written note is coloured by practising.
Color _colourOf(Written item, Color ink, SheetMarks marks) {
  NoteMark? mark;
  for (var n in item.notes) {
    mark ??= marks.marks[n];
  }
  if (item.notes.any(marks.waiting.contains)) return _next;
  return switch (mark) {
    NoteMark.right => _right,
    NoteMark.wrong => _wrong,
    NoteMark.missed => _missed,
    null => ink,
  };
}

/// _stepsOf is where each of [item]'s keys sits on [staff].
List<int> _stepsOf(Written item, Staff staff) => item.steps.isNotEmpty
    ? item.steps
    : [for (var k in item.keys) staffStep(k, staff).$1];

void _paintWritten(ui.Canvas canvas, Written item, Staff staff, double x,
    double bottom, double space, Color ink, SheetMarks marks, double? nextX,
    {bool beamed = false, bool? up, int restShift = 0}) {
  var upGiven = up;
  double yOf(int step) => bottom - step * space / 2;
  if (item.isRest) {
    var code = switch (item.base) {
      >= 4 => 0xE4E3,
      >= 2 => 0xE4E4,
      >= 1 => 0xE4E5,
      >= 0.5 => 0xE4E6,
      _ => 0xE4E7,
    };
    // A whole rest hangs from the fourth line; the rest sit on the middle
    // -- higher for an upper voice's, lower for a lower's, with two.
    var step = (item.base >= 4 ? 6 : 4) + restShift;
    _glyph(canvas, code, x, yOf(step), space, ink.withValues(alpha: 0.85));
    return;
  }
  var colour = _colourOf(item, ink, marks);
  var head = item.base >= 4
      ? 0xE0A2
      : item.base >= 2
          ? 0xE0A3
          : 0xE0A4;
  var headWidth = space * (item.base >= 4 ? 1.69 : 1.18);
  var steps = _stepsOf(item, staff);
  var low = steps.reduce(math.min);
  var high = steps.reduce(math.max);
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
  for (var (j, step) in steps.indexed) {
    _glyph(canvas, head, x, yOf(step), space, colour);
    // Its sharp, flat or natural -- only where the key and the bar so far
    // do not already say it. See Written.accidentals.
    var sign = j < item.accidentals.length ? item.accidentals[j] : null;
    if (item.accidentals.isEmpty && isBlackKey(item.keys[j])) sign = 1;
    if (sign != null) {
      _glyph(
          canvas, _signGlyph(sign), x - space * 1.3, yOf(step), space, colour);
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
  // The stem: up from below the middle line, down from above it -- drawn
  // with its beam, where it has one. See _paintBeam.
  if (item.base < 4 && !beamed) {
    var up = upGiven ?? (low + high) / 2 < 4;
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
      var flag =
          item.base <= 0.25 ? (up ? 0xE242 : 0xE243) : (up ? 0xE240 : 0xE241);
      _glyph(canvas, flag, sx - stem.strokeWidth / 2, to, space, colour);
    }
  }
  // A tie on, to the next: an arc under the notes, or over them.
  if (item.tiedOn && nextX != null) {
    for (var step in steps) {
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

/// sheetFifths is the key [part] is written in: [chosen] where one was
/// chosen; else its Scale effect's -- the major key it shares notes with --
/// where it has one in a major or minor mode; else heard in its notes.
int sheetFifths(InstrumentPart part, int? chosen) {
  if (chosen != null) return chosen;
  var scale = part.effects
      .where((m) => m.on && m.kind == MidiEffectKind.scale)
      .firstOrNull;
  if (scale != null) {
    var root = scale.choice("root") % 12;
    // How far up the major key that shares its notes is, by mode.
    var toMajor = switch (scale.choice("scale")) {
      0 || 5 => 0, // major, major pentatonic
      1 || 2 || 6 || 7 => 3, // minor, harmonic minor, minor pentatonic, blues
      3 => 10, // dorian
      4 => 5, // mixolydian
      _ => null,
    };
    if (toMajor != null) return fifthsOfMajor((root + toMajor) % 12);
  }
  return keyFifthsOf(part.notes);
}

/// sheetScore is [part] written out in [audio]'s tempo and metre, in the
/// key of [fifths] -- remembered, since the same part is drawn on every
/// frame it plays.
Score sheetScore(InstrumentPart part, AudioSettings audio, {int? fifths}) {
  var key = sheetFifths(part, fifths);
  var metre = "${audio.tempo}|${audio.beatsPerBar}|${audio.beatUnit}|$key";
  if (_score case var s?
      when identical(_scoreFor?.$1, part.notes) && _scoreFor?.$2 == metre) {
    return s;
  }
  _scoreFor = (part.notes, metre);
  return _score = writeScore(part.notes,
      tempo: audio.tempo,
      beatsPerBar: audio.beatsPerBar,
      beatUnit: audio.beatUnit,
      fifths: key);
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
    paintSheet(
        canvas, bounds.deflate(bounds.height * 0.3), writeScore(const []),
        look: SheetLook(paper: e.paper, ink: e.ink));
    return;
  }
  var audio = document.audio;
  var score = sheetScore(part, audio, fifths: e.key);
  var rate = math.max(1, document.frameRate);
  var seconds = (frame - followed.clip.at) / rate;
  var at = seconds * audio.tempo / 60;
  var end = score.bars.length * score.barQuarters;
  paintSheet(canvas, bounds, score,
      at: at < 0 || at >= end ? null : at,
      lines: e.lines,
      marks: sheetMarksOf?.call(e) ?? const SheetMarks(),
      look: look);
}
