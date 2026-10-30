import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/pitch.dart';
import 'package:bruig/plugin_system/canvas/media/warp.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_warp_test.dart is warping: a sound laid on the song's beats --
// longer or shorter, its pitch kept -- or moved in pitch, its length kept;
// and a sound's hits and tempo heard.

const double rate = 48000;

/// tone is [seconds] of a voice-like note at [hz].
Float32List tone(double hz, double seconds) {
  var n = (seconds * rate).round();
  var x = Float32List(n);
  for (var i = 0; i < n; i++) {
    var t = i / rate;
    for (var h = 1; h <= 4; h++) {
      x[i] += 0.3 / h * math.sin(2 * math.pi * hz * h * t);
    }
  }
  return x;
}

/// clicks are [seconds] of a short burst on every beat at [bpm].
Float32List clicks(double bpm, double seconds) {
  var x = Float32List((seconds * rate).round());
  var every = 60 / bpm;
  for (var t = 0.0; t < seconds; t += every) {
    var at = (t * rate).round();
    for (var k = 0; k < 480 && at + k < x.length; k++) {
      x[at + k] = 0.8 * math.exp(-k / 60) * math.sin(k * 0.9);
    }
  }
  return x;
}

double pitchAt(Float32List x, double second) {
  var from = (second * rate).round();
  return detectPitch(Float32List.sublistView(x, from, from + 2048))!.hz;
}

void main() {
  test("a warp map goes through its markers, and on at its tempo", () {
    var map = WarpMap(120, [(seconds: 1, beat: 4)]);
    expect(map.beatAt(0.5), closeTo(2, 1e-9));
    expect(map.beatAt(1), closeTo(4, 1e-9));
    expect(map.beatAt(2), closeTo(6, 1e-9), reason: "two a second past it");
    expect(map.sourceAt(5), closeTo(1.5, 1e-9));
    // A marker behind its neighbour is left out.
    expect(WarpMap(120, [(seconds: 2, beat: 1), (seconds: 1, beat: 3)]).points,
        hasLength(2));
  });

  // A two-second note at 120, laid on a song at 80: half as long again.
  for (var mode in [WarpMode.tones, WarpMode.complex, WarpMode.texture]) {
    test("${mode.label} keeps its pitch, stretched", () {
      var x = tone(220, 2);
      var (l, r) = renderWarp(x, x,
          from: 0,
          to: 2,
          warp: true,
          mode: mode,
          map: WarpMap(120, const []),
          secondsPerBeat: 60 / 80);
      expect(l.length / rate, closeTo(3, 0.01));
      expect(pitchAt(l, 1.5), closeTo(220, 3), reason: mode.label);
      expect(r[(1.5 * rate).round()], closeTo(l[(1.5 * rate).round()], 0.05),
          reason: "the same on both sides");
      var level = l.sublist(48000, 96000).map((v) => v.abs()).reduce(math.max);
      expect(level, inInclusiveRange(0.25, 0.8), reason: "about as loud");
    });
  }

  test("moved up an octave, the same length", () {
    var x = tone(220, 2);
    var (l, _) = renderWarp(x, x,
        from: 0,
        to: 2,
        warp: true,
        mode: WarpMode.complex,
        map: WarpMap(120, const []),
        secondsPerBeat: 0.5,
        semitones: 12);
    expect(l.length / rate, closeTo(2, 0.01));
    expect(pitchAt(l, 1), closeTo(440, 6));
  });

  test("Re-pitch is faster and higher together; unwarped, so is pitch", () {
    var x = tone(220, 2);
    var (l, _) = renderWarp(x, x,
        from: 0,
        to: 2,
        warp: true,
        mode: WarpMode.repitch,
        map: WarpMap(120, const []),
        secondsPerBeat: 60 / 240);
    expect(l.length / rate, closeTo(1, 0.01));
    expect(pitchAt(l, 0.5), closeTo(440, 6));
    var (u, _) = renderWarp(x, x,
        from: 0,
        to: 2,
        warp: false,
        mode: WarpMode.complex,
        map: WarpMap(120, const []),
        secondsPerBeat: 0.5,
        semitones: -12);
    expect(u.length / rate, closeTo(4, 0.01));
    expect(pitchAt(u, 2), closeTo(110, 2));
  });

  test("Beats puts each hit on its new beat, played as it was", () {
    var x = clicks(120, 4);
    var (l, _) = renderWarp(x, x,
        from: 0,
        to: 4,
        warp: true,
        mode: WarpMode.beats,
        map: WarpMap(120, const []),
        secondsPerBeat: 1); // at 60: twice as long
    expect(l.length / rate, closeTo(8, 0.01));
    // Hits a second apart now, each as sharp as it was.
    for (var beat = 1; beat < 7; beat++) {
      var at = (beat * rate).round();
      var hit = l.sublist(at, at + 200).map((v) => v.abs()).reduce(math.max);
      var between = l
          .sublist(at + 24000, at + 24200)
          .map((v) => v.abs())
          .reduce(math.max);
      expect(hit, greaterThan(0.3), reason: "a hit at $beat s");
      expect(between, lessThan(0.01), reason: "quiet between, at $beat.5 s");
    }
  });

  test("its hits and its tempo are heard", () {
    var x = clicks(128, 8);
    var hits = onsets(x, x);
    expect(hits.length, inInclusiveRange(15, 18));
    expect(hits[1] - hits[0], closeTo(60 / 128, 0.02));
    expect(estimateTempo(x, x, near: 120), closeTo(128, 1.5));
    // A loop of exactly four bars at 93: that, not a near guess.
    var loop = clicks(93, 4 * 4 * 60 / 93);
    expect(estimateTempo(loop, loop, near: 120), closeTo(93, 0.01));
  });
}
