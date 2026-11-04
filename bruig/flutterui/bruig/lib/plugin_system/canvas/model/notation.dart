import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/instrument.dart';

// notation.dart writes a part (notes in seconds) out as a score: bars on one
// or two staves, written values with rests and ties, notes spelled for the
// key and given accidentals only where the key signature or an earlier note
// in the bar does not already say so.
//
// Up to two voices a staff: notes starting and ending together are a chord,
// a note held under a moving tune is a voice of its own. A beat whose notes
// sit nearer thirds than sixteenths is written as a triplet. Times are in
// quarter notes throughout.

/// Staff is which staff: the treble, for the right hand, or the bass.
enum Staff { treble, bass }

/// Written is a chord (one key or several) or a rest on a staff, [at]
/// quarters into its bar and [quarters] long. [notes] are the part's notes it
/// sounds, by index (repeated in each tied piece), for marking what was
/// played.
class Written {
  final double at;
  final double quarters;
  final List<int> keys;
  final List<int> notes;

  /// tiedOn is whether it carries on, tied, into the next.
  final bool tiedOn;

  /// steps are each key's place in steps up from the staff's bottom line,
  /// and accidentals its sign (1 sharp, -1 flat, 0 natural, null none), in
  /// the order of [keys].
  final List<int> steps;
  final List<int?> accidentals;

  /// voice is nought for the upper voice, one for the lower (stems down).
  final int voice;

  /// tuplet is whether it is part of a triplet, so written half as long
  /// again as it lasts (a third of a beat is a quaver).
  final bool tuplet;

  const Written(this.at, this.quarters,
      {this.keys = const [],
      this.notes = const [],
      this.tiedOn = false,
      this.steps = const [],
      this.accidentals = const [],
      this.voice = 0,
      this.tuplet = false});

  Written withAccidentals(List<int?> signs) => Written(at, quarters,
      keys: keys,
      notes: notes,
      tiedOn: tiedOn,
      steps: steps,
      accidentals: signs,
      voice: voice,
      tuplet: tuplet);

  bool get isRest => keys.isEmpty;

  /// dots is how many dots its value has. Triplets are never dotted.
  int get dots => !tuplet &&
          (quarters == 3 ||
              quarters == 1.5 ||
              quarters == 0.75 ||
              quarters == 0.375)
      ? 1
      : 0;

  /// base is its value without the dot (as written, for a triplet).
  double get base => tuplet
      ? _onGrid(quarters * 1.5)
      : dots == 1
          ? quarters / 1.5
          : quarters;
}

/// tupletGroups are [items]' triplets, by index, grouped by voice and beat
/// for their brackets.
List<List<int>> tupletGroups(List<Written> items) {
  var groups = <List<int>>[];
  (int, int)? current;
  for (var (i, w) in items.indexed) {
    if (!w.tuplet) {
      current = null;
      continue;
    }
    var beat = (w.at + 1e-9).floor();
    if (current != (w.voice, beat)) {
      groups.add([]);
      current = (w.voice, beat);
    }
    groups.last.add(i);
  }
  return groups;
}

/// _onGrid is [quarters] rounded to a 48th of a quarter (holding sixteenths
/// and thirds alike), so a moment worked out two ways is one number.
double _onGrid(double quarters) => (quarters * 48).round() / 48;

/// Bar is one bar of a score: what is written on each staff.
class Bar {
  final int number;
  final double start;
  final Map<Staff, List<Written>> staves;
  const Bar(this.number, this.start, this.staves);
}

/// Score is a part written out.
class Score {
  final int beatsPerBar, beatUnit;

  /// fifths is the key signature: sharps positive, flats negative.
  final int fifths;

  /// barQuarters is how long a bar is, in quarter notes.
  final double barQuarters;
  final List<Staff> staves;
  final List<Bar> bars;

  /// noteStarts are each of the part's notes' starts, in quarters.
  final List<double> noteStarts;

  /// voicesIn is how many voices [staff] has in [bar].
  int voicesIn(Bar bar, Staff staff) =>
      {for (var w in bar.staves[staff] ?? const <Written>[]) w.voice}.length;

  const Score(this.beatsPerBar, this.beatUnit, this.barQuarters, this.staves,
      this.bars, this.noteStarts,
      {this.fifths = 0});
}

/// _Chord is a voice's chord while a score is written: keys starting and
/// ending together, and their note indexes.
class _Chord {
  final double start;
  double end;
  final List<int> keys;
  final List<int> ids;
  _Chord(this.start, this.end, this.keys, this.ids);
}

/// splitKey is the lowest key written on the treble staff: middle C.
const int splitKey = 60;

/// _values are the written values, longest first, in quarters.
const List<double> _values = [4, 3, 2, 1.5, 1, 0.75, 0.5, 0.375, 0.25];

/// writeScore writes [notes] out at [tempo] quarter notes a minute, in bars
/// of [beatsPerBar] over [beatUnit], times rounded to [grid] quarters.
Score writeScore(List<MidiNote> notes,
    {double tempo = 120,
    int beatsPerBar = 4,
    int beatUnit = 4,
    double grid = 0.25,
    Set<Staff>? only,
    int? fifths}) {
  var key = fifths ?? keyFifthsOf(notes);
  var barQ = beatsPerBar * 4 / beatUnit;
  double raw(double seconds) => seconds * tempo / 60;
  // Beats played in threes: notes nearer thirds than sixteenths. Not in a
  // compound time, whose beat is three already.
  var compound = beatUnit == 8 && beatsPerBar % 3 == 0;
  var triplets = <int>{};
  if (!compound && grid == 0.25) {
    var votes = <int, int>{};
    for (var n in notes) {
      var t = raw(n.start);
      var beat = t.floor();
      var f = t - beat;
      var third = (f * 3).round(), sixteenth = (f * 4).round();
      // On the beat either way, it says nothing.
      if ((third == 0 || third == 3) && (sixteenth == 0 || sixteenth == 4)) {
        continue;
      }
      var off3 = (f - third / 3).abs(), off16 = (f - sixteenth / 4).abs();
      votes[beat] = (votes[beat] ?? 0) + (off3 < off16 ? 1 : -1);
    }
    triplets = {
      for (var MapEntry(key: b, value: v) in votes.entries)
        if (v > 0) b
    };
  }
  double q(double seconds) {
    var t = raw(seconds);
    var step = triplets.contains(t.floor()) ? 1 / 3 : grid;
    return _onGrid((t / step).round() * step);
  }

  /// least is the shortest a note from [start] is written.
  double least(double start) =>
      triplets.contains((start + 1e-9).floor()) ? 1 / 3 : grid;
  var starts = [for (var n in notes) q(n.start)];

  // One staff when every note is on it, else both.
  var on = <Staff, List<int>>{Staff.treble: [], Staff.bass: []};
  for (var (i, n) in notes.indexed) {
    on[n.key >= splitKey ? Staff.treble : Staff.bass]!.add(i);
  }
  var staves = only?.toList() ??
      [
        if (on[Staff.treble]!.isNotEmpty || on[Staff.bass]!.isEmpty)
          Staff.treble,
        if (on[Staff.bass]!.isNotEmpty) Staff.bass,
      ];
  staves.sort((a, b) => a.index.compareTo(b.index));

  var end = notes.isEmpty
      ? barQ
      : [
          for (var (i, n) in notes.indexed)
            math.max(_onGrid(starts[i] + least(starts[i])), q(n.end))
        ].reduce(math.max);
  var barCount = math.max(1, (end / barQ - 1e-9).ceil());

  // Each staff as up to two voices of chords. A note held a quaver or more
  // into the next gets a voice of its own (a pianist's held bass); a third
  // voice, or a shorter overlap (a legato touch), is cut where the next
  // starts.
  var written = <Staff, List<List<_Chord>>>{};
  for (var staff in staves) {
    var idx = [...on[staff]!]..sort((a, b) => starts[a] != starts[b]
        ? starts[a].compareTo(starts[b])
        : notes[b].key.compareTo(notes[a].key));
    double endOf(int k) =>
        math.max(_onGrid(starts[k] + least(starts[k])), q(notes[k].end));
    var groups = <_Chord>[];
    for (var k in idx) {
      var at = starts[k], till = endOf(k);
      var same = groups
          .where(
              (g) => (g.start - at).abs() < 1e-9 && (g.end - till).abs() < 1e-9)
          .firstOrNull;
      if (same != null) {
        same.keys.add(notes[k].key);
        same.ids.add(k);
      } else {
        groups.add(_Chord(at, till, [notes[k].key], [k]));
      }
    }
    var voices = <List<_Chord>>[];
    for (var g in groups) {
      _Chord? lastOf(List<_Chord> v) => v.isEmpty ? null : v.last;
      var free = voices
          .where((v) => (lastOf(v)?.end ?? 0) <= g.start + 1e-9)
          .firstOrNull;
      if (free == null) {
        // Held a quaver or more into this one, with a voice to spare: a
        // voice of its own.
        var overlapping = [for (var v in voices) (v, lastOf(v)!.end - g.start)];
        if (voices.length < 2 && overlapping.every((o) => o.$2 >= 0.5 - 1e-9)) {
          voices.add(free = <_Chord>[]);
        } else {
          // Otherwise cut short the voice that overlaps least.
          overlapping.sort((a, b) => a.$2.compareTo(b.$2));
          free = overlapping.first.$1;
          var held = free.last;
          if ((held.start - g.start).abs() < 1e-9) {
            // Together: one chord.
            held.keys.addAll(g.keys);
            held.ids.addAll(g.ids);
            held.end = math.min(held.end, g.end);
            continue;
          }
          held.end = g.start;
        }
      }
      free.add(g);
    }
    for (var v in voices) {
      for (var c in v) {
        c.keys.sort();
      }
    }
    // The upper voice (higher on average) first.
    if (voices.length == 2) {
      double pitch(List<_Chord> v) =>
          v.expand((c) => c.keys).fold(0, (a, b) => a + b) /
          math.max(1, v.expand((c) => c.keys).length);
      if (pitch(voices[1]) > pitch(voices[0])) {
        voices = [voices[1], voices[0]];
      }
    }
    written[staff] = voices.isEmpty ? [<_Chord>[]] : voices;
  }

  var bars = <Bar>[];
  for (var b = 0; b < barCount; b++) {
    var from = b * barQ, to = from + barQ;
    var staffMap = <Staff, List<Written>>{};
    // This bar's triplet beats, counted from its start.
    var threes = {
      for (var t in triplets)
        if (t >= from - 1e-9 && t < to - 1e-9) (t - from).round()
    };
    for (var staff in staves) {
      // Each voice's notes and rests, then their accidentals in time order.
      // The alterations in force in the bar are the staff's, whichever
      // voice set them.
      var pending = <(Written, bool, List<Spelled>)>[];
      for (var (v, chords) in written[staff]!.indexed) {
        var here = chords.any((c) => c.end > from && c.start < to);
        // A second voice only in the bars it has notes in.
        if (v > 0 && !here) continue;
        var cursor = from;
        void rest(double until) {
          for (var (at, len, three) in _spell(cursor - from, until - cursor,
              rest: true, triplets: threes)) {
            pending.add((
              Written(at, len, voice: v, tuplet: three),
              false,
              const [],
            ));
          }
          cursor = until;
        }

        for (var c in chords) {
          if (c.end <= from || c.start >= to) continue;
          var a = math.max(c.start, from), z = math.min(c.end, to);
          if (a > cursor) rest(a);
          var pieces = _spell(a - from, z - a, triplets: threes);
          var spelled = [for (var k in c.keys) spellKey(k, key)];
          var steps = [for (var sp in spelled) sp.step - _bottomOf(staff)];
          for (var (k, (at, len, three)) in pieces.indexed) {
            var last = k == pieces.length - 1;
            pending.add((
              Written(at, len,
                  keys: c.keys,
                  notes: c.ids,
                  steps: steps,
                  voice: v,
                  tuplet: three,
                  // Tied on into the next piece, or across the barline.
                  tiedOn: !last || c.end > to),
              // Only a note's first piece takes a sign; ties carry it.
              k == 0 && c.start >= from,
              spelled,
            ));
          }
          cursor = z;
        }
        if (cursor < to) rest(to);
      }
      var inForce = <int, int>{};
      var order = [...pending]..sort((x, y) => x.$1.at.compareTo(y.$1.at));
      var signed = <Written, List<int?>>{};
      for (var (w, first, spelled) in order) {
        if (w.isRest) continue;
        var signs = <int?>[];
        for (var (j, sp) in spelled.indexed) {
          if (!first) {
            signs.add(null);
            continue;
          }
          var was = inForce[w.steps[j]] ?? keyAlter(sp.letter, key);
          signs.add(sp.alter == was ? null : sp.alter);
          inForce[w.steps[j]] = sp.alter;
        }
        signed[w] = signs;
      }
      staffMap[staff] = [
        for (var (w, _, _) in pending)
          w.isRest ? w : w.withAccidentals(signed[w] ?? const []),
      ];
    }
    bars.add(Bar(b + 1, from, staffMap));
  }
  return Score(beatsPerBar, beatUnit, barQ, staves, bars, starts, fifths: key);
}

/// _spell is [length] quarters from [at] in a bar as written values, and
/// whether each is a triplet's.
///
/// A partly filled beat in [triplets] is written in thirds (triplet quaver
/// or crotchet); one filled whole is a crotchet like its neighbours.
List<(double, double, bool)> _spell(double at, double length,
    {bool rest = false, Set<int> triplets = const {}}) {
  var out = <(double, double, bool)>[];
  var end = _onGrid(at + length);
  var cursor = _onGrid(at);
  while (cursor < end - 1e-9) {
    var beat = (cursor + 1e-9).floor();
    var whole = (cursor - beat).abs() < 1e-9 && end >= beat + 1 - 1e-9;
    if (triplets.contains(beat) && !whole) {
      var stop = math.min(end, beat + 1.0);
      while (cursor < stop - 1e-9) {
        var piece = stop - cursor >= 2 / 3 - 1e-9 ? 2 / 3 : 1 / 3;
        out.add((cursor, _onGrid(piece), true));
        cursor = _onGrid(cursor + piece);
      }
      continue;
    }
    // Plain values up to the next beat in threes this does not fill.
    var until = end;
    for (var b = beat + 1; b < end - 1e-9; b++) {
      if (triplets.contains(b) && end < b + 1 - 1e-9) {
        until = b.toDouble();
        break;
      }
    }
    for (var (a, len) in _plain(cursor, until - cursor, rest: rest)) {
      out.add((a, len, false));
    }
    cursor = until;
  }
  return out;
}

/// _plain is [length] quarters from [at] in a bar as written values: each
/// the longest that fits and may start there (a half note on a half of the
/// bar, a quarter on a beat). Rests are never dotted, as is plainer.
List<(double, double)> _plain(double at, double length, {bool rest = false}) {
  var out = <(double, double)>[];
  var left = length;
  while (left > 1e-9) {
    var pick = _values.last;
    for (var v in _values) {
      if (v > left + 1e-9) continue;
      if (rest && (v == 3 || v == 1.5 || v == 0.75 || v == 0.375)) continue;
      // Where a value may start: dotted values on their own grid, others on
      // a multiple of themselves.
      var unit = v >= 1
          ? (v == 3 || v == 1.5 ? 1.0 : v)
          : (v == 0.75 || v == 0.375 ? 0.25 : v);
      if (((at / unit) - (at / unit).roundToDouble()).abs() > 1e-9) continue;
      pick = v;
      break;
    }
    out.add((at, pick));
    at += pick;
    left -= pick;
  }
  return out;
}

/// Spelled is a key as written: letter (0 C to 6 B), octave, alteration (1
/// sharp, -1 flat, 0 natural) and staff step.
typedef Spelled = ({int letter, int octave, int alter, int step});

const _naturals = [0, 2, 4, 5, 7, 9, 11];

/// keyAlter is how the key signature of [fifths] alters [letter]: the
/// sharps in their order F C G D A E B, the flats B E A D G C F.
int keyAlter(int letter, int fifths) {
  const sharps = [3, 0, 4, 1, 5, 2, 6]; // F C G D A E B
  if (fifths > 0) return sharps.take(fifths).contains(letter) ? 1 : 0;
  if (fifths < 0) {
    return sharps.reversed.take(-fifths).contains(letter) ? -1 : 0;
  }
  return 0;
}

/// spellKey is [key] spelled in the key of [fifths]: as the key signature
/// has it where it does, else a white key as itself, else a sharp in a sharp
/// key and a flat in a flat one.
Spelled spellKey(int key, int fifths) {
  var pc = key % 12, octave = key ~/ 12 - 1;
  Spelled make(int letter, int alter) {
    // B sharp is in the octave below its sound; C flat in the one above.
    var o = octave;
    if (letter == 6 && alter == 1 && pc == 0) o -= 1;
    if (letter == 0 && alter == -1 && pc == 11) o += 1;
    return (
      letter: letter,
      octave: o,
      alter: alter,
      step: (o + 1) * 7 + letter,
    );
  }

  var candidates = <(int, int)>[
    for (var l = 0; l < 7; l++)
      for (var a in const [-1, 0, 1])
        if ((_naturals[l] + a) % 12 == pc) (l, a),
  ];
  for (var (l, a) in candidates) {
    if (keyAlter(l, fifths) == a) return make(l, a);
  }
  for (var (l, a) in candidates) {
    if (a == 0) return make(l, a);
  }
  var want = fifths < 0 ? -1 : 1;
  for (var (l, a) in candidates) {
    if (a == want) return make(l, a);
  }
  var (l, a) = candidates.first;
  return make(l, a);
}

/// _bottomOf is a staff's bottom line, in steps: E4 on the treble, G2 on
/// the bass.
int _bottomOf(Staff staff) => staff == Staff.treble ? 5 * 7 + 2 : 3 * 7 + 4;

/// keyFifthsOf is the likeliest key signature for [notes], correlating how
/// long each pitch class is held with the Krumhansl-Kessler key profiles.
/// Nought with no notes.
int keyFifthsOf(List<MidiNote> notes) {
  if (notes.isEmpty) return 0;
  const major = [
    6.35,
    2.23,
    3.48,
    2.33,
    4.38,
    4.09,
    2.52,
    5.19,
    2.39,
    3.66,
    2.29,
    2.88
  ];
  const minor = [
    6.33,
    2.68,
    3.52,
    5.38,
    2.60,
    3.53,
    2.54,
    4.75,
    3.98,
    2.69,
    3.34,
    3.17
  ];
  var held = List<double>.filled(12, 0);
  for (var n in notes) {
    held[n.key % 12] += math.max(0.05, n.length);
  }
  double correlate(List<double> profile, int root) {
    var mx = held.reduce((a, b) => a + b) / 12;
    var mp = profile.reduce((a, b) => a + b) / 12;
    var num = 0.0, dx = 0.0, dp = 0.0;
    for (var i = 0; i < 12; i++) {
      var x = held[(i + root) % 12] - mx, p = profile[i] - mp;
      num += x * p;
      dx += x * x;
      dp += p * p;
    }
    return dx == 0 ? 0 : num / math.sqrt(dx * dp);
  }

  var best = -2.0, root = 0;
  var isMinor = false;
  for (var r = 0; r < 12; r++) {
    for (var (profile, m) in [(major, false), (minor, true)]) {
      var c = correlate(profile, r);
      if (c > best + 1e-9) {
        best = c;
        root = r;
        isMinor = m;
      }
    }
  }
  return fifthsOfMajor(isMinor ? (root + 3) % 12 : root);
}

/// fifthsOfMajor is the signature of the major key on [root] (0 C to 11 B),
/// the spelling with fewer signs (D flat, not C sharp; F sharp at a tie).
int fifthsOfMajor(int root) {
  var f = (root * 7) % 12;
  return f > 6 ? f - 12 : f;
}

/// keyNames are the keys a score can be written in, by signature: the
/// major and its relative minor.
const keyNames = {
  -7: "C♭ major / A♭ minor",
  -6: "G♭ major / E♭ minor",
  -5: "D♭ major / B♭ minor",
  -4: "A♭ major / F minor",
  -3: "E♭ major / C minor",
  -2: "B♭ major / G minor",
  -1: "F major / D minor",
  0: "C major / A minor",
  1: "G major / E minor",
  2: "D major / B minor",
  3: "A major / F♯ minor",
  4: "E major / C♯ minor",
  5: "B major / G♯ minor",
  6: "F♯ major / D♯ minor",
  7: "C♯ major / A♯ minor",
};

/// staffStep is where [key] sits on [staff], in steps up from the bottom
/// line, and whether it needs a sharp (black keys as the white key below,
/// sharpened).
(int, bool) staffStep(int key, Staff staff) {
  const steps = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6];
  var diatonic = (key ~/ 12) * 7 + steps[key % 12];
  var bottom = staff == Staff.treble ? 5 * 7 + 2 : 3 * 7 + 4;
  return (diatonic - bottom, isBlackKey(key));
}
