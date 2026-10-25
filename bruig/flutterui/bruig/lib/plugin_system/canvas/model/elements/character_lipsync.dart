import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/canvas_cues.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';

// character_lipsync.dart is a voice-over turned into mouths: which shape,
// from which frame.
//
// Two ways, for two kinds of recording. With the words heard (whisper, the
// same hearing the Cues use), each word is spelt into the shapes its sounds
// make and its time shared between them. With nothing but the sound, the
// loudness of each frame chooses how open the mouth is -- rougher, but it
// works in any language and with nothing installed.
//
// Either way the result is a list of mouths, each holding until the next,
// tidied the way an animator would: nothing shorter than a couple of frames
// (it flickers), the mouth moving a frame before the sound (the eye expects
// the shape before the ear hears it), and a closed mouth for M, B and P
// never dropped, because a "b" without the lips meeting is the one mistake
// everybody sees.

/// MouthKey is one mouth, from [frame] until the next.
typedef MouthKey = ({int frame, MouthShape shape});

/// LipSyncFeel is how the mouths are tidied.
class LipSyncFeel {
  /// shortest is the fewest frames a mouth is held for.
  final int shortest;

  /// lead is how many frames ahead of the sound a mouth changes.
  final int lead;

  /// pause is the gap between words, in seconds, that the mouth rests in.
  final double pause;

  const LipSyncFeel({this.shortest = 2, this.lead = 1, this.pause = 0.25});
}

/// mouthsOfWord is the shapes [word] is said with, in order, from its
/// spelling. English spelling is not English sound, but the mouth shapes
/// are few and forgiving: what matters is where the lips close, where they
/// round, where the teeth show and how wide the vowels open.
List<MouthShape> mouthsOfWord(String word) {
  var w = word.toLowerCase().replaceAll(RegExp(r"[^a-z]"), "");
  // A final silent e: "make", "home", "time" -- but not "the" or "be".
  if (w.length > 3 && w.endsWith("e") && !_vowel(w[w.length - 2])) {
    w = w.substring(0, w.length - 1);
  }
  var out = <MouthShape>[];
  var i = 0;
  while (i < w.length) {
    var matched = false;
    for (var (spelt, shapes) in _rules) {
      if (w.startsWith(spelt, i)) {
        out.addAll(shapes);
        i += spelt.length;
        matched = true;
        break;
      }
    }
    if (!matched) i++;
  }
  // The same shape twice in a row is one shape held.
  var merged = <MouthShape>[];
  for (var s in out) {
    if (merged.isEmpty || merged.last != s) merged.add(s);
  }
  return merged;
}

bool _vowel(String c) => "aeiou".contains(c);

const _a = MouthShape.closed,
    _b = MouthShape.teeth,
    _c = MouthShape.open,
    _d = MouthShape.wide,
    _e = MouthShape.round,
    _f = MouthShape.pucker,
    _g = MouthShape.lip,
    _h = MouthShape.tongue;

/// _rules is how spellings sound, longest first so "ough" is tried before
/// "ou" and "o". A spelling with no shapes is said without moving the mouth
/// from the last one.
const List<(String, List<MouthShape>)> _rules = [
  ("ough", [_e]),
  ("augh", [_e]),
  ("eigh", [_c]),
  ("tion", [_b, _c, _b]),
  ("sion", [_b, _c, _b]),
  ("igh", [_d]),
  ("qu", [_b, _f]),
  ("th", [_b]),
  ("sh", [_b]),
  ("ch", [_b]),
  ("ck", [_b]),
  ("ng", [_b]),
  ("ph", [_g]),
  ("wh", [_f]),
  ("ll", [_h]),
  ("ee", [_b]),
  ("ea", [_b]),
  ("ie", [_b]),
  ("ey", [_b]),
  ("oo", [_f]),
  ("ou", [_d, _f]),
  ("ow", [_e, _f]),
  ("oi", [_e, _b]),
  ("oy", [_e, _b]),
  ("oa", [_e, _f]),
  ("au", [_e]),
  ("aw", [_e]),
  ("ai", [_c]),
  ("ay", [_c]),
  ("ew", [_f]),
  ("ue", [_f]),
  ("er", [_e]),
  ("ir", [_e]),
  ("ur", [_e]),
  ("ar", [_d]),
  ("or", [_e]),
  ("a", [_c]),
  ("e", [_c]),
  ("i", [_b]),
  ("o", [_e]),
  ("u", [_c]),
  ("y", [_b]),
  ("m", [_a]),
  ("b", [_a]),
  ("p", [_a]),
  ("f", [_g]),
  ("v", [_g]),
  ("w", [_f]),
  ("l", [_h]),
  ("r", [_e]),
  ("c", [_b]),
  ("d", [_b]),
  ("g", [_b]),
  ("j", [_b]),
  ("k", [_b]),
  ("n", [_b]),
  ("q", [_b]),
  ("s", [_b]),
  ("t", [_b]),
  ("x", [_b]),
  ("z", [_b]),
  ("h", []),
];

/// _weight is how long a shape is held, against the others in its word:
/// vowels are the long part of a syllable.
int _weight(MouthShape s) => switch (s) {
      MouthShape.open || MouthShape.wide || MouthShape.round => 3,
      MouthShape.pucker || MouthShape.tongue => 2,
      _ => 1,
    };

bool _isVowel(MouthShape s) =>
    s == MouthShape.open || s == MouthShape.wide || s == MouthShape.round;

/// mouthsFromWords is the mouths for [words], in their own frames, tidied
/// by [feel] at [frameRate].
List<MouthKey> mouthsFromWords(List<SpokenWord> words,
    {required int frameRate, LipSyncFeel feel = const LipSyncFeel()}) {
  var out = <MouthKey>[];
  var pause = (feel.pause * frameRate).round();
  for (var (i, w) in words.indexed) {
    var length = math.max(1, w.end - w.frame);
    var shapes = mouthsOfWord(w.text);
    if (shapes.isEmpty) continue;
    // Too many shapes for the time: keep the closures and the vowels, which
    // are what the eye reads, and drop the rest.
    var most = math.max(1, length ~/ math.max(1, feel.shortest));
    if (shapes.length > most) {
      var kept = [
        for (var s in shapes)
          if (s == MouthShape.closed || _isVowel(s)) s,
      ];
      shapes = kept.isEmpty ? [shapes.first] : kept;
      if (shapes.length > most) {
        shapes = [
          for (var (j, s) in shapes.indexed)
            if (j * most ~/ shapes.length != (j - 1) * most ~/ shapes.length ||
                j == 0)
              s,
        ].take(most).toList();
      }
    }
    var total = shapes.fold(0, (n, s) => n + _weight(s));
    var at = w.frame.toDouble();
    for (var s in shapes) {
      out.add((frame: at.round(), shape: s));
      at += length * _weight(s) / total;
    }
    // Rest after the word, unless the next follows on closely.
    var next = i + 1 < words.length ? words[i + 1].frame : null;
    if (next == null || next - w.end >= pause) {
      out.add((frame: w.end, shape: MouthShape.rest));
    }
  }
  return tidyMouths(out, feel);
}

/// mouthsFromLoudness is the mouths for a recording whose shape is [peaks]
/// -- loudness from nought to one, evenly across [seconds] -- starting at
/// [startFrame], tidied by [feel] at [frameRate].
///
/// Louder is more open. Where the voice dips sharply for a moment in the
/// middle of speech the lips are closed, which is where the m's, b's and
/// p's mostly are; a long stretch at one loudness is broken into two shapes
/// so a held vowel does not freeze the face.
List<MouthKey> mouthsFromLoudness(Float32List peaks, double seconds,
    {required int startFrame,
    required int frameRate,
    LipSyncFeel feel = const LipSyncFeel()}) {
  if (peaks.isEmpty || seconds <= 0) return const [];
  var frames = (seconds * frameRate).ceil();
  var per = peaks.length / frames;
  var level = List<double>.filled(frames, 0);
  var loudest = 0.0;
  for (var f = 0; f < frames; f++) {
    var a = (f * per).floor(), b = math.max(a + 1, ((f + 1) * per).floor());
    var v = 0.0;
    for (var i = a; i < b && i < peaks.length; i++) {
      v = math.max(v, peaks[i]);
    }
    level[f] = v;
    loudest = math.max(loudest, v);
  }
  if (loudest <= 0) return const [];
  var out = <MouthKey>[];
  var held = 0;
  MouthShape? last;
  for (var f = 0; f < frames; f++) {
    var v = level[f] / loudest;
    MouthShape s;
    if (v < 0.08) {
      s = MouthShape.rest;
    } else if (f > 0 &&
        f + 1 < frames &&
        v < 0.45 * level[f - 1] / loudest &&
        v < 0.45 * level[f + 1] / loudest) {
      s = MouthShape.closed;
    } else if (v < 0.25) {
      s = MouthShape.teeth;
    } else if (v < 0.5) {
      s = MouthShape.open;
    } else if (v < 0.75) {
      s = MouthShape.round;
    } else {
      s = MouthShape.wide;
    }
    if (s == last && s != MouthShape.rest && ++held >= 6) {
      // Held open too long: a second shape of about the same size.
      s = s == MouthShape.wide || s == MouthShape.round
          ? MouthShape.open
          : MouthShape.round;
      held = 0;
    } else if (s != last) {
      held = 0;
    }
    if (s != last) out.add((frame: startFrame + f, shape: s));
    last = s;
  }
  if (last != MouthShape.rest) {
    out.add((frame: startFrame + frames, shape: MouthShape.rest));
  }
  return tidyMouths(out, feel);
}

/// tidyMouths is [keys] in order, led by [feel.lead] frames, with every
/// mouth held for at least [feel.shortest] -- a mouth too short is dropped,
/// unless it closes the lips, in which case the one before it gives way --
/// and the same shape twice in a row made one.
List<MouthKey> tidyMouths(List<MouthKey> keys, LipSyncFeel feel) {
  var sorted = [
    for (var k in keys) (frame: math.max(0, k.frame - feel.lead), shape: k.shape),
  ]..sort((a, b) => a.frame.compareTo(b.frame));
  var out = <MouthKey>[];
  for (var k in sorted) {
    if (out.isNotEmpty && out.last.frame == k.frame) {
      // Two on one frame: the later wins, unless the earlier closes the lips.
      if (out.last.shape != MouthShape.closed) out.removeLast();
      if (out.isNotEmpty && out.last.frame == k.frame) continue;
    }
    if (out.isNotEmpty && k.frame - out.last.frame < feel.shortest) {
      if (k.shape == MouthShape.closed && out.last.shape != MouthShape.closed) {
        // The closure stays; the shape it cut short goes.
        out.removeLast();
      } else if (out.last.shape == MouthShape.closed) {
        // Let the closure be held its frames: this one starts after it.
        k = (frame: out.last.frame + feel.shortest, shape: k.shape);
      } else {
        continue;
      }
    }
    if (out.isNotEmpty && out.last.shape == k.shape) continue;
    out.add(k);
  }
  return out;
}
