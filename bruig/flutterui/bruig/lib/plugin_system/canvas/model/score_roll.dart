import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/music_score.dart';
import 'package:bruig/plugin_system/canvas/model/score_edit.dart';

// score_roll.dart is a score part in the piano roll (Ken, 2026-11-14: "would
// it be possible to also edit the score from the piano roll?"). The roll
// shows the part as written -- each bar once, in quarters, ties joined --
// and what is drawn there is written back as notation: only the bars whose
// notes changed are written again, new notes on the sixteenth grid, held
// notes tied, overlaps as a second voice, every marking kept at its beat,
// and a velocity drawn kept on the note without changing the dynamic.

/// WrittenNote is a note of a part as written: when (quarters from the
/// score's start, each bar once), on which staff, from which event.
typedef WrittenNote = ({MidiNote note, int staff, String event});

/// barStarts are each bar's start in quarters, and the end after the last.
List<double> barStarts(MusicScore s) {
  var out = <double>[0];
  for (var b = 0; b < s.barCount; b++) {
    out.add(out.last + s.barQuarters(b));
  }
  return out;
}

/// _velocityOf is how hard [e] plays with [dyn] in force, by its marks
/// alone: what a velocity drawn in the roll is told apart from.
int _velocityOf(ScoreEvent e, Dynamic dyn) {
  var v = (e.dyn != null && !e.dyn!.lasting ? e.dyn! : dyn).velocity;
  if (e.articulations.contains(Articulation.accent)) v += 18;
  if (e.articulations.contains(Articulation.marcato)) v += 26;
  return v.clamp(1, 127);
}

/// writtenNotes are [part]'s notes as written: each bar once, ties joined,
/// sounding keys (a transposing part as it sounds), velocity as marked or
/// drawn.
List<WrittenNote> writtenNotes(MusicScore s, String part) {
  var p = s.partById(part);
  if (p == null || p.strum) return const [];
  var starts = barStarts(s);
  var transpose = p.kind.transpose;
  var out = <WrittenNote>[];
  for (var (si, st) in p.staves.indexed) {
    var dyn = Dynamic.mf;
    var held = <int, Map<int, int>>{}; // voice → key → index in out
    for (var b = 0; b < s.barCount; b++) {
      var t = <int, double>{};
      for (var e in st.barAt(b)) {
        var at = t[e.voice] ?? 0;
        t[e.voice] = at + e.quarters;
        if (e.dyn case var d? when d.lasting) dyn = d;
        if (e.grace) continue;
        var was = held[e.voice] ?? const <int, int>{};
        var now = <int, int>{};
        held[e.voice] = now;
        if (e.isRest || e.slash) continue;
        var start = starts[b] + at;
        for (var pitch in e.pitches) {
          var key = (pitch.key - transpose).clamp(0, 127);
          if (was[key] case var i?) {
            var w = out[i];
            out[i] = (
              note: w.note.copyWith(length: start + e.quarters - w.note.start),
              staff: w.staff,
              event: w.event
            );
            if (e.tie) now[key] = i;
            continue;
          }
          out.add((
            note: MidiNote(
                key, start, e.quarters, e.velocity ?? _velocityOf(e, dyn)),
            staff: si,
            event: e.id
          ));
          if (e.tie) now[key] = out.length - 1;
        }
      }
    }
  }
  out.sort((a, b) => a.note.start != b.note.start
      ? a.note.start.compareTo(b.note.start)
      : a.note.key.compareTo(b.note.key));
  return out;
}

/// _Piece is a note's part in one bar: from and to (quarters into the
/// bar), whether it is tied in from the bar before and on to the next.
typedef _Piece = ({
  int key,
  double from,
  double to,
  bool tiedIn,
  bool tiedOn,
  int velocity
});

List<_Piece> _pieces(Iterable<MidiNote> notes, double bs, double be) => [
      for (var n in notes)
        if (n.start < be - 1e-6 && n.end > bs + 1e-6)
          (
            key: n.key,
            from: math.max(n.start, bs) - bs,
            to: math.min(n.end, be) - bs,
            tiedIn: n.start < bs - 1e-6,
            tiedOn: n.end > be + 1e-6,
            velocity: n.velocity
          )
    ];

String _sig(List<_Piece> ps) {
  var l = [
    for (var p in ps)
      "${p.key}@${p.from.toStringAsFixed(4)}-${p.to.toStringAsFixed(4)}"
          "${p.tiedIn ? "<" : ""}${p.tiedOn ? ">" : ""}v${p.velocity}"
  ]..sort();
  return l.join(",");
}

/// withRollNotes is [s] with [part]'s notes as [notes] say (quarters from
/// the start, as written, sounding keys): bars added at the end for notes
/// past it, and every bar whose notes changed written again.
MusicScore withRollNotes(MusicScore s, String part, List<MidiNote> notes) {
  var p = s.partById(part);
  if (p == null || p.strum) return s;
  var old = writtenNotes(s, part);
  bool same(MidiNote a, MidiNote b) =>
      a.key == b.key &&
      (a.start - b.start).abs() < 1e-6 &&
      (a.length - b.length).abs() < 1e-6;
  // New notes on the sixteenth grid; notes as they were, left as they were
  // (a triplet stays one).
  double q(double t) => (t * 4).round() / 4;
  var drawn = [
    for (var n in notes)
      if (old.any((o) => same(o.note, n)))
        n
      else
        n.copyWith(
            start: math.max(0, q(n.start)),
            length: math.max(0.25, q(n.length))),
  ];
  // Bars enough for every note.
  var end = drawn.isEmpty ? 0.0 : drawn.map((n) => n.end).reduce(math.max);
  var starts = barStarts(s);
  if (end > starts.last + 1e-6) {
    var q0 = s.barQuarters(s.barCount - 1);
    s = s.insertBars(s.barCount, ((end - starts.last) / q0).ceil());
    starts = barStarts(s);
    p = s.partById(part)!;
  }
  // Each note's staff: as it was, else by where it sits.
  var two = p.staves.length > 1;
  int staffOf(MidiNote n) {
    for (var o in old) {
      if (o.note.key == n.key && (o.note.start - n.start).abs() < 1e-6) {
        return o.staff;
      }
    }
    return two && n.key < 60 ? 1 : 0;
  }

  var newBy = <int, List<MidiNote>>{};
  for (var n in drawn) {
    (newBy[staffOf(n)] ??= []).add(n);
  }
  var oldBy = <int, List<MidiNote>>{};
  for (var o in old) {
    (oldBy[o.staff] ??= []).add(o.note);
  }
  var transpose = p.kind.transpose;
  for (var si = 0; si < p.staves.length; si++) {
    for (var b = 0; b < s.barCount; b++) {
      var bs = starts[b], be = starts[b + 1];
      var now = _pieces(newBy[si] ?? const [], bs, be);
      var was = _pieces(oldBy[si] ?? const [], bs, be);
      if (_sig(now) == _sig(was)) continue;
      s = _rewriteBar(s, part, si, b, now, transpose);
    }
  }
  return s;
}

/// _rewriteBar writes [pieces] into [part]'s [staff] [bar] as notation,
/// keeping what was marked there at its beat.
MusicScore _rewriteBar(MusicScore s, String part, int staff, int bar,
    List<_Piece> pieces, int transpose) {
  var barQ = s.barQuarters(bar);
  var fifths = s.keyAt(bar);
  var old = s.partById(part)!.staves[staff].barAt(bar);
  // The old events with their times.
  var oldAt = <(double, ScoreEvent)>[];
  var t0 = <int, double>{};
  for (var e in old) {
    var at = t0[e.voice] ?? 0;
    oldAt.add((at, e));
    t0[e.voice] = at + e.quarters;
  }
  // The dynamic in force here, for telling a drawn velocity apart.
  var dyn = Dynamic.mf;
  for (var b = 0; b < bar; b++) {
    for (var e in s.partById(part)!.staves[staff].barAt(b)) {
      if (e.dyn case var d? when d.lasting) dyn = d;
    }
  }
  // Chords: pieces starting and ending together.
  var chords = <({double from, double to, bool tiedOn, List<_Piece> keys})>[];
  for (var pc in [...pieces]..sort((a, b) => a.from.compareTo(b.from))) {
    var i = chords.indexWhere((c) =>
        (c.from - pc.from).abs() < 1e-6 &&
        (c.to - pc.to).abs() < 1e-6 &&
        c.tiedOn == pc.tiedOn);
    if (i < 0) {
      chords.add((from: pc.from, to: pc.to, tiedOn: pc.tiedOn, keys: [pc]));
    } else if (!chords[i].keys.any((k) => k.key == pc.key)) {
      // The same key twice at once is one note.
      chords[i].keys.add(pc);
    }
  }
  // Into two voices: each chord in the first free; a third overlap cuts
  // the second voice's last short.
  var voices =
      <List<({double from, double to, bool tiedOn, List<_Piece> keys})>>[
    [],
    []
  ];
  for (var c in chords) {
    var v = voices.indexWhere((l) => l.isEmpty || l.last.to <= c.from + 1e-6);
    if (v < 0) {
      v = 1;
      var last = voices[1].removeLast();
      if (c.from - last.from > 1e-6) {
        voices[1]
            .add((from: last.from, to: c.from, tiedOn: false, keys: last.keys));
      }
    }
    voices[v].add(c);
  }
  var ids = s.newIds(64);
  var idAt = 0;
  var usedOld = <String>{};
  String idFor(int voice, double at) {
    for (var (t, e) in oldAt) {
      if (e.voice == voice && (t - at).abs() < 1e-6 && usedOld.add(e.id)) {
        return e.id;
      }
    }
    return ids[idAt++];
  }

  Pitch spell(int key, double at) {
    var written = key + transpose;
    for (var (t, e) in oldAt) {
      if ((t - at).abs() > 1e-6) continue;
      for (var p in e.pitches) {
        if (p.key == written) return p;
      }
    }
    return Pitch.spelled(written, fifths: fifths);
  }

  var made = <(double, ScoreEvent)>[];
  for (var (v, list) in voices.indexed) {
    if (v == 1 && list.isEmpty) continue;
    var t = 0.0;
    void rests(double from, double to) {
      var r = from;
      for (var (val, d) in restsFor(from, to)) {
        made.add((r, ScoreEvent(idFor(v, r), val, dots: d, voice: v)));
        r += val * (2 - math.pow(0.5, d));
      }
    }

    for (var c in list) {
      if (c.from > t + 1e-6) rests(t, c.from);
      var pitches = [for (var k in c.keys) spell(k.key, c.from)]
        ..sort((a, b) => a.key.compareTo(b.key));
      var vel = c.keys.map((k) => k.velocity).reduce(math.max);
      var r = c.from;
      var parts = valuesFor(c.to - c.from);
      for (var (i, (val, d)) in parts.indexed) {
        var last = i == parts.length - 1;
        var e = ScoreEvent(idFor(v, r), val,
            dots: d, voice: v, pitches: pitches, tie: !last || c.tiedOn);
        // Drawn harder or softer than its marks play: kept on the note.
        if (i == 0 && !c.keys.first.tiedIn) {
          var marked = _velocityOf(e, dyn);
          if ((vel - marked).abs() > 2) e = e.copyWith(velocity: vel);
        }
        made.add((r, e));
        r += val * (2 - math.pow(0.5, d));
      }
      t = c.to;
    }
    if (t < barQ - 1e-6) rests(t, barQ);
  }
  // The markings, each at its beat: on the new event there; lyrics on the
  // next note in the beat, chords and dynamics on the next event in the
  // bar; else gone.
  int? at(double time, {int? voice, bool note = false, double? until}) {
    int? best;
    for (var (i, m) in made.indexed) {
      if (voice != null && m.$2.voice != voice) continue;
      if (note && m.$2.isRest) continue;
      if (m.$1 < time - 1e-6) continue;
      if (until != null && m.$1 >= until - 1e-6) continue;
      if (best == null || m.$1 < made[best].$1) best = i;
    }
    return best;
  }

  void mark(int i, ScoreEvent Function(ScoreEvent e) f) =>
      made[i] = (made[i].$1, f(made[i].$2));

  for (var (time, e) in oldAt) {
    var exact = at(time, voice: e.voice, until: time + 1e-3) ??
        at(time, until: time + 1e-3);
    if (e.lyrics.any((l) => l.isNotEmpty)) {
      var to = exact != null && !made[exact].$2.isRest
          ? exact
          : at(time, note: true, until: time.floor() + 1.0);
      if (to != null) {
        mark(
            to,
            (x) => x.copyWith(lyrics: e.lyrics, offsets: {
                  ...x.offsets,
                  for (var k in e.offsets.keys)
                    if (k.startsWith("lyr")) k: e.offsets[k]!
                }));
      }
    }
    if (e.chord != null || e.dyn != null) {
      var to = exact ?? at(time);
      if (to != null) {
        mark(
            to,
            (x) => x.copyWith(
                    chord: x.chord ?? e.chord,
                    dyn: x.dyn ?? e.dyn,
                    offsets: {
                      ...x.offsets,
                      for (var k in [MarkKind.chord, MarkKind.dynamic])
                        if (e.offsets[k] case var o?) k: o
                    }));
      }
    }
    if (e.articulations.isNotEmpty && exact != null && !made[exact].$2.isRest) {
      mark(
          exact,
          (x) => x.copyWith(
              articulations: {...x.articulations, ...e.articulations}));
    }
  }
  var events = [
    for (var v = 0; v < 4; v++)
      for (var m in made)
        if (m.$2.voice == v) m.$2
  ];
  return s.withBar(part, staff, bar, events);
}
