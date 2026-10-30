import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/instrument.dart'
    show ControlPoint;
import 'package:bruig/plugin_system/canvas/model/session.dart';

// warp.dart is warping: a sound laid on the song's beats, faster or slower
// than it was recorded, without its pitch moving -- and moved in pitch
// without its speed changing. Ableton's warp modes, each the way that
// suits a kind of sound:
//
//  - Beats: cut at its hits, each piece played as it was, where its hit
//    falls on the beat. Drums stay sharp; slowed down, gaps open after
//    each hit.
//  - Tones: WSOLA -- the sound overlapped from pieces a few hundredths of
//    a second long, each chosen to join the last where it fits best. One
//    voice or instrument at a time.
//  - Texture: a phase vocoder with a long window, its phases loosened a
//    little: pads, noise, washes.
//  - Complex: a phase vocoder with its phases locked to the peaks they
//    belong to, and set afresh at each hit: whole mixes and vocals.
//  - Re-pitch: read faster or slower, as a record is: speed is pitch.
//
// It is done ahead of time, not as it plays: a warped clip is rendered into
// a file of its own, at the song's tempo, as a MIDI clip's notes are -- see
// CanvasController.
//
// Everything here works on both sides at once, so the stereo picture is
// kept: one choice of where to read, for both.

const double _rate = 48000;

/// renderWarp is [l] and [r] (at 48kHz) from [from] to [to] seconds,
/// warped by [clip]: laid on the song's beats at [secondsPerBeat] by its
/// warp map, in its mode, and moved [semitones] in pitch. Unwarped, it is
/// only moved in pitch -- re-pitched, so faster or slower with it.
(Float32List, Float32List) renderWarp(
  Float32List l,
  Float32List r, {
  required double from,
  required double to,
  required bool warp,
  required WarpMode mode,
  required WarpMap map,
  required double secondsPerBeat,
  double semitones = 0,
  Map<ClipEnvelope, List<ControlPoint>> envelopes = const {},
}) {
  var (ol, or) = _warped(l, r,
      from: from,
      to: to,
      warp: warp,
      mode: mode,
      map: map,
      secondsPerBeat: secondsPerBeat,
      semitones: semitones);
  _envelop(ol, or, envelopes, secondsPerBeat);
  return (ol, or);
}

/// _envelop applies [envelopes] to [l] and [r] -- the clip's sound from its
/// first beat, at [secondsPerBeat] -- in place: its gain, squared so half
/// way is well down (twelve decibels), and its pan as a balance.
void _envelop(Float32List l, Float32List r,
    Map<ClipEnvelope, List<ControlPoint>> envelopes, double secondsPerBeat) {
  var gain = envelopes[ClipEnvelope.gain] ?? const [];
  var pan = envelopes[ClipEnvelope.pan] ?? const [];
  if (gain.isEmpty && pan.isEmpty) return;
  var spb = math.max(1e-3, secondsPerBeat);
  for (var i = 0; i < l.length; i++) {
    var beat = i / _rate / spb;
    var g = curveAt(gain, beat, 1);
    var level = g * g;
    var p = curveAt(pan, beat, 0.5);
    l[i] *= level * (p > 0.5 ? 2 * (1 - p) : 1);
    r[i] *= level * (p < 0.5 ? 2 * p : 1);
  }
}

(Float32List, Float32List) _warped(
  Float32List l,
  Float32List r, {
  required double from,
  required double to,
  required bool warp,
  required WarpMode mode,
  required WarpMap map,
  required double secondsPerBeat,
  double semitones = 0,
}) {
  var a = (from * _rate).round().clamp(0, l.length);
  var b = (to * _rate).round().clamp(a, l.length);
  var sl = Float32List.sublistView(l, a, b);
  var sr = Float32List.sublistView(r, a, b);
  var length = (b - a) / _rate;
  var p = math.pow(2, semitones / 12).toDouble();
  if (!warp) {
    // As it is -- a copy, to be changed -- or re-pitched: read p times as
    // fast.
    if (p == 1) return (Float32List.fromList(sl), Float32List.fromList(sr));
    return _readAlong(sl, sr, (length / p * _rate).round(), (u) => u * p);
  }
  var spb = math.max(1e-3, secondsPerBeat);
  var outLength = map.beatAt(length) * spb;
  double source(double u) => map.sourceAt(u / spb).clamp(0, length);
  switch (mode) {
    case WarpMode.repitch:
      return _readAlong(sl, sr, (outLength * _rate).round(), source);
    case WarpMode.beats:
      return _beats(sl, sr, outLength, source, map, spb, p);
    case WarpMode.tones || WarpMode.texture || WarpMode.complex:
      // Stretched p times longer than wanted, then read p times as fast:
      // the length wanted, p higher.
      double longer(double v) => source(v / p);
      var stretched = mode == WarpMode.tones
          ? _wsola(sl, sr, (outLength * p * _rate).round(), longer)
          : _vocoder(sl, sr, (outLength * p * _rate).round(), longer,
              texture: mode == WarpMode.texture);
      if (p == 1) return stretched;
      var (xl, xr) = stretched;
      return _readAlong(xl, xr, (outLength * _rate).round(), (u) => u * p);
  }
}

// ---------------------------------------------------------------------------
// Reading at another speed
// ---------------------------------------------------------------------------

const int _sincHalf = 12;

/// _readAlong is [n] samples read from [l] and [r] at [at] seconds for each
/// output's second: between samples by a windowed sinc, its cut-off lowered
/// where it reads faster than it was recorded, so the highs do not fold
/// back down.
(Float32List, Float32List) _readAlong(
    Float32List l, Float32List r, int n, double Function(double u) at) {
  var ol = Float32List(n), or = Float32List(n);
  if (l.isEmpty) return (ol, or);
  var last = at(0) * _rate;
  for (var i = 0; i < n; i++) {
    var pos = at(i / _rate) * _rate;
    var speed = math.max(1.0, (pos - last).abs());
    last = pos;
    var cut = 1 / speed;
    var base = pos.floor();
    var frac = pos - base;
    var vl = 0.0, vr = 0.0, sum = 0.0;
    for (var k = -_sincHalf + 1; k <= _sincHalf; k++) {
      var j = base + k;
      if (j < 0 || j >= l.length) continue;
      var t = k - frac;
      var x = t * cut;
      var sinc = x.abs() < 1e-9 ? 1.0 : math.sin(math.pi * x) / (math.pi * x);
      var w = 0.5 + 0.5 * math.cos(math.pi * t / _sincHalf);
      var g = sinc * w * cut;
      vl += l[j] * g;
      vr += r[j] * g;
      sum += g;
    }
    // Kept at level where the edge cut the sinc short.
    if (sum.abs() > 1e-6 &&
        (base < _sincHalf || base >= l.length - _sincHalf)) {
      vl /= sum / cut;
      vr /= sum / cut;
    }
    ol[i] = vl;
    or[i] = vr;
  }
  return (ol, or);
}

// ---------------------------------------------------------------------------
// Beats
// ---------------------------------------------------------------------------

/// _beats lays each hit where the map puts it, played as it was -- p times
/// as fast, for its pitch -- until the next hit, or the next hit's place,
/// whichever comes first; faded out there, so it does not click.
(Float32List, Float32List) _beats(
    Float32List l,
    Float32List r,
    double outLength,
    double Function(double u) source,
    WarpMap map,
    double spb,
    double p) {
  var n = (outLength * _rate).round();
  var ol = Float32List(n), or = Float32List(n);
  var length = l.length / _rate;
  var hits = [0.0, ...onsets(l, r).where((t) => t > 0.02), length];
  const fadeOut = 0.004, fadeIn = 0.0005;
  for (var i = 0; i + 1 < hits.length; i++) {
    var s0 = hits[i], s1 = hits[i + 1];
    var u0 = map.beatAt(s0) * spb, u1 = map.beatAt(s1) * spb;
    // As long as its own piece, read p times as fast, or as its place.
    var span = math.min((s1 - s0) / p, u1 - u0);
    if (span <= 0) continue;
    var start = (u0 * _rate).round();
    var count = (span * _rate).round();
    var (pl, pr) = _readAlong(l, r, count, (u) => s0 + u * p);
    for (var k = 0; k < count && start + k < n; k++) {
      var t = k / _rate;
      var g = math.min(1.0, t / fadeIn) * math.min(1.0, (span - t) / fadeOut);
      if (start + k < 0) continue;
      ol[start + k] += pl[k] * g;
      or[start + k] += pr[k] * g;
    }
  }
  return (ol, or);
}

// ---------------------------------------------------------------------------
// Tones: WSOLA
// ---------------------------------------------------------------------------

const int _wsolaN = 1024;
const int _wsolaHop = _wsolaN ~/ 2;
const int _wsolaTolerance = 256;

/// _wsola is [n] samples of [l] and [r], each piece of [_wsolaN] read from
/// where [at] says, moved by up to [_wsolaTolerance] to where it best
/// carries on from the last piece -- so the voice's waves join.
(Float32List, Float32List) _wsola(
    Float32List l, Float32List r, int n, double Function(double u) at) {
  var ol = Float32List(n + _wsolaN), or = Float32List(n + _wsolaN);
  var weight = Float32List(n + _wsolaN);
  var window = Float32List(_wsolaN);
  for (var i = 0; i < _wsolaN; i++) {
    window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / _wsolaN);
  }
  var mono = Float32List(l.length);
  for (var i = 0; i < l.length; i++) {
    mono[i] = (l[i] + r[i]) * 0.5;
  }
  double sample(Float32List x, int i) => i >= 0 && i < x.length ? x[i] : 0;
  int? last;
  for (var out = 0; out < n; out += _wsolaHop) {
    var want = (at(out / _rate) * _rate).round();
    var best = want;
    if (last != null) {
      // Where the last piece would naturally have gone on to.
      var natural = last + _wsolaHop;
      // Coarse, every fourth place and every eighth sample; then fine,
      // every place near the best and every sample.
      double score(int d, int step) {
        var s = 0.0;
        for (var k = 0; k < _wsolaN; k += step) {
          s += sample(mono, want + d + k) * sample(mono, natural + k);
        }
        return s;
      }

      var bestScore = double.negativeInfinity;
      var bestD = 0;
      for (var d = -_wsolaTolerance; d <= _wsolaTolerance; d += 4) {
        var s = score(d, 8);
        if (s > bestScore) {
          bestScore = s;
          bestD = d;
        }
      }
      var coarse = bestD;
      bestScore = double.negativeInfinity;
      for (var d = coarse - 3; d <= coarse + 3; d++) {
        var s = score(d, 1);
        if (s > bestScore) {
          bestScore = s;
          bestD = d;
        }
      }
      best = want + bestD;
    }
    for (var k = 0; k < _wsolaN; k++) {
      var w = window[k];
      ol[out + k] += sample(l, best + k) * w;
      or[out + k] += sample(r, best + k) * w;
      weight[out + k] += w;
    }
    last = best;
  }
  for (var i = 0; i < n; i++) {
    if (weight[i] > 1e-3) {
      ol[i] /= weight[i];
      or[i] /= weight[i];
    }
  }
  return (Float32List.sublistView(ol, 0, n), Float32List.sublistView(or, 0, n));
}

// ---------------------------------------------------------------------------
// Complex and Texture: a phase vocoder
// ---------------------------------------------------------------------------

/// _Fft is a complex FFT of one size, its tables made once.
class _Fft {
  final int n;
  final Int32List _flip;
  final Float64List _cos, _sin;

  _Fft(this.n)
      : _flip = Int32List(n),
        _cos = Float64List(n ~/ 2),
        _sin = Float64List(n ~/ 2) {
    var bits = 0;
    while ((1 << bits) < n) {
      bits++;
    }
    for (var i = 0; i < n; i++) {
      var j = 0;
      for (var b = 0; b < bits; b++) {
        if (i & (1 << b) != 0) j |= 1 << (bits - 1 - b);
      }
      _flip[i] = j;
    }
    for (var k = 0; k < n ~/ 2; k++) {
      _cos[k] = math.cos(2 * math.pi * k / n);
      _sin[k] = math.sin(2 * math.pi * k / n);
    }
  }

  /// run transforms [re] and [im] in place: forward, or [inverse] (then
  /// scaled by 1/n).
  void run(Float64List re, Float64List im, {bool inverse = false}) {
    for (var i = 0; i < n; i++) {
      var j = _flip[i];
      if (i < j) {
        var t = re[i];
        re[i] = re[j];
        re[j] = t;
        t = im[i];
        im[i] = im[j];
        im[j] = t;
      }
    }
    var sign = inverse ? 1.0 : -1.0;
    for (var len = 2; len <= n; len <<= 1) {
      var half = len >> 1, step = n ~/ len;
      for (var i = 0; i < n; i += len) {
        for (var k = 0; k < half; k++) {
          var c = _cos[k * step], s = sign * _sin[k * step];
          var a = i + k, b = a + half;
          var tr = re[b] * c - im[b] * s, ti = re[b] * s + im[b] * c;
          re[b] = re[a] - tr;
          im[b] = im[a] - ti;
          re[a] += tr;
          im[a] += ti;
        }
      }
    }
    if (inverse) {
      for (var i = 0; i < n; i++) {
        re[i] /= n;
        im[i] /= n;
      }
    }
  }
}

double _wrap(double a) => a - 2 * math.pi * (a / (2 * math.pi)).roundToDouble();

/// _vocoder is [n] samples of [l] and [r] read where [at] says, frame by
/// frame through their spectra: each partial's phase carried on from the
/// frame before at the frequency it is heard at, so it sounds unbroken
/// whatever the speed. Complex: phases locked to the peak each bin belongs
/// to, and set afresh at a hit. [texture]: a longer window, peaks not
/// locked, phases loosened a little.
(Float32List, Float32List) _vocoder(
    Float32List l, Float32List r, int n, double Function(double u) at,
    {bool texture = false}) {
  var size = texture ? 8192 : 4096;
  var hop = size ~/ 4;
  var fft = _Fft(size);
  var half = size ~/ 2;
  var window = Float64List(size);
  for (var i = 0; i < size; i++) {
    window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / size);
  }
  // Hann, a quarter apart, twice over: the windows' squares sum to 1.5.
  const overlap = 1.5;
  var ol = Float32List(n + size), or = Float32List(n + size);
  var phaseL = Float64List(half + 1), phaseR = Float64List(half + 1);
  var dice = math.Random(7);
  double sample(Float32List x, int i) => i >= 0 && i < x.length ? x[i] : 0;

  // One frame of both sides, at [pos]: left as real, right as imaginary,
  // one transform for both.
  var re = Float64List(size), im = Float64List(size);
  (Float64List, Float64List, Float64List, Float64List) frame(int pos) {
    for (var i = 0; i < size; i++) {
      re[i] = sample(l, pos + i) * window[i];
      im[i] = sample(r, pos + i) * window[i];
    }
    fft.run(re, im);
    var magL = Float64List(half + 1), argL = Float64List(half + 1);
    var magR = Float64List(half + 1), argR = Float64List(half + 1);
    for (var k = 0; k <= half; k++) {
      var j = (size - k) % size;
      // L = (X[k] + conj X[n-k]) / 2;  R = (X[k] - conj X[n-k]) / 2i.
      var lr = (re[k] + re[j]) / 2, li = (im[k] - im[j]) / 2;
      var rr = (im[k] + im[j]) / 2, ri = (re[j] - re[k]) / 2;
      magL[k] = math.sqrt(lr * lr + li * li);
      argL[k] = math.atan2(li, lr);
      magR[k] = math.sqrt(rr * rr + ri * ri);
      argR[k] = math.atan2(ri, rr);
    }
    return (magL, argL, magR, argR);
  }

  var energyBefore = 0.0;
  var first = true;
  for (var out = 0; out < n; out += hop) {
    var pos = (at(out / _rate) * _rate).round();
    var (magL, argL, magR, argR) = frame(pos);
    var (_, prevL, _, prevR) = frame(pos - hop);
    // A hit: much louder than the frame a hop before -- its phases taken
    // as they are, so the attack stays sharp.
    var energy = 0.0;
    for (var k = 0; k <= half; k++) {
      energy += magL[k] * magL[k] + magR[k] * magR[k];
    }
    var hit = !texture && energy > energyBefore * 4 && energy > 1e-6;
    energyBefore = energy;
    // Texture's loosening, the same on both sides: they stay together.
    var jitter = texture
        ? Float64List.fromList(
            [for (var k = 0; k <= half; k++) (dice.nextDouble() - 0.5) * 0.6])
        : null;
    for (var (mag, arg, prev, phase) in [
      (magL, argL, prevL, phaseL),
      (magR, argR, prevR, phaseR),
    ]) {
      if (first || hit) {
        for (var k = 0; k <= half; k++) {
          phase[k] = arg[k];
        }
        continue;
      }
      // Each bin's frequency as heard, from how far its phase went in a
      // hop; carried on that far.
      var advance = Float64List(half + 1);
      for (var k = 0; k <= half; k++) {
        var expected = 2 * math.pi * k * hop / size;
        advance[k] = expected + _wrap(arg[k] - prev[k] - expected);
      }
      if (texture) {
        for (var k = 0; k <= half; k++) {
          phase[k] = _wrap(phase[k] + advance[k] + jitter![k]);
        }
        continue;
      }
      // Locked: a peak's phase carried on; each bin round it kept where
      // it was against the peak.
      var peaks = <int>[];
      for (var k = 2; k < half - 1; k++) {
        if (mag[k] > mag[k - 1] &&
            mag[k] >= mag[k + 1] &&
            mag[k] > mag[k - 2] &&
            mag[k] >= mag[k + 2]) {
          peaks.add(k);
        }
      }
      var next = Float64List(half + 1);
      if (peaks.isEmpty) {
        for (var k = 0; k <= half; k++) {
          next[k] = _wrap(phase[k] + advance[k]);
        }
      } else {
        var p = 0;
        for (var k = 0; k <= half; k++) {
          while (p + 1 < peaks.length &&
              (peaks[p + 1] - k).abs() <= (peaks[p] - k).abs()) {
            p++;
          }
          var peak = peaks[p];
          var peakPhase = phase[peak] + advance[peak];
          next[k] = _wrap(peakPhase + arg[k] - arg[peak]);
        }
      }
      phase.setAll(0, next);
    }
    first = false;
    // Back to sound: left as real, right as imaginary, again.
    for (var k = 0; k <= half; k++) {
      var lr = magL[k] * math.cos(phaseL[k]),
          li = magL[k] * math.sin(phaseL[k]);
      var rr = magR[k] * math.cos(phaseR[k]),
          ri = magR[k] * math.sin(phaseR[k]);
      // Y = L + iR, with the conjugate mirror for the other half.
      re[k] = lr - ri;
      im[k] = li + rr;
      if (k > 0 && k < half) {
        re[size - k] = lr + ri;
        im[size - k] = -li + rr;
      }
    }
    fft.run(re, im, inverse: true);
    for (var i = 0; i < size && out + i < ol.length; i++) {
      var w = window[i] / overlap;
      ol[out + i] += re[i] * w;
      or[out + i] += im[i] * w;
    }
  }
  return (Float32List.sublistView(ol, 0, n), Float32List.sublistView(or, 0, n));
}

// ---------------------------------------------------------------------------
// Hearing hits, and a tempo
// ---------------------------------------------------------------------------

const int _onsetSize = 1024;
const int _onsetHop = 512;

/// _flux is how much louder each hop's spectrum got than the hop before's,
/// summed over its bins: high where something is struck.
Float64List _flux(Float32List l, Float32List r) {
  var fft = _Fft(_onsetSize);
  var frames = math.max(0, (l.length - _onsetSize) ~/ _onsetHop + 1);
  var out = Float64List(frames);
  var before = Float64List(_onsetSize ~/ 2);
  var re = Float64List(_onsetSize), im = Float64List(_onsetSize);
  for (var f = 0; f < frames; f++) {
    var at = f * _onsetHop;
    for (var i = 0; i < _onsetSize; i++) {
      var w = 0.5 - 0.5 * math.cos(2 * math.pi * i / _onsetSize);
      re[i] = (l[at + i] + r[at + i]) * 0.5 * w;
      im[i] = 0;
    }
    fft.run(re, im);
    var sum = 0.0;
    for (var k = 1; k < _onsetSize ~/ 2; k++) {
      var m = math.log(1 + 100 * math.sqrt(re[k] * re[k] + im[k] * im[k]));
      if (m > before[k]) sum += m - before[k];
      before[k] = m;
    }
    out[f] = sum;
  }
  return out;
}

/// onsets are where [l] and [r] are struck, in seconds: peaks of the
/// flux well over the flux round them.
List<double> onsets(Float32List l, Float32List r) {
  var flux = _flux(l, r);
  var out = <double>[];
  const around = 8;
  var lastAt = -1.0;
  for (var f = 1; f + 1 < flux.length; f++) {
    if (flux[f] <= flux[f - 1] || flux[f] < flux[f + 1]) continue;
    var sum = 0.0, count = 0;
    for (var g = math.max(0, f - around);
        g < math.min(flux.length, f + around + 1);
        g++) {
      sum += flux[g];
      count++;
    }
    var mean = sum / count;
    if (flux[f] < mean * 1.5 + 1) continue;
    // To the sample: where, in the frame, it first rises to a third of
    // its loudest -- a little before, so the hit's start is kept.
    var from = f * _onsetHop, to = math.min(l.length, from + _onsetSize);
    var peak = 0.0;
    for (var i = from; i < to; i++) {
      peak = math.max(peak, (l[i] + r[i]).abs() * 0.5);
    }
    var at = from;
    while (at < to && (l[at] + r[at]).abs() * 0.5 < peak / 3) {
      at++;
    }
    var t = math.max(0, at - 24) / _rate;
    if (t - lastAt < 0.05) continue;
    out.add(t);
    lastAt = t;
  }
  return out;
}

/// estimateTempo is the tempo [l] and [r] are played at, in beats a
/// minute: the beat its hits keep returning on, put in the octave nearest
/// [near] -- and, where the sound is a whole number of bars of
/// [beatsPerBar] at a tempo close to that, that tempo exactly, as a loop
/// cut to its bars is.
double estimateTempo(Float32List l, Float32List r,
    {double near = 120, int beatsPerBar = 4}) {
  var seconds = l.length / _rate;
  var flux = _flux(l, r);
  var fps = _rate / _onsetHop;
  double? found;
  if (flux.length > 16) {
    var mean = flux.reduce((a, b) => a + b) / flux.length;
    var x = [for (var v in flux) v - mean];
    double corr(int lag) {
      var s = 0.0;
      for (var i = 0; i + lag < x.length; i++) {
        s += x[i] * x[i + lag];
      }
      return s / math.max(1, x.length - lag);
    }

    var bestScore = double.negativeInfinity;
    for (var bpm = 60.0; bpm <= 200; bpm += 0.5) {
      var lag = (60 * fps / bpm).round();
      if (lag * 2 >= x.length) continue;
      var score = corr(lag) + 0.5 * corr(lag * 2);
      if (score > bestScore) {
        bestScore = score;
        found = bpm;
      }
    }
  }
  var tempo = found ?? near;
  // The octave nearest the song's.
  while (tempo < near / 1.41) {
    tempo *= 2;
  }
  while (tempo > near * 1.41) {
    tempo /= 2;
  }
  // A whole number of bars, at a tempo close by.
  for (var bars in const [1, 2, 4, 8, 16, 32, 64]) {
    var exact = bars * beatsPerBar * 60 / seconds;
    if ((exact - tempo).abs() / tempo < 0.04) return exact;
  }
  return (tempo * 100).roundToDouble() / 100;
}
