import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart' show dbToGain;

// device_dsp.dart is the devices a chain can hold beside the reverb and the
// delay: a gate, a swept filter, chorus, flanger, phaser, an auto-pan, three
// kinds of drive, a bit crusher and a utility. Each reads its settings as
// it is made, and again when they change -- tuned, as automation moves
// them -- keeping what it is in the middle of: a delay line, an LFO's
// phase, a filter's state.
//
// All at the mix rate, 48kHz, on a block of a channel's two sides.

const double _rate = 48000;

/// _Lfo is a low-frequency oscillator: a phase going round [hz] times a
/// second, read as a sine, a triangle or a square, -1 to 1.
class _Lfo {
  double step;
  double phase;
  _Lfo(double hz, [this.phase = 0]) : step = hz / _rate;

  set hz(double hz) => step = hz / _rate;

  double next([int shape = 0]) {
    var p = phase;
    phase += step;
    if (phase >= 1) phase -= 1;
    return switch (shape) {
      1 => 1 - 4 * (p - 0.5).abs(),
      2 => p < 0.5 ? 1 : -1,
      _ => math.sin(2 * math.pi * p),
    };
  }
}

/// Gate lets a sound through only while it is louder than the threshold:
/// open in the attack, held open the hold after it falls, closed over the
/// release -- down to the floor, not always to nothing.
class Gate implements DeviceProcessor, Tunable {
  late double _threshold, _attack, _release, _floor;
  late int _hold;
  double _env = 0, _gain = 0;
  int _held = 0;

  Gate(MixDevice d) {
    tune(d);
  }

  @override
  void tune(MixDevice d) {
    _threshold = dbToGain(d.value("threshold"));
    _attack = 1 / math.max(1, d.value("attack") / 1000 * _rate);
    _release = 1 / math.max(1, d.value("release") / 1000 * _rate);
    _hold = (d.value("hold") / 1000 * _rate).round();
    _floor = dbToGain(d.value("floor"));
  }

  @override
  void process(Float32List l, Float32List r, int n) {
    for (var i = 0; i < n; i++) {
      var x = math.max(l[i].abs(), r[i].abs());
      // A fast peak follower, falling over ten milliseconds.
      _env = x > _env ? x : _env * 0.9979;
      if (_env >= _threshold) {
        _held = _hold;
        _gain = math.min(1, _gain + _attack);
      } else if (_held > 0) {
        _held--;
      } else {
        _gain = math.max(0, _gain - _release);
      }
      var g = _floor + (1 - _floor) * _gain;
      l[i] *= g;
      r[i] *= g;
    }
  }
}

/// _Svf is a state-variable filter -- the trapezoidal kind, which stays
/// steady while its frequency is swept -- giving low-, high- and band-pass
/// at once.
class _Svf {
  double _ic1 = 0, _ic2 = 0;
  double _a1 = 0, _a2 = 0, _a3 = 0, _k = 1;

  void set(double hz, double q) {
    var g = math.tan(math.pi * hz.clamp(20.0, _rate * 0.45) / _rate);
    _k = 1 / q;
    _a1 = 1 / (1 + g * (g + _k));
    _a2 = g * _a1;
    _a3 = g * _a2;
  }

  /// run filters [x], returning (low, band, high).
  (double, double, double) run(double x) {
    var v3 = x - _ic2;
    var v1 = _a1 * _ic1 + _a2 * v3;
    var v2 = _ic2 + _a2 * _ic1 + _a3 * v3;
    _ic1 = 2 * v1 - _ic1;
    _ic2 = 2 * v2 - _ic2;
    return (v2, v1, x - _k * v1 - v2);
  }
}

/// AutoFilter is a filter whose frequency an LFO sweeps up and down, up to
/// four octaves either way.
class AutoFilter implements DeviceProcessor, Tunable {
  late int _type;
  late double _freq, _q, _amount, _mix;
  final _Lfo _lfo = _Lfo(1);
  final _Svf _l = _Svf(), _r = _Svf();

  AutoFilter(MixDevice d) {
    tune(d);
  }

  @override
  void tune(MixDevice d) {
    _type = d.value("type").round();
    _freq = d.value("freq");
    _q = 0.5 + d.value("res") * 9.5;
    _amount = d.value("amount");
    _mix = d.value("mix");
    _lfo.hz = d.value("rate");
  }

  @override
  void process(Float32List l, Float32List r, int n) {
    for (var i = 0; i < n; i++) {
      // Retuned every sixteen samples: often enough not to step.
      if (i % 16 == 0) {
        var sweep = _amount == 0 ? 0.0 : _amount * 4 * _lfo.next();
        var hz = _freq * math.pow(2, sweep);
        _l.set(hz.toDouble(), _q);
        _r.set(hz.toDouble(), _q);
      } else if (_amount != 0) {
        _lfo.next();
      }
      var (ll, lb, lh) = _l.run(l[i]);
      var (rl, rb, rh) = _r.run(r[i]);
      var wl = switch (_type) { 1 => lh, 2 => lb, _ => ll };
      var wr = switch (_type) { 1 => rh, 2 => rb, _ => rl };
      l[i] = l[i] * (1 - _mix) + wl * _mix;
      r[i] = r[i] * (1 - _mix) + wr * _mix;
    }
  }
}

/// _ModDelay is a delay line read at a moving point between samples: the
/// heart of a chorus and a flanger.
class _ModDelay {
  final Float32List _buffer;
  int _at = 0;
  _ModDelay(int size) : _buffer = Float32List(size);

  /// run writes [x], and reads back [delay] samples ago.
  double read(double delay) {
    var pos = _at - delay;
    while (pos < 0) {
      pos += _buffer.length;
    }
    var i = pos.floor(), f = pos - i;
    var a = _buffer[i % _buffer.length], b = _buffer[(i + 1) % _buffer.length];
    return a + (b - a) * f;
  }

  void write(double x) {
    _buffer[_at] = x;
    if (++_at >= _buffer.length) _at = 0;
  }
}

/// Chorus and Flanger are one sound mixed with a copy of itself delayed by
/// a moving amount: a few milliseconds and more for a chorus's thickening,
/// under a few with feedback for a flanger's sweep. The two sides' LFOs are
/// a quarter turn apart, for width.
abstract class _Modulated implements DeviceProcessor, Tunable {
  /// _longest is the longest a chorus's or a flanger's delay goes, in
  /// milliseconds: the lines are that long whatever they are set to, so a
  /// setting moved never has to start them again.
  static const double _longest = 40;

  late double _base, _swing, _feedback, _mix;
  final _Lfo _lfoL = _Lfo(1), _lfoR = _Lfo(1, 0.25);
  final _ModDelay _dl = _ModDelay((_longest / 1000 * _rate).ceil() + 4),
      _dr = _ModDelay((_longest / 1000 * _rate).ceil() + 4);
  double _fl = 0, _fr = 0;

  _Modulated(MixDevice d) {
    tune(d);
  }

  /// times are the delay and its swing, in milliseconds, from [d].
  (double, double) times(MixDevice d);

  @override
  void tune(MixDevice d) {
    var (baseMs, swingMs) = times(d);
    _base = baseMs / 1000 * _rate;
    _swing = swingMs / 1000 * _rate;
    _feedback = d.value("feedback");
    _mix = d.value("mix");
    _lfoL.hz = d.value("rate");
    _lfoR.hz = d.value("rate");
  }

  @override
  void process(Float32List l, Float32List r, int n) {
    for (var i = 0; i < n; i++) {
      var dl = _base + _swing * (0.5 + 0.5 * _lfoL.next());
      var dr = _base + _swing * (0.5 + 0.5 * _lfoR.next());
      var wl = _dl.read(math.max(1, dl)), wr = _dr.read(math.max(1, dr));
      _dl.write(l[i] + wl * _feedback);
      _dr.write(r[i] + wr * _feedback);
      _fl = wl;
      _fr = wr;
      l[i] = l[i] * (1 - _mix * 0.5) + _fl * _mix;
      r[i] = r[i] * (1 - _mix * 0.5) + _fr * _mix;
    }
  }
}

class Chorus extends _Modulated {
  Chorus(super.d);

  @override
  (double, double) times(MixDevice d) =>
      (d.value("delay"), d.value("depth") * 8);
}

class Flanger extends _Modulated {
  Flanger(super.d);

  @override
  (double, double) times(MixDevice d) =>
      (d.value("delay") * 0.2, d.value("delay") * d.value("depth"));
}

/// Phaser is a sound mixed with itself through a row of all-pass stages
/// whose turning point an LFO sweeps: notches that move up and down.
class Phaser implements DeviceProcessor, Tunable {
  late int _stages;
  late double _depth, _feedback, _mix;
  final _Lfo _lfoL = _Lfo(1), _lfoR = _Lfo(1, 0.25);
  final List<double> _xl = List.filled(12, 0),
      _yl = List.filled(12, 0),
      _xr = List.filled(12, 0),
      _yr = List.filled(12, 0);
  double _lastL = 0, _lastR = 0;

  Phaser(MixDevice d) {
    tune(d);
  }

  @override
  void tune(MixDevice d) {
    _stages = (d.value("stages").round() ~/ 2 * 2).clamp(2, 12);
    _depth = d.value("depth");
    _feedback = d.value("feedback");
    _mix = d.value("mix");
    _lfoL.hz = d.value("rate");
    _lfoR.hz = d.value("rate");
  }

  double _coef(double lfo) {
    // From 200Hz up to four octaves above, as far as the depth says.
    var hz = 200 * math.pow(2, _depth * 4 * (0.5 + 0.5 * lfo));
    var t = math.tan(math.pi * hz / _rate);
    return (1 - t) / (1 + t);
  }

  double _run(double x, double a, List<double> xs, List<double> ys) {
    var v = x;
    for (var s = 0; s < _stages; s++) {
      var y = -a * v + xs[s] + a * ys[s];
      xs[s] = v;
      ys[s] = y;
      v = y;
    }
    return v;
  }

  @override
  void process(Float32List l, Float32List r, int n) {
    for (var i = 0; i < n; i++) {
      var al = _coef(_lfoL.next()), ar = _coef(_lfoR.next());
      _lastL = _run(l[i] + _lastL * _feedback, al, _xl, _yl);
      _lastR = _run(r[i] + _lastR * _feedback, ar, _xr, _yr);
      l[i] = l[i] * (1 - _mix * 0.5) + _lastL * _mix * 0.5;
      r[i] = r[i] * (1 - _mix * 0.5) + _lastR * _mix * 0.5;
    }
  }
}

/// AutoPan moves a sound from side to side: each side turned down as the
/// LFO swings to the other, as far as the amount.
class AutoPan implements DeviceProcessor, Tunable {
  late double _amount;
  late int _shape;
  final _Lfo _lfo = _Lfo(1);
  AutoPan(MixDevice d) {
    tune(d);
  }

  @override
  void tune(MixDevice d) {
    _amount = d.value("amount");
    _shape = d.value("shape").round();
    _lfo.hz = d.value("rate");
  }

  @override
  void process(Float32List l, Float32List r, int n) {
    for (var i = 0; i < n; i++) {
      var p = _lfo.next(_shape) * _amount;
      l[i] *= p > 0 ? 1 - p : 1;
      r[i] *= p < 0 ? 1 + p : 1;
    }
  }
}

/// Saturator drives a sound into a curve: soft (a hyperbolic tangent),
/// warm (the same, a little lopsided, as valves are), or hard (clipped).
class Saturator implements DeviceProcessor, Tunable {
  late double _drive, _out, _mix;
  late int _type;
  Saturator(MixDevice d) {
    tune(d);
  }

  @override
  void tune(MixDevice d) {
    _drive = dbToGain(d.value("drive"));
    _out = dbToGain(d.value("output"));
    _mix = d.value("mix");
    _type = d.value("type").round();
  }

  double _shape(double x) {
    var v = x * _drive;
    var y = switch (_type) {
      1 => v >= 0 ? _tanh(v) : _tanh(v * 0.8) / 0.8 * 0.9,
      2 => v.clamp(-1.0, 1.0),
      _ => _tanh(v),
    };
    return y * _out;
  }

  @override
  void process(Float32List l, Float32List r, int n) {
    for (var i = 0; i < n; i++) {
      l[i] = l[i] * (1 - _mix) + _shape(l[i]) * _mix;
      r[i] = r[i] * (1 - _mix) + _shape(r[i]) * _mix;
    }
  }
}

double _tanh(double x) {
  if (x > 9) return 1;
  if (x < -9) return -1;
  var e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}

/// Overdrive is an amplifier pushed past its limit: a great deal of gain
/// into a rounded clip, then a tone control taking off the fizz.
class Overdrive implements DeviceProcessor, Tunable {
  late double _gain, _lp, _out, _mix;
  double _fl = 0, _fr = 0;
  Overdrive(MixDevice d) {
    tune(d);
  }

  @override
  void tune(MixDevice d) {
    _gain = 1 + d.value("drive") * 40;
    _lp = 1 - math.exp(-2 * math.pi * d.value("tone") / _rate);
    _out = dbToGain(d.value("output"));
    _mix = d.value("mix");
  }

  @override
  void process(Float32List l, Float32List r, int n) {
    for (var i = 0; i < n; i++) {
      var yl = 2 / math.pi * math.atan(l[i] * _gain);
      var yr = 2 / math.pi * math.atan(r[i] * _gain);
      _fl += _lp * (yl - _fl);
      _fr += _lp * (yr - _fr);
      l[i] = l[i] * (1 - _mix) + _fl * _out * _mix;
      r[i] = r[i] * (1 - _mix) + _fr * _out * _mix;
    }
  }
}

/// BitCrusher makes a sound cruder: fewer steps of loudness (bits), and
/// each sample held for several (downsample).
class BitCrusher implements DeviceProcessor, Tunable {
  late double _steps, _mix;
  late int _hold;
  int _held = 0;
  double _hl = 0, _hr = 0;
  BitCrusher(MixDevice d) {
    tune(d);
  }

  @override
  void tune(MixDevice d) {
    _steps = math.pow(2, d.value("bits").round() - 1).toDouble();
    _hold = d.value("down").round().clamp(1, 50);
    _mix = d.value("mix");
  }

  @override
  void process(Float32List l, Float32List r, int n) {
    for (var i = 0; i < n; i++) {
      if (_held <= 0) {
        _hl = (l[i] * _steps).roundToDouble() / _steps;
        _hr = (r[i] * _steps).roundToDouble() / _steps;
        _held = _hold;
      }
      _held--;
      l[i] = l[i] * (1 - _mix) + _hl * _mix;
      r[i] = r[i] * (1 - _mix) + _hr * _mix;
    }
  }
}

/// Utility is the plain things: a gain, the stereo width (nought mono, one
/// as it is, two twice as wide), mono outright, and either side turned
/// upside down.
class Utility implements DeviceProcessor, Tunable {
  late double _gain, _width;
  late bool _mono;
  late int _invert;
  Utility(MixDevice d) {
    tune(d);
  }

  @override
  void tune(MixDevice d) {
    _gain = dbToGain(d.value("gain"));
    _width = d.value("width");
    _mono = d.value("mono").round() == 1;
    _invert = d.value("invert").round();
  }

  @override
  void process(Float32List l, Float32List r, int n) {
    var sl = _invert == 1 || _invert == 3 ? -1.0 : 1.0;
    var sr = _invert == 2 || _invert == 3 ? -1.0 : 1.0;
    var width = _mono ? 0.0 : _width;
    for (var i = 0; i < n; i++) {
      var m = (l[i] + r[i]) / 2, s = (l[i] - r[i]) / 2 * width;
      l[i] = (m + s) * _gain * sl;
      r[i] = (m - s) * _gain * sr;
    }
  }
}
