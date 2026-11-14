import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/music_score.dart';
import 'package:bruig/plugin_system/canvas/model/notation.dart' show keyAlter;
import 'package:flutter/painting.dart';

// score_engraver.dart engraves a MusicScore (see model/music_score.dart) in
// Bravura, the SMuFL music font, as the Score Studio's prototype draws it:
// parts down the page, each with its staves, bars laid out in systems as
// wide as the page, everything a player reads where they look for it --
// chord symbols and strum marks above, dynamics, hairpins and lyrics below
// -- and every marking movable by the offset it keeps.
//
// It is two steps: layoutScore works out where everything goes (and what a
// press on each place means), paintScore draws it. Measures are in staff
// spaces, the gap between two lines; Bravura's em is four spaces.

/// EngraveOptions is how a score is engraved.
class EngraveOptions {
  final double width;

  /// space is a staff space, in the canvas's units.
  final double space;

  /// parts are the parts shown, by id, or null for all; staves, for a part
  /// shown, the staves of it shown (null for all).
  final Set<String>? parts;
  final Map<String, Set<int>>? staves;

  /// heading is whether the title, composer and tempo are drawn; each can
  /// be left out on its own ([titled], [subtitled], [credited], [tempoed]),
  /// and [title] is drawn in place of the score's own where it is given.
  final bool heading;
  final bool titled, subtitled, credited, tempoed;
  final String? title;

  /// names is whether each part's name is drawn at its staves' left; with
  /// none, the music starts further left.
  final bool names;

  /// marks is whether rehearsal marks are drawn (and room kept for them).
  final bool marks;

  /// bars are the bars laid out, the first and last (from nought), or null
  /// for every one.
  final (int, int)? bars;

  /// verse is the one verse of lyrics shown, or null for every verse.
  final int? verse;

  final Color paper, ink;

  const EngraveOptions(
      {this.width = 860,
      this.space = 8,
      this.parts,
      this.staves,
      this.heading = true,
      this.titled = true,
      this.subtitled = true,
      this.credited = true,
      this.tempoed = true,
      this.title,
      this.names = true,
      this.marks = true,
      this.bars,
      this.verse,
      this.paper = const Color(0xFFFBFAF6),
      this.ink = const Color(0xFF1D1C1A)});

  bool get showsTempo => heading && tempoed;

  /// left is where the systems start: room for the names, or a brace's.
  double get left => space * (names ? 9.5 : 3);

  bool showsPart(String id) => parts == null || parts!.contains(id);
  bool showsStaff(String part, int staff) =>
      staves?[part] == null || staves![part]!.contains(staff);
}

/// ScoreHitKind is what a place on an engraved score is.
enum ScoreHitKind { event, staff, mark, barline }

/// ScoreHit is a place on an engraved score: an event, the open staff of a
/// bar (where a note would go), or a marking that can be dragged.
class ScoreHit {
  final ScoreHitKind kind;
  final Rect rect;
  final String part;
  final int staff, bar;

  /// event is the event there, if any; at its time in the bar.
  final String? event;
  final double at;

  /// mark is the marking's kind (see MarkKind) for a mark.
  final String? mark;

  /// bottom and step turn a height on a staff into a staff step: [bottom]
  /// is the y of its bottom line, [step0] the step written there.
  final double bottom;
  final int step0;

  /// xs are the bar's note places: each time in the bar and its x.
  final List<(double, double)> xs;

  const ScoreHit(this.kind, this.rect, this.part, this.staff, this.bar,
      {this.event,
      this.at = 0,
      this.mark,
      this.bottom = 0,
      this.step0 = 0,
      this.xs = const []});

  /// stepAt is the staff step at height [y] on this hit's staff.
  int stepAt(double y, double space) =>
      step0 + ((bottom - y) / (space / 2)).round();

  /// timeAt is the time in the bar nearest [x], on [grid] quarters.
  double timeAt(double x, double barQuarters, {double grid = 0.25}) {
    if (xs.isEmpty) return 0;
    // Between the two places either side, in proportion.
    var t = xs.first.$1;
    for (var i = 0; i < xs.length; i++) {
      var (ta, xa) = xs[i];
      var (tb, xb) =
          i + 1 < xs.length ? xs[i + 1] : (barQuarters, rect.right - 6);
      if (x < xa) break;
      t = xb > xa ? ta + (x - xa) / (xb - xa) * (tb - ta) : ta;
    }
    t = (t / grid).round() * grid;
    return t.clamp(0.0, math.max(0.0, barQuarters - grid));
  }
}

/// _Staff is one staff shown: its part, index, clef and place in a system.
class _Staff {
  final ScorePart part;
  final int partIndex, index;
  final ScoreStaff staff;
  double top = 0;
  _Staff(this.part, this.partIndex, this.index, this.staff);
  bool get strum => part.strum;
}

/// _BarPlace is a bar laid out: its x, width and the x of each time.
class _BarPlace {
  final int bar;
  double x = 0, width = 0, lead = 0;

  /// times are the onsets in the bar, across every staff shown, and their
  /// x's (set once the system is justified).
  final List<double> times;
  final List<double> gaps;
  List<double> xs = const [];

  /// tail is room after the last note for what the bar ends with (a
  /// repeat's dots and lines); widen its BarInfo.width.
  double tail = 0, widen = 1;
  _BarPlace(this.bar, this.times, this.gaps);

  double get spread => gaps.fold(0.0, (a, b) => a + b) * widen;
  double get natural => lead + spread + tail;

  double xAt(double t) {
    if (xs.isEmpty) return x + lead;
    for (var i = 0; i < times.length; i++) {
      if ((times[i] - t).abs() < 1e-6) return xs[i];
      if (times[i] > t) {
        if (i == 0) return xs[0];
        var f = (t - times[i - 1]) / (times[i] - times[i - 1]);
        return xs[i - 1] + f * (xs[i] - xs[i - 1]);
      }
    }
    return xs.last;
  }
}

/// _Heading is where the heading's rows go, each null where it is not
/// drawn, and the y below them all.
typedef _Heading = ({
  double? title,
  double? subtitle,
  double? credits,
  double end
});

_Heading _heading(MusicScore s, EngraveOptions o) {
  var sp = o.space;
  if (!o.heading) return (title: null, subtitle: null, credits: null, end: sp);
  var y = sp * 2;
  double? title, subtitle, credits;
  var name = o.title ?? s.title;
  if (o.titled && name.isNotEmpty) {
    title = y;
    y += sp * 4;
  }
  if (o.subtitled && s.subtitle.isNotEmpty) {
    subtitle = y;
    y += sp * 2.5;
  }
  if (o.credited && (s.composer.isNotEmpty || s.lyricist.isNotEmpty)) {
    credits = y;
    y += sp * 2;
  }
  return (
    title: title,
    subtitle: subtitle,
    credits: credits,
    end: y + sp * 0.5
  );
}

/// _Rows are how far above its first staff's top line, in spaces, each row
/// of a system's markings sits: endings, rehearsal marks, the tempo.
typedef _Rows = ({double ending, double mark, double tempo});

/// _chordRow is how far above its staff's top line a chord symbol's top is:
/// over the strum marks on a strum staff.
double _chordRow(bool strum) => strum ? 5.0 : 3.2;

/// EngravedSystem is one line of bars across the page.
class EngravedSystem {
  final List<int> bars;
  final double top, bottom;
  const EngravedSystem(this.bars, this.top, this.bottom);
}

/// EngravedScore is a score laid out: its systems, its height and the
/// places a press can mean something.
class EngravedScore {
  final MusicScore score;
  final EngraveOptions options;
  final List<EngravedSystem> systems;
  final double height;
  final List<ScoreHit> hits;
  final List<_Staff> _staves;
  final List<List<_BarPlace>> _places;

  /// _staffTops are each system's staves' top lines.
  final List<Map<_Staff, double>> _staffTops;

  final List<_Rows> _rows;

  /// _placed are the events as put on the page.
  final List<_Placed> _placed = [];

  EngravedScore._(this.score, this.options, this.systems, this.height,
      this.hits, this._staves, this._places, this._staffTops, this._rows);

  /// eventAt is the event under [p], nearest first, or null.
  ScoreHit? eventAt(Offset p) {
    ScoreHit? best;
    var bestD = double.infinity;
    for (var h in hits) {
      if (h.kind != ScoreHitKind.event) continue;
      if (!h.rect.inflate(options.space * 0.6).contains(p)) continue;
      var d = (h.rect.center - p).distance;
      if (d < bestD) {
        bestD = d;
        best = h;
      }
    }
    return best;
  }

  /// markAt is the marking under [p], or null.
  ScoreHit? markAt(Offset p) => hits
      .where(
          (h) => h.kind == ScoreHitKind.mark && h.rect.inflate(2).contains(p))
      .lastOrNull;

  /// barlineAt is the bar whose closing line is under [p], or null.
  ScoreHit? barlineAt(Offset p) => hits
      .where((h) => h.kind == ScoreHitKind.barline && h.rect.contains(p))
      .firstOrNull;

  /// staffAt is the bar of a staff under [p], or null.
  ScoreHit? staffAt(Offset p) => hits
      .where((h) => h.kind == ScoreHitKind.staff && h.rect.contains(p))
      .firstOrNull;

  /// xOf is the x of [at] quarters into [bar], and the system it is on.
  (double, int)? xOf(int bar, double at) {
    for (var (si, places) in _places.indexed) {
      for (var p in places) {
        if (p.bar == bar) return (p.xAt(at), si);
      }
    }
    return null;
  }
}

// ---------------------------------------------------------------- layout

double _gapFor(double quarters, double space) =>
    space * (1.6 + 1.5 * math.log(1 + quarters * 2) / math.ln2);

/// layoutScore lays [score] out with [o].
EngravedScore layoutScore(MusicScore score, EngraveOptions o) {
  var sp = o.space;
  var staves = <_Staff>[];
  for (var (pi, p) in score.parts.indexed) {
    if (!o.showsPart(p.id)) continue;
    for (var (si, s) in p.staves.indexed) {
      if (o.showsStaff(p.id, si)) staves.add(_Staff(p, pi, si, s));
    }
  }
  var left = o.left;
  var right = o.width - sp * 1.5;

  // Each bar's onsets across the staves shown, and its natural width.
  var bars = <_BarPlace>[];
  var (firstBar, lastBar) = o.bars ?? (0, score.barCount - 1);
  firstBar = firstBar.clamp(0, math.max(0, score.barCount - 1));
  lastBar = lastBar.clamp(firstBar, math.max(0, score.barCount - 1));
  for (var b = firstBar; b <= lastBar; b++) {
    var q = score.barQuarters(b);
    var times = <double>{};
    for (var s in staves) {
      var t = <int, double>{};
      for (var e in s.staff.barAt(b)) {
        var at = t[e.voice] ?? 0;
        times.add((at * 48).round() / 48);
        t[e.voice] = at + e.quarters;
      }
    }
    if (times.isEmpty) times.add(0);
    var sorted = times.toList()..sort();
    var gaps = [
      for (var (i, t) in sorted.indexed)
        _gapFor((i + 1 < sorted.length ? sorted[i + 1] : q) - t, sp),
    ];
    var place = _BarPlace(b, sorted, gaps);
    var info = score.bars[b];
    place.lead = sp *
        (1.4 +
            (info.repeatStart ? 1.4 : 0) +
            (info.time != null ? 2.4 : 0) +
            (info.key != null ? 1.2 * (info.key!.abs() + 1) : 0));
    place.widen = info.width;
    // A closing repeat's lines and dots after the last note, not on it.
    place.tail = info.repeatEnd > 0 ? sp * 2.2 : sp * 0.3;
    // An accidental in the bar wants room before its note.
    for (var s in staves) {
      if (s.staff.barAt(b).any((e) => e.pitches.any((p) => p.alter != 0))) {
        place.lead += sp * 0.6;
        break;
      }
    }
    bars.add(place);
  }

  // Bars into systems: as many as fit, broken where a bar asks.
  var keyW = sp * (1.1 * score.fifths.abs() + (score.fifths != 0 ? 0.6 : 0));
  double startW(bool first) =>
      sp * 4.2 + keyW + (first ? sp * 3 : 0); // clef, key, (time)
  var systemsBars = <List<_BarPlace>>[];
  var current = <_BarPlace>[];
  var used = startW(true);
  for (var p in bars) {
    var w = p.natural;
    if (current.isNotEmpty && left + used + w > right) {
      systemsBars.add(current);
      current = [];
      used = startW(false);
    }
    current.add(p);
    used += w;
    if (score.bars[p.bar].breakAfter != BarBreak.none) {
      systemsBars.add(current);
      current = [];
      used = startW(false);
    }
  }
  if (current.isNotEmpty) systemsBars.add(current);

  // Justified: each bar's gaps stretched to fill the line (the last line
  // only when it is mostly full already).
  for (var (si, sys) in systemsBars.indexed) {
    var start = left + startW(si == 0);
    var natural = sys.fold(0.0, (a, p) => a + p.natural);
    var room = right - start;
    var last = si == systemsBars.length - 1;
    var stretch = last && natural < room * 0.7
        ? 1.0
        : math.max(1.0, room / math.max(1, natural));
    var x = start;
    for (var p in sys) {
      p.x = x;
      p.width = p.natural * stretch;
      var gx = x + p.lead;
      var xs = <double>[];
      var room = p.width - p.lead - p.tail;
      for (var g in p.gaps) {
        xs.add(gx + sp * 0.6);
        gx += g * p.widen * room / math.max(1, p.spread);
      }
      p.xs = xs;
      x += p.width;
    }
  }

  // Down the page: the heading, then each system's staves.
  var y = _heading(score, o).end;
  var systems = <EngravedSystem>[];
  var staffTops = <Map<_Staff, double>>[];
  var rows = <_Rows>[];
  var hits = <ScoreHit>[];
  for (var (si, sys) in systemsBars.indexed) {
    var top = y;
    var these = <_Staff, double>{};
    var r = (ending: 0.0, mark: 0.0, tempo: 0.0);
    for (var (i, s) in staves.indexed) {
      // Room above for what sits there, row on row: strum marks, chord
      // symbols, and over the first staff endings, rehearsal marks and the
      // tempo.
      var level = s.strum ? 2.8 : 1.4;
      if (_hasChords(s, sys)) level = _chordRow(s.strum) + 0.3;
      if (i == 0) {
        var ending = 0.0, mark = 0.0, tempo = 0.0;
        if (sys.any((p) => score.bars[p.bar].endings.isNotEmpty)) {
          ending = level + 1.6;
          level = ending + 0.4;
        }
        if (o.marks && sys.any((p) => score.bars[p.bar].mark.isNotEmpty)) {
          mark = level + 2.6;
          level = mark + 0.3;
        }
        if (si == 0 && o.showsTempo) {
          tempo = level + 2.4;
          level = tempo;
        }
        r = (ending: ending, mark: mark, tempo: tempo);
      }
      y += sp * (level + 1.2);
      s.top = y;
      var lyrics = _hasLyrics(s, sys) ? _verses(score, o) : 0;
      var below = sp *
          (4 +
              (lyrics > 0
                  ? 4.6 + lyrics * 2.3
                  : _hasDynamics(score, s, sys)
                      ? 4.4
                      : 2.4));
      for (var p in sys) {
        var ys = s.staff.clef.bottom;
        hits.add(ScoreHit(
            ScoreHitKind.staff,
            Rect.fromLTRB(p.x, y - sp * 3, p.x + p.width, y + sp * 7),
            s.part.id,
            s.index,
            p.bar,
            bottom: y + sp * 4,
            step0: ys,
            xs: [for (var (k, t) in p.times.indexed) (t, p.xs[k])]));
      }
      y += below;
      these[s] = s.top;
    }
    systems.add(EngravedSystem([for (var p in sys) p.bar], top, y));
    // Each bar line, a place to take hold of to widen its bar.
    if (staves.isNotEmpty) {
      var lineTop = these[staves.first]!,
          lineBottom = these[staves.last]! + sp * 4;
      for (var p in sys) {
        var end = p.x + p.width;
        hits.add(ScoreHit(
            ScoreHitKind.barline,
            Rect.fromLTRB(end - sp * 0.7, lineTop, end + sp * 0.7, lineBottom),
            "",
            0,
            p.bar));
      }
    }
    staffTops.add(these);
    rows.add(r);
    y += sp * 3;
  }
  var e = EngravedScore._(score, o, systems, y + sp * 2, hits, staves,
      systemsBars, staffTops, rows);
  // The events: their places depend on the staff tops above.
  _layoutEvents(e);
  return e;
}

bool _hasChords(_Staff st, List<_BarPlace> sys) =>
    sys.any((p) => st.staff.barAt(p.bar).any((e) => e.chord != null));

bool _hasLyrics(_Staff st, List<_BarPlace> sys) => sys.any(
    (p) => st.staff.barAt(p.bar).any((e) => e.lyrics.any((l) => l.isNotEmpty)));

bool _hasDynamics(MusicScore s, _Staff st, List<_BarPlace> sys) =>
    sys.any((p) => st.staff.barAt(p.bar).any((e) => e.dyn != null)) ||
    s.spanners.any((sn) =>
        sn.part == st.part.id &&
        sn.staff == st.index &&
        (sn.kind == SpannerKind.crescendo ||
            sn.kind == SpannerKind.diminuendo) &&
        sys.any((p) => p.bar >= sn.from.bar && p.bar <= sn.to.bar));

int _verses(MusicScore s, EngraveOptions o) => o.verse != null ? 1 : s.verses;

/// _Placed is an event put on the page: where its notes are, its stem.
class _Placed {
  final ScoreEvent e;
  final _Staff staff;
  final int bar, system;
  final double at, x;
  final List<double> ys;
  bool up = true;
  double stemX = 0, tip = 0;
  _Placed(this.e, this.staff, this.bar, this.system, this.at, this.x, this.ys);
}

/// _stepOf is [p]'s place on [clef]'s staff: nought the bottom line, each
/// step a line or a space up.
int _stepOf(Pitch p, Clef clef) => p.step - clef.bottom;

void _layoutEvents(EngravedScore es) {
  var sp = es.options.space;
  var placed = <_Placed>[];
  for (var (si, sys) in es._places.indexed) {
    var tops = es._staffTops[si];
    for (var s in es._staves) {
      var top = tops[s]!;
      var bottom = top + sp * 4;
      for (var p in sys) {
        var t = <int, double>{};
        var voices = {for (var e in s.staff.barAt(p.bar)) e.voice}.length;
        for (var e in s.staff.barAt(p.bar)) {
          var at = t[e.voice] ?? 0;
          t[e.voice] = at + e.quarters;
          var x = p.xAt(at);
          // A strum's slash on the second line: from the bottom line up to
          // the middle, where its stem starts (Ken, 2026-11-14).
          var ys = e.slash
              ? [bottom - sp]
              : e.isRest
                  ? [bottom - sp * 2]
                  : [
                      for (var q in e.pitches)
                        bottom - _stepOf(q, s.staff.clef) * sp / 2
                    ];
          var pl = _Placed(e, s, p.bar, si, at, x, ys);
          if (e.slash) {
            pl.up = true;
          } else if (voices > 1) {
            pl.up = e.voice.isEven;
          } else if (!e.isRest) {
            var mid = bottom - sp * 2;
            var avg = ys.reduce((a, b) => a + b) / ys.length;
            pl.up = avg >= mid;
          }
          var headW = sp * 1.18;
          pl.stemX = pl.up ? x + headW - sp * 0.06 : x + sp * 0.06;
          if (e.slash) {
            // Out of the slash's top end.
            pl.stemX =
                x + _glyphW(e.value >= 2 ? 0xE103 : 0xE101, sp * 4) - sp * 0.08;
            // A strum's stem stays in the staff, to the top line.
            pl.tip = top + sp * 0.1;
          } else if (!e.isRest) {
            var len = sp * 3.5;
            pl.tip =
                pl.up ? ys.reduce(math.min) - len : ys.reduce(math.max) + len;
            // Never short of the middle line, far from the staff.
            var mid = bottom - sp * 2;
            if (pl.up && pl.tip > mid) pl.tip = mid;
            if (!pl.up && pl.tip < mid) pl.tip = mid;
          }
          placed.add(pl);
          es.hits.add(ScoreHit(
              ScoreHitKind.event,
              Rect.fromLTRB(
                  x - sp * 0.3,
                  (ys.reduce(math.min) - sp * 0.7),
                  // A slash is wider than a note's head.
                  x +
                      (e.slash
                          ? _glyphW(e.value >= 2 ? 0xE103 : 0xE101, sp * 4)
                          : headW) +
                      sp * 0.3,
                  ys.reduce(math.max) + sp * 0.7),
              s.part.id,
              s.index,
              p.bar,
              event: e.id,
              at: at));
        }
      }
    }
  }
  es._placed.addAll(placed);
}

// ---------------------------------------------------------------- paint

/// ScorePaintState is what changes while a score is shown: what is
/// playing, what is picked, where the input cursor and the playhead are.
class ScorePaintState {
  final Set<String> playing;
  final Set<String> picked;

  /// marks colours events by id: right, wrong, waiting.
  final Map<String, Color> marks;
  final ({String part, int staff, int bar, double at})? cursor;
  final ({int bar, double at})? playhead;

  /// pickedMark is the marking picked (its kind, and its event's or
  /// spanner's id): outlined with its handles.
  final ({String kind, String id})? pickedMark;

  /// paper and ink, given, are drawn in place of the options' (a Sheet
  /// music element's own colours); a paper with no opacity is no paper.
  final Color? paper, ink;
  const ScorePaintState(
      {this.playing = const {},
      this.picked = const {},
      this.marks = const {},
      this.cursor,
      this.playhead,
      this.pickedMark,
      this.paper,
      this.ink});
}

const _playingColour = Color(0xFFE2622B);
const _pickedColour = Color(0xFF6B5CE7);

final _glyphs = <(int, double, int), TextPainter>{};

void _glyph(
    ui.Canvas canvas, int code, double x, double y, double size, Color colour) {
  var p = _glyphs[(code, size, colour.toARGB32())] ??= TextPainter(
    text: TextSpan(
        text: String.fromCharCode(code),
        style: TextStyle(
            fontFamily: "Bravura", fontSize: size, height: 1, color: colour)),
    textDirection: TextDirection.ltr,
  )..layout();
  var base = p.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  p.paint(canvas, Offset(x, y - base));
}

double _glyphW(int code, double size) => (TextPainter(
      text: TextSpan(
          text: String.fromCharCode(code),
          style: TextStyle(fontFamily: "Bravura", fontSize: size, height: 1)),
      textDirection: TextDirection.ltr,
    )..layout())
        .width;

TextPainter _text(String s, double size, Color colour,
        {String family = "Inter",
        FontWeight weight = FontWeight.w400,
        FontStyle style = FontStyle.normal}) =>
    TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              fontFamily: family,
              fontSize: size,
              fontWeight: weight,
              fontStyle: style,
              color: colour,
              height: 1.1)),
      textDirection: TextDirection.ltr,
    )..layout();

/// paintScore draws [es] on [canvas] at [origin].
void paintScore(ui.Canvas canvas, EngravedScore es,
    {Offset origin = Offset.zero,
    ScorePaintState state = const ScorePaintState()}) {
  canvas.save();
  canvas.translate(origin.dx, origin.dy);
  var o = es.options, sp = o.space, s = es.score;
  var ink = state.ink ?? o.ink, paper = state.paper ?? o.paper;
  canvas.drawRect(
      Rect.fromLTWH(0, 0, o.width, es.height), Paint()..color = paper);
  var line = Paint()
    ..color = ink
    ..strokeWidth = math.max(0.8, sp * 0.13);
  var stemPaint = Paint()
    ..color = ink
    ..strokeWidth = math.max(0.8, sp * 0.14);
  var em = sp * 4;

  // Marks: a marking drawn at its place plus its offset, its rect a hit.
  void markHit(String kind, Rect r, String part, int staff, int bar,
      {String? event}) {
    es.hits.removeWhere((h) =>
        h.kind == ScoreHitKind.mark &&
        h.mark == kind &&
        h.event == event &&
        h.bar == bar &&
        h.part == part);
    es.hits.add(ScoreHit(ScoreHitKind.mark, r, part, staff, bar,
        event: event, mark: kind));
  }

  Offset off(Map<String, Offset> offsets, String kind) =>
      offsets[kind] ?? Offset.zero;

  // The heading.
  var head = _heading(s, o);
  if (head.title case var y?) {
    var t = _text(o.title ?? s.title, sp * 3.2, ink, weight: FontWeight.w800);
    t.paint(canvas, Offset((o.width - t.width) / 2, y));
  }
  if (head.subtitle case var y?) {
    var st = _text(s.subtitle, sp * 1.6, ink.withValues(alpha: 0.75));
    st.paint(canvas, Offset((o.width - st.width) / 2, y));
  }
  if (head.credits case var y?) {
    if (s.composer.isNotEmpty) {
      var c = _text(s.composer, sp * 1.5, ink);
      c.paint(canvas, Offset(o.width - sp * 1.5 - c.width, y));
    }
    if (s.lyricist.isNotEmpty) {
      _text(s.lyricist, sp * 1.5, ink).paint(canvas, Offset(sp * 1.5, y));
    }
  }

  var placed = es._placed;
  for (var (si, sys) in es._places.indexed) {
    var tops = es._staffTops[si];
    if (sys.isEmpty || es._staves.isEmpty) continue;
    var first = si == 0;
    var leftX = o.left;
    var systemTop = tops[es._staves.first]!;
    var systemBottom = tops[es._staves.last]! + sp * 4;

    // The tempo, over the first system.
    if (first && o.showsTempo) {
      var at = Offset(leftX, systemTop - sp * es._rows[si].tempo) +
          off(s.offsets, MarkKind.tempo);
      var words = s.tempoText.isEmpty ? "" : "${s.tempoText}  ";
      var w = _text(words, sp * 1.6, ink, weight: FontWeight.w800);
      w.paint(canvas, at);
      _glyph(canvas, 0xE1D5, at.dx + w.width, at.dy + sp * 1.5, em * 0.5, ink);
      var n =
          _text("= ${s.tempo.round()}", sp * 1.6, ink, weight: FontWeight.w700);
      n.paint(canvas, at + Offset(w.width + sp * 1.2, 0));
      markHit(
          MarkKind.tempo,
          Rect.fromLTWH(at.dx, at.dy, w.width + sp * 1.2 + n.width, sp * 2),
          "",
          0,
          0);
    }

    // The system's line at the left, braces for a part of two staves.
    canvas.drawLine(
        Offset(leftX, systemTop), Offset(leftX, systemBottom), line);
    for (var (i, st) in es._staves.indexed) {
      var top = tops[st]!;
      for (var l = 0; l < 5; l++) {
        canvas.drawLine(Offset(leftX, top + l * sp),
            Offset(sys.last.x + sys.last.width, top + l * sp), line);
      }
      // The part's name, before its first staff.
      if (st.index == 0) {
        var count = st.part.staves.length;
        var name = first ? st.part.name : st.part.short;
        if (name.isNotEmpty && o.names) {
          var span = count > 1 ? sp * 4 * count + sp * 6 : sp * 4;
          var t = _text(name, sp * (first ? 1.4 : 1.2), ink,
              weight: FontWeight.w600);
          t.paint(
              canvas,
              Offset(leftX - sp * (count > 1 ? 2.2 : 0.8) - t.width,
                  top + span / 2 - t.height / 2));
        }
        if (count > 1 && i + count - 1 < es._staves.length) {
          var last = tops[es._staves[i + count - 1]]! + sp * 4;
          var h = last - top;
          canvas.save();
          canvas.translate(leftX - sp * 1.6, last);
          canvas.scale(1, h / em);
          _glyph(canvas, 0xE000, 0, 0, em, ink);
          canvas.restore();
        }
      }
      // Clef, key, and on the first system the time.
      var bottom = top + sp * 4;
      var x = leftX + sp * 0.8;
      var clef = st.staff.clef;
      // Each clef's origin is on the line it names: G the second line up,
      // F the fourth, C the middle (alto) or fourth (tenor).
      var (code, onLine) = switch (clef) {
        Clef.treble => (0xE050, 1),
        Clef.treble8 => (0xE052, 1),
        Clef.bass => (0xE062, 3),
        Clef.alto => (0xE05C, 2),
        Clef.tenor => (0xE05C, 3),
        Clef.percussion => (0xE069, 2),
      };
      _glyph(canvas, code, x, bottom - onLine * sp, em, ink);
      x += sp * 3.4;
      var fifths = s.keyAt(sys.first.bar);
      x = _paintKey(canvas, fifths, clef, x, bottom, sp, ink);
      if (first) {
        // As the time is where it starts: a range of bars after a change
        // opens in the time changed to.
        var (beats, unit) = s.timeAt(sys.first.bar);
        _paintTime(canvas, beats, unit, x + sp * 0.4, top, sp, ink);
      }
    }

    // Bar by bar.
    for (var (bi, p) in sys.indexed) {
      var info = s.bars[p.bar];
      var barEnd = p.x + p.width;
      // Bar lines, through each part's staves.
      void barline(double x, {bool thick = false}) {
        for (var st in es._staves) {
          var top = tops[st]!;
          canvas.drawRect(
              Rect.fromLTWH(x - (thick ? sp * 0.5 : sp * 0.07), top,
                  thick ? sp * 0.5 : sp * 0.14, sp * 4),
              Paint()..color = ink);
        }
      }

      void dots(double x) {
        for (var st in es._staves) {
          var top = tops[st]!;
          for (var d in [1.5, 2.5]) {
            canvas.drawCircle(
                Offset(x, top + d * sp), sp * 0.22, Paint()..color = ink);
          }
        }
      }

      var last = bi == sys.length - 1 && si == es._places.length - 1;
      if (info.repeatEnd > 0) {
        barline(barEnd, thick: true);
        barline(barEnd - sp * 0.9);
        dots(barEnd - sp * 1.5);
      } else if (last || info.fine) {
        barline(barEnd, thick: last);
        barline(barEnd - sp * 0.9);
      } else {
        barline(barEnd);
      }
      if (info.repeatStart) {
        var x = p.x + (bi == 0 ? sp * 0.2 : 0);
        barline(x + sp * 0.5, thick: true);
        barline(x + sp * 1.1);
        dots(x + sp * 1.7);
      }
      // A time or key change at the bar.
      for (var st in es._staves) {
        var top = tops[st]!;
        var x = p.x + sp * (info.repeatStart ? 2.4 : 0.6);
        if (info.key != null && bi > 0) {
          x = _paintKey(
              canvas, info.key!, st.staff.clef, x, top + sp * 4, sp, ink);
        }
        if (info.time case (var b, var u)) {
          _paintTime(canvas, b, u, x + sp * 0.2, top, sp, ink);
        }
      }
      // Bar number at each system's start.
      var topStaff = tops[es._staves.first]!;
      if (bi == 0 && p.bar > 0) {
        _text("${p.bar + 1}", sp * 1.1, ink.withValues(alpha: 0.6))
            .paint(canvas, Offset(p.x + sp * 0.2, topStaff - sp * 2.4));
      }
      // Endings.
      if (info.endings.isNotEmpty) {
        var y = topStaff - sp * es._rows[si].ending;
        var path = Path()
          ..moveTo(p.x + sp * 0.4, y + sp * 1.6)
          ..lineTo(p.x + sp * 0.4, y)
          ..lineTo(barEnd - sp * 0.6, y);
        if (info.repeatEnd > 0) path.lineTo(barEnd - sp * 0.6, y + sp * 1.6);
        canvas.drawPath(
            path,
            Paint()
              ..color = ink
              ..style = PaintingStyle.stroke
              ..strokeWidth = sp * 0.14);
        _text("${info.endings.join(", ")}.", sp * 1.2, ink,
                weight: FontWeight.w700)
            .paint(canvas, Offset(p.x + sp * 0.8, y + sp * 0.2));
      }
      // A rehearsal mark, above the chord symbols (and any ending).
      if (info.mark.isNotEmpty && o.marks) {
        var at = Offset(p.x - sp * 0.2, topStaff - sp * es._rows[si].mark) +
            off(info.offsets, MarkKind.rehearsal);
        var t = _text(info.mark, sp * 1.5, ink, weight: FontWeight.w800);
        var r = Rect.fromLTWH(at.dx, at.dy, t.width + sp * 1.2, sp * 2.2);
        canvas.drawRect(r, Paint()..color = paper);
        canvas.drawRect(
            r,
            Paint()
              ..color = ink
              ..style = PaintingStyle.stroke
              ..strokeWidth = sp * 0.15);
        t.paint(canvas,
            Offset(r.left + sp * 0.6, r.top + (r.height - t.height) / 2));
        markHit(MarkKind.rehearsal, r, "", 0, p.bar);
      }
      // Segno, coda, jumps.
      for (var (on, code) in [(info.segno, 0xE047), (info.coda, 0xE048)]) {
        if (on) {
          _glyph(
              canvas, code, p.x + sp * 0.4, topStaff - sp * 1.4, em * 0.6, ink);
        }
      }
      var words = [
        if (info.jump != Jump.none) info.jump.label,
        if (info.toCoda) "To Coda",
        if (info.fine) "Fine",
      ];
      if (words.isNotEmpty) {
        var t = _text(words.join("  "), sp * 1.3, ink,
            style: FontStyle.italic,
            family: "PTSerif",
            weight: FontWeight.w700);
        var at = Offset(barEnd - t.width - sp * 0.4,
                tops[es._staves.last]! + sp * 5.2) +
            off(info.offsets, MarkKind.jump);
        t.paint(canvas, at);
        markHit(MarkKind.jump, at & Size(t.width, t.height), "", 0, p.bar);
      }
    }

    // The playhead.
    if (state.playhead case var ph?) {
      for (var p in sys) {
        if (p.bar != ph.bar) continue;
        var x = p.xAt(ph.at) + sp * 0.5;
        var pp = Paint()
          ..color = _playingColour
          ..strokeWidth = sp * 0.25;
        canvas.drawLine(Offset(x, systemTop - sp * 2),
            Offset(x, systemBottom + sp * 2), pp);
        canvas.drawPath(
            Path()
              ..moveTo(x - sp * 0.8, systemTop - sp * 2.8)
              ..lineTo(x + sp * 0.8, systemTop - sp * 2.8)
              ..lineTo(x, systemTop - sp * 1.8)
              ..close(),
            Paint()..color = _playingColour);
      }
    }
  }

  // The events, staff by staff, voice by voice.
  var byStaffBar = <(String, int, int, int), List<_Placed>>{};
  for (var pl in placed) {
    (byStaffBar[(pl.staff.part.id, pl.staff.index, pl.bar, pl.e.voice)] ??= [])
        .add(pl);
  }
  for (var entry in byStaffBar.entries) {
    var list = entry.value;
    var st = list.first.staff;
    var tops = es._staffTops[list.first.system];
    var top = tops[st]!;
    var bottom = top + sp * 4;
    var fifths = s.keyAt(list.first.bar);
    // Accidentals as the bar has them so far, by step.
    var inBar = <int, int>{};
    for (var pl in list) {
      var e = pl.e;
      var colour = state.marks[e.id] ??
          (state.playing.contains(e.id)
              ? _playingColour
              : state.picked.contains(e.id)
                  ? _pickedColour
                  : ink);
      var x = pl.x;
      if (e.isRest) {
        var code = switch (e.value) {
          >= 4 => 0xE4E3,
          >= 2 => 0xE4E4,
          >= 1 => 0xE4E5,
          >= 0.5 => 0xE4E6,
          >= 0.25 => 0xE4E7,
          _ => 0xE4E8,
        };
        // A whole-bar rest sits in the bar's middle.
        var y = bottom - sp * 2 - (e.value >= 4 ? sp : 0);
        var rx = e.value >= 4 && list.length == 1
            ? (pl.x + (es.xOf(pl.bar, s.barQuarters(pl.bar))?.$1 ?? pl.x)) / 2
            : x;
        _glyph(canvas, code, rx, y, em, colour);
        _dots(canvas, e.dots, rx + sp * 1.4, bottom - sp * 2.5, sp, colour);
        continue;
      }
      var headCode = e.slash
          ? (e.value >= 2 ? 0xE103 : 0xE101)
          : e.value >= 4
              ? 0xE0A2
              : e.value >= 2
                  ? 0xE0A3
                  : 0xE0A4;
      var stepped = <int>[];
      for (var (k, pitch) in e.pitches.indexed) {
        var step = _stepOf(pitch, st.staff.clef);
        stepped.add(step);
        var y = pl.ys[k];
        // Ledger lines.
        for (var l = -2; l >= step; l -= 2) {
          canvas.drawLine(Offset(x - sp * 0.4, bottom - l * sp / 2),
              Offset(x + sp * 1.6, bottom - l * sp / 2), line);
        }
        for (var l = 10; l <= step; l += 2) {
          canvas.drawLine(Offset(x - sp * 0.4, bottom - l * sp / 2),
              Offset(x + sp * 1.6, bottom - l * sp / 2), line);
        }
        // The accidental, where the key or the bar does not already say.
        var want = pitch.alter;
        var have = inBar[pitch.step] ?? keyAlter(pitch.letter, fifths);
        if (want != have) {
          var code = switch (want) {
            2 => 0xE263,
            1 => 0xE262,
            -1 => 0xE260,
            -2 => 0xE264,
            _ => 0xE261,
          };
          _glyph(canvas, code, x - sp * 1.5, y, em, colour);
          inBar[pitch.step] = want;
        }
        // Heads a second apart sit either side of the stem.
        var shift = k > 0 && (step - stepped[k - 1]).abs() == 1 && !pl.up
            ? -sp * 1.18
            : k > 0 && (step - stepped[k - 1]).abs() == 1
                ? sp * 1.18
                : 0.0;
        _glyph(canvas, headCode, x + shift, y, em, colour);
        _dots(canvas, e.dots, x + sp * 1.6, step.isEven ? y - sp / 2 : y, sp,
            colour);
      }
      if (e.slash) {
        _glyph(canvas, headCode, x, pl.ys.first, em, colour);
        _dots(canvas, e.dots, x + sp * 1.8, pl.ys.first - sp / 2, sp, colour);
      }
      // Stem and flag (a beam is drawn with its group).
      if (e.value < 4) {
        var from = e.slash
            ? pl.ys.first - sp + sp * 0.15
            : pl.up
                ? pl.ys.reduce(math.max)
                : pl.ys.reduce(math.min);
        canvas.drawLine(
            Offset(pl.stemX, from + (pl.up ? -sp * 0.15 : sp * 0.15)),
            Offset(pl.stemX, pl.tip),
            stemPaint..color = colour);
        stemPaint.color = ink;
      }
      // Articulations, on the head's side away from the stem.
      var artUp = !pl.up || e.slash;
      var ay = artUp
          ? pl.ys.reduce(math.min) - sp * 1.2
          : pl.ys.reduce(math.max) + sp * 1.4;
      for (var a in e.articulations) {
        var code = switch (a) {
          Articulation.staccato => artUp ? 0xE4A2 : 0xE4A3,
          Articulation.staccatissimo => artUp ? 0xE4A6 : 0xE4A7,
          Articulation.tenuto => artUp ? 0xE4A4 : 0xE4A5,
          Articulation.accent => artUp ? 0xE4A0 : 0xE4A1,
          Articulation.marcato => artUp ? 0xE4AC : 0xE4AD,
          Articulation.fermata => artUp ? 0xE4C0 : 0xE4C1,
        };
        var fy = a == Articulation.fermata
            ? (artUp ? math.min(ay, top - sp) : math.max(ay, bottom + sp * 2))
            : ay;
        _glyph(canvas, code, x + sp * 0.1, fy, em, colour);
        ay += artUp ? -sp * 1.1 : sp * 1.1;
      }
      // A strum's direction, above the staff.
      if (e.slash && e.strum != null) {
        var at = Offset(x + sp * 0.1, top - sp * 1.2) +
            off(e.offsets, MarkKind.strum);
        _glyph(canvas, e.strum == Strum.down ? 0xE610 : 0xE612, at.dx, at.dy,
            em, colour);
        markHit(
            MarkKind.strum,
            Rect.fromLTWH(
                at.dx - sp * 0.2, at.dy - sp * 1.6, sp * 1.6, sp * 1.8),
            st.part.id,
            st.index,
            pl.bar,
            event: e.id);
      }
      // The chord symbol.
      if (e.chord case var c?) {
        var at = Offset(x - sp * 0.2, top - sp * _chordRow(st.strum)) +
            off(e.offsets, MarkKind.chord);
        var t = _text(c, sp * 1.6, colour, weight: FontWeight.w800);
        t.paint(canvas, at);
        markHit(MarkKind.chord, at & Size(t.width, t.height), st.part.id,
            st.index, pl.bar,
            event: e.id);
      }
      // The dynamic, below.
      if (e.dyn case var d?) {
        var at = Offset(x - sp * 0.3, bottom + sp * 3.6) +
            off(e.offsets, MarkKind.dynamic);
        var w = 0.0;
        var size = em * 0.75 * e.sizeOf(MarkKind.dynamic);
        for (var ch in d.name.split("")) {
          var code = switch (ch) {
            "p" => 0xE520,
            "m" => 0xE521,
            "f" => 0xE522,
            "s" => 0xE524,
            "z" => 0xE525,
            _ => 0xE520,
          };
          _glyph(canvas, code, at.dx + w, at.dy, size, colour);
          w += _glyphW(code, size) * 0.92;
        }
        var tall = size / (em * 0.75);
        markHit(
            MarkKind.dynamic,
            Rect.fromLTWH(at.dx, at.dy - sp * 1.6 * tall, w, sp * 2 * tall),
            st.part.id,
            st.index,
            pl.bar,
            event: e.id);
      }
      // Lyrics, below the dynamics.
      for (var (v, word) in e.lyrics.indexed) {
        if (word.isEmpty || (o.verse != null && v != o.verse)) continue;
        var row = o.verse != null ? 0 : v;
        var at = Offset(x + sp * 0.6, bottom + sp * 4.6 + row * sp * 2.3) +
            off(e.offsets, MarkKind.lyric(v));
        var t = _text(word.replaceAll(RegExp(r"-$"), ""), sp * 1.45,
            state.picked.contains(e.id) ? _pickedColour : ink,
            style: v == 1 ? FontStyle.italic : FontStyle.normal,
            weight: v == 0 ? FontWeight.w600 : FontWeight.w500);
        t.paint(canvas, Offset(at.dx - t.width / 2, at.dy));
        if (word.endsWith("-")) {
          canvas.drawLine(
              Offset(at.dx + t.width / 2 + sp * 0.6, at.dy + t.height / 2),
              Offset(at.dx + t.width / 2 + sp * 1.4, at.dy + t.height / 2),
              line);
        }
        markHit(
            MarkKind.lyric(v),
            Rect.fromLTWH(at.dx - t.width / 2, at.dy, t.width, t.height),
            st.part.id,
            st.index,
            pl.bar,
            event: e.id);
      }
    }
    _paintBeams(canvas, list, sp, ink,
        s.beatUnit == 8 && s.beats % 3 == 0 ? 1.5 : 1.0, state);
    _paintTies(canvas, list, placed, sp, ink);
    _paintTuplets(canvas, list, sp, ink);
  }

  // Slurs and hairpins.
  for (var sn in s.spanners) {
    var from = placed
        .where((p) =>
            p.staff.part.id == sn.part &&
            p.staff.index == sn.staff &&
            p.bar == sn.from.bar &&
            (p.at - sn.from.at).abs() < 1e-6)
        .firstOrNull;
    var to = placed
        .where((p) =>
            p.staff.part.id == sn.part &&
            p.staff.index == sn.staff &&
            p.bar == sn.to.bar &&
            (p.at - sn.to.at).abs() < 1e-6)
        .firstOrNull;
    var tops = es._staffTops;
    if (from == null && to == null) continue;
    var a = from ?? to!, b = to ?? from!;
    var bottomA = tops[a.system][a.staff]! + sp * 4;
    var paint = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = sp * 0.16;
    if (sn.kind == SpannerKind.slur) {
      var above = !a.up;
      double end(_Placed p) => above
          ? p.ys.reduce(math.min) - sp * 0.9
          : p.ys.reduce(math.max) + sp * 0.9;
      var x1 = a.x + sp * 0.6;
      var y1 = end(a);
      var x2 =
          b.system == a.system ? b.x + sp * 0.6 : es.options.width - sp * 2;
      var y2 = b.system == a.system ? end(b) : y1;
      var lift = above ? -sp * 1.6 : sp * 1.6;
      canvas.drawPath(
          Path()
            ..moveTo(x1, y1)
            ..cubicTo(x1 + (x2 - x1) * 0.3, y1 + lift, x1 + (x2 - x1) * 0.7,
                y2 + lift, x2, y2),
          paint);
    } else if (sn.kind == SpannerKind.crescendo ||
        sn.kind == SpannerKind.diminuendo) {
      var y = bottomA + sp * 3.0 + sn.offset.dy;
      var x1 = a.x + sn.offset.dx;
      var x2 =
          (b.system == a.system ? b.x + sp * 1.2 : es.options.width - sp * 2) +
              sn.offset.dx;
      var open = sp * 0.9;
      var cresc = sn.kind == SpannerKind.crescendo;
      canvas.drawPath(
          Path()
            ..moveTo(cresc ? x2 : x1, y - open)
            ..lineTo(cresc ? x1 : x2, y)
            ..lineTo(cresc ? x2 : x1, y + open),
          paint);
      // A place to pick it up, drag it, and stretch it by its ends.
      markHit(
          MarkKind.hairpin,
          Rect.fromLTRB(x1, y - open - sp * 0.4, x2, y + open + sp * 0.4),
          sn.part,
          sn.staff,
          a.bar,
          event: sn.id);
    }
  }

  // A marking picked: outlined, with the handles that size it (a
  // dynamic's corner) or stretch it (a hairpin's ends).
  if (state.pickedMark case var pm?) {
    var hit = es.hits
        .where((h) =>
            h.kind == ScoreHitKind.mark &&
            h.mark == pm.kind &&
            h.event == pm.id)
        .firstOrNull;
    if (hit != null) {
      var blue = Paint()
        ..color = _pickedColour
        ..style = PaintingStyle.stroke
        ..strokeWidth = sp * 0.12;
      canvas.drawRect(hit.rect.inflate(sp * 0.3), blue);
      for (var h in scoreMarkHandles(hit, sp)) {
        canvas.drawCircle(
            h, sp * 0.45, Paint()..color = const Color(0xFFFFFFFF));
        canvas.drawCircle(h, sp * 0.45, blue);
      }
    }
  }

  // The input cursor.
  if (state.cursor case var cur?) {
    var st = es._staves
        .where((x) => x.part.id == cur.part && x.index == cur.staff)
        .firstOrNull;
    var at = es.xOf(cur.bar, cur.at);
    if (st != null && at != null) {
      var top = es._staffTops[at.$2][st]!;
      var r = RRect.fromRectAndRadius(
          Rect.fromLTWH(at.$1 - sp * 0.6, top - sp * 1.2, sp * 2.6, sp * 6.4),
          Radius.circular(sp * 0.5));
      canvas.drawRRect(r, Paint()..color = const Color(0x2E5AA9FF));
      canvas.drawRRect(
          r,
          Paint()
            ..color = const Color(0xFF5AA9FF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = sp * 0.18);
    }
  }
  canvas.restore();
}

/// scoreMarkHandles are where a picked marking's handles are: a dynamic's
/// at its bottom right corner (to size it), a hairpin's at its two ends (to
/// stretch it).
List<Offset> scoreMarkHandles(ScoreHit hit, double sp) {
  var r = hit.rect.inflate(sp * 0.3);
  return switch (hit.mark) {
    MarkKind.hairpin => [r.centerLeft, r.centerRight],
    MarkKind.dynamic => [r.bottomRight],
    _ => const [],
  };
}

void _dots(ui.Canvas canvas, int n, double x, double y, double sp, Color c) {
  for (var i = 0; i < n; i++) {
    canvas.drawCircle(
        Offset(x + i * sp * 0.8, y), sp * 0.22, Paint()..color = c);
  }
}

/// _paintKey draws key signature [fifths] for [clef] from [x]; the x after.
double _paintKey(ui.Canvas canvas, int fifths, Clef clef, double x,
    double bottom, double sp, Color ink) {
  if (fifths == 0) return x;
  // Each sharp's and flat's staff step on a treble staff (F5 C5 G5 D5 A4
  // E5 B4; B4 E5 A4 D5 G4 C5 F4), moved for the other clefs.
  const sharps = [8, 5, 9, 6, 3, 7, 4];
  const flats = [4, 7, 3, 6, 2, 5, 1];
  var shift = switch (clef) {
    Clef.bass => -2,
    Clef.alto => -1,
    Clef.tenor => 1,
    _ => 0,
  };
  var list = fifths > 0 ? sharps : flats;
  for (var i = 0; i < fifths.abs(); i++) {
    var step = list[i] + shift;
    _glyph(canvas, fifths > 0 ? 0xE262 : 0xE260, x + i * sp * 1.1,
        bottom - step * sp / 2, sp * 4, ink);
  }
  return x + fifths.abs() * sp * 1.1 + sp * 0.6;
}

void _paintTime(ui.Canvas canvas, int beats, int unit, double x, double top,
    double sp, Color ink) {
  void digits(int n, double y) {
    var s = "$n";
    for (var (i, ch) in s.split("").indexed) {
      _glyph(canvas, 0xE080 + int.parse(ch), x + i * sp * 1.6, y, sp * 4, ink);
    }
  }

  digits(beats, top + sp * 1);
  digits(unit, top + sp * 3);
}

/// _paintBeams beams a voice's quavers and shorter within each beat, the
/// rest flagged.
void _paintBeams(ui.Canvas canvas, List<_Placed> voice, double sp, Color ink,
    double beat, ScorePaintState state) {
  var groups = <List<_Placed>>[];
  List<_Placed>? g;
  int? beatOf;
  for (var p in voice) {
    var short = !p.e.isRest && p.e.value < 1 && !p.e.grace;
    var b = (p.at / beat + 1e-6).floor();
    if (!short) {
      g = null;
      continue;
    }
    if (g == null || beatOf != b) {
      g = [];
      groups.add(g);
      beatOf = b;
    }
    g.add(p);
  }
  for (var grp in groups) {
    if (grp.length == 1) {
      var p = grp.single;
      var code = p.e.value <= 0.25
          ? (p.up ? 0xE242 : 0xE243)
          : (p.up ? 0xE240 : 0xE241);
      _glyph(canvas, code, p.stemX - sp * 0.07, p.tip, sp * 4, ink);
      continue;
    }
    var up = grp.first.up;
    for (var p in grp) {
      p.up = up;
    }
    // A straight beam through the group's farthest tip.
    var tip = up
        ? grp.map((p) => p.tip).reduce(math.min)
        : grp.map((p) => p.tip).reduce(math.max);
    if (grp.first.e.slash) tip = grp.first.tip;
    var thick = sp * 0.5;
    var paint = Paint()..color = ink;
    for (var p in grp) {
      // Stems to the beam.
      canvas.drawLine(
          Offset(p.stemX, p.tip),
          Offset(p.stemX, tip),
          Paint()
            ..color = ink
            ..strokeWidth = math.max(0.8, sp * 0.14));
    }
    var y = up ? tip : tip - thick;
    canvas.drawRect(
        Rect.fromLTRB(grp.first.stemX - sp * 0.07, y,
            grp.last.stemX + sp * 0.07, y + thick),
        paint);
    // Sixteenths: a second beam between them, or a stub.
    var y2 = up ? y + thick * 1.6 : y - thick * 1.6;
    for (var (i, p) in grp.indexed) {
      if (p.e.value > 0.25) continue;
      var next = i + 1 < grp.length && grp[i + 1].e.value <= 0.25;
      var prev = i > 0 && grp[i - 1].e.value <= 0.25;
      if (next) {
        canvas.drawRect(
            Rect.fromLTRB(p.stemX - sp * 0.07, y2, grp[i + 1].stemX + sp * 0.07,
                y2 + thick),
            paint);
      } else if (!prev) {
        var dir = i + 1 < grp.length ? 1 : -1;
        canvas.drawRect(
            Rect.fromLTRB(math.min(p.stemX, p.stemX + dir * sp * 1.2), y2,
                math.max(p.stemX, p.stemX + dir * sp * 1.2), y2 + thick),
            paint);
      }
    }
  }
}

/// _paintTies draws each tie from a note to the same pitch in the next
/// event of its voice (in this bar or the next).
void _paintTies(ui.Canvas canvas, List<_Placed> voice, List<_Placed> all,
    double sp, Color ink) {
  var paint = Paint()
    ..color = ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = sp * 0.15;
  for (var (i, p) in voice.indexed) {
    if (!p.e.tie || p.e.isRest) continue;
    _Placed? next = i + 1 < voice.length ? voice[i + 1] : null;
    next ??= all
        .where((q) =>
            q.staff == p.staff && q.bar == p.bar + 1 && q.e.voice == p.e.voice)
        .firstOrNull;
    for (var (k, y) in p.ys.indexed) {
      var below = !p.up;
      var x1 = p.x + sp * 1.4;
      var x2 = next != null && next.system == p.system
          ? next.x - sp * 0.2
          : x1 + sp * 3;
      var yy = y + (below ? sp * 0.8 : -sp * 0.8);
      var bend = below ? sp * 1.0 : -sp * 1.0;
      if (p.e.pitches.length > 1) bend = k == 0 ? sp : -sp;
      canvas.drawPath(
          Path()
            ..moveTo(x1, yy)
            ..quadraticBezierTo((x1 + x2) / 2, yy + bend, x2, yy),
          paint);
    }
  }
}

/// _paintTuplets brackets each run of a tuplet in a voice with its number.
void _paintTuplets(
    ui.Canvas canvas, List<_Placed> voice, double sp, Color ink) {
  var run = <_Placed>[];
  void flush() {
    if (run.isEmpty) return;
    var up = run.first.up;
    var y = up
        ? run
                .map((p) => math.min(p.tip, p.ys.reduce(math.min)))
                .reduce(math.min) -
            sp * 1.4
        : run
                .map((p) => math.max(p.tip, p.ys.reduce(math.max)))
                .reduce(math.max) +
            sp * 1.4;
    var x1 = run.first.x, x2 = run.last.x + sp * 1.2;
    var mid = (x1 + x2) / 2;
    var paint = Paint()
      ..color = ink
      ..strokeWidth = sp * 0.12
      ..style = PaintingStyle.stroke;
    var hook = up ? sp * 0.7 : -sp * 0.7;
    canvas.drawPath(
        Path()
          ..moveTo(x1, y + hook)
          ..lineTo(x1, y)
          ..lineTo(mid - sp * 0.9, y)
          ..moveTo(mid + sp * 0.9, y)
          ..lineTo(x2, y)
          ..lineTo(x2, y + hook),
        paint);
    var n = run.first.e.tuplet!.actual;
    _glyph(canvas, 0xE880 + n, mid - sp * 0.5, y + sp * 0.7, sp * 3, ink);
    run = [];
  }

  for (var p in voice) {
    if (p.e.tuplet == null) {
      flush();
      continue;
    }
    run.add(p);
    var total = run.fold(0.0, (a, q) => a + q.e.quarters);
    var span = p.e.tuplet!.normal * p.e.value;
    if (total >= span - 1e-6) flush();
  }
  flush();
}
