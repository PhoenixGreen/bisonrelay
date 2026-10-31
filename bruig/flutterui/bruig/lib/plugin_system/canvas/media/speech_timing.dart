import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';

// speech_timing.dart is where a take's words are, for an engine that does
// not say: the voice's own pauses found, and matched in order to the stops,
// commas and beats written, the words between spread by their lengths
// across the time spoken. Spread by their lengths alone they drift -- by
// half a second, ten words on -- the pauses not being words. Both engines'
// takes are timed so, for lip sync and for Phrasing.

/// voicePauses is where the voice paused in [sound], at the mix rate: from
/// and to where it speaks, and each pause between, in seconds. A pause is
/// 60ms or more 20dB under its loud part -- the voice's own pauses are not
/// silent, but a breath's noise or a room's, and how loud that is goes
/// with how loud it speaks.
({double from, double to, List<(double, double)> pauses}) voicePauses(
    Float32List sound) {
  var db = _levels(sound);
  var heard = [
    for (var d in db)
      if (d > -60) d
  ]..sort();
  if (heard.isEmpty) return (from: 0, to: 0, pauses: const []);
  var under = heard[(heard.length * 0.9).floor()] - 20;
  var first = db.indexWhere((d) => d >= under);
  var last = db.lastIndexWhere((d) => d >= under);
  var pauses = <(double, double)>[];
  var start = -1, end = -1;
  for (var f = first; f <= last + 1; f++) {
    if (f <= last && db[f] < under) {
      if (start < 0) start = f;
      end = f + 1;
    } else if (start >= 0 && (f > last || f - end >= 2)) {
      // A blip of 20ms or less within it is the pause still.
      if (end - start >= 6) pauses.add((start * 0.01, end * 0.01));
      start = -1;
    }
  }
  return (from: first * 0.01, to: (last + 1) * 0.01, pauses: pauses);
}

/// _levels is [sound]'s loudness, in dB, each 10ms of it at the mix rate.
List<double> _levels(Float32List sound) => [
      for (var at = 0; at + 480 <= sound.length; at += 480)
        () {
          var sum = 0.0;
          for (var i = at; i < at + 480; i++) {
            sum += sound[i] * sound[i];
          }
          return 10 * math.log(sum / 480 + 1e-14) / math.ln10;
        }(),
    ];

/// timeWords is [words] -- a stretch's, as it was given them -- timed
/// across [sound], at the mix rate, and the pause after each the voice
/// paused after. The program says nothing of where its words are, and
/// spread by their lengths alone they drift: by half a second, ten words
/// on, the voice's pauses -- the longest at "...", a sentence's end -- not
/// being words. So its pauses are found, and matched in order to the
/// stops, commas and beats written: the words between spread by their
/// lengths across the time spoken, which no pause is in.
({List<TimedWord> words, Map<int, (double, double)> after}) timeWords(
    Float32List sound, List<String> words) {
  var (:from, :to, :pauses) = voicePauses(sound);
  if (words.isEmpty || to <= from) return (words: const [], after: const {});
  // The time spoken, and where in it each pause is.
  var at = <double>[];
  var spoken = 0.0, last = from;
  for (var (a, b) in pauses) {
    spoken += a - last;
    at.add(spoken);
    last = b;
  }
  spoken += to - last;
  // A word as long as its letters; a stop, a comma and a beat where the
  // voice should pause -- a beat most of all.
  var weights = [
    for (var w in words)
      w.replaceAll(RegExp(r"[^\p{L}\p{N}]", unicode: true), "").length + 1.0
  ];
  var total = weights.reduce((a, b) => a + b);
  var ends = <double>[];
  var sum = 0.0;
  for (var w in weights) {
    sum += w;
    ends.add(spoken * sum / total);
  }
  var stops = <(int, double)>[
    for (var (i, w) in words.indexed)
      if (i < words.length - 1 && RegExp(r"[,.;:!?…]$").hasMatch(w))
        (
          i,
          w.endsWith("...") || w.endsWith("…")
              ? 4.0
              : RegExp(r"[.!?]$").hasMatch(w)
                  ? 2.0
                  : 0.7
        ),
  ];
  // Matched in order, the cheapest way: a stop far from its pause costs,
  // as does a stop the voice did not pause at, by how much it should
  // have, and a pause nothing written is at, by its length.
  var n = stops.length, m = pauses.length;
  var cost = List.generate(n + 1, (_) => List.filled(m + 1, double.infinity));
  var back = List.generate(n + 1, (_) => List.filled(m + 1, 0));
  cost[0][0] = 0;
  for (var i = 0; i <= n; i++) {
    for (var j = 0; j <= m; j++) {
      var c = cost[i][j];
      if (c == double.infinity) continue;
      void step(int i2, int j2, double by, int how) {
        if (c + by < cost[i2][j2]) {
          cost[i2][j2] = c + by;
          back[i2][j2] = how;
        }
      }

      if (i < n) step(i + 1, j, stops[i].$2, 1);
      if (j < m) step(i, j + 1, (pauses[j].$2 - pauses[j].$1) / 0.15, 2);
      if (i < n && j < m) {
        var d = (ends[stops[i].$1] - at[j]) / 0.6;
        step(i + 1, j + 1, d * d, 3);
      }
    }
  }
  var matched = <int, int>{}; // a word, the pause after it
  for (var i = n, j = m; i > 0 || j > 0;) {
    switch (back[i][j]) {
      case 1:
        i--;
      case 2:
        j--;
      default:
        matched[stops[--i].$1] = --j;
    }
  }
  // The real time a moment of the time spoken is: after each pause before
  // it -- and the one at it, for a word starting there.
  double real(double t, {required bool starting}) {
    var r = from + t;
    for (var (k, p) in at.indexed) {
      if (p < t - 1e-9 || (starting && (p - t).abs() <= 1e-9)) {
        r += pauses[k].$2 - pauses[k].$1;
      }
    }
    return r;
  }

  // The words between two pauses matched spread across the time spoken
  // between them.
  var timed = <TimedWord>[];
  var first = 0;
  var since = 0.0;
  for (var i = 0; i < words.length; i++) {
    var k = matched[i];
    if (k == null && i < words.length - 1) continue;
    var until = k == null ? spoken : at[k];
    var share = 0.0;
    for (var w = first; w <= i; w++) {
      share += weights[w];
    }
    var t = since;
    for (var w = first; w <= i; w++) {
      var d = (until - since) * weights[w] / share;
      timed.add((
        text: words[w],
        start: real(t, starting: true),
        end: real(t + d, starting: false)
      ));
      t += d;
    }
    first = i + 1;
    since = until;
  }
  return (
    words: timed,
    after: {for (var e in matched.entries) e.key: pauses[e.value]},
  );
}

/// quietestNear is the quietest moment of [sound], at the mix rate, within
/// [within] seconds of [at]: where a beat goes that the voice did not
/// pause for, between two words rather than in one.
double quietestNear(Float32List sound, double at, {double within = 0.4}) {
  var db = _levels(sound);
  if (db.length < 3) return at.clamp(0, sound.length / 48000);
  var lo = ((at - within) * 100).floor().clamp(1, db.length - 2);
  var hi = ((at + within) * 100).ceil().clamp(1, db.length - 2);
  var best = lo, quietest = double.infinity;
  for (var f = lo; f <= hi; f++) {
    var level = db[f - 1] + db[f] + db[f + 1];
    if (level < quietest) {
      quietest = level;
      best = f;
    }
  }
  return (best + 0.5) * 0.01;
}
