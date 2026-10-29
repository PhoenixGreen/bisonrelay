import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/instrument.dart';

// notation.dart writes a part out as a score: its notes, played in seconds,
// as bars of a time signature on one staff or two, each note a written value
// -- a crotchet, a dotted quaver -- with rests between, ties across the
// barlines, and the sharps a note needs.
//
// Engraved simply, as a lead sheet is: one voice to a staff, the notes that
// start together a chord, a note held under one that starts later cut short
// where it does. The time is in quarter notes throughout -- a beat of 4/4 --
// and the tempo is the document's.

/// Staff is which staff: the treble, for the right hand, or the bass.
enum Staff { treble, bass }

/// Written is one thing written on a staff: a chord -- one key or several --
/// or a rest, at [at] quarters into its bar, [quarters] long. [notes] are the
/// part's notes it sounds, by index -- the same note in each piece of one
/// tied across a barline -- for marking what was played.
class Written {
  final double at;
  final double quarters;
  final List<int> keys;
  final List<int> notes;

  /// tiedOn is whether it carries on, tied, into the next.
  final bool tiedOn;

  const Written(this.at, this.quarters,
      {this.keys = const [], this.notes = const [], this.tiedOn = false});

  bool get isRest => keys.isEmpty;

  /// dots is how many dots its value has: 1.5 a quarter is a dotted
  /// quarter.
  int get dots =>
      quarters == 3 || quarters == 1.5 || quarters == 0.75 || quarters == 0.375
          ? 1
          : 0;

  /// base is its value without the dot.
  double get base => dots == 1 ? quarters / 1.5 : quarters;
}

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

  /// barQuarters is how long a bar is, in quarter notes.
  final double barQuarters;
  final List<Staff> staves;
  final List<Bar> bars;

  /// noteStarts are each of the part's notes' starts, in quarters.
  final List<double> noteStarts;

  const Score(this.beatsPerBar, this.beatUnit, this.barQuarters, this.staves,
      this.bars, this.noteStarts);
}

/// splitKey is the lowest key written on the treble staff: middle C.
const int splitKey = 60;

/// noteValues are the written values, longest first, in quarters.
const List<double> _values = [4, 3, 2, 1.5, 1, 0.75, 0.5, 0.375, 0.25];

/// writeScore writes [notes] out: at [tempo] quarter notes a minute, in
/// bars of [beatsPerBar] over [beatUnit], each start and end put on the
/// nearest [grid] of a quarter.
Score writeScore(List<MidiNote> notes,
    {double tempo = 120,
    int beatsPerBar = 4,
    int beatUnit = 4,
    double grid = 0.25,
    Set<Staff>? only}) {
  var barQ = beatsPerBar * 4 / beatUnit;
  double q(double seconds) =>
      (seconds * tempo / 60 / grid).round() * grid;
  var starts = [for (var n in notes) q(n.start)];

  // The staves: one where every note is on it, else both.
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
      : [for (var (i, n) in notes.indexed) math.max(starts[i] + grid, q(n.end))]
          .reduce(math.max);
  var barCount = math.max(1, (end / barQ - 1e-9).ceil());

  // Each staff as one line of chords: those starting together, each held
  // until the next starts or it ends.
  var written = <Staff, List<(double, double, List<int>, List<int>)>>{};
  for (var staff in staves) {
    var idx = [...on[staff]!]..sort((a, b) => starts[a].compareTo(starts[b]));
    var chords = <(double, double, List<int>, List<int>)>[];
    var i = 0;
    while (i < idx.length) {
      var at = starts[idx[i]];
      var group = <int>[];
      while (i < idx.length && (starts[idx[i]] - at).abs() < 1e-9) {
        group.add(idx[i]);
        i++;
      }
      var till = group
          .map((k) => math.max(at + grid, q(notes[k].end)))
          .reduce(math.max);
      if (i < idx.length) till = math.min(till, starts[idx[i]]);
      chords.add((at, till, [for (var k in group) notes[k].key]..sort(), group));
    }
    written[staff] = chords;
  }

  var bars = <Bar>[];
  for (var b = 0; b < barCount; b++) {
    var from = b * barQ, to = from + barQ;
    var staffMap = <Staff, List<Written>>{};
    for (var staff in staves) {
      var items = <Written>[];
      var cursor = from;
      void rest(double until) {
        for (var (at, len) in _spell(cursor - from, until - cursor, rest: true)) {
          items.add(Written(at, len));
        }
        cursor = until;
      }

      for (var (s, e, keys, ids) in written[staff]!) {
        if (e <= from || s >= to) continue;
        var a = math.max(s, from), z = math.min(e, to);
        if (a > cursor) rest(a);
        var pieces = _spell(a - from, z - a);
        for (var (k, (at, len)) in pieces.indexed) {
          var last = k == pieces.length - 1;
          items.add(Written(at, len,
              keys: keys,
              notes: ids,
              // Tied on into the next piece, or across the barline.
              tiedOn: !last || e > to));
        }
        cursor = z;
      }
      if (cursor < to) rest(to);
      staffMap[staff] = items;
    }
    bars.add(Bar(b + 1, from, staffMap));
  }
  return Score(beatsPerBar, beatUnit, barQ, staves, bars, starts);
}

/// _spell is [length] quarters from [at] in a bar as written values: each
/// the longest that fits and starts where a note of its length may -- a
/// half note on a half of the bar, a quarter on a beat.
///
/// A rest is never dotted: a dotted rest is written, but a quaver rest and a
/// half rest say the same thing more plainly.
List<(double, double)> _spell(double at, double length, {bool rest = false}) {
  var out = <(double, double)>[];
  var left = length;
  while (left > 1e-9) {
    var pick = _values.last;
    for (var v in _values) {
      if (v > left + 1e-9) continue;
      if (rest && (v == 3 || v == 1.5 || v == 0.75 || v == 0.375)) continue;
      // Where a value of this length may start: dotted ones and those under
      // a beat on their own grid, the rest on a multiple of themselves.
      var unit = v >= 1 ? (v == 3 || v == 1.5 ? 1.0 : v) : (v == 0.75 || v == 0.375 ? 0.25 : v);
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

/// staffStep is where [key] sits on [staff], in steps up from the staff's
/// bottom line -- a line, a space, a line -- and whether it needs a sharp:
/// the black keys are written as the white key below, sharpened.
(int, bool) staffStep(int key, Staff staff) {
  const steps = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6];
  var diatonic = (key ~/ 12) * 7 + steps[key % 12];
  // The bottom lines: E4 on the treble, G2 on the bass.
  var bottom = staff == Staff.treble ? 5 * 7 + 2 : 3 * 7 + 4;
  return (diatonic - bottom, isBlackKey(key));
}
