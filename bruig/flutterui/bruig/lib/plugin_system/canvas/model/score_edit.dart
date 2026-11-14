import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:bruig/plugin_system/canvas/model/music_score.dart';
import 'package:bruig/plugin_system/canvas/model/notation.dart' show keyAlter;

// score_edit.dart is every change the Score Studio makes to a score, each a
// score in, a score out: notes entered as MuseScore's note input enters
// them (writing over what was there), notes deleted, lengthened, moved up
// and down, marked, and the bars and parts themselves added and taken out.

/// nextEvent is the event after [id] in its part's staff and voice, over
/// the bar lines: the next note only, for [notes] (a lyric's next home), or
/// the next of anything. Null at the end.
String? nextEvent(MusicScore s, String id, {bool notes = true}) {
  var at = s.find(id);
  var e0 = s.event(id);
  if (at == null || e0 == null) return null;
  var st = s.partById(at.part)!.staves[at.staff];
  var found = false;
  for (var b = at.bar; b < st.bars.length; b++) {
    for (var e in st.bars[b]) {
      if (e.voice != e0.voice) continue;
      if (found && !(notes && (e.isRest || e.grace))) return e.id;
      if (e.id == id) found = true;
    }
  }
  return null;
}

/// ScoreCursor is where note input writes next: a part's staff, a bar, a
/// time in it, and a voice.
typedef ScoreCursor = ({String part, int staff, int bar, double at, int voice});

/// EventPlace is where an event is: its part, staff, bar and index there.
typedef EventPlace = ({String part, int staff, int bar, int index});

/// _values are the written values, longest first, with their dots: what a
/// length is broken into to be written.
const _values = <(double, int)>[
  (4, 0),
  (2, 1),
  (2, 0),
  (1, 1),
  (1, 0),
  (0.5, 1),
  (0.5, 0),
  (0.25, 1),
  (0.25, 0),
  (0.125, 0),
];

double _q(double value, int dots) => value * (2 - math.pow(0.5, dots));

/// valuesFor is [length] quarters as written values, longest first.
List<(double, int)> valuesFor(double length) {
  var out = <(double, int)>[];
  var left = length;
  for (var (v, d) in _values) {
    while (left >= _q(v, d) - 1e-6) {
      out.add((v, d));
      left -= _q(v, d);
    }
  }
  return out;
}

/// restsFor are the rests from [start] to [end] quarters into a bar, as a
/// player reads them: each starting where its value falls on the beat (a
/// minim on beat one or three of 4/4, never across the middle), longest
/// first. In a compound time ([compound]), dotted rests by the beat.
List<(double, int)> restsFor(double start, double end,
    {bool compound = false}) {
  var out = <(double, int)>[];
  var t = start;
  const plain = [(4.0, 0), (2.0, 0), (1.0, 0), (0.5, 0), (0.25, 0), (0.125, 0)];
  const dotted = [(2.0, 1), (1.0, 1), (0.5, 1)];
  var choices = compound ? [...dotted, ...plain] : plain;
  for (var guard = 0; t < end - 1e-6 && guard < 64; guard++) {
    (double, int)? pick;
    for (var (v, d) in choices) {
      var q = _q(v, d);
      var onBeat = ((t / q) - (t / q).roundToDouble()).abs() < 1e-6;
      if (onBeat && t + q <= end + 1e-6) {
        pick = (v, d);
        break;
      }
    }
    pick ??= valuesFor(end - t).first;
    out.add(pick);
    t += _q(pick.$1, pick.$2);
  }
  return out;
}

extension ScoreEdits on MusicScore {
  bool get _compound => beatUnit == 8 && beats % 3 == 0;

  /// _rests are rests from [from] to [to] in [voice], as [restsFor] has them,
  /// with their start times.
  List<(double, ScoreEvent)> _rests(
      double from, double to, int voice, String Function() id) {
    var out = <(double, ScoreEvent)>[];
    var r = from;
    for (var (v, d) in restsFor(from, to, compound: _compound)) {
      out.add((r, ScoreEvent(id(), v, dots: d, voice: voice)));
      r += _q(v, d);
    }
    return out;
  }

  /// newIds are [count] event ids not yet used in this score.
  List<String> newIds(int count) {
    var top = 0;
    for (var p in parts) {
      for (var st in p.staves) {
        for (var b in st.bars) {
          for (var e in b) {
            var m = RegExp(r"(\d+)$").firstMatch(e.id);
            if (m != null) top = math.max(top, int.parse(m.group(1)!));
          }
        }
      }
    }
    return [for (var i = 1; i <= count; i++) "e${top + i}"];
  }

  /// find is where event [id] is, or null.
  EventPlace? find(String id) {
    for (var p in parts) {
      for (var (si, st) in p.staves.indexed) {
        for (var (bi, b) in st.bars.indexed) {
          for (var (i, e) in b.indexed) {
            if (e.id == id) return (part: p.id, staff: si, bar: bi, index: i);
          }
        }
      }
    }
    return null;
  }

  ScoreEvent? event(String id) {
    var at = find(id);
    if (at == null) return null;
    return partById(at.part)!.staves[at.staff].bars[at.bar][at.index];
  }

  /// timeOf is when event [id] starts in its bar.
  double timeOf(String id) {
    var at = find(id);
    if (at == null) return 0;
    var e0 = event(id)!;
    var t = 0.0;
    for (var e in partById(at.part)!.staves[at.staff].bars[at.bar]) {
      if (e.id == id) return t;
      if (e.voice == e0.voice) t += e.quarters;
    }
    return t;
  }

  /// withBar is this score with [part]'s [staff]'s [bar] as [events].
  MusicScore withBar(
          String part, int staff, int bar, List<ScoreEvent> events) =>
      copyWith(parts: [
        for (var p in parts)
          p.id != part
              ? p
              : p.copyWith(staves: [
                  for (var (si, st) in p.staves.indexed)
                    si != staff
                        ? st
                        : st.copyWith(bars: [
                            for (var (bi, b) in st.bars.indexed)
                              bi == bar ? events : b
                          ])
                ])
      ]);

  /// withEvent is this score with event [id] changed by [change].
  MusicScore withEvent(String id, ScoreEvent Function(ScoreEvent e) change) {
    var at = find(id);
    if (at == null) return this;
    var bar = [...partById(at.part)!.staves[at.staff].bars[at.bar]];
    bar[at.index] = change(bar[at.index]);
    return withBar(at.part, at.staff, at.bar, bar);
  }

  /// overwrite is this score with [made] written into [c]'s voice at its
  /// time, as MuseScore's note input writes: what it covers goes, a note it
  /// cuts into is cut short (or turned to rests where its new length cannot
  /// be written), and the rest of what it covered becomes rests. It is cut
  /// at the bar's end.
  MusicScore overwrite(ScoreCursor c, ScoreEvent made) {
    var p = partById(c.part);
    if (p == null || c.staff >= p.staves.length) return this;
    var barQ = barQuarters(c.bar);
    var at = (c.at * 48).round() / 48;
    if (at >= barQ - 1e-6) return this;
    var room = barQ - at;
    if (made.quarters > room + 1e-6) {
      var (v, d) = valuesFor(room).first;
      made = made.copyWith(value: v, dots: d, noTuplet: true, tie: false);
    }
    var len = made.quarters;
    var events = p.staves[c.staff].barAt(c.bar);
    var ids = newIds(16);
    var idAt = 0;
    String next() => ids[idAt++];
    var mine = <(double, ScoreEvent)>[];
    var t = 0.0;
    for (var e in events.where((e) => e.voice == c.voice)) {
      var s = t, end = t + e.quarters;
      t = end;
      if (end <= at + 1e-6 || s >= at + len - 1e-6) {
        mine.add((s, e));
        continue;
      }
      if (s < at - 1e-6) {
        // What is left of it before the new one.
        var keep = at - s;
        var fits = valuesFor(keep);
        if (!e.isRest && fits.length == 1 && e.tuplet == null) {
          mine.add((
            s,
            e.copyWith(value: fits.first.$1, dots: fits.first.$2, tie: false)
          ));
        } else {
          mine.addAll(_rests(s, at, c.voice, next));
        }
      }
      if (end > at + len + 1e-6) {
        mine.addAll(_rests(at + len, end, c.voice, next));
      }
    }
    // A voice with nothing written yet up to here: rests to the new one.
    var filled = mine.fold(0.0, (a, x) => math.max(a, x.$1 + x.$2.quarters));
    if (filled < at - 1e-6) mine.addAll(_rests(filled, at, c.voice, next));
    mine.add((at, made.copyWith(voice: c.voice)));
    mine.sort((a, b) => a.$1.compareTo(b.$1));
    var out = <ScoreEvent>[];
    for (var v = 0; v < 4; v++) {
      if (v == c.voice) {
        out.addAll([for (var x in mine) x.$2]);
      } else {
        out.addAll(events.where((e) => e.voice == v));
      }
    }
    return withBar(c.part, c.staff, c.bar, out);
  }

  /// enter writes [pitches] (none for a rest) of [value] with [dots] at
  /// [c], and is where the cursor goes next: just after it, into the next
  /// bar at the bar's end. Answers the score, the new event's id and the
  /// cursor.
  (MusicScore, String, ScoreCursor) enter(
      ScoreCursor c, List<Pitch> pitches, double value,
      {int dots = 0, bool slash = false, Strum? strum}) {
    var id = newIds(1).first;
    var made = ScoreEvent(id, value,
        dots: dots,
        pitches: [...pitches]..sort((a, b) => a.key.compareTo(b.key)),
        slash: slash,
        strum: strum);
    var next = overwrite(c, made);
    var written = next.event(id)?.quarters ?? made.quarters;
    var at = c.at + written;
    var cur = c;
    if (at >= barQuarters(c.bar) - 1e-6) {
      cur = c.bar + 1 < barCount
          ? (
              part: c.part,
              staff: c.staff,
              bar: c.bar + 1,
              at: 0.0,
              voice: c.voice
            )
          : (part: c.part, staff: c.staff, bar: c.bar, at: at, voice: c.voice);
    } else {
      cur = (part: c.part, staff: c.staff, bar: c.bar, at: at, voice: c.voice);
    }
    return (next, id, cur);
  }

  /// addToChord puts [pitch] in event [id], a note added to its chord.
  MusicScore addToChord(String id, Pitch pitch) => withEvent(
      id,
      (e) => e.pitches.contains(pitch) || e.slash
          ? e
          : e.copyWith(
              pitches: [...e.pitches, pitch]
                ..sort((a, b) => a.key.compareTo(b.key))));

  /// deleteEvent turns event [id] into a rest as long (in voices past the
  /// first, it goes, as MuseScore does).
  MusicScore deleteEvent(String id) {
    var e = event(id);
    if (e == null) return this;
    if (e.voice > 0) {
      var at = find(id)!;
      var bar = [...partById(at.part)!.staves[at.staff].bars[at.bar]]
        ..removeAt(at.index);
      return withBar(at.part, at.staff, at.bar, bar);
    }
    return withEvent(
        id,
        (e) => ScoreEvent(e.id, e.value,
            dots: e.dots, tuplet: e.tuplet, voice: e.voice, offsets: const {}));
  }

  /// setValue makes event [id] [value] long with [dots], writing over what
  /// follows (or leaving rests where it was longer).
  MusicScore setValue(String id, double value, {int dots = 0}) {
    var at = find(id);
    var e = event(id);
    if (at == null || e == null) return this;
    return overwrite((
      part: at.part,
      staff: at.staff,
      bar: at.bar,
      at: timeOf(id),
      voice: e.voice
    ), e.copyWith(value: value, dots: dots, noTuplet: true));
  }

  /// transposed moves event [id]'s notes: [steps] staff steps (each keeping
  /// to the key), or [semitones], or [octaves].
  MusicScore transposed(String id,
      {int steps = 0, int semitones = 0, int octaves = 0}) {
    var at = find(id);
    if (at == null) return this;
    var fifths = keyAt(at.bar);
    return withEvent(id, (e) {
      if (e.isRest || e.slash) return e;
      return e.copyWith(
          pitches: [
        for (var p in e.pitches)
          () {
            var q = p;
            if (steps != 0) {
              q = p.up(steps);
              q = q.withAlter(keyAlter(q.letter, fifths));
            }
            if (semitones != 0) {
              // Spelled as the key has it; in C, sharps going up and flats
              // going down, as a player expects.
              q = Pitch.spelled(q.key + semitones,
                  fifths: fifths != 0 ? fifths : (semitones > 0 ? 1 : -1));
            }
            if (octaves != 0) q = Pitch(q.letter, q.octave + octaves, q.alter);
            return q;
          }()
      ]..sort((a, b) => a.key.compareTo(b.key)));
    });
  }

  MusicScore toggleArticulation(String id, Articulation a) => withEvent(
      id,
      (e) => e.copyWith(
          articulations: e.articulations.contains(a)
              ? ({...e.articulations}..remove(a))
              : {...e.articulations, a}));

  /// setDynamic marks [id] with [d] (the same again takes it off).
  MusicScore setDynamic(String id, Dynamic? d) => withEvent(
      id,
      (e) => d == null || e.dyn == d
          ? e.copyWith(noDyn: true)
          : e.copyWith(dyn: d));

  MusicScore setChord(String id, String? chord) => withEvent(
      id,
      (e) => chord == null || chord.trim().isEmpty
          ? e.copyWith(noChord: true)
          : e.copyWith(chord: chord.trim()));

  /// setLyric is event [id]'s syllable in [verse] (0-based).
  MusicScore setLyric(String id, int verse, String text) => withEvent(id, (e) {
        var l = [...e.lyrics];
        while (l.length <= verse) {
          l.add("");
        }
        l[verse] = text;
        while (l.isNotEmpty && l.last.isEmpty) {
          l.removeLast();
        }
        return e.copyWith(lyrics: l);
      }).copyWith(verses: math.max(verses, verse + 1));

  MusicScore toggleTie(String id) =>
      withEvent(id, (e) => e.copyWith(tie: !e.tie && !e.isRest));

  MusicScore setStrum(String id, Strum? s) => withEvent(
      id,
      (e) => !e.slash
          ? e
          : s == null
              ? e.copyWith(noStrum: true)
              : e.copyWith(strum: s));

  /// setAlter sharpens, flattens or naturals every note of [id].
  MusicScore setAlter(String id, int alter) => withEvent(
      id,
      (e) =>
          e.copyWith(pitches: [for (var p in e.pitches) p.withAlter(alter)]));

  /// movedEventMark, movedBarMark and movedScoreMark keep a marking dragged
  /// to [to] from where it is drawn.
  MusicScore movedEventMark(String id, String kind, Offset to) =>
      withEvent(id, (e) => e.movedMark(kind, to));

  MusicScore movedBarMark(int bar, String kind, Offset to) =>
      withBarInfo(bar, (b) {
        var o = {...b.offsets, kind: to}
          ..removeWhere((_, v) => v == Offset.zero);
        return b.copyWith(offsets: o);
      });

  MusicScore movedScoreMark(String kind, Offset to) => copyWith(
      offsets: {...offsets, kind: to}..removeWhere((_, v) => v == Offset.zero));

  MusicScore withBarInfo(int bar, BarInfo Function(BarInfo b) change) =>
      bar < 0 || bar >= barCount
          ? this
          : copyWith(bars: [
              for (var (i, b) in bars.indexed) i == bar ? change(b) : b
            ]);

  /// _restBar is a bar of rests [quarters] long, for every staff.
  List<ScoreEvent> _restBar(double quarters, List<String> ids) => [
        for (var (i, (v, d)) in valuesFor(quarters).indexed)
          ScoreEvent(ids[i], v, dots: d)
      ];

  /// insertBars puts [count] empty bars before bar [at] (at the end for
  /// barCount), in the time in force there.
  MusicScore insertBars(int at, [int count = 1]) {
    at = at.clamp(0, barCount);
    var q = barQuarters(math.max(0, math.min(at, barCount - 1)));
    var staves = parts.fold(0, (a, p) => a + p.staves.length);
    var ids = newIds(staves * count * 4);
    var n = 0;
    List<String> take(int k) => [for (var i = 0; i < k; i++) ids[n++]];
    // Spanners and marks past the new bars move along with their bars.
    Spanner moved(Spanner s) => Spanner(
        s.id,
        s.kind,
        s.part,
        s.staff,
        s.from.bar >= at ? (bar: s.from.bar + count, at: s.from.at) : s.from,
        s.to.bar >= at ? (bar: s.to.bar + count, at: s.to.at) : s.to);
    return copyWith(
        bars: [...bars]..insertAll(at, List.filled(count, const BarInfo())),
        spanners: [
          for (var s in spanners) moved(s)
        ],
        parts: [
          for (var p in parts)
            p.copyWith(staves: [
              for (var st in p.staves)
                st.copyWith(
                    bars: [...st.bars]..insertAll(at, [
                        for (var i = 0; i < count; i++)
                          _restBar(q, take(valuesFor(q).length))
                      ]))
            ])
        ]);
  }

  /// removeBars takes out [count] bars from [at] (never the last one).
  MusicScore removeBars(int at, [int count = 1]) {
    if (barCount - count < 1 || at < 0 || at + count > barCount) return this;
    bool inside(ScoreTime t) => t.bar >= at && t.bar < at + count;
    ScoreTime shift(ScoreTime t) =>
        t.bar >= at + count ? (bar: t.bar - count, at: t.at) : t;
    return copyWith(bars: [...bars]..removeRange(at, at + count), spanners: [
      for (var s in spanners)
        if (!inside(s.from) && !inside(s.to))
          Spanner(s.id, s.kind, s.part, s.staff, shift(s.from), shift(s.to))
    ], parts: [
      for (var p in parts)
        p.copyWith(staves: [
          for (var st in p.staves)
            st.copyWith(bars: [...st.bars]..removeRange(at, at + count))
        ])
    ]);
  }

  /// addPart adds a part for [instrument] (see scoreInstruments) at the
  /// bottom, its bars rests.
  MusicScore addPart(String instrument) {
    var inst = scoreInstrument(instrument);
    var ids = newIds(barCount * inst.clefs.length * 4);
    var n = 0;
    var id = "p1";
    for (var i = 1; parts.any((p) => p.id == id); i++) {
      id = "p$i";
    }
    var same = parts.where((p) => p.instrument == instrument).length;
    return copyWith(parts: [
      ...parts,
      ScorePart(
          id,
          same == 0 ? inst.name : "${inst.name} ${same + 1}",
          inst.id,
          [
            for (var clef in inst.clefs)
              ScoreStaff(clef, [
                for (var b = 0; b < barCount; b++)
                  [
                    for (var (v, d) in valuesFor(barQuarters(b)))
                      ScoreEvent(ids[n++], v, dots: d)
                  ]
              ])
          ],
          short: inst.short),
    ]);
  }

  MusicScore removePart(String id) => copyWith(parts: [
        for (var p in parts)
          if (p.id != id) p
      ], spanners: [
        for (var s in spanners)
          if (s.part != id) s
      ]);

  /// movePart moves part [id] [by] places down (up for negative).
  MusicScore movePart(String id, int by) {
    var i = parts.indexWhere((p) => p.id == id);
    if (i < 0) return this;
    var j = (i + by).clamp(0, parts.length - 1);
    var list = [...parts];
    var p = list.removeAt(i);
    list.insert(j, p);
    return copyWith(parts: list);
  }

  MusicScore setClef(String part, int staff, Clef clef) => copyWith(parts: [
        for (var p in parts)
          p.id != part
              ? p
              : p.copyWith(staves: [
                  for (var (si, st) in p.staves.indexed)
                    si == staff ? st.copyWith(clef: clef) : st
                ])
      ]);

  MusicScore addSpanner(
      SpannerKind kind, String part, int staff, ScoreTime from, ScoreTime to) {
    var n = 1;
    while (spanners.any((s) => s.id == "s$n")) {
      n++;
    }
    return copyWith(
        spanners: [...spanners, Spanner("s$n", kind, part, staff, from, to)]);
  }

  MusicScore withSpanner(String id, Spanner Function(Spanner s) change) =>
      copyWith(spanners: [for (var s in spanners) s.id == id ? change(s) : s]);

  /// resizedEventMark draws event [id]'s marking [kind] at [size] times its
  /// own size (one puts it back).
  MusicScore resizedEventMark(String id, String kind, double size) =>
      withEvent(id, (e) {
        var sizes = {...e.sizes, kind: size.clamp(0.3, 4.0)}
          ..removeWhere((_, v) => (v - 1).abs() < 1e-3);
        return e.copyWith(sizes: sizes);
      });

  MusicScore removeSpanner(String id) => copyWith(spanners: [
        for (var s in spanners)
          if (s.id != id) s
      ]);
}
