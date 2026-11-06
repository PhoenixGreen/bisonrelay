import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart'
    show DeviceKind, MixDevice;

// analysers.dart is what the Chain's analysers hear, where they are in the
// chain, changing nothing: the latest of the sound itself -- for the Scope
// (its wave over a few milliseconds) and the Stereo Image (left against
// right, and how alike they are) -- and its loudness as broadcast meters
// read it (BS.1770: momentary, short-term and integrated LUFS) with its
// true peak (between the samples, four times over).

/// Wave is the latest of a sound, left and right, oldest first: as many
/// points as are drawn, taken evenly from the stretch listened to.
typedef Wave = (Float32List, Float32List);

/// LoudnessReading is a loudness meter's reading, in LUFS -- the last 400ms,
/// the last three seconds, and everything since it began (gated) -- and the
/// highest true peak since, in dBTP. Minus infinity for silence.
typedef LoudnessReading = ({
  double momentary,
  double shortTerm,
  double integrated,
  double truePeak,
});

/// WaveTap keeps the last [frames] of what passes it, both sides, to be
/// read as a [Wave] of at most [points].
class WaveTap implements DeviceProcessor, Tunable {
  /// kind is the analyser it listens for: a Scope, or a Stereo Image.
  final DeviceKind kind;
  int frames;
  final int points;
  Float32List _l, _r;
  int _at = 0;

  WaveTap(this.kind, {required int frames, this.points = 1200})
      : frames = math.max(16, frames),
        _l = Float32List(math.max(16, frames)),
        _r = Float32List(math.max(16, frames));

  /// framesOf is how much a Scope's Time keeps, in frames.
  static int framesOf(MixDevice device) =>
      (device.value("time") / 1000 * mixRate).round();

  /// tune follows a Scope's Time, keeping a longer or shorter stretch; its
  /// Zoom is only how it is drawn.
  @override
  void tune(MixDevice device) {
    if (kind != DeviceKind.scope) return;
    var want = math.max(16, framesOf(device));
    if (want == frames) return;
    frames = want;
    _l = Float32List(want);
    _r = Float32List(want);
    _at = 0;
  }

  @override
  void process(Float32List l, Float32List r, int n) {
    for (var i = 0; i < n; i++) {
      _l[_at] = l[i];
      _r[_at] = r[i];
      _at = (_at + 1) % frames;
    }
  }

  /// wave is what it holds, oldest first, thinned evenly to [points].
  Wave get wave {
    var count = math.min(points, frames);
    var l = Float32List(count), r = Float32List(count);
    for (var i = 0; i < count; i++) {
      var k = (_at + (i * frames) ~/ count) % frames;
      l[i] = _l[k];
      r[i] = _r[k];
    }
    return (l, r);
  }
}

/// TruePeak is the highest level a sound reaches between its samples as
/// well as on them: each side resampled four times over by a windowed-sinc
/// interpolator, as BS.1770's Annex 2 has it.
class TruePeak {
  static const int _taps = 12;
  static final List<Float64List> _phases = _design();
  final List<Float64List> _history = [Float64List(_taps), Float64List(_taps)];
  int _at = 0;

  /// peak is the highest so far, as a level (one is full scale).
  double peak = 0;

  /// _design is the interpolator: four phases of twelve taps, a sinc
  /// windowed by a Kaiser-like cosine taper, each phase summing to one.
  static List<Float64List> _design() {
    const factor = 4, length = _taps * factor;
    var phases = [for (var p = 0; p < factor; p++) Float64List(_taps)];
    for (var k = 0; k < length; k++) {
      var t = (k - (length - 1) / 2) / factor;
      var sinc = t == 0 ? 1.0 : math.sin(math.pi * t) / (math.pi * t);
      var w = 0.5 - 0.5 * math.cos(2 * math.pi * (k + 0.5) / length);
      phases[k % factor][k ~/ factor] = sinc * w;
    }
    for (var p in phases) {
      var sum = p.fold(0.0, (a, x) => a + x);
      for (var i = 0; i < p.length; i++) {
        p[i] /= sum;
      }
    }
    return phases;
  }

  void add(Float32List l, Float32List r, int n) {
    for (var i = 0; i < n; i++) {
      _history[0][_at] = l[i];
      _history[1][_at] = r[i];
      _at = (_at + 1) % _taps;
      for (var side in _history) {
        for (var phase in _phases) {
          var y = 0.0;
          for (var t = 0; t < _taps; t++) {
            y += phase[t] * side[(_at + t) % _taps];
          }
          var a = y.abs();
          if (a > peak) peak = a;
        }
      }
    }
  }

  void reset() => peak = 0;
}

/// LoudnessTap measures what passes it: see [LoudnessReading].
class LoudnessTap implements DeviceProcessor, Tunable {
  /// tune changes nothing: its Target is only where the reading aims, and
  /// what it has measured is kept.
  @override
  void tune(MixDevice device) {}

  final LoudnessMeter _meter = LoudnessMeter();
  final TruePeak _peak = TruePeak();

  @override
  void process(Float32List l, Float32List r, int n) {
    _meter.add(l, r, n);
    _peak.add(l, r, n);
  }

  LoudnessReading get reading => (
        momentary: _meter.momentary,
        shortTerm: _meter.shortTerm,
        integrated: _meter.integrated,
        truePeak: _peak.peak <= 0
            ? -double.infinity
            : 20 * math.log(_peak.peak) / math.ln10,
      );

  /// reset starts it measuring again.
  void reset() {
    _meter.reset();
    _peak.reset();
  }
}

/// correlation is how alike [wave]'s two sides are: one the same, nought
/// unrelated, minus one opposite (heard as mono, they cancel).
double correlation(Wave wave) {
  var (l, r) = wave;
  var lr = 0.0, ll = 0.0, rr = 0.0;
  for (var i = 0; i < l.length; i++) {
    lr += l[i] * r[i];
    ll += l[i] * l[i];
    rr += r[i] * r[i];
  }
  // A side silent: nothing to compare.
  if (ll <= 1e-12 || rr <= 1e-12) return 0;
  return (lr / math.sqrt(ll * rr)).clamp(-1.0, 1.0);
}
