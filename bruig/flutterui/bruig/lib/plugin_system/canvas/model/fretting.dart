import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/instrument.dart';

// fretting.dart is where a guitar's or bass's notes are played on its neck
// (Ken, 2026-11-14: "the guitar instrument's notes don't play in the correct
// positions ... the chords are triggering random chords in random
// positions"):
//
//  - a chord symbol is a real chord shape: the open chord a guitarist
//    learns first where there is one (G is 320003), or one of the movable
//    barre shapes up the neck, which the Score Studio can choose;
//  - notes sounding together go one to a string, as a hand can hold them,
//    in the closest position; a run of single notes stays where the hand
//    is, rather than each jumping to the lowest fret that has it.

/// FretPlace is where a note is played: the string (0 the lowest) and the
/// fret (0 open).
typedef FretPlace = (int string, int fret);

/// GuitarShape is a chord as a guitarist holds it: each string's fret, low
/// to high, null where it is not played.
class GuitarShape {
  /// name says where it is: "Open", "Barre, 3rd fret (E shape)".
  final String name;
  final List<int?> frets;
  const GuitarShape(this.name, this.frets);

  /// keys are what it sounds, low to high, on [strings].
  List<int> keysOn(List<int> strings) => [
        for (var (i, f) in frets.indexed)
          if (f != null && i < strings.length) strings[i] + f,
      ];

  /// places are its notes' places on the neck, low to high.
  List<FretPlace> get places => [
        for (var (i, f) in frets.indexed)
          if (f != null) (i, f),
      ];

  /// fingers are which finger holds each string, low to high (1 the first
  /// finger, null open or not played), as a chord chart numbers them: the
  /// lowest fret's notes barred by the first finger where they stretch
  /// from the lowest string played to the highest, otherwise a finger to a
  /// note, fret by fret.
  List<int?> get fingers {
    var out = List<int?>.filled(frets.length, null);
    var played = [
      for (var (i, f) in frets.indexed)
        if (f != null) i
    ];
    var fretted = [
      for (var (i, f) in frets.indexed)
        if (f != null && f > 0) (i, f)
    ];
    if (fretted.isEmpty) return out;
    var lowest = fretted.map((p) => p.$2).reduce(math.min);
    var atLowest = [
      for (var (i, f) in fretted)
        if (f == lowest) i
    ];
    var barre = atLowest.length >= 2 &&
        atLowest.contains(played.first) &&
        atLowest.contains(played.last);
    var finger = 1;
    if (barre) {
      for (var i in atLowest) {
        out[i] = 1;
      }
      finger = 2;
    }
    var byFret = [
      for (var p in fretted)
        if (!(barre && p.$2 == lowest)) p
    ]..sort(
        (a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1));
    for (var (i, _) in byFret) {
      out[i] = math.min(4, finger++);
    }
    return out;
  }

  /// lowestFret is the lowest fret it holds down, or 0 for none.
  int get lowestFret {
    var fretted = [
      for (var f in frets)
        if (f != null && f > 0) f
    ];
    return fretted.isEmpty ? 0 : fretted.reduce(math.min);
  }

  @override
  String toString() => "$name ${frets.map((f) => f?.toString() ?? "x").join()}";
}

const _letters = ["C", "D", "E", "F", "G", "A", "B"];
const _naturals = [0, 2, 4, 5, 7, 9, 11];

/// ChordName is a chord symbol read: its root, its bass (the root but for
/// a slash chord), and its kind ("", "m", "7", "m7", "maj7", "sus2",
/// "sus4", "dim", "aug", "6", "m6", "9", "add9" ...).
typedef ChordName = ({int root, int bass, String kind});

/// readChord reads chord symbol [symbol]; null where it is not one.
ChordName? readChord(String symbol) {
  var m = RegExp(r"^\s*([A-G])([#b♯♭]?)([^/]*)(?:/([A-G])([#b♯♭]?))?\s*$")
      .firstMatch(symbol);
  if (m == null) return null;
  int pc(String l, String a) =>
      (_naturals[_letters.indexOf(l)] +
          (a == "#" || a == "♯"
              ? 1
              : a == "b" || a == "♭"
                  ? -1
                  : 0)) %
      12;
  var root = pc(m.group(1)!, m.group(2) ?? "");
  var bass = m.group(4) != null ? pc(m.group(4)!, m.group(5) ?? "") : root;
  var q = (m.group(3) ?? "").trim();
  var minor = RegExp(r"^(m(?!aj)|min|-)").hasMatch(q);
  String kind;
  if (q.startsWith("dim") || q.startsWith("°")) {
    kind = q.contains("7") ? "dim7" : "dim";
  } else if (q.startsWith("aug") || q.startsWith("+")) {
    kind = "aug";
  } else if (q.contains("sus2")) {
    kind = "sus2";
  } else if (q.contains("sus")) {
    kind = q.contains("7") ? "7sus4" : "sus4";
  } else if (q.contains("maj7") || q.contains("Δ") || q.contains("M7")) {
    kind = minor ? "mmaj7" : "maj7";
  } else if (q.contains("add9")) {
    kind = minor ? "madd9" : "add9";
  } else if (q.contains("9")) {
    kind = minor ? "m9" : "9";
  } else if (q.contains("7")) {
    kind = minor ? "m7" : "7";
  } else if (q.contains("6")) {
    kind = minor ? "m6" : "6";
  } else {
    kind = minor ? "m" : "";
  }
  return (root: root, bass: bass, kind: kind);
}

/// chordTones are [kind]'s notes above its root, in semitones.
List<int> chordTones(String kind) => switch (kind) {
      "m" => [0, 3, 7],
      "7" => [0, 4, 7, 10],
      "m7" => [0, 3, 7, 10],
      "maj7" => [0, 4, 7, 11],
      "mmaj7" => [0, 3, 7, 11],
      "sus2" => [0, 2, 7],
      "sus4" => [0, 5, 7],
      "7sus4" => [0, 5, 7, 10],
      "dim" => [0, 3, 6],
      "dim7" => [0, 3, 6, 9],
      "aug" => [0, 4, 8],
      "6" => [0, 4, 7, 9],
      "m6" => [0, 3, 7, 9],
      "9" => [0, 4, 7, 10, 14],
      "m9" => [0, 3, 7, 10, 14],
      "add9" => [0, 4, 7, 14],
      "madd9" => [0, 3, 7, 14],
      _ => [0, 4, 7],
    };

/// _open are the open chords every guitarist learns, by root and kind,
/// low E to high e (-1 not played).
const _open = <(int, String), List<int>>{
  (0, ""): [-1, 3, 2, 0, 1, 0],
  (0, "maj7"): [-1, 3, 2, 0, 0, 0],
  (0, "7"): [-1, 3, 2, 3, 1, 0],
  (0, "add9"): [-1, 3, 2, 0, 3, 0],
  (0, "sus4"): [-1, 3, 3, 0, 1, 1],
  (2, ""): [-1, -1, 0, 2, 3, 2],
  (2, "m"): [-1, -1, 0, 2, 3, 1],
  (2, "7"): [-1, -1, 0, 2, 1, 2],
  (2, "m7"): [-1, -1, 0, 2, 1, 1],
  (2, "maj7"): [-1, -1, 0, 2, 2, 2],
  (2, "sus2"): [-1, -1, 0, 2, 3, 0],
  (2, "sus4"): [-1, -1, 0, 2, 3, 3],
  (2, "6"): [-1, -1, 0, 2, 0, 2],
  (4, ""): [0, 2, 2, 1, 0, 0],
  (4, "m"): [0, 2, 2, 0, 0, 0],
  (4, "7"): [0, 2, 0, 1, 0, 0],
  (4, "m7"): [0, 2, 0, 0, 0, 0],
  (4, "maj7"): [0, 2, 1, 1, 0, 0],
  (4, "sus4"): [0, 2, 2, 2, 0, 0],
  (4, "7sus4"): [0, 2, 0, 2, 0, 0],
  // The small F every beginner's chart has; the full barre is the next
  // position along.
  (5, ""): [-1, -1, 3, 2, 1, 1],
  (5, "maj7"): [-1, -1, 3, 2, 1, 0],
  (7, ""): [3, 2, 0, 0, 0, 3],
  (7, "7"): [3, 2, 0, 0, 0, 1],
  (7, "maj7"): [3, 2, 0, 0, 0, 2],
  (7, "6"): [3, 2, 0, 0, 0, 0],
  (9, ""): [-1, 0, 2, 2, 2, 0],
  (9, "m"): [-1, 0, 2, 2, 1, 0],
  (9, "7"): [-1, 0, 2, 0, 2, 0],
  (9, "m7"): [-1, 0, 2, 0, 1, 0],
  (9, "maj7"): [-1, 0, 2, 1, 2, 0],
  (9, "sus2"): [-1, 0, 2, 2, 0, 0],
  (9, "sus4"): [-1, 0, 2, 2, 3, 0],
  (9, "7sus4"): [-1, 0, 2, 0, 3, 0],
  (9, "6"): [-1, 0, 2, 2, 2, 2],
  (11, "7"): [-1, 2, 1, 2, 0, 2],
};

/// _eShape and _aShape are the movable barre shapes, frets above the
/// barre, low E to high e (-1 not played): the E shape's root on the low E
/// string, the A shape's on the A.
const _eShape = <String, List<int>>{
  "": [0, 2, 2, 1, 0, 0],
  "m": [0, 2, 2, 0, 0, 0],
  "7": [0, 2, 0, 1, 0, 0],
  "m7": [0, 2, 0, 0, 0, 0],
  "maj7": [0, -1, 1, 1, 0, -1],
  "sus4": [0, 2, 2, 2, 0, 0],
  "7sus4": [0, 2, 0, 2, 0, 0],
  "6": [0, -1, -1, 1, 2, 0],
  "m6": [0, -1, -1, 0, 2, 0],
};
const _aShape = <String, List<int>>{
  "": [-1, 0, 2, 2, 2, 0],
  "m": [-1, 0, 2, 2, 1, 0],
  "7": [-1, 0, 2, 0, 2, 0],
  "m7": [-1, 0, 2, 0, 1, 0],
  "maj7": [-1, 0, 2, 1, 2, 0],
  "sus2": [-1, 0, 2, 2, 0, 0],
  "sus4": [-1, 0, 2, 2, 3, 0],
  "7sus4": [-1, 0, 2, 0, 3, 0],
  "6": [-1, 0, 2, 2, 2, 2],
  "m6": [-1, 0, 2, 2, 1, 2],
  "add9": [-1, 0, 2, 4, 2, 0],
  "dim": [-1, 0, 1, 2, 1, -1],
  "aug": [-1, 0, 3, 2, 2, -1],
  "dim7": [-1, 0, 1, 2, 1, 2],
};

String _ordinal(int n) => switch (n % 100) {
      11 || 12 || 13 => "${n}th",
      _ => switch (n % 10) {
          1 => "${n}st",
          2 => "${n}nd",
          3 => "${n}rd",
          _ => "${n}th",
        },
    };

/// guitarChordShapes are the places [symbol] can be played on a guitar in
/// standard tuning, the common one first: the open chord where there is
/// one, then barre chords up the neck, lowest first. A slash chord's bass
/// is put on the lowest string that can reach it. Empty where it cannot be
/// read.
List<GuitarShape> guitarChordShapes(String symbol) {
  var c = readChord(symbol);
  if (c == null) return const [];
  var out = <GuitarShape>[];
  void add(String name, List<int> frets) {
    var shape = _withBass(frets, c.bass, c.root);
    if (shape == null) return;
    if (out.any((s) => _same(s.frets, shape))) return;
    out.add(GuitarShape(name, shape));
  }

  if (_open[(c.root, c.kind)] case var f?) add("Open", f);
  var moves = <(int, String, List<int>)>[];
  if (_eShape[c.kind] case var f?) {
    var at = (c.root - 4) % 12;
    for (var fret in [at, at + 12]) {
      if (fret >= 1 && fret + 4 <= frets) moves.add((fret, "E", f));
    }
  }
  if (_aShape[c.kind] case var f?) {
    var at = (c.root - 9) % 12;
    for (var fret in [at, at + 12]) {
      if (fret >= 1 && fret + 4 <= frets) moves.add((fret, "A", f));
    }
  }
  moves.sort((a, b) => a.$1.compareTo(b.$1));
  for (var (fret, letter, f) in moves) {
    add("Barre, ${_ordinal(fret)} fret ($letter shape)",
        [for (var x in f) x < 0 ? -1 : x + fret]);
  }
  // Nothing in the shapes: the chord's notes, a hand's worth placed.
  if (out.isEmpty) {
    var keys = <int>[];
    var low = 40 + ((c.bass - 40) % 12 + 12) % 12;
    keys.add(low);
    var pcs = {for (var t in chordTones(c.kind)) (c.root + t) % 12};
    for (var k = low + 1; k <= 64 && keys.length < 6; k++) {
      if (pcs.contains(k % 12)) keys.add(k);
    }
    var places = neckPlaces(keys, guitarStrings);
    if (places.isNotEmpty) {
      var f = List<int?>.filled(6, null);
      for (var (s, fret) in places) {
        f[s] = fret;
      }
      out.add(GuitarShape("Close voiced", f));
    }
  }
  return out;
}

/// guitarChord is [symbol] played in position [shape] (by its place in
/// guitarChordShapes; null or out of range the common one), or null where
/// it cannot be read.
GuitarShape? guitarChord(String symbol, [int? shape]) {
  var all = guitarChordShapes(symbol);
  if (all.isEmpty) return null;
  return all[(shape ?? 0) >= 0 && (shape ?? 0) < all.length ? shape ?? 0 : 0];
}

bool _same(List<int?> a, List<int?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// _withBass is [frets] with [bass] lowest: as it is where its lowest
/// note is already the bass; otherwise the bass put on the lowest string
/// below its lowest note that reaches it near the shape, the strings under
/// that not played. Null where no string can.
List<int?>? _withBass(List<int> frets, int bass, int root) {
  var f = [for (var x in frets) x < 0 ? null : x];
  var lowest = f.indexWhere((x) => x != null);
  if (lowest < 0) return null;
  if ((guitarStrings[lowest] + f[lowest]!) % 12 == bass) return f;
  // The bass already in it, a string up: the strings under that left out
  // (G/B, x20003).
  for (var s = lowest + 1; s < f.length && s <= 2; s++) {
    if (f[s] case var x? when (guitarStrings[s] + x) % 12 == bass) {
      return [for (var (i, y) in f.indexed) i < s ? null : y];
    }
  }
  var fretted = [
    for (var x in f)
      if (x != null && x > 0) x
  ];
  var lo = fretted.isEmpty ? 0 : fretted.reduce(math.min);
  var hi = fretted.isEmpty ? 3 : fretted.reduce(math.max);
  for (var s = lowest - 1; s >= 0; s--) {
    var fret = (bass - guitarStrings[s]) % 12;
    for (var g in [fret, fret + 12]) {
      if (g == 0 || (g >= lo - 1 && g <= math.max(hi, lo + 3) + 1)) {
        return [
          for (var (i, x) in f.indexed)
            i < s
                ? null
                : i == s
                    ? g
                    : x
        ];
      }
    }
  }
  // No string under it reaches: the bass put on the lowest string played
  // instead, where it is near the shape.
  var fret = (bass - guitarStrings[lowest]) % 12;
  if (fret == 0 || (fret >= lo - 1 && fret <= hi + 1)) {
    return [for (var (i, x) in f.indexed) i == lowest ? fret : x];
  }
  // Out of reach in this shape: not a place for this chord.
  return null;
}

/// bassChordKeys is [symbol] as a bass plays it under a strum: its bass
/// note, low on the neck.
List<int> bassChordKeys(String symbol) {
  var c = readChord(symbol);
  if (c == null) return const [36];
  return [28 + ((c.bass - 28) % 12 + 12) % 12];
}

// ------------------------------------------------------------ placing notes

/// neckPlaces is where [keys], sounding together, are played on [strings]:
/// one to a string, in the closest position a hand can hold -- near fret
/// [near] where the hand already is, otherwise as low as it goes. Keys the
/// neck has no room for are left out.
List<FretPlace> neckPlaces(Iterable<int> keys, List<int> strings,
    {double? near, Set<int> busy = const {}}) {
  var sorted = keys.toSet().toList()..sort();
  if (sorted.isEmpty) return const [];
  List<FretPlace>? best;
  var bestCost = double.infinity;
  var current = <FretPlace>[];
  var used = <int>{...busy};
  void place(int i, int missed) {
    if (i == sorted.length) {
      var cost = _cost(current, near) + missed * 100;
      if (cost < bestCost) {
        bestCost = cost;
        best = [...current];
      }
      return;
    }
    var key = sorted[i];
    for (var (s, open) in strings.indexed) {
      if (used.contains(s)) continue;
      var fret = key - open;
      if (fret < 0 || fret > frets) continue;
      used.add(s);
      current.add((s, fret));
      place(i + 1, missed);
      current.removeLast();
      used.remove(s);
    }
    place(i + 1, missed + 1);
  }

  place(0, 0);
  return best ?? const [];
}

/// _cost is how hard [places] are to hold: how far the fretted notes
/// stretch, how far the hand moves from [near] (or how far up the neck,
/// with nowhere to start from), and a lower string for a lower note.
double _cost(List<FretPlace> places, double? near) {
  var fretted = [
    for (var (_, f) in places)
      if (f > 0) f
  ];
  var cost = 0.0;
  if (fretted.isNotEmpty) {
    var lo = fretted.reduce(math.min), hi = fretted.reduce(math.max);
    var span = hi - lo;
    cost += span * 4 + (span > 4 ? (span - 4) * 20 : 0);
    var at = fretted.reduce((a, b) => a + b) / fretted.length;
    cost += near == null ? at * 0.6 : (at - near).abs() * 1.2;
  }
  // An open string is free low on the neck; up it, the hand would rather
  // stay where it is.
  if (near != null && near > 4) {
    for (var (_, f) in places) {
      if (f == 0) cost += near * 0.5;
    }
  }
  // Strings crossed against the notes' order cost a little.
  for (var i = 1; i < places.length; i++) {
    if (places[i].$1 < places[i - 1].$1) cost += 3;
  }
  return cost;
}

/// _hand is where a hand holding [places] is: the middle of its fretted
/// notes, or [was] for open strings alone.
double? _hand(List<FretPlace> places, double? was) {
  var fretted = [
    for (var (_, f) in places)
      if (f > 0) f
  ];
  if (fretted.isEmpty) return was;
  return fretted.reduce((a, b) => a + b) / fretted.length;
}

final Expando<(List<int>, List<FretPlace?>)> _fretted = Expando("fretting");

/// fretting is where each of [notes] is played on [strings], in order:
/// those starting together (a chord, or a strum's strings a moment apart)
/// placed together, each next group near where the hand was, and never on
/// a string still sounding from before. Kept for the same notes.
List<FretPlace?> fretting(List<MidiNote> notes, List<int> strings) {
  if (_fretted[notes] case (var s, var kept) when identical(s, strings)) {
    return kept;
  }
  var order = [for (var i = 0; i < notes.length; i++) i]
    ..sort((a, b) => notes[a].start.compareTo(notes[b].start));
  var out = List<FretPlace?>.filled(notes.length, null);
  double? hand;
  var i = 0;
  while (i < order.length) {
    // A group: starts each within a moment of the last.
    var group = [order[i]];
    var j = i + 1;
    while (j < order.length &&
        notes[order[j]].start - notes[order[j - 1]].start < 0.04) {
      group.add(order[j]);
      j++;
    }
    var start = notes[order[i]].start;
    var busy = <int>{
      for (var k in order.take(i))
        if (notes[k].end > start + 0.01 && out[k] != null) out[k]!.$1,
    };
    var places = neckPlaces([for (var g in group) notes[g].key], strings,
        near: hand, busy: busy);
    if (places.length < group.toSet().length && busy.isNotEmpty) {
      places =
          neckPlaces([for (var g in group) notes[g].key], strings, near: hand);
    }
    for (var g in group) {
      var key = notes[g].key;
      for (var p in places) {
        if (strings[p.$1] + p.$2 == key) {
          out[g] = p;
          break;
        }
      }
    }
    hand = _hand(places, hand);
    i = j;
  }
  _fretted[notes] = (strings, out);
  return out;
}

/// placesAt are where [part]'s notes sounding [seconds] in are played, by
/// key (see fretting).
Map<int, FretPlace> placesAt(InstrumentPart part, double seconds) {
  var strings = switch (part.look) {
    InstrumentLook.guitar => guitarStrings,
    InstrumentLook.bass => bassStrings,
    _ => null,
  };
  if (strings == null) return const {};
  var all = fretting(part.notes, strings);
  return {
    for (var (i, n) in part.notes.indexed)
      if (seconds >= n.start && seconds < n.end && all[i] != null)
        n.key: all[i]!,
  };
}
