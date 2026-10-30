import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/midi_effects.dart'
    show scaleSteps;

// pitch.dart is a voice's pitch: heard (YIN), and moved (PSOLA) -- the
// Tuner reads the first, Auto-tune does both.
//
// YIN (de Cheveigné and Kawahara, 2002) finds the period a sound repeats
// at: for each lag, how unlike the sound is to itself that far on, made
// relative to the lags under it, and the first lag that falls under a
// threshold is the period. It is right for a voice or an instrument held on
// a note, and says so with how far under the threshold it went.
//
// TD-PSOLA moves a pitch without moving the voice's formants -- the shape
// of the mouth that makes an "ah" an "ah" -- so a voice moved up is not a
// chipmunk: two-period slices of the sound, each windowed, are laid down
// again closer together (higher) or further apart (lower), each still the
// shape it was.

/// PitchReading is what YIN heard: the pitch in Hz, and how sure -- nought
/// to one -- or no pitch at all, for noise or silence.
typedef PitchReading = ({double hz, double clarity});

/// detectPitch finds [x]'s pitch at [rate] samples a second, between
/// [minHz] and [maxHz]; null where nothing repeats clearly enough.
PitchReading? detectPitch(Float32List x,
    {double rate = 48000,
    double minHz = 60,
    double maxHz = 1200,
    double threshold = 0.15}) {
  var maxLag = math.min((rate / minHz).floor(), x.length ~/ 2);
  var minLag = math.max(2, (rate / maxHz).floor());
  if (maxLag <= minLag + 2) return null;
  var w = x.length - maxLag;
  // Too quiet to say.
  var energy = 0.0;
  for (var i = 0; i < w; i++) {
    energy += x[i] * x[i];
  }
  if (energy / w < 1e-7) return null;
  var d = Float64List(maxLag + 1);
  for (var tau = 1; tau <= maxLag; tau++) {
    var sum = 0.0;
    for (var i = 0; i < w; i++) {
      var diff = x[i] - x[i + tau];
      sum += diff * diff;
    }
    d[tau] = sum;
  }
  // The cumulative mean normalised difference.
  var cmnd = Float64List(maxLag + 1)..[0] = 1;
  var running = 0.0;
  for (var tau = 1; tau <= maxLag; tau++) {
    running += d[tau];
    cmnd[tau] = running == 0 ? 1 : d[tau] * tau / running;
  }
  var tau = -1;
  for (var t = minLag; t < maxLag; t++) {
    if (cmnd[t] < threshold) {
      // On to the bottom of the dip.
      while (t + 1 < maxLag && cmnd[t + 1] < cmnd[t]) {
        t++;
      }
      tau = t;
      break;
    }
  }
  if (tau < 0) return null;
  // Between samples: a parabola through the dip and its neighbours.
  var better = tau.toDouble();
  if (tau > 1 && tau < maxLag) {
    var a = cmnd[tau - 1], b = cmnd[tau], c = cmnd[tau + 1];
    var den = a + c - 2 * b;
    if (den.abs() > 1e-12) better = tau + 0.5 * (a - c) / den;
  }
  return (hz: rate / better, clarity: (1 - cmnd[tau]).clamp(0.0, 1.0));
}

/// midiOf is [hz] as a MIDI note, fractional: 69.0 is A440.
double midiOf(double hz) => 69 + 12 * math.log(hz / 440) / math.ln2;

/// snapNote is the note [midi] is pulled to: the nearest of [steps] above
/// [root], or of every semitone for an empty [steps].
double snapNote(double midi, int root, List<int> steps) {
  if (steps.isEmpty) return midi.roundToDouble();
  var best = midi.roundToDouble();
  var bestD = double.infinity;
  var octave = ((midi - root) / 12).floor();
  for (var o = octave - 1; o <= octave + 1; o++) {
    for (var s in steps) {
      var n = (root + 12 * o + s).toDouble();
      var d = (n - midi).abs();
      if (d < bestD) {
        bestD = d;
        best = n;
      }
    }
  }
  return best;
}

/// AutoTune pulls a voice to the nearest note of a key and scale: its pitch
/// heard as it goes, the correction eased in over the retune time -- at
/// nought, at once, the robotic sound -- and as much of it as the amount
/// says, made by PSOLA so the voice stays itself. It hears a little ahead
/// of what it plays, and lays its slices a little ahead of what it sends
/// on: [latency] samples late in all, always the same.
class AutoTune implements DeviceProcessor {
  static const int latency = 1024;

  /// _settle is how far behind what has been laid out it reads: half a
  /// slice at the lowest pitch heard, so every slice touching a sample is
  /// down before it goes.
  static const int _settle = 1024;
  static const int _size = 8192;
  static const int _window = 2048;

  final int _root;
  final List<int> _steps;
  final double _amount;
  final double _ease;

  final Float32List _inL = Float32List(_size), _inR = Float32List(_size);
  final Float32List _outL = Float32List(_size), _outR = Float32List(_size);
  final Float32List _scratch = Float32List(_window);

  /// _t is how many samples have gone in; _synth the next place a slice is
  /// laid down, in output time; _mark the last slice's place in the input.
  int _t = 0;
  double _synth = latency.toDouble();
  double _mark = 0;
  double _period = 240;
  double _ratio = 1, _target = 1;
  int _sinceHeard = 0;

  /// heard is the last pitch it heard, for a tuner beside it.
  PitchReading? heard;

  AutoTune(MixDevice d)
      : _root = d.value("key").round(),
        _steps = d.value("scale").round() == 0
            ? const []
            : scaleSteps[
                (d.value("scale").round() - 1).clamp(0, scaleSteps.length - 1)],
        _amount = d.value("amount"),
        // The retune time as a glide a sample: e to the minus one over it.
        _ease = d.value("retune") <= 0
            ? 0
            : math.exp(-1 / (d.value("retune") / 1000 * 48000));

  void _listen() {
    // The last window of what came in, both sides as one.
    for (var i = 0; i < _window; i++) {
      var k = (_t - _window + i) & (_size - 1);
      _scratch[i] = (_inL[k] + _inR[k]) * 0.5;
    }
    var p = detectPitch(_scratch);
    heard = p;
    if (p == null || p.clarity < 0.5) {
      _target = 1;
      return;
    }
    _period = 48000 / p.hz;
    var midi = midiOf(p.hz);
    var to = snapNote(midi, _root, _steps);
    _target = math.pow(2, (to - midi) * _amount / 12).toDouble();
  }

  @override
  void process(Float32List l, Float32List r, int n) {
    for (var i = 0; i < n; i++) {
      var k = _t & (_size - 1);
      _inL[k] = l[i];
      _inR[k] = r[i];
      _t++;
      if (++_sinceHeard >= 256 && _t > _window) {
        _sinceHeard = 0;
        _listen();
      }
      _ratio = _ease == 0 ? _target : _target + (_ratio - _target) * _ease;
      // Lay down every slice due by now: a slice of two periods, from the
      // input [latency] behind, at a spacing of the period over the ratio --
      // each turned down by the ratio, as that many more of them overlap.
      while (_synth <= _t) {
        var at = _synth - latency;
        // The input's own marks a period apart: the one nearest.
        while (_mark + _period < at) {
          _mark += _period;
        }
        if (_mark > at + _period) _mark = at;
        var span = _period.round();
        var centre = _mark.round();
        var out = _synth.round();
        var gain = 1 / _ratio;
        for (var j = -span; j < span; j++) {
          var w = (0.5 + 0.5 * math.cos(math.pi * j / span)) * gain;
          var src = (centre + j) & (_size - 1);
          var dst = (out + j) & (_size - 1);
          _outL[dst] += _inL[src] * w;
          _outR[dst] += _inR[src] * w;
        }
        _synth += _period / _ratio;
      }
      // What is due out now, taken and cleared for the next time round.
      var o = (_t - 1 - _settle) & (_size - 1);
      l[i] = _outL[o];
      r[i] = _outR[o];
      _outL[o] = 0;
      _outR[o] = 0;
    }
  }
}

/// PitchListener is a device that changes nothing and only listens -- a tuner,
/// a spectrum -- its pitch heard for the panel to read.
class PitchListener implements DeviceProcessor {
  final Float32List _buffer = Float32List(2048);
  int _at = 0, _since = 0;
  PitchReading? heard;
  final bool pitch;
  PitchListener({this.pitch = false});

  @override
  void process(Float32List l, Float32List r, int n) {
    if (!pitch) return;
    for (var i = 0; i < n; i++) {
      _buffer[_at] = (l[i] + r[i]) * 0.5;
      _at = (_at + 1) % _buffer.length;
    }
    _since += n;
    if (_since < 1024) return;
    _since = 0;
    var ordered = Float32List(_buffer.length);
    for (var i = 0; i < _buffer.length; i++) {
      ordered[i] = _buffer[(_at + i) % _buffer.length];
    }
    heard = detectPitch(ordered);
  }
}
